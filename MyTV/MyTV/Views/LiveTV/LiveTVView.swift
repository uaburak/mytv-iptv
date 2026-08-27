import SwiftUI

public struct LiveTVView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared
    @ObservedObject private var storage = StorageManager.shared

    @State private var destinationCategory: MediaCategory?

    public init() {}

    private var activeCategories: [MediaCategory] {
        appState.liveCategories.filter { cat in
            appState.channels.contains { $0.categoryId == cat.id }
        }
    }

    public var body: some View {
        Group {
            if appState.channels.isEmpty {
                ContentUnavailableView(
                    "Kanal Bulunamadı",
                    systemImage: "tv.slash",
                    description: Text("Hesabınızda canlı kanal bulunmuyor veya henüz yüklenmedi.")
                )
            } else {
                ScrollView {
                    categoryShelvesFeed
                        .padding(.top, 8)
                        .padding(.bottom, 36)
                }
                            }
        }
        .navigationTitle("Canlı TV")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .refreshable {
            await appState.syncActiveAccount()
        }
        .navigationDestination(item: $destinationCategory) { cat in
            CategoryMediaListView(category: cat)
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
