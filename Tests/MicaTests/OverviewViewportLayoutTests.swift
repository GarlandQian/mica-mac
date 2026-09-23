import Foundation
import Testing
@testable import Mica

struct OverviewViewportLayoutTests {
    @Test(arguments: [CGFloat(440), 820, 1_100, 2_400])
    func topologyRetainsPriorityWithoutInflatingTrendsOnShortWindows(width: CGFloat) {
        let short = OverviewViewportLayout(width: width, height: 460, metricCount: 3)
        let tall = OverviewViewportLayout(width: width, height: 1_100, metricCount: 3)
        #expect(short.metricPlotHeight <= tall.metricPlotHeight)
        #expect(short.topologyMinimumHeight < tall.topologyMinimumHeight)
        #expect(short.metricPlotHeight <= 64)
        #expect(short.topologyMinimumHeight <= 240)
        #expect(tall.metricPlotHeight <= 92)
        #expect(tall.topologyMinimumHeight <= 440)
        #expect(short.topologyMinimumHeight > short.metricPlotHeight * 3)
        // The map and plot leave room for their headings, readouts and page
        // padding even before a sparse map releases unused canvas space.
        #expect(460 - short.topologyMinimumHeight - short.metricPlotHeight >= 180)
    }

    @Test(arguments: [0, 1, 2, 3])
    func columnsRemainBoundedByVisibleMetricCount(metricCount: Int) {
        for width in [CGFloat(440), 820, 1_100] {
            let layout = OverviewViewportLayout(width: width, height: 800, metricCount: metricCount)
            #expect(layout.metricColumns >= 1)
            #expect(layout.metricColumns <= max(metricCount, 1))
            #expect(width / CGFloat(layout.metricColumns) >= 280)
        }
    }

    @Test func mediumWindowsNeverWrapAThirdChartIntoASecondRow() {
        for width in [CGFloat(440), 640, 760, 820] {
            let layout = OverviewViewportLayout(width: width, height: 700, metricCount: 3)
            #expect(layout.metricColumns == 1)
        }
        #expect(OverviewViewportLayout(width: 1_100, height: 700, metricCount: 3).metricColumns == 3)
        #expect(OverviewViewportLayout(width: 820, height: 700, metricCount: 2).metricColumns == 2)
    }

    @Test func invalidGeometryCannotProduceInvalidCanvasDimensions() {
        for value in [CGFloat.zero, -10, .nan, .infinity] {
            let layout = OverviewViewportLayout(width: value, height: value, metricCount: 0)
            #expect(layout.metricColumns == 1)
            #expect(layout.metricPlotHeight.isFinite && layout.metricPlotHeight > 0)
            #expect(layout.topologyMinimumHeight.isFinite && layout.topologyMinimumHeight > 0)
        }
    }

    @Test func compactOverviewSizingDoesNotChangeCompleteExplorationViewportBounds() {
        #expect(OverviewTopologyViewportSizing.height(
            displayMode: .complete, requestedHeight: 208, contentHeight: 10_000
        ) == 280)
        #expect(OverviewTopologyViewportSizing.height(
            displayMode: .complete, requestedHeight: 800, contentHeight: 180
        ) == 500)
        for value in [CGFloat.zero, -10, .nan, .infinity] {
            let height = OverviewTopologyViewportSizing.height(
                displayMode: .overview, requestedHeight: value, contentHeight: value
            )
            #expect(height.isFinite && height > 0)
        }
    }
}
