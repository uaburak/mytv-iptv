import UIKit

/// Arama ekranı — Apple TV uygulamasının (tvOS 26) arama sayfasıyla aynı düzen.
///
/// Üstteki arama alanı ve alfabe klavyesi sistemin kendisi: tvOS'ta ekran bir
/// `UISearchContainerViewController` içinde duruyor, aşağıdaki koleksiyon da
/// klavyenin altından kayarak geçiyor.
///
/// Sayfanın sırası Apple'ın ekranındakiyle aynı:
/// - boştayken **Trend Olanlar**: katalogdan seçilmiş afişler,
/// - yazmaya başlayınca sonuçlar türe göre başlıklı **ızgaralar** hâlinde
///   (Filmler → Diziler → Canlı).
///
/// Apple'ın sayfasında olmayan iki şey burada da yok: tür süzgeci çipleri
/// (sonuç başlıkları zaten aynı ayrımı yapıyor) ve renkli "Keşfet" kartları.
/// Sonuçlar yatay raylar değil dikey ızgara: klavyenin altındaki alan
/// aşağı kayıyor, yana değil.
final class SearchViewController: UIViewController {
    /// Apple'ın arama sayfasında son aramalar bölümü **yok**; burada duruyor
    /// çünkü uygulama aramaları zaten kaydediyor ve kumandayla aynı adı
    /// yeniden yazmak pahalı. Tamamen Apple düzeni istenirse tek satır: `false`.
    private static let showsRecentSearches = true

    private enum Section: Hashable {
        case recents
        case trending
        case results(MediaKind)
    }

    private enum Item: Hashable {
        case recent(String)
        case media(MediaItem)
    }

    private let model: AppModel
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var emptyState: EmptyStateView!

    private weak var activeSearchController: UISearchController?
    private var currentQuery = ""
    /// Sonucu ekrana yansımış son sorgu. "Sonuç bulunamadı" ancak arama
    /// bitince çıkıyor: her tuş vuruşunda bir an için belirip kaybolması
    /// yazarken ekranı titretiyordu.
    private var completedQuery: String?
    private var searchTask: Task<Void, Never>?
    private var searchWorkItem: DispatchWorkItem?

    private let recentSearchesStore = RecentSearchStore()
    /// Boştaki ızgara. Kataloğun tamamı değil, seçilmiş bir avuç başlık.
    private var trending: [MediaItem] = []
    private var results: [MediaKind: [MediaItem]] = [:]
    private var visibleSections: [Section] = []

    #if os(iOS)
    private let ownSearchController = UISearchController(searchResultsController: nil)
    #else
    private weak var searchContainerController: UIViewController?
    private let topFocusGuide = UIFocusGuide()
    #endif

