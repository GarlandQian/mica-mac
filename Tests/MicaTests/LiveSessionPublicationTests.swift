import Foundation
import MicaCore
import Observation
import Synchronization
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

struct DecodedConnectionFrameFixture {
    struct Frames {
        let initial: [ConnectionSnapshot]
        let metricUpdated: [ConnectionSnapshot]
        let additionalFieldUpdated: [ConnectionSnapshot]
        let changedIndex: Int
    }

    static func make(connectionCount: Int = 3) throws -> Frames {
        precondition(connectionCount > 1)

        var source = MicaPerformanceFixtures.connections(count: connectionCount)
        for index in source.indices {
            source[index].fields["controller-extra"] = .object([
                "sequence": .number(Double(index)),
                "stable": .bool(true),
            ])
        }

        let changedIndex = connectionCount / 2
        let initial = try roundTrip(source)

        var metricUpdatedSource = initial
        metricUpdatedSource[changedIndex].upload =
            (metricUpdatedSource[changedIndex].upload ?? 0) + 101
        metricUpdatedSource[changedIndex].download =
            (metricUpdatedSource[changedIndex].download ?? 0) + 103
        metricUpdatedSource[changedIndex].uploadSpeed =
            (metricUpdatedSource[changedIndex].uploadSpeed ?? 0) + 107
        metricUpdatedSource[changedIndex].downloadSpeed =
            (metricUpdatedSource[changedIndex].downloadSpeed ?? 0) + 109
        let metricUpdated = try roundTrip(metricUpdatedSource)

        var additionalFieldUpdatedSource = initial
        additionalFieldUpdatedSource[changedIndex].fields["controller-extra"] = .object([
            "sequence": .number(Double(changedIndex)),
            "stable": .bool(false),
        ])
        let additionalFieldUpdated = try roundTrip(additionalFieldUpdatedSource)

        return Frames(
            initial: initial,
            metricUpdated: metricUpdated,
            additionalFieldUpdated: additionalFieldUpdated,
            changedIndex: changedIndex
        )
    }

    private static func roundTrip(
        _ connections: [ConnectionSnapshot]
    ) throws -> [ConnectionSnapshot] {
        let data = try JSONEncoder().encode(connections)
        return try JSONDecoder().decode([ConnectionSnapshot].self, from: data)
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

    @MainActor
    @Test func dashboardAssemblyCacheIsNotObservedButDomainCatalogPublicationInvalidates() {
        let model = makeModel()
        let dashboardInvalidated = Mutex(false)
        let catalogInvalidated = Mutex(false)

        withObservationTracking {
            _ = model.dashboard
        } onChange: {
            dashboardInvalidated.withLock { $0 = true }
        }
        withObservationTracking {
            _ = model.policyGroupCatalog
        } onChange: {
            catalogInvalidated.withLock { $0 = true }
        }

        var next = DashboardSnapshot.empty
        next.mode = "Rule"
        model.replaceDashboard(next)

        #expect(!dashboardInvalidated.withLock { $0 })
        #expect(catalogInvalidated.withLock { $0 })
        #expect(model.dashboard.mode == "Rule")
        #expect(model.policyGroupCatalog.mode == "Rule")
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

        model.mutateSessionDashboard(publishing: [.rules, .providers, .insight]) { dashboard in
            dashboard.rules = [rule]
            dashboard.providers = [provider]
            dashboard.insight = InsightSummarySnapshot(snapshot: dashboard)
        }

        #expect(model.controllerMetadata == initialMetadata)
        #expect(model.policyGroupCatalog == initialGroups)
        #expect(model.policyGroupCatalogRevision == initialGroupRevision)
        #expect(model.connectionsCatalog == initialConnections)
        #expect(model.logsCatalog == initialLogs)
        #expect(model.rulesCatalog == RulesCatalogSnapshot(dashboard: model.dashboard))
        #expect(model.providersCatalog == ProvidersCatalogSnapshot(dashboard: model.dashboard))
        #expect(model.insightCatalog == model.dashboard.insight)
        #expect(model.insightCatalog.ruleCount == 1)
        #expect(model.insightCatalog.providerCount == 1)
    }

    @MainActor
    @Test func ruleAndProviderCatalogObservationsInvalidateIndependently() {
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
        let rulesInvalidated = Mutex(false)

        withObservationTracking {
            _ = model.rulesCatalog
        } onChange: {
            rulesInvalidated.withLock { $0 = true }
        }

        model.mutateSessionDashboard(publishing: [.providers]) { dashboard in
            dashboard.providers = [provider]
        }

        #expect(!rulesInvalidated.withLock { $0 })
        #expect(model.rulesCatalog == .empty)
        #expect(model.providersCatalog.providers == [provider])

        let providersInvalidated = Mutex(false)
        withObservationTracking {
            _ = model.providersCatalog
        } onChange: {
            providersInvalidated.withLock { $0 = true }
        }

        model.mutateSessionDashboard(publishing: [.rules]) { dashboard in
            dashboard.rules = [rule]
        }

        #expect(!providersInvalidated.withLock { $0 })
        #expect(model.rulesCatalog.rules == [rule])
        #expect(model.providersCatalog.providers == [provider])
    }

    @MainActor
    @Test func policyCatalogRevisionChangesOnlyWithPublishedCatalogData() {
        let model = makeModel()
        let initialRevision = model.policyGroupCatalogRevision
        let node = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Tokyo",
                type: "VLESS",
                metadata: [
                    "controller-meta": .object([
                        "nested": .object(["enabled": .bool(true)]),
                    ]),
                ]
            )
        )
        let group = ProxyGroupViewState(
            id: "Auto",
            type: "URLTest",
            selected: "Tokyo",
            options: ["Tokyo"],
            details: node,
            optionDetails: ["Tokyo": node]
        )

