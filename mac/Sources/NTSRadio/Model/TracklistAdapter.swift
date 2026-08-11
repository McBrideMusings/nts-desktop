import Foundation
import NTSFirestore

/// The seam between NTS's Firestore `live_tracks` wire format and the app's view
/// model. Owns both directions: building the listener's query filter for the
/// current source (filter-out), and mapping wire `LiveTrack`s to UI `Track`s
/// (tracks-in). Keeping both here keeps `AppModel` free of wire details.
enum TracklistAdapter {
    /// The wire filter for a source plus the accent hue its tracks render with.
    struct Stream: Equatable {
        let filter: LiveTracksFilter
        let hue: Double
    }

    /// The stream to listen to for the current source, or nil when there's
    /// nothing resolvable to stream. Both feeds are supporter-gated; the caller
    /// decides whether to actually open the stream based on sign-in.
    static func stream(for selection: Selection,
                       mixtape: Mixtape?,
                       channel: Channel?) -> Stream? {
        switch selection {
        case .idle:
            return nil
        // `live_tracks` is what is being played out right now on a channel or a
        // mixtape. A past episode is not being played out by NTS at all, so there
        // is no document to listen to.
        case .episode:
            return nil
        case .mixtape:
            guard let mix = mixtape else { return nil }
            return Stream(filter: .mixtape(mix.alias), hue: mix.hue)
        case .channel:
            guard let ch = channel, let filter = LiveTracksFilter.channel(ch.number) else { return nil }
            return Stream(filter: filter, hue: ch.artHue)
        }
    }

    /// Map wire tracks to UI tracks: drop any still being identified (empty
    /// title) and stamp each with the source's accent hue.
    static func tracks(from live: [LiveTrack], hue: Double) -> [Track] {
        live.compactMap { t in
            t.title.isEmpty ? nil
                : Track(time: hhmm.string(from: t.startTime),
                        title: t.title,
                        artist: t.artists.joined(separator: ", "),
                        hue: hue)
        }
    }

    /// A past episode's own tracklist, already ordered earliest-first. The time
    /// column reads as a position in the recording (`SeekBar`'s own clock),
    /// unlike a live push's wall-clock time — there is no broadcast time to show,
    /// only where the seek bar would need to be.
    static func tracks(from episode: [NTSAPI.EpisodeTrack], hue: Double) -> [Track] {
        episode.compactMap { t in
            t.title.isEmpty ? nil
                : Track(time: SeekBar.clock(t.offsetSeconds), title: t.title, artist: t.artist,
                        hue: hue, offsetSeconds: t.offsetSeconds)
        }
    }

    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
}
