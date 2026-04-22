import Foundation

enum PaperLinkDestination {
    case abstract
    case pdf
    case code
    case project
}

enum LinkRouter {
    static func url(for destination: PaperLinkDestination, in paper: PaperItem) -> URL? {
        switch destination {
        case .abstract:
            return sanitizedURL(paper.absURL)
        case .pdf:
            return sanitizedURL(paper.pdfURL)
        case .code:
            return sanitizedURL(paper.codeURL)
        case .project:
            return sanitizedURL(paper.projectURL)
        }
    }

    static func sanitizedURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }
}
