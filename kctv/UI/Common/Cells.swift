import UIKit

/// Raylardaki tek içerik kartı.
///
/// Kart tamamen afişten ibaret: başlık ve ilerleme afişin üstündeki buzlu
/// şeritte duruyor, altında ayrı etiket yok. Şerit yalnızca gerektiğinde
/// görünüyor — yarım bırakılmış içerikte, ya da tvOS'ta kart odaktayken.
final class PosterCell: UICollectionViewCell {
    static let reuseID = "PosterCell"
    /// Odakta uygulanan büyüme; kenarlık kalınlığı da buna göre düzeltiliyor.
    private static let focusScale: CGFloat = 1.08

    private let artwork = RemoteImageView()
    private let overlay = CardOverlayView()
    private let badgeContainer = UIView()
    private let badgeLabel = UILabel()
    /// Afişin üstündeki cam katman yalnızca tvOS'ta.
    ///
    /// 10 feet mesafede camın kenardaki kırılması ve parlaması kartı zeminden
    /// ayırıyor, ekranın karanlığında kartın nerede bittiği ancak bundan belli
    /// oluyor. Elde tutulan ekranda ise afiş zaten kol mesafesinde: aynı katman
    /// orada görüntüyü yumuşatmaktan başka bir şey yapmıyordu, iOS'ta afiş
    /// olduğu gibi gösteriliyor.
    #if os(tvOS)
    private let glass = UIView.glassOverlay(cornerRadius: 0, intensity: 0.55)
    #endif
    private var artworkHeight: NSLayoutConstraint?

    private var title = ""
    private var progress: Double?
    private var metrics: AppMetrics?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        artwork.layer.cornerCurve = .continuous
        artwork.clipsToBounds = true
        artwork.translatesAutoresizingMaskIntoConstraints = false
        overlay.translatesAutoresizingMaskIntoConstraints = false

        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        badgeContainer.layer.cornerRadius = 6
        badgeContainer.layer.borderWidth = 0.8
        badgeContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        badgeContainer.clipsToBounds = true
        badgeContainer.isHidden = true

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeContainer.addSubview(badgeLabel)

        contentView.addSubview(artwork)
        // Sıra önemli: cam afişin üstünde (onu kırıyor), bilgi katmanı camın
        // üstünde (metin kırılmasın diye). İkisi de afişin içinde, böylece
        // köşe yuvarlaması ikisini de kırpıyor.
        #if os(tvOS)
        artwork.addSubview(glass)
        #endif
        artwork.addSubview(overlay)
        artwork.addSubview(badgeContainer)

        #if os(tvOS)
        prepareFocusShadow()
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: artwork.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: artwork.trailingAnchor),
            glass.topAnchor.constraint(equalTo: artwork.topAnchor),
            glass.bottomAnchor.constraint(equalTo: artwork.bottomAnchor),
        ])
        #endif

        NSLayoutConstraint.activate([
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            artwork.topAnchor.constraint(equalTo: contentView.topAnchor),

            overlay.leadingAnchor.constraint(equalTo: artwork.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: artwork.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: artwork.bottomAnchor),

            badgeContainer.topAnchor.constraint(equalTo: artwork.topAnchor, constant: 8),
            badgeContainer.trailingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: -8),
            badgeLabel.topAnchor.constraint(equalTo: badgeContainer.topAnchor, constant: 3),
            badgeLabel.bottomAnchor.constraint(equalTo: badgeContainer.bottomAnchor, constant: -3),
            badgeLabel.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 6),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -6),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artwork.prepareForReuse()
        artwork.alpha = 1.0
        badgeContainer.isHidden = true
        overlay.isHidden = true
    }

    /// Odakta kartın tamamı büyüyüp yükseliyor ve başlık şeridi beliriyor.
    ///
    /// tvOS'un yerel afiş efekti (`adjustsImageWhenAncestorFocused`) burada
    /// kullanılmıyor: o efekt görseli kendi çerçevesinin dışına taşırarak
    /// çiziyor, dolayısıyla kırpma kapalı olmak zorunda — kırpma kapalıyken de
    /// köşe yuvarlaması çalışmıyor. İkisi uzlaşmadığı için yuvarlak köşe ve
    /// büyüyen kart tercih edildi.
    #if os(tvOS)
    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        // Metin ve oynat işareti animasyona girmiyor: yerleşim değişimi
        // araya karıştığında yazılar kayarak/zıplayarak yerleşiyordu.
        // Yumuşak geçiş yalnızca kartın kendisinde — ölçek, gölge, ışık.
        applyOverlay()
        layoutIfNeeded()

        updateFocusAppearance(isFocused: isFocused, using: coordinator, scale: Self.focusScale)
    }
    #endif

    /// - Parameter cardWidth: kartın ekranda kaplayacağı genişlik. Izgara
    ///   düzenlerinde sütun genişliği ray ölçüsünden farklı oluyor; verilmezse
    ///   ray ölçüsü kullanılıyor. Görselin indirme boyutu da bundan geliyor.
    func configure(
        item: MediaItem,
        metrics: AppMetrics,
        progress: PlaybackProgress?,
        cardWidth: CGFloat? = nil,
        badgeText: String? = nil,
        isAvailable: Bool = true
    ) {
        self.title = item.title
        self.progress = progress?.fraction
        self.metrics = metrics

        let width = cardWidth ?? metrics.cardWidth(for: item.kind)
        artwork.layer.cornerRadius = metrics.cardCornerRadius
        #if os(tvOS)
        glass.cornerConfiguration = .uniformCorners(radius: .fixed(metrics.cardCornerRadius))
        #endif
        artwork.configure(url: item.posterURL, title: item.title, displayWidth: width)
        artwork.alpha = isAvailable ? 1.0 : 0.65

        if let badgeText, !badgeText.isEmpty {
            badgeLabel.text = badgeText
            badgeContainer.isHidden = false
        } else {
            badgeContainer.isHidden = true
        }

        artworkHeight?.isActive = false
        let height = artwork.heightAnchor.constraint(
            equalToConstant: width / item.kind.posterAspect
        )
        height.isActive = true
        artworkHeight = height

        // Kart tek bir erişilebilirlik öğesi: içinde okunacak bir alt görünüm
        // yok, başlık yalnızca kaplamada ve o da her zaman görünmüyor.
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = item.accessibilityDescription
        accessibilityValue = progress.map { L10n.watchedPercent(Int(($0.fraction * 100).rounded())) }

        applyOverlay()
    }

    private func applyOverlay() {
        guard let metrics else { return }
        #if os(tvOS)
        let shouldShow = progress != nil || isFocused
        #else
        let shouldShow = progress != nil
        #endif
        overlay.isHidden = !shouldShow
        guard shouldShow else { return }

        #if os(tvOS)
        let focused = isFocused
        #else
        let focused = false
        #endif
        overlay.configure(
            title: title,
            durationText: nil,
            progress: progress,
            focused: focused,
            metrics: metrics
        )
    }
}

