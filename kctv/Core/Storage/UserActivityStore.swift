import Foundation
import Observation

/// Favoriler ve "izlemeyi sürdür" kayıtları.
/// Cihazda anında yazılır, oturum açıksa Firestore'a da aktarılır.
@MainActor
@Observable
final class UserActivityStore {
    private(set) var favorites: [MediaItem] = []
    private(set) var progress: [PlaybackProgress] = []

    private let store = LocalStore(folder: "activity")
    private let favoritesKey = "favorites"
    private let progressKey = "progress"

    /// Firestore'a yazma işini üstlenen kapan; oturum açılınca bağlanır.
    var onChange: ((_ favorites: [MediaItem], _ progress: [PlaybackProgress]) -> Void)?

    init() {
        favorites = store.read([MediaItem].self, key: favoritesKey) ?? []
        progress = store.read([PlaybackProgress].self, key: progressKey) ?? []
    }

    // MARK: - Favoriler

    func isFavorite(_ item: MediaItem) -> Bool {
        favorites.contains { $0.id == item.id }
    }

    func toggleFavorite(_ item: MediaItem) {
        if isFavorite(item) {
            favorites.removeAll { $0.id == item.id }
        } else {
            favorites.insert(item, at: 0)
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

    func merge(favorites remoteFavorites: [MediaItem], progress remoteProgress: [PlaybackProgress]) {
        var mergedFavorites = favorites
        for item in remoteFavorites where !mergedFavorites.contains(where: { $0.id == item.id }) {
            mergedFavorites.append(item)
        }
        favorites = mergedFavorites

        // Aynı içerik iki cihazda izlendiyse en yeni kayıt kazanır.
        var mergedProgress = Dictionary(progress.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in remoteProgress {
            if let existing = mergedProgress[entry.id], existing.updatedAt >= entry.updatedAt { continue }
            mergedProgress[entry.id] = entry
        }
        progress = mergedProgress.values.sorted { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func clearAll() {
        favorites.removeAll()
        progress.removeAll()
        store.removeAll()
    }

    private func persist() {
        store.write(favorites, key: favoritesKey)
        store.write(progress, key: progressKey)
        onChange?(favorites, progress)
    }
}
