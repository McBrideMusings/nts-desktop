import Foundation

/// Everything observable about the app, typed. This is the other half of the
/// contract `ScriptState.json()` used to assemble by hand as a 54-key
/// `[String: Any]` with nothing tying it to the state it mirrored — a new
/// published property meant a second, manual edit here or the control surface
/// silently drifted from what the interface shows. Adding a field to this
/// struct without populating it in `AppModel.stateSnapshot()` fails the build,
/// because Swift requires every stored property to be initialized at the call
/// site that constructs one.
///
/// No custom `CodingKeys` — every property name below is already the wire
/// name the AppleScript dictionary (`mac/Resources/NTSRadio.sdef`) expects, so
/// the synthesized keys are a 1:1 mapping and a rename shows up as a diff.
struct StateSnapshot: Codable {
    var running: Bool
    var playing: Bool
    var rendering: Bool
    var source: String
    var sourceName: String
    var subtitle: String
    var currentTrack: String
    var trackCount: Int
    /// The secondary label's link — the nts.live episode page for a mixtape's
    /// current source episode (resolved from the sitemap when Firestore left
    /// the aliases empty). Empty when there is none to show.
    var episodeURL: String

    /// Audio held but not yet played — how far the speakers trail the
    /// stream, and so how far ahead of them the tracklist runs.
    var bufferSeconds: Double
    /// A track that has started upstream but is being held back until the
    /// audio carrying it is actually audible.
    var pendingTrack: String
    var pendingSeconds: Double
    var volume: Int
    /// The knob's position, 0–100; `volume` is the output level it maps to.
    var volumeSlider: Int
    var volumeCurve: String
    var volumeSteepness: Double
    var muted: Bool
    var signedIn: Bool
    var savedCount: Int
    /// Every saved item's id in the Saved tab's order — `show:<alias>`,
    /// `mixtape:<alias>` or `episode:<show>/<episode>` — so a script can tell
    /// which item `save` added (it goes first) or removed, not only that the
    /// count moved.
    var savedKeys: [String]
    /// Whether the account's own follows and saved episodes have actually
    /// been read. Without this, "nothing on the account" and "never asked"
    /// are the same empty list.
    var syncedWithAccount: Bool

    /// An episode takes two requests before any audio exists, either of
    /// which can fail. Without these, a stuck resolve and a playing episode
    /// both read as "not playing".
    var episodeLoading: Bool
    var episodeError: String
    var episodeStream: String

    /// Where the playhead is, and whether it can be moved at all. The seek
    /// bar's whole rule is `seekable` — reading it back is how a script
    /// checks the bar is absent for a live channel without looking at
    /// pixels.
    var seekable: Bool
    var position: Double
    var duration: Double

    /// Whether nts.live is answering. A stale catalog and a healthy one hold
    /// the same contents, so this is the only way a script can tell "nothing
    /// new" from "nothing got through".
    var outage: OutageSnapshot

    var windowVisible: Bool
    /// Whether the radio UI is in its window. False while the window is closed
    /// (and before it is first built): a closed window keeps no SwiftUI
    /// content, so it does no work on a model change. A miniaturised window
    /// keeps it.
    var windowContentAttached: Bool
    /// Settings is its own window, so "is it up" is not answerable from
    /// anything about the radio window. Without these a script could open it
    /// and have no way to tell that it had.
    var settingsVisible: Bool
    var settingsPane: String

    /// Where the window is — "live" or "catalog" — and whether the
    /// tracklist drawer is over it. Two separate facts because they are two
    /// separate things: the drawer covers a pane without changing which
    /// pane you are in, so reading only one of them would report a window
    /// covered by the tracklist as though nothing were on screen.
    var pane: String
    var tracksOpen: Bool
    var catalogOpen: Bool
    /// What the catalog is actually listing. Without these, a list that
    /// came back empty and one that was never asked for read the same.
    var catalogTab: String

