import KSPlayer
import UIKit

/// Oynatıcının alt sekmeleri: Bilgi ve Bölümler.
///
/// Çipleri oynatıcı yerleştiriyor — Bilgi solda simge olarak, Bölümler sağda
/// yazıyla — ve görünümlerini `styleChip` ile o veriyor; ölçüler yanlarındaki
/// simge butonlarıyla aynı hizada durmalı. Seçilen çipin paneli denetim
/// satırının altında açılıyor, çip yeniden seçilince kapanıyor.
///
/// Veri uygulamanın kendi katalogundan geliyor; yalnızca "Bölümler" iki
/// kaynaklı: dizide gerçek bölümler, filmde dosyanın kendi bölüm işaretleri
/// (`player.chapters`). İkisi de yoksa çip hiç görünmüyor.
@MainActor
final class PlayerTabsController {
    enum Tab: CaseIterable {
        case info
        case episodes

        var title: String {
            switch self {
            case .info: L10n.info
            case .episodes: L10n.episodes
            }
        }
    }

    /// Oynatıcı bunları kendi yerleşimine koyuyor. Çipler sabit: sekme
    /// listesi değişince yeniden kurulmuyor, yalnızca görünürlükleri
    /// değişiyor — tvOS'ta odak o an bir çipin üstündeyse kaybolmasın diye.
    let infoChip = UIButton()
    let episodesChip = UIButton()
    let panel = UIView()

    /// Çipin görünümünü oynatıcı veriyor: seçili/seçili değil ve hangi sekme
    /// olduğu geçiliyor.
    var styleChip: ((UIButton, Tab, Bool) -> Void)?

    /// Panel açıldı/kapandı. Oynatıcı transport bloğunu gizliyor ve
    /// kendiliğinden gizlenme sayacını durduruyor.
    var onPanelVisibilityChanged: ((Bool) -> Void)?
    /// Dosyanın bölüm işaretinden sarma.
    var onSeek: ((TimeInterval) -> Void)?
    /// "Baştan" ve "Sıradaki Bölüm".
    var onRestart: (() -> Void)?
    var onNextEpisode: (() -> Void)?
    /// Başka bir içeriğe geçildi; oynatıcı aynı ekranda katman değiştiriyor.
    var onPlay: ((PlaybackContext) -> Void)?

    /// Kart ölçüleri ekran genişliğinden geliyor; oynatıcı yerleşim turunda
    /// tazeliyor.
    var metrics: AppMetrics = .regular

    /// Sıradaki bölüm oynatıcıda çözülüyor; "Bilgi" paneli butonu ona göre
    /// gösteriyor.
    var hasNextEpisode = false {
        didSet {
            guard hasNextEpisode != oldValue, openTab == .info else { return }
            reopenPanel()
        }
    }

    /// Oynatılan an. Bölüm işareti kartındaki "İZLENİYOR" rozeti buna
    /// bakıyor; oynatıcı ilerledikçe tazeliyor.
    var currentTime: TimeInterval?

    private(set) var openTab: Tab?
    var isPanelOpen: Bool { openTab != nil }

    /// Bölüm işareti ve sırası. Sıra ada gerekiyor: dosyalarda işaretler
    /// çoğunlukla adsız geliyor ve "3. Bölüm" ancak indisten üretiliyor.
    private struct ChapterEntry {
        let index: Int
        let chapter: Chapter
    }

    private weak var model: AppModel?
    private var context: PlaybackContext?
    private var item: MediaItem?
    private var series: MediaItem?
    private var episodes: [Episode] = []
    private var currentEpisodeID: String?
    private var chapters: [Chapter] = []

    private var detailTask: Task<Void, Never>?
    private var openTask: Task<Void, Never>?

