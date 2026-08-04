import Dispatch
import MicaCore
import Testing
@testable import Mica

@Suite(.serialized)
struct PerformanceObservationTests {
    @Test func operationsCoverEveryStablePerformanceCategory() {
        let coveredCategories = Set(MicaPerformanceOperation.allCases.map(\.category))

        #expect(coveredCategories == Set(MicaPerformanceCategory.allCases))
        #expect(MicaPerformanceOperation.rawFrameIngestion.category == .ingestion)
        #expect(MicaPerformanceOperation.sessionPublication.category == .publication)
        #expect(MicaPerformanceOperation.connectionProjection.category == .projection)
        #expect(MicaPerformanceOperation.topologyLayout.category == .topology)
        #expect(MicaPerformanceOperation.scrollPhase.category == .interaction)
        #expect(MicaPerformanceOperation.dataTableEvaluation.category == .rendering)
        #expect(MicaPerformanceOperation.refreshFlight.category == .refresh)
        #expect(MicaPerformanceOperation.retryBackoff.category == .retry)
        #expect(MicaPerformanceOperation.transportClientCreation.category == .transport)
        #expect(MicaPerformanceOperation.persistenceRead.category == .persistence)
        #expect(MicaPerformanceOperation.workspaceEncoding.category == .persistence)
        #expect(MicaPerformanceOperation.localizationCacheMiss.category == .localization)
    }

    @Test func metadataAndObservationAPIsUseOnlyTypedPrivacySafeInputs() {
        let metadata = MicaPerformanceMetadata(
            count: 12,
            revision: 34,
            duration: .milliseconds(5),
            controllerKind: .surgeCompatible
        )
        let record: (MicaPerformanceOperation, MicaPerformanceMetadata) -> Void = { operation, metadata in
            MicaPerformanceObservation.record(operation, metadata: metadata)
        }

        #expect(metadata.count == 12)
        #expect(metadata.revision == 34)
        #expect(metadata.duration == .milliseconds(5))
        #expect(metadata.controllerKind == .surgeCompatible)
        #expect(!Mirror(reflecting: metadata).children.contains { $0.value is String })

        MicaPerformanceObservation.resetCounters()
        record(.sessionPublication, metadata)
        #expect(MicaPerformanceObservation.counterSnapshot()[.sessionPublication].eventCount == 1)
        MicaPerformanceObservation.resetCounters()
    }

    @Test func counterSnapshotsRemainStableAcrossReset() {
        let store = MicaPerformanceCounterStore()
        store.recordEvent(
            .logProjection,
            metadata: MicaPerformanceMetadata(
                count: 2,
                revision: 3,
                duration: .microseconds(250)
            )
        )
        store.recordEvent(
            .logProjection,
            metadata: MicaPerformanceMetadata(
                count: 5,
                revision: 8,
                duration: .microseconds(750)
            )
        )

        let beforeReset = store.snapshot()
        store.reset()
        let afterReset = store.snapshot()

        #expect(beforeReset[.logProjection].eventCount == 2)
        #expect(beforeReset[.logProjection].reportedCount == 7)
        #expect(beforeReset[.logProjection].maximumRevision == 8)
        #expect(beforeReset[.logProjection].totalDuration == .milliseconds(1))
        #expect(afterReset.isEmpty)
        #expect(beforeReset[.logProjection].eventCount == 2)
    }

    @Test func concurrentCounterUpdatesAreDeterministic() {
        let store = MicaPerformanceCounterStore()
        let iterations = 4_096

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            store.recordEvent(
                .rawFrameIngestion,
                metadata: MicaPerformanceMetadata(
                    count: 2,
                    revision: UInt64(index)
                )
            )
        }

        let counter = store.snapshot()[.rawFrameIngestion]
        #expect(counter.eventCount == UInt64(iterations))
        #expect(counter.completedObservationCount == UInt64(iterations))
        #expect(counter.reportedCount == UInt64(iterations * 2))
        #expect(counter.maximumRevision == UInt64(iterations - 1))
    }

    @Test func intervalCountersTrackStartsAndCompletedMetadataSeparately() {
        MicaPerformanceObservation.resetCounters()
        defer { MicaPerformanceObservation.resetCounters() }

        let interval = MicaPerformanceObservation.beginInterval(
            .topologyNormalization,
            metadata: MicaPerformanceMetadata(count: 1, revision: 10)
        )
        MicaPerformanceObservation.endInterval(
            interval,
            metadata: MicaPerformanceMetadata(
                count: 1,
                revision: 11,
                duration: .milliseconds(4),
                controllerKind: .mihomoCompatible
            )
        )

        let snapshot = MicaPerformanceObservation.counterSnapshot()
        let counter = snapshot[.topologyNormalization]
        #expect(counter.eventCount == 0)
        #expect(counter.intervalStartCount == 1)
        #expect(counter.intervalEndCount == 1)
        #expect(counter.completedObservationCount == 1)
        #expect(counter.reportedCount == 1)
        #expect(counter.maximumRevision == 11)
        #expect(counter.totalDuration == .milliseconds(4))
        #expect(snapshot.total(for: .topology) == counter)
    }
}
