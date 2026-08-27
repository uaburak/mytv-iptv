import SwiftUI

public struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var playback = PlaybackManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: AppTab = .home
    @State private var searchText = ""

    public init() {}

    public var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                // 1. Anasayfa
                Tab(value: AppTab.home) {
                    HomeView()
                } label: {
                    tabLabel(for: .home)
                }

                // 2. Favoriler
                Tab(value: AppTab.favorites) {
                    FavoritesView()
                } label: {
                    tabLabel(for: .favorites)
                }

                // 3. Listeler
                Tab(value: AppTab.playlists) {
                    PlaylistsView()
                } label: {
                    tabLabel(for: .playlists)
                }

                // 4. Arama
                Tab(value: AppTab.search) {
                    NavigationStack {
                        SearchView(searchText: $searchText)
                    }
                } label: {
                    tabLabel(for: .search)
                }

                // 5. Profil
                Tab(value: AppTab.profile) {
                    ProfileView()
                } label: {
                    tabLabel(for: .profile)
                }
            }
            #if os(iOS)
            .tabBarMinimizeBehavior(.onScrollDown)
            #endif
            .onAppear {
                TabBarConfigurator.configure(tabs: AppTab.allCases)
            }
            .onChange(of: colorScheme) { _, _ in
                TabBarConfigurator.configure(tabs: AppTab.allCases)
            }
            .tint(.brandPrimary)

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

    // MARK: - Tab Label (Finvo Style Outline/Fill Template Icons)
    private func tabLabel(for tab: AppTab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(tab.iconName(isActive: false))
                .renderingMode(.template)
        }
    }
}
