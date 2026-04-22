import SwiftUI

struct PaperListView: View {
    let papers: [PaperItem]
    let favoritePaperIDs: Set<String>
    let readPaperIDs: Set<String>
    let emptyTitle: String
    let emptyMessage: String
    let contextNote: ((PaperItem) -> String?)?
    let onToggleFavorite: (PaperItem) -> Void
    let onToggleRead: (PaperItem) -> Void
    let onOpenDetail: (PaperItem) -> Void

    var body: some View {
        if papers.isEmpty {
            EmptyStateView(title: emptyTitle, message: emptyMessage)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(papers) { paper in
                    PaperRowView(
                        paper: paper,
                        isFavorite: favoritePaperIDs.contains(paper.id),
                        isRead: readPaperIDs.contains(paper.id),
                        contextNote: contextNote?(paper),
                        onToggleFavorite: { onToggleFavorite(paper) },
                        onToggleRead: { onToggleRead(paper) },
                        onOpenDetail: { onOpenDetail(paper) }
                    )
                }
            }
        }
    }
}
