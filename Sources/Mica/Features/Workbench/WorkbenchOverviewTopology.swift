import Foundation
import MicaCore
import Observation
import SwiftUI

struct OverviewTopologyStructureRequest: Hashable, Sendable {
    let generation: UUID
    let revision: UInt64
}

struct OverviewTopologyRequest: Hashable, Sendable {
    let structure: OverviewTopologyStructureRequest
    let availableWidth: Int
    let minimumFlowHeight: Int

    init(
        generation: UUID,
        revision: UInt64,
        availableWidth: Int,
        minimumFlowHeight: Int = 352
    ) {
        structure = OverviewTopologyStructureRequest(
            generation: generation,
            revision: revision
        )
        self.availableWidth = availableWidth
        self.minimumFlowHeight = minimumFlowHeight
    }

    var generation: UUID { structure.generation }
    var revision: UInt64 { structure.revision }
}

struct OverviewTopologyPresentation {
    let request: OverviewTopologyRequest
    let topology: ConnectionTopology
    let index: OverviewTopologyIndex
    let layout: OverviewTopologyLayout

    func canRemainVisible(whileResolving request: OverviewTopologyRequest) -> Bool {
        self.request.generation == request.generation
            && self.request.availableWidth <= request.availableWidth
            && self.request.minimumFlowHeight <= request.minimumFlowHeight
    }
}

@MainActor
final class OverviewTopologyPresentationCache {
    struct Statistics: Equatable {
        var topologyBuildCount = 0
        var topologyIndexBuildCount = 0
        var layoutBuildCount = 0
        var exactRequestHitCount = 0
        var structureReuseCount = 0
    }

    private struct GraphPresentation {
        let request: OverviewTopologyStructureRequest
        let topology: ConnectionTopology
        let index: OverviewTopologyIndex
    }

    private var graph: GraphPresentation?
    private var cachedPresentation: OverviewTopologyPresentation?
    private(set) var statistics = Statistics()

    func resolve(
        request: OverviewTopologyRequest,
        connections: [ConnectionSnapshot]
    ) async throws -> OverviewTopologyPresentation {
        if let cachedPresentation, cachedPresentation.request == request {
            statistics.exactRequestHitCount += 1
            return cachedPresentation
        }

        let graphPresentation: GraphPresentation
        if let graph, graph.request == request.structure {
            graphPresentation = graph
            statistics.structureReuseCount += 1
        } else {
            statistics.topologyBuildCount += 1
            let interval = MicaPerformanceObservation.beginInterval(
                .topologyNormalization,
                metadata: MicaPerformanceMetadata(
                    count: UInt64(connections.count),
                    revision: request.revision
                )
            )
            let clock = ContinuousClock()
            let start = clock.now
            do {
                let topology = try await ConnectionTopologyBuilder.buildCancellable(
                    from: connections
                )
                try Task.checkCancellation()
                let index = OverviewTopologyIndex(topology: topology)
                try Task.checkCancellation()
                MicaPerformanceObservation.endInterval(
                    interval,
                    metadata: MicaPerformanceMetadata(
                        count: UInt64(topology.paths.count),
                        revision: request.revision,
                        duration: start.duration(to: clock.now)
                    )
                )
                statistics.topologyIndexBuildCount += 1
                let nextGraph = GraphPresentation(
                    request: request.structure,
                    topology: topology,
                    index: index
                )
                graph = nextGraph
                cachedPresentation = nil
                graphPresentation = nextGraph
            } catch {
                MicaPerformanceObservation.endInterval(
                    interval,
                    metadata: MicaPerformanceMetadata(
                        count: UInt64(connections.count),
                        revision: request.revision,
                        duration: start.duration(to: clock.now)
                    )
                )
                throw error
            }
        }

        statistics.layoutBuildCount += 1
        let layout = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: graphPresentation.topology,
            availableWidth: CGFloat(request.availableWidth),
            minimumFlowHeight: CGFloat(request.minimumFlowHeight),
            revision: request.revision
        )
        try Task.checkCancellation()
        let presentation = OverviewTopologyPresentation(
            request: request,
            topology: graphPresentation.topology,
            index: graphPresentation.index,
            layout: layout
        )
        cachedPresentation = presentation
        return presentation
    }
}

enum OverviewTopologySelection: Hashable, Sendable {
    case node(String)
    case edge(String)
    case path(ConnectionTopology.ConnectionOccurrenceID)
}

struct OverviewTopologyHighlightOperationCounts: Equatable, Sendable {
    fileprivate(set) var selectedPathIDCount = 0
    fileprivate(set) var pathRecordLookupCount = 0
    fileprivate(set) var stageVisitCount = 0
    fileprivate(set) var edgeVisitCount = 0
}

struct OverviewTopologyHighlight: Equatable, Sendable {
    let pathIDs: Set<ConnectionTopology.ConnectionOccurrenceID>
    let nodeIDs: Set<String>
    let edgeIDs: Set<String>
    let paths: [ConnectionTopology.PathRecord]

    static let empty = OverviewTopologyHighlight(
        pathIDs: [],
        nodeIDs: [],
        edgeIDs: [],
        paths: []
    )
}

struct OverviewTopologyHighlightCacheStatistics: Equatable {
    var projectionCount = 0
    var cacheHitCount = 0
}

/// Keeps a pinned or unchanged hover selection from being reprojected when an
/// unrelated metrics frame reevaluates the Overview hierarchy.
final class OverviewTopologyHighlightCache {
    private struct Key: Equatable {
        let structure: OverviewTopologyStructureRequest
        let selection: OverviewTopologySelection?
    }

    private var key: Key?
    private var highlight = OverviewTopologyHighlight.empty
    private(set) var statistics = OverviewTopologyHighlightCacheStatistics()

    func resolve(
        structure: OverviewTopologyStructureRequest,
        selection: OverviewTopologySelection?,
        index: OverviewTopologyIndex
    ) -> OverviewTopologyHighlight {
        let nextKey = Key(structure: structure, selection: selection)
        if key == nextKey {
            statistics.cacheHitCount += 1
            return highlight
        }

        highlight = index.highlight(for: selection)
        key = nextKey
        statistics.projectionCount += 1
        return highlight
    }
}

struct OverviewTopologyInteractionSnapshot: Equatable, Sendable {
    let activeSelection: OverviewTopologySelection?
    let isHovering: Bool
    let isPinned: Bool
    let highlight: OverviewTopologyHighlight

    static let empty = OverviewTopologyInteractionSnapshot(
        activeSelection: nil,
        isHovering: false,
        isPinned: false,
        highlight: .empty
    )
}

@MainActor
@Observable
final class OverviewTopologyInteractionState {
    private(set) var snapshot = OverviewTopologyInteractionSnapshot.empty

    @ObservationIgnored private var hoveredSelection: OverviewTopologySelection?
    @ObservationIgnored private var pinnedSelection: OverviewTopologySelection?
    @ObservationIgnored private var structure: OverviewTopologyStructureRequest?
    @ObservationIgnored private var index: OverviewTopologyIndex?
    @ObservationIgnored private let highlightCache = OverviewTopologyHighlightCache()

    var statistics: OverviewTopologyHighlightCacheStatistics {
        highlightCache.statistics
    }

    func configure(
        structure: OverviewTopologyStructureRequest,
        index: OverviewTopologyIndex
    ) {
        guard self.structure != structure else { return }
        self.structure = structure
        self.index = index
        hoveredSelection = hoveredSelection.flatMap { selection in
            index.contains(selection) ? selection : nil
        }
        pinnedSelection = pinnedSelection.flatMap { selection in
            index.contains(selection) ? selection : nil
        }
        publishSnapshot()
    }

