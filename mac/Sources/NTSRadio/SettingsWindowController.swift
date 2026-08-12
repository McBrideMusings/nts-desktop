import SwiftUI
import AppKit

/// The Settings window: a real, ordinary macOS window hosting `SettingsView`,
/// with the classic preferences chrome — a toolbar of icon-and-label tabs, the
/// window title naming the pane on show, and the window resizing to fit whichever
/// pane that is.
///
/// **Why AppKit builds this rather than a SwiftUI `TabView`.** A `TabView` of
/// `.tabItem`s renders as a small segmented picker at the top of the content,
/// which is the iOS-derived look; the preferences toolbar in the screenshot is
/// `NSToolbar` with `toolbarStyle = .preference`, and there is no SwiftUI
/// spelling for it outside the `Settings` scene. The window is already ours, so
/// the toolbar is a few lines rather than a fight.
///
/// **And why not SwiftUI's `Settings` scene.** That is the documented way to get
/// a settings window, and it was tried first — declared in `NTSRadioApp`, opened
/// with `openSettings()` and with the action it installs on the responder chain.
/// Both reported success and no window was ever created: enumerating the app's
/// windows through `CGWindowListCopyWindowInfo` after `open settings` returned
/// showed the radio window and nothing else. The scene hangs off the app menu,
/// and this app spends most of its life as an agent
/// (`NSApp.setActivationPolicy(.accessory)` whenever "Show in Dock" is off),
/// where there is no app menu for it to hang off.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    /// What the one hosted view is drawing. Writing to this is the whole of
    /// switching panes — see `SettingsSelection`.
    private let selection = SettingsSelection()
    private var pane: SettingsPane { selection.pane }

    /// Bring the Settings window up, making it on first use. Activating first is
    /// what an agent app has to do to put any window in front — without it the
    /// window is ordered in behind whatever the user is looking at.
    /// Bring the window up on a named pane — the scripted equivalent of clicking
    /// one of its toolbar tabs, so the panes are reachable without a mouse.
    func show(_ pane: SettingsPane) {
        show()
        select(pane)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil { window = make() }
        // The login item can be switched off in System Settings ▸ General ▸ Login
        // Items while this app is running, so the toggle re-reads the real state
        // every time the window comes up rather than showing what it last set.
        AppModel.shared.refreshStartOnLogin()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Whether the window is up, for the scripting layer's state blob.
    var isVisible: Bool { window?.isVisible ?? false }

    // MARK: Window

    private func make() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(selection: selection))
        // The window follows the hosted view's own preferred size, so changing
        // pane resizes it once, by AppKit, anchored where AppKit anchors a
        // content-size change. Doing that by hand — `setContentSize`, or a
        // `setFrame` animation — walked the window up the screen, because
        // AppKit's origin is the bottom-left corner and those keep it fixed.
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        // Closing must not destroy it — the same window comes back, in the same
        // place, and a released one would crash the second open.
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("NTSSettingsWindow")

        let toolbar = NSToolbar(identifier: "NTSSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        // After the toolbar is on the window, not before: until then it has no
        // items to select, and setting an identifier that matches nothing leaves
        // the selection on whichever item AppKit inserts last — which is how a
        // window whose title said "General" opened showing Account.
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(pane.rawValue)
        // The style that puts the tabs across the top of the window under the
        // title, which is what every preferences window has looked like since
        // long before it had a name.
        window.toolbarStyle = .preference

        window.title = pane.title
        window.center()
        window.delegate = self
        return window
    }

    /// Show a pane: tell the hosted view what to draw and retitle the window.
    /// Nothing here touches the window's size — the hosting controller reports
    /// its new preferred size and AppKit does the resize.
    private func select(_ pane: SettingsPane) {
        guard pane != selection.pane else { return }
        selection.pane = pane
        window?.title = pane.title
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(pane.rawValue)
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane(rawValue: sender.itemIdentifier.rawValue) else { return }
        select(pane)
    }

    // MARK: NSToolbarDelegate

    private var identifiers: [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    /// What makes a toolbar item show as *selected* rather than just clickable —
    /// without this the tabs light up for a moment and then look inactive again.
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = SettingsPane(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = pane.title
        item.paletteLabel = pane.title
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }
}
