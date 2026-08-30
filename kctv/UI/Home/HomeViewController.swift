import UIKit

/// Ana sayfa: hero banner → ana kartlar → izlemeyi sürdür → kategori rayları.
final class HomeViewController: UIViewController {
    private enum Section: Hashable {
        case hero
        case mainCards
        case row(id: String, title: String, kind: MediaKind, categoryID: String?)
    }

    private enum Item: Hashable {
        /// Banner tek hücre: bütün öne çıkanları o taşıyor, kimliği içeriğe
        /// bağlı değil.
        case hero
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

    /// Ekrandaki banner. Otomatik geçişi hücre kendisi yürütüyor; burada
    /// yalnızca ekran arkaya düşünce durdurulup geri gelince sürdürülüyor.
    private weak var heroCell: HeroCell?
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

    /// Ekran boyu değişince (dönme, bölünmüş pencere) görselin taşma payı da
    /// değişiyor; hücre yeniden kurulmadığı için buradan güncelleniyor.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let heroCell, collectionView.bounds.height > 0 else { return }
        heroCell.artworkOverhang = Self.heroOverhang(
            container: collectionView.bounds.size, metrics: metrics
        )
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
        // Kenar payı ekranın kenarından ölçülüyor, güvenli alandan değil.
        //
        // Varsayılan `.automatic` bölümleri güvenli alana yaslıyor ve ölçüler
        // onun **üstüne** biniyordu: tvOS'ta 60pt taşma payı + 60pt ekran payı
        // ile raylar iki kat içeride kalıyor, banner da her kenarından
        // boşluklu duruyordu. Detay ekranı da aynı kuralı kullanıyor.
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.contentInsetsReference = .none

        return UICollectionViewCompositionalLayout(
            sectionProvider: { [weak self] index, environment in
                guard let self else { return nil }
                let metrics = AppMetrics.metrics(for: environment.container.contentSize.width)
                let section = dataSource.sectionIdentifier(for: index) ?? .mainCards

                switch section {
                case .hero:
                    return self.heroSection(
                        metrics: metrics, container: environment.container.contentSize
                    )
                case .mainCards:
                    return self.mainCardsSection(metrics: metrics)
                case let .row(id, _, kind, _):
                    // İzlemeye devam et rayı dikey afiş değil yatay kart:
                    // kaldığın yeri gösteren kare görselin kendisi.
                    return id == Self.continueRowID
                        ? MediaSectionLayout.clipRow(metrics: metrics)
                        : MediaSectionLayout.posterRow(kind: kind, metrics: metrics)
                }
            },
            configuration: configuration
        )
    }

