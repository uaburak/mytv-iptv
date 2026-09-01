import UIKit

/// Canlı Kanallar, Filmler, Diziler ve İzleme Listem sayfalarının ortak
/// ekranı: solda sayfaya gömülü menü, sağda afiş ızgarası.
///
/// Dört sayfanın düzeni birebir aynı — sabit üst filtre bloğu, altında kayan
/// "Türler" listesi, sağda seçime göre değişen ızgara. Aralarındaki tek fark
/// menünün neyi listelediği ve ızgaranın neyi çözdüğü; ikisi de `Source`'tan
/// geliyor. Dört ayrı ekran yazıldığında aynı düzeltmeyi dört kez yapmak
/// gerekiyordu.
final class BrowseViewController: UIViewController {

    /// Ekranın neyi gezdirdiği.
    enum Source: Hashable {
        case kind(MediaKind)
        case watchlist
    }

    enum SidebarFilter: Hashable {
        case finished
        case continueWatching
        case favorites
        case watchlist
        case category(id: String, name: String)
        /// İzleme listesinde: hepsi.
        case all
        /// İzleme listesinde: tür süzgeci.
        case kind(MediaKind)
        /// Kanallarda: kullanıcının kendi listesi.
        case channelList(id: String, name: String)
        /// Kanallarda: yeni liste kuran satır. Süzgeç değil, eylem — seçilince
        /// ızgara değişmiyor, bir kip açılıyor.
        case createList

        func title(kind: MediaKind) -> String {
            switch self {
            case .finished: return L10n.watched
            case .continueWatching: return L10n.continueWatching
            case .favorites: return L10n.tabFavorites
            case .watchlist: return L10n.myWatchlist
            case let .category(_, name): return name
            case .all: return L10n.allItems
            case let .kind(kind): return kind.title
            case let .channelList(_, name): return name
            case .createList: return L10n.createList
            }
        }

        func symbol(kind: MediaKind) -> String {
            switch self {
            case .finished: return "clock.arrow.circlepath"
            case .continueWatching: return "play.circle"
            case .favorites: return "heart.fill"
            case .watchlist: return "bookmark.fill"
            case let .category(_, name): return Self.categorySymbol(for: name, kind: kind)
            case .all: return "square.grid.2x2.fill"
            case let .kind(kind): return kind.symbol
            case .channelList: return "list.bullet"
            case .createList: return "plus.circle"
            }
        }

        /// Kategori simgesi adından çıkıyor.
        ///
        /// Ad sağlayıcıdan geldiği için sabit bir liste kurulamıyor; anahtar
        /// kelimeye bakılıyor. Eşleşme aksana ve büyük/küçük harfe duyarsız:
        /// "AKSİYON", "Aksiyon" ve "aksiyon" aynı yere düşüyor. Türkçe'de
        /// `lowercased()` tek başına yetmiyor — "İ" küçültülünce birleşik
        /// noktalı bir "i" çıkıyor ve düz "i" ile eşleşmiyor.
        ///
        /// Eşleşmeyen kategori de simgesiz kalmıyor: türün kendi simgesi
        /// devreye giriyor, böylece her satırda bir ikon oluyor.
        private static func categorySymbol(for name: String, kind: MediaKind) -> String {
            let folded = name
                .replacingOccurrences(of: "İ", with: "I")
                .replacingOccurrences(of: "ı", with: "i")
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)

            for (keywords, symbol) in symbolKeywords {
                if keywords.contains(where: { folded.contains($0) }) { return symbol }
            }

            switch kind {
            case .movie: return "film"
            case .series: return "tv"
            case .live: return "antenna.radiowaves.left.and.right"
            }
        }

