import Foundation
import MicaCore
import XCTest
@testable import Mica

@MainActor
final class SurgeDomainProjectionPerformanceTests: XCTestCase {
    func testNearLiveProjectionComparedWithFullSnapshot() throws {
        guard let path = ProcessInfo.processInfo.environment["MICA_SURGE_PROJECTION_REPORT"] else {
            throw XCTSkip("Set MICA_SURGE_PROJECTION_REPORT under tmp/codex for the Surge projection comparison.")
        }
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scratch = repository.appendingPathComponent("tmp/codex/").standardizedFileURL.resolvingSymlinksInPath()
        let output = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard output.path.hasPrefix(scratch.path + "/") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        var reports: [[String: Any]] = []
        for (groupCount, nodeCount, ruleCount, connectionCount) in [
            (24, 500, 5_000, 300), (64, 1_000, 20_000, 1_000),
        ] {
            let names = (0..<nodeCount).map { "Node \($0)" }
            var snapshot = SurgeControlSnapshot(
                policies: SurgePoliciesResponse(policies: names.map { SurgePolicy(name: $0, type: "ss") }),
                policyGroups: SurgePolicyGroupsResponse(groups: (0..<groupCount).map {
                    SurgePolicyGroup(name: "Group \($0)", type: "select", selected: names.first, policies: names)
                }),
                activeRequests: SurgeActiveRequestsResponse(requests: (0..<connectionCount).map {
                    SurgeActiveRequest(id: "request-\($0)", url: "fixture-\($0).invalid", policy: names[$0 % names.count], upload: $0 * 100, download: $0 * 200)
                }),
                rules: SurgeRulesResponse(rules: (0..<ruleCount).map {
                    SurgeRule(type: "DOMAIN", payload: "rule-\($0).invalid", policy: "Group \($0 % groupCount)")
                }),
                checkedAt: Date(timeIntervalSince1970: 100)
            )
            let model = AppModel(
                dashboard: DashboardSnapshot(surge: snapshot),
                profileStore: InMemoryRouterProfileStore(),
                secretStore: InMemorySecretStore()
            )
            var fullTimes: [Double] = []
            var partialTimes: [Double] = []
            var checksum = 0
            for iteration in 0..<11 {
                snapshot.activeRequests[0].upload = iteration
                snapshot.traffic.upload = iteration * 7
                let startFull = ContinuousClock.now
                let full = model.projectedSurgeDashboard(snapshot, connectionRatesReceivedAt: nil)
                let fullDuration = startFull.duration(to: .now)
                let startPartial = ContinuousClock.now
                let partial = model.projectedSurgeDashboard(
                    snapshot, connectionRatesReceivedAt: nil, domains: [.connections, .insight]
                )
                let partialDuration = startPartial.duration(to: .now)
                XCTAssertEqual(partial, full)
                checksum += partial.connections.count + partial.rules.count + partial.groups.count
                if iteration >= 2 {
                    fullTimes.append(milliseconds(fullDuration))
                    partialTimes.append(milliseconds(partialDuration))
                }
            }
            fullTimes.sort()
            partialTimes.sort()
            reports.append([
                "groups": groupCount, "nodesPerGroup": nodeCount,
                "rules": ruleCount, "connections": connectionCount,
                "samples": fullTimes.count,
                "fullMedianMilliseconds": fullTimes[fullTimes.count / 2],
                "connectionDomainMedianMilliseconds": partialTimes[partialTimes.count / 2],
                "fullMaximumMilliseconds": fullTimes.last ?? 0,
                "connectionDomainMaximumMilliseconds": partialTimes.last ?? 0,
                "checksum": checksum,
            ])
        }
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let report: [String: Any] = [
            "configuration": configuration,
            "scope": "MainActor Surge dashboard projection, full vs connections+insight on identical snapshots; excludes network, log staging, SwiftUI layout and compositor.",
            "cases": reports,
        ]
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        print("Surge projection comparison: \(reports)")
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }
}
