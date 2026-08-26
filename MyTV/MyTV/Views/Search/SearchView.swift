import SwiftUI

public struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared
    @ObservedObject private var storage = StorageManager.shared
    @Binding var searchText: String

    @State private var selectedScope: SearchScope = .all
    @State private var selectedMediaForDetail: VODItem?

    public enum SearchScope: String, CaseIterable, Identifiable {
        case all = "Tümü"
        case live = "Canlı TV"
        case movies = "Filmler"
        case series = "Diziler"

        public var id: String { rawValue }
    }

    public init(searchText: Binding<String>) {
        self._searchText = searchText
    }

    private var matchingChannels: [Channel] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return appState.channels.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var matchingMovies: [VODItem] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return appState.movies.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var matchingSeries: [VODItem] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return appState.series.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var totalResultsCount: Int {
        switch selectedScope {
        case .all:
            return matchingChannels.count + matchingMovies.count + matchingSeries.count
        case .live:
            return matchingChannels.count
        case .movies:
            return matchingMovies.count
        case .series:
            return matchingSeries.count
        }
    }

    public var body: some View {
        Group {
            if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView(
                    "İçerik Arayın",
                    systemImage: "magnifyingglass",
                    description: Text("Canlı kanal, film veya dizi adını yazarak arayabilirsiniz.")
                )
            } else if totalResultsCount == 0 {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        scopeFilterBar

                        if selectedScope == .all || selectedScope == .live {
                            if !matchingChannels.isEmpty { channelsSection }
                        }

                        if selectedScope == .all || selectedScope == .movies {
                            if !matchingMovies.isEmpty { moviesSection }
                        }

                        if selectedScope == .all || selectedScope == .series {
                            if !matchingSeries.isEmpty { seriesSection }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 36)
                }
            }
        }
        .sheet(item: $selectedMediaForDetail) { item in
            NavigationStack {
                MediaDetailView(item: item)
            }
        }
    }

    // MARK: - Scope Filter Bar

    @ViewBuilder
    private var scopeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchScope.allCases) { scope in
                    let isSelected = (selectedScope == scope)
                    Button {
                        selectedScope = scope
                    } label: {
                        Text(scope.rawValue)
                            .font(.caption.weight(isSelected ? .bold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var channelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Canlı Kanallar")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95, maximum: 140), spacing: 12)], spacing: 14) {
                ForEach(matchingChannels) { ch in
                    MediaCardView(channel: ch, width: 100) {
                        playChannel(ch)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var moviesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filmler")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95, maximum: 140), spacing: 12)], spacing: 14) {
                ForEach(matchingMovies) { movie in
                    MediaCardView(item: movie, width: 100) {
                        selectedMediaForDetail = movie
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diziler")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95, maximum: 140), spacing: 12)], spacing: 14) {
                ForEach(matchingSeries) { series in
                    MediaCardView(item: series, width: 100) {
                        selectedMediaForDetail = series
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

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
