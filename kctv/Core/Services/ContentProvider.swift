import Foundation

enum ContentError: LocalizedError, Sendable {
    case invalidCredentials
    case accountExpired
    case badResponse(status: Int)
    case emptyPlaylist
    case unsupported(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Kullanıcı adı veya şifre hatalı."
        case .accountExpired: "Hesabın süresi dolmuş."
        case let .badResponse(status): "Sunucu \(status) döndürdü."
        case .emptyPlaylist: "Listede oynatılabilir içerik bulunamadı."
        case let .unsupported(what): "Desteklenmeyen içerik: \(what)"
        case let .network(message): message
        }
    }
}

/// Xtream ve M3U kaynaklarını tek arayüzde toplar.
/// Arayüz katmanı hangi kaynağın bağlı olduğunu bilmez.
protocol ContentProvider: Sendable {
    /// `MediaID.source` alanına yazılır; favori/geçmiş kayıtları buna bağlanır.
    nonisolated var sourceID: String { get }

    func validate() async throws -> ProviderAccount
    func categories(for kind: MediaKind) async throws -> [MediaCategory]
    func items(kind: MediaKind, categoryID: String?) async throws -> [MediaItem]
    func detail(for item: MediaItem) async throws -> MediaDetail
    func shortEPG(for item: MediaItem) async throws -> [EPGEntry]

    /// Sunucunun izin verdiği kapsayıcı biçimi ancak `validate()` sonrası bilindiği
    /// için bu iki çağrı da async: sağlayıcı durumunu okumaları gerekiyor.
    func playbackURL(for item: MediaItem) async throws -> URL
    func playbackURL(for episode: Episode) async throws -> URL
}

extension ContentProvider {
    func shortEPG(for item: MediaItem) async throws -> [EPGEntry] { [] }
}
