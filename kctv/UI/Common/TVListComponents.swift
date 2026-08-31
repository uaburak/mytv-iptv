#if os(tvOS)
import UIKit

/// Apple TV'de ayarlar, listeler ve benzeri "form" ekranlarının ortak
/// yapıtaşları.
///
/// Bu ekranlar daha önce `UITableView` ile çiziliyordu. tvOS'ta tablo, iOS'tan
/// devralınmış bir görünüm: satırlar minik, odak geri bildirimi sistemin gri
/// vurgusu, gruplu başlıklar da on feet mesafede okunmuyor. Uygulamanın geri
/// kalanı (kenar çubuğu, çipler, kartlar) beyaz dolgu + siyah yazı ve yumuşak
/// büyüme diliyle konuşuyor; bu bileşenler o dili forma taşıyor.
enum TVFormMetrics {
    /// İçerik kolonunun genişliği. Ekranın tamamına yayılan bir form 10 feet
    /// mesafeden okunmuyor; göz satır başına dönemiyor.
    static let contentWidth: CGFloat = 1180
    /// Sol üstteki bölüm rozetinin altından başlıyor.
    static let topInset: CGFloat = 140
    static let bottomInset: CGFloat = 80
    static let rowHeight: CGFloat = 92
    static let groupCornerRadius: CGFloat = 28
    static let groupSpacing: CGFloat = 48
    static let titleFont = UIFont.systemFont(ofSize: 62, weight: .bold)
    static let headerFont = UIFont.systemFont(ofSize: 24, weight: .semibold)
    static let rowTitleFont = UIFont.systemFont(ofSize: 30, weight: .medium)
    static let rowValueFont = UIFont.systemFont(ofSize: 28, weight: .regular)
    static let rowSubtitleFont = UIFont.systemFont(ofSize: 22, weight: .regular)
    static let footerFont = UIFont.systemFont(ofSize: 22, weight: .regular)
}

/// Yeniden kurulumdan sonra odağın geri döneceği görünümler bunu uyguluyor.
protocol TVFocusIdentifiable: UIView {
    var identifier: String? { get }
}

