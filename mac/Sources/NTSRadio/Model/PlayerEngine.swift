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

    private var currentURL: URL?

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
    }

    func load(_ url: URL, autoplay: Bool) {
        if url != currentURL {
            currentURL = url
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        if autoplay { play() }
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
