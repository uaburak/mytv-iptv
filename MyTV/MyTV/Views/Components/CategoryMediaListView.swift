import SwiftUI

public struct CategoryMediaListView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared
    @Namespace private var detailNamespace

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
                        let card = MediaCardView(item: movie, width: 100) {
                            selectedMediaForDetail = movie
                        }
                        if #available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, *) {
                            card.matchedTransitionSource(id: movie.id, in: detailNamespace)
                        } else {
                            card
                        }
                    }
                case .series:
                    ForEach(series) { s in
                        let card = MediaCardView(item: s, width: 100) {
                            selectedMediaForDetail = s
                        }
                        if #available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, *) {
                            card.matchedTransitionSource(id: s.id, in: detailNamespace)
                        } else {
                            card
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .navigationTitle(category.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $selectedMediaForDetail) { item in
            if #available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, *) {
                MediaDetailView(item: item)
                    .navigationTransition(.zoom(sourceID: item.id, in: detailNamespace))
            } else {
                MediaDetailView(item: item)
            }
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
