import Foundation

/// Minimal client for NTS's public live endpoint. Best-effort + defensive:
/// every field is optional, and anything that doesn't parse is just omitted.
enum NTSAPI {
    struct LiveUpdate {
        let channel: Int
        let show: String
        let startEnd: String
        let genre: String
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
        struct Details: Decodable { let genres: [Genre]? }
        struct Genre: Decodable { let value: String? }
    }

    static func live() async throws -> [LiveUpdate] {
        let url = URL(string: "https://www.nts.live/api/v2/live")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(Response.self, from: data)

        return decoded.results.compactMap { r -> LiveUpdate? in
            guard let chName = r.channel_name, let ch = Int(chName), let now = r.now else { return nil }
            let show = now.broadcast_title ?? ""
            let genre = now.embeds?.details?.genres?.first?.value ?? ""
            let startEnd = timeRange(now.start_timestamp, now.end_timestamp)
            return LiveUpdate(channel: ch, show: show, startEnd: startEnd, genre: genre)
        }
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
