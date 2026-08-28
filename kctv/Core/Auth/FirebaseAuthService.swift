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

        guard let presentingVC = Self.topViewController() else {
            throw AuthError.failed("Görünüm penceresi bulunamadı.")
        }

        let presenter = AuthPresenter(viewController: presentingVC)

        do {
            let credential = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthCredential, any Error>) in
                provider.getCredentialWith(presenter) { credential, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let credential = credential {
                        continuation.resume(returning: credential)
                    } else {
                        continuation.resume(throwing: AuthError.failed("Google kimlik bilgisi alınamadı."))
                    }
                }
            }

            let authResult = try await Auth.auth().signIn(with: credential)
            let user = Self.map(authResult.user)
            currentUser = user
            return user
        } catch let error as NSError {
            if error.domain == AuthErrorDomain,
               error.code == AuthErrorCode.webContextCancelled.rawValue ||
               error.code == AuthErrorCode.webContextAlreadyPresented.rawValue {
                throw AuthError.cancelled
            }
            if error.domain == "com.apple.AuthenticationServices.WebAuthenticationSession",
               error.code == 1 { // ASWebAuthenticationSessionError.canceledLogin
                throw AuthError.cancelled
            }
            throw AuthError.failed(error.localizedDescription)
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard let window = activeScene?.windows.first(where: \.isKeyWindow) ?? activeScene?.windows.first else {
            return nil
        }
        var topController = window.rootViewController
        while let presented = topController?.presentedViewController {
            topController = presented
        }
        return topController
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

/// Firebase OAuth için arayüz sunucu temsilcisi
private final class AuthPresenter: NSObject, AuthUIDelegate {
    private weak var viewController: UIViewController?

    init(viewController: UIViewController) {
        self.viewController = viewController
    }

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        viewController?.present(viewControllerToPresent, animated: flag, completion: completion)
    }

    func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        viewController?.dismiss(animated: flag, completion: completion)
    }
}
