import Foundation
import MicaCore
import Testing
@testable import Mica

/// Deliberately lets a cancelled sleeper finish successfully as well as throw:
/// cancellation can race with the normal wake-up before its MainActor hop.
private actor RuntimePublicationTaskGate {
    private var nextCall = 0
    private var sleepers: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]

    func sleep() async throws {
        let call = nextCall
        nextCall += 1
        try await withCheckedThrowingContinuation { continuation in
            sleepers[call] = continuation
            waiters.removeValue(forKey: call)?.resume()
        }
    }

    func waitUntilSleeping(_ call: Int) async {
        if sleepers[call] != nil { return }
        await withCheckedContinuation { waiters[call] = $0 }
    }

    func release(_ call: Int, throwingCancellation: Bool = false) {
        let continuation = sleepers.removeValue(forKey: call)
        if throwingCancellation {
            continuation?.resume(throwing: CancellationError())
        } else {
            continuation?.resume()
        }
    }
}

@MainActor
struct RuntimePublicationTaskOwnershipTests {
    @Test(arguments: [false, true])
    func obsoleteSleeperCannotRemoveReplacementTask(throwingCancellation: Bool) async throws {
        let gate = RuntimePublicationTaskGate()
        let profile = RouterProfile(
            displayName: "Offline task ownership",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore(),
            sessionPublicationSleepOperation: { _, _ in try await gate.sleep() }
        )
        defer { model.leaveLiveSession() }
        let oldRuntime = try beginSession(model: model, profile: profile)
        let oldIdentity = try #require(model.liveSessionRuntimeIdentity)
        let oldDomains = await oldRuntime.ingestLog(
            LogMessage(type: "info", payload: "old"),
            source: .mihomoWebSocket,
            id: "old"
        )
        model.scheduleLiveSessionRuntimePublications(oldDomains, runtime: oldRuntime, identity: oldIdentity)
        let oldTask = try #require(model.runtimePublicationTasks[.logs])
        await gate.waitUntilSleeping(0)

        model.leaveLiveSession()
        let replacement = try beginSession(model: model, profile: profile)
        let replacementIdentity = try #require(model.liveSessionRuntimeIdentity)
        let replacementDomains = await replacement.ingestLog(
            LogMessage(type: "info", payload: "new"),
            source: .mihomoWebSocket,
            id: "new"
        )
        model.scheduleLiveSessionRuntimePublications(
            replacementDomains,
            runtime: replacement,
            identity: replacementIdentity
        )
        let replacementTask = try #require(model.runtimePublicationTasks[.logs])
        await gate.waitUntilSleeping(1)

        await gate.release(0, throwingCancellation: throwingCancellation)
        await oldTask.value
        #expect(model.runtimePublicationTasks[.logs] != nil)
        #expect(model.liveSessionRuntime === replacement)
        #expect(model.liveSessionRuntimeIdentity == replacementIdentity)
        #expect(model.logsCatalog.entries.isEmpty)

        // Retaining the dictionary entry matters for cancellation ownership,
        // not merely for the presence of a bookkeeping value.
        model.cancelLiveSessionRuntime()
        #expect(replacementTask.isCancelled)
        replacementTask.cancel()
        await gate.release(1)
        await replacementTask.value
        #expect(model.runtimePublicationTasks.isEmpty)
        #expect(model.logsCatalog.entries.isEmpty)
    }

    private func beginSession(model: AppModel, profile: RouterProfile) throws -> LiveSessionRuntime {
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
        model.controllerSession.state = .live
        model.activeSessionControllerKind = .mihomoCompatible
        model.liveStreamRequested = true
        _ = model.sessionPresentationCoordinator.registerWindowDemand(
            LiveSessionWindowDemandID(),
            destination: .logs
        )
        model.installLiveSessionRuntime(for: profile, generation: model.controllerSession.generation)
        return try #require(model.liveSessionRuntime)
    }
}
