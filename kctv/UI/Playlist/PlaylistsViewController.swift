import UIKit

/// Liste yönetimi: ekleme, seçme, düzenleme ve silme.
final class PlaylistsViewController: UIViewController {
    private let model: AppModel
    // `insetGrouped` tvOS'ta yok; orada düz gruplu stil kullanılıyor.
    #if os(iOS)
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    #else
    private let tableView = UITableView(frame: .zero, style: .grouped)
    #endif
    private var emptyState: EmptyStateView!

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background

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
        #if os(tvOS)
        installLongPressActions()
        #endif

        emptyState = EmptyStateView.installed(in: view)
        // Metinler boş durum görünümü kurulduktan sonra: başlık ve boş durum
        // aynı yerden besleniyor.
        updateLocalizedTexts()

        NSLayoutConstraint.activate([
            // Güvenli alana değil ekranın tepesine: içerik navigation bar'ın
            // ardından geçip bulanıklaşıyor, sert bir çizgide kesilmiyor.
            // Dinlenme konumundaki boşluğu `contentInsetAdjustmentBehavior`
            // varsayılanı veriyor.
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
        // Boş ekran yalnızca durumu anlatmıyor, çözümü de sunuyor: kullanıcı
        // "sağ üstteki artı"yı aramak zorunda kalmadan listesini ekliyor.
        emptyState?.configure(
            symbol: "list.bullet.rectangle",
            title: L10n.noPlaylistsTitle,
            message: L10n.noPlaylistsSubtitle,
            actionTitle: L10n.addPlaylist
        ) { [weak self] in
            self?.addPlaylist()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        emptyState.isHidden = !model.playlists.playlists.isEmpty
        tableView.reloadData()
    }

    // MARK: - tvOS satır eylemleri

    /// tvOS'ta satırı kaydırmak mümkün değil; düzenleme ve silme odaklı satıra
    /// uzun basınca açılan eylem listesinden yapılıyor.
    #if os(tvOS)
    private func installLongPressActions() {
        let recognizer = UILongPressGestureRecognizer(
            target: self, action: #selector(handleLongPress)
        )
        tableView.addGestureRecognizer(recognizer)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let indexPath = tableView.indexPathForSelectedRow
                  ?? tableView.indexPathsForVisibleRows?.first(where: {
                      tableView.cellForRow(at: $0)?.isFocused == true
                  }),
              indexPath.row < model.playlists.playlists.count
        else { return }

        let playlist = model.playlists.playlists[indexPath.row]

        let sheet = UIAlertController(title: playlist.name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L10n.edit, style: .default) { [weak self] _ in
            guard let self else { return }
            edit(playlist)
        })
        sheet.addAction(UIAlertAction(title: L10n.delete, style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.model.removePlaylist(playlist)
                self.reload()
            }
        })
        sheet.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        present(sheet, animated: true)
    }
    #endif

    @objc private func addPlaylist() {
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
}

extension PlaylistsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        model.playlists.playlists.count
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard !model.playlists.playlists.isEmpty else { return nil }
        // Yönerge platforma göre değişiyor: tvOS'ta kaydırma diye bir
        // etkileşim yok, düzenleme ve silme odaklı satıra uzun basınca açılıyor.
        let isTurkish = AppLanguage.current.effectiveLanguageCode == "tr"
        #if os(tvOS)
        return isTurkish
            ? "Seçili listeyi değiştirmek için üstüne bas. Düzenlemek ya da silmek için basılı tut."
            : "Press to select the active playlist. Press and hold to edit or delete."
        #else
        return isTurkish
            ? "Seçili listeyi değiştirmek için üstüne dokun. Düzenlemek ya da silmek için sola kaydır."
            : "Tap to select active playlist. Swipe left to edit or delete."
        #endif
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

    /// Kaydırmalı satır eylemleri tvOS'ta yok — orada kumandayla kaydırma diye
    /// bir etkileşim olmadığı için API'nin tamamı kullanılamıyor. tvOS'ta aynı
    /// işi odaklı satıra uzun basmak açıyor (`playlistActions`).
    #if os(iOS)
    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let playlist = model.playlists.playlists[indexPath.row]

        let delete = UIContextualAction(style: .destructive, title: L10n.delete) { [weak self] _, _, done in
            guard let self else { return done(false) }
            Task {
                await self.model.removePlaylist(playlist)
                self.reload()
            }
            done(true)
        }
        let edit = UIContextualAction(style: .normal, title: L10n.edit) { [weak self] _, _, done in
            self?.edit(playlist)
            done(true)
        }
        edit.backgroundColor = AppPalette.accent
        return UISwipeActionsConfiguration(actions: [delete, edit])
    }
    #endif
}