    func reset() {
        hoveredSelection = nil
        pinnedSelection = nil
        structure = nil
        index = nil
        guard snapshot != .empty else { return }
        snapshot = .empty
    }

    func setHoveredSelection(_ selection: OverviewTopologySelection?) {
        guard hoveredSelection != selection else { return }
        hoveredSelection = selection
        publishSnapshot()
    }

    func togglePinnedSelection(_ selection: OverviewTopologySelection?) {
        hoveredSelection = nil
        pinnedSelection = pinnedSelection == selection ? nil : selection
        publishSnapshot()
    }

    func togglePinnedPath(_ pathID: ConnectionTopology.ConnectionOccurrenceID) {
        togglePinnedSelection(.path(pathID))
    }

    func clearSelection() {
        guard hoveredSelection != nil || pinnedSelection != nil else { return }
        hoveredSelection = nil
        pinnedSelection = nil
        publishSnapshot()
    }

    func canMovePath(by offset: Int) -> Bool {
        guard offset != 0, let index, index.pathCount > 0 else { return false }
        guard case .path(let pathID) = snapshot.activeSelection,
              let currentIndex = index.pathIndex(id: pathID) else {
            return true
        }
        return (0..<index.pathCount).contains(currentIndex + offset)
    }

    func movePathSelection(by offset: Int) {
        guard canMovePath(by: offset), let index else { return }

        let nextIndex: Int
        if case .path(let pathID) = snapshot.activeSelection,
           let currentIndex = index.pathIndex(id: pathID) {
            nextIndex = min(
                max(currentIndex + offset, 0),
                index.pathCount - 1
            )
        } else if let relatedPathID = offset < 0
            ? snapshot.highlight.paths.last?.id
            : snapshot.highlight.paths.first?.id,
            let relatedIndex = index.pathIndex(id: relatedPathID) {
            nextIndex = relatedIndex
        } else {
            nextIndex = offset < 0 ? index.pathCount - 1 : 0
        }

        guard let pathID = index.pathID(at: nextIndex) else { return }
        hoveredSelection = nil
        pinnedSelection = .path(pathID)
        publishSnapshot()
    }

    private func publishSnapshot() {
        let activeSelection = hoveredSelection ?? pinnedSelection
        let highlight: OverviewTopologyHighlight
        if let structure, let index {
            highlight = highlightCache.resolve(
                structure: structure,
                selection: activeSelection,
                index: index
            )
        } else {
            highlight = .empty
        }
        let next = OverviewTopologyInteractionSnapshot(
            activeSelection: activeSelection,
            isHovering: hoveredSelection != nil,
            isPinned: activeSelection != nil && pinnedSelection == activeSelection,
            highlight: highlight
        )
        guard snapshot != next else { return }
        snapshot = next
    }
}

struct OverviewTopologyIndex: Sendable {
    struct OperationCounts: Equatable, Sendable {
        let nodeWriteCount: Int
        let edgeWriteCount: Int
        let pathWriteCount: Int
    }

    struct AccessibilityGroup: Identifiable, Equatable, Sendable {
        let id: Int
        let pathRange: Range<Int>
    }

    static let accessibilityGroupCapacity = 32

    private let nodeByID: [String: ConnectionTopology.Node]
    private let edgeByID: [String: ConnectionTopology.Edge]
    private let pathByID: [
        ConnectionTopology.ConnectionOccurrenceID: ConnectionTopology.PathRecord
    ]
    private let pathIndexByID: [ConnectionTopology.ConnectionOccurrenceID: Int]
    private let orderedPathIDs: [ConnectionTopology.ConnectionOccurrenceID]
    let accessibilityGroups: [AccessibilityGroup]
    let operationCounts: OperationCounts

    init(topology: ConnectionTopology) {
        var nodeByID: [String: ConnectionTopology.Node] = [:]
        let nodes = topology.nodes
        nodeByID.reserveCapacity(nodes.count)
        for node in nodes {
            nodeByID[node.id] = node
        }

        var edgeByID: [String: ConnectionTopology.Edge] = [:]
        edgeByID.reserveCapacity(topology.edges.count)
        for edge in topology.edges {
            edgeByID[edge.id] = edge
        }

        var pathByID: [
            ConnectionTopology.ConnectionOccurrenceID: ConnectionTopology.PathRecord
        ] = [:]
        pathByID.reserveCapacity(topology.paths.count)
        var pathIndexByID: [ConnectionTopology.ConnectionOccurrenceID: Int] = [:]
        pathIndexByID.reserveCapacity(topology.paths.count)
        var orderedPathIDs: [ConnectionTopology.ConnectionOccurrenceID] = []
        orderedPathIDs.reserveCapacity(topology.paths.count)
        for (pathIndex, path) in topology.paths.enumerated() {
            pathByID[path.id] = path
            pathIndexByID[path.id] = pathIndex
            orderedPathIDs.append(path.id)
        }

        self.nodeByID = nodeByID
        self.edgeByID = edgeByID
        self.pathByID = pathByID
        self.pathIndexByID = pathIndexByID
        self.orderedPathIDs = orderedPathIDs
        accessibilityGroups = stride(
            from: topology.paths.startIndex,
            to: topology.paths.endIndex,
            by: Self.accessibilityGroupCapacity
        ).enumerated().map { groupIndex, lowerBound in
            AccessibilityGroup(
                id: groupIndex,
                pathRange: lowerBound..<min(
                    lowerBound + Self.accessibilityGroupCapacity,
                    topology.paths.endIndex
                )
            )
        }
        operationCounts = OperationCounts(
            nodeWriteCount: nodes.count,
            edgeWriteCount: topology.edges.count,
            pathWriteCount: topology.paths.count
        )
    }

    func node(id: String) -> ConnectionTopology.Node? {
        nodeByID[id]
    }

    func edge(id: String) -> ConnectionTopology.Edge? {
        edgeByID[id]
    }

    func path(id: ConnectionTopology.ConnectionOccurrenceID) -> ConnectionTopology.PathRecord? {
        pathByID[id]
    }

    var pathCount: Int {
        orderedPathIDs.count
    }

    func pathIndex(id: ConnectionTopology.ConnectionOccurrenceID) -> Int? {
        pathIndexByID[id]
    }

    func pathID(at index: Int) -> ConnectionTopology.ConnectionOccurrenceID? {
        guard orderedPathIDs.indices.contains(index) else { return nil }
        return orderedPathIDs[index]
    }

    func contains(_ selection: OverviewTopologySelection) -> Bool {
        switch selection {
        case .node(let id):
            nodeByID[id] != nil
        case .edge(let id):
            edgeByID[id] != nil
        case .path(let id):
            pathByID[id] != nil
        }
    }

    func highlight(for selection: OverviewTopologySelection?) -> OverviewTopologyHighlight {
        highlightWithOperationCounts(for: selection).highlight
    }

