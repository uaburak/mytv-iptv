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
            // Güvenli alana değil ekranın tepesine bağlanıyor: içerik
            // navigation bar'ın ardından geçip bulanıklaşıyor, sert bir çizgide
            // kesilmiyor. Dinlenme konumundaki boşluğu
            // `contentInsetAdjustmentBehavior` varsayılanı veriyor.
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
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

        var snapshot = NSDiffableDataSourceSnapshot<Section, MediaItem>()
        var kinds: [MediaKind] = []
        for kind in Self.order {
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

    /// Oynatma ve favoriden çıkarma karta uzun basınca açılıyor. Kaydırmalı
    /// satır eylemleri tvOS'ta yok; bağlam menüsü iki platformda da çalışıyor.
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
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(
                    title: item.kind == .live ? L10n.watch : L10n.play,
                    image: UIImage(systemName: "play.fill")
                ) { _ in
                    Task { await self?.model.play(item) }
                },
                UIAction(
                    title: L10n.removeFromFavorites,
                    image: UIImage(systemName: "heart.slash"),
                    attributes: .destructive
                ) { _ in
                    self?.model.activity.toggleFavorite(item)
                },
            ])
        }
    }
}