    init() {
        for tab in Tab.allCases {
            let button = button(for: tab)
            button.isHidden = true
            button.addSpringPressFeedback()
            button.addAction(UIAction { [weak self] _ in self?.toggle(tab) }, for: .primaryActionTriggered)
        }
        // Odaktaki kart kendi çerçevesinin dışına büyüyor; panel kırpmamalı.
        panel.clipsToBounds = false
        panel.isHidden = true
    }

    private func button(for tab: Tab) -> UIButton {
        switch tab {
        case .info: return infoChip
        case .episodes: return episodesChip
        }
    }

    /// Odak açık panele geçmesin: Apple TV'de de seçili çipte kalıyor,
    /// kullanıcı aşağı basınca panele iniyor.
    var focusEnvironments: [UIFocusEnvironment] {
        [button(for: openTab ?? .info)]
    }

    // MARK: - Veri

    /// Yeni bir yayın açılırken. Açık panel kapanıyor, liste baştan kuruluyor.
    func configure(context: PlaybackContext, model: AppModel) {
        detailTask?.cancel()
        openTask?.cancel()
        close()

        self.context = context
        self.model = model
        item = nil
        series = nil
        episodes = []
        chapters = []
        hasNextEpisode = false

        guard let decoded = AppModel.decode(contextID: context.id) else {
            refreshChips()
            return
        }
        currentEpisodeID = decoded.episodeID
        item = model.library.item(for: decoded.mediaID)
        refreshChips()

        guard context.kind == .series, let series = item else { return }
        self.series = series
        detailTask = Task { [weak self] in
            guard let self else { return }
            guard let detail = try? await model.library.detail(for: series) else { return }
            // Oynatılan bölümün sezonu; bulunamazsa ilk sezon.
            let season = detail.seasons.first { season in
                season.episodes.contains { $0.id == decoded.episodeID }
            } ?? detail.seasons.first
            await MainActor.run {
                self.episodes = season?.episodes ?? []
                self.refreshChips()
            }
        }
    }

    /// `readyToPlay` sonrası: dosyanın kendi bölüm işaretleri.
    func setChapters(_ chapters: [Chapter]) {
        guard self.chapters.count != chapters.count else { return }
        self.chapters = chapters
        refreshChips()
    }

    /// Dışarıdan açma: denetim satırının altına inmeye çalışmak "Bilgi"
    /// panelini getiriyor. Sekme yoksa ya da paneli kurulamıyorsa sessiz.
    func open(_ tab: Tab) {
        guard openTab != tab, availableTabs().contains(tab) else { return }
        toggle(tab)
    }

    func close() {
        guard openTab != nil else { return }
        openTab = nil
        showPanel(nil)
        refreshChips()
    }

    // MARK: - Çipler

    private func availableTabs() -> [Tab] {
        var tabs: [Tab] = []
        if item != nil { tabs.append(.info) }
        if !episodes.isEmpty || !chapters.isEmpty { tabs.append(.episodes) }
        return tabs
    }

    private func refreshChips() {
        let tabs = availableTabs()
        // Açık sekme listeden düştüyse panel de kapanmalı.
        if let openTab, !tabs.contains(openTab) { close() }
        for tab in Tab.allCases {
            let button = button(for: tab)
            button.isHidden = !tabs.contains(tab)
            styleChip?(button, tab, openTab == tab)
        }
    }

    /// Çip yeniden seçilince panel kapanıyor. Panel kurulamıyorsa (veri
    /// aradan çekilmiş olabilir) çip seçili görünmüyor: aksi hâlde işaretli
    /// ama boş bir sekmede kalınıyordu.
    private func toggle(_ tab: Tab) {
        if openTab == tab {
            close()
            return
        }
        guard let content = makePanel(for: tab) else { return }
        openTab = tab
        refreshChips()
        showPanel(content)
    }

    /// Veri geç geldiğinde açık paneli yerinde tazeler.
    private func reopenPanel() {
        guard let openTab else { return }
        guard let content = makePanel(for: openTab) else {
            close()
            return
        }
        showPanel(content)
    }

