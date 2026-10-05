import AppKit
import Foundation

/// The app's control surface: AppleScript terminology backed by the same
/// `AppModel` the UI drives, so a script can tune, play, pause and — crucially —
/// read back what happened without anyone touching the mouse.
///
/// The vocabulary lives in `mac/Resources/NTSRadio.sdef`; this file is the other
/// half of every entry there. Adding a command means editing both.
///
/// Only the `.app` bundle carries the dictionary, so `admin dev`'s bare binary
/// answers nothing — verify against `admin install`'s copy.

// MARK: - Where the scripting layer finds the running app

extension AppModel {
    /// Whether launch has finished, so the commands below can say "not yet"
    /// instead of half-driving an app that is still assembling itself.
    ///
    /// This used to be a weak `scriptTarget` pointer that the AppDelegate set,
    /// and every command read the model through it — so "which model" and "is it
    /// ready" were the same question asked of one optional. They are not the same
    /// question: the model is `AppModel.shared` and always exists, while
    /// readiness is a moment in launch. Under `NTS_SNAPSHOT` this stays false,
    /// which is correct — that mode renders PNGs and exits.
    @MainActor static var scriptingReady = false
}

extension RadioWindowController {
    /// The live window controller, for the window commands. Same lifetime rules
    /// as `RadioWindowController.scriptTarget` below.
    @MainActor static weak var scriptTarget: RadioWindowController?
}

// MARK: - The state blob

@MainActor
enum ScriptState {
    /// Everything observable about the app, as a JSON object. Every command
    /// returns this too, so one round trip both acts and reports.
    static func json() -> String {
        guard AppModel.scriptingReady else {
            return #"{"running":false}"#
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(AppModel.shared.stateSnapshot()),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"running":true,"error":"could not encode state"}"#
        }
        return text
    }

    /// `Selection` as the same string `tune to` accepts, so what the app reports
    /// can be handed straight back to it.
    static func sourceID(_ s: Selection) -> String {
        switch s {
        case .idle: return "idle"
        case .mixtape(let alias): return "mixtape:\(alias)"
        case .channel(let n): return "channel:\(n)"
        case .episode(let show, let episode): return "episode:\(show)/\(episode)"
        }
    }

    /// Parse what `tune to` was given. Returns nil for anything that doesn't
    /// name a source the catalog actually holds — a typo'd alias must fail
    /// loudly rather than silently tuning nothing.
    static func selection(from text: String) -> Selection? {
        let m = AppModel.shared
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw == "idle" { return .idle }
        let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let value = String(parts[1])
        switch parts[0] {
        case "mixtape":
            guard m.catalog.mixtapes.contains(where: { $0.alias == value }) else { return nil }
            return .mixtape(value)
        case "channel":
            guard let n = Int(value), m.catalog.channels.contains(where: { $0.number == n }) else { return nil }
            return .channel(n)
        // `episode:<show>/<episode>`. Unlike a mixtape or a channel there is
        // nothing local to check it against — the catalog holds no list of the
        // ~89,000 episodes — so both halves being present is the whole test, and
        // a wrong alias surfaces as the fetch failing.
        case "episode":
            let halves = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            guard halves.count == 2 else { return nil }
            return .episode(show: String(halves[0]), episode: String(halves[1]))
        default:
            return nil
        }
    }
}

// MARK: - Properties of `application`

/// Read (and for volume/muted, written) through key-value coding by the
/// scripting bridge. The keys here are the `<cocoa key="…">` values in the sdef.
/// Apple Events are delivered on the main thread, which is where `AppModel`
/// lives — hence `assumeIsolated` rather than a hop.
extension NSApplication {
    @objc var ntsState: String { MainActor.assumeIsolated { ScriptState.json() } }

    @objc var ntsPlaying: Bool {
        MainActor.assumeIsolated { AppModel.shared.isPlaying }
    }

    @objc var ntsRendering: Bool {
        MainActor.assumeIsolated { AppModel.shared.engine.isRendering }
    }

    @objc var ntsSource: String {
        MainActor.assumeIsolated {
            let m = AppModel.shared
            return ScriptState.sourceID(m.selection)
        }
    }

    @objc var ntsSourceName: String {
        MainActor.assumeIsolated { AppModel.shared.displayName }
    }

