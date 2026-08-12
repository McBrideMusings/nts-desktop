import Foundation

/// Minimal client for nts.live's public API — the schedule grid, shows and
/// episodes, the mixtape catalog, Explore. Best-effort + defensive: every field
/// is optional, and anything that doesn't parse is just omitted.
enum NTSAPI {

    // MARK: - Requests

    enum APIError: LocalizedError {
        /// nts.live answered, but not with what was asked for.
        case http(Int)
        /// nts.live answered 200 with a body this app can't read.
        case malformed
        case noAudio
        case tokenMissing

        var errorDescription: String? {
            switch self {
            case .http(let code):  return "nts.live answered HTTP \(code)."
            case .malformed:       return "nts.live sent something this app couldn’t read."
            case .noAudio:         return "This episode has no audio on NTS."
            case .tokenMissing:    return "Could not read nts.live’s stream token."
            }
        }
    }

    /// Every request to nts.live goes through here.
    ///
    /// Not for tidiness: each call site used to swallow its own error with
    /// `try?`, so a schedule that had silently stopped refreshing was
    /// indistinguishable from one where nothing had changed. Funnelling them
    /// means each failure is logged once and reported to `ServiceStatus` once,
    /// and callers keep deciding for themselves whether to carry on with stale
    /// data — they just can't do it silently any more.
    ///
    /// `endpoint` is the short name the banner and the log use, not a URL.
    private static func fetch<T: Decodable>(_ type: T.Type,
                                            from url: URL,
                                            endpoint: String,
                                            headers: [String: String] = [:]) async throws -> T {
        let data = try await fetchData(from: url, endpoint: endpoint, headers: headers)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            await ServiceStatus.shared.failed(endpoint, APIError.malformed)
            throw APIError.malformed
        }
    }

    private static func fetchData(from url: URL,
                                  endpoint: String,
                                  headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw APIError.http(code) }
            Log.api.debug("\(endpoint, privacy: .public) ok, \(data.count) bytes")
            await ServiceStatus.shared.succeeded(endpoint)
            return data
        } catch {
            await ServiceStatus.shared.failed(endpoint, error)
            throw error
        }
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
        let decoded = try await fetch(MixtapeResponse.self, from: url, endpoint: "mixtapes")

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
        let decoded = try await fetch(ScheduleResponse.self, from: url, endpoint: "schedule")

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
        let metadata: Metadata?
        struct Metadata: Decodable {
            let resultset: Resultset?
            struct Resultset: Decodable { let count: Int? }
        }
    }

    private struct ShowJSON: Decodable {
        let show_alias: String?
        let episode_alias: String?
        let name: String?
        let description: String?
        let location_short: String?
        /// "London" against `location_short`'s "LDN". The rail has room for the
        /// spelt-out city and nts.live shows that form, so it is preferred where
        /// NTS supplies it.
        let location_long: String?
        let genres: [Tag]?
        let moods: [Tag]?
        /// NTS writes a genre or mood as `{"id": …, "value": "Ambient"}`.
        struct Tag: Decodable { let value: String? }
        let media: Media?
        let broadcast: String?
        let external_links: [String]?
        let audio_sources: [AudioSource]?
        let embeds: Embeds?
        struct AudioSource: Decodable { let url: String? }
        /// A past episode's tracklist, when NTS has one on file — the same data
        /// nts.live's own "Tracklist" tab reads. Absent for a lot of older or
        /// unidentified episodes, present for anything Shazam-style track ID has
        /// run against; `EpisodeDetail` treats a missing one as an empty list
        /// rather than a failure.
        struct Embeds: Decodable {
            let tracklist: Tracklist?
            struct Tracklist: Decodable { let results: [TrackJSON]? }

            /// When an episode has no identified tracks NTS writes
            /// `"tracklist": []` — a bare array where the populated case is an
            /// object — and that includes every episode still on air. Decoding
            /// it strictly threw and took the whole episode with it, so the
            /// tracklist is read leniently: unreadable means no tracklist, not
            /// a failed request.
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                tracklist = try? c.decodeIfPresent(Tracklist.self, forKey: .tracklist)
            }
            private enum CodingKeys: String, CodingKey { case tracklist }
        }
        struct TrackJSON: Decodable {
            let artist: String?
            let title: String?
            let offset: Double?
        }
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

    /// Every show NTS publishes, from its own sitemap.
    ///
    /// This replaces walking `/api/v2/shows`, which clamps `limit` to 12 and
    /// answers `422 Unprocessable Entity: The requested offset is not allowed`
    /// past `offset=1000` — 85 requests to reach 1012 of them, with the rest
    /// simply unreachable. The sitemap is the same catalogue with no ceiling:
    /// 1,834 aliases, ~1.9MB gzipped, three requests including the index that
    /// names the parts.
    ///
    /// The files are served with `Content-Encoding: gzip`, so URLSession
    /// decompresses them on the way in and this only ever sees XML.
    static func sitemapShowAliases() async throws -> [String] {
        let index = try await fetchData(from: URL(string: "https://www.nts.live/sitemap.xml.gz")!,
                                        endpoint: "sitemap")
        let parts = locations(in: index).filter { $0.hasSuffix(".xml.gz") }

        var aliases: Set<String> = []
        for part in parts {
            guard let url = URL(string: part) else { continue }
            let data = try await fetchData(from: url, endpoint: "sitemap")
            for location in locations(in: data) {
                // `/shows/<alias>` and `/shows/<alias>/episodes/<episode>` both
                // name the show; only the first segment is wanted.
                let parts = location.split(separator: "/").map(String.init)
                guard let i = parts.firstIndex(of: "shows"), parts.count > i + 1 else { continue }
                aliases.insert(parts[i + 1])
            }
        }
        return aliases.sorted()
    }

    /// Every `<loc>` in a sitemap, without pulling in an XML parser for two tags.
    private static func locations(in data: Data) -> [String] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        return xml.components(separatedBy: "<loc>").dropFirst().compactMap {
            $0.components(separatedBy: "</loc>").first
        }
    }

    /// The newest episodes NTS has published, newest broadcast first.
    ///
    /// This is what covers the gap the sitemap cannot: it is regenerated about
    /// daily, so today's shows are missing from it while they are already here.
    static func recentlyAdded(limit: Int = 24) async throws -> [EpisodeCard] {
        let url = URL(string: "https://www.nts.live/api/v2/collections/recently-added?offset=0&limit=\(limit)")!
        let decoded = try await fetch(ShowEnvelope.self, from: url, endpoint: "recently-added")
        return decoded.results.compactMap { e -> EpisodeCard? in
            guard let show = e.show_alias, !show.isEmpty else { return nil }
            return EpisodeCard(
                showAlias: show,
                episodeAlias: e.episode_alias ?? "",
                title: decodeEntities(e.name ?? show).trimmingCharacters(in: .whitespaces),
                date: e.broadcast.flatMap(parse).map { dayMonthYear.string(from: $0) } ?? "",
                location: e.location_short ?? "",
                genres: (e.genres ?? []).compactMap { $0.value }.map(decodeEntities),
                image: e.picture.flatMap { URL(string: $0) }
            )
        }
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
        let s = try await fetch(ShowJSON.self, from: url, endpoint: "show")
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

    /// One page of a show's episodes, oldest-broadcast-first-among-equals as
    /// nts.live orders them. `limit` is clamped to 12 by the server whatever is
    /// asked for, but unlike `/api/v2/shows` an offset past the end just answers
    /// with zero results rather than 422 — so `total` (from
    /// `metadata.resultset.count`) is how a caller knows when to stop paging.
    static func episodes(alias: String, offset: Int = 0, limit: Int = 12) async throws
        -> (episodes: [Episode], total: Int) {
        let url = URL(string: "https://www.nts.live/api/v2/shows/\(alias)/episodes?offset=\(offset)&limit=\(limit)")!
        let decoded = try await fetch(ShowEnvelope.self, from: url, endpoint: "episodes")
        let episodes = decoded.results.map { e in
            Episode(
                name: decodeEntities(e.name ?? "").trimmingCharacters(in: .whitespaces),
                date: e.broadcast.flatMap(parse).map { dayMonthYear.string(from: $0) } ?? "",
                alias: e.episode_alias ?? "",
                showAlias: alias,
                image: (e.thumb ?? e.picture).flatMap { URL(string: $0) }
            )
        }
        return (episodes, decoded.metadata?.resultset?.count ?? episodes.count)
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
        /// The city spelt out, when NTS gives it — `location` is the abbreviation.
        let locationLong: String
        let date: String
        let image: URL?
        let audioSources: [URL]
        /// Ordered by `offset`, earliest first — empty when NTS has no ID'd
        /// tracklist for this episode, which is common for older or spoken-word
        /// shows and is not an error.
        let tracklist: [EpisodeTrack]

        var pageURL: URL? {
            guard !showAlias.isEmpty, !episodeAlias.isEmpty else { return nil }
            return URL(string: "https://www.nts.live/shows/\(showAlias)/episodes/\(episodeAlias)")
        }
    }

    /// One row of a past episode's tracklist: who and what, and how far into the
    /// recording it starts — the offset is what lets a saved episode's tracklist
    /// highlight the same way a live one does, off the seek position instead of
    /// the live edge.
    struct EpisodeTrack: Hashable {
        let artist: String
        let title: String
        let offsetSeconds: Double
    }

    /// `reportAs` is the name a failure is filed under, which is what the outage
    /// banner turns into a sentence. It defaults to the play path — someone
    /// pressed play and got nothing — but the rail calls this in the background
    /// just to fetch the on-air programme's photograph, where the consequence is
    /// a blank tile and saying "this episode wouldn't start" is simply untrue.
    static func episode(show: String, episode: String,
                        reportAs endpoint: String = "episode") async throws -> EpisodeDetail {
        let url = URL(string: "https://www.nts.live/api/v2/shows/\(show)/episodes/\(episode)")!
        let e = try await fetch(ShowJSON.self, from: url, endpoint: endpoint)
        let tracklist = (e.embeds?.tracklist?.results ?? []).map {
            EpisodeTrack(artist: decodeEntities($0.artist ?? "").trimmingCharacters(in: .whitespaces),
                        title: decodeEntities($0.title ?? "").trimmingCharacters(in: .whitespaces),
                        offsetSeconds: $0.offset ?? 0)
        }
        return EpisodeDetail(
            showAlias: e.show_alias ?? show,
            episodeAlias: e.episode_alias ?? episode,
            name: decodeEntities(e.name ?? "").trimmingCharacters(in: .whitespaces),
            description: decodeEntities(e.description ?? ""),
            genres: (e.genres ?? []).compactMap { $0.value }.map { decodeEntities($0).trimmingCharacters(in: .whitespaces) },
            location: e.location_short ?? "",
            locationLong: e.location_long ?? "",
            date: e.broadcast.flatMap(parse).map { dayMonthYear.string(from: $0) } ?? "",
            image: (e.picture).flatMap { URL(string: $0) },
            audioSources: (e.audio_sources ?? []).compactMap { $0.url.flatMap(URL.init(string:)) },
            tracklist: tracklist
        )
    }

    // MARK: - Explore

    /// A mood, as NTS files them: ten of them, each with its own artwork.
    struct Mood: Identifiable, Hashable {
        let id: String
        let name: String
        let image: URL?
    }

    /// A primary genre and the subgenres filed under it. Twenty primaries carry
    /// 438 subgenres between them, which is why the picker is a drawer that
    /// opens one primary at a time rather than a wall of chips.
    struct Genre: Identifiable, Hashable {
        let id: String
        let name: String
        let subgenres: [Genre]
    }

    /// One episode as Explore returns it — everything a tile needs, plus the two
    /// aliases that make it playable.
    struct EpisodeCard: Identifiable, Hashable {
        let showAlias: String
        let episodeAlias: String
        let title: String
        let date: String
        let location: String
        let genres: [String]
        let image: URL?
        var id: String { "\(showAlias)/\(episodeAlias)" }
    }

    /// What Explore is asking for. Empty means "everything, newest first".
    struct ExploreFilters: Equatable {
        var mood: String?
        /// Ordered, because the chips read in the order they were picked.
        var genres: [String] = []
        /// nts.live's "Music Only". Not a flag of its own — a mood tag whose name
        /// they keep out of the mood list.
        var musicOnly = false
        /// nts.live's "Focused": episodes tagged with exactly as many genres as
        /// are selected, so a two-genre search returns shows that are only those
        /// two things rather than eclectic sets that happen to include them.
        var focused = false

        var isEmpty: Bool { mood == nil && genres.isEmpty && !musicOnly && !focused }

        /// The query as nts.live itself builds it.
        var queryItems: [URLQueryItem] {
            var items: [URLQueryItem] = []
            if focused {
                items.append(URLQueryItem(name: "genre_count", value: String(max(1, genres.count))))
            }
            if musicOnly { items.append(URLQueryItem(name: "moods[]", value: "no-talkin")) }
            for genre in genres { items.append(URLQueryItem(name: "genres[]", value: genre)) }
            if let mood { items.append(URLQueryItem(name: "moods[]", value: mood)) }
            return items
        }
    }

    private struct MoodResponse: Decodable {
        let results: [Entry]
        struct Entry: Decodable { let id: String?; let name: String?; let image: Image? }
        struct Image: Decodable { let medium: String?; let small: String?; let thumb: String? }
    }

    private struct GenreResponse: Decodable {
        let results: [Entry]
        struct Entry: Decodable { let id: String?; let name: String?; let subgenres: [Entry]? }
    }

    private struct ExploreResponse: Decodable {
        let metadata: Meta?
        let results: [Entry]
        struct Meta: Decodable { let resultset: Set?; struct Set: Decodable { let count: Int? } }
        struct Entry: Decodable {
            let title: String?
            let article: Article?
            let image: Image?
            let genres: [Tag]?
            let location: String?
            let local_date: String?
        }
        struct Article: Decodable { let path: String? }
        struct Tag: Decodable { let name: String? }
        struct Image: Decodable { let medium: String?; let small: String? }
    }

    static func moods() async throws -> [Mood] {
        let url = URL(string: "https://www.nts.live/api/v2/moods")!
        let decoded = try await fetch(MoodResponse.self, from: url, endpoint: "moods")
        return decoded.results.compactMap { m in
            guard let id = m.id else { return nil }
            return Mood(id: id,
                        name: decodeEntities(m.name ?? id),
                        image: (m.image?.medium ?? m.image?.small).flatMap { URL(string: $0) })
        }
    }

    static func genres() async throws -> [Genre] {
        let url = URL(string: "https://www.nts.live/api/v2/genres")!
        let decoded = try await fetch(GenreResponse.self, from: url, endpoint: "genres")
        return decoded.results.compactMap(genre)
    }

    private static func genre(_ e: GenreResponse.Entry) -> Genre? {
        guard let id = e.id else { return nil }
        return Genre(id: id,
                     name: decodeEntities(e.name ?? id),
                     subgenres: (e.subgenres ?? []).compactMap(genre))
    }

    /// One page of Explore. Twelve at a time, which is what the endpoint serves
    /// and what nts.live asks for.
    static let explorePageSize = 12

    static func explore(_ filters: ExploreFilters, offset: Int = 0) async throws -> (episodes: [EpisodeCard], total: Int) {
        var components = URLComponents(string: "https://www.nts.live/api/v2/search/episodes")!
        components.queryItems = [URLQueryItem(name: "offset", value: String(offset)),
                                 URLQueryItem(name: "limit", value: String(explorePageSize))]
            + filters.queryItems

        let decoded = try await fetch(ExploreResponse.self, from: components.url!, endpoint: "explore")
        let episodes = decoded.results.compactMap { e -> EpisodeCard? in
            let (show, episode) = episodeAliases(e.article?.path)
            guard !show.isEmpty, !episode.isEmpty else { return nil }
            return EpisodeCard(
                showAlias: show,
                episodeAlias: episode,
                title: decodeEntities(e.title ?? show).trimmingCharacters(in: .whitespaces),
                date: e.local_date ?? "",
                location: e.location ?? "",
                genres: (e.genres ?? []).compactMap { $0.name }.map(decodeEntities),
                image: (e.image?.medium ?? e.image?.small).flatMap { URL(string: $0) }
            )
        }
        return (episodes, decoded.metadata?.resultset?.count ?? episodes.count)
    }

    /// `/shows/<show>/episodes/<episode>` → both aliases.
    private static func episodeAliases(_ path: String?) -> (show: String, episode: String) {
        let parts = (path ?? "").split(separator: "/").map(String.init)
        guard let i = parts.firstIndex(of: "shows"), parts.count > i + 3, parts[i + 2] == "episodes"
        else { return ("", "") }
        return (parts[i + 1], parts[i + 3])
    }

    // MARK: - Playable streams

    /// Turn an episode's SoundCloud/Mixcloud page into a playable HLS URL.
    ///
    /// `/api/v2/resolve-stream` answers 401 without an `Authorization: Basic`
    /// header carrying the token nts.live ships in the HTML of every page — see
    /// `siteToken()`. The playlist it hands back is signed and expires, so it is
    /// resolved per play rather than cached.
    static func resolveStream(_ source: URL) async throws -> URL {
        do {
            return try await resolve(source, token: await siteToken())
        } catch APIError.http(401) {
            // The token rotated under us. Re-read it from the site and retry once
            // rather than making the user restart the app.
            Log.player.notice("resolve-stream 401 — re-reading the site token")
            cachedToken = nil
            return try await resolve(source, token: await siteToken())
        }
    }

    private struct Resolved: Decodable { let hls: String? }

    private static func resolve(_ source: URL, token: String) async throws -> URL {
        var components = URLComponents(string: "https://www.nts.live/api/v2/resolve-stream")!
        components.queryItems = [URLQueryItem(name: "url", value: source.absoluteString)]

        let resolved = try await fetch(Resolved.self, from: components.url!,
                                       endpoint: "resolve-stream",
                                       headers: ["Accept": "application/json",
                                                 "Authorization": "Basic \(token)"])
        guard let hls = resolved.hls, let url = URL(string: hls) else {
            await ServiceStatus.shared.failed("resolve-stream", APIError.malformed)
            throw APIError.malformed
        }
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
        let data = try await fetchData(from: URL(string: "https://www.nts.live/")!, endpoint: "site-token")
        guard let html = String(data: data, encoding: .utf8),
              let range = html.range(of: #""NTS_API_TOKEN":"[^"]+""#, options: .regularExpression),
              let token = html[range].split(separator: "\"").last.map(String.init)
        else {
            await ServiceStatus.shared.failed("site-token", APIError.tokenMissing)
            throw APIError.tokenMissing
        }
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