/// Grup başlığı: "HESAP", "İÇERİK" gibi.
final class TVFormSectionHeader: UILabel {
    init(title: String) {
        super.init(frame: .zero)
        text = title.uppercased()
        font = TVFormMetrics.headerFont
        textColor = AppPalette.secondaryText
        // Harf aralığı açıldığında grup başlığı satırdan ayrışıyor.
        if let text {
            attributedText = NSAttributedString(
                string: text.uppercased(),
                attributes: [.kern: 1.6, .font: font as Any, .foregroundColor: textColor as Any]
            )
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Grup altındaki açıklama satırı.
final class TVFormFooterLabel: UILabel {
    init(text: String) {
        super.init(frame: .zero)
        self.text = text
        font = TVFormMetrics.footerFont
        textColor = AppPalette.secondaryText
        numberOfLines = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Formdaki tek satır.
///
/// Solda simge, ortada başlık (ve varsa açıklama), sağda değer ya da onay imi.
/// Odakta beyaz dolgu ve siyah yazı — kenar çubuğu satırlarıyla aynı.
final class TVFormRow: FocusableControl, TVFocusIdentifiable {
    enum Accessory {
        case none
        case value(String)
        case check(Bool)
        case chevron
    }

    private let highlight = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let valueLabel = UILabel()
    private let accessoryView = UIImageView()
    private let separator = UIView()

    var onSelect: (() -> Void)?

    /// Ekran yeniden kurulduğunda odağın aynı satıra dönmesi için kimlik.
    var identifier: String?

    /// Yıkıcı eylemler (çıkış yap, sil) kırmızı yazıyor.
    var isDestructive = false { didSet { applyFocusStyle(isFocused: isFocused) } }
    /// Vurgulanan eylem (listeyi yenile) accent renginde.
    var isProminent = false { didSet { applyFocusStyle(isFocused: isFocused) } }
    /// Grubun son satırında ayraç yok.
    var showsSeparator = true { didSet { separator.isHidden = !showsSeparator } }

    override var focusScale: CGFloat { 1.02 }

    init(
        symbol: String?,
        title: String,
        subtitle: String? = nil,
        accessory: Accessory = .none
    ) {
        super.init(frame: .zero)
        build()
        configure(symbol: symbol, title: title, subtitle: subtitle, accessory: accessory)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(symbol: String?, title: String, subtitle: String?, accessory: Accessory) {
        iconView.image = symbol.flatMap { UIImage(systemName: $0) }
        iconView.isHidden = iconView.image == nil
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty ?? true

        switch accessory {
        case .none:
            valueLabel.isHidden = true
            accessoryView.isHidden = true
        case let .value(text):
            valueLabel.text = text
            valueLabel.isHidden = false
            accessoryView.isHidden = true
        case let .check(isOn):
            valueLabel.isHidden = true
            accessoryView.isHidden = !isOn
            accessoryView.image = UIImage(systemName: "checkmark")
        case .chevron:
            valueLabel.isHidden = true
            accessoryView.isHidden = false
            accessoryView.image = UIImage(systemName: "chevron.right")
        }

        accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")
        applyFocusStyle(isFocused: isFocused)
    }

    private func build() {
        highlight.layer.cornerRadius = 20
        highlight.layer.cornerCurve = .continuous
        highlight.isUserInteractionEnabled = false
        highlight.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 26, weight: .semibold
        )
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = TVFormMetrics.rowTitleFont
        subtitleLabel.font = TVFormMetrics.rowSubtitleFont
        subtitleLabel.numberOfLines = 1

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textColumn.axis = .vertical
        textColumn.spacing = 2
        textColumn.alignment = .leading
        textColumn.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = TVFormMetrics.rowValueFont
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        accessoryView.contentMode = .center
        accessoryView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 26, weight: .semibold
        )
        accessoryView.translatesAutoresizingMaskIntoConstraints = false

        separator.backgroundColor = AppPalette.separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(highlight)
        addSubview(iconView)
        addSubview(textColumn)
        addSubview(valueLabel)
        addSubview(accessoryView)
        addSubview(separator)

        addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .primaryActionTriggered)

        let textLeading = titleLabel.leadingAnchor
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: TVFormMetrics.rowHeight),

            highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            highlight.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 34),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 42),

            textColumn.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 22),
            textColumn.centerYAnchor.constraint(equalTo: centerYAnchor),
            textColumn.trailingAnchor.constraint(
                lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -24
            ),

            valueLabel.trailingAnchor.constraint(equalTo: accessoryView.leadingAnchor, constant: -12),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            accessoryView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -34),
            accessoryView.centerYAnchor.constraint(equalTo: centerYAnchor),
            accessoryView.widthAnchor.constraint(equalToConstant: 32),

            separator.leadingAnchor.constraint(equalTo: textLeading),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -34),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        applyFocusStyle(isFocused: false)
    }

    override func applyFocusStyle(isFocused: Bool) {
        // Odaktaki satırın ayracı görünmüyor: beyaz dolgunun içinde çizgi
        // kalıyordu.
        separator.alpha = isFocused ? 0 : 1
        guard !isFocused else {
            highlight.backgroundColor = .white
            let content: UIColor = isDestructive ? .systemRed : .black
            titleLabel.textColor = content
            iconView.tintColor = content
            accessoryView.tintColor = content
            subtitleLabel.textColor = UIColor.black.withAlphaComponent(0.6)
            valueLabel.textColor = UIColor.black.withAlphaComponent(0.6)
            return
        }
        highlight.backgroundColor = .clear
        let tint: UIColor = isDestructive ? .systemRed : (isProminent ? AppPalette.accent : .white)
        titleLabel.textColor = tint
        iconView.tintColor = isDestructive ? .systemRed : AppPalette.secondaryText
        accessoryView.tintColor = AppPalette.accent
        subtitleLabel.textColor = AppPalette.secondaryText
        valueLabel.textColor = AppPalette.secondaryText
    }
}

/// Satırları saran koyu kart. Grup sınırını gösteriyor.
final class TVFormGroup: UIView {
    private let stack = UIStackView()

