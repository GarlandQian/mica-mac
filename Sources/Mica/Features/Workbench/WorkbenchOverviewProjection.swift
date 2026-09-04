import Foundation
import MicaCore
import Observation

enum OverviewTimelineWindow: String, CaseIterable, Codable, Identifiable, Sendable {
    case oneMinute
    case threeMinutes
    case fiveMinutes

    var id: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .oneMinute:
            60
        case .threeMinutes:
            3 * 60
        case .fiveMinutes:
            5 * 60
        }
    }

    var titleKey: String {
        switch self {
        case .oneMinute:
            "overview.timeline_one_minute"
        case .threeMinutes:
            "overview.timeline_three_minutes"
        case .fiveMinutes:
            "overview.timeline_five_minutes"
        }
    }
}

struct OverviewTimelineProjectionSnapshot: Equatable {
    let trafficSamples: [TrafficTimeline.Sample]
    let memorySamples: [MemoryTimeline.Sample]
    let connectionSamples: [ConnectionCountTimeline.Sample]
    let dates: [Date]

    static let empty = OverviewTimelineProjectionSnapshot(
        trafficSamples: [],
        memorySamples: [],
        connectionSamples: [],
        dates: []
    )
}

struct OverviewTimelineChartScale: Equatable, Sendable {
    let domain: ClosedRange<Int>
    let axisValues: [Int]

    static func traffic(
        _ samples: [TrafficTimeline.Sample]
    ) -> OverviewTimelineChartScale {
        let maximum = samples.reduce(0) { partial, sample in
            max(partial, max(sample.upload, sample.download))
        }
        return resolve(
            maximumObservedValue: maximum,
            minimumPositiveMaximum: 60_000
        )
    }

    static func memory(
        _ samples: [MemoryTimeline.Sample]
    ) -> OverviewTimelineChartScale {
        let maximum = samples.reduce(0) {
            max($0, $1.inUseBytes)
        }
        return resolve(
            maximumObservedValue: maximum,
            minimumPositiveMaximum: 100 * 1_024 * 1_024
        )
    }

    static func connections(
        _ samples: [ConnectionCountTimeline.Sample]
    ) -> OverviewTimelineChartScale {
        let maximum = samples.reduce(0) {
            max($0, $1.activeCount)
        }
        return resolve(
            maximumObservedValue: maximum,
            minimumPositiveMaximum: 100
        )
    }

    private static func resolve(
        maximumObservedValue: Int,
        minimumPositiveMaximum: Int
    ) -> OverviewTimelineChartScale {
        let observedMaximum = max(maximumObservedValue, 0)
        guard observedMaximum > 0 else {
            return OverviewTimelineChartScale(
                domain: -1...1,
                axisValues: [0]
            )
        }

        let scaledMaximum = max(observedMaximum, minimumPositiveMaximum)
        let headroom = max(scaledMaximum / 8, 1)
        let upperBound: Int
        if scaledMaximum > Int.max - headroom {
            upperBound = Int.max
        } else {
            upperBound = scaledMaximum + headroom
        }
        let lowerBound = -max(upperBound / 20, 1)
        let midpoint = upperBound / 2
        let axisValues = midpoint > 0 && midpoint < upperBound
            ? [0, midpoint, upperBound]
            : [0, upperBound]

        return OverviewTimelineChartScale(
            domain: lowerBound...upperBound,
            axisValues: axisValues
        )
    }
}

struct OverviewTimelineInteractionSnapshot: Equatable, Sendable {
    let hoveredDate: Date?
    let pinnedDate: Date?

    static let empty = OverviewTimelineInteractionSnapshot(
        hoveredDate: nil,
        pinnedDate: nil
    )

    var selectedDate: Date? {
        hoveredDate ?? pinnedDate
    }

    var isPinned: Bool {
        pinnedDate != nil
    }
}

@MainActor
@Observable
final class OverviewTimelineInteractionState {
    private(set) var snapshot = OverviewTimelineInteractionSnapshot.empty

    func setHoveredDate(_ date: Date?) {
        guard snapshot.hoveredDate != date else { return }
        snapshot = OverviewTimelineInteractionSnapshot(
            hoveredDate: date,
            pinnedDate: snapshot.pinnedDate
        )
    }

