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
        enum Kind: String, Codable { case show, mixtape }
        let kind: Kind
        let alias: String
        let title: String
        let subtitle: String
        let image: String?
        var id: String { "\(kind.rawValue):\(alias)" }
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

    /// Merge the account's follows into the local list, and register this Mac so
    /// stars written here are found by the same device lookup nts.live does.
    ///
    /// Only shows are merged in. The account also holds saved *episodes*, which
    /// this list has no row type for yet — they are counted, not dropped, so the
    /// gap is visible rather than silent.
    func sync() async {
        guard let token = try? await token?() else { return }
        try? await NTSFavourites.registerDevice(token: token)
        guard let favourites = try? await NTSFavourites.fetch(token: token) else { return }

        remote = Dictionary(favourites.map { ($0.showAlias + ":" + $0.episodeAlias, $0) },
                            uniquingKeysWith: { first, _ in first })
        syncedWithAccount = true

        var merged = items
        for favourite in favourites where !favourite.isEpisode {
            guard !merged.contains(where: { $0.kind == .show && $0.alias == favourite.showAlias })
            else { continue }
            let indexed = ShowIndex.shared.ref(favourite.showAlias)
            merged.append(Item(kind: .show,
                               alias: favourite.showAlias,
                               title: indexed?.name ?? ShowIndex.title(from: favourite.showAlias),
                               subtitle: indexed?.location ?? "",
                               image: indexed?.picture))
        }
        guard merged.count != items.count else { return }
        items = merged
        persist()
    }

    /// How many of the account's favourites are episodes — rows this list can't
    /// hold yet. Shown rather than hidden.
    var accountEpisodeCount: Int { remote.values.filter(\.isEpisode).count }

    private func starOnAccount(_ item: Item) {
        // Mixtapes are this app's own idea of a bookmark; NTS files favourites
        // against shows and episodes only, so there is nowhere to put one.
        guard item.kind == .show, let token else { return }
        Task {
            guard let token = try? await token() else { return }
            try? await NTSFavourites.add(showAlias: item.alias, token: token)
        }
    }

    private func unstarOnAccount(_ item: Item) {
        guard item.kind == .show, let token,
              let favourite = remote[item.alias + ":"] else { return }
        remote[item.alias + ":"] = nil
        Task {
            guard let token = try? await token() else { return }
            try? await NTSFavourites.remove(name: favourite.name, token: token)
        }
    }
}