    /// Explore's filters and how much they matched. A grid of twelve
    /// episodes says nothing about why those twelve, so the filters are
    /// reported alongside the count they produced.
    var exploreMood: String
    var exploreGenres: [String]
    var exploreMusicOnly: Bool
    var exploreFocused: Bool
    var exploreLoaded: Int
    var exploreTotal: Int
    var exploreLoading: Bool
    var moodCount: Int
    var genreCount: Int

    /// Which detail pane is open over the grid, and the tags it draws. A
    /// pane covering the whole catalog was invisible from here — the grid's
    /// own fields keep describing the list underneath it — and its tags are
    /// chips you can click, so what they say is behaviour rather than
    /// decoration. `detailError` is why the open show's page fetch failed, so
    /// a failed fetch and one still in flight don't both read as no tags.
    var catalogDetail: String
    var detailTags: [String]
    var detailError: String
    var catalogQuery: String
    var catalogRows: Int
    var catalogFirstRows: [String]

    /// The timeline draws itself from these three, and none of them are
    /// readable off a tile grid: which channel it is showing, how many days
    /// it grouped the grid into, and what it calls on air.
    var scheduleChannel: Int
    var scheduleDays: [String]
    /// Slots in the timeline whose end has passed. Both writers of the grid
    /// drop them, so this is 0 except for the second after a changeover and the
    /// minute after a wake from sleep, before the advance catches up.
    var scheduleEnded: Int
    var onAir: String
    var nextUp: String

    /// The show index's own coverage: how many shows it knows about at all,
    /// how many have their real name/location/description backfilled
    /// (`ShowRef.detailed != nil`), how many are still queued, and whether
    /// the backfill is actively running right now — so a script can watch a
    /// fresh machine's crawl finish without polling pixels.
    var showIndex: ShowIndexSnapshot

    var mixtapeCount: Int
    var channelCount: Int
    /// What each channel is airing, readable whatever the app is playing —
    /// `sourceName` only ever describes the current source, so with a
    /// mixtape on, the rail's contents were unobservable from outside.
    var channels: [ChannelSnapshot]

    /// Unwrapped, so consecutive readings show which way the dial turned
    /// and by how much — a step of -22.5 and one of +337.5 land the index
    /// mark in the same place but are not the same movement.
    var knobAngle: Double

    /// Sparkle's own state — otherwise "did Check for Updates actually do
    /// anything" is only answerable by watching a window appear.
    var autoChecksForUpdates: Bool
    var canCheckForUpdates: Bool

    /// Where `app.log` and `tracks.log` are written, and which sources the
    /// recorder is currently subscribed to (empty while signed out) — the
    /// two facts a script needs before it reads those files.
    var logDirectory: String
    var recordedSources: [String]

    /// Which line leads a tracklist row — "title" or "artist".
    var trackLead: String

    /// Whether launch tunes `lastSource`, and the channel or mixtape it would
    /// tune — "" when idle or an episode was the last thing tuned.
    var resumeLastSource: Bool
    var lastSource: String

    /// What the engine is doing about a stream that should be playing and
    /// is silent. `playing` and `rendering` say that it is silent; this says
    /// whether anything is being done about it, and what mended it last time.
    var recovery: RecoverySnapshot
}

/// `PlayerEngine`'s recovery state, mirrored for `StateSnapshot.recovery`.
/// Times are ISO 8601, "" when the thing has not happened since launch.
struct RecoverySnapshot: Codable {
    /// Whether what is loaded is a channel or a mixtape — the only kind
    /// recovery reloads.
    var endless: Bool
    /// Reloads since audio last came out and held for `StallWatch.settle`; 0
    /// when no recovery is under way.
    var attempts: Int
    var reason: String
    var lastAttempt: String
    /// Streaks that ended with audio holding again, since launch.
    var recoveries: Int
    var lastRecovered: String
    /// "satisfied", "unsatisfied", or "unknown" before the first report.
    var network: String
}

/// `ShowIndex`'s coverage, mirrored for `StateSnapshot.showIndex`.
struct ShowIndexSnapshot: Codable {
    var shows: Int
    var named: Int
    var remaining: Int
    var running: Bool
}

