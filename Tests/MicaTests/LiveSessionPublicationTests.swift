import Foundation
import MicaCore
import Testing
@testable import Mica

private actor PublicationSleepGate {
    struct Call: Equatable, Sendable {
        var domain: LiveSessionPublicationDomain
        var cadence: Duration
    }

    private var calls: [Call] = []
    private var continuations: [
        LiveSessionPublicationDomain: [CheckedContinuation<Void, Never>]
    ] = [:]

    func sleep(domain: LiveSessionPublicationDomain, cadence: Duration) async {
        calls.append(Call(domain: domain, cadence: cadence))
        await withCheckedContinuation { continuation in
            continuations[domain, default: []].append(continuation)
        }
    }

    func recordedCalls() -> [Call] {
        calls
    }

    func release(_ domain: LiveSessionPublicationDomain) {
        guard var pending = continuations[domain], !pending.isEmpty else { return }
        let continuation = pending.removeFirst()
        continuations[domain] = pending
        continuation.resume()
    }
}

struct LiveSessionPublicationTests {
    @Test func publicationCadencesMatchTheVisibleDomainBudgets() {
        #expect(LiveSessionPublicationDomain.logs.cadence == .milliseconds(200))
        #expect(LiveSessionPublicationDomain.traffic.cadence == .milliseconds(250))
        #expect(LiveSessionPublicationDomain.connections.cadence == .milliseconds(500))
        #expect(LiveSessionPublicationDomain.memory.cadence == .seconds(1))
    }

