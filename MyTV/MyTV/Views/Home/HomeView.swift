import SwiftUI

public struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var playback = PlaybackManager.shared

    @State private var selectedMediaForDetail: VODItem?

    public init() {}

    private var featuredItems: [VODItem] {
        // Pick top items that have backdrops or high ratings
        let pool = appState.movies + appState.series
        return Array(pool.prefix(6))
    }

    private var trendingMovies: [VODItem] {
        Array(appState.movies.prefix(15))
    }

    private var popularSeries: [VODItem] {
        Array(appState.series.prefix(15))
    }

    private var featuredChannels: [Channel] {
        Array(appState.channels.prefix(20))
    }

    public var body: some View {
        NavigationStack {
            Group {
                if storage.activeAccount == nil {
                    noAccountView
                } else if appState.isLoading && appState.channels.isEmpty && appState.movies.isEmpty {
                    loadingView
                } else {
                    appleTVDashboardView
                }
            }
            .navigationTitle("Ana Sayfa")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.isAddAccountPresented = true
                    } label: {
                        Label("Liste Ekle", systemImage: "plus.circle")
                    }
                }
            }
            .sheet(isPresented: $appState.isAddAccountPresented) {
                AddAccountView()
            }
            .navigationDestination(item: $selectedMediaForDetail) { item in
                MediaDetailView(item: item)
            }
        }
    }

    // MARK: - Apple TV Dashboard View

    @ViewBuilder
    private var appleTVDashboardView: some View {
        ScrollView {
            LazyVStack(spacing: 28) {
                // 1. Top Hero Banner Carousel (Featured)
                if !featuredItems.isEmpty {
                    HeroBannerView(
                        items: featuredItems,
                        onPlay: { item in
                            handlePlay(item)
                        },
                        onSelect: { item in
                            selectedMediaForDetail = item
                        }
                    )
                    .padding(.top, 8)
                }

                // 2. Canlı TV Öne Çıkanlar (Horizontal Live Channels Shelf)
                if !featuredChannels.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Canlı TV")
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                            Spacer()
                            Button {
                                appState.selectedTab = 1
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Tümü")
                                        .font(.system(size: 13, weight: .medium))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundStyle(.tint)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(featuredChannels) { ch in
                                    ChannelCardView(channel: ch) {
                                        playChannel(ch)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                // 3. Trend Filmler (Trending Movies Shelf)
                if !trendingMovies.isEmpty {
                    MediaShelfRow(
                        title: "Trend Filmler",
                        subtitle: "En çok izlenen ve popüler filmler",
                        items: trendingMovies,
                        onSeeAll: {
                            appState.selectedTab = 2
                        },
                        onPlay: { movie in
                            selectedMediaForDetail = movie
                        }
                    )
                }

                // 4. Popüler Diziler (Popular Series Shelf)
                if !popularSeries.isEmpty {
                    MediaShelfRow(
                        title: "Popüler Diziler",
                        subtitle: "Tüm sezon ve bölümler",
                        items: popularSeries,
                        onSeeAll: {
                            appState.selectedTab = 3
                        },
                        onPlay: { series in
                            selectedMediaForDetail = series
                        }
                    )
                }

                // 5. Film Kategorileri Rafları
                ForEach(appState.vodCategories.filter { cat in appState.movies.contains { $0.categoryId == cat.id } }.prefix(8)) { cat in
                    let catItems = appState.movies.filter { $0.categoryId == cat.id }
                    if !catItems.isEmpty {
                        MediaShelfRow(
                            title: cat.name,
                            subtitle: "\(catItems.count) Film",
                            items: Array(catItems.prefix(15)),
                            onSeeAll: {
                                appState.selectedTab = 2
                            },
                            onPlay: { movie in
                                selectedMediaForDetail = movie
                            }
                        )
                    }
                }

                // 6. Dizi Kategorileri Rafları
                ForEach(appState.seriesCategories.filter { cat in appState.series.contains { $0.categoryId == cat.id } }.prefix(6)) { cat in
                    let catItems = appState.series.filter { $0.categoryId == cat.id }
                    if !catItems.isEmpty {
                        MediaShelfRow(
                            title: cat.name,
                            subtitle: "\(catItems.count) Dizi",
                            items: Array(catItems.prefix(15)),
                            onSeeAll: {
                                appState.selectedTab = 3
                            },
                            onPlay: { series in
                                selectedMediaForDetail = series
                            }
                        )
                    }
                }
            }
            .padding(.bottom, 36)
        }
        .refreshable {
            await appState.syncActiveAccount()
        }
    }

    // MARK: - Actions

    private func handlePlay(_ item: VODItem) {
        if item.type == .series {
            selectedMediaForDetail = item
        } else {
            let media = PlayableMedia(
                mediaId: item.id,
                title: item.name,
                subtitle: item.genre ?? "Film",
                posterUrl: item.streamIcon,
                streamUrl: item.streamUrl,
                contentType: .movie,
                rating: item.rating,
                releaseDate: item.releaseDate,
                duration: item.duration,
                overview: item.overview,
                genre: item.genre
            )
            playback.play(media: media)
        }
    }

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

    // MARK: - Empty & Loading States

    @ViewBuilder
    private var noAccountView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tv.and.mediabox")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .padding(.bottom, 8)

            Text("MyTV'ye Hoş Geldiniz")
                .font(.title2.bold())

            Text("Yayınları izlemek için Xtream Codes veya M3U/M3U8 çalma listenizi ekleyin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                appState.isAddAccountPresented = true
            } label: {
                Label("Çalma Listesi Ekle", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text(appState.loadingMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
