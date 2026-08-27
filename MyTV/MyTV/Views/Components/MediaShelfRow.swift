import SwiftUI

public struct MediaShelfRow: View {
    let title: String
    let onSeeAll: (() -> Void)?
    let content: AnyView

    // MARK: - VODItems (Film / Dizi) için
    public init(
        title: String,
        subtitle: String? = nil,
        items: [VODItem],
        namespace: Namespace.ID? = nil,
        onSeeAll: (() -> Void)? = nil,
        onPlay: @escaping (VODItem) -> Void
    ) {
        self.title = title
        self.onSeeAll = onSeeAll
        self.content = AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 11) {
                    ForEach(items) { item in
                        let card = MediaCardView(item: item, width: 110) {
                            onPlay(item)
                        }
                        if #available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, *), let namespace {
                            card.matchedTransitionSource(id: item.id, in: namespace)
                        } else {
                            card
                        }
                    }
                }
                .padding(.horizontal)
            }
        )
    }

    // MARK: - Channels (Canlı TV) için
    public init(
        title: String,
        subtitle: String? = nil,
        channels: [Channel],
        onSeeAll: (() -> Void)? = nil,
        onPlay: @escaping (Channel) -> Void
    ) {
        self.title = title
        self.onSeeAll = onSeeAll
        self.content = AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 11) {
                    ForEach(channels) { ch in
                        MediaCardView(channel: ch, width: 110) {
                            onPlay(ch)
                        }
                    }
                }
                .padding(.horizontal)
            }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header (Kibar Başlık ve sağında inline ok ile Tümü aksiyonu)
            HStack {
                if let onSeeAll {
                    Button(action: onSeeAll) {
                        HStack(spacing: 4) {
                            Text(title)
                                .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()
            }
            .padding(.horizontal)

            // Carousel Content
            content
        }
        .padding(.vertical, 2)
    }
}
