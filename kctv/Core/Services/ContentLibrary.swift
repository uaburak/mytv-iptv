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

/// Tür başına çekim sonucu.
///
/// Dosya düzeyinde duruyor, `ContentLibrary` içinde değil: `@MainActor` bir
/// sınıfın içine yazılan tip izolasyonu miras alır ve görev grubunun
/// yalıtımsız kapanından kurulamazdı.
private struct KindPayload: Sendable {
    var kind: MediaKind
    var categories: [MediaCategory]
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

    /// Aramanın tarayacağı düzleştirilmiş katalog. Süzgeç uygulanmış hâli;
    /// süzülmemiş kaynak `rawSnapshot`'ta duruyor.
    private(set) var catalog: [MediaKind: [MediaItem]] = [:]

    /// Sağlayıcıdan geldiği hâliyle katalog. İçerik süzgeci tercihi
    /// değiştiğinde yeniden indirmek yerine bundan türetiyoruz.
    private var rawSnapshot = CatalogSnapshot()

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
    /// Yayın akışı hızla eskiyor; kısa ömürlü bellek önbelleği yetiyor.
    private var epgCache: [MediaID: (entries: [EPGEntry], fetchedAt: Date)] = [:]
    private static let epgCacheLifetime: TimeInterval = 300
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

        // Zorlanmış yenilemede sağlayıcının bellek içi anlık görüntüsü de
        // atılıyor; M3U sağlayıcısı listeyi bir kez indirip sakladığı için
        // bu olmadan "yenile" ağa hiç çıkmıyordu.
        if force { await provider.invalidate() }

        // Sürüm eki: MediaItem alanları değiştiğinde eski anlık görüntüler
        // çözümlenemez, boşuna denenmesin.
        let cacheKey = (currentPlaylistID ?? provider.sourceID) + ".v3"
        let isCacheFresh = !force && (cache.age(key: cacheKey).map { $0 < cacheLifetime } ?? false)

