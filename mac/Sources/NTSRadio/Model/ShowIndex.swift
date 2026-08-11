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

    private static let fileName = "shows-index.json"
    /// NTS regenerates the sitemap about daily, so a day-old index is the oldest
    /// that can still be current.
    private static let maxAge: TimeInterval = 24 * 60 * 60

    private var built = false

    private init() {
        for s in Cache.load([NTSAPI.ShowRef].self, from: Self.fileName) ?? [] {
            shows[s.alias] = s
        }
    }

    var count: Int { shows.count }

    /// Everything in the index, sorted by name — the order the catalog lists them.
    var all: [NTSAPI.ShowRef] { shows.values.sorted { $0.name < $1.name } }

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
                                      genres: genres, picture: picture, thumb: thumb)
    }

    /// Build the index if it's missing or older than a day. Safe to call on every
    /// launch; a fresh cache makes it a no-op.
    func buildIfStale() async {
        guard !built, !building else { return }
        let age = Cache.modified(Self.fileName).map { Date().timeIntervalSince($0) }
        guard shows.isEmpty || (age ?? .infinity) > Self.maxAge else { built = true; return }
        await build()
    }

    /// Seed from the sitemap, then top up from what NTS published today.
    ///
    /// Best-effort in both halves: a failure leaves whatever is already indexed
    /// standing rather than emptying it, and `ServiceStatus` has already said so.
    func build() async {
        guard !building else { return }
        building = true
        defer { building = false; built = true }

        if let aliases = try? await NTSAPI.sitemapShowAliases() {
            for alias in aliases {
                // `note` leaves richer entries alone, so re-seeding never
                // downgrades a show the app has actually met.
                note(alias: alias, name: Self.title(from: alias))
            }
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

        Cache.save(Array(shows.values), to: Self.fileName)
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

    /// Persist whatever `note` has accumulated. Called when the app is about to
    /// lose the in-memory copy, not on every note — the index is a cache, and a
    /// write per encountered show would be a write per schedule refresh.
    func flush() {
        Cache.save(Array(shows.values), to: Self.fileName)
    }
}
