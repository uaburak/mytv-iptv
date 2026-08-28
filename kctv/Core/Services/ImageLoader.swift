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

    private let cache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 400
        // Yaklaşık 96 MB; poster ağırlıklı bir katalog için rahat bir tavan.
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    private var inFlight: [String: Task<PlatformImage?, Never>] = [:]
    /// Çözülemeyen bağlantılar. Tekrar tekrar denenmesini engelliyor.
    private var failed: Set<String> = []

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "kctv-images"
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    /// Önbellekte varsa anında döner; yoksa indirip hedef boyuta indirir.
    func image(for url: URL, maxPixelSize: CGFloat) async -> PlatformImage? {
        let key = Self.key(url: url, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if failed.contains(url.absoluteString) { return nil }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<PlatformImage?, Never> { [session] in
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
            cache.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
        } else {
            failed.insert(url.absoluteString)
        }
        return image
    }

    /// Sadece önbellekten okur; ilk kareyi beklemeden çizebilmek için.
    func cached(url: URL, maxPixelSize: CGFloat) -> PlatformImage? {
        cache.object(forKey: Self.key(url: url, maxPixelSize: maxPixelSize) as NSString)
    }

    private static func key(url: URL, maxPixelSize: CGFloat) -> String {
        // Boyutu kovalara ayırıyoruz: 124pt ve 130pt aynı çözünürlüğü paylaşsın.
        let bucket = Int((maxPixelSize / 128).rounded(.up)) * 128
        return "\(url.absoluteString)#\(bucket)"
    }

    private static func cost(of image: PlatformImage) -> Int {
        #if os(macOS)
        Int(image.size.width * image.size.height * 4)
        #else
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
        #endif
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
