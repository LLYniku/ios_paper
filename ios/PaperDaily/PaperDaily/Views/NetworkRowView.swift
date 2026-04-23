import SwiftUI

struct NetworkRowView: View {
    let item: NetworkItem
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
                    Text(item.title)
                        .font(.headline)
                    Text(item.displaySummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if let score = item.relevanceScore {
                    Text(String(format: "%.2f", score))
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
            }

            Text(item.creator)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let contextNote, !contextNote.isEmpty {
                Text(contextNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(item.publicationLine)
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
                Text(item.platformLabel)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: Capsule())

                ForEach(item.tags.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12), in: Capsule())
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

                Button("链接") {
                    openURL(item.url)
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
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenDetail()
        }
    }
}
