import SwiftUI
import KSPlayer
import AVKit

public struct NativePlayerView: View {
    @ObservedObject private var playback = PlaybackManager.shared
    @ObservedObject private var appState = AppState.shared
    @Environment(\.dismiss) private var dismiss

    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var isPlaying: Bool = true
    @State private var playerState: KSPlayerState = .preparing
    @State private var currentPlaybackTime: TimeInterval = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var isControlsVisible: Bool = true
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: Double = 0
    @State private var hideControlsTask: Task<Void, Never>? = nil

    // Track Selection State
    @State private var selectedAudioTrackID: Int32? = nil
    @State private var selectedSubtitleID: String? = nil

    // Summary & Left Drawer State
    @State private var isSummaryExpanded: Bool = false
    @State private var showEpisodesDrawer: Bool = false
    @State private var seriesEpisodes: [Episode] = []
    @State private var isLoadingEpisodes: Bool = false
    @State private var selectedSeason: Int = 1
    @State private var selectedLiveCategoryId: String? = nil

    private let controlHeight: CGFloat = 44

    public init() {}

    private var seasons: [Int] {
        Array(Set(seriesEpisodes.map { $0.seasonNum })).sorted()
    }

    private var seasonEpisodes: [Episode] {
        seriesEpisodes.filter { $0.seasonNum == selectedSeason }
    }

    /// Slider üstündeki başlık: Dizilerde S1:B1 - "Bölüm Adı", Film ve canlı yayında doğrudan Film / Kanal adı.
    private var sliderEpisodeTitle: String {
        guard let media = playback.currentMedia else { return "" }
        if media.contentType == .series {
            let s = media.seasonNum ?? 1
            let e = media.episodeNum ?? 1
            let sePrefix = "S\(s):B\(e)"

            var rawTitle = ""
            if let currentEp = seriesEpisodes.first(where: { $0.episodeNum == media.episodeNum && $0.seasonNum == media.seasonNum }) {
                rawTitle = currentEp.title
            } else if let subtitle = media.subtitle, !subtitle.isEmpty {
                let parts = subtitle.components(separatedBy: "•").map { $0.trimmingCharacters(in: .whitespaces) }
                rawTitle = parts.count > 1 ? parts[1...].joined(separator: " • ") : parts[0]
            }

            let cleaned = cleanEpisodeName(title: rawTitle, episodeNum: e)
            if !cleaned.isEmpty && cleaned != "Bölüm \(e)" {
                return "\(sePrefix) - \(cleaned)"
            } else {
                return sePrefix
            }
        } else {
            return media.title
        }
    }

