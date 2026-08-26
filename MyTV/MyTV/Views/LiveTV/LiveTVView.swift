import SwiftUI

public struct LiveTVView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared
    @ObservedObject private var storage = StorageManager.shared

    @State private var selectedCategory: MediaCategory?
    @State private var destinationCategory: MediaCategory?

    public init() {}

    private var activeCategories: [MediaCategory] {
        appState.liveCategories.filter { cat in
            appState.channels.contains { $0.categoryId == cat.id }
        }
    }

    private var channelsForSelectedCategory: [Channel] {
        guard let selected = selectedCategory else { return [] }
        return appState.channels.filter { $0.categoryId == selected.id }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if appState.channels.isEmpty {
                    ContentUnavailableView(
                        "Kanal Bulunamadı",
                        systemImage: "tv.slash",
                        description: Text("Hesabınızda canlı kanal bulunmuyor veya henüz yüklenmedi.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            if let selected = selectedCategory {
                                singleCategoryGrid(category: selected)
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
            .navigationTitle(selectedCategory?.name ?? "Canlı TV")
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
                                    Text("Tüm Kanallar")
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
        }
    }

    // MARK: - Category Shelves Feed (Canlı TV Rafları)

    @ViewBuilder
    private var categoryShelvesFeed: some View {
        LazyVStack(spacing: 20) {
            // Favori Kanallar Vitrini
            let favoriteChannels = appState.channels.filter { storage.isFavorite(id: $0.id) }
            if !favoriteChannels.isEmpty {
                MediaShelfRow(
                    title: "Favori Kanallarım",
                    channels: favoriteChannels,
                    onSeeAll: nil,
                    onPlay: { ch in
                        playChannel(ch)
                    }
                )
            }

            // Kategori Rafları
            ForEach(activeCategories) { cat in
                let items = appState.channels.filter { $0.categoryId == cat.id }
                if !items.isEmpty {
                    MediaShelfRow(
                        title: cat.name,
                        channels: Array(items.prefix(15)),
                        onSeeAll: {
                            destinationCategory = cat
                        },
                        onPlay: { ch in
                            playChannel(ch)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Single Category Grid

    @ViewBuilder
    private func singleCategoryGrid(category: MediaCategory) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 95, maximum: 140), spacing: 12)], spacing: 14) {
            ForEach(channelsForSelectedCategory) { channel in
                MediaCardView(channel: channel, width: 100) {
                    playChannel(channel)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Playback Helper

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
