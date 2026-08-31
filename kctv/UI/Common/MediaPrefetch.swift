import UIKit

/// Kartlar ekrana girmeden önce görsellerini ve künyelerini hazırlar.
///
/// Uygulamanın kuralı şu: kullanıcı hiçbir yerde "yükleniyor" görmemeli.
/// Bunun iki ayağı var — görsel ve künye:
///
/// - **Görsel.** `UICollectionView`'ın kendi ön yükleme kancası, kart daha
///   ekrana girmeden görseli çözdürüyor. Hücre göründüğünde `ImageLoader`
///   önbelleğinden senkron geliyor ve tek kare bile boş kalmıyor.
/// - **Künye.** Detay ekranının beklediği tek şey TMDB yanıtı. Kart ekranda
///   görünürken künyesi arkada çözülürse, kullanıcı o karta bastığında ekran
///   dolu açılıyor. `TMDBService` sırayı dar tutuyor (aynı anda üç istek) ve
///   sonucu diske yazıyor: bedel içerik başına bir kez ödeniyor.
enum MediaPrefetch {
    @MainActor
    static func warm(_ items: [MediaItem], posterWidth: CGFloat) {
        guard !items.isEmpty else { return }
        RemoteImageView.prefetch(items.compactMap(\.posterURL), displayWidth: posterWidth)
        // Canlı kanalın detay ekranı yok; künyesi de aranmıyor.
        let enrichable = items.filter { $0.kind != .live }
        guard !enrichable.isEmpty else { return }
        TMDBService.shared.prefetchMetadata(for: enrichable)
    }
}
