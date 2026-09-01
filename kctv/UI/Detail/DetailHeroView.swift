import UIKit

/// Detay ekranının üst bloğu: anasayfa hero banner'ıyla birebir aynı görsel
/// mimari, karartma gradyanları, tipografi, logo oranları ve kaydırma efektleri.
final class DetailHeroView: UIView {

    // MARK: - Görsel Katman

    private let visual = UIView()
    let artwork = HeroArtworkView()
    /// Alttan karartma: yazılar görselin üstünde okunur kalsın.
    private let scrim = HeroGradientView()
    /// Soldan karartma: geniş ekranda içerik solda dar bir kolonda duruyor.
    private let sideScrim = HeroGradientView()
    /// Görselin alt ucunda sayfanın siyah zeminine yumuşak geçiş.
    private let bodyBackdrop = GradientBackdropView()

    // MARK: - İçerik

    let column = UIStackView()
    let textBlock = UIStackView()
    var contentStack: UIStackView { column }

    private let titleSlot = UIView()
    let logoView = UIImageView()
    let titleLabel = UILabel()

    let metaRow = UIStackView()
    let metaLabel = UILabel()
    let imdbRow = UIStackView()
    let imdbLogoView = UIImageView()
    let imdbRatingLabel = UILabel()
    let ageBadge = BadgeLabel()
    private let metaTrailingSpacer = UIView()

    let plotLabel = UILabel()

    let playButton = UIButton(type: .system)
    let watchlistButton = UIButton(type: .system)
    private var buttonsGlass: UIView!

    // MARK: - Durum

    #if os(tvOS)
    private var metrics: AppMetrics = .tv
    #else
    private var metrics: AppMetrics = .regular
    #endif
    private var appliedLayout: Layout?
    private var contentLift: CGFloat = 0

    private static let contentLiftDistance: CGFloat = 100
    private static let contentLiftRamp: CGFloat = 320

    var artworkOverhang: CGFloat = 0 {
        didSet {
            guard abs(oldValue - artworkOverhang) > 0.5 else { return }
            artworkBottom.constant = artworkOverhang
            visualBottom.constant = artworkOverhang
        }
    }

    private var visualTop: NSLayoutConstraint!
    private var visualBottom: NSLayoutConstraint!
    private var artworkBottom: NSLayoutConstraint!
    private var bodyBackdropHeight: NSLayoutConstraint!

    private var columnLeading: NSLayoutConstraint!
    private var columnBottom: NSLayoutConstraint!
    private var columnWidth: NSLayoutConstraint!
    private var titleSlotHeight: NSLayoutConstraint!
    private var logoHeight: NSLayoutConstraint!
    private var logoMaxWidth: NSLayoutConstraint!
    private var logoAspect: NSLayoutConstraint?
    private var logoLeading: NSLayoutConstraint!
    private var logoCenterX: NSLayoutConstraint!
    private var imdbLogoHeight: NSLayoutConstraint!
    private var imdbLogoAspect: NSLayoutConstraint!
    private var plotHeight: NSLayoutConstraint!
    private var ownHeight: NSLayoutConstraint!

    private(set) var baseHeight: CGFloat = 660

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        clipsToBounds = false

