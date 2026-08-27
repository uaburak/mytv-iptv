import SwiftUI

public struct MediaDetailView: View {
    let initialItem: VODItem
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var playback = PlaybackManager.shared

    // Detailed metadata loaded on appear
    @State private var currentItem: VODItem
    @State private var clearLogoUrl: String?
    @State private var cast: String?
    @State private var director: String?
    @State private var youtubeTrailer: String?

    // Series specific state
    @State private var episodes: [Episode] = []
    @State private var seasonInfos: [SeasonInfo] = []
    @State private var isLoadingDetails = false
    @State private var selectedSeason: Int = 1

    public init(item: VODItem) {
        self.initialItem = item
        self._currentItem = State(initialValue: item)
        self._cast = State(initialValue: item.cast)
        self._director = State(initialValue: item.director)
        self._youtubeTrailer = State(initialValue: item.youtubeTrailer)

        let cached = TMDBService.shared.cachedMetadata(title: item.name, isSeries: item.type == .series)
        self._clearLogoUrl = State(initialValue: cached?.logoUrl)
    }

    private var isFav: Bool {
        storage.isFavorite(id: currentItem.id)
    }

    private var seasons: [Int] {
        if !seasonInfos.isEmpty {
            return seasonInfos.map { $0.seasonNumber }.sorted()
        }
        return Array(Set(episodes.map { $0.seasonNum })).sorted()
    }

    private var seasonEpisodes: [Episode] {
        episodes.filter { $0.seasonNum == selectedSeason }
    }

