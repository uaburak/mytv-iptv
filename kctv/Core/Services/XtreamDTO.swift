import Foundation

// MARK: - player_api.php kök yanıtı

struct XtreamAuthResponse: Decodable, Sendable {
    var userInfo: UserInfo?
    var serverInfo: ServerInfo?

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
        case serverInfo = "server_info"
    }

    struct UserInfo: Decodable, Sendable {
        @LooseString var username: String?
        @LooseString var status: String?
        @LooseString var expDate: String?
        @LooseInt var isTrial: Int?
        @LooseInt var activeCons: Int?
        @LooseInt var maxConnections: Int?
        @LooseInt var auth: Int?
        @LooseStringList var allowedOutputFormats: [String]

        enum CodingKeys: String, CodingKey {
            case username, status, auth
            case expDate = "exp_date"
            case isTrial = "is_trial"
            case activeCons = "active_cons"
            case maxConnections = "max_connections"
            case allowedOutputFormats = "allowed_output_formats"
        }
    }

    struct ServerInfo: Decodable, Sendable {
        @LooseString var url: String?
        @LooseString var port: String?
        @LooseString var httpsPort: String?
        @LooseString var serverProtocol: String?

        enum CodingKeys: String, CodingKey {
            case url, port
            case httpsPort = "https_port"
            case serverProtocol = "server_protocol"
        }
    }
}

// MARK: - Kategoriler

struct XtreamCategoryDTO: Decodable, Sendable {
    @LooseString var categoryID: String?
    @LooseString var categoryName: String?

    enum CodingKeys: String, CodingKey {
        case categoryID = "category_id"
        case categoryName = "category_name"
    }
}

// MARK: - Listeler

/// get_live_streams / get_vod_streams / get_series tek DTO ile karşılanıyor;
/// üç uçtaki alan adları büyük ölçüde örtüşüyor, ayrışanlar opsiyonel.
struct XtreamStreamDTO: Decodable, Sendable {
    @LooseInt var num: Int?
    @LooseString var name: String?
    @LooseString var streamID: String?
    @LooseString var seriesID: String?
    @LooseString var streamIcon: String?
    @LooseString var cover: String?
    @LooseString var categoryID: String?
    @LooseString var containerExtension: String?
    @LooseDouble var rating: Double?
    @LooseString var added: String?
    @LooseString var lastModified: String?
    @LooseString var plot: String?
    @LooseString var genre: String?
    @LooseString var releaseDate: String?
    @LooseString var releasedate: String?
    @LooseString var releaseDateSnake: String?
    @LooseString var year: String?
    @LooseString var cast: String?
    @LooseString var director: String?
    @LooseString var youtubeTrailer: String?
    @LooseInt var episodeRunTime: Int?
    @LooseString var epgChannelID: String?
    @LooseString var directSource: String?
    @LooseInt var tvArchive: Int?
    @LooseStringList var backdropPath: [String]

    enum CodingKeys: String, CodingKey {
        case num, name, cover, rating, added, plot, genre, year
        case streamID = "stream_id"
        case seriesID = "series_id"
        case streamIcon = "stream_icon"
        case categoryID = "category_id"
        case containerExtension = "container_extension"
        case lastModified = "last_modified"
        case cast, director
        case releaseDate = "releaseDate"
        case releasedate = "releasedate"
        case releaseDateSnake = "release_date"
        case youtubeTrailer = "youtube_trailer"
        case episodeRunTime = "episode_run_time"
        case epgChannelID = "epg_channel_id"
        case directSource = "direct_source"
        case tvArchive = "tv_archive"
        case backdropPath = "backdrop_path"
    }

    var identifier: String? { streamID ?? seriesID }
    var artwork: String? { streamIcon ?? cover }
    var releaseText: String? { releaseDateSnake ?? releaseDate ?? releasedate ?? year }
}

// MARK: - Detaylar

struct XtreamVODInfoResponse: Decodable, Sendable {
    var info: Info?
    var movieData: MovieData?

    enum CodingKeys: String, CodingKey {
        case info
        case movieData = "movie_data"
    }

    struct Info: Decodable, Sendable {
        @LooseInt var tmdbID: Int?
        @LooseString var name: String?
        @LooseString var plot: String?
        @LooseString var description: String?
        @LooseString var cast: String?
        @LooseString var actors: String?
        @LooseString var director: String?
        @LooseString var genre: String?
        @LooseString var country: String?
        @LooseString var releasedate: String?
        @LooseString var releaseDate: String?
        @LooseString var movieImage: String?
        @LooseString var coverBig: String?
        @LooseString var youtubeTrailer: String?
        @LooseDouble var rating: Double?
        @LooseInt var durationSecs: Int?
        @LooseString var duration: String?
        @LooseStringList var backdropPath: [String]

        enum CodingKeys: String, CodingKey {
            case name, plot, description, cast, actors, director, genre, country, rating, duration
            case tmdbID = "tmdb_id"
            case releasedate
            case releaseDate = "release_date"
            case movieImage = "movie_image"
            case coverBig = "cover_big"
            case youtubeTrailer = "youtube_trailer"
            case durationSecs = "duration_secs"
            case backdropPath = "backdrop_path"
        }
    }

