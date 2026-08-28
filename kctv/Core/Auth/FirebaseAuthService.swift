import AuthenticationServices
import Foundation
import FirebaseAuth

/// Firebase Authentication üzerinden Apple ve Google girişi.
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
        let provider = OAuthProvider(providerID: "google.com")
        provider.scopes = ["profile", "email"]
        provider.customParameters = ["prompt": "select_account"]

        do {
            let authResult = try await Auth.auth().signIn(with: provider)
            let user = Self.map(authResult.user)
            currentUser = user
            return user
        } catch {
            throw AuthError.failed(error.localizedDescription)
        }
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
