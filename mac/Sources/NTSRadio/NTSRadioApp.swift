import SwiftUI
import AppKit

@main
struct NTSRadioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
        } label: {
            MenuBarIcon(playing: model.isPlaying && !model.muted)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.registerFonts()
        if let dir = ProcessInfo.processInfo.environment["NTS_SNAPSHOT"] {
            NSApp.setActivationPolicy(.prohibited)
            Snapshot.run(dir: dir)   // renders PNGs then exits
            return
        }
        // Menu-bar-only agent: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
    }
}
