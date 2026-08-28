import UIKit

/// Detay ekranının üst bloğu: arka plan görseli, üzerindeki karartma/blur
/// katmanı ve içerik (logo ya da başlık, butonlar, künye satırı).
///
/// Kaydırma davranışı `DetailViewController` tarafından sürülüyor:
/// - aşağı çekildiğinde görsel üste sabitlenip büyür,
/// - yukarı kaydırıldığında içerikten yavaş hareket eder (parallax).
final class DetailHeroView: UIView {
    let artwork = RemoteImageView()

    /// TMDB'den gelen şeffaf logo. Varsa başlık yerine bu gösteriliyor.
    let logoView = UIImageView()
    let titleLabel = UILabel()
    let genreLabel = UILabel()
    let plotLabel = UILabel()
    let metaLabel = UILabel()
    let moreButton = UIButton(type: .system)
    let playButton = UIButton(configuration: .filled())
    let favoriteButton = UIButton(configuration: .bordered())

    let contentStack = UIStackView()

    /// Görselin altından üstüne doğru siyah gradient (karartma).
    private let scrim = CAGradientLayer()

    /// İlk açılışta TMDB görseli yüklenene kadar gösterilen geçiş blur katmanı.
    private let loadingBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))

    private var artworkTop: NSLayoutConstraint!
    private var artworkHeight: NSLayoutConstraint!
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

        artwork.translatesAutoresizingMaskIntoConstraints = false
        artwork.clipsToBounds = true
        // Görsel gelene kadar harf değil, sade koyu bir zemin dursun.
        artwork.showsInitials = false
        addSubview(artwork)

        // Resmin altından üstüne doğru kademeli siyah gradient
        scrim.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.08).cgColor,
            UIColor.black.withAlphaComponent(0.35).cgColor,
            UIColor.black.withAlphaComponent(0.72).cgColor,
            UIColor.black.withAlphaComponent(0.94).cgColor,
            UIColor.black.cgColor,
        ]
        scrim.locations = [0.0, 0.35, 0.55, 0.75, 0.90, 1.0]
        artwork.layer.addSublayer(scrim)

        // Açılış blur katmanı
        loadingBlurView.translatesAutoresizingMaskIntoConstraints = false
        loadingBlurView.alpha = 1
        artwork.addSubview(loadingBlurView)

        buildContent()

        artworkTop = artwork.topAnchor.constraint(equalTo: topAnchor)
        artworkHeight = artwork.heightAnchor.constraint(equalToConstant: baseHeight)
        ownHeight = heightAnchor.constraint(equalToConstant: baseHeight)

        NSLayoutConstraint.activate([
            ownHeight,
            artworkTop,
            artworkHeight,
            artwork.leadingAnchor.constraint(equalTo: leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: trailingAnchor),

            loadingBlurView.leadingAnchor.constraint(equalTo: artwork.leadingAnchor),
            loadingBlurView.trailingAnchor.constraint(equalTo: artwork.trailingAnchor),
            loadingBlurView.topAnchor.constraint(equalTo: artwork.topAnchor),
            loadingBlurView.bottomAnchor.constraint(equalTo: artwork.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
        ])
    }

    func showLoadingBlur() {
        loadingBlurView.alpha = 1
        loadingBlurView.isHidden = false
    }

    func hideLoadingBlur(animated: Bool = true) {
        guard !loadingBlurView.isHidden, loadingBlurView.alpha > 0 else { return }
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
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

        genreLabel.font = .systemFont(ofSize: 15)
        genreLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        genreLabel.textAlignment = .center

        var playConfiguration = UIButton.Configuration.filled()
        playConfiguration.image = UIImage(systemName: "play.fill")
        playConfiguration.imagePadding = 6
        playConfiguration.baseBackgroundColor = .white
        playConfiguration.baseForegroundColor = .black
        playConfiguration.cornerStyle = .capsule
        playButton.configuration = playConfiguration

        var favoriteConfiguration = UIButton.Configuration.bordered()
        favoriteConfiguration.cornerStyle = .capsule
        favoriteConfiguration.baseForegroundColor = .white
        favoriteButton.configuration = favoriteConfiguration

        let buttons = UIStackView(arrangedSubviews: [playButton, favoriteButton])
        buttons.axis = .horizontal
        buttons.spacing = 14

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
        [logoView, titleLabel, genreLabel, buttons, plotLabel, moreButton, metaLabel]
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
        artworkHeight.constant = height
        artworkTop.constant = 0
    }

    /// `offset` kaydırma konumu. Negatifse görsel sabitlenip büyür, pozitifse
    /// içerikten yavaş hareket eder.
    ///
    /// Kısıt güncelleyip her karede `layoutIfNeeded()` çağırmak yerine
    /// `transform` kullanıyoruz: düzen geçişi tetiklenmediği için blur katmanı
    /// kare başına yeniden kurulmuyor. (`glassEffect() tried to update multiple
    /// times per frame` uyarısının kaynağı buydu.)
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

        artwork.transform = transform
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutLayers()
    }

    /// Katman çerçevelerini örtük animasyon olmadan günceller; aksi hâlde
    /// görsel esnerken karartma bir kare geriden geliyor.
    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrim.frame = artwork.bounds
        CATransaction.commit()
    }
}
