import UIKit

/// Filmler, Diziler ve Canlı Kanallar için Apple TV tarzı gömülü sol menülü (in-page sidebar) gezinme ekranı.
///
/// Sol tarafta uygulamanın genel sidebar butonlarıyla birebir aynı stilde butonlar
/// (Son İzlediklerim, İzlemeye Devam Et, Favoriler, İzleme Listem ve Türler/Kategoriler),
/// sağ tarafta ise seçili olan filtrenin/kategorinin dinamik afiş ızgarası yer alır.
final class KindBrowseViewController: UIViewController {

    enum SidebarFilter: Hashable {
        case finished
        case continueWatching
        case favorites
        case watchlist
        case category(id: String, name: String)

        func title(kind: MediaKind) -> String {
            switch self {
            case .finished: return L10n.recentlyWatched
            case .continueWatching: return L10n.continueWatching
            case .favorites: return L10n.tabFavorites
            case .watchlist: return L10n.myWatchlist
            case let .category(_, name): return name
            }
        }

        func symbol(kind: MediaKind) -> String {
            switch self {
            case .finished: return "clock.arrow.circlepath"
            case .continueWatching: return "play.circle"
            case .favorites: return "heart.fill"
            case .watchlist: return "bookmark.fill"
            case let .category(_, name): return Self.categorySymbol(for: name, kind: kind)
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
    private let kind: MediaKind

    private var selectedFilter: SidebarFilter = .finished

    // Sol Gömülü Menü
    /// Kırpmayı yapan kap. Kaydırma görünümünün kendisi kırpmıyor (odaklanan
    /// satır çerçevesinin dışına büyüyüp gölge bırakıyor); kırpma bir üst
    /// katmana alınmasa görünen listenin dışında kalan satırlar da çiziliyor ve
    /// sayfanın üstüne — rozetin, ızgaranın üzerine — taşıyor.
    private let sidebarClip = UIView()
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
    #else
    private static let sidebarWidth: CGFloat = 260
    private static let sidebarGap: CGFloat = 20
    private static let contentTopPadding: CGFloat = 16
    private static let contentBottomPadding: CGFloat = 20
    private static let focusBleed: CGFloat = 0
    #endif

    private var metrics: AppMetrics { AppMetrics.metrics(for: view.bounds.width) }

    init(kind: MediaKind, model: AppModel) {
        self.kind = kind
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = kind.title
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
            name: .appModelFavoritesDidChange,
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
        title = kind.title
        #if os(tvOS)
        navigationItem.title = ""
        #endif
    }

    private func determineInitialFilter() {
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
            selectedFilter = .favorites
        }
    }

    private var categories: [MediaCategory] {
        model.library.categories[kind] ?? []
    }

    private func countText(forCategory id: String) -> String {
        "(\(model.library.items(kind: kind, categoryID: id).count.formatted()))"
    }

    /// Sayılar satırlar yeniden kurulmadan tazeleniyor: kütüphane
    /// güncellendiğinde odak listede kalıyor.
    private func refreshCategoryCounts() {
        for (filter, itemView) in filterViews {
            guard case let .category(id, _) = filter else { continue }
            itemView.detail = countText(forCategory: id)
        }
    }

    @objc private func libraryDidChange() {
        setupSidebar()
        refreshCategoryCounts()
        // Kaydırma korunuyor: kullanıcı ızgaranın ortasındayken arka planda
        // gelen bir güncelleme onu başa atmasın.
        commitFilter(reloading: false, resettingScroll: false)
    }

    /// Favori / izleme listesi değişti. Yalnızca o listeleri gösteren
    /// süzgeçlerde ızgara tazeleniyor: kategoriye bakan kullanıcının önünde
    /// boşuna iş yapılmıyor.
    @objc private func activityDidChange() {
        switch selectedFilter {
        case .favorites, .watchlist, .finished, .continueWatching:
            commitFilter(reloading: false, resettingScroll: false)
        case .category:
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

        sidebarScrollView.showsVerticalScrollIndicator = false
        sidebarScrollView.showsHorizontalScrollIndicator = false
        sidebarScrollView.clipsToBounds = false
        sidebarScrollView.contentInsetAdjustmentBehavior = .never
        sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false
        sidebarClip.addSubview(sidebarScrollView)

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

            sidebarScrollView.leadingAnchor.constraint(equalTo: sidebarClip.leadingAnchor, constant: bleed),
            sidebarScrollView.trailingAnchor.constraint(equalTo: sidebarClip.trailingAnchor, constant: -bleed),
            sidebarScrollView.topAnchor.constraint(equalTo: sidebarClip.topAnchor, constant: bleed),
            sidebarScrollView.bottomAnchor.constraint(equalTo: sidebarClip.bottomAnchor, constant: -bleed),

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
        // 1. Özel Filtre Butonları (Son İzlediklerim, İzlemeye Devam Et, Favoriler, İzleme Listem)
        let topFilters: [SidebarFilter]
        if kind == .live {
            topFilters = [.favorites, .watchlist]
        } else {
            topFilters = [.finished, .continueWatching, .favorites, .watchlist]
        }

        let signature = (topFilters.map { $0.title(kind: kind) }
            + categories.map { "\($0.id)|\($0.name)" }).joined(separator: "\n")
        guard force || signature != sidebarSignature || sidebarStack.arrangedSubviews.isEmpty else {
            return
        }
        sidebarSignature = signature

        sidebarStack.arrangedSubviews.forEach { subview in
            sidebarStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        filterViews.removeAll()

        for filter in topFilters {
            sidebarStack.addArrangedSubview(
                makeRow(for: filter, title: filter.title(kind: kind), detail: nil)
            )
        }

        // 2. "TÜRLER" / "KATEGORİLER" Başlık Etiketi
        if let last = sidebarStack.arrangedSubviews.last {
            sidebarStack.setCustomSpacing(20, after: last)
        }

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
        sidebarStack.addArrangedSubview(headerContainer)
        sidebarStack.setCustomSpacing(6, after: headerContainer)

        // 3. Sunucudan Gelen Kategori Butonları
        for category in categories {
            let filter = SidebarFilter.category(id: category.id, name: category.name)
            sidebarStack.addArrangedSubview(
                makeRow(for: filter, title: category.name, detail: countText(forCategory: category.id))
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

    private func makeRow(
        for filter: SidebarFilter, title: String, detail: String?
    ) -> SidebarItemView {
        let itemView = SidebarItemView()
        itemView.configure(symbol: filter.symbol(kind: kind), title: title, detail: detail)
        itemView.isCurrent = (filter == selectedFilter)
        // Odak satıra gelince ızgara değişiyor (Apple TV deseni), tıklanınca
        // odak ızgaraya geçiyor: liste bir filtre, varış noktası içerik.
        itemView.onFocus = { [weak self] in self?.focusFilter(filter) }
        itemView.onSelect = { [weak self] in self?.commitFilterAndFocusGrid(filter) }
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

    private func resolveItems(for filter: SidebarFilter) -> [MediaItem] {
        switch filter {
        case .finished:
            let ids = model.activity.progress
                .filter { $0.isFinished && $0.mediaID.kind == kind }
                .sorted { $0.updatedAt > $1.updatedAt }
                .map(\.mediaID)
            var seen = Set<MediaID>()
            return ids.filter { seen.insert($0).inserted }.compactMap { model.library.item(for: $0) }

        case .continueWatching:
            let ids = model.activity.continueWatching
                .filter { $0.mediaID.kind == kind }
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
            title = L10n.recentlyWatched
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

extension KindBrowseViewController: UICollectionViewDelegate {
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

extension KindBrowseViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        let items = indexPaths.compactMap { dataSource.itemIdentifier(for: $0) }
        MediaPrefetch.warm(items, posterWidth: metrics.cardWidth(for: kind))
    }
}