    private var isSearching: Bool {
        currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func makeTabController(model: AppModel) -> UIViewController {
        let controller = SearchViewController(model: model)
        #if os(tvOS)
        let searchController = UISearchController(searchResultsController: controller)
        searchController.searchResultsUpdater = controller
        searchController.searchBar.delegate = controller
        searchController.searchBar.placeholder = L10n.searchPlaceholder
        controller.activeSearchController = searchController

        let container = UISearchContainerViewController(searchController: searchController)
        container.title = L10n.tabSearch
        controller.searchContainerController = container
        return container
        #else
        return controller
        #endif
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background

        #if os(iOS)
        ownSearchController.searchResultsUpdater = self
        ownSearchController.searchBar.delegate = self
        ownSearchController.obscuresBackgroundDuringPresentation = false
        definesPresentationContext = true
        activeSearchController = ownSearchController
        navigationItem.searchController = ownSearchController
        navigationItem.hidesSearchBarWhenScrolling = false
        #endif

        buildHierarchy()
        configureDataSource()
        configureEmptyState()
        refreshLocalization()

        loadTrending()
        updateSnapshot(animated: false)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLibraryChange),
            name: .contentLibraryDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: .appLanguageDidChange,
            object: nil
        )
    }

    private func buildHierarchy() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        // Sonuç kartları ekrana girmeden görselleri ve künyeleri hazırlanıyor;
        // arama sonucuna dokunulduğunda detay dolu açılıyor.
        collectionView.prefetchDataSource = self
        collectionView.isPrefetchingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.applyNativeScrollEdges()

        #if os(iOS)
        collectionView.keyboardDismissMode = .onDrag
        #endif

        collectionView.register(SearchChipCell.self, forCellWithReuseIdentifier: SearchChipCell.reuseID)
        collectionView.register(PosterCell.self, forCellWithReuseIdentifier: PosterCell.reuseID)
        collectionView.register(
            SearchSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: SearchSectionHeaderView.reuseID
        )

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        #if os(tvOS)
        view.addLayoutGuide(topFocusGuide)
        NSLayoutConstraint.activate([
            topFocusGuide.topAnchor.constraint(equalTo: view.topAnchor),
            topFocusGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topFocusGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topFocusGuide.heightAnchor.constraint(equalToConstant: 120),
        ])
        if let searchBar = activeSearchController?.searchBar {
            topFocusGuide.preferredFocusEnvironments = [searchBar]
        }
        #endif
    }

    private func configureEmptyState() {
        emptyState = EmptyStateView.installed(in: view)
    }

    // MARK: - Düzen

    private func createLayout() -> UICollectionViewLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.contentInsetsReference = .none

        return UICollectionViewCompositionalLayout(
            sectionProvider: { [weak self] sectionIndex, environment in
                guard let self, sectionIndex < visibleSections.count else { return nil }
                let metrics = AppMetrics.metrics(for: environment.container.contentSize.width)

                switch visibleSections[sectionIndex] {
                case .recents:
                    return self.createRecentsSection(metrics: metrics)
                case .trending:
                    return self.createGridSection(
                        kind: .movie,
                        metrics: metrics,
                        containerWidth: environment.container.contentSize.width
                    )
                case let .results(kind):
                    return self.createGridSection(
                        kind: kind,
                        metrics: metrics,
                        containerWidth: environment.container.contentSize.width
                    )
                }
            },
            configuration: configuration
        )
    }

    private func createRecentsSection(metrics: AppMetrics) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .estimated(140),
            heightDimension: .absolute(SearchChipCell.height)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(SearchChipCell.height)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        group.interItemSpacing = .fixed(metrics.cardSpacing * 0.75)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = metrics.cardSpacing * 0.75
        section.contentInsets = NSDirectionalEdgeInsets(
            top: metrics.rowHeaderGap * 0.5,
            leading: metrics.screenPadding,
            bottom: metrics.rowSpacing * 0.5,
            trailing: metrics.screenPadding
        )
        section.boundarySupplementaryItems = [headerItem(metrics: metrics)]
        return section
    }

    /// Afiş ızgarası: hem "Trend Olanlar" hem de sonuç bölümleri bunu
    /// kullanıyor — Apple'ın arama sayfasında ikisi de aynı karttan kurulu.
    ///
    /// Düzen uygulamanın ortak ızgarası (`posterGrid`): kart ölçüsü, sütun
    /// sayısı ve boşluklar anasayfa, favoriler ve katalogla **aynı**. Yalnızca
    /// başlık bu ekranın kendi başlığı — "Temizle" eylemini taşıyor.
    private func createGridSection(
        kind: MediaKind,
        metrics: AppMetrics,
        containerWidth: CGFloat
    ) -> NSCollectionLayoutSection {
        let section = MediaSectionLayout.posterGrid(
            kind: kind, containerWidth: containerWidth, metrics: metrics
        )
        section.boundarySupplementaryItems = [headerItem(metrics: metrics)]
        return section
    }

    private func headerItem(metrics: AppMetrics) -> NSCollectionLayoutBoundarySupplementaryItem {
        NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(metrics.rowHeaderHeight + 16)
            ),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
    }

    // MARK: - Veri kaynağı

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            guard let self else { return nil }
            let metrics = AppMetrics.metrics(for: view.bounds.width)

            switch item {
            case let .recent(queryText):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: SearchChipCell.reuseID,
                    for: indexPath
                ) as! SearchChipCell
                cell.configure(
                    title: queryText,
                    symbol: "magnifyingglass",
                    isSelected: false
                ) { [weak self] in
                    self?.applyQuery(queryText)
                }
                return cell

            case let .media(mediaItem):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: PosterCell.reuseID,
                    for: indexPath
                ) as! PosterCell
                cell.configure(
                    item: mediaItem,
                    metrics: metrics,
                    progress: model.activity.progress(for: mediaItem.id),
                    cardWidth: MediaSectionLayout.gridItemWidth(
                        kind: mediaItem.kind,
                        containerWidth: max(collectionView.bounds.width, 1),
                        metrics: metrics
                    )
                )
                return cell
            }
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, elementKind, indexPath in
            guard let self,
                  elementKind == UICollectionView.elementKindSectionHeader,
                  let section = dataSource.sectionIdentifier(for: indexPath.section)
            else { return nil }

            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: elementKind,
                withReuseIdentifier: SearchSectionHeaderView.reuseID,
                for: indexPath
            ) as! SearchSectionHeaderView
            let font = AppMetrics.metrics(for: view.bounds.width).rowTitleFont

            switch section {
            case .recents:
                header.configure(
                    title: L10n.recentSearches,
                    font: font,
                    actionTitle: L10n.clearRecentSearches
                )
                header.onAction = { [weak self] in
                    self?.clearRecents()
                }
            case .trending:
                header.configure(title: L10n.trending, font: font, actionTitle: nil)
                header.onAction = nil
            case let .results(kind):
                header.configure(title: kind.title, font: font, actionTitle: nil)
                header.onAction = nil
            }
            return header
        }
    }

    private func updateSnapshot(animated: Bool) {
        let snapshot = makeSnapshot()
        visibleSections = snapshot.sectionIdentifiers
        dataSource.apply(snapshot, animatingDifferences: animated)
        updateEmptyStateView()
    }

    /// Dil değişiminde bölüm başlıkları yeniden yazılmalı. Aynı anlık
    /// görüntüyü uygulamak başlıklara dokunmuyor — fark yok, dolayısıyla
    /// yeniden çizim de yok; yeniden yükleme tek yol.
    private func reloadSnapshot() {
        let snapshot = makeSnapshot()
        visibleSections = snapshot.sectionIdentifiers
        dataSource.applySnapshotUsingReloadData(snapshot)
        updateEmptyStateView()
    }

    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()

        if isSearching {
            // Sonuçlar Apple'daki sırayla: önce filmler, sonra diziler, en
            // altta canlı kanallar.
            for kind in [MediaKind.movie, .series, .live] {
                guard let items = results[kind], !items.isEmpty else { continue }
                snapshot.appendSections([.results(kind)])
                snapshot.appendItems(items.map(Item.media), toSection: .results(kind))
            }
        } else {
            if Self.showsRecentSearches, !recentSearchesStore.queries.isEmpty {
                snapshot.appendSections([.recents])
                snapshot.appendItems(recentSearchesStore.queries.map(Item.recent), toSection: .recents)
            }
            if !trending.isEmpty {
                snapshot.appendSections([.trending])
                snapshot.appendItems(trending.map(Item.media), toSection: .trending)
            }
        }

        return snapshot
    }

    /// Apple'ın boş sonuç ekranı yalın: büyük bir "Sonuç bulunamadı" ve
    /// altında ne yapılacağını söyleyen tek satır — simge yok.
    private func updateEmptyStateView() {
        if isSearching {
            let hasResults = results.values.contains { !$0.isEmpty }
            emptyState.configure(
                title: L10n.noSearchResults,
                message: L10n.noSearchResultsHint
            )
            emptyState.isHidden = hasResults || completedQuery != currentQuery
        } else {
            emptyState.configure(symbol: "magnifyingglass", title: L10n.searchPrompt)
            emptyState.isHidden = !(recentSearchesStore.queries.isEmpty && trending.isEmpty)
        }
    }

    private func loadTrending() {
        trending = SearchTrending.items(in: model.library)
    }

    private func executeSearch() {
        searchTask?.cancel()

        guard isSearching else {
            results = [:]
            completedQuery = nil
            updateSnapshot(animated: true)
            return
        }

        let query = currentQuery

        searchTask = Task { [weak self] in
            guard let self else { return }
            let matches = await model.library.search(query)
            guard !Task.isCancelled, query == self.currentQuery else { return }

            var groupedResults: [MediaKind: [MediaItem]] = [:]
            var seenIDs = Set<MediaID>()
            for item in matches where seenIDs.insert(item.id).inserted {
                groupedResults[item.kind, default: []].append(item)
            }

            self.results = groupedResults
            self.completedQuery = query
            self.updateSnapshot(animated: true)
        }
    }

    private func applyQuery(_ queryText: String) {
        guard let searchController = activeSearchController else { return }
        searchController.searchBar.text = queryText
        recentSearchesStore.record(queryText)
        updateSearchResults(for: searchController)
    }

    private func clearRecents() {
        recentSearchesStore.clear()
        updateSnapshot(animated: true)
    }

    private func refreshLocalization() {
        title = L10n.tabSearch
        activeSearchController?.searchBar.placeholder = L10n.searchPlaceholder
        updateEmptyStateView()
    }

    @objc private func handleLibraryChange() {
        loadTrending()
        if isSearching {
            executeSearch()
        } else {
            updateSnapshot(animated: true)
        }
    }

    @objc private func handleLanguageChange() {
        refreshLocalization()
        reloadSnapshot()
    }

    private var navigationTarget: UINavigationController? {
        if let navigationController { return navigationController }
        #if os(tvOS)
        if let nav = searchContainerController?.navigationController { return nav }
        #endif

        var current: UIViewController? = parent ?? presentingViewController
        while let vc = current {
            if let nav = vc as? UINavigationController { return nav }
            if let nav = vc.navigationController { return nav }
            current = vc.parent ?? vc.presentingViewController
        }
        return nil
    }

    private func navigateTo(_ controller: UIViewController) {
        #if os(iOS)
        activeSearchController?.searchBar.resignFirstResponder()
        #endif

        if let nav = navigationTarget {
            nav.pushViewController(controller, animated: true)
        } else {
            present(controller, animated: true)
        }
    }

    private func openMediaDetail(_ mediaItem: MediaItem, at indexPath: IndexPath) {
        // Sonuca gidilen arama kaydediliyor; boştaki ızgaradan açılan başlık
        // bir arama değil, kaydedilmiyor.
        if isSearching { recentSearchesStore.record(currentQuery) }

        guard mediaItem.kind != .live else {
            Task { await model.play(mediaItem) }
            return
        }

        let detailVC = DetailViewController(item: mediaItem, model: model)
        detailVC.applyZoomTransition(from: collectionView.cellForItem(at: indexPath))
        navigateTo(detailVC)
    }
}

