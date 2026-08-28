import UIKit

/// Raylardaki tek içerik kartı.
final class PosterCell: UICollectionViewCell {
    static let reuseID = "PosterCell"

    private let artwork = RemoteImageView()
    private let titleLabel = UILabel()
    private let captionLabel = UILabel()
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private var progressWidth: NSLayoutConstraint?
    private var artworkHeight: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        artwork.layer.cornerRadius = 8
        artwork.layer.cornerCurve = .continuous
        artwork.clipsToBounds = true

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = AppPalette.primaryText
        captionLabel.font = .systemFont(ofSize: 13)
        captionLabel.textColor = AppPalette.secondaryText

        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        progressTrack.layer.cornerRadius = 1.5
        progressFill.backgroundColor = .white
        progressFill.layer.cornerRadius = 1.5
        progressTrack.isHidden = true

        let stack = UIStackView(arrangedSubviews: [artwork, titleLabel, captionLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(8, after: artwork)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        artwork.addSubview(progressTrack)
        progressTrack.addSubview(progressFill)

        let width = progressFill.widthAnchor.constraint(equalToConstant: 0)
        progressWidth = width

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),

            progressTrack.leadingAnchor.constraint(equalTo: artwork.leadingAnchor, constant: 8),
            progressTrack.trailingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: -8),
            progressTrack.bottomAnchor.constraint(equalTo: artwork.bottomAnchor, constant: -8),
            progressTrack.heightAnchor.constraint(equalToConstant: 3),

            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            width,
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artwork.prepareForReuse()
        progressTrack.isHidden = true
    }

    func configure(item: MediaItem, metrics: AppMetrics, progress: PlaybackProgress?) {
        let width = metrics.cardWidth(for: item.kind)
        artwork.configure(url: item.posterURL, title: item.title, displayWidth: width)
        artworkHeight?.isActive = false
        let height = artwork.heightAnchor.constraint(equalToConstant: metrics.cardHeight(for: item.kind))
        height.isActive = true
        artworkHeight = height

        titleLabel.text = item.title
        titleLabel.font = metrics.cardTitleFont
        captionLabel.text = caption(for: item)
        captionLabel.font = metrics.cardTitleFont

        // Telefonda afiş kendi başına yeterli; etiketler kalabalık yapıyor.
        titleLabel.isHidden = !metrics.showsCardLabels
        captionLabel.isHidden = !metrics.showsCardLabels || captionLabel.text == nil

        guard let progress else {
            progressTrack.isHidden = true
            return
        }
        progressTrack.isHidden = false
        progressWidth?.constant = max(3, (width - 16) * progress.fraction)
    }

    private func caption(for item: MediaItem) -> String? {
        switch item.kind {
        case .live:
            item.categoryName
        case .movie:
            [item.yearText, item.durationText].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        case .series:
            item.genres.first ?? item.yearText
        }
    }
}

/// Anasayfadaki "Canlı / Film / Dizi" ana kartları.
final class MainCardCell: UICollectionViewCell {
    static let reuseID = "MainCardCell"

    private let gradientLayer = CAGradientLayer()
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        contentView.layer.insertSublayer(gradientLayer, at: 0)

        symbolView.tintColor = UIColor.white.withAlphaComponent(0.22)
        symbolView.contentMode = .scaleAspectFit

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .white
        countLabel.font = .systemFont(ofSize: 14)
        countLabel.textColor = UIColor.white.withAlphaComponent(0.8)

        let stack = UIStackView(arrangedSubviews: [titleLabel, countLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(symbolView)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            symbolView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            symbolView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            symbolView.widthAnchor.constraint(equalToConstant: 54),
            symbolView.heightAnchor.constraint(equalToConstant: 54),

            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: symbolView.leadingAnchor, constant: -8),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = contentView.bounds
    }

    func configure(kind: MediaKind, count: Int) {
        titleLabel.text = kind.title
        countLabel.text = count > 0 ? "\(count.formatted()) içerik" : nil
        symbolView.image = UIImage(systemName: kind.symbol)

        let colors = AppPalette.mainCardColors(for: kind)
        gradientLayer.colors = colors.map(\.cgColor)
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
    }
}

/// Ray başlığı — dokunulunca tüm kategoriyi açar.
final class RowHeaderView: UICollectionReusableView {
    static let reuseID = "RowHeaderView"

    private let titleLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
    private let button = UIButton(type: .system)

    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        chevron.tintColor = AppPalette.secondaryText
        chevron.contentMode = .scaleAspectFit
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, chevron])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        addSubview(button)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, font: UIFont, showsChevron: Bool) {
        titleLabel.text = title
        titleLabel.font = font
        chevron.isHidden = !showsChevron
        button.isEnabled = showsChevron
    }

    @objc private func handleTap() { onTap?() }
}
