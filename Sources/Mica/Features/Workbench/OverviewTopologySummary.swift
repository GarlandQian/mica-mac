import Foundation
import MicaCore

/// A bounded diagram of connection membership. Its edges summarize reported
/// paths; the original topology remains the only source for complete routes.
struct OverviewTopologySummary: Sendable {
    enum Value: Hashable, Sendable {
        case reported(String)
        case unreported
        case other
    }

    struct Item: Sendable {
        let value: Value
        let representedNameCount: Int
        let pathIDs: [ConnectionTopology.ConnectionOccurrenceID]

        var isAggregate: Bool {
            if case .other = value { return true }
            return false
        }
    }

    struct Labels: Sendable {
        let unknownSource: String
        let unknownEntry: String
        let unknownOutbound: String
        let other: String
    }

    let diagram: ConnectionTopology
    let itemsByID: [String: Item]
    let mergedNameCount: Int
    let mergedConnectionCount: Int

    /// Six cards per column leave room for names, counts, and route gaps in a
    /// normal window. Unknown data always has its own bucket, never “Other”.
    static let maximumItemsPerColumn = 6

    @concurrent
    static func build(
        topology: ConnectionTopology,
        labels: Labels,
        maximumItems: Int = maximumItemsPerColumn
    ) async throws -> Self {
        let columns: [ConnectionTopology.Column.ID] = [.source, .policyHop(0), .finalOutbound]
        let limit = max(3, min(maximumItems, maximumItemsPerColumn))
        var counts = Array(repeating: [Value: Int](), count: columns.count)
        var valuesByPath: [[Value]] = []
        valuesByPath.reserveCapacity(topology.paths.count)

        for (index, path) in topology.paths.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation(); await Task.yield() }
            let values = [path.source, path.policyHops.first, path.finalOutbound].map {
                $0.map(Value.reported) ?? .unreported
            }
            valuesByPath.append(values)
            for column in columns.indices { counts[column][values[column], default: 0] += 1 }
        }

        var admitted: [Set<Value>] = []
        var omittedCounts: [Int] = []
        for columnCounts in counts {
            let reported = columnCounts.keys.compactMap { value -> (Value, String)? in
                if case .reported(let name) = value { return (value, name) }
                return nil
            }.sorted { lhs, rhs in
                let left = columnCounts[lhs.0, default: 0]
                let right = columnCounts[rhs.0, default: 0]
                return left == right ? lhs.1 < rhs.1 : left > right
            }
            let unknownSlot = columnCounts[.unreported] == nil ? 0 : 1
            let capacity = limit - unknownSlot
            let retainedCount = reported.count <= capacity ? reported.count : max(capacity - 1, 0)
            var retained = Set(reported.prefix(retainedCount).map(\.0))
            if unknownSlot > 0 { retained.insert(.unreported) }
            admitted.append(retained)
            omittedCounts.append(reported.count - retainedCount)
        }

        var membership: [String: [ConnectionTopology.ConnectionOccurrenceID]] = [:]
        var itemValue: [String: Value] = [:]
        var edgesByID: [String: (source: String, target: String, paths: [ConnectionTopology.ConnectionOccurrenceID])] = [:]
        var edgeOrder: [String] = []
        var nodeOrder = Array(repeating: [String](), count: columns.count)
        var diagramPaths: [ConnectionTopology.PathRecord] = []
        var mergedPathIDs = Set<ConnectionTopology.ConnectionOccurrenceID>()

        func nodeID(column: Int, value: Value) -> String {
            let identity: String
            switch value {
            case .reported(let name): identity = "reported:\(name.utf8.count):\(name)"
            case .unreported: identity = "unreported"
            case .other: identity = "other"
            }
            return "summary:\(column):\(identity)"
        }

        func title(column: Int, value: Value) -> String {
            switch value {
            case .reported(let name): return name
            case .unreported:
                return [labels.unknownSource, labels.unknownEntry, labels.unknownOutbound][column]
            case .other: return "\(labels.other) · \(omittedCounts[column])"
            }
        }

        for (pathIndex, path) in topology.paths.enumerated() {
            if pathIndex.isMultiple(of: 64) { try Task.checkCancellation(); await Task.yield() }
            var stages: [ConnectionTopology.Stage] = []
            for column in columns.indices {
                let rawValue = valuesByPath[pathIndex][column]
                let value: Value = admitted[column].contains(rawValue) ? rawValue : .other
                let id = nodeID(column: column, value: value)
                if membership[id] == nil { nodeOrder[column].append(id) }
                membership[id, default: []].append(path.id)
                itemValue[id] = value
                if value == .other { mergedPathIDs.insert(path.id) }
                stages.append(.init(nodeID: id, columnID: columns[column], name: title(column: column, value: value)))
            }
            var edgeIDs: [String] = []
            for (source, target) in zip(stages, stages.dropFirst()) {
                let edgeID = "\(source.nodeID.utf8.count):\(source.nodeID)\(target.nodeID.utf8.count):\(target.nodeID)"
                if edgesByID[edgeID] == nil {
                    edgeOrder.append(edgeID)
                    edgesByID[edgeID] = (source.nodeID, target.nodeID, [])
                }
                edgesByID[edgeID]?.paths.append(path.id)
                edgeIDs.append(edgeID)
            }
            // These stages are diagram buckets, not invented protocol hops.
            // Preserve the route-unavailable state and look up the original
            // record before presenting or navigating a complete connection.
            diagramPaths.append(.init(
                id: path.id, sourceIndex: path.sourceIndex,
                reportedConnectionID: path.reportedConnectionID,
                stages: stages, edgeIDs: edgeIDs, routeState: path.routeState
            ))
        }

        var items: [String: Item] = [:]
        var nodes: [String: ConnectionTopology.Node] = [:]
        let projectedColumns = columns.indices.map { column in
            let orderedIDs = nodeOrder[column].sorted { left, right in
                let leftSpecial = itemValue[left] == .other || itemValue[left] == .unreported
                let rightSpecial = itemValue[right] == .other || itemValue[right] == .unreported
                if leftSpecial != rightSpecial { return !leftSpecial }
                let leftCount = membership[left]?.count ?? 0
                let rightCount = membership[right]?.count ?? 0
                return leftCount == rightCount ? left < right : leftCount > rightCount
            }
            let columnNodes = orderedIDs.map { id in
                let value = itemValue[id] ?? .unreported
                let pathIDs = membership[id] ?? []
                let node = ConnectionTopology.Node(id: id, columnID: columns[column], name: title(column: column, value: value), pathIDs: pathIDs)
                nodes[id] = node
                items[id] = Item(value: value, representedNameCount: value == .other ? omittedCounts[column] : 1, pathIDs: pathIDs)
                return node
            }
            return ConnectionTopology.Column(id: columns[column], nodes: columnNodes)
        }
        let projectedEdges = edgeOrder.compactMap { id -> ConnectionTopology.Edge? in
            guard let edge = edgesByID[id], let source = nodes[edge.source], let target = nodes[edge.target] else { return nil }
            return .init(id: id, sourceID: source.id, targetID: target.id, sourceName: source.name, targetName: target.name, sourceColumnID: source.columnID, targetColumnID: target.columnID, pathIDs: edge.paths)
        }
        try Task.checkCancellation()
        return Self(
            diagram: ConnectionTopology(columns: projectedColumns, edges: projectedEdges, paths: diagramPaths),
            itemsByID: items,
            mergedNameCount: omittedCounts.reduce(0, +),
            mergedConnectionCount: mergedPathIDs.count
        )
    }
}
