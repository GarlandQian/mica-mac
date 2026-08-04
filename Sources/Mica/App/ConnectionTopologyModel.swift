import Foundation
import MicaCore

/// A complete projection of controller-reported active connection paths.
///
/// Dynamic columns are the canonical layout input. The semantic `Layer` roles
/// remain useful for styling and for grouping nodes independent of path depth.
struct ConnectionTopology: Equatable, Sendable {
    enum Layer: Int, CaseIterable, Equatable, Hashable, Sendable {
        case source
        case rule
        case proxyEntry
        case proxyExit
    }

    struct ConnectionOccurrenceID: Equatable, Hashable, Sendable {
        /// The trimmed controller ID, or `nil` when the controller did not report one.
        let reportedID: String?
        /// Zero-based occurrence among connections with the same reported-ID state.
        let occurrence: Int

        var stableKey: String {
            if let reportedID {
                return "reported:\(reportedID.utf8.count):\(reportedID):\(occurrence)"
            }
            return "unreported:\(occurrence)"
        }
    }

    struct Column: Identifiable, Equatable, Sendable {
        enum ID: Equatable, Hashable, Sendable {
            case source
            case rule
            case policyHop(Int)
            case finalOutbound

            fileprivate var layer: Layer {
                switch self {
                case .source:
                    .source
                case .rule:
                    .rule
                case .policyHop:
                    .proxyEntry
                case .finalOutbound:
                    .proxyExit
                }
            }

            fileprivate var order: Int {
                switch self {
                case .source:
                    0
                case .rule:
                    1
                case .policyHop(let depth):
                    2 + depth
                case .finalOutbound:
                    .max
                }
            }

            fileprivate var stableKey: String {
                switch self {
                case .source:
                    "source"
                case .rule:
                    "rule"
                case .policyHop(let depth):
                    "policy:\(depth)"
                case .finalOutbound:
                    "final"
                }
            }
        }

        let id: ID
        let nodes: [Node]

        var layer: Layer { id.layer }
    }

    struct Stage: Equatable, Sendable {
        let nodeID: String
        let columnID: Column.ID
        let name: String

        var layer: Layer { columnID.layer }
    }

    struct PathRecord: Identifiable, Equatable, Sendable {
        enum RouteState: Equatable, Sendable {
            case available
            case routeUnavailable(RouteUnavailableReason)
        }

        enum RouteUnavailableReason: Equatable, Sendable {
            case missingSource
            case missingChain
            case missingSourceAndChain
        }

        let id: ConnectionOccurrenceID
        let sourceIndex: Int
        /// The exact controller-reported value, including blank values.
        let reportedConnectionID: String
        /// Known real stages in source-to-final order. Unavailable routes may be partial.
        let stages: [Stage]
        /// Aggregated graph edges used by this path. Empty for unavailable routes.
        let edgeIDs: [String]
        let routeState: RouteState

        var source: String? {
            stages.first(where: { $0.columnID == .source })?.name
        }

        var rule: String? {
            stages.first(where: { $0.columnID == .rule })?.name
        }

        var policyHops: [String] {
            stages.compactMap { stage in
                guard case .policyHop = stage.columnID else { return nil }
                return stage.name
            }
        }

        var finalOutbound: String? {
            stages.first(where: { $0.columnID == .finalOutbound })?.name
        }

        var nodeIDs: [String] { stages.map(\.nodeID) }
        var isDrawable: Bool { routeState == .available }
    }

    struct Node: Identifiable, Equatable, Sendable {
        let id: String
        let columnID: Column.ID
        let name: String
        /// Paths traversing this shared semantic vertex, in controller order.
        let pathIDs: [ConnectionOccurrenceID]

        var layer: Layer { columnID.layer }
        var connectionCount: Int { pathIDs.count }
    }

    struct Edge: Identifiable, Equatable, Sendable {
        let id: String
        let sourceID: String
        let targetID: String
        let sourceName: String
        let targetName: String
        let sourceColumnID: Column.ID
        let targetColumnID: Column.ID
        /// Paths traversing this shared adjacency, in controller order.
        let pathIDs: [ConnectionOccurrenceID]

        var sourceLayer: Layer { sourceColumnID.layer }
        var targetLayer: Layer { targetColumnID.layer }
        var connectionCount: Int { pathIDs.count }
    }

