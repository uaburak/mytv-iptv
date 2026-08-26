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

        var urlString = "\(base)/player_api.php?username=\(username)&password=\(password)"
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

    public func getSeriesInfo(account: Account, seriesId: String) async throws -> [Episode] {
        guard let url = makeURL(serverUrl: account.serverUrl, username: account.username, password: account.password, action: "get_series_info", extraParams: "&series_id=\(seriesId)") else {
            return []
        }

        struct SeriesInfoResponse: Decodable {
            let episodes: [String: [EpisodeDTO]]?
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

        let resp: SeriesInfoResponse = (try? await fetch(url)) ?? SeriesInfoResponse(episodes: nil)
        guard let episodeDict = resp.episodes else { return [] }

        var base = account.serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.lowercased().hasPrefix("http://") && !base.lowercased().hasPrefix("https://") {
            base = "http://" + base
        }
        if base.hasSuffix("/") { base.removeLast() }

        var result: [Episode] = []
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
        return result.sorted { $0.seasonNum == $1.seasonNum ? $0.episodeNum < $1.episodeNum : $0.seasonNum < $1.seasonNum }
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
