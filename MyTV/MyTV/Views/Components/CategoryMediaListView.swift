import SwiftUI

public struct CategoryMediaListView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared

    let category: MediaCategory
    @State private var selectedMediaForDetail: VODItem?

    public init(category: MediaCategory) {
        self.category = category
    }

    private var channels: [Channel] {
        appState.channels.filter { $0.categoryId == category.id }
    }

    private var movies: [VODItem] {
        appState.movies.filter { $0.categoryId == category.id }
    }

    private var series: [VODItem] {
        appState.series.filter { $0.categoryId == category.id }
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95, maximum: 140), spacing: 12)], spacing: 14) {
                switch category.type {
                case .live:
                    ForEach(channels) { channel in
                        MediaCardView(channel: channel, width: 100) {
                            playChannel(channel)
                        }
                    }
                case .movie:
                    ForEach(movies) { movie in
                        MediaCardView(item: movie, width: 100) {
                            selectedMediaForDetail = movie
                        }
                    }
                case .series:
                    ForEach(series) { s in
                        MediaCardView(item: s, width: 100) {
                            selectedMediaForDetail = s
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationTitle(category.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $selectedMediaForDetail) { item in
            MediaDetailView(item: item)
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
}
