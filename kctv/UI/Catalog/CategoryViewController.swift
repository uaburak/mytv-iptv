import UIKit

/// Bir kategorinin kendi sayfası — anasayfanın düzeni, tek kategorinin içeriği.
///
/// Anasayfadaki kategori rayının başındaki kart buraya açılıyor. Rayda
/// kategorinin yalnızca ilk 24 içeriği var; burada tamamı.
///
/// Düzen anasayfayla aynı: tepede aynı banner (`HeroCell`, ölçüsü de
/// `HeroSectionMetrics`'ten — iki sayfanın tepesi birebir aynı), altında afiş
/// ızgarası. Banner'a kategorinin görseli olan en yüksek puanlı içerikleri
/// çıkıyor; anasayfadaki öne çıkanların kategori ölçeğindeki karşılığı.
///
/// Canlı yayın kategorilerinde banner yok: kanalın afişi değil 16:9 logosu
/// var, banner'ın içinde esnetilince tanınmıyor. O kategoriler doğrudan
/// ızgarayla açılıyor.
///
/// Kategori listesi ve görünüm seçici burada yok — onlar `CatalogViewController`'da
/// duruyor. Bu sayfanın işi tek bir kategoriyi anasayfa diliyle göstermek.
final class CategoryViewController: UIViewController {
    private enum Section: Hashable {
        case hero
        case items
    }

    private enum Item: Hashable {
        /// Banner tek hücre: bütün öne çıkanları o taşıyor, kimliği içeriğe
        /// bağlı değil.
        case hero
        case media(MediaItem)
    }

    private let model: AppModel
    private let kind: MediaKind
    private let categoryID: String
    private let categoryTitle: String

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var emptyState: EmptyStateView!
    private weak var heroCell: HeroCell?

    private var items: [MediaItem] = []
    /// Banner'ın anlık durumu (bkz. `FeaturedStore`). Kategoriye özel seçim
    /// de aynı yerden geliyor: sonuç diskte saklanıyor ve bölüm içerik gelene
    /// kadar yerini koruyor, sayfa zıplamıyor.
    private var featuredSnapshot = FeaturedStore.Snapshot(items: [], isResolving: false)
    private var featured: [MediaItem] { featuredSnapshot.items }
    private var expectsBanner: Bool { featuredSnapshot.expectsBanner }

    /// Bir kerede çizilen kart sayısı: bir kategoride binlerce içerik
    /// olabiliyor ve hepsini birden vermek ilk çizimi kilitliyor.
    private var visibleCount = pageSize
    private static let pageSize = 120
    /// tvOS'ta odaklanan kart büyüyor; banner yokken ilk satır tepeye
    /// yapışmasın diye içerik biraz daha aşağıdan başlıyor.
    #if os(tvOS)
    private static let contentTopPadding: CGFloat = 40
    private static let contentBottomPadding: CGFloat = 60
    #else
    private static let contentTopPadding: CGFloat = 0
    private static let contentBottomPadding: CGFloat = 0
    #endif

    private var metrics: AppMetrics { AppMetrics.metrics(for: view.bounds.width) }

    init(kind: MediaKind, categoryID: String, title: String, model: AppModel) {
        self.kind = kind
        self.categoryID = categoryID
        self.categoryTitle = title
        self.model = model
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        navigationItem.setPrefersLargeTitle(false)
        #if os(tvOS)
        // tvOS'ta başlık ızgaranın kendi başlığında duruyor; çubukta ikinci
        // kez yazsaydı banner'ın üstünde asılı kalırdı.
        navigationItem.title = ""
        #endif

        setupCollectionView()
        setupDataSource()
        loadItems()
        applySnapshot(animated: false)

        NotificationCenter.default.addObserver(
            self, selector: #selector(libraryDidChange),
            name: .contentLibraryDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(libraryDidChange),
            name: .appLanguageDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(featuredDidChange),
            name: .featuredDidChange, object: nil
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContentInsets()
        FeaturedStore.artworkDisplayWidth = metrics.heroImageWidth
        guard let heroCell, collectionView.bounds.height > 0 else { return }
        heroCell.artworkOverhang = HeroSectionMetrics.overhang(
            container: collectionView.bounds.size, metrics: metrics
        )
    }

    /// Banner varken içerik ekranın tepesinden başlıyor — görsel navigasyon
    /// çubuğunun altına kadar uzanıyor. Banner yoksa o pay elle veriliyor:
    /// kaydırma görünümünün kendi güvenli alan ayarı kapalı.
    private func updateContentInsets() {
        let top = expectsBanner ? 0 : view.safeAreaInsets.top + Self.contentTopPadding
        let bottom = view.safeAreaInsets.bottom + Self.contentBottomPadding
        let delta = top - collectionView.contentInset.top
        guard delta != 0 || collectionView.contentInset.bottom != bottom else { return }

        collectionView.contentInset.top = top
        collectionView.contentInset.bottom = bottom
        collectionView.verticalScrollIndicatorInsets.top = top

        // Girinti değişince kaydırma görünümü konumu kendiliğinden düzeltmiyor.
        // Banner seçimi asenkron olduğu için girinti sayfa açıldıktan **sonra**
        // da değişebiliyor: fark kadar kaydırmazsak sayfa o kadar kayıyor.
        guard delta != 0 else { return }
        collectionView.contentOffset.y -= delta
    }

    // MARK: - Kurulum

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.prefetchDataSource = self
        collectionView.isPrefetchingEnabled = true
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = false
        // Banner ekranın tepesine kadar uzanıyor; güvenli alan payı bölüm
        // ölçülerinin üstüne binmemeli.
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.applyNativeScrollEdges()

        collectionView.register(HeroCell.self, forCellWithReuseIdentifier: HeroCell.reuseID)
        collectionView.register(PosterCell.self, forCellWithReuseIdentifier: PosterCell.reuseID)
        collectionView.register(
            RowHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: RowHeaderView.reuseID
        )

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        emptyState = EmptyStateView.installed(in: view)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        // Kenar payı ekranın kenarından ölçülüyor, güvenli alandan değil —
        // anasayfayla aynı kural.
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.contentInsetsReference = .none

        return UICollectionViewCompositionalLayout(
            sectionProvider: { [weak self] index, environment in
                guard let self else { return nil }
                let container = environment.container.contentSize
                let metrics = AppMetrics.metrics(for: container.width)

                switch dataSource.sectionIdentifier(for: index) ?? .items {
                case .hero:
                    return self.heroSection(metrics: metrics, container: container)
                case .items:
                    return self.gridSection(metrics: metrics, containerWidth: container.width)
                }
            },
            configuration: configuration
        )
    }

