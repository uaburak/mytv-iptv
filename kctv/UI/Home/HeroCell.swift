import UIKit

/// Anasayfanın üstündeki tam genişlikte öne çıkan içerik alanı.
///
/// Davranış Apple TV uygulamasındaki banner ile aynı: logo/başlık, rozet
/// satırı, açıklama ve butonlar **yerinde sabit** duruyor. İçerik değişince
/// blok kaymıyor, yalnızca arka plan görseli ve yazılar çapraz geçişle
/// yenileniyor. Bu yüzden banner artık içerik başına bir hücre değil —
/// bütün öne çıkanları tek hücre taşıyor, yatay sayfalama yok ve sıradaki
/// içeriği ok butonu (iOS'ta ayrıca yana kaydırma) getiriyor.
///
/// Görsel mantığı detay ekranıyla aynı: arka plana yalnızca gerçek yatay
/// backdrop basılıyor, TMDB'den şeffaf logo gelirse başlığın yerini alıyor.
final class HeroCell: UICollectionViewCell {
    static let reuseID = "HeroCell"

    /// Bir içeriğin banner'da göstereceği künye.
    ///
    /// Geçişin akıcı olması buna bağlı: görsel ağdan gelirken çapraz geçiş
    /// başlarsa yeni kare önce siyah açılıyor, resim sonra düşüyor. Sıradaki
    /// içerik ekrandaki içerik dururken hazırlanıyor ve geçiş anında elde
    /// çözülmüş görsel oluyor.
    private struct Slide {
        var backdropURL: URL?
        var logoURL: URL?
        var overview: String?
        var genres: [String]
    }

    /// Çözülmüş görseller.
    ///
    /// Künyeden ayrı duruyorlar ve yalnızca ekrandaki, bir önceki ve bir
    /// sonraki içerik için tutuluyorlar: 1920 genişliğinde bir backdrop
    /// çözülmüş hâlde ~8 MB ve sekiz öne çıkan içeriği birden bellekte tutmak
    /// tvOS'un görsel bütçesinin tamamını yiyor. Gerisi `ImageLoader`
    /// önbelleğinde duruyor, oradan beklemeden geri geliyor.
    private struct Artwork {
        var backdrop: UIImage?
        var logo: UIImage?
    }

    // MARK: - Görsel katman

    /// Görselin kırpma penceresi.
    ///
    /// Görselin kendisi hep tam boyunda duruyor; geri çekilme pencereyi
    /// daraltıyor. Görseli küçültmek `scaleAspectFill` yüzünden kadrajı
    /// kaydırıyordu — bu yolla görüntü yerinde kalıyor, yalnızca alt ucu
    /// kapanıyor. Karartmalar da görsele bağlı olduğu için onunla birlikte
    /// hareket ediyor; katman çerçevesi elle hesaplansaydı düzen turlarında
    /// bir kare geriden gelirdi.
    private let visual = UIView()
    private let artwork = HeroArtworkView()
    /// Alttan karartma: yazılar görselin üstünde okunur kalsın.
    private let scrim = HeroGradientView()
    /// Soldan karartma. Geniş ekranda içerik solda dar bir kolonda duruyor ve
    /// alt karartma tek başına metnin arkasını temizlemiyor.
    private let sideScrim = HeroGradientView()
    /// Görselin alt ucunda sayfanın siyah zeminine geçiş.
    ///
    /// Detay ekranındakiyle aynı bileşen ve aynı iş: sıradaki rayın altında
    /// kalan alan yumuşakça siyaha iniyor. Hem raylar tek renk bir zemine
    /// oturuyor hem de görsel geri çekildiğinde alt kenarı kesme izi
    /// bırakmıyor — pencerenin dibine bağlı olduğu için geçiş görselin
    /// bittiği yerde duruyor.
    private let bodyBackdrop = GradientBackdropView()

    // MARK: - İçerik

    private let column = UIStackView()
    /// Çapraz geçişin uygulandığı blok. Butonlar ve gösterge dışarıda:
    /// onlar içerikten içeriğe değişmiyor.
    private let textBlock = UIStackView()

    /// Logo ile başlık aynı yuvayı paylaşıyor. Yuvanın boyu sabit: logolu bir
    /// içerikten başlıklı bir içeriğe geçerken blok yerinden oynamıyor.
    private let titleSlot = UIView()
    private let logoView = UIImageView()
    private let titleLabel = UILabel()

    private let metaRow = UIStackView()
    private let kindIcon = UIImageView()
    private let metaLabel = UILabel()
    private let ageBadge = BadgeLabel()
    /// Rozet satırını sola ya da ortaya yaslayan esnek boşluklar.
    private let metaLeadingSpacer = UIView()
    private let metaTrailingSpacer = UIView()

    private let plotLabel = UILabel()

    private let infoButton = UIButton(type: .system)
    private let favoriteButton = UIButton(type: .system)
    /// Sıradaki içeriği getiren ok. Yalnızca tvOS'ta: telefonda yana
    /// kaydırmak ve noktalara dokunmak yeterli, buton yer kaplıyor.
    private let nextButton = UIButton(type: .system)
    private var buttonsGlass: UIView!

    private let pageIndicator = BannerPageIndicator()

    // MARK: - Durum

    private var items: [MediaItem] = []
    private var currentIndex = 0
    private var slides: [MediaID: Slide] = [:]
    private var artworks: [MediaID: Artwork] = [:]
    /// Hazırlığı süren içerikler; aynı içerik için ikinci istek açılmasın.
    private var preparing: Set<MediaID> = []
    private var metrics: AppMetrics = .regular
    private var appliedLayout: Layout?
    /// Ekrandaki görsel. Aynı resmi ikinci kez basıp gereksiz geçiş
    /// başlatmamak için tutuluyor.
    private var displayedBackdrop: UIImage?

