import Foundation
import UIKit

extension Notification.Name {
    /// Banner içeriği değişti (yeni seçim tamamlandı ya da diskten geldi).
    static let featuredDidChange = Notification.Name("kctv.featuredDidChange")
}

/// Banner'ın hangi havuzdan beslendiği.
enum FeaturedScope: Hashable, Sendable {
    /// Anasayfa: film ve diziler birlikte.
    case home
    /// Film / Dizi gezinme ekranı.
    case kind(MediaKind)
    /// Tek kategoriye daraltılmış gezinme.
    case category(MediaKind, String)

    fileprivate var storageKey: String {
        switch self {
        case .home: "home"
        case let .kind(kind): "kind-\(kind.rawValue)"
        case let .category(kind, id): "cat-\(kind.rawValue)-\(id)"
        }
    }
}

/// Banner seçiminin belleği.
///
/// Banner'ın gecikmesinin sebebi seçimin kendisiydi: aday başına TMDB'ye
/// çıkılıp logo, backdrop ve açıklama şartı doğrulanıyor, sekiz içerik
/// bulunana kadar sekizerli turlar sürüyordu. Ekran o sırada banner'sız
/// açılıyor, liste gelince banner **sonradan** ekleniyor ve sayfa kendi
/// yüksekliği kadar zıplıyordu.
///
/// Bu sınıf üç şeyi değiştiriyor:
/// 1. **Seçim kalıcı.** Sonuç diske yazılıyor; ikinci açılıştan itibaren
///    banner ilk karede dolu geliyor, tazeleme arkada sürüyor.
/// 2. **Seçim erken.** Katalog hazır olur olmaz — kullanıcı o ekrana daha
///    gitmeden — anasayfa, film ve dizi banner'ları birlikte çözülüyor.
///    Filmler/Diziler sayfası açıldığında iş çoktan bitmiş oluyor.
/// 3. **Görseller önceden.** Seçim biter bitmez backdrop ve logo
///    `ImageLoader`'a ısıtılıyor; banner açıldığında ağ beklemesi kalmıyor.
@MainActor
final class FeaturedStore {
    struct Snapshot {
        var items: [MediaItem]
        /// Elde içerik yok ama seçim sürüyor. Ekranlar buna bakarak banner'a
        /// **baştan** yer ayırıyor; bölüm sonradan eklenmediği için sayfa
        /// zıplamıyor.
        var isResolving: Bool

        var expectsBanner: Bool { !items.isEmpty || isResolving }
    }

    private struct StoredSelection: Codable {
        var ids: [MediaID]
    }

    private let store = LocalStore(folder: "featured")

    /// Seçili listenin kimliği; önbellek anahtarının ön eki.
    private var sourceKey = ""
    private var catalog: [MediaKind: [MediaItem]] = [:]
    private var itemsByID: [MediaID: MediaItem] = [:]
    /// Katalogun ucuz parmak izi: tür başına kayıt sayısı. Değiştiğinde seçim
    /// arkada tazeleniyor, ekrandaki banner ise yerinde kalıyor.
    private var catalogSignature: [MediaKind: Int] = [:]

    private var picks: [FeaturedScope: [MediaID]] = [:]
    /// Seçimi bekleyen ya da süren kapsamlar.
    ///
    /// Seçim **sırayla** yapılıyor. Üç kapsam (anasayfa, filmler, diziler)
    /// aynı anda başlatıldığında yirmi dörde yakın eşzamanlı TMDB sorgusu
    /// açılıyor ve açılıştaki ağ trafiği kendi kendini boğuyordu. Üstelik
    /// gereksiz: anasayfa havuzu film ve dizileri zaten içeriyor, sırayla
    /// yürüyünce diğer iki kapsam büyük ölçüde önbellekten dönüyor.
    private var inProgress: [FeaturedScope] = []
    private var worker: Task<Void, Never>?
    /// Bu oturumda seçimi tamamlanmış kapsamlar. Sonuç boş çıksa bile tekrar
    /// tekrar denenmiyor.
    private var resolved: Set<FeaturedScope> = []
    /// Diskten okumayı bir kez yapıyoruz.
    private var loadedFromDisk: Set<FeaturedScope> = []

    /// Banner görselinin ekranda kaplayacağı genişlik. Ekranlar ilk düzen
    /// turunda kendi ölçüsünü bildiriyor; ön ısıtma da aynı çözünürlüğü
    /// kullansın diye saklanıyor (farklı ölçü, önbellekte ikinci bir kayıt
    /// demek olurdu).
    private static let artworkWidthKey = "kctv.heroArtworkWidth"
    static var artworkDisplayWidth: CGFloat {
        get {
            let saved = UserDefaults.standard.double(forKey: artworkWidthKey)
            guard saved > 0 else {
                #if os(tvOS)
                return AppMetrics.tv.heroImageWidth
                #else
                return AppMetrics.regular.heroImageWidth
                #endif
            }
            return saved
        }
        set {
            guard newValue > 0, abs(newValue - artworkDisplayWidth) > 1 else { return }
            UserDefaults.standard.set(newValue, forKey: artworkWidthKey)
        }
    }

    // MARK: - Katalog bağlantısı

