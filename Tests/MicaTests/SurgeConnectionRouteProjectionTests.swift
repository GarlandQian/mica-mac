import Foundation
import MicaCore
import Testing
@testable import Mica

struct SurgeConnectionRouteProjectionTests {
    @Test func aReportedFinalPolicyDoesNotInventAnOriginalPolicy() throws {
        let request = try decode(#"{"id":"final-only","policyName":"Node A","sourceAddress":"192.0.2.10"}"#)

        for connection in projectedConnections(for: request) {
            #expect(connection.chains == ["Node A"])
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
            #expect(connection.metadata?.sourceIP == "192.0.2.10")
        }
    }

    @Test func equalPolicyNamesPreserveBothReportedRoles() throws {
        let request = try decode(#"{"id":"same","policyName":"DIRECT","originalPolicyName":"DIRECT","sourceAddress":"192.0.2.10"}"#)

        for connection in projectedConnections(for: request) {
            #expect(connection.chains == ["DIRECT", "DIRECT"])
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
            #expect(connection.metadata?.sourceIP == "192.0.2.10")
            #expect(connection.metadata?.destinationIP == "203.0.113.10")
            #expect(connection.upload == 1024)
            #expect(connection.download == 2048)
            #expect(connection.uploadSpeed == 128)
            #expect(connection.downloadSpeed == 256)
            #expect(connection.fields["controllerField"] == .object(["reported": .bool(true)]))
        }
    }

    @Test(arguments: [
        #"{"id":"empty","sourceAddress":"192.0.2.10"}"#,
        #"{"id":"empty","policyName":"","originalPolicyName":"","sourceAddress":"192.0.2.10"}"#,
        #"{"id":"empty","policyName":" \n","originalPolicyName":" \t","sourceAddress":"192.0.2.10"}"#,
    ])
    func absentPolicyFieldsRemainEmptyChains(json: String) throws {
        let request = try decode(json)

        for connection in projectedConnections(for: request) {
            let nonBlankChains = (connection.chains ?? []).filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            #expect(nonBlankChains.isEmpty)
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
            #expect(connections.map { $0.chains?.first ?? "" } == ["Node B", "", "Node A"])
            #expect(connections.map { $0.chains?.last } == ["Proxy", "Proxy", "Proxy"])
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
}
