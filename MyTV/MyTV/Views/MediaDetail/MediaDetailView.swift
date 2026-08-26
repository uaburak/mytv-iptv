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

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // 1. Cinematic Hero Header with Backdrop & Artwork
                heroHeader

                // 2. Action Buttons (Glass Style)
                actionButtons
                    .padding(.horizontal)

                // 3. Storyline / Overview
                if let plot = currentItem.overview, !plot.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Konu Özeti")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(plot)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(5)
                    }
                    .padding(.horizontal)
                }

                // 4. Cast & Crew Details
                if (director != nil && !director!.isEmpty) || (cast != nil && !cast!.isEmpty) {
                    castAndCrewSection
                        .padding(.horizontal)
                }

                // 5. Series Seasons & Episodes (Only for Series)
                if currentItem.type == .series {
                    seriesEpisodesSection
                }

                // 6. Related Content Shelf
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
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationTitle(currentItem.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadRichDetails()
        }
    }

    // MARK: - Cinematic Hero Header

    @ViewBuilder
    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            // High Resolution Backdrop Banner
            GeometryReader { geo in
                ZStack {
                    Color.black

                    if let bgUrl = URL.fromUserString(currentItem.backdropUrl ?? currentItem.streamIcon) {
                        CachedAsyncImage(url: bgUrl) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: 290)
                                .clipped()
                        } placeholder: {
                            Color.white.opacity(0.04)
                        }
                    }
                }
            }
            .frame(height: 290)

            // Multi-stop Cinematic Gradient Mask
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.1), location: 0.0),
                    .init(color: .black.opacity(0.45), location: 0.5),
                    .init(color: .black.opacity(0.95), location: 0.9),
                    .init(color: .black, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 290)

            // Floating Artwork & Metadata
            HStack(alignment: .bottom, spacing: 16) {
                // High Quality Floating Poster Card
                MediaPosterView(
                    posterUrl: currentItem.streamIcon ?? currentItem.backdropUrl,
                    title: currentItem.name,
                    width: 100,
                    height: 150,
                    cornerRadius: 12,
                    isSeries: currentItem.type == .series
                )
                .shadow(color: .black.opacity(0.7), radius: 10, x: 0, y: 5)

                // Title & Chips
                VStack(alignment: .leading, spacing: 6) {
                    Text(currentItem.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(radius: 4)

                    // Meta Chips Bar
                    HStack(spacing: 6) {
                        Text(currentItem.type.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Color.white.opacity(0.18), in: Capsule())
                            .foregroundStyle(.white)

                        if let rating = currentItem.rating, let score = Double(rating), score > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", score))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Color.white.opacity(0.18), in: Capsule())
                        }

                        if let release = currentItem.releaseDate, !release.isEmpty {
                            Text(release.prefix(4))
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(Color.white.opacity(0.12), in: Capsule())
                                .foregroundStyle(.white.opacity(0.85))
                        }

                        if let dur = currentItem.duration, !dur.isEmpty && dur != "0" {
                            let durDisplay = dur.contains(":") ? dur : "\(dur) dk"
                            Text(durDisplay)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    if let genre = currentItem.genre, !genre.isEmpty {
                        Text(genre)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Action Buttons (Glass Style)

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Glass Play Button
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
                .padding(.vertical, 12)
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

            // Glass Favorite Button
            Button {
                storage.toggleFavorite(id: currentItem.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isFav ? .red : .primary)
                    Text(isFav ? "Favoride" : "Favori")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Cast & Crew Section

    @ViewBuilder
    private var castAndCrewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ekip & Oyuncular")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                if let director, !director.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Text("Yönetmen:")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 75, alignment: .leading)

                        Text(director)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                    }
                }

                if let cast, !cast.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Text("Oyuncular:")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 75, alignment: .leading)

                        Text(cast)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
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
