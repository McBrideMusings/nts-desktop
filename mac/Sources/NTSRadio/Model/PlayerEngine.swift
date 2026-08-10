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

    /// `volume` is 0–100 to match the prototype's meter.
    func apply(volume: Double, muted: Bool) {
        player.volume = Float(max(0, min(100, volume)) / 100)
        player.isMuted = muted
    }
}
