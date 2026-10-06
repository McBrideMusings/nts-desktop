import SwiftUI

/// Fetches, caches and persists per-schedule-row artwork: photograph, genres
/// and city, keyed by `<show>/<episode>`.
///
/// The grid publishes no artwork, no genres and no city — only a title, a
/// time and two aliases — so without this every row but the handful of shows
/// the app had met elsewhere drew the placeholder mark and no second line.
/// Filled per row as it scrolls into view rather than in one sweep at open
/// (the fortnight is ~345 slots and nobody scrolls all of it), concurrency-
/// limited so a scrollbar drag through the whole grid doesn't fire hundreds
/// of requests at once, and kept on disk (trimmed to the current grid) so a
/// relaunch doesn't re-ask for the rows this session already paid for.
///
/// Owns no reference to the catalog or the show index — both of those are
/// effects a caller performs on the cache, not something this type reads for
/// itself. `noteShow` and `onPersist` are how the caller supplies them.
@MainActor
final class SlotArtLoader: ObservableObject {
    @Published private(set) var slotDetails: [String: SlotDetail] =
        Cache.load([String: SlotDetail].self, from: slotDetailFile) ?? [:]

    nonisolated private static let slotDetailFile = "schedule-art.json"

    /// Slots asked for, so a row that leaves and re-enters the viewport
    /// doesn't ask twice. A failure drops out again — otherwise a scroll
    /// taken while the network was down would leave those rows blank until
    /// the app was relaunched, with nothing to prompt a second attempt.
    private var slotDetailAsked: Set<String> = []

    /// Rows waiting for a fetch, newest first — the ones nearest what is on
    /// screen. Dragging the scrollbar through a fortnight touches ~345 rows
    /// in a second, and firing all of them means hundreds of requests for
    /// rows that are already gone by the time they answer.
    private var slotDetailQueue: [NTSAPI.Broadcast] = []
    private var slotDetailRunning = 0
    private static let slotDetailConcurrency = 4

    private var slotDetailSaveTask: Task<Void, Never>?

    /// Fired when a fetch resolves via the show endpoint (never the episode
    /// endpoint — see the guard inside `fetchSlotDetail`), so the caller can
    /// fold it into whatever show index it keeps. `(alias, name, location,
    /// genres, picture)`.
    var noteShow: ((String, String, String, [String], String?) -> Void)?
    /// Fired a few seconds after fetches stop, so the caller can compute the
    /// live key set (from whatever catalog it holds) and call `flush(keeping:)`
    /// with it. This is the inversion that keeps this type off the catalog:
    /// the caller supplies what is still live rather than this type reading
    /// it for itself.
    var onPersist: (() -> Void)?

    /// Two airings of the same episode share an answer, which is the point of
    /// keying by episode rather than by slot. A slot NTS has not named an
    /// episode for yet has nothing to share, so it keys by its own id instead
    /// of colliding with every other unnamed slot of the same show.
    static func slotKey(_ slot: NTSAPI.Broadcast) -> String {
        slot.episodeAlias.isEmpty ? "\(slot.showAlias)/#\(slot.id)"
                                  : "\(slot.showAlias)/\(slot.episodeAlias)"
    }

    func detail(for slot: NTSAPI.Broadcast) -> SlotDetail? {
        slotDetails[Self.slotKey(slot)]
    }

    /// Fetch one schedule row's episode — its photograph, genres and city.
    ///
    /// The episode rather than the show, so a repeat carries the cover of the
    /// broadcast being repeated instead of the show's standing one. A slot
    /// with no episode alias yet (the furthest-out ~30% of the grid) falls
    /// back to the show, which still has artwork.
    func request(_ slot: NTSAPI.Broadcast) {
        guard !slot.showAlias.isEmpty else { return }
        let key = Self.slotKey(slot)
        guard slotDetails[key] == nil, slotDetailAsked.insert(key).inserted else { return }
        slotDetailQueue.append(slot)
        pumpSlotDetails()
    }

