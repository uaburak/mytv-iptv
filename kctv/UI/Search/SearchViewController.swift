import UIKit

/// Katalog belleğe alındığı için arama tamamen yerel çalışır; her tuşta
/// sunucuya gitmez. Bu, 50 bin kanallık listelerde bile anında sonuç verir.
final class SearchViewController: UIViewController {
    private let model: AppModel
    private let searchController = UISearchController(searchResultsController: nil)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    private var kinds: Set<MediaKind> = Set(MediaKind.allCases)
    private var results: [MediaItem] = []
    /// Her tuş vuruşunda katalogun tamamını taramamak için gecikme.
    private var searchWork: DispatchWorkItem?

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateLocalizedTexts()
        view.backgroundColor = AppPalette.background

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 96
        tableView.register(CatalogRowCell.self, forCellReuseIdentifier: CatalogRowCell.reuseID)
        tableView.applyNativeScrollEdges()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        emptyLabel.textColor = AppPalette.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
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

    @objc private func languageDidChange() {
        updateLocalizedTexts()
        tableView.reloadData()
    }

    private func updateLocalizedTexts() {
        title = L10n.tabSearch
        searchController.searchBar.placeholder = L10n.searchPlaceholder
        let query = searchController.searchBar.text ?? ""
        emptyLabel.text = query.count >= 2 ? L10n.noSearchResults : L10n.searchPrompt
    }
}

extension SearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text ?? ""
        searchWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            results = model.library.search(query, kinds: kinds)
            emptyLabel.text = query.count >= 2 ? L10n.noSearchResults : L10n.searchPrompt
            emptyLabel.isHidden = !results.isEmpty
            tableView.reloadData()
        }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
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
        let item = results[indexPath.row]
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
