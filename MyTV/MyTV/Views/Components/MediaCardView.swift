import SwiftUI

public struct MediaCardView: View {
    let item: VODItem
    var width: CGFloat = 130
    var aspectRatio: CGFloat = 2/3
    let onPlay: () -> Void

    public init(item: VODItem, width: CGFloat = 130, aspectRatio: CGFloat = 2/3, onPlay: @escaping () -> Void) {
        self.item = item
        self.width = width
        self.aspectRatio = aspectRatio
        self.onPlay = onPlay
    }

    public var body: some View {
        Button {
            onPlay()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))

                        if let icon = item.streamIcon ?? item.backdropUrl, let url = URL(string: icon) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                case .failure(_):
                                    fallbackImage
                                case .empty:
                                    ProgressView()
                                        .scaleEffect(0.8)
                                @unknown default:
                                    fallbackImage
                                }
                            }
                        } else {
                            fallbackImage
                        }
                    }
                    .frame(width: width, height: width / aspectRatio)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )

                    // Rating Badge
                    if let rating = item.rating, let score = Double(rating), score > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", score))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(6)
                    }
                }

                // Title & Genre
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if let genre = item.genre, !genre.isEmpty {
                        Text(genre)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var fallbackImage: some View {
        VStack(spacing: 6) {
            Image(systemName: item.type == .series ? "play.tv" : "film")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
