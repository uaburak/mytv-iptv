import UIKit

/// Apple TV tarzı detay ekranı: üstte tam genişlikte sinematik görsel,
/// üzerinde logo/başlık ve aksiyonlar, altında bölümler, künye ve benzerler.
final class DetailViewController: UIViewController {
    private let model: AppModel
    private var item: MediaItem
    private var detail: MediaDetail?
    private var franchiseItems: [FranchiseEntry] = []
    private var isFranchiseLoading: Bool = false
    private var related: [MediaItem] = []
    private var selectedSeason: Int?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let hero = DetailHeroView()
    /// Hero'nun üzerinden kayan içerik; üstü şeffaftan siyaha geçiyor.
    private let bodyBackdrop = GradientBackdropView()
    private let bodyStack = UIStackView()

    private let episodesSection = UIStackView()
    private let creditsSection = UIStackView()
    private let relatedSection = UIStackView()

    /// Sezon çipleri ve bölüm rayı ayrı tutuluyor: sezon değişince yalnızca
    /// ray yenileniyor. Çipler yeniden kurulsaydı odaktaki buton yok olur ve
    /// odak listenin başına düşerdi.
    private var seasonChipButtons: [Int: UIButton] = [:]
    private var episodeRowView: UIView?

    private var isPlotExpanded = false
    private var favoriteBarButton: UIBarButtonItem?
    private var didApplyInitialLayout = false

    /// Yukarı kaydırırken görselin içerikten ne kadar yavaş hareket edeceği.
    /// 1.0 tamamen sabit, 0.0 içerikle birlikte. Apple TV'deki his buna yakın.
    private let parallaxFactor: CGFloat = 0.55

    private var metrics: AppMetrics { AppMetrics.metrics(for: view.bounds.width) }

    init(item: MediaItem, model: AppModel) {
        self.item = item
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        // Başlık hero'da duruyor; navigasyonda tekrar etmiyor.
        title = nil
        navigationItem.setPrefersLargeTitle(false)
        setupToolbarItems()
        buildLayout()
        wireActions()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .appLanguageDidChange,
            object: nil
        )

