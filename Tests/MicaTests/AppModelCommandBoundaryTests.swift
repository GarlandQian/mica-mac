import Foundation
import Observation
import Synchronization
import Testing
@testable import Mica
@testable import MicaCore

struct AppModelCommandBoundaryTests {
    @Test func ruleTargetResolverRequiresOneExactCurrentRule() throws {
        let requested = makeRule(
            id: "rule-id",
            index: 4,
            payload: "example.com"
        )
        let unrelated = makeRule(
            id: "other-rule",
            index: 3,
            payload: "other.example"
        )

        let resolvedAfterArrayInsertion = try #require(
            RuleMutationTargetResolver.resolve(
                requested: requested,
                currentRules: [unrelated, requested]
            )
        )
        #expect(resolvedAfterArrayInsertion == requested)

        var reordered = requested
        reordered.index = 5
        #expect(
            RuleMutationTargetResolver.resolve(
                requested: requested,
                currentRules: [reordered]
            ) == nil
        )

        var changedPayload = requested
        changedPayload.payload = "changed.example"
        #expect(
            RuleMutationTargetResolver.resolve(
                requested: requested,
                currentRules: [changedPayload]
            ) == nil
        )

        var missingIndex = requested
        missingIndex.index = nil
        #expect(
            RuleMutationTargetResolver.resolve(
                requested: missingIndex,
                currentRules: [missingIndex]
            ) == nil
        )
        #expect(
            RuleMutationTargetResolver.resolve(
                requested: requested,
                currentRules: [requested, requested]
            ) == nil
        )
    }

    @MainActor
    @Test func staleRuleNeverDispatchesAndCurrentRuleUsesItsResolvedIndex() async throws {
        let recorder = RuleMutationRecorder()
        let currentRule = makeRule(
            id: "rule-id",
            index: 7,
            payload: "current.example"
        )
        let currentRuleType = currentRule.type
        let currentRulePayload = currentRule.payload
        let currentRuleProxy = currentRule.proxy
        let dashboard = makeDashboard(rules: [currentRule])
        let (model, _) = makeLiveCommandModel(
            dashboard: dashboard,
            ruleOperation: { _, _, index, disabled in
                await recorder.record(index: index, disabled: disabled)
                return RulesResponse(
                    rules: [
                        RuleSnapshot(
                            index: index,
                            type: currentRuleType,
                            payload: currentRulePayload,
                            proxy: currentRuleProxy,
                            extra: RuleExtraSnapshot(disabled: disabled)
                        ),
                    ]
                )
            }
        )

        var staleRule = currentRule
        staleRule.payload = "stale.example"
        model.setRuleDisabled(
            staleRule,
            disabled: true,
            scope: commandScope(for: model)
        )

        #expect(model.rulesTask == nil)
        #expect(model.updatingRuleID == nil)
        let callsAfterStaleIntent = await recorder.calls
        #expect(callsAfterStaleIntent.isEmpty)

        model.setRuleDisabled(
            currentRule,
            disabled: true,
            scope: commandScope(for: model)
        )
        let task = try #require(model.rulesTask)
        await task.value

        let calls = await recorder.calls
        #expect(calls == [RuleMutationCall(index: 7, disabled: true)])
        #expect(model.rulesTask == nil)
        #expect(model.updatingRuleID == nil)
        #expect(model.rulesCatalog.rules.first?.payload == "current.example")
    }

    @MainActor
    @Test func authoritativeConfigRefreshPublishesOnlyItsChangedDomains() async throws {
        let config = try JSONDecoder().decode(
            ConfigResponse.self,
            from: Data(
                #"{"mode":"rule","mode-options":["rule","global"],"allow-lan":true}"#.utf8
            )
        )
        let (model, _) = makeLiveCommandModel(
            configUpdateOperation: { _, _, _ in },
            configSnapshotOperation: { _, _ in config }
        )

        let pendingRule = makeRule(
            id: "pending-rule",
            index: 9,
            payload: "pending.example"
        )
        let pendingConnection = ConnectionSnapshot(id: "pending-connection")
        model.dashboard.rules = [pendingRule]
        model.dashboard.connections = [pendingConnection]

        let metadataInvalidated = Mutex(false)
        let unrelatedCatalogInvalidated = Mutex(false)
        withObservationTracking {
            _ = model.controllerMetadata
        } onChange: {
            metadataInvalidated.withLock { $0 = true }
        }
        withObservationTracking {
            _ = model.policyGroupCatalog
            _ = model.connectionsCatalog
            _ = model.rulesCatalog
            _ = model.providersCatalog
        } onChange: {
            unrelatedCatalogInvalidated.withLock { $0 = true }
        }

        model.updateControllerConfig(
            .allowLAN(true),
            scope: commandScope(for: model)
        )
        let task = try #require(model.configTask)
        await task.value

        #expect(metadataInvalidated.withLock { $0 })
        #expect(!unrelatedCatalogInvalidated.withLock { $0 })
        #expect(model.controllerMetadata.config.allowLan == true)
        #expect(model.connectionsCatalog.connections.isEmpty)
        #expect(model.rulesCatalog.rules.isEmpty)
        #expect(model.dashboard.connections == [pendingConnection])
        #expect(model.dashboard.rules == [pendingRule])
    }

    @MainActor
    @Test func repeatConfigIntentDoesNotCancelOrReplaceItsOwnerState() {
        let (model, _) = makeLiveCommandModel()
        let ownerTask = Task<Void, Never> {
            _ = try? await Task.sleep(for: .seconds(60))
        }
        defer { ownerTask.cancel() }
        let ownerState = OperationState.working("owner")
        let initialConfig = model.dashboard.config
        model.configTask = ownerTask
        model.updatingConfigFieldID = "owner-field"
        model.operationState = ownerState

        model.updateControllerConfig(
            .allowLAN(true),
            scope: commandScope(for: model)
        )

        #expect(!ownerTask.isCancelled)
        #expect(model.configTask != nil)
        #expect(model.updatingConfigFieldID == "owner-field")
        #expect(model.operationState == ownerState)
        #expect(model.dashboard.config == initialConfig)
    }

    @MainActor
    @Test func repeatedModeRuleAndProviderIntentsPreserveTheirFamilyOwners() {
        let currentRule = makeRule(
            id: "rule-id",
            index: 2,
            payload: "current.example"
        )
        let (model, _) = makeLiveCommandModel(
            dashboard: makeDashboard(rules: [currentRule])
        )
        let ownerState = OperationState.working("owner")

        let modeOwner = makeSleepingCommandTask()
        model.modeTask = modeOwner
        model.changingMode = true
        model.operationState = ownerState
        model.setMode("Global", scope: commandScope(for: model))
        #expect(!modeOwner.isCancelled)
        #expect(model.changingMode)
        #expect(model.operationState == ownerState)
        modeOwner.cancel()
        model.modeTask = nil
        model.changingMode = false

        let ruleOwner = makeSleepingCommandTask()
        model.rulesTask = ruleOwner
        model.reloadingRules = true
        model.operationState = ownerState
        model.setRuleDisabled(
            currentRule,
            disabled: true,
            scope: commandScope(for: model)
        )
        #expect(!ruleOwner.isCancelled)
        #expect(model.reloadingRules)
        #expect(model.operationState == ownerState)
        ruleOwner.cancel()
        model.rulesTask = nil
        model.reloadingRules = false

        let providerOwner = makeSleepingCommandTask()
        model.providerTask = providerOwner
        model.reloadingProviders = true
        model.operationState = ownerState
        model.reloadProviders()
        #expect(!providerOwner.isCancelled)
        #expect(model.reloadingProviders)
        #expect(model.operationState == ownerState)
        providerOwner.cancel()
    }

    @MainActor
    @Test func retainedScopeFromEarlierGenerationCannotStartCommands() {
        let rule = makeRule(
            id: "rule-id",
            index: 2,
            payload: "current.example"
        )
        let group = ProxyGroupViewState(
            id: "Selector",
            type: "Selector",
            selected: "Node A",
            options: ["Node A", "Node B"]
        )
        let (model, profile) = makeLiveCommandModel(
            dashboard: makeDashboard(groups: [group], rules: [rule])
        )
        let retainedScope = commandScope(for: model)
        #expect(model.matchesCurrentCommandScope(retainedScope))

        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 2))
        model.controllerSession.state = .live

        #expect(model.selectedRouterID == profile.id)
        #expect(model.controllerSessionPresentation.generation != retainedScope.generation)
        #expect(!model.matchesCurrentCommandScope(retainedScope))
        let initialDashboard = model.dashboard
        let initialOperationState = model.operationState

        model.updateControllerConfig(.allowLAN(true), scope: retainedScope)
        model.setMode("Global", scope: retainedScope)
        model.setRuleDisabled(rule, disabled: true, scope: retainedScope)
        model.selectNode("Node B", in: group.id, scope: retainedScope)
        model.setControllerLogLevel(.debug, scope: retainedScope)

        #expect(model.configTask == nil)
        #expect(model.modeTask == nil)
        #expect(model.rulesTask == nil)
        #expect(model.switchTask == nil)
        #expect(model.updatingConfigFieldID == nil)
        #expect(!model.changingMode)
        #expect(model.updatingRuleID == nil)
        #expect(model.switchingGroupID == nil)
        #expect(model.controllerLogLevel == .all)
        #expect(model.dashboard == initialDashboard)
        #expect(model.operationState == initialOperationState)
    }

    @MainActor
    @Test func retainedSurgeLogLevelScopeCannotStartRemoteCommand() {
        let (model, profile) = makeLiveCommandModel(
            controllerKind: .surgeCompatible
        )
        let retainedScope = commandScope(for: model)

        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 2))
        model.controllerSession.state = .live
        let initialOperationState = model.operationState

        model.setControllerLogLevel(.debug, scope: retainedScope)

        #expect(!model.matchesCurrentCommandScope(retainedScope))
        #expect(model.surgeTask == nil)
        #expect(!model.changingControllerLogLevel)
        #expect(model.controllerLogLevel == .all)
        #expect(model.operationState == initialOperationState)
    }

    @MainActor
    @Test func repeatedSurgeAndSingBoxRuntimeIntentsPreserveTheirOwners() {
        let ownerState = OperationState.working("owner")
        let (surgeModel, surgeRouter) = makeLiveCommandModel(
            controllerKind: .surgeCompatible
        )
        let surgeOwner = makeSleepingCommandTask()
        surgeModel.surgeTask = surgeOwner
        surgeModel.changingSurgeOutbound = true
        surgeModel.operationState = ownerState

        surgeModel.setSurgeOutboundMode("global")
        surgeModel.setControllerLogLevel(
            .debug,
            scope: commandScope(for: surgeModel)
        )
        surgeModel.reloadSurgeRules(surgeRouter)

        #expect(!surgeOwner.isCancelled)
        #expect(surgeModel.surgeTask != nil)
        #expect(surgeModel.changingSurgeOutbound)
        #expect(surgeModel.controllerLogLevel == .all)
        #expect(surgeModel.operationState == ownerState)
        surgeOwner.cancel()

        let (singBoxModel, singBoxRouter) = makeLiveCommandModel(
            controllerKind: .singBoxCompatible
        )
        let singBoxOwner = makeSleepingCommandTask()
        singBoxModel.runtimeOperationTask = singBoxOwner
        singBoxModel.runningRuntimeOperationID = "owner"
        singBoxModel.operationState = ownerState

        singBoxModel.clearSingBoxControllerLogs(router: singBoxRouter)
        singBoxModel.setSingBoxTailscaleExitNode(
            endpointTag: "tailscale",
            stableID: "stable"
        )

        #expect(!singBoxOwner.isCancelled)
        #expect(singBoxModel.runtimeOperationTask != nil)
        #expect(singBoxModel.runningRuntimeOperationID == "owner")
        #expect(singBoxModel.operationState == ownerState)
        singBoxOwner.cancel()

        let (scopedSingBoxModel, _) = makeLiveCommandModel(
            controllerKind: .singBoxCompatible
        )
        let foreignRouter = RouterProfile(
            displayName: "Foreign",
            host: "foreign.invalid",
            controllerKind: .singBoxCompatible
        )
        let initialMode = scopedSingBoxModel.dashboard.mode
        scopedSingBoxModel.setSingBoxMode("Global", router: foreignRouter)
        #expect(scopedSingBoxModel.modeTask == nil)
        #expect(scopedSingBoxModel.dashboard.mode == initialMode)

        let (runtimeModel, _) = makeLiveCommandModel()
        let runtimeOwner = makeSleepingCommandTask()
        runtimeModel.runtimeOperationTask = runtimeOwner
        runtimeModel.runningRuntimeOperationID = "owner"
        runtimeModel.operationState = ownerState

        runtimeModel.performDiagnosticsRuntimeOperation("memory")

        #expect(!runtimeOwner.isCancelled)
        #expect(runtimeModel.runtimeOperationTask != nil)
        #expect(runtimeModel.runningRuntimeOperationID == "owner")
        #expect(runtimeModel.operationState == ownerState)
        runtimeOwner.cancel()
    }

    @MainActor
    @Test func connectingStaleAndBusyRefreshIntentsSubmitNoWork() async {
        let refreshGate = CommandGate<RefreshLaneCall>()
        let restartCount = Mutex(0)
        let (model, _) = makeLiveCommandModel(
            refreshLaneOperation: { lane, _, _, manual in
                await refreshGate.suspend(
                    recording: RefreshLaneCall(lane: lane, manual: manual)
                )
            },
            manualRestartOperation: { _, _ in
                restartCount.withLock { $0 += 1 }
            }
        )

        model.controllerSession.state = .connecting
        model.connectionState = .connecting
        model.refreshSelectedRouter()

        model.controllerSession.state = .staleReconnecting("offline")
        model.connectionState = .connected(version: "stale")
        model.refreshSelectedRouter()

        model.controllerSession.state = .live
        model.changingMode = true
        model.refreshSelectedRouter()

        let calls = await refreshGate.values
        #expect(calls.isEmpty)
        #expect(restartCount.withLock { $0 } == 0)
        #expect(!model.liveSessionTasks.contains(.manualRefresh))
        #expect(model.selectedRouterRefreshOperationID == nil)
        #expect(!model.isRefreshingDashboard)
    }

    @MainActor
    @Test func duplicateUserRefreshIsRejectedWhileInternalRefreshStillRuns() async throws {
        let refreshGate = CommandGate<RefreshLaneCall>()
        let restartCount = Mutex(0)
        let (model, _) = makeLiveCommandModel(
            refreshLaneOperation: { lane, _, _, manual in
                await refreshGate.suspend(
                    recording: RefreshLaneCall(lane: lane, manual: manual)
                )
            },
            manualRestartOperation: { _, _ in
                restartCount.withLock { $0 += 1 }
            }
        )

        model.refreshSelectedRouter()
        await refreshGate.waitForCount(3)
        let ownerID = try #require(model.selectedRouterRefreshOperationID)
        let ownerTask = try #require(model.liveSessionTasks.task(for: .manualRefresh))
        #expect(model.isRefreshingDashboard)
        #expect(restartCount.withLock { $0 } == 1)

        model.refreshSelectedRouter()
        #expect(model.selectedRouterRefreshOperationID == ownerID)
        #expect(!ownerTask.isCancelled)
        #expect(restartCount.withLock { $0 } == 1)

        model.requestImmediateSessionRefresh()
        await refreshGate.waitForCount(6)
        let calls = await refreshGate.values
        #expect(calls.filter(\.manual).count == 3)
        #expect(calls.filter { !$0.manual }.count == 3)
        #expect(Set(calls.filter(\.manual).map(\.lane)) == Set(SessionRefreshLane.allCases))
        #expect(restartCount.withLock { $0 } == 1)
        #expect(model.selectedRouterRefreshOperationID == ownerID)

        await refreshGate.releaseAll()
        await ownerTask.value

        #expect(!model.liveSessionTasks.contains(.manualRefresh))
        #expect(model.selectedRouterRefreshOperationID == nil)
        #expect(!model.isRefreshingDashboard)
    }

    @MainActor
    @Test func failedAndPausedSessionCanTestButDuplicateCannotReplaceOwner() async throws {
        let testGate = CommandGate<Int>()
        let (model, _) = makeLiveCommandModel(
            testOperation: { _, _, _ in
                await testGate.suspend(recording: 1)
            }
        )

        model.controllerSession.state = .failedBeforeFirstSnapshot("first failure")
        #expect(model.canTestSelectedRouter)
        model.controllerSession.state = .failed("later failure")
        #expect(model.canTestSelectedRouter)
        model.dashboardSessionControls.setPresentationPaused(true)
        #expect(model.canTestSelectedRouter)

        model.testSelectedRouter()
        await testGate.waitForCount(1)
        let ownerID = try #require(model.selectedRouterTestOperationID)
        let ownerTask = try #require(model.refreshTask)
        #expect(model.isTestingSelectedRouter)

        model.testSelectedRouter()
        let calls = await testGate.values
        #expect(calls.count == 1)
        #expect(model.selectedRouterTestOperationID == ownerID)
        #expect(!ownerTask.isCancelled)

        await testGate.releaseAll()
        await ownerTask.value

        #expect(model.refreshTask == nil)
        #expect(model.selectedRouterTestOperationID == nil)
        #expect(!model.isTestingSelectedRouter)
        #expect(model.dashboardSessionControls.dashboardUpdatesPaused)
    }

    @MainActor
    @Test func ordinaryMihomoTestFailureClearsItsBusyOwner() async throws {
        let script = FailingMihomoTestScript()
        let (model, profile) = makeLiveCommandModel()
        model.controllerSession.state = .failedBeforeFirstSnapshot("offline")
        model.sessionMihomoClient = MihomoClient(profile: profile) { request in
            try await script.load(request)
        }

        model.testSelectedRouter()
        let task = try #require(model.refreshTask)
        await task.value

        let requestCount = await script.requestCount
        #expect(requestCount == 4)
        #expect(model.operationState?.kind == .error)
        #expect(model.refreshTask == nil)
        #expect(model.selectedRouterTestOperationID == nil)
        #expect(!model.isTestingSelectedRouter)
        #expect(model.canTestSelectedRouter)
    }

    @MainActor
    @Test func cancelledOldTestCannotClearANewerOwnerMarker() async throws {
        let testGate = CommandGate<Int>()
        let (model, _) = makeLiveCommandModel(
            testOperation: { _, _, _ in
                await testGate.suspend(recording: 1)
            }
        )
        model.controllerSession.state = .failed("offline")

        model.testSelectedRouter()
        await testGate.waitForCount(1)
        let oldTask = try #require(model.refreshTask)
        model.cancelControllerOperationTasks()
        #expect(oldTask.isCancelled)
        #expect(model.selectedRouterTestOperationID == nil)

        model.testSelectedRouter()
        await testGate.waitForCount(2)
        let newOwnerID = try #require(model.selectedRouterTestOperationID)
        let newTask = try #require(model.refreshTask)

        await testGate.releaseFirst()
        await oldTask.value
        #expect(model.selectedRouterTestOperationID == newOwnerID)
        #expect(model.isTestingSelectedRouter)
        #expect(!newTask.isCancelled)

        await testGate.releaseFirst()
        await newTask.value
        #expect(model.refreshTask == nil)
        #expect(model.selectedRouterTestOperationID == nil)
        #expect(!model.isTestingSelectedRouter)
    }
}

