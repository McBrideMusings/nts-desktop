import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import SwiftProtobuf

/// One equality-filtered query against a Firestore collection, watched newest-first.
public struct FirestoreQuery: Sendable {
    public let collection: String
    public let filterField: String
    public let filterValue: String
    public let orderByField: String
    public let limit: Int32
    public let targetID: Int32

    public init(collection: String, filterField: String, filterValue: String,
                orderByField: String, limit: Int32, targetID: Int32) {
        self.collection = collection
        self.filterField = filterField
        self.filterValue = filterValue
        self.orderByField = orderByField
        self.limit = limit
        self.targetID = targetID
    }
}

/// Real-time listener for one Firestore query — the shared transport behind the
/// app's live-tracklist and mixtape-episode feeds.
///
/// Opens the Firestore `Listen` gRPC stream for `query`, decodes each document to
/// an `Element` (with a sort date), keeps the current document set, and pushes the
/// newest-first list on every change (sub-second, no polling). Access is gated by a
/// Firebase ID token (paid NTS Supporters) passed as a bearer token. Owns a
/// background task that reconnects with backoff on error and forces a reconnect
/// (with a fresh token) before the ~1h ID-token TTL.
public final class FirestoreQueryListener<Element: Sendable> {
    private static var projectID: String { "nts-ios-app" }
    private static var host: String { "firestore.googleapis.com" }
    /// Force a reconnect before the ~1h ID-token TTL so an expired token can't
    /// silently stall a long-open stream.
    private static var maxStreamAge: TimeInterval { 50 * 60 }
    private var database: String { "projects/\(Self.projectID)/databases/(default)" }

    /// Thrown when the stream hits `maxStreamAge` — a planned reconnect, distinct
    /// from cancellation (which stops the listener for good).
    private struct StreamExpired: Error {}

    private let query: FirestoreQuery
    private let decode: @Sendable (Google_Firestore_V1_Document) -> (sort: Date, value: Element)?
    private let tokenProvider: @Sendable () async throws -> String
    private let onUpdate: @MainActor @Sendable ([Element]) -> Void
    private var task: Task<Void, Never>?

    public init(query: FirestoreQuery,
                decode: @escaping @Sendable (Google_Firestore_V1_Document) -> (sort: Date, value: Element)?,
                tokenProvider: @escaping @Sendable () async throws -> String,
                onUpdate: @escaping @MainActor @Sendable ([Element]) -> Void) {
        self.query = query
        self.decode = decode
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
        let decode = self.decode

        try await withGRPCClient(transport: transport) { client in
            let firestore = Google_Firestore_V1_Firestore.Client(wrapping: client)
            try await firestore.listen(
                metadata: metadata,
                requestProducer: { writer in
                    try await writer.write(request)
                    // Hold the send side open so the server keeps streaming, but cap
                    // the lifetime: the bearer token is sent only at open and expires
                    // (~1h), so tear down and reconnect with a fresh one before then.
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
                            let list = await store.upsert(doc.name, decode(doc))
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

    // MARK: - Request

    private func makeListenRequest() -> Google_Firestore_V1_ListenRequest {
        var fieldFilter = Google_Firestore_V1_StructuredQuery.FieldFilter()
        fieldFilter.field = .with { $0.fieldPath = query.filterField }
        fieldFilter.op = .equal
        fieldFilter.value = .with { $0.stringValue = query.filterValue }

        var filter = Google_Firestore_V1_StructuredQuery.Filter()
        filter.fieldFilter = fieldFilter

        var structured = Google_Firestore_V1_StructuredQuery()
        structured.from = [.with { $0.collectionID = query.collection }]
        structured.where = filter
        structured.orderBy = [
            .with { $0.field = .with { $0.fieldPath = query.orderByField }; $0.direction = .descending },
            .with { $0.field = .with { $0.fieldPath = "__name__" }; $0.direction = .descending },
        ]
        structured.limit = .with { $0.value = query.limit }

        var queryTarget = Google_Firestore_V1_Target.QueryTarget()
        queryTarget.parent = "\(database)/documents"
        queryTarget.structuredQuery = structured

        var target = Google_Firestore_V1_Target()
        target.query = queryTarget
        target.targetID = query.targetID

        var request = Google_Firestore_V1_ListenRequest()
        request.database = database
        request.addTarget = target
        return request
    }

    /// Holds the current document set for one connection, newest-first on read.
    private actor Store {
        private var docs: [String: (sort: Date, value: Element)] = [:]

        func upsert(_ name: String, _ entry: (sort: Date, value: Element)?) -> [Element] {
            docs[name] = entry
            return sorted()
        }
        func remove(_ name: String) -> [Element] {
            docs[name] = nil
            return sorted()
        }
        func reset() -> [Element] {
            docs.removeAll()
            return []
        }
        private func sorted() -> [Element] {
            docs.values.sorted { $0.sort > $1.sort }.map { $0.value }
        }
    }
}
