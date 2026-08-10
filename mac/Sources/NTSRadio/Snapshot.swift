import SwiftUI
import AppKit

/// Headless render of each popover state to PNG, for visual verification /
/// regression against the prototype screenshots. Triggered by
/// `NTS_SNAPSHOT=<dir> swift run`. Not part of the shipping app.
@MainActor
enum Snapshot {
    static func run(dir: String) {
        let base = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        func shot(_ name: String, _ configure: (AppModel) -> Void) {
            let model = AppModel()
            configure(model)
            // Match the app's default window content size; the top bar's
            // traffic-light gap renders empty here (no real lights offscreen).
            let view = PopoverView()
                .environmentObject(model)
                .environmentObject(model.auth)
                .frame(width: 880, height: 720)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let img = renderer.nsImage,
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { print("snapshot failed: \(name)"); return }
            try? png.write(to: base.appendingPathComponent(name))
            print("wrote \(name)")
        }

        // Sample mixtape + tracklist matching the prototype's data, so the
        // tracklist surface renders with content for a faithful diff.
        let sampleMix = Mixtape(
            alias: "rap-house", title: "Rap House", subtitle: "808s and champagne.",
            streamURL: URL(string: "https://example.com/s")!,
            coverURL: nil, iconURL: nil, animationURL: nil, hue: 285,
            credits: [
                NTSAPI.MixtapeCredit(name: "Danny Brown", alias: "danny-brown"),
                NTSAPI.MixtapeCredit(name: "DJ Spanish Fly", alias: "dj-spanish-fly"),
                NTSAPI.MixtapeCredit(name: "Access Denied", alias: "access-denied"),
            ])
        let sampleTracks = [
            Track(time: "21:05", title: "Champagne", artist: "Clams Casino", hue: 285),
            Track(time: "21:00", title: "808 Heart", artist: "Metro Boomin", hue: 285),
            Track(time: "20:55", title: "Drip", artist: "Gunna", hue: 285),
        ]

        // Seed live-channel show + time so the cards render with content (the
        // snapshot has no network), matching the prototype's sample data.
        func seedChannels(_ m: AppModel) {
            if m.catalog.channels.count >= 2 {
                m.catalog.channels[0].show = "Low Slung Transmission"
                m.catalog.channels[0].startEnd = "17:00 – 19:00"
                m.catalog.channels[1].show = "Desert Frequency Hour"
                m.catalog.channels[1].startEnd = "09:00 – 11:00"
            }
        }

        // Seed a sample mixtape catalog so the dial ring renders (no network in
        // the snapshot). Icons come from the CDN, so spokes are positioned but
        // their symbols don't load here — the ring layout + hub still verify.
        func seedMixtapes(_ m: AppModel) {
            let names = ["Poolside", "Slow Focus", "100% Hip Hop", "Island Time",
                         "4 To The Floor", "Memory Lane", "The Pit", "Sheet Music",
                         "Feelings", "Expansions", "Rap House", "Labyrinth"]
            m.catalog.mixtapes = names.enumerated().map { i, n in
                Mixtape(alias: n.lowercased().replacingOccurrences(of: " ", with: "-"),
                        title: n, subtitle: "", streamURL: URL(string: "https://example.com/s")!,
                        coverURL: nil, iconURL: nil, animationURL: nil,
                        hue: Double(i) * 360 / 12, credits: [])
            }
        }

        // Default launch state is now idle — nothing selected (empty center, idle
        // now-playing bar). This shot verifies that empty state.
        shot("01-default-mix-dial.png") { seedChannels($0); seedMixtapes($0) }
        shot("02-channel1-live.png") { seedChannels($0); seedMixtapes($0); $0.select(.channel(1)) }
        shot("03-tracklist.png") {
            $0.catalog.mixtapes = [sampleMix]
            $0.select(.mixtape("rap-house"))
            $0.tracks = sampleTracks
            $0.showTracks = true
        }
        shot("04-settings.png") { seedChannels($0); seedMixtapes($0); $0.settingsOpen = true }
        shot("05-login.png") { seedChannels($0); seedMixtapes($0); $0.loginOpen = true }
        // The catalog is deliberately not snapshotted. `ImageRenderer` lays a
        // `ScrollView` out at zero height and never materialises a `LazyVGrid`, so
        // every catalog state renders as an empty pane — a picture of nothing that
        // reads as a broken screen. It is verified by capturing the real window
        // instead (`screencapture -l <windowNumber>`).

        exit(0)
    }
}
