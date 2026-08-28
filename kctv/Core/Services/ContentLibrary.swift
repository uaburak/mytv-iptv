import Foundation
import Observation

/// Anasayfadaki tek bir yatay ray.
struct ContentRow: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var subtitle: String?
    var kind: MediaKind
    var categoryID: String?
    var items: [MediaItem]
}

/// Arayüzün gördüğü tek veri kapısı.
/// Seçili listeye göre doğru `ContentProvider`'ı kurar, sonuçları diske
/// önbelleğe alır ve anasayfa raylarını üretir.
@MainActor
@Observable
final class ContentLibrary {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    /// Katalog ya da yükleme durumu değiştiğinde çağrılır.
    /// UIKit tarafı bunu bildirime çevirip listelerini yeniler.
    var onChange: (() -> Void)?

    private(set) var state: LoadState = .idle {
        didSet { onChange?() }
    }
    private(set) var account: ProviderAccount?
    private(set) var rows: [ContentRow] = []
    private(set) var categories: [MediaKind: [MediaCategory]] = [:]

    /// Aramanın tarayacağı düzleştirilmiş katalog.
    private(set) var catalog: [MediaKind: [MediaItem]] = [:]

    /// Anasayfanın öne çıkan içerikleri. Hesaplanmış özellik DEĞİL: katalog
    /// 14 binden fazla kayıt tutuyor ve her `body` değerlendirmesinde yeniden
    /// süzmek geçiş animasyonlarını kilitliyordu. Yalnızca katalog değişince
    /// üretiliyor.
    private(set) var spotlight: [MediaItem] = []

    /// Kimlik ve kategori aramalarını O(1) yapan indeksler.
    /// Bunlar olmadan her kart dokunuşu ve her detay açılışı tüm katalogda
    /// doğrusal tarama yapıyordu.
    private var itemsByID: [MediaID: MediaItem] = [:]
    private var itemsByCategory: [MediaKind: [String: [MediaItem]]] = [:]

    /// Detay yanıtları. Aynı içeriğe ikinci girişte ağ beklemesi olmasın diye.
    private var detailCache: [MediaID: MediaDetail] = [:]

    private var provider: (any ContentProvider)?
    private var currentPlaylistID: String?
    private let cache = LocalStore(folder: "catalog")
    private let activity: UserActivityStore
    /// Aynı anda birden fazla yenileme başlamasın.
    private var isReloading = false

    /// Anlık görüntü bundan eskiyse arka planda tazelenir.
    private let cacheLifetime: TimeInterval = 60 * 60 * 6

    init(activity: UserActivityStore) {
        self.activity = activity
    }

    var sourceID: String { provider?.sourceID ?? "" }

    // MARK: - Bağlanma

    func connect(to playlist: Playlist, secret: String?) async {
        do {
            provider = try Self.makeProvider(for: playlist, secret: secret)
            currentPlaylistID = playlist.id
            await reload()
        } catch {
            state = .failed((error as? ContentError)?.errorDescription ?? error.localizedDescription)
        }
    }

    nonisolated static func makeProvider(for playlist: Playlist, secret: String?) throws -> any ContentProvider {
        switch playlist.source {
        case let .xtream(host, username):
            guard let secret, !secret.isEmpty else { throw ContentError.invalidCredentials }
            return try XtreamProvider(host: host, username: username, password: secret, sourceID: playlist.id)
        case let .m3u(url):
            return M3UProvider(url: url, sourceID: playlist.id)
        }
    }

    // MARK: - Yükleme

    func reload(force: Bool = false) async {
        guard let provider, !isReloading else { return }
        isReloading = true
        defer { isReloading = false }

        // Sürüm eki: MediaItem alanları değiştiğinde eski anlık görüntüler
        // çözümlenemez, boşuna denenmesin.
        let cacheKey = (currentPlaylistID ?? provider.sourceID) + ".v3"
        let isCacheFresh = !force && (cache.age(key: cacheKey).map { $0 < cacheLifetime } ?? false)

        if !force, let snapshot = cachedSnapshot(key: cacheKey) {
            apply(snapshot)
            state = .ready
            // Önbellek tazeyse tek bir istek bile atmıyoruz. Yayın biçimi
            // sağlayıcıda kalıcı saklandığı için doğrulamaya da gerek yok.
            if isCacheFresh { return }
        } else {
            state = .loading
        }

        do {
            // Abonelik durumu ve sunucunun izin verdiği yayın biçimi burada.
            account = try await provider.validate()
            let snapshot = try await fetchSnapshot(from: provider)
            cache.write(snapshot, key: cacheKey)
            apply(snapshot)
            state = .ready
        } catch {
            let message = (error as? ContentError)?.errorDescription ?? error.localizedDescription
            // Önbellekten bir şey gösterebiliyorsak hatayı ekranı boşaltacak
            // şekilde değil, sessizce geçiyoruz.
            state = rows.isEmpty ? .failed(message) : .ready
        }
    }