        /// Anahtar kelimeler aksansız ve küçük harfle yazılı; ad da eşleşmeden
        /// önce aynı hâle getiriliyor. Sıra önemli: yukarıdaki eşleşme kazanır.
        private static let symbolKeywords: [([String], String)] = [
            (["4k", "uhd", "hdr"], "tv.and.mediabox"),
            (["aksiyon", "action", "macera", "adventure"], "flame.fill"),
            (["komedi", "comedy"], "face.smiling.inverse"),
            (["korku", "horror", "gerilim", "thriller"], "moon.stars.fill"),
            (["dram", "drama"], "theatermasks.fill"),
            (["romantik", "romance", "ask "], "heart.circle.fill"),
            (["bilim", "sci-fi", "scifi", "kurgu", "fantastik", "fantasy"], "atom"),
            (["animasyon", "animation", "anime", "cizgi", "cocuk", "kids", "cartoon"], "wand.and.stars"),
            (["belgesel", "documentary", "doga", "nature"], "globe.europe.africa.fill"),
            (["spor", "sport", "futbol", "football", "soccer"], "sportscourt.fill"),
            (["haber", "news"], "newspaper.fill"),
            (["muzik", "music"], "music.note"),
            (["polisiye", "suc", "crime", "gizem", "mystery"], "magnifyingglass.circle.fill"),
            (["savas", "war", "tarih", "history"], "shield.lefthalf.filled"),
            (["western", "kovboy"], "hare.fill"),
            (["yarisma", "reality", "program"], "star.circle.fill"),
            (["yemek", "food", "mutfak"], "fork.knife"),
            (["dini", "islam", "religion"], "moon.fill"),
            (["aile", "family"], "person.2.fill"),
            (["yerli", "ulusal", "turk"], "flag.fill"),
        ]
    }

    private let model: AppModel
    private let source: Source

    /// Izgaranın kart oranı ve ölçüleri bundan geliyor.
    ///
    /// İzleme listesinde yalnızca film ve dizi bulunuyor — kanallar favoride —
    /// ve ikisinin oranı aynı; orada film ölçüsü kullanılıyor.
    private var kind: MediaKind {
        switch source {
        case let .kind(kind): return kind
        case .watchlist: return .movie
        }
    }

    private var sourceTitle: String {
        switch source {
        case let .kind(kind): return kind.title
        case .watchlist: return L10n.myWatchlist
        }
    }

    private var selectedFilter: SidebarFilter = .finished

    // Sol Gömülü Menü
    /// Kırpmayı yapan kap. Kaydırma görünümünün kendisi kırpmıyor (odaklanan
    /// satır çerçevesinin dışına büyüyüp gölge bırakıyor); kırpma bir üst
    /// katmana alınmasa görünen listenin dışında kalan satırlar da çiziliyor ve
    /// sayfanın üstüne — rozetin, ızgaranın üzerine — taşıyor.
    private let sidebarClip = UIView()
    /// Sabit üst blok: filtre satırları ve "TÜRLER" başlığı. Kaymıyor —
    /// listenin neresinde olursan ol bu satırlar bir tuş uzakta.
    private let fixedStack = UIStackView()
    /// Kayan kategorilerin kırpma kabı.
    ///
    /// Kaydırma görünümünün kendisi kırpmıyor — odaklanan satır büyüyüp gölge
    /// bırakıyor ve o taşma görünmeli. Ama üst kenarı serbest bırakınca yukarı
    /// kayan kategoriler sabit bloğun (filtreler ve "TÜRLER" başlığı) üstüne
    /// çiziliyordu. Bu kap tam kaydırma görünümünün üst kenarında kesiyor;
    /// yanlarda ve altta taşma payı duruyor.
    private let categoriesClip = FadingClipView()
    /// Yalnızca kategoriler kayıyor.
    private let sidebarScrollView = UIScrollView()
    private let sidebarStack = UIStackView()
    private var filterViews: [SidebarFilter: SidebarItemView] = [:]
    /// Satırlar yalnızca gerçekten değiştiğinde yeniden kuruluyor.
    private var sidebarSignature = ""
    /// Odak satırdan satıra geçerken ızgarayı geciktiren iş.
    private var pendingFilterWork: DispatchWorkItem?
    /// Menüden ızgaraya köprü kuran kılavuz; yalnızca odak menüdeyken açık.
    private var bridgeGuide: UIFocusGuide?
    private var focusIsInSidebar = false
    private var lastFocusWasInGrid = false
    /// Filtre değişti: ızgaraya dönen odak baştan başlasın.
    private var resetsGridFocus = false

    // Dinamik Kısıtlar
    private var sidebarLeading: NSLayoutConstraint!
    private var sidebarTop: NSLayoutConstraint!
    private var sidebarBottom: NSLayoutConstraint!
    private var collectionTrailing: NSLayoutConstraint!

    // Sağ Izgara
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, MediaItem>!
    private var emptyState: EmptyStateView!

    #if os(tvOS)
    private static let sidebarWidth: CGFloat = 380
    private static let sidebarGap: CGFloat = 32
    /// Menü sütununun sol payı. İçeriğin genel kenar payından (60) dar:
    /// sütun sayfanın kenarına yaslanıyor, ızgara ise kendi payını koruyor.
    private static let sidebarLeadingPadding: CGFloat = 48
    /// Üst pay ekranın tepesinden ölçülüyor, güvenli alandan değil.
    ///
    /// tvOS'ta güvenli alanın üstü gezinme çubuğunu da içeriyor (~147pt);
    /// oraya 135 eklenince menü, sol üstteki bölüm rozetinin çok aşağısında
    /// kalıyordu. Rozet ekranın tepesinden 24pt'de başlayıp ~53pt yer
    /// kapladığı için içerik onun hemen altından, 104pt'den başlıyor.
    private static let contentTopPadding: CGFloat = 104
    private static let contentBottomPadding: CGFloat = 60
    /// Odaklanan satırın büyüme ve gölge payı: kırpan kap listeden bu kadar
    /// taşıyor, kaydırma görünümünün dışına çıkan satırlar burada kesiliyor.
    private static let focusBleed: CGFloat = 24
    /// Kırpma kenarındaki yumuşamanın boyu.
    private static let categoriesFadeHeight: CGFloat = 40
    /// İlk kategorinin kırpma kenarına payı.
    ///
    /// Kabın üst kenarından değil, kaydırma **içeriğinin** üstünden veriliyor:
    /// kap yerinde kalıyor (yumuşama başlığın hemen altında başlıyor) ama ilk
    /// satır o kadar aşağıdan başlıyor. Böylece hem başlıkla arası açılıyor
    /// hem de odaklanınca büyüyen satırın üst kenarı yumuşamanın altında
    /// kalmıyor.
    private static let categoriesTopInset: CGFloat = 8
    #else
    private static let sidebarWidth: CGFloat = 260
    private static let sidebarGap: CGFloat = 20
    private static let contentTopPadding: CGFloat = 16
    private static let contentBottomPadding: CGFloat = 20
    private static let focusBleed: CGFloat = 0
    private static let categoriesFadeHeight: CGFloat = 16
    private static let categoriesTopInset: CGFloat = 4
    #endif

    private var metrics: AppMetrics { AppMetrics.metrics(for: view.bounds.width) }

    init(source: Source, model: AppModel) {
        self.source = source
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = sourceTitle
    }

    convenience init(kind: MediaKind, model: AppModel) {
        self.init(source: .kind(kind), model: model)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        navigationItem.setPrefersLargeTitle(false)
        refreshTitle()

        determineInitialFilter()

        setupLayout()
        setupSidebar()
        setupCollectionView()
        setupDataSource()
        setupEmptyState()
        setupFocusGuides()

        selectFilter(selectedFilter)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(libraryDidChange),
            name: .contentLibraryDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .appLanguageDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(activityDidChange),
            name: .appModelActivityDidChange,
            object: nil
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        #if os(tvOS)
        // Rozetle aynı çizgiden ölçülüyor (bkz. `contentTopPadding`); menü
        // sütunu da ekranın altına kadar iniyor, altta pay bırakmıyor.
        let topPadding = Self.contentTopPadding
        let sidebarBottomPadding: CGFloat = 0
        let sidebarLeadingPadding = Self.sidebarLeadingPadding
        #else
        let topPadding = view.safeAreaInsets.top + Self.contentTopPadding
        let sidebarBottomPadding = view.safeAreaInsets.bottom + Self.contentBottomPadding
        let sidebarLeadingPadding = metrics.screenPadding
        #endif
        let bottomPadding = view.safeAreaInsets.bottom + Self.contentBottomPadding
        let screenPadding = metrics.screenPadding

        sidebarLeading.constant = sidebarLeadingPadding - Self.focusBleed
        sidebarTop.constant = topPadding - Self.focusBleed
        sidebarBottom.constant = Self.focusBleed - sidebarBottomPadding
        collectionTrailing.constant = -screenPadding

        collectionView.contentInset = UIEdgeInsets(
            top: topPadding,
            left: 0,
            bottom: bottomPadding,
            right: 0
        )

        updateCategoriesFade()
    }

    /// Yumuşama yalnızca üstte gerçekten içerik kaldığında var.
    ///
    /// Sabit bir degrade, liste en başındayken ilk kategoriyi de soluk
    /// gösteriyor — hata gibi duruyor. Bu yüzden degradenin boyu kaydırma
    /// miktarıyla açılıyor: liste yerindeyken kesme yok, kaydırma başlar
    /// başlamaz yumuşama beliriyor.
    private func updateCategoriesFade() {
        let scrolled = sidebarScrollView.contentOffset.y
            + sidebarScrollView.adjustedContentInset.top
        let ratio = min(max(scrolled / Self.categoriesFadeHeight, 0), 1)
        categoriesClip.fadeHeight = Self.categoriesFadeHeight * ratio
    }

    #if os(tvOS)
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        guard let collectionView else { return super.preferredFocusEnvironments }
        // Detaydan dönerken odak bıraktığı afişe, menüden gelirken seçili
        // satıra dönüyor. Hep menüye dönseydi izlediği filmden çıkan kullanıcı
        // her seferinde ızgaranın başına atılıyordu.
        if lastFocusWasInGrid, gridItemCount > 0 {
            return [collectionView]
        }
        if let currentView = filterViews[selectedFilter] {
            return [currentView, sidebarScrollView, collectionView]
        }
        return [collectionView]
    }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard let next = context.nextFocusedView else { return }
        focusIsInSidebar = next.isDescendant(of: sidebarClip)
        lastFocusWasInGrid = next.isDescendant(of: collectionView)
        updateBridgeGuide()
    }
    #endif

    private func refreshTitle() {
        title = sourceTitle
        #if os(tvOS)
        navigationItem.title = ""
        #endif
    }

    private func determineInitialFilter() {
        // İzleme listesinde her şey tek listede; süzgeç isteğe bağlı.
        if case .watchlist = source {
            selectedFilter = .all
            return
        }
        // Canlı kanallarda "izlemeye devam / bitirdiklerim" satırları yok;
        // oraya düşen bir seçim menüde karşılığı olmayan bir filtre bırakıyor.
        guard kind != .live else {
            selectedFilter = categories.first.map { .category(id: $0.id, name: $0.name) } ?? .favorites
            return
        }

        let continueItems = resolveItems(for: .continueWatching)
        if !continueItems.isEmpty {
            selectedFilter = .continueWatching
            return
        }
        let finishedItems = resolveItems(for: .finished)
        if !finishedItems.isEmpty {
            selectedFilter = .finished
            return
        }
        if let firstCategory = categories.first {
            selectedFilter = .category(id: firstCategory.id, name: firstCategory.name)
        } else {
            // Menüde favori satırı yok; boşa düşen bir seçim bırakılmıyor.
            selectedFilter = .watchlist
        }
    }

    private var categories: [MediaCategory] {
        guard case .kind = source else { return [] }
        return model.library.categories[kind] ?? []
    }

    /// Sabit üst bloktaki satırlar.
    private var topFilters: [SidebarFilter] {
        switch source {
        case .kind(.live):
            // Favoriler, sonra kullanıcının kendi listeleri, en altta da yeni
            // liste kuran satır.
            return [.favorites]
                + model.activity.channelLists.map { .channelList(id: $0.id, name: $0.name) }
                + [.createList]
        case .kind: return [.continueWatching, .watchlist, .finished]
        // İzleme listesi sayfası da "benim listem" mantığında: kaydettiklerim
        // ve izlediklerim yan yana.
        case .watchlist: return [.all, .finished]
        }
    }

    /// Kayan bölümdeki satırlar: tür sayfalarında kategoriler, izleme
    /// listesinde içerik türleri. İkisi de aynı yuvayı dolduruyor.
    private var scrollingFilters: [SidebarFilter] {
        switch source {
        case .kind:
            return categories.map { .category(id: $0.id, name: $0.name) }
        case .watchlist:
            // Boş tür satırı gösterilmiyor: izleme listesinde dizi yoksa
            // "Diziler (0)" satırı kullanıcıya bir şey vaat edip boş açılıyor.
            return [MediaKind.movie, .series, .live]
                .filter { !resolveItems(for: .kind($0)).isEmpty }
                .map { .kind($0) }
        }
    }

    private func countText(for filter: SidebarFilter) -> String {
        "(\(resolveItems(for: filter).count.formatted()))"
    }

    /// Sayılar satırlar yeniden kurulmadan tazeleniyor: kütüphane
    /// güncellendiğinde odak listede kalıyor.
    private func refreshRowCounts() {
        for (filter, itemView) in filterViews {
            switch filter {
            case .category, .kind, .channelList:
                itemView.detail = countText(for: filter)
            default:
                break
            }
        }
    }

    @objc private func libraryDidChange() {
        setupSidebar()
        refreshRowCounts()
        // Kaydırma korunuyor: kullanıcı ızgaranın ortasındayken arka planda
        // gelen bir güncelleme onu başa atmasın.
        commitFilter(reloading: false, resettingScroll: false)
    }

    /// Favori / izleme listesi değişti. Yalnızca o listeleri gösteren
    /// süzgeçlerde ızgara tazeleniyor: kategoriye bakan kullanıcının önünde
    /// boşuna iş yapılmıyor.
    @objc private func activityDidChange() {
        // İzleme listesi sayfasında menünün kendisi de listeden besleniyor:
        // tür satırları gelip gidiyor, sayılar değişiyor.
        if case .watchlist = source {
            setupSidebar()
            refreshRowCounts()
            commitFilter(reloading: false, resettingScroll: false)
            return
        }
        // Liste satırları ve sayıları izleme kaydından besleniyor; satırlar
        // gerçekten değişmediyse `setupSidebar` zaten erken dönüyor.
        setupSidebar()
        refreshRowCounts()

        switch selectedFilter {
        case .favorites, .watchlist, .finished, .continueWatching, .channelList:
            commitFilter(reloading: false, resettingScroll: false)
        case .category, .all, .kind, .createList:
            break
        }
    }

    @objc private func languageDidChange() {
        refreshTitle()
        setupSidebar(force: true)
        commitFilter(reloading: false, resettingScroll: false)
    }

    // MARK: - Düzen Kurulumu

    private func setupLayout() {
        sidebarClip.clipsToBounds = true
        sidebarClip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebarClip)

        fixedStack.axis = .vertical
        fixedStack.spacing = 6
        fixedStack.alignment = .fill
        fixedStack.clipsToBounds = false
        fixedStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarClip.addSubview(fixedStack)

        sidebarScrollView.showsVerticalScrollIndicator = false
        sidebarScrollView.showsHorizontalScrollIndicator = false
        sidebarScrollView.clipsToBounds = false
        sidebarScrollView.contentInsetAdjustmentBehavior = .never
        sidebarScrollView.contentInset = UIEdgeInsets(
            top: Self.categoriesTopInset, left: 0, bottom: 0, right: 0
        )
        sidebarScrollView.delegate = self
        categoriesClip.translatesAutoresizingMaskIntoConstraints = false
        sidebarClip.addSubview(categoriesClip)

        sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false
        categoriesClip.addSubview(sidebarScrollView)

        sidebarStack.axis = .vertical
        sidebarStack.spacing = 6
        sidebarStack.alignment = .fill
        sidebarStack.clipsToBounds = false
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarScrollView.addSubview(sidebarStack)

        // Kısıtlar kırpan kaba bağlanıyor; kap listeden her yönde `focusBleed`
        // kadar geniş, kaydırma görünümü onun içinde aynı payla oturuyor.
        // Böylece satırın büyümesi ve gölgesi görünüyor, listenin görünen
        // bölümünün dışı kesiliyor.
        let bleed = Self.focusBleed
        sidebarLeading = sidebarClip.leadingAnchor.constraint(
            equalTo: view.leadingAnchor, constant: 60 - bleed
        )
        sidebarTop = sidebarClip.topAnchor.constraint(
            equalTo: view.topAnchor, constant: Self.contentTopPadding - bleed
        )
        sidebarBottom = sidebarClip.bottomAnchor.constraint(
            equalTo: view.bottomAnchor, constant: -(60 - bleed)
        )

        NSLayoutConstraint.activate([
            sidebarLeading,
            sidebarTop,
            sidebarBottom,
            sidebarClip.widthAnchor.constraint(equalToConstant: Self.sidebarWidth + bleed * 2),

            fixedStack.leadingAnchor.constraint(equalTo: sidebarClip.leadingAnchor, constant: bleed),
            fixedStack.trailingAnchor.constraint(equalTo: sidebarClip.trailingAnchor, constant: -bleed),
            fixedStack.topAnchor.constraint(equalTo: sidebarClip.topAnchor, constant: bleed),

            // Kap yanlarda ve altta payı koruyor, üstte tam kaydırma
            // görünümünün kenarında kesiyor.
            categoriesClip.leadingAnchor.constraint(equalTo: sidebarClip.leadingAnchor),
            categoriesClip.trailingAnchor.constraint(equalTo: sidebarClip.trailingAnchor),
            categoriesClip.topAnchor.constraint(equalTo: fixedStack.bottomAnchor),
            categoriesClip.bottomAnchor.constraint(equalTo: sidebarClip.bottomAnchor),

            sidebarScrollView.leadingAnchor.constraint(equalTo: categoriesClip.leadingAnchor, constant: bleed),
            sidebarScrollView.trailingAnchor.constraint(equalTo: categoriesClip.trailingAnchor, constant: -bleed),
            sidebarScrollView.topAnchor.constraint(equalTo: categoriesClip.topAnchor),
            sidebarScrollView.bottomAnchor.constraint(equalTo: categoriesClip.bottomAnchor, constant: -bleed),

            sidebarStack.leadingAnchor.constraint(equalTo: sidebarScrollView.contentLayoutGuide.leadingAnchor),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebarScrollView.contentLayoutGuide.trailingAnchor),
            sidebarStack.topAnchor.constraint(equalTo: sidebarScrollView.contentLayoutGuide.topAnchor),
            sidebarStack.bottomAnchor.constraint(equalTo: sidebarScrollView.contentLayoutGuide.bottomAnchor),
            sidebarStack.widthAnchor.constraint(equalTo: sidebarScrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    /// Menü satırları yalnızca gerçekten değiştiğinde yeniden kuruluyor.
    ///
    /// Kütüphane bildirimi sık geliyor; her seferinde satırları söküp yeniden
    /// eklemek odağı düşürüyor ve kullanıcı listenin başına atılıyordu.
    private func setupSidebar(force: Bool = false) {
        let top = topFilters
        let scrolling = scrollingFilters

        let signature = (top + scrolling)
            .map { "\($0)" }
            .joined(separator: "\n")
        guard force || signature != sidebarSignature || fixedStack.arrangedSubviews.isEmpty else {
            return
        }
        sidebarSignature = signature

        for stack in [fixedStack, sidebarStack] {
            stack.arrangedSubviews.forEach { subview in
                stack.removeArrangedSubview(subview)
                subview.removeFromSuperview()
            }
        }
        filterViews.removeAll()

        // 1. Sabit filtre satırları.
        for filter in top {
            // Sayı yalnızca bir listeyi temsil eden satırlarda; "Liste Oluştur"
            // bir liste değil.
            let detail: String?
            if case .channelList = filter {
                detail = countText(for: filter)
            } else {
                detail = nil
            }
            fixedStack.addArrangedSubview(
                makeRow(for: filter, title: filter.title(kind: kind), detail: detail)
            )
        }

        // 2. "TÜRLER" / "KATEGORİLER" başlığı. Kayan bölümün başlığı ama
        // kendisi sabit blokta: listeyle kaysaydı kullanıcı kategorilerin
        // arasındayken neye baktığını gösteren tek şey ekrandan çıkardı.
        // Altında satır yoksa başlık da yok: boş bir "TÜRLER" bir şey vaat
        // edip hiçbir şey göstermiyor.
        if !scrolling.isEmpty {
            if let last = fixedStack.arrangedSubviews.last {
                fixedStack.setCustomSpacing(20, after: last)
            }
            fixedStack.addArrangedSubview(makeSectionHeader())
        }

        // 3. Kayan satırlar: kategoriler ya da içerik türleri.
        for filter in scrolling {
            sidebarStack.addArrangedSubview(
                makeRow(
                    for: filter,
                    title: filter.title(kind: kind),
                    detail: countText(for: filter)
                )
            )
        }

        // Seçili filtre listeden düşmüş olabilir (kategoriler sonradan geldi).
        if filterViews[selectedFilter] == nil {
            determineInitialFilter()
            for (filter, itemView) in filterViews {
                itemView.isCurrent = (filter == selectedFilter)
            }
        }
    }

    private func makeSectionHeader() -> UIView {
        let headerLabel = UILabel()
        headerLabel.text = kind == .live ? L10n.categories : L10n.genres
        #if os(tvOS)
        headerLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        #else
        headerLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        #endif
        headerLabel.textColor = AppPalette.secondaryText

        let headerContainer = UIView()
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(headerLabel)

        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(
                equalTo: headerContainer.leadingAnchor, constant: SidebarRowGeometry.pillInset
            ),
            headerLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            headerLabel.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 10),
            headerLabel.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -6),
        ])
        return headerContainer
    }

    private func makeRow(
        for filter: SidebarFilter, title: String, detail: String?
    ) -> SidebarItemView {
        let itemView = SidebarItemView()
        itemView.configure(symbol: filter.symbol(kind: kind), title: title, detail: detail)
        itemView.isCurrent = (filter == selectedFilter)
        // Odak satıra gelince ızgara değişiyor (Apple TV deseni), tıklanınca
        // odak ızgaraya geçiyor: liste bir filtre, varış noktası içerik.
        if case .channelList = filter {
            // Kurduğu listeyi kaldıramamak tuzak. Kanal kartındaki jestin
            // aynısı: satıra basılı tut, menü gelsin.
            itemView.addInteraction(UIContextMenuInteraction(delegate: self))
        }

        if case .createList = filter {
            // Odakla ızgarayı değiştirmiyor: bu satır bir liste değil, bir
            // eylem. Seçilince kip açılıyor.
            itemView.onSelect = { [weak self] in self?.presentCreateList() }
        } else {
            itemView.onFocus = { [weak self] in self?.focusFilter(filter) }
            itemView.onSelect = { [weak self] in self?.commitFilterAndFocusGrid(filter) }
        }
        filterViews[filter] = itemView
        return itemView
    }

    private func setupCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] _, environment in
            guard let self else { return nil }
            let container = environment.container.contentSize
            let metrics = AppMetrics.metrics(for: container.width)
            return MediaSectionLayout.posterGrid(
                kind: self.kind,
                containerWidth: container.width,
                metrics: metrics,
                showsHeader: false
            )
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.isPrefetchingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.applyNativeScrollEdges()
        #if os(tvOS)
        // Detaydan dönen kullanıcı bıraktığı afişi buluyor.
        collectionView.remembersLastFocusedIndexPath = true
        #endif

        collectionView.register(PosterCell.self, forCellWithReuseIdentifier: PosterCell.reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        collectionTrailing = collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(
                equalTo: sidebarScrollView.trailingAnchor, constant: Self.sidebarGap
            ),
            collectionTrailing,
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Int, MediaItem>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, media in
            guard let self else { return nil }
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: PosterCell.reuseID, for: indexPath
            ) as! PosterCell
            
            let progressEntry: PlaybackProgress?
            if self.selectedFilter == .continueWatching {
                progressEntry = self.model.activity.latestProgress(for: media.id)
            } else {
                progressEntry = nil
            }
            
            cell.configure(item: media, metrics: self.metrics, progress: progressEntry)
            return cell
        }
    }

    private func setupEmptyState() {
        emptyState = EmptyStateView.installed(in: view, centeredOn: collectionView)
    }

    private func setupFocusGuides() {
        #if os(tvOS)
        // Menüdeki satır ile ızgaradaki afişler aynı hizada olmayabiliyor; bu
        // kılavuz sağa basıldığında odağın aradaki boşluğa düşmesini önlüyor.
        //
        // Ama yalnızca odak menüdeyken açık kalmalı: kılavuzun yönü yok, iki
        // yönde de çalışıyor. Sürekli açık bırakıldığında ızgaranın ilk
        // sütunundan sola basan odak kılavuza düşüyor, kılavuz da onu ızgaraya
        // geri yolluyordu — menüye hiç çıkılamıyordu.
        let guide = UIFocusGuide()
        view.addLayoutGuide(guide)

        NSLayoutConstraint.activate([
            guide.leadingAnchor.constraint(equalTo: sidebarScrollView.trailingAnchor),
            guide.trailingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            guide.topAnchor.constraint(equalTo: view.topAnchor),
            guide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        guide.preferredFocusEnvironments = [collectionView]
        guide.isEnabled = false
        bridgeGuide = guide
        #endif
    }

    /// Köprü kılavuzu yalnızca odak menüdeyken ve ızgarada gidilecek bir şey
    /// varken açık.
    private func updateBridgeGuide() {
        #if os(tvOS)
        bridgeGuide?.isEnabled = focusIsInSidebar && gridItemCount > 0
        #endif
    }

    private var gridItemCount: Int {
        dataSource?.snapshot().numberOfItems ?? 0
    }

    // MARK: - Filtre Seçimi ve Veri Çözümleme

    private func selectFilter(_ filter: SidebarFilter) {
        pendingFilterWork?.cancel()
        pendingFilterWork = nil
        markSelected(filter)
        commitFilter(reloading: true, resettingScroll: true)
    }

    /// Odak menüde gezerken ızgara hemen değil, kısa bir duraklamadan sonra
    /// yenileniyor: satırlar arasında hızla geçerken her adımda koca bir
    /// ızgarayı kurup atmanın anlamı yok. Satırın seçili görünümü ise anında
    /// değişiyor — kullanıcı beklemiyor.
    private func focusFilter(_ filter: SidebarFilter) {
        guard filter != selectedFilter else { return }
        markSelected(filter)

        pendingFilterWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.commitFilter(reloading: true, resettingScroll: true)
        }
        pendingFilterWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    /// Satıra tıklandığında bekleme yok: ızgara hemen kuruluyor ve odak oraya
    /// geçiyor. Menü bir filtre, varış noktası içerik.
    private func commitFilterAndFocusGrid(_ filter: SidebarFilter) {
        pendingFilterWork?.cancel()
        pendingFilterWork = nil
        markSelected(filter)
        commitFilter(reloading: true, resettingScroll: true)

        #if os(tvOS)
        guard gridItemCount > 0 else { return }
        lastFocusWasInGrid = true
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        #endif
    }

    /// Yeni liste kipi.
    ///
    /// Ad boş bırakılırsa liste yine kuruluyor: kullanıcıyı adlandırmaya
    /// zorlamanın bir karşılığı yok, adı sonradan da değişebilir.
    private func presentCreateList() {
        let alert = UIAlertController(
            title: L10n.createList,
            message: L10n.channelListName,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = L10n.channelListNamePlaceholder
            #if os(iOS)
            field.autocapitalizationType = .words
            #endif
        }
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.create, style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let typed = (alert?.textFields?.first?.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let list = model.activity.createChannelList(
                named: typed.isEmpty ? L10n.newListDefaultName : typed
            )
            adoptNewList(list)
        })
        present(alert, animated: true)
    }

    /// Yeni liste menüye giriyor, seçiliyor ve odak ona gidiyor: kullanıcı
    /// listeyi kurduğu anda içindeymiş gibi oluyor.
    private func adoptNewList(_ list: ChannelList) {
        setupSidebar(force: true)
        selectFilter(.channelList(id: list.id, name: list.name))
        #if os(tvOS)
        lastFocusWasInGrid = false
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        #endif
    }

    /// Listeyi siliyor.
    ///
    /// Menüyü ve seçili satırı depo bildirimi zaten tazeliyor; ızgara burada
    /// elle çözülüyor çünkü seçim silinen listeden başka bir satıra düşmüş
    /// olabiliyor ve bildirim yolu yalnızca **aynı** seçimi yeniliyor.
    private func deleteChannelList(id: String) {
        model.activity.deleteChannelList(id: id)
        commitFilter(reloading: true, resettingScroll: true)
        #if os(tvOS)
        lastFocusWasInGrid = false
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        #endif
    }

    private func markSelected(_ filter: SidebarFilter) {
        selectedFilter = filter
        for (candidate, itemView) in filterViews {
            itemView.isCurrent = (candidate == filter)
        }
    }

    private func commitFilter(reloading: Bool, resettingScroll: Bool) {
        let filter = selectedFilter
        let items = resolveItems(for: filter)
        applyGridItems(items, reloading: reloading)
        updateEmptyState(for: filter, isEmpty: items.isEmpty)
        updateBridgeGuide()

        guard resettingScroll, collectionView.numberOfSections > 0 else { return }
        resetsGridFocus = true
        collectionView.setContentOffset(
            CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false
        )
    }

    /// İzleme kaydından beslenen satırlar (İzlediklerim, İzlemeye Devam Et)
    /// hangi türleri toplayacak?
    ///
    /// Tür sayfasında yalnızca o tür. İzleme listesi sayfasında film ve dizi
    /// birlikte — ama kanal değil: kanalların kart oranı başka ve tek ızgarada
    /// afişle yan yana duramıyorlar.
    private func matchesSource(_ itemKind: MediaKind) -> Bool {
        switch source {
        case let .kind(kind): return itemKind == kind
        case .watchlist: return itemKind != .live
        }
    }

    private func resolveItems(for filter: SidebarFilter) -> [MediaItem] {
        switch filter {
        case .finished:
            let ids = model.activity.progress
                .filter { $0.isFinished && matchesSource($0.mediaID.kind) }
                .sorted { $0.updatedAt > $1.updatedAt }
                .map(\.mediaID)
            var seen = Set<MediaID>()
            return ids.filter { seen.insert($0).inserted }.compactMap { model.library.item(for: $0) }

        case .continueWatching:
            let ids = model.activity.continueWatching
                .filter { matchesSource($0.mediaID.kind) }
                .map(\.mediaID)
            var seen = Set<MediaID>()
            return ids.filter { seen.insert($0).inserted }.compactMap { model.library.item(for: $0) }

        case .favorites:
            let ids = model.activity.favoriteIDs.filter { $0.kind == kind }
            return ids.compactMap { model.library.item(for: $0) }

        case .watchlist:
            let ids = model.activity.watchlistIDs.filter { $0.kind == kind }
            return ids.compactMap { model.library.item(for: $0) }

        case let .category(id, _):
            return model.library.items(kind: kind, categoryID: id)

        case .all:
            return model.activity.watchlistIDs.compactMap { model.library.item(for: $0) }

        case let .kind(kind):
            return model.activity.watchlistIDs
                .filter { $0.kind == kind }
                .compactMap { model.library.item(for: $0) }

        case let .channelList(id, _):
            return model.activity.channelIDs(inList: id)
                .compactMap { model.library.item(for: $0) }

        case .createList:
            return []
        }
    }

    private func applyGridItems(_ items: [MediaItem], reloading: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, MediaItem>()
        snapshot.appendSections([0])
        var seen = Set<MediaID>()
        let uniqueItems = items.filter { seen.insert($0.id).inserted }
        snapshot.appendItems(uniqueItems, toSection: 0)

        if reloading {
            // Kategori değişiminde ızgaranın tamamı değişiyor. Binlerce öğeyi
            // eskisiyle karşılaştırıp farkı canlandırmanın bir karşılığı yok;
            // geçişleri tutuklaştıran da buydu. Doğrudan yeniden çiziliyor.
            dataSource.applySnapshotUsingReloadData(snapshot)
        } else {
            // Arka planda gelen kütüphane güncellemesi: fark hesaplanıyor ama
            // canlandırılmıyor, böylece odak bulunduğu kartta kalıyor.
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    private func updateEmptyState(for filter: SidebarFilter, isEmpty: Bool) {
        guard isEmpty else {
            emptyState.isHidden = true
            return
        }

        let symbol: String
        let title: String
        let message: String

        switch filter {
        case .finished:
            symbol = "clock.arrow.circlepath"
            title = L10n.watched
            message = isTurkish ? "Henüz izleyip bitirdiğiniz bir içerik yok." : "No watched content yet."
        case .continueWatching:
            symbol = "play.circle"
            title = L10n.continueWatching
            message = isTurkish ? "Yarım kalan bir izleme kaydınız bulunmuyor." : "No in-progress content."
        case .favorites:
            symbol = "heart.fill"
            title = L10n.tabFavorites
            message = isTurkish ? "Favorilerinize henüz içerik eklemediniz." : "No favorites added yet."
        case .watchlist:
            symbol = "bookmark.fill"
            title = L10n.myWatchlist
            message = isTurkish ? "İzleme listenizde henüz içerik yok." : "No items in your watchlist."
        case let .category(_, name):
            symbol = "tray"
            title = name
            message = L10n.categoryEmpty
        case .all:
            symbol = "bookmark"
            title = L10n.watchlistEmptyTitle
            message = L10n.watchlistEmptyMessage
        case let .kind(kind):
            symbol = "bookmark"
            title = kind.title
            message = L10n.watchlistEmptyMessage
        case let .channelList(_, name):
            symbol = "list.bullet"
            title = name
            message = isTurkish
                ? "Bu liste boş. Bir kanala basılı tutup \"Listeye Ekle\" ile ekleyebilirsiniz."
                : "This list is empty. Long-press a channel and choose \"Add to List\"."
        case .createList:
            symbol = "plus.circle"
            title = L10n.createList
            message = ""
        }

        emptyState.configure(symbol: symbol, title: title, message: message)
        emptyState.isHidden = false
    }

    private var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier.lowercased().hasPrefix("tr") ?? true
    }

    // MARK: - Gezinme ve Oynatma

    private func openDetail(_ item: MediaItem, sourceView: UIView? = nil) {
        guard item.kind != .live else {
            Task { await model.play(item) }
            return
        }
        let controller = DetailViewController(item: item, model: model)
        controller.applyZoomTransition(from: sourceView)
        navigationController?.pushViewController(controller, animated: true)
    }
}

// MARK: - UICollectionViewDelegate

extension BrowseViewController: UICollectionViewDelegate {
    #if os(tvOS)
    /// Filtre değiştiğinde ızgara baştan başlıyor. `remembersLastFocusedIndexPath`
    /// eski listedeki sırayı hatırlıyor; yeni listede o sıra bambaşka bir afiş
    /// oluyordu.
    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        guard resetsGridFocus else { return nil }
        resetsGridFocus = false
        guard collectionView.numberOfSections > 0,
              collectionView.numberOfItems(inSection: 0) > 0 else { return nil }
        return IndexPath(item: 0, section: 0)
    }
    #endif

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        #if os(tvOS)
        collectionView.unclipFocusGrowth(around: cell)
        #endif
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === sidebarScrollView else { return }
        updateCategoriesFade()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        openDetail(item, sourceView: collectionView.cellForItem(at: indexPath))
    }

    /// Karta uzun basınca çıkan menü. Uzun basışı sistem karşılıyor; kartın
    /// kendi seçimiyle çakışmıyor.
    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1,
              let indexPath = indexPaths.first,
              let item = dataSource.itemIdentifier(for: indexPath)
        else { return nil }
        return MediaCardMenu.configuration(for: item, model: model) { [weak self] item in
            self?.openDetail(item)
        }
    }
}

