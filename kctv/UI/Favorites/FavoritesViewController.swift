import UIKit

/// Favorilere eklenen içerikler. Katalogla aynı satır düzenini kullanıyor.
final class FavoritesViewController: UIViewController {
    private let model: AppModel
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    private var items: [MediaItem] = []

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        updateLocalizedTexts()

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

        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = AppPalette.secondaryText
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
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(reload), name: .appModelFavoritesDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageDidChange), name: .appLanguageDidChange, object: nil
        )
    }

    @objc private func languageDidChange() {
        updateLocalizedTexts()
        tableView.reloadData()
    }

    private func updateLocalizedTexts() {
        title = L10n.tabFavorites
        emptyLabel.text = "\(L10n.favoritesEmptyTitle)\n\(L10n.favoritesEmptyMessage)"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    @objc private func reload() {
        items = model.activity.favorites
        emptyLabel.isHidden = !items.isEmpty
        tableView.reloadData()
    }
}

extension FavoritesViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CatalogRowCell.reuseID, for: indexPath) as! CatalogRowCell
        let item = items[indexPath.row]
        cell.configure(item: item, metrics: AppMetrics.metrics(for: view.bounds.width), isFavorite: true)
        cell.onPlay = { [weak self] in Task { await self?.model.play(item) } }
        cell.onToggleFavorite = { [weak self] in self?.model.activity.toggleFavorite(item) }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        guard item.kind != .live else {
            Task { await model.play(item) }
            return
        }
        let sourceView = (tableView.cellForRow(at: indexPath) as? CatalogRowCell)?.artworkView
        let controller = DetailViewController(item: item, model: model)
        controller.applyZoomTransition(from: sourceView)
        navigationController?.pushViewController(controller, animated: true)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let item = items[indexPath.row]
        let removeTitle = AppLanguage.current.effectiveLanguageCode == "tr" ? "Çıkar" : "Remove"
        let remove = UIContextualAction(style: .destructive, title: removeTitle) { [weak self] _, _, done in
            self?.model.activity.toggleFavorite(item)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }
}
