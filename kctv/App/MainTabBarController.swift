#if os(iOS)
import UIKit

/// iPhone/iPad kabuğu.
///
/// Bölümlerin adı, simgesi ve hangi ekranı açtığı `AppDestination` içinde;
/// burada yalnızca çubuğun görünümü ve sekmelerin kurulumu var. Apple TV'de
/// aynı liste `SidebarViewController` tarafından kenar çubuğu olarak
/// çiziliyor.
final class MainTabBarController: UITabBarController {
    private let model: AppModel
    private let destinations = AppDestination.tabBar

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
        for (index, nav) in (viewControllers ?? []).enumerated() where index < destinations.count {
            nav.tabBarItem.title = destinations[index].title
        }
    }

    private func setupAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.95)
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = AppPalette.accent
        tabBar.unselectedItemTintColor = AppPalette.secondaryText
    }

    private func setupTabs() {
        viewControllers = destinations.map { destination in
            let nav = UINavigationController.app(root: destination.makeViewController(model: model))
            let image = UIImage(systemName: destination.symbol)
            nav.tabBarItem = UITabBarItem(title: destination.title, image: image, selectedImage: image)
            return nav
        }
    }
}
#endif