    /// A row that scrolled away before its turn came gives up its place. One
    /// already in flight is left alone — it is nearly paid for, and the
    /// answer is kept either way.
    func cancel(_ slot: NTSAPI.Broadcast) {
        let key = Self.slotKey(slot)
        guard let i = slotDetailQueue.firstIndex(where: { Self.slotKey($0) == key }) else { return }
        slotDetailQueue.remove(at: i)
        slotDetailAsked.remove(key)
    }

    /// Claim a key against a duplicate fetch, and optionally write a fetched
    /// result with the debounced persist that follows it.
    ///
    /// `detail == nil` is the pre-fetch reservation the on-air rail makes
    /// before it has an answer — this is what stops the timeline's ON AIR row
    /// asking NTS for the same episode a second time while the rail's own
    /// fetch is in flight. `detail` non-nil is the post-fetch write, once the
    /// rail already has the episode and hands its result straight into the
    /// cache.
    func adopt(_ slot: NTSAPI.Broadcast, detail: SlotDetail?) {
        let key = Self.slotKey(slot)
        slotDetailAsked.insert(key)
        guard let detail else { return }
        slotDetails[key] = detail
        saveSlotDetailsSoon()
    }

    private func pumpSlotDetails() {
        while slotDetailRunning < Self.slotDetailConcurrency, let slot = slotDetailQueue.popLast() {
            slotDetailRunning += 1
            fetchSlotDetail(slot)
        }
    }

    private func fetchSlotDetail(_ slot: NTSAPI.Broadcast) {
        let key = Self.slotKey(slot)
        Task { [weak self] in
            defer {
                if let self {
                    self.slotDetailRunning -= 1
                    self.pumpSlotDetails()
                }
            }
            let show = slot.showAlias, episode = slot.episodeAlias
            var image: URL?
            var genres: [String] = []
            var location = ""
            var name = slot.title
            var fromShow = false

            if !episode.isEmpty,
               let ep = try? await NTSAPI.episode(show: show, episode: episode,
                                                  reportAs: .scheduleArt) {
                image = ep.image
                genres = ep.genres
                location = [ep.locationLong, ep.location].first { !$0.isEmpty } ?? ""
                if !ep.name.isEmpty { name = ep.name }
            } else if let s = try? await NTSAPI.show(alias: show) {
                image = s.image
                genres = s.genres
                location = s.location
                if !s.name.isEmpty { name = s.name }
                fromShow = true
            } else {
                self?.slotDetailAsked.remove(key)
                return
            }

            guard let self else { return }
            self.slotDetails[key] = SlotDetail(slotID: slot.id, image: image,
                                               genres: genres, location: location)
            self.saveSlotDetailsSoon()
            // Only the show endpoint's answer is passed on. An episode's
            // title and cover belong to that broadcast, not to the show — and
            // the caller's index keeps the first rich entry it is given, so
            // firing this on the episode path would make "Lung Dart 10th
            // August 2026" the show's name in search for good.
            if fromShow {
                self.noteShow?(show, name, location, genres, image?.absoluteString)
            }
        }
    }

    /// Write the row artwork a few seconds after the fetches stop. Encoding
    /// and writing happen off the main actor: the UI is running while a
    /// scroll is what triggers this.
    private func saveSlotDetailsSoon() {
        slotDetailSaveTask?.cancel()
        slotDetailSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.slotDetailSaveTask = nil
            self.onPersist?()
        }
    }

    /// Drop the rows that have left `live`, and persist what is left.
    ///
    /// `sync: false` (the default) is the scroll-triggered path: encoding and
    /// writing happen off the main actor via `Task.detached`. `sync: true` is
    /// the quit path, which writes synchronously (a detached task would not
    /// outlive the process) and cancels any pending debounced save first.
    @discardableResult
    func flush(keeping live: Set<String>, sync: Bool = false) -> [String: SlotDetail] {
        slotDetails = slotDetails.filter { live.contains($0.key) }
        if sync {
            slotDetailSaveTask?.cancel()
            slotDetailSaveTask = nil
            Cache.save(slotDetails, to: Self.slotDetailFile)
        } else {
            let live = slotDetails
            Task.detached { Cache.save(live, to: Self.slotDetailFile) }
        }
        return slotDetails
    }
}