    func setPinnedDate(_ date: Date?) {
        guard snapshot.pinnedDate != date else { return }
        snapshot = OverviewTimelineInteractionSnapshot(
            hoveredDate: snapshot.hoveredDate,
            pinnedDate: date
        )
    }

    func togglePinnedDate(_ date: Date) {
        setPinnedDate(snapshot.pinnedDate == date ? nil : date)
    }

    func clearPinnedDate() {
        setPinnedDate(nil)
    }

    func reset() {
        guard snapshot != .empty else { return }
        snapshot = .empty
    }

    func retainPinnedDate(in dates: [Date]) {
        guard let pinnedDate = snapshot.pinnedDate,
              !dates.contains(pinnedDate) else {
            return
        }
        clearPinnedDate()
    }

    func canMoveSelection(by offset: Int, in dates: [Date]) -> Bool {
        guard let index = selectionIndex(in: dates) else { return false }
        return dates.indices.contains(index + offset)
    }

    func moveSelection(by offset: Int, in dates: [Date]) {
        guard let index = selectionIndex(in: dates), !dates.isEmpty else { return }
        let nextIndex = min(
            max(index + offset, dates.startIndex),
            dates.index(before: dates.endIndex)
        )
        snapshot = OverviewTimelineInteractionSnapshot(
            hoveredDate: nil,
            pinnedDate: dates[nextIndex]
        )
    }

    private func selectionIndex(in dates: [Date]) -> Int? {
        guard let selectedDate = snapshot.selectedDate ?? dates.last else { return nil }
        return OverviewTimelineProjection.nearestDateIndex(to: selectedDate, in: dates)
    }
}

struct OverviewTimelineProjectionStatistics: Equatable {
    var trafficProjectionCount = 0
    var memoryProjectionCount = 0
    var connectionProjectionCount = 0
    var mergedDateProjectionCount = 0
}

/// View-owned memoization keyed only by monotonic timeline identity and window.
/// The cache is destroyed with the Overview subtree, so hidden destinations retain
/// no chart preparation work or long-lived presentation state.
final class OverviewTimelineProjectionCache {
    private struct SourceSignature: Equatable {
        let count: Int
        let firstID: Int?
        let lastID: Int?
        let firstReceivedAt: Date?
        let lastReceivedAt: Date?
    }

    private struct TrafficKey: Equatable {
        let generation: UUID
        let window: OverviewTimelineWindow
        let signature: SourceSignature
    }

    private struct MemoryKey: Equatable {
        let generation: UUID
        let window: OverviewTimelineWindow
        let signature: SourceSignature
    }

    private struct ConnectionKey: Equatable {
        let generation: UUID
        let window: OverviewTimelineWindow
        let signature: SourceSignature
    }

    private var trafficKey: TrafficKey?
    private var memoryKey: MemoryKey?
    private var connectionKey: ConnectionKey?
    private var mergedTrafficKey: TrafficKey?
    private var mergedMemoryKey: MemoryKey?
    private var mergedConnectionKey: ConnectionKey?
    private var trafficSamples: [TrafficTimeline.Sample] = []
    private var memorySamples: [MemoryTimeline.Sample] = []
    private var connectionSamples: [ConnectionCountTimeline.Sample] = []
    private var dates: [Date] = []
    private var latestSnapshot = OverviewTimelineProjectionSnapshot.empty

    private(set) var statistics = OverviewTimelineProjectionStatistics()

