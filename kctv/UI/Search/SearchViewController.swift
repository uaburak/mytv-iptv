import UIKit

/// Katalog belleğe alındığı için arama tamamen yerel çalışır; her tuşta
/// sunucuya gitmez. Bu, 50 bin kanallık listelerde bile anında sonuç verir.
///
/// Ekranın iki hâli var ve ikisi de aynı koleksiyon görünümünde:
/// - **Boşta**: son aramalar kapsül düğmeler olarak yan yana, altında hazır
///   arama kartları ("Aksiyon Filmleri", "Belgeseller") — poster kartla aynı
///   ölçü ve malzeme.
/// - **Arama sırasında**: sonuçlar poster kart ızgarasında, satıra sığdığı
///   kadar yan yana. Kartlar tür türe ayrı bölümlerde çünkü kart oranı türe
///   göre değişiyor: canlı kanal 16:9, film ve dizi dikey afiş.
final class SearchViewController: UIViewController {
    private enum Section: Hashable {
        case kinds
        case recents
        case suggestions
        case results(MediaKind)
    }

    private enum Item: Hashable {
        /// `nil` = "Tümü" çipi.
        case kind(MediaKind?)
        case recent(String)
        case suggestion(SearchSuggestion)
        case result(MediaItem)
    }

    private let model: AppModel
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let emptyLabel = UILabel()

    /// Arama çubuğunun sahibi platforma göre değişiyor: iOS'ta bu ekran kendi
    /// `UISearchController`'ını kurup navigasyona gömüyor, tvOS'ta ise çubuk
    /// `UISearchContainerViewController` tarafından yönetiliyor ve bu ekran
    /// yalnızca sonuçları gösteriyor. Sorgu her iki durumda da buradan okunuyor.
    private weak var activeSearchController: UISearchController?
    private var query = ""

    #if os(iOS)
    private let ownSearchController = UISearchController(searchResultsController: nil)
    #else
    /// tvOS'ta arama çubuğunu taşıyan kapsayıcı. Detay ekranı **onun**
    /// yığınına itiliyor; ayrıntı için `pushTarget`.
    private weak var searchContainer: UIViewController?
    #endif

    /// `nil` ise tür ayrımı yok. Tek tür seçiliyse hem arama hem hazır kartlar
    /// ona daralıyor.
    private var selectedKind: MediaKind?
    private var kinds: Set<MediaKind> { selectedKind.map { [$0] } ?? Set(MediaKind.allCases) }

    private var results: [MediaKind: [MediaItem]] = [:]
    private var suggestions: [SearchSuggestion] = []

    /// Düzen kapanışı bölümleri sırayla soruyor ama elinde yalnızca sıra
    /// numarası var; anlık görüntüdeki bölüm sırası burada tutuluyor.
    private var visibleSections: [Section] = []

    /// Her tuş vuruşunda katalogun tamamını taramamak için gecikme.
    private var searchWork: DispatchWorkItem?
    /// Uçuştaki tarama. Yeni bir arama başlarken iptal ediliyor.
    private var searchTask: Task<Void, Never>?
    /// Klavye yalnızca sekmeye ilk gelişte açılıyor; detaydan geri dönerken
    /// kendiliğinden açılması kullanıcının okuduğu listeyi kapatıyordu.
    private var didFocusSearchBar = false

    private let recentSearches = RecentSearchStore()

    /// Sonuç bölümlerinin sırası: aranan şey çoğunlukla bir film ya da dizi,
    /// kanallar en altta.
    private static let resultOrder: [MediaKind] = [.movie, .series, .live]

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { trimmedQuery.count >= 2 }

    /// Hazır kartların oranını belirleyen tür. Kartlar yalnızca canlı süzgeci
    /// seçiliyken 16:9 oluyor; film ve dizi kartları aynı dikey afiş oranında
    /// olduğu için tek bölümde yan yana durabiliyorlar.
    private var suggestionKind: MediaKind { selectedKind ?? .movie }

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Arama sekmesine konacak denetleyici.
    ///
    /// tvOS'ta `UISearchController(searchResultsController: nil)` çalışma
    /// zamanında çöküyor — o platformda sonuç ekranı zorunlu. Bu yüzden orada
    /// bu ekran *sonuç ekranı* olarak kullanılıyor ve arama çubuğunu
    /// `UISearchContainerViewController` taşıyor. iOS'ta değişen bir şey yok.
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
        controller.searchContainer = container
        return container
        #else
        return controller
        #endif
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background

