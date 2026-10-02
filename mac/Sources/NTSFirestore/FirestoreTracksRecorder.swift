import Foundation
import SwiftProtobuf

/// One document change in NTS's `live_tracks` collection, as Firestore delivered it.
public struct TrackChange: Sendable {
    public enum Kind: String, Sendable {
        /// First time this connection sees the document.
        case added
        /// The document changed after it was already known.
        case modified
        /// The document left the watched window — a newer track pushed it out of
        /// the newest-12 — but still exists.
        case removed
        /// NTS deleted the document.
        case deleted
    }

    /// Which source the document belongs to: `channel-1`, `channel-2` or `mixtape:<alias>`.
    public let source: String
    public let kind: Kind
    /// Part of the opening snapshot Firestore sends for a target (the newest
    /// 12), not a track that just aired.
    public let initial: Bool
    public let documentID: String
    /// `start_time` as Firestore stored it.
    public let startTime: Date?
    public let title: String?
    /// The `artist_names` array exactly as stored — one entry per array element,
    /// before anything joins them for display.
    public let artists: [String]?
    /// Firestore's own write times for the document.
    public let createTime: Date?
    public let updateTime: Date?
    /// Names of the document's other fields, so a field NTS adds shows up in the log.
    public let otherFields: [String]
    public let receivedAt: Date
}

/// Records every `live_tracks` change for a set of sources over one `Listen`
/// stream — one target per source on a single connection, rather than one
/// connection per source.
///
/// The all-sources query (no filter) was not used: Firestore security rules
/// accept the per-source equality queries the app already makes, and a source
/// listed here gets its newest 12 documents whatever the others are doing.
public final class FirestoreTracksRecorder {
    private let stream: FirestoreListenStream

    /// - Parameter sources: what to watch; each `label` is what a `TrackChange`
    ///   reports as its `source`.
    public init(sources: [(label: String, filter: LiveTracksFilter)],
                tokenProvider: @escaping @Sendable () async throws -> String,
                onChange: @escaping @Sendable (TrackChange) -> Void,
                onLifecycle: @escaping @Sendable (String) -> Void) {
        var labels: [Int32: String] = [:]
        let queries = sources.enumerated().map { index, source -> FirestoreQuery in
            let id = Int32(index + 1)
            labels[id] = source.label
            return FirestoreQuery(collection: "live_tracks",
                                  filterField: source.filter.field, filterValue: source.filter.value,
                                  orderByField: "start_time", limit: 12, targetID: id)
        }
        let state = State(labels: labels)
        stream = FirestoreListenStream(
            queries: queries,
            tokenProvider: tokenProvider,
            onConnect: { await state.connected() },
            onMessage: { message in
                let now = Date()
                switch message.responseType {
                case .documentChange(let change):
                    if let event = await state.change(change, receivedAt: now) { onChange(event) }
                case .documentDelete(let del):
                    onChange(await state.gone(del.document, targets: del.removedTargetIds,
                                              kind: .deleted, receivedAt: now))
                case .documentRemove(let rem):
                    onChange(await state.gone(rem.document, targets: rem.removedTargetIds,
                                              kind: .removed, receivedAt: now))
                case .targetChange(let tc) where tc.targetChangeType == .current:
                    await state.markCurrent(tc.targetIds)
                case .targetChange(let tc) where tc.targetChangeType == .reset:
                    // The server is about to resend the whole window.
                    await state.reset()
                default:
                    break
                }
            },
            onLifecycle: onLifecycle
        )
    }

    public func start() { stream.start() }
    public func stop() { stream.stop() }

    private actor State {
        private let labels: [Int32: String]
        /// Document name → the `update_time` last logged for it. Kept across
        /// reconnects: Firestore replays every document in a target's window when
        /// a stream reopens, and re-logging an unchanged one every 50 minutes
        /// would bury the real changes.
        private var known: [String: Date?] = [:]
        private var summaries: [String: (title: String?, artists: [String]?, start: Date?)] = [:]
        private var current: Set<Int32> = []

        init(labels: [Int32: String]) { self.labels = labels }

        func connected() { current = [] }
        func reset() {
            current = []
            known = [:]
            summaries = [:]
        }
        func markCurrent(_ ids: [Int32]) { current.formUnion(ids) }

        func change(_ change: Google_Firestore_V1_DocumentChange, receivedAt: Date) -> TrackChange? {
            let doc = change.document
            let updated = doc.hasUpdateTime ? doc.updateTime.date : nil
            let wasKnown = known[doc.name] != nil
            if wasKnown, known[doc.name]! == updated, updated != nil { return nil }
            known[doc.name] = .some(updated)

            let fields = doc.fields
            let title = fields["song_title"]?.stringValue
            let artists = fields["artist_names"]?.arrayValue.values.map { $0.stringValue }
            var start: Date?
            if case .timestampValue(let t)? = fields["start_time"]?.valueType { start = t.date }
            summaries[doc.name] = (title, artists, start)
            let other = fields.keys.filter { !["song_title", "artist_names", "start_time"].contains($0) }.sorted()

            let ids = change.targetIds
            let source = ids.compactMap { labels[$0] }.sorted().joined(separator: ",")
            return TrackChange(
                source: source.isEmpty ? "unknown" : source,
                kind: wasKnown ? .modified : .added,
                initial: !ids.contains { current.contains($0) },
                documentID: Self.id(of: doc.name),
                startTime: start, title: title, artists: artists,
                createTime: doc.hasCreateTime ? doc.createTime.date : nil,
                updateTime: updated, otherFields: other, receivedAt: receivedAt)
        }

        func gone(_ name: String, targets: [Int32], kind: TrackChange.Kind, receivedAt: Date) -> TrackChange {
            let summary = summaries[name]
            known[name] = nil
            summaries[name] = nil
            let source = targets.compactMap { labels[$0] }.sorted().joined(separator: ",")
            return TrackChange(
                source: source.isEmpty ? "unknown" : source, kind: kind, initial: false,
                documentID: Self.id(of: name),
                startTime: summary?.start, title: summary?.title, artists: summary?.artists,
                createTime: nil, updateTime: nil, otherFields: [], receivedAt: receivedAt)
        }

        private static func id(of name: String) -> String {
            name.split(separator: "/").last.map(String.init) ?? name
        }
    }
}