    func resolve(
        generation: UUID,
        window: OverviewTimelineWindow,
        traffic sourceTraffic: [TrafficTimeline.Sample],
        memory sourceMemory: [MemoryTimeline.Sample],
        connections sourceConnections: [ConnectionCountTimeline.Sample],
        isPaused: Bool = false
    ) -> OverviewTimelineProjectionSnapshot {
        if isPaused, latestSnapshot != .empty {
            return latestSnapshot
        }

        let nextTrafficKey = TrafficKey(
            generation: generation,
            window: window,
            signature: SourceSignature(
                count: sourceTraffic.count,
                firstID: sourceTraffic.first?.id,
                lastID: sourceTraffic.last?.id,
                firstReceivedAt: sourceTraffic.first?.receivedAt,
                lastReceivedAt: sourceTraffic.last?.receivedAt
            )
        )
        let nextMemoryKey = MemoryKey(
            generation: generation,
            window: window,
            signature: SourceSignature(
                count: sourceMemory.count,
                firstID: sourceMemory.first?.id,
                lastID: sourceMemory.last?.id,
                firstReceivedAt: sourceMemory.first?.receivedAt,
                lastReceivedAt: sourceMemory.last?.receivedAt
            )
        )
        let nextConnectionKey = ConnectionKey(
            generation: generation,
            window: window,
            signature: SourceSignature(
                count: sourceConnections.count,
                firstID: sourceConnections.first?.id,
                lastID: sourceConnections.last?.id,
                firstReceivedAt: sourceConnections.first?.receivedAt,
                lastReceivedAt: sourceConnections.last?.receivedAt
            )
        )

        if trafficKey != nextTrafficKey {
            trafficSamples = OverviewTimelineProjection.downsample(
                OverviewTimelineProjection.trafficSamples(sourceTraffic, window: window),
                maximumCount: 120
            )
            trafficKey = nextTrafficKey
            statistics.trafficProjectionCount += 1
        }

        if memoryKey != nextMemoryKey {
            memorySamples = OverviewTimelineProjection.downsample(
                OverviewTimelineProjection.memorySamples(sourceMemory, window: window),
                maximumCount: 120
            )
            memoryKey = nextMemoryKey
            statistics.memoryProjectionCount += 1
        }

        if connectionKey != nextConnectionKey {
            connectionSamples = OverviewTimelineProjection.downsample(
                OverviewTimelineProjection.connectionSamples(
                    sourceConnections,
                    window: window
                ),
                maximumCount: 120
            )
            connectionKey = nextConnectionKey
            statistics.connectionProjectionCount += 1
        }

        if mergedTrafficKey != nextTrafficKey
            || mergedMemoryKey != nextMemoryKey
            || mergedConnectionKey != nextConnectionKey {
            dates = OverviewTimelineProjection.mergedDates(
                traffic: trafficSamples,
                memory: memorySamples,
                connections: connectionSamples
            )
            mergedTrafficKey = nextTrafficKey
            mergedMemoryKey = nextMemoryKey
            mergedConnectionKey = nextConnectionKey
            statistics.mergedDateProjectionCount += 1
        }

        let snapshot = OverviewTimelineProjectionSnapshot(
            trafficSamples: trafficSamples,
            memorySamples: memorySamples,
            connectionSamples: connectionSamples,
            dates: dates
        )
        latestSnapshot = snapshot
        return snapshot
    }
}

enum OverviewTimelineProjection {
    static func dateDomain(
        endingAt latestDate: Date,
        window: OverviewTimelineWindow
    ) -> ClosedRange<Date> {
        latestDate.addingTimeInterval(-window.duration)...latestDate
    }

    static func trafficSamples(
        _ samples: [TrafficTimeline.Sample],
        window: OverviewTimelineWindow
    ) -> [TrafficTimeline.Sample] {
        bounded(samples, duration: window.duration, date: \.receivedAt)
    }

    static func memorySamples(
        _ samples: [MemoryTimeline.Sample],
        window: OverviewTimelineWindow
    ) -> [MemoryTimeline.Sample] {
        bounded(samples, duration: window.duration, date: \.receivedAt)
    }

    static func connectionSamples(
        _ samples: [ConnectionCountTimeline.Sample],
        window: OverviewTimelineWindow
    ) -> [ConnectionCountTimeline.Sample] {
        bounded(samples, duration: window.duration, date: \.receivedAt)
    }

    static func nearestTrafficSample(
        to date: Date,
        in samples: [TrafficTimeline.Sample]
    ) -> TrafficTimeline.Sample? {
        nearest(to: date, in: samples, date: \.receivedAt)
    }

    static func nearestMemorySample(
        to date: Date,
        in samples: [MemoryTimeline.Sample]
    ) -> MemoryTimeline.Sample? {
        nearest(to: date, in: samples, date: \.receivedAt)
    }

    static func nearestConnectionSample(
        to date: Date,
        in samples: [ConnectionCountTimeline.Sample]
    ) -> ConnectionCountTimeline.Sample? {
        nearest(to: date, in: samples, date: \.receivedAt)
    }

    static func mergedDates(
        traffic: [TrafficTimeline.Sample],
        memory: [MemoryTimeline.Sample],
        connections: [ConnectionCountTimeline.Sample] = []
    ) -> [Date] {
        mergeSortedUniqueDates([
            traffic.map(\.receivedAt),
            memory.map(\.receivedAt),
            connections.map(\.receivedAt),
        ])
    }

