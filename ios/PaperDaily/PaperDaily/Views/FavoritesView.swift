import SwiftUI

struct FavoritesView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case today = "今日"
        case classics = "经典"
        case network = "网络"

        var id: String { rawValue }
    }

    @EnvironmentObject private var store: PaperStore
    @EnvironmentObject private var classicsStore: ClassicsStore
    @EnvironmentObject private var networkStore: NetworkStore
    @EnvironmentObject private var settings: UserSettingsStore

    @State private var searchText = ""
    @State private var showUnreadOnly = false
    @State private var selectedScope: Scope = .today
    @State private var selectedPaper: PaperItem?
    @State private var selectedClassicPaper: ClassicPaper?
    @State private var selectedNetworkItem: NetworkItem?

    var body: some View {
        let todayRecords = store.favoritePapers(
            searchText: searchText,
            unreadOnly: showUnreadOnly
        )
        let todayPapers = todayRecords.map(\.paper)
        let todayContextByID = Dictionary(uniqueKeysWithValues: todayRecords.map { ($0.id, $0.contextNote) })
        let todayRatingByID = Dictionary(uniqueKeysWithValues: todayRecords.map { ($0.id, $0.rating) })

        let classicRecords = classicsStore.favoritePapers(
            searchText: searchText,
            unreadOnly: showUnreadOnly
        )
        let classicPapers = classicRecords.map(\.paper)
        let classicContextByID = Dictionary(uniqueKeysWithValues: classicRecords.map { ($0.id, $0.contextNote) })
        let classicRatingByID = Dictionary(uniqueKeysWithValues: classicRecords.map { ($0.id, $0.rating) })

        let networkRecords = networkStore.favoriteItems(
            searchText: searchText,
            unreadOnly: showUnreadOnly
        )
        let networkItems = networkRecords.map(\.item)
        let networkContextByID = Dictionary(uniqueKeysWithValues: networkRecords.map { ($0.id, $0.contextNote) })
        let networkRatingByID = Dictionary(uniqueKeysWithValues: networkRecords.map { ($0.id, $0.rating) })

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
                        rating: { todayRatingByID[$0.id] ?? 0 },
                        onSetRating: { store.setFavoriteRating($0.id, rating: $1) },
                        onToggleFavorite: { store.toggleFavorite($0) },
                        onToggleRead: { store.toggleRead($0.id) },
                        onOpenDetail: { selectedPaper = $0 }
                    )
                } else if selectedScope == .classics {
                    ClassicPaperListView(
                        papers: classicPapers,
                        favoritePaperIDs: classicsStore.favoriteClassicIDs,
                        readPaperIDs: classicsStore.readClassicIDs,
                        emptyTitle: "还没有收藏的经典论文",
                        emptyMessage: "在经典页点收藏后，这里会长期保留。",
                        contextNote: { classicContextByID[$0.id] },
                        rating: { classicRatingByID[$0.id] ?? 0 },
                        onSetRating: { classicsStore.setFavoriteRating($0.id, rating: $1) },
                        onToggleFavorite: { classicsStore.toggleFavorite($0) },
                        onToggleRead: { classicsStore.toggleRead($0.id) },
                        onOpenDetail: { selectedClassicPaper = $0 }
                    )
                } else {
                    NetworkItemListView(
                        items: networkItems,
                        favoriteItemIDs: networkStore.favoriteNetworkIDs,
                        readItemIDs: networkStore.readNetworkIDs,
                        emptyTitle: "还没有收藏的网络内容",
                        emptyMessage: "在网络页点收藏后，这里会长期保留。",
                        contextNote: { networkContextByID[$0.id] },
                        rating: { networkRatingByID[$0.id] ?? 0 },
                        onSetRating: { networkStore.setFavoriteRating($0.id, rating: $1) },
                        onToggleFavorite: { networkStore.toggleFavorite($0) },
                        onToggleRead: { networkStore.toggleRead($0.id) },
                        onOpenDetail: { selectedNetworkItem = $0 }
                    )
                }
            }
            .padding(16)
        }
        .desktopPageContainer()
        .navigationTitle("收藏")
        .searchable(text: $searchText, prompt: "搜索收藏内容")
        .task {
            showUnreadOnly = settings.defaultUnreadOnly
        }
        .navigationDestination(item: $selectedPaper) { paper in
            PaperDetailView(
                paper: paper,
                isFavorite: store.isFavorite(paper.id),
                isRead: store.isRead(paper.id),
                onToggleFavorite: { store.toggleFavorite(paper) },
                onToggleRead: { store.toggleRead(paper.id) }
            )
        }
        .navigationDestination(item: $selectedClassicPaper) { paper in
            ClassicDetailView(
                paper: paper,
                isFavorite: classicsStore.isFavorite(paper.id),
                isRead: classicsStore.isRead(paper.id),
                onToggleFavorite: { classicsStore.toggleFavorite(paper) },
                onToggleRead: { classicsStore.toggleRead(paper.id) }
            )
        }
        .navigationDestination(item: $selectedNetworkItem) { item in
            NetworkDetailView(
                item: item,
                isFavorite: networkStore.isFavorite(item.id),
                isRead: networkStore.isRead(item.id),
                onToggleFavorite: { networkStore.toggleFavorite(item) },
                onToggleRead: { networkStore.toggleRead(item.id) }
            )
        }
    }
}
