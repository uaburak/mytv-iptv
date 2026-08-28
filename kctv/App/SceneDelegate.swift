import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    /// Uygulamanın tek durum kaynağı. Bütün ekranlar bunu paylaşır.
    private let model = AppModel(
        auth: AppDelegate.hasFirebaseConfig ? FirebaseAuthService() : PreviewAuthService()
    )

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = RootViewController(model: model)
        // Apple TV uygulaması gibi her zaman koyu.
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
        self.window = window
    }
}
