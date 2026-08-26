import Foundation

/// Resolves a Firestore `MixtapeTitle.title` (e.g. "Pu$$yrap with Jody Simms,
/// 7 Nov 2022") to the NTS episode it names, by matching it against the
/// sitemap's date-bucketed episode aliases (e.g. `pu-yrap-w-jody-simms-7th-november-2022`).
///
/// Pure and I/O-free: no network, no disk, no `Cache`/`NTSAPI`/`MainActor`.
/// `EpisodeIndex` (in the app target) owns fetching and persisting the sitemap
/// walk; the accuracy probe (`FSProbe accuracy`) links this alone so both share
/// the exact matching logic the measured accuracy numbers were taken against.
///
/// The similarity metric is a Swift port of Python difflib's
/// `SequenceMatcher.ratio()` — Ratcliff/Obershelp, `2*M/T` where `M` is the
/// total size of matching blocks found by recursively taking the longest
/// matching block and recursing left and right of it, `T` the sum of both
/// lengths. Swift has no difflib; the accuracy numbers this was measured
/// against (115/1/49 on 165 real samples) only hold for this exact algorithm.
public enum EpisodeMatch {

    // MARK: - Ratcliff/Obershelp ratio

    /// `difflib.SequenceMatcher(None, a, b).ratio()`. No autojunk handling —
    /// these are short title/alias fragments, never the 200+ char strings
    /// autojunk exists for.
    public static func ratio(_ a: String, _ b: String) -> Double {
        let ac = Array(a)
        let bc = Array(b)
        guard !ac.isEmpty || !bc.isEmpty else { return 1.0 }

        var b2j: [Character: [Int]] = [:]
        for (j, ch) in bc.enumerated() { b2j[ch, default: []].append(j) }

        func findLongestMatch(_ alo: Int, _ ahi: Int, _ blo: Int, _ bhi: Int) -> (Int, Int, Int) {
            var besti = alo, bestj = blo, bestsize = 0
            var j2len: [Int: Int] = [:]
            for i in alo..<ahi {
                var newj2len: [Int: Int] = [:]
                if let js = b2j[ac[i]] {
                    for j in js {
                        if j < blo { continue }
                        if j >= bhi { break }
                        let k = (j2len[j - 1] ?? 0) + 1
                        newj2len[j] = k
                        if k > bestsize {
                            besti = i - k + 1
                            bestj = j - k + 1
                            bestsize = k
                        }
                    }
                }
                j2len = newj2len
            }
            return (besti, bestj, bestsize)
        }

        var matches = 0
        var queue: [(Int, Int, Int, Int)] = [(0, ac.count, 0, bc.count)]
        while let (alo, ahi, blo, bhi) = queue.popLast() {
            let (i, j, k) = findLongestMatch(alo, ahi, blo, bhi)
            guard k > 0 else { continue }
            matches += k
            if alo < i, blo < j { queue.append((alo, i, blo, j)) }
            if i + k < ahi, j + k < bhi { queue.append((i + k, ahi, j + k, bhi)) }
        }
        return 2.0 * Double(matches) / Double(ac.count + bc.count)
    }

    /// Similarity of a title fragment to a candidate alias fragment. A plain
    /// ratio punishes the common case where the alias is just the host name
    /// ("kemarr") but the title carries the whole show name ("LIGHTER DANCE
    /// W/ KEMARR"), so containment counts too: a candidate of 5+ characters
    /// that appears whole inside the target scores on how much of the target
    /// it explains, floored so it always beats an unrelated show sharing the
    /// date. Both arguments must already be normalized (see `normalize`).
    public static func score(target: String, candidate: String) -> Double {
        guard !target.isEmpty, !candidate.isEmpty else { return 0 }
        var r = ratio(target, candidate)
        if candidate.count >= 5, target.contains(candidate) {
            r = max(r, 0.6 + 0.4 * (Double(candidate.count) / Double(target.count)))
        }
        return r
    }

    /// Lowercase alphanumerics only — strips everything else so "Pu$$yrap"
    /// matches "pu-yrap".
    public static func normalize(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.lowercased() where ch.isASCII && (ch.isLetter || ch.isNumber) {
            out.append(ch)
        }
        return out
    }

    // MARK: - NTS date-alias vocabulary

    static let months = ["january", "february", "march", "april", "may", "june",
                          "july", "august", "september", "october", "november", "december"]

