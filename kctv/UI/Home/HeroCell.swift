import UIKit

/// Anasayfanın üstündeki tam genişlikte öne çıkan içerik. Elle kaydırılabilir
/// (bölüm yatay sayfalama yapıyor), üstünde bilgi ve favori butonları var.
final class HeroCell: UICollectionViewCell {
    static let reuseID = "HeroCell"

    private let backdrop = RemoteImageView()
    private let scrim = CAGradientLayer()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let infoButton = UIButton(configuration: .filled())
    private let favoriteButton = UIButton(configuration: .bordered())

    private var item: MediaItem?
    var onDetails: ((MediaItem) -> Void)?
    var onToggleFavorite: ((MediaItem) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        contentView.clipsToBounds = true
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backdrop)

        scrim.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.35).cgColor,
            UIColor.black.withAlphaComponent(0.85).cgColor,
            UIColor.black.cgColor,
        ]
        scrim.locations = [0, 0.45, 0.78, 1]
        contentView.layer.addSublayer(scrim)

        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        metaLabel.font = .systemFont(ofSize: 14)
        metaLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        metaLabel.textAlignment = .center

        var infoConfiguration = UIButton.Configuration.filled()
        infoConfiguration.title = "Daha Fazla Bilgi"
        infoConfiguration.image = UIImage(systemName: "info.circle")
        infoConfiguration.imagePadding = 6
        infoConfiguration.baseBackgroundColor = .white
        infoConfiguration.baseForegroundColor = .black
        infoConfiguration.cornerStyle = .capsule
        infoButton.configuration = infoConfiguration
        infoButton.addTarget(self, action: #selector(showDetails), for: .touchUpInside)

        var favoriteConfiguration = UIButton.Configuration.bordered()
        favoriteConfiguration.image = UIImage(systemName: "plus")
        favoriteConfiguration.cornerStyle = .capsule
        favoriteConfiguration.baseForegroundColor = .white
        favoriteButton.configuration = favoriteConfiguration
        favoriteButton.addTarget(self, action: #selector(toggleFavorite), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [infoButton, favoriteButton])
        buttons.axis = .horizontal
        buttons.spacing = 14

        let stack = UIStackView(arrangedSubviews: [titleLabel, metaLabel, buttons])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: contentView.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -44),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrim.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        backdrop.prepareForReuse()
    }

    func configure(item: MediaItem, metrics: AppMetrics, isFavorite: Bool) {
        self.item = item
        backdrop.configure(
            url: item.backdropURL ?? item.posterURL,
            title: item.title,
            displayWidth: metrics.heroImageWidth
        )
        titleLabel.text = item.title
        titleLabel.font = metrics.titleFont

        var parts = [item.kind.title]
        if let genre = item.genres.first { parts.append(genre) }
        if let percent = item.ratingPercent { parts.append("%\(percent)") }
        metaLabel.text = parts.joined(separator: " · ")

        favoriteButton.configuration?.image = UIImage(systemName: isFavorite ? "checkmark" : "plus")
    }

    @objc private func showDetails() {
        guard let item else { return }
        onDetails?(item)
    }

    @objc private func toggleFavorite() {
        guard let item else { return }
        onToggleFavorite?(item)
        favoriteButton.configuration?.image = UIImage(systemName: "checkmark")
    }
}
