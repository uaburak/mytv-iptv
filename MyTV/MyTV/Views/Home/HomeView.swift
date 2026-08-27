import SwiftUI

public struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var playback = PlaybackManager.shared

    public enum HomeNavigationTarget: String, Hashable, Identifiable {
        case liveTV = "Canlı TV"
        case movies = "Filmler"
        case series = "Diziler"

        public var id: String { rawValue }
    }

    @Namespace private var detailNamespace
    @State private var navigationTarget: HomeNavigationTarget?
    @State private var selectedMediaForDetail: VODItem?
    @State private var selectedCategoryForGrid: MediaCategory?
    @State private var showProfileSheet = false

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

    private var watchlistItems: [VODItem] {
        let all = appState.movies + appState.series
        return all.filter { storage.isInWatchlist(id: $0.id) }
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
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        showProfileSheet = true
                    } label: {
                        ProfileImageView(size: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileView()
            }
            .sheet(isPresented: $appState.isAddAccountPresented) {
                AddAccountView()
            }
            .navigationDestination(item: $selectedMediaForDetail) { item in
                if #available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, *) {
                    MediaDetailView(item: item)
                        .navigationTransition(.zoom(sourceID: item.id, in: detailNamespace))
                } else {
                    MediaDetailView(item: item)
                }
            }
            .navigationDestination(item: $selectedCategoryForGrid) { cat in
                CategoryMediaListView(category: cat)
            }
            .navigationDestination(item: $navigationTarget) { target in
                switch target {
                case .liveTV:
                    LiveTVView()
                case .movies:
                    MoviesView()
                case .series:
                    SeriesView()
                }
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
                            selectedMediaForDetail = item
                        },
                        onSelect: { item in
                            selectedMediaForDetail = item
                        }
                    )
                    .padding(.top, 8)
                }

                // 2. Hub Quick Access Cards (Canlı TV, Filmler, Diziler)
                quickNavigationHub

                // 3. Listem (Kullanıcının Listesine Eklediği İçerikler)
                if !watchlistItems.isEmpty {
                    MediaShelfRow(
                        title: "Listem",
                        items: watchlistItems,
                        namespace: detailNamespace,
                        onSeeAll: nil,
                        onPlay: { item in
                            selectedMediaForDetail = item
                        }
                    )
                }

                // 3. Canlı TV Öne Çıkanlar (Horizontal Live Channels Shelf)
                if !featuredChannels.isEmpty {
                    MediaShelfRow(
                        title: "Canlı TV",
                        channels: featuredChannels,
                        onSeeAll: {
                            navigationTarget = .liveTV
                        },
                        onPlay: { ch in
                            playChannel(ch)
                        }
                    )
                }

                // 4. Trend Filmler (Trending Movies Shelf)
                if !trendingMovies.isEmpty {
                    MediaShelfRow(
                        title: "Trend Filmler",
                        items: trendingMovies,
                        namespace: detailNamespace,
                        onSeeAll: {
                            navigationTarget = .movies
                        },
                        onPlay: { movie in
                            selectedMediaForDetail = movie
                        }
                    )
                }

                // 5. Popüler Diziler (Popular Series Shelf)
                if !popularSeries.isEmpty {
                    MediaShelfRow(
                        title: "Popüler Diziler",
                        items: popularSeries,
                        namespace: detailNamespace,
                        onSeeAll: {
                            navigationTarget = .series
                        },
                        onPlay: { series in
                            selectedMediaForDetail = series
                        }
                    )
                }

                // 6. Film Kategorileri Rafları
                ForEach(appState.vodCategories.filter { cat in appState.movies.contains { $0.categoryId == cat.id } }.prefix(8)) { cat in
                    let catItems = appState.movies.filter { $0.categoryId == cat.id }
                    if !catItems.isEmpty {
                        MediaShelfRow(
                            title: cat.name,
                            items: Array(catItems.prefix(15)),
                            namespace: detailNamespace,
                            onSeeAll: {
                                selectedCategoryForGrid = cat
                            },
                            onPlay: { movie in
                                selectedMediaForDetail = movie
                            }
                        )
                    }
                }

                // 7. Dizi Kategorileri Rafları
                ForEach(appState.seriesCategories.filter { cat in appState.series.contains { $0.categoryId == cat.id } }.prefix(6)) { cat in
                    let catItems = appState.series.filter { $0.categoryId == cat.id }
                    if !catItems.isEmpty {
                        MediaShelfRow(
                            title: cat.name,
                            items: Array(catItems.prefix(15)),
                            namespace: detailNamespace,
                            onSeeAll: {
                                selectedCategoryForGrid = cat
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

    // MARK: - Quick Navigation Hub

    @ViewBuilder
    private var quickNavigationHub: some View {
        HStack(spacing: 12) {
            // Canlı TV Hub Button
            hubButton(
                title: "Canlı TV",
                icon: "tv",
                count: "\(appState.channels.count)",
                gradient: [Color.blue.opacity(0.35), Color.purple.opacity(0.2)]
            ) {
                navigationTarget = .liveTV
            }

            // Filmler Hub Button
            hubButton(
                title: "Filmler",
                icon: "film",
                count: "\(appState.movies.count)",
                gradient: [Color.red.opacity(0.35), Color.orange.opacity(0.2)]
            ) {
                navigationTarget = .movies
            }

            // Diziler Hub Button
            hubButton(
                title: "Diziler",
                icon: "play.tv",
                count: "\(appState.series.count)",
                gradient: [Color.indigo.opacity(0.35), Color.cyan.opacity(0.2)]
            ) {
                navigationTarget = .series
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func hubButton(
        title: String,
        icon: String,
        count: String,
        gradient: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(count.isEmpty || count == "0" ? "Keşfet" : "\(count) İçerik")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func handlePlay(_ item: VODItem) {
        selectedMediaForDetail = item
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