    /// Katalog değiştiğinde çağrılıyor. Liste değiştiyse eldeki seçim
    /// düşüyor; aynı listenin tazelenmesinde seçim korunuyor ki banner
    /// yenilemede başa sarmasın.
    func catalogDidChange(
        sourceKey: String,
        catalog: [MediaKind: [MediaItem]],
        itemsByID: [MediaID: MediaItem]
    ) {
        if sourceKey != self.sourceKey {
            self.sourceKey = sourceKey
            picks = [:]
            resolved = []
            loadedFromDisk = []
            inProgress = []
            worker?.cancel()
            worker = nil
        }
        self.catalog = catalog
        self.itemsByID = itemsByID

        let signature = catalog.mapValues(\.count)
        if signature != catalogSignature {
            catalogSignature = signature
            // İçerik değişti: seçim yeniden yapılacak. Eldeki seçim
            // düşürülmüyor — yenisi gelene kadar banner dolu kalıyor.
            resolved = []
        }
    }

    /// Katalog hazır olduğunda ana kapsamın seçimini başlatır.
    func prewarm() {
        guard !catalog.isEmpty else { return }
        _ = snapshot(for: .home)
    }

    // MARK: - Sorgu

    /// Kapsamın anlık durumu. Gerekiyorsa seçimi de başlatıyor.
    @discardableResult
    func snapshot(for scope: FeaturedScope) -> Snapshot {
        let ids = picks[scope] ?? loadPersisted(scope)
        let items = ids.compactMap { itemsByID[$0] }

        if !resolved.contains(scope) { enqueueSelection(for: scope) }
        return Snapshot(items: items, isResolving: items.isEmpty && inProgress.contains(scope))
    }

    func reset() {
        worker?.cancel()
        worker = nil
        inProgress = []
        picks = [:]
        resolved = []
        loadedFromDisk = []
        catalog = [:]
        itemsByID = [:]
        sourceKey = ""
    }

    // MARK: - Seçim

    private func enqueueSelection(for scope: FeaturedScope) {
        // Logo şartı TMDB'ye çıkmayı gerektiriyor; anahtar yoksa banner da yok.
        guard TMDBService.isConfigured else {
            resolved.insert(scope)
            return
        }
        // Katalog henüz gelmediyse iş yok; bir sonraki sorguda yeniden bakılır.
        guard pools(for: scope).contains(where: { !$0.isEmpty }) else { return }
        guard !inProgress.contains(scope) else { return }

        inProgress.append(scope)
        startWorkerIfNeeded()
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let store = self, let scope = store.inProgress.first {
                let items = await HeroFeatured.items(from: store.pools(for: scope))
                guard !Task.isCancelled else { break }
                store.finish(scope, items: items)
            }
            self?.worker = nil
        }
    }

    private func finish(_ scope: FeaturedScope, items: [MediaItem]) {
        inProgress.removeAll { $0 == scope }
        resolved.insert(scope)

        let ids = items.map(\.id)
        if picks[scope] != ids {
            picks[scope] = ids
            persist(scope, ids: ids)
        }
        prewarmArtwork(for: items)
        // Bekleyen ekranlar her hâlükârda haberdar ediliyor: seçim boş
        // çıktıysa ayrılan yerin geri verilmesi de bu bildirime bağlı.
        NotificationCenter.default.post(name: .featuredDidChange, object: nil)
    }

    private func pools(for scope: FeaturedScope) -> [[MediaItem]] {
        switch scope {
        case .home:
            [catalog[.movie] ?? [], catalog[.series] ?? []]
        case let .kind(kind):
            [catalog[kind] ?? []]
        case let .category(kind, categoryID):
            [(catalog[kind] ?? []).filter { $0.categoryID == categoryID }]
        }
    }

    /// Banner görsellerini önceden çözer: hücre açıldığında elde hazır resim
    /// oluyor, ilk kare siyah açılmıyor.
    private func prewarmArtwork(for items: [MediaItem]) {
        var backdrops: [URL] = []
        var logos: [URL] = []
        for item in items.prefix(3) {
            let metadata = TMDBService.cachedMetadata(for: item)
            if let backdrop = metadata?.backdropURL ?? item.backdropURL { backdrops.append(backdrop) }
            if let logo = metadata?.logoURL { logos.append(logo) }
        }
        RemoteImageView.prefetch(backdrops, displayWidth: Self.artworkDisplayWidth)
        ImageLoader.shared.prefetch(logos, maxPixelSize: 900)
    }

    // MARK: - Kalıcılık

    private func storageKey(_ scope: FeaturedScope) -> String {
        "\(sourceKey)_\(scope.storageKey)_\(AppLanguage.current.effectiveLanguageCode)"
    }

    private func loadPersisted(_ scope: FeaturedScope) -> [MediaID] {
        guard loadedFromDisk.insert(scope).inserted else { return [] }
        guard let stored = store.read(StoredSelection.self, key: storageKey(scope)) else { return [] }
        picks[scope] = stored.ids
        // Diskten gelen seçimin görselleri de ısıtılıyor: ekran açılana kadar
        // genelde hazır oluyorlar.
        prewarmArtwork(for: stored.ids.compactMap { itemsByID[$0] })
        return stored.ids
    }

    private func persist(_ scope: FeaturedScope, ids: [MediaID]) {
        let store = self.store
        let key = storageKey(scope)
        let payload = StoredSelection(ids: ids)
        Task.detached(priority: .utility) {
            store.write(payload, key: key)
        }
    }
}
