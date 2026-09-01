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
    private let metaLabel = UILabel()
    private let imdbRow = UIStackView()
    private let imdbLogoView = UIImageView()
    private let imdbRatingLabel = UILabel()
    private let ageBadge = BadgeLabel()
    /// Rozet satırını sola ya da ortaya yaslayan esnek boşluklar.
    private let metaLeadingSpacer = UIView()
    private let metaTrailingSpacer = UIView()

    private let plotLabel = UILabel()

    private let infoButton = UIButton(type: .system)
    private let watchlistButton = UIButton(type: .system)
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

    /// Banner'dan aşağı inildiğinde içerik bloğunun ekstra yükselişi.
    ///
    /// Yükselen yalnızca banner'ın **içi**: başlık/logo, künye satırı,
    /// açıklama, butonlar ve sayfa göstergesi. Görsel, karartmalar ve
    /// banner alanının kendisi yerinde kalıyor — ikisi birlikte kalksaydı
    /// banner tümden yukarı kayıyormuş gibi görünürdü, oysa istenen içeriğin
    /// görselin önünden çekilmesi.
    private static let contentLiftDistance: CGFloat = 100

    /// Yükselişin tamamlandığı kaydırma yolu.
    ///
    /// Hareket bir eşiğe bağlı değil, kaydırmanın kendisine bağlı: parmak
    /// durduğunda hareket de duruyor. Eşikte tetiklenen zamanlı bir animasyon,
    /// kaydırma çoktan durmuşken kendi başına devam ettiği için yapay
    /// duruyordu — görselin alt ucunu geri çeken animasyon o yolu izleyebilir
    /// (tek seferlik bir kırpma o), yazının hareketi izleyemez.
    private static let contentLiftRamp: CGFloat = 320

    /// Yürürlükteki yükseliş. Düzen payıyla toplanıyor, onun yerine geçmiyor.
    private var contentLift: CGFloat = 0

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
    /// Banner'daki "+" butonu. Favori değil izleme listesi: kaydetmenin
    /// tek defteri o, favori yalnızca canlı kanallarda kaldı.
    var onToggleWatchlist: ((MediaItem) -> Void)?
    /// İzleme listesi durumu hücrede tutulmuyor: model tek kaynak.
    var isInWatchlist: ((MediaItem) -> Bool)?

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
            visualBottom.constant = artworkOverhang
        }
    }

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
    private var logoMaxWidth: NSLayoutConstraint!
    private var logoAspect: NSLayoutConstraint?
    private var logoLeading: NSLayoutConstraint!
    private var logoCenterX: NSLayoutConstraint!
    private var metaSpacersEqual: NSLayoutConstraint!
    private var metaRowHeight: NSLayoutConstraint!
    private var imdbLogoHeight: NSLayoutConstraint!
    private var imdbLogoAspect: NSLayoutConstraint!
    private var plotHeight: NSLayoutConstraint!
    private var indicatorBottom: NSLayoutConstraint?

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

        NSLayoutConstraint.activate([
            visual.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            visual.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            visualTop,
            visualBottom,

            columnLeading,
            columnBottom,
            columnWidth,
            textBlock.widthAnchor.constraint(equalTo: column.widthAnchor),

            // Gösterge kendi boyunda ve ekranın ortasında duruyor.
            pageIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        ])

        let bottom = pageIndicator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        indicatorBottom = bottom
        bottom.isActive = true

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
        logoMaxWidth = logoView.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        // Geniş logolarda yüksekliği kolon genişliği belirliyor; bu yüzden
        // yükseklik zorunlu değil, oran ve sağ kenar zorunlu.
        logoHeight.priority = .defaultHigh

        logoLeading = logoView.leadingAnchor.constraint(equalTo: titleSlot.leadingAnchor)
        logoCenterX = logoView.centerXAnchor.constraint(equalTo: titleSlot.centerXAnchor)

        NSLayoutConstraint.activate([
            titleSlotHeight,
            logoHeight,
            logoMaxWidth,
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

        metaLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        metaLabel.lineBreakMode = .byTruncatingTail

        imdbLogoView.contentMode = .scaleAspectFit
        imdbLogoView.image = UIImage(named: "imdb_logo") ?? Self.renderIMDbBadge()
        imdbLogoView.setContentHuggingPriority(.required, for: .horizontal)
        imdbLogoView.setContentCompressionResistancePriority(.required, for: .horizontal)

        imdbRatingLabel.textColor = AppPalette.imdbGold
        imdbRatingLabel.setContentHuggingPriority(.required, for: .horizontal)
        imdbRatingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        imdbRow.axis = .horizontal
        imdbRow.alignment = .center
        imdbRow.spacing = 6
        imdbRow.translatesAutoresizingMaskIntoConstraints = false
        [imdbLogoView, imdbRatingLabel].forEach(imdbRow.addArrangedSubview)

        imdbLogoHeight = imdbLogoView.heightAnchor.constraint(equalToConstant: 16)
        imdbLogoAspect = imdbLogoView.widthAnchor.constraint(
            equalTo: imdbLogoView.heightAnchor, multiplier: 575.0 / 290.0
        )
        NSLayoutConstraint.activate([imdbLogoHeight, imdbLogoAspect])

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
        metaRow.spacing = 10
        metaRow.translatesAutoresizingMaskIntoConstraints = false
        // Satırın içeriği kısa; kalan yeri esnek boşluklar dolduruyor.
        // Yalnızca sondaki açıkken içerik sola, ikisi birden açıkken ortaya
        // yaslanıyor.
        for spacer in [metaLeadingSpacer, metaTrailingSpacer] {
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        metaLeadingSpacer.isHidden = true
        [metaLeadingSpacer, metaLabel, imdbRow, ageBadge, metaTrailingSpacer]
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

        watchlistButton.addSpringPressFeedback(scale: 0.90)
        watchlistButton.addTarget(self, action: #selector(toggleWatchlist), for: .primaryActionTriggered)

        nextButton.addSpringPressFeedback(scale: 0.90)
        nextButton.accessibilityLabel = L10n.nextContent
        nextButton.addTarget(self, action: #selector(showNext), for: .primaryActionTriggered)

        let buttons = UIStackView(arrangedSubviews: [infoButton, watchlistButton, nextButton])
        buttons.axis = .horizontal
        buttons.spacing = 10
        buttons.alignment = .center

        // Aksiyon satırı tek bir boyu paylaşıyor: ikon-only butonlar simge
        // ölçüsünden daha kısa kalıyordu, ölçüyü bilgi butonu belirliyor.
        for button in [watchlistButton, nextButton] {
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
    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        // En sol butonda (infoButton) sola doğru gidildiğinde:
        // Eğer ilk içerikte değilsek (currentIndex > 0), önceki içeriğe geçilir ve odak butonda kalır.
        // İlk içerikteysek (currentIndex == 0), odağın sol kenara (SidebarEdgeTrigger) geçmesine izin verilir ve sidebar açılır.
        if context.previouslyFocusedView === infoButton,
           context.focusHeading == .left {
            if currentIndex > 0 {
                showPrevious()
                return false
            }
        }
        return super.shouldUpdateFocus(in: context)
    }

    /// Odak, satırın ucundan öteye gitmeye çalıştığında içerik değişiyor.
    ///
    /// Okun sağında odaklanacak bir şey yok: kumanda oraya gitmeye çalıştığında
    /// odak hareketi başarısız oluyor ve sistem bunu bildiriyor.
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
        case .right where nextButton.isFocused:
            showNext()
        case .left where infoButton.isFocused && currentIndex > 0:
            showPrevious()
        default:
            break
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
        var logoMaxWidth: CGFloat
        var metaFont: UIFont
        var badgeFont: UIFont
        var plotFont: UIFont
        var iconSize: CGFloat
        var buttonFontSize: CGFloat
        var buttonInset: CGFloat
        var buttonVerticalInset: CGFloat
        var spacing: CGFloat
        var buttonSpacing: CGFloat
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
        let indicatorInset = HeroSectionMetrics.spacing(metrics: metrics)
        #if os(tvOS)
        // tvOS'ta butonların alt kenarının banner tabanına mesafesi:
        let contentInset = max(18, (inset * 0.35).rounded())
        // Banner'ın altındaki ilk rayın (İzlemeye Devam Et) kartları, gizli başlık payı
        // (44pt) ve boşluğu (28pt) nedeniyle banner tabanından 72pt aşağıda başlar.
        let nextSectionGap = metrics.rowHeaderHeight + metrics.rowHeaderGap
        let indicatorHeight = BannerPageIndicator.preferredHeight
        // Göstergeyi butonlar ile aşağıdaki kartlar arasındaki toplam boşluğun (contentInset + nextSectionGap)
        // tam ortasına konumlandırıyoruz; böylece buton->gösterge ve gösterge->kartlar boşlukları eşitleniyor.
        let indicatorBottomConstant = ((nextSectionGap - contentInset + indicatorHeight) / 2).rounded()
        #else
        let contentInset = indicatorInset * 2 + BannerPageIndicator.preferredHeight
        let indicatorBottomConstant = -indicatorInset
        #endif

        return Layout(
            titleFont: metrics.titleFont,
            titleSlotHeight: (titleSize * 1.3).rounded(),
            logoHeight: (titleSize * 0.56).rounded(),
            logoMaxWidth: width >= 900 ? 280 : 160,
            metaFont: .systemFont(ofSize: secondary, weight: .medium),
            badgeFont: .systemFont(ofSize: max(11, secondary - 3), weight: .semibold),
            plotFont: .systemFont(ofSize: secondary),
            iconSize: (secondary * 1.1).rounded(),
            buttonFontSize: max(14, (secondary * 1.05).rounded()),
            buttonInset: max(18, (secondary * 1.1).rounded()),
            buttonVerticalInset: max(11, (secondary * 0.55).rounded()),
            spacing: max(14, (inset * 0.40).rounded()),
            buttonSpacing: max(20, (inset * 0.55).rounded()),
            horizontalInset: inset,
            contentBottomInset: contentInset,
            indicatorBottomInset: indicatorBottomConstant,
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
        logoMaxWidth.constant = layout.logoMaxWidth

        metaLabel.font = layout.metaFont
        imdbRatingLabel.font = layout.metaFont
        ageBadge.font = layout.badgeFont
        imdbLogoHeight.constant = (layout.metaFont.pointSize * 0.85).rounded()
        metaRowHeight.constant = max(layout.metaFont.lineHeight, imdbLogoHeight.constant).rounded(.up)

        plotLabel.font = layout.plotFont
        plotHeight.constant = (layout.plotFont.lineHeight * 2).rounded(.up)

        textBlock.spacing = layout.spacing
        column.spacing = layout.buttonSpacing
        columnLeading.constant = layout.horizontalInset
        applyContentLift()

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

        var watchlist = compact
        watchlist.image = UIImage(systemName: isCurrentlySaved ? "checkmark" : "plus")
        watchlistButton.configuration = watchlist

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
        // İçerik kaydırmayla birlikte görselin önünden yukarı çekiliyor.
        // Yol boyunca yumuşak: `smoothstep` hem başlangıçta hem tavana
        // otururken sertliği alıyor, doğrusal ilerleyiş yapay duruyordu.
        let progress = min(max(offset / Self.contentLiftRamp, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        let lift = eased * Self.contentLiftDistance

        if abs(visualTop.constant - top) > 0.5 || abs(contentLift - lift) > 0.5 {
            visualTop.constant = top
            contentLift = lift
            applyContentLift()
            // Kaydırma her karede kısıt değiştiriyor; düzeni hemen kapatmak
            // görselin bir kare geriden gelmesini önlüyor.
            layoutIfNeeded()
        }
    }

    /// İçerik bloğunun dikey yeri: düzenin kendi payı + kaydırma yükselişi.
    private func applyContentLift() {
        let layout = appliedLayout
        columnBottom.constant = -((layout?.contentBottomInset ?? 0) + contentLift)
        indicatorBottom?.constant = (layout?.indicatorBottomInset ?? 0) - contentLift
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
        textBlock.alpha = 1
        buttonsGlass.alpha = 1
        artwork.prepareForReuse()
    }

    // MARK: - Yapılandırma

    /// Banner'ın bütün içeriği. Liste değişmediyse ekrandaki içerik ve süre
    /// olduğu gibi kalıyor — favori değişimi banner'ı başa sarmamalı.
    func configure(items: [MediaItem], metrics: AppMetrics) {
        self.metrics = metrics
        applyLayoutIfNeeded()

        guard items != self.items else {
            guard !items.isEmpty else { return }
            // Aynı liste: içerik ve süre yerinde kalıyor ama metinler
            // yeniden yazılıyor. Dil değişimi ve izleme listesi güncellemesi
            // de buradan geçiyor.
            infoButton.configuration?.title = L10n.moreInfo
            nextButton.accessibilityLabel = L10n.nextContent
            render(animated: false)
            return
        }

        let wasPlaceholder = self.items.isEmpty
        self.items = items
        // Listeden düşen içeriklerin hazırlığı bellekte kalmasın.
        let live = Set(items.map(\.id))
        slides = slides.filter { live.contains($0.key) }
        artworks = artworks.filter { live.contains($0.key) }
        preparing = preparing.filter { live.contains($0) }

        // Seçim henüz gelmediğinde hücre yerini koruyor: sayfa banner'lı
        // açılıyor, üstünde nabız atan koyu bir zemin duruyor ve içerik
        // geldiğinde **aynı yükseklikte** yerine oturuyor. Bölümü sonradan
        // eklemek sayfayı banner boyu zıplatıyordu.
        guard !items.isEmpty else {
            showPlaceholder()
            return
        }
        hidePlaceholder(animated: wasPlaceholder)

        pageIndicator.setPages(items.count)
        // Tek içerik varken gösterge de ok da otomatik geçiş de anlamsız.
        pageIndicator.isHidden = items.count <= 1
        nextButton.isHidden = !Self.showsNextButton || items.count <= 1

        currentIndex = min(currentIndex, max(items.count - 1, 0))
        show(currentIndex, animated: false)
    }

    /// İçerik beklenirken görünen hâl: yalnızca nabız atan koyu zemin.
    private func showPlaceholder() {
        stopTimer()
        displayedBackdrop = nil
        artwork.setImage(nil)
        artwork.startLoading()
        pageIndicator.isHidden = true
        nextButton.isHidden = true
        textBlock.alpha = 0
        buttonsGlass.alpha = 0
    }

    private func hidePlaceholder(animated: Bool) {
        guard textBlock.alpha < 1 || buttonsGlass.alpha < 1 else { return }
        guard animated, window != nil else {
            textBlock.alpha = 1
            buttonsGlass.alpha = 1
            return
        }
        UIView.animate(withDuration: 0.32, delay: 0, options: [.allowUserInteraction]) {
            self.textBlock.alpha = 1
            self.buttonsGlass.alpha = 1
        }
    }

    // MARK: - İçerik geçişi

    /// Verilen içeriği gösterir. Blok yerinde kalıyor; `animated` yalnızca
    /// yazıların ve arka planın çapraz geçişini açıyor.
    private func show(_ index: Int, animated: Bool) {
        guard items.indices.contains(index) else { return }
        currentIndex = index

        // Hazırlık çizimden **önce**: önbellekte duran künye ve görsel bu
        // karede uygulanıyor, bir sonrakinde değil.
        prepare(index)
        render(animated: animated)
        pageIndicator.setCurrentPage(index)
        restartTimer()

        // Ekrandaki içerik dururken sıradaki hazırlanıyor: geçiş anında
        // görsel elde oluyor ve kare siyah açılmıyor.
        prepare((index + 1) % max(items.count, 1))
    }

    private func render(animated: Bool) {
        guard let item = currentItem else { return }
        let slide = slides[item.id]
        let images = artworks[item.id]

        let logo = images?.logo
        setLogo(logo)
        titleLabel.text = item.title
        titleLabel.isHidden = logo != nil

        metaLabel.text = Self.metaText(for: item, slide: slide)

        if let rating = item.ratingFormatted {
            imdbRatingLabel.text = rating
            imdbRow.isHidden = false
        } else {
            imdbRow.isHidden = true
        }

        let age = Self.ageBadgeText(for: item)
        ageBadge.text = age
        ageBadge.isHidden = age == nil

        plotLabel.text = Self.plotText(for: item, slide: slide)

        updateWatchlistButton(animated: animated)
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

    private var isCurrentlySaved: Bool {
        guard let currentItem, let isInWatchlist else { return false }
        return isInWatchlist(currentItem)
    }

    private func updateWatchlistButton(animated: Bool) {
        let symbol = isCurrentlySaved ? "checkmark" : "plus"
        guard animated else {
            watchlistButton.configuration?.image = UIImage(systemName: symbol)
            return
        }
        watchlistButton.setSymbol(symbol)
    }

    // MARK: - Metinler

    private static func metaText(for item: MediaItem, slide: Slide?) -> String {
        let genres = slide.map { $0.genres.isEmpty ? item.genres : $0.genres } ?? item.genres
        var parts = [item.kind.title]
        if let genre = genres.first { parts.append(genre) }
        if let year = item.yearText { parts.append(year) }
        return parts.joined(separator: " · ")
    }

    private static func renderIMDbBadge() -> UIImage {
        let size = CGSize(width: 48, height: 24)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            AppPalette.imdbGold.setFill()
            path.fill()

            let text = "IMDb"
            let font = UIFont.systemFont(ofSize: 14, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black
            ]
            let str = NSAttributedString(string: text, attributes: attrs)
            let strSize = str.size()
            let strRect = CGRect(
                x: (size.width - strSize.width) / 2,
                y: (size.height - strSize.height) / 2,
                width: strSize.width,
                height: strSize.height
            )
            str.draw(in: strRect)
        }
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

        // `AppMetrics` içinde `UIFont` var; görev sınırından yalnızca gereken
        // sayı geçiriliyor.
        let scale = window?.windowScene?.screen.scale ?? traitCollection.displayScale
        let pixelWidth = RemoteImageView.pixelSize(
            displayWidth: metrics.heroImageWidth, scale: scale
        )

        // Elde hazır olan her şey **senkron** toplanıyor. `FeaturedStore`
        // seçimi yaparken künyeyi ve görselleri ısıttığı için bu yol pratikte
        // ana yol: banner ilk karede dolu çiziliyor, tek bir bulanık kare
        // bile geçmiyor. Eskiden bu yolda da bir aktör turu vardı ve hücre
        // her açılışta önce nabız katmanını gösteriyordu.
        if let ready = known ?? Self.cachedSlide(for: item) {
            let backdrop = ready.backdropURL.flatMap {
                ImageLoader.cachedImage(url: $0, maxPixelSize: pixelWidth)
            }
            let logo = ready.logoURL.flatMap {
                ImageLoader.cachedImage(url: $0, maxPixelSize: 900)
            }
            let missesBackdrop = ready.backdropURL != nil && backdrop == nil
            let missesLogo = ready.logoURL != nil && logo == nil
            if !missesBackdrop, !missesLogo {
                store(
                    ready,
                    artwork: Artwork(backdrop: backdrop, logo: logo),
                    for: item.id,
                    notifies: false
                )
                return
            }
        }

        guard preparing.insert(item.id).inserted else { return }
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
                    overview = HeroFeatured.overview(metadata.overview, overview)
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

    /// Önbellekte hazır duran künyeden slayt kurar; ağa çıkmıyor.
    private static func cachedSlide(for item: MediaItem) -> Slide? {
        guard let metadata = TMDBService.cachedMetadata(for: item) else { return nil }
        return Slide(
            backdropURL: metadata.backdropURL ?? item.backdropURL,
            logoURL: metadata.logoURL,
            overview: HeroFeatured.overview(metadata.overview, item.plot),
            genres: metadata.genres.isEmpty ? item.genres : metadata.genres
        )
    }

    /// - Parameter notifies: senkron yolda `false`. Çizim çağıranda zaten
    ///   yapılıyor; burada ikinci kez çizmek geçiş animasyonunu boşuna
    ///   tetikliyordu.
    private func store(_ slide: Slide?, artwork: Artwork, for id: MediaID, notifies: Bool = true) {
        preparing.remove(id)
        // Hücre bu arada başka listeye geçtiyse yanıt artık geçersiz.
        guard let slide, items.contains(where: { $0.id == id }) else { return }
        slides[id] = slide
        artworks[id] = artwork
        pruneArtworks()

        guard notifies, currentItem?.id == id else { return }
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

    @objc private func toggleWatchlist() {
        guard let currentItem else { return }
        onToggleWatchlist?(currentItem)
        Haptics.impact(.medium)
        // Model değişimi bildirimle geri dönüp butonu tazeliyor; dokunmanın
        // karşılığı yine de anında görünsün.
        watchlistButton.setSymbol(isCurrentlySaved ? "checkmark" : "plus")
    }

    @objc private func showNext() {
        step(by: 1)
    }

    private func showPrevious() {
        #if os(tvOS)
        guard currentIndex > 0 else { return }
        #endif
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
final class BadgeLabel: UILabel {
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

/// Banner'a çıkacak içerikler: **en son eklenenler**.
///
/// Sağlayıcılarda "öne çıkan / editör seçkisi" diye bir veri yok (ne Xtream
/// API'sinde ne M3U'da). Elde kullanılabilir tek sinyal içeriğin listeye
/// eklenme tarihi — sıralama ondan geliyor, böylece banner kendiliğinden
/// güncel kalıyor: listeye yeni bir film/dizi düştüğünde banner'ın başına
/// geçiyor ve en eski slayt düşüyor.
///
/// Künyesi eksik hiçbir kayıt banner'a girmiyor. Üçü de şart:
/// - **geniş görsel** (`backdrop_path`) — banner afişi değil backdrop çiziyor,
///   yoksa slayt bomboş kalıyor,
/// - **logo** — yalnızca TMDB'den geliyor, sağlayıcıda karşılığı yok,
/// - **açıklama** — sağlayıcının `plot`'u ya da TMDB'nin özeti.
///
/// İlk iki koşul sağlayıcı verisinden anında bakılıyor; logo için TMDB'ye
/// çıkmak gerektiği için seçim asenkron. Aday listesi baştan kırpılıyor,
/// yoksa on binlerce kayıt için TMDB'ye çıkılırdı.
///
/// Canlı yayın banner'a hiç girmiyor: kanalın afişi değil 16:9 logosu var.
enum HeroFeatured {
    /// Banner'ın gezdirdiği içerik sayısı.
    static let limit = 8
    /// TMDB'ye sorulacak en fazla aday. Sekizi doldurmak için yeterli pay
    /// bırakıyor ama ilk açılışta ağ turunu da sınırlıyor.
    private static let candidateLimit = 48

    /// Sağlayıcı verisiyle elenmiş adaylar: en son eklenen başta.
    ///
    /// Ayrı duruyor çünkü tarama eş zamanlı ve ucuz; asıl pahalı iş bundan
    /// sonraki TMDB turu.
    /// - Parameter pools: birden çok liste ayrı ayrı geçiliyor, birleştirilip
    ///   değil: anasayfa hem filmleri hem dizileri veriyor ve iki kataloğu
    ///   toplamak on binlerce kaydı boşuna kopyalamak olurdu.
    ///
    /// Görsel/açıklama koşulu burada **aranmıyor**: çoğu panel film listesinde
    /// `backdrop_path` göndermiyor (o alan yalnızca `get_vod_info`'da) ve
    /// eksiği TMDB kapatabiliyor. Burada elense banner çoğu listede bomboş
    /// kalırdı; eleme künye çözüldükten sonra, `grade(_:)` içinde.
    static func candidates(from pools: [[MediaItem]]) -> [MediaItem] {
        // Katalog on binlerce kayıt. Hepsini toplayıp sıralamak yerine en yeni
        // `candidateLimit` tanesi tarama sırasında tutuluyor: liste dolduktan
        // sonra çoğu kayıt tek bir tarih karşılaştırmasıyla eleniyor.
        var seen = Set<MediaID>()
        var newest: [MediaItem] = []
        newest.reserveCapacity(candidateLimit)

        for pool in pools {
            for item in pool where item.kind != .live {
                let date = item.addedAt ?? .distantPast
                if newest.count == candidateLimit,
                   date <= (newest.last?.addedAt ?? .distantPast) { continue }
                // Sağlayıcı listeleri temiz değil: aynı yayın havuzda birden
                // çok kez bulunabiliyor ve banner aynı içeriği iki kez
                // gezdiriyordu. Küme sorgusu tarih elemesinden sonra: sırf
                // kimlik bakmak için on binlerce ekleme yapılmıyor.
                guard seen.insert(item.id).inserted else { continue }

                // Eşit tarihlerde katalog sırası korunuyor; liste her
                // kuruluşta aynı çıkıyor.
                let index = newest.firstIndex { ($0.addedAt ?? .distantPast) < date }
                newest.insert(item, at: index ?? newest.count)
                if newest.count > candidateLimit { newest.removeLast() }
            }
        }
        return newest
    }

    /// Banner'a çıkacak nihai liste.
    ///
    /// Şart iki kademeli: önce logosu, yatay görseli ve açıklaması olan
    /// adaylar aranıyor — banner'ın Apple TV'deki görünümü buna bağlı.
    /// Sekiz tane çıkmazsa logosu olmayan ama görseli ve açıklaması olan
    /// adaylarla tamamlanıyor: eskiden bu kademe yoktu ve logosu az olan
    /// listelerde banner ya çok geç doluyor ya hiç çıkmıyordu.
    static func items(from pool: [MediaItem]) async -> [MediaItem] {
        await items(from: [pool])
    }

    static func items(from pools: [[MediaItem]]) async -> [MediaItem] {
        // Logo yalnızca TMDB'den geliyor; anahtar yoksa şartı sağlayan hiçbir
        // içerik olamaz ve banner hiç kurulmuyor.
        guard TMDBService.isConfigured else { return [] }

        let candidates = candidates(from: pools)
        var picked: [MediaItem] = []
        var runnersUp: [MediaItem] = []
        var index = 0

        // Adaylar sırayla ama **kümeler hâlinde** yoklanıyor: tek tek beklemek
        // ilk açılışta banner'ı saniyelerce boş bırakıyordu, hepsini birden
        // sormak da sekiz içerik için otuz iki gereksiz istek demekti.
        while index < candidates.count, picked.count < limit {
            let chunk = Array(candidates.dropFirst(index).prefix(limit))
            index += chunk.count

            let graded = await withTaskGroup(
                of: (offset: Int, grade: Grade).self
            ) { group in
                for (offset, item) in chunk.enumerated() {
                    group.addTask { (offset: offset, grade: await grade(item)) }
                }
                var buffer: [(offset: Int, grade: Grade)] = []
                for await result in group { buffer.append(result) }
                // Görevler bitiş sırasına göre dönüyor; eklenme sırası korunmalı.
                return buffer.sorted { $0.offset < $1.offset }
            }

            for (offset, grade) in graded {
                switch grade {
                case .featured: picked.append(chunk[offset])
                case .usable: runnersUp.append(chunk[offset])
                case .unusable: break
                }
            }
        }

        if picked.count < limit {
            picked += runnersUp.prefix(limit - picked.count)
        }
        return Array(picked.prefix(limit))
    }

    /// Adayın banner'a uygunluğu.
    private enum Grade {
        /// Logo + yatay görsel + açıklama: aranan görünüm.
        case featured
        /// Logosuz ama görseli ve açıklaması var; yer doldurmaya yeter.
        case usable
        case unusable
    }

    private static func grade(_ item: MediaItem) async -> Grade {
        let metadata = await TMDBService.shared.metadata(for: item)
        guard (metadata?.backdropURL ?? item.backdropURL) != nil,
              overview(metadata?.overview, item.plot) != nil
        else { return .unusable }
        return metadata?.logoURL != nil ? .featured : .usable
    }

    /// İki kaynaktan ilk **dolu** açıklama.
    ///
    /// Düz `??` yetmiyor: TMDB kimi başlıkta boş dizge dönüyor ve o da bir
    /// değer sayıldığı için sağlayıcının açıklaması hiç denenmiyordu. Elemeyle
    /// gösterimin aynı sonucu vermesi için ikisi de buradan geçiyor.
    static func overview(_ primary: String?, _ fallback: String?) -> String? {
        [primary, fallback]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

/// Banner bölümünün ölçüleri.
///
/// Anasayfa ve kategori sayfası aynı banner'ı kullanıyor. Yükseklik, boşluk ve
/// taşma hesabı iki ekranda ayrı yazıldığında ikisi birbirinden kayıyordu;
/// ölçü tek yerde duruyor, iki sayfanın tepesi birebir aynı.
enum HeroSectionMetrics {
    /// Açılış ekranında sıradaki raydan görünen kadarı: başlığı, boşluğu ve
    /// kartın bir bölümü. Sayfanın devamı olduğu ilk bakışta anlaşılıyor.
    static func peek(metrics: AppMetrics) -> CGFloat {
        #if os(tvOS)
        // tvOS'ta kartların sadece üst ~%30'luk kısmı alttan hafifçe görünerek
        // ilk açılışta kartların daha aşağıda durmasını sağlar.
        return metrics.rowHeaderHeight + metrics.rowHeaderGap
            + metrics.clipCardWidth * (9.0 / 16.0) * 0.30
        #else
        return metrics.rowHeaderHeight + metrics.rowHeaderGap
            + metrics.clipCardWidth * (9.0 / 16.0) * 0.35
        #endif
    }

    /// Banner'ın alt ucundaki **eşit** boşluk: içerik bloğu → sayfa göstergesi
    /// → sıradaki bölüm. Üçünün arası aynı ve dar; gösterge kendi payını
    /// hücrenin içinde bırakıyor, bölüme ayrıca boşluk eklenmiyor — eklenseydi
    /// göstergeyle sıradaki bölüm arası içerik-gösterge arasından geniş olurdu.
    static func spacing(metrics: AppMetrics) -> CGFloat {
        max(12, (metrics.screenPadding * 0.4).rounded())
    }

    /// Banner hücresinin yüksekliği.
    ///
    /// İçerik bloğu bu hücrenin içinde duruyor; görsel ise altından taşıp
    /// ekranın dibine kadar iniyor.
    ///
    /// tvOS'ta ekranın tamamı. Telefon ve tablette detay ekranıyla aynı kural
    /// geçerli — ekranın yaklaşık %74'ü, en az 560pt — böylece iki ekranın
    /// hero'su aynı boyda duruyor; sıradaki raya ayrılan yer düşüldükten sonra
    /// kalan alan bundan küçükse o geçerli.
    static func height(container: CGSize, metrics: AppMetrics) -> CGFloat {
        guard container.width > 0, container.height > 0 else { return metrics.heroHeight }
        let visible = container.height - peek(metrics: metrics)
        #if os(tvOS)
        return max(240, visible)
        #else
        return max(240, min(visible, max(560, container.height * 0.74)))
        #endif
    }

    /// Görselin hücrenin altından taşacağı miktar: açılışta ekranın dibine
    /// kadar iniyor, ray ve aradaki boşluk onun üstünde duruyor.
    ///
    /// Yalnızca tvOS'ta. Telefonda banner sıradaki rayın altına uzanmıyor:
    /// ekran zaten dar, bindirme okumayı zorlaştırmaktan başka bir şey
    /// yapmıyor.
    static func overhang(container: CGSize, metrics: AppMetrics) -> CGFloat {
        #if os(tvOS)
        return min(
            peek(metrics: metrics),
            max(0, container.height - height(container: container, metrics: metrics))
        )
        #else
        return 0
        #endif
    }
}
