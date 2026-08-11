import Foundation

/// Minimal client for NTS's public live endpoint. Best-effort + defensive:
/// every field is optional, and anything that doesn't parse is just omitted.
enum NTSAPI {
    struct LiveUpdate {
        let channel: Int
        let show: String
        let startEnd: String
        let genre: String
        let background: String?   // current program's full-bleed artwork
        let showAlias: String     // for linking the title to its episode page
        let episodeAlias: String
    }

    /// One programme slot on a channel, as published in NTS's own schedule.
    ///
    /// Every slot carries a real start and end and the aliases of the show and
    /// episode filling it, because it comes from `/api/v2/radio/schedule/N`
    /// rather than being scraped out of the now-playing payload.
    struct Broadcast: Hashable, Identifiable {
        let channel: Int
        let title: String
        let start: Date?
        let end: Date?
        let startEnd: String
        let genres: [String]
        let location: String
        /// Programme artwork. The schedule carries none, so this is nil and the
        /// row falls back to the show's own artwork, looked up by alias.
        let image: URL?
        let showAlias: String
        let episodeAlias: String

        var id: String { "\(channel)-\(startEnd)-\(showAlias)-\(title)" }

        var episodeURL: URL? {
            guard !showAlias.isEmpty, !episodeAlias.isEmpty else { return nil }
            return URL(string: "https://www.nts.live/shows/\(showAlias)/episodes/\(episodeAlias)")
        }
    }

    /// The now-playing feed. Only `now` is read: the response also carries
    /// `next` … `next17`, but those slots come from the schedule endpoint, which
    /// publishes fourteen days of them with the aliases attached.
    private struct Response: Decodable {
        let results: [Result]

        struct Result: Decodable {
            let channel_name: String?
            let now: Raw?
        }

        struct Raw: Decodable {
            let broadcast_title: String?
            let start_timestamp: String?
            let end_timestamp: String?
            let embeds: Embeds?
        }
        struct Embeds: Decodable { let details: Details? }
        struct Details: Decodable {
            let genres: [Genre]?
            let media: Media?
            let show_alias: String?
            let episode_alias: String?
            let location_short: String?
        }
        struct Genre: Decodable { let value: String? }
        struct Media: Decodable {
            let background_large: String?
            let background_medium_large: String?
            let background_small: String?
        }
    }

    // MARK: - Infinite mixtapes

    /// One mixtape as served by NTS's public catalog endpoint. Codable so the
    /// fetched feed can be cached to disk for instant/offline first paint.
    struct MixtapeFeed: Codable {
        let alias: String
        let title: String
        let subtitle: String
        let streamURL: String
        let pictureLarge: String?
        let iconWhite: String?
        let animationLarge: String?
        let animationThumb: String?
        /// The shows feeding this mixtape. Optional so a cache written before this
        /// field existed still decodes — losing it would blank the dial on the
        /// first offline launch after an update.
        let credits: [MixtapeCredit]?
    }

    /// A show credited on a mixtape. The alias comes from the `path` NTS returns
    /// (`/shows/all-styles-all-smiles`), which is what makes a credit a link into
    /// the show rather than a dead label.
    struct MixtapeCredit: Codable, Hashable, Identifiable {
        let name: String
        let alias: String
        var id: String { alias.isEmpty ? name : alias }
    }

    private struct MixtapeResponse: Decodable {
        let results: [Entry]
        struct Entry: Decodable {
            let mixtape_alias: String
            let title: String?
            let subtitle: String?
            let audio_stream_endpoint_hls_aac: String?
            let media: Media?
            let credits: [Credit]?
        }
        struct Credit: Decodable { let name: String?; let path: String? }
        struct Media: Decodable {
            let picture_large: String?
            let icon_white: String?
            let animation_large_landscape: String?
            let animation_thumb: String?
        }
    }