    /// Tam genişlikte banner.
    ///
    /// Yatay sayfalama yok: içerikten içeriğe geçerken metin bloğu ve butonlar
    /// yerinde kalmalı, bunu ancak tek hücre yapabiliyor. Sıradaki içeriği
    /// hücrenin kendi ok butonu getiriyor.
    private func heroSection(metrics: AppMetrics, container: CGSize) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(Self.heroHeight(container: container, metrics: metrics))
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        // Banner ile sıradaki ray arasındaki boşluk. Açılış ekranında
        // görünmüyor: görsel hücrenin altından taşıp bu boşluğun ve rayın
        // arkasına geçiyor, ray banner'ın içinden çıkmış gibi duruyor.
        // Kullanıcı aşağı indiğinde görsel geri çekiliyor ve boşluk ortaya
        // çıkıyor.
        section.contentInsets.bottom = Self.heroGap(metrics: metrics)
        return section
    }

    /// Açılış ekranında sıradaki raydan görünen kadarı: başlığı, boşluğu ve
    /// kartın bir bölümü. Sayfanın devamı olduğu ilk bakışta anlaşılıyor.
    private static func heroPeek(metrics: AppMetrics) -> CGFloat {
        metrics.rowHeaderHeight + metrics.rowHeaderGap
            + metrics.clipCardWidth * (9.0 / 16.0) * 0.55
    }

    /// Banner ile sıradaki ray arasındaki boşluk. Aşağı inildiğinde görünür
    /// hâle geliyor.
    private static func heroGap(metrics: AppMetrics) -> CGFloat {
        (metrics.rowSpacing * 0.5).rounded()
    }

    /// Banner hücresinin yüksekliği.
    ///
    /// İçerik bloğu bu hücrenin içinde duruyor; görsel ise altından taşıp
    /// ekranın dibine kadar iniyor.
    ///
    /// tvOS'ta ekranın tamamı. Telefon ve tablette detay ekranıyla aynı kural
    /// geçerli — ekranın yaklaşık %74'ü, en az 560pt — böylece iki ekranın
    /// hero'su aynı boyda duruyor; sıradaki raya ayrılan yer düşüldükten sonra
    /// kalan alan bundan küçükse o geçerli.
    private static func heroHeight(container: CGSize, metrics: AppMetrics) -> CGFloat {
        guard container.width > 0, container.height > 0 else { return metrics.heroHeight }
        let visible = container.height - heroPeek(metrics: metrics) - heroGap(metrics: metrics)
        #if os(tvOS)
        return max(240, visible)
        #else
        return max(240, min(visible, max(560, container.height * 0.74)))
        #endif
    }

    /// Görselin hücrenin altından taşacağı miktar: açılışta ekranın dibine
    /// kadar iniyor, ray ve aradaki boşluk onun üstünde duruyor.
    ///
    /// Yalnızca tvOS'ta. Telefonda banner sıradaki rayın altına uzanmıyor:
    /// ekran zaten dar, bindirme okumayı zorlaştırmaktan başka bir şey
    /// yapmıyor.
    private static func heroOverhang(container: CGSize, metrics: AppMetrics) -> CGFloat {
        #if os(tvOS)
        let full = heroPeek(metrics: metrics) + heroGap(metrics: metrics)
        return min(full, max(0, container.height - heroHeight(container: container, metrics: metrics)))
        #else
        return 0
        #endif
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
            case .hero:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: HeroCell.reuseID, for: indexPath
                ) as! HeroCell
                // Kapanlar yapılandırmadan önce bağlanıyor: ilk çizimde
                // izleme listesi durumu da doğru olsun.
                cell.isFavorite = { [weak self] in self?.model.activity.isFavorite($0) ?? false }
                cell.onDetails = { [weak self] in self?.openDetail($0) }
                cell.onToggleFavorite = { [weak self] in self?.model.activity.toggleFavorite($0) }
                cell.artworkOverhang = Self.heroOverhang(
                    container: collectionView.bounds.size, metrics: metrics
                )
                cell.configure(items: model.library.spotlight, metrics: metrics)
                heroCell = cell
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
                // Dizide kayıt bölüm başına tutuluyor: kimliği bölümsüz
                // sormak hiçbir zaman eşleşmiyor ve kart hem bölüm adını hem
                // ilerleme çubuğunu kaybediyordu.
                let progress = model.activity.latestProgress(for: media.id)
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

    /// Sürdürme kartının başlığı.
    ///
    /// Dizide dizinin adı değil kalınan bölüm yazıyor: "Silo · S3:B3 · Bölüm
    /// adı". Bölümün adı oynatılırken ilerleme kaydına yazıldığı için detayın
    /// indirilmiş olması gerekmiyor; eski kayıtlarda yoksa detay
    /// önbelleğinden çözülüyor, o da yoksa dizinin adıyla yetiniliyor.
    private func continueTitle(for item: MediaItem, progress: PlaybackProgress?) -> String {
        guard item.kind == .series else { return item.title }
        let episode = progress?.episodeLabel ?? cachedEpisodeLabel(for: item, episodeID: progress?.episodeID)
        guard let episode else { return item.title }
        return "\(item.title) · \(episode)"
    }

    private func cachedEpisodeLabel(for item: MediaItem, episodeID: String?) -> String? {
        guard let episodeID,
              let detail = model.library.cachedDetail(for: item),
              let episode = detail.seasons.flatMap(\.episodes).first(where: { $0.id == episodeID })
        else { return nil }
        return [episode.numberText, episode.title].compactMap { $0 }.joined(separator: " · ")
    }

    @objc private func libraryDidChange() {
        applySnapshot(animated: true)
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        let existing = dataSource.snapshot().itemIdentifiers

        if !model.library.spotlight.isEmpty {
            snapshot.appendSections([.hero])
            snapshot.appendItems([.hero], toSection: .hero)
            // Banner'ın kimliği içeriğe bağlı değil: öne çıkanlar değişince
            // diffable hücreyi kendiliğinden yenilemiyor. Hücrenin yerinde
            // kalması istenen şey zaten — geçen içerik ve süre sıfırlanmasın —
            // o yüzden yeniden kurmak yerine tazeleniyor.
            if existing.contains(.hero) {
                snapshot.reconfigureItems([.hero])
            }
        }

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
        var didFail = false
        if case .failed = model.library.state { didFail = true }

        // Yükleme başarısızsa ekran sessizce boş kalmıyor: sebep yazılıyor ve
        // yeniden denemek için bir yol sunuluyor.
        if case let .failed(message) = model.library.state, isEmpty {
            statusLabel.text = "\(L10n.libraryLoadFailed)\n\(message)"
            statusStack.isHidden = false
        } else {
            statusStack.isHidden = true
        }

        // Liste gelene kadar sayfa boş değil, kapalı duruyor: bölümler tek tek
        // yerleşirken düzen sıçrıyor ve kullanıcı yarım bir ekrana bakıyor.
        // İçerik gerçekten boşsa (liste yüklendi ama hiçbir şey yok) gösterge
        // dönmeye devam etmiyor.
        let isLoading = isEmpty && !didFail && model.library.state != .ready
        collectionView.isHidden = isLoading
        isLoading ? spinner.startAnimating() : spinner.stopAnimating()
    }

    // MARK: - Banner otomatik geçişi

    /// Geçiş yalnızca ekran öndeyken sürüyor: detaya gidildiğinde banner
    /// arkada içerik değiştirmesin, geri dönünce kaldığı yerden devam etsin.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        heroCell?.resumeAutoAdvance()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        heroCell?.pauseAutoAdvance()
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

    /// Kaldığı yerden oynatır.
    ///
    /// Filmde saniye bilgisi zaten oynatma bağlamına ekleniyor. Dizide kalınan
    /// bölüm ilerleme kaydında duruyor ama oynatmak için bölüm nesnesi
    /// gerekiyor; detay önbellekteyse ağa çıkılmıyor. Bölüm çözülemezse kart
    /// eskisi gibi detay ekranını açıyor — sessizce hiçbir şey yapmaktansa.
    private func resumePlayback(for item: MediaItem) {
        guard item.kind == .series else {
            Task { await model.play(item) }
            return
        }

        Task { [weak self] in
            guard let self else { return }
            guard let episodeID = model.activity.latestProgress(for: item.id)?.episodeID,
                  let detail = try? await model.library.detail(for: item),
                  let episode = detail.seasons.flatMap(\.episodes).first(where: { $0.id == episodeID })
            else {
                openDetail(item)
                return
            }
            await model.play(episode, in: detail.item)
        }
    }

    private func openCatalog(kind: MediaKind, categoryID: String?, title: String) {
        let controller = CatalogViewController(kind: kind, model: model, categoryID: categoryID, title: title)
        navigationController?.pushViewController(controller, animated: true)
    }
}

