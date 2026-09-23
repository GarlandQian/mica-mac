import Foundation
import MicaCore
import Testing
@testable import Mica

struct OverviewTopologyCardGeometryTests {
    @Test func branchingDensityReducesInkWithoutMakingRoutesInvisible() {
        let sparse = OverviewTopologyDensityStyle(edgeCount: 12, nodeCount: 16)
        let dense = OverviewTopologyDensityStyle(edgeCount: 600, nodeCount: 72)
        let extreme = OverviewTopologyDensityStyle(edgeCount: 100_000, nodeCount: 72)

        #expect(dense.edgeOpacity < sparse.edgeOpacity)
        #expect(dense.maximumLineWidth < sparse.maximumLineWidth)
        #expect(extreme.edgeOpacity <= dense.edgeOpacity)
        #expect(extreme.maximumLineWidth <= dense.maximumLineWidth)
        #expect(extreme.edgeOpacity > 0)
        #expect(extreme.maximumLineWidth >= 1)
        #expect(OverviewTopologyDensityStyle(edgeCount: 0, nodeCount: 0).edgeOpacity.isFinite)
    }

    @Test(arguments: [CGFloat(520), 1_024, 2_400])
    func longNamesStayInsideTheirCardsAndLeaveRoutingSpace(availableWidth: CGFloat) async throws {
        let topology = ConnectionTopologyBuilder.build(from: [
            ConnectionSnapshot(
                id: "long-route",
                chains: [
                    "美国 · 家庭宽带 · Very Long Final Outbound Name",
                    "自动选择 · Very Long Policy Group Name",
                    "流媒体和国际服务 · Very Long First Policy Name",
                ],
                metadata: ConnectionMetadataSnapshot(sourceIP: "2001:db8:1234:5678:abcd:ef01:2345:6789")
            ),
        ])
        let layout = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: topology,
            availableWidth: availableWidth
        )

        #expect(layout.nodes.count == topology.nodes.count)
        for node in layout.nodes {
            #expect(node.rect.contains(node.labelRect))
            #expect(node.labelRect.width >= 96)
            #expect(node.labelRect.minX > node.rect.minX)
            #expect(node.labelRect.maxX < node.rect.maxX)
            #expect(node.rect.minX >= 0)
            #expect(node.rect.maxX <= layout.size.width)
            #expect(node.rect.minY >= OverviewTopologyLayout.columnHeaderHeight)
            #expect(node.rect.maxY <= layout.size.height)
        }

