import UIKit

/// Canlı yayın rehberi: kanallar numara sırasına göre, her satırda o an
/// yayında olan ve sıradaki program.
///
/// Yayın akışı kanal başına ayrı bir ağ isteği (`get_short_epg`). Binlerce
/// kanallı listelerde hepsini çekmek mümkün değil, bu yüzden akış yalnızca
/// ekranda görünen satırlar için isteniyor ve `ContentLibrary` içinde kısa
/// ömürlü önbellekte tutuluyor.
final class GuideViewController: UIViewController {
    private let model: AppModel
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    private var channels: [MediaItem] = []
    /// Uçuşta olan istekler; hücre yeniden kullanılınca iptal ediliyor.
    private var epgTasks: [MediaID: Task<Void, Never>] = [:]

    private var metrics: AppMetrics { AppMetrics.metrics(for: view.bounds.width) }

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = L10n.guide
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        navigationItem.setPrefersLargeTitle(false)

        tableView.backgroundColor = .clear
        #if os(iOS)
        tableView.separatorStyle = .none
        #endif
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 96
        tableView.register(GuideChannelCell.self, forCellReuseIdentifier: GuideChannelCell.reuseID)
        tableView.applyNativeScrollEdges()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        emptyLabel.text = L10n.noChannels
        emptyLabel.textColor = AppPalette.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            // İçerik navigation bar'ın ardından geçiyor; girintiyi
            // `contentInsetAdjustmentBehavior` varsayılanı veriyor.
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(reload), name: .contentLibraryDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageDidChange), name: .appLanguageDidChange, object: nil
        )

        reload()
    }

    deinit {
        epgTasks.values.forEach { $0.cancel() }
    }

    @objc private func languageDidChange() {
        title = L10n.guide
        emptyLabel.text = L10n.noChannels
        tableView.reloadData()
    }

    @objc private func reload() {
        // IPTV kullanıcısının beklediği sıra kanal numarası; numarası
        // olmayanlar alfabetik olarak sona geliyor.
        channels = model.library.items(kind: .live, categoryID: nil).sorted { first, second in
            switch (first.channelNumber, second.channelNumber) {
            case let (lhs?, rhs?): lhs < rhs
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
            }
        }
        emptyLabel.isHidden = !channels.isEmpty
        tableView.reloadData()
    }
}

extension GuideViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        channels.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: GuideChannelCell.reuseID, for: indexPath
        ) as! GuideChannelCell
        cell.configure(item: channels[indexPath.row], metrics: metrics)
        return cell
    }

    /// Yayın akışı ancak satır ekrana girdiğinde isteniyor.
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let cell = cell as? GuideChannelCell, indexPath.row < channels.count else { return }
        let channel = channels[indexPath.row]
        guard epgTasks[channel.id] == nil else { return }

        let metrics = self.metrics
        epgTasks[channel.id] = Task { [weak self] in
            guard let self else { return }
            let entries = await model.library.epg(for: channel)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.epgTasks[channel.id] = nil
                // Hücre bu arada başka kanala geçmiş olabilir.
                guard let current = self.tableView.indexPath(for: cell),
                      current.row < self.channels.count,
                      self.channels[current.row].id == channel.id
                else { return }
                cell.setPrograms(entries, metrics: metrics)
            }
        }
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row < channels.count else { return }
        let id = channels[indexPath.row].id
        epgTasks[id]?.cancel()
        epgTasks[id] = nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let channel = channels[indexPath.row]
        Task { await model.play(channel) }
    }
}
