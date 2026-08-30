import UIKit

/// Canlı yayında oynatıcının kanal / kategori çekmecesi.
///
/// Ekranın tam 4'te 1'ini kaplar (1/4 genişlik).
/// Üstte "Listem" ve "Kategoriler" sekmeleri yer alır.
/// "Listem" butonuna basılı tutulduğunda veya boş durumdaki butona basıldığında liste düzenleme ekranı açılır.
/// Kategori içine girildiğinde header'da yazı görünmez, liste tam yükseklikte akar.
/// Seçilen/odaklanan öğelerin metinleri siyah olur.
@MainActor
final class PlayerChannelsController: NSObject {
    #if os(tvOS)
    private static let rowHeight: CGFloat = 86
    private static let categoryRowHeight: CGFloat = 78
    private static let topPadding: CGFloat = 36
    #else
    private static let rowHeight: CGFloat = 64
    private static let categoryRowHeight: CGFloat = 54
    private static let topPadding: CGFloat = 16
    #endif

    enum Tab {
        case myList
        case categories
    }

    enum ViewMode {
        case categories
        case channels(ChannelSection)
        case myList
    }

    /// Bir kategori ve içindeki kanallar.
    struct ChannelSection {
        let title: String
        let categoryID: String?
        let channels: [MediaItem]
    }

    /// Oynatıcı bunları kendi yerleşimine koyuyor: çip denetim satırının soluna,
    /// çekmece ekranın sol kenarına.
    let chip = UIButton()
    let drawer = UIView()

    /// Çipin görünümünü oynatıcı veriyor; seçili olup olmadığı geçiliyor.
    var styleChip: ((UIButton, Bool) -> Void)?
    /// Çekmece açıldı/kapandı.
    var onVisibilityChanged: ((Bool) -> Void)?
    /// Kanal seçildi; oynatıcı aynı ekranda katman değiştiriyor.
    var onSelect: ((MediaItem) -> Void)?
    /// Liste düzenleme ekranını açma isteği.
    var onOpenListEditor: (() -> Void)?

    private(set) var isOpen = false
    private(set) var activeTab: Tab = .categories
    private(set) var viewMode: ViewMode = .categories

    /// Tek kanallı listede geçilecek bir yer yok; çip hiç görünmüyor.
    var hasChannels: Bool { channelCount > 1 }

    private let surface = UIVisualEffectView(effect: nil)
    private let headerContainer = UIView()
    private let tabsStack = UIStackView()
    private let myListButton = UIButton()
    private let categoriesButton = UIButton()

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyListView = PlayerEmptyListPlaceholderView()
    private let edge = UIView()

    private var tableViewTopWithHeader: NSLayoutConstraint!
    private var tableViewTopWithoutHeader: NSLayoutConstraint!

    private weak var model: AppModel?
    private var sections: [ChannelSection] = []
    private var channelCount = 0
    private var currentChannelID: MediaID?
    private var selectedCategory: ChannelSection?

    /// Kullanıcının "Listem"deki kanalları
    private var myListChannels: [MediaItem] = []

    /// Gelen yayın akışından yalnızca o an yayında olan programın adı tutuluyor.
    private var programs: [MediaID: String] = [:]
    /// Uçuşta olan istekler; satır ekrandan çıkınca iptal ediliyor.
    private var epgTasks: [MediaID: Task<Void, Never>] = [:]

    override init() {
        super.init()
        buildChip()
        buildDrawer()
    }

    deinit {
        epgTasks.values.forEach { $0.cancel() }
    }