    /// Fetch the live infinite-mixtapes catalog. Entries without a usable stream
    /// URL are dropped; everything else is best-effort optional.
    static func mixtapes() async throws -> [MixtapeFeed] {
        let url = URL(string: "https://www.nts.live/api/v2/mixtapes")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(MixtapeResponse.self, from: data)

        return decoded.results.compactMap { e -> MixtapeFeed? in
            guard let stream = e.audio_stream_endpoint_hls_aac else { return nil }
            return MixtapeFeed(
                alias: e.mixtape_alias,
                title: e.title ?? e.mixtape_alias,
                subtitle: e.subtitle ?? "",
                streamURL: stream,
                pictureLarge: e.media?.picture_large,
                iconWhite: e.media?.icon_white,
                animationLarge: e.media?.animation_large_landscape,
                animationThumb: e.media?.animation_thumb,
                credits: (e.credits ?? []).compactMap { c in
                    guard let name = c.name else { return nil }
                    let alias = (c.path ?? "").hasPrefix("/shows/")
                        ? String((c.path ?? "").dropFirst("/shows/".count)) : ""
                    return MixtapeCredit(name: decodeEntities(name), alias: alias)
                }
            )
        }
    }

    static func live() async throws -> [LiveUpdate] {
        let url = URL(string: "https://www.nts.live/api/v2/live")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(Response.self, from: data)

        return decoded.results.compactMap { r -> LiveUpdate? in
            guard let chName = r.channel_name, let ch = Int(chName),
                  let now = r.now else { return nil }
            let details = now.embeds?.details
            let show = decodeEntities(now.broadcast_title ?? "")
            let genre = decodeEntities(details?.genres?.first?.value ?? "")
            let startEnd = timeRange(now.start_timestamp, now.end_timestamp)
            let background = details?.media?.background_large
            return LiveUpdate(
                channel: ch, show: show, startEnd: startEnd, genre: genre, background: background,
                showAlias: details?.show_alias ?? "", episodeAlias: details?.episode_alias ?? ""
            )
        }
    }

    // MARK: - Schedule

    /// NTS's published programme grid for one channel: fourteen days of slots,
    /// each with a real start and end and a link naming the episode filling it.
    private struct ScheduleResponse: Decodable {
        let results: [Day]
        struct Day: Decodable {
            let date: String?
            let broadcasts: [Slot]?
        }
        struct Slot: Decodable {
            let broadcast_title: String?
            let start_timestamp: String?
            let end_timestamp: String?
            let links: [Link]?
        }
        struct Link: Decodable {
            let href: String?
            let rel: String?
        }
    }

