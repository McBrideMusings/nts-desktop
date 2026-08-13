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
        case episode(show: String, episode: String)
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

    /// `resolved` is the indexed show this slot's alias points at.
    ///
    /// The schedule gives every slot a show alias but no genres, location or
    /// artwork, so the index supplies those. Without it the tile is a titled
    /// rectangle — still openable and saveable, just bare.
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
        // The index can supply an alias the slot itself lacks, so the item is
        // built from a broadcast carrying whichever of the two is present.
        savedItem = Saved.Item.show(b.withShowAlias(alias), image: b.image ?? resolved?.pictureURL)
    }

    /// An Explore result. It plays where a schedule slot only tunes a channel:
    /// this is a finished recording, and its two aliases are everything the
    /// player needs to resolve the audio.
    init(_ e: NTSAPI.EpisodeCard) {
        id = "e:\(e.id)"
        title = e.title
        meta = ([e.date, e.location] + e.genres.prefix(1))
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            .uppercased()
        image = e.image
        live = false
        target = .show(alias: e.showAlias, title: e.title)
        playable = .episode(show: e.showAlias, episode: e.episodeAlias)
        savedItem = Saved.Item(kind: .episode, alias: e.showAlias, episodeAlias: e.episodeAlias,
                               title: e.title, subtitle: e.date, image: e.image?.absoluteString)
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
        switch item.kind {
        case .show: meta = "SHOW"
        case .mixtape: meta = "MIXTAPE"
        case .episode: meta = "EPISODE"
        }
        image = item.imageURL
        live = false
        switch item.kind {
        case .show:
            target = .show(alias: item.alias, title: item.title)
            playable = nil
        case .mixtape:
            target = .mixtape(alias: item.alias)
            playable = .mixtape(item.alias)
        case .episode:
            target = .show(alias: item.alias, title: item.title)
            playable = .episode(show: item.alias, episode: item.episodeAlias ?? "")
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
