import Foundation

/// Arama ekranındaki hazır arama kartı.
///
/// Kart tek bir sağlayıcı kategorisine değil, **bir türe** karşılık geliyor:
/// "Aksiyon Filmleri" listede birden çok kategoriyi kapsayabiliyor (çoğu
/// listede "TR | AKSİYON" ve "4K AKSİYON" ayrı kategoriler). Bu yüzden kart
/// kapsadığı kategori kimliklerini birlikte taşıyor; açıldığında hepsi
/// birleştirilip tek liste olarak gösteriliyor.
///
/// Kartın kendisi içerik **taşımıyor**: diffable veri kaynağı her güncellemede
/// öğeleri karşılaştırıyor ve on binlerce `MediaItem`'ı kartın içinde taşımak
/// her karşılaştırmayı ağırlaştırırdı. İçerik yalnızca karta dokunulduğunda
/// katalog indeksinden çözülüyor.
///
/// Kartta afiş yok: bir türü kategorideki ilk afişle temsil etmek yanıltıcı
/// duruyordu, kimliği artık renk ve simge veriyor.
struct SearchSuggestion: Hashable, Sendable {
    var id: String
    var title: String
    var kind: MediaKind
    var symbol: String
    /// Kartta gösterilmiyor; kartın açılmaya değer olup olmadığına bakarken
    /// ve kategori kartlarını sıralarken kullanılıyor.
    var itemCount: Int
    var categoryIDs: [String]
}

/// Hazır arama kartlarında kullanılan tür sözlüğü.
///
/// Sağlayıcılar tür bilgisini ayrı bir alanda vermiyor; tek ipucu kategori
/// adı ("FİLM - BİLİM KURGU", "4K AKSİYON/MACERA"). Bu yüzden türler kategori
/// adlarındaki anahtar kelimelerden çıkarılıyor.
enum SearchGenre: String, CaseIterable, Sendable {
    case action
    case comedy
    case sciFi
    case drama
    case thriller
    case horror
    case romance
    case animation
    case family
    case adventure
    case crime
    case fantasy
    case documentary
    case war
    case western

    private var isTurkish: Bool { AppLanguage.current.effectiveLanguageCode == "tr" }

    /// Türün adı — kart başlığı buna içerik türü eklenerek kuruluyor.
    private var name: String {
        switch self {
        case .action: isTurkish ? "Aksiyon" : "Action"
        case .comedy: isTurkish ? "Komedi" : "Comedy"
        case .sciFi: isTurkish ? "Bilim Kurgu" : "Sci-Fi"
        case .drama: isTurkish ? "Dram" : "Drama"
        case .thriller: isTurkish ? "Gerilim" : "Thriller"
        case .horror: isTurkish ? "Korku" : "Horror"
        case .romance: isTurkish ? "Romantik" : "Romance"
        case .animation: isTurkish ? "Animasyon" : "Animation"
        case .family: isTurkish ? "Aile" : "Family"
        case .adventure: isTurkish ? "Macera" : "Adventure"
        case .crime: isTurkish ? "Suç" : "Crime"
        case .fantasy: isTurkish ? "Fantastik" : "Fantasy"
        case .documentary: isTurkish ? "Belgesel" : "Documentary"
        case .war: isTurkish ? "Savaş" : "War"
        case .western: isTurkish ? "Western" : "Western"
        }
    }

    /// Türkçede tür adı sıfatsa çoğul eki değişiyor: "Romantik Filmler" ama
    /// "Aksiyon Filmleri".
    private var isTurkishAdjective: Bool {
        self == .romance || self == .fantasy
    }

    var symbol: String {
        switch self {
        case .action: "flame.fill"
        case .comedy: "face.smiling"
        case .sciFi: "sparkles"
        case .drama: "theatermasks.fill"
        case .thriller: "bolt.fill"
        case .horror: "moon.fill"
        case .romance: "heart.fill"
        case .animation: "pawprint.fill"
        case .family: "figure.2.and.child.holdinghands"
        case .adventure: "map.fill"
        case .crime: "shield.lefthalf.filled"
        case .fantasy: "wand.and.stars"
        case .documentary: "book.closed.fill"
        case .war: "airplane"
        case .western: "sun.horizon.fill"
        }
    }

    /// Kategori adlarında aranan anahtar kelimeler. Hepsi katlanmış (küçük
    /// harf, aksansız) yazılıyor; karşılaştırma da katlanmış metin üzerinde.
    var keywords: [String] {
        switch self {
        case .action: ["aksiyon", "action"]
        case .comedy: ["komedi", "comedy", "komik"]
        case .sciFi: ["bilim kurgu", "bilimkurgu", "bilim-kurgu", "science fiction", "sci-fi", "scifi"]
        case .drama: ["dram", "drama"]
        case .thriller: ["gerilim", "thriller", "suspense"]
        case .horror: ["korku", "horror"]
        case .romance: ["romantik", "romance", "romantic"]
        case .animation: ["animasyon", "animation", "anime", "cizgi", "cartoon"]
        case .family: ["aile", "family", "cocuk", "kids"]
        case .adventure: ["macera", "adventure"]
        case .crime: ["suc", "polisiye", "crime", "mafya", "gangster"]
        case .fantasy: ["fantastik", "fantasy", "fantezi"]
        case .documentary: ["belgesel", "documentary"]
        case .war: ["savas", "harp", "askeri"]
        case .western: ["western", "kovboy"]
        }
    }

