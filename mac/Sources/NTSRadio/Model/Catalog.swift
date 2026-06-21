import SwiftUI

// MARK: - Mixtape

struct Mixtape: Identifiable, Hashable {
    let alias: String
    let title: String
    let subtitle: String
    let streamURL: URL
    let coverURL: URL?   // local cached colour cover (dial wedge)
    let iconURL: URL?    // local cached monochrome symbol (ring icon)
    let hue: Double      // accent hue, matching the prototype where it had one

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

    var id: Int { number }

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

@MainActor
final class Catalog {
    let mixtapes: [Mixtape]
    var channels: [Channel]

    static let shared = Catalog()

    /// Per-alias accent hues. First 10 match the prototype's `MIX` hues; the
    /// remaining 6 are assigned across the wheel.
    private static let hues: [String: Double] = [
        "poolside": 195, "slow-focus": 275, "low-key": 35, "memory-lane": 50,
        "4-to-the-floor": 330, "island-time": 140, "the-tube": 210, "sheet-music": 18,
        "feelings": 350, "expansions": 45,
        "rap-house": 285, "labyrinth": 255, "sweat": 15, "otaku": 320,
        "the-pit": 0, "field-recordings": 110,
    ]

    init() {
        self.mixtapes = Catalog.loadMixtapes()
        self.channels = [
            Channel(number: 1, artHue: 235, accent: Theme.ch1, accentText: Theme.ch1Text, city: "LONDON"),
            Channel(number: 2, artHue: 22,  accent: Theme.ch2, accentText: Theme.ch2Text, city: "LOS ANGELES"),
        ]
    }

    /// Where the mixtape catalog lives. In a packaged `.app` it's bundled into
    /// Resources/mixtapes (portable); in dev (`swift run`) it resolves to the
    /// repo's mixtapes/ dir relative to this source file.
    static var mixtapesDir: URL {
        let fm = FileManager.default
        if let res = Bundle.main.resourceURL?.appendingPathComponent("mixtapes"),
           fm.fileExists(atPath: res.appendingPathComponent("manifest.json").path) {
            return res
        }
        return URL(fileURLWithPath: #filePath)      // .../mac/Sources/NTSRadio/Model/Catalog.swift
            .deletingLastPathComponent()            // Model
            .deletingLastPathComponent()            // NTSRadio
            .deletingLastPathComponent()            // Sources
            .deletingLastPathComponent()            // mac
            .deletingLastPathComponent()            // repo root
            .appendingPathComponent("mixtapes")
    }

    private struct ManifestEntry: Decodable {
        let alias: String
        let title: String
        let subtitle: String
        let stream: Stream
        struct Stream: Decodable { let hls_aac: String; let hls_mp3: String }
    }

    private static func loadMixtapes() -> [Mixtape] {
        let dir = mixtapesDir
        let manifestURL = dir.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([ManifestEntry].self, from: data)
        else { return [] }

        return entries.compactMap { e in
            guard let stream = URL(string: e.stream.hls_aac) else { return nil }
            let mdir = dir.appendingPathComponent(e.alias)
            let cover = mdir.appendingPathComponent("cover_large.jpeg")
            let icon  = mdir.appendingPathComponent("icon_white.png")
            let fm = FileManager.default
            return Mixtape(
                alias: e.alias,
                title: e.title,
                subtitle: e.subtitle,
                streamURL: stream,
                coverURL: fm.fileExists(atPath: cover.path) ? cover : nil,
                iconURL:  fm.fileExists(atPath: icon.path)  ? icon  : nil,
                hue: hues[e.alias] ?? 200
            )
        }
    }
}
