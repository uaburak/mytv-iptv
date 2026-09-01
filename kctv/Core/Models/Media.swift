import Foundation

/// Uygulamadaki üç ana içerik türü. Xtream'de live/vod/series,
/// M3U'da ise grup adı ve URL kalıbından çıkarılır.
enum MediaKind: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case live
    case movie
    case series

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: L10n.liveTV
        case .movie: L10n.movies
        case .series: L10n.series
        }
    }

    var symbol: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .movie: "film.stack"
        case .series: "tv"
        }
    }

    /// Canlı kanal kartları yatay (16:9 logo), film/dizi kartları dikey poster.
    var posterAspect: Double {
        switch self {
        case .live: 16.0 / 9.0
        case .movie, .series: 2.0 / 3.0
        }
    }
}

/// Sağlayıcı + tür + ham kimliği birleştiren kararlı kimlik.
/// Navigation path ve favori kaydı bunun üzerinden gider, bu yüzden `Codable`.
struct MediaID: Hashable, Codable, Sendable, CustomStringConvertible {
    var source: String
    var kind: MediaKind
    var raw: String

    init(source: String, kind: MediaKind, raw: String) {
        self.source = source
        self.kind = kind
        self.raw = raw
    }

    var description: String { "\(source)|\(kind.rawValue)|\(raw)" }
}

struct MediaItem: Identifiable, Hashable, Codable, Sendable {
    var id: MediaID
    var title: String
    var posterURL: URL?
    var backdropURL: URL?
    var categoryID: String?
    var categoryName: String?
    var year: Int?
    /// 0...10 aralığında. Arayüzde yüzdeye çevriliyor.
    var rating: Double?
    var genres: [String] = []
    var plot: String?
    var durationSeconds: Int?
    var addedAt: Date?
    var isAdult: Bool = false
    /// Xtream stream/series id'si veya M3U'daki doğrudan URL.
    var streamReference: String
    var containerExtension: String?
    /// Canlı kanallarda kanal numarası (EPG sıralaması için).
    var channelNumber: Int?
    /// Xtream liste uçları künyeyi de taşıyor. Bunları burada tutmak detay
    /// ekranının ağ yanıtını beklemeden dolmasını sağlıyor.
    var cast: [String] = []
    var director: String?
    var trailerURL: URL?
    /// Sağlayıcı filmlerde TMDB kimliğini doğrudan veriyor. Varsa isim
    /// eşleştirmesine hiç gerek kalmıyor — yanlış eşleşme riski sıfır.
    var tmdbID: Int?

    var kind: MediaKind { id.kind }

    var yearText: String? { year.map(String.init) }

    var durationText: String? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        return L10n.duration(
            hours: durationSeconds / 3600,
            minutes: (durationSeconds % 3600) / 60
        )
    }

    /// VoiceOver'ın kart yerine okuyacağı metin.
    ///
    /// Afiş kartlarında görünür bir etiket yok — başlık yalnızca ilerleme
    /// varken ya da tvOS'ta odakta beliren şeritte duruyor. Bu olmadan
    /// VoiceOver kartı yalnızca "düğme" diye okuyordu.
    var accessibilityDescription: String {
        [title, kind.title, yearText]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    var ratingPercent: Int? {
        guard let rating, rating > 0 else { return nil }
        return Int((rating * 10).rounded())
    }

    var ratingFormatted: String? {
        guard let rating, rating > 0 else { return nil }
        return String(format: "%.1f", rating)
    }
}

extension String {
    /// Sağlayıcıdan gelen kategori adının ekranda görünecek hâli.
    ///
    /// IPTV listelerinde kategori adının sonuna liste etiketi ekleniyor
    /// ("4K Film|VOD", "Aksiyon|AY VOD", "Yerli|Dizi"), başına da dikkat çeksin
    /// diye emoji konuyor ("⏸️ Yeni Eklenenler"). İkisi de sağlayıcının kendi
    /// defterinden kalma; ekranda kategorinin adı yeter.
    ///
    /// Kategori **kimliği** ham addan üretiliyor ve bu temizlik ona hiç
    /// dokunmuyor: gruplama, önbellek ve favoriler eskisi gibi çalışıyor.
    var cleanedCategoryName: String {
        // Boru işaretinden sonrası etiket.
        let head = prefix { $0 != "|" }
        let withoutDecoration = String(
            String.UnicodeScalarView(head.unicodeScalars.filter { !$0.isDecorative })
        )
        // Etiket ve emoji düşünce başta/sonda kalan ayraçlar ve çift boşluklar.
        let cleaned = withoutDecoration
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-–—•·:,;/\\"))
            .trimmingCharacters(in: .whitespaces)
        // Adın tamamı süsten ibaretse elimizde kalanı gösteriyoruz.
        return cleaned.isEmpty ? trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
    }
}

