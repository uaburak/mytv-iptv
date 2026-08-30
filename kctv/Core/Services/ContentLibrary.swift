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
        let cacheKey = (currentPlaylistID ?? provider.sourceID) + ".v3"
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

        state = .loading
        await refresh(from: provider, cacheKey: cacheKey)
    }

    /// Sağlayıcıdan taze anlık görüntüyü çekip uygular.
    private func refresh(from provider: any ContentProvider, cacheKey: String) async {
        do {
            // Abonelik durumu ve sunucunun izin verdiği yayın biçimi burada.
            account = try await provider.validate()
            let snapshot = try await fetchSnapshot(from: provider)
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

    /// TMDB'den asenkron çekilen koleksiyon parçalarını kullanıcının kataloğuyla eşleştirir.
    func matchFranchiseEntries(parts: [TMDBCollectionPart], for item: MediaItem) -> [FranchiseEntry] {
        guard item.kind == .movie, !parts.isEmpty else { return [] }
        let allMovies = catalog[.movie] ?? []
        var entries: [FranchiseEntry] = []
        var matchedCatalogIDs: Set<MediaID> = []

        for part in parts {
            let normTR = normalizeForFranchise(part.title)
            let normEN = part.originalTitle.map { normalizeForFranchise($0) } ?? ""
            var possibleVariants: Set<String> = [normTR]
            if !normEN.isEmpty { possibleVariants.insert(normEN) }

            // Çeviri varyantlarını türet (örn: Endgame -> Son Oyun, Avengers -> Yenilmezler, Civil War -> İç Savaş)
            for base in [normTR, normEN] where !base.isEmpty {
                for (enKey, trList) in Self.commonSubtitleTranslations {
                    if base.contains(enKey) {
                        for tr in trList {
                            let replaced = base.replacingOccurrences(of: enKey, with: tr)
                            possibleVariants.insert(replaced)
                            possibleVariants.insert(replaced.replacingOccurrences(of: "avengers", with: "yenilmezler"))
                            possibleVariants.insert(replaced.replacingOccurrences(of: "yenilmezler", with: "avengers"))
                            possibleVariants.insert(replaced.replacingOccurrences(of: "captain america", with: "kaptan amerika"))
                            possibleVariants.insert(replaced.replacingOccurrences(of: "kaptan amerika", with: "captain america"))
                        }
                    }
                }
            }

            var matchedItem: MediaItem?
            for candidate in allMovies where !matchedCatalogIDs.contains(candidate.id) {
                if let cid = candidate.tmdbID, cid == part.id {
                    matchedItem = candidate
                    break
                }
                let normCandidate = normalizeForFranchise(candidate.title)
                if possibleVariants.contains(normCandidate) {
                    matchedItem = candidate
                    break
                }
                // Rakam farklılıklarını tolere et (örn: 'Thor 2: Karanlık Dünya' vs 'Thor: Karanlık Dünya')
                let normCandidateNoNum = normCandidate.replacingOccurrences(of: #"\b\d+\b"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if possibleVariants.contains(normCandidateNoNum) {
                    matchedItem = candidate
                    break
                }

                // Yıl ve ana başlık kökü eşleşmesi (örn: 2019 + Avengers / Yenilmezler)
                if let partYear = part.releaseYear, let cYear = candidate.year, String(cYear) == partYear {
                    let isMockbuster = normCandidate.contains("reenactors") || normCandidate.contains("bikini") || normCandidate.contains("scavengers") || normCandidate.contains("making") || normCandidate.contains("behind")
                    if !isMockbuster {
                        let cStem = extractPrimaryFranchiseStem(from: candidate.title)
                        let pStem = extractPrimaryFranchiseStem(from: part.title)
                        if cStem == pStem || (cStem.count >= 4 && pStem.count >= 4 && (cStem.contains(pStem) || pStem.contains(cStem))) {
                            matchedItem = candidate
                            break
                        }
                        if (cStem.contains("avenger") || cStem.contains("yenilmez")) && (pStem.contains("avenger") || pStem.contains("yenilmez")) {
                            matchedItem = candidate
                            break
                        }
                    }
                }
            }

            if let matchedItem {
                matchedCatalogIDs.insert(matchedItem.id)
                entries.append(FranchiseEntry(
                    id: matchedItem.id.description,
                    title: matchedItem.title,
                    originalTitle: part.originalTitle,
                    year: matchedItem.year ?? Int(part.releaseYear ?? ""),
                    releaseDate: part.releaseDate,
                    posterURL: matchedItem.posterURL ?? part.posterURL,
                    backdropURL: matchedItem.backdropURL ?? part.backdropURL,
                    overview: matchedItem.plot ?? part.overview,
                    tmdbID: part.id,
                    localItem: matchedItem
                ))
            } else {
                // Kullanıcının listesinde YOK -> TMDB verisiyle sanal kart oluştur
                entries.append(FranchiseEntry(
                    id: "tmdb-\(part.id)",
                    title: part.title,
                    originalTitle: part.originalTitle,
                    year: Int(part.releaseYear ?? ""),
                    releaseDate: part.releaseDate,
                    posterURL: part.posterURL,
                    backdropURL: part.backdropURL,
                    overview: part.overview,
                    tmdbID: part.id,
                    localItem: nil
                ))
            }
        }

        return entries
    }

    /// 1. Seriye ait tüm filmleri döner (kullanıcının listesinde olanlar + seriye dahil olup listede henüz bulunmayanlar).
    func franchiseEntries(for item: MediaItem, tmdb: TMDBMetadata? = nil) -> [FranchiseEntry] {
        if let tmdb, !tmdb.collectionParts.isEmpty {
            let matched = matchFranchiseEntries(parts: tmdb.collectionParts, for: item)
            if !matched.isEmpty { return matched }
        }

        // Çevrimdışı / TMDB'siz kesin kök eşleşmesi
        guard item.kind == .movie else { return [] }
        let allMovies = catalog[.movie] ?? []
        var entries: [FranchiseEntry] = []
        let targetStem = extractPrimaryFranchiseStem(from: item.title)
        guard targetStem.count >= 3 else { return [] }

        for candidate in allMovies {
            let candidateStem = extractPrimaryFranchiseStem(from: candidate.title)
            if targetStem == candidateStem {
                entries.append(FranchiseEntry(
                    id: candidate.id.description,
                    title: candidate.title,
                    originalTitle: nil,
                    year: candidate.year,
                    releaseDate: nil,
                    posterURL: candidate.posterURL,
                    backdropURL: candidate.backdropURL,
                    overview: candidate.plot,
                    tmdbID: candidate.tmdbID,
                    localItem: candidate
                ))
            }
        }

        entries.sort { a, b in
            if let ya = a.year, let yb = b.year, ya != yb {
                return ya < yb
            }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }

        return entries
    }

    /// Yalnızca kullanıcının listesinde var olan seri filmlerini döner.
    func franchise(for item: MediaItem, tmdb: TMDBMetadata? = nil) -> [MediaItem] {
        franchiseEntries(for: item, tmdb: tmdb)
            .compactMap(\.localItem)
            .filter { $0.id != item.id }
    }

    /// İçeriğin bir seriye (franchise) ait olup olmadığını kontrol eder.
    func hasFranchise(for item: MediaItem, tmdb: TMDBMetadata? = nil) -> Bool {
        let entries = franchiseEntries(for: item, tmdb: tmdb)
        return entries.count > 1
    }

    /// 2. Detay ekranının en altındaki "Önerilen İçerikler" bölümü:
    /// - Seri filmleri KESİNLİKLE İÇERMEZ (seri filmler üstte ayrı başlıkta gösterilir).
    /// - TMDB izleyici alışkanlıkları ve öneri motoru (Recommendations API).
    /// - Multiverse (Marvel, DC) & Sinematik Vibe (John Wick -> Nobody, Bullet Train, Equalizer, Extraction) Kümeleri.
    /// - Oyuncu / Yönetmen eşleşmesi ve kategori tamamlayıcısı.
    func recommendations(for item: MediaItem, tmdb: TMDBMetadata? = nil, limit: Int = 16) -> [MediaItem] {
        var result: [MediaItem] = []
        var excludedIDs: Set<MediaID> = [item.id]

        // Serideki tüm filmleri önerilerden KESİNLİKLE hariç tut (önerilerde seri tekrarlanmasın)
        let franchiseMovies = franchise(for: item, tmdb: tmdb)
        for fm in franchiseMovies {
            excludedIDs.insert(fm.id)
        }

        let allMovies = catalog[.movie] ?? []
        let normTitle = normalizeForFranchise(item.title)

        // 1. TMDB'nin Gerçek İzleyici Davranışı Önerileri (Multiverse / Vibe Recommendations)
        if let tmdb, !tmdb.recommendedMovieIDs.isEmpty || !tmdb.recommendedMovieTitles.isEmpty {
            let recIDs = Set(tmdb.recommendedMovieIDs)
            let recTitles = tmdb.recommendedMovieTitles.map { normalizeForFranchise($0) }

            for candidate in allMovies where !excludedIDs.contains(candidate.id) {
                if let cid = candidate.tmdbID, recIDs.contains(cid) {
                    result.append(candidate)
                    excludedIDs.insert(candidate.id)
                    if result.count >= 8 { break }
                } else {
                    let normCandidate = normalizeForFranchise(candidate.title)
                    if recTitles.contains(where: { $0 == normCandidate }) {
                        result.append(candidate)
                        excludedIDs.insert(candidate.id)
                        if result.count >= 8 { break }
                    }
                }
            }
        }

        // 2. Multiverse & Sinematik Tarz Kümeleri (Marvel MCU, DC, John Wick Gun-Fu / Revenge, Heist vb.)
        if item.kind == .movie && result.count < limit {
            if let matchedCluster = Self.cinematicVibeClusters.first(where: { cluster in
                cluster.triggers.contains(where: { normTitle.contains($0) })
            }) {
                for recPattern in matchedCluster.recommendationPatterns {
                    for candidate in allMovies where !excludedIDs.contains(candidate.id) {
                        let normCandidate = normalizeForFranchise(candidate.title)
                        if normCandidate.range(of: recPattern, options: .regularExpression) != nil {
                            result.append(candidate)
                            excludedIDs.insert(candidate.id)
                            if result.count >= 12 { break }
                        }
                    }
                    if result.count >= 12 { break }
                }
            }
        }

        // 3. Oyuncu ve Yönetmen Eşleşmesi (Aynı aktör veya yönetmenin listedeki diğer filmleri)
        let director = tmdb?.director ?? item.director?.trimmingCharacters(in: .whitespacesAndNewlines)
        let castList = (tmdb?.cast.nilIfEmptyList ?? item.cast).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.count >= 3 }

        if (director != nil || !castList.isEmpty) && result.count < limit {
            for candidate in allMovies where !excludedIDs.contains(candidate.id) {
                var matchesPerson = false
                if let d = director, !d.isEmpty, let cd = candidate.director, cd.localizedCaseInsensitiveContains(d) {
                    matchesPerson = true
                }
                if !matchesPerson && !castList.isEmpty {
                    for actor in castList.prefix(3) {
                        if candidate.cast.contains(where: { $0.localizedCaseInsensitiveContains(actor) }) {
                            matchesPerson = true
                            break
                        }
                    }
                }
                if matchesPerson {
                    result.append(candidate)
                    excludedIDs.insert(candidate.id)
                    if result.count >= 14 { break }
                }
            }
        }

        // 4. Kategori / Tür Tamamlayıcısı
        if result.count < limit, let categoryID = item.categoryID {
            let siblings = itemsByCategory[item.kind]?[categoryID] ?? []
            for candidate in siblings where !excludedIDs.contains(candidate.id) {
                result.append(candidate)
                excludedIDs.insert(candidate.id)
                if result.count == limit { break }
            }
        }

        // 5. Genel Katalog Tamamlayıcısı
        if result.count < limit {
            let fallbackList = catalog[item.kind] ?? []
            for candidate in fallbackList where !excludedIDs.contains(candidate.id) {
                result.append(candidate)
                excludedIDs.insert(candidate.id)
                if result.count == limit { break }
            }
        }

        return Array(result.prefix(limit))
    }

    /// Geriye uyumluluk için alias
    func related(to item: MediaItem, limit: Int = 16) -> [MediaItem] {
        recommendations(for: item, limit: limit)
    }

    // MARK: - Popüler Altyazı ve Çeviri Varyantları

    private static let commonSubtitleTranslations: [String: [String]] = [
        "endgame": ["son oyun", "end game", "sonoyun"],
        "end game": ["son oyun", "endgame"],
        "infinity war": ["sonsuzluk savasi"],
        "age of ultron": ["ultron cagi", "ultron"],
        "the avengers": ["yenilmezler", "avengers"],
        "avengers": ["yenilmezler"],
        "civil war": ["ic savas", "kahramanlarin savasi"],
        "winter soldier": ["kis askeri"],
        "the first avenger": ["ilk yenilmez", "ilk avenger"],
        "brave new world": ["cesur yeni dunya"],
        "dark world": ["karanlik dunya"],
        "love and thunder": ["ask ve gok gurultusu"],
        "no way home": ["eve donus yok"],
        "far from home": ["evden uzakta"],
        "homecoming": ["eve donus"],
        "dead reckoning": ["olumcul hesaplasma"],
        "fallout": ["yansimalar"],
        "ghost protocol": ["hayalet protokol"],
        "rogue nation": ["gizli millet", "kacak ulus"],
        "the two towers": ["iki kule"],
        "the return of the king": ["kralin donusu"],
        "the fellowship of the ring": ["yuzuk kardesligi"],
        "an unexpected journey": ["beklenmedik bir yolculuk"],
        "desolation of smaug": ["smaugun corak topraklari"],
        "battle of the five armies": ["bes ordunun savasi"],
        "reloaded": ["yeniden yuklendi"],
        "revolutions": ["devrimler"],
        "resurrections": ["yeniden dogus", "dirilis"],
        "salvation": ["kurtulus"],
        "genisys": ["yaratilis"],
        "dark fate": ["kara kader"],
        "judgement day": ["kiyamet gunu", "hesap gunu"]
    ]

    // MARK: - Sinematik Evrenler & Vibe Kümeleri

    private struct CinematicVibeCluster: Sendable {
        let name: String
        let triggers: [String]
        let recommendationPatterns: [String]
    }

    private static let cinematicVibeClusters: [CinematicVibeCluster] = [
        // 1. Marvel / MCU Multiverse
        CinematicVibeCluster(
            name: "Marvel Multiverse",
            triggers: [
                "orumcek adam", "spider man", "iron man", "demir adam", "yenilmezler", "avengers",
                "thor", "kaptan amerika", "captain america", "doctor strange", "doktor strange",
                "black widow", "kara dul", "galaksinin koruyuculari", "guardians of the galaxy",
                "ant man", "karinca adam", "black panther", "kara panter", "shang chi", "eternals",
                "deadpool", "wolverine", "venom", "x men", "hulk", "daredevil", "blade", "loki", "morbius"
            ],
            recommendationPatterns: [
                #"\bdeadpool\b"#, #"\bwolverine\b"#, #"\byenilmezler\b"#, #"\bavengers\b"#,
                #"\bdemir adam\b"#, #"\biron man\b"#, #"\bdoktor strange\b"#, #"\bdoctor strange\b"#,
                #"\bkaptan amerika\b"#, #"\bcaptain america\b"#, #"\borumcek adam\b"#, #"\bspider man\b"#,
                #"\bgalaksinin koruyuculari\b"#, #"\bguardians of the galaxy\b"#, #"\bthor\b"#,
                #"\bblack panther\b"#, #"\bkara panter\b"#, #"\bant man\b"#, #"\bvenom\b"#, #"\bx men\b"#, #"\bhulk\b"#
            ]
        ),
        // 2. DC Multiverse
        CinematicVibeCluster(
            name: "DC Multiverse",
            triggers: [
                "batman", "kara sovalye", "dark knight", "superman", "adalet birligi", "justice league",
                "aquaman", "wonder woman", "flash", "joker", "suicide squad", "intihar timi", "shazam", "black adam"
            ],
            recommendationPatterns: [
                #"\bbatman\b"#, #"\bkara sovalye\b"#, #"\bjoker\b"#, #"\bsuperman\b"#,
                #"\badalet birligi\b"#, #"\bjustice league\b"#, #"\baquaman\b"#, #"\bwonder woman\b"#,
                #"\bflash\b"#, #"\bsuicide squad\b"#, #"\bshazam\b"#, #"\bblack adam\b"#
            ]
        ),
        // 3. Gun-Fu / Assassin / Revenge Action (John Wick Vibe)
        CinematicVibeCluster(
            name: "Gun-Fu & Revenge Action",
            triggers: [
                "john wick", "nobody", "onemsiz biri", "equalizer", "adalet", "bullet train", "suikast treni",
                "extraction", "tahliye", "the beekeeper", "beekeeper", "olumcul koruma", "atomic blonde",
                "sarisin bomba", "the raid", "baskin", "taken", "96 saat", "sicario", "man on fire",
                "gazap atesi", "sisu", "kill bill", "leon", "sevginin gucu", "wrath of man", "intikam vakti",
                "polar", "peppermint", "monkey man", "hitman", "tetikci"
            ],
            recommendationPatterns: [
                #"\bnobody\b"#, #"\bonemsiz biri\b"#, #"\bequalizer\b"#, #"\badalet\b(?!\s*birligi|\s*merkezi)"#,
                #"\bbullet train\b"#, #"\bsuikast treni\b"#, #"\bextraction\b"#, #"\btahliye\b"#,
                #"\bbeekeeper\b"#, #"\bolumcul koruma\b"#, #"\batomic blonde\b"#, #"\bsarisin bomba\b"#,
                #"\bthe raid\b"#, #"\bbaskin\b"#, #"\btaken\b"#, #"\b96 saat\b"#, #"\bsicario\b"#,
                #"\bman on fire\b"#, #"\bgazap atesi\b"#, #"\bsisu\b"#, #"\bkill bill\b"#, #"\bleon\b"#,
                #"\bwrath of man\b"#, #"\bintikam vakti\b"#, #"\bhitman\b"#, #"\bpeppermint\b"#, #"\bmonkey man\b"#
            ]
        ),
        // 4. Soygun & Zeka Oyunları (Heist & Crime)
        CinematicVibeCluster(
            name: "Heist & Crime",
            triggers: [
                "ocean", "la casa de papel", "baby driver", "the town", "hirsizlar sehri", "heat",
                "buyuk hesaplasma", "now you see me", "sihirbazlar cetesi", "den of thieves", "red notice", "inside man"
            ],
            recommendationPatterns: [
                #"\bocean\b"#, #"\bbaby driver\b"#, #"\bthe town\b"#, #"\bhirsizlar sehri\b"#,
                #"\bheat\b"#, #"\bbuyuk hesaplasma\b"#, #"\bnow you see me\b"#, #"\bsihirbazlar cetesi\b"#,
                #"\bden of thieves\b"#, #"\bred notice\b"#, #"\binside man\b"#
            ]
        ),
        // 5. Bilim Kurgu Siberpunk & Zeka (Sci-Fi Cyberpunk)
        CinematicVibeCluster(
            name: "Sci-Fi Cyberpunk",
            triggers: [
                "matrix", "blade runner", "cyberpunk", "alita", "ghost in the shell", "minority report",
                "azinlik raporu", "i robot", "ben robot", "total recall", "gercege cagri", "upgrade",
                "inception", "baslangic", "tenet", "interstellar", "yildizlararasi"
            ],
            recommendationPatterns: [
                #"\bmatrix\b"#, #"\bblade runner\b"#, #"\balita\b"#, #"\bghost in the shell\b"#,
                #"\bminority report\b"#, #"\bazinlik raporu\b"#, #"\bi robot\b"#, #"\btotal recall\b"#,
                #"\bupgrade\b"#, #"\binception\b"#, #"\bbaslangic\b"#, #"\btenet\b"#, #"\binterstellar\b"#
            ]
        )
    ]

    // MARK: - Evrensel Franchise / Seri Analiz Yardımcıları

    private func extractPrimaryFranchiseStem(from title: String) -> String {
        var cleaned = title.replacingOccurrences(
            of: #"\s*[\(\[\{][^\)\]\}]*[\)\]\}]"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?i)\b(4k|uhd|fhd|hd|1080p|720p|dual|multi|vostfr|sub|dub|extended|unrated|remastered|hevc)\b"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let delimiters = CharacterSet(charactersIn: ":|•/\\")
        let parts = cleaned.components(separatedBy: delimiters)
        let firstSubpart = parts.first ?? cleaned
        let dashParts = firstSubpart.components(separatedBy: " - ")
        let primaryPart = (dashParts.first ?? firstSubpart).trimmingCharacters(in: .whitespacesAndNewlines)

        let strippedSuffix = primaryPart.replacingOccurrences(
            of: #"(?i)\s+(bölüm|bolum|part|partie|teil|parte|kısım|kisim|chapter|chapitre|kapitel|vol|volume|ep|episode)?\s*(\d+(\.\d+)?|[ivx]+)$"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return normalizeForFranchise(strippedSuffix)
    }

    // MARK: - Evrensel Franchise / Seri Analiz Yardımcıları

    private func extractFranchiseStems(from title: String) -> [String] {
        // 1. Uluslararası M3U / IPTV format, kalite, yıl ve ses etiketlerini temizle:
        // [4K], (FHD), [TR-EN], (VOSTFR), [Multi], [HEVC], (2024), [Extended], [1080p] vb.
        var cleaned = title.replacingOccurrences(
            of: #"\s*[\(\[\{][^\)\]\}]*[\)\]\}]"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?i)\b(4k|uhd|fhd|hd|1080p|720p|dual|multi|vostfr|sub|dub|extended|unrated|remastered|hevc)\b"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Bölüm / Alt başlık ayraçları: ":", "|", "•", " - ", " – ", " — ", "/", "\"
        let delimiters = CharacterSet(charactersIn: ":|•/\\")
        let parts = cleaned.components(separatedBy: delimiters)
        let firstSubpart = parts.first ?? cleaned
        let dashParts = firstSubpart.components(separatedBy: " - ")
        let primaryPart = (dashParts.first ?? firstSubpart).trimmingCharacters(in: .whitespacesAndNewlines)

        // 3. Çok dilli bölüm / parça / roma rakamı temizleme (TR/EN/FR/DE/ES/IT):
        // Part, Partie, Teil, Parte, Bölüm, Kısım, Chapter, Chapitre, Kapitel, Vol, Volume, Ep, Episode + Rakamlar
        let strippedSuffix = primaryPart.replacingOccurrences(
            of: #"(?i)\s+(bölüm|bolum|part|partie|teil|parte|kısım|kisim|chapter|chapitre|kapitel|vol|volume|ep|episode)?\s*(\d+(\.\d+)?|[ivx]+)$"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        var stems: Set<String> = []
        let normalizedPrimary = normalizeForFranchise(strippedSuffix)
        if normalizedPrimary.count >= 3 {
            stems.insert(normalizedPrimary)
        }

        // 4. Çok dilli bağlaçlar ile bağlanan seriler (" ve ", " and ", " und ", " et ", " e ", " y "):
        // Örn: "Harry Potter et la Coupe de Feu" -> "Harry Potter"
        // Örn: "Astérix et Obélix" -> "Astérix et Obélix"
        let lower = primaryPart.lowercased()
        for conj in [" ve ", " and ", " und ", " et ", " e ", " y "] {
            if let range = lower.range(of: conj) {
                let prefix = String(primaryPart[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let normPrefix = normalizeForFranchise(prefix)
                if normPrefix.count >= 5 || normPrefix.split(separator: " ").count >= 2 {
                    stems.insert(normPrefix)
                }
            }
        }

        // 5. İki kelimelik genel seri önekleri (örn: "Der Herr der Ringe", "The Matrix", "John Wick")
        let words = normalizedPrimary.split(separator: " ")
        if words.count >= 2 {
            let twoWords = words.prefix(2).joined(separator: " ")
            let stopPhrases: Set<String> = ["bir zamanlar", "son durak", "yeni bir", "once upon", "the last", "a very"]
            if twoWords.count >= 5 && !stopPhrases.contains(twoWords) {
                stems.insert(twoWords)
            }
        }

        return Array(stems)
    }

    /// Evrensel metin normalizasyonu (Aksanları kaldırır, harf duyarlılığını siler, sembolleri temizler).
    private func normalizeForFranchise(_ text: String) -> String {
        // Swift'in diacriticInsensitive katmanı tüm dillerdeki aksanları (é, è, ü, ö, ş, ç, ğ, ñ, ø, å vs.) temel Latin harfine çevirir.
        var str = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        str = str.replacingOccurrences(of: "-", with: " ")
        str = str.replacingOccurrences(of: "_", with: " ")
        str = str.replacingOccurrences(of: "ı", with: "i")
        str = str.replacingOccurrences(of: #"[^\w\s]"#, with: " ", options: .regularExpression)
        str = str.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
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
