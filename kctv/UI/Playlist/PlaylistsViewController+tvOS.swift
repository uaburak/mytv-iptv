#if os(tvOS)
import UIKit

/// Apple TV'de liste yönetimi.
///
/// Telefondaki tablo burada kullanılmıyordu: kaydırmalı satır eylemleri
/// tvOS'ta yok, gruplu tablo başlıkları on feet mesafeden okunmuyor ve seçili
/// listeyi gösteren minik onay imi kaybolup gidiyordu. Bunun yerine her liste
/// bir kart: adı büyük, kaynağı ve bitiş tarihi altında, aktif olan üstünde
/// rozetiyle. Odaktaki kart uygulamanın geri kalanı gibi büyüyor.
final class PlaylistsViewController: TVFormViewController {
    private let model: AppModel
    private var cards: [TVPlaylistCard] = []
    private var emptyState: EmptyStateView!

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        screenTitle = L10n.tabPlaylists
        super.viewDidLoad()
        emptyState = EmptyStateView.installed(in: view)
        installLongPressAction()
        rebuild()

        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuild), name: .appLanguageDidChange, object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuild()
    }

    // MARK: - İçerik

    @objc private func rebuild() {
        // Kartlar baştan kuruluyor; odak seçili listenin kartına geri dönüyor.
        let focused = cards.first(where: \.isFocused)?.identifier
        screenTitle = L10n.tabPlaylists
        clearSections()
        cards = []

        let playlists = model.playlists.playlists
        emptyState.isHidden = !playlists.isEmpty
        scrollView.isHidden = playlists.isEmpty
        emptyState.configure(
            symbol: "list.bullet.rectangle",
            title: L10n.noPlaylistsTitle,
            message: L10n.noPlaylistsSubtitle,
            actionTitle: L10n.addPlaylist
        ) { [weak self] in
            self?.addPlaylist()
        }
        guard !playlists.isEmpty else { return }

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 24
        grid.alignment = .fill

        for playlist in playlists {
            let card = TVPlaylistCard()
            card.configure(
                playlist: playlist,
                isActive: model.playlists.selected?.id == playlist.id,
                needsSecret: model.playlists.needsSecret(for: playlist)
            )
            card.onSelect = { [weak self] in self?.activate(playlist) }
            card.identifier = playlist.id
            cards.append(card)
            grid.addArrangedSubview(card)
        }

        let addCard = TVPlaylistAddCard()
        addCard.onSelect = { [weak self] in self?.addPlaylist() }
        grid.addArrangedSubview(addCard)

        contentStack.addArrangedSubview(grid)
        contentStack.addArrangedSubview(TVFormFooterLabel(text: L10n.playlistCardHint))
        register(rows: cards)
        restoreFocus(toRowWith: focused)
    }

    // MARK: - Eylemler

    private func activate(_ playlist: Playlist) {
        guard !model.playlists.needsSecret(for: playlist) else {
            promptForSecret(playlist: playlist)
            return
        }
        Task { [weak self] in
            await self?.model.selectPlaylist(playlist)
            self?.rebuild()
        }
    }

    private func addPlaylist() {
        present(
            UINavigationController.app(root: AddPlaylistViewController(model: model)),
            animated: true
        )
    }

    private func edit(_ playlist: Playlist) {
        present(
            UINavigationController.app(
                root: AddPlaylistViewController(model: model, editing: playlist)
            ),
            animated: true
        )
    }

    /// tvOS'ta satırı kaydırmak mümkün değil; düzenleme ve silme odaktaki
    /// karta basılı tutunca açılıyor.
    private func installLongPressAction() {
        let recognizer = UILongPressGestureRecognizer(
            target: self, action: #selector(handleLongPress)
        )
        recognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        view.addGestureRecognizer(recognizer)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let focused = cards.first(where: \.isFocused),
              let playlist = model.playlists.playlists.first(where: { $0.id == focused.identifier })
        else { return }

        let sheet = UIAlertController(title: playlist.name, message: playlist.subtitle, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L10n.edit, style: .default) { [weak self] _ in
            self?.edit(playlist)
        })
        sheet.addAction(UIAlertAction(title: L10n.delete, style: .destructive) { [weak self] _ in
            self?.confirmDelete(playlist)
        })
        sheet.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        present(sheet, animated: true)
    }

    private func confirmDelete(_ playlist: Playlist) {
        let alert = UIAlertController(
            title: L10n.deletePlaylistConfirmTitle,
            message: L10n.deletePlaylistConfirmMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.delete, style: .destructive) { [weak self] _ in
            Task {
                await self?.model.removePlaylist(playlist)
                self?.rebuild()
            }
        })
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        present(alert, animated: true)
    }

    private func promptForSecret(playlist: Playlist) {
        let alert = UIAlertController(
            title: L10n.enterPasswordTitle,
            message: "\(playlist.name)\n\(L10n.enterPasswordMessage)",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = L10n.password
            textField.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: L10n.save, style: .default) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text, !text.isEmpty else { return }
            model.playlists.saveSecret(text, for: playlist)
            Task {
                await self.model.selectPlaylist(playlist)
                self.rebuild()
            }
        })
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        present(alert, animated: true)
    }
}

