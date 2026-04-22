import SwiftUI

struct PaperDetailView: View {
    let paper: PaperItem
    let isFavorite: Bool
    let isRead: Bool
    let onToggleFavorite: () -> Void
    let onToggleRead: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(paper.title)
                        .font(.title2.bold())
                    Text(paper.authors.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                    if let score = paper.relevanceScore {
                        Text("相关性分数：\(String(format: "%.3f", score))")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                actionButtons

                detailSection(title: "中文总结", content: paper.summaryZh ?? "暂无")
                detailSection(title: "一句话 TL;DR", content: paper.tldr ?? "暂无")
                detailSection(title: "推荐理由", content: paper.recommendationReason ?? "暂无")
                detailSection(title: "原始摘要", content: paper.abstract ?? "暂无")
                detailSection(title: "关键词", content: paper.keywords.joined(separator: "、").ifEmpty("暂无"))
                detailSection(title: "分类", content: paper.categories.joined(separator: "、").ifEmpty("暂无"))
                detailSection(title: "机构", content: paper.affiliations.joined(separator: "、").ifEmpty("暂无"))
                detailSection(title: "发布时间", content: formattedDate(paper.publishedAt))
                detailSection(title: "更新时间", content: formattedDate(paper.updatedAt))
                detailSection(title: "DOI", content: paper.doi ?? "暂无")
            }
            .padding(16)
        }
        .navigationTitle("论文详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                actionButton(title: "打开摘要页", url: LinkRouter.url(for: .abstract, in: paper))
                actionButton(title: "打开 PDF", url: LinkRouter.url(for: .pdf, in: paper))
            }
            HStack {
                actionButton(title: "打开代码", url: LinkRouter.url(for: .code, in: paper))
                actionButton(title: "打开项目页", url: LinkRouter.url(for: .project, in: paper))
            }
            HStack {
                Button(isFavorite ? "取消收藏" : "加入收藏") {
                    onToggleFavorite()
                }
                .buttonStyle(.borderedProminent)

                Button(isRead ? "标记未读" : "标记已读") {
                    onToggleRead()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func actionButton(title: String, url: URL?) -> some View {
        Button(title) {
            guard let url else { return }
            openURL(url)
        }
        .buttonStyle(.bordered)
        .disabled(url == nil)
    }

    private func detailSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "暂无" }
        return FeedDisplay.dateTimeString(from: date)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
