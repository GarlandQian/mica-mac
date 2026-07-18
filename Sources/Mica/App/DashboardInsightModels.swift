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
        connectionCount = snapshot.connections.count
        ruleCount = snapshot.rules.count
        providerCount = snapshot.providers.count

        connectionDistribution = Self.makeSlices(
            counts: Dictionary(grouping: snapshot.connections) { connection in
                Self.ruleType(for: connection)
            }
            .mapValues { $0.count }
        )

        let upload = max(snapshot.traffic.upload, 0)
        let download = max(snapshot.traffic.download, 0)
        trafficSplit = [
            InsightSlice(label: "upload", value: upload),
            InsightSlice(label: "download", value: download),
        ].filter { $0.value > 0 }

        let latencyValues = snapshot.groups.flatMap { $0.delays.values }
        latencySampleCount = latencyValues.count
        routeHealth = LatencyHealthGrade.allCases.map { grade in
            LatencyHealthBucket(
                grade: grade,
                count: latencyValues.filter { grade.includes(delay: $0) }.count
            )
        }

        topConnections = snapshot.connections
            .sorted { lhs, rhs in
                Self.totalTraffic(lhs) > Self.totalTraffic(rhs)
            }
            .prefix(5)
            .map { $0 }
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

enum LatencyHealthGrade: String, CaseIterable, Equatable {
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
