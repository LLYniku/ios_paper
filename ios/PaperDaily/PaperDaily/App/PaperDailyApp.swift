import SwiftUI

@main
struct PaperDailyApp: App {
    @StateObject private var settings: UserSettingsStore
    @StateObject private var store: PaperStore

    init() {
        let settingsStore = UserSettingsStore()
        _settings = StateObject(wrappedValue: settingsStore)
        _store = StateObject(
            wrappedValue: PaperStore(
                settings: settingsStore,
                sampleFeedLoader: PaperStore.makeSampleFeedLoader(bundle: .main)
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            TabView {
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
            .task {
                await store.bootstrap()
            }
        }
    }
}
