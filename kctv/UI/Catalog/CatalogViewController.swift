import UIKit

/// Kategori seçicili içerik listesi.
/// Apple TV'nin kategori ekranıyla aynı satır düzeni: küçük afiş, başlık,
/// "yıl · tür" alt satırı ve sağda bağlam menüsü.
final class CatalogViewController: UIViewController {
    private let model: AppModel
    private let kind: MediaKind
    private let initialCategoryID: String?
    /// Verilmişse liste katalogdan değil bu diziden geliyor: arama ekranındaki
    /// hazır kartlar ("Aksiyon Filmleri") birden çok kategoriyi birleştirdiği
    /// için tek bir kategori kimliğiyle ifade edilemiyor.
    private let fixedItems: [MediaItem]?

    private var selectedCategoryID: String?
    private var items: [MediaItem] = []
    /// Şerit girintisi ilk kez uygulandığında liste başa alınıyor; sonraki
    /// düzen turlarında kaydırma konumuna dokunulmuyor.
    private var didApplyCategoryBarInset = false
    /// Tek seferde çizilen satır sayısı; katalogda 14 binden fazla kayıt olabiliyor.
    private var visibleCount = pageSize
    private static let pageSize = 120
    private static let categoryBarHeight: CGFloat = AppChipSize.regular.height + 12
    private static let categoryBarTopSpacing: CGFloat = 8
    private static let categoryBarBottomSpacing: CGFloat = 4
    /// tvOS'ta odaklanan kart büyüyor; ilk satır navigasyon çubuğunun altında
    /// kırpılmasın diye içerik biraz daha aşağıdan başlıyor.
    #if os(tvOS)
    private static let contentTopPadding: CGFloat = 40
    private static let contentBottomPadding: CGFloat = 60
    #else
    private static let contentTopPadding: CGFloat = 0
    private static let contentBottomPadding: CGFloat = 0
    #endif

    private let categoryBar = UIScrollView()
    private let categoryStack = UIStackView()
    private var collectionView: UICollectionView!
    private var emptyState: EmptyStateView!

    /// Varsayılan görünüm poster kart.
    private var displayMode: CatalogItemCell.DisplayMode = .grid
    private var displayModeBarButton: UIBarButtonItem?