extension SearchViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        recentSearchesStore.record(currentQuery)
        searchBar.resignFirstResponder()
    }

    #if os(iOS)
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        currentQuery = ""
        results = [:]
        completedQuery = nil
        updateSnapshot(animated: true)
    }
    #endif
}

extension SearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        currentQuery = searchController.searchBar.text ?? ""
        searchWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.executeSearch()
        }
        searchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

extension SearchViewController: UICollectionViewDelegate {
    #if os(tvOS)
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        collectionView.unclipFocusGrowth(around: cell)
    }
    #endif

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
            self?.openMediaDetail(item, at: indexPath)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case let .recent(queryText):
            applyQuery(queryText)
        case let .media(mediaItem):
            openMediaDetail(mediaItem, at: indexPath)
        }
    }

    #if os(tvOS)
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        if let searchBar = activeSearchController?.searchBar {
            topFocusGuide.preferredFocusEnvironments = [searchBar]
        }
    }
    #endif
}

/// Arama boşken gösterilen ızgara — Apple TV'deki "Trend Olanlar".
///
/// Sağlayıcılar popülerlik bilgisi vermiyor; eldeki en yakın ölçüt puan.
/// Katalog on binlerce kayıt ve tamamını sıralamak her açılışta pahalı, o
/// yüzden baştan bir dilim alınıp yalnızca o sıralanıyor — anasayfadaki öne
/// çıkanlarla aynı yaklaşım.
private enum SearchTrending {
    /// Tür başına taranan kayıt ve ekrana çıkan kart sayısı. Yirmi bir kart
    /// Apple TV'de tam üç sıra ediyor.
    private static let scanLimit = 400
    private static let limit = 21

