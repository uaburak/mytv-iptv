import CoreGraphics
import Foundation
import ImageIO
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

/// Çözülmüş görsellerin bellek önbelleği.
///
/// Aktörün **dışında** duruyor. `NSCache` kendi kilidini taşıyor, dolayısıyla
/// okuması her iş parçacığından güvenli; aktörün içinde kalsaydı önbellekte
/// hazır duran bir görseli okumak bile bir `await` gerektirirdi ve kart o
/// kareyi boş çizip görseli bir sonraki karede soldurarak açardı. Kaydırırken
/// ve ekranlar arası gidip gelirken görülen "önce boş, sonra dolan kart"
/// davranışının kaynağı buydu.
private final class ImageMemoryCache: @unchecked Sendable {
    private let storage: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        // tvOS'ta uygulama bellek bütçesi iOS'takinden belirgin biçimde dar
        // ve katalog, FFmpeg çözücüsü ve Firebase aynı bütçeyi paylaşıyor;
        // görsel önbelleğine orada daha az yer ayrılıyor.
        // Sayı değil maliyet bağlayıcı: tvOS'ta 240pt'lik bir afiş çözülmüş
        // hâlde ~1,7 MB. Eski 48 MB'lık tavan ekranda duran iki sıra afişten
        // fazlasını tutamıyordu ve geri kaydırınca kartlar yeniden çözülüyordu.
        // Encoded veri `URLCache`'te diskte durduğu için tavana çarpmak ağa
        // çıkmak demek değil, ama yine de bir kare gecikme demek.
        #if os(tvOS)
        cache.countLimit = 300
        cache.totalCostLimit = 72 * 1024 * 1024
        #else
        cache.countLimit = 700
        // Yaklaşık 144 MB; poster ağırlıklı bir katalog için rahat bir tavan.
        cache.totalCostLimit = 144 * 1024 * 1024
        #endif
        return cache
    }()

    func object(_ key: String) -> PlatformImage? { storage.object(forKey: key as NSString) }

    func set(_ image: PlatformImage, for key: String) {
        storage.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
    }

    func removeAll() { storage.removeAllObjects() }

    private static func cost(of image: PlatformImage) -> Int {
        #if os(macOS)
        Int(image.size.width * image.size.height * 4)
        #else
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
        #endif
    }
}

