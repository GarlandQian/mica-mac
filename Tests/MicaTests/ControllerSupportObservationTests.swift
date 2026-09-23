import Foundation
import MicaCore
import Observation
import Synchronization
import Testing
@testable import Mica

@MainActor
struct ControllerSupportObservationTests {
    @Test func ordinarySnapshotRefreshDoesNotInvalidateCapabilityConsumers() {
        let model = makeModel()
        model.unifiedSnapshot = .init(
            controllerType: .mihomoCompatible, capabilities: .mihomoCompatible,
            checkedAt: Date(timeIntervalSince1970: 1)
        )
        let invalidations = Mutex(0)
        withObservationTracking {
            _ = model.selectedUnifiedCapabilities
            _ = model.selectedUnifiedControllerType
        } onChange: {
            invalidations.withLock { $0 += 1 }
        }
        for revision in 2...40 {
            var snapshot = model.unifiedSnapshot
            snapshot.checkedAt = Date(timeIntervalSince1970: Double(revision))
            snapshot.connectionsCount = revision
            snapshot.rulesCount = revision * 10
            snapshot.traffic.upload = revision * 100
            snapshot.versionLabel = "received-\(revision)"
            model.unifiedSnapshot = snapshot
        }
        #expect(invalidations.withLock { $0 } == 0)
        #expect(model.unifiedSnapshot.connectionsCount == 40)
        #expect(model.unifiedSnapshot.traffic.upload == 4_000)
        #expect(model.selectedUnifiedCapabilities == .mihomoCompatible)
    }

    @Test func capabilityRevocationAndControllerTypeChangesAreImmediatelyVisible() {
        let model = makeModel()
        model.unifiedSnapshot = .init(
            controllerType: .mihomoCompatible, capabilities: .mihomoCompatible,
            checkedAt: Date(timeIntervalSince1970: 1)
        )
        let invalidations = Mutex(0)
        withObservationTracking {
            _ = model.selectedUnifiedCapabilities
        } onChange: {
            invalidations.withLock { $0 += 1 }
        }
        // Exercise nested mutation as well as replacing a whole snapshot.
        model.unifiedSnapshot.capabilities.logs = false
        #expect(!model.selectedUnifiedCapabilities.logs)
        #expect(invalidations.withLock { $0 } == 1)

        model.unifiedSnapshot.controllerType = .unknown
        #expect(model.selectedUnifiedControllerType == .unknown)
        #expect(!model.selectedUnifiedCapabilities.logs)
    }

    @Test func unloadedAndClearedSnapshotsKeepProfileFallbackWithoutStaleSupport() {
        let model = makeModel()
        let fallbackType = model.selectedUnifiedControllerType
        let fallbackCapabilities = model.selectedUnifiedCapabilities
        model.unifiedSnapshot = .init(controllerType: .unknown, capabilities: .none)
        #expect(model.selectedUnifiedControllerType == fallbackType)
        #expect(model.selectedUnifiedCapabilities == fallbackCapabilities)

        model.unifiedSnapshot.checkedAt = Date(timeIntervalSince1970: 1)
        #expect(model.selectedUnifiedControllerType == .unknown)
        #expect(model.selectedUnifiedCapabilities == .none)
        model.unifiedSnapshot = .empty
        #expect(model.selectedUnifiedControllerType == fallbackType)
        #expect(model.selectedUnifiedCapabilities == fallbackCapabilities)
        model.selectedRouterID = nil
        #expect(model.selectedUnifiedControllerType == .unknown)
        #expect(model.selectedUnifiedCapabilities == .none)
    }

    private func makeModel() -> AppModel {
        let profile = RouterProfile(displayName: "Offline", host: "controller.invalid", controllerKind: .mihomoCompatible)
        return AppModel(
            routers: [profile], selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(), secretStore: InMemorySecretStore()
        )
    }
}
