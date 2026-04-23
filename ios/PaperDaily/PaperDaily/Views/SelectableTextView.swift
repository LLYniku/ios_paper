import SwiftUI

#if os(iOS)
import UIKit

struct SelectableTextView: UIViewRepresentable {
    let text: String
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var textColor: UIColor = .label

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.font = font
        uiView.textColor = textColor
        uiView.text = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fittingSize.height)
    }
}

#elseif os(macOS)
import AppKit

struct SelectableTextView: NSViewRepresentable {
    let text: String
    var font: NSFont = .preferredFont(forTextStyle: .body)
    var textColor: NSColor = .labelColor

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = CGSize(width: 0, height: .greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.font = font
        textView.textColor = textColor
        textView.string = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard
            let textView = nsView.documentView as? NSTextView,
            let textContainer = textView.textContainer,
            let layoutManager = textView.layoutManager
        else {
            return nil
        }

        let width = proposal.width ?? nsView.bounds.width
        guard width > 0 else { return nil }

        textContainer.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let rect = layoutManager.usedRect(for: textContainer)
        return CGSize(width: width, height: ceil(rect.height))
    }
}
#endif
