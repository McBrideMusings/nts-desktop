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
    /// Smallest window the interface is laid out for. With `.fullSizeContentView`
    /// the content view spans the whole frame, so this is both the frame minimum
    /// and the content minimum.
    static let minContentSize = NSSize(width: 720, height: 300)

    init(model: AppModel) {
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
        // The floor the layout is designed against: below 720×300 the two channel
        // cards stop fitting side by side and the dial shrinks past the point
        // where its face text can be read. `contentMinSize` on its own did not
        // hold: the window was draggable down to roughly 340×790 and to a 95pt
        // strip. `minSize` constrains the frame, which is what a resize drag
        // actually moves, so both are set.
        window.contentMinSize = Self.minContentSize
        window.minSize = Self.minContentSize
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
        // A frame saved before the minimum was enforced can be smaller than the
        // layout survives; `setFrameUsingName` restores it verbatim, so grow it
        // back here rather than reopening at 340×90 forever.
        let f = window.frame
        if f.width < Self.minContentSize.width || f.height < Self.minContentSize.height {
            window.setFrame(NSRect(x: f.minX,
                                   y: f.maxY - max(f.height, Self.minContentSize.height),
                                   width: max(f.width, Self.minContentSize.width),
                                   height: max(f.height, Self.minContentSize.height)),
                            display: false)
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
