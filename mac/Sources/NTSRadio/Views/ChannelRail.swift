import SwiftUI
import AppKit

struct ChannelRail: View {
    @EnvironmentObject var model: AppModel

    /// Which side the rail's dividing hairline sits on — the edge facing the dial.
    let edge: Edge

    var body: some View {
        // A GeometryReader here measures the rail's actual slot size and, as a
        // side effect, stops the cards' intrinsic size from forcing a tall window
        // minimum — the rail now fills whatever space it's given instead.
        GeometryReader { proxy in
            // The rail arranges its own two cards from the box it was handed:
            // split the long side, so each card comes out as square as the box
            // allows. A tall rail down one edge stacks them; a wide one across
            // the top — or a short one beside the dial — puts them side by side.
            // This used to be told to the rail by `PopoverView`, keyed to the
            // window being under 430pt tall, which is a number about the window
            // and not about the cards.
            let stacked = proxy.size.height > proxy.size.width
            // `GeometryReader` reports `.zero` on the first layout pass and again
            // while siblings are still measuring, and subtracting the divider's
            // 1pt from 0 gives −0.5 — a negative slot handed to a card, which
            // every proportion downstream then inherits. `half` never goes below
            // zero, so a not-yet-measured rail is empty rather than inverted.
            let slotH = stacked ? Self.half(proxy.size.height) : proxy.size.height
            let slotW = stacked ? proxy.size.width : Self.half(proxy.size.width)
            let cards = Array(model.catalog.channels.enumerated())
            Group {
                if stacked {
                    VStack(spacing: 0) {
                        ForEach(cards, id: \.element.id) { idx, c in
                            card(c, w: slotW, h: slotH)
                            if idx == 0 { Rectangle().fill(Theme.hairline(0.1)).frame(height: 1) }
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        ForEach(cards, id: \.element.id) { idx, c in
                            card(c, w: slotW, h: slotH)
                            if idx == 0 { Rectangle().fill(Theme.hairline(0.1)).frame(width: 1) }
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .overlay(alignment: edge == .bottom ? .bottom : .trailing) {
            if edge == .bottom {
                Rectangle().fill(Theme.hairline(0.08)).frame(height: 1)
            } else {
                Rectangle().fill(Theme.hairline(0.08)).frame(width: 1)
            }
        }
    }

    /// One of the two card slots along an axis, once the 1pt divider between
    /// them comes out. Clamped at zero — see the note at the call site.
    static func half(_ total: CGFloat) -> CGFloat { max(0, (total - 1) / 2) }

    /// Cards fill their slot, always. Square is what the rail *asks* for —
    /// `PopoverView` sizes it so each slot comes out square whenever the window
    /// allows — but when the window's proportions won't permit it the card
    /// stretches rather than sitting centred with bare rail showing either side.
    /// A gap between the two channels is worse than a card that isn't quite
    /// square.
    private func card(_ c: Channel, w: CGFloat, h: CGFloat) -> some View {
        ChannelCard(channel: c,
                    active: model.selection == .channel(c.number),
                    slotW: w, slotH: h)
            .onTapGesture { model.select(.channel(c.number)) }
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
    let slotW: CGFloat
    let slotH: CGFloat
    /// Hovering a card previews it the way hovering a dial wedge does: the photo
    /// comes back up to full strength and the accent outline appears, so the card
    /// answers the pointer before it's clicked. Committing is still the click.
    @State private var hovering = false

    /// Below this slot height the card drops the genre chips and shrinks the
    /// title, so two cards still fit when the window is short.
    private static let compactThreshold: CGFloat = 170
    private var compact: Bool { slotH < Self.compactThreshold || narrow }
    /// Side by side, two cards split the rail's width, and the metadata line is
    /// the first thing that stops fitting: "LONDON · 17:00 — 19:00 · ◉ PLAYING"
    /// truncates to "LO… · 17:0… · ◉…", which says nothing. Under this width the
    /// line drops to the times alone — the LED and the accent border already
    /// carry live and playing.
    private var narrow: Bool { slotW < 200 }
    /// Narrower still — two cards inside a 340pt window get about 76pt each,
    /// where even the time truncates. The card keeps the photograph, the numeral
    /// and the LED, which is what identifies it; the words go.
    private var tiny: Bool { slotW < 130 }

    private var location: String { channel.location.uppercased() }
    private var genres: [String] { Array(channel.genres.prefix(3)) }

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
                .opacity(tiny ? 0 : 1)

            if !tiny { meta }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.stage)
        .overlay(alignment: .topLeading) { numeral }
        .overlay(alignment: .topTrailing) { led }
        .overlay {
            if active {
                Rectangle().strokeBorder(channel.accent, lineWidth: 2)
            } else if hovering {
                Rectangle().strokeBorder(channel.accent.opacity(0.8), lineWidth: 1)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
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
                if narrow {
                    Text(channel.startEnd).monospacedDigit()
                        .foregroundStyle(active ? channel.accent : Color(hex: 0xcfcec8))
                } else {
                    Text(location)
                    if !channel.startEnd.isEmpty {
                        Text("·").opacity(0.5)
                        Text(channel.startEnd).monospacedDigit()
                    }
                    Text("·").opacity(0.5)
                    Text(active ? "◉ PLAYING" : "LIVE")
                        .foregroundStyle(active ? channel.accent : Color(hex: 0xcfcec8))
                }
            }
            .font(Theme.mono(9, .bold))
            .tracking(1.6)
            .foregroundStyle(Color(hex: 0xcfcec8))
            .lineLimit(1)

            Text(channel.show.uppercased())
                .font(Theme.display(narrow ? 13 : (compact ? 14 : 16), .black))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !compact && !genres.isEmpty && chipsFit {
                HStack(spacing: 5) {
                    ForEach(genres, id: \.self) { g in chip(g) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 14, bottom: 13, trailing: 14))
    }

    // MARK: Genre chips

    private static let chipFont = Theme.mono(8, .semibold)
    /// How far the chip text may shrink before the row is not worth showing.
    private static let chipMinScale: CGFloat = 0.62

    /// Chips are one line, always — the row is a single band of boxes the same
    /// height, and a long genre shrinks its own text to stay on that line rather
    /// than wrapping and making its box twice as tall as its neighbours.
    private func chip(_ g: String) -> some View {
        Text(g.uppercased())
            .font(Self.chipFont)
            .tracking(1)
            .lineLimit(1)
            .minimumScaleFactor(Self.chipMinScale)
            .foregroundStyle(Theme.popover)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(Theme.ink.opacity(0.85))
    }

    /// Roughly how wide the chips want to be at full size. The mono face is
    /// fixed-pitch, so a character is worth about 0.62 of the point size, plus
    /// the 1pt of tracking after it; each chip adds its 10pt of side padding and
    /// each gap 5pt.
    private var chipsNaturalWidth: CGFloat {
        let perChar = 8 * 0.62 + 1
        let text = genres.reduce(CGFloat(0)) { $0 + CGFloat($1.count) * perChar + 10 }
        return text + CGFloat(max(0, genres.count - 1)) * 5
    }

    /// Show the chips only while they'd still be legible: the row has to fit the
    /// card at no less than `chipMinScale`. Past that the whole row goes, never
    /// part of it — one card with chips beside one without looks like a bug.
    private var chipsFit: Bool {
        chipsNaturalWidth * Self.chipMinScale <= slotW - 28
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
        .saturation(active || hovering ? 1 : 0.45)
        .brightness(active ? 0 : (hovering ? -0.06 : -0.22))
        .overlay(Color.black.opacity(active ? 0 : (hovering ? 0.08 : 0.28)))
        .animation(.easeOut(duration: 0.2), value: active)
        .animation(.easeOut(duration: 0.16), value: hovering)
    }
}