    static func ordinalSuffix(_ day: Int) -> String {
        if (11...13).contains(day) { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    static func dateKey(day: Int, monthIndex: Int, year: Int) -> String {
        "\(day)\(ordinalSuffix(day))-\(months[monthIndex])-\(year)"
    }

    private static let aliasDateSuffix = try! NSRegularExpression(
        pattern: "-(\\d{1,2})(st|nd|rd|th)-(january|february|march|april|may|june|july|august|september|october|november|december)-(\\d{4})$"
    )

    /// "pu-yrap-w-jody-simms-7th-november-2022" -> ("pu-yrap-w-jody-simms", "7th-november-2022").
    /// Nil when the alias carries no trailing date — unresolvable by this method.
    public static func splitTrailingDate(_ alias: String) -> (namePart: String, dateKey: String)? {
        let ns = alias as NSString
        guard let m = aliasDateSuffix.firstMatch(in: alias, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let namePart = ns.substring(to: m.range.location)
        let dateKey = ns.substring(from: m.range.location + 1)
        return (namePart, dateKey)
    }

    private static let titleDateSuffix = try! NSRegularExpression(
        pattern: ",\\s*(\\d{1,2})\\s+([A-Za-z]{3,})\\s+(\\d{4})\\s*$"
    )

    /// "Pu$$yrap with Jody Simms, 7 Nov 2022" -> ("Pu$$yrap with Jody Simms", "7th-november-2022").
    /// Nil when the title carries no trailing ", D Mon YYYY".
    public static func parseTitle(_ title: String) -> (name: String, dateKey: String)? {
        let ns = title as NSString
        guard let m = titleDateSuffix.firstMatch(in: title, range: NSRange(location: 0, length: ns.length)),
              let day = Int(ns.substring(with: m.range(at: 1)))
        else { return nil }
        let monAbbrev = ns.substring(with: m.range(at: 2)).lowercased().prefix(3)
        let year = ns.substring(with: m.range(at: 3))
        guard let monthIndex = months.firstIndex(where: { $0.hasPrefix(monAbbrev) }) else { return nil }
        let name = ns.substring(to: m.range.location)
        return (name, dateKey(day: day, monthIndex: monthIndex, year: Int(year) ?? 0))
    }

    private static let dateKeyPattern = try! NSRegularExpression(
        pattern: "^(\\d{1,2})(st|nd|rd|th)-([a-z]+)-(\\d{4})$"
    )

    static func parseDateKey(_ key: String) -> (day: Int, monthIndex: Int, year: Int)? {
        let ns = key as NSString
        guard let m = dateKeyPattern.firstMatch(in: key, range: NSRange(location: 0, length: ns.length)),
              let day = Int(ns.substring(with: m.range(at: 1))),
              let monthIndex = months.firstIndex(of: ns.substring(with: m.range(at: 3))),
              let year = Int(ns.substring(with: m.range(at: 4)))
        else { return nil }
        return (day, monthIndex, year)
    }

    /// The dateKey's calendar day, its predecessor and its successor — NTS's
    /// own alias and the mixtape title's date disagree by a day often enough
    /// that resolution has to check both neighbours, not just the exact
    /// bucket (see `EpisodeIndex`'s doc comment for the measured case).
    public static func adjacentDateKeys(_ key: String) -> [String] {
        guard let (day, monthIndex, year) = parseDateKey(key) else { return [key] }
        var comps = DateComponents()
        comps.day = day
        comps.month = monthIndex + 1
        comps.year = year
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let date = cal.date(from: comps) else { return [key] }
        return [-1, 0, 1].compactMap { offset -> String? in
            guard let d = cal.date(byAdding: .day, value: offset, to: date) else { return nil }
            let c = cal.dateComponents([.day, .month, .year], from: d)
            guard let dd = c.day, let mm = c.month, let yy = c.year else { return nil }
            return dateKey(day: dd, monthIndex: mm - 1, year: yy)
        }
    }

    // MARK: - Resolution

    /// One sitemap episode alias, minus its date suffix.
    public struct Candidate: Codable, Sendable {
        public let show: String
        public let namePart: String
        public init(show: String, namePart: String) {
            self.show = show
            self.namePart = namePart
        }
    }

    /// Resolve a Firestore `MixtapeTitle.title` to its source episode.
    ///
    /// `bucket(dateKey)` must return the candidates for that exact date —
    /// callers supply this instead of a `[String: [Candidate]]` directly so
    /// `EpisodeIndex` can hand over a closure over its own storage rather than
    /// copying it.
    ///
    /// Candidates come from the parsed date's bucket plus the day before and
    /// after. Accepts the top match only when it clears both an absolute floor
    /// (0.60) and a 1.4x margin over the runner-up across all three days'
    /// candidates combined; refuses (nil) otherwise. Refusing is correct — a
    /// wrong link is worse than no link.
    public static func resolve(title: String, bucket: (String) -> [Candidate]) -> (show: String, episode: String)? {
        guard let (name, key) = parseTitle(title) else { return nil }
        let target = normalize(name)

        var scored: [(score: Double, show: String, episode: String)] = []
        for dk in adjacentDateKeys(key) {
            for c in bucket(dk) {
                let s = max(score(target: target, candidate: normalize(c.namePart)),
                            score(target: target, candidate: normalize(c.show)))
                scored.append((s, c.show, "\(c.namePart)-\(dk)"))
            }
        }
        guard !scored.isEmpty else { return nil }
        scored.sort { $0.score > $1.score }
        let best = scored[0]
        let runnerUp = scored.count > 1 ? scored[1].score : 0.0
        guard best.score >= 0.60, best.score >= 1.4 * runnerUp else { return nil }
        return (best.show, best.episode)
    }
}
