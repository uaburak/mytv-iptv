import UIKit

/// Katalog belleğe alındığı için arama tamamen yerel çalışır; her tuşta
/// sunucuya gitmez. Bu, 50 bin kanallık listelerde bile anında sonuç verir.
final class SearchViewController: UIViewController {
    private let model: AppModel
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    /// Arama çubuğunun sahibi platforma göre değişiyor: iOS'ta bu ekran kendi
    /// `UISearchController`'ını kurup navigasyona gömüyor, tvOS'ta ise çubuk
    /// `UISearchContainerViewController` tarafından yönetiliyor ve bu ekran
    /// yalnızca sonuçları gösteriyor. Sorgu her iki durumda da buradan okunuyor.
    private weak var activeSearchController: UISearchController?
    private var query = ""

    #if os(iOS)
    private let ownSearchController = UISearchController(searchResultsController: nil)
    #endif

    /// `nil` ise tür ayrımı yok. Tek tür seçiliyse arama ona daralıyor.
    private var selectedKind: MediaKind?
    private var kinds: Set<MediaKind> { selectedKind.map { [$0] } ?? Set(MediaKind.allCases) }

    /// Tür çipleri listenin başlığında duruyor: iOS'ta arama çubuğu
    /// navigasyonda, tvOS'ta arama kapsayıcısında olduğu için tablo başlığı
    /// iki platformda da boşta ve aynı kod çalışıyor.
    private let kindFilterBar = UIScrollView()
    private let kindFilterStack = UIStackView()
    private static let kindFilterHeight: CGFloat = 56
    private var results: [MediaItem] = []
    /// Her tuş vuruşunda katalogun tamamını taramamak için gecikme.
    private var searchWork: DispatchWorkItem?

    private let recentSearches = RecentSearchStore()
    private static let recentCellID = "RecentSearchCell"

    /// Sorgu boşken sonuç yerine son aramalar listeleniyor.
    private var isShowingRecents: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
            && !recentSearches.queries.isEmpty
    }

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
        activeSearchController = ownSearchController
        navigationItem.searchController = ownSearchController
        navigationItem.hidesSearchBarWhenScrolling = false
        #endif

        // Arama denetleyicisi bağlandıktan sonra: metinler onun da
        // placeholder'ını kuruyor.
        updateLocalizedTexts()

        tableView.backgroundColor = .clear
        // Ayırıcı stili tvOS'ta yok; orada satırlar zaten ayırıcısız.
        #if os(iOS)
        tableView.separatorStyle = .none
        #endif
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 96
        tableView.register(CatalogRowCell.self, forCellReuseIdentifier: CatalogRowCell.reuseID)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.recentCellID)
        tableView.applyNativeScrollEdges()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        buildKindFilter()

        emptyLabel.textColor = AppPalette.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            // Güvenli alana değil ekranın tepesine: içerik navigation bar ve
            // arama çubuğunun ardından geçip bulanıklaşıyor, sert bir çizgide
            // kesilmiyor. Dinlenme konumundaki boşluğu
            // `contentInsetAdjustmentBehavior` varsayılanı veriyor.
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .appLanguageDidChange,
            object: nil
        )
    }

    /// Sekmeye her geçişte klavye açık ve yazmaya hazır geliyor.
    /// tvOS'ta arama çubuğunun odağını `UISearchContainerViewController`
    /// kendisi veriyor; oraya elle dokunulmuyor.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.reloadData()
        #if os(iOS)
        // Görünüm hiyerarşisi tam oturmadan ilk yanıtlayıcı olmak sessizce
        // başarısız olabiliyor; bir tur sonraya bırakılıyor.
        DispatchQueue.main.async { [weak self] in
            self?.ownSearchController.searchBar.becomeFirstResponder()
        }
        #endif
    }

    /// Tablo başlığı Auto Layout ile boyutlanmıyor; çerçevesi elle veriliyor.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = tableView.bounds.width
        guard width > 0, kindFilterBar.frame.width != width else { return }
        kindFilterBar.frame = CGRect(x: 0, y: 0, width: width, height: Self.kindFilterHeight)
        tableView.tableHeaderView = kindFilterBar
    }

    private func buildKindFilter() {
        kindFilterBar.showsHorizontalScrollIndicator = false
        kindFilterBar.frame = CGRect(x: 0, y: 0, width: 320, height: Self.kindFilterHeight)

        kindFilterStack.axis = .horizontal
        kindFilterStack.spacing = 10
        kindFilterStack.translatesAutoresizingMaskIntoConstraints = false
        kindFilterBar.addSubview(kindFilterStack)

        NSLayoutConstraint.activate([
            kindFilterStack.topAnchor.constraint(equalTo: kindFilterBar.contentLayoutGuide.topAnchor, constant: 8),
            kindFilterStack.bottomAnchor.constraint(equalTo: kindFilterBar.contentLayoutGuide.bottomAnchor, constant: -8),
            kindFilterStack.leadingAnchor.constraint(equalTo: kindFilterBar.contentLayoutGuide.leadingAnchor, constant: 16),
            kindFilterStack.trailingAnchor.constraint(equalTo: kindFilterBar.contentLayoutGuide.trailingAnchor, constant: -16),
        ])

        reloadKindFilter()
        tableView.tableHeaderView = kindFilterBar
    }

    private func reloadKindFilter() {
        kindFilterStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        kindFilterStack.addArrangedSubview(makeKindChip(title: L10n.allKinds, kind: nil))
        for kind in MediaKind.allCases {
            kindFilterStack.addArrangedSubview(makeKindChip(title: kind.title, kind: kind))
        }
    }

    private func makeKindChip(title: String, kind: MediaKind?) -> UIButton {
        var configuration = UIButton.Configuration.appGlass(
            horizontalInset: 16, verticalInset: 8, fontSize: 14
        )
        configuration.title = title
        if selectedKind == kind {
            configuration.baseBackgroundColor = AppPalette.accent
        }

        let button = UIButton(configuration: configuration)
        button.addSpringPressFeedback(scale: 0.93)
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            selectedKind = kind
            reloadKindFilter()
            // Sorgu aynı kalıyor, yalnızca kapsam daraldı; sonucu tazele.
            if let searchController = activeSearchController {
                updateSearchResults(for: searchController)
            }
        }, for: .primaryActionTriggered)
        return button
    }

    @objc private func languageDidChange() {
        updateLocalizedTexts()
        reloadKindFilter()
        tableView.reloadData()
    }

    private func updateLocalizedTexts() {
        title = L10n.tabSearch
        activeSearchController?.searchBar.placeholder = L10n.searchPlaceholder
        updateEmptyLabel()
    }

    private func updateEmptyLabel() {
        emptyLabel.text = query.count >= 2 ? L10n.noSearchResults : L10n.searchPrompt
        emptyLabel.isHidden = isShowingRecents || !results.isEmpty
    }

    /// Sonuca ulaşan aramalar kaydediliyor: kullanıcı bir içeriğe girdiğinde
    /// ya da klavyedeki Ara'ya bastığında. Her tuş vuruşunu kaydetmek listeyi
    /// yarım kelimelerle dolduruyordu.
    private func recordCurrentQuery() {
        recentSearches.record(query)
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
        results = []
        tableView.reloadData()
        updateEmptyLabel()
    }
    #endif
}

