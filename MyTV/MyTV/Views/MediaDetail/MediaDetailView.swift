import SwiftUI

public struct MediaDetailView: View {
    let initialItem: VODItem
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var playback = PlaybackManager.shared

    // Detailed metadata loaded on appear
    @State private var currentItem: VODItem
    @State private var cast: String?
    @State private var director: String?
    @State private var youtubeTrailer: String?

    // Series specific state
    @State private var episodes: [Episode] = []
    @State private var isLoadingDetails = false
    @State private var selectedSeason: Int = 1

    public init(item: VODItem) {
        self.initialItem = item
        self._currentItem = State(initialValue: item)
        self._cast = State(initialValue: item.cast)
        self._director = State(initialValue: item.director)
        self._youtubeTrailer = State(initialValue: item.youtubeTrailer)
    }

    private var isFav: Bool {
        storage.isFavorite(id: currentItem.id)
    }

    private var seasons: [Int] {
        Array(Set(episodes.map { $0.seasonNum })).sorted()
    }

    private var seasonEpisodes: [Episode] {
        episodes.filter { $0.seasonNum == selectedSeason }
    }

    private var relatedItems: [VODItem] {
        let pool = currentItem.type == .movie ? appState.movies : appState.series
        return pool.filter { $0.categoryId == currentItem.categoryId && $0.id != currentItem.id }.prefix(12).map { $0 }
    }

