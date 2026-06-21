import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ChannelRail()
                DialView()
                    .overlay(alignment: .topTrailing) { settingsGear }
                    .overlay { if model.showTracks { TracklistOverlay() } }
            }
            .frame(height: 580)

            NowPlayingBar()
        }
        .frame(width: 800)
        .background(Theme.popover)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay { if model.settingsOpen { SettingsView() } }
    }

    private var settingsGear: some View {
        Button { model.settingsOpen.toggle() } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(model.settingsOpen ? Theme.popover : Theme.hubInk)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(model.settingsOpen ? Theme.hubInk : Theme.hairline(0.10)))
        }
        .buttonStyle(.plain)
        .padding(14)
    }
}
