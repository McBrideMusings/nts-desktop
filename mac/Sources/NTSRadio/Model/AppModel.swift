import SwiftUI
import Combine
import ServiceManagement
import NTSFirestore

enum Selection: Equatable {
    case idle              // nothing selected — the default empty state on launch
    case mixtape(String)   // mixtape alias — stable across catalog rebuilds
    case channel(Int)
    /// A past episode, played on demand. Unlike the other two this has no stream
    /// URL of its own: the audio lives on SoundCloud or Mixcloud and has to be
    /// resolved through NTS before it can be played, so loading it is async.
    case episode(show: String, episode: String)
}

/// Which of the two places the window is. **One slot, not one flag each.**
///
/// These are peers — two views of the station you switch between and stay in —
/// so they are one value with two cases. As two independent `Bool`s they could
/// both be true, which is what used to happen: the catalog drew over the
/// tracklist while the tracklist's button stayed lit, so the interface claimed
/// two things were open and showed one. A value cannot hold two cases.
///
/// The tracklist is deliberately *not* a case here — it is a drawer that covers
/// whichever of these is underneath and gives it straight back
/// (`AppModel.tracksOpen`), not a third place to be.
enum Pane: Equatable {
    /// The faceplate: what is on air now — the two channel cards and the mixtape
    /// dial.
    case live
    /// The archive: explore, schedule, saved, search.
    case catalog
}

/// A pane and whether the drawer is over it — the pair, as one value to animate
/// on. See `AppModel.paneState`.
struct PaneState: Equatable {
    let pane: Pane
    let tracksOpen: Bool
}

/// Which list the catalog is showing when no search is running. A live query
/// outranks the tab — it searches everything at once — so this only decides the
/// resting view.
enum CatalogTab: String, CaseIterable, Identifiable {
    case explore, schedule, saved
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

/// What the catalog is looking at beyond a list. Pushed on top of the grid and
/// popped by the back control — a stack of one, which is all the depth the
/// content has (a show's episodes link out to nts.live rather than deeper in).
enum CatalogDetail: Equatable {
    case show(alias: String, fallbackTitle: String)
    case mixtape(alias: String)
}

@MainActor
final class AppModel: ObservableObject {
    /// The app's one model. It existed as a single instance already — the
    /// `AppDelegate` made it and handed it to the radio window — but the Settings
    /// window is built by `SettingsWindowController`, outside any SwiftUI
    /// environment and with nothing to hand it the model. Naming the instance
    /// here is what lets both windows reach the same object, and matches
    /// `Catalog.shared` / `Saved.shared` / `ShowIndex.shared` beside it.
    static let shared = AppModel()

    let catalog = Catalog.shared
    let engine = PlayerEngine()
    let auth = NTSAuth()
    let saved = Saved.shared
    let showIndex = ShowIndex.shared

    // MARK: Catalog surface

    /// Where the window is: live, or the catalog. The two-segment control in the
    /// now-playing bar writes it and reads it back, so its lit segment and what
    /// is on screen are the same fact rather than two that have to agree.
    @Published var pane: Pane = .live
    /// Whether the tracklist drawer is covering that pane. A flag rather than a
    /// third `Pane` case because it is a different kind of thing: it does not
    /// change where you are, it lays what is playing over the top of wherever
    /// that is and hands it back on close. All four combinations of this and
    /// `pane` are real, visible states — the drawer over the faceplate and the
    /// drawer over the catalog are both things you can be looking at, and the
    /// segment underneath goes on truthfully saying which one you will get back.
    @Published var tracksOpen = false
    /// The two together, for the one animation that covers both. Changing pane
    /// while the drawer is up changes both properties in the same tick, and
    /// animating them separately ran two curves over the same region at once.
    var paneState: PaneState { PaneState(pane: pane, tracksOpen: tracksOpen) }
    /// Whether the catalog is the pane on screen. Read-only, for the places that
    /// only care about that one — the service banner, the scripting state blob.
    var catalogOpen: Bool { pane == .catalog }
    /// Explore, not the schedule: the schedule answers "what is on", which the
    /// channel cards already say, while Explore is the only route to the other
    /// 89,000 episodes.
    @Published var catalogTab: CatalogTab = .explore
    /// The search field's contents. Non-empty means the query is showing instead
    /// of `catalogTab`, across shows and mixtapes at once.
    @Published var query = ""
    @Published var detail: CatalogDetail? = nil

    /// Fetched lazily when a show detail opens, keyed by alias so reopening the
    /// same show is instant and a slow fetch can't land under a different show.
    @Published var showDetails: [String: NTSAPI.ShowDetail] = [:]
    /// Loaded a page at a time as the episode list scrolls — `/shows/<alias>/episodes`
    /// clamps to 12 regardless of what's asked for, so a show with more than that
    /// (Lung Dart has 102) needs one request per twelve.
    @Published var showEpisodes: [String: [NTSAPI.Episode]] = [:]
    @Published private(set) var showEpisodeTotals: [String: Int] = [:]
    @Published private(set) var showEpisodesLoading = false

    @Published var selection: Selection = .idle
    @Published var muted = UserDefaults.standard.bool(forKey: "muted") {
        didSet {
            engine.apply(volume: volume, muted: muted)
            UserDefaults.standard.set(muted, forKey: "muted")
        }
    }
    /// Dragging the volume slider fires this on every frame; only the disk write
    /// is debounced (`engine.apply` below stays live so audio tracks the drag).
    private var volumePersist: Task<Void, Never>?
    @Published var volume: Double = UserDefaults.standard.object(forKey: "volume") as? Double ?? 72 {
        didSet {
            engine.apply(volume: volume, muted: muted)
            let volume = volume
            volumePersist?.cancel()
            volumePersist = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                UserDefaults.standard.set(volume, forKey: "volume")
            }
        }
    }
    @Published var hoverIndex: Int? = nil
    /// Where the dial's index mark is pointing, in degrees, accumulated across
    /// turns rather than wrapped into 0..<360 — so it is free to wind past a full
    /// turn in either direction and always takes the short way to the next tape.
    /// It lives here rather than in `DialView` so a script can read it back.
    @Published var knobAngle: Double = 0
    // Nothing is drawn over the radio window any more. Settings and the account
    // were both sheets in here with painted traffic lights; both are tabs of the
    // real Settings window now (`SettingsView`), so the flags that tracked
    // whether they were up are gone with them.

