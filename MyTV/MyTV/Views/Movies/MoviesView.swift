import SwiftUI

public struct MoviesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared

    @State private var searchText = ""
    @State private var selectedCategory: MediaCategory?
    @State private var selectedMovieForDetail: VODItem?

    public init() {}

    private var activeCategories: [MediaCategory] {
        // Only show categories that actually contain movies
        appState.vodCategories.filter { cat in
            appState.movies.contains { $0.categoryId == cat.id }
        }
    }

    private var filteredCategories: [MediaCategory] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return activeCategories
        }
        return activeCategories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var moviesForSelectedCategory: [VODItem] {
        guard let selected = selectedCategory else { return [] }
        var list = appState.movies.filter { $0.categoryId == selected.id }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return list
    }

    private var searchResults: [VODItem] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return appState.movies.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
                    VStack(spacing: 0) {
                        // Category Horizontal Filter Pills
                        categoryFilterBar

                        // Main Content
                        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty && selectedCategory == nil {
                            // Search Results Grid
                            searchResultsGrid
                        } else if let selected = selectedCategory {
                            // Single Category Full Grid View
                            singleCategoryGridView(category: selected)
                        } else {
                            // Apple TV Category Shelves Feed
                            categoryShelvesFeed
                        }
                    }
                }
            }
            .navigationTitle(selectedCategory?.name ?? "Filmler")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Film veya Kategori Ara...")
            .toolbar {
                if selectedCategory != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Tüm Kategoriler") {
                            selectedCategory = nil
                        }
                    }
                }
            }
            .refreshable {
                await appState.syncActiveAccount()
            }
            .navigationDestination(item: $selectedMovieForDetail) { movie in
                MediaDetailView(item: movie)
            }
        }
    }

    // MARK: - Category Filter Bar

    @ViewBuilder
    private var categoryFilterBar: some View {
        if !activeCategories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        selectedCategory = nil
                    } label: {
                        Text("Tüm Kategoriler (\(activeCategories.count))")
                            .font(.caption.weight(selectedCategory == nil ? .bold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(selectedCategory == nil ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(selectedCategory == nil ? .white : .primary)
                    }
                    .buttonStyle(.plain)

                    ForEach(filteredCategories) { cat in
                        let isSelected = selectedCategory?.id == cat.id
                        let count = appState.movies.filter { $0.categoryId == cat.id }.count
                        Button {
                            selectedCategory = cat
                        } label: {
                            Text("\(cat.name) (\(count))")
                                .font(.caption.weight(isSelected ? .bold : .regular))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(isSelected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(Color.secondary.opacity(0.04))
        }
    }

    // MARK: - Apple TV Category Shelves Feed (Grouped by Category)

    @ViewBuilder
    private var categoryShelvesFeed: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(activeCategories) { cat in
                    let items = appState.movies.filter { $0.categoryId == cat.id }
                    if !items.isEmpty {
                        MediaShelfRow(
                            title: cat.name,
                            subtitle: "\(items.count) Film",
                            items: Array(items.prefix(15)),
                            onSeeAll: {
                                selectedCategory = cat
                            },
                            onPlay: { movie in
                                selectedMovieForDetail = movie
                            }
                        )
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
    }

    // MARK: - Single Category Full Grid View

    @ViewBuilder
    private func singleCategoryGridView(category: MediaCategory) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 14)], spacing: 18) {
                ForEach(moviesForSelectedCategory) { movie in
                    MediaCardView(item: movie, width: 115) {
                        selectedMovieForDetail = movie
                    }
                }
            }
            .padding()
            .padding(.bottom, 30)
        }
    }

    // MARK: - Search Results Grid

    @ViewBuilder
    private var searchResultsGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(searchResults.count) Sonuç Bulundu")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 14)], spacing: 18) {
                    ForEach(searchResults) { movie in
                        MediaCardView(item: movie, width: 115) {
                            selectedMovieForDetail = movie
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
    }
}
