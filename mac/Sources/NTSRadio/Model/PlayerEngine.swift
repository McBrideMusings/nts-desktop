import AVFoundation
import Combine

/// Thin AVPlayer wrapper. Handles both the live MP3 relay streams and the
/// mixtape HLS streams transparently (AVPlayer negotiates either).
@MainActor
final class PlayerEngine: ObservableObject {
    private let player = AVPlayer()
    @Published private(set) var isPlaying = false

    /// Whether audio is actually coming out, as opposed to whether it was asked
    /// for. `isPlaying` is set inside `play()`/`pause()` and never revised, so it
    /// reports intent: with `automaticallyWaitsToMinimizeStalling` on, a stalled
    /// stream leaves AVPlayer in `.waitingToPlayAtSpecifiedRate` producing silence
    /// while `isPlaying` stays true. Anything that reports live playback back to
    /// the user reads this instead — the play/pause button still reads `isPlaying`,
    /// because a button should reflect what you pressed.
    @Published private(set) var isRendering = false

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

    /// What is actually loaded, for a script to read back. An episode's audio is
    /// resolved at play time, so this is the only place the resulting stream is
    /// observable — the selection just names the episode.
    var currentURLString: String { currentURL?.absoluteString ?? "" }

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        player.publisher(for: \.timeControlStatus)
            .map { $0 == .playing }
            .removeDuplicates()
            .assign(to: &$isRendering)

        // Twice a second: fast enough that a scrubber tracks the audio, slow
        // enough to be nothing. The observer outlives each item, so it is added
        // once here rather than rebuilt on every load.
        ticker = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
    }

    deinit {
        if let ticker { player.removeTimeObserver(ticker) }
    }

    private func tick(_ time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        position = seconds.isFinite ? max(0, seconds) : 0

        let length = player.currentItem.map { CMTimeGetSeconds($0.duration) } ?? Double.nan
        duration = (length.isFinite && length > 0) ? length : 0
    }

    func load(_ url: URL, autoplay: Bool) {
        if url != currentURL {
            currentURL = url
            // A new item starts at zero with an unknown length. Leaving the old
            // values up would show the previous episode's scrubber against this
            // one's audio for the second before the first tick lands.
            position = 0
            duration = 0
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        if autoplay { play() }
    }

    /// Move the playhead. A no-op on an endless stream: there is nowhere to move
    /// to, and AVPlayer would seek within the buffered live tail.
    func seek(to seconds: Double) {
        guard isSeekable else { return }
        let target = max(0, min(duration, seconds))
        position = target
        seeks += 1
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
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

    /// `volume` is 0–100 to match the prototype's meter.
    func apply(volume: Double, muted: Bool) {
        player.volume = Float(max(0, min(100, volume)) / 100)
        player.isMuted = muted
    }
}