    /// Kart başlığı — "Aksiyon Filmleri", "Action Movies".
    func title(for kind: MediaKind) -> String {
        guard kind != .live else { return name }
        if isTurkish {
            // Belgesellerde "Belgesel Filmleri" kulağa yanlış geliyor.
            if self == .documentary { return kind == .movie ? "Belgeseller" : "Belgesel Diziler" }
            let suffix = kind == .movie
                ? (isTurkishAdjective ? "Filmler" : "Filmleri")
                : (isTurkishAdjective ? "Diziler" : "Dizileri")
            return "\(name) \(suffix)"
        }
        return "\(name) \(kind == .movie ? "Movies" : "Series")"
    }

    /// Kategori adı bu türle eşleşiyor mu?
    ///
    /// Eşleşme kelime başından: Türkçede tür adları çekimlenerek geçiyor
    /// ("BELGESELLER", "KOMEDİLER") ve tam eşitlik bunları kaçırıyor. Kelimenin
    /// ortasında aramak ise yanlış eşleşme üretiyordu — "WARNER" içinde "war",
    /// "MASKELİ" içinde "aşk". Kısa anahtarlarda (5 harften az) kelimenin
    /// tamamı aranıyor, uzunlarda başlangıcı yetiyor.
    func matches(_ categoryName: String) -> Bool {
        let haystack = " " + Self.folded(categoryName) + " "
        return keywords.contains { keyword in
            keyword.count >= 5
                ? haystack.contains(" " + keyword)
                : haystack.contains(" " + keyword + " ")
        }
    }

    /// Büyük/küçük harf ve aksan farkını siler, ayırıcıları boşluğa çevirir:
    /// "🎬 4K | BİLİM-KURGU" → "4k bilim kurgu".
    private static func folded(_ text: String) -> String {
        let lowered = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let separated = lowered.map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(separated).split(separator: " ").joined(separator: " ")
    }
}

/// Hazır arama kartlarını katalogdan üretir.
///
/// Tarama katalogda değil **kategori listesinde** yapılıyor: kategoriler
/// birkaç yüz kayıt, katalog on binlerce. İçerik sayısı kütüphanenin
/// hazır kategori indeksinden okunuyor.
enum SearchSuggestionBuilder {
    /// Kart olmaya değecek en az içerik sayısı.
    private static let minimumItemCount = 6
    /// Bir içerik türü için en fazla kart.
    private static let limitPerKind = 12

    @MainActor
    static func suggestions(for kinds: [MediaKind], in library: ContentLibrary) -> [SearchSuggestion] {
        kinds.flatMap { suggestions(for: $0, in: library) }
    }

    /// Karta dokunulduğunda listelenecek içerikler.
    /// Katalogda aynı yayın birden çok kez bulunabiliyor; tekrarlar eleniyor.
    @MainActor
    static func items(for suggestion: SearchSuggestion, in library: ContentLibrary) -> [MediaItem] {
        var seen = Set<MediaID>()
        return suggestion.categoryIDs
            .flatMap { library.items(kind: suggestion.kind, categoryID: $0) }
            .filter { seen.insert($0.id).inserted }
    }

    @MainActor
    private static func suggestions(for kind: MediaKind, in library: ContentLibrary) -> [SearchSuggestion] {
        let categories = library.categories[kind] ?? []
        guard !categories.isEmpty else { return [] }

        // Canlı yayında tür kavramı yok; oradaki kartlar doğrudan sağlayıcının
        // kategorileri ("SPOR", "HABER").
        guard kind != .live else {
            return categoryCards(categories, kind: kind, in: library)
        }

        var cards: [SearchSuggestion] = []
        var claimed = Set<String>()

        for genre in SearchGenre.allCases {
            let matching = categories.filter { genre.matches($0.name) }
            guard !matching.isEmpty else { continue }

            let ids = matching.map(\.id)
            let count = ids.reduce(0) { $0 + library.items(kind: kind, categoryID: $1).count }
            guard count >= minimumItemCount else { continue }

            claimed.formUnion(ids)
            cards.append(SearchSuggestion(
                id: "\(kind.rawValue).\(genre.rawValue)",
                title: genre.title(for: kind),
                kind: kind,
                symbol: genre.symbol,
                itemCount: count,
                categoryIDs: ids
            ))
            if cards.count == limitPerKind { break }
        }

        // Kategori adları tür sözlüğüne hiç uymuyorsa (bazı M3U listelerinde
        // gruplar "TR VOD 1" gibi adsız) ekran boş kalmasın: en dolu
        // kategoriler olduğu gibi kart oluyor.
        if cards.count < 3 {
            let remaining = categories.filter { !claimed.contains($0.id) }
            cards += categoryCards(remaining, kind: kind, in: library)
                .prefix(limitPerKind - cards.count)
        }
        return cards
    }

    /// Sağlayıcı kategorilerinden kart: en çok içeriği olanlar önce.
    @MainActor
    private static func categoryCards(
        _ categories: [MediaCategory],
        kind: MediaKind,
        in library: ContentLibrary
    ) -> [SearchSuggestion] {
        categories
            .map { (category: $0, count: library.items(kind: kind, categoryID: $0.id).count) }
            .filter { $0.count >= minimumItemCount }
            .sorted { $0.count > $1.count }
            .prefix(limitPerKind)
            .map { entry in
                SearchSuggestion(
                    id: "\(kind.rawValue).category.\(entry.category.id)",
                    title: entry.category.name,
                    kind: kind,
                    symbol: kind.symbol,
                    itemCount: entry.count,
                    categoryIDs: [entry.category.id]
                )
            }
    }

}
