import Foundation

/// A show-index entry, exactly as far as search needs to see it. `ShowSearch`
/// lives in this pure, I/O-free target so `FSProbe` can exercise it without
/// the app's `Cache`/`NTSAPI`/`MainActor` machinery; `NTSAPI.ShowRef` (the app
/// target) conforms to this rather than being passed directly, since this
/// target cannot import that one.
public protocol ShowSearchable {
    var name: String { get }
    var alias: String { get }
    var location: String { get }
    var genres: [String] { get }
    var description: String { get }
}

/// Local search over the show index, folding away the punctuation that both
/// makes NTS show names distinctive ("PU$$YRAP W/ JODY SIMMS") and defeats a
/// plain substring match against a typed query ("pussyrap", "jody simm").
public enum ShowSearch {
    /// Per word: lowercase alphanumerics only, single-space joined.
    /// "PU$$YRAP W/ JODY SIMMS" -> "puyrap w jody simms". Deliberately not
    /// `EpisodeMatch.normalize`, which also strips the spaces between words —
    /// here they mark query-token boundaries, so they have to survive.
    public static func fold(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace })
            .map { word -> String in
                var out = ""
                for ch in word.lowercased() where ch.isASCII && (ch.isLetter || ch.isNumber) {
                    out.append(ch)
                }
                return out
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Everything a query is matched against, folded once at build time.
    /// `alias` is included deliberately: folding destroys the punctuation
    /// that makes the current alias-derived name findable, so once the real
    /// name replaces it, the alias is what keeps "pussyrap" still matching
    /// "PU$$YRAP W/ JODY SIMMS".
    public static func haystack(name: String, alias: String, location: String,
                                 genres: [String], description: String) -> String {
        fold([name, alias, location, genres.joined(separator: " "), description]
            .joined(separator: " "))
    }

    /// Every token of the folded query must appear somewhere in the folded
    /// haystack. "jody simm" -> ["jody", "simm"] -> both present -> hit.
    public static func matches(query: String, haystack: String) -> Bool {
        let tokens = fold(query).split(separator: " ")
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { haystack.contains($0) }
    }

    /// Lower is better. A one-token query like "jody" matches every show
    /// whose description happens to mention a Jody, so without this a real
    /// hit on the name gets buried under description-only noise.
    ///
    /// 0 folded name starts with the folded query
    /// 1 folded name contains it
    /// 2 folded alias contains it
    /// 3 folded location or a genre contains it
    /// 4 matched in the description only
    public static func rank<T: ShowSearchable>(query: String, _ ref: T) -> Int {
        let q = fold(query)
        guard !q.isEmpty else { return 0 }
        let foldedName = fold(ref.name)
        if foldedName.hasPrefix(q) { return 0 }
        if foldedName.contains(q) { return 1 }
        if fold(ref.alias).contains(q) { return 2 }
        if fold(ref.location).contains(q) || ref.genres.contains(where: { fold($0).contains(q) }) {
            return 3
        }
        return 4
    }
}