    func highlightWithOperationCounts(
        for selection: OverviewTopologySelection?
    ) -> (
        highlight: OverviewTopologyHighlight,
        operationCounts: OverviewTopologyHighlightOperationCounts
    ) {
        guard let selection else { return (.empty, .init()) }

        let selectedPathIDs: [ConnectionTopology.ConnectionOccurrenceID]
        switch selection {
        case .node(let nodeID):
            selectedPathIDs = nodeByID[nodeID]?.pathIDs ?? []
        case .edge(let edgeID):
            selectedPathIDs = edgeByID[edgeID]?.pathIDs ?? []
        case .path(let pathID):
            selectedPathIDs = [pathID]
        }

        var counts = OverviewTopologyHighlightOperationCounts()
        counts.selectedPathIDCount = selectedPathIDs.count
        var pathIDs = Set<ConnectionTopology.ConnectionOccurrenceID>()
        pathIDs.reserveCapacity(selectedPathIDs.count)
        var nodeIDs = Set<String>()
        var edgeIDs = Set<String>()
        var paths: [ConnectionTopology.PathRecord] = []
        paths.reserveCapacity(selectedPathIDs.count)

        for pathID in selectedPathIDs {
            counts.pathRecordLookupCount += 1
            guard let path = pathByID[pathID] else { continue }
            pathIDs.insert(pathID)
            paths.append(path)
            counts.stageVisitCount += path.stages.count
            counts.edgeVisitCount += path.edgeIDs.count
            for stage in path.stages {
                nodeIDs.insert(stage.nodeID)
            }
            edgeIDs.formUnion(path.edgeIDs)
        }

        return (
            OverviewTopologyHighlight(
                pathIDs: pathIDs,
                nodeIDs: nodeIDs,
                edgeIDs: edgeIDs,
                paths: paths
            ),
            counts
        )
    }
}

struct OverviewTopologyLayout: Sendable {
    struct HitTestOperationCounts: Equatable, Sendable {
        let indexedTargetCount: Int
        let shapeCheckCount: Int
    }

    struct ColumnGeometry: Sendable {
        let id: ConnectionTopology.Column.ID
        let centerX: CGFloat
    }

    struct NodeGeometry: Sendable {
        enum LabelSide: Sendable {
            case leading
            case trailing
        }

        let node: ConnectionTopology.Node
        let rect: CGRect
        let labelRect: CGRect
        let labelSide: LabelSide
        let flowValue: CGFloat
        let hitRect: CGRect
        let drawingPath: Path
    }

    struct EdgeHitSegment: Sendable {
        let start: CGPoint
        let end: CGPoint
        let hitRect: CGRect
    }

    struct EdgeGeometry: Sendable {
        let edge: ConnectionTopology.Edge
        let source: CGPoint
        let target: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let width: CGFloat
        let hitTolerance: CGFloat
        let drawingPath: Path
        let hitRect: CGRect
        let hitSegments: [EdgeHitSegment]

        func point(at progress: CGFloat) -> CGPoint {
            let t = min(max(progress, 0), 1)
            let inverse = 1 - t
            let inverseSquared = inverse * inverse
            let tSquared = t * t
            return CGPoint(
                x: inverseSquared * inverse * source.x
                    + 3 * inverseSquared * t * control1.x
                    + 3 * inverse * tSquared * control2.x
                    + tSquared * t * target.x,
                y: inverseSquared * inverse * source.y
                    + 3 * inverseSquared * t * control1.y
                    + 3 * inverse * tSquared * control2.y
                    + tSquared * t * target.y
            )
        }
    }

    struct RenderBand: Identifiable, Sendable {
        let id: Int
        let bounds: CGRect
        let columns: [ColumnGeometry]
        let nodes: [NodeGeometry]
        let edges: [EdgeGeometry]
    }

    struct OperationCounts: Equatable, Sendable {
        let nodeGeometryCount: Int
        let edgeGeometryCount: Int
        let edgeHitSegmentCount: Int
        let hitIndexEntryCount: Int
        let renderBandCount: Int
        let renderBandNodeAdmissionCount: Int
        let renderBandEdgeAdmissionCount: Int
    }

    fileprivate struct HitCell: Hashable, Sendable {
        let x: Int
        let y: Int
    }

    fileprivate struct HitTarget: Sendable {
        enum Shape: Sendable {
            case rectangle(CGRect)
            case segment(start: CGPoint, end: CGPoint, tolerance: CGFloat)
        }

        let selection: OverviewTopologySelection
        let shape: Shape

        func contains(_ point: CGPoint) -> Bool {
            switch shape {
            case .rectangle(let rect):
                rect.contains(point)
            case .segment(let start, let end, let tolerance):
                Self.squaredDistance(from: point, toSegmentFrom: start, to: end)
                    <= tolerance * tolerance
            }
        }

        private static func squaredDistance(
            from point: CGPoint,
            toSegmentFrom start: CGPoint,
            to end: CGPoint
        ) -> CGFloat {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else {
                let pointDX = point.x - start.x
                let pointDY = point.y - start.y
                return pointDX * pointDX + pointDY * pointDY
            }
            let progress = min(
                max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0),
                1
            )
            let projectedX = start.x + progress * dx
            let projectedY = start.y + progress * dy
            let pointDX = point.x - projectedX
            let pointDY = point.y - projectedY
            return pointDX * pointDX + pointDY * pointDY
        }
    }

    static let renderBandHeight: CGFloat = 352
    static let columnHeaderHeight: CGFloat = 40
    fileprivate static let hitCellSize: CGFloat = 96

    let size: CGSize
    let columns: [ColumnGeometry]
    let nodes: [NodeGeometry]
    let edges: [EdgeGeometry]
    let renderBands: [RenderBand]
    let operationCounts: OperationCounts
    private let nodeGeometryByID: [String: NodeGeometry]
    private let hitIndex: [HitCell: [HitTarget]]

    func nodeGeometry(id: String) -> NodeGeometry? {
        nodeGeometryByID[id]
    }

    func hitTest(at point: CGPoint) -> OverviewTopologySelection? {
        hitTestWithOperationCounts(at: point).selection
    }

    func hitTestWithOperationCounts(
        at point: CGPoint
    ) -> (selection: OverviewTopologySelection?, operationCounts: HitTestOperationCounts) {
        let cell = Self.cell(for: point)
        guard let targets = hitIndex[cell] else {
            return (
                nil,
                HitTestOperationCounts(indexedTargetCount: 0, shapeCheckCount: 0)
            )
        }

        var shapeCheckCount = 0
        for target in targets.reversed() {
            shapeCheckCount += 1
            if target.contains(point) {
                return (
                    target.selection,
                    HitTestOperationCounts(
                        indexedTargetCount: targets.count,
                        shapeCheckCount: shapeCheckCount
                    )
                )
            }
        }
        return (
            nil,
            HitTestOperationCounts(
                indexedTargetCount: targets.count,
                shapeCheckCount: shapeCheckCount
            )
        )
    }

    fileprivate init(
        size: CGSize,
        columns: [ColumnGeometry],
        nodes: [NodeGeometry],
        edges: [EdgeGeometry],
        renderBands: [RenderBand],
        operationCounts: OperationCounts,
        hitIndex: [HitCell: [HitTarget]]
    ) {
        self.size = size
        self.columns = columns
        self.nodes = nodes
        self.edges = edges
        self.renderBands = renderBands
        self.operationCounts = operationCounts
        nodeGeometryByID = Dictionary(
            uniqueKeysWithValues: nodes.map { ($0.node.id, $0) }
        )
        self.hitIndex = hitIndex
    }

    fileprivate static func cell(for point: CGPoint) -> HitCell {
        HitCell(
            x: Int(floor(point.x / hitCellSize)),
            y: Int(floor(point.y / hitCellSize))
        )
    }
}

struct OverviewTopologyViewportTarget: Equatable, Sendable {
    enum ID: Hashable, Sendable {
        case node(String)
        case edge(String)
        case path(ConnectionTopology.ConnectionOccurrenceID)
    }

    let id: ID
    let centerX: CGFloat
}

enum OverviewTopologyViewportTargetResolver {
    static let acquisitionMargin: CGFloat = 28

