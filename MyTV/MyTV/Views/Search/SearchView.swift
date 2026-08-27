import SwiftUI

public struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared
    @ObservedObject private var storage = StorageManager.shared
    @Binding var searchText: String
    @Namespace private var detailNamespace

    @State private var selectedScope: SearchScope = .all
    @State private var selectedMediaForDetail: VODItem?

    public enum SearchScope: String, CaseIterable, Identifiable {
        case all = "Tümü"
        case live = "Canlı TV"
        case movies = "Filmler"
        case series = "Diziler"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .all: return "square.grid.2x2.fill"
            case .live: return "play.tv.fill"
            case .movies: return "film.fill"
            case .series: return "tv.fill"
            }
        }
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
        VStack(spacing: 12) {
            // 1. Arama Çubuğu (Search Bar)
            searchBarHeader
                .padding(.horizontal)
                .padding(.top, 8)

            // 2. Arama Sonuçları / Keşfet Ekranı
            if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                searchInitialDiscoveryView
            } else if totalResultsCount == 0 {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
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
                    .padding(.top, 4)
                    .padding(.bottom, 36)
                }
            }
        }
        .navigationTitle("Arama")
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

    // MARK: - Search Bar Header

    @ViewBuilder
    private var searchBarHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(searchText.isEmpty ? .secondary : Color.brandPrimary)

            TextField("Kanal, film veya dizi ara...", text: $searchText)
                .font(.system(size: 15, weight: .medium))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
    }

    // MARK: - Initial Discovery View (Arama Boşken)

    @ViewBuilder
    private var searchInitialDiscoveryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Hızlı Arama Önerileri
                VStack(alignment: .leading, spacing: 10) {
                    Text("Popüler Aramalar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 8) {
                        popularSuggestionChip(title: "Spor Kanalları", icon: "sportscourt") {
                            searchText = "Spor"
                        }
                        popularSuggestionChip(title: "Haber", icon: "newspaper") {
                            searchText = "Haber"
                        }
                        popularSuggestionChip(title: "Sinema", icon: "film") {
                            searchText = "Sinema"
                        }
                        popularSuggestionChip(title: "Belgesel", icon: "globe") {
                            searchText = "Belgesel"
                        }
                        popularSuggestionChip(title: "Çocuk", icon: "face.smiling") {
                            searchText = "Çocuk"
                        }
                    }
                }

                // Trend Filmlerden Örnekler
                if !appState.movies.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Öne Çıkan Filmler")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 95, maximum: 140), spacing: 12)], spacing: 14) {
                            ForEach(Array(appState.movies.prefix(6))) { movie in
                                MediaCardView(item: movie, width: 100) {
                                    selectedMediaForDetail = movie
                                }
                            }
                        }
                    }
                }

                // Popüler Dizilerden Örnekler
                if !appState.series.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Popüler Diziler")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 95, maximum: 140), spacing: 12)], spacing: 14) {
                            ForEach(Array(appState.series.prefix(6))) { series in
                                MediaCardView(item: series, width: 100) {
                                    selectedMediaForDetail = series
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
    }

    @ViewBuilder
    private func popularSuggestionChip(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scope Filter Bar

    @ViewBuilder
    private var scopeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchScope.allCases) { scope in
                    let isSelected = (selectedScope == scope)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedScope = scope
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: scope.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(scope.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? Color.brandPrimary : Color.white.opacity(0.08),
                            in: Capsule()
                        )
                        .foregroundStyle(isSelected ? .black : .white)
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
                Text("Canlı Kanallar (\(matchingChannels.count))")
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
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
                Text("Filmler (\(matchingMovies.count))")
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95, maximum: 140), spacing: 12)], spacing: 14) {
                ForEach(matchingMovies) { movie in
                    let card = MediaCardView(item: movie, width: 100) {
                        selectedMediaForDetail = movie
                    }
                    if #available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, *) {
                        card.matchedTransitionSource(id: movie.id, in: detailNamespace)
                    } else {
                        card
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
                Text("Diziler (\(matchingSeries.count))")
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95, maximum: 140), spacing: 12)], spacing: 14) {
                ForEach(matchingSeries) { series in
                    let card = MediaCardView(item: series, width: 100) {
                        selectedMediaForDetail = series
                    }
                    if #available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, *) {
                        card.matchedTransitionSource(id: series.id, in: detailNamespace)
                    } else {
                        card
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

// MARK: - FlowLayout Helper for Search Chips

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeightInRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += maxHeightInRow + spacing
                maxHeightInRow = 0
            }
            x += size.width + spacing
            maxHeightInRow = max(maxHeightInRow, size.height)
        }
        height = y + maxHeightInRow
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var maxHeightInRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += maxHeightInRow + spacing
                maxHeightInRow = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            maxHeightInRow = max(maxHeightInRow, size.height)
        }
    }
}
