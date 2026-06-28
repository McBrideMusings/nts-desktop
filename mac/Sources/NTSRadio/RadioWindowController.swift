import SwiftUI
import AppKit

/// Hosts the radio UI (`PopoverView`) in a single, persistent window that the
/// status-item click shows and hides. Unlike the old `MenuBarExtra` popover,
/// this window stays open when the app isn't frontmost and can be dragged
/// anywhere on screen — it's a free-floating window that happens to be summoned
/// from the menu bar.
@MainActor
final class RadioWindowController {
    private let window: KeyableWindow
    private static let frameName = "NTSRadioWindow"

    init(model: AppModel) {
        let root = PopoverView()
            .environmentObject(model)
            .environmentObject(model.auth)
        let hosting = NSHostingView(rootView: root)

        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Traffic lights float over the content (the TopBar reserves space for
        // them); the title bar is transparent with no title text.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // The settings + account controls must be real title-bar items: with
        // fullSizeContentView the title-bar view sits above the content and
        // eats clicks in its band for window dragging, so controls drawn into
        // the TopBar strip render but never receive a click. A trailing
        // title-bar accessory makes AppKit route clicks to them.
        let controls = TopBarControls()
            .environmentObject(model)
            .environmentObject(model.auth)
        let controlsVC = NSTitlebarAccessoryViewController()
        controlsVC.layoutAttribute = .trailing
        let controlsHost = NSHostingView(rootView: controls)
        controlsHost.frame = NSRect(x: 0, y: 0, width: 80, height: 32)
        controlsVC.view = controlsHost
        window.addTitlebarAccessoryViewController(controlsVC)
        window.backgroundColor = NSColor(red: 0x0b/255, green: 0x0b/255, blue: 0x0c/255, alpha: 1) // Theme.popover
        window.isMovableByWindowBackground = false   // drag via the title-bar strip only, not the dial
        window.level = .normal                        // ordinary window: stays open unfocused, can go behind
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentMinSize = NSSize(width: 720, height: 300)   // no max — free to grow
        window.setFrameAutosaveName(Self.frameName)  // remember size + position across launches
        self.window = window
    }

    func toggle(relativeTo statusButton: NSStatusBarButton?) {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            show(relativeTo: statusButton)
        }
    }

    func show(relativeTo statusButton: NSStatusBarButton?) {
        if !window.isVisible, !window.setFrameUsingName(Self.frameName) {
            // First ever open (no saved frame): drop it just below the menu-bar icon.
            positionUnderStatusItem(statusButton)
            window.saveFrame(usingName: Self.frameName)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func positionUnderStatusItem(_ statusButton: NSStatusBarButton?) {
        guard let statusButton, let buttonWindow = statusButton.window else {
            window.center(); return
        }
        let onScreen = buttonWindow.convertToScreen(
            statusButton.convert(statusButton.bounds, to: nil))
        let size = window.frame.size
        let gap: CGFloat = 6
        var x = onScreen.midX - size.width / 2
        let y = onScreen.minY - gap - size.height
        if let vis = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, vis.minX + 8), vis.maxX - size.width - 8)
        }
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// A borderless window that can still become key/main, so the Settings
/// sign-in text fields accept keyboard input (borderless windows refuse key
/// status by default).
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
