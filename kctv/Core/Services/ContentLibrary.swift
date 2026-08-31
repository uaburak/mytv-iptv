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

    /// Kimlik ve kategori aramalarını O(1) yapan indeksler.
    /// Bunlar olmadan her kart dokunuşu ve her detay açılışı tüm katalogda
    /// doğrusal tarama yapıyordu.
    private var itemsByID: [MediaID: MediaItem] = [:]
    private var itemsByCategory: [MediaKind: [String: [MediaItem]]] = [:]

    /// Seri ve öneri eşleştirmesinin indeksleri.
    ///
    /// Eskiden her koleksiyon parçası için katalogdaki on binlerce film
    /// baştan sona taranıyordu — sekiz parçalı bir seri sekiz tam tarama
    /// demekti ve detay ekranı gözle görülür biçimde takılıyordu. Üçü de
    /// katalog kurulurken bir kez hazırlanıyor, sorgular O(1).
    private var moviesByTMDBID: [Int: MediaItem] = [:]
    private var moviesByTitle: [String: [MediaItem]] = [:]
    private var moviesByLooseTitle: [String: [MediaItem]] = [:]

    /// Detay yanıtları. Aynı içeriğe ikinci girişte ağ beklemesi olmasın diye.
    private var detailCache: [MediaID: MediaDetail] = [:]

    private var provider: (any ContentProvider)?
    /// Bayat önbellekten sonra arkada süren tazeleme.
    private var refreshTask: Task<Void, Never>?
    private var currentPlaylistID: String?
    private let cache = LocalStore(folder: "catalog")
    /// Yayın akışı hızla eskiyor; kısa ömürlü bellek önbelleği yetiyor.
    private var epgCache: [MediaID: (entries: [EPGEntry], fetchedAt: Date)] = [:]
    private static let epgCacheLifetime: TimeInterval = 300
    private let activity: UserActivityStore
    /// Aynı anda birden fazla yenileme başlamasın.
    private var isReloading = false

    /// Banner seçimlerinin belleği. Katalog hazır olur olmaz ısıtılıyor;
    /// ekranlar açıldığında seçim çoktan yapılmış oluyor.
    let featured = FeaturedStore()

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
        refreshTask?.cancel()

        // Zorlanmış yenilemede sağlayıcının bellek içi anlık görüntüsü de
        // atılıyor; M3U sağlayıcısı listeyi bir kez indirip sakladığı için
        // bu olmadan "yenile" ağa hiç çıkmıyordu.
        if force { await provider.invalidate() }

        // Sürüm eki: MediaItem alanları değiştiğinde eski anlık görüntüler
        // çözümlenemez, boşuna denenmesin.
        // Sürüm eki bilerek yükseltildi: `MediaItem.tmdbID` artık liste
        // ucundan da geliyor ve eski anlık görüntülerde bu alan boş. Bir
        // kereye mahsus tam indirme, seri eşleştirmesinin tam çalışması için
        // gereken bedel.
        let cacheKey = (currentPlaylistID ?? provider.sourceID) + ".v4"
        let isCacheFresh = !force && (cache.age(key: cacheKey).map { $0 < cacheLifetime } ?? false)

        if !force, let snapshot = await cachedSnapshot(key: cacheKey) {
            apply(snapshot)
            state = .ready
            // Önbellek tazeyse tek bir istek bile atmıyoruz. Yayın biçimi
            // sağlayıcıda kalıcı saklandığı için doğrulamaya da gerek yok.
            if isCacheFresh { return }

            // Bayat önbellek: ekran zaten dolu, tazeleme arkada sürüyor.
            // Çağıran bunu beklemiyor — gösterilecek içerik varken ağ turunu
            // beklemek açılışı boş ekranla geciktirmek olurdu.
            refreshTask = Task { [weak self] in
                await self?.refresh(from: provider, cacheKey: cacheKey)
            }
            return
        }

        // Sürüm atlamasında ekran boş açılmasın: bir önceki biçimdeki anlık
        // görüntü varsa onunla açılıyor, taze veri arkada iniyor. Bu olmadan
        // güncellemeden sonraki ilk açılış tam bir indirme boyu bekliyordu.
        if !force, let legacy = await legacySnapshot() {
            apply(legacy)
            state = .ready
            refreshTask = Task { [weak self] in
                await self?.refresh(from: provider, cacheKey: cacheKey)
            }
            return
        }

        state = .loading
        await refresh(from: provider, cacheKey: cacheKey)
    }

    /// Önceki sürüm eklerinin anlık görüntüsü. Yalnızca ilk açılışı doldurmak
    /// için okunuyor; yerine tazesi geldiğinde bir daha bakılmıyor.
    private func legacySnapshot() async -> CatalogSnapshot? {
        let base = currentPlaylistID ?? sourceID
        for suffix in Self.legacyCacheSuffixes {
            if let snapshot = await cachedSnapshot(key: base + suffix) { return snapshot }
        }
        return nil
    }

    private static let legacyCacheSuffixes = [".v3", ".v2"]

    /// Sağlayıcıdan taze anlık görüntüyü çekip uygular.
    private func refresh(from provider: any ContentProvider, cacheKey: String) async {
        do {
            // Doğrulama ve katalog **birlikte** çekiliyor. Eskiden doğrulama
            // bitmeden liste isteği başlamıyordu; ikisi arasında bir tam ağ
            // turu boşa geçiyordu ve ilk açılış o kadar geç doluyordu.
            // Doğrulamanın sonucu (abonelik durumu, yayın biçimi) listeyi
            // çekmek için gerekmiyor.
            async let accountTask = provider.validate()
            async let snapshotTask = fetchSnapshot(from: provider)

            account = try await accountTask
            let snapshot = try await snapshotTask
            // Arkadaki tazeleme iptal edildiyse (liste değişti, çıkış yapıldı)
            // eldeki sonucu ekrana basmıyoruz.
            guard !Task.isCancelled else { return }
            writeSnapshot(snapshot, key: cacheKey)
            apply(snapshot)
            state = .ready
        } catch {
            guard !Task.isCancelled else { return }
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

        // Banner seçimi ve künye ön yüklemesi katalogla birlikte başlıyor:
        // kullanıcı Filmler/Diziler sayfasına vardığında iş bitmiş oluyor.
        featured.catalogDidChange(
            sourceKey: currentPlaylistID ?? sourceID,
            catalog: catalog,
            itemsByID: itemsByID
        )
        featured.prewarm()
        prefetchMetadataForVisibleRows()

        notifyChange()
    }

    /// Anasayfa raylarının başındaki içeriklerin TMDB künyesini önceden çeker.
    ///
    /// Kullanıcının ilk göreceği ve büyük olasılıkla ilk dokunacağı kartlar
    /// bunlar; detay ekranı açıldığında künye elde hazır oluyor ve ekran
    /// yer tutucuyla değil dolu açılıyor.
    private func prefetchMetadataForVisibleRows() {
        guard TMDBService.isConfigured else { return }
        var candidates: [MediaItem] = []
        for row in rows.prefix(4) where row.kind != .live {
            candidates.append(contentsOf: row.items.prefix(8))
        }
        guard !candidates.isEmpty else { return }
        TMDBService.shared.prefetchMetadata(for: candidates)
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
        var byTMDBID: [Int: MediaItem] = [:]
        var byTitle: [String: [MediaItem]] = [:]
        var byLooseTitle: [String: [MediaItem]] = [:]

        byID.reserveCapacity(catalog.values.reduce(0) { $0 + $1.count })
        for (kind, items) in catalog {
            var grouped: [String: [MediaItem]] = [:]
            for item in items {
                byID[item.id] = item
                if let categoryID = item.categoryID {
                    grouped[categoryID, default: []].append(item)
                }
                guard kind == .movie else { continue }
                if let tmdbID = item.tmdbID, byTMDBID[tmdbID] == nil {
                    byTMDBID[tmdbID] = item
                }
                let key = Self.titleKey(item.title)
                guard !key.isEmpty else { continue }
                byTitle[key, default: []].append(item)
                let loose = Self.looseTitleKey(item.title)
                if loose != key, !loose.isEmpty {
                    byLooseTitle[loose, default: []].append(item)
                }
            }
            byCategory[kind] = grouped
        }

        itemsByID = byID
        itemsByCategory = byCategory
        moviesByTMDBID = byTMDBID
        moviesByTitle = byTitle
        moviesByLooseTitle = byLooseTitle
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

    /// Canlı kanallar, IPTV kullanıcısının beklediği sırayla: kanal numarası,
    /// numarası olmayanlar alfabetik olarak sona. Rehber de oynatıcının kanal
    /// çekmecesi de aynı sırayı gösteriyor.
    func liveChannels() -> [MediaItem] {
        items(kind: .live, categoryID: nil).sorted { first, second in
            switch (first.channelNumber, second.channelNumber) {
            case let (lhs?, rhs?): lhs < rhs
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
            }
        }
    }

    // MARK: - Seri filmler (TMDB koleksiyonları)

    /// TMDB koleksiyonunun parçalarını kullanıcının kataloğuyla eşleştirir.
    ///
    /// Eşleştirme tamamen TMDB verisi üzerinden yürüyor; uygulamada seri
    /// listesi, çeviri sözlüğü ya da başlık kalıbı gömülü değil:
    ///
    /// 1. **TMDB kimliği.** Sağlayıcı `tmdb_id` gönderiyorsa (Xtream
    ///    panellerinin çoğu gönderiyor) eşleşme birebir ve yanılma payı yok.
    /// 2. **Başlık.** Koleksiyon iki dilde birden çekildiği için her parçanın
    ///    Türkçe, İngilizce ve orijinal adı elde. Sağlayıcı hangisini yazmış
    ///    olursa olsun normalize edilmiş biçimi tutuyor.
    /// 3. **Yıl destekli gevşek başlık.** Sondaki sıra numarası/rakam atılmış
    ///    biçim, yalnızca yayın yılı da tutuyorsa kabul ediliyor.
    ///
    /// Katalogda karşılığı bulunamayan parçalar da listeleniyor — seri eksiksiz
    /// görünüyor, listede olmayan filme dokunulduğunda uyarı çıkıyor.
    func matchFranchiseEntries(parts: [TMDBCollectionPart], for item: MediaItem) -> [FranchiseEntry] {
        // Tek parçalı bir "koleksiyon" seri değil: TMDB kimi filmi tek başına
        // bir koleksiyona koyuyor ve ekranda yalnızca filmin kendisini taşıyan
        // bir "Seri Filmler" rayı çıkıyordu.
        guard item.kind == .movie, parts.count >= 2 else { return [] }

        var entries: [FranchiseEntry] = []
        var usedCatalogIDs: Set<MediaID> = [item.id]

        for part in parts {
            // Filmin kendisi rayda tekrar etmiyor: ray "serinin diğer
            // filmleri" demek. Bu kontrol başta yapılmazsa parça katalogda
            // eşleşemiyor (kendisi zaten dışlanmış) ve TMDB verisiyle sanal
            // bir kart olarak yeniden çiziliyordu.
            guard !isSameTitle(part, as: item) else { continue }

            let match = catalogMatch(for: part, excluding: usedCatalogIDs)
            if let match { usedCatalogIDs.insert(match.id) }

            entries.append(
                FranchiseEntry(
                    id: match.map { $0.id.description } ?? "tmdb-\(part.id)",
                    title: match?.title ?? part.title,
                    originalTitle: part.originalTitle,
                    year: match?.year ?? part.releaseYear.flatMap(Int.init),
                    releaseDate: part.releaseDate,
                    // Görsel tercihen TMDB'den: sağlayıcı afişleri tutarsız ve
                    // rayda yan yana duran kartların birbirini tutması gerekiyor.
                    posterURL: part.posterURL ?? match?.posterURL,
                    backdropURL: part.backdropURL ?? match?.backdropURL,
                    overview: part.overview ?? match?.plot,
                    tmdbID: part.id,
                    localItem: match
                )
            )
        }
        return entries
    }

    /// Parça, detayı açık olan filmin kendisi mi.
    ///
    /// Sağlayıcı TMDB kimliği veriyorsa kimlik son söz: aynı serideki farklı
    /// filmler benzer adlar taşıyabiliyor. Kimlik yoksa başlık varyantlarına
    /// bakılıyor.
    private func isSameTitle(_ part: TMDBCollectionPart, as item: MediaItem) -> Bool {
        if let tmdbID = item.tmdbID { return tmdbID == part.id }
        let itemKey = Self.titleKey(item.title)
        guard !itemKey.isEmpty else { return false }
        return part.titleVariants.contains { Self.titleKey($0) == itemKey }
    }

    /// Bir koleksiyon parçasının katalogdaki karşılığı.
    private func catalogMatch(for part: TMDBCollectionPart, excluding used: Set<MediaID>) -> MediaItem? {
        if let byID = moviesByTMDBID[part.id], !used.contains(byID.id) { return byID }

        let partYear = part.releaseYear.flatMap(Int.init)

        // 1) Tam başlık — üç dil varyantının herhangi biri.
        for variant in part.titleVariants {
            let key = Self.titleKey(variant)
            guard !key.isEmpty, let candidates = moviesByTitle[key] else { continue }
            if let exact = candidates.first(where: { !used.contains($0.id) && $0.year == partYear }) {
                return exact
            }
            if let any = candidates.first(where: { !used.contains($0.id) }) { return any }
        }

        // 2) Sondaki sıra numarası atılmış biçim — yalnızca yıl da tutuyorsa.
        // "Thor 2: Karanlık Dünya" ile "Thor: Karanlık Dünya" gibi sağlayıcı
        // farklarını kapatıyor, alakasız filmleri seriye sokmuyor.
        guard let partYear else { return nil }
        for variant in part.titleVariants {
            let key = Self.looseTitleKey(variant)
            guard !key.isEmpty, let candidates = moviesByLooseTitle[key] else { continue }
            if let match = candidates.first(where: { !used.contains($0.id) && $0.year == partYear }) {
                return match
            }
        }
        return nil
    }

    /// Seri filmleri. TMDB koleksiyonu yoksa seri de yok.
    func franchiseEntries(for item: MediaItem, tmdb: TMDBMetadata? = nil) -> [FranchiseEntry] {
        guard let tmdb else { return [] }
        return matchFranchiseEntries(parts: tmdb.collectionParts, for: item)
    }

    /// Yalnızca kullanıcının listesinde var olan seri filmlerini döner.
    func franchise(for item: MediaItem, tmdb: TMDBMetadata? = nil) -> [MediaItem] {
        franchiseEntries(for: item, tmdb: tmdb)
            .compactMap(\.localItem)
            .filter { $0.id != item.id }
    }

    // MARK: - Öneriler

    /// Detay ekranının altındaki "Önerilen İçerikler".
    ///
    /// Sıra: TMDB'nin kendi öneri/benzer listesi → aynı yönetmen ve oyuncular
    /// → aynı kategori → katalogun kalanı. Serinin filmleri buraya girmiyor;
    /// onlar üstte kendi rayında duruyor.
    ///
    /// Daha önce burada elle yazılmış "sinematik evren" kümeleri vardı: Marvel,
    /// DC, John Wick benzeri listeler ve bunları yakalayan düzenli ifadeler.
    /// Kapsamı yazıldığı kadardı, dili Türkçeye sabitti ve TMDB'nin gerçek
    /// izleyici verisiyle yarışamıyordu. Kaldırıldı.
    func recommendations(
        for item: MediaItem,
        tmdb: TMDBMetadata? = nil,
        franchise franchiseEntries: [FranchiseEntry]? = nil,
        limit: Int = 16
    ) -> [MediaItem] {
        var result: [MediaItem] = []
        var excludedIDs: Set<MediaID> = [item.id]

        // Serideki filmler önerilerde tekrar etmesin.
        let seriesEntries = franchiseEntries ?? self.franchiseEntries(for: item, tmdb: tmdb)
        for entry in seriesEntries {
            if let local = entry.localItem { excludedIDs.insert(local.id) }
        }

        let pool = catalog[item.kind] ?? []

        // 1) TMDB'nin öneri ve benzer listesi.
        if let tmdb {
            let recommendedIDs = tmdb.recommendedMovieIDs
            for tmdbID in recommendedIDs {
                guard let candidate = itemsByTMDBID(tmdbID, kind: item.kind),
                      !excludedIDs.contains(candidate.id) else { continue }
                result.append(candidate)
                excludedIDs.insert(candidate.id)
                if result.count >= limit { return result }
            }

            // Kimlik tutmayan listelerde başlıktan eşleşme.
            for title in tmdb.recommendedMovieTitles {
                let key = Self.titleKey(title)
                guard !key.isEmpty,
                      let candidate = moviesByTitle[key]?.first(where: { !excludedIDs.contains($0.id) })
                else { continue }
                result.append(candidate)
                excludedIDs.insert(candidate.id)
                if result.count >= limit { return result }
            }
        }

        // 2) Aynı yönetmen ya da başrol.
        let director = (tmdb?.director ?? item.director)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let castList = (tmdb?.cast.nilIfEmptyList ?? item.cast)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
            .prefix(3)

        if director != nil || !castList.isEmpty {
            for candidate in pool where !excludedIDs.contains(candidate.id) {
                var matchesPerson = false
                if let director, let candidateDirector = candidate.director,
                   candidateDirector.localizedCaseInsensitiveContains(director) {
                    matchesPerson = true
                }
                if !matchesPerson {
                    matchesPerson = castList.contains { actor in
                        candidate.cast.contains { $0.localizedCaseInsensitiveContains(actor) }
                    }
                }
                guard matchesPerson else { continue }
                result.append(candidate)
                excludedIDs.insert(candidate.id)
                if result.count >= limit { return result }
            }
        }

        // 3) Aynı kategori.
        if let categoryID = item.categoryID {
            for candidate in itemsByCategory[item.kind]?[categoryID] ?? []
            where !excludedIDs.contains(candidate.id) {
                result.append(candidate)
                excludedIDs.insert(candidate.id)
                if result.count >= limit { return result }
            }
        }

        // 4) Katalogun kalanı: ray hiçbir zaman boş kalmıyor.
        for candidate in pool where !excludedIDs.contains(candidate.id) {
            result.append(candidate)
            excludedIDs.insert(candidate.id)
            if result.count >= limit { break }
        }

        return result
    }

    private func itemsByTMDBID(_ tmdbID: Int, kind: MediaKind) -> MediaItem? {
        kind == .movie ? moviesByTMDBID[tmdbID] : nil
    }

    // MARK: - Başlık normalizasyonu

    /// Eşleştirme anahtarı.
    ///
    /// Sağlayıcı başlıkları kalite, dil ve kaynak etiketleriyle geliyor:
    /// "Yenilmezler: Sonsuzluk Savaşı tr|en [4K] (2018)". Bunlar atılıp aksan,
    /// harf durumu ve noktalama farkları siliniyor ki TMDB'den gelen başlıkla
    /// aynı anahtara insin.
    nonisolated static func titleKey(_ raw: String) -> String {
        var text = raw
        // Parantezli / köşeli etiketler.
        text = text.replacingOccurrences(
            of: #"\s*[\(\[\{][^\)\]\}]*[\)\]\}]"#, with: " ", options: .regularExpression
        )
        // "| tr", "|EN", "| 4K" gibi ekler ve sonrası.
        if let pipe = text.firstIndex(of: "|") { text = String(text[..<pipe]) }
        text = text.replacingOccurrences(
            of: #"(?i)\b(4k|uhd|fhd|hd|sd|2160p|1080p|720p|dual|multi|vostfr|dublaj|remux|hevc|x264|x265|web-?dl|bluray|imax|extended|unrated|remastered)\b"#,
            with: " ",
            options: .regularExpression
        )
        var folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        folded = folded.replacingOccurrences(of: "ı", with: "i")
        let stripped = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(stripped)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// `titleKey`'in sondaki sıra numarası / roma rakamı atılmış hâli.
    /// Yalnızca yıl da tuttuğunda kullanılıyor.
    nonisolated static func looseTitleKey(_ raw: String) -> String {
        titleKey(raw)
            .replacingOccurrences(
                of: #"\s+(bolum|part|partie|teil|parte|kisim|chapter|chapitre|kapitel|vol|volume)?\s*(\d{1,2}|[ivx]{1,4})$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespaces)
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
        itemsByID = [:]
        itemsByCategory = [:]
        moviesByTMDBID = [:]
        moviesByTitle = [:]
        moviesByLooseTitle = [:]
        detailCache = [:]
        featured.reset()
        refreshTask?.cancel()
        refreshTask = nil
        state = .idle
        notifyChange()
    }
}

/// Diske yazılan katalog anlık görüntüsü.
struct CatalogSnapshot: Codable, Sendable {
    var categories: [MediaKind: [MediaCategory]] = [:]
    var items: [MediaKind: [MediaItem]] = [:]
}