/// Poster ve arka plan görselleri için bellek önbellekli, ölçek düşüren yükleyici.
///
/// `AsyncImage` yerine bunun yazılmasının üç sebebi var:
/// 1. AsyncImage'in bellek önbelleği yok — kart her göründüğünde görsel yeniden
///    çözülüyor. Kaydırma ve swipe-back sırasında onlarca eşzamanlı decode,
///    ana iş parçacığını kilitleyen kare düşmelerine yol açıyor.
/// 2. Sağlayıcı TMDB'den 600×900 poster, 1280 genişlik backdrop veriyor; bunları
///    124pt'lik bir karta tam boyutta çözmek bellek ve CPU israfı. ImageIO ile
///    hedef boyuta indirerek çözüyoruz.
/// 3. Listelerde ölü bağlantılar var (bazı görsel sunucularında TLS hatası).
///    Başarısızlıklar hatırlanmazsa her görünüşte yeniden denenip ağ ve zaman
///    harcanıyor.
actor ImageLoader {
    static let shared = ImageLoader()

    /// Aktörden bağımsız; senkron okunabilsin diye (bkz. `ImageMemoryCache`).
    private static let memory = ImageMemoryCache()

    private var inFlight: [String: Task<PlatformImage?, Never>] = [:]
    /// Çözülemeyen bağlantılar. Tekrar tekrar denenmesini engelliyor.
    private var failed: Set<String> = []
    private static let failedLimit = 2_000

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            diskPath: "kctv-images"
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        // Aynı ana onlarca kart görünüyor; sunucu başına eşzamanlılık
        // varsayılanla (4) sınırlı kalınca kartlar sırayla doluyordu.
        configuration.httpMaximumConnectionsPerHost = 10
        return URLSession(configuration: configuration)
    }()

    /// Bellek önbelleğinden senkron okuma. Hazırsa görsel **aynı karede**
    /// basılıyor; bu yol için `await` gerekmiyor.
    nonisolated static func cachedImage(url: URL, maxPixelSize: CGFloat) -> PlatformImage? {
        memory.object(key(url: url, maxPixelSize: maxPixelSize))
    }

    /// Önbellekte varsa anında döner; yoksa indirip hedef boyuta indirir.
    func image(for url: URL, maxPixelSize: CGFloat) async -> PlatformImage? {
        let key = Self.key(url: url, maxPixelSize: maxPixelSize)
        if let cached = Self.memory.object(key) { return cached }
        if failed.contains(url.absoluteString) { return nil }
        if let existing = inFlight[key] { return await existing.value }

        // `Task` yerine `Task.detached`: aktörün içinde açılan bir görev
        // aktörün yalıtımını miras alıyor ve çözümlemeler tek tek sıraya
        // giriyordu. Kaydırma sırasında onlarca görsel bekliyor; ağ beklemesi
        // zaten askıya alıyor ama ImageIO çözümlemesi işlemciyi tutuyor ve
        // seri çalışınca kartlar gecikmeli doluyordu.
        let task = Task<PlatformImage?, Never>.detached(priority: .utility) { [session] in
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    return nil
                }
                return Self.downsample(data: data, maxPixelSize: maxPixelSize)
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        if let image {
            Self.memory.set(image, for: key)
        } else {
            // Ölü bağlantılar sınırsız birikmesin: on binlerce kanallık bir
            // listede logoların çoğu ölü olabiliyor ve bu küme kalıcı olarak
            // büyüyordu. Tavana gelince baştan başlıyor; en kötü ihtimalle
            // birkaç istek tekrarlanır.
            if failed.count >= Self.failedLimit { failed.removeAll(keepingCapacity: true) }
            failed.insert(url.absoluteString)
        }
        return image
    }

    /// Görseli arka planda önbelleğe alır; sonucu kimse beklemiyor.
    ///
    /// Banner ve detay ekranı gibi "açıldığında hazır olmalı" yüzeyler için:
    /// içerik seçilir seçilmez görselleri de çözüyoruz, ekran açıldığında
    /// bellekten geliyor ve hiçbir bekleme görünmüyor.
    nonisolated func prefetch(_ urls: [URL], maxPixelSize: CGFloat) {
        let pending = urls.filter { Self.cachedImage(url: $0, maxPixelSize: maxPixelSize) == nil }
        guard !pending.isEmpty else { return }
        Task.detached(priority: .utility) { [self] in
            // Sıralı: ön yükleme, ekranda **görünen** görsellerin önüne
            // geçmemeli. Sıra beklemesi kimseyi bekletmiyor.
            for url in pending {
                _ = await image(for: url, maxPixelSize: maxPixelSize)
            }
        }
    }

    /// Sadece önbellekten okur; ilk kareyi beklemeden çizebilmek için.
    /// Senkron karşılığı `cachedImage(url:maxPixelSize:)`.
    func cached(url: URL, maxPixelSize: CGFloat) -> PlatformImage? {
        Self.cachedImage(url: url, maxPixelSize: maxPixelSize)
    }

    private static func key(url: URL, maxPixelSize: CGFloat) -> String {
        // Boyutu kovalara ayırıyoruz: 124pt ve 130pt aynı çözünürlüğü paylaşsın.
        let bucket = Int((maxPixelSize / 128).rounded(.up)) * 128
        return "\(url.absoluteString)#\(bucket)"
    }

    /// ImageIO ile doğrudan hedef boyutta çözer: tam boyut bitmap'i hiç
    /// oluşturmadığı için hem hızlı hem az bellek harcıyor.
    private static func downsample(data: Data, maxPixelSize: CGFloat) -> PlatformImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixelSize),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        #if os(macOS)
        return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }
}