private extension Unicode.Scalar {
    /// Emoji, dingbat, ok ve benzeri süsler. ASCII ve harfler dokunulmadan
    /// geçiyor — Türkçe karakterler de dahil.
    var isDecorative: Bool {
        if value < 0x80 { return false }
        // Varyasyon seçicileri, sıfır genişlikli birleştirici, tuş kapağı.
        if (0xFE00...0xFE0F).contains(value) || value == 0x200D || value == 0x20E3 { return true }
        if properties.isEmoji || properties.isEmojiModifier { return true }
        switch value {
        case 0x2190...0x21FF,    // oklar
             0x2300...0x23FF,    // teknik simgeler (⏸ burada)
             0x25A0...0x27BF,    // geometrik şekiller, dingbatlar
             0x2B00...0x2BFF,    // ek oklar ve yıldızlar
             0x1F000...0x1FAFF:  // emoji blokları
            return true
        default:
            return false
        }
    }
}

struct MediaCategory: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var kind: MediaKind
    /// Sağlayıcı bildiriyorsa içerik sayısı; ray başlıklarında kullanılır.
    var itemCount: Int?
}

struct Episode: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var seriesID: MediaID
    var seasonNumber: Int
    var episodeNumber: Int
    var title: String
    var plot: String?
    var stillURL: URL?
    var durationSeconds: Int?
    var airDate: Date?
    var streamReference: String
    var containerExtension: String?

    var numberText: String { L10n.episodeBadge(season: seasonNumber, episode: episodeNumber) }

    var durationText: String? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        let minutes = max(1, durationSeconds / 60)
        return L10n.duration(hours: minutes / 60, minutes: minutes % 60)
    }
}

struct Season: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var number: Int
    var name: String
    var posterURL: URL?
    var episodes: [Episode]
}

/// Detay ekranını dolduran zenginleştirilmiş içerik.
/// Liste görünümündeki `MediaItem` alanları burada güncellenmiş olabilir.
struct MediaDetail: Hashable, Codable, Sendable {
    var item: MediaItem
    var cast: [String] = []
    var director: String?
    var country: String?
    var releaseDate: Date?
    var trailerURL: URL?
    var seasons: [Season] = []
    var extraBackdrops: [URL] = []

    var hasEpisodes: Bool { seasons.contains { !$0.episodes.isEmpty } }
}

/// Canlı kanallar için kısa EPG kaydı.
struct EPGEntry: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var title: String
    var description: String?
    var start: Date
    var end: Date

    var isLive: Bool {
        let now = Date()
        return start <= now && now < end
    }

    var progress: Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, Date().timeIntervalSince(start) / total))
    }
}

/// Bir seriye (franchise/collection) ait film kaydı.
/// Kullanıcının katalogunda var olabilir (`localItem != nil`) veya yalnızca TMDB'de kayıtlı olup
/// kullanıcının listesinde henüz bulunmayabilir (`localItem == nil`).
struct FranchiseEntry: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var title: String
    var originalTitle: String?
    var year: Int?
    var releaseDate: String?
    var posterURL: URL?
    var backdropURL: URL?
    var overview: String?
    var tmdbID: Int?
    var localItem: MediaItem?

    var isAvailableInCatalog: Bool { localItem != nil }

    var effectiveItem: MediaItem {
        if let localItem { return localItem }
        return MediaItem(
            id: MediaID(source: "tmdb", kind: .movie, raw: "\(tmdbID ?? 0)"),
            title: title,
            posterURL: posterURL,
            backdropURL: backdropURL,
            year: year,
            plot: overview,
            streamReference: ""
        )
    }
}
