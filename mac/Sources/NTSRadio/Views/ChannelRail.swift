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
        .frame(width: 268)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.hairline(0.08)).frame(width: 1)
        }
    }
}

/// One channel, with the programme's own photograph as the card.
///
/// The photo is the point: both channels show theirs, and the inactive one is
/// only dimmed rather than drained, so you can see what's on the channel you
/// aren't listening to. The accent disc that used to dominate this card is gone —
/// on the Atonemo that circle is a button you press, and a flat one on screen was
/// spending the card's focal point on a channel number already printed above it.
private struct ChannelCard: View {
    let channel: Channel
    let active: Bool
    let slot: CGFloat

    /// Below this slot height the card drops the genre chips and shrinks the
    /// title, so two cards still fit when the window is short.
    private static let compactThreshold: CGFloat = 170
    private var compact: Bool { slot < Self.compactThreshold }

    private var location: String {
        let live = channel.upcoming.first?.location ?? ""
        return live.isEmpty ? channel.city : live
    }
    private var genres: [String] {
        Array((channel.upcoming.first?.genres ?? [channel.genre]).filter { !$0.isEmpty }.prefix(3))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cardArt
            // Only the base is scrimmed: a full-card wash would take the photo
            // back out again, which is the thing this card exists to show.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.78), location: 0.62),
                    .init(color: .black.opacity(0.94), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: compact ? 92 : 132)
                .frame(maxHeight: .infinity, alignment: .bottom)

            meta
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.stage)
        .overlay(alignment: .topLeading) { numeral }
        .overlay(alignment: .topTrailing) { led }
        .overlay { if active { Rectangle().strokeBorder(channel.accent, lineWidth: 2) } }
        .clipped()
        .contentShape(Rectangle())
    }

    // MARK: Pieces

    /// The boxed channel number, printed like the `1` and `2` silkscreened on the
    /// Atonemo's faceplate. Lights up in the channel's accent when it's the one
    /// playing — the panel LED, not a control.
    private var numeral: some View {
        Text("\(channel.number)")
            .font(Theme.display(13, .black))
            .foregroundStyle(active ? channel.accentText : Theme.popover)
            .frame(width: 22, height: 22)
            .background(active ? channel.accent : Theme.ink.opacity(0.55))
            .padding(12)
    }

    private var led: some View {
        Circle()
            .fill(active ? Theme.liveDot : Theme.liveDot.opacity(0.35))
            .frame(width: 7, height: 7)
            .shadow(color: Theme.liveDot.opacity(active ? 0.9 : 0), radius: 5)
            .padding(EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 14))
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(location)
                if !(channel.upcoming.first?.startEnd ?? channel.startEnd).isEmpty {
                    Text("·").opacity(0.5)
                    Text(channel.upcoming.first?.startEnd ?? channel.startEnd).monospacedDigit()
                }
                Text("·").opacity(0.5)
                Text(active ? "◉ PLAYING" : "LIVE")
                    .foregroundStyle(active ? channel.accent : Color(hex: 0xcfcec8))
            }
            .font(Theme.mono(9, .bold))
            .tracking(1.6)
            .foregroundStyle(Color(hex: 0xcfcec8))
            .lineLimit(1)

            Text(channel.show.uppercased())
                .font(Theme.display(compact ? 14 : 16, .black))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !compact && !genres.isEmpty {
                HStack(spacing: 5) {
                    ForEach(genres, id: \.self) { g in
                        Text(g.uppercased())
                            .font(Theme.mono(8, .semibold))
                            .tracking(1)
                            .foregroundStyle(Theme.popover)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(Theme.ink.opacity(0.85))
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 0, leading: 14, bottom: 13, trailing: 14))
    }

    /// The current programme's artwork, shown for both channels. The inactive one
    /// is dimmed and partly desaturated — enough to read as "not this one" while
    /// staying a legible photograph.
    @ViewBuilder private var cardArt: some View {
        Group {
            if let bg = channel.background {
                Color.clear.overlay {
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
        .saturation(active ? 1 : 0.45)
        .brightness(active ? 0 : -0.22)
        .overlay(Color.black.opacity(active ? 0 : 0.28))
        .animation(.easeOut(duration: 0.2), value: active)
    }
}
