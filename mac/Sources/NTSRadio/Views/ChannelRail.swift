import SwiftUI

struct ChannelRail: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        // A GeometryReader here measures the rail's actual slot height and, as a
        // side effect, stops the cards' intrinsic size from forcing a tall window
        // minimum — the rail now fills whatever height it's given instead.
        GeometryReader { proxy in
            let cardH = (proxy.size.height - 1) / 2   // minus the 1pt divider
            VStack(spacing: 0) {
                ForEach(Array(model.catalog.channels.enumerated()), id: \.element.id) { idx, c in
                    ChannelCard(channel: c,
                                active: model.selection == .channel(c.number),
                                slot: cardH)
                        .onTapGesture { model.select(.channel(c.number)) }
                    if idx == 0 {
                        Rectangle().fill(Theme.hairline(0.1)).frame(height: 1)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(width: 180)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.hairline(0.08)).frame(width: 1)
        }
    }
}

private struct ChannelCard: View {
    let channel: Channel
    let active: Bool
    let slot: CGFloat

    /// Below this slot height the card sheds its live chip + show title and shows
    /// just the numbered disc + city. That's what lets the whole window get short:
    /// the full card's fixed disc + `fixedSize` chip + wrapping title otherwise
    /// pin a tall minimum height that propagates up to the window.
    private static let compactThreshold: CGFloat = 168
    private var compact: Bool { slot < Self.compactThreshold }

    var body: some View {
        ZStack {
            cardArt
                .saturation(active ? 1 : 0.08)
                .brightness(active ? 0 : -0.28)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.34), location: 0),
                    .init(color: .black.opacity(0.14), location: 0.44),
                    .init(color: .black.opacity(0.86), location: 1),
                ], startPoint: .top, endPoint: .bottom)

            if compact { compactContent } else { fullContent }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.stage)
        .clipped()
        .contentShape(Rectangle())
    }

    // MARK: Full card (tall)

    private var fullContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            liveChip
            Spacer(minLength: 8)
            HStack { Spacer(); channelDisc(diameter: 86, showNumber: false); Spacer() }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 6) {
                ChipText(text: channel.city, font: Theme.mono(10).weight(.medium))
                ChipText(text: channel.show.uppercased(), font: Theme.display(17, .black))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Compact card (short)

    /// Just the numbered disc + city, both centered. The disc scales with the
    /// slot height so two cards always fit no matter how short the window gets.
    private var compactContent: some View {
        let d = max(34, min(86, slot * 0.46))
        return VStack(spacing: max(6, d * 0.14)) {
            channelDisc(diameter: d, showNumber: true)
            ChipText(text: channel.city, font: Theme.mono(10).weight(.medium))
                .opacity(active ? 1 : 0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    /// The channel's accent disc, used at full size (86, no number) in the tall
    /// card and scaled with the slot (number centered) in the compact card. One
    /// renderer so the active stroke/shadow treatment stays in sync across both.
    /// Strokes and shadow scale by `s` so at `diameter: 86` they match the
    /// original fixed-size disc exactly.
    private func channelDisc(diameter d: CGFloat, showNumber: Bool) -> some View {
        let s = d / 86
        return ZStack {
            Circle()
                .fill(channel.accent)
                .opacity(active ? 1 : 0.92)
                .overlay {
                    if active {
                        Circle().stroke(.black.opacity(0.4), lineWidth: 4 * s)
                            .padding(-2 * s)
                            .overlay(Circle().stroke(channel.accent, lineWidth: 2 * s).padding(-4 * s))
                    }
                }
                .shadow(color: .black.opacity(active ? 0.5 : 0.45),
                        radius: (active ? 13 : 8) * s, y: (active ? 5 : 6) * s)
            if showNumber {
                Text("\(channel.number)")
                    .font(Theme.display(d * 0.5, .black))
                    .foregroundStyle(channel.accentText)
            }
        }
        .frame(width: d, height: d)
    }

    /// The current program's full-bleed artwork (downloaded live, disk-cached) —
    /// shown only while this channel is active (playing/selected). Otherwise, and
    /// until the image loads, falls back to the procedural gradient.
    @ViewBuilder private var cardArt: some View {
        if active, let bg = channel.background {
            // Color.clear takes the card's slot size; the fill image rides in an
            // overlay so scaledToFill can't inflate the card's layout past the
            // rail, then we clip the overflow.
            Color.clear
                .overlay {
                    AsyncImage(url: bg) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        channel.art
                    }
                }
                .clipped()
        } else {
            channel.art
        }
    }

    private var liveChip: some View {
        HStack(spacing: 0) {
            Text("\(channel.number)")
                .font(Theme.display(15, .black))
                .foregroundStyle(channel.accentText)
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
                .background(channel.accent)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("LIVE NOW")
                        .font(Theme.mono(9, .bold))
                        .tracking(1.3)
                    Circle().fill(Theme.liveDot).frame(width: 5, height: 5)
                }
                Text(channel.startEnd.isEmpty ? "—" : channel.startEnd)
                    .font(Theme.display(14, .heavy))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(EdgeInsets(top: 4, leading: 11, bottom: 5, trailing: 11))
        }
        .fixedSize()
        .background(Theme.chipBlack)
    }
}
