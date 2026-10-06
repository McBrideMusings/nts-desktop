import Foundation
import SwiftProtobuf

/// Real-time listener for one Firestore query — the shared transport behind the
/// app's live-tracklist and mixtape-episode feeds.
///
/// Runs `query` over a `FirestoreListenStream`, decodes each document to an
/// `Element` (with a sort date), keeps the current document set, and pushes the
/// newest-first list on every change (sub-second, no polling). Access is gated by a
/// Firebase ID token (paid NTS Supporters) passed as a bearer token.
public final class FirestoreQueryListener<Element: Sendable> {
    private let stream: FirestoreListenStream

    public init(query: FirestoreQuery,
                decode: @escaping @Sendable (Google_Firestore_V1_Document) -> (sort: Date, value: Element)?,
                tokenProvider: @escaping @Sendable () async throws -> String,
                onUpdate: @escaping @MainActor @Sendable ([Element]) -> Void) {
        let store = Store()
        stream = FirestoreListenStream(
            queries: [query],
            tokenProvider: tokenProvider,
            onConnect: { await store.reset() },
            onMessage: { message in
                if let list = await Self.apply(message, to: store, decode: decode) {
                    await onUpdate(list)
                }
            }
        )
    }

    /// Apply one message to the document set, returning the list to emit, or
    /// `nil` for a message that changes nothing (a keepalive, a non-reset
    /// target change).
    private static func apply(
        _ message: Google_Firestore_V1_ListenResponse, to store: Store,
        decode: @Sendable (Google_Firestore_V1_Document) -> (sort: Date, value: Element)?
    ) async -> [Element]? {
        switch message.responseType {
        case .documentChange(let change):
            let doc = change.document
            return await store.upsert(doc.name, decode(doc))
        case .documentDelete(let del):
            return await store.remove(del.document)
        case .documentRemove(let rem):
            return await store.remove(rem.document)
        case .targetChange(let tc) where tc.targetChangeType == .reset:
            return await store.reset()
        default:
            return nil
        }
    }

    public func start() { stream.start() }
    public func stop() { stream.stop() }

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
        @discardableResult
        func reset() -> [Element] {
            docs.removeAll()
            return []
        }
        private func sorted() -> [Element] {
            docs.values.sorted { $0.sort > $1.sort }.map { $0.value }
        }
    }
}
