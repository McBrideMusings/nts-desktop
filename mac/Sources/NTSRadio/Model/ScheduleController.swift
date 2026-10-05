import Foundation
import SwiftUI

/// The channels' programme grids: fetching them, handing each channel over to
/// its next programme at a changeover, dressing the programme on air — and the
/// schedule tab's view of them, which channel it shows and what that grid
/// looks like against the clock.
///
/// The grid itself lives on the catalog (`Channel.upcoming`), the single record
/// of what is on air that the rail, the now-playing tile and the timeline all
/// read; in the running app, this is the only thing that writes it.
@MainActor
final class ScheduleController: ObservableObject {
    /// Which channel's grid the schedule tab is showing. One at a time: at the
    /// window's 340pt floor, two columns of programme titles leave about fifteen
    /// characters each.
    @Published var channel: ChannelNumber = .one

    private let catalog: Catalog
    private let slotArt: SlotArtLoader
    private let showIndex: ShowIndex

    init(catalog: Catalog, slotArt: SlotArtLoader, showIndex: ShowIndex) {
        self.catalog = catalog
        self.slotArt = slotArt
        self.showIndex = showIndex
        Task { [weak self] in await self?.pollSchedule() }
    }

    // MARK: Lifecycle

    /// In-flight artwork fetches, one per channel, so a changeover cancels the
    /// previous programme's request instead of racing it.
    private var detailTasks: [ChannelNumber: Task<Void, Never>] = [:]

    /// Sleeps until the current programme's end time, then hands the rail over to
    /// the next slot. See `scheduleSlotAdvance()`.
    private var slotTimer: Task<Void, Never>?

    /// How long a fetched grid is trusted. NTS serves the schedule with
    /// `cache-control: max-age=900`, so asking more often than that re-reads the
    /// same bytes.
    private static let scheduleMaxAge: TimeInterval = 900
    private var scheduleFetched: Date?

    /// Keep the grid fresh and the rail on the right programme. Runs for the
    /// controller's lifetime, started by `init`.
    ///
    /// The changeover is `scheduleSlotAdvance`'s timer, which fires on the
    /// boundary itself. This loop is the safety net behind it: a machine that
    /// slept through a boundary, or a grid that aged past NTS's fifteen-minute
    /// cache, catches up within a minute. It costs no request in the ordinary
    /// case — `refreshSchedule` is the only fetch here and it is rate-limited.
    private func pollSchedule() async {
        while !Task.isCancelled {
            if scheduleFetched.map({ Date().timeIntervalSince($0) > Self.scheduleMaxAge }) ?? true {
                await refreshSchedule()
            }
            advanceSlots()
            scheduleSlotAdvance()
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        }
    }

    /// Pull both channels' published programme grids — fourteen days each, every
    /// slot timed and named.
    ///
    /// This replaces reading the grid out of `/api/v2/live`, which only embedded
    /// details for the current and next slot and left the other sixteen to be
    /// matched back to a show by their title. Finished slots are dropped on the
    /// way in so `upcoming` still means what it says.
    func refreshSchedule() async {
        var grids: [ChannelNumber: [NTSAPI.Broadcast]] = [:]
        for number in ChannelNumber.allCases {
            guard let slots = try? await NTSAPI.schedule(channel: number) else { continue }
            grids[number] = slots
        }
        guard !grids.isEmpty else { return }
        scheduleFetched = Date()

        let now = Date()
        for number in ChannelNumber.allCases {
            guard let slots = grids[number] else { continue }
            let head = catalog[number].onAir?.id
            catalog[number].upcoming = slots.filter { ($0.end ?? .distantPast) > now }
            if catalog[number].onAir?.id != head { refreshDetail(number) }
            // Every slot names its show; folding those in is how the index covers
            // shows past the 1012 the shows endpoint will hand out.
            for b in slots where !b.showAlias.isEmpty {
                showIndex.note(alias: b.showAlias, name: b.title)
            }
        }
    }

    /// Move each channel on to the programme the clock is actually in, dropping
    /// the slots that have finished.
    ///
    /// The grid already names every upcoming slot and the minute it ends, so a
    /// changeover is something the app can do on its own — it doesn't have to be
    /// told. It used to be told, by `/api/v2/live`, which NTS serves with
    /// `cache-control: max-age=900`: for up to fifteen minutes after the hour
    /// every poll handed back the programme that had just finished and wrote it
    /// straight over the one that had started.
    ///
    /// Dropping the finished slots is now the whole changeover. Nothing here
    /// copies a title or a time anywhere — the rail reads them off the head of
    /// the grid — so this is idempotent and can run as often as it likes.
    func advanceSlots(now: Date = Date()) {
        withAnimation(.easeInOut(duration: 0.4)) { advance(now: now) }
    }

    private func advance(now: Date) {
        for number in ChannelNumber.allCases {
            let live = catalog[number].upcoming.drop { ($0.end ?? .distantFuture) <= now }
            guard live.first?.id != catalog[number].onAir?.id else { continue }
            catalog[number].upcoming = Array(live)
            refreshDetail(number)
        }
    }