    @objc var ntsCurrentTrack: String {
        MainActor.assumeIsolated {
            guard let t = AppModel.shared.tracks.first else { return "" }
            return "\(t.artist) — \(t.title)"
        }
    }

    @objc var ntsVolume: Int {
        get { MainActor.assumeIsolated { Int((AppModel.shared.preferences.gain).rounded()) } }
        set { MainActor.assumeIsolated { AppModel.shared.preferences.gain = Double(newValue) } }
    }

    @objc var ntsVolumeCurve: String {
        get { MainActor.assumeIsolated { AppModel.shared.preferences.curve.kind.rawValue } }
        set {
            MainActor.assumeIsolated {
                guard let kind = VolumeCurve.Kind(rawValue: newValue) else {
                    let command = NSScriptCommand.current()
                    command?.scriptErrorNumber = -1703   // errAETypeError
                    command?.scriptErrorString = """
                        "\(newValue)" is not a volume curve. Use "linear" or "perceptual".
                        """
                    return
                }
                AppModel.shared.preferences.curve.kind = kind
            }
        }
    }

    @objc var ntsVolumeSteepness: Double {
        get { MainActor.assumeIsolated { AppModel.shared.preferences.curve.exponent } }
        set { MainActor.assumeIsolated { AppModel.shared.preferences.curve.exponent = newValue } }
    }

    @objc var ntsMuted: Bool {
        get { MainActor.assumeIsolated { AppModel.shared.preferences.muted } }
        set { MainActor.assumeIsolated { AppModel.shared.preferences.muted = newValue } }
    }

    @objc var ntsTrackLead: String {
        get { MainActor.assumeIsolated { AppModel.shared.preferences.trackLead.rawValue } }
        set {
            MainActor.assumeIsolated {
                guard let lead = TrackLead(rawValue: newValue.lowercased()) else {
                    let command = NSScriptCommand.current()
                    command?.scriptErrorNumber = -1703   // errAETypeError
                    command?.scriptErrorString = "\"\(newValue)\" is not a tracklist order. Use \"title\" or \"artist\"."
                    return
                }
                AppModel.shared.preferences.trackLead = lead
            }
        }
    }

    @objc var ntsWindowVisible: Bool {
        MainActor.assumeIsolated { RadioWindowController.scriptTarget?.isWindowVisible ?? false }
    }

    @objc var ntsKnobAngle: Double {
        MainActor.assumeIsolated { AppModel.shared.knobAngle }
    }

    @objc var ntsAutoChecksForUpdates: Bool {
        get { MainActor.assumeIsolated { AppModel.shared.preferences.autoChecksForUpdates } }
        set { MainActor.assumeIsolated { AppModel.shared.preferences.autoChecksForUpdates = newValue } }
    }

    @objc var ntsResumeLastSource: Bool {
        get { MainActor.assumeIsolated { AppModel.shared.preferences.resumeLastSource } }
        set { MainActor.assumeIsolated { AppModel.shared.preferences.resumeLastSource = newValue } }
    }
}

// MARK: - Commands

/// Shared plumbing: every command reports the state it produced, and fails with
/// a real message rather than a silent no-op when the app isn't up yet.
class NTSCommand: NSScriptCommand {
    /// How long `until rendering` holds a reply before answering anyway.
    static let settleTimeout: Duration = .seconds(10)

