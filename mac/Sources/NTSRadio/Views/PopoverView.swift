import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
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

            HStack(spacing: 0) {
                ChannelRail()
                DialView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The tracklist is a full-width overlay (covers the rail + dial),
            // matching the prototype — not just the dial pane.
            .overlay { if model.showTracks { TracklistOverlay() } }
            // The catalog covers the faceplate entirely, channel cards included,
            // so the window never has to resize to make room for it.
            .overlay { if model.catalogOpen { CatalogOverlay() } }
            .animation(.easeOut(duration: 0.18), value: model.catalogOpen)

            NowPlayingBar()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.popover)
        // Lay the stack out from the very top of the window, so the strip above
        // covers the title-bar band exactly instead of being pushed below it.
        .ignoresSafeArea(.container, edges: .top)
        .overlay { if model.settingsOpen { SettingsView() } }
        .overlay { if model.loginOpen { LoginView() } }
    }
}
