import UIKit

/// Henüz listesi olmayan kullanıcının gördüğü ilk ekran.
final class PlaylistOnboardingViewController: UIViewController {
    private let model: AppModel
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let addButton = UIButton(configuration: .filled())

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background

        let icon = UIImageView(image: UIImage(systemName: "list.and.film"))
        icon.tintColor = AppPalette.secondaryText
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = AppPalette.secondaryText
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        var addConfiguration = UIButton.Configuration.filled()
        addConfiguration.image = UIImage(systemName: "plus")
        addConfiguration.imagePadding = 6
        addConfiguration.cornerStyle = .capsule
        addButton.configuration = addConfiguration
        addButton.addTarget(self, action: #selector(addPlaylist), for: .primaryActionTriggered)
        addButton.heightAnchor.constraint(equalToConstant: 48).isActive = true

        updateLocalizedTexts()

        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, subtitleLabel, addButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateLocalizedTexts),
            name: .appLanguageDidChange,
            object: nil
        )
    }

    @objc private func updateLocalizedTexts() {
        titleLabel.text = L10n.noPlaylistsTitle
        subtitleLabel.text = L10n.noPlaylistsSubtitle
        addButton.configuration?.title = L10n.addPlaylist
    }

    @objc private func addPlaylist() {
        let controller = AddPlaylistViewController(model: model)
        present(UINavigationController(rootViewController: controller), animated: true)
    }
}