    /// Run `body` on the main actor and answer with the resulting state.
    /// Returning false from `body` means the command refused; it has already set
    /// the error, and the reply is that error rather than a state blob.
    ///
    /// A command whose sdef entry has an `until rendering` parameter passes
    /// `settles: true`; when the script sets it, the reply waits until the
    /// source the command chose is audible (or has failed, or was never asked to
    /// play), up to `settleTimeout`, instead of reporting a half-applied state.
    func run(settles: Bool = false, _ body: @MainActor () -> Bool) -> Any? {
        MainActor.assumeIsolated {
            guard AppModel.scriptingReady else {
                scriptErrorNumber = -1728   // errAENoSuchObject
                scriptErrorString = "NTS Radio is not finished launching."
                return nil
            }
            guard body() else { return nil }
            guard settles, (evaluatedArguments?["untilRendering"] as? Bool) == true else {
                return ScriptState.json()
            }
            // The Apple Event stays open while the main thread keeps running, so
            // the player can make the progress being waited for.
            suspendExecution()
            nonisolated(unsafe) let command = self
            let started = ContinuousClock.now
            Task { @MainActor in
                let m = AppModel.shared
                while !m.isSettled, ContinuousClock.now - started < Self.settleTimeout {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                Log.app.info("""
                    script \(command.commandDescription.commandName, privacy: .public) settled \
                    after \(String(describing: ContinuousClock.now - started), privacy: .public) \
                    source=\(ScriptState.sourceID(m.selection), privacy: .public) \
                    rendering=\(m.engine.isRendering) error=\(m.episodeError ?? "", privacy: .public)
                    """)
                command.resumeExecution(withResult: ScriptState.json())
            }
            return nil
        }
    }
}

extension AppModel {
    /// Whether there is nothing left to wait for after tuning: the audio is
    /// coming out, the episode fetch failed, or playback was never asked for
    /// (a skip while paused stays paused, so it would never render).
    var isSettled: Bool {
        if episodeError != nil { return true }
        if episodeLoading { return false }
        return engine.isRendering || !engine.isPlaying
    }
}

@objc(NTSTuneCommand)
final class NTSTuneCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run(settles: true) {
            let text = (self.directParameter as? String) ?? ""
            guard let selection = ScriptState.selection(from: text) else {
                self.scriptErrorNumber = -1703   // errAETypeError
                self.scriptErrorString = """
                    \"\(text)\" is not a source. Use mixtape:<alias>, channel:<number>, \
                    episode:<show>/<episode> or idle — for example mixtape:rap-house or channel:1.
                    """
                return false
            }
            AppModel.shared.select(selection)
            return true
        }
    }
}

@objc(NTSPlayCommand)
final class NTSPlayCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            AppModel.shared.play()
            return true
        }
    }
}

@objc(NTSPauseCommand)
final class NTSPauseCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            AppModel.shared.pause()
            return true
        }
    }
}

@objc(NTSSkipCommand)
final class NTSSkipCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run(settles: true) {
            let m = AppModel.shared
            // The media keys hold an episode or idle where it is; a script gets
            // told so, rather than a reply it can't tell from a skip that worked.
            switch m.selection {
            case .idle, .episode:
                self.scriptErrorNumber = -1708   // errAEEventNotHandled
                self.scriptErrorString = m.isIdle
                    ? "Nothing is tuned, so there is nothing to skip from. Tune a mixtape or a channel first."
                    : """
                      An episode is not part of a group, so there is no neighbour to skip to. \
                      Tune a mixtape or a channel first.
                      """
                return false
            case .mixtape, .channel:
                break
            }
            let by = (self.evaluatedArguments?["by"] as? Int) ?? 1
            m.step(by: by)
            return true
        }
    }
}

/// `stop` — back to idle, the state the app launches in: nothing tuned and no
/// stream open. `pause` keeps the source; this lets a script put things back.
@objc(NTSStopCommand)
final class NTSStopCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            AppModel.shared.select(.idle)
            return true
        }
    }
}

@objc(NTSOpenWindowCommand)
final class NTSOpenWindowCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            RadioWindowController.scriptTarget?.showWithoutActivating()
            return true
        }
    }
}

@objc(NTSCloseWindowCommand)
final class NTSCloseWindowCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            RadioWindowController.scriptTarget?.hide()
            return true
        }
    }
}

@objc(NTSFilterExploreCommand)
final class NTSFilterExploreCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            let m = AppModel.shared
            let args = self.evaluatedArguments ?? [:]

            // The whole filter is replaced rather than merged: a caller that
            // sends only a mood means "just this mood", and a merge would leave
            // yesterday's genres silently ANDed in.
            var filters = NTSAPI.ExploreFilters()
            filters.mood = (args["mood"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            filters.genres = (args["genres"] as? [String]) ?? []
            filters.musicOnly = (args["musicOnly"] as? Bool) ?? false
            filters.focused = (args["focused"] as? Bool) ?? false

            if let mood = filters.mood, !m.moods.isEmpty,
               !m.moods.contains(where: { $0.id == mood }) {
                self.scriptErrorNumber = -1703   // errAETypeError
                self.scriptErrorString = """
                    \"\(mood)\" is not a mood. Use one of: \
                    \(m.moods.map(\.id).joined(separator: ", ")).
                    """
                return false
            }

            // Same check as the mood above, for the same reason: an id NTS does
            // not file matches nothing, so the feed returns empty and the caller
            // reads a typo as a genuine "no episodes match".
            if let bad = filters.genres.first(where: { !m.genreIDs.contains($0) }) {
                self.scriptErrorNumber = -1703   // errAETypeError
                self.scriptErrorString = m.genres.isEmpty
                    ? "The genre list hasn't loaded yet — try again in a moment."
                    : """
                      \"\(bad)\" is not a genre id. `browse genre` takes the name \
                      as the card prints it, e.g. browse genre \"Kosmische\".
                      """
                return false
            }

            // Filtering implies looking: the chips this stands in for only exist
            // while the catalog is up, so a filter set against a closed catalog
            // would report results nobody can see.
            m.catalogTab = .explore
            m.query = ""
            m.detail = nil
            m.show(.catalog)
            m.explore.filters = filters
            return true
        }
    }
}

