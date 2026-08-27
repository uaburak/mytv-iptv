import SwiftUI

public struct MediaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var playback = PlaybackManager.shared

    let item: VODItem

    @State private var vodDetail: XtreamCodesAPIService.VODDetailResponse? = nil
    @State private var seriesDetail: XtreamCodesAPIService.SeriesDetailResponse? = nil
    @State private var isLoadingDetails: Bool = false
    @State private var isOverviewExpanded: Bool = false
    @State private var selectedSeason: Int = 1

    public init(
        item: VODItem,
        vodDetail: XtreamCodesAPIService.VODDetailResponse? = nil,
        seriesDetail: XtreamCodesAPIService.SeriesDetailResponse? = nil
    ) {
        self.item = item
        self._vodDetail = State(initialValue: vodDetail)
        self._seriesDetail = State(initialValue: seriesDetail)
        self._isLoadingDetails = State(initialValue: vodDetail == nil && seriesDetail == nil)
        if let firstSeason = seriesDetail?.seasons.first?.seasonNumber {
            self._selectedSeason = State(initialValue: firstSeason)
        } else if let firstEpSeason = seriesDetail?.episodes.first?.seasonNum {
            self._selectedSeason = State(initialValue: firstEpSeason)
        }
    }

    public init(payload: MediaDetailPayload) {
        self.init(item: payload.item, vodDetail: payload.vodDetail, seriesDetail: payload.seriesDetail)
    }

    // MARK: - Computed Properties for Media Info (Server Data)

    private var isFavorite: Bool {
        storage.isFavorite(id: item.id)
    }

    private var isInWatchlist: Bool {
        storage.isInWatchlist(id: item.id)
    }

    private var backdropImageUrl: String? {
        vodDetail?.backdropUrl ?? seriesDetail?.backdropUrl ?? item.backdropUrl
    }

    private var posterImageUrl: String? {
        vodDetail?.movieImage ?? seriesDetail?.cover ?? item.streamIcon
    }

    private var displayTitle: String {
        item.name
    }

    private var displayRating: String? {
        let r = vodDetail?.rating ?? seriesDetail?.rating ?? item.rating
        guard let r = r?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty,
              let score = Double(r), score > 0 else { return nil }
        return String(format: "%.1f", score)
    }

    private var displayReleaseYear: String? {
        let raw = vodDetail?.releaseDate ?? seriesDetail?.releaseDate ?? item.releaseDate
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.count >= 4 {
            return String(raw.prefix(4))
        }
        return raw
    }

    private var displayDurationOrSeasons: String? {
        if item.type == .series {
            let seasonCount = seasons.count
            let episodeCount = seriesDetail?.episodes.count ?? 0
            if seasonCount > 0 && episodeCount > 0 {
                return "\(seasonCount) Sezon • \(episodeCount) Bölüm"
            } else if seasonCount > 0 {
                return "\(seasonCount) Sezon"
            }
            return nil
        } else {
            let rawDur = vodDetail?.duration ?? item.duration
            return formatDuration(rawDur)
        }
    }

    private var displayGenres: [String] {
        let raw = vodDetail?.genre ?? seriesDetail?.genre ?? item.genre ?? ""
        return raw.split { $0 == "," || $0 == "/" || $0 == "•" || $0 == "|" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var displayDirector: String? {
        let d = vodDetail?.director ?? seriesDetail?.director ?? item.director
        guard let d = d?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty else { return nil }
        return d
    }

    private var displayCast: String? {
        let c = vodDetail?.cast ?? seriesDetail?.cast ?? item.cast
        guard let c = c?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return nil }
        return c
    }

    private var displayCountry: String? {
        let c = vodDetail?.country ?? seriesDetail?.country ?? item.country
        guard let c = c?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return nil }
        return c
    }

    private var displayAgeRating: String? {
        let a = vodDetail?.age ?? vodDetail?.mpaaRating ?? seriesDetail?.age ?? seriesDetail?.mpaaRating ?? item.age ?? item.mpaaRating
        guard let a = a?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty else { return nil }
        return a
    }

    private var displayOverview: String? {
        let plot = vodDetail?.plot ?? seriesDetail?.plot ?? item.overview
        guard let plot = plot?.trimmingCharacters(in: .whitespacesAndNewlines), !plot.isEmpty else { return nil }
        return plot
    }

    private var youtubeTrailerUrl: URL? {
        let raw = vodDetail?.youtubeTrailer ?? seriesDetail?.youtubeTrailer ?? item.youtubeTrailer
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            return URL(string: raw)
        }
        return URL(string: "https://www.youtube.com/watch?v=\(raw)")
    }

    private var youtubeVideoId: String? {
        let raw = vodDetail?.youtubeTrailer ?? seriesDetail?.youtubeTrailer ?? item.youtubeTrailer
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.contains("v=") {
            let parts = raw.components(separatedBy: "v=")
            if let last = parts.last?.components(separatedBy: "&").first, !last.isEmpty {
                return last
            }
        } else if raw.contains("youtu.be/") {
            let parts = raw.components(separatedBy: "youtu.be/")
            if let last = parts.last?.components(separatedBy: "?").first, !last.isEmpty {
                return last
            }
        } else if !raw.contains("/") && !raw.contains("http") {
            return raw
        }
        return nil
    }

    private var trailerThumbnailUrl: String? {
        if let videoId = youtubeVideoId {
            return "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg"
        }
        return backdropImageUrl ?? posterImageUrl
    }

    private var seasons: [Int] {
        if let eps = seriesDetail?.episodes, !eps.isEmpty {
            let set = Set(eps.map { $0.seasonNum })
            return Array(set).sorted()
        }
        if let sInfos = seriesDetail?.seasons, !sInfos.isEmpty {
            return sInfos.map { $0.seasonNumber }.sorted()
        }
        return [1]
    }

    private var currentSeasonEpisodes: [Episode] {
        guard let eps = seriesDetail?.episodes else { return [] }
        return eps.filter { $0.seasonNum == selectedSeason }
    }

    // MARK: - View Body

    public var body: some View {
        ZStack(alignment: .top) {
            // 1. Koyu Zemin
            Color(red: 0.05, green: 0.05, blue: 0.07)
                .ignoresSafeArea()

            // 2. Ekranın En Üstüne Sabitlenen Backdrop Resmi (Bağımsız Katman)
            stickyBackdropLayer

            // 3. Kaydırılabilir İçerik
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Arka plandaki görselin üst kısmının net görünmesi için üst boşluk
                    Color.clear
                        .frame(height: 190)

                    // Poster ve Tüm Verileri İçeren Kapsayıcı (Aşağıdan yukarıya siyah geçiş + blur efektli)
                    mainContentContainer
                }
            }
        }
        .toolbar {
            #if !os(tvOS)
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: item.name, subject: Text(item.name), message: Text("\(item.name) - MyTV'de İzle")) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.white)
                }
                .tint(.white)
            }
            #endif

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        storage.toggleFavorite(id: item.id)
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? .red : .white)
                }
                .tint(.white)
            }
        }
        #if !os(macOS)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        #endif
        .task {
            await fetchServerDetails()
        }
    }

    // MARK: - Main Content Container (Poster ve Tüm Bilgilerin Bulunduğu Kapsayıcı)

    @ViewBuilder
    private var mainContentContainer: some View {
        VStack(spacing: 0) {
            // 1. Hero Bilgi Alanı (Afiş, Başlık, Meta Rozetleri, Butonlar)
            heroInformationSection
                .padding(.horizontal, 20)
                .padding(.top, 20)

            // 2. Detay Alanı (Türler, Konu Özeti, Künye Bilgileri)
            detailsContentSection
                .padding(.horizontal, 20)
                .padding(.top, 24)

            // 3. Fragmanlar Alanı (Apple TV Tarzı)
            trailersSection
                .padding(.horizontal, 20)
                .padding(.top, 28)

            // 4. Diziler İçin Sezonlar & Bölümler
            if item.type == .series {
                seriesEpisodesSection
                    .padding(.top, 28)
            }

            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack(alignment: .top) {
                // Aşağıdan Yukarıya Blur / Frosted Glass Katmanı
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black.opacity(0.6), location: 0.12),
                                .init(color: .black, location: 0.28)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Aşağıdan Yukarıya Siyah / Koyu Degrade Geçiş
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.7), location: 0.10),
                        .init(color: Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.95), location: 0.24),
                        .init(color: Color(red: 0.05, green: 0.05, blue: 0.07), location: 0.40)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Sticky Backdrop Layer (Sunucudan Gelen Yatay Görsel)

    @ViewBuilder
    private var stickyBackdropLayer: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // 1. Koyu Zemin
                Color(red: 0.05, green: 0.05, blue: 0.07)

                // 2. Anında Gösterilen Katman: Elimizdeki afişten üretilen sinematik ambient arkaplan (0ms bekleme)
                ambientBackdropPlaceholder(width: geo.size.width)

                // 3. Yüksek Çözünürlüklü Yatay Görsel Katmanı (Detay yanıtı / TMDB hazır olduğunda üstüne pürüzsüzce yerleşir)
                if let url = URL.fromUserString(backdropImageUrl) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: 380)
                            .clipped()
                    } placeholder: {
                        Color.clear
                    }
                    .id(url.absoluteString)
                    .transition(.opacity)
                }

                // 4. Sayfa Zeminine Doğru Koyu Degrade
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.3), location: 0.4),
                        .init(color: Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.85), location: 0.72),
                        .init(color: Color(red: 0.05, green: 0.05, blue: 0.07), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 380)
            }
        }
        .frame(height: 380)
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private func ambientBackdropPlaceholder(width: CGFloat) -> some View {
        if let posterUrl = URL.fromUserString(posterImageUrl) {
            CachedAsyncImage(url: posterUrl) { img in
                img
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: 380)
                    .blur(radius: 40)
                    .scaleEffect(1.25)
                    .opacity(0.4)
                    .clipped()
            } placeholder: {
                LinearGradient(
                    colors: [Color(red: 0.12, green: 0.12, blue: 0.18), Color(red: 0.05, green: 0.05, blue: 0.07)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 380)
            }
        } else {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.12, blue: 0.18), Color(red: 0.05, green: 0.05, blue: 0.07)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 380)
        }
    }

    // MARK: - Hero Information Section

    @ViewBuilder
    private var heroInformationSection: some View {
        HStack(alignment: .bottom, spacing: 16) {
            // 1. Sola Yaslı Dikey Afiş (Poster)
            posterCardView

            // 2. Başlık & Meta Rozetleri
            VStack(alignment: .leading, spacing: 8) {
                // Başlık Metni
                Text(displayTitle)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.7), radius: 6, x: 0, y: 2)

                // Meta Rozetleri (Tür / Puan / Yıl / Süre)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        // Tip Etiketi (FİLM / DİZİ)
                        Text(item.type.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .foregroundStyle(.white)

                        // Puan Rozeti
                        if let rating = displayRating {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.yellow)
                                Text(rating)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }

                        // Çıkış Yılı
                        if let year = displayReleaseYear {
                            Text(year)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }

                    // Süre & Yaş Sınırı
                    HStack(spacing: 8) {
                        if let dur = displayDurationOrSeasons {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.7))
                                Text(dur)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }

                        if let age = displayAgeRating {
                            Text(age)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.4), lineWidth: 0.8))
                                .foregroundStyle(.white.opacity(0.9))
                        }

                        // HD Rozeti
                        Text("HD")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.brandPrimary.opacity(0.8), lineWidth: 0.8))
                            .foregroundStyle(Color.brandPrimary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Ana Aksiyon Butonları (Oynat, Listem - .buttonStyle(.glass))
        HStack(spacing: 10) {
            // 1. Glass Oynat Butonu
            Button {
                handlePrimaryPlay()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(item.type == .series ? "İlk Bölüm" : "Oynat")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
            }
            .buttonStyle(.glass)

            // 2. Listeye Ekle / Listem İkon Butonu (Apple SF Symbol Transition)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    storage.toggleWatchlist(id: item.id)
                }
            } label: {
                Image(systemName: isInWatchlist ? "checkmark" : "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.glass)
        }
        .padding(.top, 14)
    }

    // MARK: - Dikey Afiş Kartı (Poster)

    @ViewBuilder
    private var posterCardView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))

            if let url = URL.fromUserString(posterImageUrl) {
                CachedAsyncImage(url: url) { img in
                    img
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.white.opacity(0.05)
                        Image(systemName: item.type == .series ? "tv" : "film")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            } else {
                ZStack {
                    Color.white.opacity(0.05)
                    Image(systemName: item.type == .series ? "tv" : "film")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .frame(width: 105, height: 155)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
    }

    // MARK: - Details Content Section (Türler, Konu Özeti, Künye)

    @ViewBuilder
    private var detailsContentSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Tür Etiketleri
            if !displayGenres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(displayGenres, id: \.self) { genre in
                            Text(genre)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.08), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                        }
                    }
                }
            }

            // 2. Konu Özeti (Plot / Overview)
            if let overview = displayOverview {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Konu")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)

                    Text(overview)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineSpacing(4)
                        .lineLimit(isOverviewExpanded ? nil : 3)
                        .animation(.easeInOut(duration: 0.2), value: isOverviewExpanded)

                    if overview.count > 140 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isOverviewExpanded.toggle()
                            }
                        } label: {
                            Text(isOverviewExpanded ? "Daha Az Göster" : "Daha Fazla Gör")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.brandPrimary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            }

            // 3. Künye Bilgi Kartı (Yönetmen, Oyuncular, Ülke)
            if displayDirector != nil || displayCast != nil || displayCountry != nil {
                VStack(alignment: .leading, spacing: 12) {
                    if let director = displayDirector {
                        infoRow(icon: "person.crop.circle", title: "Yönetmen", value: director)
                    }

                    if let cast = displayCast {
                        infoRow(icon: "person.2", title: "Oyuncular", value: cast)
                    }

                    if let country = displayCountry {
                        infoRow(icon: "globe.americas", title: "Ülke", value: country)
                    }

                    if let releaseDate = vodDetail?.releaseDate ?? seriesDetail?.releaseDate ?? item.releaseDate, !releaseDate.isEmpty {
                        infoRow(icon: "calendar", title: "Yayın Tarihi", value: releaseDate)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - Info Row Helper

    @ViewBuilder
    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.brandPrimary.opacity(0.9))
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))

                Text(value)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Apple TV Style Trailers Section (Fragmanlar)

    @ViewBuilder
    private var trailersSection: some View {
        if let trailerUrl = youtubeTrailerUrl {
            VStack(alignment: .leading, spacing: 14) {
                // Bölüm Başlığı (Fragmanlar >)
                Button {
                    openURL(trailerUrl)
                } label: {
                    HStack(spacing: 6) {
                        Text("Fragmanlar")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .buttonStyle(.plain)

                // 16:9 Sinematik Fragman Kartı (Apple TV Tasarımı)
                Button {
                    openURL(trailerUrl)
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        // Arka Plan Görseli (YouTube HQ Küçük Resmi veya Backdrop)
                        if let thumbUrl = URL.fromUserString(trailerThumbnailUrl) {
                            CachedAsyncImage(url: thumbUrl) { img in
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 270, height: 152)
                                    .clipped()
                            } placeholder: {
                                ZStack {
                                    Color.white.opacity(0.06)
                                    Image(systemName: "film")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                                .frame(width: 270, height: 152)
                            }
                        } else {
                            ZStack {
                                Color.white.opacity(0.06)
                                Image(systemName: "film")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            .frame(width: 270, height: 152)
                        }

                        // Okunabilirlik İçin Alt Koyu Degrade
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black.opacity(0.25), location: 0.45),
                                .init(color: .black.opacity(0.85), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: 270, height: 152)

                        // Kart İçi Metin & Rozet Alanı
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayTitle)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8))
                                Text(displayGenres.first ?? "Fragman")
                                    .font(.system(size: 11, weight: .medium))

                                Spacer()

                                Image(systemName: "ellipsis")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                        .frame(width: 270, alignment: .leading)
                    }
                    .frame(width: 270, height: 152)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Series Seasons & Episodes Section (Diziler İçin)

    @ViewBuilder
    private var seriesEpisodesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Başlık & Sezon Seçici
            VStack(alignment: .leading, spacing: 12) {
                Text("Bölümler")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)

                // Sezon Kapsülleri (1. Sezon, 2. Sezon ...)
                if seasons.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(seasons, id: \.self) { sNum in
                                let isSelected = (selectedSeason == sNum)
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedSeason = sNum
                                    }
                                } label: {
                                    Text("\(sNum). Sezon")
                                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                        .foregroundStyle(isSelected ? .black : .white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            isSelected ? Color.white : Color.white.opacity(0.08),
                                            in: Capsule()
                                        )
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.12), lineWidth: 0.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }

            // Bölüm Kartları Listesi
            let episodes = currentSeasonEpisodes
            if episodes.isEmpty {
                if isLoadingDetails {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                            .padding(.vertical, 24)
                        Spacer()
                    }
                } else {
                    Text("Bu sezona ait bölüm bulunamadı.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(episodes) { ep in
                        episodeRowView(episode: ep)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Episode Row Card View

    @ViewBuilder
    private func episodeRowView(episode: Episode) -> some View {
        Button {
            playEpisode(episode)
        } label: {
            HStack(spacing: 14) {
                // Bölüm Kapak Görseli ve Oynat Butonu
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))

                    if let url = URL.fromUserString(episode.coverUrl ?? backdropImageUrl ?? posterImageUrl) {
                        CachedAsyncImage(url: url) { img in
                            img
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.white.opacity(0.05)
                        }
                    }

                    // Play Overlay Icon
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.5), radius: 4)

                    // Süre Rozeti
                    if let dur = episode.duration, !dur.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(formatDuration(dur))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                                    .padding(4)
                            }
                        }
                    }
                }
                .frame(width: 110, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )

                // Bölüm Başlığı & Bilgileri
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(episode.episodeNum). \(episode.title)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let plot = episode.overview, !plot.isEmpty {
                        Text(plot)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                            .lineSpacing(2)
                    } else {
                        Text("Bölüm \(episode.episodeNum)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(10)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Playback Actions

    private func handlePrimaryPlay() {
        if item.type == .series {
            if let firstEp = currentSeasonEpisodes.first ?? seriesDetail?.episodes.first {
                playEpisode(firstEp)
            }
        } else {
            let media = PlayableMedia(
                mediaId: item.id,
                title: item.name,
                subtitle: displayGenres.first ?? "Film",
                posterUrl: posterImageUrl,
                streamUrl: item.streamUrl,
                contentType: .movie,
                rating: displayRating,
                releaseDate: displayReleaseYear,
                duration: displayDurationOrSeasons,
                overview: displayOverview,
                genre: vodDetail?.genre ?? item.genre,
                director: displayDirector
            )
            playback.play(media: media)
        }
    }

    private func playEpisode(_ episode: Episode) {
        let media = PlayableMedia(
            mediaId: episode.id,
            title: item.name,
            subtitle: "S\(episode.seasonNum):B\(episode.episodeNum) • \(episode.title)",
            posterUrl: episode.coverUrl ?? posterImageUrl,
            streamUrl: episode.streamUrl,
            contentType: .series,
            rating: displayRating,
            releaseDate: displayReleaseYear,
            duration: episode.duration,
            overview: episode.overview ?? displayOverview,
            genre: seriesDetail?.genre ?? item.genre,
            director: displayDirector,
            seriesId: item.id,
            episodeNum: episode.episodeNum,
            seasonNum: episode.seasonNum
        )
        playback.play(media: media)
    }

    // MARK: - Data Fetching (Sunucu Detayları)

    private func fetchServerDetails() async {
        if vodDetail != nil || seriesDetail != nil {
            return
        }

        guard let account = storage.activeAccount, account.type == .xtream else {
            isLoadingDetails = false
            return
        }

        isLoadingDetails = true

        if item.type == .movie {
            if let detail = try? await XtreamCodesAPIService.shared.getVODInfo(account: account, vodId: item.id) {
                await MainActor.run {
                    self.vodDetail = detail
                }
            }
        } else if item.type == .series {
            if let detail = try? await XtreamCodesAPIService.shared.getSeriesDetails(account: account, seriesId: item.id) {
                await MainActor.run {
                    self.seriesDetail = detail
                    if let firstSeason = detail.seasons.first?.seasonNumber {
                        self.selectedSeason = firstSeason
                    } else if let firstEpSeason = detail.episodes.first?.seasonNum {
                        self.selectedSeason = firstEpSeason
                    }
                }
            }
        }

        await MainActor.run {
            self.isLoadingDetails = false
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return "" }

        if raw.contains(":") {
            let parts = raw.split(separator: ":").compactMap { Int($0) }
            if parts.count >= 2 {
                let hours = parts[0]
                let minutes = parts[1]
                if hours > 0 {
                    return "\(hours)s \(minutes)dk"
                } else {
                    return "\(minutes) dk"
                }
            }
        }

        let digitsOnly = raw.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if let totalMinutes = Int(digitsOnly), totalMinutes > 0 {
            if totalMinutes >= 60 {
                let h = totalMinutes / 60
                let m = totalMinutes % 60
                return m > 0 ? "\(h)s \(m)dk" : "\(h) saat"
            } else {
                return "\(totalMinutes) dk"
            }
        }

        return raw
    }
}
