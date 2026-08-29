import AVFoundation
import KSPlayer
import UIKit

#if os(tvOS)
/// `UISlider` tvOS'ta yok — orada bir tutamacı sürükleme diye bir etkileşim de
/// yok. İlerleme bir çubukta gösteriliyor, sarma ileri/geri butonlarıyla
/// yapılıyor (kumandada bunlar zaten odaklanabilir).
///
/// `UIControl` türetiliyor ve `UISlider`'ın kullanılan yüzeyini birebir
/// karşılıyor; böylece ortak oynatıcı kodu iki platformda da aynı kalıyor.
final class PlaybackSlider: UIControl {
    var minimumValue: Float = 0
    var maximumValue: Float = 1

    var value: Float = 0 {
        didSet { updateProgress() }
    }

    var minimumTrackTintColor: UIColor? {
        get { progressView.progressTintColor }
        set { progressView.progressTintColor = newValue }
    }

    var maximumTrackTintColor: UIColor? {
        get { progressView.trackTintColor }
        set { progressView.trackTintColor = newValue }
    }

    private let progressView = UIProgressView(progressViewStyle: .default)

    override init(frame: CGRect) {
        super.init(frame: frame)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressView.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Tutamaç tvOS'ta yok; çağrı sessizce yutuluyor.
    func setThumbImage(_ image: UIImage?, for state: UIControl.State) {}

    private func updateProgress() {
        let span = maximumValue - minimumValue
        guard span > 0 else { return }
        progressView.progress = (value - minimumValue) / span
    }
}
#else
typealias PlaybackSlider = UISlider
#endif

/// Tam ekran oynatıcı.
///
/// AVFoundation bu içerikleri açamıyor: sağlayıcı VOD'ları `mkv`, canlı
/// yayınları ham `ts` olarak veriyor. Bu yüzden oynatma tamamen FFmpeg tabanlı
/// `KSMEPlayer` üzerinden yürüyor.
final class PlayerViewController: UIViewController {
    /// Bölüm geçişinde yerine sıradakinin bağlamı konuyor.
    private var context: PlaybackContext
    private let model: AppModel

    private var playerLayer: KSPlayerLayer?
    private var videoView: UIView?

    private let controlsView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let rewindButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let audioTracksButton = UIButton(type: .system)
    private let subtitlesButton = UIButton(type: .system)
    private let aspectButton = UIButton(type: .system)
    private let nextEpisodeButton = UIButton(type: .system)

    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let slider = PlaybackSlider()
    private let liveBadge = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .large)

    private var isPlaying = true
    private var isScrubbing = false
    private var currentTime: Double = 0
    private var duration: Double = 0
    private var hideControlsWork: DispatchWorkItem?

    private var selectedAudioTrackID: Int32?
    private var selectedSubtitleID: Int32?

    /// Sıradaki bölüm; yoksa buton gizli ve bitince otomatik geçiş olmuyor.
    private var nextEpisode: (episode: Episode, series: MediaItem)?

    init(context: PlaybackContext, model: AppModel) {
        self.context = context
        self.model = model
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Ana ekran çizgisi ve durum çubuğu yalnızca iOS'ta var.
    #if os(iOS)
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildControls()
        startPlayback()
        scheduleControlsHide()

        // tvOS'ta ekrana dokunma diye bir şey yok; girdi `pressesBegan` ve
        // `touchesBegan` üzerinden kumandadan geliyor.
        #if os(iOS)
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        tap.delegate = self
        view.addGestureRecognizer(tap)
        #endif

        if context.isLive {
            loadLiveEPG()
        }
        refreshNextEpisode()
    }

    /// Sıradaki bölümü çözüp butonun görünürlüğünü ayarlar.
    private func refreshNextEpisode() {
        nextEpisode = nil
        nextEpisodeButton.isHidden = true
        guard context.kind == .series else { return }
        Task { [weak self] in
            guard let self else { return }
            let next = await model.nextEpisode(after: context)
            await MainActor.run {
                self.nextEpisode = next
                self.nextEpisodeButton.isHidden = next == nil
            }
        }
    }

