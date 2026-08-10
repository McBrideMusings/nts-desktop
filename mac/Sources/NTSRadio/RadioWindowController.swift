import SwiftUI
import AppKit

/// Hosts the radio UI (`PopoverView`) in a single, persistent window that the
/// status-item click shows and hides. Unlike the old `MenuBarExtra` popover,
/// this window stays open when the app isn't frontmost and can be dragged
/// anywhere on screen — it's a free-floating window that happens to be summoned
/// from the menu bar.
@MainActor
final class RadioWindowController: NSObject, NSWindowDelegate {
    private var window: KeyableWindow!
    private static let frameName = "NTSRadioWindow"

    /// The smallest the window may get, in two regimes rather than one rectangle.
    ///
    /// A single 340×230 floor would allow both extremes at once, and a window that
    /// is both narrow and short has nowhere to put the dial — at 340 wide the rail
    /// alone takes 300 of it. So one of the two has to stay above 520: a narrow
    /// window stacks the rail above the dial and needs the height, a short one
    /// keeps the rail beside the dial and needs the width. Allowed is therefore
    /// `width ≥ 520` (with height ≥ 230) **or** `height ≥ 520` (with width ≥ 340).
    ///
    /// One rectangle, no coupling between the two dimensions.
    ///
    /// It used to be two regimes — a narrow window had to stay tall, a short one
    /// had to stay wide — because the channel rail was a fixed 300pt and at 340
    /// wide there was nothing left for the dial. Any such rule has a corner where
    /// the two floors meet, and dragging diagonally through it made the window
    /// stick and jump: each step's floor depended on the other dimension's current
    /// value, and the two took turns pushing each other. The rail is proportional
    /// now (`PopoverView`), so the layout survives any size at or above this and
    /// the rule can be a plain minimum.
    static let minSize = NSSize(width: 340, height: 230)

    static func clamped(_ size: NSSize) -> NSSize {
        NSSize(width: max(size.width, minSize.width),
               height: max(size.height, minSize.height))
    }

    init(model: AppModel) {
        super.init()
        let root = PopoverView()
            .environmentObject(model)
            .environmentObject(model.auth)
        // The content view spans the whole window (`.fullSizeContentView`) and
        // `PopoverView` opens with its own `TopBar.height` strip laid out from
        // the top of the window — the same constant that sizes the title-bar
        // accessory below, so the strip and the band AppKit actually draws
        // cannot disagree. They did before: the strip hardcoded 32pt while the
        // real band was taller, and the whole interface slid up by the
        // difference, which is what ran the channel cards into the traffic
        // lights and cut the second card off at the bottom.
        //
        // `sizingOptions = []` keeps the SwiftUI ideal size from driving the
        // window size — the saved frame does that.
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []

        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        // Traffic lights float over the top bar; the title bar itself is
        // transparent with no title text, so the bar's own black fill is what
        // the eye reads as the title bar.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // The whole top bar is a full-width title-bar accessory rather than a
        // strip inside the content view. Two things follow from that, and both
        // are why it lives here: AppKit routes clicks to its buttons (a view
        // drawn into the content view under the title bar never receives one —
        // the title-bar view swallows clicks in its band for window dragging),
        // and AppKit sets the content view's top safe-area inset to this
        // accessory's height, so PopoverView's rail and dial start exactly
        // below the bar with no height for the content side to guess at.
        let topBar = TopBar()
            .environmentObject(model)
            .environmentObject(model.auth)
        let topBarVC = NSTitlebarAccessoryViewController()
        topBarVC.layoutAttribute = .top
        let topBarHost = NSHostingView(rootView: topBar)
        // Width is stretched by AppKit; the height here is the band's height.
        topBarHost.frame = NSRect(x: 0, y: 0, width: 880, height: TopBar.height)
        topBarHost.autoresizingMask = [.width]
        topBarVC.view = topBarHost
        window.addTitlebarAccessoryViewController(topBarVC)
        // AppKit insets a `.top` accessory by the traffic lights' width, so the
        // bar's own fill starts 78pt in. The window background paints that
        // leading corner, so it has to be the same black as the bar — anything
        // else reads as a notch cut out of the strip. Nothing else shows the
        // window background: PopoverView paints the whole content area.
        window.backgroundColor = .black                // matches Theme.nowBar
        window.isMovableByWindowBackground = false   // drag via the title-bar strip only, not the dial
        window.level = .normal                        // ordinary window: stays open unfocused, can go behind
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // `contentMinSize` did not hold this window down on its own — it stayed
        // draggable to a 95pt strip — so the floor is also enforced from
        // `windowWillResize(_:to:)` below, which AppKit asks for at every step of
        // a resize drag.
        window.contentMinSize = Self.minSize
        window.minSize = Self.minSize
        window.delegate = self
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
        // A frame saved while the window was smaller than the rule allows comes
        // back verbatim from `setFrameUsingName`, so grow it here rather than
        // reopening at that size forever.
        let f = window.frame
        let ok = Self.clamped(f.size)
        if ok != f.size {
            window.setFrame(NSRect(x: f.minX, y: f.maxY - ok.height,
                                   width: ok.width, height: ok.height),
                            display: false)
            window.saveFrame(usingName: Self.frameName)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    nonisolated func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        MainActor.assumeIsolated { Self.clamped(frameSize) }
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
