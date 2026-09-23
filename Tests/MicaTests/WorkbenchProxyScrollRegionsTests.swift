import Foundation
import Observation
import Synchronization
import Testing
@testable import Mica

struct WorkbenchProxyScrollRegionsTests {
    @MainActor
    @Test func overlappingScrollRegionsFlushOnlyAfterTheLastRegionEnds() {
        let tracker = ProxyScrollInteractionTracker()
        let coordinator = ProxyCatalogPresentationCoordinator()
        let first = update(revision: 1)
        let latest = update(revision: 2)

        tracker.update(.interacting, in: .directory, coordinator: coordinator)
        #expect(coordinator.deferIfInteracting(first, at: Date()))
        tracker.update(.decelerating, in: .nodes, coordinator: coordinator)
        tracker.update(.idle, in: .directory, coordinator: coordinator)
        #expect(tracker.isScrolling)
        #expect(coordinator.commitRevision == 0)
        #expect(coordinator.deferIfInteracting(latest, at: Date()))

        tracker.update(.idle, in: .nodes, coordinator: coordinator)
        #expect(!tracker.isScrolling)
        #expect(coordinator.commitRevision == 1)
        #expect(coordinator.takeReadyUpdate() == latest)
    }

    @MainActor
    @Test func unrelatedDisappearDoesNotEndTheActiveDirectoryScroll() {
        let tracker = ProxyScrollInteractionTracker()
        let coordinator = ProxyCatalogPresentationCoordinator()
        let latest = update(revision: 3)

        tracker.update(.tracking, in: .directory, coordinator: coordinator)
        #expect(coordinator.deferIfInteracting(latest, at: Date()))
        tracker.end(in: .nodes, coordinator: coordinator)
        #expect(tracker.isScrolling)
        #expect(coordinator.commitRevision == 0)

        tracker.end(in: .directory, coordinator: coordinator)
        #expect(!tracker.isScrolling)
        #expect(coordinator.takeReadyUpdate() == latest)
        tracker.end(in: .directory, coordinator: coordinator)
        #expect(coordinator.commitRevision == 1)
    }

    @MainActor
    @Test func regionTransitionsDoNotInvalidateHoverWhileAggregateStateStaysActive() {
        let tracker = ProxyScrollInteractionTracker()
        let coordinator = ProxyCatalogPresentationCoordinator()
        tracker.update(.tracking, in: .directory, coordinator: coordinator)
        let invalidations = Mutex(0)
        withObservationTracking {
            _ = tracker.isScrolling
        } onChange: {
            invalidations.withLock { $0 += 1 }
        }

        tracker.update(.interacting, in: .directory, coordinator: coordinator)
        tracker.update(.tracking, in: .nodes, coordinator: coordinator)
        tracker.end(in: .directory, coordinator: coordinator)
        #expect(invalidations.withLock { $0 } == 0)
        tracker.end(in: .nodes, coordinator: coordinator)
        #expect(invalidations.withLock { $0 } == 1)
    }

    @MainActor
    @Test func resetDiscardsAllRegionsAndPendingDataWithoutPublishingOldSession() {
        let tracker = ProxyScrollInteractionTracker()
        let coordinator = ProxyCatalogPresentationCoordinator()
        tracker.update(.tracking, in: .directory, coordinator: coordinator)
        tracker.update(.interacting, in: .nodes, coordinator: coordinator)
        #expect(coordinator.deferIfInteracting(update(revision: 1), at: Date()))

        tracker.reset(coordinator: coordinator)
        #expect(!tracker.isScrolling)
        #expect(coordinator.commitRevision == 0)
        #expect(coordinator.takeReadyUpdate() == nil)
        // Late disappearance from an old view cannot release discarded data.
        tracker.end(in: .nodes, coordinator: coordinator)
        tracker.end(in: .directory, coordinator: coordinator)
        #expect(coordinator.commitRevision == 0)
        #expect(!coordinator.deferIfInteracting(update(revision: 2), at: Date()))

        // A surviving directory can report its next phase without needing an
        // intervening idle callback from the previous session.
        tracker.update(.decelerating, in: .directory, coordinator: coordinator)
        let latest = update(revision: 3)
        #expect(coordinator.deferIfInteracting(latest, at: Date()))
        tracker.end(in: .directory, coordinator: coordinator)
        #expect(coordinator.commitRevision == 1)
        #expect(coordinator.takeReadyUpdate() == latest)
    }

    @MainActor
    @Test func resetDiscardsAnAlreadyReadyUpdateBeforePageReentry() {
        let tracker = ProxyScrollInteractionTracker()
        let coordinator = ProxyCatalogPresentationCoordinator()
        tracker.update(.tracking, in: .directory, coordinator: coordinator)
        #expect(coordinator.deferIfInteracting(update(revision: 1), at: Date()))
        tracker.end(in: .directory, coordinator: coordinator)
        #expect(coordinator.commitRevision == 1)

        tracker.reset(coordinator: coordinator)
        #expect(coordinator.takeReadyUpdate() == nil)
        tracker.update(.tracking, in: .nodes, coordinator: coordinator)
        let latest = update(revision: 2)
        #expect(coordinator.deferIfInteracting(latest, at: Date()))
        tracker.end(in: .nodes, coordinator: coordinator)
        #expect(coordinator.commitRevision == 2)
        #expect(coordinator.takeReadyUpdate() == latest)
    }

    private func update(revision: UInt64) -> ProxyCatalogUpdate {
        ProxyCatalogUpdate(
            revision: ProxyCatalogRevision(controllerID: nil, generation: nil, value: revision),
            catalog: .empty
        )
    }
}
