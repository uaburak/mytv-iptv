import SwiftUI

public struct MediaCardView: View {
    @ObservedObject private var storage = StorageManager.shared

    let id: String?
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
        id: String? = nil,
        title: String,
        imageUrl: String?,
        isLive: Bool = false,
        rating: String? = nil,
        isSeries: Bool = false,
        width: CGFloat = 110,
        aspectRatio: CGFloat = 2/3,
        onPlay: @escaping () -> Void
    ) {
        self.id = id
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
        self.id = item.id
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
        self.id = channel.id
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
                                    .padding(8)
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

                // Puan Rozeti (Film & Dizi)
                if let rating, let score = Double(rating), score > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", score))
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(5)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onPlay()
            } label: {
                Label("İzlemeye Başla", systemImage: "play.fill")
            }

            if let id, !id.isEmpty {
                let isFav = storage.isFavorite(id: id)
                Button {
                    withAnimation {
                        storage.toggleFavorite(id: id)
                    }
                } label: {
                    if isFav {
                        Label("Favorilerden Çıkar", systemImage: "heart.slash")
                    } else {
                        Label("Favorilere Ekle", systemImage: "heart.fill")
                    }
                }
            }
        }
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
            } else {
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 6)
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
