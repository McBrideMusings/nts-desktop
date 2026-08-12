import SwiftUI
import AppKit

/// The Settings window: a real, ordinary macOS window hosting `SettingsView`.
///
/// **Why this exists rather than SwiftUI's `Settings` scene.** The scene is the
/// documented way to get a settings window, and it was tried first — declared in
/// `NTSRadioApp`, opened with `openSettings()` from the gear and with the action
/// it installs on the responder chain from AppKit. Both reported success and no
/// window was ever created: enumerating the app's windows through
/// `CGWindowListCopyWindowInfo` after `open settings` returned showed the radio
/// window and nothing else. The scene hangs off the app menu, and this app
/// spends most of its life as an agent (`NSApp.setActivationPolicy(.accessory)`
/// whenever "Show in Dock" is off), where there is no app menu for it to hang
/// off. A window this app makes itself has no such dependency.
///
/// Nothing here is styled. The chrome is the system's — the standard title bar,
/// the standard close button, the standard shadow — and the contents are a
/// system `Form`. Position and size are remembered by AppKit under
/// `frameAutosaveName`, so it reopens where it was left.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    /// Bring the Settings window up, making it on first use. Activating first is
    /// what an agent app has to do to put any window in front — without it the
    /// window is ordered in behind whatever the user is looking at.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil { window = make() }
        window?.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        // Closing must not destroy it — the same window comes back, in the same
        // place, and a released one would crash the second open.
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("NTSSettingsWindow")
        window.center()
        window.delegate = self
        return window
    }

    /// Whether the window is up, for the scripting layer's state blob.
    var isVisible: Bool { window?.isVisible ?? false }
}
