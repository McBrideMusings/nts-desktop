import Foundation

/// Pages through Explore's search results — `/api/v2/search/episodes` filtered
/// by mood, genre and the two derived toggles — and guards against the race a
/// filter change mid-page creates.
///
/// Owns only the filters, the paging and their results. The mood/genre
/// vocabulary and the drawer state that edits `filters` stay on `AppModel`,
/// which is the caller of `toggleGenre`/`toggleMood`/`browseGenre` mutating
/// `explore.filters` from outside.
@MainActor
final class ExploreLoader: ObservableObject {
    /// What Explore is filtered to, kept across a relaunch. Every change re-runs
    /// the search from the first page — a filter that left the old results
    /// underneath it would be showing episodes that no longer match. The
    /// results themselves are not kept: a relaunch starts again from page one.
    @Published var filters: NTSAPI.ExploreFilters {
        didSet {
            guard filters != oldValue else { return }
            preferences.exploreFilters = filters
            reload()
        }
    }
    @Published private(set) var episodes: [NTSAPI.EpisodeCard] = []
    /// How many episodes match, which is usually far more than are loaded —
    /// the grid pages twelve at a time through thousands.
    @Published private(set) var total = 0
    @Published private(set) var loading = false

    private var load: Task<Void, Never>?
    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        filters = preferences.exploreFilters
    }

    /// Start Explore over from its first page.
    func reload() {
        load?.cancel()
        episodes = []
        total = 0
        loadPage(offset: 0)
    }

    /// Fetch the next twelve, if there are more and nothing is already in
    /// flight. The grid calls this as its last row appears.
    func loadMore() {
        guard !loading, episodes.count < total else { return }
        loadPage(offset: episodes.count)
    }

    private func loadPage(offset: Int) {
        let filters = filters
        loading = true
        load = Task { [weak self] in
            defer { Task { @MainActor in self?.loading = false } }
            guard let page = try? await NTSAPI.explore(filters, offset: offset) else { return }
            guard !Task.isCancelled, let self, self.filters == filters else { return }
            // Paging can race a filter change; the guard above is why a late
            // page can't land under filters that no longer asked for it.
            self.episodes += page.episodes
            self.total = page.total
        }
    }
}
