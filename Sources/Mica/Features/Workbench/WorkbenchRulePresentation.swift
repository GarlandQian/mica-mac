import Foundation
import MicaCore

extension WorkbenchDataInspectorProjection {
    static func ruleDefinition(
        _ row: WorkbenchRuleRow
    ) -> [WorkbenchDataInspectorValue] {
        let rule = row.rule
        return [
            value("rule.id", "dashboard.col_id", rule.id, monospaced: true),
            value("rule.payload", "dashboard.col_payload", rule.payload, monospaced: true),
            value("rule.type", "dashboard.col_type", rule.type, monospaced: true),
            value("rule.proxy", "dashboard.col_proxy", rule.proxy),
            value("rule.index", "dashboard.col_index", rule.index.map(String.init), monospaced: true),
            value("rule.size", "dashboard.col_size", rule.size.map(String.init), monospaced: true),
            value("rule.active-connections", "dashboard.active_sessions", String(row.activeConnections), monospaced: true),
        ]
    }

    static func ruleStatistics(
        _ row: WorkbenchRuleRow
    ) -> [WorkbenchDataInspectorValue] {
        let rule = row.rule
        return [
            value("rule.hit-count", "traffic.rule_hits", rule.hitCount.map(String.init), monospaced: true),
            value("rule.hit-at", "traffic.rule_hit_at", WorkbenchDataFormat.reportedTimestamp(rule.hitAt), monospaced: true),
            value("rule.miss-count", "traffic.rule_misses", rule.missCount.map(String.init), monospaced: true),
            value("rule.miss-at", "traffic.rule_miss_at", WorkbenchDataFormat.reportedTimestamp(rule.missAt), monospaced: true),
            value(
                "rule.hit-rate",
                "traffic.rule_hit_rate",
                rule.hitRate?.formatted(.percent.precision(.fractionLength(0...1))),
                monospaced: true
            ),
        ]
    }

    static func ruleMetadata(
        _ row: WorkbenchRuleRow
    ) -> [WorkbenchDataInspectorValue] {
        [
            value("rule.extra-fields", "traffic.rule_extra_fields", row.rule.additionalExtraText, monospaced: true),
            value("rule.metadata-fields", "routing.additional_fields", row.rule.additionalMetadataText, monospaced: true),
        ]
    }

}

// MARK: - Rule projection

struct WorkbenchRuleRow: Identifiable, Equatable {
    let id: String
    let identityFamily: String
    let sourceIndex: Int
    let rule: RuleViewState
    let statusText: String
    let activeConnections: Int
    let indexText: String
    let indexSortValue: Int
    let typeText: String
    let definitionTitleText: String
    let definitionDetailText: String
    let targetText: String
    let activeConnectionsText: String
    let hitCountText: String
    let activityText: String
    let activityAccessibilityText: String
    let activeConnectionsAccessibilityText: String
    let hitCountAccessibilityText: String
    let searchText: String

    var payload: String { rule.payload }
    var type: String { rule.type }
    var proxy: String { rule.proxy }
    var hitCount: Int { rule.hitCount ?? -1 }
    var size: Int { rule.size ?? -1 }
}

struct WorkbenchRuleConnectionIndex: Equatable {
    private struct ExactKey: Hashable {
        let type: String
        let payload: String
    }

    private var exact: [ExactKey: Int] = [:]
    private var payloads: [String: Int] = [:]
    private var typesWithoutPayload: [String: Int] = [:]

    init(connections: [ConnectionSnapshot] = []) {
        for connection in connections {
            let type = connection.rule?.dataNonEmpty
            let payload = connection.rulePayload?.dataNonEmpty

            if let payload {
                payloads[payload, default: 0] += 1
                if let type {
                    exact[ExactKey(type: type, payload: payload), default: 0] += 1
                }
            } else if let type {
                typesWithoutPayload[type, default: 0] += 1
            }
        }
    }

    func count(for rule: RuleViewState) -> Int {
        if let payload = rule.payload.dataNonEmpty {
            if let type = rule.type.dataNonEmpty,
               let exactCount = exact[ExactKey(type: type, payload: payload)] {
                return exactCount
            }
            return payloads[payload] ?? 0
        }

        guard let type = rule.type.dataNonEmpty else { return 0 }
        return typesWithoutPayload[type] ?? 0
    }
}

struct WorkbenchRuleConnectionIndexCache: Equatable {
    private struct Key: Equatable {
        let controllerID: RouterProfile.ID?
        let generation: UUID
        let revision: UInt64
    }

    private var key: Key?
    private(set) var index = WorkbenchRuleConnectionIndex()
    private(set) var rebuildCount = 0

