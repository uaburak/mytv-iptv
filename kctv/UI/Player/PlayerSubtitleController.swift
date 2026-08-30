import AVFoundation
import KSPlayer
import UIKit

/// Oynatıcının altyazı motoru.
///
/// KSPlayer altyazıyı ekrana koymuyor: gömülü akışı çözüp `SubtitleModel`'e
/// bırakıyor, geri kalanı uygulamanın işi. Oynatıcı ekranı bu yüzden eskiden
/// altyazı **seçebiliyor** ama hiçbir şey gösteremiyordu — parça seçiliyor,
/// çizen kimse olmuyordu.
///
/// Bu tip üç şeyi tek yerde topluyor: model, ekrandaki katman ve menü.
///
/// İki oynatma yolu var ve ikisi altyazıyı farklı yerden alıyor:
/// - **FFmpeg (`KSMEPlayer`)**: parçalar `SubtitleModel` üzerinden geliyor,
///   çizimi `SubtitleOverlayView` yapıyor. Sağlayıcı içeriğinin (`mkv`, ham
///   `ts`) tamamı bu yoldan geçiyor.
/// - **`AVPlayer`**: altyazıyı sistem kendisi çiziyor; burada yalnızca parça
///   seçiliyor.
@MainActor
final class PlayerSubtitleController {
    /// Menüdeki liste ya da seçim değişti; buton menüsü yeniden kurulmalı.
    var onMenuChanged: (() -> Void)?

    private let model = SubtitleModel()
    private let overlay: SubtitleOverlayView
    private weak var playerLayer: KSPlayerLayer?

    /// Gömülü altyazıları geç tarayan iş. Bölüm değişiminde iptal ediliyor,
    /// yoksa önceki yayının parçaları yenisinin listesine düşüyor.
    private var embedScan: DispatchWorkItem?

    init(overlay: SubtitleOverlayView) {
        self.overlay = overlay
        SubtitleSettings.applyToPlayer()
    }

    // MARK: - Yaşam döngüsü

    /// Yeni bir yayın açılırken: seçim, ekrandaki yazı ve bekleyen tarama
    /// sıfırlanıyor.
    func prepare(url: URL) {
        embedScan?.cancel()
        embedScan = nil
        playerLayer = nil
        overlay.parts = []
        SubtitleSettings.applyToPlayer()
        overlay.applySettings()
        model.subtitleDelay = SubtitleSettings.delay
        model.url = url
    }

    /// `readyToPlay` sonrası çağrılıyor.
    ///
    /// Gömülü altyazılar video akışının içinde gelebiliyor ve `readyToPlay`
    /// anında listede henüz görünmüyorlar; KSPlayer'ın kendi oynatıcısı da bu
    /// yüzden bir saniye bekliyor.
    func playerBecameReady(_ layer: KSPlayerLayer) {
        playerLayer = layer

        guard let source = layer.player.subtitleDataSouce else {
            // AVPlayer yolu: liste doğrudan oynatıcıdan okunuyor, beklenecek
            // bir şey yok.
            onMenuChanged?()
            return
        }

        embedScan?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Parça parça ekleniyor: `addSubtitle(info:)` aynı kimliği iki kez
            // almıyor. `readyToPlay` yedek oynatıcıya düşüldüğünde tekrar
            // gelebiliyor ve liste o zaman ikizleniyordu.
            for info in source.infos {
                model.addSubtitle(info: info)
            }
            if model.selectedSubtitleInfo == nil, SubtitleSettings.autoEnable {
                select(preferredTrack())
            }
            onMenuChanged?()
        }
        embedScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Oynatma ilerledikçe çağrılıyor. Model değişimi bildirmediğinde katmana
    /// dokunulmuyor: geri çağrı saniyede on kez geliyor.
    func update(currentTime: TimeInterval) {
        guard model.subtitle(currentTime: currentTime) else { return }
        overlay.parts = model.parts
    }

    /// Sarma sonrası ekranda kalan eski satırı siler.
    func flush() {
        overlay.parts = []
    }

    // MARK: - Seçim

    /// Altyazıyı değiştirir; `nil` kapatıyor.
    func select(_ info: (any SubtitleInfo)?) {
        // Görüntü tabanlı altyazıda (PGS/DVB) akışın çözülmeye başlaması için
        // parçanın oynatıcıda da seçilmesi gerekiyor. Sıra önemli:
        // `selectedSubtitleInfo` parçayı zaten etkinleştirdiği için ondan
        // sonra çağrılan `select` erken dönüyor.
        if let track = info as? (any MediaPlayerTrack) {
            playerLayer?.player.select(track: track)
        }
        model.selectedSubtitleInfo = info
        model.subtitleDelay = SubtitleSettings.delay
        overlay.parts = []
        onMenuChanged?()
    }

    /// Ayar menüsünden dönüşte: punto/renk anında uygulanıyor.
    func refreshAppearance() {
        SubtitleSettings.applyToPlayer()
        overlay.applySettings()
        model.subtitleDelay = SubtitleSettings.delay
        onMenuChanged?()
    }

    // MARK: - Menü

    func makeMenu() -> UIMenu {
        UIMenu(
            title: L10n.subtitles,
            children: [
                UIMenu(options: .displayInline, children: trackElements()),
                settingsMenu(),
            ]
        )
    }

