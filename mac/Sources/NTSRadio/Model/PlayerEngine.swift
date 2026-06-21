import AVFoundation
import Combine

/// Thin AVPlayer wrapper. Handles both the live MP3 relay streams and the
/// mixtape HLS streams transparently (AVPlayer negotiates either).
@MainActor
final class PlayerEngine: ObservableObject {
    private let player = AVPlayer()
    @Published private(set) var isPlaying = false
    private var currentURL: URL?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
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
