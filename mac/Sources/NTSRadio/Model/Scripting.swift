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
    /// The live model, published for the scripting commands. Set once by the
    /// AppDelegate at launch and never reassigned; nil under `NTS_SNAPSHOT`,
    /// which builds no model and exits.
    @MainActor static weak var scriptTarget: AppModel?
}

extension RadioWindowController {
    /// The live window controller, for the window commands. Same lifetime rules
    /// as `AppModel.scriptTarget`.
    @MainActor static weak var scriptTarget: RadioWindowController?
}

// MARK: - The state blob

@MainActor
enum ScriptState {
    /// Everything observable about the app, as a JSON object. Every command
    /// returns this too, so one round trip both acts and reports.
    static func json() -> String {
        guard let m = AppModel.scriptTarget else {
            return #"{"running":false}"#
        }
        let track = m.currentTrack
        let dict: [String: Any] = [
            "running": true,
            "playing": m.isPlaying,
            "rendering": m.engine.isRendering,
            "source": sourceID(m.selection),
            "sourceName": m.displayName,
            "subtitle": m.subtitle,
            "currentTrack": track.map { "\($0.artist) — \($0.title)" } ?? "",
            "trackCount": m.tracks.count,
            // Audio held but not yet played — how far the speakers trail the
            // stream, and so how far ahead of them the tracklist runs.
            "bufferSeconds": (m.engine.bufferedAhead * 10).rounded() / 10,
            // A track that has started upstream but is being held back until the
            // audio carrying it is actually audible.
            "pendingTrack": m.pendingTrack?.name ?? "",
            "pendingSeconds": m.pendingTrack?.seconds ?? 0,
            "volume": Int(m.volume.rounded()),
            "muted": m.muted,
            "signedIn": m.auth.isAuthenticated,
            // Whether the account's own follows and saved episodes have
            // actually been read. Without this, "nothing on the account" and
            // "never asked" are the same empty list.
            "savedCount": m.saved.items.count,
            "syncedWithAccount": m.saved.syncedWithAccount,
            // An episode takes two requests before any audio exists, either of
            // which can fail. Without these, a stuck resolve and a playing
            // episode both read as "not playing".
            "episodeLoading": m.episodeLoading,
            "episodeError": m.episodeError ?? "",
            "episodeStream": m.engine.currentURLString,
            // Where the playhead is, and whether it can be moved at all. The
            // seek bar's whole rule is `seekable` — reading it back is how a
            // script checks the bar is absent for a live channel without
            // looking at pixels.
            "seekable": m.engine.isSeekable,
            "position": (m.engine.position * 10).rounded() / 10,
            "duration": (m.engine.duration * 10).rounded() / 10,
            // Whether nts.live is answering. A stale catalog and a healthy one
            // hold the same contents, so this is the only way a script can tell
            // "nothing new" from "nothing got through".
            "outage": ServiceStatus.shared.outage.map {
                ["what": $0.what, "headline": $0.headline, "detail": $0.detail,
                 "endpoint": $0.endpoint, "failures": $0.failures] as [String: Any]
            } ?? [:],
            "windowVisible": RadioWindowController.scriptTarget?.isWindowVisible ?? false,
            "catalogOpen": m.catalogOpen,
            // What the catalog is actually listing. Without these, a list that
            // came back empty and one that was never asked for read the same.
            "catalogTab": m.catalogTab.rawValue,
            // Explore's filters and how much they matched. A grid of twelve
            // episodes says nothing about why those twelve, so the filters are
            // reported alongside the count they produced.
            "exploreMood": m.exploreFilters.mood ?? "",
            "exploreGenres": m.exploreFilters.genres,
            "exploreMusicOnly": m.exploreFilters.musicOnly,
            "exploreFocused": m.exploreFilters.focused,
            "exploreLoaded": m.exploreEpisodes.count,
            "exploreTotal": m.exploreTotal,
            "exploreLoading": m.exploreLoading,
            "moodCount": m.moods.count,
            "genreCount": m.genres.count,
            "catalogQuery": m.query,
            "catalogRows": m.catalogRows.count,
            "catalogFirstRows": m.catalogRows.prefix(3).map { "\($0.title) · \($0.meta)" },
            // The timeline draws itself from these three, and none of them are
            // readable off a tile grid: which channel it is showing, how many
            // days it grouped the grid into, and what it calls on air.
            "scheduleChannel": m.scheduleChannel,
            "scheduleDays": m.scheduleDays.map { "\($0.label) · \($0.slots.count)" },
            "onAir": m.onAirSlot.map { "\($0.startEnd) \($0.title)" } ?? "",
            "nextUp": m.nextSlot.map { "\($0.startEnd) \($0.title)" } ?? "",
            "mixtapeCount": m.catalog.mixtapes.count,
            "channelCount": m.catalog.channels.count,
            // What each channel is airing, readable whatever the app is playing —
            // `sourceName` only ever describes the current source, so with a
            // mixtape on, the rail's contents were unobservable from outside.
            // `slots` is how much programme grid the channel is holding; the two
            // counts beside it are how much of it is usable — a slot with no show
            // alias can't be opened, and one with no artwork renders as an empty
            // sleeve. Both were unreadable from outside, so a schedule that
            // silently lost its links looked identical to a healthy one.
            "channels": m.catalog.channels.map { ch -> [String: Any] in
                ["number": ch.number, "show": ch.show, "startEnd": ch.startEnd,
                 "slots": ch.upcoming.count,
                 "slotsWithShow": ch.upcoming.filter { !$0.showAlias.isEmpty }.count,
                 "slotsWithEpisode": ch.upcoming.filter { !$0.episodeAlias.isEmpty }.count,
                 "nextSlots": ch.upcoming.prefix(3).map {
                     "\($0.startEnd) \($0.title) [\($0.showAlias)]"
                 }]
            },
            // Unwrapped, so consecutive readings show which way the dial turned
            // and by how much — a step of -22.5 and one of +337.5 land the index
            // mark in the same place but are not the same movement.
            "knobAngle": (m.knobAngle * 100).rounded() / 100,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict,
                                                     options: [.sortedKeys, .prettyPrinted]),
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
        guard let m = AppModel.scriptTarget else { return nil }
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        MainActor.assumeIsolated { AppModel.scriptTarget?.isPlaying ?? false }
    }

