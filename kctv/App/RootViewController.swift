#if canImport(UIKit)
import UIKit

final class RootViewController: UIViewController {
    private let model: AppModel
    private var currentChild: UIViewController?

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        setupNotifications()
        updateChild(for: model.phase, animated: false)

        Task { [weak self] in
            await self?.model.start()
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handlePhaseChange), name: .appModelPhaseDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlaybackChange), name: .appModelPlaybackDidChange, object: nil)
    }

    @objc private func handlePhaseChange() {
        updateChild(for: model.phase, animated: true)
    }

    @objc private func handlePlaybackChange() {
        guard let context = model.playback else { return }
        model.playback = nil
        let playerVC = PlayerViewController(context: context, model: model)
        present(playerVC, animated: true)
    }

    private func updateChild(for phase: AppPhase, animated: Bool) {
        let newVC: UIViewController
        switch phase {
        case .launching:
            newVC = LaunchingViewController()
        case .signedOut:
            newVC = SignInViewController(model: model)
        case .needsPlaylist:
            newVC = PlaylistOnboardingViewController(model: model)
        case .ready:
            // Kabuk platforma göre değişiyor: telefonda sekme çubuğu, Apple
            // TV'de kenar çubuğu. İkisi de aynı menü listesinden besleniyor
            // (`AppDestination`).
            #if os(tvOS)
            newVC = SidebarViewController(model: model)
            #else
            newVC = MainTabBarController(model: model)
            #endif
        }

        if let existing = currentChild {
            if type(of: existing) == type(of: newVC) { return }

            existing.willMove(toParent: nil)
            addChild(newVC)
            newVC.view.frame = view.bounds
            newVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            if animated {
                transition(from: existing, to: newVC, duration: 0.3, options: .transitionCrossDissolve, animations: nil) { [weak self] _ in
                    existing.removeFromParent()
                    newVC.didMove(toParent: self)
                    self?.currentChild = newVC
                }
            } else {
                existing.view.removeFromSuperview()
                existing.removeFromParent()
                view.addSubview(newVC.view)
                newVC.didMove(toParent: self)
                currentChild = newVC
            }
        } else {
            addChild(newVC)
            newVC.view.frame = view.bounds
            newVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(newVC.view)
            newVC.didMove(toParent: self)
            currentChild = newVC
        }
    }
}

private final class LaunchingViewController: UIViewController {
    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        spinner.startAnimating()
    }
}
#endif
