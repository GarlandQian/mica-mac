import Foundation
import MicaCore
import Observation
import Synchronization
import Testing
@testable import Mica

@MainActor
struct OverviewInteractionContinuityTests {
    @Test func pinnedSampleSurvivesResamplingWithinTheRawWindow() throws {
        let generation = UUID()
        let cache = OverviewTimelineProjectionCache()
        let interaction = OverviewTimelineInteractionState()
        let first = resolve(cache, generation: generation, samples: traffic(0..<121))
        let pin = date(30)
        #expect(first.dates.contains(pin))
        interaction.retainPinnedDate(in: first.selectionWindow)
        interaction.setPinnedDate(pin)

        let updated = resolve(cache, generation: generation, samples: traffic(0..<122), pin: pin)
        interaction.retainPinnedDate(in: updated.selectionWindow)

        #expect(interaction.pinnedDate == pin)
        #expect(updated.trafficSamples.first?.id == 0)
        #expect(updated.trafficSamples.last?.id == 121)
        #expect(updated.trafficSamples.count == 120)
        #expect(updated.memorySamples.count == 120)
        #expect(updated.connectionSamples.count == 120)
        #expect(updated.trafficSamples.contains { $0.id == 30 })
        #expect(updated.memorySamples.contains { $0.id == 30 })
        #expect(updated.connectionSamples.contains { $0.id == 30 })
        #expect(updated.trafficSamples.map(\.receivedAt) == updated.trafficSamples.map(\.receivedAt).sorted())
    }

    @Test func pinnedSampleExpiresOnlyWhenRawHistoryOrItsSessionExpires() {
        let generation = UUID()
        let cache = OverviewTimelineProjectionCache()
        let interaction = OverviewTimelineInteractionState()
        let first = resolve(cache, generation: generation, samples: traffic(0..<300))
        interaction.retainPinnedDate(in: first.selectionWindow)
        interaction.setPinnedDate(date(30))

        let rolling = resolve(cache, generation: generation, samples: traffic(1..<301), pin: date(30))
        interaction.retainPinnedDate(in: rolling.selectionWindow)
        #expect(interaction.pinnedDate == date(30))
        #expect(rolling.trafficSamples.contains { $0.id == 30 })

        let expired = resolve(cache, generation: generation, samples: traffic(31..<331), pin: date(30))
        interaction.retainPinnedDate(in: expired.selectionWindow)
        #expect(interaction.pinnedDate == nil)

        interaction.setPinnedDate(date(50))
        let newSession = resolve(cache, generation: UUID(), samples: traffic(31..<331), pin: date(50))
        interaction.retainPinnedDate(in: newSession.selectionWindow)
        #expect(interaction.snapshot == .empty)
    }

    @Test func shorterWindowExpiresPinEvenWhenRawBufferStillContainsIt() {
        let generation = UUID()
        let cache = OverviewTimelineProjectionCache()
        let interaction = OverviewTimelineInteractionState()
        let initial = cache.resolve(
            generation: generation, window: .fiveMinutes,
            traffic: traffic(0..<180), memory: [], connections: []
        )
        interaction.retainPinnedDate(in: initial.selectionWindow)
        interaction.setPinnedDate(date(30))
        let shorter = cache.resolve(
            generation: generation, window: .oneMinute,
            traffic: traffic(0..<180), memory: [], connections: [], pinnedDate: date(30)
        )
        interaction.retainPinnedDate(in: shorter.selectionWindow)
        #expect(interaction.pinnedDate == nil)
        #expect(shorter.trafficSamples.first?.id == 119)
    }

    @Test(arguments: [0, 1, 2])
    func pausedRuntimeAvoidsTheSubscriptionsCreatedByEagerSourceArguments(domain: Int) {
        let model = makeModel()
        appendSamples(to: model, at: 100)
        let runtime = OverviewTelemetryRuntime(timelineWindow: .fiveMinutes)
        let initial = runtime.resolveProjection(observing: model)
        runtime.togglePause()
        let eagerInvalidations = Mutex(0)
        let frozenInvalidations = Mutex(0)

        // Reproduce the old call boundary: a cache hit cannot undo observable
        // reads already evaluated as arguments by the calling view.
        withObservationTracking {
            _ = runtime.projectionCache.resolve(
                generation: model.controllerSessionPresentation.generation,
                window: runtime.timelineWindow,
                traffic: model.trafficTimeline.samples,
                memory: model.memoryTimeline.samples,
                connections: model.connectionCountTimeline.samples,
                isPaused: true
            )
        } onChange: { eagerInvalidations.withLock { $0 += 1 } }
        withObservationTracking {
            #expect(runtime.resolveProjection(observing: model) == initial)
        } onChange: { frozenInvalidations.withLock { $0 += 1 } }

        appendSamples(to: model, at: 101, domain: domain)
        #expect(eagerInvalidations.withLock { $0 } == 1)
        #expect(frozenInvalidations.withLock { $0 } == 0)
        #expect(runtime.resolveProjection(observing: model) == initial)

        runtime.togglePause()
        let resumed = runtime.resolveProjection(observing: model)
        #expect(resumed.dates.last == date(101))
        let resumedInvalidations = Mutex(0)
        withObservationTracking {
            _ = runtime.resolveProjection(observing: model)
        } onChange: { resumedInvalidations.withLock { $0 += 1 } }
        appendSamples(to: model, at: 102, domain: domain)
        #expect(resumedInvalidations.withLock { $0 } == 1)
    }