    @objc var ntsRendering: Bool {
        MainActor.assumeIsolated { AppModel.scriptTarget?.engine.isRendering ?? false }
    }

    @objc var ntsSource: String {
        MainActor.assumeIsolated {
            guard let m = AppModel.scriptTarget else { return "idle" }
            return ScriptState.sourceID(m.selection)
        }
    }

    @objc var ntsSourceName: String {
        MainActor.assumeIsolated { AppModel.scriptTarget?.displayName ?? "" }
    }

    @objc var ntsCurrentTrack: String {
        MainActor.assumeIsolated {
            guard let t = AppModel.scriptTarget?.tracks.first else { return "" }
            return "\(t.artist) — \(t.title)"
        }
    }

    @objc var ntsVolume: Int {
        get { MainActor.assumeIsolated { Int((AppModel.scriptTarget?.volume ?? 0).rounded()) } }
        set { MainActor.assumeIsolated { AppModel.scriptTarget?.volume = Double(min(100, max(0, newValue))) } }
    }

    @objc var ntsMuted: Bool {
        get { MainActor.assumeIsolated { AppModel.scriptTarget?.muted ?? false } }
        set { MainActor.assumeIsolated { AppModel.scriptTarget?.muted = newValue } }
    }

    @objc var ntsWindowVisible: Bool {
        MainActor.assumeIsolated { RadioWindowController.scriptTarget?.isWindowVisible ?? false }
    }

    @objc var ntsKnobAngle: Double {
        MainActor.assumeIsolated { AppModel.scriptTarget?.knobAngle ?? 0 }
    }
}

// MARK: - Commands

/// Shared plumbing: every command reports the state it produced, and fails with
/// a real message rather than a silent no-op when the app isn't up yet.
class NTSCommand: NSScriptCommand {
    /// Run `body` on the main actor and answer with the resulting state.
    /// Returning nil from `body` means the command refused; it has already set
    /// the error, and the reply is that error rather than a state blob.
    func run(_ body: @MainActor () -> Bool) -> Any? {
        MainActor.assumeIsolated {
            guard AppModel.scriptTarget != nil else {
                scriptErrorNumber = -1728   // errAENoSuchObject
                scriptErrorString = "NTS Radio is not finished launching."
                return nil
            }
            guard body() else { return nil }
            return ScriptState.json()
        }
    }
}

@objc(NTSTuneCommand)
final class NTSTuneCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            let text = (self.directParameter as? String) ?? ""
            guard let selection = ScriptState.selection(from: text) else {
                self.scriptErrorNumber = -1703   // errAETypeError
                self.scriptErrorString = """
                    \"\(text)\" is not a source. Use mixtape:<alias> or channel:<number> \
                    — for example mixtape:rap-house or channel:1.
                    """
                return false
            }
            AppModel.scriptTarget?.select(selection)
            return true
        }
    }
}

@objc(NTSPlayCommand)
final class NTSPlayCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            AppModel.scriptTarget?.play()
            return true
        }
    }
}

@objc(NTSPauseCommand)
final class NTSPauseCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            AppModel.scriptTarget?.pause()
            return true
        }
    }
}

@objc(NTSSkipCommand)
final class NTSSkipCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            let by = (self.evaluatedArguments?["by"] as? Int) ?? 1
            AppModel.scriptTarget?.step(by: by)
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
            guard let m = AppModel.scriptTarget else { return false }
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

            // Filtering implies looking: the chips this stands in for only exist
            // while the catalog is up, so a filter set against a closed catalog
            // would report results nobody can see.
            m.catalogTab = .explore
            m.query = ""
            m.detail = nil
            m.catalogOpen = true
            m.exploreFilters = filters
            return true
        }
    }
}

@objc(NTSExploreMoreCommand)
final class NTSExploreMoreCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            AppModel.scriptTarget?.loadMoreExplore()
            return true
        }
    }
}

@objc(NTSStarCommand)
final class NTSStarCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            guard let m = AppModel.scriptTarget else { return false }
            let raw = ((self.directParameter as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                self.scriptErrorNumber = -1703   // errAETypeError
                self.scriptErrorString = """
                    Give a show alias or episode:<show>/<episode>, e.g. \
                    star "lung-dart" or star "episode:lung-dart/lung-dart-10th-august-2026".
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

@objc(NTSSeekCommand)
final class NTSSeekCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            guard let m = AppModel.scriptTarget else { return false }
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
            guard let m = AppModel.scriptTarget else { return false }
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
            m.catalogOpen = true
            return true
        }
    }
}

@objc(NTSCloseCatalogCommand)
final class NTSCloseCatalogCommand: NTSCommand {
    override func performDefaultImplementation() -> Any? {
        run {
            guard let m = AppModel.scriptTarget, m.catalogOpen else { return true }
            m.toggleCatalog()
            return true
        }
    }
}
