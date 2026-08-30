import AVFoundation
import KSPlayer
import UIKit

#if os(tvOS)
/// `UISlider` tvOS'ta yok — orada tutamacı parmakla sürükleme diye bir
/// etkileşim de yok. Sarma şöyle işliyor:
///
/// - Çubuk **odağa gelince** bulunulan yerde bir tutamaç beliriyor. Tıklamak
///   gerekmiyor ve görüntü akmaya devam ediyor; kullanıcı yalnızca gezinmiş
///   olabilir.
/// - **Sağ/sol tuşu ya da dokunmatik yüzeyde yatay kaydırma** tutamacı
///   gezdirmeye başlıyor. O anda görüntü duruyor: nereye gidileceğini durağan
///   bir karede seçmek daha kolay.
/// - **Tıklama** oraya atlayıp oynatmayı sürdürüyor, **Menu** vazgeçiyor.
///
/// `UIControl` türetiliyor ve `UISlider`'ın kullanılan yüzeyini birebir
/// karşılıyor; böylece ortak oynatıcı kodu iki platformda da aynı kalıyor.
/// Konumu saniyeye çeviren taraf oynatıcı — süre ve hızlanma orada.
final class PlaybackSlider: UIControl {
    var minimumValue: Float = 0
    var maximumValue: Float = 1

    var value: Float = 0 {
        didSet {
            updateProgress()
            setNeedsLayout()
        }
    }

    var minimumTrackTintColor: UIColor? {
        get { progressView.progressTintColor }
        set { progressView.progressTintColor = newValue }
    }

    var maximumTrackTintColor: UIColor? {
        get { progressView.trackTintColor }
        set { progressView.trackTintColor = newValue }
    }

    /// Sarma başladı: oynatıcı görüntüyü durdurup hedefi bulunulan ana
    /// sabitliyor.
    var onScrubBegin: (() -> Void)?
    /// Sağ/sol tuşu: yön olarak -1 ya da +1.
    var onScrubStep: ((Int) -> Void)?
    /// Dokunmatik yüzeyde kaydırma: 0...1 aralığında doğrudan konum.
    var onScrubFraction: ((Float) -> Void)?
    /// Tıklama: hedefe atla.
    var onScrubCommit: (() -> Void)?
    /// Menu ya da odağın kaçması: vazgeç, bulunulan yerde kal.
    var onScrubCancel: (() -> Void)?

    /// Tutamaç gezdirilmeye başlandı mı. Odakta olmak yetmiyor: yalnızca
    /// gezinen kullanıcının görüntüsü durmamalı.
    private(set) var isScrubbingActive = false

    private static let handleSize: CGFloat = 30

    /// Dokunmatik yüzeyin sarma hızı. Sağ/sol tuşundan hızlı olmalı ama
    /// birebir eşleme çok sertti: parmağın küçük bir hareketi dakikaları
    /// atlıyordu. Bu değerle yüzeyi baştan sona kaydırmak filmin yaklaşık
    /// üçte birini geçiyor.
    private static let panSensitivity: CGFloat = 1.0 / 3.0

    private let progressView = UIProgressView(progressViewStyle: .default)
    private let handle = UIView()
    private var repeatWork: DispatchWorkItem?
    /// Kaydırma başladığında tutamacın bulunduğu oran.
    private var panOrigin: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressView)

        // Tutamaç otomatik yerleşimin dışında: konumu değere göre her düzen
        // turunda hesaplanıyor.
        handle.backgroundColor = .white
        handle.layer.cornerRadius = Self.handleSize / 2
        handle.layer.shadowColor = UIColor.black.cgColor
        handle.layer.shadowOpacity = 0.4
        handle.layer.shadowRadius = 6
        handle.layer.shadowOffset = .zero
        handle.isHidden = true
        handle.alpha = 0
        handle.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        addSubview(handle)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        addGestureRecognizer(pan)

        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressView.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: Self.handleSize + 6),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Tutamaç tvOS'ta ayrı bir resim değil; çağrı sessizce yutuluyor.
    func setThumbImage(_ image: UIImage?, for state: UIControl.State) {}

    override var canBecomeFocused: Bool { true }

    /// Tutamacın yeri `frame` ile değil `bounds` + `center` ile veriliyor.
    /// Dönüşümü sıfırdan farklı bir görünüme `frame` atamak tanımsız: beliriş
    /// ve kayboluş animasyonu sürerken düzen turu araya girince bounds
    /// şişiyor, sabit köşe yarıçapı da yuvarlağı büyüyen bir kareye
    /// çeviriyordu.
    override func layoutSubviews() {
        super.layoutSubviews()
        let span = maximumValue - minimumValue
        let fraction = span > 0 ? CGFloat((value - minimumValue) / span) : 0
        let size = Self.handleSize
        handle.bounds = CGRect(origin: .zero, size: CGSize(width: size, height: size))
        handle.center = CGPoint(
            x: size / 2 + (bounds.width - size) * max(0, min(1, fraction)),
            y: bounds.midY
        )
    }

    /// Odak geri bildirimi yalnızca tutamaç: çubuğu kalınlaştırmak istenmiyor.
    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        // Odak aşağıdaki butonlara inerken yarım kalan sarma uygulanıyor:
        // tutamacı oraya kullanıcı taşıdı, çıkarken atmak yaptığı işi
        // boşa çıkarıyordu. Vazgeçmenin yolu Menu.
        if !isFocused, isScrubbingActive {
            finish(commit: true)
        }
        let visible = isFocused
        if visible { handle.isHidden = false }
        coordinator.addCoordinatedAnimations {
            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.handle.transform = visible ? .identity : CGAffineTransform(scaleX: 0.1, y: 0.1)
                self.handle.alpha = visible ? 1 : 0
            } completion: { _ in
                if !visible { self.handle.isHidden = true }
            }
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .leftArrow:
                beginRepeating(-1)
                return
            case .rightArrow:
                beginRepeating(1)
                return
            case .select where isScrubbingActive:
                finish(commit: true)
                return
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        stopRepeating()
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        stopRepeating()
        super.pressesCancelled(presses, with: event)
    }

    /// Menu ile iptal. Basışı oynatıcıdaki tanıyıcı aldığı için çubuk onu
    /// kendi `pressesBegan`'inde göremiyor.
    func cancelScrubbing() {
        guard isScrubbingActive else { return }
        finish(commit: false)
    }

    /// Kumandanın dokunmatik yüzeyi. Yüzeyin bir ucundan diğerine kaydırmak
    /// çubuğun bir ucundan diğerine gitmeye denk geliyor.
    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard isFocused, bounds.width > 0 else { return }
        switch recognizer.state {
        case .began:
            activateScrubbing()
            panOrigin = CGFloat(value)
        case .changed:
            let shift = recognizer.translation(in: self).x / bounds.width * Self.panSensitivity
            onScrubFraction?(Float(max(0, min(1, panOrigin + shift))))
        default:
            break
        }
    }

    /// Tuş basılı tutuldukça adım tekrarlanıyor; uzun bir filmde tek tek
    /// basmak dakikalar sürüyor.
    private func beginRepeating(_ direction: Int) {
        activateScrubbing()
        onScrubStep?(direction)
        scheduleRepeat(direction)
    }

    /// Arayüz kapalıyken sağ/sol basıldığında oynatıcı çubuğu odağa alıp
    /// sarmayı da başlatıyor. Tekrar zamanlayıcısı kurulmuyor: bu basışın
    /// bırakılması çubuğa gelmiyor, kurulsa sonsuza dek sarardı.
    func startScrubbing(direction: Int) {
        activateScrubbing()
        onScrubStep?(direction)
    }

    private func activateScrubbing() {
        guard !isScrubbingActive else { return }
        isScrubbingActive = true
        onScrubBegin?()
    }

    private func scheduleRepeat(_ direction: Int) {
        repeatWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, isScrubbingActive else { return }
            onScrubStep?(direction)
            scheduleRepeat(direction)
        }
        repeatWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func stopRepeating() {
        repeatWork?.cancel()
        repeatWork = nil
    }

    private func finish(commit: Bool) {
        stopRepeating()
        isScrubbingActive = false
        commit ? onScrubCommit?() : onScrubCancel?()
    }

    private func updateProgress() {
        let span = maximumValue - minimumValue
        guard span > 0 else { return }
        progressView.progress = (value - minimumValue) / span
    }
}
#else
typealias PlaybackSlider = UISlider
#endif

