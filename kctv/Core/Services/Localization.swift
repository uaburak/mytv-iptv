import Foundation

/// Uygulama genelinde desteklenen diller.
enum AppLanguage: String, CaseIterable, Sendable {
    case system = "system"
    case turkish = "tr"
    case english = "en"

    private static let userDefaultsKey = "app_language_preference"

    /// Çözülmüş tercih. `L10n`'deki her metin bunu okuyor ve bazıları hücre
    /// döngüsünün içinde çağrılıyor; her seferinde `UserDefaults`'a gitmemek
    /// için bir kez çözülüp saklanıyor. Yalnızca ayarlardan değişebildiği
    /// için geçersiz kılma noktası tek: aşağıdaki `set`.
    nonisolated(unsafe) private static var cachedCurrent: AppLanguage?

    /// Kullanıcının seçtiği ya da varsayılan dil tercihi.
    static var current: AppLanguage {
        get {
            if let cachedCurrent { return cachedCurrent }
            let resolved = UserDefaults.standard.string(forKey: userDefaultsKey)
                .flatMap(AppLanguage.init(rawValue:)) ?? .system
            cachedCurrent = resolved
            return resolved
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
            cachedCurrent = newValue
            NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        }
    }

    /// Cihaz diline veya seçime göre aktif olan dil kodu ("tr" veya "en").
    ///
    /// Türkçe dışındaki her cihaz dili İngilizce'ye düşüyor: uygulamanın iki
    /// dili var ve bir Alman kullanıcıya Türkçe göstermek, İngilizce
    /// göstermekten kötü.
    var effectiveLanguageCode: String {
        switch self {
        case .turkish:
            return "tr"
        case .english:
            return "en"
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("tr") ? "tr" : "en"
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

    static func episodeName(_ number: Int) -> String {
        isTurkish ? "\(number). Bölüm" : "Episode \(number)"
    }

    /// Kart ve oynatıcı üstündeki kısa sezon/bölüm rozeti.
    static func episodeBadge(season: Int, episode: Int) -> String {
        isTurkish ? "S\(season):B\(episode)" : "S\(season):E\(episode)"
    }

    /// Süre etiketi. Türkçe "1sa 40d", İngilizce "1h 40m".
    static func duration(hours: Int, minutes: Int) -> String {
        if hours > 0 {
            return isTurkish ? "\(hours)sa \(minutes)d" : "\(hours)h \(minutes)m"
        }
        return isTurkish ? "\(minutes)d" : "\(minutes)m"
    }

    // MARK: - Sağlayıcı hataları

    static var errorInvalidCredentials: String {
        isTurkish ? "Kullanıcı adı veya şifre hatalı." : "Incorrect username or password."
    }
    static var errorAccountExpired: String {
        isTurkish ? "Hesabın süresi dolmuş." : "This account has expired."
    }
    static func errorBadResponse(status: Int) -> String {
        isTurkish ? "Sunucu \(status) döndürdü." : "Server returned \(status)."
    }
    static var errorEmptyPlaylist: String {
        isTurkish ? "Listede oynatılabilir içerik bulunamadı." : "No playable content in this playlist."
    }
    static func errorUnsupported(_ what: String) -> String {
        isTurkish ? "Desteklenmeyen içerik: \(what)" : "Unsupported content: \(what)"
    }
    static func errorInvalidHost(_ host: String) -> String {
        isTurkish ? "Sunucu adresi geçersiz: \(host)" : "Invalid server address: \(host)"
    }
    static var errorBadRequestURL: String {
        isTurkish ? "İstek adresi oluşturulamadı." : "Couldn't build the request URL."
    }
    static var errorPlaylistUnreadable: String {
        isTurkish ? "Playlist okunamadı." : "Couldn't read the playlist."
    }
    static var errorNoWindow: String {
        isTurkish ? "Görünüm penceresi bulunamadı." : "No presenting window found."
    }
    static var errorGoogleCredential: String {
        isTurkish ? "Google kimlik bilgisi alınamadı." : "Couldn't obtain Google credentials."
    }
    static var errorAppleResponse: String {
        isTurkish ? "Apple kimlik doğrulama yanıtı okunamadı." : "Couldn't read the Apple sign-in response."
    }

    // MARK: - Anasayfa rayları & kategoriler

    static func itemCount(_ count: Int) -> String {
        isTurkish ? "\(count.formatted()) içerik" : "\(count.formatted()) items"
    }
    static var newMovies: String { isTurkish ? "Yeni Eklenen Filmler" : "Recently Added Movies" }
    static var newSeries: String { isTurkish ? "Yeni Diziler" : "New Series" }
    static var otherCategory: String { isTurkish ? "Diğer" : "Other" }

    // MARK: - Oynatıcı

    static var liveBadge: String { isTurkish ? "CANLI" : "LIVE" }
    static var aspectStretch: String { isTurkish ? "Tam Ekran (Uzat)" : "Stretch (16:9)" }

    // MARK: - Listeler & form

    static var addPlaylistTitle: String { isTurkish ? "Liste Ekle" : "Add Playlist" }
    static var editPlaylistTitle: String { isTurkish ? "Listeyi Düzenle" : "Edit Playlist" }
    static var connectAndSave: String { isTurkish ? "Bağlan ve Kaydet" : "Connect & Save" }
    static var edit: String { isTurkish ? "Düzenle" : "Edit" }
    static var delete: String { isTurkish ? "Sil" : "Delete" }
    static var remove: String { isTurkish ? "Çıkar" : "Remove" }
    static var playlistNamePlaceholder: String { isTurkish ? "Örn. Ev Listesi" : "e.g. Home Playlist" }
    static var usernamePlaceholder: String { isTurkish ? "kullanıcı" : "username" }
    static var m3uURLLabel: String { isTurkish ? "M3U Bağlantısı" : "M3U URL" }
    static var keychainNote: String {
        isTurkish
            ? "Şifren yalnızca bu cihazın Keychain'inde saklanır, buluta gönderilmez. Liste adı ve sunucu bilgisi hesabına senkronlanır."
            : "Your password is only stored in this device's Keychain and never sent to the cloud. Playlist name and server are synced to your account."
    }

    // MARK: - İçerik süzgeci

    static var hideAdultContent: String { isTurkish ? "Yetişkin İçeriği Gizle" : "Hide Adult Content" }
    static var hideAdultContentNote: String {
        isTurkish
            ? "Adında ya da kategorisinde yetişkin içerik işareti olan yayınlar listelerde, aramada ve anasayfada gösterilmez."
            : "Streams flagged as adult by name or category are hidden from lists, search and the home screen."
    }

    // MARK: - Erişilebilirlik

    /// Kartın `accessibilityValue`'su: afişte görünen ilerleme çubuğunun
    /// VoiceOver karşılığı.
    static func watchedPercent(_ percent: Int) -> String {
        isTurkish ? "%\(percent) izlendi" : "\(percent)% watched"
    }

    static var accountAndSettings: String { isTurkish ? "Hesap ve ayarlar" : "Account and settings" }
    static var categoryFilter: String { isTurkish ? "Kategori filtresi" : "Category filter" }
    static var favoriteAction: String { isTurkish ? "Favori" : "Favorite" }
}
