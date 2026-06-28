import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import SwiftProtobuf

/// The source episode an infinite mixtape is currently playing from, as stored
/// in NTS's Firestore `mixtape_titles` collection. NTS assembles each mixtape
/// from past show episodes; this is the episode the current audio came from —
/// the "Playing …" line NTS shows on its own site. `title` is already formatted
/// for display (e.g. "Popstar Benny, 13 Aug 2024"); `showAlias`/`episodeAlias`
/// build the nts.live episode link.
public struct MixtapeTitle: Equatable, Sendable {
    public let title: String
    public let showAlias: String
    public let episodeAlias: String
    public let startedAt: Date
}

/// Real-time listener for one mixtape's current source episode.
///
/// Mirrors `FirestoreListener` (same project, auth, reconnect/backoff and ~1h
/// token-refresh lifecycle) but watches the `mixtape_titles` collection filtered
/// by `mixtape_alias == <alias>`, newest-first, limit 1 — so it pushes the
/// current episode every time the mixtape rolls onto a new one. Access is gated
/// by the same Firebase ID token as `live_tracks` (paid NTS Supporters).
public final class MixtapeTitleListener {
    private static let projectID = "nts-ios-app"
    private static let host = "firestore.googleapis.com"
    private static let maxStreamAge: TimeInterval = 50 * 60
    private var database: String { "projects/\(Self.projectID)/databases/(default)" }

    private struct StreamExpired: Error {}

    private let mixtapeAlias: String
    private let tokenProvider: @Sendable () async throws -> String
    private let onUpdate: @MainActor @Sendable (MixtapeTitle?) -> Void
    private var task: Task<Void, Never>?

    /// - Parameter mixtapeAlias: the mixtape whose current episode to stream.
    public init(mixtapeAlias: String,
                tokenProvider: @escaping @Sendable () async throws -> String,
                onUpdate: @escaping @MainActor @Sendable (MixtapeTitle?) -> Void) {
        self.mixtapeAlias = mixtapeAlias
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
                attempt = 0
            } catch is CancellationError {
                return
            } catch is StreamExpired {
                attempt = 0
                continue
            } catch {
                attempt += 1
            }
            if Task.isCancelled { return }
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
                            let latest = await store.upsert(doc.name, Self.title(from: doc))
                            await emit(latest)
                        case .documentDelete(let del):
                            let latest = await store.remove(del.document)
                            await emit(latest)
                        case .documentRemove(let rem):
                            let latest = await store.remove(rem.document)
                            await emit(latest)
                        case .targetChange(let tc) where tc.targetChangeType == .reset:
                            let latest = await store.reset()
                            await emit(latest)
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
        fieldFilter.field = .with { $0.fieldPath = "mixtape_alias" }
        fieldFilter.op = .equal
        fieldFilter.value = .with { $0.stringValue = self.mixtapeAlias }

        var filter = Google_Firestore_V1_StructuredQuery.Filter()
        filter.fieldFilter = fieldFilter

        var query = Google_Firestore_V1_StructuredQuery()
        query.from = [.with { $0.collectionID = "mixtape_titles" }]
        query.where = filter
        query.orderBy = [
            .with { $0.field = .with { $0.fieldPath = "started_at" }; $0.direction = .descending },
            .with { $0.field = .with { $0.fieldPath = "__name__" }; $0.direction = .descending },
        ]
        query.limit = .with { $0.value = 1 }

        var queryTarget = Google_Firestore_V1_Target.QueryTarget()
        queryTarget.parent = "\(database)/documents"
        queryTarget.structuredQuery = query

        var target = Google_Firestore_V1_Target()
        target.query = queryTarget
        target.targetID = 13

        var request = Google_Firestore_V1_ListenRequest()
        request.database = database
        request.addTarget = target
        return request
    }

    private static func title(from doc: Google_Firestore_V1_Document) -> MixtapeTitle? {
        let fields = doc.fields
        let title = fields["title"]?.stringValue ?? ""
        guard !title.isEmpty, let startedAt = fields["started_at"]?.timestampValue else { return nil }
        return MixtapeTitle(
            title: title,
            showAlias: fields["show_alias"]?.stringValue ?? "",
            episodeAlias: fields["episode_alias"]?.stringValue ?? "",
            startedAt: startedAt.date
        )
    }

    /// Holds the current document set for one connection; reads back the newest.
    private actor Store {
        private var docs: [String: MixtapeTitle] = [:]

        func upsert(_ name: String, _ title: MixtapeTitle?) -> MixtapeTitle? {
            docs[name] = title
            return latest()
        }
        func remove(_ name: String) -> MixtapeTitle? {
            docs[name] = nil
            return latest()
        }
        func reset() -> MixtapeTitle? {
            docs.removeAll()
            return nil
        }
        private func latest() -> MixtapeTitle? {
            docs.values.max { $0.startedAt < $1.startedAt }
        }
    }
}
