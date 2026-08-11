import SwiftUI

/// A strip that appears when nts.live stops answering.
///
/// Without it, a failed request is invisible: the catalog keeps showing whatever
/// it fetched last, so "the schedule stopped updating an hour ago" and "nothing
/// new has been scheduled" look the same. The strip says which of the two it is,
/// whose fault it looks like, and leaves the stale contents on screen — they are
/// still the best information the app has.
struct ServiceBanner: View {
    @ObservedObject private var status = ServiceStatus.shared

    var body: some View {
        if let outage = status.outage {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.liveDot)

                Text(outage.message)
                    .font(Theme.mono(9, .medium))
                    .tracking(1.1)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                // The detail is the technical line — HTTP 503, a timeout. It is
                // second, and quieter, because the first line is what the person
                // actually lost.
                Text(outage.detail.uppercased())
                    .font(Theme.mono(8))
                    .tracking(1)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.liveDot.opacity(0.10))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.liveDot.opacity(0.35)).frame(height: 1)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeOut(duration: 0.25), value: outage)
        }
    }
}
