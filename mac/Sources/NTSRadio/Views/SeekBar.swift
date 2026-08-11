import SwiftUI

/// Where you are inside a finite recording, and a way to move.
///
/// It exists only for a past episode. NTS 1 and the Infinite Mixtapes are
/// endless — there is no position inside them and no end to be a fraction of —
/// so this is absent for those rather than disabled or stuck at zero. Its
/// appearing is how the bar says which kind of thing is playing.
struct SeekBar: View {
    @EnvironmentObject var model: AppModel

    /// Where the thumb is being dragged to, as a fraction of the whole. Non-nil
    /// only mid-drag: while it is set the bar follows the finger rather than the
    /// audio, so the playhead doesn't fight the hand.
    @State private var scrubbing: Double?

    private var duration: Double { model.engine.duration }
    private var position: Double { model.engine.position }
    private var fraction: Double {
        if let scrubbing { return scrubbing }
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }

    var body: some View {
        HStack(spacing: 9) {
            time(fraction * duration)
            track
            time(duration)
        }
    }

    private func time(_ seconds: Double) -> some View {
        Text(Self.clock(seconds))
            .font(Theme.mono(9, .medium))
            .foregroundStyle(Theme.inkMuted)
            // Fixed width so the digits changing doesn't shove the track sideways
            // once past an hour, or when the minutes tick over.
            .frame(width: 42, alignment: .center)
            .monospacedDigit()
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline(0.12))
                Capsule().fill(model.accent).frame(width: width * fraction)
                Circle()
                    .fill(Theme.ink)
                    .frame(width: 9, height: 9)
                    .offset(x: (width * fraction) - 4.5)
            }
            .frame(height: 3)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        scrubbing = min(1, max(0, value.location.x / width))
                    }
                    .onEnded { value in
                        guard width > 0, duration > 0 else { scrubbing = nil; return }
                        let target = min(1, max(0, value.location.x / width))
                        model.engine.seek(to: target * duration)
                        scrubbing = nil
                    }
            )
        }
        .frame(height: 14)
    }

    /// `7:34`, or `1:07:34` once there is an hour to show. Archive shows run to
    /// two and three hours, so a fixed `mm:ss` would be wrong for a lot of them.
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
