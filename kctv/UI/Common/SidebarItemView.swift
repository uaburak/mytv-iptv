import UIKit

#if os(tvOS)
enum SidebarRowGeometry {
    static let pillInset: CGFloat = 20
    static let itemHeight: CGFloat = 68
    static let slotLeading: CGFloat = 7
    static let slotSize: CGFloat = 54
    static let textGap: CGFloat = 14
}

/// Hem ana uygulamanın kenar çubuğunda (SidebarViewController) hem de
/// sayfa içi gömülü menülerde (BrowseViewController) kullanılan standart satır butonu.
final class SidebarItemView: FocusableControl {
    private let highlight = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private var titleAfterIcon: NSLayoutConstraint!
    private var titleAtLeading: NSLayoutConstraint!

    var onSelect: (() -> Void)?
    var onFocus: (() -> Void)?

    /// Boş bırakılırsa satırda simge yok: metin baştan başlıyor. Sunucudan
    /// gelen kategorilerde simge uydurmak yerine ad tek başına duruyor.
    var symbol: String = "" {
        didSet {
            let hasSymbol = !symbol.isEmpty
            iconView.image = hasSymbol ? UIImage(systemName: symbol) : nil
            iconView.isHidden = !hasSymbol
            titleAfterIcon?.isActive = hasSymbol
            titleAtLeading?.isActive = !hasSymbol
        }
    }

    /// Satırın sağ ucundaki ikincil metin — kategorilerde içerik sayısı.
    var detail: String? {
        didSet {
            detailLabel.text = detail
            detailLabel.isHidden = detail == nil
        }
    }

    var title: String = "" {
        didSet {
            titleLabel.text = title
            accessibilityLabel = title
        }
    }

    var isCurrent = false {
        didSet { applyFocusStyle(isFocused: isFocused) }
    }

    override var focusScale: CGFloat { 1.03 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        highlight.layer.cornerRadius = SidebarRowGeometry.itemHeight / 2
        highlight.layer.cornerCurve = .continuous
        highlight.isUserInteractionEnabled = false
        highlight.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 24, weight: .semibold
        )
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 26, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .systemFont(ofSize: 22, weight: .regular)
        detailLabel.textAlignment = .right
        detailLabel.isHidden = true
        detailLabel.setContentHuggingPriority(.required, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(highlight)
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(detailLabel)

        addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .primaryActionTriggered)

        titleAfterIcon = titleLabel.leadingAnchor.constraint(
            equalTo: iconView.trailingAnchor, constant: SidebarRowGeometry.textGap
        )
        titleAtLeading = titleLabel.leadingAnchor.constraint(
            equalTo: leadingAnchor, constant: SidebarRowGeometry.pillInset
        )
        titleAfterIcon.isActive = true

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SidebarRowGeometry.itemHeight),

            highlight.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor),
            highlight.topAnchor.constraint(equalTo: topAnchor),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: SidebarRowGeometry.slotLeading
            ),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: SidebarRowGeometry.slotSize),
            iconView.heightAnchor.constraint(equalToConstant: SidebarRowGeometry.slotSize),

            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: detailLabel.leadingAnchor, constant: -10
            ),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            detailLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -SidebarRowGeometry.pillInset
            ),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        applyFocusStyle(isFocused: false)
    }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        if isFocused {
            onFocus?()
        }
    }

    func configure(symbol: String, title: String, detail: String? = nil) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }

    override func applyFocusStyle(isFocused: Bool) {
        if isFocused {
            highlight.backgroundColor = .white
            iconView.tintColor = .black
            titleLabel.textColor = .black
            detailLabel.textColor = UIColor.black.withAlphaComponent(0.55)
        } else if isCurrent {
            highlight.backgroundColor = AppPalette.elevated
            iconView.tintColor = AppPalette.primaryText
            titleLabel.textColor = AppPalette.primaryText
            detailLabel.textColor = AppPalette.secondaryText
        } else {
            highlight.backgroundColor = .clear
            iconView.tintColor = AppPalette.secondaryText
            titleLabel.textColor = AppPalette.secondaryText
            detailLabel.textColor = AppPalette.secondaryText
        }
    }
}
#else
enum SidebarRowGeometry {
    static let pillInset: CGFloat = 12
    static let itemHeight: CGFloat = 44
    static let slotLeading: CGFloat = 4
    static let slotSize: CGFloat = 32
    static let textGap: CGFloat = 10
}

final class SidebarItemView: UIControl {
    private let highlight = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private var titleAfterIcon: NSLayoutConstraint!
    private var titleAtLeading: NSLayoutConstraint!

    var onSelect: (() -> Void)?
    var onFocus: (() -> Void)?

    /// Boş bırakılırsa satırda simge yok: metin baştan başlıyor.
    var symbol: String = "" {
        didSet {
            let hasSymbol = !symbol.isEmpty
            iconView.image = hasSymbol ? UIImage(systemName: symbol) : nil
            iconView.isHidden = !hasSymbol
            titleAfterIcon?.isActive = hasSymbol
            titleAtLeading?.isActive = !hasSymbol
        }
    }

    /// Satırın sağ ucundaki ikincil metin — kategorilerde içerik sayısı.
    var detail: String? {
        didSet {
            detailLabel.text = detail
            detailLabel.isHidden = detail == nil
        }
    }

    var title: String = "" {
        didSet { titleLabel.text = title }
    }

    var isCurrent = false {
        didSet {
            highlight.backgroundColor = isCurrent ? AppPalette.elevated : .clear
            iconView.tintColor = isCurrent ? AppPalette.primaryText : AppPalette.secondaryText
            titleLabel.textColor = isCurrent ? AppPalette.primaryText : AppPalette.secondaryText
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        highlight.layer.cornerRadius = SidebarRowGeometry.itemHeight / 2
        highlight.layer.cornerCurve = .continuous
        highlight.isUserInteractionEnabled = false
        highlight.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .center
        iconView.tintColor = AppPalette.secondaryText
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.textColor = AppPalette.secondaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .systemFont(ofSize: 14)
        detailLabel.textColor = AppPalette.secondaryText
        detailLabel.textAlignment = .right
        detailLabel.isHidden = true
        detailLabel.setContentHuggingPriority(.required, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(highlight)
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(detailLabel)

        addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .touchUpInside)

        titleAfterIcon = titleLabel.leadingAnchor.constraint(
            equalTo: iconView.trailingAnchor, constant: SidebarRowGeometry.textGap
        )
        titleAtLeading = titleLabel.leadingAnchor.constraint(
            equalTo: leadingAnchor, constant: SidebarRowGeometry.pillInset
        )
        titleAfterIcon.isActive = true

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SidebarRowGeometry.itemHeight),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor),
            highlight.topAnchor.constraint(equalTo: topAnchor),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SidebarRowGeometry.slotLeading),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: SidebarRowGeometry.slotSize),
            iconView.heightAnchor.constraint(equalToConstant: SidebarRowGeometry.slotSize),

            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailLabel.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SidebarRowGeometry.pillInset),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(symbol: String, title: String, detail: String? = nil) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }
}
#endif
