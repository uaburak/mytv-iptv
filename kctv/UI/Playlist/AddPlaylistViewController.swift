import UIKit

/// Xtream ya da M3U kaynağı ekleme formu.
/// Kaydetmeden önce bağlantı doğrulanır; böylece kullanıcı yanlış bilgiyle
/// boş bir anasayfaya düşmez.
final class AddPlaylistViewController: UIViewController {
    private enum Mode: Int {
        case xtream, m3u
    }

    private let model: AppModel
    /// Dolu geldiğinde form düzenleme modunda açılır.
    private let editingPlaylist: Playlist?
    private var mode: Mode = .xtream

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let modePicker = UISegmentedControl(items: ["Xtream Codes", "M3U / M3U8"])

    private let nameField = LabeledTextField(label: L10n.playlistName, placeholder: L10n.playlistNamePlaceholder)
    private let hostField = LabeledTextField(label: L10n.serverURL, placeholder: "http://example.com:8080", isURL: true)
    private let usernameField = LabeledTextField(label: L10n.username, placeholder: L10n.usernamePlaceholder)
    private let passwordField = LabeledTextField(label: L10n.password, placeholder: "", isSecure: true)
    private let urlField = LabeledTextField(label: L10n.m3uURLLabel, placeholder: "http://.../get.php?...", isURL: true)

    private let statusLabel = UILabel()
    private let connectButton = UIButton(configuration: .filled())
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(model: AppModel, editing playlist: Playlist? = nil) {
        self.model = model
        self.editingPlaylist = playlist
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        title = editingPlaylist == nil ? L10n.addPlaylistTitle : L10n.editPlaylistTitle
        // `.close` sistem öğesi tvOS'ta yok; orada Menu tuşu kapatıyor.
        #if os(iOS)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        #endif
        buildLayout()
        prefillIfEditing()
        updateFieldVisibility()
    }

    /// Düzenleme modunda mevcut değerleri forma yazar. Şifre Keychain'den okunur.
    private func prefillIfEditing() {
        guard let playlist = editingPlaylist else { return }
        nameField.setText(playlist.name)

        switch playlist.source {
        case let .xtream(host, username):
            mode = .xtream
            modePicker.selectedSegmentIndex = 0
            hostField.setText(host)
            usernameField.setText(username)
            passwordField.setText(model.playlists.secret(for: playlist) ?? "")
        case let .m3u(url):
            mode = .m3u
            modePicker.selectedSegmentIndex = 1
            urlField.setText(url.absoluteString)
        }
        // Kaynak türü sonradan değiştirilmesin; ayrı liste eklemek daha net.
        modePicker.isEnabled = false
        connectButton.configuration?.title = L10n.save
    }

    private func buildLayout() {
        modePicker.selectedSegmentIndex = 0
        modePicker.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true

        var configuration = UIButton.Configuration.filled()
        configuration.title = editingPlaylist == nil ? L10n.connectAndSave : L10n.save
        configuration.cornerStyle = .capsule
        connectButton.configuration = configuration
        connectButton.addTarget(self, action: #selector(validateAndSave), for: .primaryActionTriggered)
        connectButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        let note = UILabel()
        note.text = L10n.keychainNote
        note.font = .systemFont(ofSize: 13)
        note.textColor = AppPalette.secondaryText
        note.numberOfLines = 0

        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        [modePicker, nameField, hostField, usernameField, passwordField, urlField, statusLabel, connectButton, note]
            .forEach(stack.addArrangedSubview)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.applyNativeScrollEdges()
        scrollView.addSubview(stack)
        view.addSubview(scrollView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            // Güvenli alana değil ekranın tepesine: form navigation bar'ın
            // ardından geçip bulanıklaşıyor, sert bir çizgide kesilmiyor.
            // Dinlenme konumundaki boşluğu `contentInsetAdjustmentBehavior`
            // varsayılanı veriyor.
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),

            spinner.centerXAnchor.constraint(equalTo: connectButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: connectButton.centerYAnchor),
        ])
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func modeChanged() {
        mode = Mode(rawValue: modePicker.selectedSegmentIndex) ?? .xtream
        updateFieldVisibility()
    }

    private func updateFieldVisibility() {
        let isXtream = mode == .xtream
        [hostField, usernameField, passwordField].forEach { $0.isHidden = !isXtream }
        urlField.isHidden = isXtream
    }

    @objc private func validateAndSave() {
        Task { await performValidation() }
    }

    private func performValidation() async {
        setBusy(true)
        defer { setBusy(false) }

        let playlist: Playlist
        let secret: String?
        let isTR = AppLanguage.current.effectiveLanguageCode == "tr"

        switch mode {
        case .xtream:
            let host = hostField.text.trimmed
            let username = usernameField.text.trimmed
            guard !host.isEmpty, !username.isEmpty, !passwordField.text.isEmpty else {
                show(error: isTR ? "Sunucu adresi, kullanıcı adı ve şifre zorunlu." : "Server address, username and password are required.")
                return
            }
            playlist = Playlist(
                name: nameField.text.trimmed.nilIfEmpty ?? username,
                source: .xtream(host: host, username: username)
            )
            secret = passwordField.text
        case .m3u:
            guard let url = URL(string: urlField.text.trimmed), url.scheme != nil else {
                show(error: isTR ? "Bağlantı geçersiz." : "Invalid URL.")
                return
            }
            playlist = Playlist(
                name: nameField.text.trimmed.nilIfEmpty ?? (url.host ?? (isTR ? "M3U Listesi" : "M3U Playlist")),
                source: .m3u(url: url)
            )
            secret = nil
        }

        do {
            let provider = try ContentLibrary.makeProvider(for: playlist, secret: secret)
            let account = try await provider.validate()

            var stored = playlist
            // Düzenlemede kimliği koru; yoksa yeni liste olarak eklenir.
            if let editingPlaylist {
                stored.id = editingPlaylist.id
                stored.createdAt = editingPlaylist.createdAt
            }
            stored.expiresAt = account.expiresAt
            stored.lastSyncedAt = .now
            await model.addPlaylist(stored, secret: secret)
            dismiss(animated: true)
        } catch {
            show(error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func setBusy(_ isBusy: Bool) {
        let idleTitle = editingPlaylist == nil ? L10n.connectAndSave : L10n.save
        connectButton.configuration?.title = isBusy ? "" : idleTitle
        connectButton.isEnabled = !isBusy
        isBusy ? spinner.startAnimating() : spinner.stopAnimating()
    }

    private func show(error: String) {
        statusLabel.text = error
        statusLabel.textColor = .systemOrange
        statusLabel.isHidden = false
    }
}

/// Başlıklı metin alanı — formda tekrar eden düzen.
final class LabeledTextField: UIStackView {
    private let titleLabel = UILabel()
    private let field = UITextField()

    var text: String { field.text ?? "" }

    func setText(_ value: String) { field.text = value }

    init(label: String, placeholder: String, isURL: Bool = false, isSecure: Bool = false) {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 6

        titleLabel.text = label
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.textColor = AppPalette.secondaryText

        field.placeholder = placeholder
        field.textColor = .white
        field.backgroundColor = AppPalette.elevated
        field.layer.cornerRadius = 10
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.isSecureTextEntry = isSecure
        field.keyboardType = isURL ? .URL : .default
        field.heightAnchor.constraint(equalToConstant: 46).isActive = true
        // İçerideki metni kenardan ayır.
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always

        addArrangedSubview(titleLabel)
        addArrangedSubview(field)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