        // Detay daha önce açıldıysa ağ beklemeden dolu gelsin.
        detail = model.library.cachedDetail(for: item)
        selectedSeason = detail?.seasons.first?.number
        hero.startLoadingAnimation()
        render()
        Task { await load() }
    }

    @objc private func languageDidChange() {
        render()
        Task { await load() }
    }

    /// Ölçüler yalnızca ilk düzen turunda uygulanıyor. Kaydırma sırasında
    /// kısıt sabiti değiştirmek yeni bir düzen turu tetikliyor ve içerik boyutu
    /// oynadığı için en altta sıçrama olarak hissediliyordu.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didApplyInitialLayout, view.bounds.height > 0 else { return }
        didApplyInitialLayout = true

        hero.updateBaseHeight(Self.heroHeight(forScreenHeight: view.bounds.height))
        // Hero içeriği alttaki bölümlerle aynı kenar payını kullanıyor.
        hero.updateHorizontalInset(metrics.screenPadding)

        // Sekme çubuğu içeriğin üstünde duruyor; son satır altında kalmasın.
        let tabBarHeight = tabBarController?.tabBar.bounds.height ?? 0
        let inset = tabBarHeight + view.safeAreaInsets.bottom
        scrollView.contentInset.bottom = inset
        scrollView.verticalScrollIndicatorInsets.bottom = inset
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        // Yükseklik yalnızca ekran boyu gerçekten değiştiğinde güncelleniyor.
        coordinator.animate { _ in
            self.hero.updateBaseHeight(Self.heroHeight(forScreenHeight: size.height))
            self.hero.updateHorizontalInset(AppMetrics.metrics(for: size.width).screenPadding)
        }
    }

    /// Hero yüksekliği. Backdrop 16:9 olduğu için ekranın yaklaşık %74'ü
    /// ideal dengeyi sağlıyor (~642pt @ iPhone 17 Pro).
    private static func heroHeight(forScreenHeight height: CGFloat) -> CGFloat {
        #if os(tvOS)
        // Apple TV düzeni: ilk görünümde arka plan görseli tüm ekranı kaplıyor,
        // içerik onun üzerinde solda duruyor. Bölümler ve künye aşağıda.
        return height
        #else
        return max(560, height * 0.74)
        #endif
    }

    // MARK: - Toolbar

    /// tvOS'ta navigasyon çubuğuna buton konmuyor: sağ üst köşe kumandayla
    /// ulaşması zahmetli bir yer ve paylaşım sayfası zaten o platformda yok.
    /// Favori, hero'daki aksiyon satırında Oynat'ın yanında duruyor.
    private func setupToolbarItems() {
        #if os(tvOS)
        updateFavoriteButton()
        #else
        let current = detail?.item ?? item
        let isFav = model.activity.isFavorite(current)

        let share = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(shareItem)
        )
        share.tintColor = .white

        let spacer = UIBarButtonItem.fixedSpace(12)

        let favorite = UIBarButtonItem(
            image: favoriteImage,
            style: .plain,
            target: self,
            action: #selector(toggleFavorite)
        )
        favorite.tintColor = isFav ? .systemRed : .white
        favoriteBarButton = favorite

        // İki buton arasında spacer ile ayrı ayrı konumlandırma (Sağdan sola: Favori | Spacer | Paylaş)
        navigationItem.rightBarButtonItems = [favorite, spacer, share]
        #endif
    }

    /// tvOS'taki hero favori butonunun simgesini duruma göre günceller.
    private func updateFavoriteButton() {
        let isFav = model.activity.isFavorite(detail?.item ?? item)
        hero.favoriteButton.configuration?.image = UIImage(systemName: isFav ? "heart.fill" : "heart")
        hero.favoriteButton.configuration?.baseForegroundColor = isFav ? .systemRed : .white
    }

    private var favoriteImage: UIImage? {
        let current = detail?.item ?? item
        let isFav = model.activity.isFavorite(current)
        return UIImage(systemName: isFav ? "heart.fill" : "heart")
    }

    // MARK: - Düzen

    private func buildLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.applyNativeScrollEdges()
        scrollView.delegate = self
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        hero.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(hero)

        // Gövde: şeffaftan siyaha geçen zemin, üzerinde bölümler.
        bodyStack.axis = .vertical
        bodyStack.spacing = metrics.detailSectionSpacing
        bodyStack.isLayoutMarginsRelativeArrangement = true
        bodyStack.insetsLayoutMarginsFromSafeArea = false
        bodyStack.directionalLayoutMargins = .init(top: 28, leading: 0, bottom: 40, trailing: 0)
        // Geçiş rampası uzun olsun; siyah zemin yumuşak başlasın.
        bodyBackdrop.rampHeight = 260
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        [episodesSection, creditsSection, relatedSection].forEach(bodyStack.addArrangedSubview)

        let bodyContainer = UIView()
        bodyBackdrop.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(bodyBackdrop)
        bodyContainer.addSubview(bodyStack)
        contentStack.addArrangedSubview(bodyContainer)

        for section in [episodesSection, creditsSection, relatedSection] {
            section.axis = .vertical
            section.spacing = metrics.rowHeaderGap
            section.isHidden = true
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),

            bodyBackdrop.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            bodyBackdrop.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            bodyBackdrop.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            bodyBackdrop.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),

            bodyStack.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            bodyStack.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            bodyStack.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            bodyStack.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
        ])
    }

    private func wireActions() {
        hero.playButton.addTarget(self, action: #selector(playPrimary), for: .primaryActionTriggered)
        hero.watchlistButton.addTarget(self, action: #selector(toggleWatchlist), for: .primaryActionTriggered)
        #if os(iOS)
        // Özetin tamamını okumak için metne dokunmak yeterli; ayrı bir
        // "daha fazlası" butonu yok.
        hero.plotLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(togglePlot))
        )
        #endif
        #if os(tvOS)
        hero.favoriteButton.addTarget(self, action: #selector(toggleFavorite), for: .primaryActionTriggered)
        hero.episodesButton.addTarget(self, action: #selector(scrollToEpisodes), for: .primaryActionTriggered)
        #endif
    }

    // MARK: - İçerik

    private var tmdbMetadata: TMDBMetadata?

    private func render() {
        let current = detail?.item ?? item

        // Logo varsa başlık gizli, yoksa başlık görünür.
        let hasLogo = hero.logoView.image != nil
        hero.logoView.isHidden = !hasLogo
        hero.titleLabel.isHidden = hasLogo
        hero.titleLabel.text = current.title
        hero.titleLabel.font = metrics.titleFont

        // Slogan (Tagline)
        if let tagline = tmdbMetadata?.tagline, !tagline.isEmpty {
            hero.taglineLabel.text = "\"\(tagline)\""
            hero.taglineLabel.isHidden = false
        } else {
            hero.taglineLabel.isHidden = true
        }

        var genreParts = [current.kind.title]
        let displayGenres = !current.genres.isEmpty ? current.genres : (tmdbMetadata?.genres ?? [])
        genreParts.append(contentsOf: displayGenres.prefix(3))
        hero.genreLabel.text = genreParts.joined(separator: " · ")

        hero.playButton.configuration?.title = playTitle(for: current)
        hero.watchlistButton.configuration?.image = UIImage(
            systemName: model.activity.isInWatchlist(current) ? "checkmark" : "plus"
        )

        let plotText = current.plot ?? tmdbMetadata?.overview
        hero.plotLabel.text = plotText
        hero.plotLabel.isHidden = plotText?.isEmpty != false
        // İki satıra sığan bir özette açılacak bir şey yok; dokunma da
        // kapalı kalıyor.
        hero.plotLabel.isUserInteractionEnabled = (plotText?.count ?? 0) > 140

        var metaParts: [String] = []
        if let year = current.yearText ?? tmdbMetadata?.releaseYear { metaParts.append(year) }
        if let duration = current.durationText ?? (tmdbMetadata?.runtimeMinutes.map { "\($0) dk" }) {
            metaParts.append(duration)
        }
        if let percent = current.ratingPercent {
            if let votes = tmdbMetadata?.voteCount, votes > 0 {
                let votesText = votes >= 1000 ? String(format: "%.1fk", Double(votes) / 1000.0) : "\(votes)"
                metaParts.append("%\(percent) ⭐ (\(votesText))")
            } else {
                metaParts.append("%\(percent) ⭐")
            }
        } else if let rating = tmdbMetadata?.rating, rating > 0 {
            let percent = Int((rating * 10).rounded())
            metaParts.append("%\(percent) ⭐")
        }
        if let country = detail?.country ?? tmdbMetadata?.country { metaParts.append(country) }
        hero.metaLabel.text = metaParts.joined(separator: "   ")

        #if os(tvOS)
        hero.episodesButton.isHidden = !(detail?.hasEpisodes ?? false)
        #endif

        renderEpisodes()
        renderCredits()
        renderRelated()
    }

    /// Dizide sürdürülecek bölümün neden seçildiği.
    private enum ResumeKind {
        /// Hiç izlenmemiş (ya da dizi bitmiş): baştan.
        case fresh
        /// Yarım kalmış bölüm.
        case resume
        /// Önceki bölüm bitmiş; sıradaki bölüm.
        case next
    }

    /// Dizide sürdürülecek bölüm.
    ///
    /// En son **izlenen** kayda bakılıyor, listedeki ilk yarım kalmış bölüme
    /// değil: bölümü bitirip bıraktığında sıradakinden devam etmek gerekiyor,
    /// baştan başlamak değil.
    private func resumeTarget(in detail: MediaDetail) -> (episode: Episode, kind: ResumeKind)? {
        let episodes = detail.seasons.flatMap(\.episodes)
        guard let first = episodes.first else { return nil }

        guard let latest = model.activity.latestProgress(for: detail.item.id),
              let index = episodes.firstIndex(where: { $0.id == latest.episodeID })
        else { return (first, .fresh) }

        guard latest.isFinished else { return (episodes[index], .resume) }
        // Son bölüm de bitmişse dizi tamamlanmış: baştan.
        guard episodes.indices.contains(index + 1) else { return (first, .fresh) }
        return (episodes[index + 1], .next)
    }

    private func playTitle(for current: MediaItem) -> String {
        guard current.kind == .series else {
            // Filmde yarım kalan bir kayıt varsa buton baştan oynatmıyor,
            // kalınan yerden devam ediyor.
            let progress = model.activity.progress(for: current.id)
            let canResume = progress.map { !$0.isFinished && $0.positionSeconds > 60 } ?? false
            return canResume ? L10n.resume : L10n.play
        }

        guard let detail, let target = resumeTarget(in: detail) else {
            // Bölüm listesi henüz gelmedi: elde yalnızca bu dizide yarım
            // kalmış bir kayıt olup olmadığı bilgisi var.
            let hasProgress = model.activity.progress.contains {
                $0.mediaID == current.id && !$0.isFinished
            }
            return hasProgress ? L10n.resume : L10n.playFirstEpisode
        }

        switch target.kind {
        case .fresh: return L10n.playFirstEpisode
        case .resume: return L10n.resume
        case .next: return L10n.nextEpisode
        }
    }

    private func renderEpisodes() {
        episodesSection.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let detail, detail.hasEpisodes else {
            episodesSection.isHidden = true
            return
        }
        episodesSection.isHidden = false

        let season = detail.seasons.first { $0.number == selectedSeason } ?? detail.seasons[0]

        // Ayrı bir "Bölümler" başlığı yok: sezon çipleri bölümün ne olduğunu
        // zaten söylüyor, başlık aynı bilgiyi tekrar ediyordu.
        //
        // Sezonlar yan yana çipler. Bağlam menüsü kumandayla iki adım
        // demekti ve seçili sezon menüyü açmadan görünmüyordu.
        if detail.seasons.count > 1 {
            episodesSection.addArrangedSubview(makeSeasonChips(detail.seasons, selected: season))
            // Boy kısıtı ancak çipler hiyerarşiye girdikten sonra kurulabiliyor;
            // öncesinde Oynat butonuyla ortak ataları yok.
            for chip in seasonChipButtons.values {
                chip.heightAnchor.constraint(equalTo: hero.playButton.heightAnchor).isActive = true
            }
        }
        episodeRowView = makeEpisodeRow(for: season, series: detail.item)
        episodesSection.addArrangedSubview(episodeRowView!)
    }

    /// Sezon değiştiğinde yalnızca bölüm rayı yenileniyor; çipler yerinde
    /// kalıyor, dolayısıyla odak seçilen sezonun üstünde kalıyor.
    private func selectSeason(_ number: Int) {
        guard selectedSeason != number, let detail else { return }
        selectedSeason = number

        for (seasonNumber, button) in seasonChipButtons {
            applySeasonChipStyle(to: button, isSelected: seasonNumber == number)
        }

        guard let season = detail.seasons.first(where: { $0.number == number }) else { return }
        let newRow = makeEpisodeRow(for: season, series: detail.item)
        if let old = episodeRowView, let index = episodesSection.arrangedSubviews.firstIndex(of: old) {
            old.removeFromSuperview()
            episodesSection.insertArrangedSubview(newRow, at: index)
        } else {
            episodesSection.addArrangedSubview(newRow)
        }
        episodeRowView = newRow
    }

    private func makeEpisodeRow(for season: Season, series: MediaItem) -> UIView {

        // Apple TV'de bölümler dikey liste değil yatay bir rayda, yatay
        // görsellerle yan yana duruyor.
        let width = metrics.clipCardWidth
        let cardSize = CGSize(width: width, height: width * 9 / 16 + metrics.clipCardTextHeight)
        return HorizontalCardRow<MediaClipCell, Episode>(
            values: season.episodes,
            cardSize: cardSize,
            spacing: metrics.cardSpacing,
            contentInset: metrics.screenPadding,
            reuseID: MediaClipCell.reuseID,
            configureCell: { [weak self] cell, episode in
                guard let self else { return }
                let progress = model.activity.progress(for: series.id, episodeID: episode.id)
                cell.configure(
                    title: [episode.numberText, episode.title].compactMap { $0 }.joined(separator: " · "),
                    durationText: episode.durationText,
                    imageURL: episode.stillURL,
                    metrics: metrics,
                    width: width,
                    playedFraction: progress?.fraction
                )
            },
            onSelect: { [weak self] episode, _ in
                guard let self else { return }
                Task { await self.model.play(episode, in: series) }
            }
        )
    }

    /// Sezon çipleri: seçili olan accent renginde, hepsi yan yana.
    private func makeSeasonChips(_ seasons: [Season], selected: Season) -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        seasonChipButtons = [:]
        for candidate in seasons {
            let button = UIButton(type: .system)
            applySeasonChipStyle(to: button, isSelected: candidate.number == selected.number)
            button.configuration?.title = candidate.name
            button.addSpringPressFeedback(scale: 0.93)
            button.addAction(UIAction { [weak self] _ in
                self?.selectSeason(candidate.number)
            }, for: .primaryActionTriggered)
            seasonChipButtons[candidate.number] = button
            stack.addArrangedSubview(button)
        }

        let scroller = UIScrollView()
        scroller.showsHorizontalScrollIndicator = false
        scroller.contentInsetAdjustmentBehavior = .never
        #if os(tvOS)
        scroller.clipsToBounds = false
        #endif
        scroller.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(
                equalTo: scroller.contentLayoutGuide.leadingAnchor, constant: metrics.screenPadding
            ),
            stack.trailingAnchor.constraint(
                equalTo: scroller.contentLayoutGuide.trailingAnchor, constant: -metrics.screenPadding
            ),
            stack.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor),
        ])
        return scroller
    }

    /// Sezon çipleri arama ekranındaki süzgeç düğmeleriyle aynı görünüyor;
    /// hem stil hem ölçü `UIButton.Configuration.appChip` içinde, tek yerde.
    private func applySeasonChipStyle(to button: UIButton, isSelected: Bool) {
        let title = button.configuration?.title
        button.configuration = .appChip(isSelected: isSelected)
        button.configuration?.title = title
    }

    private func renderCredits() {
        creditsSection.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // TMDB veya sağlayıcıdan gelen künye ve detaylar
        let castMembers = tmdbMetadata?.castMembers ?? []
        let castNames = tmdbMetadata?.cast.nilIfEmptyList ?? detail?.cast.nilIfEmptyList ?? item.cast
        let director = tmdbMetadata?.director ?? detail?.director ?? item.director
        let originalTitle = tmdbMetadata?.originalTitle
        let originalLang = tmdbMetadata?.originalLanguage
        let releaseDate = tmdbMetadata?.releaseDate
        let status = tmdbMetadata?.status
        let country = tmdbMetadata?.country ?? detail?.country
        let trailerURL = tmdbMetadata?.trailerURL ?? detail?.trailerURL ?? item.trailerURL
        let current = detail?.item ?? item

        let hasAnyInfo = !franchiseItems.isEmpty || !castNames.isEmpty || director != nil || originalTitle != nil
            || releaseDate != nil || trailerURL != nil
        guard hasAnyInfo else {
            creditsSection.isHidden = true
            return
        }
        creditsSection.isHidden = false
        creditsSection.spacing = metrics.detailSectionSpacing
        // Raylar kenardan kenara; kenar payını kendileri veriyor.
        creditsSection.isLayoutMarginsRelativeArrangement = false

        // 1) Fragman — bölümlerle aynı yatay kart düzeninde.
        if let trailerURL {
            creditsSection.addArrangedSubview(makeSectionHeader(L10n.watchTrailer))
            creditsSection.addArrangedSubview(makeTrailerRow(url: trailerURL, item: current))
        }

        // 2) Seri Filmler (Fragmandan hemen sonra)
        if isFranchiseLoading {
            creditsSection.addArrangedSubview(makeSectionHeader(L10n.seriesCollection))
            let skeleton = FranchiseSkeletonRow(metrics: metrics)
            skeleton.translatesAutoresizingMaskIntoConstraints = false
            skeleton.heightAnchor.constraint(equalToConstant: metrics.rowItemHeight(for: item.kind)).isActive = true
            creditsSection.addArrangedSubview(skeleton)
        } else if !franchiseItems.isEmpty {
            creditsSection.addArrangedSubview(makeSectionHeader(L10n.seriesCollection))
            let franchiseRow = HorizontalFranchiseRow(items: franchiseItems, metrics: metrics) { [weak self] selected, sourceView in
                guard let self else { return }
                if selected.isAvailableInCatalog, let local = selected.localItem {
                    let controller = DetailViewController(item: local, model: self.model)
                    controller.applyZoomTransition(from: sourceView)
                    self.navigationController?.pushViewController(controller, animated: true)
                } else {
                    self.showUnavailableFranchiseAlert(for: selected)
                }
            }
            franchiseRow.translatesAutoresizingMaskIntoConstraints = false
            franchiseRow.heightAnchor.constraint(equalToConstant: metrics.rowItemHeight(for: item.kind)).isActive = true
            creditsSection.addArrangedSubview(franchiseRow)
        }

        // 3) Oyuncular — TMDB fotoğraflarıyla yuvarlak kartlar.
        if !castMembers.isEmpty {
            creditsSection.addArrangedSubview(makeSectionHeader(L10n.cast))
            creditsSection.addArrangedSubview(makeCastRow(castMembers))
        } else if !castNames.isEmpty {
            // TMDB yoksa elimizde yalnızca isim var; düz metin kalıyor.
            creditsSection.addArrangedSubview(makeSectionHeader(L10n.cast))
            creditsSection.addArrangedSubview(
                inset(makeCreditBlock(title: "", value: castNames.prefix(12).joined(separator: ", ")))
            )
        }

        // 3) Bilgi ızgarası.
        var fields: [(String, String)] = []
        if let director { fields.append((L10n.director, director)) }
        if let originalTitle, originalTitle.lowercased() != item.title.lowercased() {
            let langSuffix = originalLang.map { " (\($0))" } ?? ""
            fields.append((L10n.originalTitle, originalTitle + langSuffix))
        }
        if let releaseDate, !releaseDate.isEmpty { fields.append((L10n.releaseYear, releaseDate)) }
        if let duration = current.durationText { fields.append((L10n.runtime, duration)) }
        if let country, !country.isEmpty { fields.append((L10n.country, country)) }
        if let status, !status.isEmpty { fields.append((L10n.status, status)) }

        if !fields.isEmpty {
            creditsSection.addArrangedSubview(makeSectionHeader(L10n.info))
            creditsSection.addArrangedSubview(inset(makeInfoGrid(fields)))
        }
    }

    /// Ray başlığı; kenar payı içeride veriliyor.
    private func makeSectionHeader(_ title: String) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = metrics.rowTitleFont
        label.textColor = .white
        return inset(label)
    }

    /// Görünümü ekran kenar payıyla saran yardımcı.
    private func inset(_ view: UIView) -> UIView {
        let row = UIStackView(arrangedSubviews: [view])
        row.isLayoutMarginsRelativeArrangement = true
        // Kenar payı ekranın kenarından ölçülüyor; güvenli alan eklenirse
        // bu blok raylardan ve hero içeriğinden daha içeride kalıyor.
        row.insetsLayoutMarginsFromSafeArea = false
        row.directionalLayoutMargins = .init(
            top: 0, leading: metrics.screenPadding, bottom: 0, trailing: metrics.screenPadding
        )
        return row
    }

    private func makeCastRow(_ members: [TMDBCastMember]) -> UIView {
        let width = metrics.castPhotoWidth
        // Daire + ad + karakter satırı.
        let cardSize = CGSize(width: width, height: width + metrics.clipCardTextHeight)
        return HorizontalCardRow<CastMemberCell, TMDBCastMember>(
            values: members,
            cardSize: cardSize,
            spacing: metrics.cardSpacing,
            contentInset: metrics.screenPadding,
            reuseID: CastMemberCell.reuseID,
            configureCell: { [weak self] cell, member in
                guard let self else { return }
                cell.configure(member: member, metrics: metrics, photoWidth: width)
            }
        )
    }

    private func makeTrailerRow(url: URL, item: MediaItem) -> UIView {
        let width = metrics.clipCardWidth
        let cardSize = CGSize(width: width, height: width * 9 / 16 + metrics.clipCardTextHeight)
        return HorizontalCardRow<MediaClipCell, URL>(
            values: [url],
            cardSize: cardSize,
            spacing: metrics.cardSpacing,
            contentInset: metrics.screenPadding,
            reuseID: MediaClipCell.reuseID,
            configureCell: { [weak self] cell, _ in
                guard let self else { return }
                cell.configure(
                    title: L10n.watchTrailer,
                    durationText: nil,
                    imageURL: tmdbMetadata?.backdropURL ?? item.backdropURL,
                    metrics: metrics,
                    width: width,
                    playedFraction: nil
                )
            },
            onSelect: { url, _ in
                UIApplication.shared.open(url)
            }
        )
    }

    /// İki kolonlu bilgi ızgarası; Apple TV'nin "Bilgi" bloğunun karşılığı.
    private func makeInfoGrid(_ fields: [(String, String)]) -> UIView {
        let columns = UIStackView()
        columns.axis = .horizontal
        columns.distribution = .fillEqually
        columns.spacing = metrics.cardSpacing
        columns.alignment = .top

        let half = (fields.count + 1) / 2
        for slice in [fields.prefix(half), fields.suffix(from: half)] {
            let column = UIStackView()
            column.axis = .vertical
            column.spacing = 18
            column.alignment = .leading
            for (title, value) in slice {
                column.addArrangedSubview(InfoFieldView(title: title, value: value, metrics: metrics))
            }
            // Tek alan kalırsa kolon boş kalabiliyor; yine de yer tutuyor.
            columns.addArrangedSubview(column)
        }
        return columns
    }

    private func makeTrailerButton(url: URL) -> UIView {
        var config = UIButton.Configuration.appGlass()
        config.title = L10n.watchTrailer
        config.image = UIImage(systemName: "play.rectangle.fill")

        let button = UIButton(configuration: config)
        button.addSpringPressFeedback()
        button.addAction(UIAction { _ in
            UIApplication.shared.open(url)
        }, for: .primaryActionTriggered)
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }

    private func makeCreditBlock(title: String, value: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 14, weight: .regular)
        valueLabel.textColor = AppPalette.secondaryText
        valueLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        return stack
    }

    private func renderRelated() {
        relatedSection.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !related.isEmpty else {
            relatedSection.isHidden = true
            return
        }
        relatedSection.isHidden = false

        let header = UILabel()
        header.text = L10n.recommendedContent
        header.font = metrics.rowTitleFont
        header.textColor = .white

        let headerRow = UIStackView(arrangedSubviews: [header])
        headerRow.isLayoutMarginsRelativeArrangement = true
        headerRow.insetsLayoutMarginsFromSafeArea = false
        headerRow.directionalLayoutMargins = .init(
            top: 0, leading: metrics.screenPadding, bottom: 0, trailing: metrics.screenPadding
        )
        relatedSection.addArrangedSubview(headerRow)

        let row = HorizontalPosterRow(items: related, metrics: metrics) { [weak self] selected, sourceView in
            guard let self else { return }
            let controller = DetailViewController(item: selected, model: model)
            controller.applyZoomTransition(from: sourceView)
            navigationController?.pushViewController(controller, animated: true)
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: metrics.rowItemHeight(for: item.kind)).isActive = true
        relatedSection.addArrangedSubview(row)
    }

    // MARK: - Yükleme

    private func load() async {
        let startTime = CACurrentMediaTime()

        // Film ise arka planda seri sorgulanırken anında skeleton moduna geç
        if item.kind == .movie {
            isFranchiseLoading = true
        }
        related = model.library.recommendations(for: item, limit: 16)
        render()
        renderCredits()
        renderRelated()

        if detail == nil {
            detail = try? await model.library.detail(for: item)
            selectedSeason = detail?.seasons.first?.number
            render()
            #if os(tvOS)
            updateFavoriteButton()
            #else
            favoriteBarButton?.image = favoriteImage
            #endif
        }

        await enrichWithTMDB(startTime: startTime)
    }

    /// TMDB'den sinematik görsel, şeffaf logo ve zengin bilgiler.
    /// Yükleme süresince koyu blur/nabız animasyonu gösterilir ve TMDB tamamlandığında yumuşakça açılır.
    private func enrichWithTMDB(startTime: Double) async {
        let current = detail?.item ?? item

        if TMDBService.isConfigured, let metadata = await TMDBService.shared.metadata(for: current, language: AppLanguage.current) {
            tmdbMetadata = metadata

            if let backdropURL = metadata.backdropURL {
                detail?.item.backdropURL = backdropURL
                item.backdropURL = backdropURL
            }

            if let logoURL = metadata.logoURL {
                let image = await ImageLoader.shared.image(for: logoURL, maxPixelSize: 900)
                if let image {
                    hero.logoView.image = image
                    hero.logoView.isHidden = false
                    hero.titleLabel.isHidden = true
                }
            }

            if let overview = metadata.overview, !overview.isEmpty {
                detail?.item.plot = overview
                item.plot = overview
            }
            if let rating = metadata.rating {
                detail?.item.rating = rating
                item.rating = rating
            }
            if let releaseYear = metadata.releaseYear.flatMap(Int.init) {
                detail?.item.year = releaseYear
                item.year = releaseYear
            }
            if let durationMin = metadata.runtimeMinutes {
                let durationSec = durationMin * 60
                detail?.item.durationSeconds = durationSec
                item.durationSeconds = durationSec
            }
            if !metadata.genres.isEmpty {
                detail?.item.genres = metadata.genres
                item.genres = metadata.genres
            }
            if !metadata.cast.isEmpty {
                detail?.cast = metadata.cast
            }
            if let director = metadata.director {
                detail?.director = director
            }
            if let country = metadata.country {
                detail?.country = country
            }
            if let trailerURL = metadata.trailerURL {
                detail?.trailerURL = trailerURL
            }

            related = model.library.recommendations(for: item, tmdb: metadata, limit: 16)

            // Aşama 2: Arka planda koleksiyon parçalarını asenkron yükle (etkileşim kilitlenmez)
            if let collectionID = metadata.collectionID {
                Task.detached(priority: .userInitiated) { [weak self, model, item] in
                    let parts = await TMDBService.shared.collectionParts(for: collectionID, language: AppLanguage.current)
                    let entries = model.library.matchFranchiseEntries(parts: parts, for: item)
                    await MainActor.run {
                        guard let self else { return }
                        self.franchiseItems = entries
                        self.isFranchiseLoading = false
                        self.renderCredits()
                        self.renderRelated()
                    }
                }
            } else {
                let localEntries = model.library.franchiseEntries(for: item)
                franchiseItems = localEntries
                isFranchiseLoading = false
            }
        } else {
            let localEntries = model.library.franchiseEntries(for: item)
            franchiseItems = localEntries
            isFranchiseLoading = false
        }

        await MainActor.run {
            self.applyHeroArtwork()
            self.render()
            self.renderCredits()
            self.renderRelated()
            self.hero.stopLoadingAnimation(animated: true)
        }
    }

    private func showUnavailableFranchiseAlert(for entry: FranchiseEntry) {
        let yearSuffix = entry.year.map { " (\($0))" } ?? ""
        let alert = UIAlertController(
            title: "\(entry.title)\(yearSuffix)",
            message: L10n.notInCatalogDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.close, style: .default))
        present(alert, animated: true)
    }

    /// Hero arka planı için en iyi görseli seçer.
    ///
    /// Tercih sırası: TMDB'nin sinematik yatay backdrop'u, sonra sağlayıcının
    /// verdiği backdrop. İkisi de yoksa elde kalan dikey afiş basılıyor —
    /// oranı hero'ya uymadığı için ortadan kırpılıyor ama içeriğin tamamen
    /// karanlık durmasından iyi.
    private func applyHeroArtwork() {
        let current = detail?.item ?? item
        let url = tmdbMetadata?.backdropURL
            ?? current.backdropURL
            ?? tmdbMetadata?.posterURL
            ?? current.posterURL
        guard let url else { return }
        hero.artwork.configure(
            backdropURL: url,
            title: current.title,
            displayWidth: metrics.heroImageWidth
        )
    }

    // MARK: - Aksiyonlar

    #if os(tvOS)
    /// Odak isteği kaydırma bitene kadar bekliyor; `preferredFocusEnvironments`
    /// yalnızca bu bayrak açıkken bölüm rayını gösteriyor.
    private var episodeFocusRequested = false

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if episodeFocusRequested, let episodeRowView {
            return [episodeRowView]
        }
        return super.preferredFocusEnvironments
    }

    /// Bölüm listesi hero'nun altında; buton oraya kaydırıp ilk bölüm kartını
    /// odağa alıyor — kumandayla ayrıca aşağı inmek gerekmiyor.
    @objc private func scrollToEpisodes() {
        guard episodeRowView != nil else { return }
        let target = episodesSection.convert(episodesSection.bounds, to: scrollView).minY
        // Hedefi kendimiz kırpıyoruz: kaydırma görünümü sınırı aşan bir offset'i
        // sessizce sabitliyor, animasyon da olmayan bir yere doğru gidiyordu.
        let maxOffsetY = max(
            scrollView.contentSize.height + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height,
            0
        )
        let fullOffsetY = min(max(target - 40, 0), maxOffsetY)

        // Tam hedef rayı ekranın tepesine çekiyor ve hero'yu tamamen
        // götürüyordu. Yolun yarısı yeterli: kartlar görünür oluyor, hero da
        // bağlam olarak ekranda kalıyor.
        let currentY = scrollView.contentOffset.y
        let offsetY = currentY + (fullOffsetY - currentY) / 2
        episodeFocusRequested = true

        // Zaten oradaysak animasyon yok; odağı hemen taşıyoruz.
        guard abs(currentY - offsetY) > 1 else {
            applyEpisodeFocus()
            return
        }

        // `setContentOffset(animated:)` sabit süreli, sert bir eğri kullanıyor;
        // kumandayla gezerken oluşan yumuşak yavaşlamaya benzemiyordu.
        // `contentOffset` animatable olduğu için yayı kendimiz sürüyoruz.
        //
        // Hero parallax'ı senkron kalıyor: `contentOffset` atandığı anda
        // `scrollViewDidScroll` bu blok içinde çağrılıyor, dolayısıyla hero'nun
        // dönüşümü de aynı süre ve eğriyle animasyona giriyor.
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.scrollView.contentOffset = CGPoint(x: 0, y: offsetY)
        } completion: { _ in
            self.applyEpisodeFocus()
        }
    }

    /// Bekleyen odak isteğini uygular.
    private func applyEpisodeFocus() {
        guard episodeFocusRequested else { return }
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        episodeFocusRequested = false
    }
    #endif

    @objc private func togglePlot() {
        isPlotExpanded.toggle()

        // Özet açılıp kapanırken hero içeriği zıplamasın; yaylanarak yerleşsin.
        hero.plotLabel.numberOfLines = isPlotExpanded ? 0 : 2
        UIView.animate(
            withDuration: 0.45,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func toggleWatchlist() {
        let current = detail?.item ?? item
        model.activity.toggleWatchlist(current)
        let inWatchlist = model.activity.isInWatchlist(current)

        Haptics.impact(.medium)

        // "+" yukarı kayıp yerini onay işaretine bırakıyor.
        hero.watchlistButton.setSymbol(inWatchlist ? "checkmark" : "plus")
    }

    @objc private func toggleFavorite() {
        let current = detail?.item ?? item
        model.activity.toggleFavorite(current)
        let isFav = model.activity.isFavorite(current)

        Haptics.impact(.medium)

        // Kalp dolarken/boşalırken sembolün kendi katmanları morph oluyor.
        #if os(tvOS)
        hero.favoriteButton.setSymbol(
            isFav ? "heart.fill" : "heart",
            transition: .replace.magic(fallback: .upUp)
        )
        hero.favoriteButton.configuration?.baseForegroundColor = isFav ? .systemRed : .white
        #else
        if let image = favoriteImage {
            favoriteBarButton?.setSymbolImage(image, contentTransition: .replace.magic(fallback: .upUp))
        }
        favoriteBarButton?.tintColor = isFav ? .systemRed : .white
        #endif
    }

    @objc private func shareItem() {
        let current = detail?.item ?? item
        var payload: [Any] = [current.title]
        if let trailer = detail?.trailerURL ?? current.trailerURL {
            payload.append(trailer)
        }
        // Paylaşım sayfası tvOS'ta yok; orada buton da kurulmuyor.
        #if os(iOS)
        let controller = UIActivityViewController(activityItems: payload, applicationActivities: nil)
        controller.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(controller, animated: true)
        #endif
    }

    @objc private func playPrimary() {
        let current = detail?.item ?? item
        Task {
            // Diziyse kaldığı bölüm — yarım kalan bölüm, o bittiyse sıradaki.
            // Bölüm içindeki saniye `playback(for:in:)` tarafından ekleniyor.
            if current.kind == .series, let detail, let target = resumeTarget(in: detail) {
                await model.play(target.episode, in: current)
                return
            }
            await model.play(current)
        }
    }
}

extension DetailViewController: UIScrollViewDelegate {
    /// Apple TV davranışı: aşağı çekildiğinde görsel üste sabitlenip büyür,
    /// yukarı kaydırıldığında içerikten yavaş hareket eder (parallax).
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        hero.apply(offset: scrollView.contentOffset.y, parallaxFactor: parallaxFactor)
    }
}
