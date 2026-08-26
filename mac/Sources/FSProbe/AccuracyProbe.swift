import Foundation
import EpisodeMatch

/// `swift run FSProbe accuracy` — reproduces the accuracy measurement the
/// episode-index-resolver design was built against (see
/// `mac/Sources/NTSRadio/Model/EpisodeIndex.swift`), against the real,
/// current sitemap rather than a frozen sample.
///
/// Independent of the app target on purpose: it fetches the sitemap and shows
/// itself (plain `URLSession`, no `NTSAPI`/`Cache`/`MainActor`) and links only
/// the pure `EpisodeMatch` library, so a green run proves the shipped matching
/// algorithm — not a mock of it — against live data.
///
/// Method: walk the sitemap into date buckets, sample 30 random shows, pull up
/// to 6 real episodes each from `/api/v2/shows/<alias>/episodes`, rebuild the
/// Firestore-style title from each episode's `name` + `broadcast` date, and
/// check what `EpisodeMatch.resolve` returns against the episode's own alias.
enum AccuracyProbe {
    static func run() async {
        print("walking sitemap…")
        guard let episodeURLs = try? await fetchSitemapEpisodeURLs() else {
            print("sitemap fetch failed")
            exit(1)
        }

        var buckets: [String: [EpisodeMatch.Candidate]] = [:]
        var undated = 0
        for url in episodeURLs {
            guard let (show, alias) = showAndEpisodeAlias(from: url) else { continue }
            guard let (namePart, dateKey) = EpisodeMatch.splitTrailingDate(alias) else { undated += 1; continue }
            buckets[dateKey, default: []].append(EpisodeMatch.Candidate(show: show, namePart: namePart))
        }
        let sizes = buckets.values.map(\.count).sorted()
        print("episodes: \(episodeURLs.count)  undated: \(undated)  date buckets: \(buckets.count)")
        if !sizes.isEmpty {
            print("bucket size: median \(sizes[sizes.count / 2])  max \(sizes[sizes.count - 1])")
        }

        let cacheSize = (try? JSONEncoder().encode(buckets).count) ?? 0
        print("encoded cache size: \(cacheSize) bytes (\(cacheSize / 1024) KB)")

        let shows = Array(Set(buckets.values.flatMap { $0.map(\.show) })).sorted()
        var rng = SeededGenerator(seed: 7)
        let sampleShows = shows.shuffled(using: &rng).prefix(30)

        var samples: [(title: String, show: String, alias: String)] = []
        for show in sampleShows {
            guard let episodes = try? await fetchEpisodes(show: show, limit: 6) else { continue }
            for ep in episodes {
                guard let broadcast = ep.broadcast, let alias = ep.episode_alias, !alias.isEmpty,
                      let date = parseBroadcastDate(broadcast) else { continue }
                let title = "\(ep.name ?? ""), \(date)"
                samples.append((title: title, show: show, alias: alias))
            }
        }
        print("samples: \(samples.count)")

        var correct = 0, wrong = 0, refused = 0
        var wrongExamples: [String] = []
        for s in samples {
            let result = EpisodeMatch.resolve(title: s.title) { buckets[$0] ?? [] }
            guard let result else { refused += 1; continue }
            if result.show == s.show, result.episode == s.alias {
                correct += 1
            } else {
                wrong += 1
                wrongExamples.append("  \(s.title) -> got \(result.show)/\(result.episode), want \(s.show)/\(s.alias)")
            }
        }
        print("correct \(correct)  wrong \(wrong)  refused \(refused)")
        for w in wrongExamples { print(w) }
        exit(0)
    }

    // MARK: - Sitemap

    private static func fetchSitemapEpisodeURLs() async throws -> [String] {
        let index = try await fetchData(URL(string: "https://www.nts.live/sitemap.xml.gz")!)
        let parts = locations(in: index).filter { $0.hasSuffix(".xml.gz") }
        var urls: [String] = []
        for part in parts {
            guard let url = URL(string: part) else { continue }
            let data = try await fetchData(url)
            urls.append(contentsOf: locations(in: data))
        }
        return urls
    }

    private static func locations(in data: Data) -> [String] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        return xml.components(separatedBy: "<loc>").dropFirst().compactMap {
            $0.components(separatedBy: "</loc>").first
        }
    }

    /// "https://www.nts.live/shows/pussyrap/episodes/pu-yrap-w-jody-simms-7th-november-2022"
    /// -> ("pussyrap", "pu-yrap-w-jody-simms-7th-november-2022")
    private static func showAndEpisodeAlias(from url: String) -> (show: String, alias: String)? {
        let parts = url.split(separator: "/").map(String.init)
        guard let i = parts.firstIndex(of: "shows"), parts.count > i + 3, parts[i + 2] == "episodes" else { return nil }
        return (parts[i + 1], parts[i + 3])
    }

    private static func fetchData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw URLError(.badServerResponse) }
        return data
    }

    // MARK: - Episodes

    private struct EpisodeJSON: Decodable {
        let name: String?
        let broadcast: String?
        let episode_alias: String?
    }
    private struct EpisodesEnvelope: Decodable { let results: [EpisodeJSON] }

    private static func fetchEpisodes(show: String, limit: Int) async throws -> [EpisodeJSON] {
        let url = URL(string: "https://www.nts.live/api/v2/shows/\(show)/episodes?offset=0&limit=\(limit)")!
        let data = try await fetchData(url)
        return try JSONDecoder().decode(EpisodesEnvelope.self, from: data).results
    }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "2022-11-06T22:00:00Z" -> "6 Nov 2022"
    private static func parseBroadcastDate(_ broadcast: String) -> String? {
        let prefix = broadcast.prefix(10)
        let parts = prefix.split(separator: "-").map(String.init)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month) else { return nil }
        return "\(day) \(months[month - 1]) \(year)"
    }
}

/// Deterministic RNG so repeated runs sample the same shows for a stable
/// number to report, even though the underlying sitemap can drift day to day.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
