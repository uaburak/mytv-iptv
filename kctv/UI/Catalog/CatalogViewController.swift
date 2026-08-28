import UIKit

/// Kategori seçicili içerik listesi.
/// Apple TV'nin kategori ekranıyla aynı satır düzeni: küçük afiş, başlık,
/// "yıl · tür" alt satırı ve sağda bağlam menüsü.
final class CatalogViewController: UIViewController {
    private let model: AppModel
    private let kind: MediaKind
    private let initialCategoryID: String?

    private var selectedCategoryID: String?
    private var items: [MediaItem] = []
    /// Tek seferde çizilen satır sayısı; katalogda 14 binden fazla kayıt olabiliyor.
    private var visibleCount = pageSize
    private static let pageSize = 120

    private let categoryBar = UIScrollView()
    private let categoryStack = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(kind: MediaKind, model: AppModel, categoryID: String? = nil, title: String? = nil) {
        self.kind = kind
        self.model = model
        self.initialCategoryID = categoryID
        self.selectedCategoryID = categoryID
        super.init(nibName: nil, bundle: nil)
        self.title = title ?? kind.title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        navigationItem.largeTitleDisplayMode = initialCategoryID == nil ? .always : .never
        buildLayout()
        reloadCategories()
        reloadItems()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(libraryDidChange),
            name: .contentLibraryDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(libraryDidChange),
            name: .appLanguageDidChange,
            object: nil
        )
    }

    private func buildLayout() {
        categoryStack.axis = .horizontal
        categoryStack.spacing = 10
        categoryStack.translatesAutoresizingMaskIntoConstraints = false
        categoryBar.addSubview(categoryStack)
        categoryBar.showsHorizontalScrollIndicator = false
        categoryBar.applyNativeScrollEdges()
        categoryBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(categoryBar)

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

        NSLayoutConstraint.activate([
            categoryBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            categoryBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            categoryBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            categoryBar.heightAnchor.constraint(equalToConstant: 44),

            categoryStack.topAnchor.constraint(equalTo: categoryBar.contentLayoutGuide.topAnchor),
            categoryStack.bottomAnchor.constraint(equalTo: categoryBar.contentLayoutGuide.bottomAnchor),
            categoryStack.leadingAnchor.constraint(equalTo: categoryBar.contentLayoutGuide.leadingAnchor, constant: 16),
            categoryStack.trailingAnchor.constraint(equalTo: categoryBar.contentLayoutGuide.trailingAnchor, constant: -16),
            categoryStack.heightAnchor.constraint(equalTo: categoryBar.frameLayoutGuide.heightAnchor),

            tableView.topAnchor.constraint(equalTo: categoryBar.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Veri

    @objc private func libraryDidChange() {
        if initialCategoryID == nil {
            title = kind.title
        }
        reloadCategories()
        reloadItems()
    }

    private func reloadCategories() {
        categoryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Belirli bir kategoriyle açıldıysa filtre şeridi anlamsız.
        guard initialCategoryID == nil else {
            categoryBar.isHidden = true
            return
        }

        let categories = model.library.categories[kind] ?? []
        guard categories.count > 1 else {
            categoryBar.isHidden = true
            return
        }
        categoryBar.isHidden = false

        let allTitle = AppLanguage.current.effectiveLanguageCode == "tr" ? "Tümü" : "All"
        categoryStack.addArrangedSubview(makeChip(title: allTitle, id: nil))
        for category in categories {
            categoryStack.addArrangedSubview(makeChip(title: category.name, id: category.id))
        }
    }

    private func makeChip(title: String, id: String?) -> UIButton {
        var configuration = UIButton.Configuration.bordered()
        configuration.title = title
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = selectedCategoryID == id
            ? AppPalette.accent.withAlphaComponent(0.35)
            : AppPalette.elevated

        let button = UIButton(configuration: configuration)
        button.addAction(UIAction { [weak self] _ in
            self?.selectedCategoryID = id
            self?.visibleCount = Self.pageSize
            self?.reloadCategories()
            self?.reloadItems()
            self?.tableView.setContentOffset(.zero, animated: false)
        }, for: .touchUpInside)
        return button
    }

    private func reloadItems() {
        items = model.library.items(kind: kind, categoryID: selectedCategoryID)
        tableView.reloadData()
    }

    private var visibleItems: ArraySlice<MediaItem> {
        items.prefix(visibleCount)
    }
}

extension CatalogViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CatalogRowCell.reuseID, for: indexPath) as! CatalogRowCell
        let item = items[indexPath.row]
        cell.configure(
            item: item,
            metrics: AppMetrics.metrics(for: view.bounds.width),
            isFavorite: model.activity.isFavorite(item)
        )
        cell.onPlay = { [weak self] in Task { await self?.model.play(item) } }
        cell.onToggleFavorite = { [weak self] in self?.model.activity.toggleFavorite(item) }
        return cell
    }

    /// Sona yaklaşınca bir sayfa daha açar.
    ///
    /// Eskiden `cellForRowAt` içinden `reloadData()` çağrılıyordu; bu, hücre
    /// üretilirken bütün tabloyu yeniden kurduğu için hem gereksiz iş hem de
    /// kaydırmada takılma üretiyordu. Artık yalnızca yeni satırlar ekleniyor.
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let threshold = visibleCount - 12
        guard indexPath.row >= threshold, visibleCount < items.count else { return }

        let previous = visibleCount
        visibleCount = min(visibleCount + Self.pageSize, items.count)
        let inserted = (previous..<visibleCount).map { IndexPath(row: $0, section: 0) }
        tableView.performBatchUpdates {
            tableView.insertRows(at: inserted, with: .none)
        }
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
}
