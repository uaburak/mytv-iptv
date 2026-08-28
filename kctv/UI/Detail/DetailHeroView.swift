import UIKit

/// `layerClass`'ı `CAGradientLayer` olan yerel UIKit gradient bileşeni.
private final class HeroGradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

    var colors: [UIColor] = [] {
        didSet { gradientLayer.colors = colors.map(\.cgColor) }
    }

    var locations: [NSNumber]? {
        get { gradientLayer.locations }
        set { gradientLayer.locations = newValue }
    }
}

/// Apple Liquid Glass tasarım diline uygun, gerçek `UIVisualEffectView` tabanlı buton.
/// Arka plandaki içeriği dinamik olarak bulanıklaştırır, yarı saydam cam efekti ve
/// dokunulduğunda akıcı fiziksel yay (spring) tepkisi verir.
open class LiquidGlassButton: UIControl {
    public let effectView: UIVisualEffectView
    public let highlightOverlay = UIView()
    public let contentStack = UIStackView()
    public let iconView = UIImageView()
    public let titleLabel = UILabel()

    public var cornerRadius: CGFloat = 22 {
        didSet {
            layer.cornerRadius = cornerRadius
            effectView.layer.cornerRadius = cornerRadius
            highlightOverlay.layer.cornerRadius = cornerRadius
        }
    }

    public override init(frame: CGRect) {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        self.effectView = UIVisualEffectView(effect: blur)
        super.init(frame: frame)
        build()
    }

    public required init?(coder: NSCoder) {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        self.effectView = UIVisualEffectView(effect: blur)
        super.init(coder: coder)
        build()
    }

    private func build() {
        clipsToBounds = false

        // 1. Liquid Glass Arka Planı (UIVisualEffectView)
        effectView.isUserInteractionEnabled = false
        effectView.clipsToBounds = true
        effectView.layer.cornerRadius = cornerRadius
        effectView.layer.borderWidth = 0.8
        effectView.layer.borderColor = UIColor.white.withAlphaComponent(0.24).cgColor
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        // 2. Işık / Vurgu Katmanı
        highlightOverlay.isUserInteractionEnabled = false
        highlightOverlay.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        highlightOverlay.layer.cornerRadius = cornerRadius
        highlightOverlay.clipsToBounds = true
        highlightOverlay.translatesAutoresizingMaskIntoConstraints = false
        effectView.contentView.addSubview(highlightOverlay)

        // 3. İçerik (İkon + Başlık)
        iconView.isUserInteractionEnabled = false
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.isUserInteractionEnabled = false
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        contentStack.isUserInteractionEnabled = false
        contentStack.axis = .horizontal
        contentStack.spacing = 8
        contentStack.alignment = .center
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(titleLabel)
        effectView.contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            highlightOverlay.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            highlightOverlay.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            highlightOverlay.topAnchor.constraint(equalTo: effectView.topAnchor),
            highlightOverlay.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),

            contentStack.centerXAnchor.constraint(equalTo: effectView.contentView.centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: effectView.contentView.centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: effectView.contentView.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: effectView.contentView.trailingAnchor, constant: -18),

            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    open override var isHighlighted: Bool {
        didSet {
            UIView.animate(
                withDuration: isHighlighted ? 0.10 : 0.25,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
                self.highlightOverlay.backgroundColor = self.isHighlighted
                    ? UIColor.white.withAlphaComponent(0.20)
                    : UIColor.white.withAlphaComponent(0.08)
            }
        }
    }
}

/// Apple Liquid Glass Oynat Butonu
final class PlayLiquidGlassButton: LiquidGlassButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        iconView.image = UIImage(systemName: "play.fill", withConfiguration: config)
        titleLabel.text = L10n.play
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTitle(_ title: String) {
        titleLabel.text = title
    }
}

/// Apple SF Symbol `.replace.downUp` geçişli, gerçek `UIVisualEffectView` Liquid Glass İzleme Listesi butonu.
final class WatchlistLiquidGlassButton: UIControl {
    let effectView: UIVisualEffectView
    let highlightOverlay = UIView()
    let iconView = UIImageView()

