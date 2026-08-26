import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

// MARK: - Safe URL Parsing & Smart HTTPS Upgrade

extension URL {
    /// Safely parses an IPTV image URL string, automatically upgrading `http://` to `https://`
    /// to prevent iOS App Transport Security (ATS) from blocking channel logos.
    public static func fromUserString(_ string: String?) -> URL? {
        guard var raw = string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        // Auto-upgrade HTTP to HTTPS for IPTV logo CDNs (e.g. 3651903.xyz) to bypass ATS restrictions
        if raw.lowercased().hasPrefix("http://3651903.xyz") {
            raw = "https://" + raw.dropFirst(7)
        } else if raw.lowercased().hasPrefix("http://exanimo.tv") {
            raw = "https://" + raw.dropFirst(7)
        } else if raw.lowercased().hasPrefix("http://") && !raw.contains(":8080") && !raw.contains(":2095") {
            // For general logo hosts without custom non-SSL ports, try HTTPS
            raw = "https://" + raw.dropFirst(7)
        }

        if let directUrl = URL(string: raw) {
            return directUrl
        }

        // If string contains unencoded spaces or special characters
        if let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(.urlQueryAllowed).union(.urlPathAllowed)),
           let url = URL(string: encoded) {
            return url
        }
        return nil
    }
}

// MARK: - SSL Bypass URLSession Delegate for IPTV CDNs

private final class IPTVURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - High-Performance Memory & Disk Image Cache

@MainActor
public final class ImageCacheService {
    public static let shared = ImageCacheService()

    private let memoryCache = NSCache<NSString, PlatformImage>()
    private let urlSession: URLSession
    private let sessionDelegate = IPTVURLSessionDelegate()

    private init() {
        memoryCache.countLimit = 600
        memoryCache.totalCostLimit = 120 * 1024 * 1024 // 120 MB RAM

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 60 * 1024 * 1024,
            diskCapacity: 250 * 1024 * 1024,
            diskPath: "MyTV_MediaImageCache"
        )
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (AppleTV; tvOS 17.0) IPTVSmarters/1.0",
            "Accept": "image/*,*/*;q=0.8"
        ]
        config.timeoutIntervalForRequest = 15
        self.urlSession = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }

    public func cachedImage(for url: URL) -> PlatformImage? {
        memoryCache.object(forKey: url.absoluteString as NSString)
    }

    public func insertImage(_ image: PlatformImage, for url: URL) {
        memoryCache.setObject(image, forKey: url.absoluteString as NSString)
    }

    public func loadImage(from url: URL) async -> PlatformImage? {
        if let cached = cachedImage(for: url) {
            return cached
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (AppleTV; tvOS 17.0) IPTVSmarters/1.0", forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 15

            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                // If HTTPS failed and original URL was converted from HTTP, fallback to HTTP attempt
                if url.scheme == "https", let httpUrl = URL(string: "http://" + url.absoluteString.dropFirst(8)) {
                    var httpReq = URLRequest(url: httpUrl)
                    httpReq.setValue("Mozilla/5.0 (AppleTV; tvOS 17.0) IPTVSmarters/1.0", forHTTPHeaderField: "User-Agent")
                    if let (httpData, httpResp) = try? await urlSession.data(for: httpReq),
                       let res = httpResp as? HTTPURLResponse, (200...299).contains(res.statusCode) {
                        #if canImport(UIKit)
                        if let platformImage = UIImage(data: httpData) {
                            insertImage(platformImage, for: url)
                            return platformImage
                        }
                        #elseif canImport(AppKit)
                        if let platformImage = NSImage(data: httpData) {
                            insertImage(platformImage, for: url)
                            return platformImage
                        }
                        #endif
                    }
                }
                return nil
            }

            #if canImport(UIKit)
            guard let platformImage = UIImage(data: data) else { return nil }
            #elseif canImport(AppKit)
            guard let platformImage = NSImage(data: data) else { return nil }
            #endif

            insertImage(platformImage, for: url)
            return platformImage
        } catch {
            return nil
        }
    }
}

// MARK: - Fast Cached Async Image

public struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var loadedImage: PlatformImage?

    public init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    public var body: some View {
        Group {
            if let loadedImage {
                #if canImport(UIKit)
                content(Image(uiImage: loadedImage))
                #elseif canImport(AppKit)
                content(Image(nsImage: loadedImage))
                #endif
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await fetchImage()
        }
    }

    private func fetchImage() async {
        guard let url else { return }
        if let cached = ImageCacheService.shared.cachedImage(for: url) {
            self.loadedImage = cached
            return
        }
        let fetched = await ImageCacheService.shared.loadImage(from: url)
        if let fetched {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.loadedImage = fetched
            }
        }
    }
}

// MARK: - Channel Logo View

/// A specialized, high-aesthetic channel logo badge for Live TV lists, drawers, and cards.
public struct ChannelLogoView: View {
    let logoUrl: String?
    let channelName: String
    var width: CGFloat = 54
    var height: CGFloat = 42
    var cornerRadius: CGFloat = 10

    public init(
        logoUrl: String?,
        channelName: String = "",
        width: CGFloat = 54,
        height: CGFloat = 42,
        cornerRadius: CGFloat = 10
    ) {
        self.logoUrl = logoUrl
        self.channelName = channelName
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    private var initials: String {
        let cleaned = channelName.replacingOccurrences(of: "HD+", with: "")
            .replacingOccurrences(of: "HD", with: "")
            .replacingOccurrences(of: "FHD", with: "")
            .replacingOccurrences(of: "4K", with: "")
            .replacingOccurrences(of: "SD", with: "")
            .replacingOccurrences(of: "tr|org", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = cleaned.split(separator: " ")
        if words.count >= 2 {
            let first = words[0].prefix(1)
            let second = words[1].prefix(1)
            return "\(first)\(second)".uppercased()
        } else if let firstWord = words.first {
            return String(firstWord.prefix(3)).uppercased()
        }
        return "TV"
    }

    public var body: some View {
        ZStack {
            // Dark subtle translucent background so both white and dark logos remain clearly legible
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.08))

            if let url = URL.fromUserString(logoUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                } placeholder: {
                    fallbackBadge
                }
            } else {
                fallbackBadge
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var fallbackBadge: some View {
        VStack(spacing: 2) {
            Image(systemName: "tv")
                .font(.system(size: max(11, min(width, height) * 0.32), weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))

            if !channelName.isEmpty && width >= 44 && height >= 36 {
                Text(initials)
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Media Poster View

/// A specialized media poster / cover artwork view for Movies & Series cards and detail headers.
public struct MediaPosterView: View {
    let posterUrl: String?
    let title: String
    var width: CGFloat = 100
    var height: CGFloat = 150
    var cornerRadius: CGFloat = 12
    var isSeries: Bool = false

    public init(
        posterUrl: String?,
        title: String = "",
        width: CGFloat = 100,
        height: CGFloat = 150,
        cornerRadius: CGFloat = 12,
        isSeries: Bool = false
    ) {
        self.posterUrl = posterUrl
        self.title = title
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.isSeries = isSeries
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))

            if let url = URL.fromUserString(posterUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    fallbackPoster
                }
            } else {
                fallbackPoster
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var fallbackPoster: some View {
        VStack(spacing: 8) {
            Image(systemName: isSeries ? "play.tv" : "film")
                .font(.system(size: width * 0.25))
                .foregroundStyle(.secondary)

            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
