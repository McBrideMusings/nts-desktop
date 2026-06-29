import Foundation
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
/// A thin wrapper over `FirestoreQueryListener` watching the `mixtape_titles`
/// collection filtered by `mixtape_alias == <alias>`, newest-first, limit 1 — so
/// it pushes the current episode every time the mixtape rolls onto a new one.
/// Access is gated by the same Firebase ID token as `live_tracks` (NTS Supporters).
public final class MixtapeTitleListener {
    private let inner: FirestoreQueryListener<MixtapeTitle>

    /// - Parameter mixtapeAlias: the mixtape whose current episode to stream.
    public init(mixtapeAlias: String,
                tokenProvider: @escaping @Sendable () async throws -> String,
                onUpdate: @escaping @MainActor @Sendable (MixtapeTitle?) -> Void) {
        inner = FirestoreQueryListener(
            query: FirestoreQuery(collection: "mixtape_titles",
                                  filterField: "mixtape_alias", filterValue: mixtapeAlias,
                                  orderByField: "started_at", limit: 1, targetID: 13),
            decode: { Self.title(from: $0) },
            tokenProvider: tokenProvider,
            onUpdate: { onUpdate($0.first) }   // limit 1 → the newest, or nil
        )
    }

    public func start() { inner.start() }
    public func stop() { inner.stop() }

    private static func title(from doc: Google_Firestore_V1_Document) -> (sort: Date, value: MixtapeTitle)? {
        let fields = doc.fields
        let title = fields["title"]?.stringValue ?? ""
        guard !title.isEmpty, let startedAt = fields["started_at"]?.timestampValue else { return nil }
        let date = startedAt.date
        return (date, MixtapeTitle(
            title: title,
            showAlias: fields["show_alias"]?.stringValue ?? "",
            episodeAlias: fields["episode_alias"]?.stringValue ?? "",
            startedAt: date
        ))
    }
}
