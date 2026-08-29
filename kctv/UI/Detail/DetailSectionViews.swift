import UIKit

/// Künyedeki tek oyuncu: yuvarlak fotoğraf, ad ve canlandırdığı karakter.
/// Apple TV'nin detay ekranındaki oyuncu rayının karşılığı.
final class CastMemberCell: UICollectionViewCell {
    static let reuseID = "CastMemberCell"
    private static let focusScale: CGFloat = 1.06

    private let photo = RemoteImageView()
    private let nameLabel = UILabel()
    private let roleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        photo.clipsToBounds = true
        photo.isCircular = true
        photo.layer.borderColor = UIColor.white.cgColor
        photo.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.textColor = AppPalette.primaryText
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        roleLabel.textColor = AppPalette.secondaryText
        roleLabel.textAlignment = .center
        roleLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [photo, nameLabel, roleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center
        stack.setCustomSpacing(10, after: photo)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        #if os(tvOS)
        prepareFocusShadow()
        #endif

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            photo.widthAnchor.constraint(equalTo: contentView.widthAnchor),
            photo.heightAnchor.constraint(equalTo: photo.widthAnchor),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        photo.prepareForReuse()
        photo.layer.borderWidth = 0
    }

    #if os(tvOS)
    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        let focused = isFocused
        photo.layer.borderWidth = focused ? UIView.focusedBorderWidth / Self.focusScale : 0
        updateFocusAppearance(isFocused: focused, using: coordinator, scale: Self.focusScale)
    }
    #endif

    func configure(member: TMDBCastMember, metrics: AppMetrics, photoWidth: CGFloat) {
        // Daire zaten büyük; isimler ölçekte geride kalıyor.
        nameLabel.font = .systemFont(ofSize: metrics.listSubtitleFont.pointSize - 3, weight: .medium)
        roleLabel.font = .systemFont(ofSize: metrics.listSubtitleFont.pointSize - 5)
        nameLabel.text = member.name
        roleLabel.text = member.character
        roleLabel.isHidden = member.character == nil
        // Fotoğrafı olmayan oyuncuda baş harfler yer tutuyor.
        photo.showsInitials = true
        photo.configure(url: member.profileURL, title: member.name, displayWidth: photoWidth)
    }
}

/// Bölüm ve fragman kartı: yatay görsel, metin görselin üstündeki buzlu
/// şeritte. Kart tamamen görselden ibaret; altında etiket yok.
final class MediaClipCell: UICollectionViewCell {
    static let reuseID = "MediaClipCell"
    private static let focusScale: CGFloat = 1.08

    private let still = RemoteImageView()
    private let overlay = CardOverlayView()

    private var title = ""
    private var durationText: String?
    private var progress: Double?
    private var metrics: AppMetrics?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        still.clipsToBounds = true
        still.layer.cornerCurve = .continuous
        still.translatesAutoresizingMaskIntoConstraints = false
        overlay.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(still)
        // Bindirme görselin içinde: kartın köşe yuvarlaması onu da kırpıyor.
        still.addSubview(overlay)

        still.layer.borderColor = UIColor.white.cgColor
        #if os(tvOS)
        prepareFocusShadow()
        #endif

        NSLayoutConstraint.activate([
            still.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            still.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            still.topAnchor.constraint(equalTo: contentView.topAnchor),
            still.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            overlay.leadingAnchor.constraint(equalTo: still.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: still.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: still.bottomAnchor),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        still.prepareForReuse()
        still.layer.borderWidth = 0
    }

    #if os(tvOS)
    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        // Odaktaki kart geniş yerleşime geçiyor: başlık kendi satırında,
        // altında tam genişlikte ilerleme ve sağda süre. Bu değişim animasyona
        // sokulmuyor — öğeler yer değiştirdiği için kayma/zıplama üretiyordu.
        // Yumuşak geçiş yalnızca kartın kendisinde.
        applyOverlay()
        layoutIfNeeded()

        // Kenarlık animasyona girmiyor: düz açılıp kapanıyor.
        let focused = isFocused
        still.layer.borderWidth = focused ? UIView.focusedBorderWidth / Self.focusScale : 0

        updateFocusAppearance(isFocused: focused, using: coordinator, scale: Self.focusScale)
    }
    #endif

    func configure(
        title: String,
        durationText: String?,
        imageURL: URL?,
        metrics: AppMetrics,
        width: CGFloat,
        playedFraction: Double?
    ) {
        self.title = title
        self.durationText = durationText
        self.progress = playedFraction
        self.metrics = metrics

        still.layer.cornerRadius = metrics.cardCornerRadius
        still.showsInitials = false
        still.configure(url: imageURL, title: title, displayWidth: width)
        applyOverlay()
    }

    private func applyOverlay() {
        guard let metrics else { return }
        #if os(tvOS)
        let focused = isFocused
        #else
        let focused = false
        #endif
        overlay.configure(
            title: title,
            durationText: durationText,
            progress: progress,
            focused: focused,
            metrics: metrics
        )
    }
}

/// "Bilgi" ızgarasındaki tek alan: üstte etiket, altında değer.
final class InfoFieldView: UIView {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()

    init(title: String, value: String, metrics: AppMetrics) {
        super.init(frame: .zero)

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: metrics.listSubtitleFont.pointSize - 1)
        titleLabel.textColor = AppPalette.secondaryText

        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: metrics.listSubtitleFont.pointSize, weight: .semibold)
        valueLabel.textColor = AppPalette.primaryText
        valueLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
