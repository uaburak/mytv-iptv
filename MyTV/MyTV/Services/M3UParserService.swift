import Foundation

public final class M3UParserService: Sendable {
    public static let shared = M3UParserService()

    private init() {}

    public struct M3UResult: Sendable {
        public let categories: [MediaCategory]
        public let channels: [Channel]
        public let movies: [VODItem]
        public let series: [VODItem]
    }

    public func extractXtreamCredentials(from urlString: String) -> (serverUrl: String, username: String, password: String)? {
        guard let components = URLComponents(string: urlString),
              let queryItems = components.queryItems else { return nil }

        guard let user = queryItems.first(where: { $0.name.lowercased() == "username" })?.value,
              let pass = queryItems.first(where: { $0.name.lowercased() == "password" })?.value else {
            return nil
        }

        let scheme = components.scheme ?? "http"
        guard let host = components.host else { return nil }
        var portStr = ""
        if let port = components.port {
            portStr = ":\(port)"
        }

        let serverUrl = "\(scheme)://\(host)\(portStr)"
        return (serverUrl, user, pass)
    }

    public func parse(url: URL) async throws -> M3UResult {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (AppleTV; tvOS 17.0) IPTVSmarters/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 45

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: "M3UParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "M3U içeriği okunamadı."])
        }

        return parseContent(content)
    }

    public func parseContent(_ content: String) -> M3UResult {
        var categoriesDict: [String: MediaCategory] = [:]
        var channels: [Channel] = []
        var movies: [VODItem] = []
        var series: [VODItem] = []

        let lines = content.components(separatedBy: .newlines)
        var currentExtInf: String? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("#EXTINF:") {
                currentExtInf = trimmed
            } else if !trimmed.hasPrefix("#") {
                if let extInf = currentExtInf {
                    let (name, group, logo, _) = parseExtInf(extInf)
                    let categoryId = group.lowercased().replacingOccurrences(of: " ", with: "_")
                    let category = MediaCategory(id: categoryId, name: group, type: .live)
                    categoriesDict[categoryId] = category

                    let itemUrl = trimmed
                    if itemUrl.contains("/movie/") || itemUrl.hasSuffix(".mp4") || itemUrl.hasSuffix(".mkv") {
                        movies.append(VODItem(
                            id: UUID().uuidString,
                            name: name,
                            streamIcon: logo,
                            backdropUrl: logo,
                            rating: nil,
                            releaseDate: nil,
                            duration: nil,
                            overview: nil,
                            streamUrl: itemUrl,
                            categoryId: categoryId,
                            type: .movie,
                            containerExtension: (itemUrl as NSString).pathExtension,
                            genre: group
                        ))
                    } else if itemUrl.contains("/series/") {
                        series.append(VODItem(
                            id: UUID().uuidString,
                            name: name,
                            streamIcon: logo,
                            backdropUrl: logo,
                            rating: nil,
                            releaseDate: nil,
                            duration: nil,
                            overview: nil,
                            streamUrl: itemUrl,
                            categoryId: categoryId,
                            type: .series,
                            containerExtension: nil,
                            genre: group
                        ))
                    } else {
                        channels.append(Channel(
                            id: UUID().uuidString,
                            name: name,
                            streamIcon: logo,
                            streamUrl: itemUrl,
                            categoryId: categoryId,
                            epgChannelId: nil,
                            num: channels.count + 1
                        ))
                    }
                    currentExtInf = nil
                }
            }
        }

        return M3UResult(
            categories: Array(categoriesDict.values),
            channels: channels,
            movies: movies,
            series: series
        )
    }

    private func parseExtInf(_ line: String) -> (name: String, group: String, logo: String?, epgId: String?) {
        var group = "Genel"
        var logo: String? = nil
        var epgId: String? = nil
        var name = "Kanal"

        if let groupMatch = line.range(of: "group-title=\"([^\"]+)\"", options: .regularExpression) {
            let sub = String(line[groupMatch])
            group = sub.replacingOccurrences(of: "group-title=\"", with: "").replacingOccurrences(of: "\"", with: "")
        }

        if let logoMatch = line.range(of: "tvg-logo=\"([^\"]+)\"", options: .regularExpression) {
            let sub = String(line[logoMatch])
            logo = sub.replacingOccurrences(of: "tvg-logo=\"", with: "").replacingOccurrences(of: "\"", with: "")
        }

        if let idMatch = line.range(of: "tvg-id=\"([^\"]+)\"", options: .regularExpression) {
            let sub = String(line[idMatch])
            epgId = sub.replacingOccurrences(of: "tvg-id=\"", with: "").replacingOccurrences(of: "\"", with: "")
        }

        if let lastComma = line.lastIndex(of: ",") {
            name = String(line[line.index(after: lastComma)...]).trimmingCharacters(in: .whitespaces)
        }

        return (name, group, logo, epgId)
    }
}