        if !force, let snapshot = await cachedSnapshot(key: cacheKey) {
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
            writeSnapshot(snapshot, key: cacheKey)
            apply(snapshot)
            state = .ready
        } catch {
            let message = (error as? ContentError)?.errorDescription ?? error.localizedDescription
            // Önbellekten bir şey gösterebiliyorsak hatayı ekranı boşaltacak
            // şekilde değil, sessizce geçiyoruz.
            state = rows.isEmpty ? .failed(message) : .ready
        }
    }

    /// Üç türü paralel çeker.
    ///
    /// Bir tür başarısız olduğunda diğerleri korunuyor: bazı paneller
    /// `get_series`'te 404 dönüyor ve bu, gelmiş olan film ve canlı listesini
    /// de çöpe atmak için sebep değil. Yalnızca **hiçbiri** gelmediğinde hata
    /// fırlatılıyor; orada sorun ağ ya da kimlik doğrulamadır ve önbellekteki
    /// eski katalog korunmalı.
    private func fetchSnapshot(from provider: any ContentProvider) async throws -> CatalogSnapshot {
        var snapshot = CatalogSnapshot()
        var failures = 0

        await withTaskGroup(of: KindPayload?.self) { group in
            for kind in MediaKind.allCases {
                group.addTask {
                    do {
                        async let categories = provider.categories(for: kind)
                        async let items = provider.items(kind: kind, categoryID: nil)
                        return try await KindPayload(kind: kind, categories: categories, items: items)
                    } catch {
                        return nil
                    }
                }
            }
            for await payload in group {
                guard let payload else {
                    failures += 1
                    continue
                }
                snapshot.categories[payload.kind] = payload.categories
                snapshot.items[payload.kind] = payload.items
            }
        }

        guard failures < MediaKind.allCases.count else { throw ContentError.emptyPlaylist }
        return snapshot
    }

    /// Anlık görüntü on binlerce kayıt; çözümlemesi de yazımı da ana
    /// aktörde yapılınca açılışta ve her yenilemede gözle görülür bir
    /// takılma oluyordu.
    private func cachedSnapshot(key: String) async -> CatalogSnapshot? {
        let cache = self.cache
        return await Task.detached(priority: .userInitiated) {
            cache.read(CatalogSnapshot.self, key: key)
        }.value
    }

    private func writeSnapshot(_ snapshot: CatalogSnapshot, key: String) {
        let cache = self.cache
        Task.detached(priority: .utility) {
            cache.write(snapshot, key: key)
        }
    }

    private func apply(_ snapshot: CatalogSnapshot) {
        rawSnapshot = snapshot
        applyContentFilter()
    }

    /// Süzgeci ham anlık görüntüye uygulayıp türetilen her şeyi yeniden kurar.
    /// Ayarlardaki tercih değiştiğinde de buraya geliniyor — yeniden indirme
    /// gerekmiyor.
    func applyContentFilter() {
        let visible = Self.filtered(rawSnapshot)
        categories = visible.categories
        catalog = visible.items
        buildIndexes()
        rows = buildRows(from: visible)
        spotlight = buildSpotlight()
        notifyChange()
    }

    /// Yetişkin içeriği ayıklar.
    ///
    /// Kategori sinyali addan güvenilir: IPTV listelerinde yetişkin yayınlar
    /// neredeyse her zaman kendi kategorisinde toplanıyor. Önce yetişkin
    /// kategoriler bulunuyor, sonra o kategorideki **bütün** yayınlar ile
    /// adından işaretlenmiş tekil yayınlar düşülüyor. Kategorinin kendisi de
    /// listeden çıkıyor ki gezinme ekranında boş bir başlık kalmasın.
    private nonisolated static func filtered(_ snapshot: CatalogSnapshot) -> CatalogSnapshot {
        guard AppSettings.hidesAdultContent else { return snapshot }

        var result = CatalogSnapshot()
        for kind in MediaKind.allCases {
            let categories = snapshot.categories[kind] ?? []
            let items = snapshot.items[kind] ?? []
            let adultCategoryIDs = Set(
                categories.lazy.filter { AdultContentFilter.looksAdult($0.name) }.map(\.id)
            )

            result.categories[kind] = adultCategoryIDs.isEmpty
                ? categories
                : categories.filter { !adultCategoryIDs.contains($0.id) }

            // Süzülecek bir şey yoksa dizi olduğu gibi geçiyor: on binlerce
            // kaydı boşuna kopyalamanın anlamı yok.
            let needsItemFilter = !adultCategoryIDs.isEmpty || items.contains(where: \.isAdult)
            result.items[kind] = needsItemFilter
                ? items.filter { item in
                    guard !item.isAdult else { return false }
                    guard let categoryID = item.categoryID else { return true }
                    return !adultCategoryIDs.contains(categoryID)
                }
                : items
        }
        return result
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
                title: L10n.newMovies,
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
                title: L10n.newSeries,
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

        // Katalogda aynı yayın iki kez bulunabiliyor (sağlayıcı listeleri
        // temiz değil); banner'da tekrar eden kayıt hem yanlış görünüyor hem
        // de diffable data source'u çökertiyor.
        var seen = Set<MediaID>()
        let pool = (candidates(.movie, limit: 40) + candidates(.series, limit: 20))
            .filter { seen.insert($0.id).inserted }
        return Array(pool.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }.prefix(8))
    }

    /// İzleme kayıtlarını katalogdaki gerçek içerikle eşleştirir.
    ///
    /// İçerik başına tek kayıt dönüyor. İlerleme dizilerde **bölüm bazında**
    /// tutuluyor: aynı dizinin iki bölümü yarım kalırsa iki kayıt oluşuyor ve
    /// ikisi de aynı diziye çözülüyordu. Rayda dizinin iki kez çıkması hem
    /// yanlış hem de diffable data source'u çökertiyordu ("supplied item
    /// identifiers are not unique"). `activity.continueWatching` en yeniden
    /// eskiye sıralı olduğu için ilk görülen kayıt en son izlenen bölüm oluyor.
    var continueWatching: [(progress: PlaybackProgress, item: MediaItem)] {
        var seen = Set<MediaID>()
        return activity.continueWatching.compactMap { entry in
            guard !seen.contains(entry.mediaID),
                  let item = item(for: entry.mediaID) else { return nil }
            seen.insert(entry.mediaID)
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

    /// Kanal başına ayrı bir ağ isteği; rehber ekranı yalnızca görünen
    /// satırlar için istiyor. Yanıt kısa ömürlü önbellekte tutuluyor ki
    /// listede ileri geri kaydırmak aynı isteği tekrarlamasın.
    func epg(for item: MediaItem) async -> [EPGEntry] {
        if let cached = epgCache[item.id], Date().timeIntervalSince(cached.fetchedAt) < Self.epgCacheLifetime {
            return cached.entries
        }
        guard let provider else { return [] }
        let entries = (try? await provider.shortEPG(for: item)) ?? []
        epgCache[item.id] = (entries, Date())
        // Önbellek sınırsız büyümesin; canlı listeler on binlerce kanal olabiliyor.
        if epgCache.count > 400 {
            for key in Array(epgCache.keys.prefix(200)) { epgCache.removeValue(forKey: key) }
        }
        return entries
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

    /// Katalogda başlığa göre arama.
    ///
    /// Tarama ana aktörde **değil**: 50 bin kanallık bir listede
    /// `localizedCaseInsensitiveContains` ile doğrusal tarama her tuş
    /// vuruşunda arayüzü kilitliyordu. Katalog `Sendable` bir değer olduğu
    /// için kopyası ucuza arka plana geçiyor.
    func search(
        _ query: String,
        kinds: Set<MediaKind> = Set(MediaKind.allCases),
        limit: Int = 60
    ) async -> [MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let catalog = self.catalog
        return await Task.detached(priority: .userInitiated) {
            Self.search(trimmed, in: catalog, kinds: kinds, limit: limit)
        }.value
    }

    private nonisolated static func search(
        _ trimmed: String,
        in catalog: [MediaKind: [MediaItem]],
        kinds: Set<MediaKind>,
        limit: Int
    ) -> [MediaItem] {
        // Eşleşmeler tür başına `limit`'te kesiliyor: önce hepsini toplayıp
        // sonra kırpmak, on binlerce kaydı boşuna kopyalamak demekti.
        var results: [MediaItem] = []
        for kind in MediaKind.allCases where kinds.contains(kind) {
            var matched = 0
            for item in catalog[kind] ?? []
            where item.title.localizedCaseInsensitiveContains(trimmed) {
                results.append(item)
                matched += 1
                if matched == limit { break }
            }
        }

        // Baştan eşleşenler daha alakalı. Kıyaslama içinde `lowercased()`
        // çağırmak aynı dizgeyi her karşılaştırmada yeniden üretiyordu;
        // bayrak sıralamadan önce bir kez hesaplanıyor.
        let needle = trimmed.lowercased()
        return results
            .map { (item: $0, matchesPrefix: $0.title.lowercased().hasPrefix(needle)) }
            .sorted { lhs, rhs in
                if lhs.matchesPrefix != rhs.matchesPrefix { return lhs.matchesPrefix }
                return lhs.item.title.count < rhs.item.title.count
            }
            .map { $0.item }
    }

    func reset() {
        provider = nil
        rawSnapshot = CatalogSnapshot()
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
