import UIKit

/// Boş liste, hata ve "henüz bir şey yok" durumlarının tek görünümü.
///
/// Daha önce her ekran kendi etiketini kuruyordu: punto her yerde `15pt`'e
/// sabitlenmişti ve tvOS'ta üç metre mesafeden okunmuyordu, kimi ekranda
/// başlık vardı kimisinde yoktu, yeniden deneme düğmesi yalnızca anasayfada
/// duruyordu. Tek görünüm hem ölçüyü platformdan alıyor hem de
/// simge → başlık → açıklama → eylem sırasını her yerde aynı tutuyor.
final class EmptyStateView: UIView {
    #if os(tvOS)
    private static let symbolPointSize: CGFloat = 72
    private static let titleFont = UIFont.systemFont(ofSize: 38, weight: .semibold)
    private static let messageFont = UIFont.systemFont(ofSize: 26)
    private static let maxWidth: CGFloat = 900
    private static let spacing: CGFloat = 22
    #else
    private static let symbolPointSize: CGFloat = 40
    private static let titleFont = UIFont.preferredFont(forTextStyle: .headline)
    private static let messageFont = UIFont.preferredFont(forTextStyle: .subheadline)
    private static let maxWidth: CGFloat = 420
    private static let spacing: CGFloat = 12
    #endif

    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(configuration: .appGlass(size: .regular))
    private let stack = UIStackView()

    private var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Görünümü kapsayıcının ortasına yerleştirir.
    ///
    /// Beş ekran aynı üç kısıtı tekrar tekrar yazıyordu; kenar payları da her
    /// birinde başka bir sayıydı.
    ///
    /// `centeredOn` verilirse görünüm kapsayıcının değil o alanın ortasına
    /// oturuyor: sayfanın solunda sabit bir menü varsa boş durum ızgaranın
    /// ortasında durmalı. Bu kısıtı sonradan **ekleyen** çağıran, kapsayıcıya
    /// bağlı olanla çelişen ikinci bir required kısıt kurmuş oluyordu; Auto
    /// Layout da çelişkiyi zincirin başka bir yerinden — menünün genişliğinden —
    /// kırıyordu.
    @discardableResult
    static func installed(in container: UIView, centeredOn target: UIView? = nil) -> EmptyStateView {
        let view = EmptyStateView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        container.addSubview(view)

        let center = target ?? container
        let width = view.widthAnchor.constraint(equalToConstant: maxWidth)
        width.priority = .defaultHigh

        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: center.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: center.centerYAnchor),
            width,
            view.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor, constant: 32
            ),
            view.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor, constant: -32
            ),
        ])
        return view
    }

    private func build() {
        symbolView.tintColor = UIColor.white.withAlphaComponent(0.35)
        symbolView.contentMode = .scaleAspectFit
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: Self.symbolPointSize, weight: .regular
        )

        titleLabel.font = Self.titleFont
        titleLabel.textColor = AppPalette.primaryText
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true

        messageLabel.font = Self.messageFont
        messageLabel.textColor = AppPalette.secondaryText
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true

        actionButton.addSpringPressFeedback()
        actionButton.addAction(
            UIAction { [weak self] _ in self?.onAction?() }, for: .primaryActionTriggered
        )

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Self.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        [symbolView, titleLabel, messageLabel, actionButton].forEach(stack.addArrangedSubview)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Erişilebilirlikte tek parça okunuyor; ayrı ayrı gezilecek bir şey yok.
        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    /// Verilmeyen her parça gizleniyor: yalnızca açıklama, yalnızca başlık ya
    /// da dördünün tamamı aynı görünümden çıkıyor.
    func configure(
        symbol: String? = nil,
        title: String? = nil,
        message: String? = nil,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        symbolView.image = symbol.flatMap { UIImage(systemName: $0) }
        symbolView.isHidden = symbolView.image == nil

        titleLabel.text = title
        titleLabel.isHidden = title?.isEmpty ?? true

        messageLabel.text = message
        messageLabel.isHidden = message?.isEmpty ?? true

        actionButton.configuration?.title = actionTitle
        actionButton.isHidden = actionTitle == nil
        self.onAction = onAction

        accessibilityLabel = [title, message].compactMap { $0 }.joined(separator: ". ")
    }
}