/// Denetim satırının hemen altındaki görünmez odak durağı (tvOS).
final class PlayerFocusSentinel: UIView {
    var onFocus: (() -> Void)?

    #if os(tvOS)
    override var canBecomeFocused: Bool { true }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        if isFocused { onFocus?() }
    }
    #endif
}

/// Tam ekran oynatıcı.
///
/// AVFoundation bu içerikleri açamıyor: sağlayıcı VOD'ları `mkv`, canlı
/// yayınları ham `ts` olarak veriyor. Bu yüzden oynatma çoğunlukla FFmpeg
/// tabanlı `KSMEPlayer` üzerinden yürüyor; AVPlayer önce deneniyor ki
/// açabildiği yayınlarda PiP, AirPlay ve kilit ekranı denetimleri çalışsın.
///
/// Yerleşim Apple TV uygulamasının oynatıcısını izliyor: üst çubuk yok, her
/// şey altta tek bir sütunda duruyor.
///
///     S3:B9 · Veda
///     0:42 ─────────── ilerleme ──────────── -1:50:08
///     ⟨i⟩⟨cc⟩⟨ses⟩      ◀◀ ▶ ▶▶      [Bölümler]⟨boyut⟩
///     ┌ seçili sekmenin paneli ────────────────────────┐
///
/// Sütun alta bağlı: bir sekme açıldığında panel en alta ekleniyor ve
/// üstündeki her şey olduğu gibi yukarı kayıyor. Hiçbir satır gizlenmiyor.
///
/// Canlıda satırlar değişiyor: ilerleme yerine "CANLI" rozeti, sarma
/// butonları olmadan tek bir oynat/duraklat ve soldaki ⟨i⟩ yerine
/// [Kanallar] çipi. Kanal listesi alta değil sola açılıyor
/// (`PlayerChannelsController`): ekranın sol kenarına sıfır oturan bir
/// yüzey ve sütunun tamamı onun genişliği kadar sağa kayıyor.
final class PlayerViewController: UIViewController {
    /// Bölüm geçişinde yerine sıradakinin bağlamı konuyor.
    private var context: PlaybackContext
    private let model: AppModel

    private var playerLayer: KSPlayerLayer?
    private var videoView: UIView?

    // MARK: - Görünümler

    private let controlsView = UIView()
    private let bottomScrim = HeroGradientView()

    /// Büyük satır: dizide bölümün kendisi ("S3:B9 · Veda"), filmde ve canlıda
    /// içeriğin adı.
    private let titleLabel = UILabel()
    /// Üstündeki ince satır: filmde yıl, canlıda anlık EPG programı. Dizide
    /// boş — bölüm satırı zaten başlıkta ve dizinin adını bir kez daha
    /// okumanın bilgi değeri yok.
    private let infoLabel = UILabel()

    private let aspectButton = UIButton()
    private let addToListButton = UIButton()
    private let audioTracksButton = UIButton()
    private let subtitlesButton = UIButton()

    private let playPauseButton = UIButton()
    private let rewindButton = UIButton()
    private let forwardButton = UIButton()
    private let nextEpisodeButton = UIButton()

