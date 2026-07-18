import SwiftUI

/// Repeated policy content uses an opaque semantic fill. Liquid Glass and
/// material remain reserved for low-count navigation and structural chrome.
struct PolicyGroupCardSurface<Content: View>: View {
    let tint: Color?
    let cornerRadius: CGFloat
    private let content: Content

    init(
        tint: Color? = nil,
        cornerRadius: CGFloat = MicaStyle.cardCornerRadius,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(shape.fill(MicaStyle.contentFill))
            .overlay(
                shape.strokeBorder(
                    tint?.opacity(MicaStyle.cardTintBorderOpacity) ?? MicaStyle.separator,
                    lineWidth: 1
                )
            )
    }
}
