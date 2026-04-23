import SwiftUI

struct ClassicPaperListView: View {
    let papers: [ClassicPaper]
    let favoritePaperIDs: Set<String>
    let readPaperIDs: Set<String>
    let emptyTitle: String
    let emptyMessage: String
    let contextNote: ((ClassicPaper) -> String?)?
    let rating: ((ClassicPaper) -> Int)?
    let onSetRating: ((ClassicPaper, Int) -> Void)?
    let onToggleFavorite: (ClassicPaper) -> Void
    let onToggleRead: (ClassicPaper) -> Void
    let onOpenDetail: (ClassicPaper) -> Void

    init(
        papers: [ClassicPaper],
        favoritePaperIDs: Set<String>,
        readPaperIDs: Set<String>,
        emptyTitle: String,
        emptyMessage: String,
        contextNote: ((ClassicPaper) -> String?)? = nil,
        rating: ((ClassicPaper) -> Int)? = nil,
        onSetRating: ((ClassicPaper, Int) -> Void)? = nil,
        onToggleFavorite: @escaping (ClassicPaper) -> Void,
        onToggleRead: @escaping (ClassicPaper) -> Void,
        onOpenDetail: @escaping (ClassicPaper) -> Void
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

    private func row(for paper: ClassicPaper) -> some View {
        ClassicPaperRowView(
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
