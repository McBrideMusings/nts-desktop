import Foundation
import EpisodeMatch

/// Resolves a mixtape's source-episode link when NTS's own Firestore push
/// leaves it out.
///
/// `MixtapeTitleListener` (`mac/Sources/NTSFirestore/MixtapeTitleListener.swift`)
/// delivers `MixtapeTitle.title` — a display string like "Pu$$yrap with Jody
/// Simms, 7 Nov 2022" — plus `showAlias`/`episodeAlias`, which NTS sometimes
/// leaves empty. When that happens, `AppModel.nowPlayingEpisodeURL` falls back
/// to `resolve(title:)` here, which matches the title against NTS's own
/// sitemap: 89,625 episode aliases (`/shows/<alias>/episodes/<episode>`),
/// bucketed by the date suffix most of them carry.
///
/// Modeled on `ShowIndex`: same disk cache through `Cache`, same ~daily
/// staleness via a `UserDefaults` seed stamp, same best-effort failure (a bad
/// fetch leaves the old index standing). The matching algorithm itself lives
/// in the `EpisodeMatch` library target — pure and I/O-free, so the accuracy
/// probe (`swift run FSProbe accuracy`) can link it directly and check it
/// against the live sitemap; a run against the real sitemap on 2026-08-26
/// scored 120 correct, 0 wrong, 41 refused on 161 samples pulled live from
/// `/shows/<alias>/episodes` across 30 random shows (93,824 episode URLs,
/// 5,967 undated, 4,744 date buckets, median bucket size 19). The exact counts
/// drift run to run since both the sitemap and the sample are live, not
/// frozen — the shape (0 wrong, most refusals honest) is what matters.
///
/// The encoded cache is ~4.6MB (vs. `ShowIndex`'s ~140KB for 49x fewer rows)
/// — big for a local JSON file, but it is a once-daily background write to
/// Application Support, never shipped, synced, or read on the main thread, so
/// plain JSON through the same `Cache` helper stays the simplest correct
/// choice rather than a bespoke binary encoding.
///
/// Known limit: the sitemap regenerates about daily, so an episode broadcast
/// today is not in it yet and cannot resolve until tomorrow's walk.
@MainActor
final class EpisodeIndex: ObservableObject {
    static let shared = EpisodeIndex()

    /// Every dated episode alias, bucketed by its trailing date — e.g.
    /// "7th-november-2022" -> [(show: "pussyrap", namePart: "pu-yrap-w-jody-simms"), ...].
    /// The full alias is `"\(namePart)-\(dateKey)"`, so nothing is stored twice.
    /// 5,967 of 89,625 aliases carry no trailing date and are dropped at seed
    /// time — unresolvable by this method regardless.
    private var buckets: [String: [EpisodeMatch.Candidate]] = [:]
    @Published private(set) var building = false

    private enum Resolution { case found(show: String, episode: String), refused }
    /// Per-title resolutions, so a SwiftUI body re-evaluating the now-playing
    /// subtitle doesn't rerun the match on every frame. Cleared whenever the
    /// buckets are reseeded.
    private var resolved: [String: Resolution] = [:]

    nonisolated private static let fileName = "episode-index.json"
    /// NTS regenerates the sitemap about daily, same as `ShowIndex`.
    private static let maxAge: TimeInterval = 24 * 60 * 60

    private var built = false

    private init() {
        buckets = Cache.load([String: [EpisodeMatch.Candidate]].self, from: Self.fileName) ?? [:]
    }

    private static let seededKey = "episodeIndexSeeded"
    private var lastSeed: Date? {
        get { UserDefaults.standard.object(forKey: Self.seededKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.seededKey) }
    }

    /// Whether the index needs a rebuild — missing, or older than a day. Read
    /// by `AppModel` before fetching the sitemap, so a walk that only
    /// `ShowIndex` needs doesn't also re-seed a fresh `EpisodeIndex`.
    var needsBuild: Bool {
        guard !built, !building else { return false }
        let age = lastSeed.map { Date().timeIntervalSince($0) }
        return buckets.isEmpty || (age ?? .infinity) > Self.maxAge
    }

    /// Build the index if it's missing or older than a day, walking the
    /// sitemap itself. Convenience for callers that don't need to share the
    /// walk with `ShowIndex` — `AppModel`'s launch sequence calls
    /// `build(entries:)` directly instead, off one shared `NTSAPI.sitemapWalk()`.
    func buildIfStale() async {
        guard needsBuild else { return }
        guard let entries = try? await NTSAPI.sitemapWalk().episodes else { return }
        await build(entries: entries)
    }

    /// Bucket the sitemap's episode entries by date and persist. Best-effort:
    /// an empty `entries` (a failed walk upstream) leaves the existing index
    /// standing rather than emptying it.
    func build(entries: [(show: String, episodeAlias: String)]) async {
        guard !building else { return }
        building = true
        defer { building = false; built = true }
        guard !entries.isEmpty else { return }

        var next: [String: [EpisodeMatch.Candidate]] = [:]
        for entry in entries {
            guard let (namePart, dateKey) = EpisodeMatch.splitTrailingDate(entry.episodeAlias) else { continue }
            next[dateKey, default: []].append(EpisodeMatch.Candidate(show: entry.show, namePart: namePart))
        }
        buckets = next
        resolved.removeAll()
        lastSeed = Date()
        flush()
    }

    func flush() {
        Cache.save(buckets, to: Self.fileName)
    }

    /// Resolve a Firestore mixtape title to its source episode. Refuses (nil)
    /// rather than risk a wrong link — see `EpisodeMatch.resolve`'s doc comment
    /// for the acceptance rule. Each title's result is cached for the life of
    /// this index (cleared on reseed), so repeated SwiftUI body evaluations
    /// don't rerun the match.
    func resolve(title: String) -> (show: String, episode: String)? {
        if let cached = resolved[title] {
            if case .found(let show, let episode) = cached { return (show, episode) }
            return nil
        }
        guard let match = EpisodeMatch.resolve(title: title, bucket: { [weak self] key in
            self?.buckets[key] ?? []
        }) else {
            resolved[title] = .refused
            return nil
        }
        resolved[title] = .found(show: match.show, episode: match.episode)
        return match
    }
}
