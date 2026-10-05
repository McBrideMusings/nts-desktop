import SwiftUI

/// The schedule as a timeline: one channel at a time, a fortnight of programmes
/// in air order, with the day headers pinned as they pass under the top edge.
///
/// It is a list rather than the catalog's tile grid because a schedule is read
/// down a time column — the question is "what is on at four", not "which of
/// these covers looks good". The clock is drawn into the list twice over: the
/// programme on air is filled and badged, and a rule marks where the current
/// minute falls, which is what makes the gaps in NTS's grid legible instead of
/// looking like missing data.
struct ScheduleTimeline: View {
    @EnvironmentObject var model: AppModel

    /// Scrolling to `now` on open, and again whenever the channel changes, so
    /// the list never opens on a fortnight-old Tuesday.
    @State private var scrollTarget: String?

    var body: some View {
        VStack(spacing: 0) {
            controls
            Rectangle().fill(Theme.hairline(0.06)).frame(height: 1)
            timeline
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 8) {
            ForEach(ChannelNumber.allCases, id: \.self) { channel in
                let on = model.timeline.channel == channel
                Button { model.timeline.channel = channel } label: {
                    Text("NTS \(channel.rawValue)")
                        .font(Theme.mono(9, .bold))
                        .tracking(1.2)
                        .foregroundStyle(on ? channelInk(channel.rawValue) : Theme.inkMuted)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(on ? channelFill(channel.rawValue) : .clear)
                        .overlay(Rectangle().stroke(Theme.hairline(on ? 0 : 0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            Button { scrollTarget = model.timeline.anchor } label: {
                Text("NOW")
                    .font(Theme.mono(9, .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .overlay(Rectangle().stroke(Theme.hairline(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Scroll back to what's on now")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    private func channelFill(_ n: Int) -> Color { n == 1 ? Theme.ch1 : Theme.ch2 }
    private func channelInk(_ n: Int) -> Color { n == 1 ? Theme.ch1Text : Theme.ch2Text }

    // MARK: Timeline

    @ViewBuilder private var timeline: some View {
        if model.timeline.days.isEmpty {
            Text("The schedule hasn’t loaded yet.")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            days
        }
    }

    private var days: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.timeline.days) { day in
                        Section {
                            ForEach(day.slots) { slot in
                                SlotRow(slot: slot)
                                    .id(slot.id)
                            }
                        } header: {
                            DayHeader(day: day)
                        }
                    }
                }
            }
            .onAppear { scrollTarget = model.timeline.anchor }
            .onChange(of: model.timeline.channel) { scrollTarget = model.timeline.anchor }
            .onChange(of: scrollTarget) {
                guard let target = scrollTarget else { return }
                // Not `.top`: the day header is pinned, so a row scrolled to the
                // very top lands underneath it. A fifth of the way down clears it.
                proxy.scrollTo(target, anchor: UnitPoint(x: 0, y: 0.2))
                scrollTarget = nil
            }
        }
    }

    static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
}

// MARK: - Day header

private struct DayHeader: View {
    let day: ScheduleController.Day

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(day.label)
                .font(Theme.mono(9, .bold))
                .tracking(1.5)
                .foregroundStyle(Theme.ink)
            if let relative = day.relative {
                Text(relative)
                    .font(Theme.mono(9))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 9).padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque, not translucent: it is pinned over live rows, and at 0.94 the
        // programme title underneath read straight through the date.
        .background(Theme.popover)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline(0.08)).frame(height: 1)
        }
    }
}

// MARK: - Slot

private struct SlotRow: View {
    @EnvironmentObject var model: AppModel
    let slot: NTSAPI.Broadcast
    @State private var hovering = false

    private var indexed: NTSAPI.ShowRef? { model.showIndex.ref(slot.showAlias) }
    /// This broadcast's own photograph, city and genres, once fetched.
    private var detail: SlotDetail? { model.slotArt.detail(for: slot) }
    private var onAir: Bool { model.timeline.onAir?.id == slot.id }
    private var past: Bool { (slot.end ?? .distantFuture) <= Date() }

    private var meta: String {
        let location = [slot.location, detail?.location ?? "", indexed?.location ?? ""]
            .first { !$0.isEmpty } ?? ""
        let genres = [slot.genres, detail?.genres ?? [], indexed?.genres ?? []]
            .first { !$0.isEmpty }?.prefix(2) ?? []
        return ([location] + genres).filter { !$0.isEmpty }.joined(separator: " · ").uppercased()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.start.map(ScheduleTimeline.hhmm.string(from:)) ?? "--:--")
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(onAir ? Theme.liveDot : Theme.inkMuted)
                if let length = slot.lengthLabel {
                    Text(length)
                        .font(Theme.mono(8))
                        .foregroundStyle(Theme.inkMuted.opacity(0.7))
                }
            }
            .frame(width: 42, alignment: .leading)

            artwork

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(slot.title)
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if onAir { onAirBadge }
                }
                if !meta.isEmpty {
                    Text(meta)
                        .font(Theme.mono(8, .medium))
                        .tracking(1.1)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(onAir ? Theme.liveDot.opacity(0.07) : (hovering ? Theme.hairline(0.03) : .clear))
        // The clock is drawn once, as the fill on the programme that is on. At a
        // changeover the finished slot leaves the list and the fill moves down to
        // its successor; `advanceSlots` animates that so the hand-over is
        // something you see happen rather than a jump you have to notice.
        .animation(.easeInOut(duration: 0.4), value: onAir)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline(0.05)).frame(height: 1)
        }
        // Finished programmes stay in the list — the grid opens a day in the past
        // and the day you are in is half over — but recede so the eye lands on
        // what is still to come.
        .opacity(past ? 0.4 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.openSlot(slot) }
        // The row asks for its own artwork as it scrolls in. `LazyVStack` only
        // builds visible rows, so this is the fortnight fetched a screen at a
        // time instead of 345 requests at open.
        .onAppear { model.slotArt.request(slot) }
        // Scrolled past before its turn came: give up the place in the queue, so
        // a drag through the fortnight doesn't spend its requests on rows that
        // are already gone.
        .onDisappear { model.slotArt.cancel(slot) }
    }

    /// This broadcast's photograph, then the show's standing one from the index,
    /// then the mark. The index's copy is on disk, so on the second launch a row
    /// is dressed before its fetch answers.
    private var artwork: some View {
        Rectangle()
            .fill(Theme.hairline(0.05))
            .frame(width: 40, height: 40)
            .overlay { ArtworkPlaceholder(size: 16) }
            .overlay {
                if let url = detail?.image ?? indexed?.thumbURL {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                }
            }
            .clipped()
    }

    /// Tapping the badge tunes the channel, which is the only thing a listener
    /// can actually do with the programme that is on: the rest of the grid is
    /// either finished or hasn't been broadcast yet.
    private var onAirBadge: some View {
        Button { model.select(.channel(slot.channel)) } label: {
            Text("ON AIR")
                .font(Theme.mono(8, .bold))
                .tracking(1.1)
                .foregroundStyle(.white)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Theme.liveDot)
        }
        .buttonStyle(.plain)
        .help("Tune to NTS \(slot.channel)")
    }
}

extension NTSAPI.Broadcast {
    /// "1h", "90m" — how long the programme runs, for the line under its start.
    var lengthLabel: String? {
        guard let start, let end, end > start else { return nil }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        if minutes >= 60, minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
}