extension SearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        searchWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            results = model.library.search(query, kinds: kinds)
            updateEmptyLabel()
            tableView.reloadData()
        }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isShowingRecents ? recentSearches.queries.count : results.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        isShowingRecents ? L10n.recentSearches : nil
    }

    /// Son aramalar başlığının sağında temizleme düğmesi.
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard isShowingRecents else { return nil }

        let label = UILabel()
        label.text = L10n.recentSearches
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = AppPalette.primaryText

        let clearButton = UIButton(type: .system)
        clearButton.setTitle(L10n.clearRecentSearches, for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 14)
        clearButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            recentSearches.clear()
            tableView.reloadData()
            updateEmptyLabel()
        }, for: .primaryActionTriggered)

        let row = UIStackView(arrangedSubviews: [label, UIView(), clearButton])
        row.axis = .horizontal
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 4, leading: 16, bottom: 4, trailing: 12)
        return row
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        isShowingRecents ? 40 : 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isShowingRecents {
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.recentCellID, for: indexPath)
            var configuration = UIListContentConfiguration.cell()
            configuration.text = recentSearches.queries[indexPath.row]
            configuration.textProperties.color = AppPalette.primaryText
            configuration.image = UIImage(systemName: "clock.arrow.circlepath")
            configuration.imageProperties.tintColor = AppPalette.secondaryText
            cell.contentConfiguration = configuration
            cell.backgroundColor = .clear
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: CatalogRowCell.reuseID, for: indexPath) as! CatalogRowCell
        let item = results[indexPath.row]
        cell.configure(
            item: item,
            metrics: AppMetrics.metrics(for: view.bounds.width),
            isFavorite: model.activity.isFavorite(item)
        )
        cell.onPlay = { [weak self] in Task { await self?.model.play(item) } }
        cell.onToggleFavorite = { [weak self] in self?.model.activity.toggleFavorite(item) }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if isShowingRecents {
            // Eski aramaya dokunmak onu arama çubuğuna yazıp sonuçları getiriyor.
            guard let searchController = activeSearchController else { return }
            searchController.searchBar.text = recentSearches.queries[indexPath.row]
            searchController.searchBar.becomeFirstResponder()
            updateSearchResults(for: searchController)
            return
        }

        let item = results[indexPath.row]
        recordCurrentQuery()
        guard item.kind != .live else {
            Task { await model.play(item) }
            return
        }
        let sourceView = (tableView.cellForRow(at: indexPath) as? CatalogRowCell)?.artworkView
        let controller = DetailViewController(item: item, model: model)
        controller.applyZoomTransition(from: sourceView)
        navigationController?.pushViewController(controller, animated: true)
    }
}