    static func target(
        for selection: OverviewTopologySelection?,
        index: OverviewTopologyIndex,
        layout: OverviewTopologyLayout
    ) -> OverviewTopologyViewportTarget? {
        guard let selection, index.contains(selection) else { return nil }

        switch selection {
        case .node(let nodeID):
            guard let geometry = layout.nodeGeometry(id: nodeID) else { return nil }
            return OverviewTopologyViewportTarget(
                id: .node(nodeID),
                centerX: geometry.rect.midX
            )
        case .edge(let edgeID):
            guard let edge = index.edge(id: edgeID),
                  let centerX = edgeCenterX(edge, layout: layout) else {
                return nil
            }
            return OverviewTopologyViewportTarget(id: .edge(edgeID), centerX: centerX)
        case .path(let pathID):
            guard let path = index.path(id: pathID),
                  let centerX = pathCenterX(path, index: index, layout: layout) else {
                return nil
            }
            return OverviewTopologyViewportTarget(id: .path(pathID), centerX: centerX)
        }
    }

    /// Returns a clamped content offset only when the selected semantic anchor
    /// is outside the current acquisition range. A nil result leaves user
    /// scrolling untouched.
    static func contentOffsetX(
        for target: OverviewTopologyViewportTarget,
        visibleRect: CGRect,
        contentWidth: CGFloat,
        margin: CGFloat = acquisitionMargin
    ) -> CGFloat? {
        guard visibleRect.width > 0,
              contentWidth > visibleRect.width + 1 else {
            return nil
        }

        let boundedMargin = min(
            max(margin, 0),
            max(visibleRect.width / 2 - 1, 0)
        )
        let acquisitionRange = (visibleRect.minX + boundedMargin)...(
            visibleRect.maxX - boundedMargin
        )
        guard !acquisitionRange.contains(target.centerX) else { return nil }

        let maximumOffset = max(contentWidth - visibleRect.width, 0)
        let nextOffset = min(
            max(target.centerX - visibleRect.width / 2, 0),
            maximumOffset
        )
        guard abs(nextOffset - visibleRect.minX) > 0.5 else { return nil }
        return nextOffset
    }

    private static func pathCenterX(
        _ path: ConnectionTopology.PathRecord,
        index: OverviewTopologyIndex,
        layout: OverviewTopologyLayout
    ) -> CGFloat? {
        if let policyStage = path.stages.first(where: { stage in
            if case .policyHop = stage.columnID { return true }
            return false
        }), let geometry = layout.nodeGeometry(id: policyStage.nodeID) {
            return geometry.rect.midX
        }

        if !path.edgeIDs.isEmpty {
            let centralEdgeID = path.edgeIDs[path.edgeIDs.count / 2]
            if let edge = index.edge(id: centralEdgeID),
               let centerX = edgeCenterX(edge, layout: layout) {
                return centerX
            }
        }

        guard !path.stages.isEmpty else { return nil }
        let centralStage = path.stages[path.stages.count / 2]
        return layout.nodeGeometry(id: centralStage.nodeID)?.rect.midX
    }

    private static func edgeCenterX(
        _ edge: ConnectionTopology.Edge,
        layout: OverviewTopologyLayout
    ) -> CGFloat? {
        guard let source = layout.nodeGeometry(id: edge.sourceID),
              let target = layout.nodeGeometry(id: edge.targetID) else {
            return nil
        }
        return (source.rect.midX + target.rect.midX) / 2
    }
}

enum OverviewTopologyFlowScale {
    /// Mirrors Zashboard's Sankey projection while retaining the real count for labels.
    static func value(forConnectionCount connectionCount: Int) -> CGFloat {
        guard connectionCount > 0 else { return 0 }
        return CGFloat(log10(Double(connectionCount) + 1) * 10)
    }
}

enum OverviewTopologyLayoutBuilder {
    private static let edgeHitTolerance: CGFloat = 10
    private static let minimumNodeAcquisitionSize: CGFloat = 28
    private static let sankeyNodeWidth: CGFloat = 20
    /// Task 08-23 R10: long chains widen the graph past the panel instead of
    /// crushing labels into truncation; the viewport scrolls horizontally.
    /// 168 leaves 132pt of label width (step - node width - 2x label gap).
    private static let minimumColumnStep: CGFloat = 168
    private static let sankeyNodeGap: CGFloat = 8
    private static let nodeLabelGap: CGFloat = 8
    private static let sankeyCurveness: CGFloat = 0.5
    private static let minimumFlowPixelsPerUnit: CGFloat = 2.4
    private static let minimumReadableNodeHeight: CGFloat = 20
    private static let minimumFlowAreaHeight: CGFloat = 352
    /// The graph always connects adjacent columns. Eight subdivisions keep the
    /// polyline approximation comfortably inside the pointer hit corridor and
    /// bound segment generation while avoiding one broad curve rectangle.
    private static let edgeHitSubdivisionCount = 8