/// Tek listenin kartı.
private final class TVPlaylistCard: FocusableControl, TVFocusIdentifiable {
    private let container = UIView()
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let badge = BadgeCapsule()

    var onSelect: (() -> Void)?
    /// Liste kimliği; odak geri dönüşü ve basılı tutma menüsü bunu kullanıyor.
    var identifier: String?

    override var focusScale: CGFloat { 1.03 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        container.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        container.layer.cornerRadius = 26
        container.layer.cornerCurve = .continuous
        container.isUserInteractionEnabled = false
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        iconView.contentMode = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 34, weight: .semibold
        )
        iconView.image = UIImage(systemName: "list.bullet.rectangle")
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 34, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 24)
        detailLabel.numberOfLines = 1

        let column = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        column.axis = .vertical
        column.spacing = 6
        column.alignment = .leading
        column.translatesAutoresizingMaskIntoConstraints = false

        badge.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(column)
        container.addSubview(badge)

        addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .primaryActionTriggered)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 148),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),

            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 38),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 48),

            column.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 26),
            column.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            column.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -24),

            badge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -38),
            badge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        applyFocusStyle(isFocused: false)
    }

    func configure(playlist: Playlist, isActive: Bool, needsSecret: Bool) {
        nameLabel.text = playlist.name

        var parts = ["\(playlist.source.label) · \(playlist.subtitle)"]
        if let expiresAt = playlist.expiresAt {
            parts.append(L10n.expiresOn(expiresAt.formatted(date: .numeric, time: .omitted)))
        }
        detailLabel.text = parts.joined(separator: " · ")

        if needsSecret {
            badge.configure(text: L10n.passwordRequired, tint: .systemOrange)
        } else if isActive {
            badge.configure(text: L10n.activePlaylist, tint: AppPalette.accent)
        } else {
            badge.configure(text: nil, tint: .clear)
        }
        accessibilityLabel = [playlist.name, detailLabel.text].compactMap { $0 }.joined(separator: ", ")
        applyFocusStyle(isFocused: isFocused)
    }

    override func applyFocusStyle(isFocused: Bool) {
        container.backgroundColor = isFocused ? .white : UIColor.white.withAlphaComponent(0.06)
        nameLabel.textColor = isFocused ? .black : .white
        detailLabel.textColor = isFocused
            ? UIColor.black.withAlphaComponent(0.6)
            : AppPalette.secondaryText
        iconView.tintColor = isFocused ? .black : AppPalette.secondaryText
        badge.setOnLightBackground(isFocused)
    }
}

/// "Liste Ekle" kartı: kesikli çerçeveli, artı simgeli.
private final class TVPlaylistAddCard: FocusableControl {
    private let container = UIView()
    private let label = UILabel()
    private let iconView = UIImageView()

    var onSelect: (() -> Void)?

    override var focusScale: CGFloat { 1.03 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        container.layer.cornerRadius = 26
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 2
        container.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        container.isUserInteractionEnabled = false
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        iconView.image = UIImage(systemName: "plus")
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 30, weight: .semibold
        )
        iconView.contentMode = .center

        label.text = L10n.addPlaylist
        label.font = .systemFont(ofSize: 30, weight: .medium)

        let row = UIStackView(arrangedSubviews: [iconView, label])
        row.axis = .horizontal
        row.spacing = 16
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .primaryActionTriggered)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 110),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = L10n.addPlaylist
        applyFocusStyle(isFocused: false)
    }

    override func applyFocusStyle(isFocused: Bool) {
        container.backgroundColor = isFocused ? .white : .clear
        container.layer.borderColor = (isFocused ? UIColor.clear : UIColor.white.withAlphaComponent(0.18)).cgColor
        label.textColor = isFocused ? .black : AppPalette.secondaryText
        iconView.tintColor = isFocused ? .black : AppPalette.secondaryText
    }
}

/// Kart üzerindeki küçük durum rozeti.
private final class BadgeCapsule: UIView {
    private let label = UILabel()
    private var tint: UIColor = .clear

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String?, tint: UIColor) {
        self.tint = tint
        label.text = text
        isHidden = text == nil
        setOnLightBackground(false)
    }

    /// Odaktaki kartın zemini beyaz oluyor; rozet orada dolu renkte duruyor.
    func setOnLightBackground(_ isLight: Bool) {
        guard !isHidden else { return }
        backgroundColor = isLight ? tint : tint.withAlphaComponent(0.22)
        label.textColor = isLight ? .white : tint
    }
}
#endif
