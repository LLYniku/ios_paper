import SwiftUI
#if targetEnvironment(macCatalyst)
import AppKit
#endif

enum DesktopLayout {
    #if targetEnvironment(macCatalyst)
    static let isDesktop = true
    #else
    static let isDesktop = false
    #endif

    static let cardMinWidth: CGFloat = 320
    static let cardMaxWidth: CGFloat = 420
    static let cardSpacing: CGFloat = 18
    static let pagePadding: CGFloat = 28
    static let detailMaxWidth: CGFloat = 940
    static let settingsMaxWidth: CGFloat = 760
    static let minWindowWidth: CGFloat = 1_180
    static let minWindowHeight: CGFloat = 820

    static var adaptiveColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: cardMinWidth, maximum: cardMaxWidth),
                spacing: cardSpacing,
                alignment: .top
            )
        ]
    }
}

private struct DesktopPageContainerModifier: ViewModifier {
    func body(content: Content) -> some View {
        if DesktopLayout.isDesktop {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, DesktopLayout.pagePadding)
        } else {
            content
        }
    }
}

private struct DesktopReadableWidthModifier: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if DesktopLayout.isDesktop {
            content
                .frame(maxWidth: maxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
        } else {
            content
        }
    }
}

private struct DesktopHoverCardModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        if DesktopLayout.isDesktop {
            content
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isHovered ? Color.blue.opacity(0.08) : Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isHovered ? Color.blue.opacity(0.28) : Color.clear, lineWidth: 1.2)
                )
                .onHover { hovering in
                    isHovered = hovering
                    #if targetEnvironment(macCatalyst)
                    if hovering {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                    #endif
                }
                .onDisappear {
                    #if targetEnvironment(macCatalyst)
                    NSCursor.arrow.set()
                    #endif
                }
        } else {
            content
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

extension View {
    func desktopPageContainer(maxWidth: CGFloat? = nil) -> some View {
        let container = modifier(DesktopPageContainerModifier())
        if let maxWidth {
            return AnyView(container.desktopReadableWidth(maxWidth))
        }
        return AnyView(container)
    }

    func desktopReadableWidth(_ maxWidth: CGFloat) -> some View {
        modifier(DesktopReadableWidthModifier(maxWidth: maxWidth))
    }

    func desktopInteractiveCard() -> some View {
        modifier(DesktopHoverCardModifier())
    }
}