    mutating func resolve(
        connections: [ConnectionSnapshot],
        controllerID: RouterProfile.ID?,
        generation: UUID,
        revision: UInt64
    ) -> WorkbenchRuleConnectionIndex {
        let nextKey = Key(
            controllerID: controllerID,
            generation: generation,
            revision: revision
        )
        guard key != nextKey else { return index }

        key = nextKey
        index = WorkbenchRuleConnectionIndex(connections: connections)
        rebuildCount += 1
        return index
    }
}

enum WorkbenchRuleProjection {
    static func rows(
        from rules: [RuleViewState],
        connections: [ConnectionSnapshot],
        language: AppLanguage
    ) -> [WorkbenchRuleRow] {
        rows(
            from: rules,
            connectionIndex: WorkbenchRuleConnectionIndex(connections: connections),
            language: language
        )
    }

    static func rows(
        from rules: [RuleViewState],
        connectionIndex: WorkbenchRuleConnectionIndex,
        language: AppLanguage
    ) -> [WorkbenchRuleRow] {
        var identities = WorkbenchStableRowIdentityBuilder(
            reportedIDs: rules.map(\.id)
        )
        return rules.enumerated().map { index, rule in
            let statusText = statusText(for: rule, language: language)
            let definitionTitleText = WorkbenchDataFormat.reported(
                rule.payload,
                language: language
            )
            let typeText = WorkbenchDataFormat.reported(
                rule.type,
                language: language
            )
            let indexSortValue = rule.index ?? index + 1
            let indexText = String(indexSortValue)
            let definitionDetailText = WorkbenchDataFormat.joined([
                typeText,
                "#\(indexText)",
            ]) ?? typeText
            let targetText = WorkbenchDataFormat.reported(
                rule.proxy,
                language: language
            )
            let activeConnections = connectionIndex.count(for: rule)
            let activeConnectionsText = String(activeConnections)
            let hitCountText = WorkbenchDataFormat.reported(
                rule.hitCount.map(String.init),
                language: language
            )
            let activeConnectionsTitle = MicaStrings.localizedKey(
                "dashboard.active_sessions",
                language: language
            )
            let hitCountTitle = MicaStrings.localizedKey(
                "traffic.rule_hits",
                language: language
            )
            let activityText = "\(activeConnectionsText) · \(hitCountText)"
            let activeConnectionsAccessibilityText = "\(activeConnectionsTitle): \(activeConnectionsText)"
            let hitCountAccessibilityText = "\(hitCountTitle): \(hitCountText)"
            let identity = identities.make(
                reportedID: rule.id,
                fallbackComponents: [
                    rule.index.map(String.init) ?? "", rule.type, rule.payload, rule.proxy,
                ]
            )
            return WorkbenchRuleRow(
                id: identity.id,
                identityFamily: identity.family,
                sourceIndex: index,
                rule: rule,
                statusText: statusText,
                activeConnections: activeConnections,
                indexText: indexText,
                indexSortValue: indexSortValue,
                typeText: typeText,
                definitionTitleText: definitionTitleText,
                definitionDetailText: definitionDetailText,
                targetText: targetText,
                activeConnectionsText: activeConnectionsText,
                hitCountText: hitCountText,
                activityText: activityText,
                activityAccessibilityText: "\(activeConnectionsAccessibilityText), \(hitCountAccessibilityText)",
                activeConnectionsAccessibilityText: activeConnectionsAccessibilityText,
                hitCountAccessibilityText: hitCountAccessibilityText,
                searchText: [
                    rule.id, rule.type, rule.payload, rule.proxy, statusText,
                    rule.index.map(String.init) ?? "", rule.hitCount.map(String.init) ?? "",
                    rule.hitAt ?? "", rule.missCount.map(String.init) ?? "",
                    rule.missAt ?? "", rule.additionalExtraText ?? "",
                    rule.additionalMetadataText ?? "",
                ].joined(separator: "\n")
            )
        }
    }

    static func visibleRows(
        from rows: [WorkbenchRuleRow],
        query: String,
        sortOrder: [KeyPathComparator<WorkbenchRuleRow>]
    ) -> [WorkbenchRuleRow] {
        let query = query.dataNonEmpty
        let filtered = rows.filter { row in
            guard let query else { return true }
            return WorkbenchDataSearch.contains(query, in: row.searchText)
        }
        return sortOrder.isEmpty ? filtered : filtered.sorted(using: sortOrder)
    }

    private static func statusText(for rule: RuleViewState, language: AppLanguage) -> String {
        guard let disabled = rule.disabled else {
            return MicaStrings.localizedKey("overview.config_not_reported", language: language)
        }
        return MicaStrings.localizedKey(
            disabled ? "traffic.rule_status_disabled" : "traffic.rule_status_enabled",
            language: language
        )
    }

