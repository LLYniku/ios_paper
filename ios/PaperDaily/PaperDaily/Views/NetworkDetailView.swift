import SwiftUI

struct NetworkDetailView: View {
    let item: NetworkItem
    let isFavorite: Bool
    let isRead: Bool
    let onToggleFavorite: () -> Void
    let onToggleRead: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.title2.bold())
                    Text(item.creator)
                        .foregroundStyle(.secondary)
                    Text(item.publicationLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                actionButtons

                detailSection(title: "一句话总结", body: item.tldr ?? "暂无")
                detailSection(title: "中文总结", body: item.detailSummary)
                if let recommendationReason = item.recommendationReason, !recommendationReason.isEmpty {
                    detailSection(title: "推荐理由", body: recommendationReason)
                }
                detailSection(title: "原始内容摘录", body: item.rawExcerpt.isEmpty ? "暂无摘录" : item.rawExcerpt)

                if !item.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("标签")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(item.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color(.tertiarySystemFill), in: Capsule())
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("网络内容")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    openURL(item.url)
                } label: {
                    Label("打开链接", systemImage: "link")
                }

                Button {
                    onToggleFavorite()
                } label: {
                    Label(isFavorite ? "取消收藏" : "收藏", systemImage: isFavorite ? "star.fill" : "star")
                }

                Button {
                    onToggleRead()
                } label: {
                    Label(isRead ? "标未读" : "标已读", systemImage: isRead ? "eye.slash" : "eye")
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func detailSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