    private let currentTimeLabel = UILabel()
    /// Sağ uçtaki süre: toplam değil **kalan**. "-1:50:08".
    private let remainingLabel = UILabel()
    private let slider = PlaybackSlider()
    private let liveBadge = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .large)

    private let subtitleOverlay = SubtitleOverlayView()
    private lazy var subtitles = PlayerSubtitleController(overlay: subtitleOverlay)
    private let tabs = PlayerTabsController()
    /// Canlı yayında "Bilgi"nin yerini alan kanal çekmecesi.
    private let channels = PlayerChannelsController()

    /// Alt sütunun tamamı. Altyazının ne kadar yükseleceği buradan ölçülüyor.
    private let bottomStack = UIStackView()
    /// Kanal çekmecesi açılınca künye/denetim sütunu ve altyazı onun genişliği
    /// kadar sağa kayıyor; kayma bu iki kısıtın sabitinden geliyor.
    private var bottomStackLeading: NSLayoutConstraint!
    private var subtitleLeading: NSLayoutConstraint!
    /// Çipler, transport ve simge butonlarının bulunduğu satır. Aşağı tuşunun
    /// ne yapacağı odağın burada olup olmamasına bakıyor.
    private let controlRow = UIView()

    // Kapatma butonu ve üstteki karartma yalnızca iOS'ta: tvOS'ta oynatıcıdan
    // Menu tuşuyla çıkılıyor ve Apple TV'nin oynatıcısında da üst çubuk yok.
    #if os(iOS)
    private let closeButton = UIButton()
    private let topScrim = HeroGradientView()
    /// Kanal çekmecesini geldiği yöne kaydırıp kapatan jest. Listenin
    /// üstünde de çalışması gerekiyor, bu yüzden dokunuş süzgecinde ayrı
    /// tutuluyor.
    private weak var drawerDismissSwipe: UISwipeGestureRecognizer?
    #endif

    // MARK: - Durum

    private var isPlaying = true
    private var isScrubbing = false
    private var currentTime: Double = 0
    private var duration: Double = 0
    private var hideControlsWork: DispatchWorkItem?

    private var selectedAudioTrackID: Int32?
    /// Kumandayla sarma: hedef zaman ve arka arkaya kaç adım atıldığı.
    private var pendingScrubTime: Double?
    private var scrubStepCount = 0
    /// Aşağı kaydırma jesti; tvOS'ta ne zaman devreye gireceğine delege
    /// karar veriyor.
    /// tvOS: arayüz kapalıyken onu geri getiren kaydırmalar.
    private var revealSwipes: [UISwipeGestureRecognizer] = []
    /// Denetim satırının altındaki görünmez odak durağı; bilgi panelini o
    /// açıyor.
    private let focusSentinel = PlayerFocusSentinel()
    /// Odağın bir kereliğine gideceği yer. Arayüz kapalıyken sağ/sol
    /// basıldığında çubuğa yönlendirmek için.
    private weak var pendingFocusTarget: UIView?
    /// Yalnızca iki durum var: sığdır ve doldur. Buton menü açmıyor, her
    /// basışta ikisi arasında gidip geliyor.
    private var videoContentMode: UIView.ContentMode = .scaleAspectFit

    /// Hata uyarısı bir kez gösteriliyor. `.error` durumu ile `finish(error:)`
    /// arka arkaya gelebiliyor ve ikinci `present` çağrısı, ilki hâlâ
    /// ekrandayken sessizce düşüp kullanıcıyı kapatılamayan bir uyarıda
    /// bırakıyordu.
    private var didShowFailure = false

    /// İlerlemenin son kaydedildiği an. Kayıt yalnızca ekran kapanırken
    /// yapılınca, uygulama izlerken sonlandırıldığında kaldığı yer
    /// kayboluyordu.
    private var lastProgressSave = Date.distantPast
    private static let progressSaveInterval: TimeInterval = 30

    /// Arayüzün kendiliğinden solmasına kalan süre. Kısa tutulunca kullanıcı
    /// daha okumaya fırsat bulmadan künye ve ilerleme kayboluyordu.
    private static let controlsHideDelay: TimeInterval = 15

    /// Sıradaki bölüm; yoksa buton gizli ve bitince otomatik geçiş olmuyor.
    private var nextEpisode: (episode: Episode, series: MediaItem)?

    // MARK: - Ölçüler

    #if os(tvOS)
    private static let edgeInset: CGFloat = 60
    private static let iconInset: CGFloat = 18
    private static let iconPointSize: CGFloat = 26
    private static let transportPointSize: CGFloat = 30
    /// Oynat/duraklat komşularından iri: satırın ana aksiyonu o.
    private static let playPointSize: CGFloat = 42
    private static let titleSize: CGFloat = 50
    private static let infoSize: CGFloat = 26
    private static let timeSize: CGFloat = 24
    /// Yazılı çip yanındaki simge butonuyla aynı boyda dursun diye ayrı.
    private static let chipInset: CGFloat = 26
    private static let chipVerticalInset: CGFloat = 15
    private static let chipFontSize: CGFloat = 26
    /// Denetim satırının sığdığı en dar genişlik: kanal listesi sütunu ancak
    /// geriye bu kadarı kalıyorsa itiyor.
    private static let minControlsWidth: CGFloat = 900
    #else
    private static let edgeInset: CGFloat = 20
    private static let iconInset: CGFloat = 11
    private static let iconPointSize: CGFloat = 16
    private static let transportPointSize: CGFloat = 20
    private static let playPointSize: CGFloat = 28
    private static let titleSize: CGFloat = 26
    private static let infoSize: CGFloat = 14
    private static let timeSize: CGFloat = 13
    private static let chipInset: CGFloat = 16
    private static let chipVerticalInset: CGFloat = 10
    private static let chipFontSize: CGFloat = 15
    private static let minControlsWidth: CGFloat = 360
    #endif

    init(context: PlaybackContext, model: AppModel) {
        self.context = context
        self.model = model
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Ana ekran çizgisi ve durum çubuğu yalnızca iOS'ta var.
    #if os(iOS)
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildControls()
        wireMenus()
        wireTabs()
        wireChannels()
        startPlayback()
        scheduleControlsHide()

        #if os(iOS)
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        tap.delegate = self
        view.addGestureRecognizer(tap)

        let up = UISwipeGestureRecognizer(target: self, action: #selector(swipedUp))
        up.direction = .up
        up.delegate = self
        view.addGestureRecognizer(up)

        // Aşağı kaydırma bilgi panelini getiriyor. tvOS'ta buna gerek yok:
        // orada aşağı kaydırmak odağı denetim satırının altındaki durağa
        // indiriyor ve paneli o açıyor.
        let down = UISwipeGestureRecognizer(target: self, action: #selector(swipedDown))
        down.direction = .down
        down.delegate = self
        view.addGestureRecognizer(down)

        // Çekmece geldiği yöne kaydırılınca kapanıyor.
        let left = UISwipeGestureRecognizer(target: self, action: #selector(swipedLeft))
        left.direction = .left
        left.delegate = self
        view.addGestureRecognizer(left)
        drawerDismissSwipe = left
        #endif

        #if os(tvOS)
        // Menu tuşu için ayrı bir tanıyıcı şart. tvOS, modal olarak sunulmuş
        // bir denetleyicide Menu'yü kendisi yakalayıp ekranı kapatıyor ve
        // `pressesBegan` bunun önüne geçmiyor — zincirde ne yazarsa yazsın
        // oynatıcı kapanıyordu. Basış tipi Menu olan bir tanıyıcı, basışı
        // sistemin kendi davranışından önce alıyor.
        let menuPress = UITapGestureRecognizer(target: self, action: #selector(menuPressed))
        menuPress.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(menuPress)

        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(swipedUp))
        swipeUp.direction = .up
        swipeUp.delegate = self
        view.addGestureRecognizer(swipeUp)

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(swipedDown))
        swipeDown.direction = .down
        swipeDown.delegate = self
        view.addGestureRecognizer(swipeDown)

        // Arayüz kapalıyken herhangi bir yöne kaydırmak onu geri getiriyor.
        // Kapalıyken odaklanabilir hiçbir şey olmadığı için bu jestler odak
        // gezinmesinin önüne geçmiyor; delege de açıkken devreye girmelerini
        // engelliyor.
        for direction in [UISwipeGestureRecognizer.Direction.up, .down, .left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swipedWhileHidden))
            swipe.direction = direction
            swipe.delegate = self
            view.addGestureRecognizer(swipe)
            revealSwipes.append(swipe)
        }
        #endif

        if context.isLive {
            loadLiveEPG()
            updateAddToListButton()
        }
        refreshNextEpisode()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Kart ölçüleri ekran genişliğinden geliyor; sekme panelleri açılırken
        // güncel değeri okuyor.
        tabs.metrics = AppMetrics.metrics(for: view.bounds.width)
        // Altyazı, kontroller açıkken alt sütunun üstüne çıkıyor. Yükseklik
        // ancak yerleşimden sonra biliniyor.
        subtitleOverlay.bottomInset = isControlsVisible ? raisedSubtitleInset : 0
    }

    /// Video oynarken ekran kararmamalı. tvOS'ta boşta kalma zamanlayıcısı
    /// zaten oynatma sırasında sistem tarafından yönetiliyor ama çağrı orada
    /// da geçerli ve zararsız.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        saveProgress()
        playerLayer?.pause()
        playerLayer?.stop()
        playerLayer = nil
    }

    // MARK: - Bölüm geçişi

    /// Sıradaki bölümü çözüp butonun görünürlüğünü ayarlar.
    private func refreshNextEpisode() {
        nextEpisode = nil
        nextEpisodeButton.isHidden = true
        tabs.hasNextEpisode = false
        guard context.kind == .series else { return }
        Task { [weak self] in
            guard let self else { return }
            let next = await model.nextEpisode(after: context)
            await MainActor.run {
                self.nextEpisode = next
                self.nextEpisodeButton.isHidden = next == nil
                self.tabs.hasNextEpisode = next != nil
            }
        }
    }

    /// Sıradaki bölüme geçer. Oynatıcı kapanıp yeniden açılmıyor; aynı ekranda
    /// katman değiştiriliyor, böylece kullanıcı akıştan kopmuyor.
    @objc private func playNextEpisode() {
        guard let next = nextEpisode else { return }
        nextEpisodeButton.isHidden = true
        Task { [weak self] in
            guard let self else { return }
            guard let newContext = try? await model.library.playback(for: next.episode, in: next.series) else { return }
            await MainActor.run { self.restart(with: newContext) }
        }
    }

    private func restart(with newContext: PlaybackContext) {
        saveProgress()
        playerLayer?.pause()
        playerLayer?.stop()
        playerLayer = nil
        videoView?.removeFromSuperview()
        videoView = nil

        context = newContext
        currentTime = 0
        duration = 0
        isPlaying = true
        didShowFailure = false
        lastProgressSave = .distantPast
        selectedAudioTrackID = nil
        playPauseButton.setSymbol("pause.fill", animated: false)
        applyTitleLines()

        startPlayback()
        refreshNextEpisode()
        // Kanal değişti: künyenin ince satırındaki anlık program da değişiyor.
        if context.isLive {
            loadLiveEPG()
            updateAddToListButton()
        }
        showControls()
    }

    // MARK: - Kumanda girdisi (tvOS)

    #if os(tvOS)
    /// Kontroller açıldığında odak oynat/duraklat'a gidiyor; bir sekme paneli
    /// açıksa seçili çipte kalıyor — Apple TV'de de odak panele kendiliğinden
    /// inmiyor, kullanıcı aşağı basınca iniyor.
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let pendingFocusTarget { return [pendingFocusTarget] }
        if channels.isOpen { return channels.focusEnvironments }
        return tabs.isPanelOpen ? tabs.focusEnvironments : [playPauseButton]
    }

    /// Kumanda tuşları.
    ///
    /// Kontroller gizliyken yön tuşu, seçim ve Menu yalnızca arayüzü geri
    /// getiriyor; basış eylemi tetiklemiyor. Aksi hâlde kullanıcı göremediği
    /// bir butonu yanlışlıkla çalıştırırdı.
    ///
    /// Oynat/Duraklat tuşu bunun dışında: o her zaman oynatmayı değiştiriyor,
    /// arayüz kapalıyken bile — kumandadaki karşılığı bu ve beklenen davranış.
    ///
    /// Arayüzü **yalnızca** gerçek bir basış açıyor. Eskiden kumandanın
    /// dokunmatik yüzeyine değmek de açıyordu ve geri tuşu hiçbir zaman
    /// oynatıcıyı kapatamıyordu: kullanıcının başparmağı yüzeyde dururken
    /// arayüz kendiliğinden geri geliyor, geri tuşu da onu kapatmakla
    /// yetiniyordu. Arayüz kapalıyken yön/seçim tuşu ya da aşağı kaydırma
    /// geri getiriyor.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .playPause:
                togglePlayPause()
                return

            case .leftArrow, .rightArrow:
                // Arayüz kapalıyken sağ/sol doğrudan sarmaya giriyor: kullanıcı
                // önce arayüzü açıp sonra çubuğa inmek zorunda kalmıyor.
                guard !isControlsVisible else { break }
                beginScrubFromHidden(direction: press.type == .leftArrow ? -1 : 1)
                return

            case .upArrow:
                guard !isControlsVisible else {
                    if channels.isOpen {
                        channels.close()
                        return
                    }
                    if tabs.isPanelOpen {
                        tabs.close()
                        setNeedsFocusUpdate()
                        updateFocusIfNeeded()
                        return
                    }
                    break
                }
                showControls()
                return

            case .select, .downArrow:
                // Aşağı inmek yalnızca odak hareketi; bilgi panelini denetim
                // satırının altındaki odak durağı açıyor.
                guard !isControlsVisible else { break }
                showControls()
                return

            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    #endif

    // MARK: - Oynatma

    private func startPlayback() {
        Task.detached(priority: .userInitiated) { KSOptions.setAudioSession() }

        // KSPlayer'ın kendi varsayılanı: önce AVPlayer, olmazsa FFmpeg.
        // Buradaki eski ayar ikisini de kapatıyordu — her yayın FFmpeg'e
        // gidiyor, dolayısıyla PiP, AirPlay ve kilit ekranı denetimleri
        // hiç çalışmıyor, üstelik AVPlayer başarısız olduğunda geri düşecek
        // bir oynatıcı da kalmıyordu.
        KSOptions.firstPlayerType = KSAVPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self

        let options = KSOptions()
        options.userAgent = context.headers["User-Agent"] ?? "VLC/3.0.20 LibVLC/3.0.20"
        if let referer = context.headers["Referer"] { options.referer = referer }
        if let startAt = context.startAt, startAt > 0, !context.isLive {
            options.startPlayTime = startAt
        }
        // Gömülü altyazıyı biz seçiyoruz: kullanıcının "kendiliğinden aç"
        // tercihi kütüphanenin varsayılanının önünde.
        options.autoSelectEmbedSubtitle = false

        subtitles.prepare(url: context.url)
        tabs.configure(context: context, model: model)
        channels.configure(context: context, model: model)

        let layer = KSPlayerLayer(url: context.url, options: options, delegate: self)
        playerLayer = layer
        refreshTrackMenus()

        guard let videoView = layer.player.view else { return }
        self.videoView = videoView
        videoView.contentMode = videoContentMode
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(videoView, at: 0)
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func saveProgress() {
        guard !context.isLive, duration > 0 else { return }
        model.recordProgress(for: context, position: currentTime, duration: duration)
    }

    private func loadLiveEPG() {
        // Canlı yayında künye satırı anlık programı gösteriyor.
        guard let decoded = AppModel.decode(contextID: context.id) else { return }
        guard let item = model.library.item(for: decoded.mediaID) else { return }

        Task { [weak self] in
            guard let self else { return }
            let epgEntries = await model.library.epg(for: item)
            let now = Date()
            guard let current = epgEntries.first(where: { $0.start <= now && $0.end >= now }) else { return }
            await MainActor.run {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                let range = "\(formatter.string(from: current.start)) - \(formatter.string(from: current.end))"
                self.infoLabel.text = "\(range) · \(current.title)"
                self.infoLabel.isHidden = false
            }
        }
    }

    /// Künye satırlarını bağlamdan çıkarır.
    ///
    /// Dizide ekranda yalnızca bölüm duruyor: "S3:B9 · Veda". Dizinin adını
    /// izleyen zaten biliyor, ince satır boş kalıyor.
    ///
    /// Filmde ince satır yıl — bağlamın taşıdığı kategori adı başlığın yanında
    /// bir şey anlatmıyor. Canlıda ince satırı `loadLiveEPG` dolduruyor.
    private func applyTitleLines() {
        if context.kind == .series, let episode = context.subtitle {
            titleLabel.text = episode
            infoLabel.text = nil
        } else {
            titleLabel.text = context.title
            infoLabel.text = secondaryLine()
        }
        infoLabel.isHidden = (infoLabel.text ?? "").isEmpty
    }

    private func secondaryLine() -> String? {
        if context.kind == .movie,
           let decoded = AppModel.decode(contextID: context.id),
           let year = model.library.item(for: decoded.mediaID)?.yearText
        {
            return year
        }
        return context.subtitle
    }

    // MARK: - Kontrollerin kurulumu

    private func buildControls() {
        buildScrims()
        buildHeader()
        buildTransport()
        layoutControls()
    }

    /// Kontroller videonun üstünde duruyor ve açık bir sahnede beyaz yazı
    /// zeminle karışıyor. Alttaki karartma, cam butonların da tutunacağı koyu
    /// bir zemin bırakıyor.
    private func buildScrims() {
        bottomScrim.colors = [
            .clear,
            UIColor.black.withAlphaComponent(0.45),
            UIColor.black.withAlphaComponent(0.9),
        ]
        bottomScrim.locations = [0, 0.4, 1]

        #if os(iOS)
        topScrim.colors = [UIColor.black.withAlphaComponent(0.6), .clear]
        topScrim.locations = [0, 1]
        #endif
    }

    private func buildHeader() {
        titleLabel.font = .systemFont(ofSize: Self.titleSize, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1

        infoLabel.font = .systemFont(ofSize: Self.infoSize)
        infoLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        infoLabel.numberOfLines = 1
        applyTitleLines()

        // Görüntü boyutu menü açmıyor: iki durum var ve buton her basışta
        // ikisi arasında gidip geliyor. Simge yapılacak işi gösteriyor.
        style(aspectButton, symbol: "arrow.up.left.and.arrow.down.right", accessibility: L10n.aspectFill)
        aspectButton.addTarget(self, action: #selector(toggleAspect), for: .primaryActionTriggered)

        style(addToListButton, symbol: "bookmark", accessibility: L10n.addToList)
        addToListButton.addTarget(self, action: #selector(toggleAddToList), for: .primaryActionTriggered)

        style(audioTracksButton, symbol: "waveform", accessibility: L10n.audioTracks)
        audioTracksButton.showsMenuAsPrimaryAction = true
        audioTracksButton.isHidden = true

        style(subtitlesButton, symbol: "captions.bubble", accessibility: L10n.subtitles)
        subtitlesButton.showsMenuAsPrimaryAction = true

        #if os(iOS)
        style(closeButton, symbol: "xmark", accessibility: L10n.close)
        closeButton.addTarget(self, action: #selector(close), for: .primaryActionTriggered)
        #endif
    }

    private func buildTransport() {
        style(playPauseButton, symbol: "pause.fill", pointSize: Self.playPointSize)
        playPauseButton.addTarget(self, action: #selector(togglePlayPause), for: .primaryActionTriggered)

        style(rewindButton, symbol: "gobackward.15", pointSize: Self.transportPointSize)
        rewindButton.addTarget(self, action: #selector(seekBackward), for: .primaryActionTriggered)

        style(forwardButton, symbol: "goforward.15", pointSize: Self.transportPointSize)
        forwardButton.addTarget(self, action: #selector(seekForward), for: .primaryActionTriggered)

        style(nextEpisodeButton, symbol: "forward.end.fill", pointSize: Self.transportPointSize,
              accessibility: L10n.nextEpisode)
        nextEpisodeButton.isHidden = true
        nextEpisodeButton.addTarget(self, action: #selector(playNextEpisode), for: .primaryActionTriggered)

        for label in [currentTimeLabel, remainingLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: Self.timeSize, weight: .regular)
            label.textColor = UIColor.white.withAlphaComponent(0.8)
        }
        currentTimeLabel.text = "0:00"
        remainingLabel.text = "-0:00"
        remainingLabel.textAlignment = .right

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = 0
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.28)
        slider.setThumbImage(Self.thumbImage, for: .normal)
        slider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        #if os(tvOS)
        slider.onScrubBegin = { [weak self] in self?.beginScrub() }
        slider.onScrubStep = { [weak self] direction in self?.scrubStep(direction) }
        slider.onScrubFraction = { [weak self] fraction in self?.scrub(toFraction: fraction) }
        slider.onScrubCommit = { [weak self] in self?.finishScrub(commit: true) }
        slider.onScrubCancel = { [weak self] in self?.finishScrub(commit: false) }
        #endif

        let dot = UIView()
        dot.backgroundColor = .systemRed
        dot.layer.cornerRadius = 4
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let liveLabel = UILabel()
        liveLabel.text = L10n.liveBadge
        liveLabel.font = .systemFont(ofSize: Self.timeSize, weight: .bold)
        liveLabel.textColor = .white
        liveBadge.addArrangedSubview(dot)
        liveBadge.addArrangedSubview(liveLabel)
        liveBadge.axis = .horizontal
        liveBadge.spacing = 6
        liveBadge.alignment = .center
        // Rozet kendi boyunda kalsın: satırdaki boşluğu yanındaki dolgu
        // yutuyor, rozet değil.
        liveBadge.setContentHuggingPriority(.required, for: .horizontal)
        liveBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func layoutControls() {
        // Künye: ince satır üstte, başlık altında.
        let titlesStack = UIStackView()
        titlesStack.axis = .vertical
        titlesStack.spacing = 2
        titlesStack.addArrangedSubview(infoLabel)
        titlesStack.addArrangedSubview(titleLabel)

        // Geçen süre solda, kalan süre sağda, ilerleme ortada. Canlıda
        // ilerleme yok: yerinde "CANLI" rozeti duruyor.
        let sliderRow = UIStackView()
        sliderRow.axis = .horizontal
        sliderRow.spacing = 12
        sliderRow.alignment = .center
        for subview in context.isLive ? [liveBadge, UIView()] : [currentTimeLabel, slider, remainingLabel] {
            sliderRow.addArrangedSubview(subview)
        }

        // Solda sekme çipleri, ortada transport, sağda simge butonları —
        // hepsi tek satırda.
        let transportRow = UIStackView(
            arrangedSubviews: context.isLive
                ? [playPauseButton]
                : [rewindButton, playPauseButton, forwardButton, nextEpisodeButton]
        )
        transportRow.axis = .horizontal
        transportRow.spacing = 10
        transportRow.alignment = .center
        let transportGlass = UIView.glassContainer(wrapping: transportRow, spacing: 10)

        // Yan yana duran cam butonlar tek bir cam yüzeyde; birbirlerine
        // yaklaştıklarında malzeme akışkan biçimde birleşiyor.
        //
        // Canlıda soldaki ilk çip "Bilgi" değil "Kanallar": kanalda gösterilecek
        // künye yok, geçilecek kanal çok.
        let leadingRow = UIStackView(
            arrangedSubviews: context.isLive
                ? [channels.chip, subtitlesButton, audioTracksButton]
                : [tabs.infoChip, subtitlesButton, audioTracksButton]
        )
        leadingRow.axis = .horizontal
        leadingRow.spacing = 8
        leadingRow.alignment = .center
        let leadingGlass = UIView.glassContainer(wrapping: leadingRow, spacing: 8)

        let trailingRow = UIStackView(
            arrangedSubviews: context.isLive
                ? [addToListButton, aspectButton]
                : [tabs.episodesChip, aspectButton]
        )
        trailingRow.axis = .horizontal
        trailingRow.spacing = 8
        trailingRow.alignment = .center
        let trailingGlass = UIView.glassContainer(wrapping: trailingRow, spacing: 8)

        for subview in [leadingGlass, transportGlass, trailingGlass] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            controlRow.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            // Transport satırın ortasında ve yüksekliği satırı belirliyor.
            transportGlass.topAnchor.constraint(equalTo: controlRow.topAnchor),
            transportGlass.bottomAnchor.constraint(equalTo: controlRow.bottomAnchor),
            transportGlass.centerXAnchor.constraint(equalTo: controlRow.centerXAnchor),

            leadingGlass.leadingAnchor.constraint(equalTo: controlRow.leadingAnchor),
            leadingGlass.centerYAnchor.constraint(equalTo: transportGlass.centerYAnchor),
            leadingGlass.trailingAnchor.constraint(lessThanOrEqualTo: transportGlass.leadingAnchor, constant: -16),

            trailingGlass.trailingAnchor.constraint(equalTo: controlRow.trailingAnchor),
            trailingGlass.centerYAnchor.constraint(equalTo: transportGlass.centerYAnchor),
            trailingGlass.leadingAnchor.constraint(greaterThanOrEqualTo: transportGlass.trailingAnchor, constant: 16),
        ])

        bottomStack.axis = .vertical
        bottomStack.spacing = 16
        bottomStack.addArrangedSubview(titlesStack)
        bottomStack.addArrangedSubview(sliderRow)
        bottomStack.addArrangedSubview(controlRow)
        bottomStack.addArrangedSubview(tabs.panel)
        bottomStack.setCustomSpacing(10, after: titlesStack)
        // Odaktaki kart kendi çerçevesinin dışına büyüyor; yığın kırpmamalı.
        bottomStack.clipsToBounds = false

        // Altyazı katmanı videonun üstünde, kontrollerin altında: kontroller
        // solduğunda altyazı ekranda kalıyor.
        subtitleOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleOverlay)

        controlsView.translatesAutoresizingMaskIntoConstraints = false
        controlsView.clipsToBounds = false
        view.addSubview(controlsView)
        for subview in [bottomScrim, bottomStack] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            controlsView.addSubview(subview)
        }
        // Karartma en altta: yazı ve butonlar üstünde kalıyor.
        controlsView.sendSubviewToBack(bottomScrim)

        #if os(tvOS)
        // Yığına konmuyor: yığının boşluğu görünür bir aralık açardı. Görünmez
        // ve bir punto yüksekliğinde, yalnızca odak için var. Canlıda açılacak
        // bir panel olmadığı için hiç kurulmuyor: odağı yutup boşluğa
        // götürürdü.
        if !context.isLive {
            focusSentinel.translatesAutoresizingMaskIntoConstraints = false
            focusSentinel.onFocus = { [weak self] in
                guard let self, !tabs.isPanelOpen else { return }
                tabs.open(.info)
            }
            controlsView.addSubview(focusSentinel)
            NSLayoutConstraint.activate([
                focusSentinel.topAnchor.constraint(equalTo: controlRow.bottomAnchor),
                focusSentinel.leadingAnchor.constraint(equalTo: controlRow.leadingAnchor),
                focusSentinel.trailingAnchor.constraint(equalTo: controlRow.trailingAnchor),
                focusSentinel.heightAnchor.constraint(equalToConstant: 1),
            ])
        }
        #endif

        // Kanal çekmecesi ekranın sol 1/4'ünü kaplar: tam 4'te 1 oranında.
        if context.isLive {
            channels.drawer.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(channels.drawer)
            NSLayoutConstraint.activate([
                channels.drawer.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.25),
                channels.drawer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                channels.drawer.topAnchor.constraint(equalTo: view.topAnchor),
                channels.drawer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        spinner.startAnimating()
        view.addSubview(spinner)

        let inset = Self.edgeInset
        subtitleLeading = subtitleOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        bottomStackLeading = bottomStack.leadingAnchor.constraint(
            equalTo: controlsView.safeAreaLayoutGuide.leadingAnchor, constant: inset
        )
        NSLayoutConstraint.activate([
            subtitleOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            subtitleOverlay.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            subtitleLeading,
            subtitleOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            controlsView.topAnchor.constraint(equalTo: view.topAnchor),
            controlsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controlsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            bottomScrim.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor),
            bottomScrim.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor),
            bottomScrim.bottomAnchor.constraint(equalTo: controlsView.bottomAnchor),
            bottomScrim.topAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -inset * 2),

            bottomStackLeading,
            bottomStack.trailingAnchor.constraint(equalTo: controlsView.safeAreaLayoutGuide.trailingAnchor, constant: -inset),
            bottomStack.bottomAnchor.constraint(equalTo: controlsView.safeAreaLayoutGuide.bottomAnchor, constant: -inset),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        #if os(iOS)
        for subview in [topScrim, closeButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            controlsView.addSubview(subview)
        }
        controlsView.sendSubviewToBack(topScrim)
        NSLayoutConstraint.activate([
            topScrim.topAnchor.constraint(equalTo: controlsView.topAnchor),
            topScrim.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor),
            topScrim.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor),
            topScrim.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: inset),

            closeButton.topAnchor.constraint(equalTo: controlsView.safeAreaLayoutGuide.topAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: controlsView.safeAreaLayoutGuide.trailingAnchor, constant: -inset),
        ])
        #endif
    }

    /// Oynatıcının simge butonu — uygulamanın her yerindeki cam buton, kare
    /// oranlı. Sembol `preferredSymbolConfigurationForImage`'a bağlanıyor:
    /// `setSymbol` yalnızca resmi değiştirdiği için ölçü resme gömülseydi
    /// oynat/duraklat geçişinde kaybolurdu.
    private func style(
        _ button: UIButton,
        symbol: String,
        pointSize: CGFloat? = nil,
        accessibility: String? = nil
    ) {
        var config = UIButton.Configuration.appGlass(
            horizontalInset: Self.iconInset,
            verticalInset: Self.iconInset
        )
        config.image = UIImage(systemName: symbol)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: pointSize ?? Self.iconPointSize,
            weight: .semibold
        )
        button.configuration = config
        button.accessibilityLabel = accessibility
        button.addSpringPressFeedback(scale: 0.92)
    }

    private static let thumbImage: UIImage = {
        let size = CGSize(width: 14, height: 14)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
    }()

    // MARK: - Sekmeler

    private func wireTabs() {
        tabs.styleChip = { [weak self] button, tab, isSelected in
            self?.styleChip(button, tab: tab, isSelected: isSelected)
        }
        tabs.onPanelVisibilityChanged = { [weak self] isOpen in
            guard let self else { return }
            // Panel denetim satırının altına ekleniyor ve yığın alta bağlı
            // olduğu için künye, ilerleme ve denetimler olduğu gibi yukarı
            // kayıyor — hiçbiri gizlenmiyor.
            //
            // Kullanıcı listeye bakıyor olabilir; kontroller kendiliğinden
            // gizlenmiyor.
            if isOpen {
                hideControlsWork?.cancel()
            } else {
                scheduleControlsHide()
            }
            UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
            #if os(tvOS)
            // Panel açıkken durak odağı yutmamalı; aşağı basınca panelin
            // içine inilsin.
            focusSentinel.isHidden = isOpen
            // Yalnızca açılırken: panel kapanırken odağı taşımak kullanıcıyı
            // çipten alıp oynat/duraklat'a atıyordu.
            if isOpen {
                setNeedsFocusUpdate()
                updateFocusIfNeeded()
            }
            #endif
        }
        tabs.onSeek = { [weak self] time in
            self?.seek(to: time)
        }
        tabs.onRestart = { [weak self] in
            guard let self else { return }
            tabs.close()
            seek(to: 0)
        }
        tabs.onNextEpisode = { [weak self] in
            guard let self else { return }
            tabs.close()
            playNextEpisode()
        }
        tabs.onPlay = { [weak self] context in
            self?.restart(with: context)
        }
    }

    // MARK: - Kanal çekmecesi

    private func wireChannels() {
        channels.styleChip = { [weak self] button, isSelected in
            self?.styleChannelsChip(button, isSelected: isSelected)
        }
        channels.onVisibilityChanged = { [weak self] isOpen in
            guard let self else { return }
            // Künye, ilerleme satırı ve denetimler listenin genişliği kadar
            // sağa kayıyor — liste videonun üstünü örtmüyor, ekranı bölüyor.
            // Yalnızca sabitler değişiyor: yerleşimi çekmece kendi
            // animasyonunun içinde yürütüyor, ikisi tek eğride ilerlesin.
            // Dar ekranda (telefon dikeyken) itecek yer yok: orada liste
            // denetimlerin üstüne biniyor, sütun yerinde kalıyor.
            let drawerWidth = channels.drawer.bounds.width
            let canPush = view.bounds.width - drawerWidth >= Self.minControlsWidth
            let shift = isOpen && canPush ? drawerWidth : 0
            // Çekmece ekranın kenarına sıfır oturuyor, alt sütun ise güvenli
            // alandan başlıyor; kayma ikisinin farkı kadar.
            bottomStackLeading.constant = Self.edgeInset + max(0, shift - view.safeAreaInsets.left)
            subtitleLeading.constant = shift

            // Kullanıcı listeye bakıyor olabilir; kontroller kendiliğinden
            // gizlenmiyor.
            if isOpen {
                hideControlsWork?.cancel()
            } else {
                scheduleControlsHide()
            }
            #if os(tvOS)
            // Açılırken odak listeye iniyor; kapanırken çipte kalıyor.
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
            #endif
        }
        // Kanal geçişinde oynatıcı kapanıp yeniden açılmıyor; bölüm
        // geçişindeki gibi aynı ekranda katman değişiyor.
        channels.onSelect = { [weak self] channel in
            Task { [weak self] in
                guard let self else { return }
                guard let newContext = try? await model.library.playback(for: channel) else { return }
                await MainActor.run { self.restart(with: newContext) }
            }
        }
        channels.onOpenListEditor = { [weak self] in
            guard let self else { return }
            let editor = PlayerListEditorViewController(model: self.model)
            editor.onSave = { [weak self] in
                self?.channels.refreshListemData()
                self?.updateAddToListButton()
            }
            let nav = UINavigationController.app(root: editor)
            self.present(nav, animated: true)
        }
    }

    /// "Kanallar" çipi "Bölümler" ile aynı: yazılı ve seçiliyken dolu beyaz.
    /// İkisi denetim satırının iki ucunda simetrik duruyor.
    private func styleChannelsChip(_ button: UIButton, isSelected: Bool) {
        var config = UIButton.Configuration.appChip(
            isSelected: isSelected,
            horizontalInset: Self.chipInset,
            verticalInset: Self.chipVerticalInset,
            fontSize: Self.chipFontSize
        )
        config.title = L10n.channels
        button.configuration = config
        button.accessibilityLabel = L10n.channels
    }

    /// Çipler yanlarındaki simge butonlarıyla aynı boyda: "Bilgi" yalnızca
    /// simge, "Bölümler" yazılı. Seçili çip dolu beyaz — `appChip`'in her
    /// yerdeki davranışı.
    private func styleChip(_ button: UIButton, tab: PlayerTabsController.Tab, isSelected: Bool) {
        switch tab {
        case .info:
            // Simge butonunda yazı yok; punto yalnızca imza gereği veriliyor.
            var config = UIButton.Configuration.appChip(
                isSelected: isSelected,
                horizontalInset: Self.iconInset,
                verticalInset: Self.iconInset,
                fontSize: Self.chipFontSize
            )
            config.image = UIImage(systemName: "info.circle")
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: Self.iconPointSize,
                weight: .semibold
            )
            button.configuration = config
            button.accessibilityLabel = L10n.info

        case .episodes:
            var config = UIButton.Configuration.appChip(
                isSelected: isSelected,
                horizontalInset: Self.chipInset,
                verticalInset: Self.chipVerticalInset,
                fontSize: Self.chipFontSize
            )
            config.title = tab.title
            button.configuration = config
        }
    }

    // MARK: - Menüler

    /// Menüler durumdan türüyor: seçili parça ve altyazı ayarları her açılışta
    /// taze kurulan menüde işaretli geliyor.
    private func wireMenus() {
        subtitles.onMenuChanged = { [weak self] in
            guard let self else { return }
            subtitlesButton.menu = subtitles.makeMenu()
        }
        subtitlesButton.menu = subtitles.makeMenu()
    }

    /// Ses parçası menüsü. Altyazınınki `PlayerSubtitleController`'da.
    private func refreshTrackMenus() {
        subtitlesButton.menu = subtitles.makeMenu()

        guard let player = playerLayer?.player else {
            audioTracksButton.isHidden = true
            return
        }
        let tracks = player.tracks(mediaType: .audio)
        // Tek ses parçasında menünün seçecek bir şeyi yok.
        guard tracks.count > 1 else {
            audioTracksButton.isHidden = true
            return
        }
        let actions = tracks.map { track in
            let isSelected = selectedAudioTrackID == track.trackID
                || (selectedAudioTrackID == nil && track.isEnabled)
            let name = track.name.isEmpty ? "\(L10n.audioTracks) \(track.trackID)" : track.name
            return UIAction(title: name, state: isSelected ? .on : .off) { [weak self] _ in
                guard let self else { return }
                playerLayer?.player.select(track: track)
                selectedAudioTrackID = track.trackID
                refreshTrackMenus()
            }
        }
        audioTracksButton.menu = UIMenu(title: L10n.audioTracks, children: actions)
        audioTracksButton.isHidden = false
    }

    // MARK: - Aksiyonlar

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func togglePlayPause() {
        isPlaying.toggle()
        isPlaying ? playerLayer?.play() : playerLayer?.pause()
        playPauseButton.setSymbol(isPlaying ? "pause.fill" : "play.fill")
        isPlaying ? scheduleControlsHide() : showControls()
    }

    private var currentMediaItem: MediaItem? {
        guard let decoded = AppModel.decode(contextID: context.id) else { return nil }
        return model.library.item(for: decoded.mediaID)
    }

    private func updateAddToListButton() {
        guard context.isLive, let current = currentMediaItem else {
            addToListButton.isHidden = true
            return
        }
        addToListButton.isHidden = false
        let isSaved = model.activity.isFavorite(current)
        addToListButton.setSymbol(isSaved ? "bookmark.fill" : "bookmark")
        addToListButton.accessibilityLabel = isSaved ? L10n.removeFromList : L10n.addToList
    }

    @objc private func toggleAddToList() {
        guard let current = currentMediaItem else { return }
        model.activity.toggleFavorite(current)
        updateAddToListButton()
        channels.refreshListemData()
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        showControls()
    }

    /// Sığdır ↔ doldur. Simge yapılacak işi gösteriyor: sığdırılmışken
    /// "büyüt", doldurulmuşken "küçült".
    @objc private func toggleAspect() {
        let isFit = videoContentMode == .scaleAspectFit
        videoContentMode = isFit ? .scaleAspectFill : .scaleAspectFit
        videoView?.contentMode = videoContentMode
        playerLayer?.player.view?.contentMode = videoContentMode

        aspectButton.setSymbol(isFit ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
        aspectButton.accessibilityLabel = isFit ? L10n.aspectFit : L10n.aspectFill
        showControls()
    }

    @objc private func seekBackward() {
        seek(to: currentTime - 15)
    }

    @objc private func seekForward() {
        seek(to: currentTime + 15)
    }

    private func seek(to seconds: Double) {
        guard duration > 0 else { return }
        let target = max(0, min(duration, seconds))
        currentTime = target
        applyTimeText(for: target)
        slider.value = Float(target / duration)
        // Sarma sonrası eski satır ekranda asılı kalmasın.
        subtitles.flush()
        playerLayer?.seek(time: target, autoPlay: isPlaying, completion: { _ in })
        showControls()
    }

    #if os(tvOS)
    /// Arayüz kapalıyken sağ/sol basıldı: arayüz açılıyor, odak çubuğa
    /// gidiyor ve sarma o basışla başlıyor.
    private func beginScrubFromHidden(direction: Int) {
        pendingFocusTarget = slider
        showControls()
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        pendingFocusTarget = nil
        slider.startScrubbing(direction: direction)
    }

    /// Tutamaç gezdirilmeye başlandı: görüntü duruyor.
    ///
    /// Duraklatma `isPlaying`'e dokunmuyor — o kullanıcının oynat/duraklat
    /// tercihi ve sarma bittiğinde oynatma ona göre sürüyor.
    private func beginScrub() {
        guard duration > 0 else { return }
        pendingScrubTime = currentTime
        scrubStepCount = 0
        isScrubbing = true
        hideControlsWork?.cancel()
        playerLayer?.pause()
        applyTimeText(for: currentTime)
    }

    /// Sağ/sol tuşuyla hedefi gezdirir; atlama tıklamayla oluyor.
    private func scrubStep(_ direction: Int) {
        guard duration > 0, let current = pendingScrubTime else { return }
        scrubStepCount += 1
        // Basılı tutuldukça adım büyüyor: iki saatlik bir filmde 10'ar
        // saniyeyle ilerlemek dakikalar sürüyor.
        let step: Double = scrubStepCount > 24 ? 60 : (scrubStepCount > 10 ? 30 : 10)
        applyScrubTarget(current + Double(direction) * step)
    }

    /// Dokunmatik yüzeyden gelen doğrudan konum.
    private func scrub(toFraction fraction: Float) {
        guard duration > 0 else { return }
        applyScrubTarget(Double(fraction) * duration)
    }

    private func applyScrubTarget(_ seconds: Double) {
        let target = max(0, min(duration, seconds))
        pendingScrubTime = target
        slider.value = Float(target / duration)
        applyTimeText(for: target)
    }

    private func finishScrub(commit: Bool) {
        defer {
            pendingScrubTime = nil
            scrubStepCount = 0
            isScrubbing = false
            scheduleControlsHide()
        }
        guard commit, let target = pendingScrubTime else {
            // Vazgeçildi: çubuk ve süreler oynatılan ana geri dönüyor, görüntü
            // durduğu yerden akmaya devam ediyor.
            refreshTimeLabels()
            if isPlaying { playerLayer?.play() }
            return
        }
        currentTime = target
        subtitles.flush()
        playerLayer?.seek(time: target, autoPlay: isPlaying, completion: { _ in })
    }

    /// Çubuktan **yalnızca** yatay odak hareketi kapalı: sağ/sol sarma demek.
    /// Yukarı ve aşağı her zaman açık — sarma sürerken bile kullanıcı alttaki
    /// butonlara inebilmeli, yoksa çubukta kilitli kalıyordu.
    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        if context.previouslyFocusedItem === slider,
           context.focusHeading == .left || context.focusHeading == .right
        {
            return false
        }
        return super.shouldUpdateFocus(in: context)
    }
    #endif

    @objc private func sliderTouchDown() {
        isScrubbing = true
        hideControlsWork?.cancel()
    }

    @objc private func sliderValueChanged() {
        guard duration > 0 else { return }
        applyTimeText(for: Double(slider.value) * duration)
    }

    @objc private func sliderTouchUp() {
        guard duration > 0 else { isScrubbing = false; return }
        let target = Double(slider.value) * duration
        currentTime = target
        subtitles.flush()
        playerLayer?.seek(time: target, autoPlay: isPlaying, completion: { _ in })
        isScrubbing = false
        scheduleControlsHide()
    }

    /// Aşağı kaydırmak bilgi panelini getiriyor.
    @objc private func swipedDown() {
        guard isControlsVisible else {
            showControls()
            return
        }
        guard !tabs.isPanelOpen else { return }
        tabs.open(.info)
    }

    #if os(iOS)
    /// Sola kaydırmak açık kanal çekmecesini kapatıyor.
    @objc private func swipedLeft() {
        channels.close()
    }
    #endif

    /// Yukarı kaydırmak veya yukarı tuşuna basmak açık olan bilgi panelini kapatıyor.
    @objc private func swipedUp() {
        guard tabs.isPanelOpen else { return }
        tabs.close()
        #if os(tvOS)
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        #endif
    }

    #if os(tvOS)
    /// Kapalı arayüzü geri getiren kaydırmalar. Açıkken delege bu jestleri
    /// hiç başlatmıyor.
    @objc private func swipedWhileHidden() {
        guard !isControlsVisible else { return }
        showControls()
    }

    /// Geri tuşu adım adım geri çıkıyor: önce yarım kalan sarma, sonra açık
    /// panel, sonra arayüz — oynatıcı ancak ekranda video dışında hiçbir şey
    /// yokken kapanıyor.
    @objc private func menuPressed() {
        if slider.isScrubbingActive {
            slider.cancelScrubbing()
        } else if channels.isOpen {
            if !channels.handleBack() {
                channels.close()
            }
        } else if tabs.isPanelOpen {
            tabs.close()
        } else if isControlsVisible {
            hideControls()
        } else {
            close()
        }
    }
    #endif

    // MARK: - Kontrollerin görünürlüğü

    @objc private func toggleControls() {
        isControlsVisible ? hideControls() : showControls()
    }

    private var isControlsVisible: Bool { controlsView.alpha > 0 }

    /// Kontroller açıkken altyazının yükseleceği miktar: alt sütunun kapladığı
    /// alan artı bir nefeslik boşluk.
    private var raisedSubtitleInset: CGFloat {
        guard bottomStack.bounds.height > 0 else { return 0 }
        let safeBottom = view.safeAreaLayoutGuide.layoutFrame.maxY
        return max(0, safeBottom - bottomStack.frame.minY + 12)
    }

    private func showControls() {
        // Kontroller gizliyken etiketler güncellenmiyor; görünür olurken
        // son duruma bir kez getiriliyor.
        refreshTimeLabels()
        setControlsVisible(true, duration: 0.2)
        scheduleControlsHide()
    }

    private func refreshTimeLabels() {
        guard !context.isLive else { return }
        applyTimeText(for: currentTime)
        guard duration > 0 else { return }
        slider.value = Float(currentTime / duration)
    }

    /// Solda geçen, sağda kalan süre.
    private func applyTimeText(for elapsed: Double) {
        currentTimeLabel.text = Self.timeText(elapsed)
        remainingLabel.text = "-" + Self.timeText(max(0, duration - elapsed))
    }

    private func hideControls() {
        // Açık bir sekme paneli ya da kanal çekmecesi varken dokunuş arayüzü
        // kapatmıyor; önce onlar kapanıyor.
        guard !isScrubbing else { return }
        if channels.isOpen {
            channels.close()
            return
        }
        if tabs.isPanelOpen {
            tabs.close()
            return
        }
        hideControlsWork?.cancel()
        setControlsVisible(false, duration: 0.2)
    }

    /// Saydamlık tek başına yetmiyor: tvOS'ta görünmez ama etkileşime açık bir
    /// katman odak almaya devam ediyor ve kullanıcı boşlukta gezinmiş oluyor.
    /// Etkileşim kapatılınca içindeki butonlar odak sisteminden de düşüyor.
    private func setControlsVisible(_ visible: Bool, duration: TimeInterval) {
        let wasVisible = isControlsVisible
        controlsView.isUserInteractionEnabled = visible
        UIView.animate(withDuration: duration) {
            self.controlsView.alpha = visible ? 1 : 0
            self.subtitleOverlay.bottomInset = visible ? self.raisedSubtitleInset : 0
            self.subtitleOverlay.layoutIfNeeded()
        }
        #if os(tvOS)
        // Odak yalnızca arayüz kapalıyken açıldığında taşınıyor. Zaten
        // açıkken taşımak, kullanıcıyı bastığı butondan alıp
        // oynat/duraklat'a ışınlıyordu.
        if visible, !wasVisible {
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }
        #endif
    }

    /// Bir sekme paneli ya da kanal çekmecesi açıkken kontroller kendiliğinden
    /// gizlenmiyor: kullanıcı listeye bakıyor olabilir.
    private func scheduleControlsHide() {
        hideControlsWork?.cancel()
        guard !tabs.isPanelOpen, !channels.isOpen else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isPlaying, !self.isScrubbing,
                  !self.tabs.isPanelOpen, !self.channels.isOpen else { return }
            setControlsVisible(false, duration: 0.25)
        }
        hideControlsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.controlsHideDelay, execute: work)
    }

    private static func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

