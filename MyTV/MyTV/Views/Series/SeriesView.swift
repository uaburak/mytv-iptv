import SwiftUI

public struct SeriesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared

    @State private var searchText = ""
    @State private var selectedCategory: MediaCategory?
    @State private var selectedSeriesForDetail: VODItem?

    public init() {}

    private var activeCategories: [MediaCategory] {
        // Only show categories that actually contain series
        appState.seriesCategories.filter { cat in
            appState.series.contains { $0.categoryId == cat.id }
        }
    }

    private var filteredCategories: [MediaCategory] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return activeCategories
        }
        return activeCategories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var seriesForSelectedCategory: [VODItem] {
        guard let selected = selectedCategory else { return [] }
        var list = appState.series.filter { $0.categoryId == selected.id }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return list
    }

    private var searchResults: [VODItem] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return appState.series.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if appState.series.isEmpty {
                    ContentUnavailableView(
                        "Dizi Bulunamadı",
                        systemImage: "play.tv",
                        description: Text("Hesabınızda dizi içeriği bulunmuyor veya henüz yüklenmedi.")
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
            .navigationTitle(selectedCategory?.name ?? "Diziler")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Dizi veya Kategori Ara...")
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
            .sheet(item: $selectedSeriesForDetail) { series in
                MediaDetailView(item: series)
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
                        let count = appState.series.filter { $0.categoryId == cat.id }.count
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
                    let items = appState.series.filter { $0.categoryId == cat.id }
                    if !items.isEmpty {
                        MediaShelfRow(
                            title: cat.name,
                            subtitle: "\(items.count) Dizi",
                            items: Array(items.prefix(15)),
                            onSeeAll: {
                                selectedCategory = cat
                            },
                            onPlay: { series in
                                selectedSeriesForDetail = series
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
                ForEach(seriesForSelectedCategory) { series in
                    MediaCardView(item: series, width: 115) {
                        selectedSeriesForDetail = series
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
                    ForEach(searchResults) { series in
                        MediaCardView(item: series, width: 115) {
                            selectedSeriesForDetail = series
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
