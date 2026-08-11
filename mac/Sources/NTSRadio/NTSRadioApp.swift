import SwiftUI
import AppKit
import Combine

@main
struct NTSRadioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The real UI is a hand-managed window toggled by the status item (see
        // AppDelegate). SwiftUI requires an App to declare at least one Scene, so
        // this empty Settings scene is just a placeholder — it never opens on its
        // own. (In Dock mode it adds a no-op "Settings…" item to the app menu.)
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var windowController: RadioWindowController!
    private var parentWatch: DispatchSourceProcess?
    private var bag = Set<AnyCancellable>()
    private var barTimer: Timer?
    private var barStep = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When run from source under `admin dev` / `swift run`, stdout is a pipe,
        // not a TTY — so Swift block-buffers `print()` and a long-running GUI app
        // (which never exits to flush) shows no output in the captured dev log.
        // Force unbuffered stdout so logs stream live to tmp/dev.<timestamp>.log.
        setvbuf(stdout, nil, _IONBF, 0)

        // Disk-backed cache so CDN cover art / icons persist across launches and
        // are available offline (URLSession.shared + AsyncImage use this).
        Cache.configureImageCache()
        Theme.registerFonts()
        if let dir = ProcessInfo.processInfo.environment["NTS_SNAPSHOT"] {
            NSApp.setActivationPolicy(.prohibited)
            Snapshot.run(dir: dir)   // renders PNGs then exits
            return
        }

        quitWhenParentExitsInDev()

        let model = AppModel()
        self.model = model

        // Menu-bar presence is always on; the Dock icon is user-controlled
        // (Settings ▸ Show in Dock) and persisted. The AppDelegate owns the
        // activation policy — this sink fires immediately with the saved value
        // (initial apply) and again whenever the toggle flips.
        model.$showInDock
            .sink { NSApp.setActivationPolicy($0 ? .regular : .accessory) }
            .store(in: &bag)

        windowController = RadioWindowController(model: model)

        // Publish both to the scripting layer, so `osascript` reaches the same
        // objects the UI drives (see Scripting.swift / Resources/NTSRadio.sdef).
        AppModel.scriptTarget = model
        RadioWindowController.scriptTarget = windowController

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.idleFrame
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        // Bars move only while audio is genuinely rendering, not merely while the
        // play button is down — so a stalled stream visibly stops instead of
        // bouncing through the silence. Subscribed after `statusItem` is assigned,
        // because this fires immediately with the current value.
        model.engine.$isRendering
            .sink { [weak self] in self?.setBarsAnimating($0) }
            .store(in: &bag)
    }

    /// Drive the status-item bars. Animating steps through the frame cycle at
    /// 10fps; otherwise the bars sit flat. Added in `.common` run-loop mode so the
    /// animation keeps running while a menu is open.
    private func setBarsAnimating(_ animating: Bool) {
        barTimer?.invalidate()
        barTimer = nil
        guard animating else {
            statusItem.button?.image = MenuBarIcon.idleFrame
            return
        }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.barStep = (self.barStep + 1) % MenuBarIcon.playingFrames.count
                self.statusItem.button?.image = MenuBarIcon.playingFrames[self.barStep]
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        barTimer = timer
    }

    /// When run from source (`swift run` / `admin dev`) the app is a bare binary,
    /// not an installed `.app` launched by launchd. In that case tie its life to
    /// the parent process (the `swift run` / shell that started it): when the
    /// terminal session closes and the parent exits, quit too instead of orphaning
    /// a stray menu-bar instance. The installed `.app` (parent = launchd) is left
    /// alone, so `admin start` / a real install still persists normally.
    private func quitWhenParentExitsInDev() {
        guard Bundle.main.bundleURL.pathExtension != "app" else { return }
        let ppid = getppid()
        guard ppid > 1 else { return }   // already reparented to launchd
        let src = DispatchSource.makeProcessSource(identifier: ppid, eventMask: .exit, queue: .main)
        src.setEventHandler { NSApp.terminate(nil) }
        src.resume()
        parentWatch = src
    }

    /// Left-click toggles the window; right-click (or control-click) opens a
    /// small menu — the menu-bar-only mode otherwise has no Quit affordance.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)
        if isRight { showStatusMenu() }
        else { windowController.toggle(relativeTo: statusItem.button) }
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        let dock = NSMenuItem(title: "Show in Dock", action: #selector(toggleDock), keyEquivalent: "")
        dock.target = self
        dock.state = model.showInDock ? .on : .off
        menu.addItem(dock)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit NTS Radio", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    @objc private func toggleDock() { model.showInDock.toggle() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    /// Clicking the Dock icon (when shown) reveals the window — a Dock app with
    /// no window is a dead end.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController.show(relativeTo: statusItem.button)
        return true
    }

    /// Hiding the window must not quit the app — it lives on in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