extension PlayerViewController: UIGestureRecognizerDelegate {
    /// tvOS'ta aşağı kaydırma yalnızca gidilecek başka yer yokken paneli
    /// açıyor: panel açıkken odak panele inmeli, ilerleme çubuğu odaktayken de
    /// aşağı inmek denetim satırına geçmek demek.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        #if os(tvOS)
        // Çekmece açıkken kaydırma odak gezinmesinin ve listenin kendi
        // kaydırmasının işi; ekran jestleri araya girmemeli.
        if channels.isOpen { return false }
        if revealSwipes.contains(where: { $0 === gestureRecognizer }) {
            return !isControlsVisible
        }
        if let swipe = gestureRecognizer as? UISwipeGestureRecognizer {
            if swipe.direction == .up {
                return isControlsVisible && tabs.isPanelOpen
            }
            if swipe.direction == .down {
                return isControlsVisible && !tabs.isPanelOpen
            }
        }
        #endif
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Kontrol butonlarına, slider'a ya da sekme paneline dokunurken ekran
        // jestinin araya girmesini engelle.
        if touch.view is UIControl || touch.view?.superview is UIControl {
            return false
        }
        if let touched = touch.view,
           touched.isDescendant(of: tabs.panel) || touched.isDescendant(of: channels.drawer)
        {
            #if os(iOS)
            // Kapatma jesti çekmecenin kendi üstünde de çalışıyor; listenin
            // dikey kaydırmasıyla çakışmıyor.
            if gestureRecognizer === drawerDismissSwipe { return channels.isOpen }
            #endif
            return false
        }
        return true
    }
}

