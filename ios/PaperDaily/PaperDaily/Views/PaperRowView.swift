import SwiftUI

struct PaperRowView: View {
    let paper: PaperItem
    let isFavorite: Bool
    let isRead: Bool
    let onToggleFavorite: () -> Void
    let onToggleRead: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(paper.title)
                        .font(.headline)
                    Text(paper.tldr ?? "暂无 TL;DR")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 8) {
                    if let score = paper.relevanceScore {
                        Text(String(format: "%.2f", score))
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                    }
                    Label(isRead ? "已读" : "未读", systemImage: isRead ? "eye.fill" : "eye.slash")
                        .font(.caption)
                        .foregroundStyle(isRead ? .secondary : .primary)
                }
            }

            Text(paper.authorSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)

            tags

            HStack(spacing: 10) {
                Button {
                    onToggleFavorite()
                } label: {
                    Label(isFavorite ? "已收藏" : "收藏", systemImage: isFavorite ? "star.fill" : "star")
                }

                Button {
                    onToggleRead()
                } label: {
                    Label(isRead ? "标未读" : "标已读", systemImage: isRead ? "eye.slash" : "eye")
                }

                if let pdfURL = LinkRouter.url(for: .pdf, in: paper) {
                    Button("PDF") {
                        openURL(pdfURL)
                    }
                }

                NavigationLink("详情") {
                    PaperDetailView(
                        paper: paper,
                        isFavorite: isFavorite,
                        isRead: isRead,
                        onToggleFavorite: onToggleFavorite,
                        onToggleRead: onToggleRead
                    )
                }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var tags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(paper.categories, id: \.self) { category in
                    Text(category)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }
        }
    }
}
