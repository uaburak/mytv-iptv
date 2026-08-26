import SwiftUI

public struct HeroBannerView: View {
    let items: [VODItem]
    let onPlay: (VODItem) -> Void
    let onSelect: (VODItem) -> Void

    @State private var currentIndex = 0

    public init(items: [VODItem], onPlay: @escaping (VODItem) -> Void, onSelect: @escaping (VODItem) -> Void) {
        self.items = items
        self.onPlay = onPlay
        self.onSelect = onSelect
    }

    public var body: some View {
        if !items.isEmpty {
            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    bannerItem(item: item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal)
            .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 8)
        }
    }

    @ViewBuilder
    private func bannerItem(item: VODItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Background Backdrop Image
            GeometryReader { geo in
                ZStack {
                    Color.black

                    if let bg = item.backdropUrl ?? item.streamIcon, let url = URL(string: bg) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                            default:
                                Color.gray.opacity(0.2)
                            }
                        }
                    }
                }
            }

            // Cinematic Dark Gradient Overlay
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.4), location: 0.4),
                    .init(color: .black.opacity(0.95), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content Details & Actions
            VStack(alignment: .leading, spacing: 10) {
                // Category & Rating Tag
                HStack(spacing: 8) {
                    Text(item.type.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundStyle(.white)

                    if let rating = item.rating, let score = Double(rating), score > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", score))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }

                    if let release = item.releaseDate, !release.isEmpty {
                        Text(release.prefix(4))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }

                // Title
                Text(item.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(radius: 4)

                // Overview Plot
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .lineSpacing(2)
                        .frame(maxWidth: 480, alignment: .leading)
                }

                // Action Buttons (Play & Details)
                HStack(spacing: 12) {
                    Button {
                        onPlay(item)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("Oynat")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onSelect(item)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14, weight: .medium))
                            Text("Detay")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .padding(.bottom, 12)
        }
    }
}