    private func buildChip() {
        chip.isHidden = true
        chip.addSpringPressFeedback()
        chip.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .primaryActionTriggered)
    }

    private func buildDrawer() {
        drawer.isHidden = true

        #if os(iOS)
        surface.effect = UIBlurEffect(style: .systemThinMaterialDark)
        #else
        surface.effect = UIBlurEffect(style: .dark)
        #endif
        surface.clipsToBounds = true
        surface.translatesAutoresizingMaskIntoConstraints = false
        drawer.addSubview(surface)

        edge.backgroundColor = AppPalette.separator

        buildHeader()
        buildTableView()

        emptyListView.onEditTapped = { [weak self] in
            self?.onOpenListEditor?()
        }

        for subview in [headerContainer, tableView, emptyListView, edge] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            surface.contentView.addSubview(subview)
        }

        tableViewTopWithHeader = tableView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 14)
        tableViewTopWithoutHeader = tableView.topAnchor.constraint(equalTo: surface.topAnchor, constant: Self.topPadding)

        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: drawer.topAnchor),
            surface.bottomAnchor.constraint(equalTo: drawer.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: drawer.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: drawer.trailingAnchor),

            headerContainer.topAnchor.constraint(equalTo: surface.topAnchor, constant: Self.topPadding),
            headerContainer.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20),
            headerContainer.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),

            tableViewTopWithHeader,
            tableView.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20),
            tableView.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),
            tableView.bottomAnchor.constraint(equalTo: surface.bottomAnchor),

            emptyListView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 14),
            emptyListView.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20),
            emptyListView.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),
            emptyListView.bottomAnchor.constraint(equalTo: surface.bottomAnchor),

            edge.topAnchor.constraint(equalTo: surface.topAnchor),
            edge.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            edge.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            edge.widthAnchor.constraint(equalToConstant: 1),
        ])

        updateTabButtons()
    }

    private func buildHeader() {
        myListButton.addSpringPressFeedback()
        myListButton.addAction(UIAction { [weak self] _ in self?.selectTab(.myList) }, for: .primaryActionTriggered)

        // Listem butonuna uzun basınca düzenleme ekranı açılsın
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressMyList(_:)))
        longPress.minimumPressDuration = 0.5
        myListButton.addGestureRecognizer(longPress)

        categoriesButton.addSpringPressFeedback()
        categoriesButton.addAction(UIAction { [weak self] _ in self?.selectTab(.categories) }, for: .primaryActionTriggered)

        tabsStack.axis = .horizontal
        tabsStack.spacing = 10
        tabsStack.distribution = .fillEqually
        tabsStack.addArrangedSubview(myListButton)
        tabsStack.addArrangedSubview(categoriesButton)
        tabsStack.translatesAutoresizingMaskIntoConstraints = false

        headerContainer.addSubview(tabsStack)

        NSLayoutConstraint.activate([
            tabsStack.topAnchor.constraint(equalTo: headerContainer.topAnchor),
            tabsStack.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            tabsStack.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            tabsStack.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
        ])
    }

    @objc private func handleLongPressMyList(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        onOpenListEditor?()
    }

    private func buildTableView() {
        tableView.backgroundColor = .clear
        #if os(iOS)
        tableView.separatorStyle = .none
        tableView.indicatorStyle = .white
        #endif
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = Self.rowHeight
        tableView.sectionHeaderTopPadding = 0
        tableView.register(PlayerChannelCell.self, forCellReuseIdentifier: PlayerChannelCell.reuseID)
        tableView.register(PlayerCategoryCell.self, forCellReuseIdentifier: PlayerCategoryCell.reuseID)

        tableView.directionalLayoutMargins = .zero
        tableView.layoutMargins = .zero
        tableView.preservesSuperviewLayoutMargins = false
        tableView.cellLayoutMarginsFollowReadableWidth = false
        tableView.insetsContentViewsToSafeArea = false
        tableView.insetsLayoutMarginsFromSafeArea = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0)
    }

    private func updateTabButtons() {
        #if os(tvOS)
        let fontSize: CGFloat = 22
        let horizontalInset: CGFloat = 26
        let verticalInset: CGFloat = 12
        #else
        let fontSize: CGFloat = 16
        let horizontalInset: CGFloat = 18
        let verticalInset: CGFloat = 10
        #endif

        var myListConfig = UIButton.Configuration.appChip(
            isSelected: activeTab == .myList,
            horizontalInset: horizontalInset,
            verticalInset: verticalInset,
            fontSize: fontSize
        )
        myListConfig.title = L10n.myList
        myListButton.configuration = myListConfig

        var catConfig = UIButton.Configuration.appChip(
            isSelected: activeTab == .categories,
            horizontalInset: horizontalInset,
            verticalInset: verticalInset,
            fontSize: fontSize
        )
        catConfig.title = L10n.categories
        categoriesButton.configuration = catConfig
    }

    // MARK: - Veri

    func configure(context: PlaybackContext, model: AppModel) {
        close()
        self.model = model
        currentChannelID = AppModel.decode(contextID: context.id)?.mediaID

        guard context.isLive else {
            sections = []
            channelCount = 0
            chip.isHidden = true
            return
        }
        if sections.isEmpty {
            sections = Self.buildSections(from: model.library)
            channelCount = sections.reduce(0) { $0 + $1.channels.count }
        }
        chip.isHidden = !hasChannels
        styleChip?(chip, false)

        loadMyListChannels()

        if let currentChannelID, let currentSection = sections.first(where: { sec in
            sec.channels.contains { $0.id == currentChannelID }
        }) {
            selectedCategory = currentSection
        } else {
            selectedCategory = sections.first
        }

        viewMode = .categories
        activeTab = .categories
        refreshView()
    }

    private func loadMyListChannels() {
        guard let model else { return }
        myListChannels = model.activity.favoriteIDs.compactMap { model.library.item(for: $0) }
    }

    func refreshListemData() {
        loadMyListChannels()
        if activeTab == .myList {
            refreshView(animated: true)
        }
    }

    private static func buildSections(from library: ContentLibrary) -> [ChannelSection] {
        var grouped: [String: [MediaItem]] = [:]
        var seen: [String] = []
        for channel in library.liveChannels() {
            let key = channel.categoryID ?? ""
            if grouped[key] == nil { seen.append(key) }
            grouped[key, default: []].append(channel)
        }

        let categories = library.categories[.live] ?? []
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var placed: Set<String> = []
        let order = (categories.map(\.id) + seen).filter { key in
            grouped[key] != nil && placed.insert(key).inserted
        }

        return order.compactMap { key in
            guard let channels = grouped[key], !channels.isEmpty else { return nil }
            let title = names[key] ?? channels[0].categoryName ?? L10n.otherCategory
            return ChannelSection(title: title, categoryID: key, channels: channels)
        }
    }

    // MARK: - Navigasyon & Durum Değişimi

    func selectTab(_ tab: Tab) {
        activeTab = tab
        if tab == .myList {
            loadMyListChannels()
            viewMode = .myList
        } else {
            viewMode = .categories
        }
        refreshView(animated: true)
    }

    func selectCategory(_ category: ChannelSection) {
        selectedCategory = category
        viewMode = .channels(category)
        refreshView(animated: true)
    }

    @objc func goBackToCategories() {
        viewMode = .categories
        activeTab = .categories
        refreshView(animated: true)
    }

    /// Geri tuşuna basıldığında çağrılır. Kanallar içindeyse kategorilere döner ve true döner.
    @discardableResult
    func handleBack() -> Bool {
        if case .channels = viewMode {
            goBackToCategories()
            return true
        }
        return false
    }

    private func refreshView(animated: Bool = false) {
        updateTabButtons()

        switch viewMode {
        case .categories:
            headerContainer.isHidden = false
            tableViewTopWithoutHeader.isActive = false
            tableViewTopWithHeader.isActive = true
            emptyListView.isHidden = true
            tableView.isHidden = false
            tableView.rowHeight = Self.categoryRowHeight
            if animated {
                UIView.transition(with: tableView, duration: 0.22, options: .transitionCrossDissolve) {
                    self.tableView.reloadData()
                }
            } else {
                tableView.reloadData()
            }

        case .channels(let section):
            // Kategori içine girildiğinde header'da hiçbir şey yazmasın (tamamen gizli)
            headerContainer.isHidden = true
            tableViewTopWithHeader.isActive = false
            tableViewTopWithoutHeader.isActive = true
            emptyListView.isHidden = true
            tableView.isHidden = false
            tableView.rowHeight = Self.rowHeight
            if animated {
                UIView.transition(with: tableView, duration: 0.22, options: .transitionCrossDissolve) {
                    self.tableView.reloadData()
                }
            } else {
                tableView.reloadData()
            }
            scrollToCurrentChannelIfNeeded()

        case .myList:
            headerContainer.isHidden = false
            tableViewTopWithoutHeader.isActive = false
            tableViewTopWithHeader.isActive = true
            if myListChannels.isEmpty {
                emptyListView.isHidden = false
                tableView.isHidden = true
            } else {
                emptyListView.isHidden = true
                tableView.isHidden = false
                tableView.rowHeight = Self.rowHeight
                if animated {
                    UIView.transition(with: tableView, duration: 0.22, options: .transitionCrossDissolve) {
                        self.tableView.reloadData()
                    }
                } else {
                    tableView.reloadData()
                }
            }
        }

        #if os(tvOS)
        drawer.setNeedsFocusUpdate()
        drawer.updateFocusIfNeeded()
        #endif
    }

    // MARK: - Açma / Kapama

    func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        guard !isOpen, hasChannels else { return }
        isOpen = true
        styleChip?(chip, true)

        // Yayın akarken "Kanallar"a basıldığında doğrudan oynayan kanalın kategorisine ve aktif kanala geç
        if let currentChannelID, let currentSection = sections.first(where: { sec in
            sec.channels.contains { $0.id == currentChannelID }
        }) {
            selectedCategory = currentSection
            viewMode = .channels(currentSection)
        }

        drawer.isHidden = false
        drawer.superview?.layoutIfNeeded()
        refreshView(animated: false)
        tableView.layoutIfNeeded()
        scrollToCurrentChannelIfNeeded()

        drawer.transform = CGAffineTransform(translationX: -hiddenOffset, y: 0)
        onVisibilityChanged?(true)
        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.2,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.drawer.transform = .identity
            self.drawer.superview?.layoutIfNeeded()
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        styleChip?(chip, false)
        onVisibilityChanged?(false)
        UIView.animate(
            withDuration: 0.26,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            self.drawer.transform = CGAffineTransform(translationX: -self.hiddenOffset, y: 0)
            self.drawer.superview?.layoutIfNeeded()
        } completion: { _ in
            guard !self.isOpen else { return }
            self.drawer.isHidden = true
            self.drawer.transform = .identity
        }
    }

    private var hiddenOffset: CGFloat {
        if let superview = drawer.superview, superview.bounds.width > 0 {
            return superview.bounds.width * 0.25
        }
        return drawer.bounds.width > 0 ? drawer.bounds.width : (UIScreen.main.bounds.width * 0.25)
    }

    private func scrollToCurrentChannelIfNeeded() {
        guard case .channels(let section) = viewMode, let currentChannelID else { return }
        if let row = section.channels.firstIndex(where: { $0.id == currentChannelID }) {
            tableView.layoutIfNeeded()
            tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: false)
        }
    }

    #if os(tvOS)
    var focusEnvironments: [UIFocusEnvironment] {
        if !tableView.isHidden {
            if case .channels(let section) = viewMode,
               let currentChannelID,
               let row = section.channels.firstIndex(where: { $0.id == currentChannelID }),
               let cell = tableView.cellForRow(at: IndexPath(row: row, section: 0)) {
                return [cell, tableView]
            }
            return [tableView]
        }
        return [categoriesButton]
    }
    #endif
}

