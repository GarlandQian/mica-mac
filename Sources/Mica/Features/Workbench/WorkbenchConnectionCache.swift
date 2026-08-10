import Foundation
import MicaCore

// MARK: - Connection cache and pulse projection

struct WorkbenchConnectionPulseOwner: Identifiable, Equatable {
    let identity: WorkbenchConnectionOwnerIdentity
    let count: Int

    var id: String { identity.id }
}

private struct WorkbenchConnectionReportedMetric: Equatable {
    private(set) var sum: Int64 = 0
    private(set) var reportedCount = 0

    var value: Int64? {
        reportedCount > 0 ? sum : nil
    }

    mutating func add(_ value: Int?) {
        guard let value, value >= 0 else { return }
        sum = Self.addingClamped(sum, Int64(value))
        reportedCount += 1
    }

    mutating func remove(_ value: Int?) {
        guard let value, value >= 0 else { return }
        sum = Self.addingClamped(sum, -Int64(value))
        reportedCount = max(0, reportedCount - 1)
        if reportedCount == 0 {
            sum = 0
        }
    }

    mutating func replace(_ previous: Int?, with current: Int?) {
        remove(previous)
        add(current)
    }

    private static func addingClamped(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard overflow else { return sum }
        return rhs >= 0 ? .max : .min
    }
}

private struct WorkbenchConnectionMetricValues: Equatable {
    let upload: Int?
    let download: Int?
    let uploadSpeed: Int?
    let downloadSpeed: Int?

    init(connection: ConnectionSnapshot) {
        upload = connection.upload
        download = connection.download
        uploadSpeed = connection.uploadSpeed
        downloadSpeed = connection.downloadSpeed
    }
}

private struct WorkbenchConnectionMetricDelta: Equatable {
    let sourceIndex: Int
    let previous: WorkbenchConnectionMetricValues
    let current: WorkbenchConnectionMetricValues
}

private struct WorkbenchConnectionMetricsReplacement {
    var changedIndices: [Int] = []
    var metricDeltas: [WorkbenchConnectionMetricDelta] = []
}

struct WorkbenchConnectionPulseProjection: Equatable {
    let scope: ConnectionSessionTab
    let visibleCount: Int
    let totalCount: Int
    let isFiltered: Bool
    let owners: [WorkbenchConnectionPulseOwner]
    let remainingOwnerCount: Int

    private var uploadMetric: WorkbenchConnectionReportedMetric
    private var downloadMetric: WorkbenchConnectionReportedMetric
    private var uploadRateMetric: WorkbenchConnectionReportedMetric
    private var downloadRateMetric: WorkbenchConnectionReportedMetric

    var uploadBytes: Int64? { uploadMetric.value }
    var downloadBytes: Int64? { downloadMetric.value }
    var uploadRate: Int64? { scope == .active ? uploadRateMetric.value : nil }
    var downloadRate: Int64? { scope == .active ? downloadRateMetric.value : nil }

    var totalBytes: Int64? {
        guard uploadBytes != nil || downloadBytes != nil else { return nil }
        let upload = uploadBytes ?? 0
        let download = downloadBytes ?? 0
        let (sum, overflow) = upload.addingReportingOverflow(download)
        return overflow ? .max : sum
    }

    static func empty(scope: ConnectionSessionTab = .active) -> Self {
        WorkbenchConnectionPulseProjection(
            scope: scope,
            visibleCount: 0,
            totalCount: 0,
            isFiltered: false,
            owners: [],
            remainingOwnerCount: 0,
            uploadMetric: WorkbenchConnectionReportedMetric(),
            downloadMetric: WorkbenchConnectionReportedMetric(),
            uploadRateMetric: WorkbenchConnectionReportedMetric(),
            downloadRateMetric: WorkbenchConnectionReportedMetric()
        )
    }