    private static func mergeSortedUniqueDates(_ collections: [[Date]]) -> [Date] {
        guard collections.allSatisfy(\.isSortedAscending) else {
            return Array(Set(collections.flatMap(\.self))).sorted()
        }

        var result: [Date] = []
        result.reserveCapacity(collections.reduce(0) { $0 + $1.count })
        var indices = collections.map(\.startIndex)

        while true {
            var nextDate: Date?
            for (collectionIndex, dates) in collections.enumerated()
                where indices[collectionIndex] < dates.endIndex {
                let candidate = dates[indices[collectionIndex]]
                if let current = nextDate {
                    if candidate < current {
                        nextDate = candidate
                    }
                } else {
                    nextDate = candidate
                }
            }
            guard let nextDate else { break }
            if result.last != nextDate {
                result.append(nextDate)
            }
            for (collectionIndex, dates) in collections.enumerated() {
                while indices[collectionIndex] < dates.endIndex,
                      dates[indices[collectionIndex]] == nextDate {
                    indices[collectionIndex] = dates.index(
                        after: indices[collectionIndex]
                    )
                }
            }
        }
        return result
    }

    static func nearestDateIndex(to target: Date, in dates: [Date]) -> Int? {
        nearestIndex(to: target, in: dates, date: { $0 })
    }

    static func downsample<Sample>(_ samples: [Sample], maximumCount: Int) -> [Sample] {
        let limit = max(maximumCount, 2)
        guard samples.count > limit else { return samples }

        let step = Double(samples.count - 1) / Double(limit - 1)
        return (0..<limit).map { offset in
            samples[min(Int((Double(offset) * step).rounded()), samples.count - 1)]
        }
    }

    private static func bounded<Sample>(
        _ samples: [Sample],
        duration: TimeInterval,
        date: KeyPath<Sample, Date>
    ) -> [Sample] {
        guard let latest = samples.last?[keyPath: date] else { return [] }
        let cutoff = latest.addingTimeInterval(-duration)
        return samples.filter { $0[keyPath: date] >= cutoff }
    }

    private static func nearest<Sample>(
        to target: Date,
        in samples: [Sample],
        date: KeyPath<Sample, Date>
    ) -> Sample? {
        guard let index = nearestIndex(
            to: target,
            in: samples,
            date: { $0[keyPath: date] }
        ) else {
            return nil
        }
        return samples[index]
    }

    private static func nearestIndex<Element>(
        to target: Date,
        in elements: [Element],
        date: (Element) -> Date
    ) -> Int? {
        guard !elements.isEmpty else { return nil }
        var lowerBound = elements.startIndex
        var upperBound = elements.endIndex
        while lowerBound < upperBound {
            let distance = elements.distance(from: lowerBound, to: upperBound)
            let middle = elements.index(lowerBound, offsetBy: distance / 2)
            if date(elements[middle]) < target {
                lowerBound = elements.index(after: middle)
            } else {
                upperBound = middle
            }
        }

        guard lowerBound != elements.startIndex else { return elements.startIndex }
        guard lowerBound != elements.endIndex else { return elements.index(before: elements.endIndex) }

        let previous = elements.index(before: lowerBound)
        let previousDistance = abs(date(elements[previous]).timeIntervalSince(target))
        let nextDistance = abs(date(elements[lowerBound]).timeIntervalSince(target))
        return previousDistance <= nextDistance ? previous : lowerBound
    }
}

struct OverviewLatencyAnomaly: Identifiable, Equatable {
    var id: String { groupOccurrenceID }

    let groupOccurrenceID: String
    let groupName: String
    let nodeName: String
    let delay: Int
}

struct OverviewRuleHitSummary: Identifiable, Equatable {
    let id: String
    let sourceIndex: Int
    let reportedRuleID: String
    let type: String
    let payload: String
    let label: String
    let proxy: String
    let hits: Int?
    let misses: Int?

    var total: Int {
        let hits = hits ?? 0
        let misses = misses ?? 0
        return hits > Int.max - misses ? Int.max : hits + misses
    }
}

struct OverviewActiveConnection: Identifiable, Equatable, Sendable {
    let id: String
    let sourceIndex: Int
    let connectionID: String
    let label: String
    let totalTraffic: Int?
}

