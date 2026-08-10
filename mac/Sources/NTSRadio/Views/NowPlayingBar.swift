import SwiftUI
import AppKit

struct NowPlayingBar: View {
    @EnvironmentObject var model: AppModel

    /// The window's width. The bar's right-hand cluster costs a fixed ~160pt, so
    /// in a narrow window it eats the title down to "LO…" — below this width the
    /// level meter and the equaliser go and the title gets their room. Mute stays:
    /// it is the control, the meter only shows what it did.
    let width: CGFloat
    private var compact: Bool { width < 460 }

    var body: some View {
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
                EqBars(playing: model.isPlaying && !model.muted, accent: model.accent)

                Rectangle().fill(Theme.hairline(0.12)).frame(width: 1, height: 22)
            }

            Button { model.showTracks.toggle() } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.showTracks ? Theme.popover : Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(model.showTracks ? Theme.ink : Theme.hairline(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(model.isIdle)
            .opacity(model.isIdle ? 0.4 : 1)

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
        .background(Theme.nowBar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline(0.08)).frame(height: 1) }
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

private struct EqBars: View {
    let playing: Bool
    let accent: Color
    @State private var up = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(i == 0 || i == 3 ? accent : Theme.ink)
                    .frame(width: 3, height: 22)
                    .scaleEffect(y: playing ? (up ? heights1[i] : heights2[i]) : 0.3, anchor: .bottom)
            }
        }
        .frame(height: 22)
        .onAppear { if playing { up = true } }
        .animation(playing ? .easeInOut(duration: 0.42).repeatForever(autoreverses: true) : .default, value: up)
        .onChange(of: playing) { _, now in up = now }
    }

    private let heights1: [CGFloat] = [1.0, 0.45, 0.85, 0.3, 0.7]
    private let heights2: [CGFloat] = [0.3, 0.9, 0.4, 0.85, 0.35]
}

private struct VolumeMeter: View {
    @Binding var volume: Double
    let muted: Bool
    private let n = 13

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<n, id: \.self) { i in
                    let on = !muted && volume >= (Double(i + 1) / Double(n)) * 100 - 0.01
                    Rectangle()
                        .fill(on ? Theme.ink : Theme.hairline(0.2))
                        .frame(width: 3, height: 6 + CGFloat(i) * 1.4)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let p = max(0, min(1, v.location.x / geo.size.width))
                        volume = (p * 100).rounded()
                    }
            )
        }
        .frame(width: CGFloat(n) * 5.5 - 2.5, height: 22)
    }
}
