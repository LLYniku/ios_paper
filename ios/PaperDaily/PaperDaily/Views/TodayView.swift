import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: PaperStore
    @EnvironmentObject private var settings: UserSettingsStore

    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var showUnreadOnly = false
    @State private var showFavoritesOnly = false
    @State private var selectedPaper: PaperItem?
    @State private var paperURLText = ""

    var body: some View {
        let papers = store.papers(
            searchText: searchText,
            category: selectedCategory,
            unreadOnly: showUnreadOnly,
            favoritesOnly: showFavoritesOnly
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                submitPaperCard

                if let lastErrorMessage = store.lastErrorMessage {
                    ErrorStateView(message: lastErrorMessage)
                }

                if let statusMessage = store.statusMessage {
                    StatusMessageView(message: statusMessage)
                }

                filters

                PaperListView(
                    papers: papers,
                    favoritePaperIDs: store.favoritePaperIDs,
                    readPaperIDs: store.readPaperIDs,
                    emptyTitle: "今日暂无匹配论文",
                    emptyMessage: "可以稍后刷新，或者调整搜索和筛选条件。",
                    onToggleFavorite: { store.toggleFavorite($0) },
                    onToggleRead: { store.toggleRead($0.id) },
                    onOpenDetail: { selectedPaper = $0 }
                )
            }
            .padding(16)
        }
        .desktopPageContainer()
        .navigationTitle("每日论文")
        .searchable(text: $searchText, prompt: "搜索标题、作者、关键词")
        .refreshable {
            await store.refresh()
        }
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
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerTitle)
                .font(.title2.bold())
            Text("更新时间：\(store.generatedAtDescription)")
                .foregroundStyle(.secondary)
            if let feed = store.feed {
                Text("推荐数量：\(feed.stats.recommendedCount) / 候选数量：\(feed.stats.totalCandidates)")
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
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(title: "全部", category: nil)
                    ForEach(store.availableCategories, id: \.self) { category in
                        categoryChip(title: category, category: category)
                    }
                }
            }
        }
    }

    private var submitPaperCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("搜索并加入")
                .font(.headline)
            Text("输入 arXiv 论文链接后，会触发 GitHub Actions 分析并加入今日列表顶部。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                TextField("https://arxiv.org/pdf/2604.22312", text: $paperURLText)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()

                Button {
                    Task {
                        await store.submitPaperToToday(urlString: paperURLText)
                        if store.lastErrorMessage == nil {
                            paperURLText = ""
                        }
                    }
                } label: {
                    if store.isSubmittingPaper {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("加入")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isSubmittingPaper || paperURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func categoryChip(title: String, category: String?) -> some View {
        Button {
            selectedCategory = category
        } label: {
            Text(title)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background((selectedCategory == category ? Color.accentColor : Color(.tertiarySystemFill)), in: Capsule())
                .foregroundStyle(selectedCategory == category ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var headerTitle: String {
        guard let feed = store.feed else {
            return "正在准备今日推荐"
        }
        if feed.recommendationMatchesToday() {
            return "今日推荐"
        }
        return "当前数据为 \(feed.recommendationDate)，今日数据尚未更新"
    }
}

struct StatusMessageView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle")
            .font(.footnote)
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label(title, systemImage: isOn ? "checkmark.circle.fill" : "circle")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isOn ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
