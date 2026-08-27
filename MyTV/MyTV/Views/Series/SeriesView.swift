import SwiftUI

public struct SeriesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared
    @Namespace private var detailNamespace

    @State private var destinationCategory: MediaCategory?
    @State private var selectedSeriesForDetail: VODItem?

    public init() {}

    private var activeCategories: [MediaCategory] {
        appState.seriesCategories.filter { cat in
            appState.series.contains { $0.categoryId == cat.id }
        }
    }

    public var body: some View {
        Group {
            if appState.series.isEmpty {
                ContentUnavailableView(
                    "Dizi Bulunamadı",
                    systemImage: "play.tv",
                    description: Text("Hesabınızda dizi içeriği bulunmuyor veya henüz yüklenmedi.")
                )
            } else {
                ScrollView {
                    categoryShelvesFeed
                        .padding(.top, 8)
                        .padding(.bottom, 36)
                }
            }
        }
        .navigationTitle("Diziler")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .refreshable {
            await appState.syncActiveAccount()
        }
        .navigationDestination(item: $destinationCategory) { cat in
            CategoryMediaListView(category: cat)
        }
        .navigationDestination(item: $selectedSeriesForDetail) { series in
            if #available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, *) {
                MediaDetailView(item: series)
                    .navigationTransition(.zoom(sourceID: series.id, in: detailNamespace))
            } else {
                MediaDetailView(item: series)
            }
        }
    }

    // MARK: - Category Shelves Feed

    @ViewBuilder
    private var categoryShelvesFeed: some View {
        LazyVStack(spacing: 20) {
            ForEach(activeCategories) { cat in
                let items = appState.series.filter { $0.categoryId == cat.id }
                if !items.isEmpty {
                    MediaShelfRow(
                        title: cat.name,
                        items: Array(items.prefix(15)),
                        namespace: detailNamespace,
                        onSeeAll: {
                            destinationCategory = cat
                        },
                        onPlay: { series in
                            selectedSeriesForDetail = series
                        }
                    )
                }
            }
        }
    }
}
