import UIKit

/// Arama ekranındaki kapsül düğme: tür süzgeci ve son aramalar.
///
/// Hücrenin içinde gerçek bir `UIButton` var ve konfigürasyonu detay
/// ekranındaki sezon çipleriyle **aynı** (`UIButton.Configuration.appChip`):
/// seçili olan beyaz zemin + siyah metin, diğerleri cam, odakta/hover'da
/// sistemin kendi beyaz vurgusu.
///
/// Genişlik butonun kendi içeriğinden geliyor (`.estimated`), böylece son
/// aramalar satıra sığdığı kadar yan yana dizilip alt satıra taşıyor.
final class SearchChipCell: UICollectionViewCell {
    static let reuseID = "SearchChipCell"

    /// Stil detay ekranındaki çiplerin aynısı; ölçü platforma göre değişiyor.
    /// tvOS'ta kullanıcı ekrana 3 metre uzaktan bakıyor ve düğmeye kumandayla
    /// geliyor: aynı puntolar orada okunmuyor, hedef de küçük kalıyor.
    #if os(tvOS)
    static let height: CGFloat = 68
    private static let horizontalInset: CGFloat = 34
    private static let verticalInset: CGFloat = 18
    private static let fontSize: CGFloat = 26
    #else
    static let height: CGFloat = 44
    private static let horizontalInset: CGFloat = 24
    private static let verticalInset: CGFloat = 12
    private static let fontSize: CGFloat = 16
    #endif

    private let button = UIButton(type: .system)
    private var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Odak **düğmeye** gitmeli: hücre odaklanabilir kaldığında odağı o
    /// yakalıyor, düğme hiç odaklanmadığı için sistemin beyaz vurgusu da
    /// çalışmıyordu — kumandayla üstüne gelince hiçbir şey olmuyordu.
    #if os(tvOS)
    override var canBecomeFocused: Bool { false }
    #endif

    private func build() {
        backgroundColor = .clear

        // Detay ekranındaki butonlarla birebir aynı basma animasyonu.
        button.addSpringPressFeedback(scale: 0.93)
        button.addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .primaryActionTriggered)
        button.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(button)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            button.topAnchor.constraint(equalTo: contentView.topAnchor),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            button.heightAnchor.constraint(equalToConstant: Self.height),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onTap = nil
    }

    /// - Parameter isSelected: seçili çip beyaz zemin + siyah metne dönüyor;
    ///   tür süzgecinde kullanılıyor, son aramalarda hep `false`.
    func configure(
        title: String,
        symbol: String?,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) {
        var configuration = UIButton.Configuration.appChip(
            isSelected: isSelected,
            horizontalInset: Self.horizontalInset,
            verticalInset: Self.verticalInset,
            fontSize: Self.fontSize
        )
        configuration.title = title
        configuration.image = symbol.flatMap { UIImage(systemName: $0) }
        button.configuration = configuration
        self.onTap = onTap
    }
}

/// Arama ekranındaki hazır arama kartı — "Aksiyon Filmleri", "Belgeseller".
///
/// Poster kartla aynı ölçü, köşe yarıçapı ve cam malzemesi ama afişi yok: bir
/// türü tek bir afişle temsil etmek yanıltıcı duruyordu, kartın kimliğini renk
/// veriyor. Zemin açık tondan koyu tona iniyor, başlık da koyu uçta duruyor —
/// poster kartındaki bulanık şeride burada gerek kalmıyor, yazı doğrudan
/// zeminin üstünde okunuyor.
final class SearchSuggestionCell: UICollectionViewCell {
    static let reuseID = "SearchSuggestionCell"
    private static let focusScale: CGFloat = 1.08

    private let gradient = CAGradientLayer()
    private let glass = UIView.glassOverlay(cornerRadius: 0, intensity: 0.55)
    private let titleLabel = UILabel()
    private let symbolView = UIImageView()
    private var titleConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        backgroundColor = .clear
        contentView.backgroundColor = AppPalette.background
        contentView.clipsToBounds = true
        contentView.layer.cornerCurve = .continuous
        contentView.layer.insertSublayer(gradient, at: 0)

        symbolView.tintColor = UIColor.white.withAlphaComponent(0.28)
        symbolView.contentMode = .scaleAspectFit
        symbolView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Cam simgenin üstünde (onu kırıyor), başlık camın üstünde (metin
        // kırılmasın diye).
        [symbolView, glass, titleLabel].forEach(contentView.addSubview)

        #if os(tvOS)
        prepareFocusShadow()
        #endif

        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            glass.topAnchor.constraint(equalTo: contentView.topAnchor),
            glass.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            symbolView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Katman Auto Layout dışında; çerçevesi elle veriliyor.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = contentView.bounds
        CATransaction.commit()
    }

    #if os(tvOS)
    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        updateFocusAppearance(isFocused: isFocused, using: coordinator, scale: Self.focusScale)
    }
    #endif

    /// - Parameter colorIndex: kartın destedeki sırası; zemin rengi buradan
    ///   seçiliyor, böylece yan yana duran kartlar farklı renklerde oluyor.
    func configure(
        suggestion: SearchSuggestion,
        metrics: AppMetrics,
        cardWidth: CGFloat,
        colorIndex: Int
    ) {
        contentView.layer.cornerRadius = metrics.cardCornerRadius
        glass.cornerConfiguration = .uniformCorners(radius: .fixed(metrics.cardCornerRadius))

        gradient.colors = AppPalette.suggestionGradient(at: colorIndex).map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)

        symbolView.image = UIImage(systemName: suggestion.symbol)
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: max(cardWidth * 0.3, 22), weight: .semibold
        )

        // İçerik sayısı gösterilmiyor; kartta yalnızca türün adı var.
        titleLabel.font = metrics.rowTitleFont
        titleLabel.text = suggestion.title

        let padding = metrics.cardOverlayPadding
        titleConstraints.forEach { $0.isActive = false }
        titleConstraints = [
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -padding),
        ]
        NSLayoutConstraint.activate(titleConstraints)
    }
}

/// Arama ekranındaki bölüm başlığı. Sağında isteğe bağlı bir eylem duruyor —
/// son aramalarda "Temizle".
final class SearchSectionHeaderView: UICollectionReusableView {
    static let reuseID = "SearchSectionHeaderView"

    #if os(tvOS)
    private static let actionFontSize: CGFloat = 24
    private static let actionInset: CGFloat = 22
    #else
    private static let actionFontSize: CGFloat = 13
    private static let actionInset: CGFloat = 14
    #endif

    private let titleLabel = UILabel()
    private let actionButton = UIButton(configuration: .appChip(
        isSelected: false,
        horizontalInset: SearchSectionHeaderView.actionInset,
        verticalInset: SearchSectionHeaderView.actionInset * 0.4,
        fontSize: SearchSectionHeaderView.actionFontSize
    ))

    var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.textColor = .white

        actionButton.addSpringPressFeedback(scale: 0.93)
        actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .primaryActionTriggered)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, UIView(), actionButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, font: UIFont, actionTitle: String?) {
        titleLabel.text = title
        titleLabel.font = font
        actionButton.isHidden = actionTitle == nil
        actionButton.configuration?.title = actionTitle
    }
}