    @concurrent
    static func buildCancellable(
        topology: ConnectionTopology,
        availableWidth: CGFloat,
        minimumFlowHeight: CGFloat = 352,
        revision: UInt64 = 0
    ) async throws -> OverviewTopologyLayout {
        let interval = MicaPerformanceObservation.beginInterval(
            .topologyLayout,
            metadata: MicaPerformanceMetadata(
                count: UInt64(topology.paths.count),
                revision: revision
            )
        )
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let layout = try await build(
                topology: topology,
                availableWidth: availableWidth,
                minimumFlowHeight: minimumFlowHeight
            )
            MicaPerformanceObservation.endInterval(
                interval,
                metadata: MicaPerformanceMetadata(
                    count: UInt64(layout.nodes.count + layout.edges.count),
                    revision: revision,
                    duration: start.duration(to: clock.now)
                )
            )
            MicaPerformanceObservation.record(
                .topologyHitIndex,
                metadata: MicaPerformanceMetadata(
                    count: UInt64(layout.operationCounts.hitIndexEntryCount),
                    revision: revision
                )
            )
            return layout
        } catch {
            MicaPerformanceObservation.endInterval(
                interval,
                metadata: MicaPerformanceMetadata(
                    count: UInt64(topology.paths.count),
                    revision: revision,
                    duration: start.duration(to: clock.now)
                )
            )
            throw error
        }
    }

    private static func build(
        topology: ConnectionTopology,
        availableWidth: CGFloat,
        minimumFlowHeight: CGFloat
    ) async throws -> OverviewTopologyLayout {
        let topInset = OverviewTopologyLayout.columnHeaderHeight + 12
        let sideInset: CGFloat = 20
        let bottomInset: CGFloat = 32
        let fittedWidth = max(availableWidth.rounded(.down), 1)

        var workCount = 0
        var edgeFlowByID: [String: CGFloat] = [:]
        var incomingFlowByNodeID: [String: CGFloat] = [:]
        var outgoingFlowByNodeID: [String: CGFloat] = [:]
        var incomingEdgesByNodeID: [String: [ConnectionTopology.Edge]] = [:]
        var outgoingEdgesByNodeID: [String: [ConnectionTopology.Edge]] = [:]
        edgeFlowByID.reserveCapacity(topology.edges.count)
        incomingEdgesByNodeID.reserveCapacity(topology.nodes.count)
        outgoingEdgesByNodeID.reserveCapacity(topology.nodes.count)

        for edge in topology.edges {
            try await checkpoint(&workCount)
            let flow = OverviewTopologyFlowScale.value(
                forConnectionCount: edge.connectionCount
            )
            edgeFlowByID[edge.id] = flow
            incomingFlowByNodeID[edge.targetID, default: 0] += flow
            outgoingFlowByNodeID[edge.sourceID, default: 0] += flow
            incomingEdgesByNodeID[edge.targetID, default: []].append(edge)
            outgoingEdgesByNodeID[edge.sourceID, default: []].append(edge)
        }

        var nodeFlowByID: [String: CGFloat] = [:]
        nodeFlowByID.reserveCapacity(topology.nodes.count)
        for node in topology.nodes {
            try await checkpoint(&workCount)
            nodeFlowByID[node.id] = max(
                max(
                    incomingFlowByNodeID[node.id, default: 0],
                    outgoingFlowByNodeID[node.id, default: 0]
                ),
                OverviewTopologyFlowScale.value(
                    forConnectionCount: node.connectionCount
                )
            )
        }

        // Flow-following node order (task 08-23 R8): the first column keeps
        // name order; every later column sorts by the flow-weighted mean slot
        // of its upstream neighbors (barycenter), so parallel flows become
        // near-parallel edges instead of maximal crossings. Name order breaks
        // ties, keeping the layout fully deterministic.
        var orderedColumns: [[ConnectionTopology.Node]] = []
        orderedColumns.reserveCapacity(topology.columns.count)
        var slotByNodeID: [String: Int] = [:]
        for (columnIndex, column) in topology.columns.enumerated() {
            let ordered: [ConnectionTopology.Node]
            if columnIndex == 0 {
                ordered = column.nodes.sorted(by: sankeyNodeOrder)
            } else {
                let barycenterKeys = Dictionary(
                    uniqueKeysWithValues: column.nodes.map { node in
                        (
                            node.id,
                            barycenterKey(
                                for: node,
                                incomingEdgesByNodeID: incomingEdgesByNodeID,
                                edgeFlowByID: edgeFlowByID,
                                slotByNodeID: slotByNodeID
                            )
                        )
                    }
                )
                ordered = column.nodes.sorted { left, right in
                    let leftKey = barycenterKeys[left.id] ?? .greatestFiniteMagnitude
                    let rightKey = barycenterKeys[right.id] ?? .greatestFiniteMagnitude
                    if leftKey != rightKey {
                        return leftKey < rightKey
                    }
                    return sankeyNodeOrder(left, right)
                }
            }
            for (slot, node) in ordered.enumerated() {
                slotByNodeID[node.id] = slot
            }
            orderedColumns.append(ordered)
        }

        let columnPlans = topology.columns.enumerated().map { columnIndex, column in
            let orderedNodes = orderedColumns[columnIndex]
            let totalFlow = orderedNodes.reduce(CGFloat.zero) { partial, node in
                partial + max(
                    nodeFlowByID[node.id, default: 0],
                    OverviewTopologyFlowScale.value(forConnectionCount: 1)
                )
            }
            let gaps = sankeyNodeGap * CGFloat(max(orderedNodes.count - 1, 0))
            let minimumReadableScale = minimumReadableNodeHeight
                / OverviewTopologyFlowScale.value(forConnectionCount: 1)
            return ColumnPlan(
                column: column,
                nodes: orderedNodes,
                totalFlow: totalFlow,
                minimumHeight: totalFlow
                    * max(minimumFlowPixelsPerUnit, minimumReadableScale)
                    + gaps
            )
        }
        let flowAreaHeight = max(
            max(minimumFlowAreaHeight, minimumFlowHeight),
            columnPlans.map(\.minimumHeight).max() ?? 0
        )
        let valueScale = columnPlans.compactMap { plan -> CGFloat? in
            guard plan.totalFlow > 0 else { return nil }
            let gaps = sankeyNodeGap * CGFloat(max(plan.nodes.count - 1, 0))
            return max(flowAreaHeight - gaps, 0) / plan.totalFlow
        }.min() ?? minimumFlowPixelsPerUnit
        let graphHeight = topInset + flowAreaHeight + bottomInset
        let columnCount = max(columnPlans.count, 1)
        let graphWidth = max(
            fittedWidth,
            sideInset * 2 + sankeyNodeWidth
                + minimumColumnStep * CGFloat(max(columnCount - 1, 0))
        )
        let usableColumnSpan = max(
            graphWidth - sideInset * 2 - sankeyNodeWidth,
            0
        )
        let columnStep = columnCount > 1
            ? usableColumnSpan / CGFloat(columnCount - 1)
            : 0

        var columns: [OverviewTopologyLayout.ColumnGeometry] = []
        var nodeRects: [String: CGRect] = [:]
        var nodes: [OverviewTopologyLayout.NodeGeometry] = []
        nodes.reserveCapacity(topology.nodes.count)

        for (columnIndex, plan) in columnPlans.enumerated() {
            try await checkpoint(&workCount)
            let barX = sideInset + CGFloat(columnIndex) * columnStep
            let centerX = barX + sankeyNodeWidth / 2
            let columnHeight = plan.totalFlow * valueScale
                + sankeyNodeGap * CGFloat(max(plan.nodes.count - 1, 0))
            var nextY = topInset + max((flowAreaHeight - columnHeight) / 2, 0)
            columns.append(
                OverviewTopologyLayout.ColumnGeometry(
                    id: plan.column.id,
                    centerX: centerX
                )
            )
            for node in plan.nodes {
                try await checkpoint(&workCount)
                let flowValue = max(
                    nodeFlowByID[node.id, default: 0],
                    OverviewTopologyFlowScale.value(forConnectionCount: 1)
                )
                let nodeHeight = max(flowValue * valueScale, 1)
                let rect = CGRect(
                    x: barX,
                    y: nextY,
                    width: sankeyNodeWidth,
                    height: nodeHeight
                )
                let isTerminalColumn = columnIndex == columnPlans.count - 1
                let labelWidth = columnPlans.count > 1
                    ? max(columnStep - sankeyNodeWidth - nodeLabelGap * 2, 12)
                    : max(
                        graphWidth - sideInset * 2 - sankeyNodeWidth - nodeLabelGap,
                        12
                    )
                let labelHeight = max(min(nodeHeight, 28), 18)
                let labelRect = CGRect(
                    x: isTerminalColumn
                        ? max(rect.minX - labelWidth - nodeLabelGap, 0)
                        : rect.maxX + nodeLabelGap,
                    y: rect.midY - labelHeight / 2,
                    width: labelWidth,
                    height: labelHeight
                )
                let labelHitWidth = min(
                    labelWidth,
                    max(
                        minimumNodeAcquisitionSize - sankeyNodeWidth,
                        min(CGFloat(node.name.count) * 7 + 10, 160)
                    )
                )
                let labelHitRect = CGRect(
                    x: isTerminalColumn
                        ? labelRect.maxX - labelHitWidth
                        : labelRect.minX,
                    y: labelRect.minY,
                    width: labelHitWidth,
                    height: labelRect.height
                )
                let interactiveContentRect = rect.union(labelHitRect)
                let hitRect = interactiveContentRect.insetBy(
                    dx: -max(
                        (minimumNodeAcquisitionSize - interactiveContentRect.width) / 2,
                        0
                    ),
                    dy: -max(
                        (minimumNodeAcquisitionSize - interactiveContentRect.height) / 2,
                        0
                    )
                )
                nodeRects[node.id] = rect
                nodes.append(
                    OverviewTopologyLayout.NodeGeometry(
                        node: node,
                        rect: rect,
                        labelRect: labelRect,
                        labelSide: isTerminalColumn ? .trailing : .leading,
                        flowValue: flowValue,
                        hitRect: hitRect,
                        drawingPath: Path(
                            roundedRect: rect,
                            cornerRadius: min(4, nodeHeight / 2)
                        )
                    )
                )
                nextY += nodeHeight + sankeyNodeGap
            }
        }

        var sourceYByEdgeID: [String: CGFloat] = [:]
        var targetYByEdgeID: [String: CGFloat] = [:]
        sourceYByEdgeID.reserveCapacity(topology.edges.count)
        targetYByEdgeID.reserveCapacity(topology.edges.count)
        for node in nodes {
            try await checkpoint(&workCount)
            let outgoing = outgoingEdgesByNodeID[node.node.id, default: []].sorted {
                sankeyEdgeOrder(
                    $0,
                    $1,
                    counterpart: \.targetID,
                    nodeRects: nodeRects
                )
            }
            let incoming = incomingEdgesByNodeID[node.node.id, default: []].sorted {
                sankeyEdgeOrder(
                    $0,
                    $1,
                    counterpart: \.sourceID,
                    nodeRects: nodeRects
                )
            }
            assignEdgeCenters(
                outgoing,
                in: node.rect,
                edgeFlowByID: edgeFlowByID,
                valueScale: valueScale,
                result: &sourceYByEdgeID
            )
            assignEdgeCenters(
                incoming,
                in: node.rect,
                edgeFlowByID: edgeFlowByID,
                valueScale: valueScale,
                result: &targetYByEdgeID
            )
        }

        var edges: [OverviewTopologyLayout.EdgeGeometry] = []
        edges.reserveCapacity(topology.edges.count)
        for edge in topology.edges {
            try await checkpoint(&workCount)
            guard let sourceRect = nodeRects[edge.sourceID],
                  let targetRect = nodeRects[edge.targetID] else {
                continue
            }
            let width = max(edgeFlowByID[edge.id, default: 0] * valueScale, 1)
            let source = CGPoint(
                x: sourceRect.maxX,
                y: sourceYByEdgeID[edge.id, default: sourceRect.midY]
            )
            let target = CGPoint(
                x: targetRect.minX,
                y: targetYByEdgeID[edge.id, default: targetRect.midY]
            )
            let edgeDistance = max(target.x - source.x, 0)
            let controlOffset = edgeDistance * sankeyCurveness
            let control1 = CGPoint(x: source.x + controlOffset, y: source.y)
            let control2 = CGPoint(x: target.x - controlOffset, y: target.y)
            let drawingPath = sankeyRibbonPath(
                source: source,
                target: target,
                control1: control1,
                control2: control2,
                width: width
            )
            let hitTolerance = max(edgeHitTolerance, width / 2 + 2)
            let hitSegments = edgeHitSegments(
                source: source,
                target: target,
                control1: control1,
                control2: control2,
                tolerance: hitTolerance
            )
            let hitRect = hitSegments.reduce(CGRect.null) { partial, segment in
                partial.union(segment.hitRect)
            }
            edges.append(
                OverviewTopologyLayout.EdgeGeometry(
                    edge: edge,
                    source: source,
                    target: target,
                    control1: control1,
                    control2: control2,
                    width: width,
                    hitTolerance: hitTolerance,
                    drawingPath: drawingPath,
                    hitRect: hitRect,
                    hitSegments: hitSegments
                )
            )
        }

        var hitIndex: [
            OverviewTopologyLayout.HitCell: [OverviewTopologyLayout.HitTarget]
        ] = [:]
        var hitIndexEntryCount = 0
        var edgeHitSegmentCount = 0
        // Expanded node targets remain easy to acquire, but ribbons must win
        // wherever invisible pointer padding overlaps the visible flow.
        for node in nodes {
            try await checkpoint(&workCount)
            hitIndexEntryCount += index(
                selection: .node(node.node.id),
                shape: .rectangle(node.hitRect),
                bounds: node.hitRect,
                in: &hitIndex
            )
        }
        for edge in edges {
            for segment in edge.hitSegments {
                try await checkpoint(&workCount)
                edgeHitSegmentCount += 1
                hitIndexEntryCount += index(
                    selection: .edge(edge.edge.id),
                    shape: .segment(
                        start: segment.start,
                        end: segment.end,
                        tolerance: edge.hitTolerance
                    ),
                    bounds: segment.hitRect,
                    in: &hitIndex
                )
            }
        }
        // The visible node bar remains the highest-priority hit target.
        for node in nodes {
            try await checkpoint(&workCount)
            hitIndexEntryCount += index(
                selection: .node(node.node.id),
                shape: .rectangle(node.rect),
                bounds: node.rect,
                in: &hitIndex
            )
        }

        let graphSize = CGSize(width: graphWidth, height: graphHeight)
        let renderBandProjection = try await renderBands(
            size: graphSize,
            columns: columns,
            nodes: nodes,
            edges: edges
        )
        try Task.checkCancellation()
        return OverviewTopologyLayout(
            size: graphSize,
            columns: columns,
            nodes: nodes,
            edges: edges,
            renderBands: renderBandProjection.bands,
            operationCounts: OverviewTopologyLayout.OperationCounts(
                nodeGeometryCount: nodes.count,
                edgeGeometryCount: edges.count,
                edgeHitSegmentCount: edgeHitSegmentCount,
                hitIndexEntryCount: hitIndexEntryCount,
                renderBandCount: renderBandProjection.bands.count,
                renderBandNodeAdmissionCount: renderBandProjection.nodeAdmissionCount,
                renderBandEdgeAdmissionCount: renderBandProjection.edgeAdmissionCount
            ),
            hitIndex: hitIndex
        )
    }

    private struct ColumnPlan {
        let column: ConnectionTopology.Column
        let nodes: [ConnectionTopology.Node]
        let totalFlow: CGFloat
        let minimumHeight: CGFloat
    }

    private static func sankeyNodeOrder(
        _ left: ConnectionTopology.Node,
        _ right: ConnectionTopology.Node
    ) -> Bool {
        let comparison = left.name.localizedCaseInsensitiveCompare(right.name)
        if comparison == .orderedSame {
            return left.id < right.id
        }
        return comparison == .orderedAscending
    }

    /// Flow-weighted mean slot of a node's upstream neighbors (task 08-23).
    /// Nodes with no incoming edge sink to the bottom via +inf. Internal (not
    /// private) so tests can pin the sink behavior directly.
    static func barycenterKey(
        for node: ConnectionTopology.Node,
        incomingEdgesByNodeID: [String: [ConnectionTopology.Edge]],
        edgeFlowByID: [String: CGFloat],
        slotByNodeID: [String: Int]
    ) -> CGFloat {
        var weightedSum: CGFloat = 0
        var totalWeight: CGFloat = 0
        for edge in incomingEdgesByNodeID[node.id, default: []] {
            guard let slot = slotByNodeID[edge.sourceID] else { continue }
            let weight = max(edgeFlowByID[edge.id, default: 1], 1)
            weightedSum += CGFloat(slot) * weight
            totalWeight += weight
        }
        return totalWeight > 0 ? weightedSum / totalWeight : .greatestFiniteMagnitude
    }

    private static func sankeyEdgeOrder(
        _ left: ConnectionTopology.Edge,
        _ right: ConnectionTopology.Edge,
        counterpart: KeyPath<ConnectionTopology.Edge, String>,
        nodeRects: [String: CGRect]
    ) -> Bool {
        let leftID = left[keyPath: counterpart]
        let rightID = right[keyPath: counterpart]
        let leftY = nodeRects[leftID]?.midY ?? 0
        let rightY = nodeRects[rightID]?.midY ?? 0
        if leftY == rightY {
            return left.id < right.id
        }
        return leftY < rightY
    }

    private static func assignEdgeCenters(
        _ edges: [ConnectionTopology.Edge],
        in nodeRect: CGRect,
        edgeFlowByID: [String: CGFloat],
        valueScale: CGFloat,
        result: inout [String: CGFloat]
    ) {
        let totalWidth = edges.reduce(CGFloat.zero) { partial, edge in
            partial + edgeFlowByID[edge.id, default: 0] * valueScale
        }
        var nextY = nodeRect.minY + max((nodeRect.height - totalWidth) / 2, 0)
        for edge in edges {
            let width = max(edgeFlowByID[edge.id, default: 0] * valueScale, 1)
            result[edge.id] = nextY + width / 2
            nextY += width
        }
    }

    private static func sankeyRibbonPath(
        source: CGPoint,
        target: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        width: CGFloat
    ) -> Path {
        let halfWidth = width / 2
        let sourceTop = CGPoint(x: source.x, y: source.y - halfWidth)
        let targetTop = CGPoint(x: target.x, y: target.y - halfWidth)
        let sourceBottom = CGPoint(x: source.x, y: source.y + halfWidth)
        let targetBottom = CGPoint(x: target.x, y: target.y + halfWidth)
        var path = Path()
        path.move(to: sourceTop)
        path.addCurve(
            to: targetTop,
            control1: CGPoint(x: control1.x, y: control1.y - halfWidth),
            control2: CGPoint(x: control2.x, y: control2.y - halfWidth)
        )
        path.addLine(to: targetBottom)
        path.addCurve(
            to: sourceBottom,
            control1: CGPoint(x: control2.x, y: control2.y + halfWidth),
            control2: CGPoint(x: control1.x, y: control1.y + halfWidth)
        )
        path.closeSubpath()
        return path
    }

    private struct RenderBandProjection {
        let bands: [OverviewTopologyLayout.RenderBand]
        let nodeAdmissionCount: Int
        let edgeAdmissionCount: Int
    }

    private static func renderBands(
        size: CGSize,
        columns: [OverviewTopologyLayout.ColumnGeometry],
        nodes: [OverviewTopologyLayout.NodeGeometry],
        edges: [OverviewTopologyLayout.EdgeGeometry]
    ) async throws -> RenderBandProjection {
        let bandHeight = OverviewTopologyLayout.renderBandHeight
        let bandCount = max(Int(ceil(size.height / bandHeight)), 1)
        var nodesByBand = Array(
            repeating: [OverviewTopologyLayout.NodeGeometry](),
            count: bandCount
        )
        var edgesByBand = Array(
            repeating: [OverviewTopologyLayout.EdgeGeometry](),
            count: bandCount
        )
        var nodeAdmissionCount = 0
        var edgeAdmissionCount = 0
        var workCount = 0

        for node in nodes {
            for bandIndex in bandIndices(
                intersecting: node.rect,
                bandCount: bandCount
            ) {
                try await checkpoint(&workCount)
                nodesByBand[bandIndex].append(node)
                nodeAdmissionCount += 1
            }
        }

        for edge in edges {
            let drawingBounds = edge.drawingPath.boundingRect.insetBy(dx: -3, dy: -3)
            for bandIndex in bandIndices(
                intersecting: drawingBounds,
                bandCount: bandCount
            ) {
                try await checkpoint(&workCount)
                edgesByBand[bandIndex].append(edge)
                edgeAdmissionCount += 1
            }
        }

        var bands: [OverviewTopologyLayout.RenderBand] = []
        bands.reserveCapacity(bandCount)
        for bandIndex in 0..<bandCount {
            try await checkpoint(&workCount)
            let minY = CGFloat(bandIndex) * bandHeight
            let height = min(bandHeight, max(size.height - minY, 0))
            bands.append(
                OverviewTopologyLayout.RenderBand(
                    id: bandIndex,
                    bounds: CGRect(
                        x: 0,
                        y: minY,
                        width: size.width,
                        height: height
                    ),
                    columns: bandIndex == 0 ? columns : [],
                    nodes: nodesByBand[bandIndex],
                    edges: edgesByBand[bandIndex]
                )
            )
        }

        try Task.checkCancellation()
        return RenderBandProjection(
            bands: bands,
            nodeAdmissionCount: nodeAdmissionCount,
            edgeAdmissionCount: edgeAdmissionCount
        )
    }

    private static func bandIndices(
        intersecting bounds: CGRect,
        bandCount: Int
    ) -> ClosedRange<Int> {
        let bandHeight = OverviewTopologyLayout.renderBandHeight
        let lowerBound = min(
            max(Int(floor(max(bounds.minY, 0) / bandHeight)), 0),
            bandCount - 1
        )
        let upperBound = min(
            max(Int(floor(max(bounds.maxY, 0) / bandHeight)), lowerBound),
            bandCount - 1
        )
        return lowerBound...upperBound
    }

    private static func checkpoint(_ workCount: inout Int) async throws {
        workCount += 1
        guard workCount.isMultiple(of: 64) else { return }
        try Task.checkCancellation()
        await Task.yield()
    }

    private static func edgeHitSegments(
        source: CGPoint,
        target: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        tolerance: CGFloat
    ) -> [OverviewTopologyLayout.EdgeHitSegment] {
        let segmentCount = edgeHitSubdivisionCount
        var result: [OverviewTopologyLayout.EdgeHitSegment] = []
        result.reserveCapacity(segmentCount)
        var previous = source
        for index in 1...segmentCount {
            let progress = CGFloat(index) / CGFloat(segmentCount)
            let next = cubicPoint(
                progress: progress,
                source: source,
                target: target,
                control1: control1,
                control2: control2
            )
            let bounds = CGRect(
                x: min(previous.x, next.x),
                y: min(previous.y, next.y),
                width: abs(next.x - previous.x),
                height: abs(next.y - previous.y)
            ).insetBy(dx: -tolerance, dy: -tolerance)
            result.append(
                OverviewTopologyLayout.EdgeHitSegment(
                    start: previous,
                    end: next,
                    hitRect: bounds
                )
            )
            previous = next
        }
        return result
    }

    private static func cubicPoint(
        progress: CGFloat,
        source: CGPoint,
        target: CGPoint,
        control1: CGPoint,
        control2: CGPoint
    ) -> CGPoint {
        let inverse = 1 - progress
        let inverseSquared = inverse * inverse
        let progressSquared = progress * progress
        return CGPoint(
            x: inverseSquared * inverse * source.x
                + 3 * inverseSquared * progress * control1.x
                + 3 * inverse * progressSquared * control2.x
                + progressSquared * progress * target.x,
            y: inverseSquared * inverse * source.y
                + 3 * inverseSquared * progress * control1.y
                + 3 * inverse * progressSquared * control2.y
                + progressSquared * progress * target.y
        )
    }

    private static func index(
        selection: OverviewTopologySelection,
        shape: OverviewTopologyLayout.HitTarget.Shape,
        bounds: CGRect,
        in index: inout [
            OverviewTopologyLayout.HitCell: [OverviewTopologyLayout.HitTarget]
        ]
    ) -> Int {
        let minX = Int(floor(bounds.minX / OverviewTopologyLayout.hitCellSize))
        let maxX = Int(floor(bounds.maxX / OverviewTopologyLayout.hitCellSize))
        let minY = Int(floor(bounds.minY / OverviewTopologyLayout.hitCellSize))
        let maxY = Int(floor(bounds.maxY / OverviewTopologyLayout.hitCellSize))
        let target = OverviewTopologyLayout.HitTarget(
            selection: selection,
            shape: shape
        )
        var entryCount = 0
        for y in minY...maxY {
            for x in minX...maxX {
                index[OverviewTopologyLayout.HitCell(x: x, y: y), default: []].append(target)
                entryCount += 1
            }
        }
        return entryCount
    }
}