    init(rows: [UIView]) {
        super.init(frame: .zero)
        backgroundColor = UIColor.white.withAlphaComponent(0.06)
        layer.cornerRadius = TVFormMetrics.groupCornerRadius
        layer.cornerCurve = .continuous
        // Odaktaki satır kartın dışına büyüyor; kırpma kapalı.
        clipsToBounds = false

        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        rows.forEach(stack.addArrangedSubview)
        (rows.last as? TVFormRow)?.showsSeparator = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Form ekranlarının kabuğu: başlık + dikey kaydırılan tek kolon.
///
/// Kaydırma tvOS'ta odakla yürüyor; `UIScrollView` odaklanan satırı
/// kendiliğinden görünür alana getiriyor.
class TVFormViewController: UIViewController {
    let scrollView = UIScrollView()
    let contentStack = UIStackView()
    private let titleLabel = UILabel()

    /// Ekran yeniden kurulduğunda odağın döneceği görünüm.
    ///
    /// Bu ekranlar bir ayar değişince baştan kuruluyor (dil seçildi, süzgeç
    /// açıldı, liste seçildi). Odaktaki satır o sırada hiyerarşiden çıktığı
    /// için odak listenin başına — hatta kenar çubuğuna — düşüyordu. Kimliği
    /// tutulan satır yeniden kurulduğunda odak oraya geri veriliyor.
    private var focusTarget: UIView?
    private var registeredRows: [UIView] = []

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let focusTarget { return [focusTarget] }
        return super.preferredFocusEnvironments
    }

    /// Şu an odakta olan satırın kimliği.
    var focusedRowIdentifier: String? {
        registeredRows.lazy
            .compactMap { $0 as? any TVFocusIdentifiable }
            .first { $0.isFocused }?
            .identifier
    }

    /// Yeniden kurulumdan sonra odağı kimliği verilen satıra döndürür.
    func restoreFocus(toRowWith identifier: String?) {
        guard let identifier,
              let match = registeredRows.lazy
                  .compactMap({ $0 as? any TVFocusIdentifiable })
                  .first(where: { $0.identifier == identifier })
        else { return }
        focusTarget = match
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        // Tek seferlik: sonraki odak hareketleri sisteme kalıyor.
        focusTarget = nil
    }

    /// Odak geri dönüşünde bulunabilmesi için satırı kaydeder.
    func register(rows: [UIView]) {
        registeredRows.append(contentsOf: rows)
    }

    /// Ekranın büyük başlığı.
    var screenTitle: String = "" {
        didSet { titleLabel.text = screenTitle }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        navigationItem.title = ""

        titleLabel.font = TVFormMetrics.titleFont
        titleLabel.textColor = .white
        titleLabel.text = screenTitle

        contentStack.axis = .vertical
        contentStack.spacing = TVFormMetrics.groupSpacing
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        // Kaydırma içeriği tek bir taşıyıcıda: genişliği ekranın genişliğine
        // eşit, böylece yatay kaydırma oluşmuyor ve içerik boyu belirsiz
        // kalmıyor. Kolon bu taşıyıcının içinde, solda, sabit genişlikte.
        let canvas = UIView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(canvas)

        let column = UIStackView(arrangedSubviews: [titleLabel, contentStack])
        column.axis = .vertical
        column.spacing = 44
        column.alignment = .fill
        column.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(column)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            canvas.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            canvas.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            column.topAnchor.constraint(equalTo: canvas.topAnchor, constant: TVFormMetrics.topInset),
            column.bottomAnchor.constraint(
                equalTo: canvas.bottomAnchor, constant: -TVFormMetrics.bottomInset
            ),
            column.leadingAnchor.constraint(
                equalTo: canvas.leadingAnchor,
                constant: AppMetrics.tv.screenPadding + 60
            ),
            column.widthAnchor.constraint(equalToConstant: TVFormMetrics.contentWidth),
        ])
    }

    /// Başlık + grup + açıklama üçlüsünü tek blok hâlinde ekler.
    func addSection(title: String?, rows: [UIView], footer: String? = nil) {
        let block = UIStackView()
        block.axis = .vertical
        block.spacing = 16
        block.alignment = .fill
        if let title { block.addArrangedSubview(TVFormSectionHeader(title: title)) }
        block.addArrangedSubview(TVFormGroup(rows: rows))
        if let footer { block.addArrangedSubview(TVFormFooterLabel(text: footer)) }
        contentStack.addArrangedSubview(block)
        register(rows: rows)
    }

    func clearSections() {
        registeredRows = []
        focusTarget = nil
        for view in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}
#endif
