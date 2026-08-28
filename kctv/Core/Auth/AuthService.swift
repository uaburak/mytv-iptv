import AuthenticationServices
import Foundation

struct AuthUser: Hashable, Codable, Sendable {
    var uid: String
    var displayName: String?
    var email: String?
    var photoURL: URL?
    var providerID: String?

    var initials: String {
        let source = displayName ?? email ?? "?"
        let letters = source.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

enum AuthError: LocalizedError, Sendable {
    case cancelled
    case notConfigured(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: nil
        case let .notConfigured(detail): detail
        case let .failed(message): message
        }
    }
}

/// Giriş sağlayıcılarını arayüzden ayırır.
/// Firebase yapılandırması eksikse `PreviewAuthService` ile aynı akış çalışır.
///
/// Giriş akışı doğrudan arayüzü sürdüğü (Apple sayfası, oturum durumu) için
/// tamamı MainActor'da yürüyor.
@MainActor
protocol AuthService: AnyObject, Sendable {
    var currentUser: AuthUser? { get }
    func restoreSession() async -> AuthUser?
    /// Apple butonu tamamlandıktan sonra çağrılır; nonce çağıran tarafta üretilir.
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthUser
    func signInWithGoogle() async throws -> AuthUser
    func signOut() throws
}

/// Firebase olmadan (önizleme, arayüz denemesi) akışı çalıştırmak için.
@MainActor
final class PreviewAuthService: AuthService, @unchecked Sendable {
    private(set) var currentUser: AuthUser?

    func restoreSession() async -> AuthUser? { currentUser }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthUser {
        let user = AuthUser(uid: "preview-apple", displayName: "Önizleme Kullanıcısı", email: nil, providerID: "apple.com")
        currentUser = user
        return user
    }

    func signInWithGoogle() async throws -> AuthUser {
        let user = AuthUser(uid: "preview-google", displayName: "Önizleme Kullanıcısı", email: nil, providerID: "google.com")
        currentUser = user
        return user
    }

    func signOut() throws { currentUser = nil }
}
