import SwiftUI
import AppKit
import NTSChannel

/// Headless render of each popover state to PNG, for visual verification /
/// regression against the prototype screenshots. Triggered by
/// `NTS_SNAPSHOT=<dir> swift run`. Not part of the shipping app.
@MainActor
enum Snapshot {
    static func run(dir: String) {
        let base = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // Default window content size; the top bar's traffic-light gap renders
        // empty here (no real lights offscreen).
        /// Render any view to a PNG. The one place pixels are produced, so the
        /// scale and the failure message cannot drift between the popover shots
        /// and the settings ones.
        func shotView<V: View>(_ name: String, _ view: V) {
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

        // Every shot's settings live in a store of their own, emptied before the
        // first shot and deleted before exit, so a run starts from the code's
        // defaults and leaves the machine's real `live.nts.desktop` untouched.
        // Nothing here may touch `AppModel.shared`: making it starts Sparkle and
        // binds the real store.
        let store = UserDefaults(suiteName: snapshotSuite)!
        store.removePersistentDomain(forName: snapshotSuite)
        let prefs = Preferences(defaults: store, loginItem: NoLoginItem(), updates: NoUpdates())
        let account = NTSAuth.sample(email: "listener@example.com")

        func shot(_ name: String, size: CGSize = CGSize(width: 880, height: 720),
                  _ configure: (AppModel) -> Void) {
            let model = AppModel(preferences: prefs)
            configure(model)
            shotView(name, PopoverView()
                .environmentObject(model)
                .environmentObject(model.auth)
                .environmentObject(model.engine)
                .frame(width: size.width, height: size.height))
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
        // snapshot has no network), matching the prototype's sample data. The
        // rail reads the current programme off the grid, so the sample is a
        // grid — one slot per channel, ending an hour out so it stays on air.
        func seedChannels(_ m: AppModel) {
            func slot(_ n: ChannelNumber, _ title: String, _ startEnd: String, _ city: String) -> NTSAPI.Broadcast {
                NTSAPI.Broadcast(channel: n, title: title, start: Date(),
                                 end: Date().addingTimeInterval(3600), startEnd: startEnd,
                                 genres: [], location: city, image: nil,
                                 showAlias: "", episodeAlias: "")
            }
            m.catalog[.one].upcoming = [slot(.one, "Low Slung Transmission", "17:00 – 19:00", "LONDON")]
            m.catalog[.two].upcoming = [slot(.two, "Desert Frequency Hour", "09:00 – 11:00", "LOS ANGELES")]
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
        shot("02-channel1-live.png") { seedChannels($0); seedMixtapes($0); $0.select(.channel(.one), autoplay: false) }
        shot("03-tracklist.png") {
            $0.catalog.mixtapes = [sampleMix]
            $0.select(.mixtape("rap-house"), autoplay: false)
            $0.tracks = sampleTracks
            $0.tracksOpen = true
        }
        // Settings and the account are one real window now, so they are rendered
        // straight rather than through `PopoverView` — its own chrome is the
        // system's and is not this repo's to check, but the contents are.
        // Seeded account, not the real one: the pane reads its state off an
        // `NTSAuth`, and rendering it against the live one made this the only
        // shot in the set whose contents depended on who was signed in on the
        // machine — and the only one that wrote a real address into a PNG.
        for pane in SettingsPane.allCases {
            let selection = SettingsSelection()
            selection.pane = pane
            shotView("04-settings-\(pane.rawValue).png",
                     SettingsView(selection: selection, preferences: prefs, auth: account))
        }
        // The knob face only carries a title once a mixtape is selected, and the
        // longest names are the ones that reach the circle's edge — this is the
        // shot that shows whether they fit.
        shot("06-dial-face.png") { m in
            seedChannels(m); seedMixtapes(m)
            if let i = m.catalog.mixtapes.firstIndex(where: { $0.alias == "4-to-the-floor" }) {
                let t = m.catalog.mixtapes[i]
                m.catalog.mixtapes[i] = Mixtape(
                    alias: t.alias, title: t.title,
                    subtitle: "House, four to the floor, no let-up.",
                    streamURL: t.streamURL, coverURL: t.coverURL, iconURL: t.iconURL,
                    animationURL: t.animationURL, hue: t.hue, credits: t.credits)
            }
            m.select(.mixtape("4-to-the-floor"), autoplay: false)
        }

        // The rail's arrangement is decided by the window's proportions, so the
        // only way to see it is to render the same state at several sizes. These
        // three are the corners: the window's own minimum, a tall column, and a
        // wide letterbox.
        // The first three are the corners of what `RadioWindowController.minSize`
        // allows: as narrow as the window goes, as short, and both at once.
        let shapes: [(String, CGSize)] = [
            ("09-shape-smallest-340x230.png",  CGSize(width: 340, height: 230)),
            ("10-shape-narrow-340x582.png",    CGSize(width: 340, height: 582)),
            ("11-shape-short-547x230.png",     CGSize(width: 547, height: 230)),
            ("12-shape-tall-760x1040.png",     CGSize(width: 760, height: 1040)),
            ("13-shape-wide-1440x520.png",     CGSize(width: 1440, height: 520)),
        ]
        for (name, size) in shapes {
            shot(name, size: size) { seedChannels($0); seedMixtapes($0); $0.select(.channel(.one), autoplay: false) }
        }

        // The catalog is deliberately not snapshotted. `ImageRenderer` lays a
        // `ScrollView` out at zero height and never materialises a `LazyVGrid`, so
        // every catalog state renders as an empty pane — a picture of nothing that
        // reads as a broken screen. It is verified by capturing the real window
        // instead (`screencapture -l <windowNumber>`).

        // The General pane's volume row in each curve and each appearance. An
        // off-screen render has no window to take its appearance from, so the
        // colour scheme and a window-coloured ground are set by hand here. Last,
        // because it moves the gain and curve every shot above renders with.
        prefs.gain = 12
        for kind in VolumeCurve.Kind.allCases {
            for dark in [false, true] {
                prefs.curve.kind = kind
                let selection = SettingsSelection()
                shotView("04-settings-general-\(kind.rawValue)-\(dark ? "dark" : "light").png",
                         SettingsView(selection: selection, preferences: prefs, auth: account)
                            .background(Color(white: dark ? 0.16 : 0.93))
                            .environment(\.colorScheme, dark ? .dark : .light))
            }
        }

        // Emptying the domain leaves cfprefsd's empty plist on disk; flush, then
        // delete the file so the run leaves nothing in ~/Library/Preferences.
        store.removePersistentDomain(forName: snapshotSuite)
        CFPreferencesAppSynchronize(snapshotSuite as CFString)
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(snapshotSuite).plist")
        try? FileManager.default.removeItem(at: plist)
        exit(0)
    }

    private static let snapshotSuite = "live.nts.desktop.snapshot"
}

/// Launch-at-login for a run that must never register anything.
private struct NoLoginItem: LoginItem {
    var isAvailable: Bool { false }
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}

/// Update checks for a run that must never start Sparkle.
private final class NoUpdates: UpdateChecker {
    var automaticallyChecks = false
    var canCheck: Bool { false }
    func check() {}
}