struct OverviewNetworkFact: Identifiable, Equatable {
    let id: String
    let group: OverviewNetworkGroupID
    let titleKey: String
    let value: String
    var monospaced = true
}

struct OverviewNetworkFactGroup: Identifiable, Equatable {
    let id: OverviewNetworkGroupID
    let facts: [OverviewNetworkFact]
}

struct OverviewTopKOperationCounts: Equatable {
    fileprivate(set) var scannedCount = 0
    fileprivate(set) var candidateCount = 0
    fileprivate(set) var comparisonCount = 0
    fileprivate(set) var maximumRetainedCount = 0
}

enum OverviewProjection {
    static func latencyAnomalies(
        from groups: [ProxyGroupViewState],
        maximumCount: Int
    ) -> [OverviewLatencyAnomaly] {
        latencyAnomaliesWithOperationCounts(from: groups, maximumCount: maximumCount).rows
    }

    static func latencyAnomaliesWithOperationCounts(
        from groups: [ProxyGroupViewState],
        maximumCount: Int
    ) -> (rows: [OverviewLatencyAnomaly], operationCounts: OverviewTopKOperationCounts) {
        var occurrences: [String: Int] = [:]
        return boundedTopK(from: groups, maximumCount: maximumCount) { sourceIndex, group in
            let occurrence = occurrences[group.id, default: 0]
            occurrences[group.id] = occurrence + 1
            guard let delay = group.delays[group.selected]
                    ?? group.detail(for: group.selected)?.latestHistoryDelay,
                  delay >= 180 else {
                return nil
            }
            return (
                OverviewLatencyAnomaly(
                    groupOccurrenceID: ProxyGroupKey(
                        groupID: group.id,
                        occurrence: occurrence
                    ).rawValue,
                    groupName: group.id,
                    nodeName: group.selected,
                    delay: delay
                ),
                delay,
                sourceIndex
            )
        }
    }

    static func ruleHitSummary(
        from rules: [RuleViewState],
        maximumCount: Int
    ) -> [OverviewRuleHitSummary] {
        ruleHitSummaryWithOperationCounts(from: rules, maximumCount: maximumCount).rows
    }

    static func ruleHitSummaryWithOperationCounts(
        from rules: [RuleViewState],
        maximumCount: Int
    ) -> (rows: [OverviewRuleHitSummary], operationCounts: OverviewTopKOperationCounts) {
        var occurrences: [String: Int] = [:]
        return boundedTopK(from: rules, maximumCount: maximumCount) { sourceIndex, rule in
            guard rule.hitCount != nil || rule.missCount != nil else { return nil }
            let baseID = nonBlank(rule.id) ?? "__unreported_rule__"
            let occurrence = occurrences[baseID, default: 0]
            occurrences[baseID] = occurrence + 1
            let row = OverviewRuleHitSummary(
                id: "\(baseID.utf8.count):\(baseID):\(occurrence)",
                sourceIndex: sourceIndex,
                reportedRuleID: rule.id,
                type: rule.type,
                payload: rule.payload,
                label: nonBlank(rule.payload) ?? rule.type,
                proxy: rule.proxy,
                hits: rule.hitCount.map { max($0, 0) },
                misses: rule.missCount.map { max($0, 0) }
            )
            return (row, row.total, sourceIndex)
        }
    }

    static func topActiveConnections(
        from connections: [ConnectionSnapshot],
        maximumCount: Int
    ) -> [OverviewActiveConnection] {
        topActiveConnectionsWithOperationCounts(
            from: connections,
            maximumCount: maximumCount
        ).rows
    }

    static func topActiveConnectionsWithOperationCounts(
        from connections: [ConnectionSnapshot],
        maximumCount: Int
    ) -> (rows: [OverviewActiveConnection], operationCounts: OverviewTopKOperationCounts) {
        var occurrences: [String: Int] = [:]
        return boundedTopK(from: connections, maximumCount: maximumCount) { sourceIndex, connection in
            activeConnectionCandidate(
                sourceIndex: sourceIndex,
                connection: connection,
                occurrences: &occurrences
            )
        }
    }

