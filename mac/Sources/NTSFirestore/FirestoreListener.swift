import Foundation
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
/// This is a thin wrapper over `FirestoreQueryListener`, which owns the gRPC
/// `Listen` stream, reconnect/backoff, and the ~1h token refresh. It pushes an
/// updated, newest-first list every time a track changes (sub-second, no polling).
/// Access is gated by a Firebase ID token (paid NTS Supporters).
public final class FirestoreListener {
    private let inner: FirestoreQueryListener<LiveTrack>

    /// - Parameter filter: which source's tracks to stream — see `LiveTracksFilter`.
    public init(filter: LiveTracksFilter,
                tokenProvider: @escaping @Sendable () async throws -> String,
                onUpdate: @escaping @MainActor @Sendable ([LiveTrack]) -> Void) {
        inner = FirestoreQueryListener(
            query: FirestoreQuery(collection: "live_tracks",
                                  filterField: filter.field, filterValue: filter.value,
                                  orderByField: "start_time", limit: 12, targetID: 12),
            decode: { Self.track(from: $0) },
            tokenProvider: tokenProvider,
            onUpdate: onUpdate
        )
    }

    public func start() { inner.start() }
    public func stop() { inner.stop() }

    private static func track(from doc: Google_Firestore_V1_Document) -> (sort: Date, value: LiveTrack)? {
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
        let date = timestamp.date
        return (date, LiveTrack(startTime: date, title: title, artists: artists))
    }
}
