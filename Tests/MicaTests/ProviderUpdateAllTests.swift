import Foundation
import MicaCore
import Testing
@testable import Mica

struct ProviderUpdateAllTests {
    @MainActor
    @Test func updateAllPreservesSourceOrderSkipsReadOnlyProvidersAndRefreshesOnce() async throws {
        let providers = makeProviders()
        let harness = ProviderUpdateHarness(failingProviderNames: ["Rule Remote"])
        let (model, profile) = makeModel(providers: providers, harness: harness)

        model.updateAllProviders()
        let task = try #require(model.providerTask)
        await task.value

        let record = await harness.record
        #expect(record.updateOrder == ["Rule Remote", "Proxy Remote"])
        #expect(record.snapshotCount == 1)

        let progress = try #require(model.providerUpdateAllProgress)
        #expect(progress.current == nil)
        #expect(progress.completed == 2)
        #expect(progress.total == 2)
        #expect(progress.succeeded == 1)
        #expect(progress.failed == 1)
        #expect(progress.failures.map(\.target.name) == ["Rule Remote"])
        #expect(!progress.isRunning)
        #expect(Set(model.providerUpdateFailures.keys) == ["rule:Rule Remote"])
        #expect(model.operationState?.kind == .partial)

        let session = model.trialSession(for: profile)
        #expect(session.lastCommandAction == .providerUpdateAll)
        #expect(session.lastCommandStatus == .partial)

        let refreshedProxy = model.providersCatalog.providers.first { $0.name == "Proxy Remote" }
        #expect(refreshedProxy?.testURL == "https://probe.example.test/generate_204")
        #expect(refreshedProxy?.subscriptionInfo == .object(["remaining": .number(2048)]))
    }

    @MainActor
    @Test func updateAllPublishesSuccessAndErrorOutcomesToOperationStateAndHistory() async throws {
        let providers = makeProviders().filter(\.updatable)

        let successHarness = ProviderUpdateHarness()
        let (successModel, successProfile) = makeModel(
            providers: providers,
            harness: successHarness
        )
        successModel.updateAllProviders()
        let successTask = try #require(successModel.providerTask)
        await successTask.value

        #expect(successModel.operationState?.kind == .success)
        #expect(successModel.trialSession(for: successProfile).lastCommandStatus == .success)
        #expect(successModel.providerUpdateAllProgress?.succeeded == 2)
        #expect(successModel.providerUpdateAllProgress?.failed == 0)

        let errorHarness = ProviderUpdateHarness(
            failingProviderNames: Set(providers.map(\.name))
        )
        let (errorModel, errorProfile) = makeModel(
            providers: providers,
            harness: errorHarness
        )
        errorModel.updateAllProviders()
        let errorTask = try #require(errorModel.providerTask)
        await errorTask.value

        #expect(errorModel.operationState?.kind == .error)
        #expect(errorModel.trialSession(for: errorProfile).lastCommandStatus == .failed)
        #expect(errorModel.providerUpdateAllProgress?.succeeded == 0)
        #expect(errorModel.providerUpdateAllProgress?.failed == 2)
        #expect(errorModel.providerUpdateAllProgress?.failures.count == 2)
    }

    @MainActor
    @Test func updateAllRejectsPausedBusyAndUnsupportedSessionsWithoutStartingWork() async {
        let providers = makeProviders()

        let pausedHarness = ProviderUpdateHarness()
        let (pausedModel, _) = makeModel(providers: providers, harness: pausedHarness)
        pausedModel.setPresentationPaused(true)
        pausedModel.updateAllProviders()
        #expect(pausedModel.providerTask == nil)
        #expect(pausedModel.operationState?.kind == .partial)
        #expect(await pausedHarness.record.updateOrder.isEmpty)

        let busyHarness = ProviderUpdateHarness()
        let (busyModel, _) = makeModel(providers: providers, harness: busyHarness)
        busyModel.closingAllConnections = true
        busyModel.updateAllProviders()
        #expect(busyModel.providerTask == nil)
        #expect(busyModel.closingAllConnections)
        #expect(busyModel.operationState?.kind == .partial)
        #expect(await busyHarness.record.updateOrder.isEmpty)

        let unsupportedHarness = ProviderUpdateHarness()
        let (unsupportedModel, _) = makeModel(
            providers: providers,
            harness: unsupportedHarness,
            controllerKind: .surgeCompatible
        )
        unsupportedModel.updateAllProviders()
        #expect(unsupportedModel.providerTask == nil)
        #expect(unsupportedModel.operationState?.kind != .working)
        #expect(await unsupportedHarness.record.updateOrder.isEmpty)
    }

    @MainActor
    @Test func individualProviderActionsCannotCancelOrRaceAnActiveBatch() async throws {
        let providers = makeProviders().filter(\.updatable)
        let harness = ProviderUpdateHarness(blockFirstUpdate: true)
        let (model, _) = makeModel(providers: providers, harness: harness)

        model.updateAllProviders()
        let batchTask = try #require(model.providerTask)
        await harness.waitForFirstUpdate()

        model.updateProxyProvider(providers[1])

        #expect(!batchTask.isCancelled)
        #expect(model.providerUpdateAllProgress?.isRunning == true)
        #expect(model.operationState?.kind == .partial)
        #expect(await harness.record.updateOrder == [providers[0].name])

        await harness.releaseFirstUpdate()
        await batchTask.value

        #expect(await harness.record.updateOrder == providers.map(\.name))
        #expect(await harness.record.snapshotCount == 1)
    }