    private func trackElements() -> [UIMenuElement] {
        let infos = model.subtitleInfos
        if !infos.isEmpty {
            let selectedID = model.selectedSubtitleInfo?.subtitleID
            var elements: [UIMenuElement] = [
                UIAction(title: L10n.subtitlesOff, state: selectedID == nil ? .on : .off) { [weak self] _ in
                    self?.select(nil)
                },
            ]
            for info in infos {
                elements.append(
                    UIAction(title: Self.menuTitle(info: info), state: info.subtitleID == selectedID ? .on : .off) { [weak self] _ in
                        self?.select(info)
                    }
                )
            }
            return elements
        }

        let tracks = playerLayer?.player.tracks(mediaType: .subtitle) ?? []
        guard !tracks.isEmpty else {
            return [UIAction(title: L10n.subtitleNotFound, attributes: .disabled) { _ in }]
        }
        let isOff = !tracks.contains { $0.isEnabled }
        var elements: [UIMenuElement] = [
            UIAction(title: L10n.subtitlesOff, state: isOff ? .on : .off) { [weak self] _ in
                self?.selectSystemTrack(nil)
            },
        ]
        for track in tracks {
            elements.append(
                UIAction(title: Self.menuTitle(track: track), state: track.isEnabled ? .on : .off) { [weak self] _ in
                    self?.selectSystemTrack(track)
                }
            )
        }
        return elements
    }

    private func settingsMenu() -> UIMenu {
        let sizes = SubtitleSettings.TextSize.allCases.map { size in
            UIAction(title: size.title, state: SubtitleSettings.textSize == size ? .on : .off) { [weak self] _ in
                SubtitleSettings.textSize = size
                self?.refreshAppearance()
            }
        }
        let colors = SubtitleSettings.TextColor.allCases.map { color in
            UIAction(title: color.title, state: SubtitleSettings.textColor == color ? .on : .off) { [weak self] _ in
                SubtitleSettings.textColor = color
                self?.refreshAppearance()
            }
        }
        let backgrounds = SubtitleSettings.Background.allCases.map { background in
            UIAction(title: background.title, state: SubtitleSettings.background == background ? .on : .off) { [weak self] _ in
                SubtitleSettings.background = background
                self?.refreshAppearance()
            }
        }
        let delays = SubtitleSettings.delayOptions.map { value in
            // Kayan noktalı eşitlik yerine tolerans: 0,5'lik adımlar ikilik
            // tabanda birebir denk gelmiyor.
            let isSelected = abs(SubtitleSettings.delay - value) < 0.01
            return UIAction(title: L10n.subtitleDelayValue(value), state: isSelected ? .on : .off) { [weak self] _ in
                SubtitleSettings.delay = value
                self?.refreshAppearance()
            }
        }

        let bold = UIAction(
            title: L10n.subtitleBold,
            state: SubtitleSettings.isBold ? .on : .off
        ) { [weak self] _ in
            SubtitleSettings.isBold.toggle()
            self?.refreshAppearance()
        }

        let auto = UIAction(
            title: L10n.subtitleAutoEnable,
            state: SubtitleSettings.autoEnable ? .on : .off
        ) { [weak self] _ in
            SubtitleSettings.autoEnable.toggle()
            self?.onMenuChanged?()
        }

        return UIMenu(
            title: L10n.subtitleSettings,
            image: UIImage(systemName: "textformat.size"),
            children: [
                UIMenu(title: L10n.subtitleTextSize, children: sizes),
                UIMenu(title: L10n.subtitleTextColor, children: colors),
                UIMenu(title: L10n.subtitleBackground, children: backgrounds),
                UIMenu(title: L10n.subtitleDelay, children: delays),
                UIMenu(options: .displayInline, children: [bold, auto]),
            ]
        )
    }

    // MARK: - Yardımcılar

    /// AVPlayer yolunda parça seçimi. Altyazıyı sistem çizdiği için katmana
    /// dokunulmuyor.
    private func selectSystemTrack(_ track: (any MediaPlayerTrack)?) {
        guard let player = playerLayer?.player else { return }
        if let track {
            player.select(track: track)
        } else {
            player.tracks(mediaType: .subtitle).forEach { $0.isEnabled = false }
        }
        onMenuChanged?()
    }

    /// Kendiliğinden açılacak altyazı.
    ///
    /// Uygulamanın diliyle eşleşen parça öne alınıyor: listede hem Arapça hem
    /// Türkçe varken ilkini seçmek kullanıcıya hiçbir şey anlatmıyor.
    /// Eşleşme yoksa çözülmeye hazır (metin ya da "forced") ilk parça
    /// kullanılıyor — KSPlayer'ın kendi kuralı da bu.
    private func preferredTrack() -> (any SubtitleInfo)? {
        let infos = model.subtitleInfos
        guard !infos.isEmpty else { return nil }

        let wanted: Set<String> = AppLanguage.current.effectiveLanguageCode == "tr"
            ? ["tr", "tur"]
            : ["en", "eng"]
        if let match = infos.first(where: { info in
            guard let code = (info as? (any MediaPlayerTrack))?.languageCode?.lowercased() else { return false }
            return wanted.contains(code)
        }) {
            return match
        }
        return infos.first { $0.isEnabled } ?? infos.first
    }

    private static func menuTitle(info: any SubtitleInfo) -> String {
        if let track = info as? (any MediaPlayerTrack) {
            return menuTitle(track: track)
        }
        let name = info.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "\(L10n.subtitles) \(info.subtitleID)" : name
    }

    private static func menuTitle(track: any MediaPlayerTrack) -> String {
        let name = track.name.trimmingCharacters(in: .whitespaces)
        guard let language = track.language, !language.isEmpty else {
            return name.isEmpty ? "\(L10n.subtitles) \(track.trackID)" : name
        }
        // `name` dil kodundan türetilmiş olabiliyor; aynı bilgiyi iki kez
        // yazmamak için okunur adla karşılaştırılıyor.
        return name.isEmpty || name.caseInsensitiveCompare(language) == .orderedSame
            || name.caseInsensitiveCompare(track.languageCode ?? "") == .orderedSame
            ? language
            : "\(language) · \(name)"
    }
}
