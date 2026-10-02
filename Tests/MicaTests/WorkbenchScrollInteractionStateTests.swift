import Foundation
import Testing
@testable import Mica

struct WorkbenchScrollInteractionStateTests {
    private let start = ContinuousClock.now

    private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start.advanced(by: .milliseconds(milliseconds))
    }

    @Test func explicitGestureIgnoresWheelIdleAndEndsOnlyWithItsEnd() {
        var state = WorkbenchScrollInteractionState()
        #expect(state.beginGesture() == .began)
        #expect(state.didScroll(at: at(0)) == nil)
        #expect(state.wheelIdleDeadline == nil)
        #expect(state.wheelIdleElapsed(at: at(10_000)) == nil)
        #expect(state.phase == .gesture)
        #expect(state.finish() == .ended)
        #expect(state.finish() == nil)
    }

    @Test func wheelBurstEndsOnlyAfterItsLatestTickIsIdle() {
        var state = WorkbenchScrollInteractionState()
        #expect(state.didScroll(at: at(0)) == .began)
        #expect(state.didScroll(at: at(100)) == nil)
        #expect(state.wheelIdleElapsed(at: at(149)) == nil)
        #expect(state.wheelIdleElapsed(at: at(249)) == nil)
        #expect(state.phase == .wheel)
        #expect(state.wheelIdleElapsed(at: at(250)) == .ended)
        #expect(state.phase == .idle)
        #expect(state.wheelIdleDeadline == nil)
        #expect(state.wheelIdleElapsed(at: at(500)) == nil)
    }

    @Test func gestureTakesOverAWheelBurstWithoutASecondBegin() {
        var state = WorkbenchScrollInteractionState()
        #expect(state.didScroll(at: at(0)) == .began)
        #expect(state.beginGesture() == nil)
        #expect(state.wheelIdleDeadline == nil)
        #expect(state.wheelIdleElapsed(at: at(1_000)) == nil)
        #expect(state.finish() == .ended)
        #expect(state.didScroll(at: at(1_100)) == .began)
    }
}
