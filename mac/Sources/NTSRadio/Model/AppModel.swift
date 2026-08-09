import SwiftUI
import Combine
import NTSFirestore

enum Selection: Equatable {
    case idle              // nothing selected — the default empty state on launch
    case mixtape(String)   // mixtape alias — stable across catalog rebuilds
    case channel(Int)
}

/// The one modal popover that can be open at a time.
enum Sheet: Equatable {
    case settings
    case login
}

@MainActor
final class AppModel: ObservableObject {
    let catalog = Catalog.shared
    let engine = PlayerEngine()
    let auth = NTSAuth()

    @Published var selection: Selection = .idle
    @Published var muted = false { didSet { engine.apply(volume: volume, muted: muted) } }
    @Published var volume: Double = 72 { didSet { engine.apply(volume: volume, muted: muted) } }
    @Published var showTracks = false
    @Published var hoverIndex: Int? = nil
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

    /// DISPLAY setting (prototype): once the window shrinks to the compact dial,
    /// drop the channel disc's center number. On by default. Persisted.
    @Published var hideDialDotWhenSmall: Bool =
        (UserDefaults.standard.object(forKey: "hideDialDotWhenSmall") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(hideDialDotWhenSmall, forKey: "hideDialDotWhenSmall") }
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

    private var bag = Set<AnyCancellable>()

    init() {
        // Both are observable objects of their own; republish their changes as
        // ours so a view watching the model repaints when the stream starts or
        // the dial's contents move.
        for upstream in [engine.objectWillChange, catalog.objectWillChange] {
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
        (currentMixtape?.title ?? currentChannel?.show ?? "").uppercased()
    }

    var subtitle: String {
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
    var nowPlayingShowURL: URL? { currentChannel?.episodeURL }

    var accent: Color {
        currentMixtape?.accent ?? currentChannel?.accent ?? Theme.ink
    }

    var tracksLabel: String { isLive ? "TRACKLIST" : "RECENTLY PLAYED" }

    // MARK: Actions

    func select(_ s: Selection) {
        selection = s
        loadCurrent(autoplay: engine.isPlaying)
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
        tracks = []
        activeStream = wanted
        guard let wanted else { return }
        let hue = wanted.hue
        let listener = FirestoreListener(
            filter: wanted.filter,
            tokenProvider: { [auth] in try await auth.validToken() },
            onUpdate: { [weak self] live in
                self?.tracks = TracklistAdapter.tracks(from: live, hue: hue)
            }
        )
        self.listener = listener
        listener.start()
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
        let url = currentMixtape?.streamURL ?? currentChannel?.streamURL
        if let url { engine.load(url, autoplay: autoplay) }
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
    /// Playing state carries over, matching a click on the dial.
    func step(by delta: Int) {
        switch selection {
        case .idle:
            return
        case .channel(let number):
            let all = catalog.channels
            guard let i = all.firstIndex(where: { $0.number == number }) else { return }
            select(.channel(all[wrap(i + delta, all.count)].number))
        case .mixtape(let alias):
            let all = catalog.mixtapes
            guard let i = all.firstIndex(where: { $0.alias == alias }) else { return }
            select(.mixtape(all[wrap(i + delta, all.count)].alias))
        }
    }

    /// Index `i` folded back into `0..<count`, for negative values too (Swift's
    /// `%` keeps the sign of the left operand, so `-1 % 16` is `-1`, not `15`).
    private func wrap(_ i: Int, _ count: Int) -> Int {
        ((i % count) + count) % count
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

    /// Refresh now-playing immediately, then every 60s so the channel backdrop
    /// and show info track program changes while the app stays open.
    private func pollLive() async {
        await refreshLive()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            await refreshLive()
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