extension HomeViewController: UICollectionViewDelegate {
    /// Banner görselini kaydırmaya bağlar: aşağı çekildiğinde üste doğru
    /// büyüyor, yukarı kaydırıldığında alt ucu geri çekiliyor.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Rayların kendi yatay kaydırma görünümleri de bu delegeye düşmüyor
        // ama yine de yalnızca ana koleksiyona bakılıyor.
        guard scrollView === collectionView else { return }
        let offset = scrollView.contentOffset.y
        for case let cell as HeroCell in collectionView.visibleCells {
            cell.applyScroll(offset: offset)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        // Ray hücreleri ortogonal bölümün kendi kaydırma görünümünün içinde
        // duruyor ve o görünüm kırpma yapıyor; tvOS'ta odaklanan kart bunun
        // dışına taşıyor.
        var ancestor = cell.superview
        while let view = ancestor, view !== collectionView {
            view.clipsToBounds = false
            ancestor = view.superview
        }
        #if os(tvOS)
        collectionView.clipsToBounds = false
        #endif

        guard let cell = cell as? HeroCell else { return }
        // Hücre ekrana girerken sayfa zaten kaydırılmış olabilir.
        cell.applyScroll(offset: collectionView.contentOffset.y)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case let .poster(rowID, media):
            // İzlemeye devam et kartı doğrudan oynatıcıyı açıyor: oradaki
            // niyet kaldığı yerden devam etmek, içeriği incelemek değil.
            if rowID == Self.continueRowID {
                resumePlayback(for: media)
            } else {
                openDetail(media, sourceView: collectionView.cellForItem(at: indexPath))
            }
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
