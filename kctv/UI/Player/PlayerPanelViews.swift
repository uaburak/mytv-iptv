import UIKit

/// Oynatıcıdaki "Bilgi" paneli.
///
/// Solda yatay görsel, ortada başlık/konu/künye satırı, sağda aksiyonlar.
/// Kendi zemini yok: alttaki karartmanın üstünde duruyor ve denetim satırının
/// altına eklenince yığının tamamı yukarı kayıyor — hiçbir şey gizlenmiyor.
///
/// Detay ekranının küçültülmüş hâli değil; oynatmayı bölmeden bakılacak
/// kadarı burada.
final class PlayerInfoPanelView: UIView {
    /// Baştan oynat.
    var onRestart: (() -> Void)?
    /// Yalnızca dizide: sıradaki bölüme geç.
    var onNextEpisode: (() -> Void)?

    #if os(tvOS)
    private static let artWidth: CGFloat = 150
    private static let titleSize: CGFloat = 34
    private static let bodySize: CGFloat = 24
    private static let metaSize: CGFloat = 22
    #else
    private static let artWidth: CGFloat = 76
    private static let titleSize: CGFloat = 19
    private static let bodySize: CGFloat = 14
    private static let metaSize: CGFloat = 12
    #endif

    private let artwork = RemoteImageView()
    private let titleLabel = UILabel()
    private let plotLabel = UILabel()
    private let metaLabel = UILabel()
    private let restartButton = UIButton()
    private let nextButton = UIButton()

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        artwork.showsInitials = false
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 10
        artwork.layer.cornerCurve = .continuous
        artwork.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: Self.titleSize, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1

        plotLabel.font = .systemFont(ofSize: Self.bodySize)
        plotLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        plotLabel.numberOfLines = 3

        metaLabel.font = .systemFont(ofSize: Self.metaSize)
        metaLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        metaLabel.numberOfLines = 1

        configure(restartButton, title: L10n.playFromStart, symbol: "play.fill")
        restartButton.addTarget(self, action: #selector(restartTapped), for: .primaryActionTriggered)

        configure(nextButton, title: L10n.nextEpisode, symbol: "forward.end.fill")
        nextButton.addTarget(self, action: #selector(nextEpisodeTapped), for: .primaryActionTriggered)
        nextButton.isHidden = true

        let texts = UIStackView(arrangedSubviews: [titleLabel, plotLabel, metaLabel])
        texts.axis = .vertical
        texts.spacing = 6
        texts.setCustomSpacing(10, after: plotLabel)

        let actions = UIStackView(arrangedSubviews: [restartButton, nextButton])
        actions.axis = .vertical
        actions.spacing = 8
        actions.alignment = .fill
        // Aksiyonlar kendi boyunda kalsın; ortadaki metin bloğu esnesin.
        actions.setContentHuggingPriority(.required, for: .horizontal)
        actions.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [artwork, texts, actions])
        row.axis = .horizontal
        row.spacing = 20
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        // Görsel yoksa yığın bu görünümü sıfır genişliğe indiriyor; ölçü
        // kısıtları o durumda çözülemez olmasın diye gerekli seviyenin altında.
        let artWidth = artwork.widthAnchor.constraint(equalToConstant: Self.artWidth)
        let artHeight = artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor, multiplier: 9.0 / 16.0)
        artWidth.priority = .defaultHigh
        artHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            artWidth,
            artHeight,
        ])
    }

    /// `nextEpisode` yoksa sıradaki bölüm butonu gizli kalıyor: filmde ve
    /// dizinin son bölümünde gösterecek bir şey yok.
    func configure(item: MediaItem?, fallbackTitle: String, hasNextEpisode: Bool) {
        titleLabel.text = item?.title ?? fallbackTitle
        plotLabel.text = item?.plot
        plotLabel.isHidden = (item?.plot ?? "").isEmpty
        metaLabel.text = Self.metaText(for: item)
        metaLabel.isHidden = metaLabel.text?.isEmpty ?? true
        nextButton.isHidden = !hasNextEpisode

        // Yatay görsel: afiş ancak backdrop yoksa devreye giriyor ve o zaman
        // 16:9 çerçevede ortasından kırpılıyor.
        let art = item?.backdropURL ?? item?.posterURL
        artwork.configure(
            url: art,
            title: item?.title ?? fallbackTitle,
            displayWidth: Self.artWidth
        )
        artwork.isHidden = art == nil
    }

    /// "Aksiyon ve Macera · 2019 · 2sa 32d · %92"
    private static func metaText(for item: MediaItem?) -> String {
        guard let item else { return "" }
        var parts: [String] = []
        if let genre = item.genres.first { parts.append(genre) }
        if let year = item.yearText { parts.append(year) }
        if let duration = item.durationText { parts.append(duration) }
        if let percent = item.ratingPercent { parts.append("%\(percent)") }
        return parts.joined(separator: " · ")
    }

    private func configure(_ button: UIButton, title: String, symbol: String) {
        var config = UIButton.Configuration.appGlass(horizontalInset: 20, verticalInset: 10, fontSize: Self.metaSize)
        config.title = title
        config.image = UIImage(systemName: symbol)
        button.configuration = config
        button.addSpringPressFeedback()
    }

    // Adlar `Tapped` ile bitiyor: `next` UIResponder'ın kendi özelliğiyle
    // çakışıyor ve selector belirsiz kalıyor.
    @objc private func restartTapped() { onRestart?() }
    @objc private func nextEpisodeTapped() { onNextEpisode?() }
}

/// Dosyanın kendi bölüm işaretleri için kart.
///
/// `MediaClipCell` bir görsel bekliyor; FFmpeg'in verdiği bölüm işaretinde
/// yalnızca ad ve başlangıç anı var. IPTV akışında kare üretmek ağdan ikinci
/// bir geçiş demek, o yüzden kart yazıyla kalıyor.
final class PlayerChapterCell: UICollectionViewCell {
    static let reuseID = "PlayerChapterCell"

    private let titleLabel = UILabel()
    private let timeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        #if os(tvOS)
        titleLabel.font = .systemFont(ofSize: 24, weight: .medium)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .regular)
        #else
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        #endif
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        timeLabel.textColor = UIColor.white.withAlphaComponent(0.6)

        let stack = UIStackView(arrangedSubviews: [titleLabel, timeLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)

        let surface = UIView.glassSurface(wrapping: stack, cornerRadius: 14, interactive: false)
        surface.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: contentView.topAnchor),
            surface.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        #if os(tvOS)
        prepareFocusShadow()
        #endif
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    #if os(tvOS)
    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        updateFocusAppearance(isFocused: isFocused, using: coordinator, scale: 1.06)
    }
    #endif

    func configure(title: String, timeText: String, isCurrent: Bool) {
        titleLabel.text = title
        timeLabel.text = isCurrent ? "\(L10n.nowPlayingBadge) · \(timeText)" : timeText
        timeLabel.textColor = isCurrent ? .white : UIColor.white.withAlphaComponent(0.6)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(title), \(timeText)"
    }
}
