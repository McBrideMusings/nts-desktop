import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel

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
            // The title-bar band. The window's top-bar accessory paints its own
            // black over everything right of the traffic lights, but AppKit
            // insets that accessory past them, so this fills the same strip
            // inside the content view — that's what colours the corner behind
            // the traffic lights and lets the rule below run the full width.
            // Nothing interactive goes here: the title bar swallows clicks in
            // this band, which is why the controls live in the accessory.
            Theme.nowBar.frame(height: TopBar.height)
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
                            .frame(height: min((w - 1) / 2, h * 0.45))
                        DialView()
                    }
                } else {
                    HStack(spacing: 0) {
                        ChannelRail(edge: .trailing)
                            .frame(width: min((h - 1) / 2, w * 0.55))
                        DialView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The tracklist is a full-width overlay (covers the rail + dial),
            // matching the prototype — not just the dial pane.
            .overlay { if model.showTracks { TracklistOverlay() } }
            // The catalog covers the faceplate entirely, channel cards included,
            // so the window never has to resize to make room for it.
            .overlay { if model.catalogOpen { CatalogOverlay() } }
            .animation(.easeOut(duration: 0.18), value: model.catalogOpen)

            // Above the now-playing bar rather than inside the catalog: an
            // outage stales the faceplate too — the channel cards are what
            // `/api/v2/live` fills — and the catalog is not always open.
            if !model.catalogOpen { ServiceBanner() }

            NowPlayingBar(width: windowWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.popover)
        .overlay { if model.settingsOpen { SettingsView() } }
        .overlay { if model.loginOpen { LoginView() } }
    }
}
