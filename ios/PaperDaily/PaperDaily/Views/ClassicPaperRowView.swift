import SwiftUI

struct ClassicPaperRowView: View {
    let paper: ClassicPaper
    let isFavorite: Bool
    let isRead: Bool
    let contextNote: String?
    let rating: Int?
    let onSetRating: ((Int) -> Void)?
    let onToggleFavorite: () -> Void
    let onToggleRead: () -> Void
    let onOpenDetail: () -> Void

    @Environment(\.openURL) private var openURL

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

            if let rating, let onSetRating {
                FavoriteRatingControl(
                    rating: rating,
                    onSetRating: onSetRating
                )
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

                Button("详情") {
                    onOpenDetail()
                }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .desktopInteractiveCard()
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenDetail()
        }
    }

}
