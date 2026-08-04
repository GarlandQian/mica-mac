import Foundation
import MicaCore

struct InsightSummarySnapshot: Equatable {
    var connectionDistribution: [InsightSlice]
    var trafficSplit: [InsightSlice]
    var routeHealth: [LatencyHealthBucket]
    var topConnections: [ConnectionSnapshot]
    var connectionCount: Int
    var ruleCount: Int
    var providerCount: Int
    var latencySampleCount: Int

    static let empty = InsightSummarySnapshot()

    init(
        connectionDistribution: [InsightSlice] = [],
        trafficSplit: [InsightSlice] = [],
        routeHealth: [LatencyHealthBucket] = LatencyHealthGrade.allCases.map { LatencyHealthBucket(grade: $0, count: 0) },
        topConnections: [ConnectionSnapshot] = [],
        connectionCount: Int = 0,
        ruleCount: Int = 0,
        providerCount: Int = 0,
        latencySampleCount: Int = 0
    ) {
        self.connectionDistribution = connectionDistribution
        self.trafficSplit = trafficSplit
        self.routeHealth = routeHealth
        self.topConnections = topConnections
        self.connectionCount = connectionCount
        self.ruleCount = ruleCount
        self.providerCount = providerCount
        self.latencySampleCount = latencySampleCount
    }

    init(snapshot: DashboardSnapshot) {
        self.init()
        updateConnections(snapshot.connections, structureChanged: true, metricsChanged: true)
        updateTraffic(snapshot.traffic)
        updateRouteHealth(snapshot.groups)
        ruleCount = snapshot.rules.count
        providerCount = snapshot.providers.count
    }

    mutating func updateConnections(
        _ connections: [ConnectionSnapshot],
        structureChanged: Bool,
        metricsChanged: Bool
    ) {
        if structureChanged {
            connectionCount = connections.count
            var ruleCounts: [String: Int] = [:]
            ruleCounts.reserveCapacity(min(connections.count, 64))
            for connection in connections {
                ruleCounts[Self.ruleType(for: connection), default: 0] += 1
            }
            connectionDistribution = Self.makeSlices(counts: ruleCounts)
        }

        if structureChanged || metricsChanged {
            topConnections = Self.topConnections(from: connections, limit: 5)
        }
    }

    mutating func updateTraffic(_ traffic: TrafficSnapshot) {
        let upload = max(traffic.upload, 0)
        let download = max(traffic.download, 0)
        trafficSplit = [
            InsightSlice(label: "upload", value: upload),
            InsightSlice(label: "download", value: download),
        ].filter { $0.value > 0 }
    }

    mutating func updateRouteHealth(_ groups: [ProxyGroupViewState]) {
        var counts = Dictionary(
            uniqueKeysWithValues: LatencyHealthGrade.allCases.map { ($0, 0) }
        )
        var sampleCount = 0
        for group in groups {
            for delay in group.delays.values {
                sampleCount += 1
                if let grade = LatencyHealthGrade.allCases.first(where: {
                    $0.includes(delay: delay)
                }) {
                    counts[grade, default: 0] += 1
                }
            }
        }
        latencySampleCount = sampleCount
        routeHealth = LatencyHealthGrade.allCases.map { grade in
            LatencyHealthBucket(grade: grade, count: counts[grade, default: 0])
        }
    }

    mutating func updateRuleCount(_ count: Int) {
        ruleCount = count
    }

    mutating func updateProviderCount(_ count: Int) {
        providerCount = count
    }

    var hasConnectionDistribution: Bool {
        !connectionDistribution.isEmpty
    }

    var hasTrafficSplit: Bool {
        !trafficSplit.isEmpty
    }

    var hasLatencySamples: Bool {
        latencySampleCount > 0
    }

    var diagnosticsStats: String {
        let activeBuckets = routeHealth
            .filter { $0.count > 0 }
            .map { "\($0.grade.diagnosticsLabel)=\($0.count)" }
            .joined(separator: ",")

        return [
            "connections=\(connectionCount)",
            "rule-types=\(connectionDistribution.count)",
            "rules=\(ruleCount)",
            "providers=\(providerCount)",
            "latency-samples=\(latencySampleCount)",
            "latency-buckets=\(activeBuckets.isEmpty ? "none" : activeBuckets)",
            "top-flows=\(topConnections.count)",
        ].joined(separator: "; ")
    }

    func diagnosticsStatsSummary(language: AppLanguage = MicaStrings.appLanguage) -> String {
        MicaStrings.localized("diagnostics.insight_summary_counts \(connectionCount) \(ruleCount) \(providerCount) \(latencySampleCount)", language: language)
    }

    static func ruleType(for connection: ConnectionSnapshot) -> String {
        let value = connection.rule?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "UNKNOWN" : value.uppercased()
    }

    static func totalTraffic(_ connection: ConnectionSnapshot) -> Int {
        max(connection.upload ?? 0, 0) + max(connection.download ?? 0, 0)
    }

    private static func makeSlices(counts: [String: Int]) -> [InsightSlice] {
        counts
            .map { InsightSlice(label: $0.key, value: $0.value) }
            .sorted {
                if $0.value == $1.value {
                    return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
                }

                return $0.value > $1.value
            }
    }

    private static func topConnections(
        from connections: [ConnectionSnapshot],
        limit: Int
    ) -> [ConnectionSnapshot] {
        guard limit > 0 else { return [] }
        var top: [ConnectionSnapshot] = []
        top.reserveCapacity(min(limit, connections.count))

        for connection in connections {
            let traffic = totalTraffic(connection)
            let insertionIndex = top.firstIndex {
                let candidateTraffic = totalTraffic($0)
                if traffic == candidateTraffic {
                    return connection.id.localizedCaseInsensitiveCompare($0.id) == .orderedAscending
                }
                return traffic > candidateTraffic
            } ?? top.endIndex
            guard insertionIndex < limit else { continue }
            top.insert(connection, at: insertionIndex)
            if top.count > limit {
                top.removeLast()
            }
        }
        return top
    }
}

struct InsightSlice: Identifiable, Equatable {
    var id: String { label }
    var label: String
    var value: Int
}

struct LatencyHealthBucket: Identifiable, Equatable {
    var id: String { grade.rawValue }
    var grade: LatencyHealthGrade
    var count: Int
}

enum LatencyHealthGrade: String, CaseIterable, Equatable, Hashable {
    case fast
    case normal
    case slow
    case timeout

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .fast:
            MicaStrings.localized("latency.fast", language: language)
        case .normal:
            MicaStrings.localized("latency.normal", language: language)
        case .slow:
            MicaStrings.localized("latency.slow", language: language)
        case .timeout:
            MicaStrings.localized("latency.timeout", language: language)
        }
    }

    var diagnosticsLabel: String {
        rawValue
    }

    func includes(delay: Int) -> Bool {
        switch self {
        case .fast:
            delay >= 0 && delay < 80
        case .normal:
            delay >= 80 && delay < 180
        case .slow:
            delay >= 180 && delay < 1000
        case .timeout:
            delay >= 1000
        }
    }
}
