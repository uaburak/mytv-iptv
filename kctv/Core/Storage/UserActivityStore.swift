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
    /// Kullanıcının kendi kanal listeleri. Şimdilik yalnızca bu cihazda:
    /// buluta yazılan üçlüye (favori, izleme listesi, ilerleme) dahil değil.
    private(set) var channelLists: [ChannelList] = []

    private let store = LocalStore(folder: "activity")
    private let favoritesKey = "favorites"
    private let watchlistKey = "watchlist"
    private let progressKey = "progress"
    private let channelListsKey = "channelLists"

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
        channelLists = store.read([ChannelList].self, key: channelListsKey) ?? []
    }

    /// Eski sürümler tam `MediaItem` yazıyordu. Yeni biçim okunamazsa eski
    /// biçim denenip kimliğe indirgeniyor; kullanıcı favorilerini kaybetmiyor.
    private static func readIDs(store: LocalStore, key: String) -> [MediaID] {
        if let ids = store.read([MediaID].self, key: key) { return ids }
        return store.read([MediaItem].self, key: key)?.map(\.id) ?? []
    }

    // MARK: - Favoriler

    func isFavorite(_ item: MediaItem) -> Bool { favoriteIDs.contains(item.id) }
    func isFavorite(id: MediaID) -> Bool { favoriteIDs.contains(id) }

    func toggleFavorite(_ item: MediaItem) {
        if let index = favoriteIDs.firstIndex(of: item.id) {
            favoriteIDs.remove(at: index)
        } else {
            favoriteIDs.insert(item.id, at: 0)
        }
        persist()
    }

    func setFavorites(_ ids: [MediaID]) {
        favoriteIDs = ids
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

    // MARK: - Kanal listeleri

    @discardableResult
    func createChannelList(named name: String) -> ChannelList {
        let list = ChannelList(id: UUID().uuidString, name: name)
        channelLists.append(list)
        persist()
        return list
    }

    func renameChannelList(id: String, to name: String) {
        guard let index = channelLists.firstIndex(where: { $0.id == id }) else { return }
        channelLists[index].name = name
        persist()
    }

    func deleteChannelList(id: String) {
        channelLists.removeAll { $0.id == id }
        persist()
    }

    func channelIDs(inList id: String) -> [MediaID] {
        channelLists.first { $0.id == id }?.channelIDs ?? []
    }

    func isChannel(_ item: MediaItem, inList id: String) -> Bool {
        channelLists.first { $0.id == id }?.channelIDs.contains(item.id) ?? false
    }

    /// Listede varsa çıkarıyor, yoksa **başa** ekliyor — en son eklenen kanal
    /// listenin başında duruyor, favorilerdeki davranışın aynısı.
    func toggleChannel(_ item: MediaItem, inList id: String) {
        guard let index = channelLists.firstIndex(where: { $0.id == id }) else { return }
        if let existing = channelLists[index].channelIDs.firstIndex(of: item.id) {
            channelLists[index].channelIDs.remove(at: existing)
        } else {
            channelLists[index].channelIDs.insert(item.id, at: 0)
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

    /// Bir içeriğin en son kaydı, bölümü fark etmeksizin.
    ///
    /// Dizide kayıt bölüm başına tutuluyor; "izlemeye devam et" rayı ve detay
    /// ekranı hangi bölümde kalındığını bilmeden en yenisini soruyor.
    func latestProgress(for mediaID: MediaID) -> PlaybackProgress? {
        progress
            .filter { $0.mediaID == mediaID }
            .max { $0.updatedAt < $1.updatedAt }
    }

    func record(
        mediaID: MediaID,
        episodeID: String?,
        episodeLabel: String? = nil,
        position: Double,
        duration: Double
    ) {
        // Canlı yayında ilerleme kaydı anlamsız.
        guard mediaID.kind != .live, duration > 0 else { return }

        let identifier = [mediaID.description, episodeID].compactMap { $0 }.joined(separator: "#")
        let entry = PlaybackProgress(
            id: identifier,
            mediaID: mediaID,
            episodeID: episodeID,
            episodeLabel: episodeLabel,
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
        channelLists.removeAll()
        store.removeAll()
    }

    private func persist() {
        store.write(favoriteIDs, key: favoritesKey)
        store.write(watchlistIDs, key: watchlistKey)
        store.write(progress, key: progressKey)
        store.write(channelLists, key: channelListsKey)
        onChange?(favoriteIDs, watchlistIDs, progress)
    }
}