extension PlayerViewController: KSPlayerLayerDelegate {
    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        switch state {
        case .readyToPlay:
            spinner.stopAnimating()
            refreshTrackMenus()
            subtitles.playerBecameReady(layer)
            tabs.setChapters(layer.player.chapters)
        case .bufferFinished:
            spinner.stopAnimating()
            refreshTrackMenus()
        case .buffering, .preparing, .initialized:
            spinner.startAnimating()
        case .error:
            spinner.stopAnimating()
            showFailure(L10n.streamFailed)
        case .paused, .playedToTheEnd:
            spinner.stopAnimating()
        }
    }

    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        // Altyazı kontrollerden bağımsız: sarma sırasında ve arayüz kapalıyken
        // de akmaya devam ediyor.
        subtitles.update(currentTime: currentTime)

        guard !isScrubbing else { return }
        self.currentTime = currentTime
        duration = totalTime.isFinite && totalTime > 0 ? totalTime : 0
        tabs.currentTime = currentTime

        // Uygulama sonlandırılırsa kaldığı yer kaybolmasın.
        if Date().timeIntervalSince(lastProgressSave) >= Self.progressSaveInterval {
            lastProgressSave = Date()
            saveProgress()
        }

        // Geri çağrı saniyede birkaç kez geliyor; kontroller gizliyken
        // görünmeyen etiketleri yeniden çizmenin anlamı yok.
        guard isControlsVisible else { return }
        refreshTimeLabels()
    }

    func player(layer: KSPlayerLayer, finish error: (any Error)?) {
        if let error {
            showFailure(error.localizedDescription)
            return
        }
        // Hatasız bitiş: dizide sıradaki bölüm varsa kendiliğinden geçiyor.
        if nextEpisode != nil {
            playNextEpisode()
        }
    }

    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {}

    private func showFailure(_ message: String) {
        guard !didShowFailure else { return }
        didShowFailure = true

        let alert = UIAlertController(title: context.title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.close, style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}
