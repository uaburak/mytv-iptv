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
    /// Liste yüklenemediğinde gösterilen açıklama ve yeniden deneme.
    private let statusStack = UIStackView()
    private let statusLabel = UILabel()
    private let retryButton = UIButton(configuration: .appGlass())

    /// Banner'ın sayfa göstergesi. Koleksiyonun kendi alt görünümü olduğu için
    /// içerikle birlikte kayıyor ve daima hero'nun alt kenarına yapışık kalıyor.
    private let pageIndicator = BannerPageIndicator()

    /// Banner'ın kendiliğinden ilerlemesi.
    ///
    /// `Timer` yerine görev kullanılıyor: `Timer`'ın kapanı yalıtımsız
    /// çalıştığı için `self`'e oradan dokunmak Swift 6'da izolasyon ihlali.
    /// Görev baştan `@MainActor`, ek bir sıçrama gerekmiyor.
    private var bannerTask: Task<Void, Never>?
    private var currentBannerPage = 0
    /// Bir içeriğin ekranda kalma süresi; gösterge bu sürede doluyor.
    private static let bannerDwellDuration: TimeInterval = 5
    /// "İzlemeye devam et" rayının kimliği; düzeni ve hücresi diğerlerinden farklı.
    private static let continueRowID = "continue" 

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
        navigationItem.setPrefersLargeTitle(false)
        #if os(iOS)
        setupAccountButton()
        #endif
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

        // İzleme listesi satırı buradan besleniyor; detayda "+" basılınca
        // anasayfanın haberi olmalı.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(libraryDidChange),
            name: .appModelFavoritesDidChange,
            object: nil
        )
    }

    /// Noktalar koleksiyonun içerik uzayına yerleştiriliyor; böylece dikey
    /// kaydırmada hero ile birlikte hareket ediyorlar.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = collectionView.bounds.width
        guard width > 0 else { return }
        let height: CGFloat = 24
        pageIndicator.frame = CGRect(
            x: 0,
            y: metrics.heroHeight - height - 8,
            width: width,
            height: height
        )
        // Hücreler koleksiyonun alt görünümü olarak ekleniyor ve göstergenin
        // üstünde kalabiliyorlar.
        collectionView.bringSubviewToFront(pageIndicator)
    }

    // MARK: - Kurulum

    /// Profil rozeti. Sabit boyutlu özel görünüm yerine hazır görsel
    /// kullanıyoruz: navigation bar öğe sarmalayıcısı kendi genişliğini
    /// dayattığı için 30pt'lik kısıt onunla çakışıp uyarı basıyordu.
    #if os(iOS)
    private func setupAccountButton() {
        let item = UIBarButtonItem(
            image: Self.avatarImage(initials: model.user?.initials ?? "?"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        item.accessibilityLabel = L10n.accountAndSettings
        navigationItem.rightBarButtonItem = item
    }
    #endif

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
        collectionView.register(MediaClipCell.self, forCellWithReuseIdentifier: MediaClipCell.reuseID)
        collectionView.register(
            RowHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: RowHeaderView.reuseID
        )

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        pageIndicator.isHidden = true
        pageIndicator.onSelectPage = { [weak self] page in
            self?.showBannerPage(page)
        }
        collectionView.addSubview(pageIndicator)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        view.addSubview(spinner)

        statusLabel.textColor = AppPalette.secondaryText
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        retryButton.configuration?.title = L10n.retry
        retryButton.addSpringPressFeedback()
        retryButton.addAction(UIAction { [weak self] _ in
            Task { await self?.model.library.reload(force: true) }
        }, for: .primaryActionTriggered)

        statusStack.axis = .vertical
        statusStack.spacing = 16
        statusStack.alignment = .center
        statusStack.isHidden = true
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        [statusLabel, retryButton].forEach(statusStack.addArrangedSubview)
        view.addSubview(statusStack)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            statusStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: 40
            ),
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
            case let .row(id, _, kind, _):
                // İzlemeye devam et rayı dikey afiş değil yatay kart:
                // kaldığın yeri gösteren kare görselin kendisi.
                return id == Self.continueRowID
                    ? MediaSectionLayout.clipRow(metrics: metrics)
                    : MediaSectionLayout.posterRow(kind: kind, metrics: metrics)
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
        // Sayfa noktaları yatay kaydırmayı buradan izliyor: ortogonal bölümün
        // kendi kaydırma görünümüne delege olunamıyor.
        section.visibleItemsInvalidationHandler = { [weak self] _, offset, environment in
            guard let self else { return }
            let width = environment.container.contentSize.width
            guard width > 0, pageIndicator.numberOfPages > 0 else { return }
            let page = min(max(Int((offset.x / width).rounded()), 0), pageIndicator.numberOfPages - 1)

            // Yalnızca sayfa gerçekten değiştiğinde: bu kapan kaydırmanın her
            // karesinde çağrılıyor, her seferinde zamanlayıcıyı yenilemek
            // otomatik geçişi tamamen durdururdu. Elle kaydırma sırasında ise
            // sayfa değiştikçe süre baştan başlıyor — istenen davranış bu.
            guard page != currentBannerPage else { return }
            currentBannerPage = page
            pageIndicator.setCurrentPage(page)
            restartBannerTimer()
        }
        return section
    }

    private func mainCardsSection(metrics: AppMetrics) -> NSCollectionLayoutSection {
        let height = metrics.mainCardWidth * 0.56
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(metrics.mainCardWidth),
                heightDimension: .absolute(height)
            )
        )
        // Grup satırın tamamını kaplayıp üç kartı birden taşıyor. Grup tek kart
        // genişliğinde bırakılırsa, yatay kaydırma kapalı olduğu için bölüm
        // grupları alt alta diziyor ve kartlar dikey sıralanıyordu.
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(height)
            ),
            repeatingSubitem: item,
            count: MediaKind.allCases.count
        )
        group.interItemSpacing = .fixed(metrics.cardSpacing)

        let section = NSCollectionLayoutSection(group: group)
        // Üç kart ekrana sığdığı için yatay kaydırmaya gerek yok.
        section.orthogonalScrollingBehavior = .none
        section.contentInsets = NSDirectionalEdgeInsets(
            top: metrics.rowSpacing * 0.6,
            leading: metrics.screenPadding,
            bottom: metrics.rowSpacing * 0.5,
            trailing: metrics.screenPadding
        )
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
                cell.configure(kind: kind, count: model.library.catalog[kind]?.count ?? 0, metrics: metrics)
                return cell

            case let .poster(rowID, media):
                guard rowID == Self.continueRowID else {
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: PosterCell.reuseID, for: indexPath
                    ) as! PosterCell
                    cell.configure(item: media, metrics: metrics, progress: nil)
                    return cell
                }

                // Sürdürme kartı yatay: kaldığın yeri gösteren görsel afiş
                // değil backdrop, ve dizide kaldığın bölümün adı yazıyor.
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: MediaClipCell.reuseID, for: indexPath
                ) as! MediaClipCell
                let progress = model.activity.progress(for: media.id)
                cell.configure(
                    title: continueTitle(for: media, progress: progress),
                    durationText: media.durationText,
                    imageURL: media.backdropURL ?? media.posterURL,
                    metrics: metrics,
                    width: metrics.clipCardWidth,
                    playedFraction: progress?.fraction
                )
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

    /// Sürdürme kartının başlığı. Dizide kaldığın bölümün adı gösteriliyor;
    /// bölüm adı ancak dizinin detayı daha önce açılmışsa elde oluyor, yoksa
    /// dizinin kendi adıyla yetiniliyor.
    private func continueTitle(for item: MediaItem, progress: PlaybackProgress?) -> String {
        guard item.kind == .series,
              let episodeID = progress?.episodeID,
              let detail = model.library.cachedDetail(for: item),
              let episode = detail.seasons.flatMap(\.episodes).first(where: { $0.id == episodeID })
        else { return item.title }
        return [episode.numberText, episode.title].compactMap { $0 }.joined(separator: " · ")
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

        // Tek banner varken gösterge de otomatik geçiş de anlamsız.
        pageIndicator.setPages(spotlight.count)
        pageIndicator.isHidden = spotlight.count <= 1
        if currentBannerPage >= spotlight.count {
            currentBannerPage = max(0, spotlight.count - 1)
            pageIndicator.setCurrentPage(currentBannerPage)
        }
        view.setNeedsLayout()
        restartBannerTimer()

// Kaldığın yer en üstte: kullanıcının aradığı ilk şey bu.
        let continueWatching = model.library.continueWatching
        if !continueWatching.isEmpty {
            let section = Section.row(
                id: Self.continueRowID, title: L10n.continueWatching, kind: .movie, categoryID: nil
            )
            snapshot.appendSections([section])
            snapshot.appendItems(
                continueWatching.map { Item.poster(rowID: Self.continueRowID, item: $0.item) },
                toSection: section
            )
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

        // İzleme listesi: detaydaki "+" ile eklenen içerikler. Kimlik olarak
        // saklandığı için katalogdan çözülüyor; karşılığı kalmayanlar
        // listelenmiyor ama kaydı duruyor.
        let watchlist = model.activity.watchlistIDs.compactMap { model.library.item(for: $0) }
        if !watchlist.isEmpty {
            let section = Section.row(id: "watchlist", title: L10n.myWatchlist, kind: .movie, categoryID: nil)
            snapshot.appendSections([section])
            snapshot.appendItems(
                watchlist.map { Item.poster(rowID: "watchlist", item: $0) },
                toSection: section
            )
        }

        for row in model.library.rows {
            let section = Section.row(id: row.id, title: row.title, kind: row.kind, categoryID: row.categoryID)
            snapshot.appendSections([section])
            // Sağlayıcı listeleri her zaman temiz değil; aynı yayın iki kez
            // gelirse diffable data source çift kimlik görüp çöküyor.
            var seen = Set<MediaID>()
            snapshot.appendItems(
                row.items
                    .filter { seen.insert($0.id).inserted }
                    .map { Item.poster(rowID: row.id, item: $0) },
                toSection: section
            )
        }

        dataSource.apply(snapshot, animatingDifferences: animated)

        // Ana kartlar her zaman var; onlardan başka bir şey yoksa içerik boş.
        let isEmpty = snapshot.numberOfItems == MediaKind.allCases.count
        isEmpty && model.library.state == .loading ? spinner.startAnimating() : spinner.stopAnimating()

        // Yükleme başarısızsa ekran sessizce boş kalmıyor: sebep yazılıyor ve
        // yeniden denemek için bir yol sunuluyor.
        if case let .failed(message) = model.library.state, isEmpty {
            statusLabel.text = "\(L10n.libraryLoadFailed)\n\(message)"
            statusStack.isHidden = false
        } else {
            statusStack.isHidden = true
        }
    }

    // MARK: - Banner otomatik geçişi

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        restartBannerTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopBannerTimer()
    }

    /// Süreyi baştan başlatır ve göstergenin dolumunu yeniden kurar.
    private func restartBannerTimer() {
        stopBannerTimer()
        guard pageIndicator.numberOfPages > 1, isViewLoaded, view.window != nil else { return }

        pageIndicator.startProgress(duration: Self.bannerDwellDuration)
        bannerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.bannerDwellDuration))
            guard !Task.isCancelled else { return }
            self?.advanceBanner()
        }
    }

    private func stopBannerTimer() {
        bannerTask?.cancel()
        bannerTask = nil
        pageIndicator.stopProgress()
    }

    private func advanceBanner() {
        let count = pageIndicator.numberOfPages
        guard count > 1 else { return }
        showBannerPage((currentBannerPage + 1) % count)
    }

    /// Banner'ı verilen sayfaya kaydırır.
    ///
    /// Hero yukarıda görünmüyorken kendiliğinden geçmiyor: `scrollToItem`
    /// gerekirse dikey konumu da oynatabiliyor ve kullanıcı aşağıda içerik
    /// okurken ekranın zıplaması kabul edilebilir değil.
    private func showBannerPage(_ page: Int) {
        guard let heroSection = dataSource.snapshot().indexOfSection(.hero),
              page >= 0, page < pageIndicator.numberOfPages
        else { return }
        guard collectionView.contentOffset.y < metrics.heroHeight / 2 else {
            restartBannerTimer()
            return
        }

        collectionView.scrollToItem(
            at: IndexPath(item: page, section: heroSection),
            at: .centeredHorizontally,
            animated: true
        )
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
    /// Stretchy header: aşağı çekildiğinde banner görseli üste doğru büyüyor.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Ortogonal bölümlerin kendi kaydırma görünümleri de bu delegeye
        // düşmüyor ama yine de yalnızca ana koleksiyona bakılıyor.
        guard scrollView === collectionView else { return }
        let offset = scrollView.contentOffset.y
        for case let cell as HeroCell in collectionView.visibleCells {
            cell.applyStretch(offset: offset)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        // Hücre, ortogonal bölümün kendi kaydırma görünümünün içinde duruyor
        // ve o görünüm kırpma yapıyor. Hem hero'nun esnemesi hem de tvOS'ta
        // odaklanan kartın büyümesi bunun dışına taşıyor.
        var ancestor = cell.superview
        while let view = ancestor, view !== collectionView {
            view.clipsToBounds = false
            ancestor = view.superview
        }
        #if os(tvOS)
        collectionView.clipsToBounds = false
        #endif

        guard let cell = cell as? HeroCell else { return }
        // Sayfa değiştirirken zaten çekili durumdaysak yeni hücre de esnesin.
        cell.applyStretch(offset: collectionView.contentOffset.y)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case let .poster(_, media):
            openDetail(media, sourceView: collectionView.cellForItem(at: indexPath))
        case let .mainCard(kind):
            // Canlı yayında beklenen ekran kanal ızgarası değil rehber:
            // hangi kanalda şu an ne var. Film ve dizi eskisi gibi.
            let controller: UIViewController = kind == .live
                ? GuideViewController(model: model)
                : KindBrowseViewController(kind: kind, model: model)
            navigationController?.pushViewController(controller, animated: true)
        case .hero:
            break
        }
    }
}
