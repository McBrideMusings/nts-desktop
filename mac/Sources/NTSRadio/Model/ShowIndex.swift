import Foundation
import Combine

/// The searchable list of NTS shows, held on disk so it survives relaunch.
///
/// NTS has no working search endpoint — `/api/v2/search` answers 200 with an empty
/// `results` array for every `type` — so the catalog's search field filters a local
/// index instead. That index is built by walking `/api/v2/shows`, which caps `limit`
/// at 12 and refuses any `offset` past 1000 with HTTP 422. Two consequences the UI
/// has to be honest about:
///
///  - the walk is ~85 requests, so it runs once in the background and is cached for
///    a week rather than rebuilt on launch, and
///  - it can only reach 1012 of the 1733 shows the endpoint says exist. Anything
///    else the app happens to see — a schedule slot, a mixtape credit, a show you
///    opened — is merged in via `note(_:)`, so the index grows with use. The search
///    field prints its own size so the ceiling is never implied away.
@MainActor
final class ShowIndex: ObservableObject {
    static let shared = ShowIndex()

    /// Every known show, alias-keyed so a merge can't duplicate.
    @Published private(set) var shows: [String: NTSAPI.ShowRef] = [:]
    /// True while the background walk is running, so the catalog can say so.
    @Published private(set) var building = false

    private static let fileName = "shows-index.json"
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    /// How many page fetches are in flight at once during the walk. Six keeps the
    /// whole build under ten seconds without hammering a public endpoint.
    private static let concurrency = 6

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

    /// Alias-per-normalised-name, rebuilt whenever `shows` changes. The schedule's
    /// later slots carry no alias, so a title is the only handle onto them.
    private var byName: [String: String] = [:]
    private var byNameStamp = -1

    /// The indexed show whose name matches this broadcast title, if any.
    /// Case, punctuation and the "(R)" repeat marker are all stripped, because a
    /// broadcast title is the show's name shouted in caps with that suffix bolted
    /// on: `"SOUP TO NUTS W/ JOHN GÓMEZ (R)"` against `"Soup To Nuts w/ John Gómez"`.
    func match(title: String) -> NTSAPI.ShowRef? {
        rebuildNamesIfNeeded()
        guard let alias = byName[Self.normalise(title)] else { return nil }
        return shows[alias]
    }

    private func rebuildNamesIfNeeded() {
        guard byNameStamp != shows.count else { return }
        byNameStamp = shows.count
        byName = [:]
        for s in shows.values { byName[Self.normalise(s.name)] = s.alias }
    }

    static func normalise(_ s: String) -> String {
        var t = s.lowercased()
        t = t.replacingOccurrences(of: "(r)", with: "")
        return t.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .folding(options: .diacriticInsensitive, locale: nil)
    }

    /// Fold a show the app encountered into the index. Cheap and idempotent: an
    /// alias already present keeps its richer entry rather than being overwritten
    /// by a sparser one (a schedule slot has no genres; the walk's entry does).
    func note(alias: String, name: String, location: String = "", genres: [String] = [],
              picture: String? = nil, thumb: String? = nil) {
        guard !alias.isEmpty else { return }
        if let existing = shows[alias], !existing.genres.isEmpty || existing.picture != nil {
            return
        }
        shows[alias] = NTSAPI.ShowRef(alias: alias, name: name, location: location,
                                      genres: genres, picture: picture, thumb: thumb)
    }

    /// Build the index if it's missing or older than a week. Safe to call on every
    /// launch; a fresh cache makes it a no-op.
    func buildIfStale() async {
        guard !built, !building else { return }
        let age = Cache.modified(Self.fileName).map { Date().timeIntervalSince($0) }
        guard shows.isEmpty || (age ?? .infinity) > Self.maxAge else { built = true; return }
        await build()
    }

    /// Walk every reachable page and merge the results. Best-effort: a page that
    /// fails is skipped, leaving the index smaller rather than empty.
    func build() async {
        guard !building else { return }
        building = true
        defer { building = false; built = true }

        let offsets = stride(from: 0, through: NTSAPI.showIndexCeiling, by: NTSAPI.showPageSize).map { $0 }
        var merged: [String: NTSAPI.ShowRef] = shows

        for chunk in offsets.chunked(into: Self.concurrency) {
            let pages = await withTaskGroup(of: [NTSAPI.ShowRef].self) { group -> [[NTSAPI.ShowRef]] in
                for offset in chunk {
                    group.addTask { (try? await NTSAPI.showPage(offset: offset)) ?? [] }
                }
                var out: [[NTSAPI.ShowRef]] = []
                for await page in group { out.append(page) }
                return out
            }
            for show in pages.flatMap({ $0 }) { merged[show.alias] = show }
        }

        shows = merged
        Cache.save(Array(merged.values), to: Self.fileName)
    }

    /// Persist whatever `note` has accumulated. Called when the app is about to
    /// lose the in-memory copy, not on every note — the index is a cache, and a
    /// write per encountered show would be a write per schedule refresh.
    func flush() {
        Cache.save(Array(shows.values), to: Self.fileName)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
