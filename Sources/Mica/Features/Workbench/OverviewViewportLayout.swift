import SwiftUI

struct OverviewViewportLayout: Equatable {
    let metricColumns: Int
    let metricPlotHeight: CGFloat
    let topologyMinimumHeight: CGFloat

    init(width: CGFloat, height: CGFloat, metricCount: Int) {
        let width = width.isFinite ? max(width, 0) : 0
        let height = height.isFinite ? max(height, 0) : 0
        let count = min(max(metricCount, 1), OverviewMetricID.allCases.count)
        // Trends occupy one row. When three charts cannot fit, a shared plot
        // follows the selected readout rather than pushing a third chart below.
        metricColumns = width / CGFloat(count) >= 280 ? count : 1
        metricPlotHeight = min(max(height * 0.10, 56), 92)
        // This is the overview's maximum canvas budget; sparse maps use their
        // natural height. Short windows keep room for the trend below, while
        // dense maps scroll inside their bounded canvas.
        topologyMinimumHeight = min(max(height * 0.48, 208), 440)
    }
}

/// One persistent set of charts changes geometry without swapping view trees.
struct OverviewMetricLayout: Layout {
    let columns: Int

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = max(proposal.width ?? 960, 0)
        let heights = rowHeights(width: width, subviews: subviews)
        return CGSize(width: width, height: heights.reduce(0, +))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let count = max(columns, 1)
        let heights = rowHeights(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            let start = row * count
            let rowCount = min(count, subviews.count - start)
            let width = bounds.width / CGFloat(rowCount)
            for column in 0..<rowCount {
                subviews[start + column].place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * width, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: width, height: height)
                )
            }
            y += height
        }
    }

    private func rowHeights(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        let count = max(columns, 1)
        return stride(from: 0, to: subviews.count, by: count).map { start in
            let rowCount = min(count, subviews.count - start)
            let proposal = ProposedViewSize(
                width: width / CGFloat(rowCount),
                height: nil
            )
            return (start..<(start + rowCount)).map {
                subviews[$0].sizeThatFits(proposal).height
            }.max() ?? 0
        }
    }
}
