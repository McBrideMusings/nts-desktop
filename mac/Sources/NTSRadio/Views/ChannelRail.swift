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
    @EnvironmentObject var model: AppModel
    let channel: Channel
    let active: Bool
    let slotW: CGFloat
    let slotH: CGFloat
    /// Hovering a card previews it the way hovering a dial wedge does: the photo
    /// comes back up to full strength and the accent outline appears, so the card
    /// answers the pointer before it's clicked. Committing is still the click.
    @State private var hovering = false
    /// Which genre chip the pointer is on — decides only how that chip draws.
    @State private var hoveredGenre: String?

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
        .overlay(alignment: .topTrailing) { stars }
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

    // MARK: Follow and save

    /// Star the show, star this episode — bare glyphs in the corner, to the left
    /// of the LED and on its centre line.
    ///
    /// **Hidden until the pointer is on the card, with one exception: a star that
    /// is already set stays lit.** Hiding those too would leave the card unable to
    /// say what you follow, which is the one thing a star is for; and a resting
    /// rail that shows a mark only on the programmes you kept is quieter than one
    /// showing four buttons all the time.
    ///
    /// No chip behind them, unlike the catalog grid's: that one sits on a tile
    /// with its own margin, this one sits on a photograph. The shadow is what
    /// keeps a white outline legible when the artwork behind it is a pale sky.
    ///
    /// The glyphs are deliberately different from each other — a star for the
    /// show, a bookmark for the one broadcast — because the two write different
    /// rows and undoing the wrong one is invisible until you next open Saved.
    @ViewBuilder private var stars: some View {
        let show = channel.savedShow
        let episode = channel.savedEpisode
        if show != nil || episode != nil {
            HStack(spacing: 2) {
                if let show { star(show, on: "star.fill", off: "star",
                                   help: model.saved.contains(show) ? "Unfollow this show" : "Follow this show") }
                if let episode { star(episode, on: "bookmark.fill", off: "bookmark",
                                      help: model.saved.contains(episode) ? "Remove this episode from saved" : "Save this episode") }
            }
            .padding(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 31))
        }
    }

    /// One glyph. It is visible while the card is hovered, and — separately —
    /// whenever this particular star is set: following the show must not also
    /// park an empty bookmark next to it, which is what a single opacity over
    /// the pair produced. Each keeps its 22pt slot either way, so the one that
    /// stays lit doesn't slide sideways as the other fades in.
    private func star(_ item: Saved.Item, on: String, off: String, help: String) -> some View {
        let set = model.saved.contains(item)
        let visible = hovering || set
        return Button { model.saved.toggle(item) } label: {
            Image(systemName: set ? on : off)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .shadow(color: .black.opacity(0.85), radius: 2, y: 1)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.hit)
        .help(help)
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.14), value: visible)
        // A hidden star must not swallow the click that tunes the channel.
        .allowsHitTesting(visible)
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
                    cityLabel
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

            // The programme's own page on nts.live, when the grid gave both
            // aliases — the same link the now-playing bar's title carries, on the
            // card that is actually showing the programme.
            LinkLabel(text: channel.show.uppercased(),
                      url: channel.episodeURL,
                      font: Theme.display(narrow ? 13 : (compact ? 14 : 16), .black),
                      color: Theme.ink,
                      lineLimit: 2)

            if !compact && !genres.isEmpty && chipsFit {
                HStack(spacing: 5) {
                    ForEach(genres, id: \.self) { g in chip(g) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 14, bottom: 13, trailing: 14))
    }

    /// The city is a label, not a link, and that is a measurement rather than a
    /// preference: Explore filters on moods and genres only, so the fallback was
    /// the catalog's own text search — and 12 of the 1834 indexed shows carry a
    /// location at all, written "LDN" and "NYC" where the card prints "LONDON"
    /// and "NEW YORK". Searching for what this label says finds nothing.
    private var cityLabel: some View { Text(location) }

    // MARK: Genre chips

    private static let chipFont = Theme.mono(8, .semibold)
    /// How far the chip text may shrink before the row is not worth showing.
    private static let chipMinScale: CGFloat = 0.62

    /// Chips are one line, always — the row is a single band of boxes the same
    /// height, and a long genre shrinks its own text to stay on that line rather
    /// than wrapping and making its box twice as tall as its neighbours.
    ///
    /// A chip whose genre Explore also files by that name browses it: the box
    /// inverts under the pointer and clicking opens the catalog filtered to it.
    /// One Explore knows nothing about stays a label — nothing to hover, nothing
    /// to click — which is also every chip until the vocabulary has loaded.
    @ViewBuilder private func chip(_ g: String) -> some View {
        if let id = model.genreID(named: g) {
            Button { model.browseGenre(id) } label: { chipFace(g, inverted: hoveredGenre == g) }
                .buttonStyle(.hit)
                .onHover { inside in
                    hoveredGenre = inside ? g : (hoveredGenre == g ? nil : hoveredGenre)
                    if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
                .help("Browse \(g) in the archive")
        } else {
            chipFace(g, inverted: false)
        }
    }

    private func chipFace(_ g: String, inverted: Bool) -> some View {
        Text(g.uppercased())
            .font(Self.chipFont)
            .tracking(1)
            .lineLimit(1)
            .minimumScaleFactor(Self.chipMinScale)
            .foregroundStyle(inverted ? Theme.ink : Theme.popover)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(inverted ? Theme.popover.opacity(0.92) : Theme.ink.opacity(0.85))
    }

    /// The AppKit twin of `chipFont`, purely for measuring — `Theme.mono` is
    /// `.system(size:weight:design: .monospaced)`, whose NSFont is
    /// `monospacedSystemFont(ofSize:weight:)`.
    private static let chipNSFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .semibold)

    /// How wide the chips want to be at full size — measured, not estimated.
    /// This used to multiply a character count by a guessed per-character width,
    /// which is a number that has to be re-guessed the moment the font, size or
    /// tracking changes, and which silently clips a chip or hides the row a turn
    /// early when it drifts.
    private var chipsNaturalWidth: CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.chipNSFont, .kern: 1]
        let text = genres.reduce(CGFloat(0)) { total, g in
            total + (g.uppercased() as NSString).size(withAttributes: attrs).width.rounded(.up) + 10
        }
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
