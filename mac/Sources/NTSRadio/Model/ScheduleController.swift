import Foundation

/// The schedule tab's own state: which channel's grid it shows, and what that
/// grid looks like against the clock — the days it scrolls through, the slot
/// on air, the next one to start, and where the list opens.
///
/// Reads the grid from the catalog and never writes it. Fetching the grid and
/// handing a channel over at a changeover stay on `AppModel`, which owns the
/// channels this reads.
@MainActor
final class ScheduleController: ObservableObject {
    /// Which channel's grid the schedule tab is showing. One at a time: at the
    /// window's 340pt floor, two columns of programme titles leave about fifteen
    /// characters each.
    @Published var channel: ChannelNumber = .one

    private let catalog: Catalog

    init(catalog: Catalog) {
        self.catalog = catalog
    }

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
