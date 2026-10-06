import SwiftUI
import AppKit

/// Hosts the radio UI (`PopoverView`) in a single window that the status-item
/// click shows and hides, built the first time it is shown and kept from then
/// on, with its SwiftUI content taken out while it is closed. Unlike the old `MenuBarExtra` popover, this window stays open when the
/// app isn't frontmost and can be dragged anywhere on screen — it's a
/// free-floating window that happens to be summoned from the menu bar.
@MainActor
final class RadioWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    /// Nil until the window is first shown. Drawing any SwiftUI first brings up
    /// RenderBox's Metal device, a large transient GPU allocation, so a launch
    /// that never opens the window must not build it. Read this to ask about
    /// the window; call `builtWindow()` only to put it on screen.
    private var built: KeyableWindow?
    /// The radio UI while the window is off screen. An ordered-out window
    /// still redraws its SwiftUI content on every model change, and each
    /// redraw of the full window reallocates ~350MB of GPU memory, so the
    /// content leaves the window when it goes off screen and comes back when
    /// it returns. Kept rather than rebuilt so scroll positions survive.
    private var parked: NSViewController?
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
        self.model = model
        super.init()
    }

    /// The window, building it on the first call and putting back any content
    /// `takeOffScreen` parked.
    private func builtWindow() -> KeyableWindow {
        if let built {
            if let parked {
                built.contentViewController = parked
                self.parked = nil
                Log.app.info("radio window content restored")
            }
            return built
        }
        let root = PopoverView()
            .environmentObject(model)
            .environmentObject(model.auth)
            .environmentObject(model.engine)
        // The content view spans the whole window (`.fullSizeContentView`) and
        // `PopoverView` opens with its own `Theme.titleBarHeight` strip laid out from
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

        // The title-bar buttons are a title-bar accessory rather than a strip
        // inside the content view. Two things follow from that, and both are why
        // it lives here: AppKit routes clicks to them (a view drawn into the
        // content view under the title bar never receives one — the title-bar
        // view swallows clicks in its band for window dragging), and AppKit sets
        // the content view's top safe-area inset to this accessory's height, so
        // PopoverView's rail and dial start exactly below the band with no
        // height for the content side to guess at. Only the buttons live here:
        // AppKit insets the accessory past the traffic lights, so its centre is
        // not the window's centre and nothing centred can go in it.
        let topBar = TitleBarControls()
            .environmentObject(model)
            .environmentObject(model.auth)
            .environmentObject(model.engine)
        let topBarVC = NSTitlebarAccessoryViewController()
        topBarVC.layoutAttribute = .top
        let topBarHost = NSHostingView(rootView: topBar)
        // Width is stretched by AppKit; the height here is the band's height.
        topBarHost.frame = NSRect(x: 0, y: 0, width: 880, height: Theme.titleBarHeight)
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
        built = window
        return window
    }

    /// The menu-bar click. Hiding is only right when the window is already the
    /// thing you are looking at: on screen, this app frontmost, this window key.
    /// A window that is merely visible but buried under Safari gets raised —
    /// otherwise the first click hides what you were pointing at and the second
    /// one brings it back, which is two clicks to do what you asked for once.
    func toggle(relativeTo statusButton: NSStatusBarButton?) {
        if let window = built, window.isVisible, NSApp.isActive, window.isKeyWindow {
            takeOffScreen(window)
        } else {
            show(relativeTo: statusButton)
        }
    }

    func show(relativeTo statusButton: NSStatusBarButton?) {
        let window = builtWindow()
        placeFrame(window, relativeTo: statusButton)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Whether the window is on screen — the scripting dictionary's
    /// `window visible`.
    var isWindowVisible: Bool { built?.isVisible ?? false }

    /// The built window, for `Demo` to size and place.
    var demoWindow: NSWindow? { built }

    /// Whether the radio UI is in the window — the state blob's
    /// `windowContentAttached`.
    var isContentAttached: Bool { built?.contentViewController != nil }

    /// Put the window on screen without activating the app. A scripted open must
    /// not take keyboard focus from whatever the person at the machine is typing
    /// into, so this is `show` minus the activation.
    func showWithoutActivating() {
        let window = builtWindow()
        let before = window.scriptLogState
        placeFrame(window, relativeTo: nil)
        window.orderFrontRegardless()
        Log.app.info("script open window: \(before, privacy: .public) -> \(window.scriptLogState, privacy: .public)")
    }

    /// Take the window off screen. The app lives on in the menu bar.
    func hide() {
        guard let window = built else {
            Log.app.info("script close window: never shown")
            return
        }
        let before = window.scriptLogState
        takeOffScreen(window)
        Log.app.info("script close window: \(before, privacy: .public) -> \(window.scriptLogState, privacy: .public)")
    }

    /// The close button and ⌘W. The window is kept (`isReleasedWhenClosed` is
    /// false), so closing it is ordering it out like the other ways to close it.
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            if let window = notification.object as? NSWindow { takeOffScreen(window) }
        }
    }

    /// Every way to close the window — the menu-bar click, the close button,
    /// ⌘W, a script — ends here, and parks its content (see `parked`) so a
    /// closed window does no SwiftUI work. Miniaturising does not come here.
    private func takeOffScreen(_ window: NSWindow) {
        window.orderOut(nil)
        guard let content = window.contentViewController else { return }
        parked = content
        window.contentViewController = nil
        Log.app.info("radio window content parked")
    }

    private func placeFrame(_ window: NSWindow, relativeTo statusButton: NSStatusBarButton?) {
        if !window.isVisible, !window.setFrameUsingName(Self.frameName) {
            // First ever open (no saved frame): drop it just below the menu-bar icon.
            positionUnderStatusItem(window, statusButton)
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
    }

    nonisolated func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        MainActor.assumeIsolated { Self.clamped(frameSize) }
    }

    private func positionUnderStatusItem(_ window: NSWindow, _ statusButton: NSStatusBarButton?) {
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

extension NSWindow {
    /// Everything that decides whether a window is on screen, for the log — so
    /// a scripted open that leaves `window visible` or `settingsVisible` false
    /// says why. `screenLocked` is the login session's lock-screen flag; the
    /// session omits the key while unlocked, and `unknown` means there was no
    /// session dictionary to read.
    var scriptLogState: String {
        let occluded = !occlusionState.contains(.visible)
        let locked = (CGSessionCopyCurrentDictionary() as? [String: Any]).map {
            String($0["CGSSessionScreenIsLocked"] as? Bool ?? false)
        } ?? "unknown"
        return """
            visible=\(isVisible) key=\(isKeyWindow) miniaturized=\(isMiniaturized) \
            onActiveSpace=\(isOnActiveSpace) occluded=\(occluded) \
            frame=\(NSStringFromRect(frame)) screen=\(screen?.localizedName ?? "none") \
            appActive=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue) \
            screenLocked=\(locked)
            """
    }
}

/// A borderless window that can still become key/main, so the Settings
/// sign-in text fields accept keyboard input (borderless windows refuse key
/// status by default).
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