    /// Dynamic source/rule/policy-depth/final columns in traversal order.
    let columns: [Column]
    let edges: [Edge]
    /// One record for every input active connection, including unavailable routes.
    let paths: [PathRecord]

    static let empty = ConnectionTopology(columns: [], edges: [], paths: [])

    var nodes: [Node] { columns.flatMap(\.nodes) }

    /// Semantic grouping used by the current renderer. Dynamic depth lives in `columns`.
    var layers: [[Node]] {
        let nodes = nodes
        return Layer.allCases.map { layer in
            nodes.filter { $0.layer == layer }
        }
    }

    var connectionCount: Int { paths.count }
    var drawableConnectionCount: Int { paths.lazy.filter(\.isDrawable).count }
    var routeUnavailableCount: Int { connectionCount - drawableConnectionCount }
    /// The graph has no drawable route edges. Unavailable path records may still exist.
    var isEmpty: Bool { edges.isEmpty }
}

enum ConnectionTopologyBuilder {
    struct OperationCounts: Equatable, Sendable {
        let inputConnectionCount: Int
        let normalizedStageCount: Int
        let nodeTableLookupCount: Int
        let nodeMembershipWriteCount: Int
        let edgeTableLookupCount: Int
        let edgeMembershipWriteCount: Int
        let uniqueNodeCount: Int
        let uniqueEdgeCount: Int
    }

    static func build(from connections: [ConnectionSnapshot]) -> ConnectionTopology {
        buildWithOperationCounts(from: connections).topology
    }

    /// Deterministic operation counts for focused scaling contracts.
    static func buildWithOperationCounts(
        from connections: [ConnectionSnapshot]
    ) -> (topology: ConnectionTopology, operationCounts: OperationCounts) {
        var accumulator = Accumulator()
        var occurrenceCounts: [OccurrenceKey: Int] = [:]
        var paths: [ConnectionTopology.PathRecord] = []
        paths.reserveCapacity(connections.count)

        for (sourceIndex, connection) in connections.enumerated() {
            guard !Task.isCancelled else {
                return (.empty, accumulator.operationCounts)
            }
            let occurrenceID = nextOccurrenceID(
                for: connection,
                occurrenceCounts: &occurrenceCounts
            )
            paths.append(
                accumulator.consume(
                    connection,
                    sourceIndex: sourceIndex,
                    occurrenceID: occurrenceID
                )
            )
        }

        guard !Task.isCancelled else {
            return (.empty, accumulator.operationCounts)
        }
        return (accumulator.finish(paths: paths), accumulator.operationCounts)
    }

    /// Builds away from the caller's actor, yielding while scanning and throwing on cancellation.
    @concurrent
    static func buildCancellable(
        from connections: [ConnectionSnapshot]
    ) async throws -> ConnectionTopology {
        var accumulator = Accumulator()
        var occurrenceCounts: [OccurrenceKey: Int] = [:]
        var paths: [ConnectionTopology.PathRecord] = []
        paths.reserveCapacity(connections.count)

        for (sourceIndex, connection) in connections.enumerated() {
            if sourceIndex.isMultiple(of: 64) {
                try Task.checkCancellation()
                await Task.yield()
            }
            let occurrenceID = nextOccurrenceID(
                for: connection,
                occurrenceCounts: &occurrenceCounts
            )
            paths.append(
                accumulator.consume(
                    connection,
                    sourceIndex: sourceIndex,
                    occurrenceID: occurrenceID
                )
            )
        }

        try Task.checkCancellation()
        let topology = accumulator.finish(paths: paths)
        try Task.checkCancellation()
        return topology
    }

    private struct Accumulator {
        private var nodeOrderByColumn: [ConnectionTopology.Column.ID: [Int]] = [:]
        private var nodeIndexByID: [String: Int] = [:]
        private var nodes: [NodeAccumulator] = []
        private var edgeIndexByKey: [EdgeKey: Int] = [:]
        private var edges: [EdgeAccumulator] = []
        private var inputConnectionCount = 0
        private var normalizedStageCount = 0
        private var nodeTableLookupCount = 0
        private var nodeMembershipWriteCount = 0
        private var edgeTableLookupCount = 0
        private var edgeMembershipWriteCount = 0

