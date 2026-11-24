import Foundation
import NTSFirestore
import TrackHold

/// The tracklist and source episode for whatever is tuned: the Firestore
/// `live_tracks` and `mixtape_titles` listeners, the per-source cache, and the
/// hold that keeps a new track off screen until its audio is heard. `AppModel`
/// tells it what is tuned through `follow`; a past episode's whole tracklist,
/// known up front, goes straight in through `publish`.
@MainActor
final class LiveTracklist: ObservableObject {
    /// Tracklist for the current source — populated by the Firestore listener for
    /// both mixtapes and live channels when signed in (empty when signed out).
    @Published private(set) var tracks: [Track] = []

    /// The current source episode for the playing mixtape (the show episode its
    /// audio is pulled from), or nil for live channels / before the first push /
    /// when signed out. Drives the now-playing bar's secondary line + its link.
    @Published private(set) var mixtapeEpisode: MixtapeTitle?

    /// A pushed tracklist waiting for the audio it describes to be heard.
    /// Deliberately not published: holding a track changes nothing on screen,
    /// and the release that does goes through `tracks`.
    var pending: TrackHold<[Track]>.Held? { hold.held }

    private let auth: NTSAuth
    private let episodeIndex: EpisodeIndex
    private let bufferedAhead: () -> TimeInterval
    private let isPlaying: () -> Bool

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

    /// Which source `tracks` and `mixtapeEpisode` belong to — nil for idle and a
    /// past episode — so moving to another source can stash them under it.
    private var shownSource: SourceKey?

    /// The last published tracks and mixtape episode for a source that isn't
    /// selected right now, stamped with when they were captured — so switching
    /// away and back within a couple of minutes shows what was already known
    /// instead of a blank list until the next Firestore push. In-memory only:
    /// a stale cache surviving a relaunch is the bug this exists to avoid.
    private struct SourceCache {
        let tracks: [Track]
        let mixtapeEpisode: MixtapeTitle?
        let capturedAt: Date
    }
    private var sourceCache: [SourceKey: SourceCache] = [:]
    private static let sourceCacheTTL: TimeInterval = 120

    private var hold = TrackHold<[Track]>()
    private var trackRelease: Task<Void, Never>?

    init(auth: NTSAuth, episodeIndex: EpisodeIndex,
         bufferedAhead: @escaping () -> TimeInterval, isPlaying: @escaping () -> Bool) {
        self.auth = auth
        self.episodeIndex = episodeIndex
        self.bufferedAhead = bufferedAhead
        self.isPlaying = isPlaying
    }

    /// Follow what is tuned now. Called on every tune, sign-in flip and catalog
    /// refresh; a call that changes neither the stream nor the mixtape is a
    /// no-op, so it never churns a connection.
    func follow(_ s: Selection, mixtape: Mixtape?, channel: Channel?) {
        let key = SourceKey(s)
        if key != shownSource {
            if let shownSource {
                sourceCache[shownSource] = SourceCache(tracks: tracks, mixtapeEpisode: mixtapeEpisode,
                                                       capturedAt: Date())
            }
            shownSource = key
        }
        let cached = key.flatMap { sourceCache[$0] }
            .flatMap { Date().timeIntervalSince($0.capturedAt) < Self.sourceCacheTTL ? $0 : nil }
        followTracks(s, mixtape: mixtape, channel: channel, cached: cached?.tracks ?? [])
        followTitle(auth.isAuthenticated ? mixtape?.alias : nil, cached: cached?.mixtapeEpisode)
    }

    /// Open (or tear down) the live tracklist stream for the current source.
    /// Signed in → a Firestore `live_tracks` listener for the current mixtape or
    /// channel; signed out → cleared (both feeds are supporter-gated). The public
    /// REST tracklist endpoint is empty for an in-progress channel show, so live
    /// channel tracks come from Firestore too, not REST.
    private func followTracks(_ s: Selection, mixtape: Mixtape?, channel: Channel?, cached: [Track]) {
        let wanted = auth.isAuthenticated
            ? TracklistAdapter.stream(for: s, mixtape: mixtape, channel: channel)
            : nil
        // Already streaming the right source — don't churn the connection (this
        // also makes a catalog rebuild a no-op unless the first mixtape changed).
        if listener != nil, wanted == activeStream { return }
        listener?.stop()
        listener = nil
        publish(cached)
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
    /// it names has actually reached the speakers. The rule is `TrackHold`'s.
    private func receive(_ incoming: [Track]) {
        let step = hold.receive(incoming, key: incoming.first?.key, startedAt: incoming.first?.startedAt,
                                shownKey: tracks.first?.key, playing: isPlaying(),
                                buffered: bufferedAhead(), now: Date())
        switch step {
        case .show: publish(incoming)
        case .hold(let deadline): scheduleTrackRelease(at: deadline)
        }
    }

    /// The track that has started but isn't being shown yet, and how long it has
    /// left to wait. Without this the delay can't be observed from outside at all —
    /// its whole effect is that nothing happens for a few seconds.
    var pendingTrack: (name: String, seconds: Double)? {
        guard let held = pending, let first = held.payload.first else { return nil }
        return ("\(first.artist) — \(first.title)",
                (max(0, held.deadline.timeIntervalSinceNow) * 10).rounded() / 10)
    }

    /// Show a tracklist now, dropping anything held.
    func publish(_ incoming: [Track]) {
        trackRelease?.cancel()
        trackRelease = nil
        hold.clear()
        tracks = incoming
    }

    private func scheduleTrackRelease(at deadline: Date) {
        trackRelease?.cancel()
        let delay = max(0, deadline.timeIntervalSinceNow)
        trackRelease = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, let held = self.pending else { return }
            self.publish(held.payload)
        }
    }

    /// Open (or tear down) the current-episode stream for the playing mixtape.
    /// Signed in + a mixtape selected → a Firestore `mixtape_titles` listener;
    /// otherwise cleared (live channels have no source episode, and the feed is
    /// supporter-gated). Mirrors `followTracks`'s no-churn guard.
    private func followTitle(_ alias: String?, cached: MixtapeTitle?) {
        if titleListener != nil, alias == activeTitleAlias { return }
        titleListener?.stop()
        titleListener = nil
        mixtapeEpisode = cached
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
                if let episode, episode.showAlias.isEmpty || episode.episodeAlias.isEmpty {
                    let resolved = self.episodeIndex.resolve(title: episode.title)
                    Log.api.debug("mixtape_titles for \(alias, privacy: .public) sent no alias for \"\(episode.title, privacy: .public)\" — EpisodeIndex resolved: \(resolved.map { "\($0.show)/\($0.episode)" } ?? "refused", privacy: .public)")
                }
            }
        )
        titleListener = listener
        listener.start()
    }
}