    /// Sıradaki bölüme geçer. Oynatıcı kapanıp yeniden açılmıyor; aynı ekranda
    /// katman değiştiriliyor, böylece kullanıcı akıştan kopmuyor.
    @objc private func playNextEpisode() {
        guard let next = nextEpisode else { return }
        nextEpisodeButton.isHidden = true
        Task { [weak self] in
            guard let self else { return }
            guard let newContext = try? await model.library.playback(for: next.episode, in: next.series) else { return }
            await MainActor.run { self.restart(with: newContext) }
        }
    }

    private func restart(with newContext: PlaybackContext) {
        saveProgress()
        playerLayer?.pause()
        playerLayer?.stop()
        playerLayer = nil
        videoView?.removeFromSuperview()
        videoView = nil

        context = newContext
        currentTime = 0
        duration = 0
        isPlaying = true
        playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        titleLabel.text = newContext.title
        subtitleLabel.text = newContext.subtitle
        subtitleLabel.isHidden = newContext.subtitle == nil

        startPlayback()
        refreshNextEpisode()
        showControls()
    }

    // MARK: - Kumanda girdisi (tvOS)

    #if os(tvOS)
    /// Kontroller açıldığında odak doğrudan oynat/duraklat'a gidiyor.
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [playPauseButton]
    }

    /// Kumanda tuşları.
    ///
    /// Kontroller gizliyken yön tuşu, seçim ve Menu yalnızca arayüzü geri
    /// getiriyor; basış eylemi tetiklemiyor. Aksi hâlde kullanıcı göremediği
    /// bir butonu yanlışlıkla çalıştırırdı.
    ///
    /// Oynat/Duraklat tuşu bunun dışında: o her zaman oynatmayı değiştiriyor,
    /// arayüz kapalıyken bile — kumandadaki karşılığı bu ve beklenen davranış.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .playPause:
                togglePlayPause()
                return

            case .menu:
                // Arayüz açıkken Menu oynatıcıdan çıkıyor; kapalıyken önce
                // arayüzü geri getiriyor. Böylece çıkış yolu hep açık kalıyor.
                if isControlsVisible {
                    close()
                } else {
                    showControls()
                }
                return

            case .select, .upArrow, .downArrow, .leftArrow, .rightArrow:
                guard !isControlsVisible else { break }
                showControls()
                return

            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    /// Kumandanın dokunmatik yüzeyine dokunmak da arayüzü geri getiriyor.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !isControlsVisible {
            showControls()
        }
        super.touchesBegan(touches, with: event)
    }
    #endif

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        saveProgress()
        playerLayer?.pause()
        playerLayer?.stop()
        playerLayer = nil
    }

    // MARK: - Oynatma

    private func startPlayback() {
        Task.detached(priority: .userInitiated) { KSOptions.setAudioSession() }

        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = nil

        let options = KSOptions()
        options.userAgent = context.headers["User-Agent"] ?? "VLC/3.0.20 LibVLC/3.0.20"
        if let referer = context.headers["Referer"] { options.referer = referer }
        if let startAt = context.startAt, startAt > 0, !context.isLive {
            options.startPlayTime = startAt
        }

        let layer = KSPlayerLayer(url: context.url, options: options, delegate: self)
        playerLayer = layer

        guard let videoView = layer.player.view else { return }
        self.videoView = videoView
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(videoView, at: 0)
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func saveProgress() {
        guard !context.isLive, duration > 0 else { return }
        model.recordProgress(for: context, position: currentTime, duration: duration)
    }

    private func loadLiveEPG() {
        // Canlı yayınlarda anlık program bilgisini alt başlık olarak göster
        let parts = context.id.split(separator: "#", maxSplits: 1).map(String.init)
        let mediaParts = parts[0].split(separator: "|", maxSplits: 2).map(String.init)
        guard mediaParts.count == 3, let kind = MediaKind(rawValue: mediaParts[1]) else { return }
        let mediaID = MediaID(source: mediaParts[0], kind: kind, raw: mediaParts[2])

        if let item = model.library.item(for: mediaID) {
            Task {
                let epgEntries = await model.library.epg(for: item)
                let now = Date()
                if let currentProgram = epgEntries.first(where: { $0.start <= now && $0.end >= now }) {
                    await MainActor.run {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "HH:mm"
                        let timeRange = "\(formatter.string(from: currentProgram.start)) - \(formatter.string(from: currentProgram.end))"
                        self.subtitleLabel.text = "\(timeRange) · \(currentProgram.title)"
                        self.subtitleLabel.isHidden = false
                    }
                }
            }
        }
    }

    // MARK: - Kontroller

    private func buildControls() {
        titleLabel.text = context.title
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2

        subtitleLabel.text = context.subtitle
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        subtitleLabel.isHidden = context.subtitle == nil

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        closeButton.layer.cornerRadius = 20
        closeButton.addTarget(self, action: #selector(close), for: .primaryActionTriggered)

        // Üst sağ kontrol butonları (Ses, Altyazı, Aspect Ratio)
        aspectButton.setImage(UIImage(systemName: "aspectratio"), for: .normal)
        aspectButton.tintColor = .white
        aspectButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        aspectButton.layer.cornerRadius = 20
        aspectButton.showsMenuAsPrimaryAction = true
        aspectButton.menu = makeAspectMenu()

        audioTracksButton.setImage(UIImage(systemName: "speaker.wave.2"), for: .normal)
        audioTracksButton.tintColor = .white
        audioTracksButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        audioTracksButton.layer.cornerRadius = 20
        audioTracksButton.showsMenuAsPrimaryAction = true

        subtitlesButton.setImage(UIImage(systemName: "captions.bubble"), for: .normal)
        subtitlesButton.tintColor = .white
        subtitlesButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        subtitlesButton.layer.cornerRadius = 20
        subtitlesButton.showsMenuAsPrimaryAction = true

        playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        playPauseButton.tintColor = .white
        playPauseButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 24, weight: .medium), forImageIn: .normal)
        playPauseButton.addTarget(self, action: #selector(togglePlayPause), for: .primaryActionTriggered)

        rewindButton.setImage(UIImage(systemName: "gobackward.15"), for: .normal)
        rewindButton.tintColor = .white
        rewindButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .regular), forImageIn: .normal)
        rewindButton.addTarget(self, action: #selector(seekBackward), for: .primaryActionTriggered)

        forwardButton.setImage(UIImage(systemName: "goforward.15"), for: .normal)
        forwardButton.tintColor = .white
        forwardButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .regular), forImageIn: .normal)
        forwardButton.addTarget(self, action: #selector(seekForward), for: .primaryActionTriggered)

        for label in [currentTimeLabel, durationLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            label.textColor = .white
        }
        currentTimeLabel.text = "0:00"
        durationLabel.text = "0:00"

        // İnteraktif Scrubber Slider
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = 0
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        slider.setThumbImage(makeThumbImage(), for: .normal)
        slider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let dot = UIView()
        dot.backgroundColor = .systemRed
        dot.layer.cornerRadius = 4
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let liveLabel = UILabel()
        liveLabel.text = AppLanguage.current.effectiveLanguageCode == "tr" ? "CANLI" : "LIVE"
        liveLabel.font = .systemFont(ofSize: 12, weight: .bold)
        liveLabel.textColor = .white
        liveBadge.addArrangedSubview(dot)
        liveBadge.addArrangedSubview(liveLabel)
        liveBadge.axis = .horizontal
        liveBadge.spacing = 6
        liveBadge.alignment = .center
        liveBadge.isHidden = !context.isLive

        nextEpisodeButton.setImage(UIImage(systemName: "forward.end.fill"), for: .normal)
        nextEpisodeButton.tintColor = .white
        nextEpisodeButton.accessibilityLabel = L10n.nextEpisode
        nextEpisodeButton.isHidden = true
        nextEpisodeButton.addTarget(self, action: #selector(playNextEpisode), for: .primaryActionTriggered)

        let controlButtons: [UIView] = context.isLive
            ? [playPauseButton, liveBadge, UIView()]
            : [rewindButton, playPauseButton, forwardButton, nextEpisodeButton,
               currentTimeLabel, slider, durationLabel]

        let scrubberRow = UIStackView(arrangedSubviews: controlButtons)
        scrubberRow.axis = .horizontal
        scrubberRow.spacing = 14
        scrubberRow.alignment = .center

        let bar = UIView()
        bar.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        bar.layer.cornerRadius = 16
        bar.layer.cornerCurve = .continuous
        scrubberRow.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(scrubberRow)

        let topButtons = UIStackView(arrangedSubviews: [aspectButton, audioTracksButton, subtitlesButton, closeButton])
        topButtons.axis = .horizontal
        topButtons.spacing = 10
        topButtons.alignment = .center

        let titles = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titles.axis = .vertical
        titles.spacing = 4

        controlsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsView)
        for subview in [titles, topButtons, bar] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            controlsView.addSubview(subview)
        }

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        spinner.startAnimating()
        view.addSubview(spinner)

        for btn in [aspectButton, audioTracksButton, subtitlesButton, closeButton] {
            btn.widthAnchor.constraint(equalToConstant: 40).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }

        NSLayoutConstraint.activate([
            controlsView.topAnchor.constraint(equalTo: view.topAnchor),
            controlsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controlsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            titles.topAnchor.constraint(equalTo: controlsView.safeAreaLayoutGuide.topAnchor, constant: 12),
            titles.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 20),
            titles.trailingAnchor.constraint(lessThanOrEqualTo: topButtons.leadingAnchor, constant: -12),

            topButtons.topAnchor.constraint(equalTo: controlsView.safeAreaLayoutGuide.topAnchor, constant: 12),
            topButtons.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -20),

            bar.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 20),
            bar.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -20),
            bar.bottomAnchor.constraint(equalTo: controlsView.safeAreaLayoutGuide.bottomAnchor, constant: -20),

            scrubberRow.topAnchor.constraint(equalTo: bar.topAnchor, constant: 12),
            scrubberRow.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -12),
            scrubberRow.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            scrubberRow.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func makeThumbImage() -> UIImage {
        let size = CGSize(width: 14, height: 14)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
    }

    private func makeAspectMenu() -> UIMenu {
        let isTR = AppLanguage.current.effectiveLanguageCode == "tr"
        let fit = UIAction(title: L10n.aspectFit, image: UIImage(systemName: "arrow.down.right.and.arrow.up.left")) { [weak self] _ in
            self?.videoView?.contentMode = .scaleAspectFit
            self?.playerLayer?.player.view?.contentMode = .scaleAspectFit
        }
        let fill = UIAction(title: L10n.aspectFill, image: UIImage(systemName: "arrow.up.left.and.arrow.down.right")) { [weak self] _ in
            self?.videoView?.contentMode = .scaleAspectFill
            self?.playerLayer?.player.view?.contentMode = .scaleAspectFill
        }
        let stretch = UIAction(title: isTR ? "Tam Ekran (Uzat)" : "Stretch (16:9)", image: UIImage(systemName: "rectangle.arrowtriangle.2.outward")) { [weak self] _ in
            self?.videoView?.contentMode = .scaleToFill
            self?.playerLayer?.player.view?.contentMode = .scaleToFill
        }
        return UIMenu(title: L10n.aspectRatio, children: [fit, fill, stretch])
    }

    private func updateTrackMenus() {
        guard let player = playerLayer?.player else { return }

        // Ses parçaları
        let audioTracks = player.tracks(mediaType: .audio)
        if !audioTracks.isEmpty {
            let actions = audioTracks.map { track in
                let isSelected = (self.selectedAudioTrackID == track.trackID) || (self.selectedAudioTrackID == nil && track.isEnabled)
                let name = track.name.isEmpty ? "\(L10n.audioTracks) \(track.trackID)" : track.name
                return UIAction(title: name, state: isSelected ? .on : .off) { [weak self] _ in
                    self?.playerLayer?.player.select(track: track)
                    self?.selectedAudioTrackID = track.trackID
                    self?.updateTrackMenus()
                }
            }
            audioTracksButton.menu = UIMenu(title: L10n.audioTracks, children: actions)
            audioTracksButton.isHidden = false
        } else {
            audioTracksButton.isHidden = true
        }

        // Altyazı parçaları
        let subTracks = player.tracks(mediaType: .subtitle)
        if !subTracks.isEmpty {
            var subActions: [UIAction] = [
                UIAction(title: L10n.subtitlesOff, state: self.selectedSubtitleID == -1 ? .on : .off) { [weak self] _ in
                    self?.selectedSubtitleID = -1
                    // Altyazı kapatma
                    self?.updateTrackMenus()
                }
            ]
            subActions += subTracks.map { track in
                let isSelected = self.selectedSubtitleID == track.trackID
                let name = track.name.isEmpty ? "\(L10n.subtitles) \(track.trackID)" : track.name
                return UIAction(title: name, state: isSelected ? .on : .off) { [weak self] _ in
                    self?.playerLayer?.player.select(track: track)
                    self?.selectedSubtitleID = track.trackID
                    self?.updateTrackMenus()
                }
            }
            subtitlesButton.menu = UIMenu(title: L10n.subtitles, children: subActions)
            subtitlesButton.isHidden = false
        } else {
            subtitlesButton.isHidden = true
        }
    }

    // MARK: - Aksiyonlar

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func togglePlayPause() {
        isPlaying.toggle()
        isPlaying ? playerLayer?.play() : playerLayer?.pause()
        playPauseButton.setImage(UIImage(systemName: isPlaying ? "pause.fill" : "play.fill"), for: .normal)
        isPlaying ? scheduleControlsHide() : showControls()
    }

    @objc private func seekBackward() {
        seek(by: -15)
    }

    @objc private func seekForward() {
        seek(by: 15)
    }

    private func seek(by seconds: Double) {
        guard duration > 0 else { return }
        let target = max(0, min(duration, currentTime + seconds))
        currentTime = target
        currentTimeLabel.text = Self.timeText(target)
        slider.value = Float(target / duration)
        playerLayer?.seek(time: target, autoPlay: isPlaying, completion: { _ in })
        showControls()
    }

    @objc private func sliderTouchDown() {
        isScrubbing = true
        hideControlsWork?.cancel()
    }

    @objc private func sliderValueChanged() {
        guard duration > 0 else { return }
        let targetTime = Double(slider.value) * duration
        currentTimeLabel.text = Self.timeText(targetTime)
    }

    @objc private func sliderTouchUp() {
        guard duration > 0 else { isScrubbing = false; return }
        let targetTime = Double(slider.value) * duration
        currentTime = targetTime
        playerLayer?.seek(time: targetTime, autoPlay: isPlaying, completion: { _ in })
        isScrubbing = false
        scheduleControlsHide()
    }

    @objc private func toggleControls() {
        isControlsVisible ? hideControls() : showControls()
    }

    private var isControlsVisible: Bool { controlsView.alpha > 0 }

    private func showControls() {
        setControlsVisible(true, duration: 0.2)
        scheduleControlsHide()
    }

    private func hideControls() {
        guard !isScrubbing else { return }
        hideControlsWork?.cancel()
        setControlsVisible(false, duration: 0.2)
    }

    /// Saydamlık tek başına yetmiyor: tvOS'ta görünmez ama etkileşime açık bir
    /// katman odak almaya devam ediyor ve kullanıcı boşlukta gezinmiş oluyor.
    /// Etkileşim kapatılınca içindeki butonlar odak sisteminden de düşüyor.
    private func setControlsVisible(_ visible: Bool, duration: TimeInterval) {
        controlsView.isUserInteractionEnabled = visible
        UIView.animate(withDuration: duration) { self.controlsView.alpha = visible ? 1 : 0 }
        #if os(tvOS)
        if visible {
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }
        #endif
    }

    private func scheduleControlsHide() {
        hideControlsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isPlaying, !self.isScrubbing else { return }
            setControlsVisible(false, duration: 0.25)
        }
        hideControlsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private static func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