enum OverviewTopologyProjection {
    static func paths(
        for selection: OverviewTopologySelection,
        in index: OverviewTopologyIndex
    ) -> [ConnectionTopology.PathRecord] {
        index.highlight(for: selection).paths
    }

    static func selectionLabel(
        _ selection: OverviewTopologySelection,
        in index: OverviewTopologyIndex,
        language: AppLanguage
    ) -> String {
        switch selection {
        case .node(let id):
            return index.node(id: id)?.name
                ?? MicaStrings.localizedKey("overview.config_not_reported", language: language)
        case .edge(let id):
            guard let edge = index.edge(id: id) else {
                return MicaStrings.localizedKey("overview.config_not_reported", language: language)
            }
            return "\(edge.sourceName) -> \(edge.targetName)"
        case .path(let id):
            guard let path = index.path(id: id) else {
                return MicaStrings.localizedKey("overview.config_not_reported", language: language)
            }
            return pathLabel(path, language: language)
        }
    }

    static func pathLabel(
        _ path: ConnectionTopology.PathRecord,
        language: AppLanguage
    ) -> String {
        let unavailable = MicaStrings.localizedKey(
            "overview.config_not_reported",
            language: language
        )
        let value = nonBlank(path.reportedConnectionID) ?? unavailable
        return "\(path.sourceIndex + 1). \(value)"
    }

