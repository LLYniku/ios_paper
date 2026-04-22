import SwiftUI

struct ClassicPaperListView: View {
    let papers: [ClassicPaper]
    let favoritePaperIDs: Set<String>
    let readPaperIDs: Set<String>
    let emptyTitle: String
    let emptyMessage: String
    let contextNote: ((ClassicPaper) -> String?)?
    let onToggleFavorite: (ClassicPaper) -> Void
    let onToggleRead: (ClassicPaper) -> Void

    var body: some View {
        if papers.isEmpty {
            EmptyStateView(title: emptyTitle, message: emptyMessage)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(papers) { paper in
                    ClassicPaperRowView(
                        paper: paper,
                        isFavorite: favoritePaperIDs.contains(paper.id),
                        isRead: readPaperIDs.contains(paper.id),
                        contextNote: contextNote?(paper),
                        onToggleFavorite: { onToggleFavorite(paper) },
                        onToggleRead: { onToggleRead(paper) }
                    )
                }
            }
        }
    }
}
