import SwiftUI

/// The only custom Liquid Glass primitive for interactive selection controls.
/// Passive content, rows, logs, and inspectors deliberately do not use it.
struct MicaGlassSelectionSurface<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let isSelected: Bool
    let isInteractive: Bool
    let tint: Color
    private let content: Content

    init(
        isSelected: Bool,
        isInteractive: Bool = true,
        tint: Color = MicaStyle.accent,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.isInteractive = isInteractive
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        Group {
            if reduceTransparency {
                content
                    .background(isSelected ? tint.opacity(0.18) : MicaStyle.glassFallback, in: ConcentricRectangle())
                    .overlay {
                        ConcentricRectangle()
                            .stroke(isSelected ? tint.opacity(0.7) : MicaStyle.separator, lineWidth: 1)
                    }
            } else {
                content
                    .glassEffect(glass, in: ConcentricRectangle())
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isSelected)
    }

    private var glass: Glass {
        let base = Glass.regular.tint(isSelected ? tint.opacity(0.24) : tint.opacity(0.08))
        return isInteractive ? base.interactive() : base
    }
}

// MARK: - Unified content-layer card

/// The single content-layer card container shared by every workbench surface
/// (overview modules, policy rows, table page chrome, form-page groupings,
/// the status bar). It follows the system light/dark appearance — never pins
/// `colorScheme` — and never uses `.glassEffect`; Liquid Glass is reserved for
/// the floating functional layer (toolbar, sidebar chrome, selection blocks).
///
/// Visual: a `.regularMaterial` fill on a continuous rounded rectangle with a
/// faint semantic (or neutral separator) hairline border. No blur stacks, no
/// forced-dark, no drop shadow — it composites cheaply and reads consistently
/// in both appearances. Tokens come from `MicaStyle` so radius/padding/border
/// stay uniform across all callers.
struct MicaContentCard<Content: View>: View {
    var tint: Color?
    var cornerRadius: CGFloat
    var padding: CGFloat
    var spacing: CGFloat
    private let content: Content

    init(
        tint: Color? = nil,
        cornerRadius: CGFloat = MicaStyle.cardCornerRadius,
        padding: CGFloat = MicaStyle.cardPadding,
        spacing: CGFloat = MicaStyle.cardSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(shape.fill(.regularMaterial))
            .overlay(
                shape.strokeBorder(
                    tint?.opacity(MicaStyle.cardTintBorderOpacity) ?? MicaStyle.separator,
                    lineWidth: 1
                )
            )
    }
}
