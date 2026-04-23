import SwiftUI

@main
struct PaperDailyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var syncStore: AppSyncStore
    @StateObject private var settings: UserSettingsStore
    @StateObject private var store: PaperStore
    @StateObject private var classicsStore: ClassicsStore
    @StateObject private var networkStore: NetworkStore

    init() {
        let syncedStateStore = AppSyncStore()
        let settingsStore = UserSettingsStore(syncStore: syncedStateStore)
        syncedStateStore.configureRemote {
            settingsStore.resolvedSyncConfiguration()
        }
        _syncStore = StateObject(wrappedValue: syncedStateStore)
        _settings = StateObject(wrappedValue: settingsStore)
        _store = StateObject(
            wrappedValue: PaperStore(
                settings: settingsStore,
                syncStore: syncedStateStore,
                sampleFeedLoader: PaperStore.makeSampleFeedLoader(bundle: .main)
            )
        )
        _classicsStore = StateObject(
            wrappedValue: ClassicsStore(
                settings: settingsStore,
                syncStore: syncedStateStore,
                sampleFeedLoader: ClassicsStore.makeSampleFeedLoader(bundle: .main)
            )
        )
        _networkStore = StateObject(
            wrappedValue: NetworkStore(
                settings: settingsStore,
                syncStore: syncedStateStore,
                sampleFeedLoader: NetworkStore.makeSampleFeedLoader(bundle: .main)
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack {
                    ClassicsView()
                }
                .tabItem {
                    Label("经典", systemImage: "books.vertical")
                }

                NavigationStack {
                    NetworkView()
                }
                .tabItem {
                    Label("网络", systemImage: "network")
                }

                NavigationStack {
                    TodayView()
                }
                .tabItem {
                    Label("今日", systemImage: "newspaper")
                }

                NavigationStack {
                    FavoritesView()
                }
                .tabItem {
                    Label("收藏", systemImage: "star")
                }

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
            }
            .environmentObject(syncStore)
            .environmentObject(settings)
            .environmentObject(store)
            .environmentObject(classicsStore)
            .environmentObject(networkStore)
            .frame(
                minWidth: DesktopLayout.isDesktop ? DesktopLayout.minWindowWidth : nil,
                minHeight: DesktopLayout.isDesktop ? DesktopLayout.minWindowHeight : nil
            )
            .task {
                syncStore.start()
                syncStore.refreshFromRemote()
                await classicsStore.bootstrap()
                await networkStore.bootstrap()
                await store.bootstrap()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                syncStore.refreshFromCloud()
                syncStore.refreshFromRemote()
            }
        }
    }
}
