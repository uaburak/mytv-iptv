import SwiftUI

public struct ChannelCardView: View {
    let channel: Channel
    let onPlay: () -> Void

    public init(channel: Channel, onPlay: @escaping () -> Void) {
        self.channel = channel
        self.onPlay = onPlay
    }

    public var body: some View {
        Button {
            onPlay()
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))

                        if let icon = channel.streamIcon, let url = URL(string: icon) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .padding(10)
                                default:
                                    Image(systemName: "tv")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Image(systemName: "tv")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )

                    // Mini Live Indicator Dot
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .padding(6)
                }

                Text(channel.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .frame(width: 88)
            }
        }
        .buttonStyle(.plain)
    }
}