    static func updatingActiveConnections(
        in row: WorkbenchRuleRow,
        to activeConnections: Int,
        language: AppLanguage
    ) -> WorkbenchRuleRow {
        guard row.activeConnections != activeConnections else { return row }
        let activeConnectionsAccessibilityText = "\(MicaStrings.localizedKey("dashboard.active_sessions", language: language)): \(activeConnections)"
        return WorkbenchRuleRow(
            id: row.id,
            identityFamily: row.identityFamily,
            sourceIndex: row.sourceIndex,
            rule: row.rule,
            statusText: row.statusText,
            activeConnections: activeConnections,
            indexText: row.indexText,
            indexSortValue: row.indexSortValue,
            typeText: row.typeText,
            definitionTitleText: row.definitionTitleText,
            definitionDetailText: row.definitionDetailText,
            targetText: row.targetText,
            activeConnectionsText: String(activeConnections),
            hitCountText: row.hitCountText,
            activityText: "\(activeConnections) · \(row.hitCountText)",
            activityAccessibilityText: "\(activeConnectionsAccessibilityText), \(row.hitCountAccessibilityText)",
            activeConnectionsAccessibilityText: activeConnectionsAccessibilityText,
            hitCountAccessibilityText: row.hitCountAccessibilityText,
            searchText: row.searchText
        )
    }

    static func accessibilitySummary(
        for row: WorkbenchRuleRow,
        localization: MicaStrings.LocalizationContext
    ) -> String {
        [
            WorkbenchAccessibilitySummary.field(
                "dashboard.col_index", value: row.indexText, localization: localization
            ),
            WorkbenchAccessibilitySummary.field(
                "dashboard.col_type", value: row.rule.type, localization: localization
            ),
            WorkbenchAccessibilitySummary.field(
                "dashboard.col_payload", value: row.rule.payload, localization: localization
            ),
            WorkbenchAccessibilitySummary.field(
                "dashboard.col_proxy", value: row.rule.proxy, localization: localization
            ),
            WorkbenchAccessibilitySummary.field(
                "dashboard.col_status", value: row.statusText, localization: localization
            ),
            row.activeConnectionsAccessibilityText,
            row.hitCountAccessibilityText,
        ].joined(separator: ", ")
    }

}

enum WorkbenchRuleProjectionUpdate {
    case source
    case connectionStructure
    case visibleOnly
}

enum WorkbenchRulePolicyTargetResolver {
    static func resolve(
        target: String,
        catalog: PolicyGroupCatalogSnapshot,
        visibility: GlobalGroupVisibility
    ) -> ProxyGroupOccurrence? {
        guard let target = target.dataNonEmpty,
              target.caseInsensitiveCompare("DIRECT")
                != ComparisonResult.orderedSame,
              target.caseInsensitiveCompare("REJECT")
                != ComparisonResult.orderedSame else {
            return nil
        }

        return ProxyProjection.arrangedGroups(
            catalog.groups,
            mode: catalog.mode,
            visibility: visibility
        ).first {
            $0.group.id == target
        }
    }
}

enum WorkbenchRuleNavigationResolver {
    static func resolve(
        _ selection: WorkbenchRuleNavigationSelection,
        controllerID: RouterProfile.ID,
        generation: UUID,
        in rows: [WorkbenchRuleRow]
    ) -> WorkbenchRuleRow? {
        guard selection.controllerID == controllerID,
              selection.generation == generation,
              rows.indices.contains(selection.sourceIndex) else {
            return nil
        }
        let row = rows[selection.sourceIndex]
        guard selection.matches(
            sourceIndex: row.sourceIndex,
            reportedRuleID: row.rule.id,
            type: row.rule.type,
            payload: row.rule.payload
        ) else {
            return nil
        }
        return row
    }
}

