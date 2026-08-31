import UIKit

/// Arama ekranındaki kapsül düğme: son aramalar.
///
/// Hücrenin içinde gerçek bir `UIButton` var ve konfigürasyonu detay
/// ekranındaki sezon çipleriyle **aynı** (`UIButton.Configuration.appChip`):
/// cam zemin, odakta/hover'da sistemin kendi beyaz vurgusu.
///
/// Genişlik butonun kendi içeriğinden geliyor (`.estimated`), böylece son
/// aramalar satıra sığdığı kadar yan yana dizilip alt satıra taşıyor.
final class SearchChipCell: UICollectionViewCell {
    static let reuseID = "SearchChipCell"

    /// Ölçü uygulamanın ortak çip ölçüsü (`AppChipSize`): katalog şeridi,
    /// sezon seçici ve buradaki süzgeç aynı boyda duruyor. Düzen sabit bir
    /// yükseklik istediği için hesap burada da okunuyor.
    static let height: CGFloat = AppChipSize.regular.height

    private let button = UIButton(type: .system)
    private var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Odak **düğmeye** gitmeli: hücre odaklanabilir kaldığında odağı o
    /// yakalıyor, düğme hiç odaklanmadığı için sistemin beyaz vurgusu da
    /// çalışmıyordu — kumandayla üstüne gelince hiçbir şey olmuyordu.
    #if os(tvOS)
    override var canBecomeFocused: Bool { false }
    #endif

    private func build() {
        backgroundColor = .clear
        clipsToBounds = false
        contentView.clipsToBounds = false

        // Detay ekranındaki butonlarla birebir aynı basma animasyonu.
        button.addSpringPressFeedback(scale: 0.93)
        button.addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .primaryActionTriggered)
        button.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(button)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            button.topAnchor.constraint(equalTo: contentView.topAnchor),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            button.heightAnchor.constraint(equalToConstant: Self.height),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onTap = nil
    }

    /// - Parameter isSelected: seçili çip beyaz zemin + siyah metne dönüyor;
    ///   tür süzgecinde kullanılıyor, son aramalarda hep `false`.
    func configure(
        title: String,
        symbol: String?,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) {
        var configuration = UIButton.Configuration.appChip(isSelected: isSelected)
        configuration.title = title
        configuration.image = symbol.flatMap { UIImage(systemName: $0) }
        button.configuration = configuration
        self.onTap = onTap
    }
}

/// Arama ekranındaki bölüm başlığı. Sağında isteğe bağlı bir eylem duruyor —
/// son aramalarda "Temizle".
final class SearchSectionHeaderView: UICollectionReusableView {
    static let reuseID = "SearchSectionHeaderView"

    private let titleLabel = UILabel()
    /// Başlık yanındaki ikincil eylem; ortak çipin küçük ölçüsü.
    private let actionButton = UIButton(configuration: .appChip(isSelected: false, size: .small))

    var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.textColor = .white

        actionButton.addSpringPressFeedback(scale: 0.93)
        actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .primaryActionTriggered)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, UIView(), actionButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, font: UIFont, actionTitle: String?) {
        titleLabel.text = title
        titleLabel.font = font
        actionButton.isHidden = actionTitle == nil
        actionButton.configuration?.title = actionTitle
    }
}