    private func cleanEpisodeName(title: String, episodeNum: Int) -> String {
        var cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^[Ss]\d+[\s:._-]*[EeBb]\d+[\s:._-]*"#,
            #"^[Ss]eason\s*\d+[\s:._-]*[Ee]pisode\s*\d+[\s:._-]*"#,
            #"^[Ss]ezon\s*\d+[\s:._-]*[Bb]ölüm\s*\d+[\s:._-]*"#,
            #"^[Ee]pisode\s*\d+[\s:._-]*"#,
            #"^[Bb]ölüm\s*\d+[\s:._-]*"#,
            #"^\d+\.\s*[Bb]ölüm[\s:._-]*"#,
            #"^-\s*"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: cleaned.utf16.count)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        while cleaned.hasPrefix("-") || cleaned.hasPrefix(":") || cleaned.hasPrefix("•") {
            cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return cleaned.isEmpty ? "Bölüm \(episodeNum)" : cleaned
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Color.black.ignoresSafeArea()

                if let url = playback.activePlayableURL {
                    // 1. Video Oynatıcı Katmanı
                    KSVideoPlayer(
                        coordinator: coordinator,
                        url: url,
                        options: playback.makeOptions()
                    )
                    .onStateChanged { _, state in
                        DispatchQueue.main.async {
                            self.playerState = state
                            if state == .readyToPlay || state == .bufferFinished {
                                self.isPlaying = true
                                if !self.isSummaryExpanded && !self.showEpisodesDrawer {
                                    self.scheduleControlsHide()
                                }
                            } else if state == .paused {
                                self.isPlaying = false
                                self.hideControlsTask?.cancel()
                            }
                        }
                    }
                    .onPlay { currentTime, totalTime in
                        DispatchQueue.main.async {
                            if !self.isScrubbing {
                                self.currentPlaybackTime = currentTime
                                self.totalDuration = totalTime
                            }
                        }
                    }
                    .ignoresSafeArea()

                    // 2. Video Alanı Dokunma ve Kaydırma Katmanı
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            if showEpisodesDrawer {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    showEpisodesDrawer = false
                                }
                            } else if isSummaryExpanded {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    isSummaryExpanded = false
                                }
                            } else {
                                toggleControlsVisibility()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 25)
                                .onEnded { value in
                                    if value.translation.height < -35 {
                                        openSummary()
                                    } else if value.translation.height > 35 {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            isSummaryExpanded = false
                                            showEpisodesDrawer = false
                                        }
                                    }
                                }
                        )

                    // 3. Apple Native Glass Kontroller Katmanı
                    if isControlsVisible {
                        controlsOverlay(geometry: geometry)
                            .transition(.opacity)
                            .zIndex(10)
                    }

                    // 4. Soldan Sağa Açılan, Tam Ekran Kaplamayan Saydam Glass Panel (Diziler için Bölümler, Canlı TV için Kanallar)
                    if showEpisodesDrawer {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    showEpisodesDrawer = false
                                }
                            }
                            .transition(.opacity)
                            .zIndex(25)

                        leftEpisodesDrawer(geometry: geometry)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .zIndex(30)
                    }
                }

                // Error Overlay
                if let error = playback.errorMessage {
                    errorOverlay(error: error)
                        .zIndex(40)
                }
            }
        }
        #if os(iOS)
        .ignoresSafeArea()
        .statusBarHidden(true)
        #endif
        .onAppear {
            scheduleControlsHide()
        }
        .onDisappear {
            hideControlsTask?.cancel()
            Task { @MainActor in
                playback.stop()
            }
        }
    }

    // MARK: - Main Controls Overlay

    private func controlsOverlay(geometry: GeometryProxy) -> some View {
        let isLandscape = geometry.size.width > geometry.size.height
        let horizontalPadding: CGFloat = isLandscape ? 68 : 20
        let topPadding: CGFloat = isLandscape ? 14 : 68
        let bottomPadding: CGFloat = isLandscape ? (isSummaryExpanded ? 8 : 16) : 24

        return ZStack {
            // Subtle backdrop gradients
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.75), Color.black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .ignoresSafeArea()

                Spacer()

                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: isSummaryExpanded ? (isLandscape ? 240 : 340) : 150)
                .ignoresSafeArea()
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // TOP BAR: Sol: PiP, Sağ: Çarpı Butonu
                topBar
                    .padding(.top, topPadding)
                    .padding(.horizontal, horizontalPadding)

                Spacer()

                // CENTER CONTROLS: Floating Glass Circles (Bilgi veya Panel açıkken gizlenir)
                if !isSummaryExpanded && !showEpisodesDrawer {
                    centerControls
                        .padding(.horizontal, horizontalPadding)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Spacer()

                // BOTTOM SECTION: Başlık + Slider + Bilgi Alanı
                bottomSection(geometry: geometry, isLandscape: isLandscape)
                    .padding(.bottom, bottomPadding)
                    .padding(.horizontal, horizontalPadding)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center) {
            // Sol: PiP Butonu (Cam Yuvarlak)
            Button {
                #if os(iOS)
                triggerHaptic(.light)
                #endif
                if let pip = coordinator.playerLayer?.player.pipController {
                    if pip.isPictureInPictureActive {
                        pip.stopPictureInPicture()
                    } else {
                        pip.startPictureInPicture()
                    }
                } else {
                    coordinator.isScaleAspectFill.toggle()
                }
                scheduleControlsHide()
            } label: {
                Image(systemName: "pip.enter")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: controlHeight, height: controlHeight)
            }
            .glassEffect(in: Circle())

            Spacer()

            // Sağ: Çarpı (Kapat) Butonu
            Button {
                #if os(iOS)
                triggerHaptic(.light)
                #endif
                playback.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: controlHeight, height: controlHeight)
            }
            .glassEffect(in: Circle())
        }
    }

    // MARK: - Center Controls (3 Floating Glass Circles)

    private var centerControls: some View {
        HStack(spacing: 42) {
            // 15 Saniye Geri
            Button {
                #if os(iOS)
                triggerHaptic(.medium)
                #endif
                coordinator.skip(interval: -15)
                scheduleControlsHide()
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .glassEffect(in: Circle())

            // Center Play / Pause
            Button {
                #if os(iOS)
                triggerHaptic(.medium)
                #endif
                if isPlaying {
                    coordinator.playerLayer?.pause()
                    isPlaying = false
                    hideControlsTask?.cancel()
                } else {
                    coordinator.playerLayer?.play()
                    isPlaying = true
                    scheduleControlsHide()
                }
            } label: {
                Group {
                    if playerState == .buffering || playerState == .preparing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.1)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: isPlaying ? 0 : 2)
                    }
                }
                .frame(width: 72, height: 72)
            }
            .glassEffect(in: Circle())

            // 15 Saniye İleri
            Button {
                #if os(iOS)
                triggerHaptic(.medium)
                #endif
                coordinator.skip(interval: 15)
                scheduleControlsHide()
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .glassEffect(in: Circle())
        }
    }

    // MARK: - Bottom Section (Başlık, Slider ve Altında Kayan Bilgi Alanı)

    private func bottomSection(geometry: GeometryProxy, isLandscape: Bool) -> some View {
        let isLive = (playback.currentMedia?.contentType == .live)

        return VStack(alignment: .leading, spacing: isLandscape ? (isSummaryExpanded ? 6 : 10) : 12) {
            // 1. ÜST SATIR: Başlık + Sağ Alt Kontrol Kapsülü
            HStack(alignment: .center) {
                Text(sliderEpisodeTitle)
                    .font(.system(size: isLandscape ? 16 : 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                // Sağ Alt Kontrol Kapsülü (Canlı TV ise sadece "Kanallar", Film/Dizi ise Hız/Ses/Bilgi/Altyazı)
                if isLive {
                    Button {
                        #if os(iOS)
                        triggerHaptic(.light)
                        #endif
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showEpisodesDrawer = true
                            isSummaryExpanded = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "tv")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Kanallar")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: isLandscape ? 34 : controlHeight)
                    }
                    .glassEffect(in: Capsule())
                } else {
                    HStack(spacing: 8) {
                        // 1. Oynatma Hızı
                        Menu {
                            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0] as [Float], id: \.self) { speed in
                                Button {
                                    #if os(iOS)
                                    triggerHaptic(.light)
                                    #endif
                                    coordinator.playbackRate = speed
                                    coordinator.playerLayer?.player.playbackRate = speed
                                    scheduleControlsHide()
                                } label: {
                                    HStack {
                                        Text("\(String(format: "%.2gx", speed))")
                                        if coordinator.playbackRate == speed {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "gauge.with.dots.needle.67percent")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }

                        // 2. Ses Dili / Parçası
                        Menu {
                            let tracks = coordinator.playerLayer?.player.tracks(mediaType: .audio) ?? []
                            if tracks.isEmpty {
                                Button {} label: {
                                    HStack {
                                        Text("Varsayılan Ses")
                                        Image(systemName: "checkmark")
                                    }
                                }
                            } else {
                                ForEach(tracks, id: \.trackID) { track in
                                    Button {
                                        #if os(iOS)
                                        triggerHaptic(.medium)
                                        #endif
                                        coordinator.playerLayer?.player.select(track: track)
                                        selectedAudioTrackID = track.trackID
                                        scheduleControlsHide()
                                    } label: {
                                        HStack {
                                            Text(track.name.isEmpty ? "Ses \(track.trackID)" : track.name)
                                            if selectedAudioTrackID == track.trackID || (selectedAudioTrackID == nil && track.isEnabled) {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "waveform")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }

                        // 3. Bilgi Butonu (Aç/Kapat)
                        Button {
                            #if os(iOS)
                            triggerHaptic(.light)
                            #endif
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                isSummaryExpanded.toggle()
                            }
                            if isSummaryExpanded {
                                hideControlsTask?.cancel()
                            } else {
                                scheduleControlsHide()
                            }
                        } label: {
                            Image(systemName: isSummaryExpanded ? "info.circle.fill" : "info.circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }

                        // 4. Altyazı Menüsü
                        Menu {
                            Button {
                                #if os(iOS)
                                triggerHaptic(.medium)
                                #endif
                                coordinator.subtitleModel.selectedSubtitleInfo = nil
                                selectedSubtitleID = nil
                                scheduleControlsHide()
                            } label: {
                                HStack {
                                    Text("Kapalı")
                                    if selectedSubtitleID == nil {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            let subtitles = coordinator.subtitleModel.subtitleInfos
                            if !subtitles.isEmpty {
                                ForEach(subtitles, id: \.subtitleID) { track in
                                    Button {
                                        #if os(iOS)
                                        triggerHaptic(.medium)
                                        #endif
                                        coordinator.subtitleModel.selectedSubtitleInfo = track
                                        selectedSubtitleID = track.subtitleID
                                        if let info = track as? MediaPlayerTrack {
                                            coordinator.playerLayer?.player.select(track: info)
                                        }
                                        scheduleControlsHide()
                                    } label: {
                                        HStack {
                                            Text(track.name)
                                            if selectedSubtitleID == track.subtitleID {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "captions.bubble")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: isLandscape ? 38 : controlHeight)
                    .glassEffect(in: Capsule())
                }
            }

            // 2. TIMELINE SLIDER: [Geçen Süre] [Slider] [-Kalan Süre]
            if isLive || totalDuration <= 0 {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)

                    Text("CANLI")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()
                }
            } else {
                HStack(spacing: 10) {
                    Text(formatTime(Int(isScrubbing ? scrubTime : currentPlaybackTime)))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(minWidth: 42, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { isScrubbing ? scrubTime : currentPlaybackTime },
                            set: { scrubTime = $0 }
                        ),
                        in: 0...max(1, totalDuration),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if editing {
                                hideControlsTask?.cancel()
                            } else {
                                coordinator.seek(time: scrubTime)
                                currentPlaybackTime = scrubTime
                                scheduleControlsHide()
                            }
                        }
                    )
                    .tint(.white)

                    let remaining = max(0, totalDuration - (isScrubbing ? scrubTime : currentPlaybackTime))
                    Text("-\(formatTime(Int(remaining)))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(minWidth: 46, alignment: .trailing)
                }
            }

            // 3. DOĞRUDAN SLIDER'IN ALTINDA AÇILAN BİLGİ ALANI (Genel İçerik Bilgileri)
            if isSummaryExpanded && !isLive {
                expandedAppleTVInfoSection(isLandscape: isLandscape)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - Expanded Apple TV Info Section (Genel İçerik Bilgileri)

    private func expandedAppleTVInfoSection(isLandscape: Bool) -> some View {
        Group {
            if let media = playback.currentMedia {
                if isLandscape {
                    landscapeInfoSection(media: media)
                } else {
                    portraitInfoSection(media: media)
                }
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: - Yatay (Landscape) Bilgi Düzeni (Kompakt, Genel İçerik Bilgisi)

    private func landscapeInfoSection(media: PlayableMedia) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // 1. Yatay Görsel (16:9 - Kompakt)
            if let posterUrl = media.posterUrl, let url = URL(string: posterUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .overlay(
                                Image(systemName: "film")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white.opacity(0.4))
                            )
                    }
                }
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
            }

            // 2. Orta Kısım: Genel İçerik Başlığı (media.title), Genel Özet ve Rozetler
            VStack(alignment: .leading, spacing: 3) {
                Text(media.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let plot = media.overview, !plot.isEmpty {
                    Text(plot)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineSpacing(1.5)
                        .lineLimit(2)
                }

                badgesView(media: media)
                    .padding(.top, 1)
            }

            Spacer(minLength: 8)

            // 3. Sağ Kısım: Kompakt Butonlar
            VStack(spacing: 6) {
                Button {
                    #if os(iOS)
                    triggerHaptic(.medium)
                    #endif
                    coordinator.seek(time: 0)
                    coordinator.playerLayer?.play()
                    isPlaying = true
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isSummaryExpanded = false
                    }
                    scheduleControlsHide()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Baştan")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 116, height: 34)
                }
                .glassEffect(in: Capsule())

                if media.contentType == .series {
                    Button {
                        #if os(iOS)
                        triggerHaptic(.light)
                        #endif
                        loadSeriesEpisodesIfNeeded()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showEpisodesDrawer = true
                            isSummaryExpanded = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 11, weight: .bold))
                            Text("Bölümler")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 116, height: 34)
                    }
                    .glassEffect(in: Capsule())
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Dikey (Portrait) Bilgi Düzeni (Genel İçerik Bilgisi)

    private func portraitInfoSection(media: PlayableMedia) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. Üst Satır: Yatay Görsel + Genel Başlık (media.title) & Rozetler
            HStack(alignment: .top, spacing: 12) {
                if let posterUrl = media.posterUrl, let url = URL(string: posterUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                        default:
                            Rectangle()
                                .fill(Color.white.opacity(0.12))
                                .overlay(
                                    Image(systemName: "film")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.white.opacity(0.4))
                                )
                        }
                    }
                    .frame(width: 110, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(media.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    badgesView(media: media)
                }

                Spacer(minLength: 0)
            }

            // 2. Açıklama: Genel özet alt satırda tam genişlik ile rahat okunur
            if let plot = media.overview, !plot.isEmpty {
                Text(plot)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineSpacing(2)
                    .lineLimit(3)
            }

            // 3. Butonlar: Alt satırda yan yana butonlar
            HStack(spacing: 12) {
                Button {
                    #if os(iOS)
                    triggerHaptic(.medium)
                    #endif
                    coordinator.seek(time: 0)
                    coordinator.playerLayer?.play()
                    isPlaying = true
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isSummaryExpanded = false
                    }
                    scheduleControlsHide()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Baştan")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                }
                .glassEffect(in: Capsule())

                if media.contentType == .series {
                    Button {
                        #if os(iOS)
                        triggerHaptic(.light)
                        #endif
                        loadSeriesEpisodesIfNeeded()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showEpisodesDrawer = true
                            isSummaryExpanded = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 12, weight: .bold))
                            Text("Bölümler")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                    }
                    .glassEffect(in: Capsule())
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Reusable Badges View

    @ViewBuilder
    private func badgesView(media: PlayableMedia) -> some View {
        HStack(spacing: 6) {
            if let genre = media.genre, !genre.isEmpty {
                Text(genre)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }

            if let releaseDate = media.releaseDate, !releaseDate.isEmpty {
                Text(releaseDate)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.70))
            }

            if let duration = media.duration, !duration.isEmpty {
                Text(duration)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.70))
            }

            if let rating = media.rating, !rating.isEmpty, rating != "0" {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                    Text(rating)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }

            if let director = media.director, !director.isEmpty {
                Text("Yönetmen: \(director)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Left Drawer (Canlı TV için Kanallar, Diziler için Bölümler)

    @ViewBuilder
    private func leftEpisodesDrawer(geometry: GeometryProxy) -> some View {
        if playback.currentMedia?.contentType == .live {
            liveChannelsDrawer(geometry: geometry)
        } else {
            seriesEpisodesDrawer(geometry: geometry)
        }
    }

    // MARK: - Canlı TV Kanal Listesi Drawer'ı

    private func liveChannelsDrawer(geometry: GeometryProxy) -> some View {
        let isLandscape = geometry.size.width > geometry.size.height
        let drawerWidth = min(360, geometry.size.width * (isLandscape ? 0.44 : 0.85))
        let topPad: CGFloat = isLandscape ? 16 : 64
        let bottomPad: CGFloat = isLandscape ? 16 : 36

        let currentChannel = appState.channels.first(where: { $0.id == playback.currentMedia?.mediaId })
        let defaultCategoryId = currentChannel?.categoryId ?? appState.liveCategories.first?.id ?? ""
        let activeCategoryId = selectedLiveCategoryId ?? defaultCategoryId
        let activeCategoryName = appState.liveCategories.first(where: { $0.id == activeCategoryId })?.name ?? "Kanallar"
        let categoryChannels = appState.channels.filter { $0.categoryId == activeCategoryId }
        let channelsToDisplay = categoryChannels.isEmpty ? appState.channels : categoryChannels

        return VStack(alignment: .leading, spacing: 14) {
            // Header: Kategori Adı, Kanal Sayısı ve Kapat Butonu
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeCategoryName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(channelsToDisplay.count) Kanal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                Button {
                    #if os(iOS)
                    triggerHaptic(.light)
                    #endif
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showEpisodesDrawer = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
                .glassEffect(in: Circle())
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            // Canlı TV Kategorileri (Yatay Haplar)
            if appState.liveCategories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appState.liveCategories) { cat in
                            let isSelected = (cat.id == activeCategoryId)
                            Button {
                                #if os(iOS)
                                triggerHaptic(.light)
                                #endif
                                selectedLiveCategoryId = cat.id
                            } label: {
                                Text(cat.name)
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? .black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        isSelected ? Color.white : Color.white.opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }

            // Kanal Listesi
            if channelsToDisplay.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("Kanal bulunamadı.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(channelsToDisplay) { ch in
                            let isCurrent = (ch.id == playback.currentMedia?.mediaId)

                            Button {
                                #if os(iOS)
                                triggerHaptic(.medium)
                                #endif
                                playSelectedChannel(ch)
                            } label: {
                                HStack(spacing: 12) {
                                    // Kanal Logosu
                                    ZStack {
                                        Color.white.opacity(0.08)

                                        if let icon = ch.streamIcon, let url = URL(string: icon) {
                                            AsyncImage(url: url) { phase in
                                                if let img = phase.image {
                                                    img.resizable().aspectRatio(contentMode: .fit)
                                                        .padding(4)
                                                } else {
                                                    Image(systemName: "tv")
                                                        .font(.system(size: 14))
                                                        .foregroundStyle(.white.opacity(0.5))
                                                }
                                            }
                                        } else {
                                            Image(systemName: "tv")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                    }
                                    .frame(width: 46, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))

                                    // Kanal Adı
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ch.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(isCurrent ? Color.yellow : .white)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    if isCurrent {
                                        Text("Oynatılıyor")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.yellow)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.yellow.opacity(0.20), in: Capsule())
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(isCurrent ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(width: drawerWidth)
        .frame(maxHeight: .infinity)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20))
        .padding(.leading, isLandscape ? 24 : 14)
        .padding(.top, topPad)
        .padding(.bottom, bottomPad)
        .shadow(color: Color.black.opacity(0.5), radius: 24, x: 8, y: 0)
    }

    // MARK: - Dizi Bölümler Drawer'ı

    private func seriesEpisodesDrawer(geometry: GeometryProxy) -> some View {
        let isLandscape = geometry.size.width > geometry.size.height
        let drawerWidth = min(360, geometry.size.width * (isLandscape ? 0.44 : 0.85))
        let topPad: CGFloat = isLandscape ? 16 : 64
        let bottomPad: CGFloat = isLandscape ? 16 : 36

        return VStack(alignment: .leading, spacing: 14) {
            // Header: Başlık, Dizi Adı ve Kapat Butonu
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bölümler")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    if let currentMedia = playback.currentMedia {
                        Text(currentMedia.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button {
                    #if os(iOS)
                    triggerHaptic(.light)
                    #endif
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showEpisodesDrawer = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
                .glassEffect(in: Circle())
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            // Sezonlar Sekmesi (Yatay Kaydırılabilir Haplar)
            if seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(seasons, id: \.self) { s in
                            Button {
                                #if os(iOS)
                                triggerHaptic(.light)
                                #endif
                                selectedSeason = s
                            } label: {
                                Text("Sezon \(s)")
                                    .font(.system(size: 12, weight: selectedSeason == s ? .bold : .medium))
                                    .foregroundStyle(selectedSeason == s ? .black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        selectedSeason == s ? Color.white : Color.white.opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }

            // Bölümler Listesi (Dikey Kaydırılabilir Glass Kartlar)
            if isLoadingEpisodes {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                }
                Spacer()
            } else if seasonEpisodes.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("Bölüm bulunamadı.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(seasonEpisodes) { ep in
                            let isCurrent = (playback.currentMedia?.episodeNum == ep.episodeNum && playback.currentMedia?.seasonNum == ep.seasonNum)
                            let epName = cleanEpisodeName(title: ep.title, episodeNum: ep.episodeNum)
                            let displayEpisodeText = (epName == "Bölüm \(ep.episodeNum)" ? "Bölüm \(ep.episodeNum)" : "Bölüm \(ep.episodeNum): \(epName)")

                            Button {
                                #if os(iOS)
                                triggerHaptic(.medium)
                                #endif
                                if let currentMedia = playback.currentMedia {
                                    playSelectedEpisode(ep, media: currentMedia)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    // Önizleme veya Oynat İkonu
                                    ZStack {
                                        if let cover = ep.coverUrl, let url = URL(string: cover) {
                                            AsyncImage(url: url) { phase in
                                                if let img = phase.image {
                                                    img.resizable().aspectRatio(16/9, contentMode: .fill)
                                                } else {
                                                    Color.white.opacity(0.08)
                                                }
                                            }
                                        } else {
                                            Color.white.opacity(0.08)
                                        }

                                        Image(systemName: isCurrent ? "play.circle.fill" : "play.fill")
                                            .font(.system(size: isCurrent ? 20 : 14))
                                            .foregroundStyle(isCurrent ? Color.yellow : Color.white.opacity(0.85))
                                    }
                                    .frame(width: 64, height: 38)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))

                                    // Bilgiler
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(displayEpisodeText)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(isCurrent ? Color.yellow : .white)
                                            .lineLimit(1)

                                        if let duration = ep.duration, !duration.isEmpty {
                                            Text(duration)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.white.opacity(0.60))
                                        }
                                    }

                                    Spacer()

                                    if isCurrent {
                                        Text("Oynatılıyor")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.yellow)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.yellow.opacity(0.20), in: Capsule())
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(isCurrent ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(width: drawerWidth)
        .frame(maxHeight: .infinity)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20))
        .padding(.leading, isLandscape ? 24 : 14)
        .padding(.top, topPad)
        .padding(.bottom, bottomPad)
        .shadow(color: Color.black.opacity(0.5), radius: 24, x: 8, y: 0)
    }

    // MARK: - Actions

    private func openSummary() {
        guard playback.currentMedia?.contentType != .live else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            isSummaryExpanded = true
            hideControlsTask?.cancel()
        }
        loadSeriesEpisodesIfNeeded()
    }

    private func loadSeriesEpisodesIfNeeded() {
        guard let media = playback.currentMedia, media.contentType == .series else { return }
        guard seriesEpisodes.isEmpty else { return }
        let seriesId = media.seriesId ?? media.mediaId
        guard let account = StorageManager.shared.activeAccount, account.type == .xtream else { return }

        isLoadingEpisodes = true
        Task {
            let list = (try? await XtreamCodesAPIService.shared.getSeriesInfo(account: account, seriesId: seriesId)) ?? []
            await MainActor.run {
                self.seriesEpisodes = list
                if let currentSeason = media.seasonNum {
                    self.selectedSeason = currentSeason
                } else if let firstSeason = seasons.first {
                    self.selectedSeason = firstSeason
                }
                self.isLoadingEpisodes = false
            }
        }
    }

    private func playSelectedEpisode(_ ep: Episode, media: PlayableMedia) {
        let newMedia = PlayableMedia(
            mediaId: ep.id,
            title: media.title,
            subtitle: "S\(ep.seasonNum):E\(ep.episodeNum) • \(ep.title)",
            posterUrl: media.posterUrl,
            streamUrl: ep.streamUrl,
            contentType: .series,
            rating: media.rating,
            releaseDate: media.releaseDate,
            duration: ep.duration ?? media.duration,
            overview: media.overview,
            genre: media.genre,
            director: media.director,
            seriesId: media.seriesId ?? media.mediaId,
            episodeNum: ep.episodeNum,
            seasonNum: ep.seasonNum
        )
        playback.play(media: newMedia)
    }

    private func playSelectedChannel(_ ch: Channel) {
        let media = PlayableMedia(
            mediaId: ch.id,
            title: ch.name,
            subtitle: "Canlı Yayın",
            posterUrl: ch.streamIcon,
            streamUrl: ch.streamUrl,
            contentType: .live
        )
        playback.play(media: media)
    }

    // MARK: - Error Overlay

    private func errorOverlay(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)

            Text("Yayın Hatası")
                .font(.headline.bold())
                .foregroundStyle(.white)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 12) {
                Button("Yeniden Dene") {
                    playback.retry()
                }
                .buttonStyle(.borderedProminent)

                Button("Kapat") {
                    playback.stop()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(28)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }

    // MARK: - Helpers

    private func toggleControlsVisibility() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isControlsVisible.toggle()
        }
        if isControlsVisible {
            scheduleControlsHide()
        } else {
            hideControlsTask?.cancel()
        }
    }

    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        guard isPlaying && !isSummaryExpanded && !showEpisodesDrawer else { return }
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                isControlsVisible = false
            }
        }
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    #if os(iOS)
    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    #endif
}
