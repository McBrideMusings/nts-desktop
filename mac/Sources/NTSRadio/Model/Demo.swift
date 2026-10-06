import AppKit

/// The scripted dial sweep `admin noodle-clip` records: `run demo` in the
/// scripting dictionary starts it, and it plays the same way every time with no
/// input from anyone.
///
/// It has three parts, so a recorder can start between the first two:
///
/// - `place` puts the app in a clean state — nothing tuned, the live pane, no
///   catalog, tracklist or Settings — and sets the window to a fixed size on a
///   Retina display, so a recording at 2× is possible.
/// - `sweep` drives `AppModel.hoverIndex`, the value the dial's hit layer writes
///   when the cursor moves, around the dial one wedge in two, and ends with no
///   hover: the state it began in, so a clip trimmed to the sweep loops.
/// - `restore` puts the window back where it was.
///
/// With no part named, all three run in that order.
///
/// **Clip contract.** Launched with env `ADMIN_CLIP=1`, the app places the window,
/// warms the artwork, waits until the file named by `ADMIN_CLIP_START` exists,
/// and calls that moment t0. From t0 the sweep repeats forever with period
/// `Demo.period` (5.0 s for the sixteen-tape catalog): hover starts at
/// t0 + `preRest`, each wedge holds `dwell`, and the dial is at rest from the
/// last clear until t0 + period, so the frame at t0 + k·period is the same for
/// every k. Events are scheduled against t0, never chained, so they do not drift.
@MainActor
enum Demo {
    enum Part: String { case place, sweep, restore, all }

    /// How long each previewed wedge stays under the simulated cursor.
    static let dwell: Duration = .milliseconds(500)
    /// Content size of the window while the demo runs, in points.
    static let windowSize = NSSize(width: 1040, height: 740)
    /// The dial at rest before the first hover.
    static let preRest: Duration = .milliseconds(400)
    /// The dial at rest after the last hover clears, long enough for the icons'
    /// scale animation to finish.
    static let postRest: Duration = .milliseconds(600)

    /// One lap of the sweep, `preRest` + one `dwell` per wedge + `postRest`.
    static func period(count: Int) -> Duration {
        preRest + dwell * sweep(count: count).count + postRest
    }

    /// Whether a sweep is playing.
    private(set) static var running = false
    /// The frame the window had before `place`, until `restore` gives it back.
    private static var placedFrom: NSRect?

    /// Wedges visited: every `stride`th one, eight in all for the sixteen-tape
    /// catalog, so the hover travels once around the dial.
    static func sweep(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let stride = max(1, count / 8)
        return Array(Swift.stride(from: 0, to: count, by: stride))
    }

    /// Run `part`. Returns an error message when it cannot.
    static func start(_ part: Part) -> String? {
        let m = AppModel.shared
        if running { return "The demo is already playing. Wait for demoRunning to turn false." }
        if part != .restore, m.catalog.mixtapes.isEmpty {
            return "The mixtape catalog has not loaded, so there is no dial to sweep."
        }
        switch part {
        case .place:
            place()
        case .sweep:
            sweep()
        case .restore:
            restore()
        case .all:
            place()
            sweep(restoring: true)
        }
        return nil
    }

    private static func place() {
        let m = AppModel.shared
        m.select(.idle)
        m.show(.live)
        if m.catalogOpen { m.toggleCatalog() }
        m.query = ""
        m.detail = nil
        m.hoverIndex = nil
        SettingsWindowController.shared.hide()
        if placedFrom == nil {
            placedFrom = RadioWindowController.scriptTarget?.placeForDemo(contentSize: windowSize)
        }
    }

    /// The clip contract: see the type's documentation. Does nothing unless
    /// `ADMIN_CLIP=1`.
    static func startClipIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard env["ADMIN_CLIP"] == "1" else { return }
        let startFile = env["ADMIN_CLIP_START"] ?? ""
        running = true
        Task { @MainActor in
            let m = AppModel.shared
            while m.catalog.mixtapes.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            place()
            // Pass over every wedge once so covers and animations are cached
            // before t0, then drop back to rest.
            for i in sweep(count: m.catalog.mixtapes.count) {
                m.hoverIndex = i
                try? await Task.sleep(for: .milliseconds(400))
            }
            m.hoverIndex = nil
            try? await Task.sleep(for: postRest)

            Log.app.info("demo clip ready, waiting for \(startFile, privacy: .public)")
            while startFile.isEmpty || !FileManager.default.fileExists(atPath: startFile) {
                try? await Task.sleep(for: .milliseconds(10))
            }
            let t0 = ContinuousClock.now
            let tapes = m.catalog.mixtapes
            let visits = sweep(count: tapes.count)
            let period = period(count: tapes.count)
            Log.app.info("demo clip t0 period=\(String(describing: period), privacy: .public)")
            var lap = 0
            while true {
                let base = t0 + period * lap
                try? await Task.sleep(until: base + preRest)
                for (n, i) in visits.enumerated() {
                    m.hoverIndex = i
                    try? await Task.sleep(until: base + preRest + dwell * (n + 1))
                }
                m.hoverIndex = nil
                lap += 1
                try? await Task.sleep(until: t0 + period * lap)
            }
        }
    }

    private static func restore() {
        guard let frame = placedFrom else { return }
        RadioWindowController.scriptTarget?.restoreAfterDemo(frame)
        placedFrom = nil
    }

    private static func sweep(restoring: Bool = false) {
        let m = AppModel.shared
        running = true
        Task { @MainActor in
            let tapes = m.catalog.mixtapes
            let visits = sweep(count: tapes.count)
            Log.app.info("demo sweep tapes=\(tapes.count) visits=\(visits.map(String.init).joined(separator: ","), privacy: .public)")
            try? await Task.sleep(for: preRest)
            for i in visits {
                m.hoverIndex = i
                Log.app.info("demo hover index=\(i) alias=\(tapes[i].alias, privacy: .public)")
                try? await Task.sleep(for: dwell)
            }
            m.hoverIndex = nil
            Log.app.info("demo hover cleared")
            try? await Task.sleep(for: postRest)
            running = false
            if restoring { restore() }
            Log.app.info("demo sweep end")
        }
    }
}

extension RadioWindowController {
    /// Put the window at a fixed size on the first display with a 2× backing
    /// store, near its top-left corner, without activating the app. Returns the
    /// frame it had, to give back to `restoreAfterDemo`.
    func placeForDemo(contentSize: NSSize) -> NSRect? {
        showWithoutActivating()
        guard let window = demoWindow else { return nil }
        let before = window.frame
        let screen = NSScreen.screens.first { $0.backingScaleFactor >= 2 } ?? window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return before }
        let size = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        window.setFrame(NSRect(x: visible.minX + 40, y: visible.maxY - 40 - size.height,
                               width: size.width, height: size.height), display: true)
        Log.app.info("demo window \(NSStringFromRect(before), privacy: .public) -> \(NSStringFromRect(window.frame), privacy: .public) scale=\(window.backingScaleFactor)")
        return before
    }

    func restoreAfterDemo(_ frame: NSRect) {
        demoWindow?.setFrame(frame, display: true)
        Log.app.info("demo window restored \(NSStringFromRect(frame), privacy: .public)")
    }
}