// MARK: - UICollectionViewDataSourcePrefetching

extension BrowseViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        let items = indexPaths.compactMap { dataSource.itemIdentifier(for: $0) }
        MediaPrefetch.warm(items, posterWidth: metrics.cardWidth(for: kind))
    }
}

/// Üst kenarı yumuşayarak kesen kırpma kabı.
///
/// Maske **burada** duruyor, dışarıdan takılmıyor: dışarıdan takılan bir
/// maskenin çerçevesi kabın ölçüsünden önce kurulabiliyor ve çerçevesi sıfır
/// olan bir maske bütün içeriği gizliyor — kategoriler odaklanabilir ama
/// görünmez kalıyordu. Burada çerçeve kabın kendi `layoutSubviews`'ünde
/// kuruluyor, yani ölçü ne zaman oturursa maske de o zaman doğru.
private final class FadingClipView: UIView {
    private let fade = CAGradientLayer()

    /// Yumuşamanın boyu (punto). Sıfırken maske hiç takılmıyor.
    var fadeHeight: CGFloat = 0 {
        didSet {
            guard abs(oldValue - fadeHeight) > 0.5 else { return }
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        fade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
        fade.startPoint = CGPoint(x: 0.5, y: 0)
        fade.endPoint = CGPoint(x: 0.5, y: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard fadeHeight > 0.5, bounds.height > 0 else {
            layer.mask = nil
            return
        }
        if layer.mask !== fade { layer.mask = fade }

        // Katman kısıt tanımıyor; örtük animasyon kapalı, yoksa degrade her
        // düzen turunda kayarak yerine oturuyor.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        fade.locations = [0, NSNumber(value: Double(min(fadeHeight / bounds.height, 1)))]
        CATransaction.commit()
    }
}

// MARK: - Liste satırının menüsü

extension BrowseViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let row = interaction.view as? SidebarItemView,
              let filter = filterViews.first(where: { $0.value === row })?.key,
              case let .channelList(id, _) = filter
        else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [
                UIAction(
                    title: L10n.deleteList,
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.deleteChannelList(id: id)
                },
            ])
        }
    }
}
