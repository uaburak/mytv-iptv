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
        onSeeAll: (() -> Void)? = nil,
        onPlay: @escaping (VODItem) -> Void
    ) {
        self.title = title
        self.onSeeAll = onSeeAll
        self.content = AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 11) {
                    ForEach(items) { item in
                        MediaCardView(item: item, width: 110) {
                            onPlay(item)
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
            // Header (Kibar Başlık ve opsiyonel Tümü butonu)
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                if let onSeeAll {
                    Button {
                        onSeeAll()
                    } label: {
                        HStack(spacing: 3) {
                            Text("Tümü")
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            // Carousel Content
            content
        }
        .padding(.vertical, 2)
    }
}
