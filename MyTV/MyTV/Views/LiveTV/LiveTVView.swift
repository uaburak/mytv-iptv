import SwiftUI

public struct LiveTVView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var selectedCategory: MediaCategory?

    public init() {}

    private var filteredCategories: [MediaCategory] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return appState.liveCategories
        }
        return appState.liveCategories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var channelsToDisplay: [Channel] {
        var list = appState.channels
        if let selected = selectedCategory {
            list = list.filter { $0.categoryId == selected.id }
        }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return list
    }

    public var body: some View {
        NavigationStack {
            Group {
                if appState.channels.isEmpty {
                    ContentUnavailableView(
                        "Kanal Bulunamadı",
                        systemImage: "tv.slash",
                        description: Text("Hesabınızda canlı kanal bulunmuyor veya henüz yüklenmedi.")
                    )
                } else {
                    VStack(spacing: 0) {
                        // Category Horizontal Filter Pills
                        if !appState.liveCategories.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    Button {
                                        selectedCategory = nil
                                    } label: {
                                        Text("Tümü (\(appState.channels.count))")
                                            .font(.caption.weight(selectedCategory == nil ? .bold : .regular))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(selectedCategory == nil ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                                            .foregroundStyle(selectedCategory == nil ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)

                                    ForEach(appState.liveCategories) { cat in
                                        let isSelected = selectedCategory?.id == cat.id
                                        Button {
                                            selectedCategory = cat
                                        } label: {
                                            Text(cat.name)
                                                .font(.caption.weight(isSelected ? .bold : .regular))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                                                .foregroundStyle(isSelected ? .white : .primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                            .background(Color.secondary.opacity(0.04))
                        }

                        // Channels List
                        List(channelsToDisplay) { channel in
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.12))
                                        .frame(width: 44, height: 44)

                                    if let icon = channel.streamIcon, let url = URL(string: icon) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let img):
                                                img.resizable().aspectRatio(contentMode: .fit)
                                            default:
                                                Image(systemName: "tv")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(width: 36, height: 36)
                                    } else {
                                        Image(systemName: "tv")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(channel.name)
                                        .font(.body.weight(.medium))
                                        .lineLimit(1)

                                    if let num = channel.num {
                                        Text("Kanal \(num)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                playChannel(channel)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Canlı TV")
            .searchable(text: $searchText, prompt: "Kanal Ara...")
            .refreshable {
                await appState.syncActiveAccount()
            }
        }
    }

    private func playChannel(_ channel: Channel) {
        let media = PlayableMedia(
            mediaId: channel.id,
            title: channel.name,
            subtitle: "Canlı Yayın",
            posterUrl: channel.streamIcon,
            streamUrl: channel.streamUrl,
            contentType: .live
        )
        PlaybackManager.shared.play(media: media)
    }
}
