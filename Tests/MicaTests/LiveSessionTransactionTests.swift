import Foundation
import MicaCore
import Testing
@testable import Mica

private enum InjectedStoreFailure: Error {
    case save
}

private func makeSleepingTask() -> Task<Void, Never> {
    Task {
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            return
        }
    }
}

private actor TransactionProfileStore: RouterProfileStore {
    private var profiles: [RouterProfile]
    private let failsOnSave: Bool

    init(profiles: [RouterProfile], failsOnSave: Bool) {
        self.profiles = profiles
        self.failsOnSave = failsOnSave
    }

    func loadProfiles() async throws -> [RouterProfile] {
        profiles
    }

    func saveProfiles(_ profiles: [RouterProfile]) async throws {
        if failsOnSave { throw InjectedStoreFailure.save }
        self.profiles = profiles
    }

    func storedProfiles() -> [RouterProfile] {
        profiles
    }
}

private actor TransactionSecretStore: SecretStore {
    private var values: [UUID: String]

    init(values: [UUID: String]) {
        self.values = values
    }

    func secret(for profileID: UUID) async throws -> String? {
        values[profileID]
    }

    func save(_ secret: String, for profileID: UUID) async throws {
        values[profileID] = secret
    }

    func removeSecret(for profileID: UUID) async throws {
        values.removeValue(forKey: profileID)
    }
}

private actor ControllerProbeScript {
    private var attempts = 0

    func resolve(
        profile: RouterProfile,
        credential: String?,
        includeSurge: Bool
    ) throws -> ControllerKind {
        _ = profile
        _ = credential
        _ = includeSurge
        attempts += 1
        if attempts == 1 {
            throw MihomoClientError.connectionFailure(.connectionRefused)
        }
        return .mihomoCompatible
    }

    func attemptCount() -> Int {
        attempts
    }
}

struct LiveSessionTransactionTests {
    @Test func laneStateCoalescesOneFollowUpAndResetsRetryAfterSuccess() {
        var state = SessionRefreshLaneState()

        let firstBegin = state.begin()
        let secondBegin = state.begin()
        #expect(firstBegin)
        #expect(!secondBegin)
        #expect(state.pendingFollowUp)

        state.finishFailure("offline", disposition: .transient)
        #expect(state.retryAttempt == 1)
        let firstFollowUp = state.consumeFollowUp()
        let secondFollowUp = state.consumeFollowUp()
        #expect(firstFollowUp)
        #expect(!secondFollowUp)

        let success = Date(timeIntervalSince1970: 42)
        state.finishSuccess(at: success)
        #expect(state.retryAttempt == 0)
        #expect(state.lastSuccessAt == success)
        #expect(state.lastFailure == nil)
    }

    @Test func retryPolicyCapsAtThirtySecondsWithInjectableJitter() {
        #expect(SessionRetryPolicy.delay(forAttempt: 0, jitter: 0) == .seconds(2))
        #expect(SessionRetryPolicy.delay(forAttempt: 4, jitter: 0) == .seconds(30))
        #expect(SessionRetryPolicy.delay(forAttempt: 40, jitter: 0) == .seconds(30))
    }

    @Test func liveStreamRetryStateDeduplicatesConcurrentChannelFailures() {
        var state = LiveStreamRetryState()

        #expect(state.reserveDelay(jitter: 0) == .seconds(2))
        #expect(state.reserveDelay(jitter: 0) == nil)
        #expect(state.attempt == 1)
        #expect(state.isScheduled)

        state.consumeScheduledRetry()
        #expect(state.reserveDelay(jitter: 0) == .seconds(4))
        #expect(state.attempt == 2)

        state.consumeScheduledRetry()
        state.recordSuccess()
        #expect(state.reserveDelay(jitter: 0) == .seconds(2))
    }

    @MainActor
    @Test func autoDetectRetriesConnectionRefusedUntilTheSelectedControllerAppears() async throws {
        let profile = RouterProfile(
            displayName: "Delayed Mihomo",
            host: "192.0.2.1",
            port: 65_535,
            controllerKind: .autoDetect
        )
        let probe = ControllerProbeScript()
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore(),
            controllerProbeOperation: { profile, credential, includeSurge in
                try await probe.resolve(
                    profile: profile,
                    credential: credential,
                    includeSurge: includeSurge
                )
            },
            controllerProbeSleepOperation: { _ in
                await Task.yield()
            }
        )

