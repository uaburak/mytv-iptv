import Foundation

public enum XtreamAPIError: LocalizedError {
    case invalidURL
    case authenticationFailed
    case networkError(String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Geçersiz sunucu adresi."
        case .authenticationFailed: return "Giriş başarısız. Kullanıcı adı veya şifre hatalı."
        case .networkError(let msg): return "Ağ hatası: \(msg)"
        case .decodingError(let msg): return "Veri ayrıştırma hatası: \(msg)"
        }
    }
}

public struct XtreamAuthResponse: Codable {
    public struct UserInfo: Codable {
        public let username: String?
        public let password: String?
        public let auth: Int?
        public let status: String?
        public let expDate: String?
        public let maxConnections: String?

        enum CodingKeys: String, CodingKey {
            case username, password, auth, status
            case expDate = "exp_date"
            case maxConnections = "max_connections"
        }
    }

    public struct ServerInfo: Codable {
        public let url: String?
        public let port: String?
        public let httpsPort: String?
        public let serverProtocol: String?
        public let timezone: String?

        enum CodingKeys: String, CodingKey {
            case url, port, timezone
            case httpsPort = "https_port"
            case serverProtocol = "server_protocol"
        }
    }

    public let userInfo: UserInfo?
    public let serverInfo: ServerInfo?

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
        case serverInfo = "server_info"
    }
}

public final class XtreamCodesAPIService: Sendable {
    public static let shared = XtreamCodesAPIService()

    private let userAgent = "Mozilla/5.0 (AppleTV; tvOS 17.0) IPTVSmarters/1.0"

    private init() {}