    @MainActor
    @Test func controllerChangeCancelsAndResetsBatchWithoutStalePublication() async throws {
        let providers = makeProviders().filter(\.updatable)
        let harness = ProviderUpdateHarness(blockFirstUpdate: true)
        let (model, _) = makeModel(providers: providers, harness: harness)

        model.updateAllProviders()
        let batchTask = try #require(model.providerTask)
        await harness.waitForFirstUpdate()
        model.providerUpdateFailures[providers[0].id] = "stale failure"

        model.leaveLiveSession()

        #expect(batchTask.isCancelled)
        #expect(model.providerTask == nil)
        #expect(model.providerUpdateAllProgress == nil)
        #expect(model.providerUpdateFailures.isEmpty)
        #expect(model.updatingProviderName == nil)
        #expect(model.operationState == nil)

        await harness.releaseFirstUpdate()
        await batchTask.value

        #expect(await harness.record.snapshotCount == 0)
        #expect(model.providerUpdateAllProgress == nil)
        #expect(model.providerUpdateFailures.isEmpty)
    }
}

private actor ProviderUpdateHarness {
    struct Record: Equatable, Sendable {
        var updateOrder: [String]
        var snapshotCount: Int
    }

    struct PlannedFailure: Error, Sendable {}

    private let failingProviderNames: Set<String>
    private let blockFirstUpdate: Bool
    private var updateOrder: [String] = []
    private var snapshotCount = 0
    private var firstUpdateStarted = false
    private var firstUpdateWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstUpdateRelease: CheckedContinuation<Void, Never>?

    init(
        failingProviderNames: Set<String> = [],
        blockFirstUpdate: Bool = false
    ) {
        self.failingProviderNames = failingProviderNames
        self.blockFirstUpdate = blockFirstUpdate
    }

    var record: Record {
        Record(updateOrder: updateOrder, snapshotCount: snapshotCount)
    }

    func update(_ provider: ProxyProviderViewState) async throws {
        updateOrder.append(provider.name)

        if blockFirstUpdate, updateOrder.count == 1 {
            await withCheckedContinuation { continuation in
                firstUpdateRelease = continuation
                firstUpdateStarted = true
                firstUpdateWaiters.forEach { $0.resume() }
                firstUpdateWaiters.removeAll(keepingCapacity: false)
            }
        }

        if failingProviderNames.contains(provider.name) {
            throw PlannedFailure()
        }
    }

    func captureSnapshots() -> AppModel.ProviderSnapshotResults {
        snapshotCount += 1
        return (
            proxy: .success(
                ProxyProvidersResponse(
                    providers: [
                        "Proxy Remote": ProxyProviderSnapshot(
                            name: "Proxy Remote",
                            type: "Proxy",
                            vehicleType: "HTTP",
                            testURL: "https://probe.example.test/generate_204",
                            subscriptionInfo: .object(["remaining": .number(2048)]),
                            updatable: true,
                            proxyCount: 3
                        ),
                    ],
                    providerOrder: ["Proxy Remote"]
                )
            ),
            rule: .success(
                RuleProvidersResponse(
                    providers: [
                        "Rule Remote": RuleProviderSnapshot(
                            name: "Rule Remote",
                            type: "Rule",
                            behavior: "domain",
                            vehicleType: "HTTP",
                            updatable: true,
                            ruleCount: 4
                        ),
                    ],
                    providerOrder: ["Rule Remote"]
                )
            )
        )
    }

    func waitForFirstUpdate() async {
        guard !firstUpdateStarted else { return }
        await withCheckedContinuation { continuation in
            firstUpdateWaiters.append(continuation)
        }
    }

    func releaseFirstUpdate() {
        firstUpdateRelease?.resume()
        firstUpdateRelease = nil
    }
}

@MainActor
private func makeModel(
    providers: [ProxyProviderViewState],
    harness: ProviderUpdateHarness,
    controllerKind: ControllerKind = .mihomoCompatible
) -> (AppModel, RouterProfile) {
    let profile = RouterProfile(
        displayName: "Offline Controller",
        host: "offline.invalid",
        port: 12_345,
        controllerKind: controllerKind
    )
    var dashboard = DashboardSnapshot.empty
    dashboard.providers = providers
    let model = AppModel(
        routers: [profile],
        selectedRouterID: profile.id,
        connectionState: .connected(version: "offline-test"),
        dashboard: dashboard,
        profileStore: InMemoryRouterProfileStore(),
        secretStore: InMemorySecretStore(),
        providerUpdateOperation: { _, _, provider in
            try await harness.update(provider)
        },
        providerSnapshotOperation: { _, _ in
            await harness.captureSnapshots()
        }
    )
    model.controllerSession.begin(controllerID: profile.id)
    model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
    model.controllerSession.state = .live
    model.activeSessionControllerKind = controllerKind
    return (model, profile)
}

private func makeProviders() -> [ProxyProviderViewState] {
    [
        ProxyProviderViewState(
            kind: .rule,
            name: "Rule Remote",
            type: "Rule",
            vehicleType: "HTTP",
            updatable: true,
            itemCount: 4
        ),
        ProxyProviderViewState(
            kind: .proxy,
            name: "Proxy Local",
            type: "Proxy",
            vehicleType: "File",
            updatable: false,
            itemCount: 2
        ),
        ProxyProviderViewState(
            kind: .proxy,
            name: "Proxy Remote",
            type: "Proxy",
            vehicleType: "HTTP",
            updatable: true,
            testURL: "https://old.example.test/generate_204",
            subscriptionInfo: .object(["remaining": .number(1024)]),
            itemCount: 3
        ),
    ]
}
