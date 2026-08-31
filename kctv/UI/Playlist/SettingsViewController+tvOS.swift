#if os(tvOS)
import UIKit

/// Apple TV ayarları.
///
/// Telefondaki `UITableViewController` burada kullanılmıyordu: tvOS'ta tablo
/// satırları küçük, odak vurgusu sistemin soluk grisi ve `UISwitch` ile
/// `insetGrouped` yok. Sonuç, uygulamanın geri kalanıyla hiç konuşmayan bir
/// ekrandı. Bu sürüm aynı bilgileri kenar çubuğuyla ve kartlarla aynı dilde
/// gösteriyor: geniş satırlar, odakta beyaz dolgu, sağda değer.
///
/// Dil seçimi de menü/aksiyon sayfası değil, doğrudan onay imli satırlar:
/// kumandayla iki adım eksiliyor ve seçili dil menüyü açmadan görünüyor.
final class SettingsViewController: TVFormViewController {
    private let model: AppModel
    private var isReloadingLibrary = false

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        screenTitle = L10n.settingsTitle
        super.viewDidLoad()
        rebuild()

        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuild), name: .appLanguageDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuild), name: .contentLibraryDidChange, object: nil
        )
    }

    // MARK: - İçerik

    @objc private func rebuild() {
        // Yeniden kurulum odaktaki satırı hiyerarşiden çıkarıyor; kimliği
        // tutup sonunda odağı aynı satıra geri veriyoruz.
        let focused = focusedRowIdentifier
        screenTitle = L10n.settingsTitle
        clearSections()
        addAccountSection()
        addLanguageSection()
        addContentSection()
        addDeveloperSection()
        restoreFocus(toRowWith: focused)
    }

    private func addAccountSection() {
        let identity = TVFormRow(
            symbol: "person.crop.circle",
            title: model.user?.displayName ?? (model.isGuest ? L10n.guestUser : L10n.regularUser),
            subtitle: model.user?.email ?? L10n.demoModeNote
        )
        // Kimlik satırı bilgi taşıyor, bir yere gitmiyor.
        identity.isUserInteractionEnabled = false

        let signOut = TVFormRow(symbol: "rectangle.portrait.and.arrow.right", title: L10n.signOut)
        signOut.identifier = "sign-out"
        signOut.isDestructive = true
        signOut.onSelect = { [weak self] in self?.confirmSignOut() }

        addSection(title: L10n.sectionAccount, rows: [identity, signOut])
    }

    private func addLanguageSection() {
        let current = AppLanguage.current
        let rows = AppLanguage.allCases.map { language -> TVFormRow in
            let row = TVFormRow(
                symbol: nil,
                title: language.displayName,
                accessory: .check(language == current)
            )
            row.identifier = "language-\(language.rawValue)"
            row.onSelect = { [weak self] in
                guard AppLanguage.current != language else { return }
                AppLanguage.current = language
                // Bildirim zaten `rebuild`'i çağırıyor; burada tekrar yok.
                _ = self
            }
            return row
        }
        addSection(title: L10n.sectionLanguage, rows: rows)
    }

    private func addContentSection() {
        let adult = TVFormRow(
            symbol: "eye.slash",
            title: L10n.hideAdultContent,
            accessory: .check(AppSettings.hidesAdultContent)
        )
        adult.identifier = "adult-filter"
        adult.onSelect = { [weak self] in
            AppSettings.hidesAdultContent.toggle()
            self?.model.library.applyContentFilter()
            self?.rebuild()
        }

        let reload = TVFormRow(
            symbol: "arrow.clockwise",
            title: L10n.reloadPlaylist,
            subtitle: isReloadingLibrary ? L10n.reloadingPlaylist : nil
        )
        reload.identifier = "reload-library"
        reload.isProminent = true
        reload.onSelect = { [weak self] in self?.reloadLibrary() }

        var rows: [UIView] = [adult, reload]
        if let account = model.library.account {
            rows.append(
                TVFormRow(
                    symbol: "calendar",
                    title: L10n.subscriptionExpires,
                    accessory: .value(
                        account.expiresAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"
                    )
                )
            )
            rows.append(
                TVFormRow(
                    symbol: "antenna.radiowaves.left.and.right",
                    title: L10n.activeConnections,
                    accessory: .value("\(account.activeConnections ?? 0)/\(account.maxConnections ?? 0)")
                )
            )
        }
        // Bilgi satırları odağa girmiyor: yapacak bir şey yok.
        for row in rows.dropFirst(2) { row.isUserInteractionEnabled = false }

        addSection(title: L10n.sectionContent, rows: rows, footer: L10n.hideAdultContentNote)
    }

    private func addDeveloperSection() {
        let clear = TVFormRow(symbol: "trash", title: L10n.clearAllLocalData)
        clear.identifier = "clear-local-data"
        clear.isDestructive = true
        clear.onSelect = { [weak self] in self?.confirmClearAllLocalData() }
        addSection(title: L10n.sectionDeveloper, rows: [clear])
    }

    // MARK: - Eylemler

    private func reloadLibrary() {
        guard !isReloadingLibrary else { return }
        isReloadingLibrary = true
        rebuild()
        Task { [weak self] in
            await self?.model.library.reload(force: true)
            self?.isReloadingLibrary = false
            self?.rebuild()
        }
    }

    private func confirmSignOut() {
        let alert = UIAlertController(title: L10n.signOut, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.signOut, style: .destructive) { [weak self] _ in
            self?.model.signOut()
        })
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        present(alert, animated: true)
    }

    private func confirmClearAllLocalData() {
        let alert = UIAlertController(
            title: L10n.clearAllDataConfirmTitle,
            message: L10n.clearAllDataConfirmMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.clear, style: .destructive) { [weak self] _ in
            self?.model.resetAllLocalData()
        })
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        present(alert, animated: true)
    }
}
#endif
