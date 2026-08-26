import Foundation

/// Fast Local Disk Cache for IPTV Metadata (Channels, Categories, Movies, Series).
/// Stores parsed metadata in Application Support directory per account.
public final class DiskCacheService: Sendable {
    public static let shared = DiskCacheService()

    private let fileManager = FileManager.default

    private init() {}

    private func getCacheDirectory(for accountId: String) -> URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("MyTVCache/\(accountId)", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Save to Disk

    public func saveMetadata(
        accountId: String,
        channels: [Channel],
        liveCategories: [MediaCategory],
        movies: [VODItem],
        vodCategories: [MediaCategory],
        series: [VODItem],
        seriesCategories: [MediaCategory]
    ) async {
        guard let dir = getCacheDirectory(for: accountId) else { return }

        let encoder = JSONEncoder()
        Task.detached(priority: .utility) {
            if let data = try? encoder.encode(channels) {
                try? data.write(to: dir.appendingPathComponent("channels.json"), options: .atomic)
            }
            if let data = try? encoder.encode(liveCategories) {
                try? data.write(to: dir.appendingPathComponent("live_categories.json"), options: .atomic)
            }
            if let data = try? encoder.encode(movies) {
                try? data.write(to: dir.appendingPathComponent("movies.json"), options: .atomic)
            }
            if let data = try? encoder.encode(vodCategories) {
                try? data.write(to: dir.appendingPathComponent("vod_categories.json"), options: .atomic)
            }
            if let data = try? encoder.encode(series) {
                try? data.write(to: dir.appendingPathComponent("series.json"), options: .atomic)
            }
            if let data = try? encoder.encode(seriesCategories) {
                try? data.write(to: dir.appendingPathComponent("series_categories.json"), options: .atomic)
            }
        }
    }

    // MARK: - Load from Disk

    public struct CachedMetadata {
        public let channels: [Channel]
        public let liveCategories: [MediaCategory]
        public let movies: [VODItem]
        public let vodCategories: [MediaCategory]
        public let series: [VODItem]
        public let seriesCategories: [MediaCategory]
    }

    public func loadMetadata(accountId: String) -> CachedMetadata? {
        guard let dir = getCacheDirectory(for: accountId) else { return nil }

        let decoder = JSONDecoder()

        let channelsUrl = dir.appendingPathComponent("channels.json")
        let liveCatsUrl = dir.appendingPathComponent("live_categories.json")
        let moviesUrl = dir.appendingPathComponent("movies.json")
        let vodCatsUrl = dir.appendingPathComponent("vod_categories.json")
        let seriesUrl = dir.appendingPathComponent("series.json")
        let seriesCatsUrl = dir.appendingPathComponent("series_categories.json")

        guard fileManager.fileExists(atPath: channelsUrl.path) || fileManager.fileExists(atPath: moviesUrl.path) else {
            return nil
        }

        let channels: [Channel] = (try? decoder.decode([Channel].self, from: Data(contentsOf: channelsUrl))) ?? []
        let liveCats: [MediaCategory] = (try? decoder.decode([MediaCategory].self, from: Data(contentsOf: liveCatsUrl))) ?? []
        let movies: [VODItem] = (try? decoder.decode([VODItem].self, from: Data(contentsOf: moviesUrl))) ?? []
        let vodCats: [MediaCategory] = (try? decoder.decode([MediaCategory].self, from: Data(contentsOf: vodCatsUrl))) ?? []
        let series: [VODItem] = (try? decoder.decode([VODItem].self, from: Data(contentsOf: seriesUrl))) ?? []
        let seriesCats: [MediaCategory] = (try? decoder.decode([MediaCategory].self, from: Data(contentsOf: seriesCatsUrl))) ?? []

        return CachedMetadata(
            channels: channels,
            liveCategories: liveCats,
            movies: movies,
            vodCategories: vodCats,
            series: series,
            seriesCategories: seriesCats
        )
    }

    // MARK: - Clear Cache

    public func clearCache(accountId: String) {
        guard let dir = getCacheDirectory(for: accountId) else { return }
        try? fileManager.removeItem(at: dir)
    }

    public func clearAllCaches() {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let root = appSupport.appendingPathComponent("MyTVCache")
        try? fileManager.removeItem(at: root)
    }
}
