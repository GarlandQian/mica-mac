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

    @State private var model = ConnectionsWorkspaceModel()

    private static let widthBudget = WorkbenchDataWidthBudget(
        fullMinimum: 1_080,
        compactMinimum: 720
    )

    var body: some View {
        WorkbenchDataBrowserScaffold(
            staleMessage: localizedStaleMessage,
            commands: { commandBar },
            supplementary: {
                if showsPulse {
                    WorkbenchConnectionPulseStrip(
                        projection: model.pulse
                    )
                }

                if let selectedRow = model.selectedRow {
                    WorkbenchConnectionDecisionPathRail(
                        projection: WorkbenchConnectionDecisionPathProjection(
                            row: selectedRow
                        ),
                        ruleIsNavigable: model.navigationDirectory.ruleTarget(
                            type: selectedRow.connection.rule ?? "",
                            payload: selectedRow.connection.rulePayload ?? ""
                        ) != nil,
                        policyTarget: model.navigationDirectory.policyTarget(named:),
                        isActive: model.scope == .active,
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
                            model.requestClose(.connection(selectedRow.id), identity: sessionIdentity)
                        },
                        requestCloseGroup: {
                            guard let selectedCloseGroup else { return }
                            model.requestClose(.group(selectedCloseGroup.id), identity: sessionIdentity)
                        }
                    )
                }

                if currentCloseIntent != nil {
                    WorkbenchDataInlineConfirmation(
                        message: closeMessage,
                        confirmTitleKey: closeConfirmTitleKey,
                        isConfirmEnabled: canConfirmClose,
                        confirm: performClose,
                        cancel: { model.closeIntent = nil }
                    )
                }
            }
        ) {
            pageContent
        }
        .background {
            WorkbenchConnectionsCatalogObserver(
                scope: model.scope,
                onActiveConnections: {
                    model.update(presentationInput)
                    consumeConnectionNavigation()
                },
                onClosedConnections: {
                    model.update(presentationInput)
                }
            )
            WorkbenchConnectionRuleCatalogObserver { rules in
                model.updateRuleNavigation(rules: rules, identity: sessionIdentity)
            }
            WorkbenchConnectionPolicyCatalogObserver { catalog, visibility in
                model.updatePolicyNavigation(
                    catalog: catalog,
                    visibility: visibility,
                    identity: sessionIdentity
                )
            }
        }
        .onAppear {
            let pageModel = model
            workspaceStore.connectionRowResolver = { pageModel.row(id: $0) }
            restoreWorkspace()
            model.update(presentationInput)
            updateNavigationDirectory()
            consumeConnectionNavigation()
        }
        .onDisappear {
            workspaceStore.connectionRowResolver = nil
            model.deactivate()
        }
        .onChange(of: sessionIdentity) {
            restoreWorkspace()
            model.update(presentationInput)
            updateNavigationDirectory()
            consumeConnectionNavigation()
        }
        .onChange(of: model.scope) {
            persistScope()
            model.update(presentationInput)
            consumeConnectionNavigation()
        }
        .onChange(of: searchText) {
            model.update(presentationInput)
        }
        .onChange(of: model.sortOrder) {
            persistSortOrder()
            model.update(presentationInput)
        }
        .onChange(of: language) {
            model.update(presentationInput)
        }
        .onChange(of: model.selectedRowID) { _, selection in
            persistSelection(selection)
            if let selection {
                workspaceStore.selectInspector(.connection(id: selection))
            } else {
                workspaceStore.clearInspectorSelection(ownedBy: .connections)
            }
        }
        .onChange(of: workspaceStore.inspectorSelection) { _, selection in
            if case .none = selection, model.selectedRowID != nil {
                model.selectedRowID = nil
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
                    get: { model.scope },
                    set: { next in
                        guard next != model.scope else { return }
                        model.selectedRowID = nil
                        model.scope = next
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
            if model.scope == .active {
                WorkbenchIconCommand(
                    titleKey: "action.close_all",
                    systemImage: "xmark.circle",
                    isEnabled: !model.allRows.isEmpty && canCloseAll,
                    role: .destructive
                ) {
                    model.requestClose(.all, identity: sessionIdentity)
                }
                .foregroundStyle(MicaTheme.statusError)
            } else {
                WorkbenchIconCommand(
                    titleKey: "traffic.clear_closed",
                    systemImage: "trash",
                    isEnabled: !model.allRows.isEmpty,
                    role: .destructive
                ) {
                    appModel.clearClosedConnections()
                    model.selectedRowID = nil
                    model.update(presentationInput, forcePresentation: true)
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
                titleKey: model.scope == .active
                    ? "dashboard.no_active_connections"
                    : "traffic.no_closed_connections_title",
                detailKey: model.scope == .active
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
        @Bindable var model = model
        let controllerID = appModel.selectedRouterID
        let generation = appModel.controllerSessionPresentation.generation
        let accessibilityWindow = model.accessibilityWindow
        let localization = MicaStrings.localizationContext(for: language)
        let accessibilityPayload = WorkbenchTableAccessibilityPayload.materialize(
            scope: WorkbenchSessionIdentity(
                controllerID: controllerID,
                generation: generation
            ),
            title: localization.localizedKey("dashboard.tab_connections"),
            sourceRows: model.rows,
            window: accessibilityWindow,
            selectedRowID: model.selectedRowID,
            localization: localization,
            sortOptions: accessibilitySortOptions,
            summary: WorkbenchConnectionProjection.accessibilitySummary
        )
        return WorkbenchDataTableViewport(
            generation: generation,
            restorationID: model.restoredScrollAnchorID,
            request: model.scrollRequest,
            interaction: model.tableInteraction,
            rowIndex: model.visibleIndex(id:),
            rowID: { index in model.rows.indices.contains(index) ? model.rows[index].id : nil },
            onInteractionEnded: {
                model.finishDeferredPresentation(
                    identity: WorkbenchSessionIdentity(controllerID: controllerID, generation: generation)
                )
            },
            onAnchorCommit: { anchorID in
                persistScrollAnchor(
                    anchorID,
                    controllerID: controllerID,
                    generation: generation
                )
            }
        ) {
            WorkbenchDataResponsive(budget: Self.widthBudget) { mode in
                Table(model.rows, selection: $model.selectedRowID, sortOrder: $model.sortOrder) {
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
                                processCell(row)
                                WorkbenchDataText(
                                    value: row.network,
                                    role: .dataCaption,
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
                                    role: .caption,
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
                                model.scope == .active ? "traffic.start_time" : "traffic.log_received_time",
                                language: language
                            )
                        ) { row in
                            WorkbenchDataText(
                                value: row.timestampText,
                                role: .dataCaption,
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
                                    role: .caption,
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
                                    systemImage: model.scope == .active
                                        ? "point.3.connected.trianglepath.dotted"
                                        : "clock",
                                    tint: model.scope == .active
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

    private func transferCell(total: String, speed: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            if model.scope == .active {
                WorkbenchDataMetric(value: speed)
                WorkbenchDataMetric(value: total, tone: .secondary)
                    .help(MicaStrings.localized(
                        "traffic.connection_accumulated \(total)",
                        language: language
                    ))
            } else {
                WorkbenchDataMetric(value: total)
            }
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .trailing
        )
    }

    private func processCell(_ row: WorkbenchConnectionRow) -> some View {
        let process = row.connection.metadata?.process?.dataNonEmpty
            ?? row.connection.metadata?.processPath?.dataNonEmpty
        return WorkbenchDataText(
            value: process ?? MicaStrings.localizedKey(
                "overview.config_not_reported",
                language: language
            ),
            role: process == nil ? .caption : .label,
            tone: process == nil ? .secondary : .primary
        )
    }

    private func connectionIdentity(_ row: WorkbenchConnectionRow) -> some View {
        WorkbenchDataPrimaryCell(
            title: row.host,
            detail: row.identityDetailText,
            systemImage: model.scope == .active
                ? "point.3.connected.trianglepath.dotted"
                : "clock",
            tint: model.scope == .active ? MicaTheme.accent : .secondary
        )
    }

    private var sessionIdentity: WorkbenchSessionIdentity {
        WorkbenchSessionIdentity(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
    }

    private var presentationInput: ConnectionsWorkspaceInput {
        ConnectionsWorkspaceInput(
            identity: sessionIdentity,
            catalog: appModel.connectionsCatalog,
            closedConnections: appModel.dashboardSessionControls.closedConnectionRecords,
            closedRevision: appModel.dashboardSessionControls.closedConnectionsRevision,
            query: searchText,
            language: language
        )
    }

    private func updateNavigationDirectory() {
        model.updateNavigation(
            rules: appModel.rulesCatalog.rules,
            catalog: appModel.policyGroupCatalog,
            visibility: preferences.globalGroupVisibility,
            identity: sessionIdentity
        )
    }

    private func openMatchingRule(for row: WorkbenchConnectionRow) {
        guard let controllerID = appModel.selectedRouterID,
              let type = row.connection.rule?.dataNonEmpty,
              let payload = row.connection.rulePayload?.dataNonEmpty,
              let target = model.navigationDirectory.ruleTarget(
                  type: type,
                  payload: payload
              ) else {
            return
        }

        workspaceStore.stageRuleNavigation(
            WorkbenchRuleNavigationSelection(
                controllerID: controllerID,
                generation: appModel.controllerSessionPresentation.generation,
                sourceIndex: target.sourceIndex,
                reportedRuleID: target.reportedRuleID,
                type: target.type,
                payload: target.payload
            )
        )
        destination = .rules
    }

    private func openPolicyGroup(_ target: ProxyGroupOccurrence) {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { workspace in
            workspace = ProxyWorkspaceProjection.activating(
                target.id,
                in: workspace,
                groups: model.navigationDirectory.visiblePolicyGroups,
                preferredMemberID: nil
            )
        }
        destination = .proxies
    }

    private var state: WorkbenchDataState {
        WorkbenchDataStateResolver.endpoint(
            hasController: appModel.selectedRouter != nil,
            isSupported: model.scope == .closed || supportsConnectionFeed,
            sourceCount: model.allRows.count,
            visibleCount: model.rows.count,
            isFiltering: searchText.dataNonEmpty != nil,
            endpointStatus: model.scope == .active
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
        guard model.pulse.isFiltered else {
            return model.rows.count.formatted()
        }
        return "\(model.rows.count.formatted()) / \(model.allRows.count.formatted())"
    }

    private var supportsConnectionFeed: Bool {
        let capabilities = appModel.selectedUnifiedCapabilities
        return capabilities.connections || capabilities.activeRequests
    }

    private var canCloseOne: Bool {
        guard model.scope == .active, let router = appModel.selectedRouter else { return false }
        let action: UnifiedControllerAction = appModel.runtimeControllerKind(for: router) == .surgeCompatible
            ? .killActiveRequest
            : .closeConnection
        return appModel.supportsUnifiedAction(action) && !appModel.isBusy
    }

    private var canCloseAll: Bool {
        guard model.scope == .active, let router = appModel.selectedRouter else { return false }
        let action: UnifiedControllerAction = appModel.runtimeControllerKind(for: router) == .surgeCompatible
            ? .killActiveRequest
            : .closeAllConnections
        return appModel.supportsUnifiedAction(action) && !appModel.isBusy
    }

    private var canCloseGroup: Bool {
        canCloseOne && (selectedCloseGroup?.connections.count ?? 0) > 1
    }

    private var currentCloseIntent: WorkbenchConnectionCloseIntent? {
        guard let intent = model.closeIntent,
              intent.isCurrent(
                routerID: appModel.selectedRouterID,
                generation: appModel.controllerSessionPresentation.generation
              ) else {
            return nil
        }
        return intent
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
                "dashboard.confirm_close_all_message \(model.allRows.count) \(controller)",
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
        guard let intent = currentCloseIntent,
              let targets = model.closeTargets(
                for: intent.target,
                currentConnections: appModel.connectionsCatalog.connections,
                identity: sessionIdentity
              ), !targets.isEmpty else { return false }
        switch intent.target {
        case .connection(let id):
            return canCloseOne && model.allRows.contains {
                $0.id == id && $0.connection.id.dataNonEmpty != nil
            }
        case .group:
            return canCloseGroup && pendingCloseGroup != nil
        case .all:
            return canCloseAll && !model.allRows.isEmpty
        }
    }

    private func performClose() {
        guard let intent = model.closeIntent else { return }
        defer { model.closeIntent = nil }
        guard intent.isCurrent(
            routerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        ), let targets = model.closeTargets(
            for: intent.target,
            currentConnections: appModel.connectionsCatalog.connections,
            identity: sessionIdentity
        ) else {
            return
        }

        switch intent.target {
        case .connection:
            guard let connection = targets.first else { return }
            appModel.closeConnection(connection)
        case .group(let id):
            guard let pendingCloseGroup = model.closeGroups.first(where: { $0.id == id }) else {
                return
            }
            appModel.closeConnectionGroup(
                targets,
                groupID: pendingCloseGroup.id,
                groupLabel: closeGroupLabel(pendingCloseGroup)
            )
        case .all:
            appModel.closeAllConnections()
        }
    }

    private var selectedCloseGroup: WorkbenchConnectionCloseGroup? {
        guard let selectedRow = model.selectedRow else { return nil }
        let identity = WorkbenchConnectionOwnerIdentity(connection: selectedRow.connection)
        return model.closeGroups.first { $0.identity == identity }
    }

    private var pendingCloseGroup: WorkbenchConnectionCloseGroup? {
        guard case .group(let id) = currentCloseIntent?.target else { return nil }
        return model.closeGroups.first { $0.id == id }
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
        let identity = sessionIdentity
        if let controllerID = identity.controllerID {
            workspaceStore.activateSession(
                controllerID: controllerID,
                generation: identity.generation
            )
        }
        model.activate(
            identity: identity,
            workspace: workspaceStore.workspace(
                controllerID: identity.controllerID,
                destination: .connections
            ),
            restoredScrollAnchorID: identity.controllerID.flatMap {
                workspaceStore.scrollAnchorID(
                    controllerID: $0,
                    generation: identity.generation,
                    destination: .connections
                )
            }
        )
    }

    private func persistScope() {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .connections
        ) { workspace in
            workspace.activeTab = model.scope.rawValue
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
            workspace.sort = model.sortOrder.compactMap(ConnectionsWorkspaceModel.workspaceSort)
        }
    }

    private func consumeConnectionNavigation() {
        guard let controllerID = appModel.selectedRouterID else { return }
        let generation = appModel.controllerSessionPresentation.generation
        let workspace = workspaceStore.workspace(
            controllerID: controllerID,
            destination: .connections
        )
        guard let pending = workspace.pendingConnectionSelection,
              let revealedQuery = model.reveal(pending, input: presentationInput),
              workspaceStore.consumeConnectionNavigation(
                  controllerID: controllerID,
                  generation: generation
              ) != nil else { return }
        searchText = revealedQuery
    }

    private var accessibilitySortOptions: [WorkbenchAccessibilitySortOption] {
        [
            accessibilitySortOption("host", titleKey: "traffic.connection_host"),
            accessibilitySortOption("process", titleKey: "traffic.connection_process"),
            accessibilitySortOption("upload", titleKey: "dashboard.col_upload"),
            accessibilitySortOption("download", titleKey: "dashboard.col_download"),
        ]
    }

    private func accessibilitySortOption(
        _ field: String,
        titleKey: String
    ) -> WorkbenchAccessibilitySortOption {
        let stored = model.sortOrder
            .compactMap(ConnectionsWorkspaceModel.workspaceSort)
            .first { $0.field == field }
        return WorkbenchAccessibilitySortOption(
            id: field,
            title: MicaStrings.localizedKey(titleKey, language: language),
            direction: stored.map { $0.ascending ? .ascending : .descending }
        )
    }

    private func activateAccessibilitySort(_ field: String, ascending: Bool) {
        model.sortOrder = ConnectionsWorkspaceModel.sortOrder(from: [
            WorkbenchWorkspaceSort(
                field: field,
                ascending: ascending
            ),
        ])
    }

    private func dispatchAccessibilityIntent(_ intent: WorkbenchTableAccessibilityIntent) {
        let currentScope = WorkbenchSessionIdentity(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
        guard intent.scope == currentScope else { return }

        switch intent {
        case .selectRow(let id, _):
            model.select(id, identity: currentScope)
        case .movePage(let lowerBound, _):
            model.moveAccessibilityWindow(to: lowerBound)
        case .setSort(let id, let ascending, _):
            activateAccessibilitySort(id, ascending: ascending)
        case .performNamedAction:
            break
        }
    }


}

/// Catalog intake must remain outside the Table's observation scope: while
/// scrolling the model accepts snapshots without publishing visible rows.
private struct WorkbenchConnectionsCatalogObserver: View {
    @Environment(AppModel.self) private var appModel

    let scope: ConnectionSessionTab
    let onActiveConnections: () -> Void
    let onClosedConnections: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: revision) {
                if scope == .active {
                    onActiveConnections()
                } else {
                    onClosedConnections()
                }
            }
    }

    private var revision: UInt64 {
        if scope == .active {
            appModel.connectionsMetricsRevision
        } else {
            appModel.dashboardSessionControls.closedConnectionsRevision
        }
    }
}

private struct WorkbenchConnectionRuleCatalogObserver: View {
    @Environment(AppModel.self) private var appModel

    let onRules: ([RuleViewState]) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: appModel.rulesCatalog.rules) { _, rules in
                onRules(rules)
            }
    }
}

private struct WorkbenchConnectionPolicyCatalogObserver: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var preferences: AppPreferencesStore

    let onPolicyGroups: (PolicyGroupCatalogSnapshot, GlobalGroupVisibility) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: appModel.policyGroupCatalogRevision) {
                onPolicyGroups(appModel.policyGroupCatalog, preferences.globalGroupVisibility)
            }
            .onChange(of: preferences.globalGroupVisibility) {
                onPolicyGroups(appModel.policyGroupCatalog, preferences.globalGroupVisibility)
            }
    }
}
