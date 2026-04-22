import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var store: PaperStore
    @EnvironmentObject private var settings: UserSettingsStore

    @State private var searchText = ""
    @State private var showUnreadOnly = false

    var body: some View {
        let records = store.favoritePapers(
            searchText: searchText,
            unreadOnly: showUnreadOnly
        )
        let papers = records.map(\.paper)
        let contextByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.contextNote) })

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

                PaperListView(
                    papers: papers,
                    favoritePaperIDs: store.favoritePaperIDs,
                    readPaperIDs: store.readPaperIDs,
                    emptyTitle: "还没有收藏的论文",
                    emptyMessage: "在今日推荐页点星标后，这里会自动汇总。",
                    contextNote: { contextByID[$0.id] },
                    onToggleFavorite: { store.toggleFavorite($0) },
                    onToggleRead: { store.toggleRead($0.id) }
                )
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
