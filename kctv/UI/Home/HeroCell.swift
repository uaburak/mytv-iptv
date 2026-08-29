import UIKit

/// Anasayfanın üstündeki tam genişlikte öne çıkan içerik. Elle kaydırılabilir
/// (bölüm yatay sayfalama yapıyor), üstünde bilgi ve favori butonları var.
///
/// Görsel mantığı detay ekranıyla aynı: arka plana yalnızca gerçek yatay
/// backdrop basılıyor, TMDB'den şeffaf logo gelirse başlığın yerini alıyor.
final class HeroCell: UICollectionViewCell {
    static let reuseID = "HeroCell"

    private let artwork = HeroArtworkView()
    private let scrim = CAGradientLayer()
    /// TMDB'den gelen şeffaf logo. Varsa başlık yerine bu gösteriliyor.
    private let logoView = UIImageView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let infoButton = UIButton(configuration: .appGlass(horizontalInset: 20, fontSize: 15))
    private let favoriteButton = UIButton(configuration: .appGlass(horizontalInset: 15))

    private var item: MediaItem?
    private var isFavorite = false

    /// Hücre yeniden kullanıldığında geç gelen TMDB yanıtının yanlış içeriğin
    /// üstüne yazmasını engelleyen jeton.
    private var loadToken = UUID()

    var onDetails: ((MediaItem) -> Void)?
    var onToggleFavorite: ((MediaItem) -> Void)?

