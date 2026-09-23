import Foundation
import MicaCore
import Testing
import XCTest
@testable import Mica

/// Covers the production refresh projection that runs before any page cache.
/// Every group deliberately shares nodes, as routing configurations often do.
@MainActor
final class MihomoPolicyRefreshPerformanceTests: XCTestCase {
    func testSharedNodeRefreshProjection() throws {
        guard let path = ProcessInfo.processInfo.environment["MICA_POLICY_REFRESH_REPORT"] else {
            throw XCTSkip("Set MICA_POLICY_REFRESH_REPORT under tmp/codex for the refresh projection benchmark.")
        }
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scratch = repository.appendingPathComponent("tmp/codex/").standardizedFileURL.resolvingSymlinksInPath()
        let output = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard output.path.hasPrefix(scratch.path + "/") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        var reports: [[String: Any]] = []
        for (groupCount, nodeCount) in [(24, 500), (64, 1_000)] {
            let frames = (0..<2).map { sharedPolicyFixture(groups: groupCount, nodes: nodeCount, revision: $0) }
            var dashboard = DashboardSnapshot.empty
            var times: [Double] = []
            var checksum = 0
            for iteration in 0..<9 {
                let start = ContinuousClock.now
                dashboard.replaceGroups(with: frames[iteration % frames.count])
                let duration = start.duration(to: .now).components
                if iteration > 1 {
                    times.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
                }
                XCTAssertEqual(dashboard.groups.count, groupCount)
                XCTAssertTrue(dashboard.groups.allSatisfy { $0.options.count == nodeCount && $0.optionDetails.count == nodeCount })
                checksum += dashboard.groups.reduce(0) { $0 + $1.optionDetails.count }
            }
            times.sort()
            reports.append([
                "groups": groupCount, "uniqueNodes": nodeCount,
                "memberOccurrences": groupCount * nodeCount, "samples": times.count,
                "medianMilliseconds": times[times.count / 2],
                "maximumMilliseconds": times.last ?? 0,
                "checksum": checksum,
            ])
        }
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let report: [String: Any] = [
            "label": ProcessInfo.processInfo.environment["MICA_PERFORMANCE_LABEL"] ?? "current",
            "configuration": configuration,
            "scope": "MainActor DashboardSnapshot.replaceGroups, including shared node metadata and search projection; excludes network, SwiftUI layout and compositor.",
            "cases": reports,
        ]
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        print("Policy refresh projection: \(reports)")
    }
}

struct MihomoPolicyRefreshCorrectnessTests {
    @Test func sharedMembersRetainEveryReportedFieldAndRefreshOnTheNextResponse() throws {
        var dashboard = DashboardSnapshot.empty
        for revision in 0..<2 {
            let response = sharedPolicyFixture(groups: 3, nodes: 4, revision: revision)
            dashboard.replaceGroups(with: response)
            for group in dashboard.groups {
                for name in group.options {
                    let reported = try #require(response.proxies[name])
                    #expect(group.optionDetails[name] == ProxyNodeViewState(snapshot: reported))
                }
            }
            #expect(dashboard.groups.first?.optionDetails["Node 0"]?.history.last?.delay == 20 + revision)
        }
    }

    @Test func sharingDoesNotMixGroupSpecificDelayOrOptionOrder() {
        var dashboard = DashboardSnapshot.empty
        var response = sharedPolicyFixture(groups: 2, nodes: 3, revision: 0)
        response.proxies["Group 1"]?.all = ["Node 2", "Node 0", "Node 1", "not reported", "Node 0"]
        dashboard.replaceGroups(with: response)
        dashboard.replaceDelays(["Node 0": 11], in: "Group 0")
        dashboard.replaceDelays(["Node 0": 99], in: "Group 1")
        dashboard.replaceGroups(with: response)
        #expect(dashboard.groups[0].delays["Node 0"] == 11)
        #expect(dashboard.groups[1].delays["Node 0"] == 99)
        #expect(dashboard.groups[1].options == ["Node 2", "Node 0", "Node 1", "not reported", "Node 0"])
        #expect(dashboard.groups[1].optionDetails["not reported"] == nil)
        #expect(dashboard.groups[1].optionDetails.count == 3)
    }
}

private func sharedPolicyFixture(groups: Int, nodes: Int, revision: Int) -> ProxiesResponse {
    let names = (0..<nodes).map { "Node \($0)" }
    var snapshots: [String: ProxySnapshot] = [:]
    for (index, name) in names.enumerated() {
        snapshots[name] = ProxySnapshot(
            name: name, type: "Shadowsocks", alive: true,
            history: (0..<5).map { .init(time: "2026-09-23T00:00:0\($0)Z", delay: 16 + index + $0 + revision) },
            providerName: "Provider \(index % 8)", udp: true, tfo: false,
            metadata: [
                "server": .string("node-\(index).example.invalid"),
                "port": .number(443), "cipher": .string("aes-128-gcm"),
                "extension": .object(["interfaces": .array([.string("en0"), .string("utun1")]), "weight": .number(Double(index))]),
                "controller-state": .object(["available": .bool(true), "revision": .number(Double(revision))]),
            ]
        )
    }
    let groupNames = (0..<groups).map { "Group \($0)" }
    for name in groupNames {
        snapshots[name] = ProxySnapshot(name: name, type: "Selector", now: names.first, all: names)
    }
    return ProxiesResponse(proxies: snapshots, proxyOrder: groupNames + names)
}
