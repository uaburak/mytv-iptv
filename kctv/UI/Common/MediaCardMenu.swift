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
        // Kaydetme defteri türe göre değişiyor. Canlı kanalda favori:
        // oynatıcının kanal listesi ve kanal çekmecesi oradan besleniyor.
        // Film ve dizide izleme listesi. İkisi bir arada gösterilmiyor —
        // kullanıcıya aynı işin iki adı gibi görünüyordu.
        let usesFavorites = item.kind == .live
        let isSaved = usesFavorites ? activity.isFavorite(item) : activity.isInWatchlist(item)
        // Yarım kalmış bir kayıt varsa eylem "Devam Et": menü, kartın
        // üstündeki ilerleme çubuğuyla aynı şeyi söylemeli.
        let resumes = activity.latestProgress(for: item.id).map { !$0.isFinished } ?? false

        // Kullanıcının kendi kanal listeleri yalnızca kanallarda ve yalnızca
        // en az bir liste kurulmuşsa. Liste yokken "Listeye Ekle" gösterip
        // boş bir alt menü açmanın anlamı yok — listeyi Kanallar sayfasının
        // sol menüsündeki "Liste Oluştur" kuruyor.
        let lists = item.kind == .live ? model.activity.channelLists : []
        let listElement = listElement(for: item, lists: lists, model: model)

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            var children: [UIMenuElement] = [
                UIAction(
                    title: resumes ? L10n.resume : L10n.watch,
                    image: UIImage(systemName: "play.fill")
                ) { _ in
                    Task { @MainActor in await watch(item, model: model, openDetail: openDetail) }
                },
                UIAction(
                    title: saveTitle(saved: isSaved, usesFavorites: usesFavorites),
                    image: UIImage(systemName: isSaved ? "bookmark.slash" : "bookmark"),
                    attributes: isSaved ? .destructive : []
                ) { _ in
                    if usesFavorites {
                        model.activity.toggleFavorite(item)
                    } else {
                        model.activity.toggleWatchlist(item)
                    }
                },
            ]
            if let listElement { children.append(listElement) }
            return UIMenu(children: children)
        }
    }

    /// Kanal listeleri menüde nasıl duruyor?
    ///
    /// Tek liste varsa doğrudan bir eylem — araya bir alt menü koymak tek
    /// seçenek için fazladan bir tuş demek. Birden fazlaysa alt menü ve her
    /// listenin yanında kanalın o listede olup olmadığını gösteren işaret;
    /// aynı satır hem ekliyor hem çıkarıyor.
    @MainActor
    private static func listElement(
        for item: MediaItem,
        lists: [ChannelList],
        model: AppModel
    ) -> UIMenuElement? {
        guard !lists.isEmpty else { return nil }

        if lists.count == 1, let only = lists.first {
            let contains = only.channelIDs.contains(item.id)
            return UIAction(
                title: contains ? L10n.removeFromList : L10n.addToList,
                image: UIImage(systemName: contains ? "text.badge.minus" : "text.badge.plus"),
                attributes: contains ? .destructive : []
            ) { _ in
                model.activity.toggleChannel(item, inList: only.id)
            }
        }

        let actions = lists.map { list in
            let contains = list.channelIDs.contains(item.id)
            return UIAction(title: list.name, state: contains ? .on : .off) { _ in
                model.activity.toggleChannel(item, inList: list.id)
            }
        }
        return UIMenu(
            title: L10n.addToList,
            image: UIImage(systemName: "text.badge.plus"),
            children: actions
        )
    }

    private static func saveTitle(saved: Bool, usesFavorites: Bool) -> String {
        if usesFavorites {
            return saved ? L10n.removeFromFavorites : L10n.addToFavorites
        }
        return saved ? L10n.removeFromWatchlist : L10n.addToWatchlist
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