private struct RefreshLaneCall: Equatable, Sendable {
    var lane: SessionRefreshLane
    var manual: Bool
}

private struct RuleMutationCall: Equatable, Sendable {
    var index: Int
    var disabled: Bool
}

private actor RuleMutationRecorder {
    private(set) var calls: [RuleMutationCall] = []

    func record(index: Int, disabled: Bool) {
        calls.append(RuleMutationCall(index: index, disabled: disabled))
    }
}

private actor FailingMihomoTestScript {
    private(set) var requestCount = 0

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        _ = request
        requestCount += 1
        throw MihomoClientError.connectionFailure(.connectionRefused)
    }
}

private actor CommandGate<Value: Sendable> {
    private(set) var values: [Value] = []
    private var blockedOperations: [CheckedContinuation<Void, Never>] = []
    private var countWaiters: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []

    func suspend(recording value: Value) async {
        await withCheckedContinuation { continuation in
            values.append(value)
            blockedOperations.append(continuation)
            resumeSatisfiedCountWaiters()
        }
    }

    func waitForCount(_ count: Int) async {
        guard values.count < count else { return }
        await withCheckedContinuation { continuation in
            countWaiters.append((count, continuation))
        }
    }

    func releaseFirst() {
        guard !blockedOperations.isEmpty else { return }
        blockedOperations.removeFirst().resume()
    }

    func releaseAll() {
        let continuations = blockedOperations
        blockedOperations.removeAll(keepingCapacity: false)
        continuations.forEach { $0.resume() }
    }

    private func resumeSatisfiedCountWaiters() {
        var pending: [
            (count: Int, continuation: CheckedContinuation<Void, Never>)
        ] = []
        for waiter in countWaiters {
            if values.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                pending.append(waiter)
            }
        }
        countWaiters = pending
    }
}

