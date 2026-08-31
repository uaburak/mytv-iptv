import Foundation

/// M3U/M3U8 kaynağı. Playlist tek seferde indirilip belleğe açılır;
/// sonraki bütün sorgular bu anlık görüntü üzerinden karşılanır.
actor M3UProvider: ContentProvider {
    private let url: URL
    private let session: URLSession

    nonisolated let sourceID: String

    private var isLoaded = false
    private var itemsByKind: [MediaKind: [MediaItem]] = [:]
    private var categoriesByKind: [MediaKind: [MediaCategory]] = [:]
    /// Dizi kimliği -> bölümler. `detail(for:)` bunu sezonlara böler.
    private var episodesBySeries: [String: [Episode]] = [:]

    init(url: URL, sourceID: String) {
        self.url = url
        self.sourceID = sourceID

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    /// Bir sonraki istekte liste yeniden indirilsin. Bu olmadan `isLoaded`
    /// hiçbir zaman düşmüyor ve "yenile" aynı anlık görüntüyü diske geri
    /// yazmaktan ibaret kalıyor.
    func invalidate() async {
        isLoaded = false
        itemsByKind = [:]
        categoriesByKind = [:]
        episodesBySeries = [:]
    }

    func validate() async throws -> ProviderAccount {
        try await load()
        guard itemsByKind.values.contains(where: { !$0.isEmpty }) else { throw ContentError.emptyPlaylist }
        return ProviderAccount(username: nil, status: "Active", serverURL: url.absoluteString)
    }

    func categories(for kind: MediaKind) async throws -> [MediaCategory] {
        try await load()
        return categoriesByKind[kind] ?? []
    }

    func items(kind: MediaKind, categoryID: String?) async throws -> [MediaItem] {
        try await load()
        let all = itemsByKind[kind] ?? []
        guard let categoryID else { return all }
        return all.filter { $0.categoryID == categoryID }
    }

    func detail(for item: MediaItem) async throws -> MediaDetail {
        try await load()
        guard item.kind == .series else { return MediaDetail(item: item) }

        let episodes = episodesBySeries[item.id.raw] ?? []
        let grouped = Dictionary(grouping: episodes, by: \.seasonNumber)
        let seasons = grouped
            .map { number, episodes in
                Season(
                    id: "\(item.id.raw).s\(number)",
                    number: number,
                    name: L10n.seasonName(number),
                    posterURL: item.posterURL,
                    episodes: episodes.sorted { $0.episodeNumber < $1.episodeNumber }
                )
            }
            .sorted { $0.number < $1.number }

        return MediaDetail(item: item, seasons: seasons)
    }

    func playbackURL(for item: MediaItem) async throws -> URL {
        // M3U'da `streamReference` doğrudan oynatma bağlantısıdır.
        guard let url = URL(string: item.streamReference) else {
            throw ContentError.unsupported(item.title)
        }
        return url
    }

    func playbackURL(for episode: Episode) async throws -> URL {
        guard let url = URL(string: episode.streamReference) else {
            throw ContentError.unsupported(episode.title)
        }
        return url
    }

    // MARK: - Yükleme

    private func load() async throws {
        guard !isLoaded else { return }

        let text: String
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw ContentError.badResponse(status: http.statusCode)
            }
            // Bazı sağlayıcılar Latin-1 döndürüyor; UTF-8 çözülemezse ona düşüyoruz.
            guard let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw ContentError.network(L10n.errorPlaylistUnreadable)
            }
            text = decoded
        } catch let error as ContentError {
            throw error
        } catch {
            throw ContentError.network(error.localizedDescription)
        }

        build(from: M3UParser.parse(text))
        isLoaded = true
    }

    private func build(from entries: [M3UEntry]) {
        var items: [MediaKind: [MediaItem]] = [:]
        var groups: [MediaKind: [String: Int]] = [:]
        var seriesItems: [String: MediaItem] = [:]
        var seriesEpisodes: [String: [Episode]] = [:]

        for entry in entries {
            let group = entry.group?.trimmingCharacters(in: .whitespaces)
            let categoryID = group.map(Self.categoryID)
            groups[entry.kind, default: [:]][group ?? L10n.otherCategory, default: 0] += 1

            switch entry.kind {
            case .live, .movie:
                let reference = entry.url.absoluteString
                let item = MediaItem(
                    id: MediaID(source: sourceID, kind: entry.kind, raw: reference),
                    title: entry.name,
                    posterURL: entry.logo,
                    backdropURL: nil,
                    categoryID: categoryID,
                    categoryName: group,
                    year: LooseParse.year(from: entry.name),
                    rating: nil,
                    genres: group.map { [$0] } ?? [],
                    plot: nil,
                    durationSeconds: entry.duration,
                    addedAt: nil,
                    isAdult: false,
                    streamReference: reference,
                    containerExtension: entry.url.pathExtension.isEmpty ? nil : entry.url.pathExtension,
                    channelNumber: nil
                )
                items[entry.kind, default: []].append(item)

            case .series:
                // Bölümler tek tek listelenir; onları dizi başlığı altında topluyoruz.
                let seriesTitle = entry.seriesTitle ?? entry.name
                let key = Self.categoryID(seriesTitle)

                if seriesItems[key] == nil {
                    seriesItems[key] = MediaItem(
                        id: MediaID(source: sourceID, kind: .series, raw: key),
                        title: seriesTitle,
                        posterURL: entry.logo,
                        backdropURL: nil,
                        categoryID: categoryID,
                        categoryName: group,
                        genres: group.map { [$0] } ?? [],
                        streamReference: key
                    )
                } else if seriesItems[key]?.posterURL == nil {
                    seriesItems[key]?.posterURL = entry.logo
                }

                let seasonNumber = entry.seasonNumber ?? 1
                let episodeNumber = entry.episodeNumber ?? ((seriesEpisodes[key]?.count ?? 0) + 1)
                seriesEpisodes[key, default: []].append(
                    Episode(
                        id: entry.url.absoluteString,
                        seriesID: MediaID(source: sourceID, kind: .series, raw: key),
                        seasonNumber: seasonNumber,
                        episodeNumber: episodeNumber,
                        title: entry.name,
                        plot: nil,
                        stillURL: entry.logo,
                        durationSeconds: entry.duration,
                        airDate: nil,
                        streamReference: entry.url.absoluteString,
                        containerExtension: entry.url.pathExtension.isEmpty ? nil : entry.url.pathExtension
                    )
                )
            }
        }

        items[.series] = seriesItems.values.sorted { $0.title < $1.title }
        itemsByKind = items
        episodesBySeries = seriesEpisodes

        categoriesByKind = groups.mapValues { counts in
            counts
                .map { MediaCategory(id: Self.categoryID($0.key), name: $0.key.cleanedCategoryName, kind: .live, itemCount: $0.value) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        // Kategori nesnesindeki `kind` alanını doğru türle eşle.
        for kind in MediaKind.allCases {
            categoriesByKind[kind] = categoriesByKind[kind]?.map {
                MediaCategory(id: $0.id, name: $0.name, kind: kind, itemCount: $0.itemCount)
            }
        }
    }

    private nonisolated static func categoryID(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }
}