        var operationCounts: OperationCounts {
            OperationCounts(
                inputConnectionCount: inputConnectionCount,
                normalizedStageCount: normalizedStageCount,
                nodeTableLookupCount: nodeTableLookupCount,
                nodeMembershipWriteCount: nodeMembershipWriteCount,
                edgeTableLookupCount: edgeTableLookupCount,
                edgeMembershipWriteCount: edgeMembershipWriteCount,
                uniqueNodeCount: nodes.count,
                uniqueEdgeCount: edges.count
            )
        }

        mutating func consume(
            _ connection: ConnectionSnapshot,
            sourceIndex: Int,
            occurrenceID: ConnectionTopology.ConnectionOccurrenceID
        ) -> ConnectionTopology.PathRecord {
            inputConnectionCount += 1
            let draft = ConnectionTopologyBuilder.pathDraft(for: connection)
            normalizedStageCount += draft.stages.count
            guard draft.routeState == .available else {
                return ConnectionTopology.PathRecord(
                    id: occurrenceID,
                    sourceIndex: sourceIndex,
                    reportedConnectionID: connection.id,
                    stages: draft.stages,
                    edgeIDs: [],
                    routeState: draft.routeState
                )
            }

            for stage in draft.stages {
                admit(stage, pathID: occurrenceID)
            }

            var edgeIDs: [String] = []
            edgeIDs.reserveCapacity(max(draft.stages.count - 1, 0))
            for (source, target) in zip(draft.stages, draft.stages.dropFirst()) {
                edgeIDs.append(admit(source: source, target: target, pathID: occurrenceID))
            }

            return ConnectionTopology.PathRecord(
                id: occurrenceID,
                sourceIndex: sourceIndex,
                reportedConnectionID: connection.id,
                stages: draft.stages,
                edgeIDs: edgeIDs,
                routeState: draft.routeState
            )
        }

        private mutating func admit(
            _ stage: ConnectionTopology.Stage,
            pathID: ConnectionTopology.ConnectionOccurrenceID
        ) {
            nodeTableLookupCount += 1
            nodeMembershipWriteCount += 1
            if let nodeIndex = nodeIndexByID[stage.nodeID] {
                nodes[nodeIndex].pathIDs.append(pathID)
                return
            }

            let nodeIndex = nodes.endIndex
            nodeIndexByID[stage.nodeID] = nodeIndex
            nodeOrderByColumn[stage.columnID, default: []].append(nodeIndex)
            nodes.append(NodeAccumulator(
                id: stage.nodeID,
                columnID: stage.columnID,
                name: stage.name,
                pathIDs: [pathID]
            ))
        }

        private mutating func admit(
            source: ConnectionTopology.Stage,
            target: ConnectionTopology.Stage,
            pathID: ConnectionTopology.ConnectionOccurrenceID
        ) -> String {
            let key = EdgeKey(sourceID: source.nodeID, targetID: target.nodeID)
            edgeTableLookupCount += 1
            edgeMembershipWriteCount += 1
            if let edgeIndex = edgeIndexByKey[key] {
                edges[edgeIndex].pathIDs.append(pathID)
                return edges[edgeIndex].id
            }

            let id = ConnectionTopologyBuilder.edgeID(
                sourceID: source.nodeID,
                targetID: target.nodeID
            )
            edgeIndexByKey[key] = edges.endIndex
            edges.append(EdgeAccumulator(
                id: id,
                sourceID: source.nodeID,
                targetID: target.nodeID,
                sourceName: source.name,
                targetName: target.name,
                sourceColumnID: source.columnID,
                targetColumnID: target.columnID,
                pathIDs: [pathID]
            ))
            return id
        }

        func finish(paths: [ConnectionTopology.PathRecord]) -> ConnectionTopology {
            let columnIDs = nodeOrderByColumn.keys.sorted { left, right in
                left.order < right.order
            }
            let columns = columnIDs.map { columnID in
                ConnectionTopology.Column(
                    id: columnID,
                    nodes: nodeOrderByColumn[columnID, default: []].map { nodeIndex in
                        let node = nodes[nodeIndex]
                        return ConnectionTopology.Node(
                            id: node.id,
                            columnID: node.columnID,
                            name: node.name,
                            pathIDs: node.pathIDs
                        )
                    }
                )
            }
            let completedEdges = edges.map { edge in
                return ConnectionTopology.Edge(
                    id: edge.id,
                    sourceID: edge.sourceID,
                    targetID: edge.targetID,
                    sourceName: edge.sourceName,
                    targetName: edge.targetName,
                    sourceColumnID: edge.sourceColumnID,
                    targetColumnID: edge.targetColumnID,
                    pathIDs: edge.pathIDs
                )
            }

            return ConnectionTopology(columns: columns, edges: completedEdges, paths: paths)
        }
    }