    fileprivate static func project(
        rows: [WorkbenchConnectionRow],
        sourceIndices: [Int],
        totalCount: Int,
        scope: ConnectionSessionTab,
        isFiltered: Bool
    ) -> Self {
        var uploadMetric = WorkbenchConnectionReportedMetric()
        var downloadMetric = WorkbenchConnectionReportedMetric()
        var uploadRateMetric = WorkbenchConnectionReportedMetric()
        var downloadRateMetric = WorkbenchConnectionReportedMetric()
        var ownerCounts: [WorkbenchConnectionOwnerIdentity: Int] = [:]
        var ownerFirstSeen: [WorkbenchConnectionOwnerIdentity: Int] = [:]

        for sourceIndex in sourceIndices where rows.indices.contains(sourceIndex) {
            let row = rows[sourceIndex]
            uploadMetric.add(row.connection.upload)
            downloadMetric.add(row.connection.download)
            if scope == .active {
                uploadRateMetric.add(row.connection.uploadSpeed)
                downloadRateMetric.add(row.connection.downloadSpeed)
            }

            let owner = WorkbenchConnectionOwnerIdentity(connection: row.connection)
            if ownerFirstSeen[owner] == nil {
                ownerFirstSeen[owner] = ownerFirstSeen.count
            }
            ownerCounts[owner, default: 0] += 1
        }

        let rankedOwners = ownerCounts.map { identity, count in
            (
                owner: WorkbenchConnectionPulseOwner(identity: identity, count: count),
                firstSeen: ownerFirstSeen[identity] ?? .max
            )
        }
        .sorted { lhs, rhs in
            if lhs.owner.count != rhs.owner.count {
                return lhs.owner.count > rhs.owner.count
            }
            return lhs.firstSeen < rhs.firstSeen
        }

        let owners = rankedOwners.prefix(3).map(\.owner)
        let remainingOwnerCount = rankedOwners.dropFirst(3).reduce(0) {
            $0 + $1.owner.count
        }

        return WorkbenchConnectionPulseProjection(
            scope: scope,
            visibleCount: sourceIndices.count,
            totalCount: totalCount,
            isFiltered: isFiltered,
            owners: owners,
            remainingOwnerCount: remainingOwnerCount,
            uploadMetric: uploadMetric,
            downloadMetric: downloadMetric,
            uploadRateMetric: uploadRateMetric,
            downloadRateMetric: downloadRateMetric
        )
    }

    fileprivate mutating func applyMetricDeltas(
        _ deltas: [WorkbenchConnectionMetricDelta]
    ) {
        guard scope == .active else { return }
        for delta in deltas {
            uploadMetric.replace(delta.previous.upload, with: delta.current.upload)
            downloadMetric.replace(delta.previous.download, with: delta.current.download)
            uploadRateMetric.replace(
                delta.previous.uploadSpeed,
                with: delta.current.uploadSpeed
            )
            downloadRateMetric.replace(
                delta.previous.downloadSpeed,
                with: delta.current.downloadSpeed
            )
        }
    }
}

struct WorkbenchConnectionProjectionCache {
    private(set) var allRows: [WorkbenchConnectionRow] = []
    private(set) var visibleRows: [WorkbenchConnectionRow] = []
    private(set) var pulseProjection = WorkbenchConnectionPulseProjection.empty()
    private(set) var closeGroups: [WorkbenchConnectionCloseGroup] = []
    private(set) var connectionIDs: Set<String> = []
    private(set) var groupIDs: Set<String> = []
    private(set) var staticProjectionCount = 0
    private(set) var metricsProjectionCount = 0
    private(set) var staticRowProjectionCount = 0
    private(set) var metricsRowProjectionCount = 0
    private(set) var metricsCandidateProjectionCount = 0
    private(set) var filterProjectionCount = 0
    private(set) var sortProjectionCount = 0
    private(set) var pulseProjectionCount = 0
    private(set) var pulseMetricUpdateCount = 0
    private(set) var pulseMetricCandidateCount = 0

    private var scope: ConnectionSessionTab?
    private var structureRevision: UInt64?
    private var metricsRevision: UInt64?
    private var closedRevision: UInt64?
    private var language: AppLanguage?
    private var query: String?
    private var sortOrder: [KeyPathComparator<WorkbenchConnectionRow>] = []
    private var filteredSourceIndices: [Int] = []
    private var rowIndexByID: [String: Int] = [:]
    private var visibleIndexBySourceIndex: [Int: Int] = [:]
    private(set) var hasDeferredMetricSort = false

