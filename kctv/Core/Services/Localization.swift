import Foundation

/// Uygulama genelinde desteklenen diller.
enum AppLanguage: String, CaseIterable, Sendable {
    case system = "system"
    case turkish = "tr"
    case english = "en"

    private static let userDefaultsKey = "app_language_preference"

    /// Kullanıcının seçtiği ya da varsayılan dil tercihi.
    static var current: AppLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let lang = AppLanguage(rawValue: raw) else {
                return .system
            }
            return lang
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
            NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        }
    }

    /// Cihaz diline veya seçime göre aktif olan dil kodu ("tr" veya "en").
    var effectiveLanguageCode: String {
        switch self {
        case .turkish:
            return "tr"
        case .english:
            return "en"
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "tr"
            return preferred.starts(with: "en") ? "en" : "tr"
        }
    }

    /// TMDB API sorguları için dil parametresi ("tr-TR" veya "en-US").
    var tmdbLanguageCode: String {
        effectiveLanguageCode == "en" ? "en-US" : "tr-TR"
    }

    /// Ayarlar ekranında gösterilecek başlık.
    var displayName: String {
        switch self {
        case .system:
            return effectiveLanguageCode == "en" ? "System Default" : "Sistem Dili"
        case .turkish:
            return "Türkçe"
        case .english:
            return "English"
        }
    }
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("kctv.appLanguageDidChange")
}

/// Statik arayüz metinlerinin Türkçe ve İngilizce karşılıkları.
enum L10n {
    private static var isTurkish: Bool {
        AppLanguage.current.effectiveLanguageCode == "tr"
    }

    // MARK: - Tab Bar
    static var tabHome: String { isTurkish ? "Ana Sayfa" : "Home" }
    static var tabSearch: String { isTurkish ? "Ara" : "Search" }
    static var tabFavorites: String { isTurkish ? "Favoriler" : "Favorites" }
    static var tabPlaylists: String { isTurkish ? "Listeler" : "Playlists" }
    static var tabSettings: String { isTurkish ? "Ayarlar" : "Settings" }

    // MARK: - Detay Ekranı (Detail)
    static var play: String { isTurkish ? "Oynat" : "Play" }
    static var resume: String { isTurkish ? "Sürdür" : "Resume" }
    static var playFirstEpisode: String { isTurkish ? "İlk Bölümü Oynat" : "Play Episode 1" }
    static var episodes: String { isTurkish ? "Bölümler" : "Episodes" }
    static var season: String { isTurkish ? "Sezon" : "Season" }
    static var more: String { isTurkish ? "DAHA FAZLASI" : "MORE" }
    static var less: String { isTurkish ? "DAHA AZ" : "LESS" }
    static var castAndCrew: String { isTurkish ? "Künye ve Oyuncular" : "Cast & Crew" }
    static var relatedContent: String { isTurkish ? "Benzer İçerikler" : "Similar Content" }
    static var director: String { isTurkish ? "Yönetmen" : "Director" }
    static var cast: String { isTurkish ? "Oyuncular" : "Cast" }
    static var genre: String { isTurkish ? "Tür" : "Genre" }
    static var releaseYear: String { isTurkish ? "Yıl" : "Year" }

    // MARK: - Ana Sayfa (Home) & Katalog
    static var continueWatching: String { isTurkish ? "İzlemeye Devam Et" : "Continue Watching" }
    static var liveTV: String { isTurkish ? "Canlı Yayın" : "Live TV" }
    static var movies: String { isTurkish ? "Filmler" : "Movies" }
    static var series: String { isTurkish ? "Diziler" : "Series" }
    static var recentlyAdded: String { isTurkish ? "Son Eklenenler" : "Recently Added" }
    static var allCategories: String { isTurkish ? "Tüm Kategoriler" : "All Categories" }
    static var seeAll: String { isTurkish ? "Tümünü Gör" : "See All" }

    // MARK: - Arama (Search)
    static var searchPlaceholder: String { isTurkish ? "Film, dizi veya kanal ara..." : "Search movies, series or channels..." }
    static var noSearchResults: String { isTurkish ? "Sonuç bulunamadı" : "No results found" }
    static var searchPrompt: String { isTurkish ? "Aramak istediğiniz başlığı yazın" : "Type a title to start searching" }

    // MARK: - Favoriler (Favorites)
    static var favoritesEmptyTitle: String { isTurkish ? "Favori Listeniz Boş" : "No Favorites Yet" }
    static var favoritesEmptyMessage: String { isTurkish ? "İçerik detayındaki artı butonuna dokunarak favorilerinize ekleyebilirsiniz." : "Tap the plus button on any content detail to add it to your favorites." }

    // MARK: - Ayarlar (Settings)
    static var settingsTitle: String { isTurkish ? "Ayarlar" : "Settings" }
    static var sectionAccount: String { isTurkish ? "Hesap" : "Account" }
    static var sectionLanguage: String { isTurkish ? "Dil / Language" : "Language" }
    static var sectionContent: String { isTurkish ? "İçerik" : "Content" }
    static var languageOption: String { isTurkish ? "Uygulama Dili" : "App Language" }
    static var guestUser: String { isTurkish ? "Misafir" : "Guest" }
    static var regularUser: String { isTurkish ? "Kullanıcı" : "User" }
    static var demoModeNote: String { isTurkish ? "Demo modunda geziliyor" : "Browsing in demo mode" }
    static var signOut: String { isTurkish ? "Çıkış Yap" : "Sign Out" }
    static var reloadPlaylist: String { isTurkish ? "Listeyi Yenile" : "Reload Playlist" }
    static var subscriptionExpires: String { isTurkish ? "Abonelik bitişi" : "Subscription expires" }
    static var activeConnections: String { isTurkish ? "Bağlantı" : "Connections" }

    // MARK: - Giriş & Onboarding (Auth & Playlists)
    static var appTagline: String { isTurkish ? "Kendi listeni ekle, bütün cihazlarında aynı yerden izle." : "Add your playlist, watch everywhere seamlessly." }
    static var signInWithApple: String { isTurkish ? "Apple ile Giriş Yap" : "Sign in with Apple" }
    static var signInWithGoogle: String { isTurkish ? "Google ile Giriş Yap" : "Sign in with Google" }
    static var continueAsGuest: String { isTurkish ? "Misafir Olarak Devam Et" : "Continue as Guest" }
    static var addPlaylist: String { isTurkish ? "Çalma Listesi Ekle" : "Add Playlist" }
    static var playlistName: String { isTurkish ? "Liste Adı" : "Playlist Name" }
    static var serverURL: String { isTurkish ? "Sunucu Adresi (URL)" : "Server URL" }
    static var username: String { isTurkish ? "Kullanıcı Adı" : "Username" }
    static var password: String { isTurkish ? "Şifre" : "Password" }
    static var save: String { isTurkish ? "Kaydet" : "Save" }
    static var cancel: String { isTurkish ? "Vazgeç" : "Cancel" }
    static var close: String { isTurkish ? "Kapat" : "Close" }
    static var error: String { isTurkish ? "Hata" : "Error" }
}
