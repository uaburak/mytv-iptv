import SwiftUI

public struct FavoritesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared
    @ObservedObject private var storage = StorageManager.shared

    @State private var selectedScope: FavoriteScope = .all
    @State private var selectedMediaForDetail: VODItem?

    public enum FavoriteScope: String, CaseIterable, Identifiable {
        case all = "Tümü"
        case live = "Canlı TV"
        case movies = "Filmler"
        case series = "Diziler"

        public var id: String { rawValue }
    }

    public init() {}

    private var favoriteChannels: [Channel] {
        appState.channels.filter { storage.isFavorite(id: $0.id) }
    }

    private var favoriteMovies: [VODItem] {
        appState.movies.filter { storage.isFavorite(id: $0.id) }
    }

    private var favoriteSeries: [VODItem] {
        appState.series.filter { storage.isFavorite(id: $0.id) }
    }

    private var totalFavoritesCount: Int {
        favoriteChannels.count + favoriteMovies.count + favoriteSeries.count
    }

    public var body: some View {
        NavigationStack {
            Group {
                if totalFavoritesCount == 0 {
                    ContentUnavailableView(
                        "Henüz Favori Eklenmedi",
                        systemImage: "heart.slash",
                        description: Text("Beğendiğiniz kanal, film veya dizileri kalp ikonuna basarak favorilere ekleyebilirsiniz.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            // Scope Filter Bar
                            scopeFilterBar

                            // 1. Canlı Kanallar
                            if selectedScope == .all || selectedScope == .live {
                                if !favoriteChannels.isEmpty {
                                    channelsSection
                                }
                            }

                            // 2. Filmler
                            if selectedScope == .all || selectedScope == .movies {
                                if !favoriteMovies.isEmpty {
                                    moviesSection
                                }
                            }

                            // 3. Diziler
                            if selectedScope == .all || selectedScope == .series {
                                if !favoriteSeries.isEmpty {
                                    seriesSection
                                }
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 36)
                    }
                    .scrollEdgeEffectStyle(.soft, for: .all)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedMediaForDetail) { item in
                MediaDetailView(item: item)
            }
        }
    }

    // MARK: - Scope Filter Bar

    @ViewBuilder
    private var scopeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FavoriteScope.allCases) { scope in
                    let isSelected = (selectedScope == scope)
                    let count = countForScope(scope)
                    Button {
                        selectedScope = scope
                    } label: {
                        Text("\(scope.rawValue) (\(count))")
                            .font(.caption.weight(isSelected ? .bold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func countForScope(_ scope: FavoriteScope) -> Int {
        switch scope {
        case .all: return totalFavoritesCount
        case .live: return favoriteChannels.count
        case .movies: return favoriteMovies.count
        case .series: return favoriteSeries.count
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var channelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Canlı Kanallar")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95, maximum: 140), spacing: 12)], spacing: 14) {
                ForEach(favoriteChannels) { ch in
                    MediaCardView(channel: ch, width: 100) {
                        playChannel(ch)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var moviesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filmler")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95, maximum: 140), spacing: 12)], spacing: 14) {
                ForEach(favoriteMovies) { movie in
                    MediaCardView(item: movie, width: 100) {
                        selectedMediaForDetail = movie
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diziler")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95, maximum: 140), spacing: 12)], spacing: 14) {
                ForEach(favoriteSeries) { series in
                    MediaCardView(item: series, width: 100) {
                        selectedMediaForDetail = series
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

    private func playChannel(_ channel: Channel) {
        let media = PlayableMedia(
            mediaId: channel.id,
            title: channel.name,
            subtitle: "Canlı Yayın",
            posterUrl: channel.streamIcon,
            streamUrl: channel.streamUrl,
            contentType: .live
        )
        playback.play(media: media)
    }
}
