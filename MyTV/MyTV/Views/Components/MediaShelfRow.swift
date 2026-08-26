import SwiftUI

public struct MediaShelfRow: View {
    let title: String
    let subtitle: String?
    let items: [VODItem]
    let onSeeAll: (() -> Void)?
    let onPlay: (VODItem) -> Void

    public init(
        title: String,
        subtitle: String? = nil,
        items: [VODItem],
        onSeeAll: (() -> Void)? = nil,
        onPlay: @escaping (VODItem) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.onSeeAll = onSeeAll
        self.onPlay = onPlay
    }

    public var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if let onSeeAll {
                        Button {
                            onSeeAll()
                        } label: {
                            HStack(spacing: 4) {
                                Text("Tümü")
                                    .font(.system(size: 13, weight: .medium))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                // Carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(items) { item in
                            MediaCardView(item: item, width: 130) {
                                onPlay(item)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