enum WorkbenchRuleInspectorResolver {
    static func resolve(
        type: String,
        payload: String,
        in rows: [WorkbenchRuleRow]
    ) -> WorkbenchRuleRow? {
        guard type.dataNonEmpty != nil, payload.dataNonEmpty != nil else {
            return nil
        }

        let matches = rows.filter {
            $0.rule.type == type && $0.rule.payload == payload
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

struct WorkbenchRuleDecisionPathProjection: Equatable {
    let type: String
    let payload: String
    let target: String
    let status: String
    let activeConnections: Int
    let hitCount: Int?
    let missCount: Int?
    let isDisabled: Bool?

    init(row: WorkbenchRuleRow) {
        type = row.rule.type
        payload = row.rule.payload
        target = row.rule.proxy
        status = row.statusText
        activeConnections = row.activeConnections
        hitCount = row.rule.hitCount
        missCount = row.rule.missCount
        isDisabled = row.rule.disabled
    }
}

struct WorkbenchRuleProjectionCache {
    private(set) var allRows: [WorkbenchRuleRow] = []
    private(set) var visibleRows: [WorkbenchRuleRow] = []
    private(set) var staticProjectionCount = 0
    private(set) var activeCountProjectionCount = 0
    private(set) var staticRowProjectionCount = 0
    private(set) var activeCountRowProjectionCount = 0
    private(set) var filterProjectionCount = 0
    private(set) var sortProjectionCount = 0

    private var connectionIndexCache = WorkbenchRuleConnectionIndexCache()
    private var structureRevision: UInt64?
    private var query: String?
    private var sortOrder: [KeyPathComparator<WorkbenchRuleRow>] = []
    private var filteredSourceIndices: [Int] = []
    private var rowIndexByID: [String: Int] = [:]

    var connectionIndexRebuildCount: Int {
        connectionIndexCache.rebuildCount
    }

    @discardableResult
    mutating func project(
        update: WorkbenchRuleProjectionUpdate,
        rules: [RuleViewState],
        connections: [ConnectionSnapshot],
        controllerID: RouterProfile.ID?,
        generation: UUID,
        structureRevision: UInt64,
        query: String,
        sortOrder: [KeyPathComparator<WorkbenchRuleRow>],
        language: AppLanguage,
        isActive: Bool = true
    ) -> Bool {
        guard isActive else { return false }

        var sourceChanged = false
        var activeCountsChanged = false

        switch update {
        case .source:
            let connectionIndex = connectionIndexCache.resolve(
                connections: connections,
                controllerID: controllerID,
                generation: generation,
                revision: structureRevision
            )
            replaceSource(
                WorkbenchRuleProjection.rows(
                    from: rules,
                    connectionIndex: connectionIndex,
                    language: language
                )
            )
            staticProjectionCount += 1
            staticRowProjectionCount += allRows.count
            self.structureRevision = structureRevision
            sourceChanged = true

        case .connectionStructure:
            guard self.structureRevision != structureRevision else { break }
            let connectionIndex = connectionIndexCache.resolve(
                connections: connections,
                controllerID: controllerID,
                generation: generation,
                revision: structureRevision
            )
            if allRows.count == rules.count {
                activeCountsChanged = replaceActiveCounts(
                    using: connectionIndex,
                    language: language
                )
            } else {
                replaceSource(
                    WorkbenchRuleProjection.rows(
                        from: rules,
                        connectionIndex: connectionIndex,
                        language: language
                    )
                )
                staticProjectionCount += 1
                staticRowProjectionCount += allRows.count
                sourceChanged = true
            }
            self.structureRevision = structureRevision

        case .visibleOnly:
            break
        }

        let visibleChanged = updateVisibleRows(
            query: query,
            sortOrder: sortOrder,
            sourceChanged: sourceChanged,
            activeCountsChanged: activeCountsChanged
        )
        return visibleChanged
    }

    func row(id: String?) -> WorkbenchRuleRow? {
        guard let id, let index = rowIndexByID[id], allRows.indices.contains(index) else {
            return nil
        }
        return allRows[index]
    }

    mutating func reset() {
        self = WorkbenchRuleProjectionCache()
    }

    private mutating func replaceSource(_ rows: [WorkbenchRuleRow]) {
        allRows = rows
        rowIndexByID = Dictionary(
            uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) }
        )
    }

    private mutating func replaceActiveCounts(
        using connectionIndex: WorkbenchRuleConnectionIndex,
        language: AppLanguage
    ) -> Bool {
        var nextRows = allRows
        var changedRows = 0
        for index in allRows.indices {
            let next = WorkbenchRuleProjection.updatingActiveConnections(
                in: allRows[index],
                to: connectionIndex.count(for: allRows[index].rule),
                language: language
            )
            if next != allRows[index] {
                nextRows[index] = next
                changedRows += 1
            }
        }
        allRows = nextRows
        activeCountProjectionCount += 1
        activeCountRowProjectionCount += changedRows
        return changedRows > 0
    }

    private mutating func updateVisibleRows(
        query: String,
        sortOrder: [KeyPathComparator<WorkbenchRuleRow>],
        sourceChanged: Bool,
        activeCountsChanged: Bool
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
            visibleRows = filteredSourceIndices.map { allRows[$0] }
            if !sortOrder.isEmpty {
                visibleRows.sort(using: sortOrder)
                sortProjectionCount += 1
            }
        } else if activeCountsChanged {
            if sortOrder.contains(where: {
                $0.keyPath == \WorkbenchRuleRow.activeConnections
            }) {
                visibleRows = filteredSourceIndices.map { allRows[$0] }
                visibleRows.sort(using: sortOrder)
                sortProjectionCount += 1
            } else {
                visibleRows = visibleRows.compactMap { row in
                    guard allRows.indices.contains(row.sourceIndex) else { return nil }
                    return allRows[row.sourceIndex]
                }
            }
        }

        self.query = normalizedQuery
        self.sortOrder = sortOrder
        return sourceChanged || filterChanged || sortChanged || activeCountsChanged
    }
}