        visual.clipsToBounds = true
        visual.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visual)

        artwork.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(artwork)

        // Karartma metin bloğunun hizasında en koyu, oradan aşağı doğru açılıyor.
        scrim.colors = [
            UIColor.black.withAlphaComponent(0),
            UIColor.black.withAlphaComponent(0.08),
            UIColor.black.withAlphaComponent(0.40),
            UIColor.black.withAlphaComponent(0.34),
            UIColor.black.withAlphaComponent(0.26),
        ]
        scrim.locations = [0, 0.40, 0.72, 0.88, 1]
        scrim.isUserInteractionEnabled = false
        scrim.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(scrim)

        sideScrim.setDirection(start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5))
        sideScrim.colors = [
            UIColor.black.withAlphaComponent(0.42),
            UIColor.black.withAlphaComponent(0.24),
            UIColor.black.withAlphaComponent(0.07),
            .clear,
        ]
        sideScrim.locations = [0, 0.30, 0.60, 0.88]
        sideScrim.isHidden = true
        sideScrim.isUserInteractionEnabled = false
        sideScrim.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(sideScrim)

        bodyBackdrop.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(bodyBackdrop)

        buildContent()
        buildButtons()

        column.axis = .vertical
        column.alignment = .leading
        column.translatesAutoresizingMaskIntoConstraints = false
        column.addArrangedSubview(textBlock)
        column.addArrangedSubview(buttonsGlass)
        addSubview(column)

        visualTop = visual.topAnchor.constraint(equalTo: topAnchor)
        visualBottom = visual.bottomAnchor.constraint(
            equalTo: bottomAnchor, constant: artworkOverhang
        )
        artworkBottom = artwork.bottomAnchor.constraint(
            equalTo: bottomAnchor, constant: artworkOverhang
        )
        columnLeading = column.leadingAnchor.constraint(equalTo: leadingAnchor)
        columnBottom = column.bottomAnchor.constraint(equalTo: bottomAnchor)
        columnWidth = column.widthAnchor.constraint(equalTo: widthAnchor)
        ownHeight = heightAnchor.constraint(equalToConstant: baseHeight)

        NSLayoutConstraint.activate([
            ownHeight,
            visual.leadingAnchor.constraint(equalTo: leadingAnchor),
            visual.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualTop,
            visualBottom,

            columnLeading,
            columnBottom,
            columnWidth,
            textBlock.widthAnchor.constraint(equalTo: column.widthAnchor),

            artwork.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
            artwork.topAnchor.constraint(equalTo: visual.topAnchor),
            artworkBottom,
        ])

        bodyBackdropHeight = bodyBackdrop.heightAnchor.constraint(equalToConstant: 140)
        NSLayoutConstraint.activate([
            bodyBackdrop.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
            bodyBackdrop.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
            bodyBackdrop.bottomAnchor.constraint(equalTo: visual.bottomAnchor),
            bodyBackdropHeight,
        ])

        for gradient in [scrim, sideScrim] {
            NSLayoutConstraint.activate([
                gradient.leadingAnchor.constraint(equalTo: artwork.leadingAnchor),
                gradient.trailingAnchor.constraint(equalTo: artwork.trailingAnchor),
                gradient.topAnchor.constraint(equalTo: artwork.topAnchor),
                gradient.bottomAnchor.constraint(equalTo: artwork.bottomAnchor),
            ])
        }
    }

    private func buildContent() {
        logoView.contentMode = .scaleAspectFit
        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        titleSlot.translatesAutoresizingMaskIntoConstraints = false
        titleSlot.addSubview(logoView)
        titleSlot.addSubview(titleLabel)

        titleSlotHeight = titleSlot.heightAnchor.constraint(equalToConstant: 80)
        logoHeight = logoView.heightAnchor.constraint(equalToConstant: 80)
        logoMaxWidth = logoView.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        logoHeight.priority = .defaultHigh

        logoLeading = logoView.leadingAnchor.constraint(equalTo: titleSlot.leadingAnchor)
        logoCenterX = logoView.centerXAnchor.constraint(equalTo: titleSlot.centerXAnchor)

        NSLayoutConstraint.activate([
            titleSlotHeight,
            logoHeight,
            logoMaxWidth,
            logoLeading,
            logoView.bottomAnchor.constraint(equalTo: titleSlot.bottomAnchor),
            logoView.topAnchor.constraint(greaterThanOrEqualTo: titleSlot.topAnchor),
            logoView.leadingAnchor.constraint(greaterThanOrEqualTo: titleSlot.leadingAnchor),
            logoView.trailingAnchor.constraint(lessThanOrEqualTo: titleSlot.trailingAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: titleSlot.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: titleSlot.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: titleSlot.bottomAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: titleSlot.topAnchor),
        ])

        metaLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        imdbLogoView.contentMode = .scaleAspectFit
        imdbLogoView.image = UIImage(named: "imdb_logo")
        imdbLogoView.setContentHuggingPriority(.required, for: .horizontal)
        imdbLogoView.setContentCompressionResistancePriority(.required, for: .horizontal)

        imdbRatingLabel.textColor = AppPalette.imdbGold
        imdbRatingLabel.setContentHuggingPriority(.required, for: .horizontal)
        imdbRatingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        imdbRow.axis = .horizontal
        imdbRow.alignment = .center
        imdbRow.spacing = 6
        imdbRow.translatesAutoresizingMaskIntoConstraints = false
        [imdbLogoView, imdbRatingLabel].forEach(imdbRow.addArrangedSubview)

        imdbLogoHeight = imdbLogoView.heightAnchor.constraint(equalToConstant: 16)
        imdbLogoAspect = imdbLogoView.widthAnchor.constraint(
            equalTo: imdbLogoView.heightAnchor, multiplier: 575.0 / 290.0
        )
        NSLayoutConstraint.activate([imdbLogoHeight, imdbLogoAspect])

        ageBadge.textColor = UIColor.white.withAlphaComponent(0.92)
        ageBadge.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        ageBadge.layer.cornerRadius = 4
        ageBadge.layer.cornerCurve = .continuous
        ageBadge.clipsToBounds = true
        ageBadge.textAlignment = .center
        ageBadge.setContentHuggingPriority(.required, for: .horizontal)
        ageBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        metaTrailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        metaTrailingSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        metaRow.axis = .horizontal
        metaRow.alignment = .center
        metaRow.spacing = 10
        metaRow.translatesAutoresizingMaskIntoConstraints = false
        [metaLabel, imdbRow, ageBadge, metaTrailingSpacer].forEach(metaRow.addArrangedSubview)

        plotLabel.textColor = UIColor.white.withAlphaComponent(0.80)
        plotLabel.numberOfLines = 2
        plotLabel.translatesAutoresizingMaskIntoConstraints = false
        plotHeight = plotLabel.heightAnchor.constraint(equalToConstant: 40)
        plotHeight.isActive = true

        textBlock.axis = .vertical
        textBlock.alignment = .fill
        textBlock.translatesAutoresizingMaskIntoConstraints = false
        [titleSlot, metaRow, plotLabel].forEach(textBlock.addArrangedSubview)
    }

    private func buildButtons() {
        playButton.addSpringPressFeedback()
        watchlistButton.addSpringPressFeedback(scale: 0.90)

        // Kaydetmenin tek yeri izleme listesi. Favori yalnızca canlı
        // kanallarda kaldı ve kanalın detay ekranı yok.
        let actionButtons = [playButton, watchlistButton]

        let buttons = UIStackView(arrangedSubviews: actionButtons)
        buttons.axis = .horizontal
        buttons.spacing = 10
        buttons.alignment = .center

        for button in actionButtons.dropFirst() {
            button.heightAnchor.constraint(equalTo: playButton.heightAnchor).isActive = true
        }

        buttonsGlass = UIView.glassContainer(wrapping: buttons, spacing: 10)
    }

    func setLogo(_ logo: UIImage?) {
        logoView.isHidden = logo == nil
        logoView.image = logo

        logoAspect?.isActive = false
        if let logo, logo.size.height > 0 {
            logoAspect = logoView.widthAnchor.constraint(
                equalTo: logoView.heightAnchor,
                multiplier: logo.size.width / logo.size.height
            )
        } else {
            logoAspect = logoView.widthAnchor.constraint(equalToConstant: 0)
        }
        logoAspect?.isActive = true
    }

    func setPlayTitle(_ title: String) {
        let layout = appliedLayout ?? Self.layout(metrics: metrics, width: bounds.width > 0 ? bounds.width : 1920)
        #if os(tvOS)
        var play = UIButton.Configuration.appGlass(
            horizontalInset: layout.buttonInset * 1.3,
            verticalInset: layout.buttonVerticalInset,
            fontSize: layout.buttonFontSize
        )
        #else
        var play = UIButton.Configuration.appProminent(
            horizontalInset: layout.buttonInset * 1.3,
            verticalInset: layout.buttonVerticalInset,
            fontSize: layout.buttonFontSize
        )
        #endif
        play.image = UIImage(systemName: "play.fill")
        play.title = title
        playButton.configuration = play
    }

    func setWatchlist(isInWatchlist: Bool) {
        let layout = appliedLayout ?? Self.layout(metrics: metrics, width: bounds.width > 0 ? bounds.width : 1920)
        var config = UIButton.Configuration.appGlass(
            horizontalInset: layout.buttonInset,
            verticalInset: layout.buttonVerticalInset,
            fontSize: layout.buttonFontSize
        )
        config.image = UIImage(systemName: isInWatchlist ? "checkmark" : "plus")
        watchlistButton.configuration = config
    }

    func startLoadingAnimation() { artwork.startLoading() }

    func stopLoadingAnimation(animated: Bool = true) { artwork.stopLoading(animated: animated) }

    // MARK: - Düzen Hesabı

    private struct Layout: Equatable {
        var titleFont: UIFont
        var titleSlotHeight: CGFloat
        var logoHeight: CGFloat
        var logoMaxWidth: CGFloat
        var metaFont: UIFont
        var badgeFont: UIFont
        var plotFont: UIFont
        var iconSize: CGFloat
        var buttonFontSize: CGFloat
        var buttonInset: CGFloat
        var buttonVerticalInset: CGFloat
        var spacing: CGFloat
        var buttonSpacing: CGFloat
        var horizontalInset: CGFloat
        var contentBottomInset: CGFloat
        var backdropRamp: CGFloat
        var columnRatio: CGFloat
        var isCentered: Bool
    }

    private static func layout(metrics: AppMetrics, width: CGFloat) -> Layout {
        let titleSize = metrics.titleFont.pointSize
        let secondary = max(13, (titleSize * 0.42).rounded())
        let inset = metrics.screenPadding
        let ratio: CGFloat = width >= 900 ? 0.44 : 1
        #if os(tvOS)
        let contentInset = max(18, (inset * 0.35).rounded())
        #else
        let contentInset = max(20, (inset * 0.45).rounded())
        #endif

        return Layout(
            titleFont: metrics.titleFont,
            titleSlotHeight: (titleSize * 1.3).rounded(),
            logoHeight: (titleSize * 0.56).rounded(),
            logoMaxWidth: width >= 900 ? 280 : 160,
            metaFont: .systemFont(ofSize: secondary, weight: .medium),
            badgeFont: .systemFont(ofSize: max(11, secondary - 3), weight: .semibold),
            plotFont: .systemFont(ofSize: secondary),
            iconSize: (secondary * 1.1).rounded(),
            buttonFontSize: max(14, (secondary * 1.05).rounded()),
            buttonInset: max(18, (secondary * 1.1).rounded()),
            buttonVerticalInset: max(11, (secondary * 0.55).rounded()),
            spacing: max(14, (inset * 0.40).rounded()),
            buttonSpacing: max(20, (inset * 0.55).rounded()),
            horizontalInset: inset,
            contentBottomInset: contentInset,
            backdropRamp: max(140, (metrics.rowSpacing * 2.5).rounded()),
            columnRatio: ratio,
            isCentered: ratio >= 1
        )
    }

    func updateMetrics(_ metrics: AppMetrics) {
        self.metrics = metrics
        applyLayoutIfNeeded()
    }

    func updateBaseHeight(_ height: CGFloat) {
        guard height > 0, abs(height - baseHeight) > 0.5 else { return }
        baseHeight = height
        ownHeight.constant = height
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyLayoutIfNeeded()
    }

    private func applyLayoutIfNeeded() {
        let width = bounds.width
        guard width > 0 else { return }
        let layout = Self.layout(metrics: metrics, width: width)
        guard layout != appliedLayout else { return }
        appliedLayout = layout

        titleLabel.font = layout.titleFont
        titleSlotHeight.constant = layout.titleSlotHeight
        logoHeight.constant = layout.logoHeight
        logoMaxWidth.constant = layout.logoMaxWidth

        metaLabel.font = layout.metaFont
        imdbRatingLabel.font = layout.metaFont
        ageBadge.font = layout.badgeFont
        imdbLogoHeight.constant = (layout.metaFont.pointSize * 0.85).rounded()

        plotLabel.font = layout.plotFont
        plotHeight.constant = (layout.plotFont.lineHeight * 2).rounded(.up)

        textBlock.spacing = layout.spacing
        column.spacing = layout.buttonSpacing
        columnLeading.constant = layout.horizontalInset
        applyContentLift()

        columnWidth.isActive = false
        columnWidth = column.widthAnchor.constraint(
            equalTo: widthAnchor,
            multiplier: layout.columnRatio,
            constant: layout.columnRatio < 1 ? 0 : -layout.horizontalInset * 2
        )
        columnWidth.isActive = true

        bodyBackdrop.rampHeight = layout.backdropRamp
        bodyBackdropHeight.constant = layout.backdropRamp

        sideScrim.isHidden = layout.isCentered

        titleLabel.textAlignment = layout.isCentered ? .center : .natural
        logoLeading.isActive = !layout.isCentered
        logoCenterX.isActive = layout.isCentered

        configureButtons(layout: layout)
    }

    private func configureButtons(layout: Layout) {
        let currentPlayTitle = playButton.configuration?.title ?? L10n.play
        setPlayTitle(currentPlayTitle)

        let isWatchlist = watchlistButton.configuration?.image == UIImage(systemName: "checkmark")
        setWatchlist(isInWatchlist: isWatchlist)
    }

    // MARK: - Kaydırma

    func applyScroll(offset: CGFloat) {
        let top = -max(0, -offset)
        let progress = min(max(offset / Self.contentLiftRamp, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        let lift = eased * Self.contentLiftDistance

        if abs(visualTop.constant - top) > 0.5 || abs(contentLift - lift) > 0.5 {
            visualTop.constant = top
            contentLift = lift
            applyContentLift()
            layoutIfNeeded()
        }
    }

    private func applyContentLift() {
        let layout = appliedLayout
        columnBottom.constant = -((layout?.contentBottomInset ?? 0) + contentLift)
    }
}
