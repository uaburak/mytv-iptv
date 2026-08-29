#if canImport(UIKit)
import UIKit

final class MainTabBarController: UITabBarController {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupAppearance()
        setupTabs()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .appLanguageDidChange,
            object: nil
        )
    }

    @objc private func languageDidChange() {
        updateTabTitles()
    }

    /// Çubuk görünümü.
    ///
    /// `UIBarAppearance` ailesi (`UITabBarAppearance`, `UINavigationBarAppearance`)
    /// tvOS başlıklarında tanımlı olduğu için **derleniyor**, ama tvOS onu
    /// çalışma zamanında reddediyor:
    /// "New Bar Appearance API is not supported on this version of tvOS."
    /// Bu yüzden tvOS'ta eski (legacy) özelleştirme kullanılıyor.
    private func setupAppearance() {
        #if os(iOS)
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.95)
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        #else
        tabBar.barTintColor = UIColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.95)
        #endif

        tabBar.tintColor = AppPalette.accent
        tabBar.unselectedItemTintColor = AppPalette.secondaryText
    }

    private func setupTabs() {
        let tabs: [(UIViewController, String, String)] = [
            (HomeViewController(model: model), L10n.tabHome, "house.fill"),
            (FavoritesViewController(model: model), L10n.tabFavorites, "heart.fill"),
            (PlaylistsViewController(model: model), L10n.tabPlaylists, "list.bullet.rectangle"),
            // Arama sekmesinin sarmalayıcısı platforma göre değişiyor;
            // tvOS'ta `UISearchContainerViewController` gerekiyor.
            (SearchViewController.makeTabController(model: model), L10n.tabSearch, "magnifyingglass"),
            (SettingsViewController(model: model), L10n.tabSettings, "gearshape.fill"),
        ]
        viewControllers = tabs.map { createNavController(for: $0.0, title: $0.1, image: $0.2) }
    }

    private func updateTabTitles() {
        guard let viewControllers, viewControllers.count == 5 else { return }
        let titles = [
            L10n.tabHome,
            L10n.tabFavorites,
            L10n.tabPlaylists,
            L10n.tabSearch,
            L10n.tabSettings
        ]
        for (index, nav) in viewControllers.enumerated() {
            nav.tabBarItem.title = titles[index]
        }
    }

    private func createNavController(for rootVC: UIViewController, title: String, image: String) -> UINavigationController {
        let nav = UINavigationController(rootViewController: rootVC)
        nav.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: image), selectedImage: UIImage(systemName: image))

        // Yeni Bar Appearance API'si tvOS'ta çalışma zamanında reddediliyor;
        // aynı saydam görünüm orada eski yöntemle kuruluyor.
        #if os(iOS)
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        nav.navigationBar.standardAppearance = navAppearance
        nav.navigationBar.scrollEdgeAppearance = navAppearance
        #else
        nav.navigationBar.setBackgroundImage(UIImage(), for: .default)
        nav.navigationBar.shadowImage = UIImage()
        nav.navigationBar.isTranslucent = true
        nav.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
        #endif

        nav.navigationBar.tintColor = AppPalette.accent
        return nav
    }
}
#endif
