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

    /// Varsayılan dikey; tvOS'ta soldan sağa karartma için yatay kullanılıyor.
    func setDirection(start: CGPoint, end: CGPoint) {
        gradientLayer.startPoint = start
        gradientLayer.endPoint = end
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

    let artwork = HeroArtworkView()

    /// TMDB'den gelen şeffaf logo. Varsa başlık yerine bu gösteriliyor.
    let logoView = UIImageView()
    let titleLabel = UILabel()
    let taglineLabel = UILabel()
    let genreLabel = UILabel()
    let plotLabel = UILabel()
    let metaLabel = UILabel()
    let moreButton = UIButton(type: .system)
    let playButton = UIButton(configuration: .filled())
    let watchlistButton = UIButton(configuration: .filled())
    /// Favori yalnızca tvOS'ta burada; iOS'ta navigasyon çubuğunda duruyor.
    /// tvOS'ta sağ üst köşe kumandayla ulaşması zahmetli bir yer.
    let favoriteButton = UIButton(configuration: .filled())
    /// Dizilerde bölüm listesine götüren buton; yalnızca tvOS'ta ve yalnızca
    /// bölümü olan içeriklerde görünüyor.
    let episodesButton = UIButton(configuration: .filled())

    let contentStack = UIStackView()

    /// Görselin ve blur katmanının üzerinde, butonların arkasında siyah gradient karartma.
    private let scrimView = HeroGradientView()
    /// tvOS'ta içerik solda duruyor; metnin okunması için soldan sağa ikinci
    /// bir karartma gerekiyor. Alt karartma tek başına yetmiyor.
    private let sideScrimView = HeroGradientView()

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

        // Görsel + açılış blur/nabız katmanı tek bileşende; aynı mantık
        // anasayfa banner'ında da kullanılıyor.
        artwork.translatesAutoresizingMaskIntoConstraints = false
        visualContainer.addSubview(artwork)

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

        #if os(tvOS)
        sideScrimView.translatesAutoresizingMaskIntoConstraints = false
        sideScrimView.isUserInteractionEnabled = false
        sideScrimView.setDirection(start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5))
        sideScrimView.colors = [
            UIColor.black.withAlphaComponent(0.92),
            UIColor.black.withAlphaComponent(0.72),
            UIColor.black.withAlphaComponent(0.25),
            UIColor.clear,
        ]
        sideScrimView.locations = [0.0, 0.30, 0.55, 0.80]
        visualContainer.addSubview(sideScrimView)
        #endif

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

            scrimView.leadingAnchor.constraint(equalTo: visualContainer.leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: visualContainer.trailingAnchor),
            scrimView.topAnchor.constraint(equalTo: visualContainer.topAnchor),
            scrimView.bottomAnchor.constraint(equalTo: visualContainer.bottomAnchor),

        ])

        #if os(tvOS)
        NSLayoutConstraint.activate([
            sideScrimView.leadingAnchor.constraint(equalTo: visualContainer.leadingAnchor),
            sideScrimView.trailingAnchor.constraint(equalTo: visualContainer.trailingAnchor),
            sideScrimView.topAnchor.constraint(equalTo: visualContainer.topAnchor),
            sideScrimView.bottomAnchor.constraint(equalTo: visualContainer.bottomAnchor),

            // İçerik solda, ekranın yarısından biraz dar bir kolonda.
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 90),
            contentStack.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.44),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -90),
        ])
        #else
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
        ])
        #endif
    }

    func startLoadingAnimation() { artwork.startLoading() }

    func stopLoadingAnimation(animated: Bool = true) { artwork.stopLoading(animated: animated) }

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

        // Oynat butonu ikincillerden yazı kalınlığı ve genişlikle ayrışıyor;
        // malzeme ikisinde de aynı tonsuz cam.
        var playConfig = UIButton.Configuration.appGlass(horizontalInset: 24, fontSize: 16)
        playConfig.image = UIImage(systemName: "play.fill")
        playButton.configuration = playConfig
        playButton.addSpringPressFeedback()

        var watchlistConfig = UIButton.Configuration.appGlass(horizontalInset: 15)
        watchlistConfig.image = UIImage(systemName: "plus")
        watchlistButton.configuration = watchlistConfig
        watchlistButton.addSpringPressFeedback(scale: 0.90)

        var favoriteConfig = UIButton.Configuration.appGlass(horizontalInset: 15)
        favoriteConfig.image = UIImage(systemName: "heart")
        favoriteButton.configuration = favoriteConfig
        favoriteButton.addSpringPressFeedback(scale: 0.90)

        var episodesConfig = UIButton.Configuration.appGlass(horizontalInset: 22, fontSize: 16)
        episodesConfig.title = L10n.episodes
        episodesConfig.image = UIImage(systemName: "list.bullet")
        episodesButton.configuration = episodesConfig
        episodesButton.addSpringPressFeedback()
        episodesButton.isHidden = true

        #if os(tvOS)
        let buttons = UIStackView(arrangedSubviews: [
            playButton, episodesButton, watchlistButton, favoriteButton,
        ])
        #else
        let buttons = UIStackView(arrangedSubviews: [playButton, watchlistButton])
        #endif
        buttons.axis = .horizontal
        buttons.spacing = 10
        buttons.alignment = .center

        // İki cam buton ortak bir cam kapsayıcıda; birbirlerine yaklaştıklarında
        // malzeme akışkan biçimde birleşiyor.
        let buttonsGlass = UIView.glassContainer(wrapping: buttons, spacing: 10)

        plotLabel.font = .systemFont(ofSize: 15)
        plotLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        plotLabel.numberOfLines = 2
        plotLabel.textAlignment = .center

        var moreConfig = UIButton.Configuration.appGlass(
            horizontalInset: 14, verticalInset: 7, fontSize: 12
        )
        moreConfig.title = L10n.more
        moreConfig.image = UIImage(systemName: "chevron.down")
        moreConfig.imagePlacement = .trailing
        moreConfig.imagePadding = 6
        moreButton.configuration = moreConfig
        moreButton.addSpringPressFeedback(scale: 0.93)

        metaLabel.font = .systemFont(ofSize: 13, weight: .medium)
        metaLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        metaLabel.textAlignment = .center

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        #if os(tvOS)
        // Apple TV düzeni: her şey solda, açıklama butonların üstünde ve
        // "daha fazla" yok — kumandayla metin açmak anlamsız, metin kırpılıyor.
        contentStack.alignment = .leading
        contentStack.spacing = 18
        [logoView, titleLabel, genreLabel, plotLabel, metaLabel, buttonsGlass]
            .forEach(contentStack.addArrangedSubview)
        [titleLabel, taglineLabel, genreLabel, plotLabel, metaLabel].forEach {
            $0.textAlignment = .left
        }
        titleLabel.numberOfLines = 2
        plotLabel.numberOfLines = 4
        plotLabel.font = .systemFont(ofSize: 26)
        genreLabel.font = .systemFont(ofSize: 24)
        metaLabel.font = .systemFont(ofSize: 22, weight: .medium)
        logoView.contentMode = .scaleAspectFit
        moreButton.isHidden = true
        logoView.heightAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
        #else
        contentStack.alignment = .center
        [logoView, titleLabel, taglineLabel, genreLabel, buttonsGlass, plotLabel, moreButton, metaLabel]
            .forEach(contentStack.addArrangedSubview)
        // Logo genişliği ekranı aşmasın, yüksekliği sınırlı kalsın.
        logoView.heightAnchor.constraint(lessThanOrEqualToConstant: 96).isActive = true
        #endif

        addSubview(contentStack)
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
