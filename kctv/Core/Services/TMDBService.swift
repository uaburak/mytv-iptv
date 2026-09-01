import Foundation

/// TMDB'den alınan görsel ve künye zenginleştirmesi.
/// Künyedeki tek oyuncu. Ad tek başına yetmiyordu: detay ekranında Apple TV'deki
/// gibi fotoğraf ve canlandırdığı karakter gösteriliyor.
struct TMDBCastMember: Codable, Sendable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var character: String?
    var profileURL: URL?
}

struct TMDBMetadata: Codable, Sendable {
    /// Şeffaf beyaz logo (PNG). Varsa başlık yerine bu gösteriliyor.
    var logoURL: URL?
    /// Sinematik dikey görsel (afiş).
    var posterURL: URL?
    /// Sinematik 16:9 yatay görsel.
    var backdropURL: URL?
    var overview: String?
    var tagline: String?
    var rating: Double?
    var voteCount: Int?
    var releaseDate: String?
    var releaseYear: String?
    var runtimeMinutes: Int?
    var genres: [String] = []
    var status: String?
    var originalTitle: String?
    var originalLanguage: String?
    var country: String?
    var director: String?
    var cast: [String] = []
    /// Fotoğraflı künye. `cast` geriye dönük uyumluluk için duruyor.
    var castMembers: [TMDBCastMember] = []
    var trailerURL: URL?
    var collectionID: Int?
    var collectionName: String?
    var collectionParts: [TMDBCollectionPart] = []
    var recommendedMovieIDs: [Int] = []
    var recommendedMovieTitles: [String] = []
}

/// Bir TMDB koleksiyonunun (seri) tek filmi.
///
/// Başlık üç biçimde tutuluyor: seçili dildeki, orijinal ve diğer dildeki.
/// Kullanıcının listesindeki karşılığını bulmak için üçü de gerekiyor —
/// sağlayıcılar aynı filmi kimi listede "Yenilmezler: Sonsuzluk Savaşı",
/// kimi listede "Avengers: Infinity War" diye yazıyor.
struct TMDBCollectionPart: Codable, Sendable, Hashable {
    var id: Int
    var title: String
    var originalTitle: String?
    /// Diğer arayüz dilindeki başlık (TR seçiliyse EN, EN seçiliyse TR).
    var alternateTitle: String?
    var posterPath: String?
    var backdropPath: String?
    var releaseDate: String?
    var releaseYear: String?
    var overview: String?

    /// Eşleştirmede denenecek bütün başlıklar.
    var titleVariants: [String] {
        [title, originalTitle, alternateTitle].compactMap { $0 }
    }

    var posterURL: URL? {
        TMDBService.imageURL(posterPath, size: "w500")
    }

    var backdropURL: URL? {
        TMDBService.imageURL(backdropPath, size: "w1280")
    }
}

/// Koleksiyon (seri) önbelleği. Künye önbelleğiyle aynı gerekçe: detay
/// ekranı daha önce görülmüş bir serinin filmlerini ilk karede basabilsin.
private final class TMDBCollectionCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: [TMDBCollectionPart]] = [:]

    func value(_ key: String) -> [TMDBCollectionPart]? {
        lock.lock(); defer { lock.unlock() }
        return entries[key]
    }

    func set(_ value: [TMDBCollectionPart], for key: String) {
        lock.lock(); defer { lock.unlock() }
        entries[key] = value
    }

    func load(_ snapshot: [String: [TMDBCollectionPart]]) {
        lock.lock(); defer { lock.unlock() }
        for (key, value) in snapshot { entries[key] = value }
    }

    func snapshot() -> [String: [TMDBCollectionPart]] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }
}

/// Künye önbelleği.
///
/// Aktörün dışında duruyor ki detay ekranı ilk karede — hiçbir `await`
/// olmadan — elindeki künyeyi basabilsin. Daha önce her açılış en az bir
/// aktör turu bekliyordu ve ekran o süre boyunca yer tutucuyla açılıyordu.
private final class TMDBMetadataCache: @unchecked Sendable {
    private let lock = NSLock()
    /// `nil` değer "aranmış ama bulunamamış" demek; anahtarın hiç olmaması
    /// "henüz sorulmamış".
    private var entries: [String: TMDBMetadata?] = [:]