    override init(frame: CGRect) {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        self.effectView = UIVisualEffectView(effect: blur)
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        self.effectView = UIVisualEffectView(effect: blur)
        super.init(coder: coder)
        build()
    }

    private func build() {
        clipsToBounds = false
        translatesAutoresizingMaskIntoConstraints = false

        effectView.isUserInteractionEnabled = false
        effectView.clipsToBounds = true
        effectView.layer.cornerRadius = 22
        effectView.layer.borderWidth = 0.8
        effectView.layer.borderColor = UIColor.white.withAlphaComponent(0.24).cgColor
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        highlightOverlay.isUserInteractionEnabled = false
        highlightOverlay.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        highlightOverlay.layer.cornerRadius = 22
        highlightOverlay.clipsToBounds = true
        highlightOverlay.translatesAutoresizingMaskIntoConstraints = false
        effectView.contentView.addSubview(highlightOverlay)

        iconView.isUserInteractionEnabled = false
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        iconView.image = UIImage(systemName: "plus", withConfiguration: config)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        effectView.contentView.addSubview(iconView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 44),
            heightAnchor.constraint(equalToConstant: 44),

            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            highlightOverlay.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            highlightOverlay.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            highlightOverlay.topAnchor.constraint(equalTo: effectView.topAnchor),
            highlightOverlay.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),

            iconView.centerXAnchor.constraint(equalTo: effectView.contentView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: effectView.contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    func setInWatchlist(_ inWatchlist: Bool, animated: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let newImage = UIImage(systemName: inWatchlist ? "checkmark" : "plus", withConfiguration: config)

        if animated {
            #if os(iOS)
            if #available(iOS 17.0, *) {
                iconView.setSymbolImage(newImage ?? UIImage(), contentTransition: .replace.downUp)
            } else {
                UIView.transition(with: iconView, duration: 0.25, options: .transitionCrossDissolve) {
                    self.iconView.image = newImage
                }
            }
            #else
            iconView.image = newImage
            #endif

            UIView.animate(withDuration: 0.10, delay: 0, options: [.curveEaseOut]) {
                self.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            } completion: { _ in
                UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8) {
                    self.transform = .identity
                    self.highlightOverlay.backgroundColor = inWatchlist
                        ? UIColor(red: 0.16, green: 0.62, blue: 1.0, alpha: 0.28)
                        : UIColor.white.withAlphaComponent(0.08)
                }
            }
        } else {
            iconView.image = newImage
            highlightOverlay.backgroundColor = inWatchlist
                ? UIColor(red: 0.16, green: 0.62, blue: 1.0, alpha: 0.28)
                : UIColor.white.withAlphaComponent(0.08)
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(
                withDuration: isHighlighted ? 0.10 : 0.25,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
            }
        }
    }
}

/// Detay ekranının üst bloğu: arka plan görseli, üzerindeki karartma/blur
/// katmanı ve içerik (logo ya da başlık, butonlar, künye satırı).
///
/// Kaydırma davranışı `DetailViewController` tarafından sürülüyor:
/// - aşağı çekildiğinde görsel üste sabitlenip büyür,
/// - yukarı kaydırıldığında içerikten yavaş hareket eder (parallax).
final class DetailHeroView: UIView {
    /// Görsel, blur katmanı ve karartma gradyanını bir arada tutan kapsayıcı.
    /// Kaydırma/esneme (stretchy header) efekti bu kapsayıcıya uygulanır;
    /// böylece resim esnerken veya kayarken gradyan daima resmin altında kalır.
    private let visualContainer = UIView()

    let artwork = RemoteImageView()

    /// TMDB'den gelen şeffaf logo. Varsa başlık yerine bu gösteriliyor.
    let logoView = UIImageView()
    let titleLabel = UILabel()
    let taglineLabel = UILabel()
    let genreLabel = UILabel()
    let plotLabel = UILabel()
    let metaLabel = UILabel()
    let moreButton = UIButton(type: .system)
    let playButton = PlayLiquidGlassButton()
    let watchlistButton = WatchlistLiquidGlassButton()

