import SwiftUI

struct HoverFeedback: ViewModifier {
    let padding: CGFloat

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                isHovering ? Color.primary.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .onHover { isHovering = $0 }
    }
}

extension View {
    func hoverFeedback(padding: CGFloat = 4) -> some View {
        modifier(HoverFeedback(padding: padding))
    }
}
