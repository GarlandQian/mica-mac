import Foundation
import MicaCore
import Testing
@testable import Mica

struct ConnectionTopologyTests {
    private func connection(
        id: String,
        sourceIP: String? = nil,
        process: String? = nil,
        inboundName: String? = nil,
        rule: String? = nil,
        rulePayload: String? = nil,
        chains: [String]?
    ) -> ConnectionSnapshot {
        ConnectionSnapshot(
            id: id,
            chains: chains,
            rule: rule,
            rulePayload: rulePayload,
            metadata: ConnectionMetadataSnapshot(
                sourceIP: sourceIP,
                process: process,
                inboundName: inboundName
            )
        )
    }

    private func requireSendable<Value: Sendable>(_: Value) {}

    @Test func completePathUsesDynamicDepthAndPreservesChainSemantics() throws {
        let topology = ConnectionTopologyBuilder.build(from: [
            connection(
                id: "1",
                sourceIP: "192.168.8.2",
                rule: "RuleSet",
                rulePayload: "Streaming",
                chains: [" Final Outbound ", "Hop 3", " ", "Hop 2", "Hop 1"]
            ),
        ])

        let path = try #require(topology.paths.first)
        #expect(path.routeState == .available)
        #expect(path.source == "192.168.8.2")
        #expect(path.rule == "RuleSet: Streaming")
        #expect(path.policyHops == ["Hop 1", "Hop 2", "Hop 3"])
        #expect(path.finalOutbound == "Final Outbound")
        #expect(path.stages.map(\.name) == [
            "192.168.8.2",
            "RuleSet: Streaming",
            "Hop 1",
            "Hop 2",
            "Hop 3",
            "Final Outbound",
        ])
        #expect(topology.columns.map(\.id) == [
            .source,
            .rule,
            .policyHop(0),
            .policyHop(1),
            .policyHop(2),
            .finalOutbound,
        ])
        #expect(topology.edges.map { "\($0.sourceName)->\($0.targetName)" } == [
            "192.168.8.2->RuleSet: Streaming",
            "RuleSet: Streaming->Hop 1",
            "Hop 1->Hop 2",
            "Hop 2->Hop 3",
            "Hop 3->Final Outbound",
        ])
    }

    @Test func processAndInboundRemainRealSourceFallbacksWithoutFabricatedRule() {
        let topology = ConnectionTopologyBuilder.build(from: [
            connection(id: "1", process: "curl", chains: ["DIRECT"]),
            connection(id: "2", inboundName: "Mixed Inbound", chains: ["Proxy"]),
        ])

        #expect(topology.paths.map(\.source) == ["curl", "Mixed Inbound"])
        #expect(topology.paths.allSatisfy { $0.rule == nil })
        #expect(topology.columns.map(\.id) == [.source, .finalOutbound])
        #expect(topology.edges.map { "\($0.sourceName)->\($0.targetName)" } == [
            "curl->DIRECT",
            "Mixed Inbound->Proxy",
        ])
    }

    @Test func everyConnectionAndCompletePathIsAdmittedWithoutCaps() throws {
        let connections = (0..<80).map { index in
            connection(
                id: "connection-\(index)",
                sourceIP: "source-\(index)",
                chains: [
                    "final-\(index)",
                    "hop-4-\(index)",
                    "hop-3-\(index)",
                    "hop-2-\(index)",
                    "hop-1-\(index)",
                ]
            )
        }

        let topology = ConnectionTopologyBuilder.build(from: connections)

        #expect(topology.connectionCount == 80)
        #expect(topology.drawableConnectionCount == 80)
        #expect(topology.routeUnavailableCount == 0)
        #expect(topology.paths.count == 80)
        #expect(topology.nodes.count == 480)
        #expect(topology.edges.count == 400)
        #expect(topology.columns.map(\.id) == [
            .source,
            .policyHop(0),
            .policyHop(1),
            .policyHop(2),
            .policyHop(3),
            .finalOutbound,
        ])
        for column in topology.columns {
            #expect(column.nodes.count == 80)
        }
        for (index, path) in topology.paths.enumerated() {
            #expect(path.sourceIndex == index)
            #expect(path.stages.count == 6)
            #expect(path.edgeIDs.count == 5)
        }

        let lastPath = try #require(topology.paths.last)
        #expect(lastPath.stages.map(\.name) == [
            "source-79",
            "hop-1-79",
            "hop-2-79",
            "hop-3-79",
            "hop-4-79",
            "final-79",
        ])
    }

    @Test func sharedVerticesAndEdgesRetainEveryPathMembership() {
        let topology = ConnectionTopologyBuilder.build(from: [
            connection(
                id: "shared",
                sourceIP: "10.0.0.2",
                rule: "MATCH",
                chains: ["Final", "Hop 2", "Hop 1"]
            ),
            connection(
                id: "shared",
                sourceIP: "10.0.0.2",
                rule: "MATCH",
                chains: ["Final", "Hop 2", "Hop 1"]
            ),
        ])

        let pathIDs = topology.paths.map(\.id)
        #expect(pathIDs.count == 2)
        #expect(Set(pathIDs).count == 2)
        #expect(topology.nodes.count == 5)
        #expect(topology.edges.count == 4)
        #expect(topology.nodes.allSatisfy { $0.pathIDs == pathIDs })
        #expect(topology.edges.allSatisfy { $0.pathIDs == pathIDs })
        #expect(topology.nodes.allSatisfy { $0.connectionCount == 2 })
        #expect(topology.edges.allSatisfy { $0.connectionCount == 2 })
        #expect(topology.paths.allSatisfy { $0.edgeIDs == topology.edges.map(\.id) })
    }

    @Test func missingSourceOrChainCreatesUnavailableRecordsWithoutGraphEdges() {
        let unavailableConnections = [
            connection(id: "missing-source", chains: ["Final"]),
            connection(id: "missing-chain", sourceIP: "10.0.0.2", chains: nil),
            connection(id: "missing-both", chains: []),
            connection(
                id: "blank-final",
                sourceIP: "10.0.0.3",
                chains: [" ", "Known Hop", ""]
            ),
        ]
        let unavailableTopology = ConnectionTopologyBuilder.build(from: unavailableConnections)

        #expect(unavailableTopology.connectionCount == 4)
        #expect(unavailableTopology.drawableConnectionCount == 0)
        #expect(unavailableTopology.routeUnavailableCount == 4)
        #expect(unavailableTopology.paths.map(\.routeState) == [
            .routeUnavailable(.missingSource),
            .routeUnavailable(.missingChain),
            .routeUnavailable(.missingSourceAndChain),
            .routeUnavailable(.missingChain),
        ])
        #expect(unavailableTopology.paths.allSatisfy { $0.edgeIDs.isEmpty })
        #expect(unavailableTopology.paths[3].policyHops == ["Known Hop"])
        #expect(unavailableTopology.paths[3].finalOutbound == nil)
        #expect(unavailableTopology.columns.isEmpty)
        #expect(unavailableTopology.edges.isEmpty)
        #expect(unavailableTopology.isEmpty)

        let mixedTopology = ConnectionTopologyBuilder.build(from: unavailableConnections + [
            connection(id: "valid", sourceIP: "10.0.0.4", chains: ["DIRECT"]),
        ])
        #expect(mixedTopology.connectionCount == 5)
        #expect(mixedTopology.drawableConnectionCount == 1)
        #expect(mixedTopology.nodes.map(\.name) == ["10.0.0.4", "DIRECT"])
        #expect(mixedTopology.edges.map { "\($0.sourceName)->\($0.targetName)" } == [
            "10.0.0.4->DIRECT",
        ])
    }

    @Test func duplicateAndBlankConnectionIDsReceiveStableOccurrenceIdentities() {
        let connections = [
            connection(id: "dup", sourceIP: "source", chains: ["DIRECT"]),
            connection(id: "dup", sourceIP: "source", chains: ["DIRECT"]),
            connection(id: "  ", sourceIP: "source", chains: ["DIRECT"]),
            connection(id: "", sourceIP: "source", chains: ["DIRECT"]),
            connection(id: "unique", sourceIP: "source", chains: ["DIRECT"]),
            connection(id: "dup", sourceIP: "source", chains: ["DIRECT"]),
        ]

        let topology = ConnectionTopologyBuilder.build(from: connections)
        let rebuilt = ConnectionTopologyBuilder.build(from: connections)
        let expectedReportedIDs: [String?] = ["dup", "dup", nil, nil, "unique", "dup"]

        #expect(topology == rebuilt)
        #expect(topology.paths.map { $0.id.reportedID } == expectedReportedIDs)
        #expect(topology.paths.map { $0.id.occurrence } == [0, 1, 0, 1, 0, 2])
        #expect(topology.paths.map(\.reportedConnectionID) == [
            "dup",
            "dup",
            "  ",
            "",
            "unique",
            "dup",
        ])
        #expect(Set(topology.paths.map { $0.id.stableKey }).count == connections.count)
    }

    @Test func columnsNodesAndEdgesFollowDeterministicFirstAppearanceOrder() throws {
        let connections = [
            connection(
                id: "1",
                sourceIP: "Source B",
                rule: "Rule B",
                chains: ["Final B", "Hop B2", "Hop Shared"]
            ),
            connection(
                id: "2",
                sourceIP: "Source A",
                rule: "Rule A",
                chains: ["Final A", "Hop A2", "Hop Shared"]
            ),
            connection(
                id: "3",
                sourceIP: "Source B",
                rule: "Rule B",
                chains: ["Final C", "Hop C2", "Hop Other"]
            ),
        ]
        let expected = ConnectionTopologyBuilder.build(from: connections)

        #expect(expected.columns.map(\.id) == [
            .source,
            .rule,
            .policyHop(0),
            .policyHop(1),
            .finalOutbound,
        ])
        #expect(expected.columns[0].nodes.map(\.name) == ["Source B", "Source A"])
        #expect(expected.columns[1].nodes.map(\.name) == ["Rule B", "Rule A"])
        #expect(expected.columns[2].nodes.map(\.name) == ["Hop Shared", "Hop Other"])
        #expect(expected.columns[3].nodes.map(\.name) == ["Hop B2", "Hop A2", "Hop C2"])
        #expect(expected.columns[4].nodes.map(\.name) == ["Final B", "Final A", "Final C"])
        #expect(expected.edges.map { "\($0.sourceName)->\($0.targetName)" } == [
            "Source B->Rule B",
            "Rule B->Hop Shared",
            "Hop Shared->Hop B2",
            "Hop B2->Final B",
            "Source A->Rule A",
            "Rule A->Hop Shared",
            "Hop Shared->Hop A2",
            "Hop A2->Final A",
            "Rule B->Hop Other",
            "Hop Other->Hop C2",
            "Hop C2->Final C",
        ])

        for _ in 0..<20 {
            #expect(ConnectionTopologyBuilder.build(from: connections) == expected)
        }
        requireSendable(expected)
        requireSendable(try #require(expected.paths.first).id)
    }

    @Test func synchronousAndCancellableBuildersRemainEquivalent() async throws {
        let connections = [
            connection(
                id: "duplicate",
                sourceIP: "Source",
                rule: "RuleSet",
                rulePayload: "Streaming",
                chains: ["Final", "Hop 2", "Hop 1"]
            ),
            connection(
                id: "duplicate",
                process: "curl",
                chains: ["DIRECT"]
            ),
            connection(id: " ", sourceIP: "Missing Chain", chains: []),
            connection(id: "", chains: ["Missing Source"]),
        ]

        let synchronous = ConnectionTopologyBuilder.build(from: connections)
        let cancellable = try await ConnectionTopologyBuilder.buildCancellable(from: connections)

        #expect(cancellable == synchronous)
    }

    @Test func sharedRouteMembershipOperationsScaleThroughTwoThousandConnections() {
        let smallCount = 500
        let largeCount = 2_000
        let scale = largeCount / smallCount
        let stagesPerPath = 6
        let edgesPerPath = stagesPerPath - 1

        let small = ConnectionTopologyBuilder.buildWithOperationCounts(
            from: sharedRouteConnections(count: smallCount)
        )
        let large = ConnectionTopologyBuilder.buildWithOperationCounts(
            from: sharedRouteConnections(count: largeCount)
        )

        #expect(small.topology.paths.count == smallCount)
        #expect(large.topology.paths.count == largeCount)
        #expect(small.topology.nodes.count == stagesPerPath)
        #expect(large.topology.nodes.count == stagesPerPath)
        #expect(small.topology.edges.count == edgesPerPath)
        #expect(large.topology.edges.count == edgesPerPath)

        let largePathIDs = large.topology.paths.map(\.id)
        #expect(large.topology.nodes.allSatisfy { $0.pathIDs == largePathIDs })
        #expect(large.topology.edges.allSatisfy { $0.pathIDs == largePathIDs })
        #expect(largePathIDs.first?.occurrence == 0)
        #expect(largePathIDs.last?.occurrence == largeCount - 1)

        #expect(small.operationCounts.inputConnectionCount == smallCount)
        #expect(large.operationCounts.inputConnectionCount == largeCount)
        #expect(small.operationCounts.normalizedStageCount == smallCount * stagesPerPath)
        #expect(large.operationCounts.normalizedStageCount == largeCount * stagesPerPath)
        #expect(small.operationCounts.nodeTableLookupCount == smallCount * stagesPerPath)
        #expect(large.operationCounts.nodeTableLookupCount == largeCount * stagesPerPath)
        #expect(small.operationCounts.nodeMembershipWriteCount == smallCount * stagesPerPath)
        #expect(large.operationCounts.nodeMembershipWriteCount == largeCount * stagesPerPath)
        #expect(small.operationCounts.edgeTableLookupCount == smallCount * edgesPerPath)
        #expect(large.operationCounts.edgeTableLookupCount == largeCount * edgesPerPath)
        #expect(small.operationCounts.edgeMembershipWriteCount == smallCount * edgesPerPath)
        #expect(large.operationCounts.edgeMembershipWriteCount == largeCount * edgesPerPath)
        #expect(small.operationCounts.uniqueNodeCount == stagesPerPath)
        #expect(large.operationCounts.uniqueNodeCount == stagesPerPath)
        #expect(small.operationCounts.uniqueEdgeCount == edgesPerPath)
        #expect(large.operationCounts.uniqueEdgeCount == edgesPerPath)

        #expect(
            large.operationCounts.nodeTableLookupCount
                == small.operationCounts.nodeTableLookupCount * scale
        )
        #expect(
            large.operationCounts.edgeTableLookupCount
                == small.operationCounts.edgeTableLookupCount * scale
        )
        #expect(
            large.operationCounts.nodeMembershipWriteCount
                == small.operationCounts.nodeMembershipWriteCount * scale
        )
        #expect(
            large.operationCounts.edgeMembershipWriteCount
                == small.operationCounts.edgeMembershipWriteCount * scale
        )
    }

    @Test func cancellableLargeProjectionThrowsWhenTaskIsCancelled() async {
        let connections = sharedRouteConnections(count: 2_000)
        let task = Task {
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                // Continue with the task's cancellation bit set.
            }
            return try await ConnectionTopologyBuilder.buildCancellable(
                from: connections
            )
        }
        task.cancel()

        var observedCancellation = false
        do {
            _ = try await task.value
        } catch is CancellationError {
            observedCancellation = true
        } catch {
            Issue.record("Unexpected topology cancellation error: \(error)")
        }
        #expect(observedCancellation)
    }

    private func sharedRouteConnections(count: Int) -> [ConnectionSnapshot] {
        (0..<count).map { _ in
            connection(
                id: "shared",
                sourceIP: "10.0.0.2",
                rule: "RuleSet",
                rulePayload: "Streaming",
                chains: ["Final", "Hop 3", "Hop 2", "Hop 1"]
            )
        }
    }

    // MARK: - Task 08-20: header clamp + status memo

    /// R4/AC2: a trailing column title ("代理链出口" / "Chain Exit") must stay
    /// fully inside the band at any panel width; leading columns clamp too.
    @Test func topologyHeaderGeometryClampsTitlesInsideBand() {
        let band = OverviewTopologyLayout.RenderBand(
            id: 0,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 400),
            columns: [
                OverviewTopologyLayout.ColumnGeometry(id: .source, centerX: 60),
                OverviewTopologyLayout.ColumnGeometry(id: .rule, centerX: 230),
                OverviewTopologyLayout.ColumnGeometry(id: .policyHop(0), centerX: 400),
                OverviewTopologyLayout.ColumnGeometry(id: .policyHop(1), centerX: 570),
                OverviewTopologyLayout.ColumnGeometry(id: .finalOutbound, centerX: 740),
            ],
            nodes: [],
            edges: []
        )

        // Middle column keeps its center; slice never overlaps a neighbor.
        let mid = band.columns[2]
        let midSlice = OverviewTopologyHeaderGeometry.sliceWidth(for: mid, in: band)
        #expect(midSlice == 340)
        #expect(
            OverviewTopologyHeaderGeometry.clampedCenter(
                sliceWidth: midSlice,
                columnCenterX: mid.centerX,
                bandWidth: 800
            ) == 400
        )

        // Trailing column: the whole slice stays inside the band.
        let last = band.columns[4]
        let lastSlice = OverviewTopologyHeaderGeometry.sliceWidth(for: last, in: band)
        let lastCenter = OverviewTopologyHeaderGeometry.clampedCenter(
            sliceWidth: lastSlice,
            columnCenterX: last.centerX,
            bandWidth: 800
        )
        #expect(lastCenter - lastSlice / 2 >= 0)
        #expect(lastCenter + lastSlice / 2 <= 800)
        #expect(lastCenter < last.centerX)

        // Leading column clamps symmetrically.
        let first = band.columns[0]
        let firstSlice = OverviewTopologyHeaderGeometry.sliceWidth(for: first, in: band)
        let firstCenter = OverviewTopologyHeaderGeometry.clampedCenter(
            sliceWidth: firstSlice,
            columnCenterX: first.centerX,
            bandWidth: 800
        )
        #expect(firstCenter - firstSlice / 2 >= 0)
        #expect(firstCenter > first.centerX)

        // Degenerate inputs: single column and an over-wide slice both resolve
        // to a centered, fully-visible title.
        let single = OverviewTopologyLayout.RenderBand(
            id: 1,
            bounds: CGRect(x: 0, y: 0, width: 320, height: 200),
            columns: [OverviewTopologyLayout.ColumnGeometry(id: .source, centerX: 40)],
            nodes: [],
            edges: []
        )
        let singleSlice = OverviewTopologyHeaderGeometry.sliceWidth(
            for: single.columns[0],
            in: single
        )
        #expect(singleSlice == 320)
        #expect(
            OverviewTopologyHeaderGeometry.clampedCenter(
                sliceWidth: 500,
                columnCenterX: 40,
                bandWidth: 320
            ) == 160
        )
    }

    /// R5/AC3: node statuses are memoized on (policy revision, topology
    /// revision); a repeat call with unchanged keys never re-resolves the
    /// policy catalog, and a topology-only flip reuses the catalog cache.
    @MainActor
    @Test func topologyNodeStatusesMemoizeOnRevisionKeys() {
        let runtime = OverviewTopologyRuntime()
        let catalog = PolicyGroupCatalogSnapshot(
            mode: "Rule",
            groups: [
                ProxyGroupViewState(
                    id: "Auto",
                    type: "URLTest",
                    selected: "Tokyo",
                    options: ["Tokyo"],
                    optionDetails: [:],
                    optionUsageRanks: [:],
                    delays: ["Tokyo": 64]
                ),
            ]
        )
        let topology = ConnectionTopologyBuilder.build(from: [
            connection(
                id: "memo",
                sourceIP: "10.0.0.2",
                rule: "RuleSet",
                rulePayload: "Streaming",
                chains: ["Final", "Auto"]
            ),
        ])

        let first = runtime.nodeStatuses(
            topology: topology,
            topologyRevision: 1,
            policyRevision: 7,
            catalog: catalog
        )
        #expect(first.values.contains(.ok))
        let statisticsAfterFirst = runtime.policyInspectionCache.statistics

        let second = runtime.nodeStatuses(
            topology: topology,
            topologyRevision: 1,
            policyRevision: 7,
            catalog: catalog
        )
        #expect(second == first)
        // Memo hit: the policy index was not re-resolved at all.
        #expect(runtime.policyInspectionCache.statistics == statisticsAfterFirst)

        // Topology-only revision flip: memo misses once, but the policy index
        // cache still hits (no catalog rebuild).
        let third = runtime.nodeStatuses(
            topology: topology,
            topologyRevision: 2,
            policyRevision: 7,
            catalog: catalog
        )
        #expect(third == first)
        #expect(
            runtime.policyInspectionCache.statistics.cacheHitCount
                == statisticsAfterFirst.cacheHitCount + 1
        )
        #expect(
            runtime.policyInspectionCache.statistics.buildCount
                == statisticsAfterFirst.buildCount
        )
    }
}
