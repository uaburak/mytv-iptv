import UIKit

/// "Listem" kanallarını düzenleme ekranı: kanal ekleme, çıkarma ve sıralama.
///
/// İki kip var ve ikisi de aynı tabloda: listedeki kanallar (sıralanabilir) ve
/// tüm kanallar (eklenip çıkarılabilir). Kip seçimi uygulamanın her yerindeki
/// çiplerle aynı — segment denetimi yerine `appChip`, böylece tvOS'ta da
/// okunur boyda ve odaklanabilir duruyor.
@MainActor
final class PlayerListEditorViewController: UIViewController {
    private enum Mode {
        case myList
        case allChannels
    }

    private let model: AppModel
    private var favoriteIDs: [MediaID] = []
    private var allChannels: [MediaItem] = []
    private var filteredChannels: [MediaItem] = []
    private var mode: Mode = .myList
    private var query = ""

    private let myListButton = UIButton(type: .system)
    private let allChannelsButton = UIButton(type: .system)
    /// `UISearchTextField` yalnızca iOS'ta var; iki platformda da aynı görünen
    /// düz bir metin alanı kullanılıyor. tvOS'ta alan odaklanınca sistemin tam
    /// ekran klavyesi açılıyor.
    private let searchField = UITextField()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let doneButton = UIButton(configuration: .appProminent(size: .regular))
    private var emptyState: EmptyStateView!

