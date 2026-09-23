import Foundation
import MicaCore
import Testing
@testable import Mica

struct SurgeDomainProjectionTests {
    @Test func connectionOnlyProjectionMatchesEveryReportedFieldAndIdentity() {
        let snapshot = SurgeDomainProjectionFixture.snapshot()
        for language in [AppLanguage.english, .simplifiedChinese] {
            let full = DashboardSnapshot(surge: snapshot, language: language)
            let connections = DashboardSnapshot.surgeActiveRequestConnections(
                for: snapshot.activeRequests, language: language
            )
            #expect(connections == full.connections)
            #expect(connections.map(\.id) == ["shared", "shared#2", "surge-request-unreported-3"])
            #expect(connections[0].chains == ["Node A", "Manual"])
            #expect(connections[1].chains == ["", "Automatic"])
            #expect(connections[0].fields["controller-extra"] == .object(["enabled": .bool(true)]))
            #expect(connections[0].metadata?.processPath == "/Applications/Fixture.app")
            #expect(connections[0].metadata?.uid == 501)
        }
    }

    @MainActor
    @Test func domainProjectionAndFullProjectionUseIdenticalRateHistory() {
        var snapshot = SurgeDomainProjectionFixture.snapshot()
        let seed = DashboardSnapshot(surge: snapshot)
        let fullModel = makeModel(dashboard: seed)
        let partialModel = makeModel(dashboard: seed)
        let firstAt = Date(timeIntervalSince1970: 100)
        let firstFull = fullModel.projectedSurgeDashboard(snapshot, connectionRatesReceivedAt: firstAt)
        let firstPartial = partialModel.projectedSurgeDashboard(
            snapshot, connectionRatesReceivedAt: firstAt, domains: [.connections, .insight]
        )
        #expect(firstPartial == firstFull)

        snapshot.activeRequests[0].upload = 1_300
        snapshot.activeRequests[0].download = 2_600
        snapshot.activeRequests[1].upload = 5
        snapshot.activeRequests[1].download = 10
        let secondAt = firstAt.addingTimeInterval(2)
        let secondFull = fullModel.projectedSurgeDashboard(snapshot, connectionRatesReceivedAt: secondAt)
        let secondPartial = partialModel.projectedSurgeDashboard(
            snapshot, connectionRatesReceivedAt: secondAt, domains: [.connections, .insight]
        )
        #expect(secondPartial == secondFull)
        #expect(secondPartial.connections[0].uploadSpeed == 150)
        #expect(secondPartial.connections[0].downloadSpeed == 300)
        #expect(secondPartial.connections[1].uploadSpeed == 31)
        #expect(secondPartial.connections[1].downloadSpeed == 47)
    }