    private var advanceTask: Task<Void, Never>?
    /// Ekran arkaya düştüğünde (detaya gidildiğinde) geçiş duruyor.
    private var isPaused = false

    /// Bir içeriğin ekranda kalma süresi; gösterge bu sürede doluyor.
    private static let dwellDuration: TimeInterval = 6
    /// Sıradaki içeriğin görseli hazır değilse geçiş bu kadar erteleniyor.
    private static let retryDelay: TimeInterval = 0.5
    private static let transitionDuration: TimeInterval = 0.45
    /// Bu kadar kaydırıldığında görselin alt ucu geri çekiliyor.
    private static let extensionThreshold: CGFloat = 8

    #if os(tvOS)
    private static let showsNextButton = true
    /// Açıklama yalnızca tvOS'ta. Telefonda banner kısa kalmalı; özet zaten
    /// bir dokunuş ötedeki detay ekranında duruyor.
    private static let showsPlot = true
    #else
    private static let showsNextButton = false
    private static let showsPlot = false
    #endif

    var onDetails: ((MediaItem) -> Void)?
    var onToggleFavorite: ((MediaItem) -> Void)?
    /// İzleme listesi durumu hücrede tutulmuyor: model tek kaynak.
    var isFavorite: ((MediaItem) -> Bool)?

    /// Görselin hücrenin altından taşacağı miktar.
    ///
    /// Açılış ekranında görsel ekranın dibine kadar iniyor: sıradaki ray ve
    /// aradaki boşluk onun üstünde duruyor, banner'ın altında siyah bant
    /// kalmıyor. Kullanıcı aşağı indiğinde taşma geri çekiliyor ve ray
    /// banner'dan ayrılıyor.
    var artworkOverhang: CGFloat = 0 {
        didSet {
            guard abs(oldValue - artworkOverhang) > 0.5 else { return }
            artworkBottom.constant = artworkOverhang
            updateArtworkExtension(animated: false)
        }
    }

    /// Görselin alt ucu şu an rayın arkasına uzanıyor mu.
    private var isArtworkExtended = true

    /// Aşağı çekildiğinde görselin hücrenin üstüne doğru büyümesini sağlayan
    /// kısıt. Detay ekranındaki gibi ölçek dönüşümü kullanılmıyor: çerçeveyi
    /// yukarı büyütmek hem taşmayı önlüyor hem de `scaleAspectFill` sayesinde
    /// görseli bozmuyor.
    private var visualTop: NSLayoutConstraint!
    private var visualBottom: NSLayoutConstraint!
    private var artworkBottom: NSLayoutConstraint!
    private var bodyBackdropHeight: NSLayoutConstraint!

    private var columnLeading: NSLayoutConstraint!
    private var columnBottom: NSLayoutConstraint!
    private var columnWidth: NSLayoutConstraint!
    private var titleSlotHeight: NSLayoutConstraint!
    private var logoHeight: NSLayoutConstraint!
    private var logoAspect: NSLayoutConstraint?
    private var logoLeading: NSLayoutConstraint!
    private var logoCenterX: NSLayoutConstraint!
    private var metaSpacersEqual: NSLayoutConstraint!
    private var metaRowHeight: NSLayoutConstraint!
    private var plotHeight: NSLayoutConstraint!
    private var indicatorBottom: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Kurulum

    private func build() {
        // Esneyen görsel hücrenin üstüne taşıyor; kırpma kapalı.
        clipsToBounds = false
        contentView.clipsToBounds = false

        visual.clipsToBounds = true
        visual.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(visual)

        artwork.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(artwork)

        // Karartma metin bloğunun hizasında en koyu, oradan aşağı doğru
        // açılıyor. Dibe kadar koyulaşsa görselin alt ucu siyah bir banda
        // dönüşüyor ve rayın banner'ın içinden çıktığı hissi kayboluyordu.
        //
        // Yoğunluk bilerek düşük: görsel karartmanın altından görünmeye devam
        // etmeli. Yazının okunmasını yan karartmayla birlikte sağlıyor.
        scrim.colors = [
            UIColor.black.withAlphaComponent(0),
            UIColor.black.withAlphaComponent(0.08),
            UIColor.black.withAlphaComponent(0.40),
            UIColor.black.withAlphaComponent(0.34),
            UIColor.black.withAlphaComponent(0.26),
        ]
        scrim.locations = [0, 0.40, 0.72, 0.88, 1]
        scrim.isUserInteractionEnabled = false
        scrim.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(scrim)

        sideScrim.setDirection(start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5))
        sideScrim.colors = [
            UIColor.black.withAlphaComponent(0.42),
            UIColor.black.withAlphaComponent(0.24),
            UIColor.black.withAlphaComponent(0.07),
            .clear,
        ]
        sideScrim.locations = [0, 0.30, 0.60, 0.88]
        sideScrim.isHidden = true
        sideScrim.isUserInteractionEnabled = false
        sideScrim.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(sideScrim)

        bodyBackdrop.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(bodyBackdrop)

        buildContent()
        buildButtons()

        column.axis = .vertical
        // Yazılar kolonun tamamını kullanıyor, buton satırı kendi boyunda
        // kalıyor: hizayı bozmadan ikisi de solda başlıyor.
        column.alignment = .leading
        column.translatesAutoresizingMaskIntoConstraints = false
        column.addArrangedSubview(textBlock)
        column.addArrangedSubview(buttonsGlass)
        contentView.addSubview(column)