    func contains(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return entries.index(forKey: key) != nil
    }

    /// Dış katman için: bulunmuş künye ya da nil.
    func value(_ key: String) -> TMDBMetadata? {
        lock.lock(); defer { lock.unlock() }
        return entries[key] ?? nil
    }

    /// Anahtar biliniyorsa `.some(...)`; hiç sorulmamışsa `nil`.
    func entry(_ key: String) -> TMDBMetadata?? {
        lock.lock(); defer { lock.unlock() }
        return entries[key]
    }

    func set(_ value: TMDBMetadata?, for key: String) {
        lock.lock(); defer { lock.unlock() }
        entries[key] = value
    }

    func load(_ snapshot: [String: TMDBMetadata]) {
        lock.lock(); defer { lock.unlock() }
        for (key, value) in snapshot { entries[key] = value }
    }

    /// Diske yazılacak hâli; bulunamamış kayıtlar saklanmıyor.
    func snapshot(limit: Int) -> [String: TMDBMetadata] {
        lock.lock(); defer { lock.unlock() }
        if entries.count > limit {
            for key in entries.keys.prefix(entries.count - limit) {
                entries.removeValue(forKey: key)
            }
        }
        return entries.compactMapValues { $0 }
    }
}

/// TMDB istemcisi.
///
/// Sağlayıcının görselleri tutarsız, bir kısmının sunucusu ölü ve künye alanları
/// eksik. TMDB bunları tek kaynaktan tutarlı veriyor.
///
/// Anahtar `Info.plist` içindeki `TMDBAPIKey` alanından okunuyor; boşsa bütün
/// çağrılar sessizce nil döner ve uygulama sağlayıcı verisiyle çalışır.
actor TMDBService {
    static let shared = TMDBService()

    private static let apiKey: String? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }()

    nonisolated static var isConfigured: Bool { apiKey != nil }

    /// v4 token'ları `ey` ile başlar ve Bearer başlığı ister; v3 anahtarı
    /// sorgu parametresi olarak gider.
    private static var usesBearerToken: Bool { apiKey?.hasPrefix("ey") == true }

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        // Ön yükleme sırası ekrandaki isteği bekletmemeli: bağlantı payı,
        // arkada süren en fazla iki ön yüklemenin (üçer istek) üstüne
        // ekranın kendi isteklerine yer kalacak kadar geniş.
        configuration.httpMaximumConnectionsPerHost = 12
        return URLSession(configuration: configuration)
    }()

    private let decoder = JSONDecoder()
    /// Başlık bazlı önbellek. Aynı içerik için ikinci kez arama isteği gitmiyor;
    /// eşleşme bulunamayanlar da hatırlanıyor.
    private static let cache = TMDBMetadataCache()
    /// Süren istekler. İki ekran aynı içeriği aynı anda sorduğunda ikinci
    /// çağrı birincinin sonucunu bekliyor — daha önce ikisi de ağa çıkıyordu.
    private var inFlight: [String: Task<TMDBMetadata?, Never>] = [:]
    private let store = LocalStore(folder: "tmdb")
    private let cacheKey = "metadata_v2"
    private let collectionCacheKey = "collections_v1"
    private static let cacheLimit = 4_000

    /// Diske yazma geciktirilmiş. Eskiden her tekil künye çözümünden sonra
    /// binlerce kayıtlık sözlüğün tamamı JSON'a kodlanıp yazılıyordu: banner
    /// için kırk sekiz aday sorgulamak kırk sekiz tam yazma demekti ve açılış
    /// gözle görülür biçimde yavaşlıyordu.
    private var persistTask: Task<Void, Never>?
    private static let persistDelay: Duration = .seconds(4)

    private init() {
        if let saved = store.read([String: TMDBMetadata].self, key: cacheKey) {
            Self.cache.load(saved)
        }
        if let savedCollections = store.read([String: [TMDBCollectionPart]].self, key: collectionCacheKey) {
            Self.collections.load(savedCollections)
        }
    }

    // MARK: - Önbellek anahtarı

    /// Bir içeriğin önbellek anahtarı. Senkron erişim de aynı hesabı
    /// kullanabilsin diye `nonisolated`.
    nonisolated static func cacheKey(for item: MediaItem, language: AppLanguage) -> String {
        let langCode = language.effectiveLanguageCode
        // Sağlayıcı kimliği veriyorsa arama yapmıyoruz: isim eşleştirmesi
        // "Kül" gibi kısa başlıklarda popülerlik sıralaması yüzünden yanlış
        // filme ("Avatar: Ateş ve Kül") düşebiliyor.
        if let tmdbID = item.tmdbID, item.kind != .series {
            return "\(langCode)_movie_id_\(tmdbID)"
        }
        return cacheKey(title: item.title, isSeries: item.kind == .series, languageCode: langCode)
    }

    /// Elde hazır künye. Ağa çıkmıyor, beklemiyor; yoksa `nil`.
    nonisolated static func cachedMetadata(
        for item: MediaItem,
        language: AppLanguage = AppLanguage.current
    ) -> TMDBMetadata? {
        guard item.kind != .live, isConfigured else { return nil }
        return cache.value(cacheKey(for: item, language: language))
    }

    /// İçerik daha önce sorulmuş mu (bulunamamış olsa bile).
    nonisolated static func isResolved(
        _ item: MediaItem,
        language: AppLanguage = AppLanguage.current
    ) -> Bool {
        guard item.kind != .live, isConfigured else { return true }
        return cache.contains(cacheKey(for: item, language: language))
    }

    // MARK: - Genel arayüz

    func metadata(for item: MediaItem, language: AppLanguage = AppLanguage.current) async -> TMDBMetadata? {
        guard item.kind != .live, Self.apiKey != nil else { return nil }
        let key = Self.cacheKey(for: item, language: language)
        if let cached = Self.cache.entry(key) { return cached }
        if let running = inFlight[key] { return await running.value }

        let isSeries = item.kind == .series
        let usesID = item.tmdbID != nil && !isSeries
        let tmdbID = item.tmdbID
        let title = item.title

        let task = Task<TMDBMetadata?, Never> { [weak self] in
            guard let self else { return nil }
            if usesID, let tmdbID {
                return await fetchByID(tmdbID, mediaType: "movie", language: language)
            }
            return await fetch(title: title, isSeries: isSeries, language: language)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil

        Self.cache.set(result, for: key)
        schedulePersist()
        return result
    }

    // MARK: - Ön yükleme

    /// Ön yükleme sırası. Kullanıcının **göreceği** içeriklerin künyesi,
    /// oraya varmadan çözülüyor: detay ekranı açıldığında elde hazır künye
    /// oluyor ve hiçbir bekleme görünmüyor.
    private var prefetchQueue: [MediaItem] = []
    private var queuedKeys: Set<String> = []
    private var activePrefetches = 0
    /// Ekrandaki isteklerin önüne geçmesin diye dar tutuluyor.
    private static let maxConcurrentPrefetches = 2
    private static let maxQueuedPrefetches = 300

    nonisolated func prefetchMetadata(for items: [MediaItem], language: AppLanguage = AppLanguage.current) {
        guard Self.isConfigured, !items.isEmpty else { return }
        Task { await enqueuePrefetch(items, language: language) }
    }

    private func enqueuePrefetch(_ items: [MediaItem], language: AppLanguage) {
        for item in items where item.kind != .live {
            guard prefetchQueue.count < Self.maxQueuedPrefetches else { break }
            let key = Self.cacheKey(for: item, language: language)
            guard !Self.cache.contains(key), inFlight[key] == nil,
                  queuedKeys.insert(key).inserted
            else { continue }
            prefetchQueue.append(item)
        }
        drainPrefetchQueue(language: language)
    }

    private func drainPrefetchQueue(language: AppLanguage) {
        while activePrefetches < Self.maxConcurrentPrefetches, !prefetchQueue.isEmpty {
            let item = prefetchQueue.removeFirst()
            activePrefetches += 1
            Task { [weak self] in
                guard let self else { return }
                _ = await metadata(for: item, language: language)
                await finishPrefetch(key: Self.cacheKey(for: item, language: language), language: language)
            }
        }
    }

    private func finishPrefetch(key: String, language: AppLanguage) {
        activePrefetches -= 1
        queuedKeys.remove(key)
        drainPrefetchQueue(language: language)
    }

    // MARK: - Koleksiyonlar (seri filmler)

    private static let collections = TMDBCollectionCache()

    private nonisolated static func collectionKey(_ id: Int, language: AppLanguage) -> String {
        "\(language.tmdbLanguageCode)_collection_\(id)"
    }

    /// Daha önce çözülmüş seri. Beklemeden, ağa çıkmadan.
    nonisolated static func cachedCollectionParts(
        for collectionID: Int,
        language: AppLanguage = AppLanguage.current
    ) -> [TMDBCollectionPart]? {
        collections.value(collectionKey(collectionID, language: language))
    }

    /// Bir koleksiyonun bütün filmleri.
    ///
    /// İki dilde birden çekiliyor: kullanıcının listesindeki başlık TMDB'nin
    /// Türkçe adıyla da İngilizce adıyla da yazılmış olabiliyor ve eşleşmeyi
    /// bunlardan hangisi tutarsa o kuruyor. İki istek de bir kez atılıyor,
    /// sonuç diske yazılıyor.
    func collectionParts(for collectionID: Int, language: AppLanguage = AppLanguage.current) async -> [TMDBCollectionPart] {
        let key = Self.collectionKey(collectionID, language: language)
        if let cached = Self.collections.value(key) { return cached }

        let alternateLanguage: AppLanguage = language.effectiveLanguageCode == "tr" ? .english : .turkish
        async let primaryTask = fetchCollection(id: collectionID, language: language)
        async let alternateTask = fetchCollection(id: collectionID, language: alternateLanguage)

        guard let primary = await primaryTask, let parts = primary.parts else { return [] }
        let alternateTitles: [Int: String] = (await alternateTask)?.parts?
            .reduce(into: [:]) { result, part in
                if let title = part.displayTitle { result[part.id] = title }
            } ?? [:]

        let result = parts.compactMap { part -> TMDBCollectionPart? in
            guard let title = part.displayTitle else { return nil }
            return TMDBCollectionPart(
                id: part.id,
                title: title,
                originalTitle: part.originalTitle,
                alternateTitle: alternateTitles[part.id],
                posterPath: part.posterPath,
                backdropPath: part.backdropPath,
                releaseDate: part.releaseDate,
                releaseYear: part.releaseYear,
                overview: part.overview
            )
        }
        // Yayın sırası: seri kronolojik okunmalı.
        .sorted { lhs, rhs in
            switch (lhs.releaseDate, rhs.releaseDate) {
            case let (left?, right?) where left != right: return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            default: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }

        Self.collections.set(result, for: key)
        persistCollections()
        return result
    }

    private func persistCollections() {
        let snapshot = Self.collections.snapshot()
        let store = self.store
        let key = collectionCacheKey
        Task.detached(priority: .utility) {
            store.write(snapshot, key: key)
        }
    }

    /// Kimlik bilindiğinde doğrudan çekiyoruz; belirsizlik yok.
    private func fetchByID(_ id: Int, mediaType: String, language: AppLanguage) async -> TMDBMetadata? {
        async let imagesTask = images(mediaType: mediaType, id: id, language: language)
        async let detailsTask = details(mediaType: mediaType, id: id, language: language)

        let images = await imagesTask
        let details = await detailsTask
        guard images.logo != nil || images.poster != nil || images.backdrop != nil || details != nil else { return nil }

        return makeMetadata(details: details, images: images)
    }

    private func details(mediaType: String, id: Int, language: AppLanguage) async -> TMDBDetailResponse? {
        guard let data = await get(
            path: "\(mediaType)/\(id)",
            query: [
                "language": language.tmdbLanguageCode,
                "append_to_response": "credits,videos,recommendations,similar",
                "include_video_language": "\(language.effectiveLanguageCode),en,null"
            ]
        ) else {
            return nil
        }
        return try? decoder.decode(TMDBDetailResponse.self, from: data)
    }

    private func fetchCollection(id: Int, language: AppLanguage) async -> TMDBDetailResponse.CollectionResponse? {
        guard let data = await get(path: "collection/\(id)", query: ["language": language.tmdbLanguageCode]) else {
            return nil
        }
        return try? decoder.decode(TMDBDetailResponse.CollectionResponse.self, from: data)
    }

    private func makeMetadata(
        details: TMDBDetailResponse?,
        images: (logo: URL?, poster: URL?, backdrop: URL?),
        collectionParts: [TMDBCollectionPart] = []
    ) -> TMDBMetadata {
        let releaseDate = details?.releaseDate ?? details?.firstAirDate
        let releaseYear = releaseDate.flatMap { str -> String? in
            guard str.count >= 4 else { return nil }
            return String(str.prefix(4))
        }

        let castItems = details?.credits?.cast?
            .sorted(by: { ($0.order ?? 99) < ($1.order ?? 99) })
            .prefix(16) ?? []
        let castMembers = castItems.map { item in
            TMDBCastMember(
                name: item.name,
                character: item.character?.nilIfEmpty,
                profileURL: Self.imageURL(item.profilePath, size: "w185")
            )
        }
        let castList = castMembers.map(\.name)

        let director = details?.credits?.crew?
            .first(where: { $0.job == "Director" })?.name

        let youtubeVideos = details?.videos?.results?.filter { $0.site.lowercased() == "youtube" } ?? []
        let langCode = AppLanguage.current.effectiveLanguageCode
        let trailerKey = youtubeVideos.first(where: { ($0.type == "Trailer" || $0.type == "Teaser") && $0.language == langCode && $0.official == true })?.key
            ?? youtubeVideos.first(where: { ($0.type == "Trailer" || $0.type == "Teaser") && $0.language == langCode })?.key
            ?? youtubeVideos.first(where: { ($0.type == "Trailer" || $0.type == "Teaser") && $0.official == true })?.key
            ?? youtubeVideos.first(where: { $0.type == "Trailer" || $0.type == "Teaser" })?.key
            ?? youtubeVideos.first?.key
        let trailerURL = trailerKey.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") }

        var recommendedMovieIDs: [Int] = []
        var recommendedMovieTitles: [String] = []
        let recItems = (details?.recommendations?.results ?? []) + (details?.similar?.results ?? [])
        for item in recItems {
            recommendedMovieIDs.append(item.id)
            if let title = item.displayTitle {
                recommendedMovieTitles.append(title)
            }
        }

        return TMDBMetadata(
            logoURL: images.logo,
            posterURL: images.poster,
            backdropURL: images.backdrop,
            overview: details?.overview?.nilIfEmpty,
            tagline: details?.tagline?.nilIfEmpty,
            rating: details?.voteAverage,
            voteCount: details?.voteCount,
            releaseDate: releaseDate,
            releaseYear: releaseYear,
            runtimeMinutes: details?.runtime ?? details?.episodeRunTime?.first,
            genres: details?.genres?.map(\.name) ?? [],
            status: details?.status,
            originalTitle: details?.originalTitle ?? details?.originalName,
            originalLanguage: details?.originalLanguage?.uppercased(),
            country: details?.productionCountries?.compactMap(\.name).first,
            director: director,
            cast: castList,
            castMembers: castMembers,
            trailerURL: trailerURL,
            collectionID: details?.belongsToCollection?.id,
            collectionName: details?.belongsToCollection?.name,
            collectionParts: collectionParts,
            recommendedMovieIDs: recommendedMovieIDs,
            recommendedMovieTitles: recommendedMovieTitles
        )
    }

    /// Yazmayı geciktirir; art arda gelen çözümler tek bir yazmada birleşiyor.
    private func schedulePersist() {
        guard persistTask == nil else { return }
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: Self.persistDelay)
            await self?.persistNow()
        }
    }

    private func persistNow() {
        persistTask = nil
        let snapshot = Self.cache.snapshot(limit: Self.cacheLimit)
        let store = self.store
        let key = cacheKey
        Task.detached(priority: .utility) {
            store.write(snapshot, key: key)
        }
    }

    // MARK: - Arama ve görseller

    private func fetch(title rawTitle: String, isSeries: Bool, language: AppLanguage) async -> TMDBMetadata? {
        let (title, year) = Self.cleanTitleAndYear(from: rawTitle)
        guard !title.isEmpty else { return nil }

        let mediaType = isSeries ? "tv" : "movie"
        let yearParameter = isSeries ? "first_air_date_year" : "primary_release_year"

        var query = ["query": title, "language": language.tmdbLanguageCode, "include_adult": "false"]
        if let year { query[yearParameter] = year }

        var match = await search(mediaType: mediaType, query: query, title: title, year: year, language: language)
        // Yıl filtresi tutmadıysa yılsız tekrar dene: sağlayıcı yılları
        // sık sık TMDB'dekiyle uyuşmuyor.
        if match == nil, year != nil {
            query.removeValue(forKey: yearParameter)
            match = await search(mediaType: mediaType, query: query, title: title, year: year, language: language)
        }
        guard let match else { return nil }

        async let imagesTask = images(mediaType: mediaType, id: match.id, language: language)
        async let detailsTask = details(mediaType: mediaType, id: match.id, language: language)

        let images = await imagesTask
        let details = await detailsTask

        return makeMetadata(details: details, images: images)
    }

    private func search(
        mediaType: String,
        query: [String: String],
        title: String,
        year: String?,
        language: AppLanguage
    ) async -> SearchResponse.Item? {
        guard let data = await get(path: "search/\(mediaType)", query: query),
              let response = try? decoder.decode(SearchResponse.self, from: data)
        else { return nil }
        return Self.bestMatch(for: title, year: year, in: response.results, language: language)
    }

    /// İlk sonucu körü körüne kabul etmek yanlış eşleşme üretiyor: TMDB
    /// popülerliğe göre sıralıyor ve "Kül" araması "Avatar: Ateş ve Kül"i
    /// başa koyuyor. Bu yüzden başlık benzerliği doğrulanıyor; yeterince
    /// benzer aday yoksa hiç eşleştirmiyoruz ve sağlayıcı verisiyle kalıyoruz.
    static func bestMatch(
        for title: String,
        year: String?,
        in results: [SearchResponse.Item],
        language: AppLanguage = .turkish
    ) -> SearchResponse.Item? {
        let target = normalized(title, language: language)
        guard !target.isEmpty else { return nil }

        var best: (item: SearchResponse.Item, score: Double)?
        for result in results.prefix(10) {
            let candidates = [result.displayTitle, result.originalTitle]
                .compactMap { $0 }
                .map { normalized($0, language: language) }
            guard let titleScore = candidates.map({ similarity($0, target) }).max(),
                  titleScore >= 0.72
            else { continue }

            var score = titleScore
            // Yıl tutuyorsa bu adayı öne al.
            if let year, let releaseYear = result.releaseYear, releaseYear == year {
                score += 0.3
            }
            if best == nil || score > best!.score {
                best = (result, score)
            }
        }
        return best?.item
    }

    /// Büyük/küçük harf, aksan ve noktalama farklarını siler.
    private static func normalized(_ text: String, language: AppLanguage) -> String {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: language.effectiveLanguageCode)
        )
        let stripped = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(stripped)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// 0...1 arası benzerlik (Levenshtein mesafesinden türetiliyor).
    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1 }
        if lhs.isEmpty || rhs.isEmpty { return 0 }

        let a = Array(lhs), b = Array(rhs)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        let distance = Double(previous[b.count])
        return 1 - distance / Double(max(a.count, b.count))
    }

    private func images(mediaType: String, id: Int, language: AppLanguage) async -> (logo: URL?, poster: URL?, backdrop: URL?) {
        guard let data = await get(
            path: "\(mediaType)/\(id)/images",
            query: ["include_image_language": "tr,en,null"]
        ), let response = try? decoder.decode(ImagesResponse.self, from: data) else {
            return (nil, nil, nil)
        }

        return (
            logo: Self.imageURL(Self.bestLogo(from: response.logos, language: language)?.path, size: "original"),
            poster: Self.imageURL(Self.textlessFirst(response.posters)?.path, size: "w780"),
            backdrop: Self.imageURL(Self.textlessFirst(response.backdrops)?.path, size: "w1280")
        )
    }

    /// Üzerinde yazı olmayan görseli tercih eder.
    ///
    /// TMDB'de dili `null` olan görseller metinsizdir; dilli olanlar afiş
    /// yazısı taşır. Başlığı zaten logo ya da metinle biz basıyoruz, arka
    /// planda ikinci bir başlık istemiyoruz.
    private static func textlessFirst(_ images: [ImagesResponse.Item]) -> ImagesResponse.Item? {
        let textless = images.filter { $0.language == nil }
        let pool = textless.isEmpty ? images : textless
        return pool.max { ($0.voteAverage ?? 0) < ($1.voteAverage ?? 0) }
    }

    /// Seçili dile göre (Türkçe ise önce TR sonra EN, İngilizce ise önce EN sonra TR) logo seçer.
    /// SVG'ler eleniyor: `UIImage` vektör TMDB logolarını açamıyor.
    private static func bestLogo(from logos: [ImagesResponse.Item], language: AppLanguage) -> ImagesResponse.Item? {
        let usable = logos.filter { !$0.path.lowercased().hasSuffix(".svg") }
        guard !usable.isEmpty else { return nil }

        let primary = language.effectiveLanguageCode
        let secondary = (primary == "tr") ? "en" : "tr"

        return usable.sorted { first, second in
            let firstLanguage = first.language ?? ""
            let secondLanguage = second.language ?? ""
            if firstLanguage == primary, secondLanguage != primary { return true }
            if firstLanguage != primary, secondLanguage == primary { return false }
            if firstLanguage == secondary, secondLanguage != secondary { return true }
            if firstLanguage != secondary, secondLanguage == secondary { return false }
            return (first.voteAverage ?? 0) > (second.voteAverage ?? 0)
        }.first
    }

    static func imageURL(_ path: String?, size: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    // MARK: - İstek

    private func get(path: String, query: [String: String]) async -> Data? {
        guard let apiKey = Self.apiKey,
              var components = URLComponents(string: "https://api.themoviedb.org/3/" + path)
        else { return nil }

        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        if !Self.usesBearerToken {
            items.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components.queryItems = items
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        if Self.usesBearerToken {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else { return nil }
        return data
    }

    // MARK: - Başlık temizleme

    private static func cacheKey(title: String, isSeries: Bool, languageCode: String) -> String {
        "\(languageCode)_\(isSeries ? "tv" : "movie")_\(title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// Sağlayıcı başlıkları TMDB'ye doğrudan uymuyor:
    /// "Malefiz: Kötülüğün Gücü tr|en |4K (2019)" → ("Malefiz: Kötülüğün Gücü", "2019")
    static func cleanTitleAndYear(from raw: String) -> (title: String, year: String?) {
        var year: String?
        if let match = raw.range(of: #"\((19|20)\d{2}\)"#, options: .regularExpression) {
            year = String(raw[match].dropFirst().dropLast())
        }

        var clean = raw
        for pattern in [
            #"\[.*?\]"#,
            #"\(.*?\)"#,
            // |4K, |TR, tr|en gibi kalite ve dil ekleri
            #"\|\s*[A-Za-zÇĞİÖŞÜçğıöşü0-9]{1,6}"#,
            #"(?i)\b(4k|fhd|hd|uhd|sd|dual|dublaj|altyazılı|altyazi|netflix|bluray|web-dl)\b"#,
        ] {
            clean = clean.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        clean = clean.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: " -|._"))
        return (clean.trimmingCharacters(in: .whitespacesAndNewlines), year)
    }
}

// MARK: - Yanıt modelleri

struct SearchResponse: Decodable {
    var results: [Item]

    /// Film ve dizi uçları farklı anahtar kullanıyor; ikisini de okuyoruz.
    struct Item: Decodable {
        var id: Int
        var overview: String?
        var voteAverage: Double?
        var title: String?
        var name: String?
        var originalTitleValue: String?
        var originalNameValue: String?
        var releaseDate: String?
        var firstAirDate: String?
        var posterPath: String?
        var backdropPath: String?

        var displayTitle: String? { title ?? name }
        var originalTitle: String? { originalTitleValue ?? originalNameValue }
        var releaseYear: String? {
            let source = releaseDate ?? firstAirDate
            guard let source, source.count >= 4 else { return nil }
            return String(source.prefix(4))
        }

        enum CodingKeys: String, CodingKey {
            case id, overview, title, name
            case voteAverage = "vote_average"
            case originalTitleValue = "original_title"
            case originalNameValue = "original_name"
            case releaseDate = "release_date"
            case firstAirDate = "first_air_date"
            case posterPath = "poster_path"
            case backdropPath = "backdrop_path"
        }
    }
}

private struct ImagesResponse: Decodable {
    var logos: [Item]
    var posters: [Item]
    var backdrops: [Item]

    struct Item: Decodable {
        var path: String
        var language: String?
        var voteAverage: Double?

        enum CodingKeys: String, CodingKey {
            case path = "file_path"
            case language = "iso_639_1"
            case voteAverage = "vote_average"
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        logos = ((try? container.decodeIfPresent([Item].self, forKey: .logos)) ?? nil) ?? []
        posters = ((try? container.decodeIfPresent([Item].self, forKey: .posters)) ?? nil) ?? []
        backdrops = ((try? container.decodeIfPresent([Item].self, forKey: .backdrops)) ?? nil) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case logos, posters, backdrops
    }
}

struct TMDBDetailResponse: Decodable {
    var id: Int?
    var overview: String?
    var tagline: String?
    var voteAverage: Double?
    var voteCount: Int?
    var title: String?
    var name: String?
    var originalTitle: String?
    var originalName: String?
    var originalLanguage: String?
    var releaseDate: String?
    var firstAirDate: String?
    var runtime: Int?
    var episodeRunTime: [Int]?
    var status: String?
    var genres: [GenreItem]?
    var productionCountries: [CountryItem]?
    var credits: CreditsResponse?
    var videos: VideosResponse?

    var belongsToCollection: CollectionItem?
    var recommendations: RecommendationsResponse?
    var similar: RecommendationsResponse?

    struct CollectionItem: Decodable, Sendable {
        var id: Int
        var name: String?
        var posterPath: String?
        var backdropPath: String?
        enum CodingKeys: String, CodingKey {
            case id, name
            case posterPath = "poster_path"
            case backdropPath = "backdrop_path"
        }
    }

    struct RecommendationsResponse: Decodable, Sendable {
        var results: [SearchResponse.Item]?
    }

    struct CollectionResponse: Decodable, Sendable {
        var id: Int?
        var name: String?
        var parts: [SearchResponse.Item]?
    }

    struct GenreItem: Decodable {
        var id: Int?
        var name: String
    }

    struct CountryItem: Decodable {
        var name: String?
        var iso31661: String?

        enum CodingKeys: String, CodingKey {
            case name
            case iso31661 = "iso_3166_1"
        }
    }

    struct CreditsResponse: Decodable {
        var cast: [CastItem]?
        var crew: [CrewItem]?

        struct CastItem: Decodable {
            var name: String
            var character: String?
            var order: Int?
            var profilePath: String?

            // Decoder snake_case dönüşümü yapmıyor; eşleme elle veriliyor.
            enum CodingKeys: String, CodingKey {
                case name, character, order
                case profilePath = "profile_path"
            }
        }

        struct CrewItem: Decodable {
            var name: String
            var job: String?
            var department: String?
        }
    }

    struct VideosResponse: Decodable {
        var results: [VideoItem]?

        struct VideoItem: Decodable {
            var key: String
            var site: String
            var type: String
            var official: Bool?
            var language: String?

            enum CodingKeys: String, CodingKey {
                case key, site, type, official
                case language = "iso_639_1"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, overview, tagline, status, genres, credits, videos
        case belongsToCollection = "belongs_to_collection"
        case recommendations, similar
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case title, name
        case originalTitle = "original_title"
        case originalName = "original_name"
        case originalLanguage = "original_language"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case runtime
        case episodeRunTime = "episode_run_time"
        case productionCountries = "production_countries"
    }
}
