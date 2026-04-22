import SwiftUI

struct ClassicPaperRowView: View {
    let paper: ClassicPaper
    let isFavorite: Bool
    let isRead: Bool
    let contextNote: String?
    let onToggleFavorite: () -> Void
    let onToggleRead: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var isShowingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(paper.title)
                        .font(.headline)
                    Text(paper.cardSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Label(isRead ? "已读" : "未读", systemImage: isRead ? "eye.fill" : "eye.slash")
                    .font(.caption)
                    .foregroundStyle(isRead ? .secondary : .primary)
            }

            Text(paper.publicationLine)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let contextNote, !contextNote.isEmpty {
                Text(contextNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(paper.category)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: Capsule())

                if let year = paper.year {
                    Text(String(year))
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
            }

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

                Button("论文") {
                    openURL(paper.paperURL)
                }

                NavigationLink("详情") {
                    ClassicDetailView(
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
        .contentShape(Rectangle())
        .onTapGesture {
            isShowingDetail = true
        }
        .background {
            NavigationLink(isActive: $isShowingDetail) {
                ClassicDetailView(
                    paper: paper,
                    isFavorite: isFavorite,
                    isRead: isRead,
                    onToggleFavorite: onToggleFavorite,
                    onToggleRead: onToggleRead
                )
            } label: {
                EmptyView()
            }
            .hidden()
        }
    }
}