    private var currentPosterUrl: String? {
        if currentItem.type == .series,
           let sCover = seasonInfos.first(where: { $0.seasonNumber == selectedSeason })?.cover,
           !sCover.isEmpty {
            return sCover
        }
        return currentItem.streamIcon ?? currentItem.backdropUrl
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

    public var body: some View {
        GeometryReader { screenGeo in
            ZStack(alignment: .top) {
                // 1. Sticky Sabit Kapak Görseli
                stickyBackdropView(width: screenGeo.size.width)

                // 2. Kaydırılabilir İçerik
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Afiş ve Yanındaki Büyük Puan / Meta Bilgiler
                        heroContent
                            .padding(.top, 220)
                            .padding(.bottom, 6)

                        // 3. Bölümü / Filmi İzle Butonu
                        actionButtons
                            .padding(.horizontal)

                        // 4. İçerik İsmi, Konu Özeti, Yönetmen ve Oyuncular
                        storylineAndCastSection
                            .padding(.horizontal)

                        // 5. Dizi Sezon ve Bölümleri
                        if currentItem.type == .series {
                            seriesEpisodesSection
                        }

                        // 6. Benzer İçerikler
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
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                favoriteToolbarButton
            }
            #else
            ToolbarItem(placement: .topBarTrailing) {
                favoriteToolbarButton
            }
            #endif
        }
        .task {
            await loadRichDetails()
        }
    }

    @ViewBuilder
    private var favoriteToolbarButton: some View {
        Button {
            storage.toggleFavorite(id: currentItem.id)
        } label: {
            Image(systemName: isFav ? "heart.fill" : "heart")
                .foregroundStyle(isFav ? .red : .primary)
        }
    }

    // MARK: - Sticky Backdrop View (Sabit Yatay Kapak)

    @ViewBuilder
    private func stickyBackdropView(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.black

            if let bg = currentItem.backdropUrl ?? currentItem.streamIcon, let bgUrl = URL.fromUserString(bg) {
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

    // MARK: - Hero Content (Floating Poster & Big Rating + Metas)

    @ViewBuilder
    private var heroContent: some View {
        HStack(alignment: .bottom, spacing: 14) {
            // Sol: Yüzen Dikey Afiş (Kartlardakiyle Birebir Aynı Orijinal Afiş)
            MediaPosterView(
                posterUrl: initialItem.streamIcon ?? initialItem.backdropUrl,
                title: currentItem.name,
                width: 102,
                height: 152,
                cornerRadius: 12,
                isSeries: currentItem.type == .series
            )
            .shadow(color: .black.opacity(0.85), radius: 12, x: 0, y: 6)

            // Sağ: Logo, Büyük Puan ve Dinamik Meta Bilgileri
            VStack(alignment: .leading, spacing: 6) {
                // 1. Şeffaf Başlık Logosu (ClearLogo - PNG)
                if let logoStr = clearLogoUrl, let logoUrl = URL.fromUserString(logoStr) {
                    AsyncImage(url: logoUrl) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 160, maxHeight: 42, alignment: .leading)
                                .shadow(color: .black.opacity(0.9), radius: 6)
                        } else {
                            EmptyView()
                        }
                    }
                }

                // 2. Büyük IMDb / TMDB Puanı (Üstte)
                if let rating = currentItem.rating, let score = Double(rating), score > 0 {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", score))
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("/10")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                // 3. Birinci Dinamik Satır (Yıl, Ülke, Yaş Sınırı, Süre, Fragman)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        if let release = currentItem.releaseDate, !release.isEmpty {
                            Text(release.prefix(4))
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(.white)
                        }

                        if let country = currentItem.country, !country.isEmpty {
                            Text(country)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                        }

                        if let age = currentItem.age ?? currentItem.mpaaRating, !age.isEmpty {
                            Text(age)
                                .font(.system(size: 10.5, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2.5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.8)
                                )
                                .foregroundStyle(.white)
                        }

                        if let dur = currentItem.duration, !dur.isEmpty && dur != "0" {
                            let durDisplay = dur.contains(":") ? dur : "\(dur) dk"
                            Text(durDisplay)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }

                        if let trailer = currentItem.youtubeTrailer, !trailer.isEmpty, let trailerUrl = URL(string: "https://www.youtube.com/watch?v=\(trailer)") {
                            Link(destination: trailerUrl) {
                                HStack(spacing: 3) {
                                    Image(systemName: "play.rectangle.fill")
                                        .font(.system(size: 9))
                                    Text("Fragman")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.3), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.red.opacity(0.5), lineWidth: 0.6)
                                )
                                .foregroundStyle(.white)
                            }
                        }
                    }
                }

                // 4. İkinci Dinamik Satır (Tür Rozetleri)
                if !genreList.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(genreList, id: \.self) { g in
                                Text(g)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
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

    // MARK: - Action Buttons (Hemen İzle / 1. Bölümü Oynat)

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

    // MARK: - Storyline, Director & Cast Section

    @ViewBuilder
    private var storylineAndCastSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // İçerik İsmi & Konu Özeti
            VStack(alignment: .leading, spacing: 6) {
                Text(currentItem.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                if let plot = currentItem.overview, !plot.isEmpty {
                    Text(plot)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Yönetmen & Oyuncular
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
        }
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

            // Seasons Picker Glass Cards With Cover Art
            if !seasons.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(seasons, id: \.self) { s in
                            let isSelected = (selectedSeason == s)
                            let sInfo = seasonInfos.first(where: { $0.seasonNumber == s })
                            Button {
                                selectedSeason = s
                            } label: {
                                HStack(spacing: 8) {
                                    if let cover = sInfo?.cover, let coverUrl = URL.fromUserString(cover) {
                                        CachedAsyncImage(url: coverUrl) { img in
                                            img
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 22, height: 30)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        } placeholder: {
                                            Color.white.opacity(0.08)
                                                .frame(width: 22, height: 30)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(sInfo?.name ?? "Sezon \(s)")
                                            .font(.system(size: 11.5, weight: isSelected ? .bold : .semibold))

                                        let epCount = sInfo?.episodeCount ?? episodes.filter { $0.seasonNum == s }.count
                                        if epCount > 0 {
                                            Text("\(epCount) Bölüm")
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        guard !isLoadingDetails else { return }
        isLoadingDetails = true

        // 1. TMDB'den Şeffaf Logo (ClearLogo) çek (Arka planı zıplatmadan sadece logo ve ek bilgileri zenginleştirir)
        let tmdb = await TMDBService.shared.getMetadata(title: currentItem.name, isSeries: currentItem.type == .series)
        if let logo = tmdb?.logoUrl {
            self.clearLogoUrl = logo
        }

        // Eğer mevcut kapak yoksa TMDB'den yatay kapak ata
        if currentItem.backdropUrl == nil || currentItem.backdropUrl?.isEmpty == true {
            if let bg = tmdb?.backdropUrl {
                self.currentItem = VODItem(
                    id: currentItem.id,
                    name: currentItem.name,
                    streamIcon: currentItem.streamIcon,
                    backdropUrl: bg,
                    rating: currentItem.rating ?? (tmdb?.rating != nil ? String(format: "%.1f", tmdb!.rating!) : nil),
                    releaseDate: currentItem.releaseDate,
                    duration: currentItem.duration,
                    overview: currentItem.overview ?? tmdb?.overview,
                    streamUrl: currentItem.streamUrl,
                    categoryId: currentItem.categoryId,
                    type: currentItem.type,
                    containerExtension: currentItem.containerExtension,
                    genre: currentItem.genre
                )
            }
        }

        // 2. Xtream Detaylarını Yükle (Bölümler, cast, yönetmen, fragman)
        guard let account = storage.activeAccount, account.type == .xtream else {
            isLoadingDetails = false
            return
        }

        if currentItem.type == .series {
            if let details = try? await XtreamCodesAPIService.shared.getSeriesDetails(account: account, seriesId: currentItem.id) {
                self.episodes = details.episodes
                self.seasonInfos = details.seasons
                self.cast = details.cast ?? self.cast
                self.director = details.director ?? self.director
                self.youtubeTrailer = details.youtubeTrailer ?? self.youtubeTrailer

                // Mevcut arka planı koru, sadece yoksa ekle
                let finalBackdrop = currentItem.backdropUrl ?? details.backdropUrl ?? tmdb?.backdropUrl
                self.currentItem = VODItem(
                    id: currentItem.id,
                    name: currentItem.name,
                    streamIcon: initialItem.streamIcon ?? details.cover ?? currentItem.streamIcon,
                    backdropUrl: finalBackdrop,
                    rating: (currentItem.rating != nil && currentItem.rating != "0") ? currentItem.rating : details.rating,
                    releaseDate: details.releaseDate ?? currentItem.releaseDate,
                    duration: currentItem.duration,
                    overview: (details.plot?.isEmpty == false ? details.plot : currentItem.overview),
                    streamUrl: currentItem.streamUrl,
                    categoryId: currentItem.categoryId,
                    type: currentItem.type,
                    containerExtension: currentItem.containerExtension,
                    genre: details.genre ?? currentItem.genre,
                    cast: details.cast ?? self.cast,
                    director: details.director ?? self.director,
                    youtubeTrailer: details.youtubeTrailer ?? self.youtubeTrailer,
                    country: details.country ?? currentItem.country,
                    age: details.age ?? currentItem.age,
                    mpaaRating: details.mpaaRating ?? currentItem.mpaaRating
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

                let finalBackdrop = currentItem.backdropUrl ?? details.backdropUrl ?? tmdb?.backdropUrl
                self.currentItem = VODItem(
                    id: currentItem.id,
                    name: currentItem.name,
                    streamIcon: initialItem.streamIcon ?? details.movieImage ?? currentItem.streamIcon,
                    backdropUrl: finalBackdrop,
                    rating: (currentItem.rating != nil && currentItem.rating != "0") ? currentItem.rating : details.rating,
                    releaseDate: details.releaseDate ?? currentItem.releaseDate,
                    duration: details.duration ?? currentItem.duration,
                    overview: (details.plot?.isEmpty == false ? details.plot : currentItem.overview),
                    streamUrl: currentItem.streamUrl,
                    categoryId: currentItem.categoryId,
                    type: currentItem.type,
                    containerExtension: currentItem.containerExtension,
                    genre: details.genre ?? currentItem.genre,
                    cast: details.cast ?? self.cast,
                    director: details.director ?? self.director,
                    youtubeTrailer: details.youtubeTrailer ?? self.youtubeTrailer,
                    country: details.country ?? currentItem.country,
                    age: details.age ?? currentItem.age,
                    mpaaRating: details.mpaaRating ?? currentItem.mpaaRating
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
