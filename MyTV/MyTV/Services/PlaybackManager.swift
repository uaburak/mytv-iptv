import Foundation
import Combine
import AVFoundation
#if canImport(AVFAudio)
import AVFAudio
#endif
import KSPlayer

public struct PlayableMedia: Identifiable, Sendable, Equatable {
    public var id: String { mediaId }
    public let mediaId: String
    public let title: String
    public let subtitle: String?
    public let posterUrl: String?
    public let streamUrl: String
    public let contentType: ContentType
    public let alternativeUrls: [String]
    public let rating: String?
    public let releaseDate: String?
    public let duration: String?
    public let overview: String?
    public let genre: String?
    public let director: String?
    public let seriesId: String?
    public let episodeNum: Int?
    public let seasonNum: Int?

    public init(
        mediaId: String,
        title: String,
        subtitle: String? = nil,
        posterUrl: String? = nil,
        streamUrl: String,
        contentType: ContentType,
        alternativeUrls: [String] = [],
        rating: String? = nil,
        releaseDate: String? = nil,
        duration: String? = nil,
        overview: String? = nil,
        genre: String? = nil,
        director: String? = nil,
        seriesId: String? = nil,
        episodeNum: Int? = nil,
        seasonNum: Int? = nil
    ) {
        self.mediaId = mediaId
        self.title = title
        self.subtitle = subtitle
        self.posterUrl = posterUrl
        self.streamUrl = streamUrl
        self.contentType = contentType
        self.alternativeUrls = alternativeUrls
        self.rating = rating
        self.releaseDate = releaseDate
        self.duration = duration
        self.overview = overview
        self.genre = genre
        self.director = director
        self.seriesId = seriesId
        self.episodeNum = episodeNum
        self.seasonNum = seasonNum
    }
}

@MainActor
public final class PlaybackManager: ObservableObject {
    public static let shared = PlaybackManager()

    public static let defaultUserAgent = "Mozilla/5.0 (AppleTV; tvOS 17.0) IPTVSmarters/1.0"

    // MARK: - Published State
    @Published public private(set) var currentMedia: PlayableMedia?
    @Published public private(set) var activePlayableURL: URL?
    @Published public var isPresented: Bool = false
    @Published public var errorMessage: String? = nil

    private init() {}

    public func makeOptions() -> KSOptions {
        let options = KSOptions()
        options.userAgent = Self.defaultUserAgent
        options.hardwareDecode = true
        options.isAccurateSeek = true
        return options
    }

    // MARK: - Public API

    public func play(media: PlayableMedia) {
        let trimmed = media.streamUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            errorMessage = "Geçersiz yayın bağlantısı."
            isPresented = true
            return
        }

        #if canImport(AVFAudio) && (os(iOS) || os(tvOS) || os(visionOS))
        Task.detached(priority: .userInitiated) {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback, options: [])
                try session.setActive(true)
            } catch {}
        }
        #endif

        stop()

        currentMedia = media
        activePlayableURL = url
        errorMessage = nil
        isPresented = true
    }

    public func stop() {
        currentMedia = nil
        activePlayableURL = nil
        isPresented = false
        errorMessage = nil
    }

    public func retry() {
        guard let media = currentMedia else { return }
        play(media: media)
    }
}
