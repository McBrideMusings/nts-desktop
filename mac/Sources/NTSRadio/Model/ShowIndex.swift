import Foundation
import Combine

/// The searchable list of NTS shows, held on disk so it survives relaunch.
///
/// NTS has no working search endpoint — `/api/v2/search` answers 200 with an empty
/// `results` array for every `type`, even called exactly as nts.live calls it — so
/// the catalog's search field filters a local index instead.
///
/// That index comes from NTS's own sitemap, which is the whole catalogue with no
/// ceiling: **1,834 show aliases** in three requests. It used to come from walking
/// `/api/v2/shows`, which clamps `limit` to 12 and refuses any `offset` past 1000
/// with HTTP 422 — 85 requests to reach 1012 shows, with 822 of them permanently
/// unfindable no matter how long you waited.
///
/// The sitemap carries URLs and nothing else, so a freshly seeded show has an
/// alias and a title read off that alias (`lung-dart` → "Lung Dart"). The real
/// name, city, genres and artwork arrive through `note(_:)` as the app meets the
/// show for real — in the schedule, in Explore, or when it is opened — and a
/// richer entry always wins over a sparser one.
@MainActor
final class ShowIndex: ObservableObject {
    static let shared = ShowIndex()

    /// Every known show, alias-keyed so a merge can't duplicate.
    @Published private(set) var shows: [String: NTSAPI.ShowRef] = [:]
    /// True while the seed is running, so the catalog can say so.
    @Published private(set) var building = false

    nonisolated private static let fileName = "shows-index.json"
    /// NTS regenerates the sitemap about daily, so a day-old index is the oldest
    /// that can still be current.
    private static let maxAge: TimeInterval = 24 * 60 * 60

    private var built = false
    private var sortedCache: [NTSAPI.ShowRef]?

    private init() {
        for s in Cache.load([NTSAPI.ShowRef].self, from: Self.fileName) ?? [] {
            shows[s.alias] = s
        }
        sortedCache = nil
    }

    var count: Int { shows.count }

    /// Everything in the index, sorted by name — the order the catalog lists them.
    var all: [NTSAPI.ShowRef] {
        if let cached = sortedCache {
            return cached
        }
        let sorted = shows.values.sorted { $0.name < $1.name }
        sortedCache = sorted
        return sorted
    }

    func ref(_ alias: String) -> NTSAPI.ShowRef? { shows[alias] }

    /// Fold a show the app encountered into the index. Cheap and idempotent: an
    /// alias already present keeps its richer entry rather than being overwritten
    /// by a sparser one (a sitemap seed has no genres; an Explore result does).
    func note(alias: String, name: String, location: String = "", genres: [String] = [],
              picture: String? = nil, thumb: String? = nil) {
        guard !alias.isEmpty else { return }
        if let existing = shows[alias], !existing.genres.isEmpty || existing.picture != nil {
            return
        }
        shows[alias] = NTSAPI.ShowRef(alias: alias, name: name, location: location,
                                      genres: genres, picture: picture, thumb: thumb,
                                      description: shows[alias]?.description ?? "",
                                      detailed: shows[alias]?.detailed)
        sortedCache = nil
        flushSoon()
    }

    /// Merge a full `/api/v2/shows/<alias>` read into the index — the richest
    /// source there is, so unlike `note(_:)` this always wins rather than
    /// deferring to whatever is already on file. Used by `ShowDetailBackfill`
    /// and by opening a show's detail page, both of which fetched the same
    /// endpoint `note(_:)`'s sparser callers never see.
    func noteDetailed(alias: String, name: String, location: String, genres: [String],
                       picture: String?, description: String, detailed: Date) {
        guard !alias.isEmpty else { return }
        let existing = shows[alias]
        shows[alias] = NTSAPI.ShowRef(alias: alias, name: name, location: location, genres: genres,
                                      picture: picture ?? existing?.picture, thumb: existing?.thumb,
                                      description: description, detailed: detailed)
        sortedCache = nil
        flushSoon()
    }

    /// Whether the index needs a rebuild — missing, or `lastSeed` (when the
    /// sitemap was last walked, `Preferences.showIndexSeeded`) older than a day.
    /// Read by `AppModel` before fetching the sitemap, so a walk that only
    /// `EpisodeIndex` needs doesn't also re-seed a fresh `ShowIndex`.
    func needsBuild(lastSeed: Date?) -> Bool {
        guard !built, !building else { return false }
        let age = lastSeed.map { Date().timeIntervalSince($0) }
        return shows.isEmpty || (age ?? .infinity) > Self.maxAge
    }

    /// Seed from the sitemap, then top up from what NTS published today.
    ///
    /// Best-effort in both halves: a failure leaves whatever is already indexed
    /// standing rather than emptying it, and `ServiceStatus` has already said so.
    ///
    /// Answers whether this counts as a seed, for the caller to stamp. Only a
    /// walk that actually answered does: stamping regardless would mean a launch
    /// with no network marked the index fresh for a day and the re-seed never
    /// ran once the network came back.
    func build(showAliases: [String]) async -> Bool {
        guard !building else { return false }
        building = true
        defer { building = false; built = true }

        for alias in showAliases {
            // `note` leaves richer entries alone, so re-seeding never
            // downgrades a show the app has actually met.
            note(alias: alias, name: Self.title(from: alias))
        }

        // The sitemap is regenerated about daily and today's shows are not in it
        // yet. This is the only route to a show that debuted this morning.
        if let recent = try? await NTSAPI.recentlyAdded() {
            for episode in recent {
                note(alias: episode.showAlias, name: episode.title,
                     location: episode.location, genres: episode.genres,
                     picture: episode.image?.absoluteString)
            }
        }

        flush()
        sortedCache = nil
        return !showAliases.isEmpty
    }

    /// A readable name from an alias, for a show the app has only seen in the
    /// sitemap: `soup-to-nuts-w-john-gomez` → "Soup To Nuts W John Gomez". Not
    /// the show's real styling, but findable and legible, and replaced by the
    /// real name the first time the show turns up in a feed.
    static func title(from alias: String) -> String {
        alias.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Persist whatever `note` has accumulated.
    func flush() {
        flushTask?.cancel()
        flushTask = nil
        Cache.save(Array(shows.values), to: Self.fileName)
    }

    private var flushTask: Task<Void, Never>?

    /// Persist a few seconds after the notes stop arriving.
    ///
    /// Not a write per note: a schedule refresh folds in 347 slots in a loop and
    /// the timeline enriches a screen of rows at a time, so an immediate write
    /// would be hundreds of writes of the same 1,834-entry file. Not the old
    /// arrangement either, which was a `flush()` nothing ever called — so a
    /// show's artwork and genres lived only until quit, and every launch drew
    /// the placeholder again until the row was re-fetched.
    private func flushSoon() {
        // `build` folds in 1,834 aliases in a loop and writes at the end itself;
        // arming a timer per alias would allocate and cancel 1,834 tasks for a
        // write that is already coming.
        guard !building else { return }
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.flushTask = nil
            // Encoding 1,834 shows and writing 140KB happens off the main actor;
            // the UI is running while a scroll is what triggers this. `flush()`
            // stays synchronous because quit cannot wait for a detached task.
            let all = Array(self.shows.values)
            Task.detached { Cache.save(all, to: Self.fileName) }
        }
    }
}