        model.mutateSessionDashboard(publishing: [.policyGroups]) { dashboard in
            dashboard.groups = [group]
        }
        #expect(model.policyGroupCatalogRevision == initialRevision &+ 1)

        model.mutateSessionDashboard(publishing: [.policyGroups]) { dashboard in
            dashboard.groups = [group]
        }
        #expect(model.policyGroupCatalogRevision == initialRevision &+ 1)

        let changedNode = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Tokyo",
                type: "VLESS",
                metadata: [
                    "controller-meta": .object([
                        "nested": .object(["enabled": .bool(false)]),
                    ]),
                ]
            )
        )
        let changedGroup = ProxyGroupViewState(
            id: "Auto",
            type: "URLTest",
            selected: "Tokyo",
            options: ["Tokyo"],
            details: changedNode,
            optionDetails: ["Tokyo": changedNode]
        )
        model.mutateSessionDashboard(publishing: [.policyGroups]) { dashboard in
            dashboard.groups = [changedGroup]
        }
        #expect(model.policyGroupCatalogRevision == initialRevision &+ 2)
        #expect(
            model.dashboard.groups.first?.optionDetails["Tokyo"]?.metadata
                == changedNode.metadata
        )
        #expect(
            model.policyGroupCatalog.groups.first?.optionDetails["Tokyo"]?.metadata
                == changedNode.metadata
        )
    }

    @Test func mihomoMediumChangePlanUsesExactRawProxyAndWeightEquality() {
        let group = ProxySnapshot(
            name: "Auto",
            type: "Smart",
            now: "Node A",
            all: ["Node A", "Node B"],
            metadata: [
                "controller-extra": .object([
                    "nested": .object(["enabled": .bool(true)]),
                ]),
            ]
        )
        let nodeA = ProxySnapshot(name: "Node A", type: "VLESS")
        let nodeB = ProxySnapshot(name: "Node B", type: "VLESS")
        let proxies = ProxiesResponse(
            proxies: ["Auto": group, "Node A": nodeA, "Node B": nodeB],
            proxyOrder: ["Auto", "Node A", "Node B"]
        )
        let weights = SmartWeightsResponse(
            message: "ok",
            weights: [
                "Auto": [SmartNodeRankSnapshot(name: "Node A", rank: "MostUsed")],
            ]
        )
        var cache = SessionEndpointCache()
        cache.proxies = proxies
        cache.smartWeights = weights

        let unchanged = MihomoEndpointChangePlan.medium(
            cache: cache,
            proxies: proxies,
            smartWeights: .replace(weights)
        )
        #expect(unchanged.cacheWriteCount == 0)
        #expect(unchanged.policyGroupProjectionWorkUnits == 0)
        #expect(unchanged.domains.isEmpty)
        #expect(!unchanged.shouldRebuildUnifiedSnapshot)

        var reordered = proxies
        reordered.proxyOrder.swapAt(1, 2)
        let reorderedPlan = MihomoEndpointChangePlan.medium(
            cache: cache,
            proxies: reordered
        )
        #expect(reorderedPlan.shouldWriteProxies)
        #expect(reorderedPlan.policyGroupProjectionWorkUnits == 1)
        #expect(reorderedPlan.shouldRebuildUnifiedSnapshot)

        var metadataChanged = proxies
        var changedGroup = group
        changedGroup.metadata["controller-extra"] = .object([
            "nested": .object(["enabled": .bool(false)]),
        ])
        metadataChanged.proxies[group.name] = changedGroup
        let metadataPlan = MihomoEndpointChangePlan.medium(
            cache: cache,
            proxies: metadataChanged
        )
        #expect(metadataPlan.shouldWriteProxies)
        #expect(metadataPlan.domains == [.policyGroups, .insight])

        var changedWeights = weights
        changedWeights.weights["Auto"] = [
            SmartNodeRankSnapshot(name: "Node A", rank: "RarelyUsed"),
        ]
        let weightsPlan = MihomoEndpointChangePlan.medium(
            cache: cache,
            smartWeights: .replace(changedWeights)
        )
        #expect(weightsPlan.shouldWriteSmartWeights)
        #expect(weightsPlan.policyGroupProjectionWorkUnits == 1)
        #expect(!weightsPlan.shouldRebuildUnifiedSnapshot)

        let clearWeightsPlan = MihomoEndpointChangePlan.medium(
            cache: cache,
            proxies: proxies,
            smartWeights: .replace(nil)
        )
        #expect(!clearWeightsPlan.shouldWriteProxies)
        #expect(clearWeightsPlan.shouldWriteSmartWeights)
        #expect(clearWeightsPlan.policyGroupProjectionWorkUnits == 1)
    }

    @Test func mihomoSlowChangePlanKeepsRuleAndProviderDomainsIndependent() {
        let firstRules = RulesResponse(rules: [
            RuleSnapshot(type: "DOMAIN", payload: "first.example", proxy: "DIRECT"),
        ])
        let secondRules = RulesResponse(rules: [
            RuleSnapshot(type: "DOMAIN", payload: "second.example", proxy: "DIRECT"),
        ])
        let firstProviders = ProxyProvidersResponse(
            providers: [
                "Remote": ProxyProviderSnapshot(
                    name: "Remote",
                    type: "Proxy",
                    vehicleType: "HTTP",
                    updatedAt: "2026-09-01T00:00:00Z"
                ),
            ],
            providerOrder: ["Remote"]
        )
        let secondProviders = ProxyProvidersResponse(
            providers: [
                "Remote": ProxyProviderSnapshot(
                    name: "Remote",
                    type: "Proxy",
                    vehicleType: "HTTP",
                    updatedAt: "2026-09-02T00:00:00Z"
                ),
            ],
            providerOrder: ["Remote"]
        )
        let ruleProviders = RuleProvidersResponse(providers: [:], providerOrder: [])
        var cache = SessionEndpointCache()
        cache.rules = firstRules
        cache.proxyProviders = firstProviders
        cache.ruleProviders = ruleProviders

        let ruleOnly = MihomoEndpointChangePlan.slow(
            cache: cache,
            version: nil,
            config: nil,
            rules: secondRules,
            proxyProviders: firstProviders,
            ruleProviders: ruleProviders
        )
        #expect(ruleOnly.shouldWriteRules)
        #expect(!ruleOnly.shouldWriteProxyProviders)
        #expect(!ruleOnly.shouldWriteRuleProviders)
        #expect(ruleOnly.domains == [.rules, .insight])

        let providerOnly = MihomoEndpointChangePlan.slow(
            cache: cache,
            version: nil,
            config: nil,
            rules: firstRules,
            proxyProviders: secondProviders,
            ruleProviders: ruleProviders
        )
        #expect(!providerOnly.shouldWriteRules)
        #expect(providerOnly.shouldWriteProxyProviders)
        #expect(!providerOnly.shouldWriteRuleProviders)
        #expect(providerOnly.domains == [.providers, .insight])
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
    @Test func decodedMetricOnlyConnectionFrameKeepsCatalogStructureRevisionStable() throws {
        let frames = try DecodedConnectionFrameFixture.make()
        let dashboard = DashboardSnapshot(
            versionLabel: "1.0",
            mode: "Rule",
            traffic: TrafficSnapshot(upload: 10, download: 20),
            groups: [],
            connections: frames.initial
        )
        let model = makeModel(dashboard: dashboard)
        let initialStructureRevision = model.connectionsCatalog.structureRevision
        let initialStructureToken = model.connectionsStructureRevision
        let initialMetricsRevision = model.connectionsCatalog.metricsRevision
        let initialMetricsToken = model.connectionsMetricsRevision
        let structureTokenInvalidated = Mutex(false)
        let metricsTokenInvalidated = Mutex(false)

        withObservationTracking {
            _ = model.connectionsStructureRevision
        } onChange: {
            structureTokenInvalidated.withLock { $0 = true }
        }
        withObservationTracking {
            _ = model.connectionsMetricsRevision
        } onChange: {
            metricsTokenInvalidated.withLock { $0 = true }
        }

        model.mutateSessionDashboard(publishing: [.connections]) { dashboard in
            dashboard.connections = frames.metricUpdated
        }

        let initial = frames.initial[frames.changedIndex]
        let updated = frames.metricUpdated[frames.changedIndex]
        #expect(initial.fields["upload"] != updated.fields["upload"])
        #expect(initial.fields["download"] != updated.fields["download"])
        #expect(initial.fields["uploadSpeed"] != updated.fields["uploadSpeed"])
        #expect(initial.fields["downloadSpeed"] != updated.fields["downloadSpeed"])
        #expect(initial.additionalFields == updated.additionalFields)
        #expect(model.connectionsCatalog.structureRevision == initialStructureRevision)
        #expect(model.connectionsStructureRevision == initialStructureToken)
        #expect(!structureTokenInvalidated.withLock { $0 })
        #expect(model.connectionsCatalog.metricsRevision == initialMetricsRevision &+ 1)
        #expect(model.connectionsMetricsRevision == initialMetricsToken &+ 1)
        #expect(metricsTokenInvalidated.withLock { $0 })
        #expect(!model.connectionsCatalog.lastChange.structureChanged)
        #expect(model.connectionsCatalog.lastChange.metricsChanged)
        #expect(
            model.connectionsCatalog.lastChange.changedMetricIndices
                == [frames.changedIndex]
        )
    }

    @MainActor
    @Test func runtimeMetricOnlyConnectionPublicationKeepsStructureTokenUnobserved() async throws {
        let frames = try DecodedConnectionFrameFixture.make()
        let gate = PublicationSleepGate()
        let (model, profile) = makeLiveModel(gate: gate)
        model.liveStreamRequested = true
        model.registerLiveSessionWindowDemand(
            LiveSessionWindowDemandID(),
            destination: .connections
        )
        model.installLiveSessionRuntime(
            for: profile,
            generation: model.controllerSession.generation
        )
        let runtime = try #require(model.liveSessionRuntime)

        _ = await runtime.ingestMihomoConnections(
            ConnectionsResponse(
                uploadTotal: 10,
                downloadTotal: 20,
                memory: 30,
                connections: frames.initial
            ),
            receivedAt: Date(timeIntervalSince1970: 1)
        )
        let initialPublication = try #require(
            await runtime.publication(for: .connections, force: true)
        )
        model.applyLiveSessionRuntimePublication(initialPublication, runtime: runtime)
        let initialStructureToken = model.connectionsStructureRevision
        let initialMetricsToken = model.connectionsMetricsRevision
        let structureTokenInvalidated = Mutex(false)
        let metricsTokenInvalidated = Mutex(false)

        withObservationTracking {
            _ = model.connectionsStructureRevision
        } onChange: {
            structureTokenInvalidated.withLock { $0 = true }
        }
        withObservationTracking {
            _ = model.connectionsMetricsRevision
        } onChange: {
            metricsTokenInvalidated.withLock { $0 = true }
        }

        _ = await runtime.ingestMihomoConnections(
            ConnectionsResponse(
                uploadTotal: 10,
                downloadTotal: 20,
                memory: 30,
                connections: frames.metricUpdated
            ),
            receivedAt: Date(timeIntervalSince1970: 2)
        )
        let metricPublication = try #require(
            await runtime.publication(for: .connections, force: true)
        )
        model.applyLiveSessionRuntimePublication(metricPublication, runtime: runtime)

        #expect(model.connectionsStructureRevision == initialStructureToken)
        #expect(!structureTokenInvalidated.withLock { $0 })
        #expect(model.connectionsMetricsRevision == initialMetricsToken &+ 1)
        #expect(metricsTokenInvalidated.withLock { $0 })
        #expect(model.connectionsCatalog.lastChange.metricsChanged)
        #expect(!model.connectionsCatalog.lastChange.structureChanged)
        model.leaveLiveSession()
    }

    @MainActor
    @Test func decodedAdditionalConnectionFieldChangeAdvancesCatalogStructureRevision() throws {
        let frames = try DecodedConnectionFrameFixture.make()
        let dashboard = DashboardSnapshot(
            versionLabel: "1.0",
            mode: "Rule",
            traffic: TrafficSnapshot(upload: 10, download: 20),
            groups: [],
            connections: frames.initial
        )
        let model = makeModel(dashboard: dashboard)
        let initialStructureRevision = model.connectionsCatalog.structureRevision
        let initialStructureToken = model.connectionsStructureRevision
        let initialMetricsRevision = model.connectionsCatalog.metricsRevision
        let initialMetricsToken = model.connectionsMetricsRevision

        model.mutateSessionDashboard(publishing: [.connections]) { dashboard in
            dashboard.connections = frames.additionalFieldUpdated
        }

        #expect(
            frames.initial[frames.changedIndex].additionalFields
                != frames.additionalFieldUpdated[frames.changedIndex].additionalFields
        )
        #expect(model.connectionsCatalog.structureRevision == initialStructureRevision &+ 1)
        #expect(model.connectionsStructureRevision == initialStructureToken &+ 1)
        #expect(model.connectionsCatalog.metricsRevision == initialMetricsRevision &+ 1)
        #expect(model.connectionsMetricsRevision == initialMetricsToken &+ 1)
        #expect(model.connectionsCatalog.lastChange.structureChanged)
        #expect(model.connectionsCatalog.lastChange.metricsChanged)
        #expect(model.connectionsCatalog.lastChange.changedMetricIndices == nil)
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
    @Test func refreshGateObservesOnlySessionPresentationLifecycleAndControls() {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let model = makeModel(routers: [profile], selectedRouterID: profile.id)
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
        model.controllerSession.state = .live
        #expect(model.canRefreshSelectedRouter)

        let controlInvalidated = Mutex(false)
        withObservationTracking {
            _ = model.canRefreshSelectedRouter
        } onChange: {
            controlInvalidated.withLock { $0 = true }
        }

        model.controllerSession.latestReceivedAt = Date(timeIntervalSince1970: 2)
        model.controllerSession.lastSuccessAt = Date(timeIntervalSince1970: 2)
        model.controllerSession.trafficTimeline.append(
            upload: 10,
            download: 20,
            receivedAt: Date(timeIntervalSince1970: 2)
        )
        model.controllerSession.logBuffer.append(
            ControllerLogEntry(
                receivedAt: Date(timeIntervalSince1970: 2),
                message: LogMessage(type: "info", payload: "retained")
            )
        )
        model.controllerSession.endpointCache.version = VersionResponse(version: "1.0")

        #expect(!controlInvalidated.withLock { $0 })
        #expect(model.canRefreshSelectedRouter)

        model.dashboardSessionControls.setPresentationPaused(true)
        #expect(controlInvalidated.withLock { $0 })
        #expect(!model.canRefreshSelectedRouter)

        model.dashboardSessionControls.setPresentationPaused(false)
        let stateInvalidated = Mutex(false)
        withObservationTracking {
            _ = model.canRefreshSelectedRouter
        } onChange: {
            stateInvalidated.withLock { $0 = true }
        }

        model.controllerSession.state = .staleReconnecting("unavailable")
        #expect(stateInvalidated.withLock { $0 })
        #expect(!model.canRefreshSelectedRouter)

        model.controllerSession.state = .live
        let identityInvalidated = Mutex(false)
        withObservationTracking {
            _ = model.canRefreshSelectedRouter
        } onChange: {
            identityInvalidated.withLock { $0 = true }
        }

        model.controllerSession.controllerID = nil
        #expect(identityInvalidated.withLock { $0 })
        #expect(!model.canRefreshSelectedRouter)
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
        let structureTokenBeforeEnd = model.connectionsStructureRevision

        model.leaveLiveSession(reason: .sessionEnd)

        #expect(model.controllerSessionPresentation.state == .stopped)
        #expect(model.controllerSessionPresentation.controllerID == nil)
        #expect(model.dashboard == .empty)
        #expect(model.controllerMetadata == .empty)
        #expect(model.policyGroupCatalog == .empty)
        #expect(model.connectionsCatalog == .empty)
        #expect(model.connectionsStructureRevision == structureTokenBeforeEnd &+ 1)
        #expect(model.logsCatalog == .empty)
        #expect(model.rulesCatalog == .empty)
        #expect(model.providersCatalog == .empty)
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