    private func showPanel(_ content: UIView?) {
        panel.subviews.forEach { $0.removeFromSuperview() }
        guard let content else {
            panel.isHidden = true
            onPanelVisibilityChanged?(false)
            return
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: panel.topAnchor),
            content.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
        ])
        panel.isHidden = false
        onPanelVisibilityChanged?(true)
    }

    // MARK: - Paneller

    private func makePanel(for tab: Tab) -> UIView? {
        switch tab {
        case .info: return makeInfoPanel()
        case .episodes: return episodes.isEmpty ? makeChapterRow() : makeEpisodeRow()
        }
    }

    private func makeInfoPanel() -> UIView {
        let view = PlayerInfoPanelView()
        view.configure(
            item: item,
            fallbackTitle: context?.title ?? "",
            hasNextEpisode: hasNextEpisode
        )
        view.onRestart = { [weak self] in self?.onRestart?() }
        view.onNextEpisode = { [weak self] in self?.onNextEpisode?() }
        return view
    }

    private func makeEpisodeRow() -> UIView? {
        guard let series, let model else { return nil }
        let width = metrics.clipCardWidth
        let size = CGSize(width: width, height: width * 9 / 16 + metrics.clipCardTextHeight)
        return HorizontalCardRow<MediaClipCell, Episode>(
            values: episodes,
            cardSize: size,
            spacing: metrics.cardSpacing,
            contentInset: 0,
            reuseID: MediaClipCell.reuseID,
            configureCell: { [weak self] cell, episode in
                guard let self else { return }
                let progress = model.activity.progress(for: series.id, episodeID: episode.id)
                let isCurrent = episode.id == currentEpisodeID
                let title = [episode.numberText, episode.title].joined(separator: " · ")
                cell.configure(
                    title: isCurrent ? "\(L10n.nowPlayingBadge) · \(title)" : title,
                    durationText: episode.durationText,
                    imageURL: episode.stillURL,
                    metrics: metrics,
                    width: width,
                    playedFraction: progress?.fraction
                )
            },
            onSelect: { [weak self] episode, _ in
                guard let self, episode.id != currentEpisodeID else { return }
                play { try await model.library.playback(for: episode, in: series) }
            }
        )
    }

    private func makeChapterRow() -> UIView? {
        guard !chapters.isEmpty else { return nil }
        #if os(tvOS)
        let size = CGSize(width: 320, height: 120)
        #else
        let size = CGSize(width: 190, height: 78)
        #endif
        let current = currentChapterIndex()
        let entries = chapters.enumerated().map { ChapterEntry(index: $0.offset, chapter: $0.element) }
        return HorizontalCardRow<PlayerChapterCell, ChapterEntry>(
            values: entries,
            cardSize: size,
            spacing: metrics.cardSpacing,
            contentInset: 0,
            reuseID: PlayerChapterCell.reuseID,
            configureCell: { cell, entry in
                let title = entry.chapter.title.isEmpty
                    ? L10n.chapterName(entry.index + 1)
                    : entry.chapter.title
                cell.configure(
                    title: title,
                    timeText: Self.timeText(entry.chapter.start),
                    isCurrent: entry.index == current
                )
            },
            onSelect: { [weak self] entry, _ in
                self?.onSeek?(entry.chapter.start)
            }
        )
    }

    // MARK: - Yardımcılar

    private func play(_ build: @escaping @MainActor () async throws -> PlaybackContext) {
        openTask?.cancel()
        openTask = Task { [weak self] in
            guard let self else { return }
            guard let context = try? await build() else { return }
            await MainActor.run {
                self.close()
                self.onPlay?(context)
            }
        }
    }

    /// Oynatılan an hangi bölüm işaretinin içinde.
    private func currentChapterIndex() -> Int? {
        guard let time = currentTime else { return nil }
        return chapters.lastIndex { $0.start <= time }
    }

    private static func timeText(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
