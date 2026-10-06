/// When to reload a live stream that has gone quiet, and when a run of reloads
/// has worked. It holds no player and no clock: `PlayerEngine` reports what
/// AVPlayer is doing and what fired, and carries out the `Step` it gets back —
/// so the whole schedule can be driven by a test with no audio and no waiting.
///
/// A *streak* is the reloads made since audio last came out and stayed out.
/// A reload that renders does not end it straight away: a stream that plays
/// for a second and drops again would otherwise start every streak at attempt
/// 1, retrying at the same pace forever. It ends once audio has held for
/// `settle`, or when the listener stops asking for audio.
public struct StallWatch: Sendable {
    /// How long a stream that should be playing may stay silent before it is
    /// reloaded with no other event to say it died — a Wi-Fi blip that never
    /// changed the network path, or a server that stopped sending.
    public static let grace: Duration = .seconds(15)

    /// How long a reload has to keep rendering before the streak counts as
    /// recovered.
    public static let settle: Duration = .seconds(60)

    /// How long a reload gets to start rendering before the next one: 5, 10,
    /// 20, then 30 seconds for as long as it takes. The first wait is long
    /// enough for a slow network to fill the buffer, so a reload is never cut
    /// off by the one after it.
    public static func backoff(after attempt: Int) -> Duration {
        .seconds(min(5 * (1 << min(attempt - 1, 3)), 30))
    }

    /// The silence allowed before reloading. A drop partway through a streak
    /// waits the grace plus that attempt's backoff — 20, 25, 35, then 45
    /// seconds — so a stream that keeps dying is reloaded less and less often.
    public static func silence(after attempt: Int) -> Duration {
        attempt == 0 ? grace : grace + backoff(after: attempt)
    }

    public enum Timer: Sendable, Equatable {
        /// Silence is being given time to mend itself.
        case grace
        /// A reload is being given time to start rendering.
        case retry
        /// A reload that rendered is being given time to prove it holds.
        case settle
    }

    /// What the player is doing, as the engine last saw it.
    public struct Player: Sendable, Equatable {
        /// The listener asked for audio.
        public var playing: Bool
        /// Audio is coming out.
        public var rendering: Bool
        /// A channel or mixtape is loaded — the only kind a reload loses
        /// nothing on.
        public var reloadable: Bool

        public init(playing: Bool, rendering: Bool, reloadable: Bool) {
            self.playing = playing
            self.rendering = rendering
            self.reloadable = reloadable
        }
    }

    public enum Step: Sendable, Equatable {
        /// Leave the pending timer as it is.
        case none
        /// Start this timer, replacing any pending one.
        case arm(Timer, Duration)
        /// Cancel the pending timer.
        case disarm
        /// Reload the stream at the live head, then arm `.retry` for `check`.
        case reload(attempt: Int, check: Duration)
        /// A trigger found nothing to reload.
        case skip
        /// The streak ended with audio holding; cancel the pending timer.
        case recovered(after: Int)
        /// The listener stopped asking for audio mid-streak; cancel the
        /// pending timer.
        case dropped(after: Int)
    }

    /// Reloads in the current streak; 0 when none is under way.
    public private(set) var attempts = 0
    /// Streaks that ended with audio holding, since launch.
    public private(set) var recoveries = 0
    /// The timer the engine should have running — never more than one.
    public private(set) var pending: Timer?

    public init() {}

    /// The player started or stopped playing or rendering.
    public mutating func changed(_ player: Player) -> Step {
        // `rendering` can lag a pause by a moment; audio the listener has
        // stopped asking for is never a recovery.
        if player.rendering, player.playing {
            guard attempts > 0 else {
                pending = nil
                return .disarm
            }
            guard pending != .settle else { return .none }
            pending = .settle
            return .arm(.settle, Self.settle)
        }
        guard player.playing, player.reloadable else {
            pending = nil
            guard attempts > 0 else { return .disarm }
            let streak = attempts
            attempts = 0
            return .dropped(after: streak)
        }
        // A grace or retry already counting down is the one that applies; a
        // settle is moot now the audio has stopped.
        if pending == .grace || pending == .retry { return .none }
        pending = .grace
        return .arm(.grace, Self.silence(after: attempts))
    }

    /// A wake, a returning network, or an expired grace or retry: reload
    /// unless audio is coming out.
    public mutating func stalled(_ player: Player) -> Step {
        guard !player.rendering else { return .skip }
        return reload(player)
    }

    /// The item failed or an endless stream ended. A failure while a streak
    /// is under way is that streak's own reload failing — offline, say — and
    /// reloading again at once would turn the backoff into a tight loop, so
    /// the stall timer the failure's silence arms decides instead.
    public mutating func failed(_ player: Player) -> Step {
        guard attempts == 0 else { return .none }
        // A failed item cannot be rendering, whatever the engine last saw:
        // that comes from a separate observation that may not have landed.
        return reload(player)
    }

    /// The pending timer went off.
    public mutating func fired(_ timer: Timer, _ player: Player) -> Step {
        pending = nil
        switch timer {
        case .grace, .retry:
            return stalled(player)
        case .settle:
            guard player.rendering, player.playing, attempts > 0 else { return changed(player) }
            recoveries += 1
            let streak = attempts
            attempts = 0
            return .recovered(after: streak)
        }
    }

    /// The listener chose something: whatever was being recovered is gone.
    public mutating func reset() {
        attempts = 0
        pending = nil
    }

    private mutating func reload(_ player: Player) -> Step {
        guard player.playing, player.reloadable else { return .skip }
        attempts += 1
        pending = .retry
        return .reload(attempt: attempts, check: Self.backoff(after: attempts))
    }
}
