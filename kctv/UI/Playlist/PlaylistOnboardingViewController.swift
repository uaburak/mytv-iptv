import UIKit

/// Henüz listesi olmayan kullanıcının gördüğü ilk ekran.
final class PlaylistOnboardingViewController: UIViewController {
    private let model: AppModel

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

        let title = UILabel()
        title.text = "Henüz bir listen yok"
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textColor = .white
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "Xtream Codes hesabını ya da M3U bağlantını ekle;\ncanlı kanallar, filmler ve diziler burada görünsün."
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = AppPalette.secondaryText
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        var addConfiguration = UIButton.Configuration.filled()
        addConfiguration.title = "Liste Ekle"
        addConfiguration.image = UIImage(systemName: "plus")
        addConfiguration.imagePadding = 6
        addConfiguration.cornerStyle = .capsule
        let addButton = UIButton(configuration: addConfiguration)
        addButton.addTarget(self, action: #selector(addPlaylist), for: .touchUpInside)
        addButton.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle, addButton])
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
    }

    @objc private func addPlaylist() {
        let controller = AddPlaylistViewController(model: model)
        present(UINavigationController(rootViewController: controller), animated: true)
    }

}