    /// Wake once, at the moment the earliest current programme ends, to hand over
    /// to the next one. Re-armed after every advance and every poll.
    private func scheduleSlotAdvance() {
        slotTimer?.cancel()
        let now = Date()
        guard let end = catalog.channels.compactMap({ $0.upcoming.first?.end }).filter({ $0 > now }).min()
        else { return }
        // A second past the boundary, so the slot being handed over has genuinely ended.
        let delay = end.timeIntervalSince(now) + 1
        slotTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.advanceSlots()
            self.scheduleSlotAdvance()
        }
    }

    /// Dress whatever is now at the head of a channel's grid.
    ///
    /// Two steps, because the grid publishes no artwork: the show's own picture
    /// goes on immediately so the tile never goes blank across a handover, then
    /// the episode's own photograph replaces it once NTS answers. Both writes
    /// name the slot they belong to, so neither can land on the next programme.
    private func refreshDetail(_ number: ChannelNumber) {
        detailTasks[number]?.cancel()
        guard let slot = catalog[number].onAir else {
            catalog[number].detail = nil
            return
        }
        let indexed = showIndex.ref(slot.showAlias)
        catalog[number].detail = SlotDetail(
            slotID: slot.id,
            image: slot.image ?? indexed?.pictureURL,
            // Genres never fall back to the show-level index: that cache holds
            // whichever episode of this show NTS first tagged, so an untagged
            // episode would inherit another episode's genres instead of showing
            // none, same as nts.live does for it.
            genres: slot.genres,
            location: slot.location.isEmpty ? (indexed?.location ?? "") : slot.location)

        guard !slot.showAlias.isEmpty, !slot.episodeAlias.isEmpty else { return }
        // The timeline's ON AIR row wants exactly this episode, so it takes the
        // rail's copy rather than asking NTS for the same JSON a second time.
        slotArt.adopt(slot, detail: nil)
        detailTasks[number] = Task { [weak self] in
            guard let ep = try? await NTSAPI.episode(show: slot.showAlias, episode: slot.episodeAlias,
                                                     reportAs: "on-air-detail"),
                  !Task.isCancelled, let self,
                  self.catalog[number].onAir?.id == slot.id
            else { return }
            self.slotArt.adopt(slot, detail: SlotDetail(
                slotID: slot.id,
                image: ep.image,
                genres: ep.genres,
                location: [ep.locationLong, ep.location].first { !$0.isEmpty } ?? ""))
            withAnimation(.easeInOut(duration: 0.3)) {
                self.catalog[number].detail = SlotDetail(
                    slotID: slot.id,
                    image: ep.image ?? self.catalog[number].detail?.image,
                    genres: ep.genres.isEmpty ? (self.catalog[number].detail?.genres ?? []) : ep.genres,
                    location: [ep.locationLong, ep.location,
                               self.catalog[number].detail?.location ?? ""]
                        .first { !$0.isEmpty } ?? "")
            }
        }
    }

    // MARK: The schedule tab

    /// One day of one channel's grid — the unit the timeline scrolls through.
    struct Day: Identifiable {
        let id: String
        /// "TUE 11 AUG", the sticky header's text.
        let label: String
        /// "TODAY"/"TOMORROW" where it applies, so the top of the list doesn't
        /// have to be read as a date to be understood.
        let relative: String?
        let slots: [NTSAPI.Broadcast]
    }

    /// The selected channel's grid, grouped into days in air order.
    var days: [Day] {
        let slots = catalog[channel].upcoming
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        var days: [(Date, [NTSAPI.Broadcast])] = []
        for slot in slots {
            guard let start = slot.start else { continue }
            let day = cal.startOfDay(for: start)
            if days.last?.0 == day { days[days.count - 1].1.append(slot) }
            else { days.append((day, [slot])) }
        }

        return days.map { day, slots in
            let offset = cal.dateComponents([.day], from: today, to: day).day ?? 0
            let relative: String? = switch offset {
            case 0: "TODAY"
            case 1: "TOMORROW"
            case -1: "YESTERDAY"
            default: nil
            }
            return Day(id: Self.dayKey.string(from: day),
                       label: Self.dayLabel.string(from: day).uppercased(),
                       relative: relative,
                       slots: slots)
        }
    }

    /// The slot the clock is inside on the selected channel, if any — the row the
    /// timeline scrolls to and marks ON AIR.
    var onAir: NTSAPI.Broadcast? {
        let now = Date()
        return catalog[channel].upcoming.first {
            ($0.start ?? .distantFuture) <= now && now < ($0.end ?? .distantPast)
        }
    }

    /// The first slot that has not started on the selected channel. The grid has
    /// real gaps — roughly thirty a fortnight per channel — so when the clock is
    /// in one of them this is what the NOW rule sits above.
    var next: NTSAPI.Broadcast? {
        let now = Date()
        return catalog[channel].upcoming.first {
            ($0.start ?? .distantPast) > now
        }
    }

    /// What the timeline scrolls to when it opens: the programme on air, or the
    /// next one to start when the clock is in a gap, or the top of the grid.
    var anchor: String? {
        onAir?.id ?? next?.id ?? days.first?.slots.first?.id
    }

    private static let dayKey: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let dayLabel: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()
}