    private var genreList: [String] {
        guard let genre = currentItem.genre, !genre.isEmpty else { return [] }
        return genre
            .components(separatedBy: CharacterSet(charactersIn: ",/|•-"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count < 25 }
    }

    private var detectedLanguages: [String] {
        var tags: [String] = []
        let lowerName = currentItem.name.lowercased()

        if lowerName.contains("dual") || lowerName.contains("multi") {
            tags.append("Dual Ses")
        }
        if lowerName.contains("dublaj") || lowerName.contains("tr dub") || lowerName.contains("[tr]") || lowerName.contains("turkce") || lowerName.contains("türkçe") {
            tags.append("TR Dublaj")
        }
        if lowerName.contains("altyaz") || lowerName.contains("sub") || lowerName.contains("softsub") {
            tags.append("TR Altyazı")
        }
        if lowerName.contains("en") || lowerName.contains("eng") || lowerName.contains("english") {
            if !tags.contains("Dual Ses") && !tags.contains("TR Dublaj") {
                tags.append("Orijinal Dil")
            }
        }
        if tags.isEmpty {
            tags.append("Türkçe")
        }
        return tags
    }

    public var body: some View {
        GeometryReader { screenGeo in
            ZStack(alignment: .top) {
                // 1. Sticky Sabit Kapak Görseli (Ekrana tam oturan genişlik)
                stickyBackdropView(width: screenGeo.size.width)

                // 2. Kaydırılabilir İçerik & Beraberinde Kayan Karartma Gradyanı
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Logo, Başlık ve Poster Alanı
                        heroContent
                            .padding(.top, 220)
                            .padding(.bottom, 6)

                        // Oynat Butonu
                        actionButtons
                            .padding(.horizontal)

                        // Konu Özeti (Başlık ile)
                        if let plot = currentItem.overview, !plot.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(currentItem.name)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)

                                Text(plot)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(5)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal)
                        }

                        // Oyuncular ve Ekip
                        if (director != nil && !director!.isEmpty) || (cast != nil && !cast!.isEmpty) {
                            castAndCrewSection
                                .padding(.horizontal)
                        }

                        // Dizi Sezon ve Bölümleri
                        if currentItem.type == .series {
                            seriesEpisodesSection
                        }

                        // Benzer İçerikler
                        if !relatedItems.isEmpty {
                            MediaShelfRow(
                                title: "Benzer İçerikler",
                                items: relatedItems,
                                onPlay: { rel in
                                    playItem(rel)
                                }
                            )
                            .padding(.top, 4)
                        }
                    }
                    .padding(.bottom, 48)
                    .frame(width: screenGeo.size.width, alignment: .leading)
                    .background(
                        // Scroll ile beraber yukarı kayan dinamik karartma katmanı
                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.0), location: 0.0),
                                    .init(color: .black.opacity(0.35), location: 0.35),
                                    .init(color: .black.opacity(0.85), location: 0.72),
                                    .init(color: .black, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 380)

                            Color.black
                        }
                        .ignoresSafeArea(edges: .bottom)
                    )
                }
                .scrollEdgeEffectStyle(.soft, for: .all)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    storage.toggleFavorite(id: currentItem.id)
                } label: {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .foregroundStyle(isFav ? .red : .primary)
                }
            }
        }
        .task {
            await loadRichDetails()
        }
    }

    // MARK: - Sticky Backdrop View (Sabit Kapak)

    @ViewBuilder
    private func stickyBackdropView(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.black

            if let bgUrl = URL.fromUserString(currentItem.backdropUrl ?? currentItem.streamIcon) {
                CachedAsyncImage(url: bgUrl) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: 520)
                        .clipped()
                } placeholder: {
                    Color.white.opacity(0.04)
                }
            }

            // Üst kısımda geri tuşu ve durum çubuğu için çok hafif üst vinyet
            LinearGradient(
                colors: [Color.black.opacity(0.4), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: width, height: 100)
        }
        .frame(width: width, height: 520)
        .clipped()
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Hero Content (Floating Poster, Logo & Title)

    @ViewBuilder
    private var heroContent: some View {
        HStack(alignment: .bottom, spacing: 14) {
            // Yüzen Poster Kartı
            MediaPosterView(
                posterUrl: currentItem.streamIcon ?? currentItem.backdropUrl,
                title: currentItem.name,
                width: 95,
                height: 142,
                cornerRadius: 12,
                isSeries: currentItem.type == .series
            )
            .shadow(color: .black.opacity(0.85), radius: 12, x: 0, y: 6)

            // Logo, Başlık & Meta Bilgiler
            VStack(alignment: .leading, spacing: 6) {
                // İçerik Logosu
                if let iconUrl = URL.fromUserString(currentItem.streamIcon) {
                    CachedAsyncImage(url: iconUrl) { logo in
                        logo
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 34, alignment: .leading)
                            .shadow(color: .black.opacity(0.7), radius: 4)
                    } placeholder: {
                        EmptyView()
                    }
                }

                Text(currentItem.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(radius: 4)
                    .fixedSize(horizontal: false, vertical: true)

                // Meta Bilgi Rozetleri (Puan, Yapım Yılı, Süre, Dil Paketleri)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        if let rating = currentItem.rating, let score = Double(rating), score > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", score))
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.18), in: Capsule())
                        }

                        if let release = currentItem.releaseDate, !release.isEmpty {
                            Text(release.prefix(4))
                                .font(.system(size: 10.5, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.14), in: Capsule())
                                .foregroundStyle(.white)
                        }

                        if let dur = currentItem.duration, !dur.isEmpty && dur != "0" {
                            let durDisplay = dur.contains(":") ? dur : "\(dur) dk"
                            Text(durDisplay)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }

                        // Dil Paketleri Rozetleri
                        ForEach(detectedLanguages, id: \.self) { lang in
                            HStack(spacing: 3) {
                                Image(systemName: lang.contains("Altyazı") ? "captions.bubble.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 8))
                                Text(lang)
                                    .font(.system(size: 10.5, weight: .semibold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.25), in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.blue.opacity(0.4), lineWidth: 0.5)
                            )
                            .foregroundStyle(.white)
                        }
                    }
                }

                // Türler Rozetleri
                if !genreList.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(genreList, id: \.self) { g in
                                Text(g)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(Color.white.opacity(0.10), in: Capsule())
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Action Buttons (Glass Style)

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            if currentItem.type == .series {
                if let firstEp = seasonEpisodes.first ?? episodes.first {
                    playEpisode(firstEp)
                }
            } else {
                playItem(currentItem)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(currentItem.type == .series ? "1. Bölümü Oynat" : "Hemen İzle")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cast & Crew Section (İkonlu & Kapsayıcısız)

    @ViewBuilder
    private var castAndCrewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let director, !director.isEmpty {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(director)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let cast, !cast.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                        .padding(.top, 2)

                    Text(cast)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Series Episodes Section

    @ViewBuilder
    private var seriesEpisodesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
                .padding(.horizontal)

            Text("Sezonlar ve Bölümler")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .padding(.horizontal)

            // Seasons Picker Glass Pills
            if !seasons.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(seasons, id: \.self) { s in
                            let isSelected = (selectedSeason == s)
                            Button {
                                selectedSeason = s
                            } label: {
                                Text("Sezon \(s)")
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(isSelected ? Color.white.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 0.6)
                                    )
                                    .foregroundStyle(isSelected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Episode Cards List (Glass Card Style)
            if isLoadingDetails {
                HStack {
                    Spacer()
                    ProgressView("Bölümler yükleniyor...")
                        .padding()
                    Spacer()
                }
            } else if seasonEpisodes.isEmpty {
                Text("Bu sezona ait bölüm bulunamadı.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(seasonEpisodes) { ep in
                        Button {
                            playEpisode(ep)
                        } label: {
                            HStack(spacing: 12) {
                                // Episode Thumbnail / Artwork Preview
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.secondary.opacity(0.15))

                                    if let cover = ep.coverUrl, let url = URL.fromUserString(cover) {
                                        CachedAsyncImage(url: url) { img in
                                            img.resizable().aspectRatio(16/9, contentMode: .fill)
                                        } placeholder: {
                                            Image(systemName: "play.tv")
                                                .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        Image(systemName: "play.tv")
                                            .foregroundStyle(.secondary)
                                    }

                                    // Mini play overlay
                                    Circle()
                                        .fill(.black.opacity(0.5))
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.white)
                                        )
                                }
                                .frame(width: 76, height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(ep.episodeNum). \(ep.title)")
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)

                                    if let dur = ep.duration, !dur.isEmpty {
                                        Text("\(dur) dk")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }

                                    if let plot = ep.overview, !plot.isEmpty {
                                        Text(plot)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary.opacity(0.8))
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Actions & Loading

    private func loadRichDetails() async {
        guard let account = storage.activeAccount, account.type == .xtream else { return }
        isLoadingDetails = true

        if currentItem.type == .series {
            if let details = try? await XtreamCodesAPIService.shared.getSeriesDetails(account: account, seriesId: currentItem.id) {
                self.episodes = details.episodes
                self.cast = details.cast ?? self.cast
                self.director = details.director ?? self.director
                self.youtubeTrailer = details.youtubeTrailer ?? self.youtubeTrailer

                // Update backdrop / cover if richer image is available
                self.currentItem = VODItem(
                    id: currentItem.id,
                    name: currentItem.name,
                    streamIcon: details.cover ?? currentItem.streamIcon,
                    backdropUrl: details.backdropUrl ?? currentItem.backdropUrl,
                    rating: details.rating ?? currentItem.rating,
                    releaseDate: details.releaseDate ?? currentItem.releaseDate,
                    duration: currentItem.duration,
                    overview: details.plot ?? currentItem.overview,
                    streamUrl: currentItem.streamUrl,
                    categoryId: currentItem.categoryId,
                    type: currentItem.type,
                    containerExtension: currentItem.containerExtension,
                    genre: details.genre ?? currentItem.genre,
                    cast: details.cast,
                    director: details.director,
                    youtubeTrailer: details.youtubeTrailer
                )

                if let firstSeason = seasons.first {
                    self.selectedSeason = firstSeason
                }
            }
        } else {
            if let details = try? await XtreamCodesAPIService.shared.getVODInfo(account: account, vodId: currentItem.id) {
                self.cast = details.cast ?? self.cast
                self.director = details.director ?? self.director
                self.youtubeTrailer = details.youtubeTrailer ?? self.youtubeTrailer

                self.currentItem = VODItem(
                    id: currentItem.id,
                    name: currentItem.name,
                    streamIcon: details.movieImage ?? currentItem.streamIcon,
                    backdropUrl: details.backdropUrl ?? currentItem.backdropUrl,
                    rating: details.rating ?? currentItem.rating,
                    releaseDate: details.releaseDate ?? currentItem.releaseDate,
                    duration: details.duration ?? currentItem.duration,
                    overview: details.plot ?? currentItem.overview,
                    streamUrl: currentItem.streamUrl,
                    categoryId: currentItem.categoryId,
                    type: currentItem.type,
                    containerExtension: currentItem.containerExtension,
                    genre: details.genre ?? currentItem.genre,
                    cast: details.cast,
                    director: details.director,
                    youtubeTrailer: details.youtubeTrailer
                )
            }
        }

        isLoadingDetails = false
    }

    private func playItem(_ vod: VODItem) {
        let media = PlayableMedia(
            mediaId: vod.id,
            title: vod.name,
            subtitle: vod.genre ?? (vod.type == .movie ? "Film" : "Dizi"),
            posterUrl: vod.streamIcon ?? vod.backdropUrl,
            streamUrl: vod.streamUrl,
            contentType: vod.type,
            rating: vod.rating,
            releaseDate: vod.releaseDate,
            duration: vod.duration,
            overview: vod.overview,
            genre: vod.genre,
            director: director
        )
        playback.play(media: media)
        dismiss()
    }

    private func playEpisode(_ episode: Episode) {
        let media = PlayableMedia(
            mediaId: episode.id,
            title: currentItem.name,
            subtitle: "S\(episode.seasonNum):E\(episode.episodeNum) • \(episode.title)",
            posterUrl: episode.coverUrl ?? currentItem.streamIcon,
            streamUrl: episode.streamUrl,
            contentType: .series,
            rating: currentItem.rating,
            releaseDate: currentItem.releaseDate,
            duration: episode.duration ?? currentItem.duration,
            overview: episode.overview ?? currentItem.overview,
            genre: currentItem.genre,
            director: director,
            seriesId: currentItem.id,
            episodeNum: episode.episodeNum,
            seasonNum: episode.seasonNum
        )
        playback.play(media: media)
        dismiss()
    }
}