        let policy = try #require(layout.nodes.first { $0.node.columnID == .policyHop(1) })
        let outbound = try #require(layout.nodes.first { $0.node.columnID == .finalOutbound })
        #expect(policy.rect.midY == outbound.rect.midY)
        #expect(!policy.rect.intersects(outbound.rect))
        #expect(!policy.labelRect.intersects(outbound.labelRect))
        #expect(outbound.rect.minX - policy.rect.maxX >= 48 - 0.000_001)
    }

    @Test func entireCardsAreSelectableWhileTheRouteGapRemainsAnEdgeTarget() async throws {
        let topology = ConnectionTopologyBuilder.build(from: [
            ConnectionSnapshot(
                id: "single-route",
                chains: ["Final Outbound", "Policy Group"],
                metadata: ConnectionMetadataSnapshot(sourceIP: "10.0.0.1")
            ),
        ])
        let layout = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: topology,
            availableWidth: 800
        )

        for node in layout.nodes {
            // Cover both icon/label sides and every corner of the interaction
            // rectangle, rather than only the old narrow rail at its center.
            for x in [node.rect.minX + 1, node.rect.midX, node.rect.maxX - 1] {
                for y in [node.rect.minY + 1, node.rect.midY, node.rect.maxY - 1] {
                    #expect(layout.hitTest(at: CGPoint(x: x, y: y)) == .node(node.node.id))
                }
            }
        }
        for edge in layout.edges {
            let source = try #require(layout.nodeGeometry(id: edge.edge.sourceID))
            let target = try #require(layout.nodeGeometry(id: edge.edge.targetID))
            let routePoint = edge.point(at: 0.5)
            #expect(routePoint.x > source.hitRect.maxX)
            #expect(routePoint.x < target.hitRect.minX)
            #expect(layout.hitTest(at: routePoint) == .edge(edge.edge.id))
        }
    }

    @Test(arguments: [1, 3, 12])
    func sparseGraphsDoNotExpandToAnOversizedRequestedHeight(sourceCount: Int) async throws {
        let topology = ConnectionTopologyBuilder.build(from: (0..<sourceCount).map { index in
            ConnectionSnapshot(
                id: "sparse-\(index)",
                chains: ["DIRECT"],
                metadata: ConnectionMetadataSnapshot(sourceIP: "source-\(index)")
            )
        })
        let natural = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: topology,
            availableWidth: 800,
            minimumFlowHeight: 0
        )
        let oversized = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: topology,
            availableWidth: 800,
            minimumFlowHeight: 10_000
        )
        let sourceCards = oversized.nodes.filter { $0.node.columnID == .source }
        let occupiedHeight = try #require(sourceCards.last).rect.maxY
            - #require(sourceCards.first).rect.minY
        let naturalSourceCards = natural.nodes.filter { $0.node.columnID == .source }
        let naturalOccupiedHeight = try #require(naturalSourceCards.last).rect.maxY
            - #require(naturalSourceCards.first).rect.minY
        let chromeHeight = natural.size.height - naturalOccupiedHeight

        #expect(occupiedHeight == naturalOccupiedHeight)
        #expect(oversized.size.height >= natural.size.height)
        #expect(oversized.size.height <= chromeHeight + max(occupiedHeight * 1.25, 160) + 0.000_001)
        #expect(oversized.nodes.map(\.rect.size) == natural.nodes.map(\.rect.size))
        #expect(oversized.edges.count == topology.edges.count)
    }

    @Test func denseCardGraphKeepsEveryNodeEdgeAndPathAndRespectsAttachmentBounds() async throws {
        // A complete source-to-policy fan-out creates hundreds of distinct
        // edges, including many ports sharing the same compact card.
        let sideCount = 24
        let connections = (0..<sideCount).flatMap { source in
            (0..<sideCount).map { destination in
                ConnectionSnapshot(
                    id: "dense-\(source)-\(destination)",
                    chains: ["outbound-\(destination)", "policy-\(destination)"],
                    metadata: ConnectionMetadataSnapshot(sourceIP: "source-\(source)")
                )
            }
        }
        let topology = ConnectionTopologyBuilder.build(from: connections)
        let layout = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: topology,
            availableWidth: 720
        )

        #expect(topology.paths.count == sideCount * sideCount)
        #expect(topology.edges.count == sideCount * sideCount + sideCount)
        #expect(layout.nodes.count == sideCount * 3)
        #expect(Set(layout.nodes.map(\.node.id)) == Set(topology.nodes.map(\.id)))
        #expect(Set(layout.edges.map(\.edge.id)) == Set(topology.edges.map(\.id)))
        #expect(Set(layout.renderBands.flatMap { $0.nodes.map(\.node.id) }) == Set(topology.nodes.map(\.id)))
        #expect(Set(layout.renderBands.flatMap { $0.edges.map(\.edge.id) }) == Set(topology.edges.map(\.id)))
        #expect(layout.operationCounts.edgeHitSegmentCount <= layout.edges.count * 8)

        for node in layout.nodes {
            #expect(node.rect.contains(node.labelRect))
            #expect(node.rect.contains(node.attachmentRect))
            #expect(layout.hitTest(at: CGPoint(x: node.rect.midX, y: node.rect.midY)) == .node(node.node.id))
        }
        for edge in layout.edges {
            let source = try #require(layout.nodeGeometry(id: edge.edge.sourceID))
            let target = try #require(layout.nodeGeometry(id: edge.edge.targetID))
            #expect(edge.source.x == source.attachmentRect.maxX)
            #expect(edge.target.x == target.attachmentRect.minX)
            #expect(edge.source.y - edge.width / 2 >= source.attachmentRect.minY - 0.000_001)
            #expect(edge.source.y + edge.width / 2 <= source.attachmentRect.maxY + 0.000_001)
            #expect(edge.target.y - edge.width / 2 >= target.attachmentRect.minY - 0.000_001)
            #expect(edge.target.y + edge.width / 2 <= target.attachmentRect.maxY + 0.000_001)
        }
    }
}