    private func makeURL(serverUrl: String, username: String, password: String, action: String? = nil, extraParams: String = "") -> URL? {
        var base = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.lowercased().hasPrefix("http://") && !base.lowercased().hasPrefix("https://") {
            base = "http://" + base
        }
        if base.hasSuffix("/") {
            base.removeLast()
        }

        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? password

        var urlString = "\(base)/player_api.php?username=\(encodedUsername)&password=\(encodedPassword)"
        if let action {
            urlString += "&action=\(action)"
        }
        if !extraParams.isEmpty {
            urlString += extraParams
        }
        return URL(string: urlString)
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw XtreamAPIError.networkError("Sunucudan geçerli bir HTTP yanıtı alınamadı.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw XtreamAPIError.networkError("Sunucu HTTP \(httpResponse.statusCode) hatası döndürdü.")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw XtreamAPIError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - API Calls

    public func authenticate(serverUrl: String, username: String, password: String) async throws -> XtreamAuthResponse {
        guard let url = makeURL(serverUrl: serverUrl, username: username, password: password) else {
            throw XtreamAPIError.invalidURL
        }
        let auth: XtreamAuthResponse = try await fetch(url)
        guard let userInfo = auth.userInfo, userInfo.auth == 1, userInfo.status == "Active" else {
            throw XtreamAPIError.authenticationFailed
        }
        return auth
    }

    public func getLiveCategories(account: Account) async throws -> [MediaCategory] {
        guard let url = makeURL(serverUrl: account.serverUrl, username: account.username, password: account.password, action: "get_live_categories") else {
            return []
        }
        struct CatDTO: Decodable {
            let category_id: DynamicID
            let category_name: String
        }
        let lossy: LossyDecodableArray<CatDTO> = (try? await fetch(url)) ?? LossyDecodableArray(elements: [])
        return lossy.elements.map { MediaCategory(id: $0.category_id.stringValue, name: $0.category_name, type: .live) }
    }

    public func getLiveStreams(account: Account) async throws -> [Channel] {
        guard let url = makeURL(serverUrl: account.serverUrl, username: account.username, password: account.password, action: "get_live_streams") else {
            return []
        }
        struct StreamDTO: Decodable {
            let num: Int?
            let name: String
            let stream_id: DynamicID
            let stream_icon: String?
            let epg_channel_id: String?
            let category_id: DynamicID?
        }
        let lossy: LossyDecodableArray<StreamDTO> = (try? await fetch(url)) ?? LossyDecodableArray(elements: [])

        var base = account.serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.lowercased().hasPrefix("http://") && !base.lowercased().hasPrefix("https://") {
            base = "http://" + base
        }
        if base.hasSuffix("/") { base.removeLast() }

        return lossy.elements.map { dto in
            let streamUrl = "\(base)/live/\(account.username)/\(account.password)/\(dto.stream_id.stringValue).ts"
            return Channel(
                id: dto.stream_id.stringValue,
                name: dto.name,
                streamIcon: dto.stream_icon,
                streamUrl: streamUrl,
                categoryId: dto.category_id?.stringValue ?? "0",
                epgChannelId: dto.epg_channel_id,
                num: dto.num
            )
        }
    }

    public func getVODCategories(account: Account) async throws -> [MediaCategory] {
        guard let url = makeURL(serverUrl: account.serverUrl, username: account.username, password: account.password, action: "get_vod_categories") else {
            return []
        }
        struct CatDTO: Decodable {
            let category_id: DynamicID
            let category_name: String
        }
        let lossy: LossyDecodableArray<CatDTO> = (try? await fetch(url)) ?? LossyDecodableArray(elements: [])
        return lossy.elements.map { MediaCategory(id: $0.category_id.stringValue, name: $0.category_name, type: .movie) }
    }

    public func getVODStreams(account: Account) async throws -> [VODItem] {
        guard let url = makeURL(serverUrl: account.serverUrl, username: account.username, password: account.password, action: "get_vod_streams") else {
            return []
        }
        struct VODDTO: Decodable {
            let stream_id: DynamicID
            let name: String
            let stream_icon: String?
            let rating: DynamicRating?
            let release_date: DynamicString?
            let releaseDate: DynamicString?
            let episode_run_time: DynamicString?
            let plot: String?
            let category_id: DynamicID?
            let container_extension: String?
            let genre: String?
            let backdrop_path: DynamicBackdrop?
        }
        let lossy: LossyDecodableArray<VODDTO> = (try? await fetch(url)) ?? LossyDecodableArray(elements: [])

        var base = account.serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.lowercased().hasPrefix("http://") && !base.lowercased().hasPrefix("https://") {
            base = "http://" + base
        }
        if base.hasSuffix("/") { base.removeLast() }

        return lossy.elements.map { dto in
            let ext = dto.container_extension ?? "mp4"
            let streamUrl = "\(base)/movie/\(account.username)/\(account.password)/\(dto.stream_id.stringValue).\(ext)"
            return VODItem(
                id: dto.stream_id.stringValue,
                name: dto.name,
                streamIcon: dto.stream_icon,
                backdropUrl: dto.backdrop_path?.firstUrl ?? dto.stream_icon,
                rating: dto.rating?.stringValue,
                releaseDate: dto.release_date?.stringValue ?? dto.releaseDate?.stringValue,
                duration: dto.episode_run_time?.stringValue,
                overview: dto.plot,
                streamUrl: streamUrl,
                categoryId: dto.category_id?.stringValue ?? "0",
                type: .movie,
                containerExtension: ext,
                genre: dto.genre
            )
        }
    }

    public func getSeriesCategories(account: Account) async throws -> [MediaCategory] {
        guard let url = makeURL(serverUrl: account.serverUrl, username: account.username, password: account.password, action: "get_series_categories") else {
            return []
        }
        struct CatDTO: Decodable {
            let category_id: DynamicID
            let category_name: String
        }
        let lossy: LossyDecodableArray<CatDTO> = (try? await fetch(url)) ?? LossyDecodableArray(elements: [])
        return lossy.elements.map { MediaCategory(id: $0.category_id.stringValue, name: $0.category_name, type: .series) }
    }

    public func getSeries(account: Account) async throws -> [VODItem] {
        guard let url = makeURL(serverUrl: account.serverUrl, username: account.username, password: account.password, action: "get_series") else {
            return []
        }
        struct SeriesDTO: Decodable {
            let series_id: DynamicID
            let name: String
            let cover: String?
            let plot: String?
            let rating: DynamicRating?
            let release_date: DynamicString?
            let releaseDate: DynamicString?
            let category_id: DynamicID?
            let genre: String?
            let backdrop_path: DynamicBackdrop?
        }
        let lossy: LossyDecodableArray<SeriesDTO> = (try? await fetch(url)) ?? LossyDecodableArray(elements: [])

        return lossy.elements.map { dto in
            VODItem(
                id: dto.series_id.stringValue,
                name: dto.name,
                streamIcon: dto.cover,
                backdropUrl: dto.backdrop_path?.firstUrl ?? dto.cover,
                rating: dto.rating?.stringValue,
                releaseDate: dto.release_date?.stringValue ?? dto.releaseDate?.stringValue,
                duration: nil,
                overview: dto.plot,
                streamUrl: "",
                categoryId: dto.category_id?.stringValue ?? "0",
                type: .series,
                containerExtension: nil,
                genre: dto.genre
            )
        }
    }

    public struct VODDetailResponse: Sendable {
        public let movieImage: String?
        public let backdropUrl: String?
        public let plot: String?
        public let cast: String?
        public let director: String?
        public let genre: String?
        public let releaseDate: String?
        public let duration: String?
        public let rating: String?
        public let youtubeTrailer: String?
        public let country: String?
        public let age: String?
        public let mpaaRating: String?
    }

    public struct SeriesDetailResponse: Sendable {
        public let cover: String?
        public let backdropUrl: String?
        public let plot: String?
        public let cast: String?
        public let director: String?
        public let genre: String?
        public let releaseDate: String?
        public let rating: String?
        public let youtubeTrailer: String?
        public let episodes: [Episode]
        public let country: String?
        public let age: String?
        public let mpaaRating: String?
        public let seasons: [SeasonInfo]
    }

    public func getVODInfo(account: Account, vodId: String) async throws -> VODDetailResponse? {
        guard let url = makeURL(serverUrl: account.serverUrl, username: account.username, password: account.password, action: "get_vod_info", extraParams: "&vod_id=\(vodId)") else {
            return nil
        }

        struct Resp: Decodable {
            let info: InfoDTO?
        }
        struct InfoDTO: Decodable {
            let movie_image: String?
            let backdrop_path: DynamicBackdrop?
            let plot: String?
            let cast: String?
            let director: String?
            let genre: String?
            let release_date: DynamicString?
            let releasedate: DynamicString?
            let duration: DynamicString?
            let episode_run_time: DynamicString?
            let rating: DynamicRating?
            let youtube_trailer: String?
            let country: String?
            let age: String?
            let mpaa_rating: String?
        }

        let resp: Resp? = try? await fetch(url)
        guard let info = resp?.info else { return nil }

        return VODDetailResponse(
            movieImage: info.movie_image,
            backdropUrl: info.backdrop_path?.firstUrl,
            plot: info.plot,
            cast: info.cast,
            director: info.director,
            genre: info.genre,
            releaseDate: info.release_date?.stringValue ?? info.releasedate?.stringValue,
            duration: info.duration?.stringValue ?? info.episode_run_time?.stringValue,
            rating: info.rating?.stringValue,
            youtubeTrailer: info.youtube_trailer,
            country: info.country,
            age: info.age,
            mpaaRating: info.mpaa_rating
        )
    }

    public func getSeriesDetails(account: Account, seriesId: String) async throws -> SeriesDetailResponse? {
        guard let url = makeURL(serverUrl: account.serverUrl, username: account.username, password: account.password, action: "get_series_info", extraParams: "&series_id=\(seriesId)") else {
            return nil
        }

        struct SeriesInfoResponse: Decodable {
            let seasons: [SeasonDTO]?
            let info: SeriesInfoDTO?
            let episodes: [String: [EpisodeDTO]]?
        }

        struct SeasonDTO: Decodable {
            let season_number: Int?
            let name: String?
            let episode_count: Int?
            let air_date: String?
            let cover: String?
            let cover_big: String?
            let overview: String?
        }

        struct SeriesInfoDTO: Decodable {
            let cover: String?
            let backdrop_path: DynamicBackdrop?
            let plot: String?
            let cast: String?
            let director: String?
            let genre: String?
            let release_date: DynamicString?
            let releaseDate: DynamicString?
            let rating: DynamicRating?
            let youtube_trailer: String?
        }

        struct EpisodeDTO: Decodable {
            let id: DynamicID?
            let episode_num: DynamicID?
            let season: Int?
            let title: String?
            let container_extension: String?
            let info: EpisodeInfoDTO?
        }

        struct EpisodeInfoDTO: Decodable {
            let movie_image: String?
            let plot: String?
            let duration: DynamicString?
        }

        let resp: SeriesInfoResponse = (try? await fetch(url)) ?? SeriesInfoResponse(seasons: nil, info: nil, episodes: nil)

        var base = account.serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.lowercased().hasPrefix("http://") && !base.lowercased().hasPrefix("https://") {
            base = "http://" + base
        }
        if base.hasSuffix("/") { base.removeLast() }

        var result: [Episode] = []
        if let episodeDict = resp.episodes {
            for (seasonKey, eps) in episodeDict {
                let sNum = Int(seasonKey) ?? 1
                for ep in eps {
                    guard let epId = ep.id?.stringValue else { continue }
                    let ext = ep.container_extension ?? "mkv"
                    let streamUrl = "\(base)/series/\(account.username)/\(account.password)/\(epId).\(ext)"
                    let num = Int(ep.episode_num?.stringValue ?? "1") ?? 1
                    result.append(Episode(
                        id: epId,
                        episodeNum: num,
                        seasonNum: ep.season ?? sNum,
                        title: ep.title ?? "\(num). Bölüm",
                        streamUrl: streamUrl,
                        coverUrl: ep.info?.movie_image,
                        overview: ep.info?.plot,
                        duration: ep.info?.duration?.stringValue
                    ))
                }
            }
        }
        let sortedEpisodes = result.sorted { $0.seasonNum == $1.seasonNum ? $0.episodeNum < $1.episodeNum : $0.seasonNum < $1.seasonNum }

        let seasonInfos: [SeasonInfo] = (resp.seasons ?? []).compactMap { s in
            guard let num = s.season_number else { return nil }
            return SeasonInfo(
                seasonNumber: num,
                name: s.name,
                episodeCount: s.episode_count,
                airDate: s.air_date,
                cover: s.cover_big ?? s.cover,
                overview: s.overview
            )
        }

        return SeriesDetailResponse(
            cover: resp.info?.cover,
            backdropUrl: resp.info?.backdrop_path?.firstUrl,
            plot: resp.info?.plot,
            cast: resp.info?.cast,
            director: resp.info?.director,
            genre: resp.info?.genre,
            releaseDate: resp.info?.release_date?.stringValue ?? resp.info?.releaseDate?.stringValue,
            rating: resp.info?.rating?.stringValue,
            youtubeTrailer: resp.info?.youtube_trailer,
            episodes: sortedEpisodes,
            country: nil,
            age: nil,
            mpaaRating: nil,
            seasons: seasonInfos
        )
    }

    public func getSeriesInfo(account: Account, seriesId: String) async throws -> [Episode] {
        let details = try? await getSeriesDetails(account: account, seriesId: seriesId)
        return details?.episodes ?? []
    }
}

// MARK: - Lossy Decodable Array (Never fails if one element is malformed)

public struct LossyDecodableArray<Element: Decodable>: Decodable, Sendable {
    public let elements: [Element]

    public init(elements: [Element]) {
        self.elements = elements
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var list: [Element] = []
        if let count = container.count {
            list.reserveCapacity(count)
        }
        while !container.isAtEnd {
            do {
                let value = try container.decode(Element.self)
                list.append(value)
            } catch {
                _ = try? container.decode(DummyDecodable.self)
            }
        }
        self.elements = list
    }

    private struct DummyDecodable: Decodable {}
}

// MARK: - Dynamic Types for Xtream Inconsistent API Payloads

public enum DynamicString: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)

