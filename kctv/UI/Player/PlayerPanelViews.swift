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

/// Kanal çekmecesindeki tek satır: numara, logo, kanal adı ve o an yayında
/// olan program.
///
/// Rehberdeki satırın dar çekmeceye sığan hâli — sıradaki program ve ilerleme
/// çubuğu buraya sığmıyor, onların yerine oynayan kanalın yanında bir dalga
/// simgesi duruyor. Yükseklik sabit: program adı ağdan sonradan geliyor ve
/// satırların o sırada yeniden ölçülmesi listeyi kaydırıyordu.
final class PlayerChannelCell: UITableViewCell {
    static let reuseID = "PlayerChannelCell"

    #if os(tvOS)
    private static let logoWidth: CGFloat = 80
    private static let logoHeight: CGFloat = 56
    private static let nameSize: CGFloat = 28
    private static let programSize: CGFloat = 22
    #else
    private static let logoWidth: CGFloat = 54
    private static let logoHeight: CGFloat = 36
    private static let nameSize: CGFloat = 17
    private static let programSize: CGFloat = 13
    #endif

    private let numberLabel = UILabel()
    private let logo = RemoteImageView()
    private let nameLabel = UILabel()
    private let programLabel = UILabel()
    private let playingIcon = UIImageView()

    private var isHovered = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        backgroundColor = .clear
        selectionStyle = .none

        preservesSuperviewLayoutMargins = false
        contentView.preservesSuperviewLayoutMargins = false
        layoutMargins = .zero
        contentView.layoutMargins = .zero
        directionalLayoutMargins = .zero
        contentView.directionalLayoutMargins = .zero

        contentView.layer.cornerRadius = 10
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        // Numaralar doğrudan soldan başlasın
        numberLabel.font = .monospacedDigitSystemFont(ofSize: Self.programSize, weight: .bold)
        numberLabel.textAlignment = .left
        numberLabel.setContentHuggingPriority(.required, for: .horizontal)
        numberLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Logoları kırpmadan, orijinal oranını koruyarak göster
        logo.imageContentMode = .scaleAspectFit
        logo.showsPlaceholderBackground = false
        logo.showsInitials = false
        logo.backgroundColor = .clear
        logo.clipsToBounds = false

        nameLabel.font = .systemFont(ofSize: Self.nameSize, weight: .semibold)
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail

        programLabel.font = .systemFont(ofSize: Self.programSize, weight: .regular)
        programLabel.numberOfLines = 1
        programLabel.lineBreakMode = .byTruncatingTail

        playingIcon.image = UIImage(systemName: "waveform")
        playingIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: Self.programSize + 2, weight: .semibold
        )
        playingIcon.contentMode = .center
        playingIcon.setContentHuggingPriority(.required, for: .horizontal)
        playingIcon.setContentCompressionResistancePriority(.required, for: .horizontal)

        let texts = UIStackView(arrangedSubviews: [nameLabel, programLabel])
        texts.axis = .vertical
        texts.spacing = 3

        let row = UIStackView(arrangedSubviews: [numberLabel, logo, texts, playingIcon])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),

            numberLabel.widthAnchor.constraint(equalToConstant: 28),
            logo.widthAnchor.constraint(equalToConstant: Self.logoWidth),
            logo.heightAnchor.constraint(equalToConstant: Self.logoHeight),
        ])

        #if os(iOS)
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hover)
        #endif

        updateVisualState(isActive: false)
    }

    #if os(iOS)
    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            isHovered = true
        case .ended, .cancelled:
            isHovered = false
        default:
            break
        }
        updateVisualState(isActive: isHovered || isHighlighted || isSelected)
    }
    #endif

    #if os(tvOS)
    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.updateVisualState(isActive: self.isFocused)
        }
    }
    #endif

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        updateVisualState(isActive: isFocused || isHovered || highlighted || isSelected)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        updateVisualState(isActive: isFocused || isHovered || isHighlighted || selected)
    }

    private func updateVisualState(isActive: Bool) {
        if isActive {
            contentView.backgroundColor = .white
            numberLabel.textColor = UIColor.black.withAlphaComponent(0.65)
            nameLabel.textColor = .black
            programLabel.textColor = UIColor.black.withAlphaComponent(0.75)
            playingIcon.tintColor = .black
        } else {
            contentView.backgroundColor = .clear
            numberLabel.textColor = UIColor.white.withAlphaComponent(0.5)
            nameLabel.textColor = .white
            programLabel.textColor = UIColor.white.withAlphaComponent(0.6)
            playingIcon.tintColor = .white
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        logo.prepareForReuse()
        isHovered = false
        updateVisualState(isActive: false)
    }

    func configure(channel: MediaItem, program: String?, isPlaying: Bool) {
        numberLabel.text = channel.channelNumber.map(String.init) ?? "—"
        nameLabel.text = channel.title
        playingIcon.isHidden = !isPlaying
        logo.configure(url: channel.posterURL, title: channel.title, displayWidth: Self.logoWidth)
        setProgram(program)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = isPlaying
            ? "\(channel.title), \(L10n.nowPlayingBadge)"
            : channel.title
        updateVisualState(isActive: isFocused || isHovered || isHighlighted || isSelected)
    }

    func setProgram(_ program: String?) {
        programLabel.text = program ?? " "
    }
}

