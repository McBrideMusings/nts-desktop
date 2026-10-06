import Foundation
import Combine
import ServiceManagement
import Sparkle

/// Every setting the app keeps across a relaunch, and the one place that talks
/// to where each is kept: `UserDefaults` for the plain values, launchd for the
/// login item, Sparkle for the update checks. The last two arrive as adapters,
/// so nothing here reaches a global.
@MainActor
final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    private let loginItem: LoginItem
    private let updates: UpdateChecker
    private var bag = Set<AnyCancellable>()

    init(defaults: UserDefaults, loginItem: LoginItem, updates: UpdateChecker) {
        self.defaults = defaults
        self.loginItem = loginItem
        self.updates = updates
        storedGain = VolumeCurve.gainRange.clamp(defaults.object(forKey: Keys.gain) as? Double ?? 72)
        muted = defaults.bool(forKey: Keys.muted)
        storedCurve = VolumeCurve(
            kind: defaults.string(forKey: Keys.curveKind).flatMap(VolumeCurve.Kind.init(rawValue:)) ?? .perceptual,
            exponent: defaults.object(forKey: Keys.curveExponent) as? Double ?? VolumeCurve.defaultExponent
        ).clamped
        trackLead = TrackLead(rawValue: defaults.string(forKey: Keys.trackLead) ?? "") ?? .title
        showInDock = defaults.bool(forKey: Keys.showInDock)
        resumeLastSource = defaults.bool(forKey: Keys.resumeLastSource)
        startOnLogin = loginItem.isEnabled
        // Dragging the volume slider writes the gain on every frame; only the
        // disk write waits for the drag to settle. `output` stays live.
        $storedGain
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [defaults] in defaults.set($0, forKey: Keys.gain) }
            .store(in: &bag)
    }

    /// The live machine's stores.
    static func live() -> Preferences {
        let defaults = UserDefaults.standard
        suppressAutoChecksForDevBuilds(defaults)
        return Preferences(defaults: defaults, loginItem: SystemLoginItem(), updates: SparkleUpdates())
    }

    /// CI only bumps `CFBundleVersion` past its committed placeholder `"1"` on a
    /// tagged release build — `admin build`/`admin deploy` always ships the
    /// placeholder, since they build straight from the committed `Info.plist`. If
    /// Sparkle's automatic background check stayed on by default, every locally
    /// installed dev copy would nag "update available" forever the moment the
    /// appcast is reachable, comparing build "1" against whatever the last real
    /// release published.
    ///
    /// `register(defaults:)` sets the *registration-domain* default — the lowest
    /// priority in `UserDefaults` — so this only changes what a fresh install
    /// starts at. An explicit choice already made through the Settings toggle
    /// lives in a higher domain and is never overwritten by this. It runs before
    /// `SparkleUpdates` exists, so the updater starts with it already in place.
    private static func suppressAutoChecksForDevBuilds(_ defaults: UserDefaults) {
        guard Bundle.main.infoDictionary?["CFBundleVersion"] as? String == "1" else { return }
        defaults.register(defaults: ["SUEnableAutomaticChecks": false])
    }

    private enum Keys {
        static let gain = "volume"
        static let muted = "muted"
        static let curveKind = "volumeCurve"
        static let curveExponent = "volumeExponent"
        static let trackLead = "trackLead"
        static let showInDock = "showInDock"
        static let exploreFilters = "exploreFilters"
        static let resumeLastSource = "resumeLastSource"
        static let lastSource = "lastSource"
        static let showIndexSeeded = "showIndexSeeded"
        static let episodeIndexSeeded = "episodeIndexSeeded"
        static let installationID = "ntsDeviceID"
    }

    // MARK: Volume

    /// The output gain, always within `VolumeCurve.gainRange`. The setter clamps
    /// before anything is stored or published, so no writer needs its own clamp.
    var gain: Double {
        get { storedGain }
        set { storedGain = VolumeCurve.gainRange.clamp(newValue) }
    }
    @Published private var storedGain: Double

    @Published var muted: Bool {
        didSet { defaults.set(muted, forKey: Keys.muted) }
    }

    /// How the knob maps to gain; its exponent always within
    /// `VolumeCurve.exponentRange`, clamped before it is stored.
    var curve: VolumeCurve {
        get { storedCurve }
        set { storedCurve = newValue.clamped }
    }
    @Published private var storedCurve: VolumeCurve {
        didSet {
            defaults.set(storedCurve.kind.rawValue, forKey: Keys.curveKind)
            defaults.set(storedCurve.exponent, forKey: Keys.curveExponent)
        }
    }

    /// The knob's position, 0–100. The gain is what is stored, so changing the
    /// curve keeps the loudness and moves the knob.
    var slider: Double {
        get { curve.slider(forGain: gain) }
        set { gain = curve.gain(forSlider: newValue) }
    }

    /// What the player should be doing — gain and mute together, emitting the
    /// current pair on subscription and again whenever either changes.
    var output: AnyPublisher<(gain: Double, muted: Bool), Never> {
        $storedGain.combineLatest($muted)
            .map { (gain: $0, muted: $1) }
            .eraseToAnyPublisher()
    }

    // MARK: Window

    /// Which of a track's two lines leads each tracklist row.
    @Published var trackLead: TrackLead {
        didSet { defaults.set(trackLead.rawValue, forKey: Keys.trackLead) }
    }

    /// Whether the app also shows a Dock icon (and app-switcher entry). Off by
    /// default — the app lives primarily in the menu bar. The AppDelegate
    /// observes it and owns applying the activation policy.
    @Published var showInDock: Bool {
        didSet { defaults.set(showInDock, forKey: Keys.showInDock) }
    }

    /// What Explore is filtered to. Read once at launch; `ExploreLoader` owns
    /// the live value and writes each change back here.
    var exploreFilters: NTSAPI.ExploreFilters {
        get {
            defaults.data(forKey: Keys.exploreFilters)
                .flatMap { try? JSONDecoder().decode(NTSAPI.ExploreFilters.self, from: $0) }
                ?? NTSAPI.ExploreFilters()
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Keys.exploreFilters) }
    }

    // MARK: Launch

    /// Whether launch tunes back to `lastSource` instead of starting idle.
    @Published var resumeLastSource: Bool {
        didSet { defaults.set(resumeLastSource, forKey: Keys.resumeLastSource) }
    }

    /// The channel or mixtape last tuned, as the id `tune to` takes
    /// (`mixtape:slow-focus`, `channel:1`). Nil once idle or an episode is
    /// tuned — an episode would need its position back, which nothing keeps.
    var lastSource: String? {
        get { defaults.string(forKey: Keys.lastSource) }
        set { defaults.set(newValue, forKey: Keys.lastSource) }
    }

    // MARK: Bookkeeping

    /// When `ShowIndex` was last seeded from the sitemap. Kept apart from the
    /// index's cache file, whose timestamp moves whenever a show's artwork is
    /// learned and so can't say when the sitemap was last walked.
    var showIndexSeeded: Date? {
        get { defaults.object(forKey: Keys.showIndexSeeded) as? Date }
        set { defaults.set(newValue, forKey: Keys.showIndexSeeded) }
    }

    /// When `EpisodeIndex` was last seeded from the sitemap.
    var episodeIndexSeeded: Date? {
        get { defaults.object(forKey: Keys.episodeIndexSeeded) as? Date }
        set { defaults.set(newValue, forKey: Keys.episodeIndexSeeded) }
    }

    /// This installation's id for NTS's `user_devices` row — made on first
    /// read and kept for good, so re-registering updates the same row.
    var installationID: String {
        if let existing = defaults.string(forKey: Keys.installationID) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: Keys.installationID)
        return fresh
    }

    // MARK: Login item

    /// Whether the app is registered to launch when the user logs in.
    ///
    /// Read from launchd rather than from a saved preference, and written by
    /// registering or unregistering — the login item is the fact, and a stored
    /// copy of it goes stale the moment the switch is thrown in System Settings ▸
    /// General ▸ Login Items, which is the same list this writes to.
    ///
    /// Registering needs a bundle, so under `admin dev` (a bare binary) it
    /// fails; the failure is logged and the value snaps back to what launchd
    /// actually reports.
    @Published var startOnLogin: Bool {
        didSet {
            guard startOnLogin != loginItem.isEnabled else { return }
            do {
                try loginItem.setEnabled(startOnLogin)
            } catch {
                let verb = startOnLogin ? "register" : "unregister"
                Log.app.error("login item \(verb, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                // Say what is true, not what was asked for.
                startOnLogin = loginItem.isEnabled
            }
        }
    }

    /// Whether this copy can be a login item at all — only a real bundle can.
    var canStartOnLogin: Bool { loginItem.isAvailable }

    /// Re-read the login item's real state — before a menu or the Settings
    /// window shows it, since System Settings can change it behind the app's back.
    func refreshStartOnLogin() {
        let enabled = loginItem.isEnabled
        if startOnLogin != enabled { startOnLogin = enabled }
    }

    // MARK: Updates

    /// Sparkle's own setting, read and written straight through — Sparkle
    /// persists it, so there is no copy here to go stale.
    var autoChecksForUpdates: Bool {
        get { updates.automaticallyChecks }
        set {
            objectWillChange.send()
            updates.automaticallyChecks = newValue
        }
    }

    var canCheckForUpdates: Bool { updates.canCheck }

    /// What every "Check for Updates…" item and the scripting command call.
    func checkForUpdates() { updates.check() }
}

// MARK: - Adapters

/// Launch-at-login, as launchd sees it.
@MainActor
protocol LoginItem {
    var isAvailable: Bool { get }
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
struct SystemLoginItem: LoginItem {
    /// Only a real bundle can be registered — `admin dev` runs a bare binary
    /// launchd has no app to launch.
    var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// `.requiresApproval` means the registration exists but the user switched it
    /// off in System Settings, so it is reported as off — on promises the app
    /// will actually start, not merely that it asked to.
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}

/// The app's update checks.
@MainActor
protocol UpdateChecker: AnyObject {
    var automaticallyChecks: Bool { get set }
    var canCheck: Bool { get }
    func check()
}

/// Sparkle, started once for the app's lifetime. `startingUpdater: true`
/// begins the scheduled background checks (`SUScheduledCheckInterval` in
/// Info.plist) as soon as this is made.
@MainActor
final class SparkleUpdates: UpdateChecker {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    func check() { controller.checkForUpdates(nil) }
}
