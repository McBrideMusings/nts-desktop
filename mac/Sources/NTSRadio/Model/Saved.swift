import Foundation
import Combine

/// What the user has starred, stored on this Mac.
///
/// NTS exposes no favourites API — `/api/v2/users/me`, `/api/v2/favourites` and
/// `/api/v2/users/me/favourites` all answer HTTP 400, signed in or not — so there
/// is nothing to sync with. Bookmarks live in Application Support and stay local.
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
            return false
        }
        items.insert(item, at: 0)
        persist()
        return true
    }

    private func persist() { Cache.save(items, to: Self.fileName) }
}
