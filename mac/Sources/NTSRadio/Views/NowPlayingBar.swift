import SwiftUI
import AppKit

struct NowPlayingBar: View {
    @EnvironmentObject var model: AppModel

    /// The window's width. The bar's right-hand cluster costs a fixed ~145pt, so
    /// in a narrow window it eats the title down to "LO…" — below this width the
    /// volume meter and the level panel go and the title gets their room. Mute
    /// stays: it is the control, the meter only shows what it did.
    ///
    /// 495, not the 445 this was before the pane switch moved down here: the
    /// two-segment control is a fixed 76pt on top of the tracklist button that
    /// was already here, so the title runs out of room 50pt sooner. Neither the
    /// switch nor the tracklist button ever drops out — they are the only ways
    /// between the panes.
    let width: CGFloat
    private var compact: Bool { width < 495 }

    var body: some View {
        VStack(spacing: 0) {
            // Only a finite recording has a position to show. The engine decides
            // that from the item's own duration, so nothing here has to know what
            // kind of source is tuned.
            if model.engine.isSeekable {
                SeekBar()
                    .padding(.horizontal, 16)
                    .padding(.top, 9)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            controls
        }
        .background(Theme.nowBar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline(0.08)).frame(height: 1) }
        .animation(.easeOut(duration: 0.2), value: model.engine.isSeekable)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.popover)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.ink))
            }
            .buttonStyle(.plain)
            .disabled(model.isIdle)
            .opacity(model.isIdle ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 2) {
                // Idle (nothing selected) → placeholder; otherwise the live show
                // title (links to its episode page) or the mixtape name.
                LinkLabel(
                    text: model.isIdle ? "NOTHING PLAYING" : model.displayName,
                    url: model.nowPlayingShowURL,
                    font: Theme.display(14, .heavy),
                    color: model.isIdle ? Theme.inkMuted : Theme.ink
                )
                // Mixtape source episode — when it's a link, NTS shows it bold white
                // (vs the muted, regular non-link descriptor).
                LinkLabel(
                    text: model.isIdle ? "PICK A MIXTAPE OR CHANNEL" : model.subtitle,
                    url: model.nowPlayingEpisodeURL,
                    font: Theme.mono(10, .regular),
                    linkFont: Theme.mono(10, .bold),
                    color: Theme.inkMuted,
                    linkColor: Theme.ink,
                    tracking: 0.5
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !compact {
                // `isRendering`, not `isPlaying`: the first is whether audio is
                // coming out, the second is only whether play was pressed. A
                // stalled stream leaves the button showing pause while the
                // speakers are silent, and a meter that keeps moving through
                // that is telling the user something untrue.
                LevelLamps(running: model.engine.isRendering && !model.muted,
                           accent: model.accent)

                Rectangle().fill(Theme.hairline(0.12)).frame(width: 1, height: 22)
            }

            // The drawer's control sits outside the two-segment switch because it
            // does something different: the switch says where you are, this lays
            // the tracklist over it and takes it away again. Being a loose button
            // next to a joined pair is the whole distinction — no divider is
            // needed to make it, and one only added a line to look at.
            TracksButton()

            PaneSwitch()

            Button { model.muted.toggle() } label: {
                Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)

            if !compact {
                VolumeMeter(volume: $model.volume, muted: model.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Where the window is: LIVE or EXPLORE, as one two-segment control beside the
/// transport.
///
/// **A segmented control rather than a lit button each, and that is the point.**
/// The catalog and the tracklist used to be a toggle each, in two different
/// places — one down here, one in the title bar — over two independent booleans.
/// Opening the catalog on top of an open tracklist left both buttons lit while
/// only the catalog was visible, because nothing in the arrangement could say
/// "one at a time". Here each segment writes `AppModel.pane`, a single value, and
/// reads its lit state back out of it: two segments cannot both be lit because
/// the model cannot hold two panes.
///
/// A signal going out, and the wall of tiles you dig through: broadcast waves for
/// live, the four-square grid for the archive. The grid is literally what the
/// catalog pane is, so it names where the segment lands rather than the activity.
/// Both keep a tooltip — no icon says which of two panes it is until it has been
/// clicked once.
private struct PaneSwitch: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            segment(.live, "dot.radiowaves.left.and.right", "What is on air now")
            segment(.catalog, "square.grid.2x2.fill", "The archive — schedule, saved and search")
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.hairline(0.08)))
    }

    private func segment(_ p: Pane, _ symbol: String, _ help: String) -> some View {
        let on = model.pane == p
        return Button { model.show(p) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(on ? Theme.popover : Theme.ink)
                .frame(width: 34, height: 28)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(on ? Theme.ink : .clear))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Raises and drops the tracklist drawer. Lit while the drawer is up, and dead
/// while nothing is playing — silence has no tracklist.
private struct TracksButton: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Button { model.toggleTracks() } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.tracksOpen ? Theme.popover : Theme.ink)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(model.tracksOpen ? Theme.ink : Theme.hairline(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(model.isIdle)
        .opacity(model.isIdle ? 0.4 : 1)
        .help(model.tracksOpen ? "Hide the tracklist" : "Tracklist for what is playing")
    }
}

/// A now-playing label that becomes a link when `url` is non-nil: it switches to
/// `linkFont`/`linkColor` (NTS shows clickable labels bold white), shows an
/// underline + pointer cursor on hover, and opens the page in the browser on tap.
/// Plain text otherwise.
private struct LinkLabel: View {
    let text: String
    let url: URL?
    let font: Font
    var linkFont: Font? = nil
    let color: Color
    var linkColor: Color? = nil
    var tracking: CGFloat = 0
    @State private var hovering = false

    var body: some View {
        let isLink = url != nil
        Text(text)
            .font(isLink ? (linkFont ?? font) : font)
            .tracking(tracking)
            .underline(isLink && hovering)
            .foregroundStyle(isLink ? (linkColor ?? color) : color)
            .lineLimit(1)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                guard isLink else { return }
                if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
            .onTapGesture { if let url { NSWorkspace.shared.open(url) } }
            .help(url?.absoluteString ?? "")
    }
}

/// A dot-matrix level panel — five columns of seven lamps, filling from the
/// bottom, with a peak lamp held above each column that steps down as the loud
/// moment holding it up ages out. The quantising to whole lamps is what makes it
/// read as a piece of hardware on the front of a rack rather than as an
/// animation.
///
/// Resting — nothing tuned, paused, muted, or buffering — is the bottom row lit
/// and nothing else: the panel is powered, the signal is zero.
///
/// **The levels are invented, not measured, and that is a decision.** Measuring
/// them is possible but not free: `MTAudioProcessingTap` cannot do it, because
/// NTS's live and mixtape endpoints hand AVPlayer an asset carrying no audio
/// track for an `audioMix` to attach to. The route that does work is a CoreAudio
/// process tap over the app's own output, and that is audio capture — a macOS
/// permission prompt on first play, for a decoration. Not worth asking anyone
/// for. So the panel is honest about the one thing that matters (it only moves
/// while audio is actually being rendered) and makes up the rest.
private struct LevelLamps: View {
    /// Whether audio is coming out of the speakers this second.
    let running: Bool
    let accent: Color

    /// With Reduce Motion on, the panel holds one steady picture instead of
    /// animating. It cannot simply rest: resting means "no audio", and the whole
    /// point of the panel is that those two states differ. So it shows a calm
    /// half-lit row — signal present, saying nothing about its moment-to-moment
    /// level, which is invented anyway.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let bands = 5, rows = 7
    private let lamp: CGFloat = 2.2, gap: CGFloat = 1.0

    /// Whether the picture is allowed to change from frame to frame.
    private var animating: Bool { running && !reduceMotion }

    var body: some View {
        // Stopping the clock stops the work: a paused or reduced-motion panel
        // redraws once and then costs nothing. Every value below is a function
        // of the date alone — there is no animation left part-finished
        // anywhere, which is what the previous bars got wrong: they scaled
        // themselves under a `repeatForever` animation, and the half-second
        // position tick rebuilt the bar mid-flight, restarting the repeat from
        // wherever the picture had got to.
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animating)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            // One `Canvas` rather than 35 `Circle` views: at 24 frames a second
            // for as long as the window is open, the difference is 35 views
            // through layout every frame against one draw call.
            Canvas(opaque: false) { g, size in
                let grid = CGFloat(rows) * lamp + CGFloat(rows - 1) * gap
                let top = (size.height - grid) / 2
                for band in 0..<bands {
                    let lit = lamps(level(band, t))
                    let held = lamps(peak(band, t))
                    let x = CGFloat(band) * (lamp + gap)
                    for row in 0..<rows {
                        // Row 0 is the top lamp, so a column of height `lit`
                        // lights from the bottom up.
                        let dot = CGRect(x: x, y: top + CGFloat(row) * (lamp + gap),
                                         width: lamp, height: lamp)
                        g.fill(Path(ellipseIn: dot),
                               with: .color(colour(height: rows - row, lit: lit, held: held)))
                    }
                }
            }
            .frame(width: CGFloat(bands) * lamp + CGFloat(bands - 1) * gap, height: 22)
        }
    }

    // MARK: What the lamps show

    /// How often band `band` picks a new target. Low bands move slower, the way
    /// music actually meters; the top band is quick and sparse.
    private func rate(_ band: Int) -> Double { 5.0 + Double(band) * 2.5 }

    /// Where every column's quiet end sits at time `t` — a slow rise and fall
    /// shared by all five, the panel breathing with the music.
    ///
    /// It moves the column's *floor* and leaves the noise its own range on top.
    /// Scaling the whole value by it instead — `floor + span × noise × tilt ×
    /// swell` — collapsed the top band into 0.18…0.29 at the bottom of every
    /// swell, and since `lamps()` rounds up and 2/7 is 0.286, every one of those
    /// values drew the same two lamps: the right-hand column stood still for a
    /// full second out of every 2.3, during real playback. A motionless column
    /// is the one thing this panel is supposed to mean, so it must never happen
    /// while audio is coming out.
    private func floor(_ t: TimeInterval) -> Double {
        0.16 + 0.22 * (0.5 + 0.5 * sin(t * 2 * .pi / 2.3))
    }

    /// How much of the scale band `band`'s own movement covers. Bass swings
    /// widest; the top band is quick and sparse.
    private func swing(_ band: Int) -> Double { 0.55 * (1.0 - Double(band) * 0.11) }

    /// Band `band` at time `t`, 0…1.
    private func level(_ band: Int, _ t: TimeInterval) -> Double {
        let r = rate(band)
        let step = Int(t * r)
        let f = t * r - Double(step)
        let eased = f * f * (3 - 2 * f)                       // smooth between targets
        let a = noise(band, step), b = noise(band, step + 1)
        return min(1, floor(t) + swing(band) * (a + (b - a) * eased))
    }

    /// The loudest this band has been in the last little while — where the peak
    /// lamp sits. Remembered nowhere: it is the largest of the band's own recent
    /// targets, so it holds flat between them and steps down as a loud one ages
    /// out. It rides the same floor as the column beneath it, so it can never
    /// sink below its own column.
    ///
    /// A sliding window of evenly spaced samples of `level` looked right and was
    /// not, in two ways: the grid shifted 1/24s per frame and landed on
    /// different local maxima, so the held lamp rose thirteen times in two
    /// seconds; and each sample carried the floor of the past instant it was
    /// taken at, which on a rising swell put the "peak" underneath the column.
    private func peak(_ band: Int, _ t: TimeInterval, window: Double = 0.7) -> Double {
        let r = rate(band)
        let step = Int(t * r)
        let back = max(2, Int((window * r).rounded()))
        // step + 1 is the target the column is currently travelling towards, so
        // it belongs in the window — otherwise the lit column overtakes its own
        // peak lamp on the way up.
        let loudest = (-1...back).map { noise(band, step - $0) }.max() ?? 0
        return min(1, floor(t) + swing(band) * loudest)
    }

    /// Deterministic 0…1 noise. A seeded hash rather than `random()` so the
    /// panel draws the same thing for the same instant however often the bar is
    /// rebuilt — the bar is rebuilt twice a second by the position tick.
    private func noise(_ band: Int, _ step: Int) -> Double {
        var h = UInt64(bitPattern: Int64(band &* 374_761_393 &+ step &* 668_265_263))
        h ^= h >> 13; h = h &* 1_274_126_177; h ^= h >> 16
        return Double(h % 1000) / 1000
    }

    // MARK: Drawing

    /// How many lamps a 0…1 level lights. Always at least one while the app is
    /// open, so the panel never blinks out entirely.
    ///
    /// The two still states are decided here rather than in the drawing, so the
    /// lit column and the peak lamp can never disagree about them: nothing
    /// playing is one lamp, and Reduce Motion while playing is a steady four —
    /// far enough from one lamp to read as a different state at a glance.
    private func lamps(_ level: Double) -> Int {
        guard running else { return 1 }
        guard !reduceMotion else { return 4 }
        return max(1, min(rows, Int((level * Double(rows)).rounded(.up))))
    }

    private func colour(height: Int, lit: Int, held: Int) -> Color {
        if height <= lit {
            // The top two lamps of a column are the loud ones, in the accent.
            return height >= rows - 1 ? accent : Theme.ink
        }
        if height == held { return accent.opacity(0.75) }   // the peak lamp
        return Theme.hairline(0.10)                          // unlit, but present
    }
}

/// A plain horizontal slider for the volume — a real track and knob you can grab
/// anywhere along, rather than thirteen bars you have to aim between.
private struct VolumeMeter: View {
    @Binding var volume: Double
    let muted: Bool

    var body: some View {
        Slider(value: $volume, in: 0...100)
            .controlSize(.small)
            .tint(Theme.ink)
            .frame(width: 76)
            .opacity(muted ? 0.4 : 1)
    }
}
