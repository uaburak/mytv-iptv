import SwiftUI
import KSPlayer
import AVKit

public struct NativePlayerView: View {
    @ObservedObject private var playback = PlaybackManager.shared
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
    @State private var volume: Float = 1.0
    @State private var showShareSheet: Bool = false

    // Track Selection State
    @State private var selectedAudioTrackID: Int32? = nil
    @State private var selectedSubtitleID: String? = nil

    // Summary & Left Episodes Drawer State
    @State private var isSummaryExpanded: Bool = false
    @State private var showLeftEpisodesDrawer: Bool = false
    @State private var seriesEpisodes: [Episode] = []
    @State private var isLoadingEpisodes: Bool = false
    @State private var selectedSeason: Int = 1

    // Standart Kapsül & Buton Yüksekliği (44pt)
    private let controlHeight: CGFloat = 44

    public init() {}

    private var seasons: [Int] {
        Array(Set(seriesEpisodes.map { $0.seasonNum })).sorted()
    }

    private var seasonEpisodes: [Episode] {
        seriesEpisodes.filter { $0.seasonNum == selectedSeason }
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
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
                                if !self.isSummaryExpanded && !self.showLeftEpisodesDrawer {
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

                    // 2. Video Alanı Arka Plan Dokunma & Kaydırma Katmanı
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            if showLeftEpisodesDrawer {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    showLeftEpisodesDrawer = false
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
                                        // Yukarı kaydırınca Başlık/Slider yukarı kayar ve Bilgi alanı açılır
                                        openSummary()
                                    } else if value.translation.height > 35 {
                                        // Aşağı kaydırınca kapanır
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            isSummaryExpanded = false
                                            showLeftEpisodesDrawer = false
                                        }
                                    }
                                }
                        )

                    // 3. Apple Native Glass Kontroller Katmanı (Başlık + Slider + Bilgi Alanı)
                    if isControlsVisible {
                        controlsOverlay(geometry: geometry)
                            .transition(.opacity)
                            .zIndex(10)
                    }

                    // 4. EKRANIN SOLUNDAN GELEN BÖLÜMLER ALANI (Kapsayıcısız, Doğal Soldan Akış)
                    if showLeftEpisodesDrawer {
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
        #if os(iOS)
        .sheet(isPresented: $showShareSheet) {
            if let url = playback.activePlayableURL {
                ShareActivityView(activityItems: [playback.currentMedia?.title ?? "Video", url])
            }
        }
        #endif
        .onAppear {
            volume = coordinator.playbackVolume
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
        ZStack {
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
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: isSummaryExpanded ? 300 : 150)
                .ignoresSafeArea()
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // TOP BAR: Close + [PiP, AirPlay, Share] (Left) & [Volume Slider] (Right)
                topBar

                Spacer()

                // CENTER CONTROLS: Floating Glass Circles (Gizlenir eğer bilgi veya bölümler açıksa)
                if !isSummaryExpanded && !showLeftEpisodesDrawer {
                    centerControls
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Spacer()

                // BOTTOM SECTION: Başlık + Slider Asla Gizlenmez, Bilgi Doğrudan Altına Eklenir
                bottomSection(geometry: geometry)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 14) {
            // Left: Close Button (Glass Circle Button - 44x44)
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

            // Left: Top Actions Glass Capsule [PiP, AirPlay, Share] - Height: 44
            HStack(spacing: 20) {
                // PiP Button
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
                }

                // AirPlay Button
                AirPlayView()
                    .frame(width: 20, height: 20)
                    .tint(.white)

                // Share Button
                Button {
                    #if os(iOS)
                    triggerHaptic(.light)
                    showShareSheet = true
                    #endif
                    scheduleControlsHide()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: controlHeight)
            .glassEffect(in: Capsule())

            Spacer()

            // Right: Volume Glass Capsule [Slider + Speaker] - Height: 44
            HStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { volume },
                        set: { newVol in
                            volume = newVol
                            coordinator.playbackVolume = newVol
                            coordinator.isMuted = (newVol == 0)
                        }
                    ),
                    in: 0...1
                )
                .tint(.white)
                .frame(width: 110)

                Button {
                    #if os(iOS)
                    triggerHaptic(.light)
                    #endif
                    coordinator.isMuted.toggle()
                    if coordinator.isMuted {
                        volume = 0
                    } else {
                        volume = coordinator.playbackVolume > 0 ? coordinator.playbackVolume : 1.0
                    }
                    scheduleControlsHide()
                } label: {
                    Image(systemName: (coordinator.isMuted || volume == 0) ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: controlHeight)
            .glassEffect(in: Capsule())
        }
    }

    // MARK: - Center Controls (3 Floating Glass Circles)

    private var centerControls: some View {
        HStack(spacing: 42) {
            // 15 Saniye Geri (Glass Circle - 56x56)
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

            // Center Play / Pause (Glass Circle - 72x72)
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

            // 15 Saniye İleri (Glass Circle - 56x56)
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

    private func bottomSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. ÜST SATIR: Başlık + Sağ Alt Kontrol Kapsülü [Hız, Ses, Bilgi, Altyazı]
            HStack(alignment: .center) {
                Text(playback.currentMedia?.title ?? "")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                // Sağ Alt Kontrol Kapsülü
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: controlHeight)
                .glassEffect(in: Capsule())
            }

            // 2. TIMELINE SLIDER (AYNI HİZADA: [Geçen Süre] [Slider] [-Kalan Süre])
            let isLive = (playback.currentMedia?.contentType == .live) || (totalDuration <= 0)

            if isLive {
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
                HStack(spacing: 12) {
                    Text(formatTime(Int(isScrubbing ? scrubTime : currentPlaybackTime)))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(minWidth: 44, alignment: .leading)

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
                        .frame(minWidth: 48, alignment: .trailing)
                }
            }

            // 3. DOĞRUDAN SLIDER'IN ALTINDA AÇILAN APPLE TV BİLGİ ALANI (Butonlar kaldırıldı, doğrudan içerik)
            if isSummaryExpanded {
                expandedAppleTVInfoSection
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - Expanded Apple TV Info Section (Bilgi / İzlemeyi Sürdür Butonları Kaldırıldı)

    private var expandedAppleTVInfoSection: some View {
        Group {
            if let media = playback.currentMedia {
                HStack(alignment: .top, spacing: 18) {
                    // SOL: Kapak Resmi (Poster)
                    if let posterUrl = media.posterUrl, let url = URL(string: posterUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(2/3, contentMode: .fill)
                            default:
                                Rectangle()
                                    .fill(Color.white.opacity(0.12))
                                    .overlay(
                                        Image(systemName: "film")
                                            .font(.system(size: 24))
                                            .foregroundStyle(.white.opacity(0.4))
                                    )
                            }
                        }
                        .frame(width: 86, height: 124)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                    }

                    // ORTA: Başlık, Açıklama ve Apple TV Rozetleri
                    VStack(alignment: .leading, spacing: 6) {
                        Text(media.title)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let plot = media.overview, !plot.isEmpty {
                            Text(plot)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineSpacing(2)
                                .lineLimit(3)
                        }

                        // Rozetler Satırı
                        HStack(spacing: 8) {
                            let genreText = media.genre ?? "Film"
                            let durationText = media.duration != nil ? " • \(media.duration!)" : ""
                            Text("\(genreText)\(durationText)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.70))

                            if let rating = media.rating, !rating.isEmpty, rating != "0" {
                                HStack(spacing: 3) {
                                    Text("🍅")
                                        .font(.system(size: 10))
                                    Text("%\(Int((Double(rating) ?? 0) * 10))")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }

                            Text("4K")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))

                            HStack(spacing: 2) {
                                Image(systemName: "opticaldisc")
                                    .font(.system(size: 8))
                                Text("Dolby")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))

                            Text("13+")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .overlay(
                                    Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                                )

                            Text("CC")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2).strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                                )

                            Text("AD")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2).strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                                )
                        }
                        .padding(.top, 2)
                    }

                    Spacer()

                    // SAĞ: [Baştan] ve [Bölümler / Filme Git] Butonları
                    VStack(spacing: 10) {
                        // 1. Baştan Oynat Butonu
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
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Baştan")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(width: 150, height: 44)
                        }
                        .glassEffect(in: Capsule())

                        // 2. Dizi ise: "Bölümler" (Ekranın Solundan Açar), Film ise: "Filme Git"
                        if media.contentType == .series {
                            Button {
                                #if os(iOS)
                                triggerHaptic(.light)
                                #endif
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    showLeftEpisodesDrawer = true
                                }
                                loadSeriesEpisodesIfNeeded()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "list.bullet")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("Bölümler")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .frame(width: 150, height: 44)
                            }
                            .glassEffect(in: Capsule())
                        } else {
                            Button {
                                #if os(iOS)
                                triggerHaptic(.light)
                                #endif
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    isSummaryExpanded = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Filme Git")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .frame(width: 150, height: 44)
                            }
                            .glassEffect(in: Capsule())
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Left Episodes Drawer (EKRANIN SOLUNDAN KAYARAK GELEN DOĞAL BÖLÜMLER ALANI - KAPSAYICISIZ)

    private func leftEpisodesDrawer(geometry: GeometryProxy) -> some View {
        let drawerWidth = min(380, geometry.size.width * 0.88)

        return VStack(alignment: .leading, spacing: 14) {
            // Header: Başlık ve Kapat Butonu
            HStack {
                Text("Bölümler")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    #if os(iOS)
                    triggerHaptic(.light)
                    #endif
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showLeftEpisodesDrawer = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.70))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Sezonlar Sekmeleri (Yatay Kaydırılabilir)
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
                                    .font(.system(size: 13, weight: selectedSeason == s ? .bold : .medium))
                                    .foregroundStyle(selectedSeason == s ? .black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(selectedSeason == s ? Color.white : Color.white.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            // Bölümler Listesi (Dikey Kaydırılabilir)
            if isLoadingEpisodes {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(seasonEpisodes) { ep in
                            let isCurrent = (playback.currentMedia?.episodeNum == ep.episodeNum && playback.currentMedia?.seasonNum == ep.seasonNum)

                            Button {
                                #if os(iOS)
                                triggerHaptic(.medium)
                                #endif
                                if let currentMedia = playback.currentMedia {
                                    playSelectedEpisode(ep, media: currentMedia)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: isCurrent ? "play.circle.fill" : "play.circle")
                                        .font(.system(size: 24))
                                        .foregroundStyle(isCurrent ? .yellow : .white.opacity(0.80))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Bölüm \(ep.episodeNum): \(ep.title)")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.white)
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
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.yellow.opacity(0.20), in: Capsule())
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(isCurrent ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(width: drawerWidth)
        .frame(maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.85), Color.black.opacity(0.60)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Actions

    private func openSummary() {
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
        guard isPlaying && !isSummaryExpanded && !showLeftEpisodesDrawer else { return }
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

#if os(iOS)
// MARK: - Share Activity Sheet Wrapper
private struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
