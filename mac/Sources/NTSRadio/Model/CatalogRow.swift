import Foundation

/// One tile in the catalog grid.
///
/// The grid mixes three sources that have nothing in common structurally — a
/// broadcast slot, a mixtape, a bare show-index entry — and a search shows all
/// three at once. Rather than branch on the source at every point in the view,
/// each one is flattened into this on the way in, so the grid renders one type
/// and the model keeps the knowledge of what each row can actually do.
struct CatalogRow: Identifiable, Hashable {
    enum Target: Hashable {
        case show(alias: String, title: String)
        case mixtape(alias: String)
    }
    /// What tuning this row starts. A future schedule slot can't be played early,
    /// so it offers its channel — the live stream it will air on.
    enum Playable: Hashable {
        case channel(Int)
        case mixtape(String)
    }

    let id: String
    let title: String
    /// The line under the title: air time and channel, detent number, saved kind.
    let meta: String
    let image: URL?
    /// Set on the slot that is on air now.
    let live: Bool
    let target: Target?
    let playable: Playable?
    let savedItem: Saved.Item?

    // MARK: Sources

    /// `resolved` is the show this slot turned out to be, looked up by title.
    ///
    /// It has to be looked up because the live response only embeds details for
    /// the current and next broadcast — the other sixteen slots per channel arrive
    /// as a title and a time with no alias, no genres and no artwork. Without the
    /// lookup those tiles are blank rectangles that can't be opened or saved.
    init(_ b: NTSAPI.Broadcast, resolved: NTSAPI.ShowRef? = nil) {
        id = "b:\(b.id)"
        title = b.title
        let loc = b.location.isEmpty ? (resolved?.location ?? "") : b.location
        let bits = [loc.isEmpty ? nil : loc, b.startEnd.isEmpty ? nil : b.startEnd]
        meta = (["NTS \(b.channel)"] + bits.compactMap { $0 }).joined(separator: " · ")
        image = b.image ?? resolved?.pictureURL
        live = false

        let alias = b.showAlias.isEmpty ? (resolved?.alias ?? "") : b.showAlias
        target = alias.isEmpty ? nil : .show(alias: alias, title: b.title)
        playable = .channel(b.channel)
        savedItem = alias.isEmpty ? nil : Saved.Item(
            kind: .show, alias: alias, title: b.title,
            subtitle: "NTS \(b.channel) · \(b.startEnd)",
            image: (b.image ?? resolved?.pictureURL)?.absoluteString)
    }

    init(_ m: Mixtape, detent: Int) {
        id = "m:\(m.alias)"
        title = m.title
        meta = "DETENT \(String(format: "%02d", detent))"
        image = m.coverURL
        live = false
        target = .mixtape(alias: m.alias)
        playable = .mixtape(m.alias)
        savedItem = Saved.Item(kind: .mixtape, alias: m.alias, title: m.title,
                               subtitle: m.subtitle, image: m.coverURL?.absoluteString)
    }

    init(_ s: NTSAPI.ShowRef) {
        id = "s:\(s.alias)"
        title = s.name
        meta = ([s.location.isEmpty ? nil : s.location] + s.genres.prefix(2).map { $0 })
            .compactMap { $0 }.joined(separator: " · ")
        image = s.pictureURL
        live = false
        target = .show(alias: s.alias, title: s.name)
        playable = nil
        savedItem = Saved.Item(kind: .show, alias: s.alias, title: s.name,
                               subtitle: s.location, image: s.picture)
    }

    init(_ item: Saved.Item) {
        id = "v:\(item.id)"
        title = item.title
        meta = item.kind == .mixtape ? "MIXTAPE" : "SHOW"
        image = item.imageURL
        live = false
        switch item.kind {
        case .show:
            target = .show(alias: item.alias, title: item.title)
            playable = nil
        case .mixtape:
            target = .mixtape(alias: item.alias)
            playable = .mixtape(item.alias)
        }
        savedItem = item
    }

    /// Copy with the on-air flag set — applied by the view once, rather than
    /// making every initialiser take a parameter only one caller uses.
    func markedLive() -> CatalogRow {
        CatalogRow(id: id, title: title, meta: meta, image: image, live: true,
                   target: target, playable: playable, savedItem: savedItem)
    }

    private init(id: String, title: String, meta: String, image: URL?, live: Bool,
                 target: Target?, playable: Playable?, savedItem: Saved.Item?) {
        self.id = id; self.title = title; self.meta = meta; self.image = image
        self.live = live; self.target = target; self.playable = playable; self.savedItem = savedItem
    }
}

// MARK: - What a query is matched against

extension NTSAPI.Broadcast {
    var searchText: String {
        "\(title) \(location) \(genres.joined(separator: " "))".lowercased()
    }
}

extension Mixtape {
    /// Includes the credits, so searching a host's name finds the mixtape their
    /// show feeds — the route the dial alone can't express.
    var searchText: String {
        "\(title) \(subtitle) \(credits.map(\.name).joined(separator: " "))".lowercased()
    }
}
