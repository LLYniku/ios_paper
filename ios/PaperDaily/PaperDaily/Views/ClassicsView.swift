import SwiftUI

struct ClassicsView: View {
    @EnvironmentObject private var classicsStore: ClassicsStore

    @State private var searchText = ""
    @State private var selectedCategory: String?

    var body: some View {
        let papers = classicsStore.papers(
            searchText: searchText,
            category: selectedCategory
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                if let lastErrorMessage = classicsStore.lastErrorMessage {
                    ErrorStateView(message: lastErrorMessage)
                }

                filters

                if papers.isEmpty {
                    EmptyStateView(
                        title: "暂无经典论文",
                        message: "可以稍后刷新，或者调整搜索和筛选条件。"
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(papers) { paper in
                            ClassicPaperRowView(paper: paper)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("经典")
        .searchable(text: $searchText, prompt: "搜索标题、会议、类别")
        .refreshable {
            await classicsStore.refresh()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("经典论文库")
                .font(.title2.bold())
            Text("数据源：Awesome LLM Compression")
                .foregroundStyle(.secondary)
            Text("更新时间：\(classicsStore.generatedAtDescription)")
                .foregroundStyle(.secondary)
            if let feed = classicsStore.feed {
                Text("论文数量：\(feed.paperCount)")
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
            if classicsStore.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(title: "全部", category: nil)
                    ForEach(classicsStore.availableCategories, id: \.self) { category in
                        categoryChip(title: category, category: category)
                    }
                }
            }
        }
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
}
