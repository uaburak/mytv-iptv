import Foundation

/// Xtream Codes `player_api.php` istemcisi.
///
/// Sunucular arasında alan adları ve tipleri oynadığı için çözümleme
/// `LooseDecoding` sarmalayıcıları üzerinden yapılıyor; tek bir bozuk kayıt
/// bütün listeyi düşürmesin diye liste uçları kayıt kayıt toleranslı okunuyor.
actor XtreamProvider: ContentProvider {
    private let baseURL: URL
    private let username: String
    private let password: String
    private let session: URLSession
    private let decoder = JSONDecoder()

    nonisolated let sourceID: String

    /// Sunucunun canlı yayınlarda izin verdiği kapsayıcı. `validate()` sırasında
    /// `allowed_output_formats` alanından okunuyor: bazı paneller yalnızca "ts"
    /// veriyor ve ".m3u8" istendiğinde 404 dönüyor.
    /// Bir kez öğrenildikten sonra kalıcı saklanıyor; böylece her açılışta
    /// yalnızca bunun için doğrulama isteği atmak gerekmiyor.
    private var liveExtension: String {
        didSet { UserDefaults.standard.set(liveExtension, forKey: Self.formatKey(sourceID)) }
    }

    /// Biçim sunucudan okunana kadar false. Katalog önbellekten geldiğinde
    /// `validate()` hiç çalışmayabildiği için oynatma anında da kontrol ediyoruz.
    private var didResolveOutputFormat: Bool

    private nonisolated static func formatKey(_ sourceID: String) -> String {
        "kctv.liveFormat.\(sourceID)"
    }

    init(host: String, username: String, password: String, sourceID: String) throws {
        guard let baseURL = Self.normalizedBaseURL(from: host) else {
            throw ContentError.network("Sunucu adresi geçersiz: \(host)")
        }
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.sourceID = sourceID

        if let saved = UserDefaults.standard.string(forKey: Self.formatKey(sourceID)) {
            liveExtension = saved
            didResolveOutputFormat = true
        } else {
            liveExtension = "ts"
            didResolveOutputFormat = false
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = true
        // Kategori/liste yanıtları megabaytlarca olabiliyor; bellekte tutmuyoruz.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    /// "1.2.3.4:8080", "http://host:8080/c/" gibi girdileri tek biçime indirger.
    nonisolated static func normalizedBaseURL(from host: String) -> URL? {
        var text = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        // Kullanıcı doğrudan player_api/get.php bağlantısını yapıştırdıysa kökü al.
        for suffix in ["/player_api.php", "/get.php", "/panel_api.php", "/c"] where text.lowercased().hasSuffix(suffix) {
            text.removeLast(suffix.count)
        }
        guard var components = URLComponents(string: text) else { return nil }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    // MARK: - İstek kurulumu

    private func apiURL(action: String?, extra: [String: String] = [:]) throws -> URL {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("player_api.php"), resolvingAgainstBaseURL: false) else {
            throw ContentError.network("İstek adresi oluşturulamadı.")
        }
        var items = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
        ]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        items.append(contentsOf: extra.map { URLQueryItem(name: $0.key, value: $0.value) })
        components.queryItems = items
        guard let url = components.url else { throw ContentError.network("İstek adresi oluşturulamadı.") }
        return url
    }

    private func data(action: String?, extra: [String: String] = [:]) async throws -> Data {
        let url = try apiURL(action: action, extra: extra)
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                if http.statusCode == 401 || http.statusCode == 403 { throw ContentError.invalidCredentials }
                throw ContentError.badResponse(status: http.statusCode)
            }
            return data
        } catch let error as ContentError {
            throw error
        } catch {
            throw ContentError.network(error.localizedDescription)
        }
    }

    /// Dizi çözümlemesi: önce tamamı, olmazsa kayıt kayıt.
    /// Tek bir bozuk eleman yüzünden bütün kategoriyi kaybetmemek için.
    private func decodeList<T: Decodable>(_ type: T.Type, from data: Data) -> [T] {
        if let values = try? decoder.decode([T].self, from: data) { return values }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return raw.compactMap { element in
            guard let elementData = try? JSONSerialization.data(withJSONObject: element) else { return nil }
            return try? decoder.decode(T.self, from: elementData)
        }
    }

    // MARK: - ContentProvider

    func validate() async throws -> ProviderAccount {
        let payload = try await data(action: nil)
        guard let response = try? decoder.decode(XtreamAuthResponse.self, from: payload),
              let info = response.userInfo else {
            throw ContentError.invalidCredentials
        }
        // auth == 0 ya da status "Disabled"/"Banned" -> giriş reddedildi.
        if info.auth == 0 { throw ContentError.invalidCredentials }
        let status = info.status?.lowercased()
        if status == "banned" || status == "disabled" { throw ContentError.invalidCredentials }

        let account = ProviderAccount(
            username: info.username ?? username,
            status: info.status,
            expiresAt: LooseParse.date(info.expDate),
            maxConnections: info.maxConnections,
            activeConnections: info.activeCons,
            isTrial: (info.isTrial ?? 0) == 1,
            serverURL: baseURL.absoluteString
        )
        if account.isExpired { throw ContentError.accountExpired }

        let formats = info.allowedOutputFormats.map { $0.lowercased() }
        if !formats.isEmpty {
            // HLS varsa tercih ediyoruz; yoksa sunucunun verdiği ilk biçim.
            liveExtension = formats.contains("m3u8") ? "m3u8" : (formats.first ?? "ts")
        }
        didResolveOutputFormat = true
        return account
    }

    func categories(for kind: MediaKind) async throws -> [MediaCategory] {
        let action = switch kind {
        case .live: "get_live_categories"
        case .movie: "get_vod_categories"
        case .series: "get_series_categories"
        }
        let payload = try await data(action: action)
        return decodeList(XtreamCategoryDTO.self, from: payload).compactMap { dto in
            guard let id = dto.categoryID, let name = dto.categoryName else { return nil }
            return MediaCategory(id: id, name: name, kind: kind)
        }
    }

    func items(kind: MediaKind, categoryID: String?) async throws -> [MediaItem] {
        let action = switch kind {
        case .live: "get_live_streams"
        case .movie: "get_vod_streams"
        case .series: "get_series"
        }
        var extra: [String: String] = [:]
        if let categoryID { extra["category_id"] = categoryID }
        let payload = try await data(action: action, extra: extra)
        return decodeList(XtreamStreamDTO.self, from: payload).compactMap { convert($0, kind: kind) }
    }

    func detail(for item: MediaItem) async throws -> MediaDetail {
        switch item.kind {
        case .live:
            return MediaDetail(item: item)
        case .movie:
            let payload = try await data(action: "get_vod_info", extra: ["vod_id": item.streamReference])
            guard let response = try? decoder.decode(XtreamVODInfoResponse.self, from: payload) else {
                return MediaDetail(item: item)
            }
            return movieDetail(from: response, base: item)
        case .series:
            let payload = try await data(action: "get_series_info", extra: ["series_id": item.streamReference])
            guard let response = try? decoder.decode(XtreamSeriesInfoResponse.self, from: payload) else {
                return MediaDetail(item: item)
            }
            return seriesDetail(from: response, base: item)
        }
    }

    func shortEPG(for item: MediaItem) async throws -> [EPGEntry] {
        guard item.kind == .live else { return [] }
        let payload = try await data(
            action: "get_short_epg",
            extra: ["stream_id": item.streamReference, "limit": "8"]
        )
        guard let response = try? decoder.decode(XtreamEPGResponse.self, from: payload) else { return [] }
        return response.listings.compactMap { listing in
            guard let start = epgDate(listing.startTimestamp ?? listing.start),
                  let end = epgDate(listing.stopTimestamp ?? listing.end) else { return nil }
            return EPGEntry(
                id: listing.id ?? UUID().uuidString,
                title: Self.decodeBase64(listing.title) ?? listing.title ?? "Program",
                description: Self.decodeBase64(listing.description) ?? listing.description,
                start: start,
                end: end
            )
        }
        .sorted { $0.start < $1.start }
    }

    func playbackURL(for item: MediaItem) async throws -> URL {
        let segment = switch item.kind {
        case .live: "live"
        case .movie: "movie"
        case .series: "series"
        }
        // Canlı yayında kapsayıcıyı sunucu belirler; VOD'da kaydın kendi uzantısı.
        if item.kind == .live, !didResolveOutputFormat {
            // Katalog diskten geldiyse hesap doğrulaması hiç çalışmamış olabilir.
            _ = try? await validate()
        }
        let ext = item.kind == .live ? liveExtension : (item.containerExtension ?? "mp4")
        return try streamURL(segment: segment, reference: item.streamReference, ext: ext)
    }

    func playbackURL(for episode: Episode) async throws -> URL {
        try streamURL(
            segment: "series",
            reference: episode.streamReference,
            ext: episode.containerExtension ?? "mp4"
        )
    }

    private func streamURL(segment: String, reference: String, ext: String) throws -> URL {
        // Sağlayıcı doğrudan bağlantı verdiyse onu kullan.
        if reference.lowercased().hasPrefix("http"), let direct = URL(string: reference) { return direct }
        let url = baseURL
            .appendingPathComponent(segment)
            .appendingPathComponent(username)
            .appendingPathComponent(password)
            .appendingPathComponent("\(reference).\(ext)")
        return url
    }

    // MARK: - Dönüştürme

    private func convert(_ dto: XtreamStreamDTO, kind: MediaKind) -> MediaItem? {
        guard let reference = dto.identifier, let name = dto.name else { return nil }
        let artwork = LooseParse.url(dto.artwork)
        let backdrop = LooseParse.url(dto.backdropPath.first) ?? artwork

        return MediaItem(
            id: MediaID(source: sourceID, kind: kind, raw: reference),
            title: name,
            posterURL: artwork,
            backdropURL: backdrop,
            categoryID: dto.categoryID,
            categoryName: nil,
            year: LooseParse.year(from: dto.releaseText),
            rating: dto.rating,
            genres: LooseParse.genres(dto.genre),
            plot: dto.plot,
            durationSeconds: dto.episodeRunTime.map { $0 * 60 },
            addedAt: LooseParse.date(dto.added ?? dto.lastModified),
            isAdult: Self.looksAdult(name),
            streamReference: reference,
            containerExtension: dto.containerExtension,
            channelNumber: kind == .live ? dto.num : nil,
            cast: LooseParse.genres(dto.cast),
            director: dto.director,
            trailerURL: Self.youtubeURL(dto.youtubeTrailer)
        )
    }

    private func movieDetail(from response: XtreamVODInfoResponse, base: MediaItem) -> MediaDetail {
        var item = base
        let info = response.info
        item.plot = info?.plot ?? info?.description ?? item.plot
        item.rating = info?.rating ?? item.rating
        item.durationSeconds = info?.durationSecs ?? item.durationSeconds
        item.title = info?.name ?? item.title
        item.genres = LooseParse.genres(info?.genre).isEmpty ? item.genres : LooseParse.genres(info?.genre)
        item.year = LooseParse.year(from: info?.releasedate ?? info?.releaseDate) ?? item.year
        item.posterURL = LooseParse.url(info?.movieImage ?? info?.coverBig) ?? item.posterURL
        item.backdropURL = LooseParse.url(info?.backdropPath.first) ?? item.backdropURL ?? item.posterURL
        item.containerExtension = response.movieData?.containerExtension ?? item.containerExtension
        item.tmdbID = info?.tmdbID ?? item.tmdbID

        return MediaDetail(
            item: item,
            cast: LooseParse.genres(info?.cast ?? info?.actors).nilIfEmptyList ?? item.cast,
            director: info?.director ?? item.director,
            country: info?.country,
            releaseDate: LooseParse.date(info?.releasedate ?? info?.releaseDate),
            trailerURL: Self.youtubeURL(info?.youtubeTrailer),
            seasons: [],
            extraBackdrops: info?.backdropPath.compactMap(LooseParse.url) ?? []
        )
    }

    private func seriesDetail(from response: XtreamSeriesInfoResponse, base: MediaItem) -> MediaDetail {
        var item = base
        let info = response.info
        item.plot = info?.plot ?? item.plot
        item.rating = info?.rating ?? item.rating
        item.genres = LooseParse.genres(info?.genre).isEmpty ? item.genres : LooseParse.genres(info?.genre)
        item.year = LooseParse.year(from: info?.releaseDate ?? info?.releasedate) ?? item.year
        item.posterURL = LooseParse.url(info?.cover) ?? item.posterURL
        item.backdropURL = LooseParse.url(info?.backdropPath.first) ?? item.backdropURL ?? item.posterURL

        // Sezon başlıkları `seasons` dizisinde, bölümler ayrı sözlükte geliyor.
        // Bazı sunucular `seasons`'ı hiç doldurmuyor; o zaman bölüm anahtarlarından üretiyoruz.
        let seasonNames = Dictionary(
            response.seasons.compactMap { dto -> (Int, String)? in
                guard let number = dto.seasonNumber else { return nil }
                return (number, dto.name ?? "\(number). Sezon")
            },
            uniquingKeysWith: { first, _ in first }
        )
        let seasonCovers = Dictionary(
            response.seasons.compactMap { dto -> (Int, URL)? in
                guard let number = dto.seasonNumber,
                      let cover = LooseParse.url(dto.coverBig ?? dto.cover) else { return nil }
                return (number, cover)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let runtimeSeconds = info?.episodeRunTime.map { $0 * 60 }
        let seasons: [Season] = response.episodes
            .compactMap { key, episodes -> Season? in
                let number = Int(key) ?? episodes.first?.season ?? 1
                let converted = episodes
                    .compactMap {
                        convert(
                            $0,
                            seriesID: item.id,
                            fallbackSeason: number,
                            runtimeSeconds: runtimeSeconds,
                            seasonCover: seasonCovers[number] ?? item.posterURL
                        )
                    }
                    .sorted { $0.episodeNumber < $1.episodeNumber }
                guard !converted.isEmpty else { return nil }
                return Season(
                    id: "\(item.id.raw).s\(number)",
                    number: number,
                    name: seasonNames[number] ?? "\(number). Sezon",
                    posterURL: seasonCovers[number] ?? item.posterURL,
                    episodes: converted
                )
            }
            .sorted { $0.number < $1.number }

        return MediaDetail(
            item: item,
            cast: LooseParse.genres(info?.cast).nilIfEmptyList ?? item.cast,
            director: info?.director ?? item.director,
            country: nil,
            releaseDate: LooseParse.date(info?.releaseDate ?? info?.releasedate),
            trailerURL: Self.youtubeURL(info?.youtubeTrailer),
            seasons: seasons,
            extraBackdrops: info?.backdropPath.compactMap(LooseParse.url) ?? []
        )
    }

    private func convert(
        _ dto: XtreamSeriesInfoResponse.EpisodeDTO,
        seriesID: MediaID,
        fallbackSeason: Int,
        runtimeSeconds: Int?,
        seasonCover: URL?
    ) -> Episode? {
        guard let id = dto.id else { return nil }
        let number = dto.episodeNum ?? 0
        let cleanTitle = Self.cleanEpisodeTitle(dto.title, episodeNumber: number)
        return Episode(
            id: id,
            seriesID: seriesID,
            seasonNumber: dto.season ?? fallbackSeason,
            episodeNumber: number,
            title: cleanTitle,
            plot: dto.info?.plot,
            stillURL: LooseParse.url(dto.info?.movieImage ?? dto.info?.coverBig) ?? seasonCover,
            durationSeconds: dto.info?.durationSecs ?? Self.seconds(from: dto.info?.duration) ?? runtimeSeconds,
            airDate: LooseParse.date(dto.info?.releaseDate ?? dto.added),
            streamReference: id,
            containerExtension: dto.containerExtension
        )
    }

    // MARK: - Yardımcılar

    private func epgDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        if let epoch = Double(text), epoch > 100_000 { return Date(timeIntervalSince1970: epoch) }
        return Self.epgFormatter.date(from: text)
    }

    /// "01:32:10" biçimindeki süreyi saniyeye çevirir.
    private nonisolated static func seconds(from text: String?) -> Int? {
        guard let text, text.contains(":") else { return nil }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    /// Sağlayıcılar bölüm adını "Dizi Adı - S01E01 - 1. Bölüm" gibi gönderiyor.
    /// Sezon/bölüm bilgisi arayüzde ayrıca gösterildiği için öneki atıyoruz.
    nonisolated static func cleanEpisodeTitle(_ raw: String?, episodeNumber: Int) -> String {
        let fallback = "\(episodeNumber). Bölüm"
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return fallback
        }
        let patterns = [
            #"^.*?[\s\-\._]*[Ss]\d{1,2}[\s\-\._]*[EeBb]\d{1,3}[\s\-\._:]*"#,
            #"^[Ss]ezon\s*\d+[\s\-\._:]*[Bb]ölüm\s*\d+[\s\-\._:]*"#,
            #"^\d+\.\s*[Bb]ölüm[\s\-\._:]*"#,
            #"^[Bb]ölüm\s*\d+[\s\-\._:]*"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " -._:"))
        }
        return text.isEmpty ? fallback : text
    }

    private nonisolated static func decodeBase64(_ text: String?) -> String? {
        guard let text, let data = Data(base64Encoded: text), let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return decoded.isEmpty ? nil : decoded
    }

    private nonisolated static func youtubeURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.lowercased().hasPrefix("http") { return URL(string: raw) }
        return URL(string: "https://www.youtube.com/watch?v=\(raw)")
    }

    private nonisolated static func looksAdult(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return ["xxx", "adult", "+18", "18+", "erotik"].contains { lowered.contains($0) }
    }

    private nonisolated static let epgFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
