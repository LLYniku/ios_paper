import SwiftUI

struct NetworkItemListView: View {
    let items: [NetworkItem]
    let favoriteItemIDs: Set<String>
    let readItemIDs: Set<String>
    let emptyTitle: String
    let emptyMessage: String
    let contextNote: ((NetworkItem) -> String?)?
    let rating: ((NetworkItem) -> Int)?
    let onSetRating: ((NetworkItem, Int) -> Void)?
    let onToggleFavorite: (NetworkItem) -> Void
    let onToggleRead: (NetworkItem) -> Void
    let onOpenDetail: (NetworkItem) -> Void

    init(
        items: [NetworkItem],
        favoriteItemIDs: Set<String>,
        readItemIDs: Set<String>,
        emptyTitle: String,
        emptyMessage: String,
        contextNote: ((NetworkItem) -> String?)? = nil,
        rating: ((NetworkItem) -> Int)? = nil,
        onSetRating: ((NetworkItem, Int) -> Void)? = nil,
        onToggleFavorite: @escaping (NetworkItem) -> Void,
        onToggleRead: @escaping (NetworkItem) -> Void,
        onOpenDetail: @escaping (NetworkItem) -> Void
    ) {
        self.items = items
        self.favoriteItemIDs = favoriteItemIDs
        self.readItemIDs = readItemIDs
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.contextNote = contextNote
        self.rating = rating
        self.onSetRating = onSetRating
        self.onToggleFavorite = onToggleFavorite
        self.onToggleRead = onToggleRead
        self.onOpenDetail = onOpenDetail
    }

    var body: some View {
        if items.isEmpty {
            EmptyStateView(title: emptyTitle, message: emptyMessage)
        } else {
            if DesktopLayout.isDesktop {
                LazyVGrid(columns: DesktopLayout.adaptiveColumns, alignment: .leading, spacing: DesktopLayout.cardSpacing) {
                    ForEach(items) { item in
                        row(for: item)
                    }
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(items) { item in
                        row(for: item)
                    }
                }
            }
        }
    }

    private func row(for item: NetworkItem) -> some View {
        NetworkRowView(
            item: item,
            isFavorite: favoriteItemIDs.contains(item.id),
            isRead: readItemIDs.contains(item.id),
            contextNote: contextNote?(item),
            rating: rating?(item),
            onSetRating: onSetRating.map { handler in { handler(item, $0) } },
            onToggleFavorite: { onToggleFavorite(item) },
            onToggleRead: { onToggleRead(item) },
            onOpenDetail: { onOpenDetail(item) }
        )
    }
}
