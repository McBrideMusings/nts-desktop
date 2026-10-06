import Foundation

/// What a show's page in the catalog shows beyond the index: its full page from
/// `/api/v2/shows/<alias>` and its episode list, fetched when the page opens.
/// Which page is open is `AppModel.detail`; this only holds what was fetched
/// for it.
@MainActor
final class ShowDetailLoader: ObservableObject {
    /// Fetched lazily when a show detail opens, keyed by alias so reopening the
    /// same show is instant and a slow fetch can't land under a different show.
    @Published private(set) var details: [String: NTSAPI.ShowDetail] = [:]
    /// Loaded a page at a time as the episode list scrolls — `/shows/<alias>/episodes`
    /// clamps to 12 regardless of what's asked for, so a show with more than that
    /// (Lung Dart has 102) needs one request per twelve.
    @Published private(set) var episodes: [String: [NTSAPI.Episode]] = [:]
    @Published private(set) var episodeTotals: [String: Int] = [:]

    /// Aliases with a request out, one set per endpoint, so a second show opened
    /// inside the first one's latency still fetches, and one show opened twice
    /// fetches once.
    private var detailsInFlight: Set<String> = []
    private var episodesInFlight: Set<String> = []

    private let showIndex: ShowIndex

    init(showIndex: ShowIndex) {
        self.showIndex = showIndex
    }

    /// Fetch a show's page and then its first page of episodes, once. Both are
    /// best-effort: a failure leaves the detail view on what the schedule row
    /// already knew. The requests run in the loader's own task, so a caller
    /// going away (a view's `.task` cancelled) can't cancel a fetch another
    /// caller is relying on.
    func load(_ alias: String) {
        if details[alias] != nil {
            if episodes[alias] == nil { loadMore(for: alias) }
            return
        }
        // Already fetching: that request loads the episodes once it lands.
        guard detailsInFlight.insert(alias).inserted else { return }
        Task { [weak self] in
            let d = try? await NTSAPI.show(alias: alias)
            guard let self else { return }
            self.detailsInFlight.remove(alias)
            if let d {
                self.details[alias] = d
                // The same fetch the backfill would otherwise make later —
                // recording it here means this alias never re-queues for that.
                self.showIndex.noteDetailed(alias: alias, name: d.name, location: d.location,
                                            genres: d.genres, picture: d.image?.absoluteString,
                                            description: d.description, detailed: Date())
            }
            if self.episodes[alias] == nil { self.loadMore(for: alias) }
        }
    }

    /// Fetch the next twelve episodes of a show, if there are more and none of
    /// that show's are already in flight. The episode list calls this as its
    /// last row appears, same as Explore's grid.
    func loadMore(for alias: String) {
        let loaded = episodes[alias]?.count ?? 0
        if let total = episodeTotals[alias], loaded >= total { return }
        guard episodesInFlight.insert(alias).inserted else { return }
        Task { [weak self] in
            let page = try? await NTSAPI.episodes(alias: alias, offset: loaded)
            guard let self else { return }
            self.episodesInFlight.remove(alias)
            guard let page else { return }
            self.episodes[alias, default: []] += page.episodes
            self.episodeTotals[alias] = page.total
        }
    }
}
