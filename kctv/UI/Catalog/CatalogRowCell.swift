import UIKit

/// Kategori ekranındaki tek satır.
final class CatalogRowCell: UITableViewCell {
    static let reuseID = "CatalogRowCell"

    private let artwork = RemoteImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let menuButton = UIButton(type: .system)
    private let separator = UIView()

    private var artworkWidth: NSLayoutConstraint?
    private var artworkHeight: NSLayoutConstraint?
    private var separatorLeading: NSLayoutConstraint?

    /// Zoom geçişinin kaynağı.
    var artworkView: UIView { artwork }

    var onPlay: (() -> Void)?
    var onToggleFavorite: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        backgroundColor = .clear
        let selectedBackground = UIView()
        selectedBackground.backgroundColor = AppPalette.elevated
        selectedBackgroundView = selectedBackground

        artwork.layer.cornerRadius = 6
        artwork.layer.cornerCurve = .continuous
        artwork.clipsToBounds = true
        artwork.translatesAutoresizingMaskIntoConstraints = false

        // Ölçüler `configure` içinde metriklerden geliyor; tvOS'ta çok daha büyük.
        titleLabel.textColor = AppPalette.primaryText
        subtitleLabel.textColor = AppPalette.secondaryText

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = AppPalette.secondaryText
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.translatesAutoresizingMaskIntoConstraints = false

        separator.backgroundColor = AppPalette.separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        [artwork, textStack, menuButton, separator].forEach(contentView.addSubview)

        let width = artwork.widthAnchor.constraint(equalToConstant: 48)
        let height = artwork.heightAnchor.constraint(equalToConstant: 72)
        let inset = separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 80)
        artworkWidth = width
        artworkHeight = height
        separatorLeading = inset

        // Kendi kendine boyutlanan hücrede dikey zincirin bir halkası zorunlu
        // önceliğin altında olmalı; aksi hâlde tablonun yuvarladığı satır
        // yüksekliğiyle çakışıp her hücrede kısıt uyarısı basıyor.
        let top = artwork.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10)
        let bottom = artwork.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        bottom.priority = .init(999)
        height.priority = .init(999)

        NSLayoutConstraint.activate([
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            top, bottom,
            width, height,

            textStack.leadingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: 16),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: menuButton.leadingAnchor, constant: -8),

            menuButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            menuButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 44),

            inset,
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artwork.prepareForReuse()
    }

    func configure(item: MediaItem, metrics: AppMetrics, isFavorite: Bool) {
        let height = metrics.posterWidth * 0.62
        let width = height * item.kind.posterAspect
        artworkHeight?.constant = height
        artworkWidth?.constant = width
        separatorLeading?.constant = width + 32

        artwork.configure(url: item.posterURL, title: item.title, displayWidth: width)
        titleLabel.font = metrics.listTitleFont
        subtitleLabel.font = metrics.listSubtitleFont
        titleLabel.text = item.title

        let parts = [item.yearText, item.genres.first ?? item.categoryName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        subtitleLabel.text = parts.joined(separator: " · ")
        subtitleLabel.isHidden = parts.isEmpty

        menuButton.menu = UIMenu(children: [
            UIAction(title: item.kind == .live ? L10n.watch : L10n.play, image: UIImage(systemName: "play.fill")) { [weak self] _ in
                self?.onPlay?()
            },
            UIAction(
                title: isFavorite ? L10n.removeFromFavorites : L10n.addToFavorites,
                image: UIImage(systemName: isFavorite ? "checkmark" : "plus")
            ) { [weak self] _ in
                self?.onToggleFavorite?()
            },
        ])
    }
}
