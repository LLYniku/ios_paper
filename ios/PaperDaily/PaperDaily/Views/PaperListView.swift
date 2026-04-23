import SwiftUI

struct PaperListView: View {
    let papers: [PaperItem]
    let favoritePaperIDs: Set<String>
    let readPaperIDs: Set<String>
    let emptyTitle: String
    let emptyMessage: String
    let contextNote: ((PaperItem) -> String?)?
    let rating: ((PaperItem) -> Int)?
    let onSetRating: ((PaperItem, Int) -> Void)?
    let onToggleFavorite: (PaperItem) -> Void
    let onToggleRead: (PaperItem) -> Void
    let onOpenDetail: (PaperItem) -> Void

    init(
        papers: [PaperItem],
        favoritePaperIDs: Set<String>,
        readPaperIDs: Set<String>,
        emptyTitle: String,
        emptyMessage: String,
        contextNote: ((PaperItem) -> String?)? = nil,
        rating: ((PaperItem) -> Int)? = nil,
        onSetRating: ((PaperItem, Int) -> Void)? = nil,
        onToggleFavorite: @escaping (PaperItem) -> Void,
        onToggleRead: @escaping (PaperItem) -> Void,
        onOpenDetail: @escaping (PaperItem) -> Void
    ) {
        self.papers = papers
        self.favoritePaperIDs = favoritePaperIDs
        self.readPaperIDs = readPaperIDs
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
        if papers.isEmpty {
            EmptyStateView(title: emptyTitle, message: emptyMessage)
        } else {
            if DesktopLayout.isDesktop {
                LazyVGrid(columns: DesktopLayout.adaptiveColumns, alignment: .leading, spacing: DesktopLayout.cardSpacing) {
                    ForEach(papers) { paper in
                        row(for: paper)
                    }
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(papers) { paper in
                        row(for: paper)
                    }
                }
            }
        }
    }

    private func row(for paper: PaperItem) -> some View {
        PaperRowView(
            paper: paper,
            isFavorite: favoritePaperIDs.contains(paper.id),
            isRead: readPaperIDs.contains(paper.id),
            contextNote: contextNote?(paper),
            rating: rating?(paper),
            onSetRating: onSetRating.map { handler in { handler(paper, $0) } },
            onToggleFavorite: { onToggleFavorite(paper) },
            onToggleRead: { onToggleRead(paper) },
            onOpenDetail: { onOpenDetail(paper) }
        )
    }
}
