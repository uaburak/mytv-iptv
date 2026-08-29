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
    /// Şerit girintisi ilk kez uygulandığında liste başa alınıyor; sonraki
    /// düzen turlarında kaydırma konumuna dokunulmuyor.
    private var didApplyCategoryBarInset = false
    /// Tek seferde çizilen satır sayısı; katalogda 14 binden fazla kayıt olabiliyor.
    private var visibleCount = pageSize
    private static let pageSize = 120
    private static let categoryBarTopSpacing: CGFloat = 8
    private static let categoryBarBottomSpacing: CGFloat = 4

    private static let gridColumns = 3
    private static let gridSpacing: CGFloat = 12

    private let categoryBar = UIScrollView()
    private let categoryStack = UIStackView()
    private var collectionView: UICollectionView!
    private let emptyLabel = UILabel()

    /// Varsayılan görünüm poster kart.
    private var displayMode: CatalogItemCell.DisplayMode = .grid
    private var displayModeBarButton: UIBarButtonItem?

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
        navigationItem.setPrefersLargeTitle(initialCategoryID == nil)
        buildLayout()
        setupDisplayModeButton()
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCategoryBarInset()
    }

    /// Kategori şeridi listenin üstünde yüzdüğü için liste onun kapladığı
    /// kadar aşağıdan başlıyor. Navigation bar payını kaydırma görünümü zaten
    /// güvenli alandan alıyor; buraya yalnızca şeridin payı ekleniyor.
    private func updateCategoryBarInset() {
        let inset = categoryBar.isHidden ? 0 : Self.categoryBarTopSpacing
            + categoryBar.bounds.height + Self.categoryBarBottomSpacing
        guard collectionView.contentInset.top != inset else { return }
        collectionView.contentInset.top = inset
        collectionView.verticalScrollIndicatorInsets.top = inset

        // Girinti değiştiğinde kaydırma görünümü konumu kendiliğinden
        // düzeltmiyor; ilk kurulumda liste tepeye alınıyor.
        guard !didApplyCategoryBarInset else { return }
        didApplyCategoryBarInset = true
        scrollToTop()
    }

    private func scrollToTop() {
        collectionView.setContentOffset(
            CGPoint(x: 0, y: -collectionView.adjustedContentInset.top),
            animated: false
        )
    }

    // MARK: - Görünüm modu

    private func setupDisplayModeButton() {
        let item = UIBarButtonItem(
            image: displayModeImage,
            style: .plain,
            target: self,
            action: #selector(toggleDisplayMode)
        )
        item.accessibilityLabel = displayModeAccessibilityLabel
        navigationItem.rightBarButtonItem = item
        displayModeBarButton = item
    }

    /// Simge, basınca geçilecek görünümü gösteriyor.
    private var displayModeImage: UIImage? {
        UIImage(systemName: displayMode == .grid ? "list.bullet" : "square.grid.2x2")
    }

    private var displayModeAccessibilityLabel: String {
        let isTurkish = AppLanguage.current.effectiveLanguageCode == "tr"
        if displayMode == .grid {
            return isTurkish ? "Liste görünümü" : "List view"
        }
        return isTurkish ? "Kart görünümü" : "Card view"
    }

    @objc private func toggleDisplayMode() {
        displayMode = displayMode == .grid ? .list : .grid

        if let image = displayModeImage {
            displayModeBarButton?.setSymbolImage(image, contentTransition: .replace.offUp)
        }
        displayModeBarButton?.accessibilityLabel = displayModeAccessibilityLabel

        Haptics.impact(.light)

        // Düzen değişimi hücreleri yeni yerlerine taşırken, hücreler de kendi
        // içlerini aynı anda dönüştürüyor. Hücre sınıfı ikisinde de aynı
        // olduğu için yeniden yüklemeye gerek yok ve geçiş kesintisiz.
        collectionView.setCollectionViewLayout(makeCollectionLayout(), animated: true)
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            for case let cell as CatalogItemCell in self.collectionView.visibleCells {
                cell.applyMode(self.displayMode)
            }
        }
    }

    /// Kart düzenindeki bir sütunun genişliği. Görsellerin indirme boyutu da
    /// buradan geliyor: iki modda da kart ölçüsünde indiriliyor, böylece
    /// görünüm değişince bulanık bir görselle kalınmıyor.
    private static func gridItemWidth(containerWidth: CGFloat, metrics: AppMetrics) -> CGFloat {
        let spacing = gridSpacing * CGFloat(gridColumns - 1)
        let available = containerWidth - metrics.screenPadding * 2 - spacing
        return max(available / CGFloat(gridColumns), 1)
    }

    private func makeCollectionLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] _, environment in
            guard let self else { return nil }
            let width = environment.container.effectiveContentSize.width
            let metrics = AppMetrics.metrics(for: width)
            return displayMode == .grid
                ? Self.gridSection(containerWidth: width, kind: kind, metrics: metrics)
                : Self.listSection(metrics: metrics)
        }
    }

    private static func gridSection(
        containerWidth: CGFloat,
        kind: MediaKind,
        metrics: AppMetrics
    ) -> NSCollectionLayoutSection {
        let itemWidth = gridItemWidth(containerWidth: containerWidth, metrics: metrics)
        // Kartta yalnızca afiş var; yükseklik tamamen afişin oranı.
        let itemHeight = itemWidth / kind.posterAspect

        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(itemWidth),
                heightDimension: .absolute(itemHeight)
            )
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(itemHeight)
            ),
            repeatingSubitem: item,
            count: gridColumns
        )
        group.interItemSpacing = .fixed(gridSpacing)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 18
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: metrics.screenPadding, bottom: 24, trailing: metrics.screenPadding
        )
        return section
    }

    private static func listSection(metrics: AppMetrics) -> NSCollectionLayoutSection {
        let itemHeight = metrics.posterWidth * 0.62 + 20
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(itemHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 24, trailing: 0)
        return section
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

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeCollectionLayout())
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CatalogItemCell.self, forCellWithReuseIdentifier: CatalogItemCell.reuseID)
        collectionView.applyNativeScrollEdges()
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            categoryBar.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: Self.categoryBarTopSpacing
            ),
            categoryBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            categoryBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            categoryBar.heightAnchor.constraint(equalToConstant: 44),

            categoryStack.topAnchor.constraint(equalTo: categoryBar.contentLayoutGuide.topAnchor),
            categoryStack.bottomAnchor.constraint(equalTo: categoryBar.contentLayoutGuide.bottomAnchor),
            categoryStack.leadingAnchor.constraint(equalTo: categoryBar.contentLayoutGuide.leadingAnchor, constant: 16),
            categoryStack.trailingAnchor.constraint(equalTo: categoryBar.contentLayoutGuide.trailingAnchor, constant: -16),
            categoryStack.heightAnchor.constraint(equalTo: categoryBar.frameLayoutGuide.heightAnchor),

            // Liste hem navigation bar'ın hem de kategori şeridinin ardından
            // geçiyor; şerit içeriğin üstünde yüzüyor. Dinlenme konumundaki
            // boşluğun navigation bar payını `contentInsetAdjustmentBehavior`
            // varsayılanı, şerit payını `updateCategoryBarInset()` veriyor.
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        emptyLabel.text = L10n.categoryEmpty
        emptyLabel.textColor = AppPalette.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
        ])

        // Şerit listenin üstünde kalmalı; ikisi de `view`'ın alt görünümü.
        view.bringSubviewToFront(categoryBar)
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
        // Çipler artık kayan içeriğin üstünde yüzüyor; cam malzeme hem
        // altındakini okunur bırakıyor hem de listeden ayrışmasını sağlıyor.
        var configuration = UIButton.Configuration.appGlass(
            horizontalInset: 16, verticalInset: 8, fontSize: 14
        )
        configuration.title = title
        if selectedCategoryID == id {
            configuration.baseBackgroundColor = AppPalette.accent
        }

        let button = UIButton(configuration: configuration)
        button.addSpringPressFeedback(scale: 0.93)
        button.addAction(UIAction { [weak self] _ in
            self?.selectedCategoryID = id
            self?.visibleCount = Self.pageSize
            self?.reloadCategories()
            self?.reloadItems()
            self?.scrollToTop()
        }, for: .primaryActionTriggered)
        return button
    }

    private func reloadItems() {
        items = model.library.items(kind: kind, categoryID: selectedCategoryID)
        collectionView.reloadData()
        // Kategoride içerik yoksa ekran tamamen boş kalmasın.
        emptyLabel.isHidden = !items.isEmpty
    }

    private var visibleItems: ArraySlice<MediaItem> {
        items.prefix(visibleCount)
    }
}