    private static func nextOccurrenceID(
        for connection: ConnectionSnapshot,
        occurrenceCounts: inout [OccurrenceKey: Int]
    ) -> ConnectionTopology.ConnectionOccurrenceID {
        let reportedID = trimmedNonEmpty(connection.id)
        let key = OccurrenceKey(reportedID: reportedID)
        let occurrence = occurrenceCounts[key, default: 0]
        occurrenceCounts[key] = occurrence + 1
        return ConnectionTopology.ConnectionOccurrenceID(
            reportedID: reportedID,
            occurrence: occurrence
        )
    }

    private static func pathDraft(for connection: ConnectionSnapshot) -> PathDraft {
        let source = firstNonEmpty(
            connection.metadata?.sourceIP,
            connection.metadata?.process,
            connection.metadata?.inboundName
        )
        let rule = ruleIdentity(for: connection)
        let reportedChains = connection.chains ?? []
        let finalOutbound = reportedChains.first.flatMap { trimmedNonEmpty($0) }
        let policyHops = reportedChains.dropFirst().reversed().compactMap {
            trimmedNonEmpty($0)
        }

        var stages: [ConnectionTopology.Stage] = []
        stages.reserveCapacity(2 + policyHops.count + (rule == nil ? 0 : 1))
        if let source {
            stages.append(stage(columnID: .source, name: source))
        }
        if let rule {
            stages.append(stage(columnID: .rule, name: rule))
        }
        for (depth, hop) in policyHops.enumerated() {
            stages.append(stage(columnID: .policyHop(depth), name: hop))
        }
        if let finalOutbound {
            stages.append(stage(columnID: .finalOutbound, name: finalOutbound))
        }

        let routeState: ConnectionTopology.PathRecord.RouteState = switch (
            source == nil,
            finalOutbound == nil
        ) {
        case (false, false):
            .available
        case (true, false):
            .routeUnavailable(.missingSource)
        case (false, true):
            .routeUnavailable(.missingChain)
        case (true, true):
            .routeUnavailable(.missingSourceAndChain)
        }

        return PathDraft(stages: stages, routeState: routeState)
    }

    private static func stage(
        columnID: ConnectionTopology.Column.ID,
        name: String
    ) -> ConnectionTopology.Stage {
        ConnectionTopology.Stage(
            nodeID: nodeID(columnID: columnID, name: name),
            columnID: columnID,
            name: name
        )
    }

    private static func ruleIdentity(for connection: ConnectionSnapshot) -> String? {
        let type = firstNonEmpty(connection.rule)
        let payload = firstNonEmpty(connection.rulePayload)
        guard let type else { return payload }
        guard let payload, !type.localizedCaseInsensitiveContains(payload) else { return type }
        return "\(type): \(payload)"
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.lazy.compactMap(trimmedNonEmpty).first
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nodeID(
        columnID: ConnectionTopology.Column.ID,
        name: String
    ) -> String {
        "\(columnID.stableKey)\u{001F}\(name.utf8.count):\(name)"
    }

    private static func edgeID(sourceID: String, targetID: String) -> String {
        "\(sourceID.utf8.count):\(sourceID)\u{001F}\(targetID.utf8.count):\(targetID)"
    }

    private struct PathDraft {
        let stages: [ConnectionTopology.Stage]
        let routeState: ConnectionTopology.PathRecord.RouteState
    }

    private struct OccurrenceKey: Hashable {
        let reportedID: String?
    }

    private struct NodeAccumulator {
        let id: String
        let columnID: ConnectionTopology.Column.ID
        let name: String
        var pathIDs: [ConnectionTopology.ConnectionOccurrenceID]
    }

    private struct EdgeKey: Hashable {
        let sourceID: String
        let targetID: String
    }

    private struct EdgeAccumulator {
        let id: String
        let sourceID: String
        let targetID: String
        let sourceName: String
        let targetName: String
        let sourceColumnID: ConnectionTopology.Column.ID
        let targetColumnID: ConnectionTopology.Column.ID
        var pathIDs: [ConnectionTopology.ConnectionOccurrenceID]
    }
}
