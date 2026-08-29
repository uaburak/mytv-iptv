import Foundation
import Observation

/// Favoriler, izleme listesi ve "izlemeyi sürdür" kayıtları.
/// Cihazda anında yazılır, oturum açıksa Firestore'a da aktarılır.
///
/// Favori ve izleme listesi yalnızca **içerik kimliği** olarak tutuluyor;
/// içeriğin başlığı, afişi ve künyesi sağlayıcının kendi verisi ve katalogdan
/// çözülüyor. Böylece hem bulutta gereksiz veri kopyası oluşmuyor hem de
/// sağlayıcı içeriği güncellediğinde eski kopyada takılı kalınmıyor.
@MainActor
@Observable
final class UserActivityStore {
    private(set) var favoriteIDs: [MediaID] = []
    private(set) var watchlistIDs: [MediaID] = []
    private(set) var progress: [PlaybackProgress] = []

    private let store = LocalStore(folder: "activity")
    private let favoritesKey = "favorites"
    private let watchlistKey = "watchlist"
    private let progressKey = "progress"

    /// Firestore'a yazma işini üstlenen kapan; oturum açılınca bağlanır.
    var onChange: ((
        _ favorites: [MediaID],
        _ watchlist: [MediaID],
        _ progress: [PlaybackProgress]
    ) -> Void)?

    init() {
        favoriteIDs = Self.readIDs(store: store, key: favoritesKey)
        watchlistIDs = Self.readIDs(store: store, key: watchlistKey)
        progress = store.read([PlaybackProgress].self, key: progressKey) ?? []
    }

    /// Eski sürümler tam `MediaItem` yazıyordu. Yeni biçim okunamazsa eski
    /// biçim denenip kimliğe indirgeniyor; kullanıcı favorilerini kaybetmiyor.
    private static func readIDs(store: LocalStore, key: String) -> [MediaID] {
        if let ids = store.read([MediaID].self, key: key) { return ids }
        return store.read([MediaItem].self, key: key)?.map(\.id) ?? []
    }

    // MARK: - Favoriler

    func isFavorite(_ item: MediaItem) -> Bool { favoriteIDs.contains(item.id) }

    func toggleFavorite(_ item: MediaItem) {
        if let index = favoriteIDs.firstIndex(of: item.id) {
            favoriteIDs.remove(at: index)
        } else {
            favoriteIDs.insert(item.id, at: 0)
        }
        persist()
    }

    // MARK: - İzleme Listesi (Watchlist)

    func isInWatchlist(_ item: MediaItem) -> Bool { watchlistIDs.contains(item.id) }

    func toggleWatchlist(_ item: MediaItem) {
        if let index = watchlistIDs.firstIndex(of: item.id) {
            watchlistIDs.remove(at: index)
        } else {
            watchlistIDs.insert(item.id, at: 0)
        }
        persist()
    }

    // MARK: - İzleme ilerlemesi

    /// Yarım kalan içerikler, en son izlenen başta.
    var continueWatching: [PlaybackProgress] {
        progress
            .filter { !$0.isFinished && $0.positionSeconds > 60 }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func progress(for mediaID: MediaID, episodeID: String? = nil) -> PlaybackProgress? {
        progress.first { $0.mediaID == mediaID && $0.episodeID == episodeID }
    }

    func record(mediaID: MediaID, episodeID: String?, position: Double, duration: Double) {
        // Canlı yayında ilerleme kaydı anlamsız.
        guard mediaID.kind != .live, duration > 0 else { return }

        let identifier = [mediaID.description, episodeID].compactMap { $0 }.joined(separator: "#")
        let entry = PlaybackProgress(
            id: identifier,
            mediaID: mediaID,
            episodeID: episodeID,
            positionSeconds: position,
            durationSeconds: duration,
            updatedAt: .now
        )
        progress.removeAll { $0.id == identifier }
        progress.insert(entry, at: 0)
        // Geçmişi sınırla; senkronda gereksiz yük olmasın.
        if progress.count > 100 { progress.removeLast(progress.count - 100) }
        persist()
    }

    func clearProgress(for mediaID: MediaID) {
        progress.removeAll { $0.mediaID == mediaID }
        persist()
    }

    func merge(
        favorites remoteFavorites: [MediaID],
        watchlist remoteWatchlist: [MediaID],
        progress remoteProgress: [PlaybackProgress]
    ) {
        favoriteIDs = Self.union(favoriteIDs, remoteFavorites)
        watchlistIDs = Self.union(watchlistIDs, remoteWatchlist)

        // Aynı içerik iki cihazda izlendiyse en yeni kayıt kazanır.
        var mergedProgress = Dictionary(progress.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in remoteProgress {
            if let existing = mergedProgress[entry.id], existing.updatedAt >= entry.updatedAt { continue }
            mergedProgress[entry.id] = entry
        }
        progress = mergedProgress.values.sorted { $0.updatedAt > $1.updatedAt }
        persist()
    }

    /// Yereldekiler sırayı koruyor, uzaktakilerden eksikler sona ekleniyor.
    private static func union(_ local: [MediaID], _ remote: [MediaID]) -> [MediaID] {
        var merged = local
        let known = Set(local)
        for id in remote where !known.contains(id) {
            merged.append(id)
        }
        return merged
    }

    func clearAll() {
        favoriteIDs.removeAll()
        watchlistIDs.removeAll()
        progress.removeAll()
        store.removeAll()
    }

    private func persist() {
        store.write(favoriteIDs, key: favoritesKey)
        store.write(watchlistIDs, key: watchlistKey)
        store.write(progress, key: progressKey)
        onChange?(favoriteIDs, watchlistIDs, progress)
    }
}