    static func selectionDescription(
        _ selection: OverviewTopologySelection,
        in index: OverviewTopologyIndex,
        language: AppLanguage
    ) -> String {
        switch selection {
        case .node(let id):
            guard let node = index.node(id: id) else {
                return MicaStrings.localizedKey(
                    "overview.config_not_reported",
                    language: language
                )
            }
            let role = columnTitle(node.columnID, language: language)
            let count = MicaStrings.localized(
                "routing.rule_match_count \(node.connectionCount)",
                language: language
            )
            return "\(role) · \(count)"
        case .edge(let id):
            guard let edge = index.edge(id: id) else {
                return MicaStrings.localizedKey(
                    "overview.config_not_reported",
                    language: language
                )
            }
            return MicaStrings.localized(
                "routing.rule_match_count \(edge.connectionCount)",
                language: language
            )
        case .path(let id):
            guard let path = index.path(id: id) else {
                return MicaStrings.localizedKey(
                    "overview.config_not_reported",
                    language: language
                )
            }
            return pathDescription(path, language: language)
        }
    }

    static func pathDescription(
        _ path: ConnectionTopology.PathRecord,
        language: AppLanguage
    ) -> String {
        let unavailable = MicaStrings.localizedKey(
            "overview.config_not_reported",
            language: language
        )
        let stages = path.stages.map(\.name)
        let route = stages.isEmpty ? unavailable : stages.joined(separator: " -> ")
        let missing = unavailableDescription(path, language: language)
        return missing.isEmpty ? route : "\(route); \(missing)"
    }