/// One channel's rail, mirroring `AppModel.catalog.channels`.
struct ChannelSnapshot: Codable {
    var number: Int
    var show: String
    var startEnd: String
    /// How much programme grid the channel is holding.
    var slots: Int
    /// How much of it is usable — a slot with no show alias can't be opened.
    var slotsWithShow: Int
    /// A slot with no episode alias renders as an empty sleeve.
    var slotsWithEpisode: Int
    /// `upcoming` leads with the programme that is on air, so this drops
    /// that first slot — a channel stuck on the 8 o'clock show while its
    /// "next" said 9 o'clock made a plain stale-data bug look like nonsense.
    /// What is on and what is next are two different fields that cannot be
    /// confused.
    var nextSlots: [String]
}

/// `ServiceStatus.shared.outage`, typed. The baseline reports `"outage": {}`
/// when nothing is wrong — not `null`, and not an absent key — so this is not
/// an `Optional`: `encodeIfPresent` on an optional would drop or null the key.
/// `.none` encodes as an empty keyed container, which serializes to `{}`;
/// `.present` writes the same five fields the dictionary literal used to.
/// `since` is deliberately not reported (see `ServiceStatus.Outage`).
enum OutageSnapshot: Codable {
    case none
    case present(what: String, headline: String, detail: String, endpoint: String, failures: Int)

    private enum CodingKeys: String, CodingKey {
        case what, headline, detail, endpoint, failures
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            break
        case .present(let what, let headline, let detail, let endpoint, let failures):
            try container.encode(what, forKey: .what)
            try container.encode(headline, forKey: .headline)
            try container.encode(detail, forKey: .detail)
            try container.encode(endpoint, forKey: .endpoint)
            try container.encode(failures, forKey: .failures)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let what = try container.decodeIfPresent(String.self, forKey: .what) {
            self = .present(
                what: what,
                headline: try container.decode(String.self, forKey: .headline),
                detail: try container.decode(String.self, forKey: .detail),
                endpoint: try container.decode(String.self, forKey: .endpoint),
                failures: try container.decode(Int.self, forKey: .failures)
            )
        } else {
            self = .none
        }
    }
}