    @concurrent
    static func topActiveConnectionsCancellable(
        from connections: [ConnectionSnapshot],
        maximumCount: Int
    ) async throws -> [OverviewActiveConnection] {
        try Task.checkCancellation()
        var occurrences: [String: Int] = [:]
        guard let projection = boundedTopK(
            from: connections,
            maximumCount: maximumCount,
            checksCancellation: true,
            candidate: { sourceIndex, connection in
                activeConnectionCandidate(
                    sourceIndex: sourceIndex,
                    connection: connection,
                    occurrences: &occurrences
                )
            }
        ) else {
            throw CancellationError()
        }
        try Task.checkCancellation()
        return projection.rows
    }

    static func networkFacts(
        router: RouterProfile?,
        metadata: ControllerMetadataSnapshot,
        language: AppLanguage
    ) -> [OverviewNetworkFact] {
        var facts: [OverviewNetworkFact] = []
        if let router {
            facts.append(OverviewNetworkFact(
                id: "controller",
                group: .controllerIdentity,
                titleKey: "overview.network_controller_name",
                value: router.displayName,
                monospaced: false
            ))
            facts.append(OverviewNetworkFact(
                id: "endpoint",
                group: .controllerIdentity,
                titleKey: "overview.network_endpoint",
                value: router.endpointURL
            ))
            facts.append(OverviewNetworkFact(
                id: "host",
                group: .controllerIdentity,
                titleKey: "overview.network_host",
                value: router.host
            ))
            facts.append(OverviewNetworkFact(
                id: "port",
                group: .controllerIdentity,
                titleKey: "overview.network_port",
                value: router.port.formatted()
            ))
        }
        if metadata.versionLabel != "-" {
            facts.append(OverviewNetworkFact(
                id: "version",
                group: .controllerIdentity,
                titleKey: "dashboard.cmd_version",
                value: metadata.versionLabel,
                monospaced: false
            ))
        }
        if metadata.mode != "unknown" {
            facts.append(OverviewNetworkFact(
                id: "mode",
                group: .controllerIdentity,
                titleKey: "dashboard.mode",
                value: metadata.mode,
                monospaced: false
            ))
        }
        let config = metadata.config
        append(
            value: config.modeOptions.isEmpty ? nil : config.modeOptions.joined(separator: "\n"),
            id: "mode-options",
            titleKey: "overview.config_mode_options",
            to: &facts,
            group: .runtimeAndFeatures,
            monospaced: false
        )
        append(value: config.logLevel, id: "log-level", titleKey: "overview.config_log_level", to: &facts, group: .runtimeAndFeatures, monospaced: false)
        append(value: config.allowLan.map { boolText($0, language: language) }, id: "allow-lan", titleKey: "overview.config_allow_lan", to: &facts, group: .runtimeAndFeatures, monospaced: false)
        append(value: config.ipv6.map { boolText($0, language: language) }, id: "ipv6", titleKey: "overview.config_ipv6", to: &facts, group: .runtimeAndFeatures, monospaced: false)
        append(value: config.tcpConcurrent.map { boolText($0, language: language) }, id: "tcp-concurrent", titleKey: "overview.config_tcp_concurrent", to: &facts, group: .runtimeAndFeatures, monospaced: false)
        append(value: config.tunEnabled.map { boolText($0, language: language) }, id: "tun", titleKey: "overview.config_tun", to: &facts, group: .runtimeAndFeatures, monospaced: false)
        append(value: config.port.map { $0.formatted() }, id: "http-port", titleKey: "overview.config_http_port", to: &facts, group: .listenerPorts)
        append(value: config.socksPort.map { $0.formatted() }, id: "socks-port", titleKey: "overview.config_socks_port", to: &facts, group: .listenerPorts)
        append(value: config.redirPort.map { $0.formatted() }, id: "redir-port", titleKey: "overview.config_redir_port", to: &facts, group: .listenerPorts)
        append(value: config.mixedPort.map { $0.formatted() }, id: "mixed-port", titleKey: "overview.config_mixed_port", to: &facts, group: .listenerPorts)
        return facts
    }

    static func networkFactGroups(
        router: RouterProfile?,
        metadata: ControllerMetadataSnapshot,
        language: AppLanguage,
        order: [OverviewNetworkGroupID] = OverviewNetworkGroupID.allCases
    ) -> [OverviewNetworkFactGroup] {
        let facts = networkFacts(router: router, metadata: metadata, language: language)
        return order.compactMap { groupID in
            let groupedFacts = facts.filter { $0.group == groupID }
            guard !groupedFacts.isEmpty else { return nil }
            return OverviewNetworkFactGroup(id: groupID, facts: groupedFacts)
        }
    }

