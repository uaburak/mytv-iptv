import Foundation

public enum ContentType: String, Codable, CaseIterable, Identifiable {
    case live = "Canlı TV"
    case movie = "Film"
    case series = "Dizi"

    public var id: String { rawValue }
}

public struct MediaCategory: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let type: ContentType

    public init(id: String, name: String, type: ContentType) {
        self.id = id
        self.name = name
        self.type = type
    }
}

public struct Channel: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let streamIcon: String?
    public let streamUrl: String
    public let categoryId: String
    public let epgChannelId: String?
    public let num: Int?

    public init(
        id: String,
        name: String,
        streamIcon: String? = nil,
        streamUrl: String,
        categoryId: String,
        epgChannelId: String? = nil,
        num: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.streamIcon = streamIcon
        self.streamUrl = streamUrl
        self.categoryId = categoryId
        self.epgChannelId = epgChannelId
        self.num = num
    }
}

public struct VODItem: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let streamIcon: String?
    public let backdropUrl: String?
    public let rating: String?
    public let releaseDate: String?
    public let duration: String?
    public let overview: String?
    public let streamUrl: String
    public let categoryId: String
    public let type: ContentType
    public let containerExtension: String?
    public let genre: String?
    public let cast: String?
    public let director: String?
    public let youtubeTrailer: String?

    public init(
        id: String,
        name: String,
        streamIcon: String? = nil,
        backdropUrl: String? = nil,
        rating: String? = nil,
        releaseDate: String? = nil,
        duration: String? = nil,
        overview: String? = nil,
        streamUrl: String,
        categoryId: String,
        type: ContentType,
        containerExtension: String? = nil,
        genre: String? = nil,
        cast: String? = nil,
        director: String? = nil,
        youtubeTrailer: String? = nil
    ) {
        self.id = id
        self.name = name
        self.streamIcon = streamIcon
        self.backdropUrl = backdropUrl
        self.rating = rating
        self.releaseDate = releaseDate
        self.duration = duration
        self.overview = overview
        self.streamUrl = streamUrl
        self.categoryId = categoryId
        self.type = type
        self.containerExtension = containerExtension
        self.genre = genre
        self.cast = cast
        self.director = director
        self.youtubeTrailer = youtubeTrailer
    }
}

public struct Episode: Identifiable, Codable, Hashable {
    public let id: String
    public let episodeNum: Int
    public let seasonNum: Int
    public let title: String
    public let streamUrl: String
    public let coverUrl: String?
    public let overview: String?
    public let duration: String?

    public init(
        id: String,
        episodeNum: Int,
        seasonNum: Int,
        title: String,
        streamUrl: String,
        coverUrl: String? = nil,
        overview: String? = nil,
        duration: String? = nil
    ) {
        self.id = id
        self.episodeNum = episodeNum
        self.seasonNum = seasonNum
        self.title = title
        self.streamUrl = streamUrl
        self.coverUrl = coverUrl
        self.overview = overview
        self.duration = duration
    }
}
