import Foundation
import Combine

/// What the user has starred: on this Mac, and on their NTS account when signed
/// in.
///
/// The local file is the one that is always there — signed out, this behaves
/// exactly as it always has. Signing in adds the account's own follows and saved
/// episodes on top, through `NTSFavourites`, and sends stars back the other way.
///
/// The merge favours keeping things: a star from either side survives. Nothing
/// here deletes from the account except an explicit unstar, because the two
/// lists were kept separately for months and treating one as authoritative
/// would silently throw away whichever side the user used less.
@MainActor
final class Saved: ObservableObject {
    static let shared = Saved()

    /// A starred thing. Shows are keyed by alias, mixtapes by alias too; the kind
    /// keeps the two namespaces apart and tells the catalog how to open it.
    struct Item: Codable, Hashable, Identifiable {
        enum Kind: String, Codable { case show, mixtape, episode }
        let kind: Kind
        /// The show alias for every kind — a mixtape's own alias for `.mixtape`.
        let alias: String
        /// Set only for `.episode`, where `alias` alone is the show, not the
        /// saved thing itself.
        var episodeAlias: String? = nil
        let title: String
        let subtitle: String
        let image: String?
        var id: String {
            switch kind {
            case .episode: return "episode:\(alias)/\(episodeAlias ?? "")"
            default: return "\(kind.rawValue):\(alias)"
            }
        }
        var imageURL: URL? { image.flatMap { URL(string: $0) } }
    }

    @Published private(set) var items: [Item] = []

    private static let fileName = "saved.json"

    private init() {
        items = Cache.load([Item].self, from: Self.fileName) ?? []
    }

    func contains(_ kind: Item.Kind, _ alias: String) -> Bool {
        items.contains { $0.kind == kind && $0.alias == alias }
    }

    /// Same check, but by full identity — the only form that tells two
    /// episodes of the same show apart.
    func contains(_ item: Item) -> Bool {
        items.contains { $0.id == item.id }
    }

    /// Star or unstar, returning the new state. The whole list is rewritten on
    /// every change — it is a handful of rows, and a partial write is a corrupt file.
    @discardableResult
    func toggle(_ item: Item) -> Bool {
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: i)
            persist()
            unstarOnAccount(item)
            return false
        }
        items.insert(item, at: 0)
        persist()
        starOnAccount(item)
        return true
    }

    private func persist() { Cache.save(items, to: Self.fileName) }

    // MARK: The account's copy

    /// What the account holds, so an unstar knows which document to delete.
    /// Populated by `sync`; empty when signed out.
    private var remote: [String: NTSFavourites.Favourite] = [:]
    /// How the token is obtained. Set by `AppModel` at launch — `Saved` is a
    /// singleton built before auth exists, and passing the whole auth object in
    /// would tie a bookmark list to sign-in machinery it otherwise ignores.
    var token: (() async throws -> String)?

    /// True once a sync has actually read the account, so the UI can tell "no
    /// follows" from "not asked yet".
    @Published private(set) var syncedWithAccount = false

    /// Merge the account's follows and saved episodes into the local list, and
    /// register this Mac so stars written here are found by the same device
    /// lookup nts.live does.
    func sync() async {
        guard let token = try? await token?() else { return }
        try? await NTSFavourites.registerDevice(token: token)
        guard let favourites = try? await NTSFavourites.fetch(token: token) else { return }

        remote = Dictionary(favourites.map { f in
            let (show, episode) = Self.normalized(f)
            return (show + ":" + episode, f)
        }, uniquingKeysWith: { first, _ in first })
        syncedWithAccount = true

        var merged = items
        for favourite in favourites {
            let (showAlias, episodeAlias) = Self.normalized(favourite)
            if episodeAlias.isEmpty {
                guard !merged.contains(where: { $0.kind == .show && $0.alias == showAlias }) else { continue }
                let indexed = ShowIndex.shared.ref(showAlias)
                // The sitemap that seeds the show index carries no artwork — a
                // show only gets a picture once it turns up in a schedule, live,
                // or recently-added feed. A followed show that never has is
                // fetched here instead of staying blank forever.
                if let picture = indexed?.picture {
                    merged.append(Item(kind: .show, alias: showAlias,
                                       title: indexed?.name ?? ShowIndex.title(from: showAlias),
                                       subtitle: indexed?.location ?? "", image: picture))
                } else if let d = try? await NTSAPI.show(alias: showAlias) {
                    merged.append(Item(kind: .show, alias: showAlias, title: d.name,
                                       subtitle: d.location, image: d.image?.absoluteString))
                } else {
                    merged.append(Item(kind: .show, alias: showAlias,
                                       title: ShowIndex.title(from: showAlias), subtitle: "", image: nil))
                }
            } else {
                // Episodes carry no local index the way shows do, so each one
                // missing locally is fetched for its real title and artwork.
                let id = "episode:\(showAlias)/\(episodeAlias)"
                guard !merged.contains(where: { $0.id == id }) else { continue }
                if let detail = try? await NTSAPI.episode(show: showAlias, episode: episodeAlias) {
                    merged.append(Item(kind: .episode, alias: showAlias, episodeAlias: episodeAlias,
                                       title: detail.name, subtitle: detail.date,
                                       image: detail.image?.absoluteString))
                } else {
                    merged.append(Item(kind: .episode, alias: showAlias, episodeAlias: episodeAlias,
                                       title: ShowIndex.title(from: episodeAlias),
                                       subtitle: "", image: nil))
                }
            }
        }
        guard merged.count != items.count else { return }
        items = merged
        persist()
    }

    /// A favourite's aliases, correcting one thing nts.live's own client gets
    /// wrong: some episode favourites land with the full `<show>/episodes/<ep>`
    /// path jammed into `show_alias` and `episode_alias` left empty, rather than
    /// the two fields split the way every other row has them. Reading that
    /// literally makes an unopenable, unpicturable "show" with a slash in its
    /// alias; splitting it here reads it as the episode favourite it actually is.
    private static func normalized(_ f: NTSFavourites.Favourite) -> (show: String, episode: String) {
        if f.episodeAlias.isEmpty, let range = f.showAlias.range(of: "/episodes/") {
            let show = String(f.showAlias[..<range.lowerBound])
            let episode = String(f.showAlias[range.upperBound...])
            if !show.isEmpty, !episode.isEmpty { return (show, episode) }
        }
        return (f.showAlias, f.episodeAlias)
    }

    private func starOnAccount(_ item: Item) {
        // Mixtapes are this app's own idea of a bookmark; NTS files favourites
        // against shows and episodes only, so there is nowhere to put one.
        guard item.kind != .mixtape, let token else { return }
        Task {
            guard let token = try? await token() else { return }
            try? await NTSFavourites.add(showAlias: item.alias, episodeAlias: item.episodeAlias ?? "", token: token)
        }
    }

    private func unstarOnAccount(_ item: Item) {
        let key = item.alias + ":" + (item.episodeAlias ?? "")
        guard item.kind != .mixtape, let token, let favourite = remote[key] else { return }
        remote[key] = nil
        Task {
            guard let token = try? await token() else { return }
            try? await NTSFavourites.remove(name: favourite.name, token: token)
        }
    }
}
