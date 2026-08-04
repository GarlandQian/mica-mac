import Foundation
import MicaCore
import SwiftUI

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
    let definitionTitleText: String
    let definitionDetailText: String
    let targetText: String
    let activeConnectionsText: String
    let hitCountText: String
    let stackedMetricsText: String
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
            let definitionDetailText = WorkbenchDataFormat.joined([
                typeText,
                rule.index.map { "#\($0)" },
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
                definitionTitleText: definitionTitleText,
                definitionDetailText: definitionDetailText,
                targetText: targetText,
                activeConnectionsText: activeConnectionsText,
                hitCountText: hitCountText,
                stackedMetricsText: "\(activeConnectionsText) · \(hitCountText)",
                activeConnectionsAccessibilityText: "\(activeConnectionsTitle): \(activeConnectionsText)",
                hitCountAccessibilityText: "\(hitCountTitle): \(hitCountText)",
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
            return row.searchText.localizedCaseInsensitiveContains(query)
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
        return WorkbenchRuleRow(
            id: row.id,
            identityFamily: row.identityFamily,
            sourceIndex: row.sourceIndex,
            rule: row.rule,
            statusText: row.statusText,
            activeConnections: activeConnections,
            definitionTitleText: row.definitionTitleText,
            definitionDetailText: row.definitionDetailText,
            targetText: row.targetText,
            activeConnectionsText: String(activeConnections),
            hitCountText: row.hitCountText,
            stackedMetricsText: "\(activeConnections) · \(row.hitCountText)",
            activeConnectionsAccessibilityText: "\(MicaStrings.localizedKey("dashboard.active_sessions", language: language)): \(activeConnections)",
            hitCountAccessibilityText: row.hitCountAccessibilityText,
            searchText: row.searchText
        )
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
        type: String,
        payload: String,
        in rules: [RuleViewState]
    ) -> RuleViewState? {
        guard type.dataNonEmpty != nil, payload.dataNonEmpty != nil else {
            return nil
        }

        let matches = rules.filter {
            $0.type == type && $0.payload == payload
        }
        return matches.count == 1 ? matches[0] : nil
    }

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
                return allRows[index].searchText.localizedCaseInsensitiveContains(normalizedQuery)
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

// MARK: - Rules

struct WorkbenchRulesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language
    @EnvironmentObject private var preferences: AppPreferencesStore

    @Binding var destination: WorkbenchDestination
    @Binding var searchText: String

    @State private var projectionCache = WorkbenchRuleProjectionCache()
    @State private var selectedRowID: String?
    @State private var sortOrder: [KeyPathComparator<WorkbenchRuleRow>] = []
    @State private var restoredScrollAnchorID: String?
    @State private var scrollRequest: WorkbenchDataScrollRequest?
    @State private var tableInteraction = WorkbenchDataInteractionCoordinator()
    @State private var isProjectionActive = false

    private static let widthBudget = WorkbenchDataWidthBudget(
        fullMinimum: 980,
        compactMinimum: 520
    )

    var body: some View {
        WorkbenchDataBrowserScaffold(
            staleMessage: localizedStaleMessage,
            commands: { commandBar },
            supplementary: {
                if let selectedRow {
                    WorkbenchRuleDecisionPathRail(
                        projection: WorkbenchRuleDecisionPathProjection(
                            row: selectedRow
                        ),
                        targetIsNavigable: policyTarget(for: selectedRow) != nil,
                        onOpenTarget: {
                            openTargetPolicyGroup(for: selectedRow)
                        }
                    )
                }
            }
        ) {
            pageContent
        }
        .onAppear {
            isProjectionActive = true
            restoreWorkspace()
            rebuildRows(reconcileSelection: true, update: .source)
            consumeRuleNavigation()
        }
        .onDisappear {
            isProjectionActive = false
        }
        .onChange(of: appModel.selectedRouterID) {
            projectionCache.reset()
            scrollRequest = nil
            restoreWorkspace()
            rebuildRows(reconcileSelection: true, update: .source)
            consumeRuleNavigation()
        }
        .onChange(of: appModel.controllerSessionPresentation.generation) {
            projectionCache.reset()
            scrollRequest = nil
            restoreWorkspace()
            rebuildRows(reconcileSelection: true, update: .source)
            consumeRuleNavigation()
        }
        .onChange(of: appModel.routingCatalog.rules) {
            rebuildRows(reconcileSelection: true, update: .source)
            consumeRuleNavigation()
        }
        .onChange(of: appModel.connectionsCatalog.structureRevision) {
            rebuildRows(reconcileSelection: true, update: .connectionStructure)
        }
        .onChange(of: searchText) {
            rebuildRows(reconcileSelection: true, update: .visibleOnly)
            consumeRuleNavigation()
        }
        .onChange(of: sortOrder) {
            persistSortOrder()
            rebuildRows(reconcileSelection: true, update: .visibleOnly)
        }
        .onChange(of: language) {
            rebuildRows(reconcileSelection: true, update: .source)
            consumeRuleNavigation()
        }
        .onChange(of: selectedRowID) { _, selection in
            persistSelection(selection)
        }
    }

    private var commandBar: some View {
        WorkbenchCommandBar {
            WorkbenchCommandSummary(
                symbolName: "list.bullet.rectangle",
                titleKey: "dashboard.tab_rules",
                value: String(rows.count),
                detail: nil
            )
        } controls: {
            WorkbenchDataActivityIndicator(
                isActive: appModel.reloadingRules || appModel.rulesSnapshotState.isLoading,
                titleKey: "snapshot.loading"
            )
        } commands: {
            WorkbenchIconCommand(
                titleKey: "action.reload_rules",
                systemImage: "arrow.clockwise",
                isEnabled: canReload
            ) {
                appModel.reloadRules()
            }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch state {
        case .noController:
            WorkbenchStateView(
                kind: .noController,
                titleKey: "dashboard.connect_router",
                detailKey: "dashboard.connect_router_message"
            )
        case .loading:
            WorkbenchStateView(
                kind: .loading,
                titleKey: "snapshot.loading",
                detailKey: "traffic.rules_loading_message"
            )
        case .unsupported:
            WorkbenchStateView(
                kind: .unsupported,
                titleKey: "traffic.rules_unsupported_title",
                detailKey: "traffic.rules_unsupported_message"
            )
        case .empty:
            WorkbenchStateView(
                kind: .empty,
                titleKey: "dashboard.no_rules_snapshot",
                detailKey: "traffic.rules_empty_message"
            )
        case .filterEmpty:
            WorkbenchStateView(
                kind: .filterEmpty,
                titleKey: "dashboard.no_matching_rules",
                detailKey: "traffic.empty_filtered"
            )
        case .failed(let message):
            WorkbenchStateView(
                kind: .failed,
                titleKey: "traffic.data_failed_title",
                message: message,
                actionTitleKey: canReload ? "action.reload_rules" : nil,
                isActionEnabled: canReload,
                action: canReload ? { appModel.reloadRules() } : nil
            )
        case .content:
            ruleTable
                .inspector(isPresented: inspectorPresented) {
                    WorkbenchRuleInspector(
                        row: selectedRow,
                        canMutate: selectedRow.map(canMutate) ?? false,
                        isUpdating: appModel.updatingRuleID == selectedRow?.rule.id,
                        failure: selectedRow.flatMap {
                            appModel.ruleUpdateFailures[$0.rule.id]
                        },
                        close: { selectedRowID = nil },
                        disabled: Binding(
                            get: { selectedRow?.rule.disabled ?? false },
                            set: { disabled in
                                guard let rule = selectedRow?.rule else { return }
                                appModel.setRuleDisabled(rule, disabled: disabled)
                            }
                        )
                    )
                    .inspectorColumnWidth(
                        min: MicaBounds.inspectorMin,
                        ideal: MicaBounds.inspectorIdeal,
                        max: MicaBounds.inspectorMax
                    )
                }
        }
    }

    private var ruleTable: some View {
        let controllerID = appModel.selectedRouterID
        let generation = appModel.controllerSessionPresentation.generation
        return WorkbenchDataTableViewport(
            generation: generation,
            restorationID: restoredScrollAnchorID,
            request: scrollRequest,
            interaction: tableInteraction,
            onAnchorCommit: { anchorID in
                persistScrollAnchor(
                    anchorID,
                    controllerID: controllerID,
                    generation: generation
                )
            }
        ) {
            WorkbenchDataResponsive(budget: Self.widthBudget) { mode in
                Table(rows, selection: $selectedRowID, sortOrder: $sortOrder) {
                    switch mode {
                    case .full:
                        TableColumn(
                            MicaStrings.localizedKey("dashboard.col_payload", language: language),
                            value: \.payload
                        ) { row in
                            ruleIdentity(row)
                        }
                        .width(min: 270, ideal: 420)

                        TableColumn(
                            MicaStrings.localizedKey("dashboard.col_proxy", language: language),
                            value: \.proxy
                        ) { row in
                            WorkbenchDataText(value: row.targetText)
                        }
                        .width(min: 140, ideal: 210)

                        TableColumn(
                            MicaStrings.localizedKey("dashboard.active_sessions", language: language),
                            value: \.activeConnections
                        ) { row in
                            WorkbenchDataMetric(value: row.activeConnectionsText)
                        }
                        .width(min: 82, ideal: 104)

                        TableColumn(
                            MicaStrings.localizedKey("traffic.rule_hits", language: language),
                            value: \.hitCount
                        ) { row in
                            WorkbenchDataMetric(value: row.hitCountText)
                        }
                        .width(min: 72, ideal: 88)

                        TableColumn(MicaStrings.localizedKey("dashboard.col_status", language: language)) { row in
                            ruleStateCell(row)
                        }
                        .width(min: 150, ideal: 180)

                    case .compact:
                        TableColumn(
                            MicaStrings.localizedKey("traffic.rule_section_definition", language: language),
                            value: \.payload
                        ) { row in
                            ruleIdentity(row)
                        }
                        .width(min: 260, ideal: 420)

                        TableColumn(MicaStrings.localizedKey("traffic.rule_section_statistics", language: language)) { row in
                            ruleCompactSummary(row)
                        }
                        .width(min: 260, ideal: 340)

                    case .stacked:
                        TableColumn(
                            MicaStrings.localizedKey("dashboard.tab_rules", language: language),
                            value: \.payload
                        ) { row in
                            ruleStackedRow(row)
                        }
                        .width(min: 220, ideal: 520)
                    }
                }
                .micaWorkbenchTable(
                    accessibilityLabel: MicaStrings.localizedKey(
                        "dashboard.tab_rules",
                        language: language
                    )
                )
            }
        }
    }

    private func ruleStateCell(_ row: WorkbenchRuleRow) -> some View {
        HStack(spacing: MicaSpacing.row) {
            ruleStateLabel(row)
            Spacer(minLength: MicaSpacing.tight)
            ruleAction(row)
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
    }

    private func ruleCompactSummary(_ row: WorkbenchRuleRow) -> some View {
        HStack(spacing: MicaSpacing.row) {
            VStack(alignment: .leading, spacing: 1) {
                WorkbenchDataText(value: row.targetText)

                HStack(spacing: MicaSpacing.module) {
                    ruleStateLabel(row)
                    ruleMetric(
                        value: row.activeConnectionsText,
                        systemImage: "point.3.connected.trianglepath.dotted",
                        accessibilityText: row.activeConnectionsAccessibilityText
                    )
                    ruleMetric(
                        value: row.hitCountText,
                        systemImage: "scope",
                        accessibilityText: row.hitCountAccessibilityText
                    )
                }
            }

            Spacer(minLength: MicaSpacing.tight)
            ruleAction(row)
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
    }

    private func ruleStackedRow(_ row: WorkbenchRuleRow) -> some View {
        HStack(spacing: MicaSpacing.module) {
            ruleIdentity(row)
            Spacer(minLength: MicaSpacing.row)

            VStack(alignment: .trailing, spacing: 1) {
                WorkbenchDataText(
                    value: row.targetText,
                    style: .caption,
                    alignment: .trailing
                )

                HStack(spacing: MicaSpacing.row) {
                    ruleStateLabel(row)
                    WorkbenchDataMetric(
                        value: row.stackedMetricsText,
                        tone: .secondary
                    )
                }
            }

            ruleAction(row)
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height
        )
    }

    private func ruleStateLabel(_ row: WorkbenchRuleRow) -> some View {
        HStack(spacing: MicaSpacing.tight) {
            Circle()
                .fill(ruleStatusTint(row.rule))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(verbatim: row.statusText)
                .micaFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func ruleMetric(
        value: String,
        systemImage: String,
        accessibilityText: String
    ) -> some View {
        Label {
            Text(verbatim: value)
                .monospacedDigit()
        } icon: {
            Image(systemName: systemImage)
        }
        .micaFont(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func ruleAction(_ row: WorkbenchRuleRow) -> some View {
        if appModel.updatingRuleID == row.rule.id {
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: MicaBounds.iconControlSize, minHeight: MicaBounds.iconControlSize)
        } else if row.rule.hasMutableExtra, row.rule.index != nil {
            WorkbenchIconCommand(
                titleKey: "action.set_rule_state",
                systemImage: row.rule.disabled == true ? "play.circle" : "pause.circle",
                isEnabled: canMutate(row)
            ) {
                appModel.setRuleDisabled(row.rule, disabled: !(row.rule.disabled ?? false))
            }
        }
    }

    private func ruleIdentity(_ row: WorkbenchRuleRow) -> some View {
        WorkbenchDataPrimaryCell(
            title: row.definitionTitleText,
            detail: row.definitionDetailText,
            systemImage: "arrow.triangle.branch",
            tint: .secondary,
            titleIsMonospaced: true,
            detailIsMonospaced: true
        )
    }

    private func rebuildRows(
        reconcileSelection: Bool,
        update: WorkbenchRuleProjectionUpdate
    ) {
        guard isProjectionActive else { return }
        let previousRows = allRows
        let previousSelection = selectedRowID
        projectionCache.project(
            update: update,
            rules: appModel.routingCatalog.rules,
            connections: appModel.connectionsCatalog.connections,
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation,
            structureRevision: appModel.connectionsCatalog.structureRevision,
            query: searchText,
            sortOrder: sortOrder,
            language: language,
            isActive: isProjectionActive
        )

        if reconcileSelection {
            selectedRowID = WorkbenchDataSelection.reconciled(
                previousSelection,
                previousRows: previousRows,
                nextVisibleRows: rows,
                identityFamily: \.identityFamily
            )
        }
    }

    private var state: WorkbenchDataState {
        WorkbenchDataStateResolver.endpoint(
            hasController: appModel.selectedRouter != nil,
            isSupported: appModel.selectedUnifiedCapabilities.rules,
            sourceCount: allRows.count,
            visibleCount: rows.count,
            isFiltering: searchText.dataNonEmpty != nil,
            endpointStatus: appModel.controllerHealth.status(for: .rules),
            snapshotState: appModel.rulesSnapshotState,
            sessionState: appModel.controllerSessionPresentation.state,
            language: language
        )
    }

    private var canReload: Bool {
        appModel.canRefreshSelectedRouter && appModel.supportsUnifiedAction(.reloadRules)
    }

    private func canMutate(_ row: WorkbenchRuleRow) -> Bool {
        row.rule.hasMutableExtra
            && row.rule.index != nil
            && appModel.canRefreshSelectedRouter
            && appModel.supportsUnifiedAction(.setRuleDisabled)
    }

    private var selectedRow: WorkbenchRuleRow? {
        projectionCache.row(id: selectedRowID)
    }

    private func policyTarget(
        for row: WorkbenchRuleRow
    ) -> ProxyGroupOccurrence? {
        WorkbenchRulePolicyTargetResolver.resolve(
            target: row.rule.proxy,
            catalog: appModel.policyGroupCatalog,
            visibility: preferences.globalGroupVisibility
        )
    }

    private func openTargetPolicyGroup(for row: WorkbenchRuleRow) {
        let groups = ProxyProjection.arrangedGroups(
            appModel.policyGroupCatalog.groups,
            mode: appModel.policyGroupCatalog.mode,
            visibility: preferences.globalGroupVisibility
        )
        guard let target = WorkbenchRulePolicyTargetResolver.resolve(
            target: row.rule.proxy,
            catalog: appModel.policyGroupCatalog,
            visibility: preferences.globalGroupVisibility
        ) else {
            return
        }

        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { workspace in
            workspace = ProxyWorkspaceProjection.opening(
                target.id,
                in: workspace,
                groups: groups,
                preferredMemberID: nil
            )
        }
        destination = .proxies
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { selectedRowID != nil },
            set: { if !$0 { selectedRowID = nil } }
        )
    }

    private func ruleStatusTint(_ rule: RuleViewState) -> Color {
        switch rule.disabled {
        case true: MicaDesignTokens.signalAmber
        case false: MicaDesignTokens.signalMint
        case nil: .secondary
        }
    }

    private var localizedStaleMessage: String? {
        state.staleMessage.map {
            MicaStrings.localized("data.stale_detail \($0)", language: language)
        }
    }

    private func restoreWorkspace() {
        let controllerID = appModel.selectedRouterID
        let generation = appModel.controllerSessionPresentation.generation
        if let controllerID {
            workspaceStore.activateSession(
                controllerID: controllerID,
                generation: generation
            )
        }
        let workspace = workspaceStore.workspace(
            controllerID: controllerID,
            destination: .rules
        )
        sortOrder = Self.ruleSortOrder(from: workspace.sort)
        selectedRowID = workspace.selectedItemID
        restoredScrollAnchorID = controllerID.flatMap {
            workspaceStore.scrollAnchorID(
                controllerID: $0,
                generation: generation,
                destination: .rules
            )
        }
    }

    private func persistSelection(_ selection: String?) {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .rules
        ) { workspace in
            workspace.selectedItemID = selection
        }
    }

    private func persistScrollAnchor(
        _ anchorID: String?,
        controllerID: RouterProfile.ID?,
        generation: UUID
    ) {
        guard let controllerID,
              appModel.selectedRouterID == controllerID,
              appModel.controllerSessionPresentation.generation == generation else {
            return
        }
        workspaceStore.updateScrollAnchor(
            controllerID: controllerID,
            generation: generation,
            destination: .rules,
            anchorID: anchorID
        )
    }

    private func persistSortOrder() {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .rules
        ) { workspace in
            workspace.sort = sortOrder.compactMap(Self.ruleWorkspaceSort)
        }
    }

    private func consumeRuleNavigation() {
        guard let controllerID = appModel.selectedRouterID else { return }
        let generation = appModel.controllerSessionPresentation.generation
        let workspace = workspaceStore.workspace(
            controllerID: controllerID,
            destination: .rules
        )
        guard let pending = workspace.pendingRuleSelection,
              pending.controllerID == controllerID,
              pending.generation == generation,
              let row = WorkbenchRuleNavigationResolver.resolve(
                  type: pending.type,
                  payload: pending.payload,
                  in: allRows
              ) else {
            return
        }

        if !rows.contains(where: { $0.id == row.id }), searchText.dataNonEmpty != nil {
            searchText = ""
            rebuildRows(reconcileSelection: false, update: .visibleOnly)
        }

        guard rows.contains(where: { $0.id == row.id }),
              workspaceStore.consumeRuleNavigation(
                  controllerID: controllerID,
                  generation: generation
              ) != nil else {
            return
        }

        selectedRowID = row.id
        scrollRequest = WorkbenchDataScrollRequest(id: row.id)
    }

    private static func ruleSortOrder(
        from workspaceSort: [WorkbenchWorkspaceSort]
    ) -> [KeyPathComparator<WorkbenchRuleRow>] {
        workspaceSort.compactMap { item -> KeyPathComparator<WorkbenchRuleRow>? in
            let order: SortOrder = item.ascending ? .forward : .reverse
            switch item.field {
            case "payload": return KeyPathComparator(\WorkbenchRuleRow.payload, order: order)
            case "type": return KeyPathComparator(\WorkbenchRuleRow.type, order: order)
            case "proxy": return KeyPathComparator(\WorkbenchRuleRow.proxy, order: order)
            case "activeConnections": return KeyPathComparator(\WorkbenchRuleRow.activeConnections, order: order)
            case "hitCount": return KeyPathComparator(\WorkbenchRuleRow.hitCount, order: order)
            default: return nil
            }
        }
    }

    private static func ruleWorkspaceSort(
        _ comparator: KeyPathComparator<WorkbenchRuleRow>
    ) -> WorkbenchWorkspaceSort? {
        let field: String
        if comparator.keyPath == \WorkbenchRuleRow.payload {
            field = "payload"
        } else if comparator.keyPath == \WorkbenchRuleRow.type {
            field = "type"
        } else if comparator.keyPath == \WorkbenchRuleRow.proxy {
            field = "proxy"
        } else if comparator.keyPath == \WorkbenchRuleRow.activeConnections {
            field = "activeConnections"
        } else if comparator.keyPath == \WorkbenchRuleRow.hitCount {
            field = "hitCount"
        } else {
            return nil
        }
        return WorkbenchWorkspaceSort(
            field: field,
            ascending: comparator.order == .forward
        )
    }

    private var allRows: [WorkbenchRuleRow] {
        projectionCache.allRows
    }

    private var rows: [WorkbenchRuleRow] {
        projectionCache.visibleRows
    }
}

private struct WorkbenchRuleDecisionPathRail: View {
    @Environment(\.micaAppLanguage) private var language

    let projection: WorkbenchRuleDecisionPathProjection
    let targetIsNavigable: Bool
    let onOpenTarget: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: MicaSpacing.module) {
                horizontalPath
                Spacer(minLength: MicaSpacing.section)
                statistics
            }

            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                compactPath
                statistics
            }
        }
        .padding(.horizontal, MicaSpacing.module)
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaDesignTokens.contentFill)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var horizontalPath: some View {
        HStack(spacing: MicaSpacing.row) {
            typeStep
            WorkbenchDecisionPathConnector()
            payloadStep
            WorkbenchDecisionPathConnector()
            targetStep
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactPath: some View {
        VStack(alignment: .leading, spacing: 0) {
            typeStep
            compactConnector
            payloadStep
            compactConnector
            targetStep
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactConnector: some View {
        Image(systemName: "chevron.down")
            .micaFont(.caption2, weight: .semibold)
            .foregroundStyle(.tertiary)
            .padding(.leading, 10)
            .accessibilityHidden(true)
    }

    private var typeStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "dashboard.col_type",
            value: reported(projection.type),
            systemImage: "line.3.horizontal.decrease.circle",
            tint: MicaDesignTokens.signalViolet,
            monospaced: true
        )
    }

    private var payloadStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "dashboard.col_payload",
            value: reported(projection.payload),
            systemImage: "scope",
            tint: MicaDesignTokens.signalCyan,
            monospaced: true
        )
    }

    private var targetStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "dashboard.col_proxy",
            value: reported(projection.target),
            systemImage: targetIsNavigable
                ? "arrow.right.circle"
                : "point.3.connected.trianglepath.dotted",
            tint: targetIsNavigable
                ? MicaDesignTokens.accent
                : .secondary,
            actionHelpKey: targetIsNavigable
                ? "traffic.open_target_policy"
                : nil,
            action: targetIsNavigable ? onOpenTarget : nil
        )
    }

    private var statistics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.section) {
                statusReadout
                activityReadout
                hitReadout
                missReadout
            }

            VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                HStack(spacing: MicaSpacing.section) {
                    statusReadout
                    activityReadout
                }
                HStack(spacing: MicaSpacing.section) {
                    hitReadout
                    missReadout
                }
            }
        }
    }

    private var statusReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "dashboard.col_status",
            value: projection.status,
            systemImage: "circle.fill",
            tint: statusTint,
            monospaced: false
        )
    }

    private var activityReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "dashboard.active_sessions",
            value: projection.activeConnections.formatted(),
            systemImage: "point.3.connected.trianglepath.dotted",
            tint: MicaDesignTokens.signalCyan
        )
    }

    private var hitReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "traffic.rule_hits",
            value: reported(projection.hitCount),
            systemImage: "scope",
            tint: MicaDesignTokens.signalMint
        )
    }

    private var missReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "traffic.rule_misses",
            value: reported(projection.missCount),
            systemImage: "circle.slash",
            tint: MicaDesignTokens.signalAmber
        )
    }

    private var statusTint: Color {
        switch projection.isDisabled {
        case true: MicaDesignTokens.signalAmber
        case false: MicaDesignTokens.signalMint
        case nil: .secondary
        }
    }

    private func reported(_ value: String?) -> String {
        value?.dataNonEmpty
            ?? MicaStrings.localizedKey(
                "overview.config_not_reported",
                language: language
            )
    }

    private func reported(_ value: Int?) -> String {
        value?.formatted()
            ?? MicaStrings.localizedKey(
                "overview.config_not_reported",
                language: language
            )
    }
}

