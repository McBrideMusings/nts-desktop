import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The now-playing bar sits outside the body's own reader, so the window
        // width comes from here.
        GeometryReader { window in
            stack(windowWidth: window.size.width)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private func stack(windowWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            // The title-bar band, painted here rather than in the accessory
            // because AppKit insets that accessory past the traffic lights: this
            // is the only view in the strip that spans the true window width, so
            // it colours the corner behind the traffic lights, lets the rule
            // below run edge to edge, and — centring the NTS mark in it — puts
            // the mark on the window's real centre line instead of the centre of
            // whatever AppKit left of the accessory. Nothing interactive goes
            // here: the title bar swallows clicks in this band, which is why the
            // controls live in the accessory.
            Theme.nowBar
                .frame(height: Theme.titleBarHeight)
                .overlay(
                    NTSMark.filled(Theme.ink.opacity(0.9))
                        .frame(width: 13, height: 13)
                )
            Rectangle().fill(Theme.hairline(0.08)).frame(height: 1)

            // The rail follows the window's long axis. A window taller than it is
            // wide puts the two channel cards in a row across the top so the dial
            // gets the full width instead of whatever is left beside a 268pt
            // column; a short window keeps the rail on the left but lays its cards
            // out side by side, which is the only way two of them still read at
            // 300pt of height. Everything else is the original left-column rail.
            // One decision here: does the rail sit above the dial or beside it.
            // That follows the window's own proportions, and the rail then picks
            // how to arrange its two cards from the box it ends up with — see
            // `ChannelRail`. There used to be a third case keyed to a bare
            // "shorter than 430pt", which swapped the whole rail for a one-point
            // change in height and had nothing to do with what the cards needed.
            //
            // Every rail size is capped at a share of the window as well as a
            // fixed number of points, so the dial always keeps the majority of
            // the pane. The fixed 300pt rail is what used to make a 340pt-wide
            // window impossible, and the minimum size had to be a two-part rule
            // to work around it — which is what made resizing snap.
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                // The rail is sized so its two cards come out square: stacked
                // down one edge, each card is half the rail's height, so the
                // rail wants to be exactly that wide; laid out across the top,
                // each is half the width, so it wants to be that tall. Capped at
                // a share of the window either way, so the dial always keeps the
                // majority of the pane — when the cap bites, `ChannelRail` still
                // centres a square card in the slot it was given.
                if h > 0 && w / h <= 1.02 {
                    VStack(spacing: 0) {
                        ChannelRail(edge: .bottom)
                            .frame(height: min(ChannelRail.half(w), h * 0.45))
                        DialView()
                    }
                } else {
                    HStack(spacing: 0) {
                        ChannelRail(edge: .trailing)
                            .frame(width: min(ChannelRail.half(h), w * 0.55))
                        DialView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Where you are. The catalog covers the faceplate entirely, channel
            // cards included, so the window never has to resize to make room for
            // it — but it replaces the faceplate rather than sitting on top of
            // it, which is why this is a switch on one value and not a stack of
            // overlays in declaration order.
            .overlay {
                switch model.pane {
                case .live:    EmptyView()
                case .catalog: CatalogOverlay()
                }
            }
            .animation(Theme.Motion.panel, value: model.paneState)
            // What is playing, over the top of either. The drawer rises from the
            // now-playing bar it belongs to and drops back into it, so it reads
            // as the bar opening up rather than a third place the window went.
            // Reduce Motion gets the same drawer without the travel.
            //
            // Both overlays animate off `paneState` — the pair, not the two
            // properties separately. Pressing EXPLORE while the drawer is up
            // changes both at once, and a curve each would run side by side,
            // leaving a moment with the catalog, the tracklist and the faceplate
            // all part-visible. One value means one transaction and one curve
            // over the same region.
            .overlay {
                if model.tracksOpen {
                    TracklistOverlay()
                        .transition(reduceMotion
                                    ? .opacity
                                    : .move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Above the now-playing bar rather than inside the catalog: an
            // outage stales the faceplate too — the channel cards are what the
            // schedule grid fills — and the catalog is not always open.
            if !model.catalogOpen { ServiceBanner() }

            NowPlayingBar(width: windowWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.popover)
    }
}