    private func heroSection(metrics: AppMetrics, container: CGSize) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(HeroSectionMetrics.height(container: container, metrics: metrics))
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
        // Bölüme alt boşluk verilmiyor: banner'ın kendi gösterge payı sıradaki
        // bölüme kadar olan boşluğu kuruyor (bkz. `HeroSectionMetrics.spacing`).
        return NSCollectionLayoutSection(group: group)
    }

    private func gridSection(metrics: AppMetrics, containerWidth: CGFloat) -> NSCollectionLayoutSection {
        // Izgara anasayfa, favoriler ve aramayla ortak: kart ölçüsü ve
        // boşluklar her ekranda aynı.
        MediaSectionLayout.posterGrid(
            kind: kind,
            containerWidth: containerWidth,
            metrics: metrics,
            showsHeader: showsGridHeader
        )
    }

    /// Kategorinin adı ızgaranın başlığında yazıyor.
    ///
    /// iOS'ta yazmıyor: orada ad zaten navigasyon çubuğunda duruyor, ikinci
    /// kez yazmak sayfayı tekrar ettiriyordu. tvOS'ta çubuk boş, ad buradan.
    private var showsGridHeader: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }

    // MARK: - Veri

    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            guard let self else { return nil }

            switch item {
            case .hero:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: HeroCell.reuseID, for: indexPath
                ) as! HeroCell
                cell.isFavorite = { [weak self] in self?.model.activity.isFavorite($0) ?? false }
                cell.onDetails = { [weak self] in self?.openDetail($0) }
                cell.onToggleFavorite = { [weak self] in self?.model.activity.toggleFavorite($0) }
                cell.artworkOverhang = HeroSectionMetrics.overhang(
                    container: collectionView.bounds.size, metrics: metrics
                )
                cell.configure(items: featured, metrics: metrics)
                heroCell = cell
                return cell

            case let .media(media):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: PosterCell.reuseID, for: indexPath
                ) as! PosterCell
                cell.configure(
                    item: media,
                    metrics: metrics,
                    progress: model.activity.progress(for: media.id),
                    cardWidth: cardWidth
                )
                return cell
            }
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, elementKind, indexPath in
            guard let self,
                  elementKind == UICollectionView.elementKindSectionHeader,
                  dataSource.sectionIdentifier(for: indexPath.section) == .items
            else { return nil }

            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: elementKind, withReuseIdentifier: RowHeaderView.reuseID, for: indexPath
            ) as! RowHeaderView
            header.configure(title: categoryTitle, font: metrics.rowTitleFont, showsChevron: false)
            // Banner'ın hemen altındaki başlık sayfa tepedeyken gizli.
            header.applyReveal(
                self.isHeroHeader(at: indexPath)
                    ? RowHeaderView.revealProgress(for: collectionView, metrics: metrics)
                    : 1
            )
            return header
        }
    }

    /// Kartın ekranda kapladığı genişlik — düzenle **aynı** hesap; görselin
    /// indirme boyutu da buradan geliyor.
    private var cardWidth: CGFloat {
        MediaSectionLayout.gridItemWidth(
            kind: kind,
            containerWidth: max(collectionView.bounds.width, 1),
            metrics: metrics
        )
    }

    private func loadItems() {
        // Sağlayıcı listeleri temiz değil: aynı yayın kategoride iki kez
        // bulunabiliyor ve diffable data source çift kimlik görüp çöküyor.
        var seen = Set<MediaID>()
        items = model.library
            .items(kind: kind, categoryID: categoryID)
            .filter { seen.insert($0.id).inserted }
        visibleCount = Self.pageSize
        reloadFeatured()
    }

    /// Banner'ın güncel durumunu okur; seçim `FeaturedStore` içinde yürüyor.
    private func reloadFeatured() {
        featuredSnapshot = model.library.featured.snapshot(
            for: .category(kind, categoryID)
        )
    }

    @objc private func featuredDidChange() {
        let previous = featuredSnapshot.expectsBanner
        reloadFeatured()
        applySnapshot(animated: true)
        if previous != featuredSnapshot.expectsBanner { updateContentInsets() }
    }

    /// Bölüm 1'in başlığı banner'ın hemen altındaki başlık.
    private func isHeroHeader(at indexPath: IndexPath) -> Bool {
        expectsBanner && indexPath.section == 1
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()

        if expectsBanner {
            snapshot.appendSections([.hero])
            snapshot.appendItems([.hero], toSection: .hero)
            // Banner'ın kimliği içeriğe bağlı değil: öne çıkanlar değişince
            // diffable hücreyi kendiliğinden yenilemiyor.
            if dataSource.snapshot().itemIdentifiers.contains(.hero) {
                snapshot.reconfigureItems([.hero])
            }
        }

        if !items.isEmpty {
            snapshot.appendSections([.items])
            snapshot.appendItems(items.prefix(visibleCount).map(Item.media), toSection: .items)
        }

        dataSource.apply(snapshot, animatingDifferences: animated)
        collectionView.updateHeroHeaderReveal(hasHero: expectsBanner, metrics: metrics)

        emptyState.configure(symbol: "tray", title: L10n.categoryEmpty)
        emptyState.isHidden = !items.isEmpty
    }

    /// Sıradaki sayfayı ekler. Kaydırma sona yaklaşınca çağrılıyor.
    private func extendVisibleItems() {
        guard visibleCount < items.count else { return }
        visibleCount = min(visibleCount + Self.pageSize, items.count)
        applySnapshot(animated: false)
    }

    @objc private func libraryDidChange() {
        loadItems()
        applySnapshot(animated: true)
    }

    // MARK: - Banner otomatik geçişi

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        heroCell?.resumeAutoAdvance()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        heroCell?.pauseAutoAdvance()
    }

    // MARK: - Gezinme

    private func openDetail(_ item: MediaItem, sourceView: UIView? = nil) {
        // Canlı kanalın detay ekranı yok; doğrudan oynatıcı açılıyor.
        guard item.kind != .live else {
            Task { await model.play(item) }
            return
        }
        let controller = DetailViewController(item: item, model: model)
        controller.applyZoomTransition(from: sourceView)
        navigationController?.pushViewController(controller, animated: true)
    }
}

