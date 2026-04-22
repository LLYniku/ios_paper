import SwiftUI

@main
struct PaperDailyApp: App {
    @StateObject private var settings: UserSettingsStore
    @StateObject private var store: PaperStore
    @StateObject private var classicsStore: ClassicsStore

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
            .task {
                await classicsStore.bootstrap()
                await store.bootstrap()
            }
        }
    }
}