private struct WorkbenchRuleInspector: View {
    @Environment(\.micaAppLanguage) private var language

    let row: WorkbenchRuleRow?
    let canMutate: Bool
    let isUpdating: Bool
    let failure: String?
    let close: () -> Void
    let disabled: Binding<Bool>

    var body: some View {
        if let row {
            let rule = row.rule
            WorkbenchDataInspectorShell(
                title: MicaStrings.localizedKey("traffic.detail_rule", language: language),
                subtitle: rule.index.map { "#\($0)" },
                statusText: row.statusText,
                statusTint: statusTint(rule),
                close: close
            ) {
                WorkbenchDataInspectorSection("traffic.rule_section_definition") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.ruleDefinition(row)
                    )
                }

                if rule.hasMutableExtra, rule.index != nil {
                    WorkbenchDataInspectorSection("traffic.rule_section_state") {
                        Toggle(
                            MicaStrings.localizedKey("traffic.rule_disabled", language: language),
                            isOn: disabled
                        )
                        .toggleStyle(.switch)
                        .disabled(!canMutate || isUpdating)
                        .frame(minHeight: MicaBounds.controlMinHeight)

                        if isUpdating {
                            ProgressView {
                                Text(MicaStrings.localizedKey("traffic.rule_updating", language: language))
                            }
                            .controlSize(.small)
                        }
                    }
                }

                if let failure {
                    WorkbenchDataInspectorSection("traffic.rule_section_error") {
                        Label {
                            Text(verbatim: failure)
                                .textSelection(.enabled)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(MicaDesignTokens.signalRed)
                        }
                    }
                }

                WorkbenchDataInspectorSection("traffic.rule_section_statistics") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.ruleStatistics(row)
                    )
                }

                WorkbenchDataInspectorSection("traffic.rule_section_metadata") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.ruleMetadata(row)
                    )
                }
            }
        }
    }

    private func statusTint(_ rule: RuleViewState) -> Color {
        switch rule.disabled {
        case true: MicaDesignTokens.signalAmber
        case false: MicaDesignTokens.signalMint
        case nil: .secondary
        }
    }
}
