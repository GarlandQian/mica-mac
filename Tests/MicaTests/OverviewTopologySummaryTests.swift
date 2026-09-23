import Foundation
import MicaCore
import Testing
@testable import Mica

struct OverviewTopologySummaryTests {
    private let labels = OverviewTopologySummary.Labels(
        unknownSource: "Source not reported",
        unknownEntry: "Policy not reported",
        unknownOutbound: "Outbound not reported",
        other: "Other"
    )

    @Test func thousandConnectionsHaveBoundedDiagramAndExactMembership() async throws {
        let connections = (0..<1_000).map { index in
            ConnectionSnapshot(
                id: "connection-\(index)",
                chains: ["outbound-\(index % 61)", "middle-\(index % 31)", "entry-\(index % 53)"],
                rule: "RuleSet", rulePayload: "rule-\(index % 47)",
                metadata: ConnectionMetadataSnapshot(sourceIP: "source-\(index % 89)")
            )
        }
        let original = ConnectionTopologyBuilder.build(from: connections)
        let summary = try await OverviewTopologySummary.build(topology: original, labels: labels)
        let index = OverviewTopologyIndex(topology: summary.diagram)
        let originalIndex = OverviewTopologyIndex(topology: original)
        let allPathIDs = Set(original.paths.map(\.id))

        #expect(summary.diagram.paths.count == connections.count)
        #expect(summary.diagram.columns.map(\.id) == [.source, .policyHop(0), .finalOutbound])
        #expect(summary.diagram.nodes.count <= 18)
        #expect(summary.diagram.edges.count <= 72)
        #expect(Set(summary.diagram.paths.map(\.id)) == allPathIDs)
        #expect(summary.mergedNameCount == (89 - 5) + (53 - 5) + (61 - 5))

        var mergedMembership = Set<ConnectionTopology.ConnectionOccurrenceID>()
        for column in summary.diagram.columns {
            #expect(column.nodes.count <= OverviewTopologySummary.maximumItemsPerColumn)
            #expect(column.nodes.reduce(0) { $0 + $1.connectionCount } == connections.count)
            #expect(Set(column.nodes.flatMap(\.pathIDs)) == allPathIDs)
            for node in column.nodes {
                #expect(node.pathIDs.count == Set(node.pathIDs).count)
                let related = index.highlight(for: .node(node.id))
                #expect(related.pathIDs == Set(node.pathIDs))
                let fullPaths = related.paths.compactMap { originalIndex.path(id: $0.id) }
                #expect(fullPaths.count == related.paths.count)
                #expect(fullPaths.allSatisfy { $0.stages.count == 5 && $0.rule != nil && $0.policyHops.count == 2 })
                if summary.itemsByID[node.id]?.isAggregate == true {
                    mergedMembership.formUnion(node.pathIDs)
                }
            }
        }
        #expect(summary.mergedConnectionCount == mergedMembership.count)
        #expect(summary.mergedConnectionCount <= connections.count)
        for edge in summary.diagram.edges {
            #expect(edge.pathIDs.count == Set(edge.pathIDs).count)
            #expect(index.highlight(for: .edge(edge.id)).pathIDs == Set(edge.pathIDs))
        }
    }

