import SwiftUI
import Combine
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

/// The one modal popover that can be open at a time.
enum Sheet: Equatable {
    case settings
    case login
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
    let catalog = Catalog.shared
    let engine = PlayerEngine()
    let auth = NTSAuth()
    let saved = Saved.shared
    let showIndex = ShowIndex.shared

    // MARK: Catalog surface

    /// Whether the catalog covers the faceplate. One toggle owns this — the ▤ in
    /// the title bar — so there is never a second way in that can disagree with it.
    @Published var catalogOpen = false
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
    @Published var showEpisodes: [String: [NTSAPI.Episode]] = [:]

    @Published var selection: Selection = .idle
    @Published var muted = false { didSet { engine.apply(volume: volume, muted: muted) } }
    @Published var volume: Double = 72 { didSet { engine.apply(volume: volume, muted: muted) } }
    @Published var showTracks = false
    @Published var hoverIndex: Int? = nil
    /// Where the dial's index mark is pointing, in degrees, accumulated across
    /// turns rather than wrapped into 0..<360 — so it is free to wind past a full
    /// turn in either direction and always takes the short way to the next tape.
    /// It lives here rather than in `DialView` so a script can read it back.
    @Published var knobAngle: Double = 0
    /// Which modal popover is up, if any — one at a time (settings and the account
    /// sheet are mutually exclusive). `settingsOpen`/`loginOpen` wrap it so callers
    /// stay simple while only one can ever be open.
    @Published var activeSheet: Sheet? = nil
    var settingsOpen: Bool {
        get { activeSheet == .settings }
        set { if newValue { activeSheet = .settings } else if activeSheet == .settings { activeSheet = nil } }
    }
    var loginOpen: Bool {
        get { activeSheet == .login }
        set { if newValue { activeSheet = .login } else if activeSheet == .login { activeSheet = nil } }
    }

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

    // Settings placeholder — Check for Updates is intentionally non-functional for
    // v1 (see GitHub issue #2). Start-on-Login only drives local UI.
    @Published var startOnLogin = false
    @Published var aboutOpen = false

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
            }
            .store(in: &bag)
        updateTracklist()
        updateMixtapeTitle()
        nowPlaying = NowPlayingCenter(model: self)
        Task { await refreshMixtapes() }
        Task { await pollLive() }
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
            if !c.host.isEmpty { parts.append("WITH \(c.host.uppercased())") }
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

    var tracksLabel: String { isLive ? "TRACKLIST" : "RECENTLY PLAYED" }

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

    // MARK: Catalog

    /// Show the catalog, or hide it. Closing drops the query and any open detail
    /// so reopening lands on a list rather than mid-navigation from last time.
    func toggleCatalog() {
        catalogOpen.toggle()
        if !catalogOpen { query = ""; detail = nil }
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
        if let genres = try? await NTSAPI.genres() { self.genres = genres }
    }

    func toggleGenre(_ id: String) {
        if let i = exploreFilters.genres.firstIndex(of: id) { exploreFilters.genres.remove(at: i) }
        else { exploreFilters.genres.append(id) }
    }

    func toggleMood(_ id: String) {
        exploreFilters.mood = exploreFilters.mood == id ? nil : id
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
        return saved.contains(item.kind, item.alias)
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

    /// Fetch a show's page and its recent episodes, once. Both are best-effort:
    /// a failure leaves the detail view on what the schedule row already knew.
    func loadShow(_ alias: String) async {
        if showDetails[alias] == nil, let d = try? await NTSAPI.show(alias: alias) {
            showDetails[alias] = d
            showIndex.note(alias: alias, name: d.name, location: d.location,
                           genres: d.genres, picture: d.image?.absoluteString)
        }
        if showEpisodes[alias] == nil, let eps = try? await NTSAPI.episodes(alias: alias) {
            showEpisodes[alias] = eps
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

    /// Pull live now-playing for the two channels. Best-effort: failures leave
    /// the seeded placeholders in place.
    func refreshLive() async {
        guard let info = try? await NTSAPI.live() else { return }
        for upd in info {
            if let idx = catalog.channels.firstIndex(where: { $0.number == upd.channel }) {
                let showChanged = catalog.channels[idx].show != upd.show
                catalog.channels[idx].show = upd.show
                catalog.channels[idx].startEnd = upd.startEnd
                catalog.channels[idx].genre = upd.genre
                catalog.channels[idx].background = upd.background.flatMap { URL(string: $0) }
                // A detail-less poll (no embeds.details) returns empty aliases —
                // don't blank a still-valid episode link mid-broadcast. Only update
                // the aliases when we got real ones or the broadcast actually changed.
                if !upd.showAlias.isEmpty || showChanged { catalog.channels[idx].showAlias = upd.showAlias }
                if !upd.episodeAlias.isEmpty || showChanged { catalog.channels[idx].episodeAlias = upd.episodeAlias }
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
            catalog.channels[idx].upcoming = slots.filter { ($0.end ?? .distantPast) > now }
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
    /// told. Waiting to be told left the rail showing the previous show: NTS serves
    /// `/api/v2/live` with `cache-control: max-age=900`, so for up to 15 minutes
    /// after the hour every poll returns the same pre-changeover JSON.
    func advanceSlots(now: Date = Date()) {
        withAnimation(.easeInOut(duration: 0.4)) { advance(now: now) }
    }

    private func advance(now: Date) {
        for idx in catalog.channels.indices {
            let live = catalog.channels[idx].upcoming.drop { ($0.end ?? .distantFuture) <= now }
            guard let current = live.first,
                  current.id != catalog.channels[idx].upcoming.first?.id else { continue }
            catalog.channels[idx].upcoming = Array(live)
            catalog.channels[idx].show = current.title
            catalog.channels[idx].startEnd = current.startEnd
            // The grid carries no genres or artwork, so the handover shows the
            // show's own — the episode's photograph arrives with the next
            // `/api/v2/live` poll, which embeds it for whatever is on now.
            let indexed = showIndex.ref(current.showAlias)
            catalog.channels[idx].genre = indexed?.genres.first ?? ""
            catalog.channels[idx].background = indexed?.pictureURL
            // A new broadcast means the old episode link is wrong, so these are
            // replaced outright rather than merged.
            catalog.channels[idx].showAlias = current.showAlias
            catalog.channels[idx].episodeAlias = current.episodeAlias
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

    /// Refresh now-playing immediately, then every 60s so the channel backdrop
    /// and show info track program changes while the app stays open.
    ///
    /// The poll re-anchors the schedule; the changeover itself is `advanceSlots`,
    /// which runs here too so a stale (or failed) response can't leave the rail on
    /// a programme that has already finished, and so a machine that slept through
    /// a boundary catches up on the next cycle.
    private func pollLive() async {
        while !Task.isCancelled {
            if scheduleFetched.map({ Date().timeIntervalSince($0) > Self.scheduleMaxAge }) ?? true {
                await refreshSchedule()
            }
            await refreshLive()
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
