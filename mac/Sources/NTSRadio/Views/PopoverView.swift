import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar()

            HStack(spacing: 0) {
                ChannelRail()
                DialView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The tracklist is a full-width overlay (covers the rail + dial),
            // matching the prototype — not just the dial pane.
            .overlay { if model.showTracks { TracklistOverlay() } }

            NowPlayingBar()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.popover)
        // Extend the content (the TopBar) up under the transparent title bar so
        // its controls land on the traffic lights' row, Spotify-style.
        .ignoresSafeArea(.container, edges: .top)
        .overlay { if model.settingsOpen { SettingsView() } }
    }
}
