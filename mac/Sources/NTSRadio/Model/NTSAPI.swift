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

    private struct Response: Decodable {
        let results: [Result]
        struct Result: Decodable {
            let channel_name: String?
            let now: Broadcast?
        }
        struct Broadcast: Decodable {
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
        }
        struct Genre: Decodable { let value: String? }
        struct Media: Decodable { let background_large: String? }
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
    }

    private struct MixtapeResponse: Decodable {
        let results: [Entry]
        struct Entry: Decodable {
            let mixtape_alias: String
            let title: String?
            let subtitle: String?
            let audio_stream_endpoint_hls_aac: String?
            let media: Media?
        }
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
                animationThumb: e.media?.animation_thumb
            )
        }
    }

    static func live() async throws -> [LiveUpdate] {
        let url = URL(string: "https://www.nts.live/api/v2/live")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(Response.self, from: data)

        return decoded.results.compactMap { r -> LiveUpdate? in
            guard let chName = r.channel_name, let ch = Int(chName), let now = r.now else { return nil }
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

    private static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? isoPlain.date(from: s)
    }

    private static func timeRange(_ start: String?, _ end: String?) -> String {
        guard let s = parse(start), let e = parse(end) else { return "" }
        return "\(hhmm.string(from: s)) – \(hhmm.string(from: e))"
    }
}
