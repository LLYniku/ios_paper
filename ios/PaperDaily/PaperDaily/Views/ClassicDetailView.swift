import SwiftUI

struct ClassicDetailView: View {
    let paper: ClassicPaper
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
                    Text(paper.publicationLine)
                        .foregroundStyle(.secondary)
                }

                actionButtons

                detailSection(title: "卡片简介", content: paper.chineseAbstract)
                detailSection(title: "简单介绍", content: paper.simpleIntro ?? "暂无")
                detailSection(title: "一句话 TL;DR", content: paper.tldr ?? "暂无")
                detailSection(title: "英文原始摘要", content: paper.abstract ?? "暂无")
                detailSection(title: "所属方向", content: paper.category)
                detailSection(title: "顶会 / 期刊", content: paper.venue ?? paper.publication)
                detailSection(title: "年份", content: paper.year.map(String.init) ?? "未标注")
                detailSection(title: "原始来源", content: paper.publication)
                detailSection(title: "来源仓库", content: "Awesome LLM Compression")
            }
            .padding(16)
        }
        .navigationTitle("经典论文")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                actionButton(title: "打开论文", url: paper.paperURL)
                actionButton(title: "打开代码", url: paper.codeURL)
            }
            HStack {
                actionButton(title: "打开项目页", url: paper.projectURL)
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
}