extension PlayerChannelsController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch viewMode {
        case .categories:
            return sections.count
        case .channels(let categorySection):
            return categorySection.channels.count
        case .myList:
            return myListChannels.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch viewMode {
        case .categories:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: PlayerCategoryCell.reuseID, for: indexPath
            ) as! PlayerCategoryCell
            guard indexPath.row < sections.count else { return cell }
            let group = sections[indexPath.row]
            cell.configure(title: group.title, count: group.channels.count)
            return cell

        case .channels(let section):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: PlayerChannelCell.reuseID, for: indexPath
            ) as! PlayerChannelCell
            guard indexPath.row < section.channels.count else { return cell }
            let channel = section.channels[indexPath.row]
            cell.configure(
                channel: channel,
                program: programs[channel.id],
                isPlaying: channel.id == currentChannelID
            )
            return cell

        case .myList:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: PlayerChannelCell.reuseID, for: indexPath
            ) as! PlayerChannelCell
            guard indexPath.row < myListChannels.count else { return cell }
            let channel = myListChannels[indexPath.row]
            cell.configure(
                channel: channel,
                program: programs[channel.id],
                isPlaying: channel.id == currentChannelID
            )
            return cell
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let channel: MediaItem?
        switch viewMode {
        case .channels(let section):
            guard indexPath.row < section.channels.count else { return }
            channel = section.channels[indexPath.row]
        case .myList:
            guard indexPath.row < myListChannels.count else { return }
            channel = myListChannels[indexPath.row]
        default:
            return
        }

        guard let channel, let cell = cell as? PlayerChannelCell else { return }
        guard programs[channel.id] == nil, epgTasks[channel.id] == nil, let model else { return }

        epgTasks[channel.id] = Task { [weak self] in
            guard let self else { return }
            let entries = await model.library.epg(for: channel)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.epgTasks[channel.id] = nil
                let now = entries.first(where: \.isLive) ?? entries.first
                self.programs[channel.id] = now?.title ?? L10n.noProgramInfo
                guard let current = self.tableView.indexPath(for: cell) else { return }
                cell.setProgram(self.programs[channel.id])
            }
        }
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let id: MediaID?
        switch viewMode {
        case .channels(let section):
            guard indexPath.row < section.channels.count else { return }
            id = section.channels[indexPath.row].id
        case .myList:
            guard indexPath.row < myListChannels.count else { return }
            id = myListChannels[indexPath.row].id
        default:
            return
        }
        guard let id else { return }
        epgTasks[id]?.cancel()
        epgTasks[id] = nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch viewMode {
        case .categories:
            guard indexPath.row < sections.count else { return }
            selectCategory(sections[indexPath.row])

        case .channels(let section):
            guard indexPath.row < section.channels.count else { return }
            let channel = section.channels[indexPath.row]
            guard channel.id != currentChannelID else {
                close()
                return
            }
            close()
            onSelect?(channel)

        case .myList:
            guard indexPath.row < myListChannels.count else { return }
            let channel = myListChannels[indexPath.row]
            guard channel.id != currentChannelID else {
                close()
                return
            }
            close()
            onSelect?(channel)
        }
    }
}
