#if canImport(UIKit)
import UIKit

/// Uygulamanın gezinme menüsü tek yerde.
///
/// Telefonda sekme çubuğu, Apple TV'de kenar çubuğu aynı listeden besleniyor:
/// bir bölümün adı, simgesi ve hangi ekranı açtığı yalnızca burada yazıyor.
/// Menü iki kabuğa ayrı ayrı yazıldığında başlıklar ve simgeler birbirinden
/// ayrışıyordu.
enum AppDestination: String, CaseIterable, Hashable {
    case search
    case home
    case live
    case movies
    case series
    case watchlist
    case playlists
    case settings

    /// Apple TV kenar çubuğunun sırası.
    ///
    /// Arama en üstte — sistem uygulamalarının deseni bu. Ardından anasayfa ve
    /// tür bölümleri geliyor: kenar çubuğu her ekranda göründüğü için
    /// "Canlı / Film / Dizi" artık anasayfadaki kartlarla değil buradan
    /// açılıyor.
    static let sidebar: [AppDestination] = [
        .search, .home, .live, .movies, .series, .watchlist, .playlists, .settings,
    ]

    /// Sekme çubuğunda tür bölümleri yok: telefonda beş sekmeyi aşan bir çubuk
    /// okunmuyor, oraya anasayfadaki kartlardan giriliyor.
    static let tabBar: [AppDestination] = [
        .home, .watchlist, .playlists, .search, .settings,
    ]

    var title: String {
        switch self {
        case .search: L10n.tabSearch
        case .home: L10n.tabHome
        case .live: L10n.liveTV
        case .movies: L10n.movies
        case .series: L10n.series
        case .watchlist: L10n.myWatchlist
        case .playlists: L10n.tabPlaylists
        case .settings: L10n.tabSettings
        }
    }

    /// Tür bölümlerinin simgesi `MediaKind`'dan geliyor: kartla, çiple ve
    /// menüdeki satırla aynı sembol.
    var symbol: String {
        switch self {
        case .search: "magnifyingglass"
        case .home: "house.fill"
        case .live: MediaKind.live.symbol
        case .movies: MediaKind.movie.symbol
        case .series: MediaKind.series.symbol
        case .watchlist: "bookmark.fill"
        case .playlists: "list.bullet.rectangle"
        case .settings: "gearshape.fill"
        }
    }

    @MainActor
    func makeViewController(model: AppModel) -> UIViewController {
        switch self {
        // Arama sekmesinin sarmalayıcısı platforma göre değişiyor; tvOS'ta
        // `UISearchContainerViewController` gerekiyor.
        case .search: SearchViewController.makeTabController(model: model)
        case .home: HomeViewController(model: model)
        case .live: BrowseViewController(kind: .live, model: model)
        case .movies: BrowseViewController(kind: .movie, model: model)
        case .series: BrowseViewController(kind: .series, model: model)
        case .watchlist: BrowseViewController(source: .watchlist, model: model)
        case .playlists: PlaylistsViewController(model: model)
        case .settings: SettingsViewController(model: model)
        }
    }
}
#endif
