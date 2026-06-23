import SwiftUI
import Combine
import NTSFirestore

enum Selection: Equatable {
    case mixtape(String)   // mixtape alias — stable across catalog rebuilds
    case channel(Int)

    /// Sentinel meaning "the first mixtape", used before the catalog has loaded
    /// (its alias isn't known yet at init).
    static let firstMixtape = Selection.mixtape("")
}

@MainActor
final class AppModel: ObservableObject {
    let catalog = Catalog.shared
    let engine = PlayerEngine()
    let auth = NTSAuth()

    @Published var selection: Selection = .firstMixtape
    @Published var muted = false { didSet { engine.apply(volume: volume, muted: muted) } }
    @Published var volume: Double = 72 { didSet { engine.apply(volume: volume, muted: muted) } }
    @Published var showTracks = false
    @Published var hoverIndex: Int? = nil
    @Published var settingsOpen = false

    /// Tracklist for the current source — populated by the Firestore listener for
    /// mixtapes (live-channel tracklists are not wired yet; see GitHub issue #3).
    @Published var tracks: [Track] = []

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

    /// Live tracklist listener for the current mixtape (nil for channels or when
    /// signed out). Recreated whenever the source or auth state changes.
    private var listener: FirestoreListener?
    /// The mixtape alias the `listener` is currently streaming, so we can tell a
    /// real source change from a no-op refresh and avoid churning the stream.
    private var activeStreamID: String?

    private var bag = Set<AnyCancellable>()

    init() {
        engine.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &bag)
        engine.apply(volume: volume, muted: muted)
        catalog.mixtapes = Catalog.build(from: Cache.loadFeed())   // instant/offline seed
        loadCurrent(autoplay: false)
        // Re-open the tracklist stream whenever sign-in state flips.
        auth.$isAuthenticated
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateTracklist() }
            .store(in: &bag)
        updateTracklist()
        Task { await refreshMixtapes() }
        Task { await pollLive() }
    }

    // MARK: Derived view-model

    var isPlaying: Bool { engine.isPlaying }
    var isLive: Bool { if case .channel = selection { return true }; return false }

    var currentMixtape: Mixtape? {
        guard case .mixtape(let alias) = selection else { return nil }
        // Empty alias is the "first mixtape" sentinel used before a real one is
        // picked; otherwise resolve by alias (nil if it's gone from the catalog).
        if alias.isEmpty { return catalog.mixtapes.first }
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
        if currentMixtape != nil { return "24/7 STREAM · NON-STOP" }
        if let c = currentChannel {
            var parts: [String] = []
            if !c.startEnd.isEmpty { parts.append(c.startEnd) }
            if !c.host.isEmpty { parts.append("WITH \(c.host.uppercased())") }
            if !c.genre.isEmpty { parts.append(c.genre.uppercased()) }
            return parts.joined(separator: " · ")
        }
        return ""
    }

    var accent: Color {
        currentMixtape?.accent ?? currentChannel?.accent ?? Theme.ink
    }

    var tracksLabel: String { isLive ? "TRACKLIST" : "RECENTLY PLAYED" }

    // MARK: Actions

    func select(_ s: Selection) {
        selection = s
        loadCurrent(autoplay: engine.isPlaying)
        updateTracklist()
    }

    /// Open (or tear down) the live tracklist stream for the current source.
    /// Mixtape + signed in → Firestore `live_tracks` listener. Channels and the
    /// signed-out state clear the list (live-channel tracklists via the public
    /// REST endpoint are a separate follow-up).
    func updateTracklist() {
        // The stream we *should* be running: the current mixtape's alias when
        // signed in, otherwise nothing.
        let wantedAlias: String? = {
            guard auth.isAuthenticated, case .mixtape = selection else { return nil }
            return currentMixtape?.alias
        }()
        // Already streaming the right source — don't churn the connection (this
        // also makes a catalog rebuild a no-op unless the first mixtape changed).
        if listener != nil, wantedAlias == activeStreamID { return }
        listener?.stop()
        listener = nil
        tracks = []
        activeStreamID = wantedAlias
        guard let alias = wantedAlias, let mix = currentMixtape else { return }
        let hue = mix.hue
        let listener = FirestoreListener(
            streamID: alias,
            tokenProvider: { [auth] in try await auth.validToken() },
            onUpdate: { [weak self] live in
                self?.tracks = live.compactMap { t in
                    t.title.isEmpty ? nil
                        : Track(time: Self.hhmm.string(from: t.startTime),
                                title: t.title,
                                artist: t.artists.joined(separator: ", "),
                                hue: hue)
                }
            }
        )
        self.listener = listener
        listener.start()
    }

    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    func loadCurrent(autoplay: Bool) {
        let url = currentMixtape?.streamURL ?? currentChannel?.streamURL
        if let url { engine.load(url, autoplay: autoplay) }
    }

    func togglePlay() {
        if engine.isPlaying { engine.pause() }
        else { loadCurrent(autoplay: true) }
    }

    /// Pull live now-playing for the two channels. Best-effort: failures leave
    /// the seeded placeholders in place.
    func refreshLive() async {
        guard let info = try? await NTSAPI.live() else { return }
        for upd in info {
            if let idx = catalog.channels.firstIndex(where: { $0.number == upd.channel }) {
                catalog.channels[idx].show = upd.show
                catalog.channels[idx].startEnd = upd.startEnd
                catalog.channels[idx].genre = upd.genre
                catalog.channels[idx].background = upd.background.flatMap { URL(string: $0) }
            }
        }
        objectWillChange.send()
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
        // start), and the live feed can reorder it; updateTracklist() is a no-op
        // unless the target stream actually changed.
        updateTracklist()
        objectWillChange.send()
    }
}