    struct MovieData: Decodable, Sendable {
        @LooseString var streamID: String?
        @LooseString var name: String?
        @LooseString var containerExtension: String?
        @LooseString var categoryID: String?

        enum CodingKeys: String, CodingKey {
            case name
            case streamID = "stream_id"
            case containerExtension = "container_extension"
            case categoryID = "category_id"
        }
    }
}

struct XtreamSeriesInfoResponse: Decodable, Sendable {
    var info: Info?
    var seasons: [SeasonDTO]
    /// Sunucular bunu sezon numarasıyla anahtarlanmış sözlük ya da düz dizi
    /// olarak döndürebiliyor; ikisi de aynı yapıya indirgeniyor.
    var episodes: [String: [EpisodeDTO]]

    enum CodingKeys: String, CodingKey {
        case info, seasons, episodes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        info = try? container.decodeIfPresent(Info.self, forKey: .info)
        seasons = ((try? container.decodeIfPresent([SeasonDTO].self, forKey: .seasons)) ?? nil) ?? []

        if let keyed = try? container.decodeIfPresent([String: [EpisodeDTO]].self, forKey: .episodes) {
            episodes = keyed
        } else if let flat = try? container.decodeIfPresent([[EpisodeDTO]].self, forKey: .episodes) {
            episodes = Dictionary(
                uniqueKeysWithValues: flat.enumerated().map { (String($0.offset + 1), $0.element) }
            )
        } else if let single = try? container.decodeIfPresent([EpisodeDTO].self, forKey: .episodes) {
            episodes = ["1": single]
        } else {
            episodes = [:]
        }
    }

    struct Info: Decodable, Sendable {
        @LooseString var name: String?
        @LooseString var plot: String?
        @LooseString var cast: String?
        @LooseString var director: String?
        @LooseString var genre: String?
        @LooseString var releaseDate: String?
        @LooseString var releasedate: String?
        @LooseString var cover: String?
        @LooseString var youtubeTrailer: String?
        @LooseDouble var rating: Double?
        @LooseInt var episodeRunTime: Int?
        @LooseStringList var backdropPath: [String]

        enum CodingKeys: String, CodingKey {
            case name, plot, cast, director, genre, cover, rating, releasedate
            case releaseDate = "releaseDate"
            case youtubeTrailer = "youtube_trailer"
            case episodeRunTime = "episode_run_time"
            case backdropPath = "backdrop_path"
        }
    }

    struct SeasonDTO: Decodable, Sendable {
        @LooseInt var seasonNumber: Int?
        @LooseString var name: String?
        @LooseString var cover: String?
        @LooseString var coverBig: String?
        @LooseString var overview: String?

        enum CodingKeys: String, CodingKey {
            case name, cover, overview
            case seasonNumber = "season_number"
            case coverBig = "cover_big"
        }
    }

    struct EpisodeDTO: Decodable, Sendable {
        @LooseString var id: String?
        @LooseInt var episodeNum: Int?
        @LooseString var title: String?
        @LooseString var containerExtension: String?
        @LooseInt var season: Int?
        @LooseString var added: String?
        var info: EpisodeInfo?

        enum CodingKeys: String, CodingKey {
            case id, title, season, added, info
            case episodeNum = "episode_num"
            case containerExtension = "container_extension"
        }
    }

    struct EpisodeInfo: Decodable, Sendable {
        @LooseInt var tmdbID: Int?
        @LooseString var plot: String?
        @LooseString var movieImage: String?
        @LooseString var coverBig: String?
        @LooseInt var durationSecs: Int?
        @LooseString var duration: String?
        @LooseString var releaseDate: String?
        @LooseDouble var rating: Double?

        enum CodingKeys: String, CodingKey {
            case plot, duration, rating
            case tmdbID = "tmdb_id"
            case movieImage = "movie_image"
            case coverBig = "cover_big"
            case durationSecs = "duration_secs"
            case releaseDate = "release_date"
        }
    }
}

// MARK: - EPG

struct XtreamEPGResponse: Decodable, Sendable {
    var listings: [Listing]

    enum CodingKeys: String, CodingKey {
        case listings = "epg_listings"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        listings = ((try? container.decodeIfPresent([Listing].self, forKey: .listings)) ?? nil) ?? []
    }

    struct Listing: Decodable, Sendable {
        @LooseString var id: String?
        /// Bu iki alan base64 kodlu gelir.
        @LooseString var title: String?
        @LooseString var description: String?
        @LooseString var start: String?
        @LooseString var end: String?
        @LooseString var startTimestamp: String?
        @LooseString var stopTimestamp: String?

        enum CodingKeys: String, CodingKey {
            case id, title, description, start, end
            case startTimestamp = "start_timestamp"
            case stopTimestamp = "stop_timestamp"
        }
    }
}
