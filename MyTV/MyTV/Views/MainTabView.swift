import SwiftUI

public struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared

    public init() {}

    public var body: some View {
        ZStack {
            TabView(selection: $appState.selectedTab) {
                HomeView()
                    .tabItem {
                        Label("Ana Sayfa", systemImage: "house")
                    }
                    .tag(0)

                LiveTVView()
                    .tabItem {
                        Label("Canlı", systemImage: "tv")
                    }
                    .tag(1)

                MoviesView()
                    .tabItem {
                        Label("Filmler", systemImage: "film")
                    }
                    .tag(2)

                SeriesView()
                    .tabItem {
                        Label("Diziler", systemImage: "play.tv")
                    }
                    .tag(3)

                SettingsView()
                    .tabItem {
                        Label("Ayarlar", systemImage: "gearshape")
                    }
                    .tag(4)
            }

            if appState.isSyncing && !appState.isAddAccountPresented && appState.channels.isEmpty {
                SyncProgressOverlayView()
            }
        }
        #if os(macOS)
        .sheet(isPresented: $playback.isPresented) {
            NativePlayerView()
        }
        #else
        .fullScreenCover(isPresented: $playback.isPresented) {
            NativePlayerView()
        }
        #endif
    }
}
