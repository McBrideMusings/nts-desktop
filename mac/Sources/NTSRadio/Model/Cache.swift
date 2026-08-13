import Foundation

/// Single owner of on-disk persistence for the app:
///  - the shared `URLCache` that backs remote cover/icon/program images
///    (so they survive relaunches and work offline), and
///  - the mixtape feed JSON, cached in Application Support so the dial paints
///    instantly / offline before the live refresh lands.
enum Cache {
    /// Size the shared URLCache for disk-backed image caching. Call once at launch.
    static func configureImageCache() {
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
    }

    /// Application Support/NTSRadio/<name> — the one place the app writes.
    static func file(_ name: String) -> URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NTSRadio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    /// Decode a JSON file written by `save`, or nil if absent/unreadable/stale in
    /// shape. Every caller treats a nil as "no cache yet", never as an error.
    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: file(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: file(name))
    }

    private static var feedURL: URL { file("mixtapes.json") }

    /// The last-saved mixtape feed, or [] if none / unreadable.
    static func loadFeed() -> [NTSAPI.MixtapeFeed] {
        guard let data = try? Data(contentsOf: feedURL),
              let feed = try? JSONDecoder().decode([NTSAPI.MixtapeFeed].self, from: data)
        else { return [] }
        return feed
    }

    static func saveFeed(_ feed: [NTSAPI.MixtapeFeed]) {
        guard let data = try? JSONEncoder().encode(feed) else { return }
        try? data.write(to: feedURL)
    }
}
