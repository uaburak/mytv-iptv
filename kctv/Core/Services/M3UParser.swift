import Foundation

/// Tek bir `#EXTINF` kaydı.
struct M3UEntry: Sendable {
    var name: String
    var url: URL
    var logo: URL?
    var group: String?
    var tvgID: String?
    var tvgName: String?
    var duration: Int?
    /// "Dizi Adı S02E05" kalıbı yakalandıysa dolu gelir.
    var seriesTitle: String?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var kind: MediaKind
}

/// M3U / M3U8 playlist çözümleyicisi.
///
/// Sağlayıcılar arasında öznitelik yazımı çok değiştiği için öznitelikler
/// büyük/küçük harf duyarsız okunuyor ve tırnaksız değerler de kabul ediliyor.
enum M3UParser {
    static func parse(_ text: String) -> [M3UEntry] {
        var entries: [M3UEntry] = []
        var pending: (attributes: [String: String], title: String, duration: Int?)?

        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            if trimmed.hasPrefix("#EXTINF") {
                pending = parseExtInf(trimmed)
                return
            }

            // #EXTGRP kayıtları group-title yerine geçebiliyor.
            if trimmed.uppercased().hasPrefix("#EXTGRP:") {
                let group = String(trimmed.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces)
                if var current = pending {
                    current.attributes["group-title"] = current.attributes["group-title"] ?? group
                    pending = current
                }
                return
            }

            // Diğer yönerge satırlarını atla.
            if trimmed.hasPrefix("#") { return }

            guard let current = pending, let url = URL(string: trimmed) else {
                pending = nil
                return
            }
            pending = nil
            entries.append(makeEntry(attributes: current.attributes, title: current.title, duration: current.duration, url: url))
        }

        return entries
    }

    // MARK: - Satır çözümleme

    private static func parseExtInf(_ line: String) -> (attributes: [String: String], title: String, duration: Int?) {
        // Biçim: #EXTINF:<süre> <öznitelikler>,<görünen ad>
        let body = String(line.dropFirst("#EXTINF:".count))
        // Görünen ad son virgülden sonrası; öznitelik değerlerinde de virgül olabildiği
        // için baştan değil sondan bölüyoruz.
        let title: String
        let head: String
        if let commaIndex = body.lastIndex(of: ",") {
            title = String(body[body.index(after: commaIndex)...]).trimmingCharacters(in: .whitespaces)
            head = String(body[..<commaIndex])
        } else {
            title = body.trimmingCharacters(in: .whitespaces)
            head = body
        }

        let duration = Int(head.prefix(while: { $0.isNumber || $0 == "-" })).flatMap { $0 > 0 ? $0 : nil }
        return (attributes: parseAttributes(head), title: title, duration: duration)
    }

    private static func parseAttributes(_ text: String) -> [String: String] {
        var attributes: [String: String] = [:]
        // key="value" ve key=value biçimlerini birlikte yakalar.
        let pattern = #"([a-zA-Z0-9_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s,]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return attributes }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
            let key = String(text[keyRange]).lowercased()
            for group in 2...4 {
                if let valueRange = Range(match.range(at: group), in: text) {
                    attributes[key] = String(text[valueRange])
                    break
                }
            }
        }
        return attributes
    }

    private static func makeEntry(attributes: [String: String], title: String, duration: Int?, url: URL) -> M3UEntry {
        let group = attributes["group-title"]
        let displayName = title.isEmpty ? (attributes["tvg-name"] ?? url.lastPathComponent) : title
        let kind = classify(name: displayName, group: group, url: url, duration: duration)
        let parsed = kind == .series ? parseEpisodeTitle(displayName) : nil

        return M3UEntry(
            name: displayName,
            url: url,
            logo: LooseParse.url(attributes["tvg-logo"] ?? attributes["logo"]),
            group: group,
            tvgID: attributes["tvg-id"],
            tvgName: attributes["tvg-name"],
            duration: duration,
            seriesTitle: parsed?.title,
            seasonNumber: parsed?.season,
            episodeNumber: parsed?.episode,
            kind: kind
        )
    }

    // MARK: - Sınıflandırma

    /// Kaynak türünü URL kalıbı, grup adı ve süreden çıkarır.
    /// Xtream tabanlı M3U'larda yol `/live/`, `/movie/`, `/series/` olur — en güvenilir ipucu bu.
    static func classify(name: String, group: String?, url: URL, duration: Int?) -> MediaKind {
        let path = url.path.lowercased()
        if path.contains("/series/") { return .series }
        if path.contains("/movie/") || path.contains("/vod/") { return .movie }
        if path.contains("/live/") { return .live }

        let haystack = (group ?? "").lowercased()
        if ["series", "serie", "dizi", "diziler", "tv show", "shows"].contains(where: { haystack.contains($0) }) {
            return .series
        }
        if ["movie", "film", "vod", "sinema", "cinema"].contains(where: { haystack.contains($0) }) {
            return .movie
        }

        // Adında SxxEyy geçen her kayıt bölümdür.
        if parseEpisodeTitle(name) != nil { return .series }

        // Canlı yayınlar süresiz (-1) gelir; sonlu süre VOD işaretidir.
        if let duration, duration > 0 { return .movie }
        return .live
    }

    /// "Dizi Adı S02 E05", "Dizi Adı - 2x05", "Dizi Adı 1. Sezon 5. Bölüm" gibi kalıpları ayrıştırır.
    static func parseEpisodeTitle(_ title: String) -> (title: String, season: Int, episode: Int)? {
        let patterns = [
            #"^(.*?)[\s\-\._]*[Ss](\d{1,2})[\s\-\._]*[Ee](\d{1,3})"#,
            #"^(.*?)[\s\-\._]+(\d{1,2})[xX](\d{1,3})"#,
            #"^(.*?)[\s\-\._]*(\d{1,2})\.?\s*[Ss]ezon[\s\-\._]*(\d{1,3})\.?\s*[Bb]ölüm"#,
            #"^(.*?)[\s\-\._]*[Ss]ezon\s*(\d{1,2})[\s\-\._]*[Bb]ölüm\s*(\d{1,3})"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  let nameRange = Range(match.range(at: 1), in: title),
                  let seasonRange = Range(match.range(at: 2), in: title),
                  let episodeRange = Range(match.range(at: 3), in: title),
                  let season = Int(title[seasonRange]),
                  let episode = Int(title[episodeRange])
            else { continue }

            let name = title[nameRange]
                .trimmingCharacters(in: CharacterSet(charactersIn: " -._:"))
            return (name.isEmpty ? title : name, season, episode)
        }

        // Tek başına bölüm ("Dizi Adı 5. Bölüm" veya "Dizi Adı Bölüm 5") -> Sezon 1 varsayılır
        let singleEpisodePatterns = [
            #"^(.*?)[\s\-\._]*(\d{1,3})\.?\s*[Bb]ölüm"#,
            #"^(.*?)[\s\-\._]*[Bb]ölüm\s*(\d{1,3})"#,
        ]
        for pattern in singleEpisodePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  let nameRange = Range(match.range(at: 1), in: title),
                  let episodeRange = Range(match.range(at: 2), in: title),
                  let episode = Int(title[episodeRange])
            else { continue }

            let name = title[nameRange]
                .trimmingCharacters(in: CharacterSet(charactersIn: " -._:"))
            return (name.isEmpty ? title : name, 1, episode)
        }

        return nil
    }
}