/// Anasayfadaki "Canlı / Film / Dizi" ana kartları.
final class MainCardCell: UICollectionViewCell {
    static let reuseID = "MainCardCell"

    private var glassSurface: UIVisualEffectView!
    private let content = UIView()
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        // Ana kartlar cam: tür rengi camın tonu olarak veriliyor, böylece
        // kimlik korunuyor ama malzeme diğer kartlarla aynı.
        #if os(tvOS)
        let radius: CGFloat = 24
        prepareFocusShadow()
        #else
        let radius: CGFloat = 12
        #endif
        glassSurface = UIView.glassSurface(wrapping: content, cornerRadius: radius)
        contentView.addSubview(glassSurface)

        symbolView.tintColor = UIColor.white.withAlphaComponent(0.22)
        symbolView.contentMode = .scaleAspectFit

        // Ölçüler `configure` içinde metriklerden geliyor.
        titleLabel.textColor = .white
        countLabel.textColor = UIColor.white.withAlphaComponent(0.8)

        let stack = UIStackView(arrangedSubviews: [titleLabel, countLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(symbolView)
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            glassSurface.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            glassSurface.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            glassSurface.topAnchor.constraint(equalTo: contentView.topAnchor),
            glassSurface.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            symbolView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            symbolView.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            symbolView.widthAnchor.constraint(equalToConstant: 54),
            symbolView.heightAnchor.constraint(equalToConstant: 54),

            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: symbolView.leadingAnchor, constant: -8),
        ])
    }

    // tvOS'ta hücre odaklanınca büyüyüp yükseliyor; kullanıcı nerede olduğunu
    // yalnızca bundan anlıyor. Efekt `contentView`'e değil hücreye uygulanıyor:
    // `contentView` kırpma yaptığında kendi gölgesi hiç çizilmiyor.
    #if os(tvOS)
    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        updateFocusAppearance(isFocused: isFocused, using: coordinator)
    }
    #endif


    func configure(kind: MediaKind, count: Int, metrics: AppMetrics) {
        titleLabel.font = metrics.mainCardTitleFont
        countLabel.font = metrics.mainCardCountFont
        titleLabel.text = kind.title
        countLabel.text = count > 0 ? L10n.itemCount(count) : nil
        symbolView.image = UIImage(systemName: kind.symbol)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = [titleLabel.text, countLabel.text]
            .compactMap { $0 }
            .joined(separator: ", ")

        // Tür rengi camın tonu; ton saydam veriliyor ki malzeme kaybolmasın.
        let tint = AppPalette.mainCardColors(for: kind).first?.withAlphaComponent(0.55)
        (glassSurface.effect as? UIGlassEffect)?.tintColor = tint
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

        var constraints = [
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ]

        // tvOS'ta ray başlığı yalnızca bir etiket: dokunulabilir olsaydı
        // odaklanabilir olurdu ve sistem arkasına kendi odak zeminini çizerdi —
        // başlık o zeminin içinde okunmuyordu. Kategoriye gitmek için zaten
        // rayın kartları var, başlığa ayrıca yönlendirme gerekmiyor.
        #if os(iOS)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(handleTap), for: .primaryActionTriggered)
        addSubview(button)
        constraints += [
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ]
        #endif

        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, font: UIFont, showsChevron: Bool) {
        titleLabel.text = title
        titleLabel.font = font
        #if os(iOS)
        chevron.isHidden = !showsChevron
        button.isEnabled = showsChevron
        #else
        // tvOS'ta yönlendirme yok; ok işareti de anlamsız.
        chevron.isHidden = true
        #endif
    }

    @objc private func handleTap() { onTap?() }
}