/// Çekmecedeki kategori satırı.
final class PlayerCategoryCell: UITableViewCell {
    static let reuseID = "PlayerCategoryCell"

    #if os(tvOS)
    private static let titleSize: CGFloat = 28
    private static let countSize: CGFloat = 22
    private static let iconSize: CGFloat = 24
    #else
    private static let titleSize: CGFloat = 17
    private static let countSize: CGFloat = 15
    private static let iconSize: CGFloat = 18
    #endif

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let chevronView = UIImageView()
    private var isHovered = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        backgroundColor = .clear
        selectionStyle = .none

        preservesSuperviewLayoutMargins = false
        contentView.preservesSuperviewLayoutMargins = false
        layoutMargins = .zero
        contentView.layoutMargins = .zero
        directionalLayoutMargins = .zero
        contentView.directionalLayoutMargins = .zero

        contentView.layer.cornerRadius = 10
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        iconView.image = UIImage(systemName: "tv")
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: Self.iconSize, weight: .medium
        )
        iconView.contentMode = .center
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.font = .systemFont(ofSize: Self.titleSize, weight: .semibold)
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        countLabel.font = .monospacedDigitSystemFont(ofSize: Self.countSize, weight: .regular)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        chevronView.image = UIImage(systemName: "chevron.right")
        chevronView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: Self.countSize - 1, weight: .semibold
        )
        chevronView.contentMode = .center
        chevronView.setContentHuggingPriority(.required, for: .horizontal)
        chevronView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [iconView, titleLabel, countLabel, chevronView])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
        ])

        #if os(iOS)
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hover)
        #endif

        updateVisualState(isActive: false)
    }

    #if os(iOS)
    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            isHovered = true
        case .ended, .cancelled:
            isHovered = false
        default:
            break
        }
        updateVisualState(isActive: isHovered || isHighlighted || isSelected)
    }
    #endif

    #if os(tvOS)
    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.updateVisualState(isActive: self.isFocused)
        }
    }
    #endif

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        updateVisualState(isActive: isFocused || isHovered || highlighted || isSelected)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        updateVisualState(isActive: isFocused || isHovered || isHighlighted || selected)
    }

    private func updateVisualState(isActive: Bool) {
        if isActive {
            contentView.backgroundColor = .white
            iconView.tintColor = .black
            titleLabel.textColor = .black
            countLabel.textColor = UIColor.black.withAlphaComponent(0.7)
            chevronView.tintColor = .black
        } else {
            contentView.backgroundColor = .clear
            iconView.tintColor = UIColor.white.withAlphaComponent(0.6)
            titleLabel.textColor = .white
            countLabel.textColor = UIColor.white.withAlphaComponent(0.5)
            chevronView.tintColor = UIColor.white.withAlphaComponent(0.4)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
        updateVisualState(isActive: false)
    }

    func configure(title: String, count: Int) {
        titleLabel.text = title
        countLabel.text = String(count)
        updateVisualState(isActive: isFocused || isHovered || isHighlighted || isSelected)
    }
}

/// "Listem" sekmesi için henüz içerik yokken gösterilen boş durum görünümü.
final class PlayerEmptyListPlaceholderView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    let editButton = UIButton()

    var onEditTapped: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        iconView.image = UIImage(systemName: "bookmark")
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 32, weight: .medium)
        iconView.tintColor = UIColor.white.withAlphaComponent(0.4)
        iconView.contentMode = .center

        titleLabel.text = L10n.emptyMyList
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        subtitleLabel.text = L10n.emptyMyListSubtitle
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        var editConfig = UIButton.Configuration.appGlass(horizontalInset: 16, verticalInset: 8, fontSize: 14)
        editConfig.title = L10n.editList
        editConfig.image = UIImage(systemName: "pencil")
        editConfig.imagePadding = 6
        editButton.configuration = editConfig
        editButton.addSpringPressFeedback()
        editButton.addAction(UIAction { [weak self] _ in self?.onEditTapped?() }, for: .primaryActionTriggered)

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, subtitleLabel, editButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }
}

/// Geriye uyumluluk için bölüm başlığı.
final class PlayerChannelSectionHeader: UITableViewHeaderFooterView {
    static let reuseID = "PlayerChannelSectionHeader"

    #if os(tvOS)
    private static let titleSize: CGFloat = 22
    #else
    private static let titleSize: CGFloat = 12
    #endif

    private let titleLabel = UILabel()
    private let countLabel = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = UIColor(white: 0.07, alpha: 0.94)
        backgroundConfiguration = background

        titleLabel.font = .systemFont(ofSize: Self.titleSize, weight: .semibold)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        titleLabel.numberOfLines = 1

        countLabel.font = .monospacedDigitSystemFont(ofSize: Self.titleSize, weight: .regular)
        countLabel.textColor = UIColor.white.withAlphaComponent(0.4)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [titleLabel, countLabel])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        ])
    }

    func configure(title: String, count: Int) {
        titleLabel.text = title
        countLabel.text = String(count)
    }
}
