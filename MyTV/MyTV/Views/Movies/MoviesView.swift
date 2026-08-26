import SwiftUI

public struct MoviesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared

    @State private var selectedCategory: MediaCategory?
    @State private var destinationCategory: MediaCategory?
    @State private var selectedMovieForDetail: VODItem?

    public init() {}

    private var activeCategories: [MediaCategory] {
        appState.vodCategories.filter { cat in
            appState.movies.contains { $0.categoryId == cat.id }
        }
    }

    private var moviesForSelectedCategory: [VODItem] {
        guard let selected = selectedCategory else { return [] }
        return appState.movies.filter { $0.categoryId == selected.id }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if appState.movies.isEmpty {
                    ContentUnavailableView(
                        "Film Bulunamadı",
                        systemImage: "film",
                        description: Text("Hesabınızda film içeriği bulunmuyor veya henüz yüklenmedi.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            if let selected = selectedCategory {
                                singleCategoryGridView(category: selected)
                            } else {
                                categoryShelvesFeed
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 36)
                    }
                    .scrollEdgeEffectStyle(.soft, for: .all)
                }
            }
            .navigationTitle(selectedCategory?.name ?? "Filmler")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !activeCategories.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                selectedCategory = nil
                            } label: {
                                HStack {
                                    Text("Tüm Filmler")
                                    if selectedCategory == nil {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Divider()

                            ForEach(activeCategories) { cat in
                                Button {
                                    selectedCategory = cat
                                } label: {
                                    HStack {
                                        Text(cat.name)
                                        if selectedCategory?.id == cat.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: selectedCategory == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                .font(.system(size: 16))
                        }
                    }
                }
            }
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

    // MARK: - Single Category Grid

    @ViewBuilder
    private func singleCategoryGridView(category: MediaCategory) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 95, maximum: 140), spacing: 12)], spacing: 14) {
            ForEach(moviesForSelectedCategory) { movie in
                MediaCardView(item: movie, width: 100) {
                    selectedMovieForDetail = movie
                }
            }
        }
        .padding(.horizontal)
    }
}
