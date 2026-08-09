import AppKit
import Combine
import MediaPlayer
import SwiftUI

/// Bridges the app to the system playback controls: the laptop's media keys, a
/// headset's play/pause and skip buttons, and the Now Playing tile in Control
/// Center and the menu bar.
///
/// Two halves of MediaPlayer.framework, both needed. `MPRemoteCommandCenter`
/// receives the button presses; `MPNowPlayingInfoCenter` publishes what's
/// playing — and publishing is also what makes macOS route the keys here at all,
/// so an app that only registers commands never hears from them.
///
/// Everything here is a continuous stream, so the tile is marked live: no
/// scrubber, no elapsed time, and the seek/skip commands stay switched off.
@MainActor
final class NowPlayingCenter {
    private unowned let model: AppModel
    private var bag = Set<AnyCancellable>()

    /// What was last handed to the system. A refresh that changes none of it
    /// (hover, volume, a catalog rebuild that kept the same source) is dropped
    /// rather than churning the tile.
    private var published: Info?
    /// Which image `artwork` holds, so a download that lands after the user has
    /// moved on can be recognised as stale and thrown away.
    private var artworkKey: ArtworkKey?
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        wireCommands()
        // Everything the tile shows: which source is selected, the live track,
        // the mixtape's source episode, and whether audio is actually running.
        // `receive(on:)` defers to after the change lands — @Published fires in
        // willSet, so reading the model in the handler would see the old value.
        Publishers.Merge4(
            model.$selection.map { _ in () },
            model.$tracks.map { _ in () },
            model.$mixtapeEpisode.map { _ in () },
            model.engine.$isPlaying.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.refresh() }
        .store(in: &bag)
        refresh()
    }

    // MARK: Commands in

    private func wireCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.run { $0.play() } ?? .commandFailed }
        center.pauseCommand.addTarget { [weak self] _ in self?.run { $0.pause() } ?? .commandFailed }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.run { $0.togglePlay() } ?? .commandFailed
        }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.run { $0.step(by: 1) } ?? .commandFailed }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.run { $0.step(by: -1) } ?? .commandFailed }
        // A live stream has no timeline to move around in — leave these off so
        // the system never offers a scrubber or skip buttons for it.
        center.changePlaybackPositionCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.stopCommand.isEnabled = false
    }

    /// Run a command against the model on the main actor. The handler has to
    /// answer the system synchronously, so it reports success up front and does
    /// the work in the next main-actor hop; the alternative is asserting which
    /// thread MediaPlayer called us on.
    private func run(_ body: @escaping @MainActor (AppModel) -> Void) -> MPRemoteCommandHandlerStatus {
        guard !model.isIdle else { return .noSuchContent }
        let model = self.model
        Task { @MainActor in body(model) }
        return .success
    }

    // MARK: Metadata out

    /// What the tile shows for the current source. Equatable so an unchanged
    /// refresh can be skipped.
    private struct Info: Equatable {
        var title: String
        var artist: String
        var album: String
        var isPlaying: Bool
        var artwork: ArtworkKey?
    }

    /// Identifies the cover image without holding it: a remote URL for mixtape
    /// art and live-channel program art, or a channel number for the procedural
    /// gradient we draw ourselves when a channel has no program art.
    private enum ArtworkKey: Equatable {
        case remote(URL)
        case channelGradient(Int)
    }

    /// Rebuild the tile from the model's current state. Cheap and idempotent —
    /// call it from anywhere the now-playing text could have moved.
    func refresh() {
        let next = snapshot()
        guard next != published else { return }
        let keyChanged = next?.artwork != published?.artwork
        published = next
        if keyChanged { loadArtwork(next?.artwork) }
        push()
    }

    private func snapshot() -> Info? {
        let track = model.tracks.first
        switch model.selection {
        case .idle:
            return nil
        case .mixtape:
            guard let mix = model.currentMixtape else { return nil }
            return Info(
                title: track?.title ?? mix.title,
                artist: nonEmpty(track?.artist) ?? nonEmpty(model.mixtapeEpisode?.title) ?? mix.subtitle,
                album: "NTS · \(mix.title)",
                isPlaying: model.engine.isPlaying,
                artwork: mix.coverURL.map(ArtworkKey.remote)
            )
        case .channel:
            guard let channel = model.currentChannel else { return nil }
            return Info(
                title: track?.title ?? channel.show,
                artist: nonEmpty(track?.artist) ?? nonEmpty(channel.host) ?? channel.genre,
                album: "NTS \(channel.number) Live",
                isPlaying: model.engine.isPlaying,
                artwork: channel.background.map(ArtworkKey.remote)
                    ?? .channelGradient(channel.number)
            )
        }
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    /// Hand the current `published` info (plus whatever artwork has arrived) to
    /// the system, and switch the commands on or off to match.
    private func push() {
        let center = MPNowPlayingInfoCenter.default()
        let commands = MPRemoteCommandCenter.shared()
        guard let info = published else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            for command in [commands.playCommand, commands.pauseCommand, commands.togglePlayPauseCommand,
                            commands.nextTrackCommand, commands.previousTrackCommand] {
                command.isEnabled = false
            }
            return
        }
        for command in [commands.playCommand, commands.pauseCommand, commands.togglePlayPauseCommand,
                        commands.nextTrackCommand, commands.previousTrackCommand] {
            command.isEnabled = true
        }
        var fields: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyArtist: info.artist,
            MPMediaItemPropertyAlbumTitle: info.album,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: info.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork { fields[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = fields
        center.playbackState = info.isPlaying ? .playing : .paused
    }

    // MARK: Artwork

    private func loadArtwork(_ key: ArtworkKey?) {
        artworkTask?.cancel()
        artworkTask = nil
        artworkKey = key
        artwork = nil
        guard let key else { return }
        switch key {
        case .channelGradient(let number):
            guard let channel = model.catalog.channels.first(where: { $0.number == number }) else { return }
            artwork = Self.render(channel.art)
        case .remote(let url):
            // URLSession.shared reads the disk-backed URLCache the covers are
            // already in (see Cache.configureImageCache), so a source the user
            // has seen before paints without a round trip.
            artworkTask = Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      !Task.isCancelled,
                      let image = NSImage(data: data),
                      let self, self.artworkKey == key
                else { return }
                self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.push()
            }
        }
    }

    /// Draw a SwiftUI view into artwork — used for the live channels' procedural
    /// gradient, which has no image file behind it.
    private static func render(_ view: some View) -> MPMediaItemArtwork? {
        let size = NSSize(width: 512, height: 512)
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: size)
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }
}
