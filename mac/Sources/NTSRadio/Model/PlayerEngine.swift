import AppKit
import AVFoundation
import Combine
import Network

/// Thin AVPlayer wrapper. Handles both the live MP3 relay streams and the
/// mixtape HLS streams transparently (AVPlayer negotiates either).
@MainActor
final class PlayerEngine: ObservableObject {
    private let player = AVPlayer()
    @Published private(set) var isPlaying = false {
        didSet { if isPlaying != oldValue { watchStall() } }
    }

    /// Whether audio is actually coming out, as opposed to whether it was asked
    /// for. `isPlaying` is set inside `play()`/`pause()` and never revised, so it
    /// reports intent: with `automaticallyWaitsToMinimizeStalling` on, a stalled
    /// stream leaves AVPlayer in `.waitingToPlayAtSpecifiedRate` producing silence
    /// while `isPlaying` stays true. Anything that reports live playback back to
    /// the user reads this instead — the play/pause button still reads `isPlaying`,
    /// because a button should reflect what you pressed.
    ///
    /// It also needs the current item to be ready: right after
    /// `replaceCurrentItem` the player can still report `.playing` for a moment,
    /// which read as the new source rendering when it was the old one's audio.
    @Published private(set) var isRendering = false {
        didSet { if isRendering != oldValue { watchStall() } }
    }

    /// How far into the current item playback has reached, in seconds.
    @Published private(set) var position: Double = 0

    /// How long the current item runs, in seconds — 0 when that is not a
    /// question with an answer.
    ///
    /// The live channels and the mixtapes are endless: AVPlayer reports their
    /// duration as `indefinite`, which is the truth, not a failure to load. A
    /// past episode is a finite recording, so its playlist carries a real
    /// length. That difference is what `isSeekable` is reading — the app never
    /// has to be told which kind of thing is playing.
    @Published private(set) var duration: Double = 0

    /// Whether there is a position within this item to move to.
    var isSeekable: Bool { duration > 0 }

    /// How many times the playhead has been moved. The system tile extrapolates
    /// elapsed time from the playback rate, so it only needs re-telling when the
    /// playhead jumps — this is what makes a jump observable to it.
    @Published private(set) var seeks = 0

    private var currentURL: URL?
    private var ticker: Any?
    private var renderingWatch: AnyCancellable?

    /// Whether what is loaded is a live channel or a mixtape — a stream with no
    /// end, where a reload rejoins the live head and loses nothing. An episode
    /// is not one: reloading it would start it again from 0:00, so recovery
    /// leaves it alone.
    private(set) var isEndless = false

    // MARK: Recovery state, for the scripted `state` and the log.

    /// Reloads made since audio last came out. Zero means no recovery is under
    /// way; it goes back to zero when the stream renders again, or when the
    /// listener pauses or tunes something else.
    private(set) var recoveryAttempts = 0
    /// What prompted the latest reload: `wake`, `network`, `item failed: …`,
    /// `stalled`, `retry`.
    private(set) var recoveryReason = ""
    private(set) var lastRecoveryAttempt: Date?
    /// Streaks that ended with audio coming out again, since launch.
    private(set) var recoveries = 0
    private(set) var lastRecovered: Date?
    /// The network path as `NWPathMonitor` last reported it; nil before its
    /// first report.
    private(set) var networkSatisfied: Bool?

    /// How long a stream that should be playing may stay silent before it is
    /// reloaded with no other event to say it died — a Wi-Fi blip that never
    /// changed the network path, or a server that stopped sending.
    static let stallGrace: Duration = .seconds(15)

    /// How long a reload gets to start rendering before the next one: 5, 10,
    /// 20, then 30 seconds for as long as it takes. The first wait is long
    /// enough for a slow network to fill the buffer, so a reload is never cut
    /// off by the one after it.
    static func backoff(after attempt: Int) -> Duration {
        .seconds(min(5 * (1 << min(attempt - 1, 3)), 30))
    }

