import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import SwiftProtobuf

/// One track as stored in NTS's Firestore `live_tracks` collection.
public struct LiveTrack: Equatable, Sendable {
    public let startTime: Date
    public let title: String
    public let artists: [String]
}

/// Real-time listener for a live tracklist.
///
/// NTS publishes the currently-playing track to a Firestore collection
/// `live_tracks`. Each source is selected by one equality filter:
/// `stream_id == <mixtape alias>` for an infinite mixtape, or
/// `stream_pathname == "/stream"` / `"/stream2"` for live channels 1 / 2.
/// This opens the Firestore `Listen` gRPC stream and pushes an updated, newest-
/// first list every time a track changes (sub-second, no polling). Access is
/// gated by a Firebase ID token (paid NTS Supporters) passed as a bearer token;
/// App Check is not enforced.
///
/// The listener owns a background task that reconnects with backoff on error
/// (including token expiry — `tokenProvider` is re-invoked on every connect).
public final class FirestoreListener {
    private static let projectID = "nts-ios-app"
    private static let host = "firestore.googleapis.com"
    /// Force a reconnect (with a fresh token) before the ~1h ID-token TTL, so an
    /// expired token can't silently stall a long-open stream.
    private static let maxStreamAge: TimeInterval = 50 * 60
    private var database: String { "projects/\(Self.projectID)/databases/(default)" }

    /// Thrown when the stream hits `maxStreamAge` — a planned reconnect, distinct
    /// from cancellation (which stops the listener for good).
    private struct StreamExpired: Error {}

    private let filterField: String
    private let filterValue: String
    private let tokenProvider: @Sendable () async throws -> String
    private let onUpdate: @MainActor @Sendable ([LiveTrack]) -> Void
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - filterField: the `live_tracks` field to match on — `"stream_id"` for
    ///     a mixtape, `"stream_pathname"` for a live channel.
    ///   - filterValue: the value that field must equal (mixtape alias, or
    ///     `"/stream"` / `"/stream2"`).
    public init(filterField: String,
                filterValue: String,
                tokenProvider: @escaping @Sendable () async throws -> String,
                onUpdate: @escaping @MainActor @Sendable ([LiveTrack]) -> Void) {
        self.filterField = filterField
        self.filterValue = filterValue
        self.tokenProvider = tokenProvider
        self.onUpdate = onUpdate
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.runLoop() }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }

    // MARK: - Connection lifecycle

    private func runLoop() async {
        var attempt = 0
        while !Task.isCancelled {
            do {
                try await connectOnce()
                attempt = 0                      // clean end (rare); retry promptly
            } catch is CancellationError {
                return
            } catch is StreamExpired {
                attempt = 0
                continue                         // planned token refresh: reconnect now
            } catch {
                attempt += 1
            }
            if Task.isCancelled { return }
            // Backoff: 1s, 2s, 4s … capped at 30s.
            let delay = min(30.0, pow(2.0, Double(min(attempt, 5))))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func connectOnce() async throws {
        let token = try await tokenProvider()
        let transport = try HTTP2ClientTransport.Posix(
            target: .dns(host: Self.host, port: 443),
            transportSecurity: .tls
        )

        var metadata = Metadata()
        metadata.addString("Bearer \(token)", forKey: "authorization")
        metadata.addString(database, forKey: "google-cloud-resource-prefix")

        let store = Store()
        let request = makeListenRequest()
        let emit = onUpdate

        try await withGRPCClient(transport: transport) { client in
            let firestore = Google_Firestore_V1_Firestore.Client(wrapping: client)
            try await firestore.listen(
                metadata: metadata,
                requestProducer: { writer in
                    try await writer.write(request)
                    // Hold the send side open so the server keeps streaming, but
                    // cap the lifetime: the bearer token is sent only at open and
                    // expires (~1h), so tear down and reconnect with a fresh one
                    // before then. Sleep throws on cancellation.
                    let deadline = Date().addingTimeInterval(Self.maxStreamAge)
                    while !Task.isCancelled {
                        try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                        if Date() >= deadline { throw StreamExpired() }
                    }
                },
                onResponse: { response in
                    for try await message in response.messages {
                        switch message.responseType {
                        case .documentChange(let change):
                            let doc = change.document
                            let list = await store.upsert(doc.name, Self.track(from: doc))
                            await emit(list)
                        case .documentDelete(let del):
                            let list = await store.remove(del.document)
                            await emit(list)
                        case .documentRemove(let rem):
                            let list = await store.remove(rem.document)
                            await emit(list)
                        case .targetChange(let tc) where tc.targetChangeType == .reset:
                            let list = await store.reset()
                            await emit(list)
                        default:
                            break
                        }
                    }
                }
            )
        }
    }

    // MARK: - Request + mapping

    private func makeListenRequest() -> Google_Firestore_V1_ListenRequest {
        var fieldFilter = Google_Firestore_V1_StructuredQuery.FieldFilter()
        fieldFilter.field = .with { $0.fieldPath = filterField }
        fieldFilter.op = .equal
        fieldFilter.value = .with { $0.stringValue = filterValue }

        var filter = Google_Firestore_V1_StructuredQuery.Filter()
        filter.fieldFilter = fieldFilter

        var query = Google_Firestore_V1_StructuredQuery()
        query.from = [.with { $0.collectionID = "live_tracks" }]
        query.where = filter
        query.orderBy = [
            .with { $0.field = .with { $0.fieldPath = "start_time" }; $0.direction = .descending },
            .with { $0.field = .with { $0.fieldPath = "__name__" }; $0.direction = .descending },
        ]
        query.limit = .with { $0.value = 12 }

        var queryTarget = Google_Firestore_V1_Target.QueryTarget()
        queryTarget.parent = "\(database)/documents"
        queryTarget.structuredQuery = query

        var target = Google_Firestore_V1_Target()
        target.query = queryTarget
        target.targetID = 12

        var request = Google_Firestore_V1_ListenRequest()
        request.database = database
        request.addTarget = target
        return request
    }

    private static func track(from doc: Google_Firestore_V1_Document) -> LiveTrack? {
        let fields = doc.fields
        let title = fields["song_title"]?.stringValue ?? ""
        let artists = fields["artist_names"]?.arrayValue.values.compactMap { v -> String? in
            let s = v.stringValue
            return s.isEmpty ? nil : s
        } ?? []
        // The newest doc can briefly have an empty title while the track is being
        // identified; keep it (the UI decides how to render), but drop docs with
        // no timestamp since they can't be ordered.
        guard let timestamp = fields["start_time"]?.timestampValue else { return nil }
        return LiveTrack(startTime: timestamp.date, title: title, artists: artists)
    }

    /// Holds the current document set for one connection, newest-first on read.
    private actor Store {
        private var docs: [String: LiveTrack] = [:]

        func upsert(_ name: String, _ track: LiveTrack?) -> [LiveTrack] {
            docs[name] = track
            return sorted()
        }
        func remove(_ name: String) -> [LiveTrack] {
            docs[name] = nil
            return sorted()
        }
        func reset() -> [LiveTrack] {
            docs.removeAll()
            return []
        }
        private func sorted() -> [LiveTrack] {
            docs.values.sorted { $0.startTime > $1.startTime }
        }
    }
}
