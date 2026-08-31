import UIKit

/// Favorilere eklenen içerikler.
///
/// Düzen katalog ve arama sonuçlarıyla aynı: tür türe ayrılmış afiş ızgarası,
/// aynı `PosterCell`, aynı `MediaSectionLayout`. Ekran daha önce kendi satır
/// hücresini çiziyordu — uygulamanın tek liste görünümü oydu ve tvOS'ta minik
/// afişli bir tablo olarak duruyordu.
final class FavoritesViewController: UIViewController {
    private enum Section: Hashable {
        case kind(MediaKind)
    }

    /// Sıra: aranan şey çoğunlukla bir film ya da dizi, kanallar en altta —
    /// arama ekranıyla aynı.
    private static let order: [MediaKind] = [.movie, .series, .live]

    private let model: AppModel
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, MediaItem>!
    private var emptyState: EmptyStateView!

    #if os(tvOS)
    /// Apple TV'de ekranın kendi başlığı ve tür süzgeci içerikte duruyor.
    ///
    /// Navigasyon çubuğundaki başlık burada işe yaramıyor: kenar çubuğu
    /// tasarımında çubuk gizli ve ekran adsız açılıyordu. Süzgeç de tvOS'a
    /// özgü: kumandayla ızgarada gezinirken "yalnızca dizilerim" demek
    /// aşağı doğru uzun bir yolculuktan kısa.
    private let headerStack = UIStackView()
    private let headerTitle = UILabel()
    private let filterRow = UIStackView()
    private var filterButtons: [MediaKind?: UIButton] = [:]
    private var selectedKind: MediaKind?
    #endif

    /// Düzen kapanışı bölümü sıra numarasıyla soruyor; anlık görüntüdeki sıra
    /// burada tutuluyor.
    private var visibleKinds: [MediaKind] = []

    private var metrics: AppMetrics { AppMetrics.metrics(for: view.bounds.width) }

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        navigationItem.setPrefersLargeTitle(false)
        #if os(tvOS)
        // Başlık içerikte; çubukta ikinci kez yazmıyor.
        navigationItem.title = ""
        setupHeader()
        #endif
        setupCollectionView()
        setupDataSource()
        emptyState = EmptyStateView.installed(in: view)
        updateLocalizedTexts()
        applySnapshot(animated: false)

        NotificationCenter.default.addObserver(
            self, selector: #selector(reload), name: .appModelFavoritesDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(reload), name: .contentLibraryDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageDidChange), name: .appLanguageDidChange, object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applySnapshot(animated: false)
    }

    // MARK: - Kurulum

