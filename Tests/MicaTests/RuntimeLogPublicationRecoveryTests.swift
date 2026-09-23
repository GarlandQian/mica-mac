import Foundation
import MicaCore
import Testing
@testable import Mica

/// Holds a publication after the actor has drained its pending delta, before
/// its MainActor callback can decide whether the logs are still visible.
private actor RuntimeLogDeliveryGate {
    private var heldPublication: LiveSessionRuntimePublication?
    private var heldWaiter: CheckedContinuation<LiveSessionRuntimePublication, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func hold(_ publication: LiveSessionRuntimePublication) async {
        heldPublication = publication
        heldWaiter?.resume(returning: publication)
        heldWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilHeld() async -> LiveSessionRuntimePublication {
        if let heldPublication { return heldPublication }
        return await withCheckedContinuation { heldWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@MainActor
struct RuntimeLogPublicationRecoveryTests {
    @Test func hiddenDeliveryThenNewDeltaRestoresEveryRetainedEntry() async throws {
        let (model, runtime, window) = try makeModel()
        defer { model.leaveLiveSession() }
        try await publish("A", model: model, runtime: runtime)

        let gate = RuntimeLogDeliveryGate()
        let delivery = Task {
            try await ingest("B", runtime: runtime)
            let publication = try #require(await runtime.publication(for: .logs))
            await gate.hold(publication)
            model.applyLiveSessionRuntimePublication(publication, runtime: runtime)
        }
        let held = await gate.waitUntilHeld()
        #expect(logs(held)?.appendedEntries.map(\.id) == ["B"])
        try await setDestination(.other, window: window, model: model, runtime: runtime)
        await gate.release()
        try await delivery.value
        #expect(model.controllerSession.logBuffer.entries.map(\.id) == ["A", "B"])
        #expect(model.logsCatalog.entries.map(\.id) == ["A"])

        try await ingest("C", runtime: runtime)
        try await setDestination(.logs, window: window, model: model, runtime: runtime)
        let resumed = try #require(await runtime.publication(for: .logs, force: true))
        #expect(logs(resumed)?.fullSnapshot == nil)
        #expect(logs(resumed)?.appendedEntries.map(\.id) == ["C"])
        model.applyLiveSessionRuntimePublication(resumed, runtime: runtime)

        #expect(model.logsCatalog.entries.map(\.id) == ["A", "B", "C"])
        #expect(model.logsCatalog.lastChange == .replace)
    }

    @Test func continuousVisibleDeliveryKeepsIncrementalCatalogChanges() async throws {
        let (model, runtime, _) = try makeModel()
        defer { model.leaveLiveSession() }
        try await publish("A", model: model, runtime: runtime)
        try await publish("B", model: model, runtime: runtime)
        guard case .delta(let dropped, let appended) = model.logsCatalog.lastChange else {
            Issue.record("Continuous visible publication should remain incremental")
            return
        }
        #expect(dropped.isEmpty)
        #expect(appended.map(\.id) == ["B"])
        #expect(model.logsCatalog.entries.map(\.id) == ["A", "B"])
        #expect(LiveSessionPublicationDomain.logs.cadence == .milliseconds(200))
    }

    @Test func pausedDeliveryIsRestoredWhenNewerDeltaResumes() async throws {
        let (model, runtime, _) = try makeModel()
        defer { model.leaveLiveSession() }
        try await publish("A", model: model, runtime: runtime)
        try await ingest("B", runtime: runtime)
        let paused = try #require(await runtime.publication(for: .logs))
        model.dashboardSessionControls.setLogsPresentationPaused(true)
        model.applyLiveSessionRuntimePublication(paused, runtime: runtime)
        #expect(model.logsCatalog.entries.map(\.id) == ["A"])
        model.dashboardSessionControls.setLogsPresentationPaused(false)
        try await publish("C", model: model, runtime: runtime)
        #expect(model.logsCatalog.entries.map(\.id) == ["A", "B", "C"])
    }

    @Test func hiddenClearCannotResurrectPreClearEntries() async throws {
        let (model, runtime, window) = try makeModel()
        defer { model.leaveLiveSession() }
        try await publish("A", model: model, runtime: runtime)
        _ = await runtime.clearLogs()
        let clear = try #require(await runtime.publication(for: .logs))
        try await setDestination(.other, window: window, model: model, runtime: runtime)
        model.applyLiveSessionRuntimePublication(clear, runtime: runtime)
        #expect(model.controllerSession.logBuffer.isEmpty)
        #expect(model.logsCatalog.entries.map(\.id) == ["A"])
        try await ingest("C", runtime: runtime)
        try await setDestination(.logs, window: window, model: model, runtime: runtime)
        let resumed = try #require(await runtime.publication(for: .logs))
        model.applyLiveSessionRuntimePublication(resumed, runtime: runtime)
        #expect(model.logsCatalog.entries.map(\.id) == ["C"])
    }

    @Test func hiddenResetReplacesEarlierVisibleHistory() async throws {
        let (model, runtime, window) = try makeModel()
        defer { model.leaveLiveSession() }
        try await publish("A", model: model, runtime: runtime)
        _ = await runtime.ingestLogs(
            [LogMessage(type: "info", payload: "reset")],
            reset: true,
            source: .singBoxGRPC
        )
        let reset = try #require(await runtime.publication(for: .logs))
        try await setDestination(.other, window: window, model: model, runtime: runtime)
        model.applyLiveSessionRuntimePublication(reset, runtime: runtime)
        #expect(model.logsCatalog.entries.map(\.message.payload) == ["A"])
        try await ingest("C", runtime: runtime)
        try await setDestination(.logs, window: window, model: model, runtime: runtime)
        let resumed = try #require(await runtime.publication(for: .logs))
        model.applyLiveSessionRuntimePublication(resumed, runtime: runtime)
        #expect(model.logsCatalog.entries.map(\.message.payload) == ["reset", "C"])
    }

    @Test func anotherLogsWindowKeepsDeliveryVisibleAndIncremental() async throws {
        let (model, runtime, firstWindow) = try makeModel()
        defer { model.leaveLiveSession() }
        let secondWindow = LiveSessionWindowDemandID()
        _ = model.sessionPresentationCoordinator.registerWindowDemand(secondWindow, destination: .logs)
        try await publish("A", model: model, runtime: runtime)
        try await ingest("B", runtime: runtime)
        let publication = try #require(await runtime.publication(for: .logs))
        try await setDestination(.other, window: firstWindow, model: model, runtime: runtime)
        model.applyLiveSessionRuntimePublication(publication, runtime: runtime)
        #expect(model.logsCatalog.entries.map(\.id) == ["A", "B"])
        guard case .delta = model.logsCatalog.lastChange else {
            Issue.record("The remaining logs window must keep the incremental path")
            return
        }
    }

    @Test func newerDeliveryBeforeHeldDeltaRecoversFromActor() async throws {
        let (model, runtime, _) = try makeModel()
        defer { model.leaveLiveSession() }
        try await publish("A", model: model, runtime: runtime)
        let gate = RuntimeLogDeliveryGate()
        let delivery = Task {
            try await ingest("B", runtime: runtime)
            let publication = try #require(await runtime.publication(for: .logs))
            await gate.hold(publication)
            model.applyLiveSessionRuntimePublication(publication, runtime: runtime)
        }
        _ = await gate.waitUntilHeld()
        try await publish("C", model: model, runtime: runtime)
        await gate.release()
        try await delivery.value
        for _ in 0..<1_000 where model.logsCatalog.entries.map(\.id) != ["A", "B", "C"] {
            await Task.yield()
        }
        #expect(model.controllerSession.logBuffer.entries.map(\.id) == ["A", "B", "C"])
        #expect(model.logsCatalog.entries.map(\.id) == ["A", "B", "C"])
        try await publish("D", model: model, runtime: runtime)
        #expect(model.logsCatalog.entries.map(\.id) == ["A", "B", "C", "D"])
        guard case .delta = model.logsCatalog.lastChange else {
            Issue.record("A completed recovery must return to incremental delivery")
            return
        }
    }

    @Test func oversizedHiddenEntryCannotRestoreEvictedHistory() async throws {
        let (model, runtime, window) = try makeModel()
        defer { model.leaveLiveSession() }
        try await publish("A", model: model, runtime: runtime)
        _ = await runtime.ingestLog(
            LogMessage(type: "info", payload: String(repeating: "x", count: BoundedLogBuffer.maximumUTF8Bytes)),
            source: .mihomoWebSocket,
            id: "oversized"
        )
        let evicted = try #require(await runtime.publication(for: .logs))
        try await setDestination(.other, window: window, model: model, runtime: runtime)
        model.applyLiveSessionRuntimePublication(evicted, runtime: runtime)
        #expect(model.controllerSession.logBuffer.isEmpty)
        try await ingest("C", runtime: runtime)
        try await setDestination(.logs, window: window, model: model, runtime: runtime)
        let resumed = try #require(await runtime.publication(for: .logs))
        model.applyLiveSessionRuntimePublication(resumed, runtime: runtime)
        #expect(model.logsCatalog.entries.map(\.id) == ["C"])
    }

    @Test func byteRetentionCannotReappendEntriesEvictedWithinThePendingBatch() async throws {
        let (model, runtime, _) = try makeModel()
        defer { model.leaveLiveSession() }
        try await publish("A", model: model, runtime: runtime)
        let payload = String(repeating: "x", count: 5 * 1_024 * 1_024)
        for id in ["B", "C"] {
            _ = await runtime.ingestLog(
                LogMessage(type: "info", payload: payload),
                source: .mihomoWebSocket,
                id: id
            )
        }
        let publication = try #require(await runtime.publication(for: .logs))
        model.applyLiveSessionRuntimePublication(publication, runtime: runtime)

        #expect(model.controllerSession.logBuffer.entries.map(\.id) == ["C"])
        #expect(model.logsCatalog.entries.map(\.id) == ["C"])
        #expect(model.controllerSession.logBuffer.utf8ByteCount <= BoundedLogBuffer.maximumUTF8Bytes)
        #expect(logs(publication)?.fullSnapshot?.map(\.id) == ["C"])

        try await publish("D", model: model, runtime: runtime)
        #expect(model.logsCatalog.entries.map(\.id) == ["C", "D"])
        guard case .delta = model.logsCatalog.lastChange else {
            Issue.record("Retained batches must resume normal incremental publication")
            return
        }
    }

    @Test func delayedOldGenerationCannotChangeReplacementLogProgress() async throws {
        let (model, runtime, window) = try makeModel()
        defer { model.leaveLiveSession() }
        try await publish("A", model: model, runtime: runtime)
        try await ingest("B", runtime: runtime)
        let oldPublication = try #require(await runtime.publication(for: .logs))
        let profile = try #require(model.selectedRouter)
        model.leaveLiveSession()
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 2))
        model.controllerSession.state = .live
        model.activeSessionControllerKind = .mihomoCompatible
        model.liveStreamRequested = true
        _ = model.sessionPresentationCoordinator.registerWindowDemand(window, destination: .logs)
        model.installLiveSessionRuntime(for: profile, generation: model.controllerSession.generation)
        let replacement = try #require(model.liveSessionRuntime)
        try await publish("new", model: model, runtime: replacement)

        model.applyLiveSessionRuntimePublication(oldPublication, runtime: runtime)

        #expect(model.logsCatalog.entries.map(\.id) == ["new"])
        #expect(model.controllerSession.logBuffer.entries.map(\.id) == ["new"])
        #expect(model.lastRuntimeLogSequence == 1)
    }

    private func makeModel() throws -> (AppModel, LiveSessionRuntime, LiveSessionWindowDemandID) {
        let profile = RouterProfile(
            displayName: "Offline logs",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
        model.controllerSession.state = .live
        model.activeSessionControllerKind = .mihomoCompatible
        model.liveStreamRequested = true
        let window = LiveSessionWindowDemandID()
        _ = model.sessionPresentationCoordinator.registerWindowDemand(window, destination: .logs)
        model.installLiveSessionRuntime(for: profile, generation: model.controllerSession.generation)
        return (model, try #require(model.liveSessionRuntime), window)
    }

    private func setDestination(
        _ destination: LiveSessionVisibleDestination,
        window: LiveSessionWindowDemandID,
        model: AppModel,
        runtime: LiveSessionRuntime
    ) async throws {
        _ = model.sessionPresentationCoordinator.updateWindowDemand(window, destination: destination)
        let identity = try #require(model.liveSessionRuntimeIdentity)
        let nextDemand = model.sessionPresentationCoordinator.nextPresentationDemand(
            identity: identity,
            presentationPaused: model.dashboardSessionControls.dashboardUpdatesPaused,
            logsPresentationPaused: model.dashboardSessionControls.logsPresentationPaused,
            baselinePublicationRequired: model.controllerSession.baselineTransaction.isActive
        )
        let demand = try #require(nextDemand)
        #expect(await runtime.setPresentationDemand(demand) != nil)
    }

    private func ingest(_ id: String, runtime: LiveSessionRuntime) async throws {
        _ = await runtime.ingestLog(
            LogMessage(type: "info", payload: id),
            source: .mihomoWebSocket,
            id: id
        )
    }

    private func publish(_ id: String, model: AppModel, runtime: LiveSessionRuntime) async throws {
        try await ingest(id, runtime: runtime)
        let publication = try #require(await runtime.publication(for: .logs))
        model.applyLiveSessionRuntimePublication(publication, runtime: runtime)
    }

    private func logs(_ publication: LiveSessionRuntimePublication) -> LiveSessionLogsPublication? {
        guard case .logs(let logs) = publication.payload else { return nil }
        return logs
    }
}
