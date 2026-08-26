import SwiftUI

public struct MoviesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared

    @State private var destinationCategory: MediaCategory?
    @State private var selectedMovieForDetail: VODItem?

    public init() {}

    private var activeCategories: [MediaCategory] {
        appState.vodCategories.filter { cat in
            appState.movies.contains { $0.categoryId == cat.id }
        }
    }

    public var body: some View {
        Group {
            if appState.movies.isEmpty {
                ContentUnavailableView(
                    "Film Bulunamadı",
                    systemImage: "film",
                    description: Text("Hesabınızda film içeriği bulunmuyor veya henüz yüklenmedi.")
                )
            } else {
                ScrollView {
                    categoryShelvesFeed
                        .padding(.top, 8)
                        .padding(.bottom, 36)
                }
                .scrollEdgeEffectStyle(.soft, for: .all)
            }
        }
        .navigationTitle("Filmler")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .refreshable {
            await appState.syncActiveAccount()
        }
        .navigationDestination(item: $destinationCategory) { cat in
            CategoryMediaListView(category: cat)
        }
        .navigationDestination(item: $selectedMovieForDetail) { movie in
            MediaDetailView(item: movie)
        }
    }

    // MARK: - Category Shelves Feed

    @ViewBuilder
    private var categoryShelvesFeed: some View {
        LazyVStack(spacing: 20) {
            ForEach(activeCategories) { cat in
                let items = appState.movies.filter { $0.categoryId == cat.id }
                if !items.isEmpty {
                    MediaShelfRow(
                        title: cat.name,
                        items: Array(items.prefix(15)),
                        onSeeAll: {
                            destinationCategory = cat
                        },
                        onPlay: { movie in
                            selectedMovieForDetail = movie
                        }
                    )
                }
            }
        }
    }
}
