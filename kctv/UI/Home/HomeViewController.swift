import UIKit

/// Ana sayfa: hero banner → ana kartlar → izlemeyi sürdür → kategori rayları.
final class HomeViewController: UIViewController {
    private enum Section: Hashable {
        case hero
        case mainCards
        case row(id: String, title: String, kind: MediaKind, categoryID: String?)
    }

    private enum Item: Hashable {
        case hero(MediaItem)
        case mainCard(MediaKind)
        case poster(rowID: String, item: MediaItem)
    }

    private let model: AppModel
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let spinner = UIActivityIndicatorView(style: .large)

    private var metrics: AppMetrics {
        AppMetrics.metrics(for: view.bounds.width)
    }

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Navigasyonda başlık yok; hero görseli tepeye kadar uzanıyor.
        title = nil
        view.backgroundColor = AppPalette.background
        navigationItem.largeTitleDisplayMode = .never
        setupAccountButton()
        setupCollectionView()
        setupDataSource()
        applySnapshot(animated: false)

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

    // MARK: - Kurulum

    /// Profil rozeti. Sabit boyutlu özel görünüm yerine hazır görsel
    /// kullanıyoruz: navigation bar öğe sarmalayıcısı kendi genişliğini
    /// dayattığı için 30pt'lik kısıt onunla çakışıp uyarı basıyordu.
    private func setupAccountButton() {
        let item = UIBarButtonItem(
            image: Self.avatarImage(initials: model.user?.initials ?? "?"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        item.accessibilityLabel = "Hesap ve ayarlar"
        navigationItem.rightBarButtonItem = item
    }

    private static func avatarImage(initials: String) -> UIImage {
        let side: CGFloat = 28
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            AppPalette.accent.withAlphaComponent(0.9).setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            let text = initials as NSString
            let bounds = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: (side - bounds.width) / 2, y: (side - bounds.height) / 2),
                withAttributes: attributes
            )
        }
        return image.withRenderingMode(.alwaysOriginal)
    }

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.applyNativeScrollEdges()

        collectionView.register(HeroCell.self, forCellWithReuseIdentifier: HeroCell.reuseID)
        collectionView.register(MainCardCell.self, forCellWithReuseIdentifier: MainCardCell.reuseID)
        collectionView.register(PosterCell.self, forCellWithReuseIdentifier: PosterCell.reuseID)
        collectionView.register(
            RowHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: RowHeaderView.reuseID
        )

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let self else { return nil }
            let metrics = AppMetrics.metrics(for: environment.container.contentSize.width)
            let section = dataSource.sectionIdentifier(for: index) ?? .mainCards

            switch section {
            case .hero:
                return self.heroSection(metrics: metrics)
            case .mainCards:
                return self.mainCardsSection(metrics: metrics)
            case let .row(_, _, kind, _):
                return self.posterRowSection(kind: kind, metrics: metrics)
            }
        }
    }

    /// Tam genişlikte, yatay sayfalamalı hero.
    private func heroSection(metrics: AppMetrics) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(metrics.heroHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .paging
        return section
    }

    private func mainCardsSection(metrics: AppMetrics) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: .absolute(metrics.mainCardWidth),
            heightDimension: .absolute(metrics.mainCardWidth * 0.56)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = metrics.cardSpacing
        section.orthogonalScrollingBehavior = .continuous
        section.contentInsets = NSDirectionalEdgeInsets(
            top: metrics.rowSpacing * 0.6,
            leading: metrics.screenPadding,
            bottom: metrics.rowSpacing * 0.5,
            trailing: metrics.screenPadding
        )
        return section
    }

    private func posterRowSection(kind: MediaKind, metrics: AppMetrics) -> NSCollectionLayoutSection {
        let width = metrics.cardWidth(for: kind)
        let height = metrics.rowItemHeight(for: kind)
        let size = NSCollectionLayoutSize(
            widthDimension: .absolute(width),
            heightDimension: .absolute(height)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = metrics.cardSpacing
        section.orthogonalScrollingBehavior = .continuous
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 12,
            leading: metrics.screenPadding,
            bottom: metrics.rowSpacing * 0.5,
            trailing: metrics.screenPadding
        )

        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(28)
        )
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        // Bölümün kendi girintisi zaten uygulanıyor; burada tekrar vermek
        // başlığı kartlardan iki kat içeri itiyordu.
        header.contentInsets = .zero
        section.boundarySupplementaryItems = [header]
        return section
    }

    // MARK: - Veri

    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            guard let self else { return nil }
            switch item {
            case let .hero(media):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: HeroCell.reuseID, for: indexPath
                ) as! HeroCell
                cell.configure(item: media, metrics: metrics, isFavorite: model.activity.isFavorite(media))
                cell.onDetails = { [weak self] in self?.openDetail($0) }
                cell.onToggleFavorite = { [weak self] in self?.model.activity.toggleFavorite($0) }
                return cell

            case let .mainCard(kind):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: MainCardCell.reuseID, for: indexPath
                ) as! MainCardCell
                cell.configure(kind: kind, count: model.library.catalog[kind]?.count ?? 0)
                return cell

            case let .poster(rowID, media):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: PosterCell.reuseID, for: indexPath
                ) as! PosterCell
                let progress = rowID == "continue" ? model.activity.progress(for: media.id) : nil
                cell.configure(item: media, metrics: metrics, progress: progress)
                return cell
            }
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard let self,
                  kind == UICollectionView.elementKindSectionHeader,
                  case let .row(_, title, mediaKind, categoryID) = dataSource.sectionIdentifier(for: indexPath.section)
            else { return nil }

            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind, withReuseIdentifier: RowHeaderView.reuseID, for: indexPath
            ) as! RowHeaderView
            header.configure(title: title, font: metrics.rowTitleFont, showsChevron: categoryID != nil)
            header.onTap = { [weak self] in
                self?.openCatalog(kind: mediaKind, categoryID: categoryID, title: title)
            }
            return header
        }
    }

    @objc private func libraryDidChange() {
        applySnapshot(animated: true)
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()

        let spotlight = model.library.spotlight
        if !spotlight.isEmpty {
            snapshot.appendSections([.hero])
            snapshot.appendItems(spotlight.map(Item.hero), toSection: .hero)
        }

        snapshot.appendSections([.mainCards])
        let mainCards = MediaKind.allCases.map(Item.mainCard)
        snapshot.appendItems(mainCards, toSection: .mainCards)

        // Ana kartların kimliği değişmediği için diffable onları yeniden
        // çizmiyordu ve içerik sayıları boş kalıyordu. Katalog güncellenince
        // bu hücreleri açıkça tazeliyoruz.
        let existing = dataSource.snapshot().itemIdentifiers
        let refreshable = mainCards.filter(existing.contains)
        if !refreshable.isEmpty {
            snapshot.reconfigureItems(refreshable)
        }

        let continueWatching = model.library.continueWatching
        if !continueWatching.isEmpty {
            let section = Section.row(id: "continue", title: L10n.continueWatching, kind: .movie, categoryID: nil)
            snapshot.appendSections([section])
            snapshot.appendItems(
                continueWatching.map { Item.poster(rowID: "continue", item: $0.item) },
                toSection: section
            )
        }

        for row in model.library.rows {
            let section = Section.row(id: row.id, title: row.title, kind: row.kind, categoryID: row.categoryID)
            snapshot.appendSections([section])
            snapshot.appendItems(
                row.items.map { Item.poster(rowID: row.id, item: $0) },
                toSection: section
            )
        }

        dataSource.apply(snapshot, animatingDifferences: animated)

        let isEmpty = snapshot.numberOfItems == MediaKind.allCases.count
        isEmpty && model.library.state == .loading ? spinner.startAnimating() : spinner.stopAnimating()
    }

    // MARK: - Gezinme

    @objc private func openSettings() {
        let controller = SettingsViewController(model: model)
        present(UINavigationController(rootViewController: controller), animated: true)
    }

    private func openDetail(_ item: MediaItem, sourceView: UIView? = nil) {
        // Canlı kanalın detay ekranı yok; doğrudan player açılır.
        guard item.kind != .live else {
            Task { await model.play(item) }
            return
        }
        let controller = DetailViewController(item: item, model: model)
        controller.applyZoomTransition(from: sourceView)
        navigationController?.pushViewController(controller, animated: true)
    }

    private func openCatalog(kind: MediaKind, categoryID: String?, title: String) {
        let controller = CatalogViewController(kind: kind, model: model, categoryID: categoryID, title: title)
        navigationController?.pushViewController(controller, animated: true)
    }
}

extension HomeViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case let .poster(_, media):
            openDetail(media, sourceView: collectionView.cellForItem(at: indexPath))
        case let .mainCard(kind):
            navigationController?.pushViewController(
                KindBrowseViewController(kind: kind, model: model),
                animated: true
            )
        case .hero:
            break
        }
    }
}
