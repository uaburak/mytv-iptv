import Foundation

/// TMDB'den alınan görsel ve künye zenginleştirmesi.
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
    var trailerURL: URL?
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
        return URLSession(configuration: configuration)
    }()

    private let decoder = JSONDecoder()
    /// Başlık bazlı önbellek. Aynı içerik için ikinci kez arama isteği gitmiyor;
    /// eşleşme bulunamayanlar da hatırlanıyor.
    private var cache: [String: TMDBMetadata?] = [:]
    private let store = LocalStore(folder: "tmdb")
    private let cacheKey = "metadata_v2"

    private init() {
        if let saved = store.read([String: TMDBMetadata].self, key: cacheKey) {
            cache = saved.mapValues { Optional($0) }
        }
    }

    // MARK: - Genel arayüz

    func metadata(for item: MediaItem, language: AppLanguage = AppLanguage.current) async -> TMDBMetadata? {
        guard item.kind != .live, Self.apiKey != nil else { return nil }
        let isSeries = item.kind == .series
        let langCode = language.effectiveLanguageCode

        // Sağlayıcı kimliği veriyorsa arama yapmıyoruz: isim eşleştirmesi
        // "Kül" gibi kısa başlıklarda popülerlik sıralaması yüzünden yanlış
        // filme ("Avatar: Ateş ve Kül") düşebiliyor.
        if let tmdbID = item.tmdbID, !isSeries {
            let key = "\(langCode)_movie_id_\(tmdbID)"
            if let cached = cache[key] { return cached }
            let result = await fetchByID(tmdbID, mediaType: "movie", language: language)
            cache[key] = result
            persist()
            return result
        }

        let key = Self.cacheKey(title: item.title, isSeries: isSeries, languageCode: langCode)
        if let cached = cache[key] { return cached }

        let result = await fetch(title: item.title, isSeries: isSeries, language: language)
        cache[key] = result
        persist()
        return result
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
            query: ["language": language.tmdbLanguageCode, "append_to_response": "credits,videos"]
        ) else {
            return nil
        }
        return try? decoder.decode(TMDBDetailResponse.self, from: data)
    }

    private func makeMetadata(
        details: TMDBDetailResponse?,
        images: (logo: URL?, poster: URL?, backdrop: URL?)
    ) -> TMDBMetadata {
        let releaseDate = details?.releaseDate ?? details?.firstAirDate
        let releaseYear = releaseDate.flatMap { str -> String? in
            guard str.count >= 4 else { return nil }
            return String(str.prefix(4))
        }

        let castList = details?.credits?.cast?
            .sorted(by: { ($0.order ?? 99) < ($1.order ?? 99) })
            .prefix(12)
            .map(\.name) ?? []

        let director = details?.credits?.crew?
            .first(where: { $0.job == "Director" })?.name

        let trailerKey = details?.videos?.results?
            .first(where: { $0.site.lowercased() == "youtube" && ($0.type == "Trailer" || $0.type == "Teaser") })?.key
        let trailerURL = trailerKey.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") }

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
            cast: Array(castList),
            trailerURL: trailerURL
        )
    }

    private func persist() {
        let snapshot = cache.compactMapValues { $0 }
        store.write(snapshot, key: cacheKey)
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

    private static func imageURL(_ path: String?, size: String) -> URL? {
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
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, overview, tagline, status, genres, credits, videos
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
