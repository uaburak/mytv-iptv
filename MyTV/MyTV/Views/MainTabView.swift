import SwiftUI

public struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared
    @State private var searchText = ""

    public init() {}

    public var body: some View {
        ZStack {
            TabView {
                Tab("Ana Sayfa", systemImage: "house") {
                    HomeView()
                }

                Tab("Favoriler", systemImage: "heart") {
                    FavoritesView()
                }

                Tab("Ayarlar", systemImage: "gearshape") {
                    SettingsView()
                }

                Tab(role: .search) {
                    NavigationStack {
                        SearchView(searchText: $searchText)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Kanal, Film veya Dizi Ara...")
            .tabViewSearchActivation(.searchTabSelection)
            #if os(iOS)
            .tabBarMinimizeBehavior(.onScrollDown)
            #endif

            if appState.isSyncing && !appState.isAddAccountPresented && appState.channels.isEmpty {
                SyncProgressOverlayView()
            }

            // Direct Full-Window Player Screen (No modal/sheet presentation on iOS, macOS, tvOS)
            if playback.isPresented {
                NativePlayerView()
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: playback.isPresented)
    }
}
