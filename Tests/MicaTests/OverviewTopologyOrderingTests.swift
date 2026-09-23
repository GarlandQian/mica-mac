import Foundation
import MicaCore
import Testing
@testable import Mica

struct OverviewTopologyOrderingTests {
    @Test func downstreamRefinementReducesCrossingsMissedByForwardPass() throws {
        let topology = makeTopology(paths: [
            ["A1", "B2", "C2", "D0"],
            ["A1", "B0", "C0", "D1"],
            ["A2", "B1", "C1", "D1"],
            ["A2", "B1", "C2", "D2"],
            ["A0", "B0", "C1", "D0"],
            ["A1", "B0", "C0", "D0"],
            ["A1", "B0", "C0", "D0"],
            ["A2", "B1", "C0", "D2"],
            ["A1", "B0", "C1", "D1"],
        ])

        let baseline = forwardOnlyColumns(in: topology)
        let refined = try OverviewTopologyOrdering.orderedColumns(in: topology)

        #expect(crossings(in: baseline, topology: topology) == 7)
        #expect(crossings(in: refined, topology: topology) == 4)
        #expect(refined[0].map(\.name) == ["A0", "A1", "A2"])
    }

    @Test func refinementPreservesEveryNodeAndIsDeterministic() throws {
        let topology = makeTopology(paths: (0..<72).map { index in
            [
                "source-\(index % 7)",
                "rule-\((index * 3) % 11)",
                "group-\((index * 5) % 13)",
                "exit-\((index * 7) % 17)",
            ]
        })
        let expected = try OverviewTopologyOrdering.orderedColumns(in: topology)

        #expect(expected.count == topology.columns.count)
        for (original, ordered) in zip(topology.columns, expected) {
            #expect(ordered.count == original.nodes.count)
            #expect(Set(ordered.map(\.id)) == Set(original.nodes.map(\.id)))
            for node in ordered {
                #expect(original.nodes.first { $0.id == node.id } == node)
            }
        }
        for _ in 0..<10 {
            #expect(try OverviewTopologyOrdering.orderedColumns(in: topology) == expected)
        }
    }