extension PlayerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Kontrol butonlarına veya slider'a dokunurken ekran jestinin araya girmesini engelle
        if touch.view is UIControl || touch.view?.superview is UIControl {
            return false
        }
        return true
    }
}

extension PlayerViewController: KSPlayerLayerDelegate {
    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        switch state {
        case .readyToPlay, .bufferFinished:
            spinner.stopAnimating()
            updateTrackMenus()
        case .buffering, .preparing, .initialized:
            spinner.startAnimating()
        case .error:
            spinner.stopAnimating()
            showFailure(L10n.streamFailed)
        case .paused, .playedToTheEnd:
            spinner.stopAnimating()
        }
    }

    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        guard !isScrubbing else { return }
        self.currentTime = currentTime
        duration = totalTime.isFinite && totalTime > 0 ? totalTime : 0

        currentTimeLabel.text = Self.timeText(currentTime)
        durationLabel.text = Self.timeText(duration)
        guard duration > 0 else { return }
        slider.value = Float(currentTime / duration)
    }

    func player(layer: KSPlayerLayer, finish error: (any Error)?) {
        if let error {
            showFailure(error.localizedDescription)
            return
        }
        // Hatasız bitiş: dizide sıradaki bölüm varsa kendiliğinden geçiyor.
        if nextEpisode != nil {
            playNextEpisode()
        }
    }

    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {}

    private func showFailure(_ message: String) {
        let alert = UIAlertController(title: context.title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.close, style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}