    private static func boundedTopK<Input, Output>(
        from input: [Input],
        maximumCount: Int,
        candidate: (Int, Input) -> (value: Output, score: Int, sourceIndex: Int)?
    ) -> (rows: [Output], operationCounts: OverviewTopKOperationCounts) {
        boundedTopK(
            from: input,
            maximumCount: maximumCount,
            checksCancellation: false,
            candidate: candidate
        )!
    }

    private static func boundedTopK<Input, Output>(
        from input: [Input],
        maximumCount: Int,
        checksCancellation: Bool,
        candidate: (Int, Input) -> (value: Output, score: Int, sourceIndex: Int)?
    ) -> (rows: [Output], operationCounts: OverviewTopKOperationCounts)? {
        let limit = max(maximumCount, 0)
        var counts = OverviewTopKOperationCounts()
        guard limit > 0 else { return ([], counts) }

        var retained: [(value: Output, score: Int, sourceIndex: Int)] = []
        retained.reserveCapacity(min(limit, input.count))

        for (sourceIndex, item) in input.enumerated() {
            if checksCancellation,
               sourceIndex.isMultiple(of: 64),
               Task<Never, Never>.isCancelled {
                return nil
            }
            counts.scannedCount += 1
            guard let candidate = candidate(sourceIndex, item) else { continue }
            counts.candidateCount += 1

            var insertionIndex = retained.endIndex
            for index in retained.indices {
                counts.comparisonCount += 1
                let current = retained[index]
                if candidate.score > current.score
                    || (candidate.score == current.score
                        && candidate.sourceIndex < current.sourceIndex) {
                    insertionIndex = index
                    break
                }
            }

            if insertionIndex < limit {
                retained.insert(candidate, at: insertionIndex)
                if retained.count > limit {
                    retained.removeLast()
                }
            } else if retained.count < limit {
                retained.append(candidate)
            }
            counts.maximumRetainedCount = max(counts.maximumRetainedCount, retained.count)
        }

        return (retained.map(\.value), counts)
    }

    private static func activeConnectionCandidate(
        sourceIndex: Int,
        connection: ConnectionSnapshot,
        occurrences: inout [String: Int]
    ) -> (value: OverviewActiveConnection, score: Int, sourceIndex: Int) {
        let baseID = nonBlank(connection.id) ?? "__unreported_connection__"
        let occurrence = occurrences[baseID, default: 0]
        occurrences[baseID] = occurrence + 1
        let upload = connection.upload.map { max($0, 0) }
        let download = connection.download.map { max($0, 0) }
        let total = reportedTotal(upload: upload, download: download)
        let label = nonBlank(connection.metadata?.host)
            ?? nonBlank(connection.metadata?.remoteDestination)
            ?? nonBlank(connection.metadata?.process)
            ?? nonBlank(connection.metadata?.destinationIP)
            ?? nonBlank(connection.id)
            ?? ""
        return (
            OverviewActiveConnection(
                id: "\(baseID.utf8.count):\(baseID):\(occurrence)",
                sourceIndex: sourceIndex,
                connectionID: connection.id,
                label: label,
                totalTraffic: total
            ),
            total ?? -1,
            sourceIndex
        )
    }

    private static func append(
        value: String?,
        id: String,
        titleKey: String,
        to facts: inout [OverviewNetworkFact],
        group: OverviewNetworkGroupID,
        monospaced: Bool = true
    ) {
        guard let value = nonBlank(value) else { return }
        facts.append(
            OverviewNetworkFact(
                id: id,
                group: group,
                titleKey: titleKey,
                value: value,
                monospaced: monospaced
            )
        )
    }

    private static func boolText(_ value: Bool, language: AppLanguage) -> String {
        MicaStrings.localizedKey(
            value ? "overview.config_enabled" : "overview.config_disabled",
            language: language
        )
    }

    private static func reportedTotal(upload: Int?, download: Int?) -> Int? {
        guard upload != nil || download != nil else { return nil }
        let upload = upload ?? 0
        let download = download ?? 0
        return upload > Int.max - download ? Int.max : upload + download
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : value
    }
}

private extension Array where Element == Date {
    var isSortedAscending: Bool {
        zip(self, dropFirst()).allSatisfy(<=)
    }
}
