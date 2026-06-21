import SwiftUI
import Combine

enum Selection: Equatable {
    case mixtape(Int)
    case channel(Int)
}

@MainActor
final class AppModel: ObservableObject {
    let catalog = Catalog.shared
    let engine = PlayerEngine()

    @Published var selection: Selection = .mixtape(0)
    @Published var muted = false { didSet { engine.apply(volume: volume, muted: muted) } }
    @Published var volume: Double = 72 { didSet { engine.apply(volume: volume, muted: muted) } }
    @Published var showTracks = false
    @Published var hoverIndex: Int? = nil
    @Published var settingsOpen = false

    /// Tracklist for the current source. Empty until wired to a real source
    /// (live-channel tracklist + mixtape recently-played are deferred —
    /// tracked in tmp/claude/followups.md).
    @Published var tracks: [Track] = []

    // Settings placeholders — Account + Updates are intentionally non-functional
    // for v1 (tracked in tmp/claude/followups.md). These only drive local UI.
    @Published var startOnLogin = false
    @Published var aboutOpen = false

    private var bag = Set<AnyCancellable>()

    init() {
        engine.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &bag)
        engine.apply(volume: volume, muted: muted)
        loadCurrent(autoplay: false)
        Task { await refreshLive() }
    }

    // MARK: Derived view-model

    var isPlaying: Bool { engine.isPlaying }
    var isLive: Bool { if case .channel = selection { return true }; return false }

    var currentMixtape: Mixtape? {
        if case .mixtape(let i) = selection, catalog.mixtapes.indices.contains(i) {
            return catalog.mixtapes[i]
        }
        return nil
    }
    var currentChannel: Channel? {
        if case .channel(let n) = selection { return catalog.channels.first { $0.number == n } }
        return nil
    }

    var displayName: String {
        (currentMixtape?.title ?? currentChannel?.show ?? "").uppercased()
    }

    var subtitle: String {
        if let m = currentMixtape { _ = m; return "24/7 STREAM · NON-STOP" }
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
    }

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
            }
        }
        objectWillChange.send()
    }
}
