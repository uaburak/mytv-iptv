import KSPlayer
import UIKit

/// Tam ekran oynatıcı.
///
/// AVFoundation bu içerikleri açamıyor: sağlayıcı VOD'ları `mkv`, canlı
/// yayınları ham `ts` olarak veriyor. Bu yüzden oynatma tamamen FFmpeg tabanlı
/// `KSMEPlayer` üzerinden yürüyor.
final class PlayerViewController: UIViewController {
    private let context: PlaybackContext
    private let model: AppModel

    private var playerLayer: KSPlayerLayer?
    private var videoView: UIView?

    private let controlsView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let liveBadge = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private var progressWidth: NSLayoutConstraint?

    private var isPlaying = true
    private var currentTime: Double = 0
    private var duration: Double = 0
    private var hideControlsWork: DispatchWorkItem?

    init(context: PlaybackContext, model: AppModel) {
        self.context = context
        self.model = model
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildControls()
        startPlayback()
        scheduleControlsHide()

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        view.addGestureRecognizer(tap)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        saveProgress()
        playerLayer?.pause()
        playerLayer?.stop()
        playerLayer = nil
    }

    // MARK: - Oynatma

    private func startPlayback() {
        // Ses oturumunu ana iş parçacığında açmak arayüzü kilitleyebiliyor.
        Task.detached(priority: .userInitiated) { KSOptions.setAudioSession() }

        // IPTV kaynaklarında AVFoundation'ın açabileceği bir kapsayıcı yok.
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = nil

        let options = KSOptions()
        // Bazı paneller bilinmeyen istemcileri reddediyor.
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
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        playPauseButton.tintColor = .white
        playPauseButton.addTarget(self, action: #selector(togglePlayPause), for: .touchUpInside)

        for label in [currentTimeLabel, durationLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            label.textColor = .white
        }

        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        progressTrack.layer.cornerRadius = 2.5
        progressFill.backgroundColor = .white
        progressFill.layer.cornerRadius = 2.5

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

        let scrubberRow = UIStackView(arrangedSubviews: context.isLive
            ? [playPauseButton, liveBadge, UIView()]
            : [playPauseButton, currentTimeLabel, progressTrack, durationLabel])
        scrubberRow.axis = .horizontal
        scrubberRow.spacing = 14
        scrubberRow.alignment = .center

        let bar = UIView()
        bar.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        bar.layer.cornerRadius = 16
        scrubberRow.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(scrubberRow)

        let titles = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titles.axis = .vertical
        titles.spacing = 4

        controlsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsView)
        for subview in [titles, closeButton, bar] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            controlsView.addSubview(subview)
        }

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        spinner.startAnimating()
        view.addSubview(spinner)

        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)
        let fillWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)
        progressWidth = fillWidth

        NSLayoutConstraint.activate([
            controlsView.topAnchor.constraint(equalTo: view.topAnchor),
            controlsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controlsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            titles.topAnchor.constraint(equalTo: controlsView.safeAreaLayoutGuide.topAnchor, constant: 12),
            titles.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 20),
            titles.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),

            closeButton.topAnchor.constraint(equalTo: controlsView.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),

            bar.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 20),
            bar.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -20),
            bar.bottomAnchor.constraint(equalTo: controlsView.safeAreaLayoutGuide.bottomAnchor, constant: -20),

            scrubberRow.topAnchor.constraint(equalTo: bar.topAnchor, constant: 14),
            scrubberRow.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -14),
            scrubberRow.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20),
            scrubberRow.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20),

            progressTrack.heightAnchor.constraint(equalToConstant: 5),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            fillWidth,

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func togglePlayPause() {
        isPlaying.toggle()
        isPlaying ? playerLayer?.play() : playerLayer?.pause()
        playPauseButton.setImage(UIImage(systemName: isPlaying ? "pause.fill" : "play.fill"), for: .normal)
        isPlaying ? scheduleControlsHide() : showControls()
    }

    @objc private func toggleControls() {
        controlsView.alpha > 0 ? hideControls() : showControls()
    }

    private func showControls() {
        UIView.animate(withDuration: 0.2) { self.controlsView.alpha = 1 }
        scheduleControlsHide()
    }

    private func hideControls() {
        hideControlsWork?.cancel()
        UIView.animate(withDuration: 0.2) { self.controlsView.alpha = 0 }
    }

    private func scheduleControlsHide() {
        hideControlsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, isPlaying else { return }
            UIView.animate(withDuration: 0.25) { self.controlsView.alpha = 0 }
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

extension PlayerViewController: KSPlayerLayerDelegate {
    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        switch state {
        case .readyToPlay, .bufferFinished:
            spinner.stopAnimating()
        case .buffering, .preparing, .initialized:
            spinner.startAnimating()
        case .error:
            spinner.stopAnimating()
            showFailure("Yayın açılamadı.")
        case .paused, .playedToTheEnd:
            spinner.stopAnimating()
        }
    }

    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        self.currentTime = currentTime
        duration = totalTime.isFinite && totalTime > 0 ? totalTime : 0

        currentTimeLabel.text = Self.timeText(currentTime)
        durationLabel.text = Self.timeText(duration)
        guard duration > 0 else { return }
        progressWidth?.constant = progressTrack.bounds.width * CGFloat(min(1, currentTime / duration))
    }

    func player(layer: KSPlayerLayer, finish error: (any Error)?) {
        guard let error else { return }
        showFailure(error.localizedDescription)
    }

    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {}

    private func showFailure(_ message: String) {
        let alert = UIAlertController(title: context.title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Kapat", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}
