import SwiftUI

public struct MediaCardView: View {
    let title: String
    let imageUrl: String?
    let isLive: Bool
    let rating: String?
    let isSeries: Bool
    var width: CGFloat = 110
    var aspectRatio: CGFloat = 2/3
    let onPlay: () -> Void

    // MARK: - Genel Başlatıcı
    public init(
        title: String,
        imageUrl: String?,
        isLive: Bool = false,
        rating: String? = nil,
        isSeries: Bool = false,
        width: CGFloat = 110,
        aspectRatio: CGFloat = 2/3,
        onPlay: @escaping () -> Void
    ) {
        self.title = title
        self.imageUrl = imageUrl
        self.isLive = isLive
        self.rating = rating
        self.isSeries = isSeries
        self.width = width
        self.aspectRatio = aspectRatio
        self.onPlay = onPlay
    }

    // MARK: - VODItem (Film / Dizi) Başlatıcısı
    public init(item: VODItem, width: CGFloat = 110, aspectRatio: CGFloat = 2/3, onPlay: @escaping () -> Void) {
        self.title = item.name
        self.imageUrl = item.streamIcon ?? item.backdropUrl
        self.isLive = false
        self.rating = item.rating
        self.isSeries = (item.type == .series)
        self.width = width
        self.aspectRatio = aspectRatio
        self.onPlay = onPlay
    }

    // MARK: - Channel (Canlı TV) Başlatıcısı
    public init(channel: Channel, width: CGFloat = 110, aspectRatio: CGFloat = 2/3, onPlay: @escaping () -> Void) {
        self.title = channel.name
        self.imageUrl = channel.streamIcon
        self.isLive = true
        self.rating = nil
        self.isSeries = false
        self.width = width
        self.aspectRatio = aspectRatio
        self.onPlay = onPlay
    }

    public var body: some View {
        Button {
            onPlay()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))

                        if let url = URL.fromUserString(imageUrl) {
                            CachedAsyncImage(url: url) { image in
                                if isLive {
                                    // Kanal logosu
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .padding(10)
                                } else {
                                    // Film / Dizi afişi
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                }
                            } placeholder: {
                                fallbackImage
                            }
                        } else {
                            fallbackImage
                        }
                    }
                    .frame(width: width, height: width / aspectRatio)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )

                    // Canlı Yayın Rozeti
                    if isLive {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(.red)
                                .frame(width: 4, height: 4)
                            Text("CANLI")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(5)
                    } else if let rating, let score = Double(rating), score > 0 {
                        // Puan Rozeti
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", score))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(5)
                    }
                }

                // Sadece Başlık (Kibar ve kompakt)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var fallbackImage: some View {
        VStack(spacing: 4) {
            Image(systemName: isLive ? "tv" : (isSeries ? "play.tv" : "film"))
                .font(.system(size: 22))
                .foregroundStyle(.secondary)

            if isLive {
                let initials = getInitials(from: title)
                if !initials.isEmpty {
                    Text(initials)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func getInitials(from name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "HD+", with: "")
            .replacingOccurrences(of: "HD", with: "")
            .replacingOccurrences(of: "FHD", with: "")
            .replacingOccurrences(of: "4K", with: "")
            .replacingOccurrences(of: "SD", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = cleaned.split(separator: " ")
        if words.count >= 2 {
            return "\(words[0].prefix(1))\(words[1].prefix(1))".uppercased()
        } else if let first = words.first {
            return String(first.prefix(3)).uppercased()
        }
        return ""
    }
}