    /// The pending stall grace or retry — never both, so a trigger replaces it.
    private var recoveryTimer: Task<Void, Never>?
    private var itemWatch: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private let pathMonitor = NWPathMonitor()

    /// Which seek is the one that matters. AVPlayer's periodic time observer
    /// keeps firing with the pre-seek time while a seek is still landing — with
    /// `toleranceBefore/After: .zero` that can take a couple of ticks — and each
    /// one was overwriting `position` back to where the scrub started before the
    /// real seek arrived, which is the flicker: the thumb visibly snaps back and
    /// then forward again. Ticks are ignored between calling `seek` and that
    /// exact seek's completion handler firing; the epoch guards against an older
    /// seek's completion clearing the flag after a newer one has already
    /// started.
    private var seekEpoch = 0
    private var isSeeking = false

    /// What is actually loaded, for a script to read back. An episode's audio is
    /// resolved at play time, so this is the only place the resulting stream is
    /// observable — the selection just names the episode.
    var currentURLString: String { currentURL?.absoluteString ?? "" }

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        // AVPlayerItem doesn't promise which thread its status KVO fires on, so
        // an off-main value hops over. An on-main one lands inline, not via
        // `receive(on:)`: `replaceCurrentItem` must read false before the same
        // call returns, or a script's reply still reports the old stream.
        renderingWatch = player.publisher(for: \.timeControlStatus)
            .combineLatest(player.publisher(for: \.currentItem?.status))
            .map { $0 == .playing && $1 == .readyToPlay }
            .removeDuplicates()
            .sink { [weak self] rendering in
                guard Thread.isMainThread else {
                    DispatchQueue.main.async { self?.isRendering = rendering }
                    return
                }
                MainActor.assumeIsolated { self?.isRendering = rendering }
            }

