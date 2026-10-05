import SwiftUI
import AppKit
import Combine

@main
struct NTSRadioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Both real windows are hand-managed: the radio (`RadioWindowController`,
        // toggled by the status item) and Settings (`SettingsWindowController`).
        // SwiftUI requires an App to declare at least one Scene, so this stays an
        // empty placeholder — putting `SettingsView` in it produced no window at
        // all, for the reason written up in `SettingsWindowController`.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var windowController: RadioWindowController!
    private var parentWatch: DispatchSourceProcess?
    private var bag = Set<AnyCancellable>()
    private var waterlineTimer: Timer?

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

        // The same instance the Settings window reads, which is why it is named
        // on the type rather than made here (see `AppModel.shared`). Making it
        // starts Sparkle's scheduled background checks (`SparkleUpdates`).
        let model = AppModel.shared
        self.model = model

        installMainMenu()

        // Menu-bar presence is always on; the Dock icon is user-controlled
        // (Settings ▸ Show in Dock) and persisted. The AppDelegate owns the
        // activation policy — this sink fires immediately with the saved value
        // (initial apply) and again whenever the toggle flips.
        model.preferences.$showInDock
            .sink { NSApp.setActivationPolicy($0 ? .regular : .accessory) }
            .store(in: &bag)

        windowController = RadioWindowController(model: model)

        // Open the scripting layer for business, and hand it the window (the
        // model it already has — `AppModel.shared`). See Scripting.swift /
        // Resources/NTSRadio.sdef.
        AppModel.scriptingReady = true
        RadioWindowController.scriptTarget = windowController

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.idleFrame
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        // The waterline moves only while audio is genuinely rendering, not merely
        // while the play button is down — so a stalled stream visibly stops instead
        // of running on through the silence. Subscribed after `statusItem` is
        // assigned, because this fires immediately with the current value.
        model.engine.$isRendering
            .sink { [weak self] in self?.setStatusItemAnimating($0) }
            .store(in: &bag)

        // The badge names the source, so it has to follow a source change that
        // happens while stopped — the media keys stepping to the next channel
        // while paused, say. While the waterline is running its own timer already
        // reads `selection` every frame, so this would only fight with it.
        //
        // The sink takes the incoming value rather than reading `model.selection`:
        // `@Published` fires from `willSet`, so the property still holds the *old*
        // selection while this runs, and reading it draws the badge one step behind
        // (paused on 2, skip to 1, icon still says 2).
        model.$selection
            .sink { [weak self] selection in
                guard let self, self.waterlineTimer == nil else { return }
                self.showStillStatusItem(for: selection)
            }
            .store(in: &bag)
    }

    /// The status item with no motion: the badge for whatever is selected, held
    /// still. Paused on Channel 2 that is a still `2`, not the NTS wordmark — the
    /// mark is what `.idle` maps to, so it appears only when nothing is loaded.
    /// Stopping the waterline is what says playback stopped; throwing the badge
    /// away as well would lose which source you are paused on.
    private func showStillStatusItem(for selection: Selection) {
        statusItem.button?.image = MenuBarIcon.image(badge: MenuBarBadge(selection), waterline: nil)
    }

    /// Drive the status item. While audio is rendering it shows the badge for
    /// whatever is playing with the waterline crossing it, redrawn 25 times a
    /// second; otherwise the same badge, held still. Added in `.common` run-loop
    /// mode so the animation keeps running while a menu is open.
    private func setStatusItemAnimating(_ animating: Bool) {
        waterlineTimer?.invalidate()
        waterlineTimer = nil
        guard animating else {
            showStillStatusItem(for: model.selection)
            return
        }
        // Measured from when this run of playback started, so the waterline picks
        // up from the top of its cycle each time rather than wherever the clock
        // happens to be.
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 25.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.statusItem.button?.image = MenuBarIcon.image(
                    badge: MenuBarBadge(self.model.selection),
                    waterline: MenuBarIcon.waterline(at: CACurrentMediaTime() - start)
                )
            }
        }
        // A menu-bar radio is left streaming for hours, so this timer is the app's
        // longest-running repeating work. The tolerance lets the run loop coalesce
        // its wakeups with whatever else is due; at 25fps a 10ms slip is invisible.
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        waterlineTimer = timer
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

    /// Built fresh on every right-click, so the play/pause title, the mute tick
    /// and the dot next to the live channel are read off the model at the moment
    /// the menu opens rather than cached.
    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        // Every item's enabled state is set here. Left on, AppKit re-derives it
        // from whether the target responds to the selector — which is always —
        // and Play/Mute would look live with nothing loaded.
        menu.autoenablesItems = false

        // Nothing loaded means there is nothing to play or silence, so both of
        // these are dimmed rather than absent — the menu keeps its shape.
        let playPause = NSMenuItem(title: model.isPlaying ? "Pause" : "Play",
                                   action: #selector(togglePlay), keyEquivalent: "")
        playPause.target = self
        playPause.isEnabled = !model.isIdle
        menu.addItem(playPause)
        let mute = NSMenuItem(title: "Mute", action: #selector(toggleMute), keyEquivalent: "")
        mute.target = self
        mute.state = model.preferences.muted ? .on : .off
        mute.isEnabled = !model.isIdle
        menu.addItem(mute)

        // The two live channels only — the mixtapes are a dial of thirty and
        // belong in the window, not here.
        menu.addItem(.separator())
        for channel in model.catalog.channels {
            let item = NSMenuItem(title: "Live \(channel.number)",
                                  action: #selector(tuneChannel(_:)), keyEquivalent: "")
            item.target = self
            item.tag = channel.number
            item.state = model.selection == .channel(channel.number) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        // Re-read first: System Settings can switch it off behind the app's back.
        model.preferences.refreshStartOnLogin()
        login.state = model.preferences.startOnLogin ? .on : .off
        // A bare binary under `admin dev` has no bundle for launchd to register,
        // so the item is shown dimmed there rather than failing on click.
        login.isEnabled = model.preferences.canStartOnLogin
        menu.addItem(login)
        let dock = NSMenuItem(title: "Show in Dock", action: #selector(toggleDock), keyEquivalent: "")
        dock.target = self
        dock.state = model.preferences.showInDock ? .on : .off
        menu.addItem(dock)
        let checkUpdates = NSMenuItem(title: "Check for Updates…",
                                      action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdates.target = self
        checkUpdates.isEnabled = model.preferences.canCheckForUpdates
        menu.addItem(checkUpdates)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit NTS Radio", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    @objc private func toggleDock() { model.preferences.showInDock.toggle() }

    @objc private func toggleLoginItem() { model.preferences.startOnLogin.toggle() }

    @objc private func checkForUpdates() { model.preferences.checkForUpdates() }

    /// The main menu autoenables its items, so this is where "Check for
    /// Updates…" dims while Sparkle is already mid-check.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(checkForUpdates) else { return true }
        return model.preferences.canCheckForUpdates
    }

    @objc private func togglePlay() { model.togglePlay() }

    @objc private func toggleMute() { model.preferences.muted.toggle() }

    /// Tune to a live channel, exactly as clicking its card in the window does —
    /// the tag is the channel number the menu was built with.
    @objc private func tuneChannel(_ sender: NSMenuItem) {
        model.select(.channel(sender.tag))
    }

    /// The status item's route into the Settings window — the same one the gear
    /// in the title bar and `osascript … open settings` take.
    @objc private func openSettings() { SettingsWindowController.shared.show() }

    /// A main menu, so the standard keystrokes have somewhere to live.
    ///
    /// In menu-bar-only mode the app is an agent and this menu is never drawn —
    /// but `NSApplication` still routes key equivalents through it while the app
    /// is frontmost, and it is the only place a key equivalent can be declared.
    /// Without it ⌘, opened nothing unless the status item's menu happened to be
    /// down, ⌘W closed no window, and ⌘Q did not quit. In Dock mode it becomes
    /// the visible menu bar, which is why the item titles are the standard ones.
    private func installMainMenu() {
        let appMenu = NSMenu()
        let checkUpdates = NSMenuItem(title: "Check for Updates…",
                                      action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdates.target = self
        appMenu.addItem(checkUpdates)
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide NTS Radio",
                                   action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Close Window",
                                   action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit NTS Radio",
                                   action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Editing shortcuts are not decoration here: the sign-in fields in the
        // Settings window get no ⌘C/⌘V/⌘A at all without a menu declaring them.
        let editMenu = NSMenu(title: "Edit")
        for (title, selector, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] as [(String, Selector, String)] {
            editMenu.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
        }

        let root = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        root.addItem(appItem)
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        root.addItem(editItem)
        NSApp.mainMenu = root
    }
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

    /// Both caches write on a five-second debounce, so quitting inside that
    /// window would throw away whatever the last screen of schedule rows just
    /// learned. This is the only moment that is guaranteed to be after the last
    /// one of them.
    func applicationWillTerminate(_ notification: Notification) {
        model?.saveSlotDetails()
        ShowIndex.shared.flush()
        LogFiles.tracks.flush()
        LogFiles.app.flush()
    }
}