    @Test func pausedRuntimeDoesNotReadSourcesForAnEmptySnapshotAndRejectsOldSessions() {
        let model = makeModel()
        let runtime = OverviewTelemetryRuntime(timelineWindow: .fiveMinutes)
        let empty = runtime.resolveProjection(observing: model)
        runtime.togglePause()
        let sourceInvalidations = Mutex(0)
        withObservationTracking {
            _ = runtime.resolveProjection(observing: model)
        } onChange: { sourceInvalidations.withLock { $0 += 1 } }
        appendSamples(to: model, at: 100)
        #expect(sourceInvalidations.withLock { $0 } == 0)
        #expect(runtime.resolveProjection(observing: model) == empty)

        let sessionInvalidations = Mutex(0)
        withObservationTracking {
            _ = runtime.resolveProjection(observing: model)
        } onChange: { sessionInvalidations.withLock { $0 += 1 } }
        model.controllerSessionPresentation.generation = UUID()
        model.trafficTimeline.reset()
        model.memoryTimeline.reset()
        model.connectionCountTimeline.reset()
        appendSamples(to: model, at: 200)
        #expect(sessionInvalidations.withLock { $0 } == 1)
        let newSession = runtime.resolveProjection(observing: model)
        #expect(newSession.selectionWindow?.generation == model.controllerSessionPresentation.generation)
        #expect(newSession.dates == [date(200)])
    }

    @Test func hoverDoesNotInvalidateTimelineProjectionInputs() {
        let model = makeModel()
        appendSamples(to: model, at: 100)
        let runtime = OverviewTelemetryRuntime(timelineWindow: .fiveMinutes)
        let invalidations = Mutex(0)
        withObservationTracking {
            _ = runtime.resolveProjection(observing: model)
        } onChange: { invalidations.withLock { $0 += 1 } }
        runtime.interaction.setHoveredDate(date(100))
        #expect(invalidations.withLock { $0 } == 0)
        runtime.interaction.setPinnedDate(date(100))
        #expect(invalidations.withLock { $0 } == 1)
    }

    @Test(arguments: [false, true])
    func frozenTopologyKeepsItsSnapshotAndControlsAcrossZeroConnections(focused: Bool) async throws {
        let generation = UUID()
        let runtime = OverviewTopologyRuntime()
        let connections = [ConnectionSnapshot(
            id: "captured", chains: ["Exit", "Policy"],
            metadata: ConnectionMetadataSnapshot(sourceIP: "Source")
        )]
        let presentation = try await runtime.presentationCache.resolve(
            request: .init(generation: generation, revision: 1, availableWidth: 560, displayMode: .overview),
            connections: connections
        )
        runtime.presentation = presentation
        if focused {
            let node = try #require(presentation.diagram.nodes.first { $0.columnID == .policyHop(0) })
            runtime.focusPaths(for: .node(node.id), presentation: presentation, language: .english)
        } else {
            runtime.togglePause()
        }
        for (count, revision) in [(1, UInt64(1)), (0, 2), (3, 3)] {
            let state = runtime.presentationState(
                generation: generation, liveConnectionCount: count, liveRevision: revision
            )
            #expect(!state.showsEmptyState)
            #expect(state.showsControls)
            #expect(state.revision == 1)
        }
        let resized = try await runtime.presentationCache.resolve(
            request: .init(generation: generation, revision: 1, availableWidth: 600, displayMode: .overview),
            connections: []
        )
        #expect(resized.topology.paths == presentation.topology.paths)
        #expect(runtime.presentationState(generation: UUID(), liveConnectionCount: 0, liveRevision: 2).showsEmptyState)
        #expect(!runtime.presentationState(generation: UUID(), liveConnectionCount: 0, liveRevision: 2).showsControls)

        if focused { runtime.returnToOverview() } else { runtime.togglePause() }
        let empty = runtime.presentationState(generation: generation, liveConnectionCount: 0, liveRevision: 2)
        #expect(empty.showsEmptyState)
        #expect(!empty.showsControls)
        let live = runtime.presentationState(generation: generation, liveConnectionCount: 3, liveRevision: 3)
        #expect(live.revision == 3)
        #expect(live.showsControls)
    }