    init(
        kind: MediaKind,
        model: AppModel,
        categoryID: String? = nil,
        items: [MediaItem]? = nil,
        title: String? = nil
    ) {
        self.kind = kind
        self.model = model
        self.initialCategoryID = categoryID
        self.selectedCategoryID = categoryID
        self.fixedItems = items
        super.init(nibName: nil, bundle: nil)
        self.title = title ?? kind.title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// tvOS'ta başlık navigasyon çubuğunda sabit durmuyor: içerikle birlikte
    /// kayan bir hero alanında duruyor. Alanın zemini sayfayla aynı renk,
    /// dolayısıyla ayrı bir kutu gibi görünmüyor.
    ///
    /// Kategori şeridiyle açılan ekranda hero yok: şerit zaten tepede yüzüyor
    /// ve başlık onun altından geçerdi.
    private var showsHeroTitle: Bool {
        #if os(tvOS)
        initialCategoryID != nil || fixedItems != nil
        #else
        false
        #endif
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        navigationItem.setPrefersLargeTitle(initialCategoryID == nil && fixedItems == nil)
        if showsHeroTitle {
            // Başlık hero alanında; çubukta ikinci kez yazmıyor.
            navigationItem.title = ""
        }
        buildLayout()
        #if os(iOS)
        setupDisplayModeButton()
        #endif
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
    /// kadar aşağıdan başlıyor. iOS'ta navigation bar payını kaydırma görünümü
    /// zaten güvenli alandan alıyor, buraya yalnızca şeridin payı ekleniyor;
    /// tvOS'ta güvenli alan ayarı kapalı olduğu için o pay da burada.
    private func updateCategoryBarInset() {
        let barInset = categoryBar.isHidden ? 0 : Self.categoryBarTopSpacing
            + categoryBar.bounds.height + Self.categoryBarBottomSpacing
        // tvOS'ta yatay payı elle verdiğimiz için (`.never`) dikey pay da
        // buradan geliyor: navigasyon çubuğu ve güvenli alan dahil.
        #if os(tvOS)
        let inset = view.safeAreaInsets.top + barInset + Self.contentTopPadding
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom + Self.contentBottomPadding
        #else
        let inset = barInset + Self.contentTopPadding
        #endif
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

    #if os(tvOS)
    /// Ekran açılınca odak ilk karta gidiyor; kategori şeridine yukarı basarak
    /// dönülüyor. Odak varsayılan olarak şeride düşünce kullanıcı her seferinde
    /// bir kez aşağı basmak zorunda kalıyordu.
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        guard let collectionView else { return super.preferredFocusEnvironments }
        return [collectionView]
    }
    #endif

    // MARK: - Görünüm modu (yalnızca iOS)

    #if os(iOS)
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
    #endif

    /// Kartın ekranda kaplayacağı genişlik; görsellerin indirme boyutu da
    /// buradan geliyor. Satır düzeninde de kart ölçüsünde indiriliyor, böylece
    /// görünüm değişince bulanık bir görselle kalınmıyor.
    private func gridItemWidth(metrics: AppMetrics) -> CGFloat {
        MediaSectionLayout.gridItemWidth(
            kind: kind, containerWidth: gridContentWidth, metrics: metrics
        )
    }

    /// Düzenin kullandığı genişlik. `view.bounds.width` değil: kaydırma
    /// görünümü güvenli alan kadar içeriden başlıyorsa düzen daha dar bir
    /// alanla çalışıyor ve iki hesap birbirini tutmuyordu.
    private var gridContentWidth: CGFloat {
        let insets = collectionView.adjustedContentInset
        return max(collectionView.bounds.width - insets.left - insets.right, 1)
    }

    private func makeCollectionLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] _, environment in
            guard let self else { return nil }
            let width = environment.container.effectiveContentSize.width
            let metrics = AppMetrics.metrics(for: width)
            // Izgara anasayfa ve arama ekranıyla ortak: sütun sayısı ekrandan
            // çıkıyor, sabit üç sütun tvOS'ta devasa kartlar üretiyordu.
            let grid = MediaSectionLayout.posterGrid(
                kind: kind, containerWidth: width, metrics: metrics
            )
            #if os(tvOS)
            // tvOS'ta liste düzeni yok: kumandayla gezilen bir ekranda afiş
            // ızgarası hem daha okunur hem de odak hareketi doğal.
            if showsHeroTitle {
                grid.boundarySupplementaryItems = [Self.heroHeader(metrics: metrics)]
            }
            return grid
            #else
            return displayMode == .grid ? grid : Self.listSection(metrics: metrics)
            #endif
        }
    }

    /// Kayan başlık alanı. Bölümün kendi girintisini paylaştığı için başlık
    /// ilk satırdaki kartla aynı hizada başlıyor.
    private static func heroHeader(metrics: AppMetrics) -> NSCollectionLayoutBoundarySupplementaryItem {
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(metrics.titleFont.lineHeight + 72)
            ),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        header.contentInsets = .zero
        return header
    }

    /// Satır düzeni yalnızca iOS'ta; tvOS'ta ızgaradan başka görünüm yok.
    #if os(iOS)
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
    #endif

    private func buildLayout() {
        categoryStack.axis = .horizontal
        // Çipler kendi doğal boylarında kalıyor: şerit onlardan yüksek ve
        // hizalama gerdirmeden ortalıyor.
        categoryStack.alignment = .center
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
        collectionView.prefetchDataSource = self
        collectionView.isPrefetchingEnabled = true
        collectionView.register(CatalogItemCell.self, forCellWithReuseIdentifier: CatalogItemCell.reuseID)
        collectionView.register(PosterCell.self, forCellWithReuseIdentifier: PosterCell.reuseID)
        collectionView.applyNativeScrollEdges()
        collectionView.register(
            CatalogHeroHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: CatalogHeroHeaderView.reuseID
        )
        #if os(tvOS)
        // Detaydan dönünce odak bırakılan kartta kalıyor.
        collectionView.remembersLastFocusedIndexPath = true
        // Güvenli alan payı kendiliğinden eklenince ızgara detay ekranından
        // daha içeriden başlıyordu: bölümün kendi girintisi (`screenPadding`)
        // güvenli alanın üstüne biniyor ve yan boşluk iki katına çıkıyordu.
        // Pay bu yüzden elle veriliyor; yatayda yalnızca `screenPadding` kalıyor
        // ve ekran detayla aynı hizada başlıyor.
        collectionView.contentInsetAdjustmentBehavior = .never
        #endif
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            categoryBar.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: Self.categoryBarTopSpacing
            ),
            categoryBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            categoryBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Şerit ortak çip ölçüsünden çıkıyor; tvOS'ta çipler 44pt'lik
            // bir şeride sığmıyordu.
            categoryBar.heightAnchor.constraint(equalToConstant: Self.categoryBarHeight),

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

        emptyState = EmptyStateView.installed(in: view)
        emptyState.configure(symbol: "tray", title: L10n.categoryEmpty)

        // Şerit listenin üstünde kalmalı; ikisi de `view`'ın alt görünümü.
        view.bringSubviewToFront(categoryBar)
    }

    // MARK: - Veri

    @objc private func libraryDidChange() {
        if initialCategoryID == nil, fixedItems == nil {
            title = kind.title
        }
        reloadCategories()
        reloadItems()
    }

    private func reloadCategories() {
        categoryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Belirli bir kategoriyle ya da hazır bir listeyle açıldıysa filtre
        // şeridi anlamsız.
        guard initialCategoryID == nil, fixedItems == nil else {
            categoryBar.isHidden = true
            return
        }

        let categories = model.library.categories[kind] ?? []
        guard categories.count > 1 else {
            categoryBar.isHidden = true
            return
        }
        categoryBar.isHidden = false

        let allTitle = L10n.allKinds
        categoryStack.addArrangedSubview(makeChip(title: allTitle, id: nil))
        for category in categories {
            categoryStack.addArrangedSubview(makeChip(title: category.name, id: category.id))
        }
    }

    private func makeChip(title: String, id: String?) -> UIButton {
        // Çipler kayan içeriğin üstünde yüzüyor; cam malzeme hem altındakini
        // okunur bırakıyor hem de listeden ayrışmasını sağlıyor. Stil arama
        // ekranındaki süzgeç ve detaydaki sezon çipleriyle ortak: seçili olan
        // beyaz zemin + siyah metin.
        var configuration = UIButton.Configuration.appChip(isSelected: selectedCategoryID == id)
        configuration.title = title

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
        items = fixedItems ?? model.library.items(kind: kind, categoryID: selectedCategoryID)
        collectionView.reloadData()
        // Kategoride içerik yoksa ekran tamamen boş kalmasın.
        emptyState.configure(symbol: "tray", title: L10n.categoryEmpty)
        emptyState.isHidden = !items.isEmpty
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
        let item = items[indexPath.item]
        let metrics = AppMetrics.metrics(for: view.bounds.width)

        #if os(tvOS)
        // Anasayfa ve gezinme ekranlarındaki kartın aynısı: odaklanınca büyüyor
        // ve başlık şeridi açılıyor. Kumandayla gezerken hangi içeriğin üstünde
        // olduğunu ancak bu şerit gösteriyor — afişin tek başına yeterli
        // olmadığı en çok bu ekranda görülüyor.
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PosterCell.reuseID, for: indexPath
        ) as! PosterCell
        cell.configure(
            item: item,
            metrics: metrics,
            progress: model.activity.progress(for: item.id),
            cardWidth: gridItemWidth(metrics: metrics)
        )
        return cell
        #else
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: CatalogItemCell.reuseID, for: indexPath
        ) as! CatalogItemCell
        cell.configure(
            item: item,
            metrics: metrics,
            mode: displayMode,
            imageWidth: gridItemWidth(metrics: metrics),
            isFavorite: model.activity.isFavorite(item)
        )
        cell.onPlay = { [weak self] in Task { await self?.model.play(item) } }
        cell.onToggleFavorite = { [weak self] in self?.model.activity.toggleFavorite(item) }
        return cell
        #endif
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: CatalogHeroHeaderView.reuseID, for: indexPath
        ) as! CatalogHeroHeaderView
        header.configure(
            title: title ?? "",
            font: AppMetrics.metrics(for: view.bounds.width).titleFont
        )
        return header
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

    /// Karta uzun basınca çıkan menü — İzle, favori, izleme listesi. Menünün
    /// kendisi `MediaCardMenu`'de: aynı kart her ekranda aynı eylemleri veriyor.
    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, let indexPath = indexPaths.first else { return nil }
        guard items.indices.contains(indexPath.item) else { return nil }
        let item = items[indexPath.item]
        return MediaCardMenu.configuration(for: item, model: model) { [weak self] item in
            guard let self else { return }
            navigationController?.pushViewController(
                DetailViewController(item: item, model: model), animated: true
            )
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let item = items[indexPath.item]

        guard item.kind != .live else {
            Task { await model.play(item) }
            return
        }
        let controller = DetailViewController(item: item, model: model)
        #if os(iOS)
        // Satır düzeninde afiş gizli ve çerçevesi yok; geçiş hücrenin
        // kendisinden başlıyor.
        let cell = collectionView.cellForItem(at: indexPath) as? CatalogItemCell
        controller.applyZoomTransition(from: displayMode == .grid ? cell?.artworkView : cell)
        #endif
        navigationController?.pushViewController(controller, animated: true)
    }
}