    var onSave: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        self.favoriteIDs = model.activity.favoriteIDs
        self.allChannels = model.library.liveChannels()
        super.init(nibName: nil, bundle: nil)
        // Listede kanal yoksa açılışta yapılacak tek iş kanal eklemek.
        self.mode = favoriteIDs.isEmpty ? .allChannels : .myList
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        reloadRows()
    }

    // MARK: - Kurulum

    private func setupUI() {
        title = L10n.manageMyList
        view.backgroundColor = AppPalette.background

        // tvOS'ta navigasyon çubuğuna düğme koymak yerine ekranın kendi
        // "Bitti" düğmesi var: kumandayla oraya odaklanmak, çubuğa çıkmaktan
        // daha kısa bir yol.
        #if os(iOS)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.done, style: .done, target: self, action: #selector(doneTapped)
        )
        #endif

        configureModeButton(myListButton, title: L10n.inMyList, mode: .myList)
        configureModeButton(allChannelsButton, title: L10n.allChannels, mode: .allChannels)

        searchField.placeholder = L10n.searchPlaceholder
        searchField.textColor = AppPalette.primaryText
        searchField.tintColor = AppPalette.accent
        #if os(iOS)
        searchField.clearButtonMode = .whileEditing
        #endif
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.borderStyle = .roundedRect
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = PlayerListEditorCell.estimatedHeight
        tableView.applyNativeScrollEdges()
        #if os(iOS)
        tableView.separatorStyle = .none
        tableView.dragInteractionEnabled = true
        // Sıralama tutamaçları yalnızca düzenleme kipinde görünüyor; ekran
        // zaten baştan sona düzenleme ekranı.
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = true
        #endif
        tableView.register(PlayerListEditorCell.self, forCellReuseIdentifier: PlayerListEditorCell.reuseID)

        let modeStack = UIStackView(arrangedSubviews: [myListButton, allChannelsButton, UIView()])
        modeStack.axis = .horizontal
        modeStack.spacing = 10
        modeStack.alignment = .center

        let topStack = UIStackView(arrangedSubviews: [modeStack, searchField])
        topStack.axis = .vertical
        topStack.spacing = 12
        topStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topStack)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        emptyState = EmptyStateView.installed(in: view)

        // Koşullu kısıtlar diziye `#if` ile yazılamıyor (dizi elemanı bir
        // ifade, derleyici yönergesi değil); platforma özel olanlar sonradan
        // ekleniyor.
        var constraints: [NSLayoutConstraint] = [
            topStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            topStack.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20
            ),

            tableView.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]

        #if os(tvOS)
        doneButton.configuration?.title = L10n.done
        doneButton.addAction(
            UIAction { [weak self] _ in self?.doneTapped() }, for: .primaryActionTriggered
        )
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(doneButton)

        constraints += [
            doneButton.centerYAnchor.constraint(equalTo: modeStack.centerYAnchor),
            doneButton.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20
            ),
            topStack.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -16),
        ]
        #else
        constraints.append(
            topStack.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20
            )
        )
        #endif

        NSLayoutConstraint.activate(constraints)
    }

    private func configureModeButton(_ button: UIButton, title: String, mode: Mode) {
        button.addSpringPressFeedback(scale: 0.93)
        button.addAction(UIAction { [weak self] _ in
            guard let self, self.mode != mode else { return }
            self.mode = mode
            self.applyModeStyles()
            self.reloadRows()
        }, for: .primaryActionTriggered)
        var configuration = UIButton.Configuration.appChip(isSelected: self.mode == mode)
        configuration.title = title
        button.configuration = configuration
    }

    private func applyModeStyles() {
        for (button, buttonMode) in [(myListButton, Mode.myList), (allChannelsButton, .allChannels)] {
            let title = button.configuration?.title
            button.configuration = .appChip(isSelected: mode == buttonMode)
            button.configuration?.title = title
        }
    }

    // MARK: - Veri

    /// Ekranda görünen satırlar. "Listemdeki kanallar" kipinde sıra
    /// kullanıcının kendi sırası; arama yazıldığında her iki kipte de tüm
    /// kanallar taranıyor — aradığı kanalı eklemek isteyen kullanıcı önce
    /// sekme değiştirmek zorunda kalmıyor.
    private var rows: [MediaItem] {
        if !query.isEmpty { return filteredChannels }
        switch mode {
        case .myList: return favoriteIDs.compactMap { model.library.item(for: $0) }
        case .allChannels: return allChannels
        }
    }

    private func reloadRows() {
        tableView.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        guard rows.isEmpty else {
            emptyState.isHidden = true
            return
        }
        emptyState.isHidden = false
        if !query.isEmpty {
            emptyState.configure(
                symbol: "magnifyingglass",
                title: L10n.noSearchResults,
                message: nil
            )
        } else if mode == .myList {
            emptyState.configure(
                symbol: "list.star",
                title: L10n.emptyMyList,
                message: L10n.emptyMyListSubtitle,
                actionTitle: L10n.allChannels
            ) { [weak self] in
                guard let self else { return }
                mode = .allChannels
                applyModeStyles()
                reloadRows()
            }
        } else {
            emptyState.configure(symbol: "tv.slash", title: L10n.noChannels, message: nil)
        }
    }

    @objc private func searchChanged() {
        query = (searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        filteredChannels = query.isEmpty
            ? []
            : allChannels.filter { $0.title.lowercased().contains(query) }
        reloadRows()
    }

    private func toggle(_ channel: MediaItem) {
        if let index = favoriteIDs.firstIndex(of: channel.id) {
            favoriteIDs.remove(at: index)
        } else {
            favoriteIDs.append(channel.id)
        }
        Haptics.impact(.light)
        reloadRows()
    }

    @objc private func doneTapped() {
        model.activity.setFavorites(favoriteIDs)
        onSave?()
        dismiss(animated: true)
    }
}

extension PlayerListEditorViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: PlayerListEditorCell.reuseID, for: indexPath
        ) as! PlayerListEditorCell
        let channel = rows[indexPath.row]
        cell.configure(
            channel: channel,
            isInList: favoriteIDs.contains(channel.id),
            metrics: AppMetrics.metrics(for: view.bounds.width)
        )
        return cell
    }

    /// Satıra basmak kanalı listeye alıyor ya da çıkarıyor. Ayrı bir düğme
    /// yok: tvOS'ta hücrenin içindeki düğme odağı hücreden çalıyor ve satır
    /// tepkisiz görünüyordu.
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        toggle(rows[indexPath.row])
    }

    /// Sıralama yalnızca kendi listesinde ve arama yokken anlamlı.
    private var canReorder: Bool { mode == .myList && query.isEmpty }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        canReorder
    }

    func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard canReorder else { return }
        let moved = favoriteIDs.remove(at: sourceIndexPath.row)
        favoriteIDs.insert(moved, at: destinationIndexPath.row)
    }

    func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt indexPath: IndexPath
    ) -> UITableViewCell.EditingStyle {
        canReorder ? .delete : .none
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete, canReorder else { return }
        favoriteIDs.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        updateEmptyState()
    }
}