    @Test func mixedRouteFixturesNeverRegressFromForwardOrder() throws {
        var seed: UInt64 = 1_437
        func next() -> Int {
            seed = (seed &* 1_664_525 &+ 1_013_904_223) & 0xffff_ffff
            return Int(seed >> 16)
        }

        for _ in 0..<24 {
            let topology = makeTopology(paths: (0..<32).map { _ in
                ["A\(next() % 5)", "B\(next() % 7)", "C\(next() % 6)", "D\(next() % 5)"]
            })
            let baseline = forwardOnlyColumns(in: topology)
            let refined = try OverviewTopologyOrdering.orderedColumns(in: topology)

            #expect(
                crossings(in: refined, topology: topology)
                    <= crossings(in: baseline, topology: topology)
            )
            #expect(refined[0] == baseline[0])
        }
    }

    @Test func emptyAndAlreadyParallelRoutesRemainComplete() throws {
        #expect(try OverviewTopologyOrdering.orderedColumns(in: .empty).isEmpty)
        let topology = makeTopology(paths: [
            ["A0", "B0", "C0", "D0"],
            ["A1", "B1", "C1", "D1"],
            ["A2", "B2", "C2", "D2"],
        ])
        let ordered = try OverviewTopologyOrdering.orderedColumns(in: topology)

        #expect(crossings(in: ordered, topology: topology) == 0)
        #expect(ordered == forwardOnlyColumns(in: topology))
    }

    @Test func routesSkippingStagesRetainTheirNodesAndOrderingGuard() throws {
        let topology = ConnectionTopologyBuilder.build(from: [
            ConnectionSnapshot(
                id: "deep",
                chains: ["Exit B", "Hop B", "Hop A"],
                rule: "RuleSet",
                rulePayload: "Proxy",
                metadata: ConnectionMetadataSnapshot(sourceIP: "Source A")
            ),
            ConnectionSnapshot(
                id: "direct",
                chains: ["DIRECT"],
                metadata: ConnectionMetadataSnapshot(sourceIP: "Source B")
            ),
            ConnectionSnapshot(
                id: "short",
                chains: ["Exit A", "Hop A"],
                metadata: ConnectionMetadataSnapshot(sourceIP: "Source C")
            ),
        ])
        let ordered = try OverviewTopologyOrdering.orderedColumns(in: topology)

        #expect(ordered.count == topology.columns.count)
        #expect(Set(ordered.flatMap { $0.map(\.id) }) == Set(topology.nodes.map(\.id)))
        #expect(
            crossings(in: ordered, topology: topology)
                <= crossings(in: forwardOnlyColumns(in: topology), topology: topology)
        )
    }

    @Test func alreadyCancelledTaskDoesNotCompleteOrdering() async {
        let topology = makeTopology(paths: (0..<2_000).map { index in
            ["A\(index % 17)", "B\(index % 23)", "C\(index % 29)", "D\(index % 31)"]
        })
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try OverviewTopologyOrdering.orderedColumns(in: topology)
        }

        do {
            _ = try await task.value
            Issue.record("A cancelled topology ordering unexpectedly completed")
        } catch is CancellationError {
            // A cancelled session must not produce a replacement presentation.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
    }

    private func makeTopology(paths: [[String]]) -> ConnectionTopology {
        ConnectionTopologyBuilder.build(from: paths.enumerated().map { index, path in
            ConnectionSnapshot(
                id: "connection-\(index)",
                chains: [path[3], path[2]],
                rule: "RuleSet",
                rulePayload: path[1],
                metadata: ConnectionMetadataSnapshot(sourceIP: path[0])
            )
        })
    }

    /// The previous layout contract: source name order, then one upstream pass.
    private func forwardOnlyColumns(
        in topology: ConnectionTopology
    ) -> [[ConnectionTopology.Node]] {
        var slots: [String: Int] = [:]
        var columns: [[ConnectionTopology.Node]] = []
        for (index, column) in topology.columns.enumerated() {
            func key(_ node: ConnectionTopology.Node) -> Double {
                guard index > 0 else { return 0 }
                var sum = 0.0
                var weight = 0.0
                for edge in topology.edges where edge.targetID == node.id {
                    guard let slot = slots[edge.sourceID] else { continue }
                    let value = max(log10(Double(edge.connectionCount) + 1) * 10, 1)
                    sum += Double(slot) * value
                    weight += value
                }
                return weight > 0 ? sum / weight : .greatestFiniteMagnitude
            }
            let ordered = column.nodes.sorted { left, right in
                let leftKey = key(left)
                let rightKey = key(right)
                if leftKey != rightKey { return leftKey < rightKey }
                let comparison = left.name.localizedCaseInsensitiveCompare(right.name)
                return comparison == .orderedSame
                    ? left.id < right.id
                    : comparison == .orderedAscending
            }
            for (slot, node) in ordered.enumerated() { slots[node.id] = slot }
            columns.append(ordered)
        }
        return columns
    }

    /// Intentionally simple pairwise oracle for small test fixtures, independent
    /// of the production inversion counter and excluding shared endpoints.
    private func crossings(
        in columns: [[ConnectionTopology.Node]],
        topology: ConnectionTopology
    ) -> Int {
        var slots: [String: Int] = [:]
        for column in columns {
            for (slot, node) in column.enumerated() { slots[node.id] = slot }
        }
        var result = 0
        for (index, left) in topology.edges.enumerated() {
            for right in topology.edges.dropFirst(index + 1) {
                guard left.sourceColumnID == right.sourceColumnID,
                      left.targetColumnID == right.targetColumnID,
                      let leftSource = slots[left.sourceID],
                      let rightSource = slots[right.sourceID],
                      let leftTarget = slots[left.targetID],
                      let rightTarget = slots[right.targetID] else { continue }
                if (leftSource - rightSource) * (leftTarget - rightTarget) < 0 {
                    result += 1
                }
            }
        }
        return result
    }
}
