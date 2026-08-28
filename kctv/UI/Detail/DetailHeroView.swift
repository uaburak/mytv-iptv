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
    let playButton = UIButton(configuration: .filled())
    let favoriteButton = UIButton(configuration: .bordered())

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

        var playConfiguration = UIButton.Configuration.filled()
        playConfiguration.image = UIImage(systemName: "play.fill")
        playConfiguration.imagePadding = 8
        playConfiguration.baseBackgroundColor = .white
        playConfiguration.baseForegroundColor = .black
        playConfiguration.cornerStyle = .capsule
        playConfiguration.contentInsets = .init(top: 10, leading: 22, bottom: 10, trailing: 22)
        playButton.configuration = playConfiguration
        playButton.layer.shadowColor = UIColor.black.cgColor
        playButton.layer.shadowOpacity = 0.28
        playButton.layer.shadowRadius = 8
        playButton.layer.shadowOffset = CGSize(width: 0, height: 3)

        var favoriteConfiguration = UIButton.Configuration.filled()
        favoriteConfiguration.cornerStyle = .capsule
        favoriteConfiguration.baseForegroundColor = .white
        favoriteConfiguration.baseBackgroundColor = UIColor.white.withAlphaComponent(0.18)
        favoriteConfiguration.contentInsets = .init(top: 10, leading: 16, bottom: 10, trailing: 16)
        favoriteButton.configuration = favoriteConfiguration
        favoriteButton.layer.borderWidth = 0.8
        favoriteButton.layer.borderColor = UIColor.white.withAlphaComponent(0.24).cgColor
        favoriteButton.layer.cornerRadius = 22
        favoriteButton.clipsToBounds = true

        let buttons = UIStackView(arrangedSubviews: [playButton, favoriteButton])
        buttons.axis = .horizontal
        buttons.spacing = 14
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