    #if os(tvOS)
    private func setupHeader() {
        headerTitle.font = TVFormMetrics.titleFont
        headerTitle.textColor = .white

        filterRow.axis = .horizontal
        filterRow.spacing = 16
        filterRow.alignment = .center

        headerStack.axis = .vertical
        headerStack.spacing = 26
        headerStack.alignment = .leading
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.addArrangedSubview(headerTitle)
        headerStack.addArrangedSubview(filterRow)
        view.addSubview(headerStack)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(
                equalTo: view.topAnchor, constant: TVFormMetrics.topInset
            ),
            headerStack.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: AppMetrics.tv.screenPadding
            ),
            headerStack.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -AppMetrics.tv.screenPadding
            ),
        ])
    }

    /// Süzgeç çipleri: yalnızca içeriği olan türler çıkıyor, sayılarıyla.
    private func rebuildFilterRow(counts: [MediaKind: Int]) {
        let available = Self.order.filter { (counts[$0] ?? 0) > 0 }
        // Tek tür varsa süzgeç bir şey yapmıyor; satır da görünmüyor.
        filterRow.isHidden = available.count < 2
        if let selectedKind, !available.contains(selectedKind) { self.selectedKind = nil }

        for view in filterRow.arrangedSubviews {
            filterRow.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        filterButtons = [:]

        let total = counts.values.reduce(0, +)
        addFilterButton(kind: nil, title: L10n.filterCount(L10n.allKinds, total))
        for kind in available {
            addFilterButton(kind: kind, title: L10n.filterCount(kind.title, counts[kind] ?? 0))
        }
    }

    private func addFilterButton(kind: MediaKind?, title: String) {
        var configuration = UIButton.Configuration.appChip(isSelected: kind == selectedKind)
        configuration.title = title
        let button = UIButton(configuration: configuration)
        button.addSpringPressFeedback(scale: 0.95)
        button.addAction(UIAction { [weak self] _ in
            guard let self, selectedKind != kind else { return }
            selectedKind = kind
            applySnapshot(animated: true)
        }, for: .primaryActionTriggered)
        filterButtons[kind] = button
        filterRow.addArrangedSubview(button)
    }
    #endif

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.isPrefetchingEnabled = true
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

        #if os(tvOS)
        // Izgara başlığın altından başlıyor.
        let topAnchor = headerStack.bottomAnchor
        let topSpacing: CGFloat = 40
        #else
        // Güvenli alana değil ekranın tepesine bağlanıyor: içerik
        // navigation bar'ın ardından geçip bulanıklaşıyor, sert bir çizgide
        // kesilmiyor. Dinlenme konumundaki boşluğu
        // `contentInsetAdjustmentBehavior` varsayılanı veriyor.
        let topAnchor = view.topAnchor
        let topSpacing: CGFloat = 0
        #endif

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor, constant: topSpacing),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let self, index < visibleKinds.count else { return nil }
            let width = environment.container.effectiveContentSize.width
            return MediaSectionLayout.posterGrid(
                kind: visibleKinds[index],
                containerWidth: width,
                metrics: AppMetrics.metrics(for: width),
                // Tek tür varsa başlık gereksiz: ekranın başlığı zaten
                // "Favoriler" ve altında tek bir ızgara duruyor.
                showsHeader: visibleKinds.count > 1
            )
        }
    }

    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, MediaItem>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            guard let self else { return nil }
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: PosterCell.reuseID, for: indexPath
            ) as! PosterCell
            cell.configure(
                item: item,
                metrics: metrics,
                progress: model.activity.progress(for: item.id),
                cardWidth: cardWidth(for: item.kind)
            )
            return cell
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, elementKind, indexPath in
            guard let self,
                  elementKind == UICollectionView.elementKindSectionHeader,
                  case let .kind(mediaKind) = dataSource.sectionIdentifier(for: indexPath.section)
            else { return nil }

            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: elementKind, withReuseIdentifier: RowHeaderView.reuseID, for: indexPath
            ) as! RowHeaderView
            header.configure(title: mediaKind.title, font: metrics.rowTitleFont, showsChevron: false)
            return header
        }
    }

    /// Kartın ekranda kaplayacağı genişlik — düzenle **aynı** hesap; görselin
    /// indirme boyutu da buradan geliyor.
    private func cardWidth(for kind: MediaKind) -> CGFloat {
        let insets = collectionView.adjustedContentInset
        let width = max(collectionView.bounds.width - insets.left - insets.right, 1)
        return MediaSectionLayout.gridItemWidth(kind: kind, containerWidth: width, metrics: metrics)
    }

    // MARK: - Veri

    @objc private func reload() {
        applySnapshot(animated: true)
    }

    @objc private func languageDidChange() {
        updateLocalizedTexts()
        applySnapshot(animated: false)
    }

    private func updateLocalizedTexts() {
        title = L10n.tabFavorites
        #if os(tvOS)
        navigationItem.title = ""
        headerTitle.text = L10n.tabFavorites
        #endif
        emptyState?.configure(
            symbol: "heart",
            title: L10n.favoritesEmptyTitle,
            message: L10n.favoritesEmptyMessage
        )
    }

    private func applySnapshot(animated: Bool) {
        // Favoriler yalnızca kimlik olarak saklanıyor; içerik katalogdan
        // çözülüyor. Katalogda karşılığı olmayan kimlikler (liste değişmiş,
        // sağlayıcı içeriği kaldırmış) listelenmiyor ama kaydı silinmiyor —
        // içerik geri gelirse favori de geri geliyor.
        let items = model.activity.favoriteIDs.compactMap { model.library.item(for: $0) }

        var grouped: [MediaKind: [MediaItem]] = [:]
        var seen = Set<MediaID>()
        for item in items where seen.insert(item.id).inserted {
            grouped[item.kind, default: []].append(item)
        }

        #if os(tvOS)
        rebuildFilterRow(counts: grouped.mapValues(\.count))
        let visibleOrder = selectedKind.map { [$0] } ?? Self.order
        #else
        let visibleOrder = Self.order
        #endif

        var snapshot = NSDiffableDataSourceSnapshot<Section, MediaItem>()
        var kinds: [MediaKind] = []
        for kind in visibleOrder {
            guard let group = grouped[kind], !group.isEmpty else { continue }
            kinds.append(kind)
            snapshot.appendSections([.kind(kind)])
            snapshot.appendItems(group, toSection: .kind(kind))
        }

        // Düzen kapanışı bölümü sıra numarasıyla soruyor; sıra uygulamadan
        // önce yazılıyor ki ilk düzen turu doğru türü görsün.
        visibleKinds = kinds
        dataSource.apply(snapshot, animatingDifferences: animated)
        emptyState.isHidden = !items.isEmpty
        #if os(tvOS)
        // Hiç favori yokken başlık ve süzgeç de yok: ekranın ortasında
        // yalnızca boş durum duruyor.
        headerStack.isHidden = items.isEmpty
        #endif
    }
}

extension FavoritesViewController: UICollectionViewDelegate {
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

        // Canlı kanalın detay ekranı yok; doğrudan player açılır.
        guard item.kind != .live else {
            Task { await model.play(item) }
            return
        }
        let controller = DetailViewController(item: item, model: model)
        controller.applyZoomTransition(from: collectionView.cellForItem(at: indexPath))
        navigationController?.pushViewController(controller, animated: true)
    }

    /// Karta uzun basınca çıkan menü — İzle, favori, izleme listesi. Menünün
    /// kendisi `MediaCardMenu`'de: aynı kart her ekranda aynı eylemleri veriyor.
    ///
    /// Tekil `...ForItemAt:` karşılığı artık kullanılamıyor; çoklu seçime
    /// açık olan bu yöntem geçerli. Burada çoklu seçim yok, o yüzden yalnızca
    /// tek karta basıldığında menü çıkıyor — boş dizi koleksiyonun kendisine
    /// basıldığı anlamına geliyor ve orada gösterilecek bir eylem yok.
    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1,
              let indexPath = indexPaths.first,
              let item = dataSource.itemIdentifier(for: indexPath)
        else { return nil }
        return MediaCardMenu.configuration(for: item, model: model) { [weak self] item in
            guard let self else { return }
            navigationController?.pushViewController(
                DetailViewController(item: item, model: model), animated: true
            )
        }
    }
}

extension FavoritesViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        let items = indexPaths.compactMap { dataSource.itemIdentifier(for: $0) }
        guard let first = items.first else { return }
        MediaPrefetch.warm(items, posterWidth: cardWidth(for: first.kind))
    }
}