        // Twice a second: fast enough that a scrubber tracks the audio, slow
        // enough to be nothing. The observer outlives each item, so it is added
        // once here rather than rebuilt on every load.
        ticker = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }

        watchForDeadStreams()
    }

    deinit {
        if let ticker { player.removeTimeObserver(ticker) }
        pathMonitor.cancel()
    }

    /// The three events that say a stream has probably died, each of which
    /// AVPlayer itself sits through in silence: the Mac waking (the socket
    /// opened before sleep is gone), the network coming back after a loss,
    /// and the item failing outright.
    private func watchForDeadStreams() {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })

        for name in [AVPlayerItem.failedToPlayToEndTimeNotification, AVPlayerItem.didPlayToEndTimeNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] note in
                let error = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                    .localizedDescription
                let item = note.object as AnyObject?
                MainActor.assumeIsolated {
                    guard let self, item === self.player.currentItem else { return }
                    // An episode reaching its end is the episode finishing.
                    guard self.isEndless else { return }
                    self.itemDied(error.map { "failed to play to end: \($0)" } ?? "stream ended")
                }
            })
        }

        itemWatch = player.publisher(for: \.currentItem?.status)
            .filter { $0 == .failed }
            .sink { [weak self] _ in
                guard Thread.isMainThread else {
                    DispatchQueue.main.async { self?.currentItemFailed() }
                    return
                }
                MainActor.assumeIsolated { self?.currentItemFailed() }
            }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            DispatchQueue.main.async { self?.networkChanged(satisfied: satisfied) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "live.nts.desktop.path"))
    }

    func didWake() {
        Log.player.info("wake: playing=\(self.isPlaying) rendering=\(self.isRendering)")
        recoverIfStalled(reason: "wake")
    }

    func networkChanged(satisfied: Bool) {
        let was = networkSatisfied
        networkSatisfied = satisfied
        guard was != satisfied else { return }
        Log.player.info("network path \(satisfied ? "satisfied" : "unsatisfied", privacy: .public)")
        // The first report is the state at launch, not a return.
        if satisfied, was == false { recoverIfStalled(reason: "network") }
    }

    private func currentItemFailed() {
        let error = player.currentItem?.error?.localizedDescription ?? "no error given"
        itemDied("item failed: \(error)")
    }

    /// A failure that lands while a retry is already waiting is that retry's
    /// own reload failing — offline, say — and reloading again at once would
    /// turn the backoff into a tight loop. Only a wake or a returning network
    /// jumps the queue.
    private func itemDied(_ reason: String) {
        Log.player.error("\(reason, privacy: .public) url=\(self.currentURLString, privacy: .public)")
        guard recoveryAttempts == 0 else { return }
        // A failed item cannot be rendering, whatever `isRendering` reads:
        // that comes from a separate KVO that may not have landed yet.
        recover(reason: reason)
    }

    /// Reload the current stream at the live head when the listener asked for
    /// audio and none is coming out, then check again after `backoff` and keep
    /// going until it renders or the listener stops asking. Does nothing to an
    /// episode, a paused player, or one that is rendering.
    func recoverIfStalled(reason: String) {
        guard !isRendering else {
            Log.player.info("recover skipped reason=\(reason, privacy: .public): rendering")
            return
        }
        recover(reason: reason)
    }

    private func recover(reason: String) {
        guard isPlaying, isEndless, let url = currentURL else {
            Log.player.info("""
                recover skipped reason=\(reason, privacy: .public) playing=\(self.isPlaying) \
                rendering=\(self.isRendering) endless=\(self.isEndless)
                """)
            return
        }
        recoveryAttempts += 1
        recoveryReason = reason
        lastRecoveryAttempt = Date()
        let wait = Self.backoff(after: recoveryAttempts)
        Log.player.notice("""
            recover attempt=\(self.recoveryAttempts) reason=\(reason, privacy: .public) \
            next-check=\(String(describing: wait), privacy: .public) url=\(url.absoluteString, privacy: .public)
            """)
        replaceItem(with: url)
        player.play()
        arm(after: wait) { $0.recoverIfStalled(reason: "retry") }
    }

    /// Start or clear the timer that turns a silence into a recovery. Called
    /// whenever `isPlaying` or `isRendering` changes.
    private func watchStall() {
        if isRendering {
            if recoveryAttempts > 0 {
                recoveries += 1
                lastRecovered = Date()
                Log.player.notice("""
                    recovered after \(self.recoveryAttempts) attempt(s), \
                    last reason=\(self.recoveryReason, privacy: .public)
                    """)
                recoveryAttempts = 0
            }
            disarm()
            return
        }
        guard isPlaying, isEndless, currentURL != nil else {
            if recoveryAttempts > 0 {
                Log.player.info("recovery dropped after \(self.recoveryAttempts) attempt(s): no longer playing")
                recoveryAttempts = 0
            }
            disarm()
            return
        }
        guard recoveryTimer == nil else { return }
        arm(after: Self.stallGrace) { $0.recoverIfStalled(reason: "stalled") }
    }

    private func arm(after wait: Duration, _ fire: @escaping @MainActor (PlayerEngine) -> Void) {
        recoveryTimer?.cancel()
        recoveryTimer = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self else { return }
            self.recoveryTimer = nil
            fire(self)
        }
    }

    private func disarm() {
        recoveryTimer?.cancel()
        recoveryTimer = nil
    }

    private func tick(_ time: CMTime) {
        // A tick landing mid-seek is reporting where the audio was, not where
        // it's headed — `seek(to:)` already set `position` to the target.
        guard !isSeeking else { return }
        let seconds = CMTimeGetSeconds(time)
        position = seconds.isFinite ? max(0, seconds) : 0

        let length = player.currentItem.map { CMTimeGetSeconds($0.duration) } ?? Double.nan
        duration = (length.isFinite && length > 0) ? length : 0
    }

    /// `force` re-requests the stream even if `url` matches what's already
    /// loaded — for live channels and mixtapes, resuming from pause must
    /// reconnect at the live edge, not replay the AVPlayerItem's buffered
    /// audio from wherever it was paused.
    ///
    /// `endless` says the URL is a live channel or a mixtape, which recovery
    /// may reload when it falls silent; an episode passes false.
    func load(_ url: URL, endless: Bool, autoplay: Bool, force: Bool = false) {
        if url != currentURL || force {
            // A choice the listener made ends any recovery of what was there.
            recoveryAttempts = 0
            disarm()
            isEndless = endless
            replaceItem(with: url)
            Log.player.info("load \(url.absoluteString, privacy: .public) endless=\(endless) autoplay=\(autoplay)")
        }
        if autoplay { play() }
    }

    private func replaceItem(with url: URL) {
        currentURL = url
        // A new item starts at zero with an unknown length. Leaving the old
        // values up would show the previous episode's scrubber against this
        // one's audio for the second before the first tick lands.
        position = 0
        duration = 0
        // A pending seek's completion belongs to the item it was asked of;
        // an interrupted one may never call back, which would otherwise
        // leave ticks off for the new item too.
        isSeeking = false
        seekEpoch += 1
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    /// Break the stream on purpose so a script can watch recovery mend it
    /// without sleeping the Mac or dropping its network. `stall` stops the
    /// audio while the listener's intent stays "playing"; `failure` swaps in
    /// an item that cannot connect, leaving `currentURL` as the real stream.
    func simulateStall() {
        player.pause()
        Log.player.info("simulate stall")
    }

    func simulateFailure() {
        // Port 9 (discard) on loopback refuses the connection at once.
        player.replaceCurrentItem(with: AVPlayerItem(url: URL(string: "http://127.0.0.1:9/dead")!))
        if isPlaying { player.play() }
        Log.player.info("simulate failure")
    }

    /// Drop the current item entirely — the state the engine is in at launch,
    /// before anything has been tuned. Pausing alone keeps the stream open.
    func unload() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentURL = nil
        isEndless = false
        position = 0
        duration = 0
        isSeeking = false
        seekEpoch += 1
        isPlaying = false
        Log.player.info("unload")
    }

    /// Move the playhead. A no-op on an endless stream: there is nowhere to move
    /// to, and AVPlayer would seek within the buffered live tail.
    func seek(to seconds: Double) {
        guard isSeekable else { return }
        let target = max(0, min(duration, seconds))
        position = target
        seeks += 1
        isSeeking = true
        seekEpoch += 1
        let epoch = seekEpoch
        // AVPlayer doesn't document which queue this fires on, unlike the time
        // observer above (which asked for `.main` explicitly), so this hops
        // over rather than assuming.
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.seekEpoch == epoch else { return }
                self.isSeeking = false
            }
        }
    }

    func play() {
        guard currentURL != nil else { return }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func toggle() { isPlaying ? pause() : play() }

    /// Seconds of audio already fetched but not yet heard.
    ///
    /// The channel streams are a live Icecast tail carrying no timestamps —
    /// `StreamTitle` comes through empty — so there is no clock inside the audio
    /// to compare a track against. What can be measured is this: everything
    /// AVPlayer has pulled off the socket and is sitting on. The connection always
    /// reads the live edge, so that hold is how far the speakers are behind the
    /// stream, while the tracklist arrives at the live edge out of band over
    /// Firestore. It is the app-side half of why a row lights up early.
    var bufferedAhead: Double {
        guard let item = player.currentItem,
              let range = item.loadedTimeRanges.last?.timeRangeValue else { return 0 }
        let edge = CMTimeGetSeconds(range.start + range.duration)
        let playhead = CMTimeGetSeconds(item.currentTime())
        guard edge.isFinite, playhead.isFinite else { return 0 }
        return max(0, edge - playhead)
    }

    /// `volume` is 0–100 to match the prototype's meter; `Preferences` owns the clamp.
    func apply(volume: Double, muted: Bool) {
        player.volume = Float(volume / 100)
        player.isMuted = muted
    }
}