    let contentStack = UIStackView()

    /// Görselin ve blur katmanının üzerinde, butonların arkasında siyah gradient karartma.
    private let scrimView = HeroGradientView()

    /// İlk açılışta TMDB görseli yüklenene kadar gösterilen geçiş blur katmanı.
    private let loadingBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let pulseOverlay = UIView()

    private var visualTop: NSLayoutConstraint!
    private var visualHeight: NSLayoutConstraint!
    private var ownHeight: NSLayoutConstraint!

    private(set) var baseHeight: CGFloat = 660

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        // Büyüyen görsel kendi sınırlarının dışına taşacağı için kırpma kapalı.
        clipsToBounds = false

        // 1. Görsel Kapsayıcısı (Stretchy & Parallax uygulanan ana blok)
        visualContainer.translatesAutoresizingMaskIntoConstraints = false
        visualContainer.clipsToBounds = true
        addSubview(visualContainer)

        artwork.translatesAutoresizingMaskIntoConstraints = false
        artwork.clipsToBounds = true
        artwork.showsInitials = false
        visualContainer.addSubview(artwork)

        // Açılış blur ve nabız (pulse) katmanı
        loadingBlurView.translatesAutoresizingMaskIntoConstraints = false
        loadingBlurView.alpha = 1
        visualContainer.addSubview(loadingBlurView)

        pulseOverlay.translatesAutoresizingMaskIntoConstraints = false
        pulseOverlay.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        loadingBlurView.contentView.addSubview(pulseOverlay)

        // Karartma katmanı: Hem görselin hem de blur katmanının üstünde yer alır.
        // visualContainer içinde olduğu için resim esnedikçe gradyan da onunla birlikte esner.
        scrimView.translatesAutoresizingMaskIntoConstraints = false
        scrimView.isUserInteractionEnabled = false
        scrimView.colors = [
            UIColor.clear,
            UIColor.black.withAlphaComponent(0.08),
            UIColor.black.withAlphaComponent(0.35),
            UIColor.black.withAlphaComponent(0.70),
            UIColor.black.withAlphaComponent(0.92),
            UIColor.black,
        ]
        scrimView.locations = [0.0, 0.35, 0.55, 0.75, 0.90, 1.0]
        visualContainer.addSubview(scrimView)

        buildContent()

        visualTop = visualContainer.topAnchor.constraint(equalTo: topAnchor)
        visualHeight = visualContainer.heightAnchor.constraint(equalToConstant: baseHeight)
        ownHeight = heightAnchor.constraint(equalToConstant: baseHeight)

        NSLayoutConstraint.activate([
            ownHeight,
            visualTop,
            visualHeight,
            visualContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualContainer.trailingAnchor.constraint(equalTo: trailingAnchor),

            artwork.leadingAnchor.constraint(equalTo: visualContainer.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: visualContainer.trailingAnchor),
            artwork.topAnchor.constraint(equalTo: visualContainer.topAnchor),
            artwork.bottomAnchor.constraint(equalTo: visualContainer.bottomAnchor),

            loadingBlurView.leadingAnchor.constraint(equalTo: visualContainer.leadingAnchor),
            loadingBlurView.trailingAnchor.constraint(equalTo: visualContainer.trailingAnchor),
            loadingBlurView.topAnchor.constraint(equalTo: visualContainer.topAnchor),
            loadingBlurView.bottomAnchor.constraint(equalTo: visualContainer.bottomAnchor),

            pulseOverlay.leadingAnchor.constraint(equalTo: loadingBlurView.leadingAnchor),
            pulseOverlay.trailingAnchor.constraint(equalTo: loadingBlurView.trailingAnchor),
            pulseOverlay.topAnchor.constraint(equalTo: loadingBlurView.topAnchor),
            pulseOverlay.bottomAnchor.constraint(equalTo: loadingBlurView.bottomAnchor),

            scrimView.leadingAnchor.constraint(equalTo: visualContainer.leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: visualContainer.trailingAnchor),
            scrimView.topAnchor.constraint(equalTo: visualContainer.topAnchor),
            scrimView.bottomAnchor.constraint(equalTo: visualContainer.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
        ])
    }

