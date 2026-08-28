import UIKit

/// Hesap, dil, listeler ve içerik yönetimi.
final class SettingsViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case account, language, content, developer
    }

    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.settingsTitle
        tableView.backgroundColor = AppPalette.background
        // Sekme olarak açıldığında kapat butonu anlamsız; yalnızca modalde.
        if presentingViewController != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close, target: self, action: #selector(close)
            )
        }
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.applyNativeScrollEdges()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .appLanguageDidChange,
            object: nil
        )
    }

    @objc private func languageDidChange() {
        title = L10n.settingsTitle
        tableView.reloadData()
    }

    @objc private func close() { dismiss(animated: true) }

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .account: L10n.sectionAccount
        case .language: L10n.sectionLanguage
        case .content: L10n.sectionContent
        case .developer: L10n.sectionDeveloper
        case nil: nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .account: 2
        case .language: 1
        case .content: 1 + (model.library.account != nil ? 2 : 0)
        case .developer: 1
        case nil: 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.tintColor = AppPalette.accent

        switch Section(rawValue: indexPath.section) {
        case .account:
            if indexPath.row == 0 {
                configuration.text = model.user?.displayName ?? (model.isGuest ? L10n.guestUser : L10n.regularUser)
                configuration.secondaryText = model.user?.email ?? L10n.demoModeNote
            } else {
                configuration.text = L10n.signOut
                configuration.textProperties.color = .systemRed
            }

        case .language:
            configuration.text = L10n.languageOption
            configuration.secondaryText = AppLanguage.current.displayName
            let menuButton = UIButton(type: .system)
            menuButton.setTitle(AppLanguage.current.displayName, for: .normal)
            menuButton.showsMenuAsPrimaryAction = true
            menuButton.menu = languageMenu()
            menuButton.sizeToFit()
            cell.accessoryView = menuButton

        case .content:
            switch indexPath.row {
            case 0:
                configuration.text = L10n.reloadPlaylist
                configuration.textProperties.color = AppPalette.accent
            case 1:
                configuration.text = L10n.subscriptionExpires
                configuration.secondaryText = model.library.account?.expiresAt
                    .map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"
            default:
                let account = model.library.account
                configuration.text = L10n.activeConnections
                configuration.secondaryText = "\(account?.activeConnections ?? 0)/\(account?.maxConnections ?? 0)"
            }

        case .developer:
            configuration.text = L10n.clearAllLocalData
            configuration.textProperties.color = .systemRed
            configuration.image = UIImage(systemName: "trash")
            configuration.imageProperties.tintColor = .systemRed

        case nil:
            break
        }

        cell.contentConfiguration = configuration
        return cell
    }

    private func languageMenu() -> UIMenu {
        let current = AppLanguage.current
        let actions = AppLanguage.allCases.map { lang in
            UIAction(
                title: lang.displayName,
                state: lang == current ? .on : .off
            ) { [weak self] _ in
                AppLanguage.current = lang
                self?.tableView.reloadData()
            }
        }
        return UIMenu(title: L10n.languageOption, children: actions)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section) {
        case .account where indexPath.row == 1:
            model.signOut()
            dismiss(animated: true)

        case .language:
            let alert = UIAlertController(title: L10n.languageOption, message: nil, preferredStyle: .actionSheet)
            for lang in AppLanguage.allCases {
                alert.addAction(UIAlertAction(title: lang.displayName, style: .default) { [weak self] _ in
                    AppLanguage.current = lang
                    self?.tableView.reloadData()
                })
            }
            alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
            if let popover = alert.popoverPresentationController {
                popover.sourceView = tableView.cellForRow(at: indexPath)
            }
            present(alert, animated: true)

        case .content where indexPath.row == 0:
            Task { await model.library.reload(force: true) }

        case .developer:
            confirmClearAllLocalData(sourceCell: tableView.cellForRow(at: indexPath))

        default:
            break
        }
    }

    private func confirmClearAllLocalData(sourceCell: UITableViewCell?) {
        let alert = UIAlertController(
            title: L10n.clearAllDataConfirmTitle,
            message: L10n.clearAllDataConfirmMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.clear, style: .destructive) { [weak self] _ in
            self?.model.resetAllLocalData()
            self?.dismiss(animated: true)
        })
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        present(alert, animated: true)
    }
}
