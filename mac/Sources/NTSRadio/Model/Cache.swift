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

    private static var feedURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NTSRadio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mixtapes.json")
    }

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
