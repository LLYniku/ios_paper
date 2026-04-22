import SwiftUI

struct ClassicPaperRowView: View {
    let paper: ClassicPaper

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(paper.title)
                    .font(.headline)
                Text(paper.publicationLine)
                    .font(.subheadline)
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
                Button("论文") {
                    openURL(paper.paperURL)
                }

                if let codeURL = paper.codeURL {
                    Button("代码") {
                        openURL(codeURL)
                    }
                }

                if let projectURL = paper.projectURL {
                    Button("项目") {
                        openURL(projectURL)
                    }
                }

                NavigationLink("详情") {
                    ClassicDetailView(paper: paper)
                }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