extension AppModel {
    /// The state the scripting layer reports, built beside the state it
    /// mirrors so the two cannot drift apart unnoticed.
    @MainActor
    func stateSnapshot() -> StateSnapshot {
        let track = currentTrack
        let outage: OutageSnapshot
        if let o = ServiceStatus.shared.outage {
            outage = .present(what: o.what, headline: o.headline, detail: o.detail,
                               endpoint: o.endpoint.rawValue, failures: o.failures)
        } else {
            outage = .none
        }
        return StateSnapshot(
            running: true,
            playing: isPlaying,
            rendering: engine.isRendering,
            source: ScriptState.sourceID(selection),
            sourceName: displayName,
            subtitle: subtitle,
            currentTrack: track.map { "\($0.artist) — \($0.title)" } ?? "",
            trackCount: tracks.count,
            episodeURL: nowPlayingEpisodeURL?.absoluteString ?? "",
            bufferSeconds: (engine.bufferedAhead * 10).rounded() / 10,
            pendingTrack: pendingTrack?.name ?? "",
            pendingSeconds: pendingTrack?.seconds ?? 0,
            volume: Int(preferences.gain.rounded()),
            volumeSlider: Int(preferences.slider.rounded()),
            volumeCurve: preferences.curve.kind.rawValue,
            volumeSteepness: preferences.curve.exponent,
            muted: preferences.muted,
            signedIn: auth.isAuthenticated,
            savedCount: saved.items.count,
            savedKeys: saved.items.map(\.id),
            syncedWithAccount: saved.syncedWithAccount,
            episodeLoading: episodeLoading,
            episodeError: episodeError ?? "",
            episodeStream: engine.currentURLString,
            seekable: engine.isSeekable,
            position: (engine.position * 10).rounded() / 10,
            duration: (engine.duration * 10).rounded() / 10,
            outage: outage,
            windowVisible: RadioWindowController.scriptTarget?.isWindowVisible ?? false,
            windowContentAttached: RadioWindowController.scriptTarget?.isContentAttached ?? false,
            settingsVisible: SettingsWindowController.shared.isVisible,
            settingsPane: SettingsWindowController.shared.visiblePane.rawValue,
            pane: {
                switch pane {
                case .live: return "live"
                case .catalog: return "catalog"
                }
            }(),
            tracksOpen: tracksOpen,
            catalogOpen: catalogOpen,
            catalogTab: catalogTab.rawValue,
            exploreMood: explore.filters.mood ?? "",
            exploreGenres: explore.filters.genres,
            exploreMusicOnly: explore.filters.musicOnly,
            exploreFocused: explore.filters.focused,
            exploreLoaded: explore.episodes.count,
            exploreTotal: explore.total,
            exploreLoading: explore.loading,
            moodCount: moods.count,
            genreCount: genres.count,
            catalogDetail: {
                switch detail {
                case .none: return ""
                case .show(let alias, _): return "show:\(alias)"
                case .mixtape(let alias): return "mixtape:\(alias)"
                }
            }(),
            detailTags: {
                guard case .show(let alias, _) = detail else { return [] }
                let d = showDetail.details[alias]
                return (d?.genres ?? []) + (d?.moods ?? [])
            }(),
            detailError: {
                guard case .show(let alias, _) = detail else { return "" }
                return showDetail.detailErrors[alias] ?? ""
            }(),
            catalogQuery: query,
            catalogRows: catalogRows.count,
            catalogFirstRows: catalogRows.prefix(3).map { "\($0.title) · \($0.meta)" },
            scheduleChannel: timeline.channel.rawValue,
            scheduleDays: timeline.days.map { "\($0.label) · \($0.slots.count)" },
            scheduleEnded: timeline.days.flatMap(\.slots).filter { ($0.end ?? .distantFuture) <= Date() }.count,
            onAir: timeline.onAir.map { "\($0.startEnd) \($0.title)" } ?? "",
            nextUp: timeline.next.map { "\($0.startEnd) \($0.title)" } ?? "",
            showIndex: ShowIndexSnapshot(
                shows: showIndex.count,
                named: showIndex.count - backfill.remaining,
                remaining: backfill.remaining,
                running: backfill.running
            ),
            mixtapeCount: catalog.mixtapes.count,
            channelCount: catalog.channels.count,
            channels: catalog.channels.map { ch in
                ChannelSnapshot(
                    number: ch.number.rawValue,
                    show: ch.show,
                    startEnd: ch.startEnd,
                    slots: ch.upcoming.count,
                    slotsWithShow: ch.upcoming.filter { !$0.showAlias.isEmpty }.count,
                    slotsWithEpisode: ch.upcoming.filter { !$0.episodeAlias.isEmpty }.count,
                    nextSlots: ch.upcoming.dropFirst().prefix(3).map {
                        "\($0.startEnd) \($0.title) [\($0.showAlias)]"
                    }
                )
            },
            knobAngle: (knobAngle * 100).rounded() / 100,
            autoChecksForUpdates: preferences.autoChecksForUpdates,
            canCheckForUpdates: preferences.canCheckForUpdates,
            logDirectory: LogFiles.directory.path,
            recordedSources: recording.sources,
            trackLead: preferences.trackLead.rawValue,
            resumeLastSource: preferences.resumeLastSource,
            lastSource: preferences.lastSource ?? "",
            recovery: RecoverySnapshot(
                endless: engine.isEndless,
                attempts: engine.recoveryAttempts,
                reason: engine.recoveryReason,
                lastAttempt: engine.lastRecoveryAttempt.map(LogFiles.stamp) ?? "",
                recoveries: engine.recoveries,
                lastRecovered: engine.lastRecovered.map(LogFiles.stamp) ?? "",
                network: engine.networkSatisfied.map { $0 ? "satisfied" : "unsatisfied" } ?? "unknown"
            )
        )
    }
}