    private func fetchSnapshot(from provider: any ContentProvider) async throws -> CatalogSnapshot {
        var snapshot = CatalogSnapshot()

        // Üç türü paralel çekiyoruz; canlı liste genelde en büyüğü.
        try await withThrowingTaskGroup(of: (MediaKind, [MediaCategory], [MediaItem]).self) { group in
            for kind in MediaKind.allCases {
                group.addTask {
                    async let categories = provider.categories(for: kind)
                    async let items = provider.items(kind: kind, categoryID: nil)
                    return try await (kind, categories, items)
                }
            }
            for try await (kind, categories, items) in group {
                snapshot.categories[kind] = categories
                snapshot.items[kind] = items
            }
        }
        return snapshot
    }

    private func cachedSnapshot(key: String) -> CatalogSnapshot? {
        cache.read(CatalogSnapshot.self, key: key)
    }

    private func apply(_ snapshot: CatalogSnapshot) {
        categories = snapshot.categories
        catalog = snapshot.items
        buildIndexes()
        rows = buildRows(from: snapshot)
        spotlight = buildSpotlight()
        notifyChange()
    }

    private func buildIndexes() {
        var byID: [MediaID: MediaItem] = [:]
        var byCategory: [MediaKind: [String: [MediaItem]]] = [:]

        byID.reserveCapacity(catalog.values.reduce(0) { $0 + $1.count })
        for (kind, items) in catalog {
            var grouped: [String: [MediaItem]] = [:]
            for item in items {
                byID[item.id] = item
                if let categoryID = item.categoryID {
                    grouped[categoryID, default: []].append(item)
                }
            }
            byCategory[kind] = grouped
        }

        itemsByID = byID
        itemsByCategory = byCategory
    }

    /// Anasayfa raylarının ve katalogların yeniden çizilmesi gerektiğini bildirir.
    private func notifyChange() { onChange?() }

    // MARK: - Anasayfa rayları

    private func buildRows(from snapshot: CatalogSnapshot) -> [ContentRow] {
        var rows: [ContentRow] = []

        // 1) Yeni eklenenler — sağlayıcı `added` alanını dolduruyorsa anlamlı.
        let recentMovies = (snapshot.items[.movie] ?? [])
            .filter { $0.addedAt != nil }
            .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
            .prefix(20)
        if recentMovies.count >= 4 {
            rows.append(ContentRow(
                id: "recent-movies",
                title: "Yeni Eklenen Filmler",
                subtitle: nil,
                kind: .movie,
                categoryID: nil,
                items: Array(recentMovies)
            ))
        }

        let recentSeries = (snapshot.items[.series] ?? [])
            .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
            .prefix(20)
        if recentSeries.count >= 4 {
            rows.append(ContentRow(
                id: "recent-series",
                title: "Yeni Diziler",
                subtitle: nil,
                kind: .series,
                categoryID: nil,
                items: Array(recentSeries)
            ))
        }

        // 2) Kategori rayları — her türden dolu olan ilk kategoriler.
        for kind in [MediaKind.movie, .series, .live] {
            let items = snapshot.items[kind] ?? []
            guard !items.isEmpty else { continue }
            let grouped = itemsByCategory[kind] ?? [:]

            let categories = (snapshot.categories[kind] ?? [])
                .filter { (grouped[$0.id]?.count ?? 0) >= 4 }
                .prefix(kind == .live ? 3 : 6)

            for category in categories {
                guard let categoryItems = grouped[category.id] else { continue }
                rows.append(ContentRow(
                    id: "\(kind.rawValue)-\(category.id)",
                    title: category.name,
                    subtitle: nil,
                    kind: kind,
                    categoryID: category.id,
                    items: Array(categoryItems.prefix(24))
                ))
            }
        }

        return rows
    }