    @discardableResult
    mutating func project(
        activeConnections: [ConnectionSnapshot],
        closedConnections: [ClosedConnectionRecord],
        scope: ConnectionSessionTab,
        structureRevision: UInt64,
        metricsRevision: UInt64,
        closedRevision: UInt64,
        query: String,
        sortOrder: [KeyPathComparator<WorkbenchConnectionRow>],
        language: AppLanguage,
        change: ConnectionsCatalogChange? = nil,
        deferMetricSorting: Bool = false,
        isActive: Bool = true
    ) -> Bool {
        guard isActive else { return false }

        let scopeChanged = self.scope != scope
        let languageChanged = self.language != language
        let normalizedQuery = query.dataNonEmpty
        let filterChanged = self.query != normalizedQuery
        var sourceChanged = false
        var changedMetricIndices: [Int] = []
        var metricDeltas: [WorkbenchConnectionMetricDelta] = []

        switch scope {
        case .active:
            if scopeChanged || self.structureRevision != structureRevision {
                replaceSource(
                    WorkbenchConnectionProjection.rows(
                        from: activeConnections,
                        language: language
                    )
                )
                staticProjectionCount += 1
                staticRowProjectionCount += allRows.count
                sourceChanged = true
            } else if self.metricsRevision != metricsRevision || languageChanged {
                if activeConnections.count == allRows.count {
                    let keyedIndices = languageChanged
                        ? nil
                        : keyedMetricIndices(
                            in: activeConnections,
                            nextRevision: metricsRevision,
                            change: change
                        )
                    if keyedIndices != nil || sourceIDsMatch(activeConnections) {
                        let replacement = replaceMetrics(
                            with: activeConnections,
                            at: keyedIndices,
                            language: language,
                            forceFormatting: languageChanged
                        )
                        changedMetricIndices = replacement.changedIndices
                        metricDeltas = replacement.metricDeltas
                    } else {
                        replaceSource(
                            WorkbenchConnectionProjection.rows(
                                from: activeConnections,
                                language: language
                            )
                        )
                        staticProjectionCount += 1
                        staticRowProjectionCount += allRows.count
                        sourceChanged = true
                    }
                } else {
                    replaceSource(
                        WorkbenchConnectionProjection.rows(
                            from: activeConnections,
                            language: language
                        )
                    )
                    staticProjectionCount += 1
                    staticRowProjectionCount += allRows.count
                    sourceChanged = true
                }
            }
            self.structureRevision = structureRevision
            self.metricsRevision = metricsRevision
            self.closedRevision = nil

        case .closed:
            if scopeChanged || self.closedRevision != closedRevision {
                replaceSource(
                    WorkbenchConnectionProjection.rows(
                        from: closedConnections,
                        language: language
                    )
                )
                staticProjectionCount += 1
                staticRowProjectionCount += allRows.count
                sourceChanged = true
            } else if languageChanged {
                let snapshots = closedConnections.map(\.snapshot)
                if snapshots.count == allRows.count, sourceIDsMatch(snapshots) {
                    let replacement = replaceMetrics(
                        with: snapshots,
                        at: nil,
                        language: language,
                        forceFormatting: true
                    )
                    changedMetricIndices = replacement.changedIndices
                    metricDeltas = replacement.metricDeltas
                } else {
                    replaceSource(
                        WorkbenchConnectionProjection.rows(
                            from: closedConnections,
                            language: language
                        )
                    )
                    staticProjectionCount += 1
                    staticRowProjectionCount += allRows.count
                    sourceChanged = true
                }
            }
            self.structureRevision = nil
            self.metricsRevision = nil
            self.closedRevision = closedRevision
        }

        self.scope = scope
        self.language = language
        let visibleChanged = updateVisibleRows(
            query: query,
            sortOrder: sortOrder,
            sourceChanged: sourceChanged,
            changedMetricIndices: changedMetricIndices,
            deferMetricSorting: deferMetricSorting
        )

        if sourceChanged || filterChanged {
            pulseProjection = WorkbenchConnectionPulseProjection.project(
                rows: allRows,
                sourceIndices: filteredSourceIndices,
                totalCount: allRows.count,
                scope: scope,
                isFiltered: normalizedQuery != nil
            )
            pulseProjectionCount += 1
        } else if !metricDeltas.isEmpty {
            let visibleDeltas = metricDeltas.filter {
                visibleIndexBySourceIndex[$0.sourceIndex] != nil
            }
            if !visibleDeltas.isEmpty {
                pulseProjection.applyMetricDeltas(visibleDeltas)
                pulseMetricUpdateCount += 1
                pulseMetricCandidateCount += visibleDeltas.count
            }
        }
        return visibleChanged
    }

