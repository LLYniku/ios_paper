import SwiftUI

struct NetworkItemListView: View {
    let items: [NetworkItem]
    let favoriteItemIDs: Set<String>
    let readItemIDs: Set<String>
    let emptyTitle: String
    let emptyMessage: String
    let contextNote: ((NetworkItem) -> String?)?
    let onToggleFavorite: (NetworkItem) -> Void
    let onToggleRead: (NetworkItem) -> Void
    let onOpenDetail: (NetworkItem) -> Void

    var body: some View {
        if items.isEmpty {
            EmptyStateView(title: emptyTitle, message: emptyMessage)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(items) { item in
                    NetworkRowView(
                        item: item,
                        isFavorite: favoriteItemIDs.contains(item.id),
                        isRead: readItemIDs.contains(item.id),
                        contextNote: contextNote?(item),
                        onToggleFavorite: { onToggleFavorite(item) },
                        onToggleRead: { onToggleRead(item) },
                        onOpenDetail: { onOpenDetail(item) }
                    )
                }
            }
        }
    }
}