        pageIndicator.translatesAutoresizingMaskIntoConstraints = false
        pageIndicator.isHidden = true
        pageIndicator.onSelectPage = { [weak self] page in
            self?.show(page, animated: true)
        }
        contentView.addSubview(pageIndicator)

        visualTop = visual.topAnchor.constraint(equalTo: contentView.topAnchor)
        visualBottom = visual.bottomAnchor.constraint(
            equalTo: contentView.bottomAnchor, constant: artworkOverhang
        )
        artworkBottom = artwork.bottomAnchor.constraint(
            equalTo: contentView.bottomAnchor, constant: artworkOverhang
        )
        columnLeading = column.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        columnBottom = column.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        columnWidth = column.widthAnchor.constraint(equalTo: contentView.widthAnchor)
        indicatorBottom = pageIndicator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)

        NSLayoutConstraint.activate([
            visual.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            visual.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            visualTop,
            visualBottom,

            columnLeading,
            columnBottom,
            columnWidth,
            textBlock.widthAnchor.constraint(equalTo: column.widthAnchor),

            // Gösterge kendi boyunda: cam kapsayıcısı yalnızca çubukları
            // sarıyor ve ekranın ortasında duruyor.
            pageIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            indicatorBottom,
        ])

        NSLayoutConstraint.activate([
            artwork.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
            artwork.topAnchor.constraint(equalTo: visual.topAnchor),
            artworkBottom,
        ])

        bodyBackdropHeight = bodyBackdrop.heightAnchor.constraint(equalToConstant: 140)
        NSLayoutConstraint.activate([
            bodyBackdrop.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
            bodyBackdrop.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
            bodyBackdrop.bottomAnchor.constraint(equalTo: visual.bottomAnchor),
            bodyBackdropHeight,
        ])

        // Karartmalar görselin üstünde ve onunla aynı çerçevede: pencere
        // daraldığında ikisi birden kırpılıyor.
        for gradient in [scrim, sideScrim] {
            NSLayoutConstraint.activate([
                gradient.leadingAnchor.constraint(equalTo: artwork.leadingAnchor),
                gradient.trailingAnchor.constraint(equalTo: artwork.trailingAnchor),
                gradient.topAnchor.constraint(equalTo: artwork.topAnchor),
                gradient.bottomAnchor.constraint(equalTo: artwork.bottomAnchor),
            ])
        }

        #if os(iOS)
        addSwipeGestures()
        #else
        observeFocusMovementFailures()
        #endif
    }

    private func buildContent() {
        logoView.contentMode = .scaleAspectFit
        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        titleSlot.translatesAutoresizingMaskIntoConstraints = false
        titleSlot.addSubview(logoView)
        titleSlot.addSubview(titleLabel)

        titleSlotHeight = titleSlot.heightAnchor.constraint(equalToConstant: 80)
        logoHeight = logoView.heightAnchor.constraint(equalToConstant: 80)
        // Geniş logolarda yüksekliği kolon genişliği belirliyor; bu yüzden
        // yükseklik zorunlu değil, oran ve sağ kenar zorunlu.
        logoHeight.priority = .defaultHigh

        logoLeading = logoView.leadingAnchor.constraint(equalTo: titleSlot.leadingAnchor)
        logoCenterX = logoView.centerXAnchor.constraint(equalTo: titleSlot.centerXAnchor)

        NSLayoutConstraint.activate([
            titleSlotHeight,
            logoHeight,
            logoLeading,
            logoView.bottomAnchor.constraint(equalTo: titleSlot.bottomAnchor),
            logoView.topAnchor.constraint(greaterThanOrEqualTo: titleSlot.topAnchor),
            logoView.leadingAnchor.constraint(greaterThanOrEqualTo: titleSlot.leadingAnchor),
            logoView.trailingAnchor.constraint(lessThanOrEqualTo: titleSlot.trailingAnchor),

            // Başlık yuvanın enini kaplıyor; sola mı ortaya mı yaslanacağını
            // yazı hizası belirliyor.
            titleLabel.leadingAnchor.constraint(equalTo: titleSlot.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: titleSlot.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: titleSlot.bottomAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: titleSlot.topAnchor),
        ])

        kindIcon.contentMode = .scaleAspectFit
        kindIcon.tintColor = UIColor.white.withAlphaComponent(0.92)
        kindIcon.setContentHuggingPriority(.required, for: .horizontal)

        metaLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        metaLabel.lineBreakMode = .byTruncatingTail

        ageBadge.textColor = UIColor.white.withAlphaComponent(0.92)
        ageBadge.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        ageBadge.layer.cornerRadius = 4
        ageBadge.layer.cornerCurve = .continuous
        ageBadge.clipsToBounds = true
        ageBadge.textAlignment = .center
        ageBadge.setContentHuggingPriority(.required, for: .horizontal)
        ageBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        metaRow.axis = .horizontal
        metaRow.alignment = .center
        metaRow.spacing = 8
        metaRow.translatesAutoresizingMaskIntoConstraints = false
        // Satırın içeriği kısa; kalan yeri esnek boşluklar dolduruyor.
        // Yalnızca sondaki açıkken içerik sola, ikisi birden açıkken ortaya
        // yaslanıyor.
        for spacer in [metaLeadingSpacer, metaTrailingSpacer] {
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        metaLeadingSpacer.isHidden = true
        [metaLeadingSpacer, kindIcon, metaLabel, ageBadge, metaTrailingSpacer]
            .forEach(metaRow.addArrangedSubview)
        metaSpacersEqual = metaLeadingSpacer.widthAnchor.constraint(
            equalTo: metaTrailingSpacer.widthAnchor
        )
        metaRowHeight = metaRow.heightAnchor.constraint(equalToConstant: 22)
        metaRowHeight.isActive = true

        plotLabel.textColor = UIColor.white.withAlphaComponent(0.80)
        plotLabel.numberOfLines = 2
        plotLabel.isHidden = !Self.showsPlot
        plotLabel.translatesAutoresizingMaskIntoConstraints = false
        // Gizliyken yükseklik kısıtı da kapalı: yığın gizli görünümü sıfıra
        // çekiyor ve zorunlu bir yükseklikle çakışıyor.
        plotHeight = plotLabel.heightAnchor.constraint(equalToConstant: 40)
        plotHeight.isActive = Self.showsPlot

        textBlock.axis = .vertical
        textBlock.alignment = .fill
        textBlock.translatesAutoresizingMaskIntoConstraints = false
        [titleSlot, metaRow, plotLabel].forEach(textBlock.addArrangedSubview)

        // Logo yuvası baştan belirli: genişlik kısıtı ilk içerikten önce de
        // duruyor.
        setLogo(nil)
    }

    private func buildButtons() {
        infoButton.addSpringPressFeedback()
        infoButton.addTarget(self, action: #selector(showDetails), for: .primaryActionTriggered)

        favoriteButton.addSpringPressFeedback(scale: 0.90)
        favoriteButton.addTarget(self, action: #selector(toggleFavorite), for: .primaryActionTriggered)

        nextButton.addSpringPressFeedback(scale: 0.90)
        nextButton.accessibilityLabel = L10n.nextContent
        nextButton.addTarget(self, action: #selector(showNext), for: .primaryActionTriggered)

        let buttons = UIStackView(arrangedSubviews: [infoButton, favoriteButton, nextButton])
        buttons.axis = .horizontal
        buttons.spacing = 10
        buttons.alignment = .center

        // Aksiyon satırı tek bir boyu paylaşıyor: ikon-only butonlar simge
        // ölçüsünden daha kısa kalıyordu, ölçüyü bilgi butonu belirliyor.
        for button in [favoriteButton, nextButton] {
            button.heightAnchor.constraint(equalTo: infoButton.heightAnchor).isActive = true
        }

        // Detay ekranındaki gibi cam butonlar ortak bir cam kapsayıcıda;
        // birbirlerine yaklaştıklarında malzeme akışkan biçimde birleşiyor.
        buttonsGlass = UIView.glassContainer(wrapping: buttons, spacing: 10)
    }

    #if os(iOS)
    /// Banner kaymıyor ama yana kaydırarak gezinmek çalışıyor; geçiş yine
    /// çapraz geçiş.
    ///
    /// Koleksiyonun kendi kaydırma hareketiyle aynı anda tanınıyor: aksi hâlde
    /// dikey kaydırma için bekleyen pan hareketi yatay kaydırmayı yutuyor ve
    /// hareket ancak arada bir tanınıyordu.
    private func addSwipeGestures() {
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let gesture = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
            gesture.direction = direction
            gesture.delegate = self
            contentView.addGestureRecognizer(gesture)
        }
    }

    /// `UIGestureRecognizerDelegate`'in metodu ama `UIView` de aynı adı
    /// taşıyor, o yüzden uzantıda değil burada ve `override` ile duruyor.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        items.count > 1
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        // Karusel alışkanlığı: içeriği sola çekince sıradaki geliyor.
        gesture.direction == .left ? showNext() : showPrevious()
    }
    #endif

    #if os(tvOS)
    /// Odak, satırın ucundan öteye gitmeye çalıştığında içerik değişiyor.
    ///
    /// Okun sağında, bilgi butonunun solunda odaklanacak bir şey yok: kumanda
    /// oraya gitmeye çalıştığında (kaydırmayla da, yön tuşuyla da) odak
    /// hareketi **başarısız** oluyor ve sistem bunu bildiriyor. Butonlar arası
    /// normal geçişlerde bildirim gelmediği için banner da değişmiyor —
    /// hareketi hücrenin kendisi yakalasaydı, odak zaten komşu butona geçmiş
    /// olduğu için ayrım yapılamıyordu.
    private func observeFocusMovementFailures() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(focusMovementDidFail),
            name: UIFocusSystem.movementDidFailNotification,
            object: nil
        )
    }

    @objc private func focusMovementDidFail(_ notification: Notification) {
        // Bildirim uygulama genelinde: banner ekranda değilken (detaya
        // gidildiğinde) başka ekranın odak hareketine karışmamalı.
        guard window != nil, !isPaused, items.count > 1 else { return }
        guard let context = notification.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey]
            as? UIFocusUpdateContext
        else { return }

        switch context.focusHeading {
        case .right where nextButton.isFocused: showNext()
        case .left where infoButton.isFocused: showPrevious()
        default: break
        }
    }
    #endif

    // MARK: - Ölçüler

    /// Banner içeriğinin ölçüleri.
    ///
    /// Hepsi sabit ve önceden belli: başlık yuvası, rozet satırı ve açıklama
    /// kaç punto yer kaplayacaksa o kadar yer tutuyor. İçerik değişirken
    /// bloğun yerinden oynamaması buna bağlı.
    private struct Layout: Equatable {
        var titleFont: UIFont
        var titleSlotHeight: CGFloat
        /// Logo yuvanın tamamını doldurmuyor: iki satırlık başlık kadar yer
        /// tutan bir yuvada logo devasa duruyordu.
        var logoHeight: CGFloat
        var metaFont: UIFont
        var badgeFont: UIFont
        var plotFont: UIFont
        var iconSize: CGFloat
        var buttonFontSize: CGFloat
        var buttonInset: CGFloat
        var buttonVerticalInset: CGFloat
        var spacing: CGFloat
        var horizontalInset: CGFloat
        var contentBottomInset: CGFloat
        var indicatorBottomInset: CGFloat
        /// Görselin alt ucundaki siyaha geçişin boyu.
        var backdropRamp: CGFloat
        /// İçerik kolonunun ekran genişliğine oranı. Dar ekranda kolon
        /// genişliğin tamamını kullanıyor.
        var columnRatio: CGFloat
        /// Dar ekranda içerik ortalı: detay ekranının telefondaki düzeni.
        var isCentered: Bool
    }

    private static func layout(metrics: AppMetrics, width: CGFloat) -> Layout {
        let titleSize = metrics.titleFont.pointSize
        // İkincil yazılar başlıkla birlikte büyüyor: tvOS'ta 10 feet mesafede
        // okunur, iPhone'da kompakt kalıyor.
        let secondary = max(13, (titleSize * 0.42).rounded())
        let inset = metrics.screenPadding
        // Geniş ekranda metin bütün eni kaplamıyor: detay ekranındaki kolonla
        // aynı oran, açıklama satırı okunur uzunlukta kalıyor.
        let ratio: CGFloat = width >= 900 ? 0.44 : 1
        // İçeriğin alt boşluğu göstergeden türetiliyor: sabit bir değerde
        // iPhone'da buton satırı noktaların üstüne oturuyordu.
        let indicatorInset = max(12, (inset * 0.75).rounded())
        let contentInset = indicatorInset + BannerPageIndicator.preferredHeight
            + max(16, (inset * 0.6).rounded())

        return Layout(
            titleFont: metrics.titleFont,
            titleSlotHeight: (titleSize * 2.4).rounded(),
            logoHeight: (titleSize * 1.45).rounded(),
            metaFont: .systemFont(ofSize: secondary, weight: .medium),
            badgeFont: .systemFont(ofSize: max(11, secondary - 3), weight: .semibold),
            plotFont: .systemFont(ofSize: secondary),
            iconSize: (secondary * 1.1).rounded(),
            buttonFontSize: max(14, (secondary * 1.05).rounded()),
            buttonInset: max(18, (secondary * 1.1).rounded()),
            buttonVerticalInset: max(11, (secondary * 0.55).rounded()),
            spacing: max(10, (inset * 0.3).rounded()),
            horizontalInset: inset,
            contentBottomInset: contentInset,
            indicatorBottomInset: indicatorInset,
            backdropRamp: max(140, (metrics.rowSpacing * 2.5).rounded()),
            columnRatio: ratio,
            isCentered: ratio >= 1
        )
    }

    private func applyLayoutIfNeeded() {
        let width = contentView.bounds.width
        guard width > 0 else { return }
        let layout = Self.layout(metrics: metrics, width: width)
        guard layout != appliedLayout else { return }
        appliedLayout = layout

        titleLabel.font = layout.titleFont
        titleSlotHeight.constant = layout.titleSlotHeight
        logoHeight.constant = layout.logoHeight

        metaLabel.font = layout.metaFont
        ageBadge.font = layout.badgeFont
        kindIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: layout.iconSize, weight: .semibold
        )
        metaRowHeight.constant = max(layout.metaFont.lineHeight, layout.iconSize * 1.3).rounded(.up)

        plotLabel.font = layout.plotFont
        plotHeight.constant = (layout.plotFont.lineHeight * 2).rounded(.up)

        textBlock.spacing = layout.spacing
        column.spacing = layout.spacing * 1.4
        columnLeading.constant = layout.horizontalInset
        columnBottom.constant = -layout.contentBottomInset
        indicatorBottom.constant = -layout.indicatorBottomInset

        // Çarpan sonradan değiştirilemiyor; kısıt yeniden kuruluyor.
        columnWidth.isActive = false
        columnWidth = column.widthAnchor.constraint(
            equalTo: contentView.widthAnchor,
            multiplier: layout.columnRatio,
            constant: layout.columnRatio < 1 ? 0 : -layout.horizontalInset * 2
        )
        columnWidth.isActive = true

        bodyBackdrop.rampHeight = layout.backdropRamp
        bodyBackdropHeight.constant = layout.backdropRamp

        sideScrim.isHidden = layout.isCentered

        // Dar ekranda blok ortalı duruyor — detay ekranının telefondaki
        // düzeninin aynısı. Geniş ekranda solda dar bir kolon.
        let alignment: NSTextAlignment = layout.isCentered ? .center : .natural
        column.alignment = layout.isCentered ? .center : .leading
        titleLabel.textAlignment = alignment
        metaLabel.textAlignment = alignment
        plotLabel.textAlignment = alignment
        metaLeadingSpacer.isHidden = !layout.isCentered
        metaSpacersEqual.isActive = layout.isCentered
        logoLeading.isActive = !layout.isCentered
        logoCenterX.isActive = layout.isCentered

        styleButtons(layout)
    }

    /// Cam butonların ölçüsü de ekranla birlikte büyüyor. Konfigürasyon
    /// baştan kurulduğu için başlık ve simge her seferinde yeniden yazılıyor.
    private func styleButtons(_ layout: Layout) {
        // Telefonda ana aksiyon dolu beyaz: cam buton görselin üstünde
        // siliniyor ve ikincillerden ayırt edilemiyor. Detay ekranındaki
        // oynat butonuyla aynı kural.
        #if os(tvOS)
        var info = UIButton.Configuration.appGlass(
            horizontalInset: layout.buttonInset * 1.3,
            verticalInset: layout.buttonVerticalInset,
            fontSize: layout.buttonFontSize
        )
        #else
        var info = UIButton.Configuration.appProminent(
            horizontalInset: layout.buttonInset * 1.3,
            verticalInset: layout.buttonVerticalInset,
            fontSize: layout.buttonFontSize
        )
        #endif
        info.title = L10n.moreInfo
        info.image = UIImage(systemName: "info.circle")
        infoButton.configuration = info

        let compact = UIButton.Configuration.appGlass(
            horizontalInset: layout.buttonInset,
            verticalInset: layout.buttonVerticalInset,
            fontSize: layout.buttonFontSize
        )

        var favorite = compact
        favorite.image = UIImage(systemName: isCurrentFavorite ? "checkmark" : "plus")
        favoriteButton.configuration = favorite

        var next = compact
        next.image = UIImage(systemName: "chevron.right")
        nextButton.configuration = next
    }

    /// Banner komşu hücrelerin **altında** çiziliyor: sıradaki rayın kartları
    /// görselin üstüne biniyor.
    ///
    /// Koleksiyon her düzen turunda z sırasını düzen özniteliğinden yazdığı
    /// için kurulumda bir kez ayarlamak yetmiyor.
    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        layer.zPosition = -1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyLayoutIfNeeded()
    }

    // Banner'ın kendisi odaklanmıyor; odak içindeki butonlara gitsin.
    // Aksi hâlde tüm banner tek bir odak öğesi olur ve butonlara ulaşılamaz.
    #if os(tvOS)
    override var canBecomeFocused: Bool { false }
    #endif

    /// Görseli dikey kaydırma konumuna bağlar.
    ///
    /// Aşağı çekme (negatif konum) birebir takip ediliyor: parmağın altındaki
    /// görsel gecikmemeli.
    ///
    /// Geri çekilme telefonda kendiliğinden devre dışı: orada görsel sıradaki
    /// rayın altına uzanmadığı için geri çekilecek bir şey de yok. Aşağı
    /// çekme efekti her iki platformda da çalışıyor.
    func applyScroll(offset: CGFloat) {
        let top = -max(0, -offset)
        if abs(visualTop.constant - top) > 0.5 {
            visualTop.constant = top
            // Kaydırma her karede kısıt değiştiriyor; düzeni hemen kapatmak
            // görselin bir kare geriden gelmesini önlüyor.
            layoutIfNeeded()
        }
        setArtworkExtended(offset < Self.extensionThreshold)
    }

    /// Görselin alt ucu yalnızca sayfa en üstteyken rayın arkasına uzanıyor.
    ///
    /// Uzunluk kaydırma konumunu **takip etmiyor**, eşik geçilince tek seferde
    /// yumuşakça çekiliyor. Her karede kısıt değiştirmek kaydırma
    /// animasyonunun ritmini bozuyor ve aşağı inerken takılma hissi veriyordu;
    /// böyle geçiş kendi eğrisiyle akıp odak animasyonuyla birlikte bitiyor.
    private func setArtworkExtended(_ extended: Bool) {
        guard extended != isArtworkExtended else { return }
        isArtworkExtended = extended
        updateArtworkExtension(animated: window != nil)
    }

    private func updateArtworkExtension(animated: Bool) {
        let target = isArtworkExtended ? artworkOverhang : 0
        guard abs(visualBottom.constant - target) > 0.5 else { return }
        visualBottom.constant = target
        guard animated else {
            layoutIfNeeded()
            return
        }
        UIView.animate(
            withDuration: 0.45,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]
        ) {
            self.layoutIfNeeded()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopTimer()
        items = []
        slides = [:]
        artworks = [:]
        preparing = []
        currentIndex = 0
        displayedBackdrop = nil
        artwork.prepareForReuse()
    }

    // MARK: - Yapılandırma

    /// Banner'ın bütün içeriği. Liste değişmediyse ekrandaki içerik ve süre
    /// olduğu gibi kalıyor — favori değişimi banner'ı başa sarmamalı.
    func configure(items: [MediaItem], metrics: AppMetrics) {
        self.metrics = metrics
        applyLayoutIfNeeded()

        guard items != self.items else {
            // Aynı liste: içerik ve süre yerinde kalıyor ama metinler
            // yeniden yazılıyor. Dil değişimi ve izleme listesi güncellemesi
            // de buradan geçiyor.
            infoButton.configuration?.title = L10n.moreInfo
            nextButton.accessibilityLabel = L10n.nextContent
            render(animated: false)
            return
        }

        self.items = items
        // Listeden düşen içeriklerin hazırlığı bellekte kalmasın.
        let live = Set(items.map(\.id))
        slides = slides.filter { live.contains($0.key) }
        artworks = artworks.filter { live.contains($0.key) }
        preparing = preparing.filter { live.contains($0) }

        pageIndicator.setPages(items.count)
        // Tek içerik varken gösterge de ok da otomatik geçiş de anlamsız.
        pageIndicator.isHidden = items.count <= 1
        nextButton.isHidden = !Self.showsNextButton || items.count <= 1

        currentIndex = min(currentIndex, max(items.count - 1, 0))
        show(currentIndex, animated: false)
    }

    // MARK: - İçerik geçişi

    /// Verilen içeriği gösterir. Blok yerinde kalıyor; `animated` yalnızca
    /// yazıların ve arka planın çapraz geçişini açıyor.
    private func show(_ index: Int, animated: Bool) {
        guard items.indices.contains(index) else { return }
        currentIndex = index

        render(animated: animated)
        pageIndicator.setCurrentPage(index)
        restartTimer()

        // Ekrandaki içerik dururken sıradaki hazırlanıyor: geçiş anında
        // görsel elde oluyor ve kare siyah açılmıyor.
        prepare(index)
        prepare((index + 1) % max(items.count, 1))
    }

    private func render(animated: Bool) {
        guard let item = currentItem else { return }
        let slide = slides[item.id]
        let images = artworks[item.id]

        let apply = { [self] in
            let logo = images?.logo
            setLogo(logo)
            titleLabel.text = item.title
            titleLabel.isHidden = logo != nil

            kindIcon.image = UIImage(systemName: item.kind.symbol)
            metaLabel.text = Self.metaText(for: item, slide: slide)

            let age = Self.ageBadgeText(for: item)
            ageBadge.text = age
            ageBadge.isHidden = age == nil

            plotLabel.text = Self.plotText(for: item, slide: slide)
        }

        if animated, window != nil {
            UIView.transition(
                with: textBlock,
                duration: Self.transitionDuration,
                options: [.transitionCrossDissolve, .allowUserInteraction]
            ) {
                // Değişim animasyonsuz uygulanıyor, geçişi yalnızca çapraz
                // erime veriyor.
                //
                // Aksi hâlde blok bir animasyon bağlamının içinde olduğu için
                // düzen değişimi de animasyona giriyor: her içeriğin logosu
                // farklı oranda olduğundan logo bir öncekinin çerçevesinden
                // yenisininkine doğru kayarak/büyüyerek geliyordu.
                UIView.performWithoutAnimation {
                    apply()
                    self.textBlock.layoutIfNeeded()
                }
            }
        } else {
            apply()
        }

        updateFavoriteButton(animated: animated)
        renderBackdrop(images?.backdrop, animated: animated)
    }

    /// Logoyu yuvaya sola dayalı yerleştirir.
    ///
    /// Genişliği görselin kendi oranı belirliyor: yuvanın tamamını kaplayan
    /// bir görünüm içinde `scaleAspectFit` logoyu ortalıyor ve sola dayalı
    /// kolonda havada duruyordu. Logo yokken de bir genişlik kısıtı kalıyor,
    /// yoksa görünümün eni belirsiz.
    private func setLogo(_ logo: UIImage?) {
        logoView.isHidden = logo == nil
        logoView.image = logo

        logoAspect?.isActive = false
        if let logo, logo.size.height > 0 {
            logoAspect = logoView.widthAnchor.constraint(
                equalTo: logoView.heightAnchor,
                multiplier: logo.size.width / logo.size.height
            )
        } else {
            logoAspect = logoView.widthAnchor.constraint(equalToConstant: 0)
        }
        logoAspect?.isActive = true
    }

    private func renderBackdrop(_ image: UIImage?, animated: Bool) {
        guard let image else {
            // Görsel henüz gelmediyse ekranda ne varsa duruyor; ilk açılışta
            // ise zemin boş olduğu için bekleme katmanı görünüyor.
            if displayedBackdrop == nil { artwork.startLoading() }
            return
        }
        guard image !== displayedBackdrop else {
            artwork.stopLoading()
            return
        }
        displayedBackdrop = image

        guard animated, window != nil else {
            artwork.setImage(image)
            artwork.stopLoading(animated: false)
            return
        }
        UIView.transition(
            with: artwork,
            duration: Self.transitionDuration,
            options: [.transitionCrossDissolve, .allowUserInteraction]
        ) {
            self.artwork.setImage(image)
            // Bekleme katmanı geçişin içinde kapanıyor: yoksa yeni kare
            // bulanığın altında açılıp sonra berraklaşıyor.
            self.artwork.stopLoading(animated: false)
        }
    }

    private var currentItem: MediaItem? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    private var isCurrentFavorite: Bool {
        guard let currentItem, let isFavorite else { return false }
        return isFavorite(currentItem)
    }

    private func updateFavoriteButton(animated: Bool) {
        let symbol = isCurrentFavorite ? "checkmark" : "plus"
        guard animated else {
            favoriteButton.configuration?.image = UIImage(systemName: symbol)
            return
        }
        favoriteButton.setSymbol(symbol)
    }

    // MARK: - Metinler

    private static func metaText(for item: MediaItem, slide: Slide?) -> String {
        let genres = slide.map { $0.genres.isEmpty ? item.genres : $0.genres } ?? item.genres
        var parts = [item.kind.title]
        if let genre = genres.first { parts.append(genre) }
        if let year = item.yearText { parts.append(year) }
        if let percent = item.ratingPercent { parts.append("%\(percent)") }
        return parts.joined(separator: " · ")
    }

    /// Açıklama iki satıra sığdığı için satır sonları boşluğa çevriliyor:
    /// sağlayıcı metinleri sık sık satır başıyla geliyor ve ikinci satır
    /// yarım kalıyordu.
    private static func plotText(for item: MediaItem, slide: Slide?) -> String? {
        let raw = slide?.overview ?? item.plot
        guard let raw else { return nil }
        let text = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Yaş rozeti. Sağlayıcı sınıflandırma vermiyor; elde yalnızca yetişkin
    /// işareti var, o yüzden başka bir değer uydurulmuyor.
    private static func ageBadgeText(for item: MediaItem) -> String? {
        item.isAdult ? "18+" : nil
    }

    // MARK: - Hazırlık

    private func isPrepared(_ index: Int) -> Bool {
        guard items.indices.contains(index) else { return false }
        let id = items[index].id
        return slides[id] != nil && artworks[id] != nil
    }

    /// İçeriğin künyesini ve görsellerini önceden çözer.
    ///
    /// Künye saklanıyor: banner başa döndüğünde TMDB'ye yeniden çıkılmıyor.
    /// Görsel ise yalnızca yakın içerikler için tutuluyor, uzaklaşınca
    /// bırakılıyor ve geri dönüldüğünde `ImageLoader` önbelleğinden bir kare
    /// içinde geliyor.
    private func prepare(_ index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        let known = slides[item.id]
        guard known == nil || artworks[item.id] == nil else { return }
        guard preparing.insert(item.id).inserted else { return }

        // `AppMetrics` içinde `UIFont` var; görev sınırından yalnızca gereken
        // sayı geçiriliyor.
        let scale = window?.windowScene?.screen.scale ?? traitCollection.displayScale
        let pixelWidth = RemoteImageView.pixelSize(
            displayWidth: metrics.heroImageWidth, scale: scale
        )
        let usesTMDB = TMDBService.isConfigured

        Task { [weak self] in
            var slide = known
            if slide == nil {
                var backdropURL = item.backdropURL
                var logoURL: URL?
                var overview = item.plot
                var genres = item.genres

                if usesTMDB, let metadata = await TMDBService.shared.metadata(for: item) {
                    backdropURL = metadata.backdropURL ?? backdropURL
                    logoURL = metadata.logoURL
                    overview = metadata.overview ?? overview
                    if !metadata.genres.isEmpty { genres = metadata.genres }
                }
                slide = Slide(
                    backdropURL: backdropURL, logoURL: logoURL,
                    overview: overview, genres: genres
                )
            }

            var artwork = Artwork()
            if let backdropURL = slide?.backdropURL {
                artwork.backdrop = await ImageLoader.shared.image(
                    for: backdropURL, maxPixelSize: pixelWidth
                )
            }
            if let logoURL = slide?.logoURL {
                artwork.logo = await ImageLoader.shared.image(for: logoURL, maxPixelSize: 900)
            }

            let resolved = slide
            await MainActor.run {
                self?.store(resolved, artwork: artwork, for: item.id)
            }
        }
    }

    private func store(_ slide: Slide?, artwork: Artwork, for id: MediaID) {
        preparing.remove(id)
        // Hücre bu arada başka listeye geçtiyse yanıt artık geçersiz.
        guard let slide, items.contains(where: { $0.id == id }) else { return }
        slides[id] = slide
        artworks[id] = artwork
        pruneArtworks()

        guard currentItem?.id == id else { return }
        // Ekrandaki içeriğin künyesi geç geldi: yazılar ve görsel yumuşakça
        // yerine otursun.
        render(animated: true)
    }

    /// Ekrandaki, bir önceki ve bir sonraki dışındaki görselleri bırakır.
    private func pruneArtworks() {
        guard items.count > 3 else { return }
        let count = items.count
        let nearby = Set(
            [currentIndex, (currentIndex + 1) % count, (currentIndex - 1 + count) % count]
                .map { items[$0].id }
        )
        artworks = artworks.filter { nearby.contains($0.key) }
    }

    // MARK: - Otomatik geçiş

    /// Ekran arkaya düştüğünde (detaya gidildiğinde) geçiş duruyor.
    func pauseAutoAdvance() {
        isPaused = true
        stopTimer()
    }

    func resumeAutoAdvance() {
        isPaused = false
        restartTimer()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        window == nil ? stopTimer() : restartTimer()
    }

    private func restartTimer() {
        scheduleAdvance(after: Self.dwellDuration, showsProgress: true)
    }

    private func scheduleAdvance(after delay: TimeInterval, showsProgress: Bool) {
        stopTimer(resetsProgress: showsProgress)
        guard items.count > 1, !isPaused, window != nil else { return }

        if showsProgress { pageIndicator.startProgress(duration: delay) }
        advanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    private func stopTimer(resetsProgress: Bool = true) {
        advanceTask?.cancel()
        advanceTask = nil
        if resetsProgress { pageIndicator.stopProgress() }
    }

    private func advance() {
        guard items.count > 1 else { return }
        let next = (currentIndex + 1) % items.count
        // Sıradaki görsel henüz hazır değilse geçiş erteleniyor: yarım kalmış
        // bir geçiş, biraz beklemekten daha kötü görünüyor.
        guard isPrepared(next) else {
            prepare(next)
            scheduleAdvance(after: Self.retryDelay, showsProgress: false)
            return
        }
        show(next, animated: true)
    }

    // MARK: - Aksiyonlar

    @objc private func showDetails() {
        guard let currentItem else { return }
        onDetails?(currentItem)
    }

    @objc private func toggleFavorite() {
        guard let currentItem else { return }
        onToggleFavorite?(currentItem)
        Haptics.impact(.medium)
        // Model değişimi bildirimle geri dönüp butonu tazeliyor; dokunmanın
        // karşılığı yine de anında görünsün.
        favoriteButton.setSymbol(isCurrentFavorite ? "checkmark" : "plus")
    }

    @objc private func showNext() {
        step(by: 1)
    }

    private func showPrevious() {
        step(by: -1)
    }

    /// Kullanıcının kendi başlattığı içerik değişimi.
    ///
    /// Kendiliğinden geçiş buradan geçmiyor: geri bildirim yalnızca kumandaya
    /// ya da parmağa cevap veriyor, altı saniyede bir kendi kendine ses
    /// çıkarmıyor.
    private func step(by offset: Int) {
        guard items.count > 1 else { return }
        Haptics.impact(.light)
        RemoteFeedback.focusChange()
        show((currentIndex + offset + items.count) % items.count, animated: true)
    }
}

#if os(iOS)
extension HeroCell: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif

/// Yaş sınırı gibi kısa rozetler için kenar payı olan etiket.
private final class BadgeLabel: UILabel {
    private let insets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }
}