    /// The episode currently tuned, once its details have arrived. Nil for the
    /// live channels and the mixtapes, which carry their own metadata.
    @Published var episode: NTSAPI.EpisodeDetail?
    /// True between picking an episode and its audio starting — the two fetches
    /// behind it take long enough to need saying so.
    @Published var episodeLoading = false
    /// Why the last episode failed to start, in words fit for the now-playing
    /// bar. Cleared on the next attempt.
    @Published var episodeError: String?
    private var episodeLoad: Task<Void, Never>?

    /// Tracklist for the current source — populated by the Firestore listener for
    /// both mixtapes and live channels when signed in (empty when signed out).
    @Published var tracks: [Track] = []

    /// The current source episode for the playing mixtape (the show episode its
    /// audio is pulled from), or nil for live channels / before the first push /
    /// when signed out. Drives the now-playing bar's secondary line + its link.
    @Published var mixtapeEpisode: MixtapeTitle?

    /// Whether the app is registered to launch when the user logs in.
    ///
    /// Read straight from `SMAppService` rather than from a saved preference, and
    /// written by registering or unregistering the service — the login item is
    /// the fact, and a stored copy of it can only be a second answer that goes
    /// stale. It goes stale the moment the switch is thrown in System Settings ▸
    /// General ▸ Login Items, which is the same list this writes to. Before this,
    /// the toggle was a `Bool` that remembered itself and registered nothing: it
    /// moved, it stayed where it was put, and the app never launched at login.
    ///
    /// Registering needs a bundle, so under `admin dev` (a bare binary, no
    /// `Info.plist`) `SMAppService` fails; the failure is logged and the toggle
    /// snaps back to what the service actually reports.
    @Published var startOnLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            guard startOnLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if startOnLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                let verb = startOnLogin ? "register" : "unregister"
                Log.app.error("login item \(verb, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                // Say what is true, not what was asked for.
                startOnLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    /// Re-read the login item's real state — after the Settings window opens, say,
    /// since it can be changed in System Settings while the app is running.
    func refreshStartOnLogin() {
        let enabled = SMAppService.mainApp.status == .enabled
        if startOnLogin != enabled { startOnLogin = enabled }
    }

    /// Whether the app also shows a Dock icon (and app-switcher entry). Off by
    /// default — the app lives primarily in the menu bar. Persisted here; the
    /// AppDelegate observes it and owns applying the activation policy.
    @Published var showInDock: Bool = UserDefaults.standard.bool(forKey: "showInDock") {
        didSet { UserDefaults.standard.set(showInDock, forKey: "showInDock") }
    }

    /// Live tracklist listener for the current source (nil when signed out).
    /// Recreated whenever the source or auth state changes.
    private var listener: FirestoreListener?
    /// The stream the `listener` is currently running, so we can tell a real
    /// source change from a no-op refresh and avoid churning the connection.
    private var activeStream: TracklistAdapter.Stream?

    /// Listener for the current mixtape's source episode (`mixtape_titles`), plus
    /// the alias it's running so a refresh that doesn't change the mixtape is a
    /// no-op (mirrors the `listener` / `activeStream` pattern above).
    private var titleListener: MixtapeTitleListener?
    private var activeTitleAlias: String?

    /// Publishes what's playing to the system and receives the media keys /
    /// headset buttons. Built last in `init` because it reads this model.
    private var nowPlaying: NowPlayingCenter?

    /// Sleeps until the current programme's end time, then hands the rail over to
    /// the next slot. See `scheduleSlotAdvance()`.
    private var slotTimer: Task<Void, Never>?

    /// A pushed tracklist waiting for the audio it describes to be heard, and the
    /// moment it may be shown. See `receive(_:)`.
    private var heldTracks: (tracks: [Track], deadline: Date)?
    private var trackRelease: Task<Void, Never>?

    private var bag = Set<AnyCancellable>()

    init() {
        // Both are observable objects of their own; republish their changes as
        // ours so a view watching the model repaints when the stream starts or
        // the dial's contents move.
        for upstream in [engine.objectWillChange, catalog.objectWillChange,
                         saved.objectWillChange, showIndex.objectWillChange] {
            upstream
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &bag)
        }
        engine.apply(volume: volume, muted: muted)
        catalog.mixtapes = Catalog.build(from: Cache.loadFeed())   // instant/offline seed
        loadCurrent(autoplay: false)
        // Re-open the tracklist + episode streams whenever sign-in state flips
        // (both feeds are supporter-gated).
        auth.$isAuthenticated
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateTracklist()
                self?.updateMixtapeTitle()
                Task { await self?.saved.sync() }
            }
            .store(in: &bag)
        // Saved is built before auth exists, so it is handed the token source
        // rather than the auth object.
        saved.token = { [auth] in try await auth.validToken() }
        Task { await saved.sync() }
        updateTracklist()
        updateMixtapeTitle()
        nowPlaying = NowPlayingCenter(model: self)
        Task { await refreshMixtapes() }
        Task { await pollSchedule() }
        Task { await showIndex.buildIfStale() }
        Task {
            await loadExploreVocabulary()
            reloadExplore()
        }
    }

    // MARK: Derived view-model

    var isPlaying: Bool { engine.isPlaying }
    var isLive: Bool { if case .channel = selection { return true }; return false }

    /// Whether nothing is selected — the idle/empty state shown on first launch.
    var isIdle: Bool { selection == .idle }

    var currentMixtape: Mixtape? {
        guard case .mixtape(let alias) = selection else { return nil }
        return catalog.mixtapes.first { $0.alias == alias }
    }
    var currentChannel: Channel? {
        if case .channel(let n) = selection { return catalog.channels.first { $0.number == n } }
        return nil
    }

    var displayName: String {
        if case .episode = selection {
            if let name = episode?.name, !name.isEmpty { return name.uppercased() }
            // Nothing arrived, so there is no name to show. "LOADING…" would keep
            // claiming something is on its way after it has already failed.
            return episodeError == nil ? "LOADING…" : "COULDN’T PLAY"
        }
        return (currentMixtape?.title ?? currentChannel?.show ?? "").uppercased()
    }

    var subtitle: String {
        if case .episode = selection {
            if let episodeError { return episodeError.uppercased() }
            if episodeLoading { return "FINDING THE AUDIO…" }
            guard let episode else { return "" }
            let bits = [episode.date, episode.location, episode.genres.first ?? ""]
            return bits.filter { !$0.isEmpty }.joined(separator: " · ").uppercased()
        }
        if currentMixtape != nil {
            // Source episode (mixed case, as NTS formats it). The feed is
            // supporter-gated: signed-in shows a loading label until the first
            // push; signed-out can't read it, so keep the static descriptor.
            if let ep = mixtapeEpisode { return ep.title }
            return auth.isAuthenticated ? "TUNING IN…" : "24/7 STREAM · NON-STOP"
        }
        if let c = currentChannel {
            var parts: [String] = []
            if !c.startEnd.isEmpty { parts.append(c.startEnd) }
            if !c.genre.isEmpty { parts.append(c.genre.uppercased()) }
            return parts.joined(separator: " · ")
        }
        return ""
    }

    /// Link for the secondary label: the nts.live episode page for the mixtape's
    /// current source episode. Nil for live channels and before the first push.
    var nowPlayingEpisodeURL: URL? {
        guard currentMixtape != nil, let ep = mixtapeEpisode,
              !ep.showAlias.isEmpty, !ep.episodeAlias.isEmpty else { return nil }
        return URL(string: "https://www.nts.live/shows/\(ep.showAlias)/episodes/\(ep.episodeAlias)")
    }

    /// Link for the primary label: the nts.live episode page for a live channel's
    /// current broadcast. Nil for mixtapes and when the live feed gave no aliases.
    var nowPlayingShowURL: URL? {
        if case .episode = selection { return episode?.pageURL }
        return currentChannel?.episodeURL
    }

    var accent: Color {
        currentMixtape?.accent ?? currentChannel?.accent ?? Theme.ink
    }

    /// A past episode's tracklist is the whole thing, known up front — not a
    /// live feed's rolling history, so it reads the same as a channel's.
    var tracksLabel: String {
        if case .episode = selection { return "TRACKLIST" }
        return isLive ? "TRACKLIST" : "RECENTLY PLAYED"
    }

    /// Which track is "now playing". A live push already lists newest-first, so
    /// it's the top row; a past episode's tracklist is the whole thing at once,
    /// known up front, so this picks it out by the seek position instead — the
    /// last track whose start the playhead has already passed.
    var currentTrack: Track? {
        if case .episode = selection {
            return tracks.last { ($0.offsetSeconds ?? 0) <= engine.position }
        }
        return tracks.first
    }

    // MARK: Actions

    /// Tune to a source. Picking one is a request to hear it, so this starts
    /// playback by default; the media keys and the snapshot renderer opt out.
    func select(_ s: Selection, autoplay: Bool = true) {
        selection = s
        loadCurrent(autoplay: autoplay)
        updateTracklist()
        updateMixtapeTitle()
    }

    /// Open (or tear down) the live tracklist stream for the current source.
    /// Signed in → a Firestore `live_tracks` listener for the current mixtape or
    /// channel; signed out → cleared (both feeds are supporter-gated). The public
    /// REST tracklist endpoint is empty for an in-progress channel show, so live
    /// channel tracks come from Firestore too, not REST.
    func updateTracklist() {
        let wanted = auth.isAuthenticated
            ? TracklistAdapter.stream(for: selection, mixtape: currentMixtape, channel: currentChannel)
            : nil
        // Already streaming the right source — don't churn the connection (this
        // also makes a catalog rebuild a no-op unless the first mixtape changed).
        if listener != nil, wanted == activeStream { return }
        listener?.stop()
        listener = nil
        publish([])
        activeStream = wanted
        guard let wanted else { return }
        let hue = wanted.hue
        let listener = FirestoreListener(
            filter: wanted.filter,
            tokenProvider: { [auth] in try await auth.validToken() },
            onUpdate: { [weak self] live in
                self?.receive(TracklistAdapter.tracks(from: live, hue: hue))
            }
        )
        self.listener = listener
        listener.start()
    }

    /// Take a Firestore push, holding a newly started track back until the audio
    /// it names has actually reached the speakers.
    ///
    /// NTS pushes the track the moment it airs, but AVPlayer is behind the live
    /// edge by whatever it has buffered — measured at ~5s on the channel streams
    /// and ~29s on the mixtape HLS. Showing the push immediately lit the top row
    /// while the previous track was still coming out of the speakers.
    private func receive(_ incoming: [Track]) {
        // Nothing to stay behind: the backfill on opening or switching source (an
        // empty list held back half a minute is worse than one that starts
        // correct), a push that only revises rows further down, or a paused
        // player with no audio in flight.
        guard incoming.first?.key != tracks.first?.key, !tracks.isEmpty, engine.isPlaying else {
            publish(incoming); return
        }
        if let held = heldTracks, held.tracks.first?.key == incoming.first?.key {
            // Same track, pushed again with revised details — take the new
            // contents but keep the original deadline, so a run of revisions
            // can't keep pushing the reveal further out.
            heldTracks = (incoming, held.deadline)
        } else {
            // 60s ceiling: the buffer has never measured anywhere near it, and a
            // wild reading shouldn't be able to freeze the list.
            let wait = min(engine.bufferedAhead, 60)
            heldTracks = (incoming, Date().addingTimeInterval(wait))
        }
        scheduleTrackRelease()
    }

    /// The track that has started but isn't being shown yet, and how long it has
    /// left to wait. Without this the delay can't be observed from outside at all —
    /// its whole effect is that nothing happens for a few seconds.
    var pendingTrack: (name: String, seconds: Double)? {
        guard let held = heldTracks, let first = held.tracks.first else { return nil }
        return ("\(first.artist) — \(first.title)",
                (max(0, held.deadline.timeIntervalSinceNow) * 10).rounded() / 10)
    }

    /// Show a tracklist now, dropping anything held.
    private func publish(_ incoming: [Track]) {
        trackRelease?.cancel()
        trackRelease = nil
        heldTracks = nil
        tracks = incoming
    }

    private func scheduleTrackRelease() {
        trackRelease?.cancel()
        guard let held = heldTracks else { return }
        let delay = max(0, held.deadline.timeIntervalSinceNow)
        trackRelease = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, let held = self.heldTracks else { return }
            self.publish(held.tracks)
        }
    }

    /// Open (or tear down) the current-episode stream for the playing mixtape.
    /// Signed in + a mixtape selected → a Firestore `mixtape_titles` listener;
    /// otherwise cleared (live channels have no source episode, and the feed is
    /// supporter-gated). Mirrors `updateTracklist`'s no-churn guard.
    func updateMixtapeTitle() {
        let alias = (auth.isAuthenticated ? currentMixtape?.alias : nil)
        if titleListener != nil, alias == activeTitleAlias { return }
        titleListener?.stop()
        titleListener = nil
        mixtapeEpisode = nil
        activeTitleAlias = alias
        guard let alias else { return }
        let listener = MixtapeTitleListener(
            mixtapeAlias: alias,
            tokenProvider: { [auth] in try await auth.validToken() },
            // Ignore a late emit from a listener we've since switched away from, so
            // a fast A→B switch can't briefly show A's episode under B.
            onUpdate: { [weak self] episode in
                guard let self, self.activeTitleAlias == alias else { return }
                self.mixtapeEpisode = episode
            }
        )
        titleListener = listener
        listener.start()
    }

    func loadCurrent(autoplay: Bool) {
        if case .episode(let show, let episode) = selection {
            loadEpisode(show: show, episode: episode, autoplay: autoplay)
            return
        }
        let url = currentMixtape?.streamURL ?? currentChannel?.streamURL
        if let url { engine.load(url, autoplay: autoplay) }
    }

    /// Fetch an episode and start it.
    ///
    /// Two hops, both of which can fail and neither of which the live channels
    /// need: the episode names a SoundCloud or Mixcloud page, and NTS turns that
    /// into a signed HLS playlist. The signature expires, so this runs per play
    /// rather than being cached. A failure leaves the reason on screen instead of
    /// a silent dead transport.
    private func loadEpisode(show: String, episode: String, autoplay: Bool) {
        episodeLoad?.cancel()
        episodeError = nil
        episodeLoading = true
        episodeLoad = Task { [weak self] in
            defer { Task { @MainActor in self?.episodeLoading = false } }
            do {
                let detail = try await NTSAPI.episode(show: show, episode: episode)
                guard let source = detail.audioSources.first else { throw NTSAPI.APIError.noAudio }
                let stream = try await NTSAPI.resolveStream(source)
                guard !Task.isCancelled, let self else { return }
                // The selection can move on while the two requests are in flight;
                // landing this audio then would start the wrong thing playing.
                guard self.selection == .episode(show: show, episode: episode) else { return }
                self.episode = detail
                // Not a Firestore stream — the whole tracklist is already here,
                // known in advance rather than revealed as it airs, so it goes
                // straight in rather than through `receive`'s live-buffer delay.
                self.publish(TracklistAdapter.tracks(from: detail.tracklist, hue: 0))
                self.engine.load(stream, autoplay: autoplay)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.episodeError = error.localizedDescription
            }
        }
    }

    func togglePlay() {
        if engine.isPlaying { engine.pause() }
        else { loadCurrent(autoplay: true) }
    }

    /// Start the current source (the system Play button — distinct from toggle,
    /// which the media key sends).
    func play() {
        guard !isIdle else { return }
        loadCurrent(autoplay: true)
    }

    func pause() { engine.pause() }

    /// Move to the neighbouring source within the current group and select it —
    /// what the next/previous-track buttons on a headset do. The two live
    /// channels toggle between themselves; mixtapes walk the dial and wrap
    /// around at both ends. Idle does nothing: there's no group to walk yet.
    /// Playing state carries over: skipping while paused stays paused.
    func step(by delta: Int) {
        switch selection {
        case .idle:
            return
        // An episode is one thing you chose, not a position in a group — there is
        // no neighbour to step to, so the keys hold it where it is.
        case .episode:
            return
        case .channel(let number):
            let all = catalog.channels
            guard let i = all.firstIndex(where: { $0.number == number }) else { return }
            select(.channel(all[wrap(i + delta, all.count)].number), autoplay: engine.isPlaying)
        case .mixtape(let alias):
            let all = catalog.mixtapes
            guard let i = all.firstIndex(where: { $0.alias == alias }) else { return }
            select(.mixtape(all[wrap(i + delta, all.count)].alias), autoplay: engine.isPlaying)
        }
    }

    /// Index `i` folded back into `0..<count`, for negative values too (Swift's
    /// `%` keeps the sign of the left operand, so `-1 % 16` is `-1`, not `15`).
    private func wrap(_ i: Int, _ count: Int) -> Int {
        ((i % count) + count) % count
    }

    // MARK: Panes

    /// Go to a pane. The one way `pane` changes, so leaving the catalog always
    /// drops the query and any open detail — coming back lands on a list rather
    /// than mid-navigation from last time — no matter which control did it.
    ///
    /// Switching also closes the tracklist drawer: it is opened over one pane, and
    /// leaving that pane is leaving what the drawer was showing on top of.
    func show(_ p: Pane) {
        // Unconditional, and before the early return: pressing LIVE while the
        // drawer is up over live has to give live back. Guarding this the same
        // way as the pane change left the tracklist covering the very pane whose
        // segment had just been pressed — the button looked broken.
        tracksOpen = false
        guard pane != p else { return }
        if pane == .catalog { query = ""; detail = nil }
        pane = p
    }

    /// Show the catalog, or go back to live if it is already showing.
    func toggleCatalog() {
        show(pane == .catalog ? .live : .catalog)
    }

    /// Raise or drop the tracklist drawer over whatever pane is up. Nothing
    /// playing means nothing to list, so it will not open.
    func toggleTracks() {
        if tracksOpen { tracksOpen = false }
        else if !isIdle { tracksOpen = true }
    }

    /// Every channel's programmes, in air order — the schedule tab's contents.
    var schedule: [NTSAPI.Broadcast] {
        catalog.channels.flatMap(\.upcoming)
    }

    /// Whether this broadcast is the one currently on air for its channel.
    func isOnAir(_ b: NTSAPI.Broadcast) -> Bool {
        catalog.channels.first { $0.number == b.channel }?.upcoming.first?.id == b.id
    }

    /// A schedule slot as a grid row, flagged if it's the one on air — the only
    /// place the LIVE badge comes from, so it can't disagree with the rail.
    private func row(for b: NTSAPI.Broadcast) -> CatalogRow {
        let row = CatalogRow(b, resolved: showIndex.ref(b.showAlias))
        return isOnAir(b) ? row.markedLive() : row
    }

    /// What the catalog lists right now. A non-empty query outranks the tab and
    /// searches shows and mixtapes together, so a term that only appears in a
    /// mixtape's credits still finds it while the schedule tab is selected.
    var catalogRows: [CatalogRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.isEmpty else { return searchRows(q) }
        switch catalogTab {
        case .explore:
            return exploreEpisodes.map(CatalogRow.init)
        case .schedule:
            return schedule.map(row(for:))
        case .saved:
            return saved.items.map(CatalogRow.init)
        }
    }

    // MARK: Explore

    /// What Explore is filtered to. Every change re-runs the search from the
    /// first page — a filter that left the old results underneath it would be
    /// showing episodes that no longer match.
    @Published var exploreFilters = NTSAPI.ExploreFilters() {
        didSet { guard exploreFilters != oldValue else { return }; reloadExplore() }
    }
    @Published private(set) var exploreEpisodes: [NTSAPI.EpisodeCard] = []
    /// How many episodes match, which is usually far more than are loaded — the
    /// grid pages twelve at a time through thousands.
    @Published private(set) var exploreTotal = 0
    @Published private(set) var exploreLoading = false
    @Published private(set) var moods: [NTSAPI.Mood] = []
    @Published private(set) var genres: [NTSAPI.Genre] = []
    /// Which primary genre the drawer has open. One at a time: twenty primaries
    /// carry 438 subgenres, and all of them at once is a wall.
    @Published var openGenre: String?
    @Published var genreDrawerOpen = false

    private var exploreLoad: Task<Void, Never>?

    /// Start Explore over from its first page.
    func reloadExplore() {
        exploreLoad?.cancel()
        exploreEpisodes = []
        exploreTotal = 0
        loadExplorePage(offset: 0)
    }

    /// Fetch the next twelve, if there are more and nothing is already in flight.
    /// The grid calls this as its last row appears.
    func loadMoreExplore() {
        guard !exploreLoading, exploreEpisodes.count < exploreTotal else { return }
        loadExplorePage(offset: exploreEpisodes.count)
    }

    private func loadExplorePage(offset: Int) {
        let filters = exploreFilters
        exploreLoading = true
        exploreLoad = Task { [weak self] in
            defer { Task { @MainActor in self?.exploreLoading = false } }
            guard let page = try? await NTSAPI.explore(filters, offset: offset) else { return }
            guard !Task.isCancelled, let self, self.exploreFilters == filters else { return }
            // Paging can race a filter change; the guard above is why a late page
            // can't land under filters that no longer asked for it.
            self.exploreEpisodes += page.episodes
            self.exploreTotal = page.total
        }
    }

    /// Load the mood and genre vocabularies once. Both are small, static lists.
    private func loadExploreVocabulary() async {
        if let moods = try? await NTSAPI.moods() { self.moods = moods }
        if let genres = try? await NTSAPI.genres() {
            self.genres = genres
            rebuildGenreIndex()
        }
    }

    func toggleGenre(_ id: String) {
        if let i = exploreFilters.genres.firstIndex(of: id) { exploreFilters.genres.remove(at: i) }
        else { exploreFilters.genres.append(id) }
    }

    func toggleMood(_ id: String) {
        exploreFilters.mood = exploreFilters.mood == id ? nil : id
    }

    /// The Explore id for a genre named the way a broadcast prints it —
    /// "Kosmische" on a channel card is `ambientnewage-kosmiche` in Explore's
    /// vocabulary. Matching goes through the name because that is all the
    /// schedule carries: its slots list genres as display strings and never as
    /// ids. Nil while the vocabulary is still loading, or for a tag Explore
    /// doesn't file (NTS tags episodes more freely than it filters them), which
    /// is what leaves a chip as plain text rather than a link to nothing.
    func genreID(named name: String) -> String? { genreIDsByName[Self.genreKey(name)] }

    /// Built once when the vocabulary lands, not walked per lookup: every genre
    /// chip on both channel cards asks this from inside `body`, and `body` runs
    /// on each position tick, so a scan of 20 primaries and 438 subgenres —
    /// allocating a folded string per comparison — would run several times a
    /// second for as long as the window is open.
    private var genreIDsByName: [String: String] = [:]

    private func rebuildGenreIndex() {
        var index: [String: String] = [:]
        for genre in genres {
            index[Self.genreKey(genre.name)] = genre.id
            for sub in genre.subgenres { index[Self.genreKey(sub.name)] = sub.id }
        }
        genreIDsByName = index
    }

    /// NTS's own list has entries with a trailing space ("Amapiano "), and case
    /// differs between the genre list and a broadcast's tags.
    private static func genreKey(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Open the catalog on Explore showing one genre. The same door the
    /// `filter explore` command opens, so a chip on a channel card and a script
    /// land in one place rather than two that can drift.
    func browseGenre(_ id: String) {
        catalogTab = .explore
        query = ""
        detail = nil
        show(.catalog)
        exploreFilters = NTSAPI.ExploreFilters(genres: [id])
    }

    /// The name to show for a selected genre id. Subgenre ids are prefixed with
    /// their primary (`ambientnewage-ambient`), so this walks both levels.
    func genreName(_ id: String) -> String {
        for genre in genres {
            if genre.id == id { return genre.name }
            if let sub = genre.subgenres.first(where: { $0.id == id }) { return sub.name }
        }
        return id
    }

    // MARK: Timeline

    /// Which channel's grid the schedule tab is showing. One at a time: at the
    /// window's 340pt floor, two columns of programme titles leave about fifteen
    /// characters each.
    @Published var scheduleChannel: Int = 1

    /// One day of one channel's grid — the unit the timeline scrolls through.
    struct ScheduleDay: Identifiable {
        let id: String
        /// "TUE 11 AUG", the sticky header's text.
        let label: String
        /// "TODAY"/"TOMORROW" where it applies, so the top of the list doesn't
        /// have to be read as a date to be understood.
        let relative: String?
        let slots: [NTSAPI.Broadcast]
    }

    /// The selected channel's grid, grouped into days in air order.
    var scheduleDays: [ScheduleDay] {
        let slots = catalog.channels.first { $0.number == scheduleChannel }?.upcoming ?? []
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        var days: [(Date, [NTSAPI.Broadcast])] = []
        for slot in slots {
            guard let start = slot.start else { continue }
            let day = cal.startOfDay(for: start)
            if days.last?.0 == day { days[days.count - 1].1.append(slot) }
            else { days.append((day, [slot])) }
        }

        return days.map { day, slots in
            let offset = cal.dateComponents([.day], from: today, to: day).day ?? 0
            let relative: String? = switch offset {
            case 0: "TODAY"
            case 1: "TOMORROW"
            case -1: "YESTERDAY"
            default: nil
            }
            return ScheduleDay(id: Self.dayKey.string(from: day),
                               label: Self.dayLabel.string(from: day).uppercased(),
                               relative: relative,
                               slots: slots)
        }
    }

    /// The slot the clock is inside on the selected channel, if any — the row the
    /// timeline scrolls to and marks ON AIR.
    var onAirSlot: NTSAPI.Broadcast? {
        let now = Date()
        return catalog.channels.first { $0.number == scheduleChannel }?.upcoming.first {
            ($0.start ?? .distantFuture) <= now && now < ($0.end ?? .distantPast)
        }
    }

    /// The first slot that has not started on the selected channel. The grid has
    /// real gaps — roughly thirty a fortnight per channel — so when the clock is
    /// in one of them this is what the NOW rule sits above.
    var nextSlot: NTSAPI.Broadcast? {
        let now = Date()
        return catalog.channels.first { $0.number == scheduleChannel }?.upcoming.first {
            ($0.start ?? .distantPast) > now
        }
    }

    /// What the timeline scrolls to when it opens: the programme on air, or the
    /// next one to start when the clock is in a gap, or the top of the grid.
    var timelineAnchor: String? {
        onAirSlot?.id ?? nextSlot?.id ?? scheduleDays.first?.slots.first?.id
    }

    /// Open a schedule slot's show, the same as clicking its tile in the grid.
    func openSlot(_ slot: NTSAPI.Broadcast) {
        open(row(for: slot))
    }

    // MARK: Timeline artwork

    /// What a schedule row draws, keyed by `<show>/<episode>`.
    ///
    /// The grid publishes no artwork, no genres and no city — only a title, a
    /// time and two aliases — and the show index behind the rows is seeded from
    /// the sitemap, which is URLs and nothing else. So without this every row
    /// but the handful of shows the app had met elsewhere drew the placeholder
    /// mark and no second line: 296 of the fortnight's shows, across both
    /// channels, blank.
    ///
    /// Filled per row as it scrolls into view rather than in one sweep at open:
    /// the fortnight is ~345 slots and nobody scrolls all of it. Kept on disk
    /// (trimmed to the current grid) so a relaunch doesn't re-ask for the rows
    /// this session already paid for.
    @Published private(set) var slotDetails: [String: SlotDetail] = Cache.load([String: SlotDetail].self, from: slotDetailFile) ?? [:]

    nonisolated private static let slotDetailFile = "schedule-art.json"

    /// Slots asked for, so a row that leaves and re-enters the viewport doesn't
    /// ask twice. A failure drops out again — otherwise a scroll taken while the
    /// network was down would leave those rows blank until the app was
    /// relaunched, with nothing to prompt a second attempt.
    private var slotDetailAsked: Set<String> = []

    func slotDetail(_ slot: NTSAPI.Broadcast) -> SlotDetail? {
        slotDetails[Self.slotKey(slot)]
    }

    /// Two airings of the same episode share an answer, which is the point of
    /// keying by episode rather than by slot. A slot NTS has not named an
    /// episode for yet has nothing to share, so it keys by its own id instead of
    /// colliding with every other unnamed slot of the same show.
    static func slotKey(_ slot: NTSAPI.Broadcast) -> String {
        slot.episodeAlias.isEmpty ? "\(slot.showAlias)/#\(slot.id)"
                                  : "\(slot.showAlias)/\(slot.episodeAlias)"
    }

    /// Rows waiting for a fetch, newest first — the ones nearest what is on
    /// screen. Dragging the scrollbar through a fortnight touches ~345 rows in a
    /// second, and firing all of them means hundreds of requests for rows that
    /// are already gone by the time they answer.
    private var slotDetailQueue: [NTSAPI.Broadcast] = []
    private var slotDetailRunning = 0
    private static let slotDetailConcurrency = 4

    /// Fetch one schedule row's episode — its photograph, genres and city.
    ///
    /// The episode rather than the show, so a repeat carries the cover of the
    /// broadcast being repeated instead of the show's standing one. A slot with
    /// no episode alias yet (the furthest-out ~30% of the grid) falls back to
    /// the show, which still has artwork.
    func loadSlotDetail(_ slot: NTSAPI.Broadcast) {
        guard !slot.showAlias.isEmpty else { return }
        let key = Self.slotKey(slot)
        guard slotDetails[key] == nil, slotDetailAsked.insert(key).inserted else { return }
        slotDetailQueue.append(slot)
        pumpSlotDetails()
    }

    /// A row that scrolled away before its turn came gives up its place. One
    /// already in flight is left alone — it is nearly paid for, and the answer
    /// is kept either way.
    func cancelSlotDetail(_ slot: NTSAPI.Broadcast) {
        let key = Self.slotKey(slot)
        guard let i = slotDetailQueue.firstIndex(where: { Self.slotKey($0) == key }) else { return }
        slotDetailQueue.remove(at: i)
        slotDetailAsked.remove(key)
    }

    private func pumpSlotDetails() {
        while slotDetailRunning < Self.slotDetailConcurrency, let slot = slotDetailQueue.popLast() {
            slotDetailRunning += 1
            fetchSlotDetail(slot)
        }
    }

    private func fetchSlotDetail(_ slot: NTSAPI.Broadcast) {
        let key = Self.slotKey(slot)
        Task { [weak self] in
            defer {
                if let self {
                    self.slotDetailRunning -= 1
                    self.pumpSlotDetails()
                }
            }
            let show = slot.showAlias, episode = slot.episodeAlias
            var image: URL?
            var genres: [String] = []
            var location = ""
            var name = slot.title
            var fromShow = false

            if !episode.isEmpty,
               let ep = try? await NTSAPI.episode(show: show, episode: episode,
                                                  reportAs: "schedule-art") {
                image = ep.image
                genres = ep.genres
                location = [ep.locationLong, ep.location].first { !$0.isEmpty } ?? ""
                if !ep.name.isEmpty { name = ep.name }
            } else if let s = try? await NTSAPI.show(alias: show) {
                image = s.image
                genres = s.genres
                location = s.location
                if !s.name.isEmpty { name = s.name }
                fromShow = true
            } else {
                self?.slotDetailAsked.remove(key)
                return
            }

            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.slotDetails[key] = SlotDetail(slotID: slot.id, image: image,
                                                   genres: genres, location: location)
            }
            self.saveSlotDetailsSoon()
            // Only the show endpoint's answer is folded into the index. An
            // episode's title and cover belong to that broadcast, not to the
            // show — and `note` keeps the first rich entry it is given, so
            // writing one there would make "Lung Dart 10th August 2026" the
            // show's name in search for good.
            if fromShow {
                self.showIndex.note(alias: show, name: name, location: location,
                                    genres: genres, picture: image?.absoluteString)
            }
        }
    }

    private var slotDetailSaveTask: Task<Void, Never>?

    /// Write the row artwork a few seconds after the fetches stop, trimmed to
    /// the grid that is actually on screen — otherwise the file would accumulate
    /// every broadcast the app ever scrolled past.
    private func saveSlotDetailsSoon() {
        slotDetailSaveTask?.cancel()
        slotDetailSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.slotDetailSaveTask = nil
            let live = self.trimSlotDetails()
            // Encoding and writing happen off the main actor: the UI is running
            // while a scroll is what triggers this.
            Task.detached { Cache.save(live, to: Self.slotDetailFile) }
        }
    }

    /// Drop the rows that have left the grid, and answer with what is left.
    @discardableResult private func trimSlotDetails() -> [String: SlotDetail] {
        let live = Set(catalog.channels.flatMap { $0.upcoming }.map(Self.slotKey))
        slotDetails = slotDetails.filter { live.contains($0.key) }
        return slotDetails
    }

    /// The synchronous write, for quit: a detached task would not outlive the
    /// process.
    func saveSlotDetails() {
        slotDetailSaveTask?.cancel()
        slotDetailSaveTask = nil
        Cache.save(trimSlotDetails(), to: Self.slotDetailFile)
    }

    private static let dayKey: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let dayLabel: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()

    private func searchRows(_ q: String) -> [CatalogRow] {
        var rows: [CatalogRow] = []
        var seen = Set<String>()

        // Mixtapes first: sixteen of them, and their credits are the only route
        // from a host's name to the mixtape carrying their show.
        for (i, m) in catalog.mixtapes.enumerated() where m.searchText.contains(q) {
            rows.append(CatalogRow(m, detent: i + 1))
            seen.insert("mixtape:\(m.alias)")
        }
        // Then anything on the air today, so a match you can play right now
        // outranks the same show's index entry.
        for b in schedule where b.searchText.contains(q) {
            rows.append(row(for: b))
            if !b.showAlias.isEmpty { seen.insert("show:\(b.showAlias)") }
        }
        for s in showIndex.all where s.haystack.contains(q) {
            guard !seen.contains("show:\(s.alias)") else { continue }
            rows.append(CatalogRow(s))
        }
        return rows
    }

    /// The line under the search field — states how much was actually searched.
    /// The index now covers every show NTS publishes, so this is a statement of
    /// coverage rather than the apology it used to be.
    var searchScope: String {
        let n = showIndex.count
        if showIndex.building { return "INDEXING SHOWS — \(n) SO FAR" }
        return "\(catalog.mixtapes.count) MIXTAPES · \(schedule.count) SCHEDULED · \(n) SHOWS"
    }

    // MARK: Saving

    func isSaved(_ row: CatalogRow) -> Bool {
        guard let item = row.savedItem else { return false }
        return saved.contains(item)
    }

    func toggleSaved(_ row: CatalogRow) {
        guard let item = row.savedItem else { return }
        saved.toggle(item)
    }

    // MARK: Detail

    func open(_ row: CatalogRow) {
        switch row.target {
        case .show(let alias, let title):
            detail = .show(alias: alias, fallbackTitle: title)
            Task { await loadShow(alias) }
        case .mixtape(let alias):
            detail = .mixtape(alias: alias)
        case .none:
            break
        }
    }

    /// Fetch a show's page and its first page of episodes, once. Both are
    /// best-effort: a failure leaves the detail view on what the schedule row
    /// already knew.
    func loadShow(_ alias: String) async {
        if showDetails[alias] == nil, let d = try? await NTSAPI.show(alias: alias) {
            showDetails[alias] = d
            showIndex.note(alias: alias, name: d.name, location: d.location,
                           genres: d.genres, picture: d.image?.absoluteString)
        }
        if showEpisodes[alias] == nil { loadMoreEpisodes(for: alias) }
    }

    /// Fetch the next twelve episodes of a show, if there are more and nothing
    /// is already in flight. The episode list calls this as its last row
    /// appears, same as Explore's grid.
    func loadMoreEpisodes(for alias: String) {
        guard !showEpisodesLoading else { return }
        let loaded = showEpisodes[alias]?.count ?? 0
        if let total = showEpisodeTotals[alias], loaded >= total { return }
        showEpisodesLoading = true
        Task { [weak self] in
            defer { Task { @MainActor in self?.showEpisodesLoading = false } }
            guard let page = try? await NTSAPI.episodes(alias: alias, offset: loaded) else { return }
            guard let self else { return }
            self.showEpisodes[alias, default: []] += page.episodes
            self.showEpisodeTotals[alias] = page.total
        }
    }

    /// Tune to whatever a catalog row points at, if it is playable. A schedule row
    /// plays its channel — a future slot can't be played early, so it tunes the
    /// channel it will air on rather than pretending to seek.
    func play(_ row: CatalogRow) {
        switch row.playable {
        case .channel(let n): select(.channel(n))
        case .mixtape(let alias): select(.mixtape(alias))
        case .episode(let show, let episode): select(.episode(show: show, episode: episode))
        case .none: break
        }
    }

    /// In-flight artwork fetches, one per channel, so a changeover cancels the
    /// previous programme's request instead of racing it.
    private var detailTasks: [Int: Task<Void, Never>] = [:]

    /// Dress whatever is now at the head of a channel's grid.
    ///
    /// Two steps, because the grid publishes no artwork: the show's own picture
    /// goes on immediately so the tile never goes blank across a handover, then
    /// the episode's own photograph replaces it once NTS answers. Both writes
    /// name the slot they belong to, so neither can land on the next programme.
    private func refreshDetail(channel idx: Int) {
        let number = catalog.channels[idx].number
        detailTasks[number]?.cancel()
        guard let slot = catalog.channels[idx].onAir else {
            catalog.channels[idx].detail = nil
            return
        }
        let indexed = showIndex.ref(slot.showAlias)
        catalog.channels[idx].detail = SlotDetail(
            slotID: slot.id,
            image: slot.image ?? indexed?.pictureURL,
            genres: slot.genres.isEmpty ? (indexed?.genres ?? []) : slot.genres,
            location: slot.location.isEmpty ? (indexed?.location ?? "") : slot.location)

        guard !slot.showAlias.isEmpty, !slot.episodeAlias.isEmpty else { return }
        // The timeline's ON AIR row wants exactly this episode, so it takes the
        // rail's copy rather than asking NTS for the same JSON a second time.
        slotDetailAsked.insert(Self.slotKey(slot))
        detailTasks[number] = Task { [weak self] in
            guard let ep = try? await NTSAPI.episode(show: slot.showAlias, episode: slot.episodeAlias,
                                                     reportAs: "on-air-detail"),
                  !Task.isCancelled, let self,
                  let i = self.catalog.channels.firstIndex(where: { $0.number == number }),
                  self.catalog.channels[i].onAir?.id == slot.id
            else { return }
            self.slotDetails[Self.slotKey(slot)] = SlotDetail(
                slotID: slot.id,
                image: ep.image,
                genres: ep.genres,
                location: [ep.locationLong, ep.location].first { !$0.isEmpty } ?? "")
            self.saveSlotDetailsSoon()
            withAnimation(.easeInOut(duration: 0.3)) {
                self.catalog.channels[i].detail = SlotDetail(
                    slotID: slot.id,
                    image: ep.image ?? self.catalog.channels[i].detail?.image,
                    genres: ep.genres.isEmpty ? (self.catalog.channels[i].detail?.genres ?? []) : ep.genres,
                    location: [ep.locationLong, ep.location,
                               self.catalog.channels[i].detail?.location ?? ""]
                        .first { !$0.isEmpty } ?? "")
            }
        }
    }

    /// How long a fetched grid is trusted. NTS serves the schedule with
    /// `cache-control: max-age=900`, so asking more often than that re-reads the
    /// same bytes.
    private static let scheduleMaxAge: TimeInterval = 900
    private var scheduleFetched: Date?

    /// Pull both channels' published programme grids — fourteen days each, every
    /// slot timed and named.
    ///
    /// This replaces reading the grid out of `/api/v2/live`, which only embedded
    /// details for the current and next slot and left the other sixteen to be
    /// matched back to a show by their title. Finished slots are dropped on the
    /// way in so `upcoming` still means what it says.
    func refreshSchedule() async {
        var grids: [Int: [NTSAPI.Broadcast]] = [:]
        for number in catalog.channels.map(\.number) {
            guard let slots = try? await NTSAPI.schedule(channel: number) else { continue }
            grids[number] = slots
        }
        guard !grids.isEmpty else { return }
        scheduleFetched = Date()

        let now = Date()
        for idx in catalog.channels.indices {
            guard let slots = grids[catalog.channels[idx].number] else { continue }
            let head = catalog.channels[idx].onAir?.id
            catalog.channels[idx].upcoming = slots.filter { ($0.end ?? .distantPast) > now }
            if catalog.channels[idx].onAir?.id != head { refreshDetail(channel: idx) }
            // Every slot names its show; folding those in is how the index covers
            // shows past the 1012 the shows endpoint will hand out.
            for b in slots where !b.showAlias.isEmpty {
                showIndex.note(alias: b.showAlias, name: b.title)
            }
        }
    }

    /// Move each channel on to the programme the clock is actually in, dropping
    /// the slots that have finished.
    ///
    /// The grid already names every upcoming slot and the minute it ends, so a
    /// changeover is something the app can do on its own — it doesn't have to be
    /// told. It used to be told, by `/api/v2/live`, which NTS serves with
    /// `cache-control: max-age=900`: for up to fifteen minutes after the hour
    /// every poll handed back the programme that had just finished and wrote it
    /// straight over the one that had started.
    ///
    /// Dropping the finished slots is now the whole changeover. Nothing here
    /// copies a title or a time anywhere — the rail reads them off the head of
    /// the grid — so this is idempotent and can run as often as it likes.
    func advanceSlots(now: Date = Date()) {
        withAnimation(.easeInOut(duration: 0.4)) { advance(now: now) }
    }

    private func advance(now: Date) {
        for idx in catalog.channels.indices {
            let live = catalog.channels[idx].upcoming.drop { ($0.end ?? .distantFuture) <= now }
            guard live.first?.id != catalog.channels[idx].onAir?.id else { continue }
            catalog.channels[idx].upcoming = Array(live)
            refreshDetail(channel: idx)
        }
    }

    /// Wake once, at the moment the earliest current programme ends, to hand over
    /// to the next one. Re-armed after every advance and every poll.
    private func scheduleSlotAdvance() {
        slotTimer?.cancel()
        let now = Date()
        guard let end = catalog.channels.compactMap({ $0.upcoming.first?.end }).filter({ $0 > now }).min()
        else { return }
        // A second past the boundary, so the slot being handed over has genuinely ended.
        let delay = end.timeIntervalSince(now) + 1
        slotTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.advanceSlots()
            self.scheduleSlotAdvance()
        }
    }

    /// Keep the grid fresh and the rail on the right programme.
    ///
    /// The changeover is `scheduleSlotAdvance`'s timer, which fires on the
    /// boundary itself. This loop is the safety net behind it: a machine that
    /// slept through a boundary, or a grid that aged past NTS's fifteen-minute
    /// cache, catches up within a minute. It costs no request in the ordinary
    /// case — `refreshSchedule` is the only fetch here and it is rate-limited.
    private func pollSchedule() async {
        while !Task.isCancelled {
            if scheduleFetched.map({ Date().timeIntervalSince($0) > Self.scheduleMaxAge }) ?? true {
                await refreshSchedule()
            }
            advanceSlots()
            scheduleSlotAdvance()
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        }
    }

    /// Pull the live infinite-mixtapes catalog and rebuild the dial. Best-effort:
    /// on failure (offline, etc.) the cached seed stays in place. On success the
    /// feed is cached to disk for the next launch.
    func refreshMixtapes() async {
        guard let feed = try? await NTSAPI.mixtapes(), !feed.isEmpty else { return }
        catalog.mixtapes = Catalog.build(from: feed)
        Cache.saveFeed(feed)
        if currentMixtape == nil, case .mixtape = selection { loadCurrent(autoplay: false) }
        // The first mixtape's alias is only known once the catalog loads (cold
        // start), and the live feed can reorder it; these are no-ops unless the
        // target stream actually changed.
        updateTracklist()
        updateMixtapeTitle()
    }
}
