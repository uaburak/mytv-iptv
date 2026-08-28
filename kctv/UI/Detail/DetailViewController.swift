import UIKit

/// Apple TV tarzı detay ekranı: üstte tam genişlikte sinematik görsel,
/// üzerinde logo/başlık ve aksiyonlar, altında bölümler, künye ve benzerler.
final class DetailViewController: UIViewController {
    private let model: AppModel
    private var item: MediaItem
    private var detail: MediaDetail?
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
        navigationItem.largeTitleDisplayMode = .never
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
        }
    }

    /// Hero yüksekliği. Backdrop 16:9 olduğu için ekranın yaklaşık %74'ü
    /// ideal dengeyi sağlıyor (~642pt @ iPhone 17 Pro).
    private static func heroHeight(forScreenHeight height: CGFloat) -> CGFloat {
        max(560, height * 0.74)
    }

    // MARK: - Toolbar

    private func setupToolbarItems() {
        let share = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(shareItem)
        )
        let favorite = UIBarButtonItem(
            image: favoriteImage,
            style: .plain,
            target: self,
            action: #selector(toggleFavorite)
        )
        favoriteBarButton = favorite
        navigationItem.rightBarButtonItems = [share, favorite]
    }

    private var favoriteImage: UIImage? {
        let current = detail?.item ?? item
        return UIImage(systemName: model.activity.isFavorite(current) ? "checkmark.circle.fill" : "plus.circle")
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
        bodyStack.spacing = 28
        bodyStack.isLayoutMarginsRelativeArrangement = true
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
            section.spacing = 12
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
        hero.playButton.addTarget(self, action: #selector(playPrimary), for: .touchUpInside)
        hero.favoriteButton.addTarget(self, action: #selector(toggleFavorite), for: .touchUpInside)
        hero.moreButton.addTarget(self, action: #selector(togglePlot), for: .touchUpInside)
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
        hero.favoriteButton.configuration?.image = UIImage(
            systemName: model.activity.isFavorite(current) ? "checkmark" : "plus"
        )

        let plotText = current.plot ?? tmdbMetadata?.overview
        hero.plotLabel.text = plotText
        hero.plotLabel.isHidden = plotText?.isEmpty != false
        hero.moreButton.isHidden = (plotText?.count ?? 0) <= 140

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

        renderEpisodes()
        renderCredits()
        renderRelated()
    }

    private func playTitle(for current: MediaItem) -> String {
        if let progress = model.activity.progress(for: current.id), !progress.isFinished, progress.positionSeconds > 60 {
            return L10n.resume
        }
        return current.kind == .series ? L10n.playFirstEpisode : L10n.play
    }

    private func renderEpisodes() {
        episodesSection.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let detail, detail.hasEpisodes else {
            episodesSection.isHidden = true
            return
        }
        episodesSection.isHidden = false

        let season = detail.seasons.first { $0.number == selectedSeason } ?? detail.seasons[0]

        let header = UILabel()
        header.text = L10n.episodes
        header.font = metrics.rowTitleFont
        header.textColor = .white

        let headerRow = UIStackView(arrangedSubviews: [header])
        headerRow.axis = .horizontal
        if detail.seasons.count > 1 {
            let seasonButton = UIButton(type: .system)
            seasonButton.setTitle(season.name, for: .normal)
            seasonButton.showsMenuAsPrimaryAction = true
            seasonButton.menu = UIMenu(children: detail.seasons.map { candidate in
                UIAction(title: candidate.name, state: candidate.number == season.number ? .on : .off) { [weak self] _ in
                    self?.selectedSeason = candidate.number
                    self?.renderEpisodes()
                }
            })
            headerRow.addArrangedSubview(UIView())
            headerRow.addArrangedSubview(seasonButton)
        }
        headerRow.isLayoutMarginsRelativeArrangement = true
        headerRow.directionalLayoutMargins = .init(
            top: 0, leading: metrics.screenPadding, bottom: 0, trailing: metrics.screenPadding
        )
        episodesSection.addArrangedSubview(headerRow)

        for episode in season.episodes {
            episodesSection.addArrangedSubview(makeEpisodeRow(episode))
        }
    }

    private func makeEpisodeRow(_ episode: Episode) -> UIView {
        let still = RemoteImageView()
        let width = metrics.posterWidth * 0.85
        still.configure(url: episode.stillURL, title: episode.title, displayWidth: width)
        still.layer.cornerRadius = 8
        still.clipsToBounds = true
        still.translatesAutoresizingMaskIntoConstraints = false
        still.widthAnchor.constraint(equalToConstant: width).isActive = true
        still.heightAnchor.constraint(equalToConstant: width * 9 / 16).isActive = true

        let number = UILabel()
        number.text = episode.numberText
        number.font = .systemFont(ofSize: 15)
        number.textColor = AppPalette.secondaryText

        let name = UILabel()
        name.text = episode.title
        name.font = .systemFont(ofSize: 15)
        name.textColor = .white

        let duration = UILabel()
        duration.text = episode.durationText
        duration.font = .systemFont(ofSize: 15)
        duration.textColor = AppPalette.secondaryText

        let topRow = UIStackView(arrangedSubviews: [number, name, UIView(), duration])
        topRow.axis = .horizontal
        topRow.spacing = 8

        let plot = UILabel()
        plot.text = episode.plot
        plot.font = .systemFont(ofSize: 13)
        plot.textColor = AppPalette.secondaryText
        plot.numberOfLines = 3
        plot.isHidden = episode.plot?.isEmpty != false

        let textStack = UIStackView(arrangedSubviews: [topRow, plot])
        textStack.axis = .vertical
        textStack.spacing = 4

        let row = UIStackView(arrangedSubviews: [still, textStack])
        row.axis = .horizontal
        row.spacing = 14
        row.alignment = .top
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(
            top: 10, leading: metrics.screenPadding, bottom: 10, trailing: metrics.screenPadding
        )

        let container = UIControl()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isUserInteractionEnabled = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        container.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            Task { await self.model.play(episode, in: self.detail?.item ?? self.item) }
        }, for: .touchUpInside)
        return container
    }

    private func renderCredits() {
        creditsSection.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // TMDB veya sağlayıcıdan gelen künye ve detaylar
        let cast = tmdbMetadata?.cast.nilIfEmptyList ?? detail?.cast.nilIfEmptyList ?? item.cast
        let director = tmdbMetadata?.director ?? detail?.director ?? item.director
        let originalTitle = tmdbMetadata?.originalTitle
        let originalLang = tmdbMetadata?.originalLanguage
        let releaseDate = tmdbMetadata?.releaseDate
        let status = tmdbMetadata?.status
        let country = tmdbMetadata?.country ?? detail?.country
        let trailerURL = tmdbMetadata?.trailerURL ?? detail?.trailerURL ?? item.trailerURL

        let hasAnyInfo = !cast.isEmpty || director != nil || originalTitle != nil || releaseDate != nil || trailerURL != nil
        guard hasAnyInfo else {
            creditsSection.isHidden = true
            return
        }
        creditsSection.isHidden = false
        creditsSection.spacing = 18

        if let director {
            creditsSection.addArrangedSubview(makeCreditBlock(title: L10n.director, value: director))
        }
        if !cast.isEmpty {
            creditsSection.addArrangedSubview(
                makeCreditBlock(title: L10n.cast, value: cast.prefix(12).joined(separator: ", "))
            )
        }
        if let originalTitle, originalTitle.lowercased() != item.title.lowercased() {
            let langSuffix = originalLang != nil ? " (\(originalLang!))" : ""
            creditsSection.addArrangedSubview(
                makeCreditBlock(title: L10n.originalTitle, value: "\(originalTitle)\(langSuffix)")
            )
        }
        if let releaseDate, !releaseDate.isEmpty {
            creditsSection.addArrangedSubview(makeCreditBlock(title: L10n.releaseYear, value: releaseDate))
        }
        if let country, !country.isEmpty {
            creditsSection.addArrangedSubview(makeCreditBlock(title: L10n.country, value: country))
        }
        if let status, !status.isEmpty {
            creditsSection.addArrangedSubview(makeCreditBlock(title: L10n.status, value: status))
        }
        if let trailerURL {
            let trailerButton = makeTrailerButton(url: trailerURL)
            creditsSection.addArrangedSubview(trailerButton)
        }

        creditsSection.isLayoutMarginsRelativeArrangement = true
        creditsSection.directionalLayoutMargins = .init(
            top: 0, leading: metrics.screenPadding, bottom: 0, trailing: metrics.screenPadding
        )
    }

    private func makeTrailerButton(url: URL) -> UIView {
        var config = UIButton.Configuration.tinted()
        config.title = L10n.watchTrailer
        config.image = UIImage(systemName: "play.rectangle.fill")
        config.imagePadding = 8
        config.cornerStyle = .capsule
        config.baseForegroundColor = AppPalette.accent
        config.baseBackgroundColor = AppPalette.accent.withAlphaComponent(0.18)

        let button = UIButton(configuration: config)
        button.addAction(UIAction { _ in
            UIApplication.shared.open(url)
        }, for: .touchUpInside)
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
        guard related.count >= 4 else {
            relatedSection.isHidden = true
            return
        }
        relatedSection.isHidden = false

        let header = UILabel()
        header.text = L10n.relatedContent
        header.font = metrics.rowTitleFont
        header.textColor = .white

        let headerRow = UIStackView(arrangedSubviews: [header])
        headerRow.isLayoutMarginsRelativeArrangement = true
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

        related = model.library.related(to: item, limit: 12)
        renderRelated()

        if detail == nil {
            detail = try? await model.library.detail(for: item)
            selectedSeason = detail?.seasons.first?.number
            render()
            favoriteBarButton?.image = favoriteImage
        }

        await enrichWithTMDB(startTime: startTime)
    }

    /// TMDB'den sinematik görsel, şeffaf logo ve zengin bilgiler.
    /// Yükleme süresince koyu blur/nabız animasyonu gösterilir ve TMDB tamamlandığında yumuşakça açılır.
    /// Afiş (dikey poster) asla hero arka planına basılmaz; yalnızca gerçek yatay backdrop konur.
    private func enrichWithTMDB(startTime: Double) async {
        let current = detail?.item ?? item

        if TMDBService.isConfigured, let metadata = await TMDBService.shared.metadata(for: current, language: AppLanguage.current) {
            tmdbMetadata = metadata

            // Arka plan: Yalnızca ve yalnızca TMDB'den gelen yatay sinematik backdrop.
            // Dikey afiş/poster kesinlikle arka plana basılmaz!
            if let backdropURL = metadata.backdropURL {
                hero.artwork.configure(
                    url: backdropURL,
                    title: current.title,
                    displayWidth: metrics.heroImageWidth
                )
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
        }

        // Açılışta en az 350ms koyu efekt tutularak ani görsel sıçramaları önlenir
        let elapsed = CACurrentMediaTime() - startTime
        let targetDelay: Double = 0.35
        if elapsed < targetDelay {
            let sleepNanos = UInt64((targetDelay - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: sleepNanos)
        }

        await MainActor.run {
            self.render()
            self.hero.stopLoadingAnimation(animated: true)
        }
    }

    // MARK: - Aksiyonlar

    @objc private func togglePlot() {
        isPlotExpanded.toggle()
        hero.plotLabel.numberOfLines = isPlotExpanded ? 0 : 2
        hero.moreButton.setTitle(isPlotExpanded ? L10n.less : L10n.more, for: .normal)
    }

    @objc private func toggleFavorite() {
        let current = detail?.item ?? item
        model.activity.toggleFavorite(current)
        hero.favoriteButton.configuration?.image = UIImage(
            systemName: model.activity.isFavorite(current) ? "checkmark" : "plus"
        )
        favoriteBarButton?.image = favoriteImage
    }

    @objc private func shareItem() {
        let current = detail?.item ?? item
        var payload: [Any] = [current.title]
        if let trailer = detail?.trailerURL ?? current.trailerURL {
            payload.append(trailer)
        }
        let controller = UIActivityViewController(activityItems: payload, applicationActivities: nil)
        controller.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(controller, animated: true)
    }

    @objc private func playPrimary() {
        let current = detail?.item ?? item
        Task {
            // Diziyse kaldığı bölüm, yoksa ilk bölüm.
            if current.kind == .series, let detail {
                let episodes = detail.seasons.flatMap(\.episodes)
                let resume = episodes.first { episode in
                    guard let progress = model.activity.progress(for: current.id, episodeID: episode.id) else { return false }
                    return !progress.isFinished
                }
                if let episode = resume ?? episodes.first {
                    await model.play(episode, in: current)
                    return
                }
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