extension CatalogViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        visibleItems.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: CatalogItemCell.reuseID, for: indexPath
        ) as! CatalogItemCell
        let item = items[indexPath.item]
        let metrics = AppMetrics.metrics(for: view.bounds.width)
        cell.configure(
            item: item,
            metrics: metrics,
            mode: displayMode,
            imageWidth: Self.gridItemWidth(containerWidth: view.bounds.width, metrics: metrics),
            isFavorite: model.activity.isFavorite(item)
        )
        cell.onPlay = { [weak self] in Task { await self?.model.play(item) } }
        cell.onToggleFavorite = { [weak self] in self?.model.activity.toggleFavorite(item) }
        return cell
    }

    /// Sona yaklaşınca bir sayfa daha açar.
    ///
    /// Eskiden hücre üretilirken `reloadData()` çağrılıyordu; bu, bütün listeyi
    /// yeniden kurduğu için hem gereksiz iş hem de kaydırmada takılma
    /// üretiyordu. Artık yalnızca yeni öğeler ekleniyor.
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        #if os(tvOS)
        collectionView.unclipFocusGrowth(around: cell)
        #endif

        let threshold = visibleCount - 12
        guard indexPath.item >= threshold, visibleCount < items.count else { return }

        let previous = visibleCount
        visibleCount = min(visibleCount + Self.pageSize, items.count)
        let inserted = (previous..<visibleCount).map { IndexPath(item: $0, section: 0) }
        collectionView.performBatchUpdates {
            collectionView.insertItems(at: inserted)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let item = items[indexPath.item]

        guard item.kind != .live else {
            Task { await model.play(item) }
            return
        }
        // Satır düzeninde afiş gizli ve çerçevesi yok; geçiş hücrenin
        // kendisinden başlıyor.
        let cell = collectionView.cellForItem(at: indexPath) as? CatalogItemCell
        let sourceView = displayMode == .grid ? cell?.artworkView : cell
        let controller = DetailViewController(item: item, model: model)
        controller.applyZoomTransition(from: sourceView)
        navigationController?.pushViewController(controller, animated: true)
    }
}