private enum OfflineCommandBoundaryFailure: Error {
    case unexpectedRuleCommand
    case unexpectedConfigUpdate
    case unexpectedConfigSnapshot
}

@MainActor
func commandScope(for model: AppModel) -> LiveCommandScope {
    guard let scope = LiveCommandScope(
        controllerID: model.selectedRouterID,
        generation: model.controllerSessionPresentation.generation
    ) else {
        preconditionFailure("A command test requires a selected controller")
    }
    return scope
}

@MainActor
private func makeLiveCommandModel(
    dashboard: DashboardSnapshot = makeDashboard(),
    controllerKind: ControllerKind = .mihomoCompatible,
    testOperation: SelectedRouterTestOperation? = nil,
    refreshLaneOperation: ImmediateSessionRefreshLaneOperation? = nil,
    manualRestartOperation: ManualRefreshStreamRestartOperation? = nil,
    ruleOperation: MihomoRuleDisableOperation? = nil,
    configUpdateOperation: MihomoConfigUpdateOperation? = nil,
    configSnapshotOperation: MihomoConfigSnapshotOperation? = nil
) -> (AppModel, RouterProfile) {
    let profile = RouterProfile(
        displayName: "Offline Controller",
        host: "offline.invalid",
        port: 12_345,
        controllerKind: controllerKind
    )
    let model = AppModel(
        routers: [profile],
        selectedRouterID: profile.id,
        connectionState: .connected(version: "offline-test"),
        dashboard: dashboard,
        profileStore: InMemoryRouterProfileStore(),
        secretStore: InMemorySecretStore(),
        mihomoConfigUpdateOperation: configUpdateOperation ?? { _, _, _ in
            throw OfflineCommandBoundaryFailure.unexpectedConfigUpdate
        },
        mihomoConfigSnapshotOperation: configSnapshotOperation ?? { _, _ in
            throw OfflineCommandBoundaryFailure.unexpectedConfigSnapshot
        },
        mihomoRuleDisableOperation: ruleOperation ?? { _, _, _, _ in
            throw OfflineCommandBoundaryFailure.unexpectedRuleCommand
        },
        selectedRouterTestOperation: testOperation,
        immediateSessionRefreshLaneOperation: refreshLaneOperation ?? { _, _, _, _ in },
        manualRefreshStreamRestartOperation: manualRestartOperation ?? { _, _ in }
    )
    model.controllerSession.begin(controllerID: profile.id)
    model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
    model.controllerSession.state = .live
    model.activeSessionControllerKind = controllerKind
    return (model, profile)
}

private func makeSleepingCommandTask() -> Task<Void, Never> {
    Task<Void, Never> {
        _ = try? await Task.sleep(for: .seconds(60))
    }
}

private func makeDashboard(
    groups: [ProxyGroupViewState] = [],
    rules: [RuleViewState] = []
) -> DashboardSnapshot {
    DashboardSnapshot(
        versionLabel: "offline-test",
        mode: "Rule",
        traffic: TrafficSnapshot(upload: 0, download: 0),
        groups: groups,
        connections: [],
        rules: rules
    )
}

private func makeRule(
    id: String,
    index: Int?,
    payload: String
) -> RuleViewState {
    RuleViewState(
        id: id,
        index: index,
        type: "DOMAIN",
        payload: payload,
        proxy: "Proxy",
        disabled: false,
        hasMutableExtra: true
    )
}
