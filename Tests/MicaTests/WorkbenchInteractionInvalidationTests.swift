import Foundation
import Observation
import Synchronization
import Testing
@testable import Mica

struct WorkbenchInteractionInvalidationTests {
    @MainActor
    @Test func topologyScrollKeepsExactRevealGeometryWithoutInvalidatingGraph() {
        let geometry = OverviewTopologyViewportGeometry()
        geometry.update(CGRect(x: 0, y: 0, width: 720, height: 400))
        let graphInvalidations = Mutex(0)
        withObservationTracking {
            _ = geometry.size.width
        } onChange: {
            graphInvalidations.withLock { $0 += 1 }
        }

        for frame in 1...600 {
            geometry.update(CGRect(
                x: CGFloat(frame) / 4,
                y: CGFloat(frame) * 2,
                width: 720,
                height: 400
            ))
        }

        #expect(graphInvalidations.withLock { $0 } == 0)
        #expect(geometry.visibleRect == CGRect(x: 150, y: 1_200, width: 720, height: 400))

        geometry.update(CGRect(x: 150, y: 1_200, width: 640, height: 360))
        #expect(graphInvalidations.withLock { $0 } == 1)
        #expect(geometry.size == CGSize(width: 640, height: 360))
        #expect(geometry.visibleRect.origin == CGPoint(x: 150, y: 1_200))
    }

    @MainActor
    @Test func lateHoverExitDoesNotDismissAnotherNodePreview() {
        let hover = ProxyNodeHoverState()
        hover.setHovered("first", isHovered: true)
        hover.setHovered("second", isHovered: true)
        let previewInvalidations = Mutex(0)
        withObservationTracking {
            _ = hover.memberID
        } onChange: {
            previewInvalidations.withLock { $0 += 1 }
        }
        hover.setHovered("first", isHovered: false)
        #expect(hover.memberID == "second")
        #expect(previewInvalidations.withLock { $0 } == 0)
        hover.setHovered("second", isHovered: false)
        #expect(hover.memberID == nil)
        #expect(previewInvalidations.withLock { $0 } == 1)
    }

    @MainActor
    @Test func hoverRetainsStationaryCandidateAcrossScrollAndResetsForNewSession() {
        let hover = ProxyNodeHoverState()
        hover.setHovered("stationary", isHovered: true)
        let scrolling = ProxyNodeHoverRequest(memberID: hover.memberID, isScrolling: true)
        #expect(scrolling.previewCandidateID == nil)
        let stopped = ProxyNodeHoverRequest(memberID: hover.memberID, isScrolling: false)
        #expect(stopped.previewCandidateID == "stationary")

        hover.reset()
        #expect(ProxyNodeHoverRequest(memberID: hover.memberID, isScrolling: false).previewCandidateID == nil)
    }
}
