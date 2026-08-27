import Foundation

public struct TMDBMetadata: Sendable, Codable {
    public let logoUrl: String?
    public let backdropUrl: String?
    public let posterUrl: String?
    public let overview: String?
    public let rating: Double?
    public let voteCount: Int?

    public init(
        logoUrl: String? = nil,
        backdropUrl: String? = nil,
        posterUrl: String? = nil,
        overview: String? = nil,
        rating: Double? = nil,
        voteCount: Int? = nil
    ) {
        self.logoUrl = logoUrl
        self.backdropUrl = backdropUrl
        self.posterUrl = posterUrl
        self.overview = overview
        self.rating = rating
        self.voteCount = voteCount
    }
}

public actor TMDBService {
    public static let shared = TMDBService()

    private let apiKey = "15d2ea6d0dc1d476efbca3eba2b9bbfb"
    private var cache: [String: TMDBMetadata] = [:]
    private let urlSession: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.urlSession = URLSession(configuration: config)
    }

    /// Fetches the highest quality clear logo and cinematic backdrop for a movie or TV show.
    public func getMetadata(title: String, isSeries: Bool) async -> TMDBMetadata? {
        let cacheKey = "\(isSeries ? "tv" : "movie")_\(title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
        if let cached = cache[cacheKey] {
            return cached
        }

        let (cleanTitle, year) = cleanTitleAndYear(from: title)
        guard !cleanTitle.isEmpty else { return nil }

        let mediaType = isSeries ? "tv" : "movie"
        guard let encodedTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }

        var searchUrlStr = "https://api.themoviedb.org/3/search/\(mediaType)?api_key=\(apiKey)&query=\(encodedTitle)&language=tr-TR"
        if let year {
            let yearParam = isSeries ? "&first_air_date_year=\(year)" : "&primary_release_year=\(year)"
            searchUrlStr += yearParam
        }

        guard let searchUrl = URL(string: searchUrlStr) else { return nil }

        struct SearchResult: Decodable {
            struct Item: Decodable {
                let id: Int
                let overview: String?
                let vote_average: Double?
                let vote_count: Int?
            }
            let results: [Item]?
        }

        var results: [SearchResult.Item] = []

        if let (data, resp) = try? await urlSession.data(from: searchUrl),
           let httpResp = resp as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
           let decoded = try? JSONDecoder().decode(SearchResult.self, from: data),
           let items = decoded.results, !items.isEmpty {
            results = items
        } else if year != nil {
            // Retry without strict year filter
            let retryUrlStr = "https://api.themoviedb.org/3/search/\(mediaType)?api_key=\(apiKey)&query=\(encodedTitle)&language=tr-TR"
            if let retryUrl = URL(string: retryUrlStr),
               let (data, resp) = try? await urlSession.data(from: retryUrl),
               let httpResp = resp as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
               let decoded = try? JSONDecoder().decode(SearchResult.self, from: data),
               let items = decoded.results, !items.isEmpty {
                results = items
            }
        }

        guard let firstItem = results.first else {
            return nil
        }

        let itemId = firstItem.id

        // Fetch all images (logos, backdrops, posters)
        let imagesUrlStr = "https://api.themoviedb.org/3/\(mediaType)/\(itemId)/images?api_key=\(apiKey)&include_image_language=tr,en,null"
        guard let imagesUrl = URL(string: imagesUrlStr) else { return nil }

        struct ImagesResponse: Decodable {
            struct ImageItem: Decodable {
                let file_path: String
                let iso_639_1: String?
                let vote_average: Double?
            }
            let backdrops: [ImageItem]?
            let logos: [ImageItem]?
            let posters: [ImageItem]?
        }

        var bestLogoUrl: String?
        var bestBackdropUrl: String?
        var bestPosterUrl: String?

        if let (data, resp) = try? await urlSession.data(from: imagesUrl),
           let httpResp = resp as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
           let decoded = try? JSONDecoder().decode(ImagesResponse.self, from: data) {

            // 1. Şeffaf Logo (ClearLogo - PNG)
            if let logos = decoded.logos, !logos.isEmpty {
                // Prefer Turkish or English or first logo
                let sortedLogos = logos.sorted {
                    let l0Lang = $0.iso_639_1 ?? ""
                    let l1Lang = $1.iso_639_1 ?? ""
                    if l0Lang == "tr" && l1Lang != "tr" { return true }
                    if l0Lang != "tr" && l1Lang == "tr" { return false }
                    if l0Lang == "en" && l1Lang != "en" && l1Lang != "tr" { return true }
                    return ($0.vote_average ?? 0) > ($1.vote_average ?? 0)
                }
                if let best = sortedLogos.first {
                    bestLogoUrl = "https://image.tmdb.org/t/p/original\(best.file_path)"
                }
            }

            // 2. Ana Sinematik Yatay Kapak (Backdrop - 1280px)
            if let backdrops = decoded.backdrops, !backdrops.isEmpty {
                if let best = backdrops.first {
                    bestBackdropUrl = "https://image.tmdb.org/t/p/w1280\(best.file_path)"
                }
            }

            // 3. Afiş (Poster)
            if let posters = decoded.posters, !posters.isEmpty {
                if let best = posters.first {
                    bestPosterUrl = "https://image.tmdb.org/t/p/w600_and_h900_bestv2\(best.file_path)"
                }
            }
        }

        let meta = TMDBMetadata(
            logoUrl: bestLogoUrl,
            backdropUrl: bestBackdropUrl,
            posterUrl: bestPosterUrl,
            overview: firstItem.overview,
            rating: firstItem.vote_average,
            voteCount: firstItem.vote_count
        )

        cache[cacheKey] = meta
        return meta
    }

    private func cleanTitleAndYear(from raw: String) -> (title: String, year: String?) {
        var year: String?
        if let regex = try? NSRegularExpression(pattern: #"\((\d{4})\)"#) {
            let ns = raw as NSString
            if let match = regex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) {
                year = ns.substring(with: match.range(at: 1))
            }
        }

        var clean = raw
        let patterns = [
            #"\[.*?\]"#,
            #"\(.*?\)"#,
            #"(?i)\b(4k|fhd|hd|uhd|dual|dublaj|altyazılı|altyazi|tr|eng|netflix|bluray|web-dl)\b"#
        ]
        for p in patterns {
            clean = clean.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean, year)
    }
}
