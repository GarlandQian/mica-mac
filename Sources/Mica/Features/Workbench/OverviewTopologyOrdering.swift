import Foundation

/// Refines the structure-time route order without hiding any connection.
/// Sources remain stable; a small number of sweeps considers both ends of the
/// remaining columns. The best candidate starts with the previous forward-only
/// order, so refinement cannot increase crossings between the same column pair.
enum OverviewTopologyOrdering {
    private static let maximumRefinementRounds = 4

    @concurrent
    static func prepare(in topology: ConnectionTopology) async throws -> [[ConnectionTopology.Node]] {
        try orderedColumns(in: topology)
    }

    static func orderedColumns(
        in topology: ConnectionTopology
    ) throws -> [[ConnectionTopology.Node]] {
        try Task.checkCancellation()
        var workCount = 0
        var candidate: [[ConnectionTopology.Node]] = []
        for column in topology.columns {
            try checkpoint(&workCount)
            candidate.append(try column.nodes.sorted { left, right in
                try checkpoint(&workCount)
                return nameOrder(left, right)
            })
        }
        try Task.checkCancellation()
        guard topology.columns.count > 1 else { return candidate }

        let context = try Context(topology: topology)
        try sweep(&candidate, direction: .forward, context: context)
        var best = candidate
        var bestCrossings = try context.crossings(in: best)
        guard bestCrossings > 0 else { return best }

        for _ in 0..<maximumRefinementRounds {
            try Task.checkCancellation()
            let previous = candidate
            for direction in [Direction.backward, .forward] {
                try sweep(&candidate, direction: direction, context: context)
                let crossings = try context.crossings(in: candidate)
                if crossings < bestCrossings {
                    best = candidate
                    bestCrossings = crossings
                    if crossings == 0 { return best }
                }
            }
            if candidate == previous { break }
        }
        try Task.checkCancellation()
        return best
    }

    private enum Direction {
        case forward
        case backward
    }

    private struct Neighbor {
        let id: String
        let weight: Double
    }

    private struct ColumnPair: Hashable {
        let source: Int
        let target: Int
    }

    private struct Context {
        let incoming: [String: [Neighbor]]
        let outgoing: [String: [Neighbor]]
        let edgesByColumns: [ColumnPair: [ConnectionTopology.Edge]]

        init(topology: ConnectionTopology) throws {
            try Task.checkCancellation()
            var workCount = 0
            var columnIndexes: [ConnectionTopology.Column.ID: Int] = [:]
            for (index, column) in topology.columns.enumerated() {
                try checkpoint(&workCount)
                columnIndexes[column.id] = index
            }
            var incoming: [String: [Neighbor]] = [:]
            var outgoing: [String: [Neighbor]] = [:]
            var edgesByColumns: [ColumnPair: [ConnectionTopology.Edge]] = [:]
            for edge in topology.edges {
                try checkpoint(&workCount)
                let weight = max(log10(Double(edge.connectionCount) + 1) * 10, 1)
                incoming[edge.targetID, default: []].append(
                    Neighbor(id: edge.sourceID, weight: weight)
                )
                outgoing[edge.sourceID, default: []].append(
                    Neighbor(id: edge.targetID, weight: weight)
                )
                guard let source = columnIndexes[edge.sourceColumnID],
                      let target = columnIndexes[edge.targetColumnID] else { continue }
                edgesByColumns[ColumnPair(source: source, target: target), default: []]
                    .append(edge)
            }
            self.incoming = incoming
            self.outgoing = outgoing
            self.edgesByColumns = edgesByColumns
            try Task.checkCancellation()
        }

