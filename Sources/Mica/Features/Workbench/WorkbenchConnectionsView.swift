import AppKit
import Foundation
import MicaCore
import SwiftUI

struct WorkbenchConnectionsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.micaAppFontScale) private var fontScale
    @EnvironmentObject private var preferences: AppPreferencesStore

    @Binding var destination: WorkbenchDestination
    @Binding var searchText: String

    @State private var model = ConnectionsWorkspaceModel()
    @State private var resolverToken: UUID?

    private static let widthBudget = WorkbenchDataWidthBudget(
        fullMinimum: 900,
        compactMinimum: 640
    )

    var body: some View {
        WorkbenchDataBrowserScaffold(
            staleMessage: localizedStaleMessage,
            commands: { commandBar },
            supplementary: {
                if showsPulse {
                    WorkbenchConnectionPulseStrip(
                        projection: model.pulse,
                        onSelectOwner: { owner in
                            searchText = searchText == owner ? "" : owner
                        }
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
            resolverToken = workspaceStore.registerConnectionRowResolver { [weak pageModel] id in
                pageModel?.row(id: id)
            }
            restoreWorkspace()
            model.update(presentationInput)
            syncRestoredSelectionIfCleared()
            updateNavigationDirectory()
            consumeConnectionNavigation()
        }
        .onDisappear {
            if let resolverToken {
                workspaceStore.clearConnectionRowResolver(token: resolverToken)
                self.resolverToken = nil
            }
            model.deactivate()
        }
        .onChange(of: sessionIdentity) {
            restoreWorkspace()
            model.update(presentationInput)
            syncRestoredSelectionIfCleared()
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
                WorkbenchLabeledCommand(
                    titleKey: "action.close_all",
                    systemImage: "xmark.circle",
                    isEnabled: !model.allRows.isEmpty && canCloseAll,
                    role: .destructive
                ) {
                    model.requestClose(.all, identity: sessionIdentity)
                }
            } else {
                WorkbenchLabeledCommand(
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
                detailKey: "traffic.empty_filtered",
                actionTitleKey: searchText.isEmpty ? nil : "dashboard.clear_filter",
                actionSystemImage: "xmark.circle",
                action: searchText.isEmpty ? nil : { searchText = "" }
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
                        .width(min: 190, ideal: 260)

                        TableColumn(
                            MicaStrings.localizedKey("traffic.connection_process", language: language),
                            value: \.process
                        ) { row in
                            // The network already sits under the host; the
                            // process column owns process name and path.
                            processCell(row)
                                .frame(
                                    minHeight: WorkbenchDataRowGeometry.height(for: fontScale),
                                    alignment: .leading
                                )
                        }
                        .width(min: 120, ideal: 180)

                        TableColumn(MicaStrings.localizedKey("dashboard.col_rule", language: language)) { row in
                            VStack(alignment: .leading, spacing: 1) {
                                WorkbenchDataText(value: Self.reportedParts([row.rule, row.payload]))
                                WorkbenchDataText(
                                    value: reportedValue(row.route),
                                    role: .caption,
                                    tone: .secondary
                                )
                            }
                            .frame(
                                minHeight: WorkbenchDataRowGeometry.height(for: fontScale),
                                alignment: .leading
                            )
                        }
                        .width(min: 190, ideal: 280)

                        if model.scope == .active {
                            TableColumn(
                                MicaStrings.localizedKey("dashboard.col_upload", language: language),
                                value: \.uploadSpeed
                            ) { row in
                                transferCell(
                                    total: row.uploadDisplayText,
                                    speed: row.uploadRateDisplayText
                                )
                            }
                            .width(min: 86, ideal: 106)

                            TableColumn(
                                MicaStrings.localizedKey("dashboard.col_download", language: language),
                                value: \.downloadSpeed
                            ) { row in
                                transferCell(
                                    total: row.downloadDisplayText,
                                    speed: row.downloadRateDisplayText
                                )
                            }
                            .width(min: 86, ideal: 106)
                        } else {
                            TableColumn(
                                MicaStrings.localizedKey("dashboard.col_upload", language: language),
                                value: \.upload
                            ) { row in
                                transferCell(
                                    total: row.uploadDisplayText,
                                    speed: row.uploadRateDisplayText
                                )
                            }
                            .width(min: 86, ideal: 106)

                            TableColumn(
                                MicaStrings.localizedKey("dashboard.col_download", language: language),
                                value: \.download
                            ) { row in
                                transferCell(
                                    total: row.downloadDisplayText,
                                    speed: row.downloadRateDisplayText
                                )
                            }
                            .width(min: 86, ideal: 106)
                        }

                        TableColumn(
                            MicaStrings.localizedKey(
                                model.scope == .active ? "traffic.start_time" : "traffic.closed_time",
                                language: language
                            ),
                            value: \.timestampSortKey
                        ) { row in
                            WorkbenchDataText(
                                value: row.formattedTimestampText,
                                role: .dataCaption,
                                tone: .secondary
                            )
                        }
                        .width(min: 112, ideal: 148)

                    case .compact:
                        TableColumn(
                            MicaStrings.localizedKey("traffic.connection_section_identity", language: language),
                            value: \.host
                        ) { row in
                            connectionIdentity(row)
                        }
                        .width(min: 220, ideal: 340)

                        TableColumn(MicaStrings.localizedKey("traffic.connection_section_routing", language: language)) { row in
                            VStack(alignment: .leading, spacing: 1) {
                                WorkbenchDataText(value: reportedText([row.process]))
                                WorkbenchDataText(
                                    value: reportedText([row.rule, row.route]),
                                    role: .caption,
                                    tone: .secondary
                                )
                            }
                            .frame(
                                minHeight: WorkbenchDataRowGeometry.height(for: fontScale),
                                alignment: .leading
                            )
                        }
                        .width(min: 220, ideal: 340)

                        TableColumn(MicaStrings.localizedKey("traffic.connection_section_transfer", language: language)) { row in
                            VStack(alignment: .trailing, spacing: 1) {
                                WorkbenchDataMetric(value: row.uploadSummaryText)
                                WorkbenchDataMetric(
                                    value: row.downloadSummaryText,
                                    tone: .secondary
                                )
                            }
                            .frame(
                                minHeight: WorkbenchDataRowGeometry.height(for: fontScale),
                                alignment: .trailing
                            )
                        }
                        .width(min: 96, ideal: 120)

                    case .stacked:
                        TableColumn(
                            MicaStrings.localizedKey("dashboard.tab_connections", language: language),
                            value: \.host
                        ) { row in
                            HStack(spacing: MicaTheme.Spacing.space3) {
                                WorkbenchDataPrimaryCell(
                                    title: reportedValue(row.host),
                                    detail: Self.reportedParts([row.destination, row.rule, row.route]).dataNonEmpty,
                                    systemImage: model.scope == .active
                                        ? "point.3.connected.trianglepath.dotted"
                                        : "clock",
                                    tint: .secondary
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
                                minHeight: WorkbenchDataRowGeometry.height(for: fontScale)
                            )
                        }
                        .width(min: 220, ideal: 520)

                    }
                }
                .contextMenu(forSelectionType: WorkbenchConnectionRow.ID.self) { selectedIDs in
                    if let id = selectedIDs.first ?? model.selectedRowID,
                       let row = model.row(id: id) {
                        connectionContextMenu(for: row)
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
            minHeight: WorkbenchDataRowGeometry.height(for: fontScale),
            alignment: .trailing
        )
    }

    private func processCell(_ row: WorkbenchConnectionRow) -> some View {
        let name = row.connection.metadata?.process?.dataNonEmpty
        let path = row.connection.metadata?.processPath?.dataNonEmpty
        return VStack(alignment: .leading, spacing: 1) {
            WorkbenchDataText(
                value: name ?? path ?? MicaStrings.localizedKey(
                    "overview.config_not_reported",
                    language: language
                )
            )
            if name != nil, let path, path != name {
                WorkbenchDataText(value: path, role: .dataCaption, tone: .secondary)
            }
        }
    }

    private func reportedValue(_ value: String) -> String {
        value == "-" ? MicaStrings.localizedKey("overview.config_not_reported", language: language) : value
    }

    /// Joins only the parts the controller reported; the projection keeps
    /// `-` placeholders for search and identity, not for display.
    static func reportedParts(_ parts: [String]) -> String {
        parts.filter { $0 != "-" }.joined(separator: " · ")
    }

    /// Joined reported parts, or the not-reported state when none exist.
    private func reportedText(_ parts: [String]) -> String {
        Self.reportedParts(parts).dataNonEmpty
            ?? MicaStrings.localizedKey("overview.config_not_reported", language: language)
    }

    /// Host first, then only the reported destination and network parts.
    private func connectionIdentity(_ row: WorkbenchConnectionRow) -> some View {
        WorkbenchDataPrimaryCell(
            title: reportedValue(row.host),
            detail: Self.reportedParts([row.destination, row.network]).dataNonEmpty,
            systemImage: nil
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
              let target = model.navigationDirectory.ruleTarget(
                  type: type,
                  payload: row.connection.rulePayload?.dataNonEmpty ?? ""
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
            sessionState: model.scope == .active ? appModel.controllerSessionPresentation.state : nil,
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
            return canCloseOne && (pendingCloseGroup?.connections.count ?? 0) > 1
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

    private func syncRestoredSelectionIfCleared() {
        if model.selectedRowID == nil {
            persistSelection(nil)
            workspaceStore.clearInspectorSelection(ownedBy: .connections)
        } else if let selectedRowID = model.selectedRowID {
            workspaceStore.selectInspector(.connection(id: selectedRowID))
        }
    }

    private func consumeConnectionNavigation() {
        guard let controllerID = appModel.selectedRouterID else { return }
        let generation = appModel.controllerSessionPresentation.generation
        let workspace = workspaceStore.workspace(
            controllerID: controllerID,
            destination: .connections
        )
        guard let pending = workspace.pendingConnectionSelection else { return }
        if model.scope != .active {
            model.scope = .active
        }
        if let revealedQuery = model.reveal(pending, input: presentationInput) {
            if workspaceStore.consumeConnectionNavigation(
                controllerID: controllerID,
                generation: generation
            ) != nil {
                searchText = revealedQuery
            }
        } else if appModel.connectionsMetricsRevision > 0
                    || appModel.controllerSessionPresentation.state.isTerminatedOrFailed {
            _ = workspaceStore.consumeConnectionNavigation(
                controllerID: controllerID,
                generation: generation
            )
        }
    }

    @ViewBuilder
    private func connectionContextMenu(for row: WorkbenchConnectionRow) -> some View {
        if row.host != "-" {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.host, forType: .string)
            } label: {
                Label(MicaStrings.localizedKey("action.copy_host", language: language), systemImage: "doc.on.doc")
            }
        }
        if row.destination != "-" {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.destination, forType: .string)
            } label: {
                Label(MicaStrings.localizedKey("action.copy_destination", language: language), systemImage: "doc.on.doc")
            }
        }
        if let processCopy = row.connection.metadata?.processPath?.dataNonEmpty ?? (row.process == "-" ? nil : row.process) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(processCopy, forType: .string)
            } label: {
                Label(MicaStrings.localizedKey("action.copy_process", language: language), systemImage: "doc.on.doc")
            }
        }
        if let filterProcess = row.connection.metadata?.process?.dataNonEmpty {
            Button {
                searchText = filterProcess
            } label: {
                Label(MicaStrings.localizedKey("traffic.filter_by_process", language: language), systemImage: "line.3.horizontal.decrease.circle")
            }
        }
        if let filterRule = row.connection.rule?.dataNonEmpty {
            Button {
                searchText = row.connection.rulePayload?.dataNonEmpty ?? filterRule
            } label: {
                Label(MicaStrings.localizedKey("traffic.filter_by_rule", language: language), systemImage: "line.3.horizontal.decrease.circle")
            }
        }
        if model.scope == .active, canCloseOne, row.connection.id.dataNonEmpty != nil {
            Divider()
            Button(role: .destructive) {
                model.requestClose(.connection(row.id), identity: sessionIdentity)
            } label: {
                Label(MicaStrings.localizedKey("action.close_connection", language: language), systemImage: "xmark.circle")
            }
        }
    }

    private var accessibilitySortOptions: [WorkbenchAccessibilitySortOption] {
        [
            accessibilitySortOption("host", titleKey: "traffic.connection_host"),
            accessibilitySortOption("process", titleKey: "traffic.connection_process"),
            accessibilitySortOption(
                model.scope == .active ? "uploadSpeed" : "upload",
                titleKey: "dashboard.col_upload"
            ),
            accessibilitySortOption(
                model.scope == .active ? "downloadSpeed" : "download",
                titleKey: "dashboard.col_download"
            ),
            accessibilitySortOption(
                "timestamp",
                titleKey: model.scope == .active ? "traffic.start_time" : "traffic.closed_time"
            ),
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