    private static func unavailableDescription(
        _ path: ConnectionTopology.PathRecord,
        language: AppLanguage
    ) -> String {
        let unavailable = MicaStrings.localizedKey(
            "overview.config_not_reported",
            language: language
        )
        switch path.routeState {
        case .available:
            return ""
        case .routeUnavailable(.missingSource):
            return "\(MicaStrings.localizedKey("overview.topology_source", language: language)): \(unavailable)"
        case .routeUnavailable(.missingChain):
            return "\(MicaStrings.localizedKey("overview.topology_exit", language: language)): \(unavailable)"
        case .routeUnavailable(.missingSourceAndChain):
            return "\(MicaStrings.localizedKey("overview.topology_source", language: language)): \(unavailable); \(MicaStrings.localizedKey("overview.topology_exit", language: language)): \(unavailable)"
        }
    }

    static func columnTitle(
        _ id: ConnectionTopology.Column.ID,
        language: AppLanguage
    ) -> String {
        switch id {
        case .source:
            MicaStrings.localizedKey("overview.topology_source", language: language)
        case .rule:
            MicaStrings.localizedKey("overview.topology_rule", language: language)
        case .policyHop(let depth):
            "\(MicaStrings.localizedKey("overview.topology_entry", language: language)) \(depth + 1)"
        case .finalOutbound:
            MicaStrings.localizedKey("overview.topology_exit", language: language)
        }
    }

    /// Muted identity tint for a topology column (task 08-23). The tint
    /// encodes column identity only; controller-reported status colors and
    /// the accent always win over it.
    static func columnTint(
        for id: ConnectionTopology.Column.ID
    ) -> Color {
        switch id {
        case .source:
            MicaTheme.ColumnTint.source
        case .rule:
            MicaTheme.ColumnTint.rule
        case .policyHop:
            MicaTheme.ColumnTint.policyHop
        case .finalOutbound:
            MicaTheme.ColumnTint.finalOutbound
        }
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : value
    }
}


// MARK: - Column header geometry (task 08-20 R4)

/// Pure column-header placement helpers: titles stay fully inside their render
/// band at any panel width, so the trailing column title can never be clipped
/// by the panel shape.
enum OverviewTopologyHeaderGeometry {
    /// Breathing room subtracted from every title slice so adjacent titles
    /// keep a visible gap even when both fill their slices.
    private static let titleGutter: CGFloat = 8

    /// Horizontal slice a column title may occupy. Closed form (task 08-23):
    /// capped by the band width, by twice the distance to each band edge (so
    /// `clampedCenter` never has to push the center inward - the push used to
    /// be what collided with neighbors), and by the distance to each adjacent
    /// column center (so neighboring half-slices never overlap), minus a
    /// gutter.
    static func sliceWidth(
        for column: OverviewTopologyLayout.ColumnGeometry,
        in band: OverviewTopologyLayout.RenderBand
    ) -> CGFloat {
        let centers = band.columns.map(\.centerX)
        guard let index = centers.firstIndex(of: column.centerX) else {
            return max(band.bounds.width, 1)
        }
        let bandWidth = max(band.bounds.width, 1)
        let centerX = column.centerX - band.bounds.minX
        var slice = bandWidth
        slice = min(slice, 2 * max(centerX, 0))
        slice = min(slice, 2 * max(bandWidth - centerX, 0))
        if index > 0 {
            slice = min(slice, abs(centers[index] - centers[index - 1]))
        }
        if index < centers.count - 1 {
            slice = min(slice, abs(centers[index + 1] - centers[index]))
        }
        return max(slice - titleGutter, 1)
    }

    /// Title center clamped so the whole slice - and therefore the title,
    /// which truncates to the slice - stays inside the band.
    static func clampedCenter(
        sliceWidth: CGFloat,
        columnCenterX: CGFloat,
        bandWidth: CGFloat
    ) -> CGFloat {
        let boundedWidth = max(bandWidth, 1)
        let half = min(max(sliceWidth, 1), boundedWidth) / 2
        return min(max(columnCenterX, half), max(boundedWidth - half, half))
    }
}

// MARK: - Node status (moved from the topology view in task 08-20)

/// Controller-reported status resolution for policy-hop nodes. Internal (not
/// private) so `OverviewTopologyRuntime` can memoize per-revision results.
enum OverviewTopologyNodeStatus {
    static func resolve(
        name: String,
        policyIndex: OverviewPolicyInspectionIndex
    ) -> MicaTheme.Status {
        let delay: Int?
        switch policyIndex.resolve(name: name) {
        case .group(let group):
            delay = group.selectedMember.delay
        case .member(let member):
            delay = member.delay
        case .ambiguous, .missing:
            delay = nil
        }
        guard let delay, delay > 0 else { return .neutral }
        switch LatencyHealthGrade.allCases.first(where: { $0.includes(delay: delay) }) {
        case .fast?, .normal?:
            return .ok
        case .slow?:
            return .warning
        case .timeout?:
            return .error
        case nil:
            return .neutral
        }
    }
}
