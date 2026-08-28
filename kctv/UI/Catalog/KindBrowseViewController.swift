import UIKit

/// Ana karttan (Canlı / Film / Dizi) açılan gezinme ekranı.
///
/// Liste değil, anasayfadaki gibi kategorilere bölünmüş poster rayları.
/// Sağ üstteki filtre yalnızca tek bir kategoriye daralmayı sağlıyor.
final class KindBrowseViewController: UIViewController {
    private enum Section: Hashable {
        case category(id: String, title: String)
    }

    private struct Item: Hashable {
        var categoryID: String
        var media: MediaItem
    }

    private let model: AppModel
    private let kind: MediaKind

    /// nil ise bütün kategoriler listeleniyor.
    private var filterCategoryID: String?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

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
        navigationItem.largeTitleDisplayMode = .never
        setupCollectionView()
        setupDataSource()
        setupFilterButton()
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

    @objc private func languageDidChange() {
        title = kind.title
        navigationItem.rightBarButtonItem?.menu = makeFilterMenu()
        applySnapshot(animated: true)
    }

    // MARK: - Kurulum

    private func setupFilterButton() {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease"),
            style: .plain,
            target: nil,
            action: nil
        )
        item.accessibilityLabel = AppLanguage.current.effectiveLanguageCode == "tr" ? "Kategori filtresi" : "Category filter"
        item.menu = makeFilterMenu()
        navigationItem.rightBarButtonItem = item
    }

    private func makeFilterMenu() -> UIMenu {
        let allTitle = AppLanguage.current.effectiveLanguageCode == "tr" ? "Tümü" : "All"
        var actions: [UIAction] = [
            UIAction(title: allTitle, state: filterCategoryID == nil ? .on : .off) { [weak self] _ in
                self?.applyFilter(nil)
            },
        ]
        actions += categories.map { category in
            UIAction(title: category.name, state: filterCategoryID == category.id ? .on : .off) { [weak self] _ in
                self?.applyFilter(category.id)
            }
        }
        return UIMenu(children: actions)
    }

    private func applyFilter(_ categoryID: String?) {
        filterCategoryID = categoryID
        navigationItem.rightBarButtonItem?.menu = makeFilterMenu()
        applySnapshot(animated: true)
        collectionView.setContentOffset(.zero, animated: false)
    }

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.applyNativeScrollEdges()
        collectionView.register(PosterCell.self, forCellWithReuseIdentifier: PosterCell.reuseID)
        collectionView.register(
            RowHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: RowHeaderView.reuseID
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] _, environment in
            guard let self else { return nil }
            let metrics = AppMetrics.metrics(for: environment.container.contentSize.width)

            let size = NSCollectionLayoutSize(
                widthDimension: .absolute(metrics.cardWidth(for: kind)),
                heightDimension: .absolute(metrics.rowItemHeight(for: kind))
            )
            let item = NSCollectionLayoutItem(layoutSize: size)
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = metrics.cardSpacing
            section.orthogonalScrollingBehavior = .continuous
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 10,
                leading: metrics.screenPadding,
                bottom: metrics.rowSpacing * 0.5,
                trailing: metrics.screenPadding
            )

            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(28)
            )
            section.boundarySupplementaryItems = [
                NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: headerSize,
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                ),
            ]
            return section
        }
    }

    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            guard let self else { return nil }
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: PosterCell.reuseID, for: indexPath
            ) as! PosterCell
            cell.configure(item: item.media, metrics: metrics, progress: nil)
            return cell
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard let self,
                  kind == UICollectionView.elementKindSectionHeader,
                  case let .category(id, title) = dataSource.sectionIdentifier(for: indexPath.section)
            else { return nil }

            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind, withReuseIdentifier: RowHeaderView.reuseID, for: indexPath
            ) as! RowHeaderView
            header.configure(title: title, font: metrics.rowTitleFont, showsChevron: true)
            header.onTap = { [weak self] in
                self?.openCategoryList(id: id, title: title)
            }
            return header
        }
    }

    // MARK: - Veri

    private var categories: [MediaCategory] {
        model.library.categories[kind] ?? []
    }

    @objc private func libraryDidChange() {
        navigationItem.rightBarButtonItem?.menu = makeFilterMenu()
        applySnapshot(animated: true)
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()

        let visible = categories.filter { filterCategoryID == nil || $0.id == filterCategoryID }
        for category in visible {
            let items = model.library.items(kind: kind, categoryID: category.id)
            guard !items.isEmpty else { continue }

            let section = Section.category(id: category.id, title: category.name)
            snapshot.appendSections([section])
            // Ray başına makul bir üst sınır; tamamı "tümünü gör" ile açılıyor.
            snapshot.appendItems(
                items.prefix(24).map { Item(categoryID: category.id, media: $0) },
                toSection: section
            )
        }
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    // MARK: - Gezinme

    private func openCategoryList(id: String, title: String) {
        let controller = CatalogViewController(kind: kind, model: model, categoryID: id, title: title)
        navigationController?.pushViewController(controller, animated: true)
    }
}

extension KindBrowseViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        // Canlı kanalın detay ekranı yok; doğrudan player açılır.
        guard item.media.kind != .live else {
            Task { await model.play(item.media) }
            return
        }
        let controller = DetailViewController(item: item.media, model: model)
        controller.applyZoomTransition(from: collectionView.cellForItem(at: indexPath))
        navigationController?.pushViewController(controller, animated: true)
    }
}