    @discardableResult
    mutating func commitDeferredMetricSort() -> Bool {
        guard hasDeferredMetricSort else { return false }
        hasDeferredMetricSort = false
        guard isMetricSort(sortOrder) else { return false }

        visibleRows = filteredSourceIndices.map { allRows[$0] }
        visibleRows.sort(using: sortOrder)
        rebuildVisibleIndex()
        sortProjectionCount += 1
        return true
    }

    func row(id: String?) -> WorkbenchConnectionRow? {
        guard let id, let index = rowIndexByID[id], allRows.indices.contains(index) else {
            return nil
        }
        return allRows[index]
    }

    mutating func reset() {
        self = WorkbenchConnectionProjectionCache()
    }

    private mutating func replaceSource(_ rows: [WorkbenchConnectionRow]) {
        allRows = rows
        rowIndexByID = Dictionary(
            uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) }
        )
        connectionIDs = Set(rows.map(\.id))
        closeGroups = WorkbenchConnectionProjection.closeGroups(from: rows)
        groupIDs = Set(closeGroups.map(\.id))
    }

    private mutating func replaceMetrics(
        with connections: [ConnectionSnapshot],
        at sourceIndices: [Int]?,
        language: AppLanguage,
        forceFormatting: Bool
    ) -> WorkbenchConnectionMetricsReplacement {
        let formatter = WorkbenchDataFormat.MetricsFormatter(language: language)
        var nextRows = allRows
        var replacement = WorkbenchConnectionMetricsReplacement()

        func updatedRow(at index: Int) -> WorkbenchConnectionRow {
            WorkbenchConnectionProjection.updatingMetrics(
                in: allRows[index],
                from: connections[index],
                formatter: formatter,
                forceFormatting: forceFormatting
            )
        }

        if let sourceIndices {
            replacement.changedIndices.reserveCapacity(sourceIndices.count)
            replacement.metricDeltas.reserveCapacity(sourceIndices.count)
            for index in sourceIndices {
                let next = updatedRow(at: index)
                if next != allRows[index] {
                    let previousMetrics = WorkbenchConnectionMetricValues(
                        connection: allRows[index].connection
                    )
                    let currentMetrics = WorkbenchConnectionMetricValues(
                        connection: next.connection
                    )
                    nextRows[index] = next
                    replacement.changedIndices.append(index)
                    if previousMetrics != currentMetrics {
                        replacement.metricDeltas.append(
                            WorkbenchConnectionMetricDelta(
                                sourceIndex: index,
                                previous: previousMetrics,
                                current: currentMetrics
                            )
                        )
                    }
                }
            }
        } else {
            replacement.changedIndices.reserveCapacity(connections.count)
            replacement.metricDeltas.reserveCapacity(connections.count)
            for index in connections.indices {
                let next = updatedRow(at: index)
                if next != allRows[index] {
                    let previousMetrics = WorkbenchConnectionMetricValues(
                        connection: allRows[index].connection
                    )
                    let currentMetrics = WorkbenchConnectionMetricValues(
                        connection: next.connection
                    )
                    nextRows[index] = next
                    replacement.changedIndices.append(index)
                    if previousMetrics != currentMetrics {
                        replacement.metricDeltas.append(
                            WorkbenchConnectionMetricDelta(
                                sourceIndex: index,
                                previous: previousMetrics,
                                current: currentMetrics
                            )
                        )
                    }
                }
            }
        }

        allRows = nextRows
        metricsProjectionCount += 1
        metricsCandidateProjectionCount += sourceIndices?.count ?? connections.count
        metricsRowProjectionCount += replacement.changedIndices.count
        return replacement
    }

    private func keyedMetricIndices(
        in connections: [ConnectionSnapshot],
        nextRevision: UInt64,
        change: ConnectionsCatalogChange?
    ) -> [Int]? {
        guard let previousRevision = metricsRevision,
              previousRevision &+ 1 == nextRevision,
              let change,
              !change.structureChanged,
              let indices = change.changedMetricIndices else {
            return nil
        }

        var uniqueIndices: [Int] = []
        var seen: Set<Int> = []
        uniqueIndices.reserveCapacity(indices.count)
        for index in indices {
            guard connections.indices.contains(index),
                  allRows.indices.contains(index),
                  allRows[index].connection.id == connections[index].id else {
                return nil
            }
            if seen.insert(index).inserted {
                uniqueIndices.append(index)
            }
        }
        return uniqueIndices
    }

    private func sourceIDsMatch(_ connections: [ConnectionSnapshot]) -> Bool {
        connections.count == allRows.count
            && zip(allRows, connections).allSatisfy {
                $0.connection.id == $1.id
            }
    }

    private func isMetricSort(
        _ sortOrder: [KeyPathComparator<WorkbenchConnectionRow>]
    ) -> Bool {
        sortOrder.contains {
            $0.keyPath == \WorkbenchConnectionRow.upload
                || $0.keyPath == \WorkbenchConnectionRow.download
        }
    }

    private mutating func updateVisibleMetrics(at sourceIndices: [Int]) {
        for sourceIndex in sourceIndices {
            guard let visibleIndex = visibleIndexBySourceIndex[sourceIndex],
                  visibleRows.indices.contains(visibleIndex),
                  allRows.indices.contains(sourceIndex) else {
                continue
            }
            visibleRows[visibleIndex] = allRows[sourceIndex]
        }
    }

    private mutating func rebuildVisibleIndex() {
        visibleIndexBySourceIndex = Dictionary(
            uniqueKeysWithValues: visibleRows.enumerated().map {
                ($0.element.sourceIndex, $0.offset)
            }
        )
    }

    private mutating func rebuildVisibleRows(
        sortOrder: [KeyPathComparator<WorkbenchConnectionRow>]
    ) {
        visibleRows = filteredSourceIndices.map { allRows[$0] }
        if !sortOrder.isEmpty {
            visibleRows.sort(using: sortOrder)
            sortProjectionCount += 1
        }
        rebuildVisibleIndex()
    }

    private mutating func updateVisibleRows(
        query: String,
        sortOrder: [KeyPathComparator<WorkbenchConnectionRow>],
        sourceChanged: Bool,
        changedMetricIndices: [Int],
        deferMetricSorting: Bool
    ) -> Bool {
        let normalizedQuery = query.dataNonEmpty
        let filterChanged = self.query != normalizedQuery
        let sortChanged = self.sortOrder != sortOrder

        if sourceChanged || filterChanged {
            filteredSourceIndices = allRows.indices.filter { index in
                guard let normalizedQuery else { return true }
                return WorkbenchDataSearch.contains(
                    normalizedQuery,
                    in: allRows[index].searchText
                )
            }
            filterProjectionCount += 1
        }

        if sourceChanged || filterChanged || sortChanged {
            rebuildVisibleRows(sortOrder: sortOrder)
            hasDeferredMetricSort = false
        } else if !changedMetricIndices.isEmpty {
            updateVisibleMetrics(at: changedMetricIndices)
            if isMetricSort(sortOrder) {
                if deferMetricSorting {
                    hasDeferredMetricSort = true
                } else {
                    rebuildVisibleRows(sortOrder: sortOrder)
                    hasDeferredMetricSort = false
                }
            }
        }

        self.query = normalizedQuery
        self.sortOrder = sortOrder
        return sourceChanged || filterChanged || sortChanged || !changedMetricIndices.isEmpty
    }
}

struct WorkbenchConnectionMetricSortCadence: Equatable {
    static let maximumDeferral: TimeInterval = 0.2

    private(set) var pendingDeadline: Date?

    mutating func schedule(now: Date = Date()) {
        guard pendingDeadline == nil else { return }
        pendingDeadline = now.addingTimeInterval(Self.maximumDeferral)
    }

    mutating func consume(now: Date = Date()) -> Bool {
        guard let pendingDeadline, pendingDeadline <= now else { return false }
        self.pendingDeadline = nil
        return true
    }

    mutating func cancel() {
        pendingDeadline = nil
    }
}