@objc(NTSExploreMoreCommand)
final class NTSExploreMoreCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            AppModel.shared.explore.loadMore()
            return true
        }
    }
}

@objc(NTSSaveCommand)
final class NTSSaveCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            let m = AppModel.shared
            let raw = ((self.directParameter as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                self.scriptErrorNumber = -1703   // errAETypeError
                self.scriptErrorString = """
                    Give a show alias or episode:<show>/<episode>, e.g. \
                    save "lung-dart" or save "episode:lung-dart/lung-dart-10th-august-2026".
                    """
                return false
            }
            // `episode:<show>/<episode>` saves the episode, not its show — the
            // same distinction `tune to` already makes.
            if raw.hasPrefix("episode:") {
                let value = String(raw.dropFirst("episode:".count))
                let halves = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
                guard halves.count == 2 else {
                    self.scriptErrorNumber = -1703
                    self.scriptErrorString = """
                        episode:<show>/<episode> needs both halves, e.g. \
                        episode:lung-dart/lung-dart-10th-august-2026.
                        """
                    return false
                }
                let show = String(halves[0]), episode = String(halves[1])
                m.saved.toggle(Saved.Item(kind: .episode, alias: show, episodeAlias: episode,
                                          title: ShowIndex.title(from: episode), subtitle: "", image: nil))
                return true
            }
            let indexed = m.showIndex.ref(raw)
            m.saved.toggle(Saved.Item(kind: .show, alias: raw,
                                      title: indexed?.name ?? ShowIndex.title(from: raw),
                                      subtitle: indexed?.location ?? "",
                                      image: indexed?.picture))
            return true
        }
    }
}

/// A show's page in the archive — the pane carrying its blurb, its genre and
/// mood tags and its episode list. Clicking a tile is the only other way in, so
/// without this nothing about that pane can be driven or read back.
@objc(NTSOpenShowCommand)
final class NTSOpenShowCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            let m = AppModel.shared
            let alias = (self.directParameter as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alias.isEmpty else {
                self.scriptErrorNumber = -1703   // errAETypeError
                self.scriptErrorString = "Give a show alias, e.g. open show \"veronica-vasicka\"."
                return false
            }
            m.query = ""
            m.show(.catalog)
            m.detail = .show(alias: alias, fallbackTitle: ShowIndex.title(from: alias))
            Task { await m.loadShow(alias) }
            return true
        }
    }
}

/// The channel card's genre chip, scripted. It takes the genre by the name the
/// card prints rather than by an Explore id, because that translation is the
/// part worth being able to drive: NTS tags episodes with genres Explore does
/// not file, and those chips are deliberately left as plain text.
@objc(NTSBrowseCommand)
final class NTSBrowseCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            let m = AppModel.shared
            let name = (self.directParameter as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                self.scriptErrorNumber = -1703   // errAETypeError
                self.scriptErrorString = "Give a genre as the card prints it, e.g. browse genre \"Kosmische\"."
                return false
            }
            guard let id = m.genreID(named: name) else {
                self.scriptErrorNumber = -1703
                self.scriptErrorString = m.genres.isEmpty
                    ? "The genre list hasn't loaded yet — try again in a moment."
                    : "\"\(name)\" is not a genre Explore files. The card leaves that chip as plain text."
                return false
            }
            m.browseGenre(id)
            return true
        }
    }
}

