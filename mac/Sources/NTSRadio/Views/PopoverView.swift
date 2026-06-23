import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar()

            HStack(spacing: 0) {
                ChannelRail()
                DialView()
                    .overlay { if model.showTracks { TracklistOverlay() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
