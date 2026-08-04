import Foundation
import MicaCore
import Testing
@testable import Mica

struct DashboardInsightPerformanceTests {
    @Test func metricsOnlyConnectionRefreshPreservesStaticInsightDomains() {
        let group = ProxyGroupViewState(
            id: "Group",
            type: "select",
            selected: "Node",
            options: ["Node"],
            delays: ["Node": 90]
        )
        var dashboard = DashboardSnapshot(
            versionLabel: "1.0",
            mode: "Rule",
            traffic: TrafficSnapshot(upload: 10, download: 20),
            groups: [group],
            connections: [ConnectionSnapshot(id: "a", upload: 1, download: 2)],
            rules: [RuleViewState(id: "rule", type: "MATCH", payload: "", proxy: "DIRECT")],
            providers: [ProxyProviderViewState(name: "provider", type: "Proxy", itemCount: 1)]
        )
        let distribution = dashboard.insight.connectionDistribution
        let routeHealth = dashboard.insight.routeHealth
        let ruleCount = dashboard.insight.ruleCount
        let providerCount = dashboard.insight.providerCount

        dashboard.replaceConnections(
            with: ConnectionsResponse(
                uploadTotal: 10,
                downloadTotal: 20,
                connections: [ConnectionSnapshot(id: "a", upload: 300, download: 400)]
            ),
            structureChanged: false,
            metricsChanged: true,
            trafficChanged: false
        )

        #expect(dashboard.insight.connectionDistribution == distribution)
        #expect(dashboard.insight.routeHealth == routeHealth)
        #expect(dashboard.insight.ruleCount == ruleCount)
        #expect(dashboard.insight.providerCount == providerCount)
        #expect(dashboard.insight.topConnections.first?.upload == 300)
    }

    @Test func connectionTopKIsBoundedAndDeterministic() {
        let connections = (0..<100).map { index in
            ConnectionSnapshot(
                id: String(format: "connection-%03d", index),
                upload: index * 10,
                download: index
            )
        }
        let insight = InsightSummarySnapshot(
            snapshot: DashboardSnapshot(
                versionLabel: "1.0",
                mode: "Rule",
                traffic: TrafficSnapshot(upload: 0, download: 0),
                groups: [],
                connections: connections
            )
        )

        #expect(insight.topConnections.count == 5)
        #expect(insight.topConnections.map(\.id) == [
            "connection-099",
            "connection-098",
            "connection-097",
            "connection-096",
            "connection-095",
        ])
    }
}
