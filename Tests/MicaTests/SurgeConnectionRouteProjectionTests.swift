import Foundation
import MicaCore
import Testing
@testable import Mica

struct SurgeConnectionRouteProjectionTests {
    @Test func aReportedFinalPolicyDoesNotInventAnOriginalPolicy() throws {
        let request = try decode(#"{"id":"final-only","policyName":"Node A","sourceAddress":"192.0.2.10"}"#)

        for connection in projectedConnections(for: request) {
            #expect(connection.chains == ["Node A"])
            let path = try projectedPath(for: connection)
            #expect(path.finalOutbound == "Node A")
            #expect(path.policyHops.isEmpty)
            #expect(path.routeState == .available)
        }
    }

    @Test(arguments: [
        #"{"id":"original-only","originalPolicyName":"Proxy","sourceAddress":"192.0.2.10"}"#,
        #"{"id":"original-only","policyName":"","originalPolicyName":"Proxy","sourceAddress":"192.0.2.10"}"#,
        #"{"id":"original-only","policyName":null,"originalPolicyName":"Proxy","sourceAddress":"192.0.2.10"}"#,
        #"{"id":"original-only","policyName":" \n","originalPolicyName":"Proxy","sourceAddress":"192.0.2.10"}"#,
    ])
    func anOriginalPolicyNeverBecomesAnUnreportedFinalOutbound(json: String) throws {
        let request = try decode(json)

        for connection in projectedConnections(for: request) {
            #expect(connection.chains?.count == 2)
            #expect(connection.chains?.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "")
            #expect(connection.chains?.last == "Proxy")
            let topology = ConnectionTopologyBuilder.build(from: [connection])
            let path = try #require(topology.paths.first)
            #expect(path.source == "192.0.2.10")
            #expect(path.policyHops == ["Proxy"])
            #expect(path.finalOutbound == nil)
            #expect(path.routeState == .routeUnavailable(.missingChain))
            #expect(path.edgeIDs.isEmpty)
            #expect(topology.edges.isEmpty)
            #expect(topology.drawableConnectionCount == 0)
        }
    }

    @Test func equalPolicyNamesPreserveBothReportedRoles() throws {
        let request = try decode(#"{"id":"same","policyName":"DIRECT","originalPolicyName":"DIRECT","sourceAddress":"192.0.2.10"}"#)

        for connection in projectedConnections(for: request) {
            #expect(connection.chains == ["DIRECT", "DIRECT"])
            let path = try projectedPath(for: connection)
            #expect(path.policyHops == ["DIRECT"])
            #expect(path.finalOutbound == "DIRECT")
            #expect(path.stages.map(\.columnID) == [.source, .rule, .policyHop(0), .finalOutbound])
            #expect(Set(path.nodeIDs).count == path.nodeIDs.count)
            #expect(path.routeState == .available)
        }
    }

    @Test func reportedOriginalPolicyPrecedesTheFinalOutboundWithoutInventedIntermediateHops() throws {
        let request = try decode(#"""
        {
          "requestId": "normal",
          "policyName": "Node A",
          "originalPolicyName": "Proxy",
          "ruleName": "DOMAIN-SUFFIX example.com",
          "clientAddress": "192.0.2.10",
          "remoteAddress": "203.0.113.10",
          "outBytes": 1024,
          "inBytes": 2048,
          "outCurrentSpeed": 128,
          "inCurrentSpeed": 256,
          "controllerField": { "reported": true }
        }
        """#)

        for connection in projectedConnections(for: request) {
            #expect(connection.chains == ["Node A", "Proxy"])
            #expect(connection.metadata?.specialProxy == "Node A")
            #expect(connection.metadata?.destinationIP == "203.0.113.10")
            #expect(connection.upload == 1024)
            #expect(connection.download == 2048)
            #expect(connection.uploadSpeed == 128)
            #expect(connection.downloadSpeed == 256)
            #expect(connection.fields["controllerField"] == .object(["reported": .bool(true)]))
            let path = try projectedPath(for: connection)
            #expect(path.policyHops == ["Proxy"])
            #expect(path.finalOutbound == "Node A")
            #expect(path.stages.map(\.name) == [
                "192.0.2.10", "DOMAIN-SUFFIX: example.com", "Proxy", "Node A",
            ])
            #expect(path.routeState == .available)
        }
    }

    @Test(arguments: [
        #"{"id":"empty","sourceAddress":"192.0.2.10"}"#,
        #"{"id":"empty","policyName":"","originalPolicyName":"","sourceAddress":"192.0.2.10"}"#,
        #"{"id":"empty","policyName":" \n","originalPolicyName":" \t","sourceAddress":"192.0.2.10"}"#,
    ])
    func absentPolicyFieldsRemainAnUnavailableRoute(json: String) throws {
        let request = try decode(json)

        for connection in projectedConnections(for: request) {
            let path = try projectedPath(for: connection)
            #expect(path.finalOutbound == nil)
            #expect(path.policyHops.isEmpty)
            #expect(path.routeState == .routeUnavailable(.missingChain))
            #expect(path.edgeIDs.isEmpty)
        }
    }

    @Test func partialRoutesStayInControllerOrderAndCannotBorrowAnotherRequestsFinalOutbound() throws {
        let requests = [
            SurgeActiveRequest(id: "repeated", policy: "Node B", originalPolicy: "Proxy", sourceAddress: "192.0.2.10"),
            SurgeActiveRequest(id: "repeated", originalPolicy: "Proxy", sourceAddress: "192.0.2.10"),
            SurgeActiveRequest(id: "last", policy: "Node A", originalPolicy: "Proxy", sourceAddress: "192.0.2.10"),
        ]
        let dashboard = DashboardSnapshot(
            surge: SurgeControlSnapshot(activeRequests: SurgeActiveRequestsResponse(requests: requests)),
            language: .english
        )
        for connections in [
            dashboard.connections,
            DashboardSnapshot.surgeRecentRequestConnections(for: requests, language: .english),
        ] {
            #expect(connections.map(\.id) == ["repeated", "repeated#2", "last"])
            let topology = ConnectionTopologyBuilder.build(from: connections)
            #expect(topology.connectionCount == 3)
            #expect(topology.drawableConnectionCount == 2)
            #expect(topology.routeUnavailableCount == 1)
            #expect(topology.paths.map(\.finalOutbound) == ["Node B", nil, "Node A"])
            #expect(topology.paths.map(\.policyHops) == [["Proxy"], ["Proxy"], ["Proxy"]])
            #expect(topology.paths[1].edgeIDs.isEmpty)
        }
    }

    private func decode(_ json: String) throws -> SurgeActiveRequest {
        try JSONDecoder().decode(SurgeActiveRequest.self, from: Data(json.utf8))
    }

    private func projectedConnections(for request: SurgeActiveRequest) -> [ConnectionSnapshot] {
        let dashboard = DashboardSnapshot(
            surge: SurgeControlSnapshot(activeRequests: SurgeActiveRequestsResponse(requests: [request])),
            language: .english
        )
        return dashboard.connections + DashboardSnapshot.surgeRecentRequestConnections(
            for: [request],
            language: .english
        )
    }

    private func projectedPath(for connection: ConnectionSnapshot) throws -> ConnectionTopology.PathRecord {
        try #require(ConnectionTopologyBuilder.build(from: [connection]).paths.first)
    }
}