extension CategoryViewController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        let offset = scrollView.contentOffset.y
        for case let cell as HeroCell in collectionView.visibleCells {
            cell.applyScroll(offset: offset)
        }
        collectionView.updateHeroHeaderReveal(hasHero: expectsBanner, metrics: metrics)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        #if os(tvOS)
        collectionView.unclipFocusGrowth(around: cell)
        #endif

        if let cell = cell as? HeroCell {
            // Hücre ekrana girerken sayfa zaten kaydırılmış olabilir.
            cell.applyScroll(offset: collectionView.contentOffset.y)
            return
        }

        // Sıradaki sayfa: anlık görüntüyü çizim döngüsünün içinde
        // uygulamamak için bir sonraki tura bırakılıyor.
        guard dataSource.sectionIdentifier(for: indexPath.section) == .items,
              indexPath.item >= visibleCount - 12
        else { return }
        DispatchQueue.main.async { [weak self] in
            self?.extendVisibleItems()
        }
    }

    /// Karta uzun basınca çıkan menü — İzle, favori, izleme listesi. Menünün
    /// kendisi `MediaCardMenu`'de: aynı kart her ekranda aynı eylemleri veriyor.
    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, let indexPath = indexPaths.first else { return nil }
        guard case let .media(item)? = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return MediaCardMenu.configuration(for: item, model: model) { [weak self] item in
            self?.openDetail(item)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard case let .media(item) = dataSource.itemIdentifier(for: indexPath) else { return }
        openDetail(item, sourceView: collectionView.cellForItem(at: indexPath))
    }
}

extension CategoryViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        let items = indexPaths.compactMap { indexPath -> MediaItem? in
            guard case let .media(media)? = dataSource.itemIdentifier(for: indexPath) else {
                return nil
            }
            return media
        }
        MediaPrefetch.warm(items, posterWidth: cardWidth)
    }
}
