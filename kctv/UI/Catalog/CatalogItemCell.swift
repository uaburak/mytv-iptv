import UIKit

/// Katalog ekranındaki içerik hücresi. Aynı hücre iki düzeni de çiziyor:
/// satır (afiş solda, başlık ve alt satır sağda) ve poster kart (yalnızca
/// afiş — kartta metin gösterilmiyor).
///
/// İki ayrı hücre sınıfı yerine tek sınıf kullanılıyor: görünüm değişirken
/// koleksiyonu yeniden yüklemek gerekmiyor, `setCollectionViewLayout` mevcut
/// hücreleri yeni yerlerine taşırken hücre de kendi içini aynı anda
/// dönüştürüyor. İki sınıf olsaydı geçiş ancak sert bir yeniden yükleme olurdu.
final class CatalogItemCell: UICollectionViewCell {
    static let reuseID = "CatalogItemCell"

    enum DisplayMode {
        case list
        case grid
    }

    private let artwork = RemoteImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textStack = UIStackView()
    private let menuButton = UIButton(type: .system)
    private let separator = UIView()

    /// Zoom geçişinin kaynağı.
    var artworkView: UIView { artwork }

    var onPlay: (() -> Void)?
    var onToggleFavorite: (() -> Void)?

    private var listConstraints: [NSLayoutConstraint] = []
    private var gridConstraints: [NSLayoutConstraint] = []
    private var artworkWidth: NSLayoutConstraint!
    private var artworkHeight: NSLayoutConstraint!
    private var mode: DisplayMode = .grid

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        backgroundColor = .clear
        #if os(tvOS)
        prepareFocusShadow()
        #endif

        // Yarıçap `configure` içinde metriklerden geliyor.
        artwork.layer.cornerCurve = .continuous
        artwork.clipsToBounds = true
        artwork.translatesAutoresizingMaskIntoConstraints = false

        // Metin yalnızca satır düzeninde görünüyor. Ölçü `configure` içinde
        // metriklerden geliyor: tvOS'ta 10 feet mesafe için çok daha büyük.
        titleLabel.textColor = AppPalette.primaryText
        titleLabel.numberOfLines = 1
        subtitleLabel.textColor = AppPalette.secondaryText

        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        [titleLabel, subtitleLabel].forEach(textStack.addArrangedSubview)

        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = AppPalette.secondaryText
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.translatesAutoresizingMaskIntoConstraints = false

        separator.backgroundColor = AppPalette.separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        [artwork, textStack, menuButton, separator].forEach(contentView.addSubview)

        artworkWidth = artwork.widthAnchor.constraint(equalToConstant: 48)
        artworkHeight = artwork.heightAnchor.constraint(equalToConstant: 72)

        listConstraints = [
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            artwork.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            artworkWidth,
            artworkHeight,

            textStack.leadingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: 16),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -8),

            menuButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            menuButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 44),

            separator.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ]

        // Kartta afiş hücrenin tamamını kaplıyor; hücre yüksekliğini zaten
        // düzen afişin oranına göre veriyor.
        gridConstraints = [
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            artwork.topAnchor.constraint(equalTo: contentView.topAnchor),
            artwork.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ]

        applyMode(.grid)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artwork.prepareForReuse()
    }

    #if os(tvOS)
    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        // Kart düzeninde afiş büyüyor, satır düzeninde satır hafifçe kalkıyor.
        updateFocusAppearance(isFocused: isFocused, using: coordinator, scale: mode == .grid ? 1.08 : 1.02)
    }
    #endif

    /// Yalnızca düzeni değiştiriyor; çağıranın bunu bir animasyon bloğuna
    /// alması hâlinde geçiş yumuşuyor.
    func applyMode(_ mode: DisplayMode) {
        self.mode = mode
        switch mode {
        case .list:
            NSLayoutConstraint.deactivate(gridConstraints)
            NSLayoutConstraint.activate(listConstraints)
            textStack.isHidden = false
            menuButton.isHidden = false
            separator.isHidden = false
        case .grid:
            NSLayoutConstraint.deactivate(listConstraints)
            NSLayoutConstraint.activate(gridConstraints)
            textStack.isHidden = true
            menuButton.isHidden = true
            separator.isHidden = true
        }
        contentView.layoutIfNeeded()
    }

    /// `imageWidth` her iki modda da kart ölçüsü olarak geliyor. Satırda afiş
    /// küçük ama görünüm değiştiğinde `RemoteImageView` aynı URL'yi yeniden
    /// yüklemediği için, satır ölçüsünde indirilseydi kartlar bulanık açılırdı.
    func configure(
        item: MediaItem,
        metrics: AppMetrics,
        mode: DisplayMode,
        imageWidth: CGFloat,
        isFavorite: Bool
    ) {
        let listHeight = metrics.posterWidth * 0.62
        artworkHeight.constant = listHeight
        artworkWidth.constant = listHeight * item.kind.posterAspect

        applyMode(mode)
        artwork.layer.cornerRadius = metrics.cardCornerRadius
        // Kanal logosu afiş değil: her biri başka oranda geliyor ve karta
        // doldurmak için kırpılınca logonun kenarları gidiyor. Kart zemini
        // zaten siyah; logo geldiği oranla ortasına sığıyor — kenarlara
        // dayanmasın diye de bir pay bırakılıyor.
        let isChannelLogo = item.kind == .live
        artwork.imageContentMode = isChannelLogo ? .scaleAspectFit : .scaleAspectFill
        artwork.imageInsetRatio = isChannelLogo ? RemoteImageView.logoInsetRatio : 0
        artwork.configure(url: item.posterURL, title: item.title, displayWidth: max(imageWidth, 1))

        titleLabel.font = metrics.listTitleFont
        subtitleLabel.font = metrics.listSubtitleFont
        titleLabel.text = item.title

        let parts = [item.yearText, item.genres.first ?? item.categoryName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        subtitleLabel.text = parts.joined(separator: " · ")
        subtitleLabel.isHidden = parts.isEmpty

        let menu = UIMenu(children: [
            UIAction(
                title: item.kind == .live ? L10n.watch : L10n.play,
                image: UIImage(systemName: "play.fill")
            ) { [weak self] _ in
                self?.onPlay?()
            },
            UIAction(
                title: isFavorite ? L10n.removeFromFavorites : L10n.addToFavorites,
                image: UIImage(systemName: isFavorite ? "checkmark" : "plus")
            ) { [weak self] _ in
                self?.onToggleFavorite?()
            },
        ])
        menuButton.menu = menu

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = item.accessibilityDescription
    }
}
