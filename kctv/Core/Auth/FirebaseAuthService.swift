import AuthenticationServices
import Foundation
import FirebaseAuth

/// Firebase Authentication üzerinden Apple ve Google girişi.
///
/// Google tarafı iki ayrı yol kullanır:
/// - iOS/macOS: GoogleSignIn SDK (paket eklendiğinde devreye girer)
/// - tvOS: SDK tvOS'u desteklemediği için OAuth "device flow"
///   (TV'de kod göster, kullanıcı telefondan onaylasın)
@MainActor
final class FirebaseAuthService: AuthService, @unchecked Sendable {
    private(set) var currentUser: AuthUser?

    init() {
        currentUser = Auth.auth().currentUser.map(Self.map)
    }

    func restoreSession() async -> AuthUser? {
        guard let user = Auth.auth().currentUser else { return nil }
        // Token süresi dolduysa sessizce yenile; başarısızsa oturumu düşür.
        do {
            _ = try await user.getIDTokenResult(forcingRefresh: false)
        } catch {
            try? Auth.auth().signOut()
            currentUser = nil
            return nil
        }
        let mapped = Self.map(user)
        currentUser = mapped
        return mapped
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthUser {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: fullName
        )

        do {
            let authResult = try await Auth.auth().signIn(with: credential)
            // Apple adı yalnızca ilk girişte gelir; Firebase profiline bir kez yazılır.
            if authResult.user.displayName == nil, let components = fullName {
                let name = PersonNameComponentsFormatter().string(from: components)
                if !name.isEmpty {
                    let request = authResult.user.createProfileChangeRequest()
                    request.displayName = name
                    try? await request.commitChanges()
                }
            }
            let user = Self.map(authResult.user)
            currentUser = user
            return user
        } catch {
            throw AuthError.failed(error.localizedDescription)
        }
    }

    func signInWithGoogle() async throws -> AuthUser {
        #if os(tvOS)
        throw AuthError.notConfigured(
            "tvOS'ta Google girişi için OAuth cihaz akışı gerekiyor. Google Cloud'da \"TVs and Limited Input devices\" istemcisi oluşturulduktan sonra etkinleşecek."
        )
        #else
        throw AuthError.notConfigured(
            "Google girişi henüz yapılandırılmadı: GoogleService-Info.plist içinde CLIENT_ID yok. Firebase konsolunda Google sağlayıcısını açıp plist'i yeniden indirmen gerekiyor."
        )
        #endif
    }

    func signOut() throws {
        try Auth.auth().signOut()
        currentUser = nil
    }

    private static func map(_ user: User) -> AuthUser {
        AuthUser(
            uid: user.uid,
            displayName: user.displayName,
            email: user.email,
            photoURL: user.photoURL,
            providerID: user.providerData.first?.providerID
        )
    }
}