        model.enterLiveSession(for: profile)
        let generation = model.controllerSession.generation
        defer { model.leaveLiveSession() }

        for _ in 0 ..< 100 where model.activeSessionControllerKind != .mihomoCompatible {
            try await Task.sleep(for: .milliseconds(10))
        }

        let attemptCount = await probe.attemptCount()
        #expect(attemptCount == 2)
        #expect(model.activeSessionControllerKind == .mihomoCompatible)
        #expect(model.controllerSession.controllerID == profile.id)
        #expect(model.controllerSession.generation == generation)
        #expect(model.backendProbeTask == nil)
    }

    @MainActor
    @Test func selectedControllerPersistenceRoundTripsAndClears() {
        let suiteName = "MicaTests.SelectedController.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore(),
            userDefaults: defaults
        )
        let id = UUID()

        model.persistSelectedRouterID(id)
        #expect(model.persistedSelectedRouterID() == id)

        model.persistSelectedRouterID(nil)
        #expect(model.persistedSelectedRouterID() == nil)
    }

    @MainActor
    @Test func commandCapabilitiesKeepTestingAvailableWhilePresentationIsPaused() {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .unsupported
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

        #expect(model.canTestSelectedRouter)
        #expect(model.canRefreshSelectedRouter)
        #expect(model.canTogglePresentationPause)

        var controls = model.dashboardSessionControls
        let pausedAt = Date(timeIntervalSince1970: 123)
        controls.setPresentationPaused(true, at: pausedAt)
        model.dashboardSessionControls = controls

        #expect(model.canTestSelectedRouter)
        #expect(!model.canRefreshSelectedRouter)
        #expect(model.canTogglePresentationPause)
        #expect(model.dashboardSessionControls.presentationPausedAt == pausedAt)

        controls.setPresentationPaused(false, at: pausedAt)
        #expect(controls.presentationPausedAt == nil)

        model.selectedRouterID = nil
        #expect(!model.canTestSelectedRouter)
        #expect(!model.canRefreshSelectedRouter)
        #expect(!model.canTogglePresentationPause)
    }

    @MainActor
    @Test func autoDetectedSurgeDrivesRuntimeRoutingWithoutChangingTheProfile() {
        let profile = RouterProfile(
            displayName: "Auto",
            host: "127.0.0.1",
            controllerKind: .autoDetect
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.activeSessionControllerKind = .surgeCompatible

        #expect(model.runtimeControllerKind(for: profile) == .surgeCompatible)
        #expect(model.effectiveUnifiedControllerType(for: profile) == .surgeHTTPAPI)
        #expect(model.effectiveUnifiedCapabilities(for: profile) == .surgeHTTPAPI)
        #expect(model.selectedControllerAdapter.detectedKind == .surgeCompatible)
        #expect(model.activeUnifiedAdapter?.controllerType == .surgeHTTPAPI)
        #expect(model.modeChangeAction(for: profile) == .setOutboundMode)
        #expect(model.routers.first?.controllerKind == .autoDetect)
    }

    @MainActor
    @Test func autoDetectedMihomoBuildsAMihomoRuntimeAdapterWithoutMutatingProfile() {
        let profile = RouterProfile(
            displayName: "Auto",
            host: "127.0.0.1",
            controllerKind: .autoDetect
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.activeSessionControllerKind = .mihomoCompatible

        #expect(model.activeUnifiedAdapter?.controllerType == .mihomoCompatible)
        #expect(model.activeUnifiedAdapter?.capabilities == .mihomoCompatible)
        #expect(model.modeChangeAction(for: profile) == .changeMode)
        #expect(model.routers.first?.controllerKind == .autoDetect)
    }

    @MainActor
    @Test func leavingSessionClearsAutoDetectedRuntimeKind() {
        let profile = RouterProfile(
            displayName: "Auto",
            host: "127.0.0.1",
            controllerKind: .autoDetect
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        let generation = model.controllerSession.generation
        model.activeSessionControllerKind = .mihomoCompatible

        model.leaveLiveSession()

        #expect(model.activeSessionControllerKind == nil)
        #expect(model.controllerSession.controllerID == nil)
        #expect(!model.isCurrentSession(routerID: profile.id, generation: generation))
    }

    @MainActor
    @Test func leavingSessionCancelsEveryControllerOperationTaskAndMarker() {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .unsupported
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)

        let refreshTask = makeSleepingTask()
        let switchTask = makeSleepingTask()
        let modeTask = makeSleepingTask()
        let configTask = makeSleepingTask()
        let delayTask = makeSleepingTask()
        let connectionTask = makeSleepingTask()
        let providerTask = makeSleepingTask()
        let rulesTask = makeSleepingTask()
        let surgeTask = makeSleepingTask()
        let runtimeOperationTask = makeSleepingTask()

        model.refreshTask = refreshTask
        model.switchTask = switchTask
        model.modeTask = modeTask
        model.configTask = configTask
        model.delayTask = delayTask
        model.connectionTask = connectionTask
        model.providerTask = providerTask
        model.rulesTask = rulesTask
        model.surgeTask = surgeTask
        model.runtimeOperationTask = runtimeOperationTask
        model.switchingGroupID = "group"
        model.clearingFixedGroupID = "group"
        model.changingMode = true
        model.updatingConfigFieldID = "allow-lan"
        model.measuringDelayGroupID = "group"
        model.measuringDelayNode = PolicyNodeLatencyTestTarget(
            groupID: "group",
            nodeName: "node"
        )
        model.closingConnectionID = "connection"
        model.closingConnectionGroupID = "owner-group"
        model.closingAllConnections = true
        model.updatingProviderName = "provider"
        model.checkingProviderName = "provider-health"
        model.providerHealthCheckFailures["provider-health"] = "failed"
        model.isRefreshingDashboard = true
        model.reloadingRules = true
        model.updatingRuleID = "rule"
        model.ruleUpdateFailures["rule"] = "failed"
        model.reloadingProviders = true
        model.changingSurgeOutbound = true
        model.testingSurgePolicyGroup = "group"
        model.switchingSurgePolicyGroup = "group"
        model.killingSurgeRequestID = "request"
        model.killingSurgeProjectedConnectionID = "connection"
        model.reloadingSurgeProfile = true
        model.changingControllerLogLevel = true
        model.runningRuntimeOperationID = "memory"

        model.leaveLiveSession()

        #expect(refreshTask.isCancelled)
        #expect(switchTask.isCancelled)
        #expect(modeTask.isCancelled)
        #expect(configTask.isCancelled)
        #expect(delayTask.isCancelled)
        #expect(connectionTask.isCancelled)
        #expect(providerTask.isCancelled)
        #expect(rulesTask.isCancelled)
        #expect(surgeTask.isCancelled)
        #expect(runtimeOperationTask.isCancelled)
        #expect(model.refreshTask == nil)
        #expect(model.switchTask == nil)
        #expect(model.modeTask == nil)
        #expect(model.configTask == nil)
        #expect(model.delayTask == nil)
        #expect(model.connectionTask == nil)
        #expect(model.providerTask == nil)
        #expect(model.rulesTask == nil)
        #expect(model.surgeTask == nil)
        #expect(model.runtimeOperationTask == nil)
        #expect(model.clearingFixedGroupID == nil)
        #expect(model.updatingConfigFieldID == nil)
        #expect(model.measuringDelayNode == nil)
        #expect(model.closingConnectionGroupID == nil)
        #expect(model.checkingProviderName == nil)
        #expect(model.providerHealthCheckFailures.isEmpty)
        #expect(!model.reloadingSurgeProfile)
        #expect(!model.changingControllerLogLevel)
        #expect(model.updatingRuleID == nil)
        #expect(model.ruleUpdateFailures.isEmpty)
        #expect(!model.isBusy)
    }

    @MainActor
    @Test func leavingSessionCancelsTheCompleteLiveTaskTree() {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .unsupported
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)

        let tasks = (0..<11).map { _ in makeSleepingTask() }
        model.initialSessionRefreshTask = tasks[0]
        model.fastSessionRefreshTask = tasks[1]
        model.mediumSessionRefreshTask = tasks[2]
        model.slowSessionRefreshTask = tasks[3]
        model.manualSessionRefreshTask = tasks[4]
        model.liveTrafficTask = tasks[5]
        model.liveLogsTask = tasks[6]
        model.liveMemoryTask = tasks[7]
        model.liveConnectionsTask = tasks[8]
        model.liveRetryTask = tasks[9]
        model.backendProbeTask = tasks[10]

        model.leaveLiveSession()

        #expect(tasks.allSatisfy { $0.isCancelled })
        #expect(model.initialSessionRefreshTask == nil)
        #expect(model.fastSessionRefreshTask == nil)
        #expect(model.mediumSessionRefreshTask == nil)
        #expect(model.slowSessionRefreshTask == nil)
        #expect(model.manualSessionRefreshTask == nil)
        #expect(model.liveTrafficTask == nil)
        #expect(model.liveLogsTask == nil)
        #expect(model.liveMemoryTask == nil)
        #expect(model.liveConnectionsTask == nil)
        #expect(model.liveRetryTask == nil)
        #expect(model.backendProbeTask == nil)
    }

    @MainActor
    @Test func profileSaveFailureRollsBackSecretAndLeavesLiveModelUntouched() async {
        let id = UUID()
        let profile = RouterProfile(
            id: id,
            displayName: "Existing",
            host: "127.0.0.1",
            secretReference: AppModel.secretReference(for: id),
            controllerKind: .unsupported
        )
        let profileStore = TransactionProfileStore(profiles: [profile], failsOnSave: true)
        let secretStore = TransactionSecretStore(values: [id: "old-secret"])
        let model = AppModel(
            routers: [profile],
            controllerSecrets: [id: "old-secret"],
            profileStore: profileStore,
            secretStore: secretStore
        )
        var draft = RouterDraft(profile: profile, secret: "new-secret", hasStoredSecret: true)
        draft.displayName = "Changed"

        do {
            try await model.upsertRouter(from: draft)
            Issue.record("Expected the injected profile-store failure")
        } catch {
            #expect(model.routers == [profile])
            #expect(model.controllerSecrets[id] == "old-secret")
            let storedSecret = try? await secretStore.secret(for: id)
            let storedProfiles = await profileStore.storedProfiles()
            #expect(storedSecret == "old-secret")
            #expect(storedProfiles == [profile])
        }
    }

    @MainActor
    @Test func deleteFailureRestoresSecretAndPreservesSelectionAndOrder() async {
        let first = RouterProfile(
            displayName: "First",
            host: "127.0.0.1",
            secretReference: nil,
            controllerKind: .unsupported
        )
        let second = RouterProfile(
            displayName: "Second",
            host: "127.0.0.2",
            secretReference: AppModel.secretReference(for: UUID()),
            controllerKind: .unsupported
        )
        var storedSecond = second
        storedSecond.secretReference = AppModel.secretReference(for: second.id)
        let profiles = [first, storedSecond]
        let profileStore = TransactionProfileStore(profiles: profiles, failsOnSave: true)
        let secretStore = TransactionSecretStore(values: [storedSecond.id: "keep-me"])
        let model = AppModel(
            routers: profiles,
            selectedRouterID: first.id,
            controllerSecrets: [storedSecond.id: "keep-me"],
            profileStore: profileStore,
            secretStore: secretStore
        )

        do {
            try await model.deleteRouterTransaction(storedSecond)
            Issue.record("Expected the injected profile-store failure")
        } catch {
            #expect(model.routers == profiles)
            #expect(model.selectedRouterID == first.id)
            #expect(model.controllerSecrets[storedSecond.id] == "keep-me")
            let storedSecret = try? await secretStore.secret(for: storedSecond.id)
            #expect(storedSecret == "keep-me")
        }
    }
}
