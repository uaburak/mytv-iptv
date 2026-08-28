import UIKit
import FirebaseCore

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    static let hasFirebaseConfig = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil

    private static var isFirebaseConfigured = false

    /// `FirebaseApp.app()` yapılandırma öncesi çağrıldığında kendisi hata
    /// logluyor; durumu kendi bayrağımızla izliyoruz.
    static func configureFirebaseIfPossible() {
        guard hasFirebaseConfig, !isFirebaseConfigured else { return }
        isFirebaseConfigured = true
        FirebaseApp.configure()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.configureFirebaseIfPossible()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