/// Düzenleme satırı: kanal logosu, adı, kategorisi ve listede olup olmadığı.
///
/// Görünüm rehberdeki kanal satırıyla aynı dili konuşuyor — aynı logo oranı,
/// aynı başlık/alt satır puntoları ve aynı seçim zemini.
final class PlayerListEditorCell: UITableViewCell {
    static let reuseID = "PlayerListEditorCell"
    #if os(tvOS)
    static let estimatedHeight: CGFloat = 110
    private static let logoWidth: CGFloat = 112
    #else
    static let estimatedHeight: CGFloat = 64
    private static let logoWidth: CGFloat = 60
    #endif

    private let logo = RemoteImageView()
    private let titleLabel = UILabel()
    private let categoryLabel = UILabel()
    private let stateIcon = UIImageView()
    private let separator = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        backgroundColor = .clear
        let selectedBackground = UIView()
        selectedBackground.backgroundColor = AppPalette.elevated
        selectedBackgroundView = selectedBackground

        logo.imageContentMode = .scaleAspectFit
        logo.showsPlaceholderBackground = false
        logo.showsInitials = false
        logo.backgroundColor = .clear
        logo.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.textColor = AppPalette.primaryText
        categoryLabel.textColor = AppPalette.secondaryText

        stateIcon.contentMode = .center
        stateIcon.translatesAutoresizingMaskIntoConstraints = false
        stateIcon.setContentHuggingPriority(.required, for: .horizontal)

        separator.backgroundColor = AppPalette.separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let texts = UIStackView(arrangedSubviews: [titleLabel, categoryLabel])
        texts.axis = .vertical
        texts.spacing = 2
        texts.translatesAutoresizingMaskIntoConstraints = false

        [logo, texts, stateIcon, separator].forEach(contentView.addSubview)

        // Kendi kendine boyutlanan hücrede dikey zincirin bir halkası zorunlu
        // önceliğin altında olmalı; aksi hâlde tablonun yuvarladığı satır
        // yüksekliğiyle çakışıp her hücrede kısıt uyarısı basıyor.
        let bottom = logo.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        bottom.priority = .init(999)
        let logoHeight = logo.heightAnchor.constraint(equalToConstant: Self.logoWidth * 9 / 16)
        logoHeight.priority = .init(999)

        NSLayoutConstraint.activate([
            logo.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            logo.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            bottom,
            logo.widthAnchor.constraint(equalToConstant: Self.logoWidth),
            logoHeight,

            texts.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 16),
            texts.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: stateIcon.leadingAnchor, constant: -12),

            stateIcon.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stateIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: texts.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        logo.prepareForReuse()
    }

    func configure(channel: MediaItem, isInList: Bool, metrics: AppMetrics) {
        titleLabel.font = metrics.listTitleFont
        categoryLabel.font = metrics.listSubtitleFont
        titleLabel.text = channel.title
        categoryLabel.text = channel.categoryName
        categoryLabel.isHidden = (channel.categoryName ?? "").isEmpty
        logo.configure(url: channel.posterURL, title: channel.title, displayWidth: Self.logoWidth)

        stateIcon.image = UIImage(systemName: isInList ? "checkmark.circle.fill" : "plus.circle")
        stateIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: metrics.listTitleFont.pointSize, weight: .semibold
        )
        stateIcon.tintColor = isInList ? AppPalette.accent : AppPalette.secondaryText

        accessibilityLabel = channel.title
        accessibilityValue = isInList ? L10n.inMyList : nil
        accessibilityHint = isInList ? L10n.removeFromList : L10n.addToList
    }
}
