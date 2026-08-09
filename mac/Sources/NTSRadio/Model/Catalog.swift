import SwiftUI

// MARK: - Mixtape

struct Mixtape: Identifiable, Hashable {
    let alias: String
    let title: String
    let subtitle: String
    let streamURL: URL
    let coverURL: URL?      // remote still (picture_large) — wedge poster
    let iconURL: URL?       // remote monochrome symbol (ring icon)
    let animationURL: URL?  // remote looping mp4 — played in wedge when active
    let hue: Double         // accent hue, matching the prototype where it had one

    var id: String { alias }
    var accent: Color { Color(h: hue, s: 68, l: 54) }
}

// MARK: - Live channel

struct Channel: Identifiable, Hashable {
    let number: Int          // 1 or 2
    let artHue: Double
    let accent: Color
    let accentText: Color

    // Live now-playing — populated by NTSAPI; seeded empty.
    var city: String = "—"
    var show: String = "NTS LIVE"
    var host: String = ""
    var genre: String = ""
    var startEnd: String = ""
    var background: URL? = nil   // current program's full-bleed artwork
    // Aliases for the current broadcast, used to link the show title to its
    // nts.live episode page (empty when the live feed didn't supply them).
    var showAlias: String = ""
    var episodeAlias: String = ""

    var id: Int { number }

    /// The nts.live episode page for the current broadcast, when the feed gave us
    /// the aliases — lets the show title act as a link.
    var episodeURL: URL? {
        guard !showAlias.isEmpty, !episodeAlias.isEmpty else { return nil }
        return URL(string: "https://www.nts.live/shows/\(showAlias)/episodes/\(episodeAlias)")
    }

    var streamURL: URL {
        URL(string: number == 1
            ? "https://stream-relay-geo.ntslive.net/stream?client=NTSWebApp"
            : "https://stream-relay-geo.ntslive.net/stream2?client=NTSWebApp")!
    }

    /// Procedural cover-art gradient, matching the prototype's `channelArt(h)`.
    var art: some View {
        ZStack {
            Color(h: artHue, s: 60, l: 9)
            RadialGradient(colors: [Color(h: (artHue + 34).truncatingRemainder(dividingBy: 360), s: 86, l: 56, opacity: 0.92), .clear],
                           center: UnitPoint(x: 0.28, y: 0.18), startRadius: 0, endRadius: 180)
            RadialGradient(colors: [Color(h: (artHue + 318).truncatingRemainder(dividingBy: 360), s: 82, l: 46, opacity: 0.85), .clear],
                           center: UnitPoint(x: 0.82, y: 0.88), startRadius: 0, endRadius: 160)
            LinearGradient(colors: [Color(h: artHue, s: 72, l: 30), Color(h: artHue, s: 78, l: 11)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Catalog

/// The dial's contents. Observable so that a change announces itself — the
/// live-channel poll and the mixtape refresh both rewrite these in place, and
/// everything downstream (the views, the system now-playing tile) has to hear
/// about it. Before this was observable each writer had to remember to notify
/// by hand, and a forgotten call showed up as a stale show name on screen.
@MainActor
final class Catalog: ObservableObject {
    /// Populated dynamically from the NTS catalog endpoint (seeded from the
    /// on-disk cache for instant/offline first paint, then refreshed live).
    @Published var mixtapes: [Mixtape]
    @Published var channels: [Channel]

    static let shared = Catalog()

    /// Per-alias accent hues, kept as overrides for the known mixtapes. Any
    /// alias not listed here gets a fallback hue distributed around the wheel.
    private static let hues: [String: Double] = [
        "poolside": 195, "slow-focus": 275, "100-percent-hip-hop": 35, "memory-lane": 50,
        "4-to-the-floor": 330, "island-time": 140, "the-tube": 210, "sheet-music": 18,
        "feelings": 350, "expansions": 45,
        "rap-house": 285, "labyrinth": 255, "sweat": 15, "otaku": 320,
        "the-pit": 0, "field-recordings": 110,
    ]

    init() {
        self.mixtapes = []   // filled by AppModel: cache seed → live refresh
        self.channels = [
            Channel(number: 1, artHue: 235, accent: Theme.ch1, accentText: Theme.ch1Text, city: "LONDON"),
            Channel(number: 2, artHue: 22,  accent: Theme.ch2, accentText: Theme.ch2Text, city: "LOS ANGELES"),
        ]
    }

    /// Map a fetched (or cached) feed into the in-memory catalog. Entries with
    /// an unparseable stream URL are dropped; unknown aliases get a hue spread
    /// evenly across the wheel by position.
    static func build(from feed: [NTSAPI.MixtapeFeed]) -> [Mixtape] {
        let n = feed.count
        return feed.enumerated().compactMap { i, e in
            guard let stream = URL(string: e.streamURL) else { return nil }
            let fallbackHue = Double(i) * 360.0 / Double(n)   // n >= 1 inside this closure
            return Mixtape(
                alias: e.alias,
                title: e.title,
                subtitle: e.subtitle,
                streamURL: stream,
                coverURL: e.pictureLarge.flatMap { URL(string: $0) },
                iconURL: e.iconWhite.flatMap { URL(string: $0) },
                animationURL: (e.animationLarge ?? e.animationThumb).flatMap { URL(string: $0) },
                hue: hues[e.alias] ?? fallbackHue
            )
        }
    }
}
