import SwiftUI

public struct MediaDetailView: View {
    let item: VODItem
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var playback = PlaybackManager.shared

    // Series specific state
    @State private var episodes: [Episode] = []
    @State private var isLoadingEpisodes = false
    @State private var selectedSeason: Int = 1

    public init(item: VODItem) {
        self.item = item
    }

    private var isFav: Bool {
        storage.isFavorite(id: item.id)
    }

    private var seasons: [Int] {
        Array(Set(episodes.map { $0.seasonNum })).sorted()
    }

    private var seasonEpisodes: [Episode] {
        episodes.filter { $0.seasonNum == selectedSeason }
    }

    private var relatedItems: [VODItem] {
        let pool = item.type == .movie ? appState.movies : appState.series
        return pool.filter { $0.categoryId == item.categoryId && $0.id != item.id }.prefix(12).map { $0 }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Cinematic Hero Header
                heroHeader

                // 2. Action Buttons (Play & Favorite)
                actionButtons
                    .padding(.horizontal)

                // 3. Storyline / Overview
                if let plot = item.overview, !plot.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Konu Özeti")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(plot)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal)
                }

                // 4. Series Seasons & Episodes (Only for Series)
                if item.type == .series {
                    seriesEpisodesSection
                }

                // 5. Related Content Shelf
                if !relatedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Benzer İçerikler")
                            .font(.headline)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(relatedItems) { rel in
                                    MediaCardView(item: rel, width: 120) {
                                        playItem(rel)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle(item.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if item.type == .series {
                await loadEpisodes()
            }
        }
    }

    // MARK: - Hero Header

    @ViewBuilder
    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop Image
            GeometryReader { geo in
                ZStack {
                    Color.black

                    if let bg = item.backdropUrl ?? item.streamIcon, let url = URL(string: bg) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width, height: 260)
                                    .clipped()
                            default:
                                Color.secondary.opacity(0.15)
                            }
                        }
                    }
                }
            }
            .frame(height: 260)

            // Cinematic Gradient
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.4), location: 0.4),
                    .init(color: .black.opacity(0.95), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)

            // Poster & Title Info Overlay
            HStack(alignment: .bottom, spacing: 16) {
                // Floating Poster
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.2))

                    if let icon = item.streamIcon ?? item.backdropUrl, let url = URL(string: icon) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Image(systemName: item.type == .series ? "play.tv" : "film")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(width: 95, height: 142)
                .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )

                // Title & Badges
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(radius: 4)

                    // Meta Chips
                    HStack(spacing: 8) {
                        Text(item.type.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.white)

                        if let rating = item.rating, let score = Double(rating), score > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", score))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                        }

                        if let release = item.releaseDate, !release.isEmpty {
                            Text(release.prefix(4))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        if let dur = item.duration, !dur.isEmpty && dur != "0" {
                            Text("\(dur) dk")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    if let genre = item.genre, !genre.isEmpty {
                        Text(genre)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Play Button
            Button {
                if item.type == .series {
                    if let firstEp = seasonEpisodes.first ?? episodes.first {
                        playEpisode(firstEp)
                    }
                } else {
                    playItem(item)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.headline)
                    Text(item.type == .series ? "1. Bölümü İzle" : "Hemen İzle")
                        .font(.headline)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            // Favorite Button
            Button {
                storage.toggleFavorite(id: item.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .font(.headline)
                        .foregroundStyle(isFav ? .red : .primary)
                    Text(isFav ? "Favoride" : "Favori")
                        .font(.subheadline.bold())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Series Episodes Section

    @ViewBuilder
    private var seriesEpisodesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
                .padding(.horizontal)

            Text("Sezonlar ve Bölümler")
                .font(.headline)
                .padding(.horizontal)

            // Seasons Picker Pills
            if !seasons.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(seasons, id: \.self) { s in
                            Button {
                                selectedSeason = s
                            } label: {
                                Text("Sezon \(s)")
                                    .font(.subheadline.weight(selectedSeason == s ? .bold : .regular))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(selectedSeason == s ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                                    .foregroundStyle(selectedSeason == s ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Episode Cards List
            if isLoadingEpisodes {
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
                                // Episode Thumbnail / Icon
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.15))
                                        .frame(width: 70, height: 48)

                                    if let cover = ep.coverUrl, let url = URL(string: cover) {
                                        AsyncImage(url: url) { img in
                                            img.resizable().aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Image(systemName: "play.tv")
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 70, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        Image(systemName: "play.tv")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(ep.episodeNum). \(ep.title)")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)

                                    if let dur = ep.duration, !dur.isEmpty {
                                        Text("\(dur) dk")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.tint)
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Actions

    private func loadEpisodes() async {
        guard let account = storage.activeAccount, account.type == .xtream else { return }
        isLoadingEpisodes = true
        let list = (try? await XtreamCodesAPIService.shared.getSeriesInfo(account: account, seriesId: item.id)) ?? []
        self.episodes = list
        if let firstSeason = seasons.first {
            self.selectedSeason = firstSeason
        }
        isLoadingEpisodes = false
    }

    private func playItem(_ vod: VODItem) {
        let media = PlayableMedia(
            mediaId: vod.id,
            title: vod.name,
            subtitle: vod.genre ?? (vod.type == .movie ? "Film" : "Dizi"),
            posterUrl: vod.streamIcon,
            streamUrl: vod.streamUrl,
            contentType: vod.type,
            rating: vod.rating,
            releaseDate: vod.releaseDate,
            duration: vod.duration,
            overview: vod.overview,
            genre: vod.genre
        )
        playback.play(media: media)
        dismiss()
    }

    private func playEpisode(_ episode: Episode) {
        let media = PlayableMedia(
            mediaId: episode.id,
            title: item.name,
            subtitle: "S\(episode.seasonNum):E\(episode.episodeNum) • \(episode.title)",
            posterUrl: item.streamIcon,
            streamUrl: episode.streamUrl,
            contentType: .series,
            rating: item.rating,
            releaseDate: item.releaseDate,
            duration: item.duration,
            overview: item.overview,
            genre: item.genre,
            seriesId: item.id,
            episodeNum: episode.episodeNum,
            seasonNum: episode.seasonNum
        )
        playback.play(media: media)
        dismiss()
    }
}