        /// Count inversions in O(E log N), without pairwise edge comparisons.
        /// Shared source/target ports are not crossings. Routes that skip a
        /// column are compared with other routes spanning that same pair.
        func crossings(in columns: [[ConnectionTopology.Node]]) throws -> Int {
            try Task.checkCancellation()
            let ranks = try slotIndexes(in: columns)
            var workCount = 0
            var crossings = 0
            for (pair, edges) in edgesByColumns {
                try checkpoint(&workCount)
                var orderedEndpoints: [(source: Int, target: Int)] = []
                orderedEndpoints.reserveCapacity(edges.count)
                for edge in edges {
                    try checkpoint(&workCount)
                    guard let source = ranks[edge.sourceID],
                          let target = ranks[edge.targetID] else { continue }
                    orderedEndpoints.append((source, target))
                }
                try orderedEndpoints.sort {
                    try checkpoint(&workCount)
                    return $0.source == $1.source
                        ? $0.target < $1.target : $0.source < $1.source
                }
                var tree = FenwickTree(size: columns[pair.target].count)
                var consumed = 0
                var lowerBound = 0
                while lowerBound < orderedEndpoints.count {
                    try checkpoint(&workCount)
                    var upperBound = lowerBound + 1
                    while upperBound < orderedEndpoints.count,
                          orderedEndpoints[upperBound].source
                            == orderedEndpoints[lowerBound].source {
                        try checkpoint(&workCount)
                        upperBound += 1
                    }
                    // Query all edges sharing a source before admitting them.
                    for index in lowerBound..<upperBound {
                        try checkpoint(&workCount)
                        crossings += consumed - tree.count(through: orderedEndpoints[index].target)
                    }
                    for index in lowerBound..<upperBound {
                        try checkpoint(&workCount)
                        tree.insert(at: orderedEndpoints[index].target)
                        consumed += 1
                    }
                    lowerBound = upperBound
                }
            }
            try Task.checkCancellation()
            return crossings
        }
    }

    private static func sweep(
        _ columns: inout [[ConnectionTopology.Node]],
        direction: Direction,
        context: Context
    ) throws {
        try Task.checkCancellation()
        var workCount = 0
        var slots = try slotIndexes(in: columns)
        let indexes: [Int]
        let neighbors: [String: [Neighbor]]
        switch direction {
        case .forward:
            indexes = Array(1..<columns.count)
            neighbors = context.incoming
        case .backward:
            indexes = Array((1..<columns.count - 1).reversed())
            neighbors = context.outgoing
        }
        for index in indexes {
            try checkpoint(&workCount)
            var barycenters: [String: Double] = [:]
            for node in columns[index] {
                try checkpoint(&workCount)
                var weightedSlots = 0.0
                var totalWeight = 0.0
                for neighbor in neighbors[node.id, default: []] {
                    try checkpoint(&workCount)
                    guard let slot = slots[neighbor.id] else { continue }
                    weightedSlots += Double(slot) * neighbor.weight
                    totalWeight += neighbor.weight
                }
                barycenters[node.id] = totalWeight > 0
                    ? weightedSlots / totalWeight : .greatestFiniteMagnitude
            }
            try columns[index].sort { left, right in
                try checkpoint(&workCount)
                let leftKey = barycenters[left.id, default: .greatestFiniteMagnitude]
                let rightKey = barycenters[right.id, default: .greatestFiniteMagnitude]
                return leftKey == rightKey
                    ? nameOrder(left, right)
                    : leftKey < rightKey
            }
            for (slot, node) in columns[index].enumerated() {
                try checkpoint(&workCount)
                slots[node.id] = slot
            }
        }
        try Task.checkCancellation()
    }

    private static func slotIndexes(
        in columns: [[ConnectionTopology.Node]]
    ) throws -> [String: Int] {
        try Task.checkCancellation()
        var workCount = 0
        var slots: [String: Int] = [:]
        for column in columns {
            for (slot, node) in column.enumerated() {
                try checkpoint(&workCount)
                slots[node.id] = slot
            }
        }
        try Task.checkCancellation()
        return slots
    }

    /// Cancellation is checked during all linear work and comparator batches,
    /// not just between sweeps, so a replaced session can stop a large graph.
    private static func checkpoint(_ workCount: inout Int) throws {
        workCount += 1
        if workCount.isMultiple(of: 256) { try Task.checkCancellation() }
    }

    private static func nameOrder(
        _ left: ConnectionTopology.Node,
        _ right: ConnectionTopology.Node
    ) -> Bool {
        let comparison = left.name.localizedCaseInsensitiveCompare(right.name)
        return comparison == .orderedSame
            ? left.id < right.id
            : comparison == .orderedAscending
    }

    private struct FenwickTree {
        private var values: [Int]

        init(size: Int) {
            values = Array(repeating: 0, count: size + 1)
        }

        mutating func insert(at position: Int) {
            var index = position + 1
            while index < values.count {
                values[index] += 1
                index += index & -index
            }
        }

        func count(through position: Int) -> Int {
            var result = 0
            var index = position + 1
            while index > 0 {
                result += values[index]
                index -= index & -index
            }
            return result
        }
    }
}
