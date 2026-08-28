import Foundation

/// Kullanıcının eklediği kaynak. Şifre burada tutulmaz; Keychain'e yazılır.
struct Playlist: Identifiable, Hashable, Codable, Sendable {
    enum Source: Hashable, Codable, Sendable {
        case xtream(host: String, username: String)
        case m3u(url: URL)

        var label: String {
            switch self {
            case .xtream: "Xtream Codes"
            case .m3u: "M3U / M3U8"
            }
        }
    }

    var id: String
    var name: String
    var source: Source
    var createdAt: Date
    var lastSyncedAt: Date?
    /// Hesabın bitiş tarihi (Xtream `user_info.exp_date`).
    var expiresAt: Date?
    var isActive: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        source: Source,
        createdAt: Date = .now,
        lastSyncedAt: Date? = nil,
        expiresAt: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.createdAt = createdAt
        self.lastSyncedAt = lastSyncedAt
        self.expiresAt = expiresAt
        self.isActive = isActive
    }

    var subtitle: String {
        switch source {
        case let .xtream(host, username):
            "\(username) · \(URL(string: host)?.host ?? host)"
        case let .m3u(url):
            url.host ?? url.lastPathComponent
        }
    }

    /// Keychain'de şifrenin saklandığı anahtar.
    var secretKey: String { "playlist.\(id).secret" }
}

/// Xtream `user_info` + `server_info` özeti; liste doğrulandığında gösterilir.
struct ProviderAccount: Hashable, Codable, Sendable {
    var username: String?
    var status: String?
    var expiresAt: Date?
    var maxConnections: Int?
    var activeConnections: Int?
    var isTrial: Bool = false
    var serverURL: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < .now
    }
}