    /// Fetch a channel's programme grid — fourteen days, roughly sixteen slots a
    /// day, every one of them named and timed.
    ///
    /// This is the whole schedule, not the eighteen slots `/api/v2/live` carries,
    /// and it names the show and episode on every slot rather than only the first
    /// two — so nothing here has to be matched back to a show by its title.
    /// Genres, location and artwork are not in this payload; they come from the
    /// show index, keyed by the alias each slot supplies.
    static func schedule(channel: Int) async throws -> [Broadcast] {
        let url = URL(string: "https://www.nts.live/api/v2/radio/schedule/\(channel)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(ScheduleResponse.self, from: data)

        return decoded.results.flatMap { day -> [Broadcast] in
            (day.broadcasts ?? []).map { slot in
                let (show, episode) = aliases(slot.links)
                return Broadcast(
                    channel: channel,
                    title: decodeEntities(slot.broadcast_title ?? ""),
                    start: parse(slot.start_timestamp),
                    end: parse(slot.end_timestamp),
                    startEnd: timeRange(slot.start_timestamp, slot.end_timestamp),
                    genres: [],
                    location: "",
                    image: nil,
                    showAlias: show,
                    episodeAlias: episode
                )
            }
        }
    }

    /// The show and episode aliases carried by a slot's `details` link, whose
    /// href is `…/api/v2/shows/<show>/episodes/<episode>`. Empty strings when the
    /// link is missing or shaped differently — a slot without them still renders,
    /// it just can't be opened.
    private static func aliases(_ links: [ScheduleResponse.Link]?) -> (show: String, episode: String) {
        guard let href = (links ?? []).first(where: { $0.rel == "details" })?.href,
              let path = URLComponents(string: href)?.path else { return ("", "") }
        let parts = path.split(separator: "/").map(String.init)
        guard let i = parts.firstIndex(of: "shows"), parts.count > i + 1 else { return ("", "") }
        let episode = (parts.count > i + 3 && parts[i + 2] == "episodes") ? parts[i + 3] : ""
        return (parts[i + 1], episode)
    }

    // MARK: - Shows

    /// One show in the searchable index. Codable so the index survives relaunch —
    /// building it costs ~85 requests, which is not something to repeat on launch.
    struct ShowRef: Codable, Hashable, Identifiable {
        let alias: String
        let name: String
        let location: String
        let genres: [String]
        let picture: String?
        let thumb: String?
        var id: String { alias }

        var pictureURL: URL? { picture.flatMap { URL(string: $0) } }
        var thumbURL: URL? { (thumb ?? picture).flatMap { URL(string: $0) } }
        var pageURL: URL? { URL(string: "https://www.nts.live/shows/\(alias)") }
        /// Everything a query is matched against, lowercased once at build time.
        var haystack: String { "\(name) \(location) \(genres.joined(separator: " "))".lowercased() }
    }

    /// A show's own page: the host blurb, its genres and moods, its artwork.
    struct ShowDetail {
        let alias: String
        let name: String
        let description: String
        let genres: [String]
        let moods: [String]
        let location: String
        let image: URL?
        let links: [URL]
    }

    struct Episode: Identifiable, Hashable {
        let name: String
        let date: String
        let alias: String
        let showAlias: String
        let image: URL?
        var id: String { alias.isEmpty ? name : alias }
        var pageURL: URL? {
            guard !showAlias.isEmpty, !alias.isEmpty else { return nil }
            return URL(string: "https://www.nts.live/shows/\(showAlias)/episodes/\(alias)")
        }
    }

    private struct ShowEnvelope: Decodable {
        let results: [ShowJSON]
    }

    private struct ShowJSON: Decodable {
        let show_alias: String?
        let episode_alias: String?
        let name: String?
        let description: String?
        let location_short: String?
        let genres: [Response.Genre]?
        let moods: [Response.Genre]?
        let media: Media?
        let broadcast: String?
        let external_links: [String]?
        let audio_sources: [AudioSource]?
        struct AudioSource: Decodable { let url: String? }
        struct Media: Decodable {
            let picture_medium_large: String?
            let picture_medium: String?
            let picture_small: String?
            let picture_thumb: String?
            let background_medium_large: String?
            let background_large: String?
        }
        var picture: String? { media?.picture_medium_large ?? media?.picture_medium
            ?? media?.background_medium_large ?? media?.background_large }
        var thumb: String? { media?.picture_small ?? media?.picture_thumb ?? picture }
    }

    /// `offset` past this returns HTTP 422, so the shows endpoint only exposes the
    /// first 1012 of the 1733 shows it reports. The index is capped accordingly and
    /// the catalog states its own size rather than implying it covers everything.
    static let showIndexCeiling = 1000
    /// The endpoint clamps `limit` to 12 whatever you ask for, so paging is fixed
    /// at 12 and the ceiling above costs ~85 requests to walk.
    static let showPageSize = 12

    /// One page of the show list.
    static func showPage(offset: Int) async throws -> [ShowRef] {
        let url = URL(string: "https://www.nts.live/api/v2/shows?offset=\(offset)&limit=\(showPageSize)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(ShowEnvelope.self, from: data)
        return decoded.results.compactMap(showRef)
    }

    private static func showRef(_ s: ShowJSON) -> ShowRef? {
        guard let alias = s.show_alias, !alias.isEmpty else { return nil }
        return ShowRef(
            alias: alias,
            name: decodeEntities(s.name ?? alias).trimmingCharacters(in: .whitespaces),
            location: s.location_short ?? "",
            genres: (s.genres ?? []).compactMap { $0.value }.map { decodeEntities($0).trimmingCharacters(in: .whitespaces) },
            picture: s.picture,
            thumb: s.thumb
        )
    }

    static func show(alias: String) async throws -> ShowDetail {
        let url = URL(string: "https://www.nts.live/api/v2/shows/\(alias)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let s = try JSONDecoder().decode(ShowJSON.self, from: data)
        return ShowDetail(
            alias: alias,
            name: decodeEntities(s.name ?? alias).trimmingCharacters(in: .whitespaces),
            description: decodeEntities(s.description ?? ""),
            genres: (s.genres ?? []).compactMap { $0.value }.map { decodeEntities($0).trimmingCharacters(in: .whitespaces) },
            moods: (s.moods ?? []).compactMap { $0.value }.map(decodeEntities),
            location: s.location_short ?? "",
            image: (s.picture).flatMap { URL(string: $0) },
            links: (s.external_links ?? []).compactMap { URL(string: $0) }
        )
    }

    static func episodes(alias: String, limit: Int = 12) async throws -> [Episode] {
        let url = URL(string: "https://www.nts.live/api/v2/shows/\(alias)/episodes?offset=0&limit=\(limit)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(ShowEnvelope.self, from: data)
        return decoded.results.map { e in
            Episode(
                name: decodeEntities(e.name ?? "").trimmingCharacters(in: .whitespaces),
                date: e.broadcast.flatMap(parse).map { dayMonthYear.string(from: $0) } ?? "",
                alias: e.episode_alias ?? "",
                showAlias: alias,
                image: (e.thumb ?? e.picture).flatMap { URL(string: $0) }
            )
        }
    }

    // MARK: - Episodes on demand

    /// A single episode: what it is, and where its audio actually lives.
    ///
    /// The audio is not an NTS URL — it is a SoundCloud or Mixcloud page, which
    /// AVPlayer cannot open. `resolveStream` turns one into a playable HLS
    /// playlist.
    struct EpisodeDetail {
        let showAlias: String
        let episodeAlias: String
        let name: String
        let description: String
        let genres: [String]
        let location: String
        let date: String
        let image: URL?
        let audioSources: [URL]

        var pageURL: URL? {
            guard !showAlias.isEmpty, !episodeAlias.isEmpty else { return nil }
            return URL(string: "https://www.nts.live/shows/\(showAlias)/episodes/\(episodeAlias)")
        }
    }

    static func episode(show: String, episode: String) async throws -> EpisodeDetail {
        let url = URL(string: "https://www.nts.live/api/v2/shows/\(show)/episodes/\(episode)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let e = try JSONDecoder().decode(ShowJSON.self, from: data)
        return EpisodeDetail(
            showAlias: e.show_alias ?? show,
            episodeAlias: e.episode_alias ?? episode,
            name: decodeEntities(e.name ?? "").trimmingCharacters(in: .whitespaces),
            description: decodeEntities(e.description ?? ""),
            genres: (e.genres ?? []).compactMap { $0.value }.map { decodeEntities($0).trimmingCharacters(in: .whitespaces) },
            location: e.location_short ?? "",
            date: e.broadcast.flatMap(parse).map { dayMonthYear.string(from: $0) } ?? "",
            image: (e.picture).flatMap { URL(string: $0) },
            audioSources: (e.audio_sources ?? []).compactMap { $0.url.flatMap(URL.init(string:)) }
        )
    }

    // MARK: - Playable streams

    enum StreamError: LocalizedError {
        case noAudio
        case tokenMissing
        case refused(Int)

        var errorDescription: String? {
            switch self {
            case .noAudio:          return "This episode has no audio on NTS."
            case .tokenMissing:     return "Could not read nts.live's stream token."
            case .refused(let code): return "nts.live refused the stream (HTTP \(code))."
            }
        }
    }

    /// Turn an episode's SoundCloud/Mixcloud page into a playable HLS URL.
    ///
    /// `/api/v2/resolve-stream` answers 401 without an `Authorization: Basic`
    /// header carrying the token nts.live ships in the HTML of every page — see
    /// `siteToken()`. The playlist it hands back is signed and expires, so it is
    /// resolved per play rather than cached.
    static func resolveStream(_ source: URL) async throws -> URL {
        do {
            return try await resolve(source, token: await siteToken())
        } catch StreamError.refused(401) {
            // The token rotated under us. Re-read it from the site and retry once
            // rather than making the user restart the app.
            cachedToken = nil
            return try await resolve(source, token: await siteToken())
        }
    }

    private static func resolve(_ source: URL, token: String) async throws -> URL {
        var components = URLComponents(string: "https://www.nts.live/api/v2/resolve-stream")!
        components.queryItems = [URLQueryItem(name: "url", value: source.absoluteString)]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw StreamError.refused(code) }

        struct Resolved: Decodable { let hls: String? }
        guard let hls = try JSONDecoder().decode(Resolved.self, from: data).hls,
              let url = URL(string: hls) else { throw StreamError.refused(code) }
        return url
    }

    private static var cachedToken: String?

    /// The API token nts.live embeds in every page it serves, as
    /// `"NTS_API_TOKEN":"…"`.
    ///
    /// It is read off the site rather than compiled in: it is their constant,
    /// not ours, and scraping it means a rotation costs one extra request
    /// instead of an app release. Held in memory only — a launch that never
    /// plays an episode never fetches it.
    private static func siteToken() async throws -> String {
        if let cachedToken { return cachedToken }
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://www.nts.live/")!)
        guard let html = String(data: data, encoding: .utf8),
              let range = html.range(of: #""NTS_API_TOKEN":"[^"]+""#, options: .regularExpression),
              let token = html[range].split(separator: "\"").last.map(String.init)
        else { throw StreamError.tokenMissing }
        cachedToken = token
        return token
    }

    /// Decode the handful of HTML entities NTS leaves in broadcast titles/genres
    /// (e.g. `&amp;` → `&`). Numeric entities (`&#39;`, `&#x27;`) are handled too.
    /// `&amp;` is unescaped last so `&amp;lt;` survives as `&lt;`.
    ///
    /// Deliberately a tiny hand-rolled table rather than a library: `NSAttributedString`
    /// HTML import is heavyweight and main-thread-only (wrong for a background decode of
    /// a one-line title), and pulling a parser dependency (SwiftSoup, etc.) is overkill
    /// for the few entities NTS actually emits in a plain-text title.
    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        // Numeric entities: &#123; (decimal) and &#x1F;/&#X1F; (hex). Resolve each
        // match independently against the original ranges (reversed, so earlier
        // ranges stay valid) — a single malformed/out-of-range token is left as-is
        // rather than abandoning every entity after it.
        if let re = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);", options: .caseInsensitive) {
            let ns = out as NSString
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed() {
                let hex = !ns.substring(with: m.range(at: 1)).isEmpty
                let digits = ns.substring(with: m.range(at: 2))
                guard let code = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) else { continue }
                out = (out as NSString).replacingCharacters(in: m.range, with: String(scalar))
            }
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()
    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dayMonthYear: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd MMM yyyy"; return f
    }()

    private static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? isoPlain.date(from: s)
    }

    private static func timeRange(_ start: String?, _ end: String?) -> String {
        guard let s = parse(start), let e = parse(end) else { return "" }
        return "\(hhmm.string(from: s)) – \(hhmm.string(from: e))"
    }
}