    func startLoadingAnimation() {
        loadingBlurView.alpha = 1
        loadingBlurView.isHidden = false
        pulseOverlay.layer.removeAllAnimations()

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.2
        pulse.toValue = 0.9
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulseOverlay.layer.add(pulse, forKey: "pulse")
    }

    func stopLoadingAnimation(animated: Bool = true) {
        pulseOverlay.layer.removeAllAnimations()
        guard !loadingBlurView.isHidden, loadingBlurView.alpha > 0 else { return }
        if animated {
            UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.loadingBlurView.alpha = 0
            } completion: { _ in
                self.loadingBlurView.isHidden = true
            }
        } else {
            loadingBlurView.alpha = 0
            loadingBlurView.isHidden = true
        }
    }

    private func buildContent() {
        logoView.contentMode = .scaleAspectFit
        logoView.isHidden = true
        logoView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 3

        taglineLabel.font = .italicSystemFont(ofSize: 14)
        taglineLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        taglineLabel.textAlignment = .center
        taglineLabel.numberOfLines = 2
        taglineLabel.isHidden = true

        genreLabel.font = .systemFont(ofSize: 15)
        genreLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        genreLabel.textAlignment = .center

        let buttons = UIStackView(arrangedSubviews: [playButton, watchlistButton])
        buttons.axis = .horizontal
        buttons.spacing = 12
        buttons.alignment = .center

        plotLabel.font = .systemFont(ofSize: 15)
        plotLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        plotLabel.numberOfLines = 2
        plotLabel.textAlignment = .center

        moreButton.setTitle(L10n.more, for: .normal)
        moreButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)

        metaLabel.font = .systemFont(ofSize: 13, weight: .medium)
        metaLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        metaLabel.textAlignment = .center

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.alignment = .center
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        [logoView, titleLabel, taglineLabel, genreLabel, buttons, plotLabel, moreButton, metaLabel]
            .forEach(contentStack.addArrangedSubview)
        addSubview(contentStack)

        // Logo genişliği ekranı aşmasın, yüksekliği sınırlı kalsın.
        logoView.heightAnchor.constraint(lessThanOrEqualToConstant: 96).isActive = true
    }

    // MARK: - Kaydırma sürüşü

    func updateBaseHeight(_ height: CGFloat) {
        guard height > 0, abs(height - baseHeight) > 0.5 else { return }
        baseHeight = height
        ownHeight.constant = height
        visualHeight.constant = height
        visualTop.constant = 0
    }

    /// `offset` kaydırma konumu. Negatifse görsel kapsayıcısı (resim+blur+gradient)
    /// üste sabitlenip büyür, pozitifse içerikten yavaş hareket eder (parallax).
    ///
    /// `visualContainer`'a uygulandığı için resim, blur ve karartma gradyanı
    /// birlikte esner; resim asla gradyanın altından taşmaz.
    func apply(offset: CGFloat, parallaxFactor: CGFloat) {
        guard baseHeight > 0 else { return }

        let transform: CGAffineTransform
        if offset < 0 {
            // Merkez etrafında ölçeklerken üst kenarı `offset` konumunda tutmak
            // için gereken ek kaydırma tam olarak offset/2 oluyor.
            let scale = (baseHeight - offset) / baseHeight
            transform = CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(translationX: 0, y: offset / 2))
        } else {
            // Hero tamamen yukarı çıktıktan sonra kaydırmayı durduruyoruz;
            // aksi hâlde görsel gövdenin altından taşıp en altta sıçrama gibi
            // görünüyordu.
            transform = CGAffineTransform(translationX: 0, y: min(offset * parallaxFactor, baseHeight))
        }

        visualContainer.transform = transform
    }
}