    @Test(arguments: [CGFloat(280), 400, 560, 960, 1_440])
    func overviewFitsWidthAndKeepsHeightBounded(width: CGFloat) async throws {
        let original = ConnectionTopologyBuilder.build(from: (0..<1_000).map { index in
            ConnectionSnapshot(
                id: String(index), chains: ["outbound-\(index)", "policy-\(index)"],
                metadata: ConnectionMetadataSnapshot(sourceIP: "source-\(index)")
            )
        })
        let summary = try await OverviewTopologySummary.build(topology: original, labels: labels)
        let layout = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: summary.diagram, availableWidth: width,
            minimumFlowHeight: 360, fitsOverviewWidth: true
        )
        #expect(layout.size.width <= width)
        #expect(layout.size.height <= 480)
        #expect(layout.nodes.count <= 18)
        for node in layout.nodes {
            #expect(node.rect.minX >= 0)
            #expect(node.rect.maxX <= width + 0.000_001)
            #expect(node.labelRect.width > 0)
            #expect(node.rect.contains(node.labelRect))
        }
    }

    @Test(arguments: [1, 3])
    func sparseOverviewUsesItsRowsInsteadOfReservingATallWindow(sourceCount: Int) async throws {
        let original = ConnectionTopologyBuilder.build(from: (0..<sourceCount).map { index in
            ConnectionSnapshot(
                id: "sparse-\(index)", chains: ["Exit", "Entry"],
                metadata: ConnectionMetadataSnapshot(sourceIP: "Source \(index)")
            )
        })
        let summary = try await OverviewTopologySummary.build(topology: original, labels: labels)
        let short = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: summary.diagram, availableWidth: 560,
            minimumFlowHeight: 208, fitsOverviewWidth: true
        )
        let tall = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: summary.diagram, availableWidth: 560,
            minimumFlowHeight: 10_000, fitsOverviewWidth: true
        )
        let firstSource = try #require(tall.nodes.first { $0.node.columnID == .source })
        let viewportHeight = OverviewTopologyViewportSizing.height(
            displayMode: .overview, requestedHeight: 440, contentHeight: tall.size.height
        )

        #expect(tall.size == short.size)
        #expect(tall.nodes.map(\.rect) == short.nodes.map(\.rect))
        #expect(tall.size.height <= 240)
        #expect(viewportHeight == tall.size.height)
        // The first row stays near the column heading as the window grows.
        #expect(firstSource.rect.minY - OverviewTopologyLayout.columnHeaderHeight <= 56)
        #expect(summary.diagram.paths.map(\.id) == original.paths.map(\.id))
    }

    @Test func denseOverviewKeepsAllRowsReachableInsideAShortViewport() async throws {
        let original = ConnectionTopologyBuilder.build(from: (0..<1_000).map { index in
            ConnectionSnapshot(
                id: "dense-\(index)", chains: ["Exit \(index)", "Entry \(index)"],
                metadata: ConnectionMetadataSnapshot(sourceIP: "Source \(index)")
            )
        })
        let summary = try await OverviewTopologySummary.build(topology: original, labels: labels)
        let page = OverviewViewportLayout(width: 560, height: 460, metricCount: 3)
        let layout = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: summary.diagram, availableWidth: 560,
            minimumFlowHeight: page.topologyMinimumHeight, fitsOverviewWidth: true
        )
        let viewportHeight = OverviewTopologyViewportSizing.height(
            displayMode: .overview, requestedHeight: page.topologyMinimumHeight,
            contentHeight: layout.size.height
        )
        let finalCard = try #require(layout.nodes.max { $0.rect.maxY < $1.rect.maxY })
        let offset = try #require(OverviewTopologyViewportTargetResolver.contentOffsetY(
            for: .init(id: .node(finalCard.node.id), centerX: finalCard.rect.midX, centerY: finalCard.rect.midY),
            visibleRect: CGRect(x: 0, y: 0, width: 560, height: viewportHeight),
            contentHeight: layout.size.height
        ))

        #expect(summary.diagram.columns.allSatisfy { $0.nodes.count == 6 })
        #expect(viewportHeight <= 240)
        #expect(viewportHeight < layout.size.height)
        #expect(layout.nodes.allSatisfy { $0.rect.height >= 36 })
        #expect(offset > 0)
        #expect(finalCard.rect.maxY <= offset + viewportHeight)
        #expect(Set(summary.diagram.paths.map(\.id)) == Set(original.paths.map(\.id)))
        #expect(Set(layout.renderBands.flatMap { $0.nodes.map(\.node.id) }) == Set(summary.diagram.nodes.map(\.id)))
    }

    @Test func unknownRoutesRemainVisibleWithoutInventedFactsOrDirectFallback() async throws {
        let original = ConnectionTopologyBuilder.build(from: [
            ConnectionSnapshot(id: "no-source", chains: ["Reported outbound", "Entry"]),
            ConnectionSnapshot(id: "no-chain", metadata: ConnectionMetadataSnapshot(sourceIP: "Known source")),
            ConnectionSnapshot(id: "nothing"),
            ConnectionSnapshot(id: "blank-final", chains: [" ", "Known hop"], metadata: ConnectionMetadataSnapshot(sourceIP: "Source")),
            ConnectionSnapshot(id: "direct", chains: ["DIRECT"], metadata: ConnectionMetadataSnapshot(sourceIP: "Source")),
        ])
        let summary = try await OverviewTopologySummary.build(topology: original, labels: labels)
        #expect(!summary.diagram.isEmpty)
        #expect(summary.diagram.connectionCount == 5)
        #expect(summary.diagram.routeUnavailableCount == 4)
        #expect(summary.diagram.paths.map(\.routeState) == original.paths.map(\.routeState))
        let direct = try #require(summary.diagram.paths.last)
        let entry = try #require(direct.stages.first { $0.columnID == .policyHop(0) })
        #expect(summary.itemsByID[entry.nodeID]?.value == .unreported)
        #expect(original.paths.last?.policyHops.isEmpty == true)
        #expect(original.paths[3].finalOutbound == nil)
        #expect(original.paths[3].policyHops == ["Known hop"])
        #expect(summary.diagram.paths[3].finalOutbound == labels.unknownOutbound)
        #expect(summary.diagram.nodes.contains { $0.name == labels.unknownSource })
        #expect(summary.diagram.nodes.contains { $0.name == labels.unknownOutbound })
        #expect(summary.diagram.nodes.contains { $0.name == "DIRECT" })
    }

    @Test func missingOnlyRoutesDoNotLookLikeAnEmptyConnectionSet() async throws {
        let original = ConnectionTopologyBuilder.build(from: [ConnectionSnapshot(id: "missing")])
        #expect(original.isEmpty)
        let summary = try await OverviewTopologySummary.build(topology: original, labels: labels)
        #expect(!summary.diagram.isEmpty)
        #expect(summary.diagram.nodes.count == 3)
        #expect(summary.diagram.paths.count == 1)
        #expect(summary.diagram.paths[0].routeState == .routeUnavailable(.missingSourceAndChain))
    }

    @Test func duplicateIDsAndBucketLikeNamesCannotAliasSyntheticItems() async throws {
        var connections = (0..<20).map { index in
            ConnectionSnapshot(id: "duplicate", chains: ["Final-\(index)", "Entry-\(index)"], metadata: ConnectionMetadataSnapshot(sourceIP: "Source-\(index)"))
        }
        connections += (0..<5).map { _ in
            ConnectionSnapshot(id: "", chains: [labels.unknownOutbound, "Other"], metadata: ConnectionMetadataSnapshot(sourceIP: labels.unknownSource))
        }
        connections.append(ConnectionSnapshot(id: ""))
        let original = ConnectionTopologyBuilder.build(from: connections)
        let first = try await OverviewTopologySummary.build(topology: original, labels: labels)
        let rebuilt = try await OverviewTopologySummary.build(topology: original, labels: labels)
        #expect(first.diagram == rebuilt.diagram)
        #expect(first.diagram.paths.count == Set(first.diagram.paths.map(\.id)).count)
        let reportedUnknown = first.itemsByID.filter { $0.value.value == .reported(labels.unknownSource) }
        let actualUnknown = first.itemsByID.filter { $0.value.value == .unreported }
        #expect(reportedUnknown.count == 1)
        #expect(actualUnknown.count == 3)
        #expect(Set(reportedUnknown.keys).isDisjoint(with: Set(actualUnknown.keys)))
        #expect(first.itemsByID.values.contains { $0.value == .reported("Other") })
        #expect(first.itemsByID.values.contains { $0.value == .other })
    }

    @MainActor
    @Test func presentationRetainsCompletePathsAndModeChangesReconfigureInteraction() async throws {
        let generation = UUID()
        let connection = ConnectionSnapshot(id: "connection", chains: ["Exit", "Inner", "Outer"], rule: "RuleSet", rulePayload: "Service", metadata: ConnectionMetadataSnapshot(sourceIP: "Source"))
        let cache = OverviewTopologyPresentationCache()
        let overview = try await cache.resolve(
            request: .init(generation: generation, revision: 3, availableWidth: 560, displayMode: .overview),
            connections: [connection]
        )
        #expect(overview.topology.paths[0].policyHops == ["Outer", "Inner"])
        #expect(overview.diagram.paths[0].policyHops == ["Outer"])
        let completeRequest = OverviewTopologyRequest(generation: generation, revision: 3, availableWidth: 560, displayMode: .complete)
        #expect(!overview.canRemainVisible(whileResolving: completeRequest))
        let complete = try await cache.resolve(request: completeRequest, connections: [connection])
        #expect(complete.diagram == overview.topology)
        #expect(complete.layout.nodes.count == overview.topology.nodes.count)
        #expect(cache.statistics.topologyBuildCount == 1)

        let runtime = OverviewTopologyRuntime()
        let group = try #require(overview.diagram.nodes.first { $0.columnID == .policyHop(0) })
        runtime.focusPaths(for: .node(group.id), presentation: overview, language: .english)
        let focus = try #require(runtime.focusedPaths)
        #expect(focus.paths == overview.topology.paths)
        #expect(focus.canNavigate(generation: generation, revision: 3))
        #expect(!focus.canNavigate(generation: generation, revision: 4))
        #expect(!focus.canNavigate(generation: UUID(), revision: 3))
        runtime.returnToOverview()
        #expect(runtime.focusedPaths == nil)
        #expect(runtime.displayMode == .overview)

        runtime.interaction.configure(structure: overview.request.diagramStructure, index: overview.diagramIndex)
        runtime.interaction.togglePinnedSelection(.node(group.id))
        runtime.interaction.configure(structure: complete.request.diagramStructure, index: complete.diagramIndex)
        #expect(runtime.interaction.snapshot.activeSelection == nil)
    }

    @Test func fullGraphKeyboardTargetCanBeRevealedVerticallyWithoutMovingVisibleItems() {
        let target = OverviewTopologyViewportTarget(id: .node("last"), centerX: 200, centerY: 1_800)
        #expect(OverviewTopologyViewportTargetResolver.contentOffsetY(
            for: target, visibleRect: CGRect(x: 0, y: 0, width: 600, height: 400), contentHeight: 2_000
        ) == 1_600)
        #expect(OverviewTopologyViewportTargetResolver.contentOffsetY(
            for: target, visibleRect: CGRect(x: 0, y: 1_600, width: 600, height: 400), contentHeight: 2_000
        ) == nil)
        #expect(OverviewTopologyViewportTargetResolver.contentOffsetY(
            for: target, visibleRect: .zero, contentHeight: 2_000
        ) == nil)
    }

    @MainActor
    @Test func relabelingACapturedRevisionCannotAdmitNewerConnectionsUnderTheOldIdentity() async throws {
        let generation = UUID()
        let cache = OverviewTopologyPresentationCache()
        let captured = try await cache.resolve(
            request: .init(generation: generation, revision: 8, availableWidth: 560, displayMode: .overview, languageID: "en"),
            connections: [ConnectionSnapshot(id: "captured")]
        )
        let relabeled = try await cache.resolve(
            request: .init(generation: generation, revision: 8, availableWidth: 560, displayMode: .overview, languageID: "zh-Hans"),
            connections: [ConnectionSnapshot(id: "newer"), ConnectionSnapshot(id: "another")]
        )
        #expect(relabeled.topology == captured.topology)
        #expect(relabeled.topology.paths.map(\.reportedConnectionID) == ["captured"])
        #expect(relabeled.diagram.paths.count == 1)
        #expect(cache.statistics.topologyBuildCount == 1)
        let current = try await cache.resolve(
            request: .init(generation: generation, revision: 9, availableWidth: 560, displayMode: .overview, languageID: "zh-Hans"),
            connections: [ConnectionSnapshot(id: "newer"), ConnectionSnapshot(id: "another")]
        )
        #expect(current.topology.paths.map(\.reportedConnectionID) == ["newer", "another"])
        #expect(cache.statistics.topologyBuildCount == 2)
    }
}