    @Test func destinationsObserveOnlyTheirExpensiveLiveDomains() {
        #expect(Set(LiveSessionVisibleDestination.overview.observedDomains) == Set([
            .traffic,
            .connections,
            .memory,
        ]))
        #expect(LiveSessionVisibleDestination.connections.observedDomains == [.connections])
        #expect(LiveSessionVisibleDestination.logs.observedDomains == [.logs])
        #expect(LiveSessionVisibleDestination.other.observedDomains.isEmpty)
    }

    @Test func windowDemandRegistryUnionsDestinationsAndUnregistersOnlyItsToken() throws {
        var coordinator = LiveSessionPublicationCoordinator()
        let generation = UUID()
        let overviewWindow = LiveSessionWindowDemandID()
        let secondOverviewWindow = LiveSessionWindowDemandID()
        let detailWindow = LiveSessionWindowDemandID()
        let restoredOverviewWindow = LiveSessionWindowDemandID(
            rawValue: overviewWindow.rawValue
        )
        let overviewDomains = Set(LiveSessionVisibleDestination.overview.observedDomains)
        coordinator.begin(generation: generation)
        #expect(restoredOverviewWindow == overviewWindow)

        let overviewChange = coordinator.registerWindowDemand(
            overviewWindow,
            destination: .overview
        )
        let overview = try #require(overviewChange)
        #expect(overview.observedDomains == overviewDomains)
        #expect(overview.newlyObservedDomains == overviewDomains)

        let logsChange = coordinator.registerWindowDemand(
            detailWindow,
            destination: .logs
        )
        let withLogs = try #require(logsChange)
        #expect(withLogs.observedDomains == Set(LiveSessionPublicationDomain.allCases))
        #expect(withLogs.newlyObservedDomains == [.logs])

        let connectionsChange = coordinator.updateWindowDemand(
            detailWindow,
            destination: .connections
        )
        let overviewAndConnections = try #require(connectionsChange)
        #expect(overviewAndConnections.observedDomains == overviewDomains)
        #expect(overviewAndConnections.newlyObservedDomains.isEmpty)

        let unchangedRegistration = coordinator.registerWindowDemand(
            secondOverviewWindow,
            destination: .overview
        )
        #expect(unchangedRegistration == nil)
        #expect(coordinator.windowDestinations.count == 3)
        let unchangedUnregister = coordinator.unregisterWindowDemand(
            restoredOverviewWindow
        )
        #expect(unchangedUnregister == nil)
        #expect(coordinator.windowDestinations[overviewWindow] == nil)
        #expect(coordinator.windowDestinations[secondOverviewWindow] == .overview)
        #expect(coordinator.windowDestinations[detailWindow] == .connections)
        #expect(coordinator.observedDomains == overviewDomains)
    }

    @Test func demandRevisionResetsPerGenerationWithoutDroppingWindowRegistry() throws {
        var coordinator = LiveSessionPublicationCoordinator()
        let windowID = LiveSessionWindowDemandID()
        let firstGeneration = UUID()
        _ = coordinator.registerWindowDemand(windowID, destination: .logs)
        coordinator.begin(generation: firstGeneration)

        let firstIdentity = LiveSessionRuntimeIdentity(
            controllerID: UUID(),
            generation: firstGeneration
        )
        let firstDemand = coordinator.nextPresentationDemand(
            identity: firstIdentity,
            presentationPaused: false,
            logsPresentationPaused: false,
            baselinePublicationRequired: false
        )
        let first = try #require(firstDemand)
        let secondDemand = coordinator.nextPresentationDemand(
            identity: firstIdentity,
            presentationPaused: true,
            logsPresentationPaused: true,
            baselinePublicationRequired: true
        )
        let second = try #require(secondDemand)
        #expect(first.revision == 1)
        #expect(second.revision == 2)
        #expect(second.observedDomains == [.logs])

        coordinator.begin(generation: firstGeneration)
        let sameGenerationDemand = coordinator.nextPresentationDemand(
            identity: firstIdentity,
            presentationPaused: false,
            logsPresentationPaused: false,
            baselinePublicationRequired: false
        )
        let sameGeneration = try #require(sameGenerationDemand)
        #expect(sameGeneration.revision == 3)

        let nextGeneration = UUID()
        coordinator.begin(generation: nextGeneration)
        let nextDemand = coordinator.nextPresentationDemand(
            identity: LiveSessionRuntimeIdentity(
                controllerID: firstIdentity.controllerID,
                generation: nextGeneration
            ),
            presentationPaused: false,
            logsPresentationPaused: false,
            baselinePublicationRequired: false
        )
        let next = try #require(nextDemand)
        #expect(next.revision == 1)
        #expect(next.observedDomains == [.logs])
        #expect(coordinator.windowDestinations[windowID] == .logs)

        coordinator.invalidate()
        #expect(coordinator.demandRevision == 0)
        #expect(coordinator.windowDestinations[windowID] == .logs)
    }

    @Test func newlyVisibleFlushRequiresCurrentPauseAndBaselineGates() {
        let identity = LiveSessionRuntimeIdentity(
            controllerID: UUID(),
            generation: UUID()
        )
        let domains: Set<LiveSessionPublicationDomain> = [.logs, .traffic]
        let active = LiveSessionPresentationDemand(
            identity: identity,
            revision: 1,
            observedDomains: domains,
            presentationPaused: false,
            logsPresentationPaused: false,
            baselinePublicationRequired: false
        )
        #expect(active.permitsImmediateVisibilityFlush(.logs))
        #expect(active.permitsImmediateVisibilityFlush(.traffic))

        let logsPaused = LiveSessionPresentationDemand(
            identity: identity,
            revision: 2,
            observedDomains: domains,
            presentationPaused: false,
            logsPresentationPaused: true,
            baselinePublicationRequired: false
        )
        #expect(!logsPaused.permitsImmediateVisibilityFlush(.logs))
        #expect(logsPaused.permitsImmediateVisibilityFlush(.traffic))

        let globallyPaused = LiveSessionPresentationDemand(
            identity: identity,
            revision: 3,
            observedDomains: domains,
            presentationPaused: true,
            logsPresentationPaused: false,
            baselinePublicationRequired: false
        )
        #expect(!globallyPaused.permitsImmediateVisibilityFlush(.logs))
        #expect(!globallyPaused.permitsImmediateVisibilityFlush(.traffic))

        let baseline = LiveSessionPresentationDemand(
            identity: identity,
            revision: 4,
            observedDomains: domains,
            presentationPaused: false,
            logsPresentationPaused: false,
            baselinePublicationRequired: true
        )
        #expect(!baseline.permitsImmediateVisibilityFlush(.logs))
        #expect(!baseline.permitsImmediateVisibilityFlush(.traffic))
    }

    @Test func providerProjectionPreservesTestURLAndSubscriptionInformation() {
        var dashboard = DashboardSnapshot.empty
        dashboard.replaceProviders(
            with: ProxyProvidersResponse(
                providers: [
                    "Remote": ProxyProviderSnapshot(
                        name: "Remote",
                        type: "Proxy",
                        vehicleType: "HTTP",
                        testURL: "https://www.gstatic.com/generate_204",
                        subscriptionInfo: .object([
                            "total": .number(1_073_741_824),
                            "expire": .number(1_800_000_000),
                        ]),
                        proxyCount: 12
                    ),
                ],
                providerOrder: ["Remote"]
            )
        )

        let provider = dashboard.providers.first
        #expect(provider?.testURL == "https://www.gstatic.com/generate_204")
        #expect(provider?.subscriptionInfo == .object([
            "total": .number(1_073_741_824),
            "expire": .number(1_800_000_000),
        ]))
        #expect(provider?.subscriptionInfoText?.contains("1073741824") == true)
        #expect(provider?.subscriptionInfoText?.contains("1800000000") == true)
    }

    @MainActor
    @Test func namedDashboardMutationPublishesOnlyRequestedCatalogs() {
        let model = makeModel()
        let rule = RuleViewState(
            id: "rule-1",
            type: "DOMAIN",
            payload: "example.com",
            proxy: "Proxy"
        )
        let provider = ProxyProviderViewState(
            kind: .proxy,
            name: "Provider",
            type: "Proxy",
            itemCount: 1
        )
        let initialMetadata = model.controllerMetadata
        let initialGroups = model.policyGroupCatalog
        let initialGroupRevision = model.policyGroupCatalogRevision
        let initialConnections = model.connectionsCatalog
        let initialLogs = model.logsCatalog

        model.mutateSessionDashboard(publishing: [.routing, .insight]) { dashboard in
            dashboard.rules = [rule]
            dashboard.providers = [provider]
            dashboard.insight = InsightSummarySnapshot(snapshot: dashboard)
        }

        #expect(model.controllerMetadata == initialMetadata)
        #expect(model.policyGroupCatalog == initialGroups)
        #expect(model.policyGroupCatalogRevision == initialGroupRevision)
        #expect(model.connectionsCatalog == initialConnections)
        #expect(model.logsCatalog == initialLogs)
        #expect(model.routingCatalog == RoutingCatalogSnapshot(dashboard: model.dashboard))
        #expect(model.insightCatalog == model.dashboard.insight)
        #expect(model.insightCatalog.ruleCount == 1)
        #expect(model.insightCatalog.providerCount == 1)
    }

    @MainActor
    @Test func policyCatalogRevisionChangesOnlyWithPublishedCatalogData() {
        let model = makeModel()
        let initialRevision = model.policyGroupCatalogRevision
        let group = ProxyGroupViewState(
            id: "Auto",
            type: "URLTest",
            selected: "Tokyo",
            options: ["Tokyo"]
        )

        model.mutateSessionDashboard(publishing: [.policyGroups]) { dashboard in
            dashboard.groups = [group]
        }
        #expect(model.policyGroupCatalogRevision == initialRevision &+ 1)

        model.mutateSessionDashboard(publishing: [.policyGroups]) { dashboard in
            dashboard.groups = [group]
        }
        #expect(model.policyGroupCatalogRevision == initialRevision &+ 1)
    }

    @MainActor
    @Test func visibleLogBurstsUseOneNonRestartingFiveHertzPublisher() async {
        let gate = PublicationSleepGate()
        let (model, _) = makeLiveModel(gate: gate)
        model.registerLiveSessionWindowDemand(
            LiveSessionWindowDemandID(),
            destination: .logs
        )

        model.recordControllerLog(LogMessage(type: "info", payload: "one"))
        model.recordControllerLog(LogMessage(type: "info", payload: "two"))
        model.recordControllerLog(LogMessage(type: "info", payload: "three"))

        for _ in 0 ..< 100 where await gate.recordedCalls().isEmpty {
            await Task.yield()
        }
        let calls = await gate.recordedCalls()
        #expect(calls == [.init(domain: .logs, cadence: .milliseconds(200))])
        #expect(model.logsCatalog.entries.isEmpty)

        await gate.release(.logs)
        for _ in 0 ..< 100 where model.logsCatalog.entries.count != 3 {
            await Task.yield()
        }

        #expect(model.logsCatalog.entries.map(\.message.payload) == ["one", "two", "three"])
        #expect(await gate.recordedCalls().count == 1)
        model.leaveLiveSession()
    }

    @MainActor
    @Test func actorBackedLogBurstUsesOneMainActorPublication() async throws {
        let gate = PublicationSleepGate()
        let (model, profile) = makeLiveModel(gate: gate)
        model.liveStreamRequested = true
        model.registerLiveSessionWindowDemand(
            LiveSessionWindowDemandID(),
            destination: .logs
        )
        model.installLiveSessionRuntime(
            for: profile,
            generation: model.controllerSession.generation
        )
        let runtime = try #require(model.liveSessionRuntime)
        let identity = try #require(model.liveSessionRuntimeIdentity)

        for index in 0..<1_000 {
            let scheduled = await runtime.ingestLog(
                LogMessage(type: "info", payload: "actor-\(index)"),
                source: .mihomoWebSocket,
                id: "actor-\(index)"
            )
            if !scheduled.isEmpty {
                model.scheduleLiveSessionRuntimePublications(
                    scheduled,
                    runtime: runtime,
                    identity: identity
                )
            }
        }

        for _ in 0..<100 where await gate.recordedCalls().isEmpty {
            await Task.yield()
        }
        #expect(await gate.recordedCalls() == [
            .init(domain: .logs, cadence: .milliseconds(200)),
        ])
        #expect(model.logsCatalog.entries.isEmpty)

        await gate.release(.logs)
        for _ in 0..<100 where model.logsCatalog.entries.count != 1_000 {
            await Task.yield()
        }
        #expect(model.logsCatalog.entries.first?.id == "actor-0")
        #expect(model.logsCatalog.entries.last?.id == "actor-999")
        model.leaveLiveSession()
    }

    @MainActor
    @Test func runtimeInstallationUsesCurrentCompleteDemandBeforeIngestion() async throws {
        let gate = PublicationSleepGate()
        let (model, profile) = makeLiveModel(gate: gate)
        let windowID = LiveSessionWindowDemandID()
        model.liveStreamRequested = true
        model.registerLiveSessionWindowDemand(windowID, destination: .logs)
        model.dashboardSessionControls.setPresentationPaused(true)
        model.dashboardSessionControls.setLogsPresentationPaused(true)
        model.controllerSession.beginReconnect(message: "reconnecting")

        model.installLiveSessionRuntime(
            for: profile,
            generation: model.controllerSession.generation
        )

        let runtime = try #require(model.liveSessionRuntime)
        let identity = try #require(model.liveSessionRuntimeIdentity)
        let demand = await runtime.currentPresentationDemand()
        #expect(demand.identity == identity)
        #expect(demand.revision == 1)
        #expect(demand.observedDomains == [.logs])
        #expect(demand.presentationPaused)
        #expect(demand.logsPresentationPaused)
        #expect(demand.baselinePublicationRequired)
        model.leaveLiveSession()
    }

    @MainActor
    @Test func dualWindowUnionUsesOneGenerationAndOneRuntime() async throws {
        let gate = PublicationSleepGate()
        let (model, profile) = makeLiveModel(gate: gate)
        let overviewWindow = LiveSessionWindowDemandID()
        let logsWindow = LiveSessionWindowDemandID()
        let generation = model.controllerSession.generation
        model.liveStreamRequested = true
        model.installSessionRefreshCoordinator(generation: generation)
        let refreshCoordinator = try #require(model.sessionRefreshCoordinator)
        model.registerLiveSessionWindowDemand(
            overviewWindow,
            destination: .overview
        )
        model.registerLiveSessionWindowDemand(logsWindow, destination: .logs)
        model.installLiveSessionRuntime(for: profile, generation: generation)

        let runtime = try #require(model.liveSessionRuntime)
        let identity = try #require(model.liveSessionRuntimeIdentity)
        let initialDemand = await runtime.currentPresentationDemand()
        #expect(initialDemand.observedDomains == Set(LiveSessionPublicationDomain.allCases))

        model.unregisterLiveSessionWindowDemand(logsWindow)
        let overviewDomains = Set(LiveSessionVisibleDestination.overview.observedDomains)
        for _ in 0..<100 {
            let demand = await runtime.currentPresentationDemand()
            if demand.observedDomains == overviewDomains {
                break
            }
            await Task.yield()
        }

        let finalDemand = await runtime.currentPresentationDemand()
        #expect(finalDemand.observedDomains == overviewDomains)
        #expect(model.liveSessionRuntime === runtime)
        #expect(model.liveSessionRuntimeIdentity == identity)
        #expect(model.sessionRefreshCoordinator === refreshCoordinator)
        #expect(model.controllerSession.generation == generation)
        #expect(
            model.sessionPresentationCoordinator.windowDestinations[overviewWindow]
                == .overview
        )
        #expect(model.sessionPresentationCoordinator.windowDestinations[logsWindow] == nil)
        model.leaveLiveSession()
    }

    @MainActor
    @Test func endedGenerationRejectsPendingActorPublication() async throws {
        let gate = PublicationSleepGate()
        let (model, profile) = makeLiveModel(gate: gate)
        model.liveStreamRequested = true
        model.registerLiveSessionWindowDemand(
            LiveSessionWindowDemandID(),
            destination: .logs
        )
        model.installLiveSessionRuntime(
            for: profile,
            generation: model.controllerSession.generation
        )
        let runtime = try #require(model.liveSessionRuntime)
        let identity = try #require(model.liveSessionRuntimeIdentity)
        let scheduled = await runtime.ingestLog(
            LogMessage(type: "warning", payload: "stale"),
            source: .mihomoWebSocket,
            id: "stale"
        )
        model.scheduleLiveSessionRuntimePublications(
            scheduled,
            runtime: runtime,
            identity: identity
        )

        for _ in 0..<100 where await gate.recordedCalls().isEmpty {
            await Task.yield()
        }
        model.leaveLiveSession()
        await gate.release(.logs)
        await Task.yield()

        #expect(model.logsCatalog == .empty)
        #expect(model.controllerSession.controllerID == nil)
        #expect(model.liveSessionRuntime == nil)
    }

    @MainActor
    @Test func olderRuntimePublicationCannotOverwriteNewerVisibleState() throws {
        let gate = PublicationSleepGate()
        let (model, profile) = makeLiveModel(gate: gate)
        model.liveStreamRequested = true
        model.registerLiveSessionWindowDemand(
            LiveSessionWindowDemandID(),
            destination: .overview
        )
        model.installLiveSessionRuntime(
            for: profile,
            generation: model.controllerSession.generation
        )
        let runtime = try #require(model.liveSessionRuntime)
        let identity = try #require(model.liveSessionRuntimeIdentity)

        var newerTimeline = TrafficTimeline()
        newerTimeline.append(
            upload: 200,
            download: 400,
            receivedAt: Date(timeIntervalSince1970: 2)
        )
        model.applyLiveSessionRuntimePublication(
            LiveSessionRuntimePublication(
                identity: identity,
                domain: .traffic,
                revision: 2,
                receivedAt: Date(timeIntervalSince1970: 2),
                observation: LiveSessionObservationDelta(),
                payload: .traffic(
                    LiveSessionTrafficPublication(
                        timeline: newerTimeline,
                        latestRate: TrafficSnapshot(upload: 200, download: 400),
                        singBoxStatus: nil
                    )
                )
            ),
            runtime: runtime
        )

        var olderTimeline = TrafficTimeline()
        olderTimeline.append(
            upload: 100,
            download: 150,
            receivedAt: Date(timeIntervalSince1970: 1)
        )
        model.applyLiveSessionRuntimePublication(
            LiveSessionRuntimePublication(
                identity: identity,
                domain: .traffic,
                revision: 1,
                receivedAt: Date(timeIntervalSince1970: 1),
                observation: LiveSessionObservationDelta(),
                payload: .traffic(
                    LiveSessionTrafficPublication(
                        timeline: olderTimeline,
                        latestRate: TrafficSnapshot(upload: 100, download: 150),
                        singBoxStatus: nil
                    )
                )
            ),
            runtime: runtime
        )

        #expect(model.liveTrafficRate == TrafficSnapshot(upload: 200, download: 400))
        #expect(model.trafficTimeline.samples.last?.upload == 200)
        model.leaveLiveSession()
    }

    @MainActor
    @Test func hiddenLogsRetainRawDataAndEnteringLogsFlushesImmediately() async {
        let gate = PublicationSleepGate()
        let (model, _) = makeLiveModel(gate: gate)
        let windowID = LiveSessionWindowDemandID()
        model.registerLiveSessionWindowDemand(windowID, destination: .other)

        model.recordControllerLog(LogMessage(type: "warning", payload: "retained"))
        await Task.yield()

        #expect(model.logsCatalog.entries.isEmpty)
        #expect(model.controllerSession.logBuffer.entries.count == 1)
        #expect(await gate.recordedCalls().isEmpty)

        model.updateLiveSessionWindowDemand(windowID, destination: .logs)

        #expect(model.logsCatalog.entries.map(\.message.payload) == ["retained"])
        #expect(await gate.recordedCalls().isEmpty)
        model.leaveLiveSession()
    }

    @MainActor
    @Test func actorNewlyVisibleFlushWaitsForGlobalPauseToClear() async throws {
        let gate = PublicationSleepGate()
        let (model, profile) = makeLiveModel(gate: gate)
        let windowID = LiveSessionWindowDemandID()
        model.liveStreamRequested = true
        model.dashboardSessionControls.setPresentationPaused(true)
        model.registerLiveSessionWindowDemand(windowID, destination: .other)
        model.installLiveSessionRuntime(
            for: profile,
            generation: model.controllerSession.generation
        )
        let runtime = try #require(model.liveSessionRuntime)

        #expect(
            await runtime.ingestLog(
                LogMessage(type: "info", payload: "paused-retained"),
                source: .mihomoWebSocket,
                id: "paused-retained"
            ).isEmpty
        )
        model.updateLiveSessionWindowDemand(windowID, destination: .logs)
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(model.logsCatalog.entries.isEmpty)
        #expect(await gate.recordedCalls().isEmpty)

        model.dashboardSessionControls.setPresentationPaused(false)
        model.updateLiveSessionRuntimePresentationDemand(forceVisible: true)
        for _ in 0..<100 where model.logsCatalog.entries.isEmpty {
            await Task.yield()
        }

        #expect(model.logsCatalog.entries.map(\.id) == ["paused-retained"])
        #expect(await gate.recordedCalls().isEmpty)
        model.leaveLiveSession()
    }

    @MainActor
    @Test func actorVisibilityReentryFlushesPreviouslyStagedLogs() async throws {
        let gate = PublicationSleepGate()
        let (model, profile) = makeLiveModel(gate: gate)
        let windowID = LiveSessionWindowDemandID()
        model.liveStreamRequested = true
        model.registerLiveSessionWindowDemand(windowID, destination: .logs)
        model.installLiveSessionRuntime(
            for: profile,
            generation: model.controllerSession.generation
        )
        let runtime = try #require(model.liveSessionRuntime)

        _ = await runtime.ingestLog(
            LogMessage(type: "info", payload: "staged-while-hidden"),
            source: .mihomoWebSocket,
            id: "staged-while-hidden"
        )
        let publication = try #require(
            await runtime.publication(for: .logs)
        )

        model.updateLiveSessionWindowDemand(windowID, destination: .other)
        for _ in 0..<100 {
            if !(await runtime.currentPresentationDemand()).observes(.logs) {
                break
            }
            await Task.yield()
        }
        model.applyLiveSessionRuntimePublication(
            publication,
            runtime: runtime
        )

        #expect(model.logsCatalog.entries.isEmpty)
        #expect(
            model.controllerSession.logBuffer.entries.map(\.id)
                == ["staged-while-hidden"]
        )

        model.updateLiveSessionWindowDemand(windowID, destination: .logs)
        for _ in 0..<100 where model.logsCatalog.entries.isEmpty {
            await Task.yield()
        }

        #expect(
            model.logsCatalog.entries.map(\.id)
                == ["staged-while-hidden"]
        )
        model.leaveLiveSession()
    }

    @MainActor
    @Test func userLogClearPublishesImmediatelyAheadOfPendingCadence() async {
        let gate = PublicationSleepGate()
        let (model, _) = makeLiveModel(gate: gate)
        let windowID = LiveSessionWindowDemandID()
        model.registerLiveSessionWindowDemand(windowID, destination: .other)
        model.recordControllerLog(LogMessage(type: "info", payload: "published"))
        model.updateLiveSessionWindowDemand(windowID, destination: .logs)
        #expect(model.logsCatalog.entries.count == 1)

        model.recordControllerLog(LogMessage(type: "info", payload: "pending"))
        for _ in 0 ..< 100 where await gate.recordedCalls().isEmpty {
            await Task.yield()
        }
        model.clearControllerLogs()

        #expect(model.controllerSession.logBuffer.entries.isEmpty)
        #expect(model.logsCatalog.entries.isEmpty)

        await gate.release(.logs)
        model.leaveLiveSession()
    }

    @MainActor
    @Test func connectionRemovalPublishesConnectionsCatalogImmediately() {
        let retained = ConnectionSnapshot(id: "retained", upload: 30, download: 40)
        let removed = ConnectionSnapshot(id: "removed", upload: 10, download: 20)
        let dashboard = DashboardSnapshot(
            versionLabel: "1.0",
            mode: "Rule",
            traffic: TrafficSnapshot(upload: 100, download: 200),
            groups: [],
            connections: [removed, retained]
        )
        let model = makeModel(dashboard: dashboard)

        model.removeSessionConnections([removed])

        #expect(model.dashboard.connections.map(\.id) == ["retained"])
        #expect(model.connectionsCatalog.connections.map(\.id) == ["retained"])
        #expect(model.connectionsCatalog.traffic == dashboard.traffic)
    }

    @MainActor
    @Test func connectionCatalogRevisionIgnoresTrafficOnlyFrames() {
        let model = makeModel()
        let initialRevision = model.connectionsCatalog.metricsRevision
        let initialMetadata = model.controllerMetadata

        model.mutateSessionDashboard(publishing: [.connections]) { dashboard in
            dashboard.traffic = TrafficSnapshot(upload: 40, download: 80)
        }

        #expect(model.connectionsCatalog.metricsRevision == initialRevision)
        #expect(model.connectionsCatalog.traffic == TrafficSnapshot(upload: 40, download: 80))
        #expect(model.connectionsCatalog.lastChange == ConnectionsCatalogChange(
            structureChanged: false,
            metricsChanged: false,
            changedMetricIndices: [],
            trafficChanged: true
        ))
        #expect(model.controllerMetadata == initialMetadata)

        model.mutateSessionDashboard(publishing: [.connections]) { dashboard in
            dashboard.connections = [ConnectionSnapshot(id: "connection-1")]
        }

        #expect(model.connectionsCatalog.metricsRevision == initialRevision &+ 1)
        #expect(model.connectionsCatalog.lastChange.structureChanged)
        #expect(model.connectionsCatalog.lastChange.changedMetricIndices == nil)
    }

    @MainActor
    @Test func metricOnlyConnectionPublicationReportsChangedRowIndices() {
        let first = ConnectionSnapshot(id: "first", upload: 10, download: 20)
        let second = ConnectionSnapshot(id: "second", upload: 30, download: 40)
        let dashboard = DashboardSnapshot(
            versionLabel: "1.0",
            mode: "Rule",
            traffic: TrafficSnapshot(upload: 0, download: 0),
            groups: [],
            connections: [first, second]
        )
        let model = makeModel(dashboard: dashboard)

        model.mutateSessionDashboard(publishing: [.connections]) { dashboard in
            dashboard.connections[1].download = 400
        }

        #expect(!model.connectionsCatalog.lastChange.structureChanged)
        #expect(model.connectionsCatalog.lastChange.metricsChanged)
        #expect(model.connectionsCatalog.lastChange.changedMetricIndices == [1])
        #expect(!model.connectionsCatalog.lastChange.trafficChanged)
    }

    @MainActor
    @Test func identicalConnectionPublicationDoesNotReplaceObservableCatalog() {
        let dashboard = DashboardSnapshot(
            versionLabel: "1.0",
            mode: "Rule",
            traffic: TrafficSnapshot(upload: 10, download: 20),
            groups: [],
            connections: [ConnectionSnapshot(id: "stable", upload: 1, download: 2)]
        )
        let model = makeModel(dashboard: dashboard)
        let initial = model.connectionsCatalog

        model.mutateSessionDashboard(publishing: [.connections]) { _ in }

        #expect(model.connectionsCatalog == initial)
    }

    @Test func logCatalogKeepsAppendDropDeltaForPresentation() {
        let first = ControllerLogEntry(
            id: "first",
            receivedAt: Date(timeIntervalSince1970: 1),
            message: LogMessage(type: "info", payload: "first")
        )
        let second = ControllerLogEntry(
            id: "second",
            receivedAt: Date(timeIntervalSince1970: 2),
            message: LogMessage(type: "warning", payload: "second")
        )
        let initial = LogsCatalogSnapshot(
            entries: [first],
            entriesRevision: 1
        )

        let next = initial.applying(
            LiveSessionLogsPublication(
                sequence: 2,
                fullSnapshot: nil,
                droppedEntryIDs: ["first"],
                appendedEntries: [second]
            )
        )

        #expect(next.entries == [second])
        #expect(next.entriesRevision == 2)
        #expect(next.lastChange == .delta(
            droppedEntryIDs: ["first"],
            appendedEntries: [second]
        ))
    }

    @MainActor
    @Test func logReceiptPreservesTheTransportTimestamp() {
        let model = makeModel()
        let receivedAt = Date(timeIntervalSince1970: 1_735_689_600)

        model.recordControllerLog(
            LogMessage(type: "info", payload: "timestamped"),
            receivedAt: receivedAt
        )

        #expect(model.controllerSession.logBuffer.entries.first?.receivedAt == receivedAt)
    }

    @MainActor
    @Test func explicitSessionEndClearsEveryPublishedOperationalDomain() {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let row = ConnectionSnapshot(id: "active", upload: 12, download: 34)
        let dashboard = DashboardSnapshot(
            versionLabel: "1.0",
            mode: "Rule",
            traffic: TrafficSnapshot(upload: 100, download: 200),
            groups: [],
            connections: [row]
        )
        let model = makeModel(
            routers: [profile],
            selectedRouterID: profile.id,
            dashboard: dashboard
        )
        let entry = ControllerLogEntry(
            receivedAt: Date(timeIntervalSince1970: 100),
            message: LogMessage(type: "warning", payload: "retained")
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 100))
        model.controllerSession.state = .live
        model.controllerSession.logBuffer.append(entry)
        model.publishControllerLogs([entry])
        model.dashboardSessionControls.recordClosed([row])
        model.trafficTimeline.append(upload: 10, download: 20, receivedAt: Date())
        model.memoryTimeline.append(inUseBytes: 1_024, receivedAt: Date())
        model.connectionCountTimeline.append(activeCount: 1, receivedAt: Date())
        model.liveStreamUpdatedAt = Date()

        model.leaveLiveSession(reason: .sessionEnd)

        #expect(model.controllerSessionPresentation.state == .stopped)
        #expect(model.controllerSessionPresentation.controllerID == nil)
        #expect(model.dashboard == .empty)
        #expect(model.controllerMetadata == .empty)
        #expect(model.policyGroupCatalog == .empty)
        #expect(model.connectionsCatalog == .empty)
        #expect(model.logsCatalog == .empty)
        #expect(model.routingCatalog == .empty)
        #expect(model.insightCatalog == .empty)
        #expect(model.dashboardSessionControls.closedConnections.isEmpty)
        #expect(model.controllerSession.logBuffer.entries.isEmpty)
        #expect(model.controllerSession.trafficTimeline.samples.isEmpty)
        #expect(model.controllerSession.memoryTimeline.samples.isEmpty)
        #expect(model.controllerSession.connectionCountTimeline.samples.isEmpty)
        #expect(model.trafficTimeline.samples.isEmpty)
        #expect(model.memoryTimeline.samples.isEmpty)
        #expect(model.connectionCountTimeline.samples.isEmpty)
        #expect(model.liveStreamUpdatedAt == nil)
        #expect(!model.canRefreshSelectedRouter)
    }

    @MainActor
    @Test func reconnectRetainsTheCommittedSnapshotAsReadOnlyStaleData() {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let dashboard = DashboardSnapshot(
            versionLabel: "1.0",
            mode: "Rule",
            traffic: TrafficSnapshot(upload: 100, download: 200),
            groups: [],
            connections: [ConnectionSnapshot(id: "active")]
        )
        let model = makeModel(
            routers: [profile],
            selectedRouterID: profile.id,
            dashboard: dashboard
        )
        let committedAt = Date(timeIntervalSince1970: 200)
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: committedAt)
        model.controllerSession.state = .live

        model.controllerSession.beginReconnect(message: "transport unavailable")

        #expect(model.dashboard == dashboard)
        #expect(model.connectionsCatalog.connections.map(\.id) == ["active"])
        #expect(
            model.controllerSessionPresentation.state
                == .staleReconnecting("transport unavailable")
        )
        #expect(model.controllerSessionPresentation.lastSuccessAt == committedAt)
        #expect(!model.canRefreshSelectedRouter)
        #expect(model.controllerSession.baselineTransaction.isReconnect)
    }

    @MainActor
    @Test func pendingMemoryResumePreservesLatestReceiveTimestamp() {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let model = makeModel(routers: [profile], selectedRouterID: profile.id)
        model.controllerSession.begin(controllerID: profile.id)
        model.dashboardSessionControls.setPresentationPaused(true)

        let firstReceivedAt = Date(timeIntervalSince1970: 100)
        let latestReceivedAt = Date(timeIntervalSince1970: 200)
        model.controllerSession.memoryTimeline.append(
            inUseBytes: 1_048_576,
            receivedAt: firstReceivedAt
        )
        model.controllerSession.recordPendingMemory(
            MemoryResponse(inuse: 1_048_576, oslimit: 2_097_152),
            receivedAt: firstReceivedAt
        )
        model.controllerSession.memoryTimeline.append(
            inUseBytes: 3_145_728,
            receivedAt: latestReceivedAt
        )
        model.controllerSession.recordPendingMemory(
            MemoryResponse(inuse: 3_145_728, oslimit: 4_194_304),
            receivedAt: latestReceivedAt
        )

        model.dashboardSessionControls.setPresentationPaused(false)
        model.applyPendingSessionPresentation()

        #expect(model.controllerSession.runtime.memoryInUseBytes == 3_145_728)
        #expect(model.controllerSession.runtime.memoryLimitBytes == 4_194_304)
        #expect(model.controllerSession.runtime.memoryUpdatedAt == latestReceivedAt)
        #expect(model.controllerSession.runtime.lastRuntimeOperationAt == latestReceivedAt)
        #expect(model.memoryTimeline.samples.map(\.receivedAt) == [firstReceivedAt, latestReceivedAt])
        #expect(model.controllerSession.pendingMemorySample == nil)
        #expect(model.controllerSession.pendingPresentation.isEmpty)
    }

    @MainActor
    @Test func surgeConnectionsPublicationExposesNearLiveRatesAndTimelines() {
        let profile = RouterProfile(
            displayName: "Surge",
            host: "127.0.0.1",
            controllerKind: .surgeCompatible
        )
        let model = makeModel(
            routers: [profile],
            selectedRouterID: profile.id
        )
        model.controllerSession.begin(controllerID: profile.id)
        let receivedAt = Date(timeIntervalSince1970: 300)
        let request = SurgeActiveRequest(
            id: "request-1",
            url: "https://example.com",
            policy: "Proxy",
            uploadSpeed: 1_024,
            downloadSpeed: 2_048
        )
        let snapshot = SurgeControlSnapshot(
            activeRequests: SurgeActiveRequestsResponse(requests: [request]),
            traffic: SurgeTrafficResponse(upload: 300, download: 600),
            checkedAt: receivedAt
        )
        model.controllerSession.trafficTimeline.append(
            upload: snapshot.traffic.upload,
            download: snapshot.traffic.download,
            receivedAt: receivedAt
        )
        model.stageSurgeSnapshot(
            snapshot,
            receivedAt: receivedAt,
            includesCompleteBaseline: false
        )

        model.publishStagedSurgePresentation(
            router: profile,
            domains: [.connections]
        )

        #expect(model.trafficTimeline.samples.last?.upload == 300)
        #expect(model.trafficTimeline.samples.last?.download == 600)
        #expect(model.connectionCountTimeline.samples.last?.activeCount == 1)
        #expect(model.liveTrafficRate == TrafficSnapshot(upload: 300, download: 600))
        #expect(model.liveStreamUpdatedAt == receivedAt)
        #expect(model.connectionsCatalog.traffic == TrafficSnapshot(upload: 300, download: 600))
        #expect(model.connectionsCatalog.connections.count == 1)
    }

    @MainActor
    @Test func sessionPresentationIgnoresTimelineOnlyChanges() {
        let model = makeModel()
        let initialGeneration = model.controllerSessionPresentation.generation
        let initialState = model.controllerSessionPresentation.state
        let initialRuntime = model.controllerSessionPresentation.runtime

        model.controllerSession.trafficTimeline.append(
            upload: 1_024,
            download: 2_048,
            receivedAt: Date(timeIntervalSince1970: 100)
        )
        model.controllerSession.memoryTimeline.append(
            inUseBytes: 4_096,
            receivedAt: Date(timeIntervalSince1970: 100)
        )
        model.controllerSession.connectionCountTimeline.append(
            activeCount: 1,
            receivedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(model.controllerSessionPresentation.generation == initialGeneration)
        #expect(model.controllerSessionPresentation.state == initialState)
        #expect(model.controllerSessionPresentation.runtime == initialRuntime)

        model.controllerSession.state = .connecting

        #expect(model.controllerSessionPresentation.state == .connecting)
    }

    @MainActor
    @Test func terminalMihomoChannelFailureKeepsRuntimeAndSiblingPublicationAlive() async throws {
        let gate = PublicationSleepGate()
        let (model, profile) = makeLiveModel(gate: gate)
        let generation = model.controllerSession.generation
        model.connectionState = .connected(version: "test")
        model.liveStreamRequested = true
        model.registerLiveSessionWindowDemand(
            LiveSessionWindowDemandID(),
            destination: .logs
        )
        model.installLiveSessionRuntime(for: profile, generation: generation)
        let runtime = try #require(model.liveSessionRuntime)
        let identity = try #require(model.liveSessionRuntimeIdentity)

        model.handleLiveStreamFailure(
            .traffic,
            error: MihomoClientError.unauthorized,
            routerID: profile.id,
            generation: generation
        )

        #expect(model.liveSessionRuntime === runtime)
        #expect(model.liveSessionRuntimeIdentity == identity)
        #expect(model.connectionState == .connected(version: "test"))
        #expect(model.liveStreamState.isPartial)

        let receivedAt = Date(timeIntervalSince1970: 10)
        _ = await runtime.ingestLog(
            LogMessage(type: "info", payload: "healthy sibling"),
            source: .mihomoWebSocket,
            receivedAt: receivedAt,
            id: "healthy-sibling"
        )
        let publication = try #require(
            await runtime.publication(for: .logs, force: true)
        )
        model.applyLiveSessionRuntimePublication(publication, runtime: runtime)

        #expect(model.logsCatalog.entries.map(\.id) == ["healthy-sibling"])
        #expect(model.liveSessionRuntime === runtime)
        #expect(model.liveStreamState.isPartial)
        #expect(model.controllerSession.liveObservation.state == .partial)
        #expect(model.controllerSession.lastSuccessAt == receivedAt)
        model.leaveLiveSession()
    }

    @MainActor
    @Test func terminalMihomoChannelFailureBeforeBaselineRemainsPartialAfterCommit() async throws {
        let gate = PublicationSleepGate()
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore(),
            sessionPublicationSleepOperation: { domain, cadence in
                await gate.sleep(domain: domain, cadence: cadence)
            }
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.activeSessionControllerKind = .mihomoCompatible
        model.liveStreamRequested = true
        let logsWindow = LiveSessionWindowDemandID()
        model.registerLiveSessionWindowDemand(
            logsWindow,
            destination: .logs
        )
        let generation = model.controllerSession.generation
        model.installLiveSessionRuntime(for: profile, generation: generation)
        let runtime = try #require(model.liveSessionRuntime)
        let identity = try #require(model.liveSessionRuntimeIdentity)

        model.handleLiveStreamFailure(
            .traffic,
            error: MihomoClientError.unauthorized,
            routerID: profile.id,
            generation: generation,
            runtime: runtime
        )

        if case .failedBeforeFirstSnapshot = model.controllerSession.state {
            // The REST baseline has not committed yet.
        } else {
            Issue.record("Expected the session to remain failed before its baseline")
        }
        #expect(model.liveStreamState.isPartial)
        #expect(model.controllerSession.liveObservation.state == .failed)
        #expect(model.liveSessionRuntime === runtime)

        model.controllerSession.endpointCache.version = VersionResponse(
            version: "1.0"
        )
        model.controllerSession.endpointCache.config = try JSONDecoder().decode(
            ConfigResponse.self,
            from: Data(#"{"mode":"rule"}"#.utf8)
        )
        model.controllerSession.endpointCache.proxies = ProxiesResponse(
            proxies: [:]
        )
        model.controllerSession.endpointCache.connections = ConnectionsResponse(
            connections: []
        )

        #expect(
            model.attemptSessionBaselineCommit(
                for: profile,
                generation: generation
            )
        )
        #expect(model.controllerSession.hasCommittedBaseline)
        #expect(model.controllerSession.state.failureDetail != nil)
        #expect(model.liveStreamState.isPartial)
        #expect(model.controllerSession.liveObservation.state == .partial)
        #expect(model.liveSessionRuntime === runtime)

        let receivedAt = Date(timeIntervalSince1970: 20)
        let scheduled = await runtime.ingestLog(
            LogMessage(type: "info", payload: "pre-baseline sibling"),
            source: .mihomoWebSocket,
            receivedAt: receivedAt,
            id: "pre-baseline-sibling"
        )
        model.scheduleLiveSessionRuntimePublications(
            scheduled,
            runtime: runtime,
            identity: identity
        )
        for _ in 0..<100 {
            guard model.logsCatalog.entries.isEmpty,
                  await gate.recordedCalls().isEmpty else {
                break
            }
            await Task.yield()
        }
        if model.logsCatalog.entries.isEmpty {
            await gate.release(.logs)
        }
        for _ in 0..<100 where model.logsCatalog.entries.isEmpty {
            await Task.yield()
        }

        #expect(model.logsCatalog.entries.map(\.id) == ["pre-baseline-sibling"])
        #expect(model.controllerSession.state.failureDetail != nil)
        #expect(model.liveStreamState.isPartial)
        #expect(model.controllerSession.liveObservation.state == .partial)
        model.unregisterLiveSessionWindowDemand(logsWindow)
        model.leaveLiveSession()
    }

    @MainActor
    @Test func outOfOrderDomainCompletionsKeepLastSuccessMonotonic() {
        let gate = PublicationSleepGate()
        let (model, profile) = makeLiveModel(gate: gate)
        let newer = Date(timeIntervalSince1970: 200)
        let older = Date(timeIntervalSince1970: 100)

        model.completeLiveTransportIngestion(
            receivedAt: newer,
            router: profile,
            streamState: .live
        )
        model.completeLiveTransportIngestion(
            receivedAt: older,
            router: profile,
            streamState: .live
        )

        #expect(model.controllerSession.lastSuccessAt == newer)
        #expect(model.controllerSessionPresentation.lastSuccessAt == newer)
        model.leaveLiveSession()
    }

    @MainActor
    @Test func manualRefreshRecognizesEveryResolvedMihomoRuntimeKind() {
        let mihomoKinds: [ControllerKind] = [
            .mihomoCompatible,
            .nikkiMihomoCompatible,
            .openClashMihomoCompatible,
            .cmfaCompatible,
            .stashCompatible,
        ]
        let otherKinds: [ControllerKind] = [
            .autoDetect,
            .surgeCompatible,
            .singBoxCompatible,
            .stashCmfaCompatible,
            .unknown,
            .unsupported,
        ]

        for kind in mihomoKinds {
            #expect(AppModel.usesMihomoLiveStreams(kind))
        }
        for kind in otherKinds {
            #expect(!AppModel.usesMihomoLiveStreams(kind))
        }
    }

    @MainActor
    private func makeModel(
        routers: [RouterProfile] = [],
        selectedRouterID: RouterProfile.ID? = nil,
        dashboard: DashboardSnapshot = .empty
    ) -> AppModel {
        AppModel(
            routers: routers,
            selectedRouterID: selectedRouterID,
            dashboard: dashboard,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
    }

    @MainActor
    private func makeLiveModel(
        gate: PublicationSleepGate
    ) -> (AppModel, RouterProfile) {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore(),
            sessionPublicationSleepOperation: { domain, cadence in
                await gate.sleep(domain: domain, cadence: cadence)
            }
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
        model.controllerSession.state = .live
        model.activeSessionControllerKind = .mihomoCompatible
        return (model, profile)
    }
}
