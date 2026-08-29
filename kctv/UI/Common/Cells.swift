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

        contentView.addSubview(artwork)
        // Bindirme afişin içinde: köşe yuvarlaması onu da kırpıyor.
        artwork.addSubview(overlay)

        artwork.layer.borderColor = UIColor.white.cgColor
        #if os(tvOS)
        prepareFocusShadow()
        #endif

        NSLayoutConstraint.activate([
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            artwork.topAnchor.constraint(equalTo: contentView.topAnchor),

            overlay.leadingAnchor.constraint(equalTo: artwork.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: artwork.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: artwork.bottomAnchor),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artwork.prepareForReuse()
        overlay.isHidden = true
        // Odaktayken geri dönen hücrede kenarlık açık kalmasın.
        artwork.layer.borderWidth = 0
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

        // Kenarlık animasyona girmiyor: düz açılıp kapanıyor. Kart ölçeğine
        // bölünüyor ki büyürken kalınlaşmasın.
        let focused = isFocused
        artwork.layer.borderWidth = focused ? UIView.focusedBorderWidth / Self.focusScale : 0

        updateFocusAppearance(isFocused: focused, using: coordinator, scale: Self.focusScale)
    }
    #endif

    func configure(item: MediaItem, metrics: AppMetrics, progress: PlaybackProgress?) {
        self.title = item.title
        self.progress = progress?.fraction
        self.metrics = metrics

        let width = metrics.cardWidth(for: item.kind)
        artwork.layer.cornerRadius = metrics.cardCornerRadius
        artwork.configure(url: item.posterURL, title: item.title, displayWidth: width)

        artworkHeight?.isActive = false
        let height = artwork.heightAnchor.constraint(
            equalToConstant: metrics.cardHeight(for: item.kind)
        )
        height.isActive = true
        artworkHeight = height

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
        #if os(tvOS)
        contentView.layer.cornerRadius = 24
        #else
        contentView.layer.cornerRadius = 12
        #endif
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        contentView.layer.insertSublayer(gradientLayer, at: 0)
        // Gölge `contentView` kırptığı için hücrenin kendisine kuruluyor.
        #if os(tvOS)
        prepareFocusShadow()
        #endif

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