    @MainActor
    @Test func nearLivePublicationRetainsSlowDomainsAndTheirInsightCounts() {
        let snapshot = SurgeDomainProjectionFixture.snapshot()
        let profile = RouterProfile(displayName: "Fixture Surge", host: "127.0.0.1", controllerKind: .surgeCompatible)
        let model = makeModel(dashboard: DashboardSnapshot(surge: snapshot), profile: profile)
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 100))
        let before = model.dashboard
        let beforeGroups = model.policyGroupCatalog
        let beforeGroupRevision = model.policyGroupCatalogRevision
        var next = snapshot
        // A connection-domain publication must not replace any slow-domain
        // catalog even if the raw snapshot contains a different staged value.
        next.outboundMode = "direct"
        next.policyGroups = []
        next.policies = []
        next.rules = []
        next.activeRequests.removeLast()
        next.traffic = SurgeTrafficResponse(upload: 8_000, download: 9_000)
        let receivedAt = Date(timeIntervalSince1970: 102)
        model.controllerSession.surgeRawSnapshot = next
        model.controllerSession.surgeConnectionRatesReceivedAt = receivedAt
        model.controllerSession.trafficTimeline.append(upload: 77, download: 88, receivedAt: receivedAt)
        model.publishStagedSurgePresentation(router: profile, domains: [.connections])

        #expect(model.dashboard.versionLabel == before.versionLabel)
        #expect(model.dashboard.mode == before.mode)
        #expect(model.dashboard.config == before.config)
        #expect(model.dashboard.groups == before.groups)
        #expect(model.dashboard.rules == before.rules)
        #expect(model.dashboard.providers == before.providers)
        #expect(model.dashboard.insight == before.insight)
        #expect(model.policyGroupCatalog == beforeGroups)
        #expect(model.policyGroupCatalogRevision == beforeGroupRevision)
        #expect(model.connectionsCatalog.connections.count == 2)
        #expect(model.connectionsCatalog.traffic == TrafficSnapshot(upload: 8_000, download: 9_000))
        #expect(model.liveTrafficRate == TrafficSnapshot(upload: 77, download: 88))
        #expect(model.surgeSnapshot == next)

        model.flushSessionPublicationDomain(.connections, generation: model.controllerSession.generation, force: true)
        #expect(model.dashboard.insight.connectionCount == 2)
        #expect(model.dashboard.insight.ruleCount == before.insight.ruleCount)
        #expect(model.dashboard.insight.providerCount == before.insight.providerCount)
        #expect(model.dashboard.insight.routeHealth == before.insight.routeHealth)
        #expect(model.dashboard.insight.latencySampleCount == before.insight.latencySampleCount)
        #expect(model.dashboard.groups == before.groups)
        #expect(model.dashboard.rules == before.rules)
    }

    @MainActor
    @Test func newSessionBaselineReplacesPreviousControllerFieldsAndHonorsPause() {
        let profile = RouterProfile(displayName: "New Surge", host: "127.0.0.1", controllerKind: .surgeCompatible)
        var previous = DashboardSnapshot(surge: SurgeDomainProjectionFixture.snapshot())
        previous.versionLabel = "previous-controller"
        previous.mode = "previous-mode"
        let model = makeModel(dashboard: previous, profile: profile)
        model.controllerSession.begin(controllerID: profile.id)
        model.activeSessionControllerKind = .surgeCompatible
        let generation = model.controllerSession.generation
        let next = SurgeControlSnapshot(
            outbound: SurgeOutboundResponse(mode: "direct"),
            policies: SurgePoliciesResponse(policies: [SurgePolicy(name: "new-node", type: "trojan")]),
            policyGroups: SurgePolicyGroupsResponse(groups: [SurgePolicyGroup(name: "new-group", selected: "new-node", policies: ["new-node"])]),
            activeRequests: SurgeActiveRequestsResponse(requests: [SurgeActiveRequest(id: "new-request", policy: "new-node")]),
            checkedAt: Date(timeIntervalSince1970: 500)
        )
        model.stageSurgeSnapshot(next, receivedAt: Date(timeIntervalSince1970: 500), includesCompleteBaseline: true)
        model.dashboardSessionControls.setPresentationPaused(true)
        let pausedCommit = model.attemptSessionBaselineCommit(for: profile, generation: generation)
        #expect(!pausedCommit)
        #expect(model.dashboard == previous)
        model.dashboardSessionControls.setPresentationPaused(false)
        let obsoleteCommit = model.attemptSessionBaselineCommit(for: profile, generation: UUID())
        #expect(!obsoleteCommit)
        let committed = model.attemptSessionBaselineCommit(for: profile, generation: generation)
        #expect(committed)
        #expect(model.dashboard == DashboardSnapshot(surge: next, language: model.presentationLanguage))
        #expect(model.dashboard.groups.map(\.id) == ["new-group"])
        #expect(model.dashboard.rules.isEmpty)
        #expect(model.policyGroupCatalog.groups.map(\.id) == ["new-group"])
        #expect(model.controllerSession.hasCommittedBaseline)
    }

    @MainActor
    private func makeModel(dashboard: DashboardSnapshot, profile: RouterProfile? = nil) -> AppModel {
        AppModel(
            routers: profile.map { [$0] } ?? [],
            selectedRouterID: profile?.id,
            dashboard: dashboard,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
    }
}

enum SurgeDomainProjectionFixture {
    static func snapshot() -> SurgeControlSnapshot {
        SurgeControlSnapshot(
            policies: SurgePoliciesResponse(policies: [SurgePolicy(name: "Node A", type: "ss")]),
            policyGroups: SurgePolicyGroupsResponse(groups: [
                SurgePolicyGroup(name: "Manual", type: "select", selected: "Node A", policies: ["Node A"], latency: ["Node A": 45]),
            ]),
            activeRequests: SurgeActiveRequestsResponse(requests: [
                SurgeActiveRequest(
                    id: "shared", method: "TCP", url: "fixture.invalid", rule: "DOMAIN fixture.invalid",
                    ruleType: "DOMAIN", rulePayload: "fixture.invalid", policy: "Node A", originalPolicy: "Manual",
                    upload: 1_000, download: 2_000, sourceAddress: "192.0.2.1", sourcePort: "1234",
                    destinationAddress: "203.0.113.1", destinationPort: "443", localAddress: "127.0.0.1",
                    interfaceName: "fixture", process: "Fixture", processPath: "/Applications/Fixture.app",
                    uid: 501, notes: ["controller note"], status: "active", start: "2026-01-01T00:00:00Z",
                    fields: ["controller-extra": .object(["enabled": .bool(true)])]
                ),
                SurgeActiveRequest(id: "shared", originalPolicy: "Automatic", upload: 200, download: 300, uploadSpeed: 31, downloadSpeed: 47),
                SurgeActiveRequest(id: "", url: "other.invalid"),
            ]),
            rules: SurgeRulesResponse(rules: [SurgeRule(type: "DOMAIN", payload: "fixture.invalid", policy: "Manual")]),
            traffic: SurgeTrafficResponse(upload: 1_200, download: 2_300),
            checkedAt: Date(timeIntervalSince1970: 100)
        )
    }
}
