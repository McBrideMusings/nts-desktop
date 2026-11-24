import Foundation

/// When a pushed tracklist may be shown: a newly started track is held back
/// until the audio it names has reached the speakers. It holds no player, no
/// listener and no clock — the caller says what is on screen, what was pushed,
/// how far behind the live edge the player is and what time it is, then shows
/// or waits as told — so the rule is tested with no Firestore and no AVPlayer.
///
/// AVPlayer is behind the live edge by whatever it has buffered — measured at
/// ~5s on the channel streams and ~29s on the mixtape HLS — so a track reaches
/// the speakers that long after NTS's `start_time`, and the deadline is
/// `start_time` plus the buffer. The push itself lands ~11s after `start_time`,
/// so on a channel the deadline has usually passed already and the track shows
/// at once; a mixtape still holds for the remainder.
public struct TrackHold<Payload> {
    /// The longest a push is held, counted from its arrival: the buffer has
    /// never measured anywhere near it, and neither a wild buffer reading nor a
    /// `start_time` skewed against this Mac's clock should freeze the list.
    public static var ceiling: TimeInterval { 60 }

    /// A push waiting to be shown, and the moment it may be.
    public struct Held {
        public let payload: Payload
        public let key: String?
        public let deadline: Date
    }

    public enum Step: Equatable {
        case show
        case hold(until: Date)
    }

    public private(set) var held: Held?

    public init() {}

    /// Take a push. `key` and `startedAt` describe its top row (nil for an
    /// empty push); `shownKey` is the top row on screen, nil when the list is
    /// empty. On `.show` the caller shows `payload` now and nothing is held.
    public mutating func receive(_ payload: Payload, key: String?, startedAt: Date?,
                                 shownKey: String?, playing: Bool,
                                 buffered: TimeInterval, now: Date) -> Step {
        // Nothing to stay behind: the backfill on opening or switching source (an
        // empty list held back half a minute is worse than one that starts
        // correct), a push that only revises rows further down, or a paused
        // player with no audio in flight.
        guard shownKey != nil, key != shownKey, playing else {
            held = nil
            return .show
        }
        if let held, held.key == key {
            // Same track, pushed again with revised details — take the new
            // contents but keep the original deadline, so a run of revisions
            // can't keep pushing the reveal further out.
            self.held = Held(payload: payload, key: key, deadline: held.deadline)
            return .hold(until: held.deadline)
        }
        let deadline = min((startedAt ?? now).addingTimeInterval(buffered),
                           now.addingTimeInterval(Self.ceiling))
        guard deadline > now else {
            held = nil
            return .show
        }
        held = Held(payload: payload, key: key, deadline: deadline)
        return .hold(until: deadline)
    }

    /// Drop whatever is held — something else was shown in its place.
    public mutating func clear() { held = nil }
}
