import UIKit

/// Liste yönetimi: ekleme, seçme, düzenleme ve silme.
final class PlaylistsViewController: UIViewController {
    private let model: AppModel
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        updateLocalizedTexts()

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addPlaylist)
        )

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.applyNativeScrollEdges()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = AppPalette.secondaryText
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .appLanguageDidChange,
            object: nil
        )
    }

    @objc private func languageDidChange() {
        updateLocalizedTexts()
        tableView.reloadData()
    }

    private func updateLocalizedTexts() {
        title = L10n.tabPlaylists
        emptyLabel.text = AppLanguage.current.effectiveLanguageCode == "tr"
            ? "Henüz bir listen yok.\nSağ üstteki artıdan ekleyebilirsin."
            : "No playlists yet.\nTap plus icon to add one."
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        emptyLabel.isHidden = !model.playlists.playlists.isEmpty
        tableView.reloadData()
    }

    @objc private func addPlaylist() {
        present(
            UINavigationController(rootViewController: AddPlaylistViewController(model: model)),
            animated: true
        )
    }

    private func edit(_ playlist: Playlist) {
        present(
            UINavigationController(
                rootViewController: AddPlaylistViewController(model: model, editing: playlist)
            ),
            animated: true
        )
    }
}

extension PlaylistsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        model.playlists.playlists.count
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard !model.playlists.playlists.isEmpty else { return nil }
        return AppLanguage.current.effectiveLanguageCode == "tr"
            ? "Seçili listeyi değiştirmek için üstüne dokun. Düzenlemek ya da silmek için sola kaydır."
            : "Tap to select active playlist. Swipe left to edit or delete."
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let playlist = model.playlists.playlists[indexPath.row]
        let isTR = AppLanguage.current.effectiveLanguageCode == "tr"
        let needsSecret = model.playlists.needsSecret(for: playlist)

        var configuration = cell.defaultContentConfiguration()
        configuration.text = playlist.name
        var subtitle = "\(playlist.source.label) · \(playlist.subtitle)"
        if needsSecret {
            subtitle += isTR ? " · ⚠️ (Şifre Gerekli)" : " · ⚠️ (Password Required)"
        }
        if let expiresAt = playlist.expiresAt {
            let expiresPrefix = isTR ? "bitiş" : "expires"
            subtitle += " · \(expiresPrefix) \(expiresAt.formatted(date: .numeric, time: .omitted))"
        }
        configuration.secondaryText = subtitle
        if needsSecret {
            configuration.secondaryTextProperties.color = .systemOrange
        }
        cell.contentConfiguration = configuration
        cell.accessoryType = model.playlists.selected?.id == playlist.id ? .checkmark : .none
        cell.tintColor = AppPalette.accent
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let playlist = model.playlists.playlists[indexPath.row]

        if model.playlists.needsSecret(for: playlist) {
            promptForSecret(playlist: playlist)
            return
        }

        Task {
            await model.selectPlaylist(playlist)
            reload()
        }
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
            self.model.playlists.saveSecret(text, for: playlist)
            Task {
                await self.model.selectPlaylist(playlist)
                self.reload()
            }
        })
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        present(alert, animated: true)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let playlist = model.playlists.playlists[indexPath.row]
        let isTR = AppLanguage.current.effectiveLanguageCode == "tr"

        let delete = UIContextualAction(style: .destructive, title: isTR ? "Sil" : "Delete") { [weak self] _, _, done in
            guard let self else { return done(false) }
            Task {
                await self.model.removePlaylist(playlist)
                self.reload()
            }
            done(true)
        }
        let edit = UIContextualAction(style: .normal, title: isTR ? "Düzenle" : "Edit") { [weak self] _, _, done in
            self?.edit(playlist)
            done(true)
        }
        edit.backgroundColor = AppPalette.accent
        return UISwipeActionsConfiguration(actions: [delete, edit])
    }
}