    @Test func populatedTopologyHeaderDoesNotObservePresentationOrHover() async throws {
        let generation = UUID()
        let runtime = OverviewTopologyRuntime()
        let presentation = try await runtime.presentationCache.resolve(
            request: .init(generation: generation, revision: 1, availableWidth: 560),
            connections: [ConnectionSnapshot(
                id: "captured", chains: ["Exit", "Policy"],
                metadata: ConnectionMetadataSnapshot(sourceIP: "Source")
            )]
        )
        runtime.interaction.configure(
            structure: presentation.request.diagramStructure, index: presentation.diagramIndex
        )
        let invalidations = Mutex(0)
        withObservationTracking {
            #expect(OverviewTopologyHeaderAvailability.showsControls(
                generation: generation, liveConnectionCount: 1, runtime: runtime
            ))
        } onChange: { invalidations.withLock { $0 += 1 } }

        runtime.presentation = presentation
        let node = try #require(presentation.diagram.nodes.first)
        runtime.interaction.setHoveredSelection(.node(node.id))
        runtime.togglePause()
        #expect(invalidations.withLock { $0 } == 0)

        // Empty input still observes the captured snapshot and its pause gate,
        // so the recovery entry disappears immediately when it is resumed.
        let emptyInvalidations = Mutex(0)
        runtime.interaction.setHoveredSelection(nil)
        withObservationTracking {
            #expect(OverviewTopologyHeaderAvailability.showsControls(
                generation: generation, liveConnectionCount: 0, runtime: runtime
            ))
        } onChange: { emptyInvalidations.withLock { $0 += 1 } }
        runtime.togglePause()
        #expect(emptyInvalidations.withLock { $0 } == 1)
        #expect(!OverviewTopologyHeaderAvailability.showsControls(
            generation: generation, liveConnectionCount: 0, runtime: runtime
        ))
    }

    @Test func unfrozenTopologyStateDoesNotObserveCapturedPresentation() async throws {
        let generation = UUID()
        let runtime = OverviewTopologyRuntime()
        let invalidations = Mutex(0)
        withObservationTracking {
            let state = runtime.presentationState(
                generation: generation, liveConnectionCount: 1, liveRevision: 7
            )
            #expect(state.revision == 7)
        } onChange: { invalidations.withLock { $0 += 1 } }
        runtime.presentation = try await runtime.presentationCache.resolve(
            request: .init(generation: generation, revision: 7, availableWidth: 560),
            connections: []
        )
        #expect(invalidations.withLock { $0 } == 0)
    }

    private func date(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private func traffic(_ range: Range<Int>) -> [TrafficTimeline.Sample] {
        range.map { .init(id: $0, receivedAt: date($0), upload: $0, download: $0 * 2) }
    }

    private func resolve(
        _ cache: OverviewTimelineProjectionCache, generation: UUID,
        samples: [TrafficTimeline.Sample], pin: Date? = nil
    ) -> OverviewTimelineProjectionSnapshot {
        cache.resolve(
            generation: generation, window: .fiveMinutes, traffic: samples,
            memory: samples.map { .init(id: $0.id, receivedAt: $0.receivedAt, inUseBytes: $0.download, source: .memoryEndpoint) },
            connections: samples.map { .init(id: $0.id, receivedAt: $0.receivedAt, activeCount: $0.id) },
            pinnedDate: pin
        )
    }

    private func makeModel() -> AppModel {
        AppModel(profileStore: InMemoryRouterProfileStore(), secretStore: InMemorySecretStore())
    }

    private func appendSamples(to model: AppModel, at seconds: Int, domain: Int? = nil) {
        if domain == nil || domain == 0 {
            model.trafficTimeline.append(upload: seconds, download: seconds * 2, receivedAt: date(seconds))
        }
        if domain == nil || domain == 1 {
            model.memoryTimeline.append(inUseBytes: seconds, receivedAt: date(seconds))
        }
        if domain == nil || domain == 2 {
            model.connectionCountTimeline.append(activeCount: seconds, receivedAt: date(seconds))
        }
    }
}
