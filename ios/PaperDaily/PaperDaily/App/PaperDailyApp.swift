import SwiftUI

@main
struct PaperDailyApp: App {
    @StateObject private var settings: UserSettingsStore
    @StateObject private var store: PaperStore
    @StateObject private var classicsStore: ClassicsStore
    @StateObject private var networkStore: NetworkStore

    init() {
        let settingsStore = UserSettingsStore()
        _settings = StateObject(wrappedValue: settingsStore)
        _store = StateObject(
            wrappedValue: PaperStore(
                settings: settingsStore,
                sampleFeedLoader: PaperStore.makeSampleFeedLoader(bundle: .main)
            )
        )
        _classicsStore = StateObject(
            wrappedValue: ClassicsStore(
                settings: settingsStore,
                sampleFeedLoader: ClassicsStore.makeSampleFeedLoader(bundle: .main)
            )
        )
        _networkStore = StateObject(
            wrappedValue: NetworkStore(
                settings: settingsStore,
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
            .environmentObject(settings)
            .environmentObject(store)
            .environmentObject(classicsStore)
            .environmentObject(networkStore)
            .task {
                await classicsStore.bootstrap()
                await networkStore.bootstrap()
                await store.bootstrap()
            }
        }
    }
}
