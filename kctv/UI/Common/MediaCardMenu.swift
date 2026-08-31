import UIKit

/// Afiş kartına uzun basınca çıkan menü: İzle, favori, izleme listesi.
///
/// Menü tek yerden kuruluyor. Aynı kart anasayfada, aramada, kategoride,
/// favorilerde ve tür sayfalarında duruyor; hepsinde aynı eylemleri vermesi
/// gerekiyor ve eylemin adı içeriğin durumuna göre değişiyor ("Favorilere
/// Ekle" ↔ "Favorilerden Çıkar"). Ekranların yaptığı tek iş, basılan hücrenin
/// hangi içeriğe denk geldiğini söylemek.
///
/// Jest kurulmuyor: uzun basışı sistemin kendi bağlam menüsü karşılıyor,
/// dolayısıyla kartın seçimiyle çakışmıyor ve menü tvOS'ta da iOS'ta da
/// yerel görünüyor.
enum MediaCardMenu {
    /// - Parameter openDetail: dizide oynatılacak bölüm çözülemezse buraya
    ///   düşülüyor — hangi bölüm sorusunun yeri detay ekranı.
    @MainActor
    static func configuration(
        for item: MediaItem,
        model: AppModel,
        openDetail: @escaping (MediaItem) -> Void
    ) -> UIContextMenuConfiguration {
        // Durum menü kurulmadan önce okunuyor: eylem sağlayıcı ana aktörde
        // çalışmıyor, oraya yalnızca hazır metinler giriyor.
        let activity = model.activity
        let isFavorite = activity.isFavorite(item)
        let isInWatchlist = activity.isInWatchlist(item)
        // Yarım kalmış bir kayıt varsa eylem "Devam Et": menü, kartın
        // üstündeki ilerleme çubuğuyla aynı şeyi söylemeli.
        let resumes = activity.latestProgress(for: item.id).map { !$0.isFinished } ?? false

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [
                UIAction(
                    title: resumes ? L10n.resume : L10n.watch,
                    image: UIImage(systemName: "play.fill")
                ) { _ in
                    Task { @MainActor in await watch(item, model: model, openDetail: openDetail) }
                },
                UIAction(
                    title: isFavorite ? L10n.removeFromFavorites : L10n.addToFavorites,
                    image: UIImage(systemName: isFavorite ? "heart.slash" : "heart"),
                    attributes: isFavorite ? .destructive : []
                ) { _ in
                    model.activity.toggleFavorite(item)
                },
                UIAction(
                    title: isInWatchlist ? L10n.removeFromWatchlist : L10n.addToWatchlist,
                    image: UIImage(systemName: isInWatchlist ? "bookmark.slash" : "bookmark"),
                    attributes: isInWatchlist ? .destructive : []
                ) { _ in
                    model.activity.toggleWatchlist(item)
                },
            ])
        }
    }

    @MainActor
    private static func watch(
        _ item: MediaItem,
        model: AppModel,
        openDetail: (MediaItem) -> Void
    ) async {
        // Dizinin kendisinin akışı yok; oynatılacak bölüm künyeden çözülüyor.
        guard item.kind == .series else {
            await model.play(item)
            return
        }
        guard let episode = await resolveEpisode(for: item, model: model) else {
            openDetail(item)
            return
        }
        await model.play(episode, in: item)
    }

    /// Dizide "İzle" hangi bölüm?
    ///
    /// Yarım kalan bölüm varsa o, biten bir bölümden sonra sıradaki, hiç
    /// izlenmemişse ilki — detay ekranındaki oynat düğmesiyle aynı sıra.
    @MainActor
    private static func resolveEpisode(for series: MediaItem, model: AppModel) async -> Episode? {
        guard let detail = try? await model.library.detail(for: series) else { return nil }
        let episodes = detail.seasons.flatMap(\.episodes)
        guard !episodes.isEmpty else { return nil }

        guard let latest = model.activity.latestProgress(for: series.id),
              let episodeID = latest.episodeID,
              let index = episodes.firstIndex(where: { $0.id == episodeID })
        else { return episodes.first }

        guard latest.isFinished else { return episodes[index] }
        return episodes.indices.contains(index + 1) ? episodes[index + 1] : episodes[index]
    }
}