        // tvOS'ta arama çubuğu dışarıda (`makeTabController`) kuruluyor.
        #if os(iOS)
        ownSearchController.searchResultsUpdater = self
        ownSearchController.searchBar.delegate = self
        ownSearchController.obscuresBackgroundDuringPresentation = false
        // Arama denetleyicisi etkinken kendi görünümünü sunuyor. Bu satır
        // olmadan sunumu **kök** denetleyici yapıyor: sonuca ya da hazır karta
        // dokunulduğunda detay ekranı navigasyona itiliyor ama arama sunumu
        // onun üstünde kaldığı için ekranda hiçbir şey olmuyormuş gibi
        // görünüyor. Sunum bu ekrana bağlanınca itilen ekran öne geçiyor.
        definesPresentationContext = true
        activeSearchController = ownSearchController
        navigationItem.searchController = ownSearchController
        navigationItem.hidesSearchBarWhenScrolling = false
        #endif

        // Arama denetleyicisi bağlandıktan sonra: metinler onun da
        // placeholder'ını kuruyor.
        updateLocalizedTexts()

        setupCollectionView()
        setupDataSource()
        setupEmptyLabel()

        reloadSuggestions()
        applySnapshot(animated: false)

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
    }

    /// Sekmeye **ilk** gelişte klavye açık ve yazmaya hazır geliyor. Sonraki
    /// gelişlerde açılmıyor: detaydan geri dönen kullanıcı listeye bakmak
    /// istiyor, klavye onun yarısını kapatıyordu.
    ///
    /// tvOS'ta arama çubuğunun odağını `UISearchContainerViewController`
    /// kendisi veriyor; oraya elle dokunulmuyor.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applySnapshot(animated: false)
        #if os(iOS)
        guard !didFocusSearchBar else { return }
        didFocusSearchBar = true
        // Görünüm hiyerarşisi tam oturmadan ilk yanıtlayıcı olmak sessizce
        // başarısız olabiliyor; bir tur sonraya bırakılıyor.
        DispatchQueue.main.async { [weak self] in
            self?.ownSearchController.searchBar.becomeFirstResponder()
        }
        #endif
    }

    // MARK: - Kurulum

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.applyNativeScrollEdges()
        // Klavye açıkken kartlara bakmak isteyen kullanıcı listeyi çektiğinde
        // klavye kendiliğinden kapanıyor.
        #if os(iOS)
        collectionView.keyboardDismissMode = .onDrag
        #endif
        collectionView.register(SearchChipCell.self, forCellWithReuseIdentifier: SearchChipCell.reuseID)
        collectionView.register(
            SearchSuggestionCell.self, forCellWithReuseIdentifier: SearchSuggestionCell.reuseID
        )
        collectionView.register(PosterCell.self, forCellWithReuseIdentifier: PosterCell.reuseID)
        collectionView.register(
            SearchSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: SearchSectionHeaderView.reuseID
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            // Güvenli alana değil ekranın tepesine: içerik navigation bar ve
            // arama çubuğunun ardından geçip bulanıklaşıyor, sert bir çizgide
            // kesilmiyor. Dinlenme konumundaki boşluğu
            // `contentInsetAdjustmentBehavior` varsayılanı veriyor.
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupEmptyLabel() {
        emptyLabel.textColor = AppPalette.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
        ])
    }

    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            guard let self else { return nil }
            let metrics = AppMetrics.metrics(for: view.bounds.width)

            switch item {
            case let .kind(kind):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: SearchChipCell.reuseID, for: indexPath
                ) as! SearchChipCell
                cell.configure(
                    title: kind?.title ?? L10n.allKinds,
                    symbol: kind?.symbol,
                    isSelected: selectedKind == kind
                ) { [weak self] in
                    self?.selectKind(kind)
                }
                return cell

            case let .recent(text):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: SearchChipCell.reuseID, for: indexPath
                ) as! SearchChipCell
                cell.configure(
                    title: text,
                    symbol: "clock.arrow.circlepath",
                    isSelected: false
                ) { [weak self] in
                    self?.applyQuery(text)
                }
                return cell

            case let .suggestion(suggestion):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: SearchSuggestionCell.reuseID, for: indexPath
                ) as! SearchSuggestionCell
                cell.configure(
                    suggestion: suggestion,
                    metrics: metrics,
                    cardWidth: cardWidth(for: suggestion.kind, metrics: metrics),
                    colorIndex: indexPath.item
                )
                return cell

            case let .result(media):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: PosterCell.reuseID, for: indexPath
                ) as! PosterCell
                cell.configure(
                    item: media,
                    metrics: metrics,
                    progress: model.activity.progress(for: media.id),
                    cardWidth: cardWidth(for: media.kind, metrics: metrics)
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
            case .kinds:
                return nil
            case .recents:
                header.configure(
                    title: L10n.recentSearches,
                    font: font,
                    actionTitle: L10n.clearRecentSearches
                )
                header.onAction = { [weak self] in
                    guard let self else { return }
                    recentSearches.clear()
                    applySnapshot(animated: true)
                }
            case .suggestions:
                header.configure(title: L10n.discover, font: font, actionTitle: nil)
                header.onAction = nil
            case let .results(kind):
                header.configure(title: kind.title, font: font, actionTitle: nil)
                header.onAction = nil
            }
            return header
        }
    }

    // MARK: - Düzen

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let self, index < visibleSections.count else { return nil }
            let width = environment.container.effectiveContentSize.width
            let metrics = AppMetrics.metrics(for: width)

            switch visibleSections[index] {
            case .kinds:
                return Self.chipSection(metrics: metrics, showsHeader: false)
            case .recents:
                return Self.chipSection(metrics: metrics, showsHeader: true)
            case .suggestions:
                return Self.gridSection(
                    kind: suggestionKind, containerWidth: width, metrics: metrics
                )
            case let .results(kind):
                return Self.gridSection(kind: kind, containerWidth: width, metrics: metrics)
            }
        }
    }

    /// Kapsül düğmelerin bölümü: satıra sığdığı kadar yan yana, kalanı alt
    /// satıra. Grup satırın tamamını kaplıyor ve öğeler kendi genişliklerince
    /// diziliyor; sarma bundan çıkıyor.
    private static func chipSection(
        metrics: AppMetrics,
        showsHeader: Bool
    ) -> NSCollectionLayoutSection {
        let spacing = metrics.cardSpacing * 0.75
        let size = NSCollectionLayoutSize(
            widthDimension: .estimated(140),
            heightDimension: .absolute(SearchChipCell.height)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(SearchChipCell.height)
            ),
            subitems: [item]
        )
        group.interItemSpacing = .fixed(spacing)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(
            top: showsHeader ? metrics.rowHeaderGap * 0.5 : 0,
            leading: metrics.screenPadding,
            bottom: metrics.rowSpacing * 0.5,
            trailing: metrics.screenPadding
        )
        if showsHeader {
            section.boundarySupplementaryItems = [header(metrics: metrics)]
        }
        return section
    }

    /// Poster kart ızgarası — katalog ekranıyla ortak.
    private static func gridSection(
        kind: MediaKind,
        containerWidth: CGFloat,
        metrics: AppMetrics
    ) -> NSCollectionLayoutSection {
        let section = MediaSectionLayout.posterGrid(
            kind: kind, containerWidth: containerWidth, metrics: metrics
        )
        // Bölüm başlığı burada tür adını taşıyor ve kendi görünümü var; ortak
        // ray başlığı kullanılmıyor.
        section.boundarySupplementaryItems = [header(metrics: metrics)]
        return section
    }

    private static func header(metrics: AppMetrics) -> NSCollectionLayoutBoundarySupplementaryItem {
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(metrics.rowHeaderHeight + 16)
            ),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        header.contentInsets = .zero
        return header
    }

    /// Hücrenin ekranda kaplayacağı genişlik — görsellerin indirme boyutu da
    /// buradan geliyor.
    ///
    /// Ölçü düzenin kullandığı genişlikten çıkıyor: `view.bounds.width`
    /// kullanıldığında güvenli alan payı kadar sapıyor ve afiş hücresinden
    /// taşıp alt satırdaki kartın üstüne biniyordu.
    private func cardWidth(for kind: MediaKind, metrics: AppMetrics) -> CGFloat {
        let insets = collectionView.adjustedContentInset
        let width = max(collectionView.bounds.width - insets.left - insets.right, 1)
        return MediaSectionLayout.gridItemWidth(
            kind: kind, containerWidth: width, metrics: metrics
        )
    }

    // MARK: - Veri

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()

        snapshot.appendSections([.kinds])
        snapshot.appendItems(
            [Item.kind(nil)] + MediaKind.allCases.map { Item.kind($0) },
            toSection: .kinds
        )

        if isSearching {
            for kind in Self.resultOrder {
                let items = results[kind] ?? []
                guard !items.isEmpty else { continue }
                snapshot.appendSections([.results(kind)])
                snapshot.appendItems(items.map(Item.result), toSection: .results(kind))
            }
        } else {
            if !recentSearches.queries.isEmpty {
                snapshot.appendSections([.recents])
                snapshot.appendItems(recentSearches.queries.map(Item.recent), toSection: .recents)
            }
            if !suggestions.isEmpty {
                snapshot.appendSections([.suggestions])
                snapshot.appendItems(suggestions.map(Item.suggestion), toSection: .suggestions)
            }
        }

        // Düzen kapanışı bölümü sıra numarasıyla soruyor; sıra uygulamadan
        // önce yazılıyor ki ilk düzen turu doğru bölümü görsün.
        visibleSections = snapshot.sectionIdentifiers
        dataSource.apply(snapshot, animatingDifferences: animated)
        updateEmptyLabel()
    }

    /// Tür çiplerinin kimliği seçiliyken de aynı kalıyor; fark motoru değişimi
    /// göremediği için hücreler elle tazeleniyor.
    private func reconfigureKindChips() {
        var snapshot = dataSource.snapshot()
        guard snapshot.indexOfSection(.kinds) != nil else { return }
        snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .kinds))
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func reloadSuggestions() {
        let kinds = selectedKind.map { [$0] } ?? [MediaKind.movie, .series]
        suggestions = SearchSuggestionBuilder.suggestions(for: kinds, in: model.library)
    }

    /// Tarama artık arka planda; sonuç geldiğinde sorgu değişmiş olabilir.
    /// Geciken bir yanıtın daha yeni bir aramanın sonucunu ezmemesi için hem
    /// görev iptal ediliyor hem de sorgu tekrar karşılaştırılıyor.
    private func runSearch() {
        searchTask?.cancel()

        guard isSearching else {
            results = [:]
            applySnapshot(animated: true)
            return
        }

        let query = self.query
        let kinds = self.kinds
        searchTask = Task { [weak self] in
            guard let self else { return }
            let matches = await model.library.search(query, kinds: kinds)
            guard !Task.isCancelled, query == self.query else { return }

            var grouped: [MediaKind: [MediaItem]] = [:]
            // Katalogda aynı yayın birden çok kez bulunabiliyor; tekrarlar hem
            // yanlış görünüyor hem de diffable veri kaynağını çökertiyor.
            var seen = Set<MediaID>()
            for item in matches where seen.insert(item.id).inserted {
                grouped[item.kind, default: []].append(item)
            }
            results = grouped
            applySnapshot(animated: true)
        }
    }

    @objc private func libraryDidChange() {
        reloadSuggestions()
        runSearch()
    }

    @objc private func languageDidChange() {
        updateLocalizedTexts()
        reloadSuggestions()
        applySnapshot(animated: false)
    }

    private func updateLocalizedTexts() {
        title = L10n.tabSearch
        activeSearchController?.searchBar.placeholder = L10n.searchPlaceholder
        updateEmptyLabel()
    }

    private func updateEmptyLabel() {
        emptyLabel.text = isSearching ? L10n.noSearchResults : L10n.searchPrompt
        emptyLabel.isHidden = isSearching
            ? !results.isEmpty
            : !(recentSearches.queries.isEmpty && suggestions.isEmpty)
    }

    /// Sonuca ulaşan aramalar kaydediliyor: kullanıcı bir içeriğe girdiğinde
    /// ya da klavyedeki Ara'ya bastığında. Her tuş vuruşunu kaydetmek listeyi
    /// yarım kelimelerle dolduruyordu.
    private func recordCurrentQuery() {
        recentSearches.record(query)
    }

    // MARK: - Gezinme

    private func selectKind(_ kind: MediaKind?) {
        guard selectedKind != kind else { return }
        selectedKind = kind
        Haptics.impact(.light)
        reloadSuggestions()
        // Sorgu aynı kalıyor, yalnızca kapsam daraldı; anlık görüntüyü de
        // arama uyguluyor.
        runSearch()
        reconfigureKindChips()
    }

    /// Eski bir aramaya dokunmak onu arama çubuğuna yazıp sonuçları getiriyor.
    private func applyQuery(_ text: String) {
        guard let searchController = activeSearchController else { return }
        searchController.searchBar.text = text
        // En son kullanılan arama listenin başına geçiyor.
        recentSearches.record(text)
        updateSearchResults(for: searchController)
    }

    /// Detay ekranının itileceği navigasyon yığını.
    ///
    /// tvOS'ta bu ekran yığında **değil**: arama çubuğunu
    /// `UISearchContainerViewController` taşıyor ve bu ekran yalnızca onun
    /// sonuç denetleyicisi. Dolayısıyla kendi `navigationController`'ı nil
    /// kalıyor, `push` de sessizce hiçbir şey yapmıyor — karta dokunmak
    /// ekranda hiçbir şeyi değiştirmiyordu. Yığın önce kapsayıcıdan, o da
    /// yoksa sunan/kapsayan denetleyici zinciri yürünerek bulunuyor.
    private var pushTarget: UINavigationController? {
        if let navigationController { return navigationController }
        #if os(tvOS)
        if let nav = searchContainer?.navigationController { return nav }
        #endif

        var candidate: UIViewController? = parent ?? presentingViewController
        while let current = candidate {
            if let nav = current as? UINavigationController { return nav }
            if let nav = current.navigationController { return nav }
            candidate = current.parent ?? current.presentingViewController
        }
        return nil
    }

    private func open(_ controller: UIViewController) {
        #if os(iOS)
        // Klavye açıkken itilen ekranın üstünde kalıyor.
        activeSearchController?.searchBar.resignFirstResponder()
        #endif

        if let pushTarget {
            pushTarget.pushViewController(controller, animated: true)
        } else {
            // Yığın hiç bulunamazsa ekran modal açılıyor: hiç açılmamasından iyi.
            present(controller, animated: true)
        }
    }

    private func openSuggestion(_ suggestion: SearchSuggestion) {
        let items = SearchSuggestionBuilder.items(for: suggestion, in: model.library)
        guard !items.isEmpty else { return }

        open(CatalogViewController(
            kind: suggestion.kind,
            model: model,
            items: items,
            title: suggestion.title
        ))
    }

    private func openResult(_ item: MediaItem, at indexPath: IndexPath) {
        recordCurrentQuery()
        guard item.kind != .live else {
            Task { await model.play(item) }
            return
        }
        let controller = DetailViewController(item: item, model: model)
        controller.applyZoomTransition(from: collectionView.cellForItem(at: indexPath))
        open(controller)
    }
}

extension SearchViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        recordCurrentQuery()
        searchBar.resignFirstResponder()
    }

    // İptal düğmesi tvOS'ta yok; delege metodu da orada kullanılamıyor.
    #if os(iOS)
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        query = ""
        results = [:]
        applySnapshot(animated: true)
    }
    #endif
}

extension SearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        searchWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.runSearch()
        }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

extension SearchViewController: UICollectionViewDelegate {
    /// Odaklanan kart hücresinin dışına büyüyor; araya giren katmanlar kırpma
    /// yaparsa büyüme görünmüyor.
    #if os(tvOS)
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        collectionView.unclipFocusGrowth(around: cell)
    }
    #endif

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case let .kind(kind):
            selectKind(kind)
        case let .recent(text):
            applyQuery(text)
        case let .suggestion(suggestion):
            openSuggestion(suggestion)
        case let .result(media):
            openResult(media, at: indexPath)
        }
    }
}