    /// Hero banner içeriği: görseli olan, en yüksek puanlı film ve diziler.
    /// Aday havuzu baştan sınırlanıyor; tüm katalogu süzüp sonra kırpmak
    /// on binlerce kaydın gereksiz kopyalanması demekti.
    private func buildSpotlight() -> [MediaItem] {
        func candidates(_ kind: MediaKind, limit: Int) -> [MediaItem] {
            var picked: [MediaItem] = []
            picked.reserveCapacity(limit)
            for item in catalog[kind] ?? [] where item.backdropURL != nil || item.posterURL != nil {
                picked.append(item)
                if picked.count == limit { break }
            }
            return picked
        }

        let pool = candidates(.movie, limit: 40) + candidates(.series, limit: 20)
        return Array(pool.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }.prefix(8))
    }

    /// İzleme kayıtlarını katalogdaki gerçek içerikle eşleştirir.
    var continueWatching: [(progress: PlaybackProgress, item: MediaItem)] {
        activity.continueWatching.compactMap { entry in
            guard let item = item(for: entry.mediaID) else { return nil }
            return (entry, item)
        }
    }

    func item(for id: MediaID) -> MediaItem? {
        itemsByID[id]
    }

    func items(kind: MediaKind, categoryID: String?) -> [MediaItem] {
        guard let categoryID else { return catalog[kind] ?? [] }
        return itemsByCategory[kind]?[categoryID] ?? []
    }

    /// Detay ekranındaki "Benzer İçerikler". Gövde içinde süzmek yerine
    /// indeksten okunup burada bir kez hazırlanıyor.
    func related(to item: MediaItem, limit: Int = 20) -> [MediaItem] {
        guard let categoryID = item.categoryID else { return [] }
        let siblings = itemsByCategory[item.kind]?[categoryID] ?? []
        var result: [MediaItem] = []
        result.reserveCapacity(limit)
        for candidate in siblings where candidate.id != item.id {
            result.append(candidate)
            if result.count == limit { break }
        }
        return result
    }

    // MARK: - Detay & oynatma

    /// Önbellekte hazır detay varsa ağ beklemeden döner.
    func cachedDetail(for item: MediaItem) -> MediaDetail? {
        detailCache[item.id]
    }

    func detail(for item: MediaItem) async throws -> MediaDetail {
        if let cached = detailCache[item.id] { return cached }
        guard let provider else { return MediaDetail(item: item) }
        let result = try await provider.detail(for: item)
        detailCache[item.id] = result
        if detailCache.count > 250 {
            let keysToRemove = Array(detailCache.keys.prefix(50))
            for key in keysToRemove { detailCache.removeValue(forKey: key) }
        }
        return result
    }

    func epg(for item: MediaItem) async -> [EPGEntry] {
        guard let provider else { return [] }
        return (try? await provider.shortEPG(for: item)) ?? []
    }

    func playback(for item: MediaItem) async throws -> PlaybackContext {
        guard let provider else { throw ContentError.unsupported(item.title) }
        let resume = activity.progress(for: item.id)
        return PlaybackContext(
            id: item.id.description,
            url: try await provider.playbackURL(for: item),
            title: item.title,
            subtitle: item.categoryName ?? item.genres.first,
            artworkURL: item.posterURL,
            kind: item.kind,
            startAt: resume.flatMap { $0.isFinished ? nil : $0.positionSeconds }
        )
    }

    func playback(for episode: Episode, in series: MediaItem) async throws -> PlaybackContext {
        guard let provider else { throw ContentError.unsupported(episode.title) }
        let resume = activity.progress(for: series.id, episodeID: episode.id)
        return PlaybackContext(
            id: "\(series.id.description)#\(episode.id)",
            url: try await provider.playbackURL(for: episode),
            title: series.title,
            subtitle: "\(episode.numberText) · \(episode.title)",
            artworkURL: episode.stillURL ?? series.posterURL,
            kind: .series,
            startAt: resume.flatMap { $0.isFinished ? nil : $0.positionSeconds }
        )
    }

    // MARK: - Arama

    func search(_ query: String, kinds: Set<MediaKind> = Set(MediaKind.allCases), limit: Int = 60) -> [MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var results: [MediaItem] = []
        for kind in MediaKind.allCases where kinds.contains(kind) {
            let matches = (catalog[kind] ?? []).filter {
                $0.title.localizedCaseInsensitiveContains(trimmed)
            }
            results.append(contentsOf: matches.prefix(limit))
        }
        // Baştan eşleşenler daha alakalı.
        return results.sorted { lhs, rhs in
            let lhsPrefix = lhs.title.lowercased().hasPrefix(trimmed.lowercased())
            let rhsPrefix = rhs.title.lowercased().hasPrefix(trimmed.lowercased())
            if lhsPrefix != rhsPrefix { return lhsPrefix }
            return lhs.title.count < rhs.title.count
        }
    }

    func reset() {
        provider = nil
        currentPlaylistID = nil
        account = nil
        rows = []
        categories = [:]
        catalog = [:]
        spotlight = []
        itemsByID = [:]
        itemsByCategory = [:]
        detailCache = [:]
        state = .idle
        notifyChange()
    }
}

/// Diske yazılan katalog anlık görüntüsü.
struct CatalogSnapshot: Codable, Sendable {
    var categories: [MediaKind: [MediaCategory]] = [:]
    var items: [MediaKind: [MediaItem]] = [:]
}
