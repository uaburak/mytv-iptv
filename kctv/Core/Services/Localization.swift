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
    static var nextEpisode: String { isTurkish ? "Sıradaki Bölüm" : "Next Episode" }
    static var episodes: String { isTurkish ? "Bölümler" : "Episodes" }
    static var season: String { isTurkish ? "Sezon" : "Season" }
    static var more: String { isTurkish ? "DAHA FAZLASI" : "MORE" }
    static var less: String { isTurkish ? "DAHA AZ" : "LESS" }
    static var castAndCrew: String { isTurkish ? "Künye ve Detaylar" : "Cast & Details" }
    static var relatedContent: String { isTurkish ? "Benzer İçerikler" : "Similar Content" }
    static var director: String { isTurkish ? "Yönetmen" : "Director" }
    static var cast: String { isTurkish ? "Oyuncular" : "Cast" }
    static var genre: String { isTurkish ? "Tür" : "Genre" }
    static var releaseYear: String { isTurkish ? "Yıl" : "Year" }
    static var originalTitle: String { isTurkish ? "Orijinal Başlık" : "Original Title" }
    static var status: String { isTurkish ? "Durum" : "Status" }
    static var country: String { isTurkish ? "Ülke" : "Country" }
    static var runtime: String { isTurkish ? "Süre" : "Runtime" }
    static var info: String { isTurkish ? "Bilgi" : "Info" }
    static var watchTrailer: String { isTurkish ? "Fragman" : "Trailer" }

    // MARK: - Ana Sayfa (Home) & Katalog
    static var moreInfo: String { isTurkish ? "Daha Fazla Bilgi" : "More Info" }
    static var continueWatching: String { isTurkish ? "İzlemeye Devam Et" : "Continue Watching" }
    static var myWatchlist: String { isTurkish ? "İzleme Listem" : "My Watchlist" }
    static var liveTV: String { isTurkish ? "Canlı Yayın" : "Live TV" }
    static var guide: String { isTurkish ? "Rehber" : "Guide" }
    static var nextUp: String { isTurkish ? "Sonra" : "Next" }
    static var noProgramInfo: String { isTurkish ? "Program bilgisi yok" : "No programme info" }
    static var noChannels: String { isTurkish ? "Kanal bulunamadı" : "No channels found" }
    static var movies: String { isTurkish ? "Filmler" : "Movies" }
    static var series: String { isTurkish ? "Diziler" : "Series" }
    static var recentlyAdded: String { isTurkish ? "Son Eklenenler" : "Recently Added" }
    static var allCategories: String { isTurkish ? "Tüm Kategoriler" : "All Categories" }
    static var seeAll: String { isTurkish ? "Tümünü Gör" : "See All" }

    // MARK: - Arama (Search)
    static var searchPlaceholder: String { isTurkish ? "Film, dizi veya kanal ara..." : "Search movies, series or channels..." }
    static var noSearchResults: String { isTurkish ? "Sonuç bulunamadı" : "No results found" }
    static var searchPrompt: String { isTurkish ? "Aramak istediğiniz başlığı yazın" : "Type a title to start searching" }
    static var recentSearches: String { isTurkish ? "Son Aramalar" : "Recent Searches" }
    static var allKinds: String { isTurkish ? "Tümü" : "All" }
    static var categoryEmpty: String {
        isTurkish ? "Bu kategoride içerik yok" : "Nothing in this category"
    }
    static var clearRecentSearches: String { isTurkish ? "Temizle" : "Clear" }
    /// Hazır arama kartlarının başlığı.
    static var discover: String { isTurkish ? "Keşfet" : "Discover" }


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
    static var sectionDeveloper: String { isTurkish ? "Geliştirici" : "Developer" }
    static var clearAllLocalData: String { isTurkish ? "Tüm Yerel Verileri Temizle" : "Clear All Local Data" }
    static var clearAllDataConfirmTitle: String { isTurkish ? "Tüm Yerel Veriler Silinsin mi?" : "Clear All Local Data?" }
    static var clearAllDataConfirmMessage: String { isTurkish ? "Bu cihazdaki tüm çalma listeleri, önbellek ve ayarlar silinecek ve oturum kapatılacaktır. (Bulut verileri silinmez)" : "All playlists, cache, and settings on this device will be deleted and you will be signed out. (Cloud data will not be deleted)" }
    static var clear: String { isTurkish ? "Temizle" : "Clear" }

    // MARK: - Giriş & Onboarding (Auth & Playlists)
    static var appTagline: String { isTurkish ? "Kendi listeni ekle, bütün cihazlarında aynı yerden izle." : "Add your playlist, watch everywhere seamlessly." }
    static var signInWithApple: String { isTurkish ? "Apple ile Giriş Yap" : "Sign in with Apple" }
    static var signInWithGoogle: String { isTurkish ? "Google ile Giriş Yap" : "Sign in with Google" }
    static var googleSignInUnavailable: String {
        isTurkish
            ? "Google ile giriş bu cihazda desteklenmiyor. Apple ile giriş yapabilirsin."
            : "Google sign-in isn't supported on this device. You can sign in with Apple."
    }
    static var continueAsGuest: String { isTurkish ? "Misafir Olarak Devam Et" : "Continue as Guest" }
    static var addPlaylist: String { isTurkish ? "Çalma Listesi Ekle" : "Add Playlist" }
    static var noPlaylistsTitle: String { isTurkish ? "Henüz bir listen yok" : "No playlists yet" }
    static var noPlaylistsSubtitle: String { isTurkish ? "Xtream Codes hesabını ya da M3U bağlantını ekle;\ncanlı kanallar, filmler ve diziler burada görünsün." : "Add your Xtream Codes account or M3U link to browse live TV, movies and series." }
    static var playlistName: String { isTurkish ? "Liste Adı" : "Playlist Name" }
    static var serverURL: String { isTurkish ? "Sunucu Adresi (URL)" : "Server URL" }
    static var username: String { isTurkish ? "Kullanıcı Adı" : "Username" }
    static var password: String { isTurkish ? "Şifre" : "Password" }
    static var enterPasswordTitle: String { isTurkish ? "Parolayı Girin" : "Enter Password" }
    static var enterPasswordMessage: String { isTurkish ? "Bu liste için cihazınızda parola bulunamadı. Lütfen parolanızı girin." : "Password not found on this device for this playlist. Please enter your password." }
    static var save: String { isTurkish ? "Kaydet" : "Save" }
    static var cancel: String { isTurkish ? "Vazgeç" : "Cancel" }
    static var close: String { isTurkish ? "Kapat" : "Close" }
    static var error: String { isTurkish ? "Hata" : "Error" }

    // MARK: - Oynatıcı & Hücre Aksiyonları (Player & Actions)
    static var watch: String { isTurkish ? "İzle" : "Watch" }
    static var addToFavorites: String { isTurkish ? "Favorilere Ekle" : "Add to Favorites" }
    static var removeFromFavorites: String { isTurkish ? "Favorilerden Çıkar" : "Remove from Favorites" }
    static var streamFailed: String { isTurkish ? "Yayın açılamadı." : "Playback failed." }
    static var libraryLoadFailed: String {
        isTurkish ? "İçerikler yüklenemedi" : "Couldn't load content"
    }
    static var retry: String { isTurkish ? "Tekrar Dene" : "Try Again" }
    static var audioTracks: String { isTurkish ? "Ses Parçası" : "Audio Track" }
    static var subtitles: String { isTurkish ? "Altyazı" : "Subtitles" }
    static var subtitlesOff: String { isTurkish ? "Altyazı Kapalı" : "Subtitles Off" }
    static var aspectRatio: String { isTurkish ? "Görüntü Boyutu" : "Aspect Ratio" }
    static var aspectFit: String { isTurkish ? "Sığdır (Fit)" : "Fit" }
    static var aspectFill: String { isTurkish ? "Doldur (Fill)" : "Fill" }

    static func seasonName(_ number: Int) -> String {
        isTurkish ? "\(number). Sezon" : "Season \(number)"
    }
}
