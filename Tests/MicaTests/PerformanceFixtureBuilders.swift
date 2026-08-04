import Foundation
import MicaCore
@testable import Mica

enum MicaPerformanceFixtures {
    enum TopologyShape: Equatable {
        case shared
        case unique
    }

    static func connections(
        count: Int,
        topology: TopologyShape = .unique
    ) -> [ConnectionSnapshot] {
        (0..<count).map { index in
            let routeIndex = topology == .shared ? 0 : index
            return ConnectionSnapshot(
                id: "connection-\(index)",
                upload: index * 97,
                download: index * 193,
                uploadSpeed: index % 8_192,
                downloadSpeed: index % 16_384,
                start: "2026-07-29T08:\(String(format: "%02d", index % 60)):00Z",
                chains: [
                    "outbound-\(routeIndex % 31)",
                    "policy-2-\(routeIndex % 17)",
                    "policy-1-\(routeIndex % 13)",
                ],
                providerChains: ["provider-\(routeIndex % 11)"],
                rule: "RuleSet",
                rulePayload: "fixture-\(routeIndex % 101)",
                metadata: ConnectionMetadataSnapshot(
                    host: "host-\(index).example.test",
                    network: index.isMultiple(of: 2) ? "tcp" : "udp",
                    type: "fixture",
                    sourceIP: "192.0.2.\((index % 250) + 1)",
                    destinationIP: "198.51.100.\((index % 250) + 1)",
                    sourcePort: String(10_000 + (index % 50_000)),
                    destinationPort: index.isMultiple(of: 2) ? "443" : "53",
                    process: "FixtureProcess-\(index % 19)",
                    processPath: "/Applications/Fixture-\(index % 19).app/Contents/MacOS/Fixture",
                    inboundName: "inbound-\(routeIndex % 7)"
                )
            )
        }
    }

    static func topologyConnections(
        count: Int,
        shape: TopologyShape
    ) -> [ConnectionSnapshot] {
        connections(count: count, topology: shape)
    }

    static func logs(count: Int) -> [ControllerLogEntry] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            ControllerLogEntry(
                id: "log-\(index)",
                receivedAt: base.addingTimeInterval(TimeInterval(index) / 10),
                message: LogMessage(
                    type: index.isMultiple(of: 17) ? "warning" : "info",
                    payload: "fixture log payload \(index) route=policy-\(index % 13)",
                    time: "08:\(String(format: "%02d", index % 60)):\(String(format: "%02d", index % 60))",
                    level: index.isMultiple(of: 17) ? "warning" : "info",
                    fields: .object([
                        "sequence": .number(Double(index)),
                        "source": .string("performance-fixture"),
                    ])
                )
            )
        }
    }
}
