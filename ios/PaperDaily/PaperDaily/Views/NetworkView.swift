import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var networkStore: NetworkStore

    @State private var searchText = ""
    @State private var selectedPlatform: String?
    @State private var showUnreadOnly = false
    @State private var showFavoritesOnly = false
    @State private var selectedItem: NetworkItem?

    var body: some View {
        let items = networkStore.items(
            searchText: searchText,
            platform: selectedPlatform,
            unreadOnly: showUnreadOnly,
            favoritesOnly: showFavoritesOnly
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                if let lastErrorMessage = networkStore.lastErrorMessage {
                    ErrorStateView(message: lastErrorMessage)
                }

                filters

                NetworkItemListView(
                    items: items,
                    favoriteItemIDs: networkStore.favoriteNetworkIDs,
                    readItemIDs: networkStore.readNetworkIDs,
                    emptyTitle: "暂无网络内容",
                    emptyMessage: "可以稍后刷新，或者调整搜索和筛选条件。",
                    onToggleFavorite: { networkStore.toggleFavorite($0) },
                    onToggleRead: { networkStore.toggleRead($0.id) },
                    onOpenDetail: { selectedItem = $0 }
                )
            }
            .padding(16)
        }
        .desktopPageContainer()
        .navigationTitle("网络")
        .searchable(text: $searchText, prompt: "搜索标题、平台、标签")
        .refreshable {
            await networkStore.refresh()
        }
        .navigationDestination(item: $selectedItem) { item in
            NetworkDetailView(
                item: item,
                isFavorite: networkStore.isFavorite(item.id),
                isRead: networkStore.isRead(item.id),
                onToggleFavorite: { networkStore.toggleFavorite(item) },
                onToggleRead: { networkStore.toggleRead(item.id) }
            )
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("网络推荐")
                .font(.title2.bold())
            Text("来源：\(networkStore.feed?.config.platforms.map(platformLabel).joined(separator: " / ") ?? "暂无")")
                .foregroundStyle(.secondary)
            Text("更新时间：\(networkStore.generatedAtDescription)")
                .foregroundStyle(.secondary)
            if let feed = networkStore.feed {
                Text("内容数量：\(feed.stats.recommendedCount) / 候选数量：\(feed.stats.totalCandidates)")
                    .foregroundStyle(.secondary)
                Text("已读数量：\(readCount(in: feed))")
                    .foregroundStyle(.secondary)
                Text("Schema：\(feed.schemaVersion)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ToggleChip(title: "仅未读", isOn: $showUnreadOnly)
                ToggleChip(title: "仅收藏", isOn: $showFavoritesOnly)
                if networkStore.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    platformChip(title: "全部", platform: nil)
                    ForEach(networkStore.availablePlatforms, id: \.self) { platform in
                        platformChip(title: platformLabel(platform), platform: platform)
                    }
                }
            }
        }
    }

    private func readCount(in feed: NetworkFeed) -> Int {
        let itemIDs = Set(feed.items.map(\.id))
        return networkStore.readNetworkIDs.intersection(itemIDs).count
    }

    private func platformLabel(_ platform: String) -> String {
        switch platform.lowercased() {
        case "github":
            return "GitHub"
        case "openreview":
            return "OpenReview"
        case "youtube":
            return "YouTube"
        default:
            return platform.capitalized
        }
    }

    private func platformChip(title: String, platform: String?) -> some View {
        Button {
            selectedPlatform = platform
        } label: {
            Text(title)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background((selectedPlatform == platform ? Color.accentColor : Color(.tertiarySystemFill)), in: Capsule())
                .foregroundStyle(selectedPlatform == platform ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
