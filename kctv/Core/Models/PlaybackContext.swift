import Foundation

/// Player'a gönderilen tek parça. Detay ekranı ve canlı liste aynı tipi üretir,
/// böylece player'ın içerik türünden haberi olmasına gerek kalmaz.
struct PlaybackContext: Identifiable, Hashable, Sendable {
    var id: String
    var url: URL
    var title: String
    var subtitle: String?
    var artworkURL: URL?
    var kind: MediaKind
    /// Canlı yayında seek/scrub kapalı olacak.
    var isLive: Bool
    /// Kaldığı yerden devam için başlangıç saniyesi.
    var startAt: Double?
    var headers: [String: String] = [:]

    init(
        id: String,
        url: URL,
        title: String,
        subtitle: String? = nil,
        artworkURL: URL? = nil,
        kind: MediaKind,
        startAt: Double? = nil,
        headers: [String: String] = [:]
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.kind = kind
        self.isLive = kind == .live
        self.startAt = startAt
        self.headers = headers
    }
}

/// İzlemeyi sürdür kaydı.
struct PlaybackProgress: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var mediaID: MediaID
    var episodeID: String?
    /// Bölümün okunur adı: "S3:B4 · Bölüm adı".
    ///
    /// Oynatma sırasında yazılıyor. "İzlemeye devam et" rayında dizinin
    /// kendisi değil kalınan bölüm görünüyor ve bunun için dizinin detayını
    /// yeniden indirmek gerekmiyor. Eski kayıtlarda boş.
    var episodeLabel: String?
    var positionSeconds: Double
    var durationSeconds: Double
    var updatedAt: Date

    var fraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1, max(0, positionSeconds / durationSeconds))
    }

    /// %95'i geçen kayıtlar "izlemeyi sürdür" rayından düşer.
    var isFinished: Bool { fraction >= 0.95 }

    var remainingText: String {
        let remaining = Int(max(0, durationSeconds - positionSeconds))
        return L10n.duration(hours: remaining / 3600, minutes: (remaining % 3600) / 60)
    }
}
