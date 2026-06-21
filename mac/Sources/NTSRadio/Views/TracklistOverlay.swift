import SwiftUI

struct TracklistOverlay: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.tracksLabel)
                        .font(Theme.mono(10, .regular)).tracking(1.6)
                        .foregroundStyle(Theme.inkMuted)
                    Text(model.displayName)
                        .font(Theme.display(18, .black))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button { model.showTracks = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hairline(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(EdgeInsets(top: 18, leading: 22, bottom: 12, trailing: 22))

            if model.tracks.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("No tracklist available")
                        .font(Theme.mono(11, .regular))
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.tracks) { TrackRow(track: $0) }
                    }
                }
                .padding(.horizontal, 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.popover)
    }
}

private struct TrackRow: View {
    let track: Track
    var body: some View {
        HStack(spacing: 14) {
            Text(track.time)
                .font(Theme.display(13, .heavy)).monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 44, alignment: .leading)
            Rectangle()
                .fill(Color(h: track.hue, s: 70, l: 55))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title.uppercased())
                    .font(Theme.display(14, .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(track.artist)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline(0.07)).frame(height: 1) }
    }
}
