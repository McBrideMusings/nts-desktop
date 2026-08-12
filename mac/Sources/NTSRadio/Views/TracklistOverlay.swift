import SwiftUI
import AppKit

struct TracklistOverlay: View {
    @EnvironmentObject var model: AppModel

    private static let colDim = Color(hex: 0x6f6f6b)   // column-header / faint label

    /// Which row is "now playing" — `AppModel.currentTrack`, resolved to its
    /// index in the list this view is actually iterating.
    private var currentIndex: Int? {
        guard let current = model.currentTrack else { return nil }
        return model.tracks.firstIndex(of: current)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: small label + now-playing block (title + subtitle) + close.
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOW PLAYING — \(model.tracksLabel)")
                        .font(Theme.mono(9, .regular)).tracking(1.6)
                        .foregroundStyle(Theme.ch1)
                    Text(model.displayName)
                        .font(Theme.display(24, .black)).tracking(-0.4)
                        .foregroundStyle(Theme.ink)
                    Text(model.subtitle)
                        .font(Theme.mono(10, .regular)).tracking(0.5)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                Button { model.tracksOpen = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hairline(0.08)))
                }
                .buttonStyle(.hit)
            }
            .padding(EdgeInsets(top: 18, leading: 22, bottom: 14, trailing: 22))

            if model.tracks.isEmpty {
                Spacer()
                Text("No tracklist available")
                    .font(Theme.mono(11, .regular))
                    .foregroundStyle(Theme.inkMuted)
                Spacer()
            } else {
                columnHeader
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(model.tracks.enumerated()), id: \.element.id) { idx, track in
                            TrackRow(track: track, playing: idx == currentIndex)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.popover)
    }

    private var columnHeader: some View {
        HStack(spacing: 14) {
            Text("TIME").frame(width: 50, alignment: .leading)
            Text("TRACK").frame(maxWidth: .infinity, alignment: .leading)
            Text("COPY").frame(width: 34, alignment: .trailing)
        }
        .font(Theme.mono(9, .regular)).tracking(1.6)
        .foregroundStyle(Self.colDim)
        .padding(.horizontal, 22)
        .padding(.bottom, 6)
    }
}

private struct TrackRow: View {
    let track: Track
    let playing: Bool
    @State private var copied = false

    var body: some View {
        HStack(spacing: 14) {
            Text(track.time)
                .font(Theme.mono(12, .regular)).monospacedDigit()
                .foregroundStyle(playing ? Theme.ch1 : Theme.inkMuted)
                .frame(width: 50, alignment: .leading)

            // Artist leads, track underneath — the order nts.live lists them in.
            // A track still being identified can arrive with no artist; it takes
            // the lead line rather than leaving a blank one.
            VStack(alignment: .leading, spacing: 1) {
                Text(track.artist.isEmpty ? track.title : track.artist)
                    .font(Theme.display(15, .bold)).tracking(-0.06)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if !track.artist.isEmpty {
                    Text(track.title)
                        .font(Theme.ui(12.5))
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "square.on.square")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(copied ? Theme.green : Color(hex: 0xcfcecb))
                    .frame(width: 27, height: 27)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hairline(0.06)))
            }
            .buttonStyle(.hit)
            .frame(width: 34, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 22)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline(0.07)).frame(height: 1) }
        .overlay(alignment: .leading) {
            if playing { Rectangle().fill(Theme.ch1).frame(width: 3) }
        }
    }

    private func copy() {
        let text = track.artist.isEmpty ? track.title : "\(track.title) — \(track.artist)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
    }
}