    /// Aşağı çekildiğinde görselin hücrenin üstüne doğru büyümesini sağlayan
    /// kısıt. Detay ekranındaki gibi ölçek dönüşümü kullanılmıyor: burada
    /// hücre yatay sayfalama içinde olduğu için genişleyen görsel komşu
    /// sayfaların üstüne taşardı. Çerçeveyi yukarı büyütmek hem taşmayı
    /// önlüyor hem de `scaleAspectFill` sayesinde görseli bozmuyor.
    private var artworkTop: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        // Esneyen görsel hücrenin üstüne taşıyor; kırpma kapalı.
        // Hücre ile koleksiyon arasındaki kaydırma kapsayıcısının kırpması
        // `HomeViewController` tarafından kapatılıyor.
        clipsToBounds = false
        contentView.clipsToBounds = false
        artwork.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artwork)

        scrim.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.35).cgColor,
            UIColor.black.withAlphaComponent(0.85).cgColor,
            UIColor.black.cgColor,
        ]
        scrim.locations = [0, 0.45, 0.78, 1]
        contentView.layer.addSublayer(scrim)

        logoView.contentMode = .scaleAspectFit
        logoView.isHidden = true
        logoView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        metaLabel.font = .systemFont(ofSize: 14)
        metaLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        metaLabel.textAlignment = .center

        infoButton.configuration?.title = L10n.moreInfo
        infoButton.configuration?.image = UIImage(systemName: "info.circle")
        infoButton.addSpringPressFeedback()
        infoButton.addTarget(self, action: #selector(showDetails), for: .primaryActionTriggered)

        favoriteButton.configuration?.image = UIImage(systemName: "plus")
        favoriteButton.addSpringPressFeedback(scale: 0.90)
        favoriteButton.addTarget(self, action: #selector(toggleFavorite), for: .primaryActionTriggered)

        let buttons = UIStackView(arrangedSubviews: [infoButton, favoriteButton])
        buttons.axis = .horizontal
        buttons.spacing = 10
        buttons.alignment = .center

        // Detay ekranındaki gibi iki cam buton ortak bir cam kapsayıcıda.
        let buttonsGlass = UIView.glassContainer(wrapping: buttons, spacing: 10)

        let stack = UIStackView(arrangedSubviews: [logoView, titleLabel, metaLabel, buttonsGlass])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        artworkTop = artwork.topAnchor.constraint(equalTo: contentView.topAnchor)

        NSLayoutConstraint.activate([
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            artworkTop,
            artwork.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -44),

            // Logo banner'ı ezmesin.
            logoView.heightAnchor.constraint(lessThanOrEqualToConstant: 72),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Karartma hücrenin kendi sınırlarında kalıyor: esneyen alan üstte
        // açılıyor ve gradyanın o ucu zaten saydam.
        scrim.frame = contentView.bounds
    }

    // Banner'ın kendisi odaklanmıyor; odak içindeki butonlara gitsin.
    // Aksi hâlde tüm banner tek bir odak öğesi olur ve butonlara ulaşılamaz.
    #if os(tvOS)
    override var canBecomeFocused: Bool { false }
    #endif

    /// `offset` dikey kaydırma konumu. Negatifken (aşağı çekme) görsel
    /// hücrenin üstüne doğru büyüyor; yukarı kaydırmada hiçbir şey yapmıyor.
    func applyStretch(offset: CGFloat) {
        let overshoot = max(0, -offset)
        guard abs(artworkTop.constant + overshoot) > 0.5 else { return }
        artworkTop.constant = -overshoot
        // Kaydırma her karede kısıt değiştiriyor; düzeni hemen kapatmak
        // görselin bir kare geriden gelmesini önlüyor.
        layoutIfNeeded()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Yeni jeton: uçuşta olan TMDB yanıtı bu hücreye artık yazamaz.
        loadToken = UUID()
        artwork.prepareForReuse()
        logoView.image = nil
        logoView.isHidden = true
        titleLabel.isHidden = false
    }

    func configure(item: MediaItem, metrics: AppMetrics, isFavorite: Bool) {
        // Aynı içerik yeniden kurulduğunda (dil/kütüphane değişimi) zaten
        // yerleşmiş logoyu söküp başlığa dönmek gereksiz bir titreme yaratıyor.
        let isSameItem = self.item?.id == item.id
        self.item = item
        self.isFavorite = isFavorite

        let token = UUID()
        loadToken = token

        if !isSameItem {
            logoView.image = nil
            logoView.isHidden = true
            titleLabel.isHidden = false
        }
        titleLabel.text = item.title
        titleLabel.font = metrics.titleFont

        // Afiş arka plana basılmıyor: elde yatay backdrop yoksa TMDB gelene
        // kadar koyu blur bekliyor.
        artwork.configure(
            backdropURL: item.backdropURL,
            title: item.title,
            displayWidth: metrics.heroImageWidth
        )
        if item.backdropURL == nil {
            artwork.startLoading()
        }

        var parts = [item.kind.title]
        if let genre = item.genres.first { parts.append(genre) }
        if let percent = item.ratingPercent { parts.append("%\(percent)") }
        metaLabel.text = parts.joined(separator: " · ")

        favoriteButton.configuration?.image = UIImage(systemName: isFavorite ? "checkmark" : "plus")

        guard TMDBService.isConfigured else {
            artwork.stopLoading()
            return
        }
        // `AppMetrics` içinde `UIFont` var; görev sınırından yalnızca gereken
        // sayı geçiriliyor.
        let imageWidth = metrics.heroImageWidth
        Task { [weak self] in
            let metadata = await TMDBService.shared.metadata(for: item)
            var logo: UIImage?
            if let logoURL = metadata?.logoURL {
                logo = await ImageLoader.shared.image(for: logoURL, maxPixelSize: 900)
            }
            await MainActor.run {
                self?.apply(metadata, logo: logo, for: item, imageWidth: imageWidth, token: token)
            }
        }
    }

    private func apply(
        _ metadata: TMDBMetadata?,
        logo: UIImage?,
        for item: MediaItem,
        imageWidth: CGFloat,
        token: UUID
    ) {
        // Hücre bu arada başka içeriğe geçtiyse yanıt artık geçersiz.
        guard loadToken == token else { return }

        if let backdropURL = metadata?.backdropURL {
            artwork.configure(
                backdropURL: backdropURL,
                title: item.title,
                displayWidth: imageWidth
            )
        }
        // Logo başlığın yerini alırken yığın da birlikte yerleşiyor; blokta
        // `isHidden` değiştirmek stack geçişini animasyona bağlıyor.
        if let logo, logoView.image !== logo {
            logoView.image = logo
            logoView.alpha = 0
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
                self.logoView.isHidden = false
                self.titleLabel.isHidden = true
                self.logoView.alpha = 1
                self.contentView.layoutIfNeeded()
            }
        }
        artwork.stopLoading()
    }

    @objc private func showDetails() {
        guard let item else { return }
        onDetails?(item)
    }

    @objc private func toggleFavorite() {
        guard let item else { return }
        onToggleFavorite?(item)
        isFavorite.toggle()

        Haptics.impact(.medium)

        favoriteButton.setSymbol(isFavorite ? "checkmark" : "plus")
    }
}
