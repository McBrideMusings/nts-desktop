import AppKit
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

/// One Firestore `Listen` gRPC stream carrying one or more query targets — the
/// transport under both the single-source tracklist feed (`FirestoreQueryListener`)
/// and the all-sources recorder (`FirestoreTracksRecorder`).
///
/// Owns everything about keeping the stream alive: bearer-token auth, a
/// background task that reconnects with backoff on error, a forced reconnect
/// (with a fresh token) before the ~1h ID-token TTL, a reconnect on wake, and
/// stall detection. What the messages mean is the caller's: every
/// `ListenResponse` is handed to `onMessage` in order, and `onConnect` fires
/// before the first message of each new connection so the caller can drop state
/// that belonged to the last one.
public final class FirestoreListenStream {
    private static var projectID: String { "nts-ios-app" }
    private static var host: String { "firestore.googleapis.com" }
    /// Force a reconnect before the ~1h ID-token TTL so an expired token can't
    /// silently stall a long-open stream.
    private static var maxStreamAge: TimeInterval { 50 * 60 }
    /// A gRPC stream that dies silently (half-open TCP after sleep/App Nap)
    /// throws nothing, so liveness is inferred from Firestore's ~30s keepalive
    /// cadence instead: no message at all — not even a no-change `targetChange`
    /// — for this long means the connection is dead.
    private static var stallThreshold: TimeInterval { 90 }
    private var database: String { "projects/\(Self.projectID)/databases/(default)" }

    /// Thrown from `requestProducer` to force the stream down for a planned
    /// reconnect (token expiry or a detected stall) — distinct from a genuine
    /// transport failure. grpc-swift wraps whatever `requestProducer` throws
    /// into its own `RPCError` before it reaches `connectOnce()`'s caller, so
    /// `runLoop` can't tell a planned reconnect from a real error by catching
    /// this type; `reconnectReason` is the side channel that survives the
    /// wrap and lets it reset the backoff instead of penalizing it.
    private struct ForcedReconnect: Error {}
    private actor ReconnectReason {
        enum Reason { case none, expired, stalled }
        private var reason = Reason.none
        func set(_ r: Reason) { reason = r }
        func consume() -> Reason {
            defer { reason = .none }
            return reason
        }
    }
    private let reconnectReason = ReconnectReason()

    /// When the connection last said anything.
    private actor Liveness {
        private var lastMessageAt = Date()
        func reset() { lastMessageAt = Date() }
        func touch() { lastMessageAt = Date() }
        func timeSinceLastMessage() -> TimeInterval { Date().timeIntervalSince(lastMessageAt) }
    }

    private let queries: [FirestoreQuery]
    private let tokenProvider: @Sendable () async throws -> String
    private let onConnect: @Sendable () async -> Void
    private let onMessage: @Sendable (Google_Firestore_V1_ListenResponse) async -> Void
    private let onLifecycle: (@Sendable (String) -> Void)?
    private var task: Task<Void, Never>?
    /// The in-flight `connectOnce()` attempt, so `forceReconnect()` can cancel
    /// just that attempt without stopping the listener for good.
    private var currentConnection: Task<Void, Error>?
    private var wakeObserver: NSObjectProtocol?

    /// - Parameter onLifecycle: a one-line description of each connect, planned
    ///   reconnect and failure, for a caller that keeps a log. Never carries the token.
    public init(queries: [FirestoreQuery],
                tokenProvider: @escaping @Sendable () async throws -> String,
                onConnect: @escaping @Sendable () async -> Void,
                onMessage: @escaping @Sendable (Google_Firestore_V1_ListenResponse) async -> Void,
                onLifecycle: (@Sendable (String) -> Void)? = nil) {
        self.queries = queries
        self.tokenProvider = tokenProvider
        self.onConnect = onConnect
        self.onMessage = onMessage
        self.onLifecycle = onLifecycle
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.runLoop() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.forceReconnect() }
    }

    public func stop() {
        task?.cancel()
        task = nil
        currentConnection?.cancel()
        currentConnection = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    deinit {
        task?.cancel()
        currentConnection?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    /// Tear down the in-flight connection so `runLoop` rebuilds it — used on
    /// wake, where a half-open stream from before sleep would otherwise sit
    /// silent until `stallThreshold` catches it.
    private func forceReconnect() {
        onLifecycle?("reconnecting after wake")
        currentConnection?.cancel()
    }

    // MARK: - Connection lifecycle

    private func runLoop() async {
        var attempt = 0
        while !Task.isCancelled {
            let connection = Task { try await self.connectOnce() }
            currentConnection = connection
            do {
                try await connection.value
                attempt = 0
            } catch is CancellationError {
                // Either the listener was stopped for good (outer task
                // cancelled) or `forceReconnect()` cancelled just this
                // attempt — the latter reconnects rather than stopping.
                if Task.isCancelled { return }
                attempt = 0
                continue
            } catch {
                switch await reconnectReason.consume() {
                case .expired:
                    // A planned reconnect (token TTL or a detected stall), not
                    // a real failure — don't penalize it with backoff.
                    onLifecycle?("reconnecting: token lifetime reached")
                    attempt = 0
                    continue
                case .stalled:
                    onLifecycle?("reconnecting: no message for \(Int(Self.stallThreshold))s")
                    attempt = 0
                    continue
                case .none:
                    attempt += 1
                    onLifecycle?("stream failed (attempt \(attempt)): \(error)")
                }
            }
            currentConnection = nil
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

        let liveness = Liveness()
        let requests = makeListenRequests()
        let onMessage = self.onMessage
        let onConnect = self.onConnect
        let onLifecycle = self.onLifecycle
        let reconnectReason = self.reconnectReason
        let targetCount = queries.count

        await onConnect()
        onLifecycle?("connecting with \(targetCount) target\(targetCount == 1 ? "" : "s")")

        try await withGRPCClient(transport: transport) { client in
            let firestore = Google_Firestore_V1_Firestore.Client(wrapping: client)
            try await firestore.listen(
                metadata: metadata,
                requestProducer: { writer in
                    for request in requests { try await writer.write(request) }
                    // Hold the send side open so the server keeps streaming, but cap
                    // the lifetime: the bearer token is sent only at open and expires
                    // (~1h), so tear down and reconnect with a fresh one before then.
                    // The same poll also catches a silently dead connection: Firestore
                    // sends a `targetChange` keepalive roughly every 30s, so no message
                    // at all for `stallThreshold` means the stream died without an error.
                    let deadline = Date().addingTimeInterval(Self.maxStreamAge)
                    while !Task.isCancelled {
                        try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                        if Date() >= deadline {
                            await reconnectReason.set(.expired)
                            throw ForcedReconnect()
                        }
                        if await liveness.timeSinceLastMessage() >= Self.stallThreshold {
                            await reconnectReason.set(.stalled)
                            throw ForcedReconnect()
                        }
                    }
                },
                onResponse: { response in
                    var first = true
                    for try await message in response.messages {
                        await liveness.touch()
                        if first {
                            first = false
                            onLifecycle?("connected")
                        }
                        await onMessage(message)
                    }
                }
            )
        }
    }

    // MARK: - Request

    private func makeListenRequests() -> [Google_Firestore_V1_ListenRequest] {
        queries.map { query in
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
    }
}
