import SwiftUI

struct FavoritesView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case today = "今日"
        case classics = "经典"

        var id: String { rawValue }
    }

    @EnvironmentObject private var store: PaperStore
    @EnvironmentObject private var classicsStore: ClassicsStore
    @EnvironmentObject private var settings: UserSettingsStore

    @State private var searchText = ""
    @State private var showUnreadOnly = false
    @State private var selectedScope: Scope = .today

    var body: some View {
        let todayRecords = store.favoritePapers(
            searchText: searchText,
            unreadOnly: showUnreadOnly
        )
        let todayPapers = todayRecords.map(\.paper)
        let todayContextByID = Dictionary(uniqueKeysWithValues: todayRecords.map { ($0.id, $0.contextNote) })

        let classicRecords = classicsStore.favoritePapers(
            searchText: searchText,
            unreadOnly: showUnreadOnly
        )
        let classicPapers = classicRecords.map(\.paper)
        let classicContextByID = Dictionary(uniqueKeysWithValues: classicRecords.map { ($0.id, $0.contextNote) })

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("本地收藏")
                        .font(.title2.bold())
                    Spacer()
                    Button(showUnreadOnly ? "显示全部" : "仅未读") {
                        showUnreadOnly.toggle()
                    }
                    .buttonStyle(.bordered)
                }

                Picker("收藏范围", selection: $selectedScope) {
                    ForEach(Scope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                if selectedScope == .today {
                    PaperListView(
                        papers: todayPapers,
                        favoritePaperIDs: store.favoritePaperIDs,
                        readPaperIDs: store.readPaperIDs,
                        emptyTitle: "还没有收藏的今日论文",
                        emptyMessage: "在今日推荐页点星标后，这里会自动汇总。",
                        contextNote: { todayContextByID[$0.id] },
                        onToggleFavorite: { store.toggleFavorite($0) },
                        onToggleRead: { store.toggleRead($0.id) }
                    )
                } else {
                    ClassicPaperListView(
                        papers: classicPapers,
                        favoritePaperIDs: classicsStore.favoriteClassicIDs,
                        readPaperIDs: classicsStore.readClassicIDs,
                        emptyTitle: "还没有收藏的经典论文",
                        emptyMessage: "在经典页点收藏后，这里会长期保留。",
                        contextNote: { classicContextByID[$0.id] },
                        onToggleFavorite: { classicsStore.toggleFavorite($0) },
                        onToggleRead: { classicsStore.toggleRead($0.id) }
                    )
                }
            }
            .padding(16)
        }
        .navigationTitle("收藏")
        .searchable(text: $searchText, prompt: "搜索收藏论文")
        .task {
            showUnreadOnly = settings.defaultUnreadOnly
        }
    }
}