@objc(NTSSeekCommand)
final class NTSSeekCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            let m = AppModel.shared
            guard m.engine.isSeekable else {
                self.scriptErrorNumber = -1708   // errAEEventNotHandled
                self.scriptErrorString = """
                    What’s tuned has no position to seek to — the channels and the \
                    mixtapes are continuous streams. Tune an episode first.
                    """
                return false
            }
            let seconds = (self.directParameter as? NSNumber)?.doubleValue ?? 0
            m.engine.seek(to: seconds)
            return true
        }
    }
}

@objc(NTSOpenCatalogCommand)
final class NTSOpenCatalogCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            let m = AppModel.shared
            if let name = self.evaluatedArguments?["showing"] as? String,
               !name.isEmpty {
                guard let tab = CatalogTab(rawValue: name.lowercased()) else {
                    self.scriptErrorNumber = -1703   // errAETypeError
                    self.scriptErrorString = """
                        \"\(name)\" is not a catalog list. Use \
                        \(CatalogTab.allCases.map(\.rawValue).joined(separator: ", ")).
                        """
                    return false
                }
                m.catalogTab = tab
            }
            if let channel = self.evaluatedArguments?["channel"] as? Int {
                guard m.catalog.channels.contains(where: { $0.number == channel }) else {
                    self.scriptErrorNumber = -1703   // errAETypeError
                    self.scriptErrorString = "NTS \(channel) is not a channel. Use 1 or 2."
                    return false
                }
                m.scheduleChannel = channel
            }
            m.query = (self.evaluatedArguments?["searchingFor"] as? String) ?? ""
            m.detail = nil
            m.show(.catalog)
            return true
        }
    }
}

/// `open settings` — the same window the gear in the title bar and the status
/// item's Settings… item open. It exists so the window can be raised and looked
/// at without a mouse; every other route into it is a click. Unlike those, it
/// does not activate the app, so a script never takes keyboard focus.
@objc(NTSOpenSettingsCommand)
final class NTSOpenSettingsCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            let name = (self.directParameter as? String)?.lowercased() ?? ""
            var pane: SettingsPane?
            if !name.isEmpty {
                guard let named = SettingsPane(rawValue: name) else {
                    self.scriptErrorNumber = -1703   // errAETypeError
                    self.scriptErrorString = "\"\(name)\" is not a settings pane. Use general or account."
                    return false
                }
                pane = named
            }
            SettingsWindowController.shared.showWithoutActivating(pane)
            return true
        }
    }
}

@objc(NTSCloseSettingsCommand)
final class NTSCloseSettingsCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            SettingsWindowController.shared.hide()
            return true
        }
    }
}

/// `show pane "tracks"` — the scripted half of the segmented switch in the
/// now-playing bar. It goes through `AppModel.show(_:)`, the same call the
/// segments make, so a script cannot reach a combination the buttons cannot.
@objc(NTSShowPaneCommand)
final class NTSShowPaneCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            let m = AppModel.shared
            let name = (self.directParameter as? String)?.lowercased() ?? ""
            switch name {
            case "live": m.show(.live)
            case "catalog": m.show(.catalog)
            // The drawer is not a pane, but a script asking for it by name means
            // one thing only, and refusing on a technicality would be unhelpful.
            // "show" opens — it does not toggle, or a script could not put the
            // drawer up without first reading whether it was already there.
            case "tracks", "tracklist":
                guard !m.isIdle else {
                    self.scriptErrorNumber = -1728   // errAENoSuchObject
                    self.scriptErrorString = "Nothing is playing, so there is no tracklist to show."
                    return false
                }
                m.tracksOpen = true
            case "none":
                m.tracksOpen = false
            default:
                self.scriptErrorNumber = -1703   // errAETypeError
                self.scriptErrorString =
                    "\"\(name)\" is not a pane. Use live or catalog; tracks raises the tracklist drawer over either, none drops it."
                return false
            }
            return true
        }
    }
}

@objc(NTSCloseCatalogCommand)
final class NTSCloseCatalogCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            let m = AppModel.shared
            guard m.catalogOpen else { return true }
            m.toggleCatalog()
            return true
        }
    }
}

/// The same call the status menu's and the main menu's "Check for Updates…"
/// items make. Sparkle owns everything past this point — the network fetch,
/// and any window it puts up to report what it found or that the appcast
/// could not be reached.
@objc(NTSCheckForUpdatesCommand)
final class NTSCheckForUpdatesCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            AppModel.shared.preferences.checkForUpdates()
            return true
        }
    }
}
