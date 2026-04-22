import SwiftUI

struct ErrorStateView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
        .background(Color.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