/// Liste ekranının kayan başlığı.
///
/// tvOS'ta başlık navigasyon çubuğunda sabit durmuyor: 10 feet mesafede ince
/// bir çubuk yazısı hem okunmuyor hem de ekranın üstünü sürekli işgal ediyor.
/// Başlık bunun yerine içerikle birlikte kayan bu alanda; zemini sayfanınkiyle
/// aynı olduğu için ayrı bir kutu gibi durmuyor, yalnızca yazı görünüyor.
final class CatalogHeroHeaderView: UICollectionReusableView {
    static let reuseID = "CatalogHeroHeaderView"

    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        titleLabel.textColor = AppPalette.primaryText
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            // Yazı alta yaslı: üstte navigasyon çubuğuyla arayı açan bir boşluk
            // kalıyor, altta da ilk kart satırıyla ölçülü bir aralık.
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, font: UIFont) {
        titleLabel.text = title
        titleLabel.font = font
    }
}

extension CatalogViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        let upcoming = indexPaths.compactMap { indexPath -> MediaItem? in
            items.indices.contains(indexPath.item) ? items[indexPath.item] : nil
        }
        MediaPrefetch.warm(
            upcoming, posterWidth: gridItemWidth(metrics: AppMetrics.metrics(for: view.bounds.width))
        )
    }
}
