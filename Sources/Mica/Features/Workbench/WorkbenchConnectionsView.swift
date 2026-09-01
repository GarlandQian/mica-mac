import Foundation
import MicaCore
import SwiftUI

struct WorkbenchConnectionsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language
    @EnvironmentObject private var preferences: AppPreferencesStore

    @Binding var destination: WorkbenchDestination
    @Binding var searchText: String

    @State private var scope: ConnectionSessionTab = .active
    @State private var projectionCache = WorkbenchConnectionProjectionCache()
    @State private var selectedRowID: String?
    @State private var sortOrder: [KeyPathComparator<WorkbenchConnectionRow>] = []
    @State private var closeIntent: WorkbenchConnectionCloseIntent?
    @State private var restoredScrollAnchorID: String?
    @State private var scrollRequest: WorkbenchDataScrollRequest?
    @State private var tableInteraction = WorkbenchDataInteractionCoordinator()
    @State private var metricSortCadence = WorkbenchConnectionMetricSortCadence()
    @State private var navigationDirectory = WorkbenchConnectionNavigationDirectory()
    @State private var isProjectionActive = false

    private static let widthBudget = WorkbenchDataWidthBudget(
        fullMinimum: 1_080,
        compactMinimum: 580
    )

    var body: some View {
        WorkbenchDataBrowserScaffold(
            staleMessage: localizedStaleMessage,
            commands: { commandBar },
            supplementary: {
                if showsPulse {
                    WorkbenchConnectionPulseStrip(
                        projection: projectionCache.pulseProjection
                    )
                }

                if let selectedRow {
                    WorkbenchConnectionDecisionPathRail(
                        projection: WorkbenchConnectionDecisionPathProjection(
                            row: selectedRow
                        ),
                        ruleIsNavigable: navigationDirectory.ruleTarget(
                            type: selectedRow.connection.rule ?? "",
                            payload: selectedRow.connection.rulePayload ?? ""
                        ) != nil,
                        policyTarget: navigationDirectory.policyTarget(named:),
                        isActive: scope == .active,
                        showsClose: selectedRow.connection.id.dataNonEmpty != nil,
                        canClose: canCloseOne && selectedRow.connection.id.dataNonEmpty != nil,
                        closeGroup: selectedCloseGroup,
                        canCloseGroup: canCloseGroup,
                        isClosing: appModel.closingConnectionID == selectedRow.connection.id,
                        isClosingGroup: appModel.closingConnectionGroupID == selectedCloseGroup?.id,
                        openRule: {
                            openMatchingRule(for: selectedRow)
                        },
                        openPolicyGroup: openPolicyGroup,
                        requestClose: {
                            requestClose(.connection(selectedRow.id))
                        },
                        requestCloseGroup: {
                            guard let selectedCloseGroup else { return }
                            requestClose(.group(selectedCloseGroup.id))
                        }
                    )
                }

                if currentCloseIntent != nil {
                    WorkbenchDataInlineConfirmation(
                        message: closeMessage,
                        confirmTitleKey: closeConfirmTitleKey,
                        isConfirmEnabled: canConfirmClose,
                        confirm: performClose,
                        cancel: { closeIntent = nil }
                    )
                }
            }
        ) {
            pageContent
        }
        .onAppear {
            let projectionCacheBinding = $projectionCache
            workspaceStore.connectionRowResolver = { id in
                projectionCacheBinding.wrappedValue.row(id: id)
            }
            if let selectedRowID {
                workspaceStore.selectInspector(.connection(id: selectedRowID))
            }
            isProjectionActive = true
            restoreWorkspace()
            rebuildRows(reconcileSelection: true)
            rebuildNavigationDirectory()
            consumeConnectionNavigation()
        }
        .onDisappear {
            workspaceStore.connectionRowResolver = nil
            isProjectionActive = false
            metricSortCadence.cancel()
        }
        .onChange(of: appModel.selectedRouterID) {
            closeIntent = nil
            projectionCache.reset()
            metricSortCadence.cancel()
            scrollRequest = nil
            restoreWorkspace()
            rebuildRows(reconcileSelection: true)
            rebuildNavigationDirectory()
            consumeConnectionNavigation()
        }
        .onChange(of: appModel.controllerSessionPresentation.generation) {
            closeIntent = nil
            projectionCache.reset()
            metricSortCadence.cancel()
            scrollRequest = nil
            restoreWorkspace()
            rebuildRows(reconcileSelection: true)
            rebuildNavigationDirectory()
            consumeConnectionNavigation()
        }
        .onChange(of: appModel.connectionsCatalog.metricsRevision) {
            guard scope == .active else { return }
            rebuildRows(reconcileSelection: true)
            consumeConnectionNavigation()
        }
        .onChange(of: appModel.routingCatalog.rules) {
            rebuildNavigationDirectory()
        }
        .onChange(of: appModel.policyGroupCatalog) {
            rebuildNavigationDirectory()
        }
        .onChange(of: preferences.globalGroupVisibility) {
            rebuildNavigationDirectory()
        }
        .onChange(of: appModel.dashboardSessionControls.closedConnectionsRevision) {
            guard scope == .closed else { return }
            rebuildRows(reconcileSelection: true)
        }
        .onChange(of: scope) {
            closeIntent = nil
            persistScope()
            rebuildRows(reconcileSelection: true)
            consumeConnectionNavigation()
        }
        .onChange(of: searchText) {
            rebuildRows(reconcileSelection: true)
        }
        .onChange(of: sortOrder) {
            persistSortOrder()
            rebuildRows(reconcileSelection: true)
        }
        .onChange(of: language) {
            rebuildRows(reconcileSelection: true)
        }
        .onChange(of: selectedRowID) { _, selection in
            persistSelection(selection)
            if let selection {
                workspaceStore.selectInspector(.connection(id: selection))
            } else {
                workspaceStore.clearInspectorSelection(ownedBy: .connections)
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
                symbolName: "point.3.connected.trianglepath.dotted",
                titleKey: "dashboard.tab_connections",
                value: resultCountText,
                detail: nil
            )
        } controls: {
            Picker(
                MicaStrings.localizedKey("traffic.connection_tab", language: language),
                selection: Binding(
                    get: { scope },
                    set: { next in
                        guard next != scope else { return }
                        selectedRowID = nil
                        scope = next
                    }
                )
            ) {
                ForEach(ConnectionSessionTab.allCases) { option in
                    Text(MicaStrings.localizedKey(option.titleKey, language: language))
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(
                MicaStrings.localizedKey("traffic.connection_tab", language: language)
            )
            .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
        } commands: {
            if scope == .active {
                WorkbenchIconCommand(
                    titleKey: "action.close_all",
                    systemImage: "xmark.circle",
                    isEnabled: !allRows.isEmpty && canCloseAll,
                    role: .destructive
                ) {
                    requestClose(.all)
                }
                .foregroundStyle(MicaTheme.statusError)
            } else {
                WorkbenchIconCommand(
                    titleKey: "traffic.clear_closed",
                    systemImage: "trash",
                    isEnabled: !allRows.isEmpty,
                    role: .destructive
                ) {
                    appModel.clearClosedConnections()
                    selectedRowID = nil
                }
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
                detailKey: "traffic.connections_loading_message"
            )
        case .unsupported:
            WorkbenchStateView(
                kind: .unsupported,
                titleKey: "traffic.connections_unsupported_title",
                detailKey: "traffic.connections_unsupported_message"
            )
        case .empty:
            WorkbenchStateView(
                kind: .empty,
                titleKey: scope == .active
                    ? "dashboard.no_active_connections"
                    : "traffic.no_closed_connections_title",
                detailKey: scope == .active
                    ? "traffic.no_active_connections_message"
                    : "traffic.no_closed_connections"
            )
        case .filterEmpty:
            WorkbenchStateView(
                kind: .filterEmpty,
                titleKey: "dashboard.no_matching_connections",
                detailKey: "traffic.empty_filtered"
            )
        case .failed(let message):
            WorkbenchStateView(
                kind: .failed,
                titleKey: "traffic.data_failed_title",
                message: message,
                actionTitleKey: "action.refresh",
                isActionEnabled: appModel.canRefreshSelectedRouter,
                action: { appModel.refreshSelectedRouter() }
            )
        case .content:
            connectionTable
        }
    }

    private var connectionTable: some View {
        let controllerID = appModel.selectedRouterID
        let generation = appModel.controllerSessionPresentation.generation
        return WorkbenchDataTableViewport(
            generation: generation,
            restorationID: restoredScrollAnchorID,
            request: scrollRequest,
            interaction: tableInteraction,
            onInteractionEnded: finishDeferredMetricSort,
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
                            MicaStrings.localizedKey("traffic.connection_host", language: language),
                            value: \.host
                        ) { row in
                            connectionIdentity(row)
                        }
                        .width(min: 190, ideal: 270)

                        TableColumn(
                            MicaStrings.localizedKey("traffic.connection_process", language: language),
                            value: \.process
                        ) { row in
                            VStack(alignment: .leading, spacing: 1) {
                                WorkbenchDataText(value: row.process)
                                WorkbenchDataText(
                                    value: row.network,
                                    style: .caption, design: .monospaced,
                                    tone: .secondary
                                )
                            }
                            .frame(
                                minHeight: WorkbenchDataRowGeometry.height,
                                maxHeight: WorkbenchDataRowGeometry.height,
                                alignment: .leading
                            )
                        }
                        .width(min: 130, ideal: 190)

                        TableColumn(MicaStrings.localizedKey("dashboard.col_rule", language: language)) { row in
                            VStack(alignment: .leading, spacing: 1) {
                                WorkbenchDataText(value: row.rulePayloadText)
                                WorkbenchDataText(
                                    value: row.route,
                                    style: .caption,
                                    tone: .secondary
                                )
                            }
                            .frame(
                                minHeight: WorkbenchDataRowGeometry.height,
                                maxHeight: WorkbenchDataRowGeometry.height,
                                alignment: .leading
                            )
                        }
                        .width(min: 210, ideal: 320)

                        TableColumn(
                            MicaStrings.localizedKey("dashboard.col_upload", language: language),
                            value: \.upload
                        ) { row in
                            transferCell(
                                total: row.uploadDisplayText,
                                speed: row.uploadRateDisplayText
                            )
                        }
                        .width(min: 88, ideal: 108)

                        TableColumn(
                            MicaStrings.localizedKey("dashboard.col_download", language: language),
                            value: \.download
                        ) { row in
                            transferCell(
                                total: row.downloadDisplayText,
                                speed: row.downloadRateDisplayText
                            )
                        }
                        .width(min: 88, ideal: 108)

                        TableColumn(
                            MicaStrings.localizedKey(
                                scope == .active ? "traffic.start_time" : "traffic.log_received_time",
                                language: language
                            )
                        ) { row in
                            WorkbenchDataText(
                                value: row.timestampText,
                                style: .caption, design: .monospaced,
                                tone: .secondary
                            )
                        }
                        .width(min: 120, ideal: 160)

                    case .compact:
                        TableColumn(
                            MicaStrings.localizedKey("traffic.connection_section_identity", language: language),
                            value: \.host
                        ) { row in
                            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                                connectionIdentity(row)
                            }
                        }
                        .width(min: 250, ideal: 360)

                        TableColumn(MicaStrings.localizedKey("traffic.connection_section_routing", language: language)) { row in
                            VStack(alignment: .leading, spacing: 1) {
                                WorkbenchDataText(value: row.processNetworkText)
                                WorkbenchDataText(
                                    value: row.ruleRouteText,
                                    style: .caption,
                                    tone: .secondary
                                )
                            }
                            .frame(
                                minHeight: WorkbenchDataRowGeometry.height,
                                maxHeight: WorkbenchDataRowGeometry.height,
                                alignment: .leading
                            )
                        }
                        .width(min: 250, ideal: 360)

                        TableColumn(MicaStrings.localizedKey("traffic.connection_section_transfer", language: language)) { row in
                            VStack(alignment: .trailing, spacing: 1) {
                                WorkbenchDataMetric(value: row.uploadSummaryText)
                                WorkbenchDataMetric(
                                    value: row.downloadSummaryText,
                                    tone: .secondary
                                )
                            }
                            .frame(
                                minHeight: WorkbenchDataRowGeometry.height,
                                maxHeight: WorkbenchDataRowGeometry.height,
                                alignment: .trailing
                            )
                        }
                        .width(min: 104, ideal: 124)

                    case .stacked:
                        TableColumn(
                            MicaStrings.localizedKey("dashboard.tab_connections", language: language),
                            value: \.host
                        ) { row in
                            HStack(spacing: MicaTheme.Spacing.space3) {
                                WorkbenchDataPrimaryCell(
                                    title: row.host,
                                    detail: row.stackedDetailText,
                                    systemImage: scope == .active
                                        ? "point.3.connected.trianglepath.dotted"
                                        : "clock",
                                    tint: scope == .active
                                        ? MicaTheme.accent
                                        : .secondary
                                )

                                Spacer(minLength: MicaTheme.Spacing.space2)

                                VStack(alignment: .trailing, spacing: 1) {
                                    WorkbenchDataMetric(value: row.uploadSummaryText)
                                    WorkbenchDataMetric(
                                        value: row.downloadSummaryText,
                                        tone: .secondary
                                    )
                                }
                            }
                            .frame(
                                minHeight: WorkbenchDataRowGeometry.height,
                                maxHeight: WorkbenchDataRowGeometry.height
                            )
                        }
                        .width(min: 220, ideal: 520)

                    }
                }
                .micaWorkbenchTable(
                    accessibilityLabel: MicaStrings.localizedKey(
                        "dashboard.tab_connections",
                        language: language
                    )
                )
            }
        }
        .task(id: metricSortCadence.pendingDeadline) {
            guard let pendingDeadline = metricSortCadence.pendingDeadline else { return }
            let remainingMilliseconds = Int64(
                ceil(max(0, pendingDeadline.timeIntervalSinceNow * 1_000))
            )
            if remainingMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(remainingMilliseconds))
            }
            guard !Task.isCancelled, metricSortCadence.consume() else { return }
            finishDeferredMetricSort()
        }
    }

    private func transferCell(total: String, speed: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            WorkbenchDataMetric(value: total)
            WorkbenchDataMetric(
                value: speed,
                tone: .secondary
            )
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .trailing
        )
    }

    private func connectionIdentity(_ row: WorkbenchConnectionRow) -> some View {
        WorkbenchDataPrimaryCell(
            title: row.host,
            detail: row.identityDetailText,
            systemImage: scope == .active
                ? "point.3.connected.trianglepath.dotted"
                : "clock",
            tint: scope == .active ? MicaTheme.accent : .secondary
        )
    }

    private func rebuildNavigationDirectory() {
        let visibleGroups = ProxyProjection.arrangedGroups(
            appModel.policyGroupCatalog.groups,
            mode: appModel.policyGroupCatalog.mode,
            visibility: preferences.globalGroupVisibility
        )
        navigationDirectory = WorkbenchConnectionNavigationDirectory(
            rules: appModel.routingCatalog.rules,
            groups: visibleGroups
        )
    }

    private func openMatchingRule(for row: WorkbenchConnectionRow) {
        guard let controllerID = appModel.selectedRouterID,
              let type = row.connection.rule?.dataNonEmpty,
              let payload = row.connection.rulePayload?.dataNonEmpty,
              navigationDirectory.ruleTarget(type: type, payload: payload) != nil else {
            return
        }

        workspaceStore.stageRuleNavigation(
            WorkbenchRuleNavigationSelection(
                controllerID: controllerID,
                generation: appModel.controllerSessionPresentation.generation,
                type: type,
                payload: payload
            )
        )
        destination = .rules
    }

    private func openPolicyGroup(_ target: ProxyGroupOccurrence) {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { workspace in
            workspace = ProxyWorkspaceProjection.opening(
                target.id,
                in: workspace,
                groups: navigationDirectory.visiblePolicyGroups,
                preferredMemberID: nil
            )
        }
        destination = .proxies
    }

    private func rebuildRows(reconcileSelection: Bool) {
        guard isProjectionActive else { return }
        let previousRows = allRows
        let previousSelection = selectedRowID
        projectionCache.project(
            activeConnections: appModel.connectionsCatalog.connections,
            closedConnections: appModel.dashboardSessionControls.closedConnectionRecords,
            scope: scope,
            structureRevision: appModel.connectionsCatalog.structureRevision,
            metricsRevision: appModel.connectionsCatalog.metricsRevision,
            closedRevision: appModel.dashboardSessionControls.closedConnectionsRevision,
            query: searchText,
            sortOrder: sortOrder,
            language: language,
            change: appModel.connectionsCatalog.lastChange,
            deferMetricSorting: tableInteraction.isUserScrolling,
            isActive: isProjectionActive
        )
        if projectionCache.hasDeferredMetricSort {
            metricSortCadence.schedule()
        } else {
            metricSortCadence.cancel()
        }

        if reconcileSelection {
            selectedRowID = WorkbenchDataSelection.reconciled(
                previousSelection,
                previousRows: previousRows,
                nextVisibleRows: rows,
                identityFamily: \.identityFamily
            )
        }

        closeIntent = closeIntent?.reconciled(
            routerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation,
            connectionIDs: projectionCache.connectionIDs,
            groupIDs: projectionCache.groupIDs
        )
    }

    private var state: WorkbenchDataState {
        WorkbenchDataStateResolver.endpoint(
            hasController: appModel.selectedRouter != nil,
            isSupported: scope == .closed || supportsConnectionFeed,
            sourceCount: allRows.count,
            visibleCount: rows.count,
            isFiltering: searchText.dataNonEmpty != nil,
            endpointStatus: scope == .active
                ? appModel.controllerHealth.status(for: .connections)
                : nil,
            sessionState: appModel.controllerSessionPresentation.state,
            language: language
        )
    }

    private var showsPulse: Bool {
        if case .content = state {
            return true
        }
        return false
    }

    private var resultCountText: String {
        guard projectionCache.pulseProjection.isFiltered else {
            return rows.count.formatted()
        }
        return "\(rows.count.formatted()) / \(allRows.count.formatted())"
    }

    private var supportsConnectionFeed: Bool {
        let capabilities = appModel.selectedUnifiedCapabilities
        return capabilities.connections || capabilities.activeRequests
    }

    private var canCloseOne: Bool {
        guard scope == .active, let router = appModel.selectedRouter else { return false }
        let action: UnifiedControllerAction = appModel.runtimeControllerKind(for: router) == .surgeCompatible
            ? .killActiveRequest
            : .closeConnection
        return appModel.supportsUnifiedAction(action) && !appModel.isBusy
    }

    private var canCloseAll: Bool {
        guard scope == .active, let router = appModel.selectedRouter else { return false }
        let action: UnifiedControllerAction = appModel.runtimeControllerKind(for: router) == .surgeCompatible
            ? .killActiveRequest
            : .closeAllConnections
        return appModel.supportsUnifiedAction(action) && !appModel.isBusy
    }

    private var canCloseGroup: Bool {
        canCloseOne && (selectedCloseGroup?.connections.count ?? 0) > 1
    }

    private var selectedRow: WorkbenchConnectionRow? {
        projectionCache.row(id: selectedRowID)
    }

    private var currentCloseIntent: WorkbenchConnectionCloseIntent? {
        guard let closeIntent,
              closeIntent.isCurrent(
                routerID: appModel.selectedRouterID,
                generation: appModel.controllerSessionPresentation.generation
              ) else {
            return nil
        }
        return closeIntent
    }

    private var closeMessage: String {
        let controller = appModel.selectedRouter?.displayName
            ?? MicaStrings.localizedKey("overview.config_not_reported", language: language)
        switch currentCloseIntent?.target {
        case .connection:
            return MicaStrings.localized(
                "dashboard.confirm_close_connection_message \(controller)",
                language: language
            )
        case .group:
            guard let pendingCloseGroup else { return "" }
            return MicaStrings.localized(
                "dashboard.confirm_close_connection_group_message \(pendingCloseGroup.connections.count) \(closeGroupLabel(pendingCloseGroup)) \(controller)",
                language: language
            )
        case .all:
            return MicaStrings.localized(
                "dashboard.confirm_close_all_message \(allRows.count) \(controller)",
                language: language
            )
        case nil:
            return ""
        }
    }

    private var closeConfirmTitleKey: String {
        switch currentCloseIntent?.target {
        case .connection:
            "dashboard.confirm_close_connection_button"
        case .group:
            "action.close_connection_group"
        case .all:
            "dashboard.confirm_close_all_button"
        case nil:
            "action.cancel"
        }
    }

    private var canConfirmClose: Bool {
        guard let closeIntent = currentCloseIntent else { return false }
        switch closeIntent.target {
        case .connection(let id):
            return canCloseOne && allRows.contains {
                $0.id == id && $0.connection.id.dataNonEmpty != nil
            }
        case .group:
            return canCloseGroup && pendingCloseGroup != nil
        case .all:
            return canCloseAll && !allRows.isEmpty
        }
    }

    private func performClose() {
        guard let closeIntent else { return }
        defer { self.closeIntent = nil }
        guard closeIntent.isCurrent(
            routerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        ) else {
            return
        }

        switch closeIntent.target {
        case .connection(let id):
            guard let row = projectionCache.row(id: id) else { return }
            appModel.closeConnection(row.connection)
        case .group(let id):
            guard let pendingCloseGroup = closeGroups.first(where: { $0.id == id }) else {
                return
            }
            appModel.closeConnectionGroup(
                pendingCloseGroup.connections,
                groupID: pendingCloseGroup.id,
                groupLabel: closeGroupLabel(pendingCloseGroup)
            )
        case .all:
            appModel.closeAllConnections()
        }
    }

    private func requestClose(_ target: WorkbenchConnectionCloseIntent.Target) {
        guard let routerID = appModel.selectedRouterID else {
            closeIntent = nil
            return
        }
        closeIntent = WorkbenchConnectionCloseIntent(
            routerID: routerID,
            generation: appModel.controllerSessionPresentation.generation,
            target: target
        )
    }

    private var closeGroups: [WorkbenchConnectionCloseGroup] {
        projectionCache.closeGroups
    }

    private var selectedCloseGroup: WorkbenchConnectionCloseGroup? {
        guard let selectedRow else { return nil }
        let identity = WorkbenchConnectionOwnerIdentity(connection: selectedRow.connection)
        return closeGroups.first { $0.identity == identity }
    }

    private var pendingCloseGroup: WorkbenchConnectionCloseGroup? {
        guard case .group(let id) = currentCloseIntent?.target else { return nil }
        return closeGroups.first { $0.id == id }
    }

    private func closeGroupLabel(_ group: WorkbenchConnectionCloseGroup) -> String {
        switch group.identity {
        case .inner:
            MicaStrings.localizedKey("traffic.connection_group_inner", language: language)
        case .process(let value), .source(let value):
            value
        case .unreported:
            MicaStrings.localizedKey("traffic.connection_group_unreported", language: language)
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
            destination: .connections
        )
        scope = workspace.activeTab.flatMap(ConnectionSessionTab.init(rawValue:)) ?? .active
        sortOrder = Self.connectionSortOrder(from: workspace.sort)
        selectedRowID = workspace.selectedItemID
        restoredScrollAnchorID = controllerID.flatMap {
            workspaceStore.scrollAnchorID(
                controllerID: $0,
                generation: generation,
                destination: .connections
            )
        }
    }

    private func persistScope() {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .connections
        ) { workspace in
            workspace.activeTab = scope.rawValue
        }
    }

    private func persistSelection(_ selection: String?) {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .connections
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
            destination: .connections,
            anchorID: anchorID
        )
    }

    private func persistSortOrder() {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .connections
        ) { workspace in
            workspace.sort = sortOrder.compactMap(Self.connectionWorkspaceSort)
        }
    }

    private func consumeConnectionNavigation() {
        guard scope == .active,
              let controllerID = appModel.selectedRouterID else { return }
        let generation = appModel.controllerSessionPresentation.generation
        let workspace = workspaceStore.workspace(
            controllerID: controllerID,
            destination: .connections
        )
        guard let pending = workspace.pendingConnectionSelection,
              pending.generation == generation,
              allRows.contains(where: {
                  pending.matches(
                      sourceIndex: $0.sourceIndex,
                      reportedConnectionID: $0.connection.id
                  )
              }),
              let navigation = workspaceStore.consumeConnectionNavigation(
                controllerID: controllerID,
                generation: generation
              ),
              let row = allRows.first(where: {
                  navigation.matches(
                      sourceIndex: $0.sourceIndex,
                      reportedConnectionID: $0.connection.id
                  )
              }) else {
            return
        }

        selectedRowID = row.id
        scrollRequest = WorkbenchDataScrollRequest(id: row.id)
    }

    private func finishDeferredMetricSort() {
        metricSortCadence.cancel()
        projectionCache.commitDeferredMetricSort()
    }

    private static func connectionSortOrder(
        from workspaceSort: [WorkbenchWorkspaceSort]
    ) -> [KeyPathComparator<WorkbenchConnectionRow>] {
        workspaceSort.compactMap { item -> KeyPathComparator<WorkbenchConnectionRow>? in
            let order: SortOrder = item.ascending ? .forward : .reverse
            switch item.field {
            case "host": return KeyPathComparator(\WorkbenchConnectionRow.host, order: order)
            case "process": return KeyPathComparator(\WorkbenchConnectionRow.process, order: order)
            case "upload": return KeyPathComparator(\WorkbenchConnectionRow.upload, order: order)
            case "download": return KeyPathComparator(\WorkbenchConnectionRow.download, order: order)
            default: return nil
            }
        }
    }

    private static func connectionWorkspaceSort(
        _ comparator: KeyPathComparator<WorkbenchConnectionRow>
    ) -> WorkbenchWorkspaceSort? {
        let field: String
        if comparator.keyPath == \WorkbenchConnectionRow.host {
            field = "host"
        } else if comparator.keyPath == \WorkbenchConnectionRow.process {
            field = "process"
        } else if comparator.keyPath == \WorkbenchConnectionRow.upload {
            field = "upload"
        } else if comparator.keyPath == \WorkbenchConnectionRow.download {
            field = "download"
        } else {
            return nil
        }
        return WorkbenchWorkspaceSort(
            field: field,
            ascending: comparator.order == .forward
        )
    }

    private var allRows: [WorkbenchConnectionRow] {
        projectionCache.allRows
    }

    private var rows: [WorkbenchConnectionRow] {
        projectionCache.visibleRows
    }
}
