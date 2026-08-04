import SwiftUI

struct MicaSetupDetailLayout<Content: View>: View {
    var breakpoint: CGFloat
    var setupWidth: CGFloat
    var spacing: CGFloat
    var content: Content

    init(
        breakpoint: CGFloat,
        setupWidth: CGFloat,
        spacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.breakpoint = breakpoint
        self.setupWidth = setupWidth
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        MicaSetupDetailAdaptiveLayout(
            breakpoint: breakpoint,
            setupWidth: setupWidth,
            spacing: spacing
        ) {
            content
        }
    }
}

private struct MicaSetupDetailAdaptiveLayout: Layout {
    var breakpoint: CGFloat
    var setupWidth: CGFloat
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count == 2 else {
            return .zero
        }

        let proposedWidth = proposal.width ?? breakpoint
        if proposedWidth >= breakpoint {
            let detailWidth = max(0, proposedWidth - setupWidth - spacing)
            let setupSize = subviews[0].sizeThatFits(
                ProposedViewSize(width: setupWidth, height: proposal.height)
            )
            let detailSize = subviews[1].sizeThatFits(
                ProposedViewSize(width: detailWidth, height: proposal.height)
            )

            return CGSize(
                width: proposedWidth,
                height: max(setupSize.height, detailSize.height)
            )
        }

        let setupSize = subviews[0].sizeThatFits(
            ProposedViewSize(width: proposedWidth, height: nil)
        )
        let detailSize = subviews[1].sizeThatFits(
            ProposedViewSize(width: proposedWidth, height: nil)
        )

        return CGSize(
            width: proposedWidth,
            height: setupSize.height + spacing + detailSize.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 2 else {
            return
        }

        if bounds.width >= breakpoint {
            let detailWidth = max(0, bounds.width - setupWidth - spacing)
            subviews[0].place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: setupWidth, height: bounds.height)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX + setupWidth + spacing, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: detailWidth, height: bounds.height)
            )
            return
        }

        let setupSize = subviews[0].sizeThatFits(
            ProposedViewSize(width: bounds.width, height: nil)
        )
        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: setupSize.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + setupSize.height + spacing),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
    }
}