    @MainActor
    static func items(in library: ContentLibrary) -> [MediaItem] {
        func pool(_ kind: MediaKind, scan: Int) -> [MediaItem] {
            var picked: [MediaItem] = []
            picked.reserveCapacity(scan)
            for item in library.catalog[kind] ?? [] where item.posterURL != nil {
                picked.append(item)
                if picked.count == scan { break }
            }
            return picked
        }

        // Katalogda aynı yayın birden çok kez bulunabiliyor; ızgarada tekrar
        // eden kayıt diffable veri kaynağını da çökertiyor.
        var seen = Set<MediaID>()
        let candidates = (pool(.movie, scan: scanLimit) + pool(.series, scan: scanLimit / 2))
            .filter { seen.insert($0.id).inserted }

        return Array(
            candidates
                .sorted { lhs, rhs in
                    let left = lhs.rating ?? 0
                    let right = rhs.rating ?? 0
                    // Puansız kayıtlarda sıralama başlığa düşüyor: yoksa aynı
                    // liste her kuruluşta başka bir sırada çıkıyor.
                    if left != right { return left > right }
                    return lhs.title < rhs.title
                }
                .prefix(limit)
        )
    }
}

extension SearchViewController: UICollectionViewDataSourcePrefetching {
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
        guard let first = items.first else { return }
        MediaPrefetch.warm(
            items,
            posterWidth: MediaSectionLayout.gridItemWidth(
                kind: first.kind,
                containerWidth: max(collectionView.bounds.width, 1),
                metrics: AppMetrics.metrics(for: view.bounds.width)
            )
        )
    }
}
