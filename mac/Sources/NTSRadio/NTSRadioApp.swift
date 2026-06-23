import SwiftUI
import AppKit

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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        // (Settings ▸ Show in Dock) and persisted across launches. didSet doesn't
        // fire for the initial value, so apply the saved choice explicitly here.
        NSApp.setActivationPolicy(model.showInDock ? .regular : .accessory)

        windowController = RadioWindowController(model: model)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.barsImage
        item.button?.target = self
        item.button?.action = #selector(toggleWindow)
        statusItem = item
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

    @objc private func toggleWindow() {
        windowController.toggle(relativeTo: statusItem.button)
    }

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
