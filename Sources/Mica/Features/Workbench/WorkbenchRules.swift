import Foundation
import MicaCore
import SwiftUI

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
    @State private var accessibilityCursor = WorkbenchAccessibilityWindowCursor()

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
            let projectionCacheBinding = $projectionCache
            let selectedRowIDBinding = $selectedRowID
            workspaceStore.ruleRowResolver = { type, payload in
                let cache = projectionCacheBinding.wrappedValue
                if let selected = cache.row(id: selectedRowIDBinding.wrappedValue),
                   selected.rule.type == type,
                   selected.rule.payload == payload {
                    return selected
                }
                return WorkbenchRuleInspectorResolver.resolve(
                    type: type,
                    payload: payload,
                    in: cache.allRows
                )
            }
            if let selectedRowID, let row = projectionCache.row(id: selectedRowID) {
                workspaceStore.selectInspector(
                    .rule(type: row.rule.type, payload: row.rule.payload)
                )
            }
            isProjectionActive = true
            restoreWorkspace()
            rebuildRows(reconcileSelection: true, update: .source)
            consumeRuleNavigation()
        }
        .onDisappear {
            workspaceStore.ruleRowResolver = nil
            isProjectionActive = false
        }
        .onChange(of: appModel.selectedRouterID) {
            projectionCache.reset()
            scrollRequest = nil
            accessibilityCursor.reset()
            restoreWorkspace()
            rebuildRows(reconcileSelection: true, update: .source)
            consumeRuleNavigation()
        }
        .onChange(of: appModel.controllerSessionPresentation.generation) {
            projectionCache.reset()
            scrollRequest = nil
            accessibilityCursor.reset()
            restoreWorkspace()
            rebuildRows(reconcileSelection: true, update: .source)
            consumeRuleNavigation()
        }
        .onChange(of: appModel.rulesCatalog.rules) {
            rebuildRows(reconcileSelection: true, update: .source)
            consumeRuleNavigation()
        }
        .onChange(of: appModel.connectionsStructureRevision) {
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
            reconcileAccessibilityWindow(revealing: selection)
            persistSelection(selection)
            if let selection, let row = projectionCache.row(id: selection) {
                workspaceStore.selectInspector(
                    .rule(type: row.rule.type, payload: row.rule.payload)
                )
            } else {
                workspaceStore.clearInspectorSelection(ownedBy: .rules)
            }
        }
        .onChange(of: workspaceStore.inspectorSelection) { _, selection in
            if case .none = selection, selectedRowID != nil {
                selectedRowID = nil
            }
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
        }
    }

    private var ruleTable: some View {
        let controllerID = appModel.selectedRouterID
        let generation = appModel.controllerSessionPresentation.generation
        let accessibilityWindow = WorkbenchAccessibilityWindow.resolve(
            totalCount: rows.count,
            preferredLowerBound: accessibilityCursor.lowerBound
        )
        let localization = MicaStrings.localizationContext(for: language)
        let accessibilityPayload = WorkbenchTableAccessibilityPayload.materialize(
            scope: WorkbenchTableAccessibilityScope(
                controllerID: controllerID,
                generation: generation
            ),
            title: localization.localizedKey("dashboard.tab_rules"),
            sourceRows: rows,
            window: accessibilityWindow,
            selectedRowID: selectedRowID,
            localization: localization,
            sortOptions: accessibilitySortOptions,
            summary: WorkbenchRuleProjection.accessibilitySummary,
            namedAction: { row in
                accessibilityNamedAction(for: row, localization: localization)
            }
        )
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
                            MicaStrings.localizedKey("dashboard.col_index", language: language),
                            value: \.indexSortValue
                        ) { row in
                            WorkbenchDataMetric(value: row.indexText, tone: .secondary)
                        }
                        .width(min: 48, ideal: 56)

                        TableColumn(
                            MicaStrings.localizedKey("dashboard.col_type", language: language),
                            value: \.type
                        ) { row in
                            ruleTypeCell(row)
                        }
                        .width(min: 118, ideal: 148)

                        TableColumn(
                            MicaStrings.localizedKey("dashboard.col_payload", language: language),
                            value: \.payload
                        ) { row in
                            WorkbenchDataText(
                                value: row.definitionTitleText,
                                role: .dataLabel
                            )
                        }
                        .width(min: 240, ideal: 420)

                        TableColumn(
                            MicaStrings.localizedKey("dashboard.col_proxy", language: language),
                            value: \.proxy
                        ) { row in
                            WorkbenchDataText(
                                value: row.targetText,
                                role: .label,
                                weight: .medium
                            )
                        }
                        .width(min: 132, ideal: 196)

                        TableColumn(
                            MicaStrings.localizedKey("traffic.rule_section_statistics", language: language),
                            value: \.activeConnections
                        ) { row in
                            ruleActivityCell(row)
                        }
                        .width(min: 128, ideal: 154)

                        TableColumn(MicaStrings.localizedKey("dashboard.col_status", language: language)) { row in
                            ruleStateCell(row)
                        }
                        .width(min: 142, ideal: 176)

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
                .accessibilityHidden(true)
                .overlay {
                    WorkbenchTableAccessibilityHost(
                        payload: accessibilityPayload,
                        dispatch: dispatchAccessibilityIntent
                    )
                    .equatable()
                }
            }
        }
    }

    private func ruleStateCell(_ row: WorkbenchRuleRow) -> some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            ruleStateLabel(row)
            Spacer(minLength: MicaTheme.Spacing.space1)
            ruleAction(row)
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
    }

    private func ruleTypeCell(_ row: WorkbenchRuleRow) -> some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(ruleStatusTint(row.rule).opacity(0.72))
                .frame(width: 3, height: 28)
                .accessibilityHidden(true)

            WorkbenchDataText(
                value: row.typeText,
                role: .dataCaption,
                weight: .semibold
            )
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
    }

    private func ruleActivityCell(_ row: WorkbenchRuleRow) -> some View {
        HStack(spacing: MicaTheme.Spacing.space3) {
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
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
        .accessibilityLabel(
            row.activityAccessibilityText
        )
        .accessibilityValue(row.activityText)
    }

    private func ruleCompactSummary(_ row: WorkbenchRuleRow) -> some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            VStack(alignment: .leading, spacing: 1) {
                WorkbenchDataText(value: row.targetText)

                HStack(spacing: MicaTheme.Spacing.space3) {
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

            Spacer(minLength: MicaTheme.Spacing.space1)
            ruleAction(row)
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
    }

    private func ruleStackedRow(_ row: WorkbenchRuleRow) -> some View {
        HStack(spacing: MicaTheme.Spacing.space3) {
            ruleIdentity(row)
            Spacer(minLength: MicaTheme.Spacing.space2)

            VStack(alignment: .trailing, spacing: 1) {
                WorkbenchDataText(
                    value: row.targetText,
                    role: .caption,
                    alignment: .trailing
                )

                HStack(spacing: MicaTheme.Spacing.space2) {
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

            ruleAction(row)
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height
        )
    }

    private func ruleStateLabel(_ row: WorkbenchRuleRow) -> some View {
        HStack(spacing: MicaTheme.Spacing.space1) {
            Circle()
                .fill(ruleStatusTint(row.rule))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(verbatim: row.statusText)
                .micaThemeFont(.dataCaption)
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
        .micaThemeFont(.dataCaption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func ruleAction(_ row: WorkbenchRuleRow) -> some View {
        let commandScope = LiveCommandScope(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
        if appModel.updatingRuleID == row.rule.id {
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: MicaTheme.Metrics.iconControlSize, minHeight: MicaTheme.Metrics.iconControlSize)
        } else if row.rule.hasMutableExtra, row.rule.index != nil {
            WorkbenchIconCommand(
                titleKey: "action.set_rule_state",
                systemImage: row.rule.disabled == true ? "play.circle" : "pause.circle",
                isEnabled: canMutate(row)
            ) {
                guard let commandScope else { return }
                appModel.setRuleDisabled(
                    row.rule,
                    disabled: !(row.rule.disabled ?? false),
                    scope: commandScope
                )
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
            rules: appModel.rulesCatalog.rules,
            connections: appModel.connectionsCatalog.connections,
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation,
            structureRevision: appModel.connectionsStructureRevision,
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
        reconcileAccessibilityWindow(revealing: selectedRowID)
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

    private func ruleStatusTint(_ rule: RuleViewState) -> Color {
        switch rule.disabled {
        case true: MicaTheme.statusWarning
        case false: MicaTheme.statusOK
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
              let row = WorkbenchRuleNavigationResolver.resolve(
                  pending,
                  controllerID: controllerID,
                  generation: generation,
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
            case "index": return KeyPathComparator(\WorkbenchRuleRow.indexSortValue, order: order)
            case "payload": return KeyPathComparator(\WorkbenchRuleRow.payload, order: order)
            case "type": return KeyPathComparator(\WorkbenchRuleRow.type, order: order)
            case "proxy": return KeyPathComparator(\WorkbenchRuleRow.proxy, order: order)
            case "activeConnections": return KeyPathComparator(\WorkbenchRuleRow.activeConnections, order: order)
            case "hitCount": return KeyPathComparator(\WorkbenchRuleRow.hitCount, order: order)
            default: return nil
            }
        }
    }

    private var accessibilitySortOptions: [WorkbenchAccessibilitySortOption] {
        [
            accessibilitySortOption("index", titleKey: "dashboard.col_index"),
            accessibilitySortOption("type", titleKey: "dashboard.col_type"),
            accessibilitySortOption("payload", titleKey: "dashboard.col_payload"),
            accessibilitySortOption("proxy", titleKey: "dashboard.col_proxy"),
            accessibilitySortOption("activeConnections", titleKey: "dashboard.active_sessions"),
            accessibilitySortOption("hitCount", titleKey: "traffic.rule_hits"),
        ]
    }

    private func accessibilitySortOption(
        _ field: String,
        titleKey: String
    ) -> WorkbenchAccessibilitySortOption {
        let stored = sortOrder
            .compactMap(Self.ruleWorkspaceSort)
            .first { $0.field == field }
        return WorkbenchAccessibilitySortOption(
            id: field,
            title: MicaStrings.localizedKey(titleKey, language: language),
            direction: stored.map { $0.ascending ? .ascending : .descending }
        )
    }

    private func activateAccessibilitySort(_ field: String, ascending: Bool) {
        sortOrder = Self.ruleSortOrder(from: [
            WorkbenchWorkspaceSort(
                field: field,
                ascending: ascending
            ),
        ])
    }

    private func accessibilityNamedAction(
        for row: WorkbenchRuleRow,
        localization: MicaStrings.LocalizationContext
    ) -> WorkbenchAccessibilityNamedAction? {
        WorkbenchRuleAccessibilityMutationResolver.namedAction(
            for: row,
            title: localization.localizedKey("action.set_rule_state"),
            updatingRuleID: appModel.updatingRuleID,
            canRefresh: appModel.canRefreshSelectedRouter,
            isBusy: appModel.isBusy,
            supportsMutation: appModel.supportsUnifiedAction(.setRuleDisabled)
        )
    }

    private func dispatchAccessibilityIntent(_ intent: WorkbenchTableAccessibilityIntent) {
        let currentScope = WorkbenchTableAccessibilityScope(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
        guard intent.scope == currentScope else { return }

        switch intent {
        case .selectRow(let id, _):
            guard projectionCache.visibleRows.contains(where: { $0.id == id }) else { return }
            selectedRowID = id
        case .movePage(let lowerBound, _):
            moveAccessibilityWindow(to: lowerBound)
        case .setSort(let id, let ascending, _):
            activateAccessibilitySort(id, ascending: ascending)
        case .performNamedAction:
            guard let rule = WorkbenchRuleAccessibilityMutationResolver.resolve(
                intent: intent,
                currentScope: currentScope,
                rows: projectionCache.visibleRows,
                updatingRuleID: appModel.updatingRuleID,
                canRefresh: appModel.canRefreshSelectedRouter,
                isBusy: appModel.isBusy,
                supportsMutation: appModel.supportsUnifiedAction(.setRuleDisabled)
            ) else {
                return
            }
            guard let commandScope = LiveCommandScope(
                controllerID: intent.scope.controllerID,
                generation: intent.scope.generation
            ) else { return }
            appModel.setRuleDisabled(
                rule,
                disabled: !(rule.disabled ?? false),
                scope: commandScope
            )
        }
    }

    private func reconcileAccessibilityWindow(revealing selectionID: String? = nil) {
        accessibilityCursor.reconcile(
            orderedIDs: rows.map(\.id),
            revealing: selectionID
        )
    }

    private func moveAccessibilityWindow(to lowerBound: Int) {
        accessibilityCursor.move(
            to: lowerBound,
            orderedIDs: rows.map(\.id)
        )
    }

    private static func ruleWorkspaceSort(
        _ comparator: KeyPathComparator<WorkbenchRuleRow>
    ) -> WorkbenchWorkspaceSort? {
        let field: String
        if comparator.keyPath == \WorkbenchRuleRow.indexSortValue {
            field = "index"
        } else if comparator.keyPath == \WorkbenchRuleRow.payload {
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

enum WorkbenchRuleAccessibilityMutationResolver {
    static let actionID = "rule.set-disabled"

    static func namedAction(
        for row: WorkbenchRuleRow,
        title: String,
        updatingRuleID: String?,
        canRefresh: Bool,
        isBusy: Bool,
        supportsMutation: Bool
    ) -> WorkbenchAccessibilityNamedAction? {
        guard isAvailable(
            row,
            updatingRuleID: updatingRuleID,
            canRefresh: canRefresh,
            isBusy: isBusy,
            supportsMutation: supportsMutation
        ) else {
            return nil
        }
        return WorkbenchAccessibilityNamedAction(id: actionID, title: title)
    }

    static func resolve(
        intent: WorkbenchTableAccessibilityIntent,
        currentScope: WorkbenchTableAccessibilityScope,
        rows: [WorkbenchRuleRow],
        updatingRuleID: String?,
        canRefresh: Bool,
        isBusy: Bool,
        supportsMutation: Bool
    ) -> RuleViewState? {
        guard case .performNamedAction(let rowID, let actionID, let scope) = intent,
              scope == currentScope,
              actionID == Self.actionID,
              let row = rows.first(where: { $0.id == rowID }),
              isAvailable(
                  row,
                  updatingRuleID: updatingRuleID,
                  canRefresh: canRefresh,
                  isBusy: isBusy,
                  supportsMutation: supportsMutation
              ) else {
            return nil
        }
        return row.rule
    }

    static func isAvailable(
        _ row: WorkbenchRuleRow,
        updatingRuleID: String?,
        canRefresh: Bool,
        isBusy: Bool,
        supportsMutation: Bool
    ) -> Bool {
        row.rule.hasMutableExtra
            && row.rule.index != nil
            && updatingRuleID != row.rule.id
            && canRefresh
            && !isBusy
            && supportsMutation
    }
}
