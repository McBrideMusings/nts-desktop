import Foundation

/// Backfills every show's real name, location, genres and host blurb from
/// `/api/v2/shows/<alias>` — the endpoint that carries everything a search
/// needs but costs ~36.9KB per show (~68MB for the whole catalog), so this
/// runs once per machine rather than on any recurring cadence.
///
/// Modeled on `EpisodeIndex`/`ShowIndex`: a singleton the app starts once at
/// launch, best-effort throughout. What "stale" means is deliberately
/// different from both: this never rides `ShowIndex.maxAge` (the sitemap's
/// ~daily regeneration window), because that would mean redownloading all
/// ~1,834 shows every day forever. It keys off `ShowRef.detailed` instead —
/// nil means "never fetched" — so a fresh machine backfills once and every
/// later launch has nothing queued but the handful of shows NTS published
/// since.
@MainActor
final class ShowDetailBackfill: ObservableObject {
    static let shared = ShowDetailBackfill()

    /// True while a crawl is in flight, so the catalog can say so.
    @Published private(set) var running = false

    /// At most this many `/api/v2/shows/<alias>` requests in flight together.
    private static let concurrency = 4
    /// Between starting one request and the next, so a fresh machine's 1,834
    /// requests don't all fire in the same instant.
    private static let stagger: UInt64 = 250_000_000

    private init() {}

    /// How many known shows still have no real name/location/description —
    /// still queued, or (once `running` goes false) failed their one attempt
    /// this launch and waiting for the next to retry.
    var remaining: Int {
        ShowIndex.shared.shows.values.filter { $0.detailed == nil }.count
    }

    /// Fetch every alias in the show index that has never been detailed,
    /// `concurrency` at a time. Safe to call every launch: an index with
    /// nothing left to backfill returns immediately. Quitting mid-crawl loses
    /// nothing — each fetch's result is already on disk (`ShowIndex.flush`),
    /// so the next launch resumes exactly where this one stopped.
    func start() async {
        guard !running else { return }
        let queue = ShowIndex.shared.all.filter { $0.detailed == nil }
        guard !queue.isEmpty else { return }
        running = true
        defer { running = false }

        await withTaskGroup(of: Void.self) { group in
            var next = 0
            var active = 0
            while next < queue.count || active > 0 {
                while active < Self.concurrency, next < queue.count {
                    let alias = queue[next].alias
                    next += 1
                    active += 1
                    group.addTask { await Self.fetchOne(alias: alias) }
                    if next < queue.count {
                        try? await Task.sleep(nanoseconds: Self.stagger)
                    }
                }
                if active > 0 {
                    _ = await group.next()
                    active -= 1
                }
            }
        }
    }

    /// One alias's fetch-and-merge. A failure leaves the existing entry's
    /// `detailed` at nil, so it stays queued for the next launch — refusing
    /// is correct, since NTS answering doesn't mean this alias got worse.
    private static func fetchOne(alias: String) async {
        guard let d = try? await NTSAPI.show(alias: alias) else { return }
        ShowIndex.shared.noteDetailed(
            alias: alias, name: d.name, location: d.location, genres: d.genres,
            picture: d.image?.absoluteString, description: d.description, detailed: Date()
        )
    }
}