    public var stringValue: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s) }
        else if let i = try? container.decode(Int.self) { self = .int(i) }
        else if let d = try? container.decode(Double.self) { self = .double(d) }
        else { self = .string("") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

public enum DynamicBackdrop: Codable, Sendable {
    case array([String])
    case string(String)

    public var firstUrl: String? {
        switch self {
        case .array(let list): return list.first
        case .string(let s): return s.isEmpty ? nil : s
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let arr = try? container.decode([String].self) {
            self = .array(arr)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            self = .array([])
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .array(let arr): try container.encode(arr)
        case .string(let s): try container.encode(s)
        }
    }
}

public enum DynamicRating: Codable, Sendable {
    case string(String)
    case double(Double)
    case int(Int)

    public var stringValue: String {
        switch self {
        case .string(let s): return s
        case .double(let d): return String(format: "%.1f", d)
        case .int(let i): return "\(i)"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) { self = .double(d) }
        else if let i = try? container.decode(Int.self) { self = .int(i) }
        else if let s = try? container.decode(String.self) { self = .string(s) }
        else { self = .string("0") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

public enum DynamicID: Codable, Sendable {
    case string(String)
    case int(Int)

    public var stringValue: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int.self) { self = .int(i) }
        else if let s = try? container.decode(String.self) { self = .string(s) }
        else { self = .string("") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}
