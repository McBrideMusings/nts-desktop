import SwiftUI

struct ChannelRail: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.catalog.channels.enumerated()), id: \.element.id) { idx, c in
                ChannelCard(channel: c, active: model.selection == .channel(c.number))
                    .onTapGesture { model.select(.channel(c.number)) }
                if idx == 0 {
                    Rectangle().fill(Theme.hairline(0.1)).frame(height: 1)
                }
            }
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

            VStack(alignment: .leading, spacing: 0) {
                liveChip
                Spacer(minLength: 8)
                HStack { Spacer(); disc; Spacer() }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.stage)
        .clipped()
        .contentShape(Rectangle())
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

    private var disc: some View {
        Circle()
            .fill(channel.accent)
            .frame(width: 86, height: 86)
            .opacity(active ? 1 : 0.92)
            .overlay {
                if active {
                    Circle().stroke(.black.opacity(0.4), lineWidth: 4)
                        .padding(-2)
                        .overlay(Circle().stroke(channel.accent, lineWidth: 2).padding(-4))
                }
            }
            .shadow(color: .black.opacity(active ? 0.5 : 0.45), radius: active ? 13 : 8, y: active ? 5 : 6)
    }
}
