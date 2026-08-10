import Foundation
import MicaCore
import SwiftUI

// MARK: - Sources

struct WorkbenchSourcesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language
    @Binding var searchText: String

    @State private var kind: ProviderSessionKind = .all
    @State private var projectionCache = WorkbenchSourceProjectionCache()
    @State private var selectedRowID: String?
    @State private var sortOrder: [KeyPathComparator<WorkbenchSourceRow>] = []
    @State private var restoredScrollAnchorID: String?
    @State private var tableInteraction = WorkbenchDataInteractionCoordinator()
    @State private var isProjectionActive = false

    private static let widthBudget = WorkbenchDataWidthBudget(
        fullMinimum: 960,
        compactMinimum: 520
    )

    var body: some View {
        WorkbenchDataBrowserScaffold(
            staleMessage: localizedStaleMessage,
            commands: { commandBar },
            supplementary: {
                if let progress = appModel.providerUpdateAllProgress {
                    WorkbenchProviderUpdateAllProgressView(progress: progress)
                }

                if let selectedRow {
                    WorkbenchSourceFocusRail(
                        projection: WorkbenchSourceFocusProjection(row: selectedRow),
                        supportsUpdate: selectedRow.source.updatable,
                        supportsHealthCheck: selectedRow.source.supportsHealthCheck,
                        canUpdate: canUpdate(selectedRow),
                        canHealthCheck: canHealthCheck(selectedRow),
                        isUpdating: appModel.updatingProviderName == selectedRow.source.id,
                        isChecking: appModel.checkingProviderName == selectedRow.source.id,
                        update: {
                            appModel.updateProxyProvider(selectedRow.source)
                        },
                        healthCheck: {
                            appModel.healthCheckProxyProvider(selectedRow.source)
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
        }
        .onDisappear {
            isProjectionActive = false
        }
        .onChange(of: appModel.selectedRouterID) {
            projectionCache.reset()
            restoreWorkspace()
            rebuildRows(reconcileSelection: true, update: .source)
        }
        .onChange(of: appModel.controllerSessionPresentation.generation) {
            projectionCache.reset()
            restoreWorkspace()
            rebuildRows(reconcileSelection: true, update: .source)
        }
        .onChange(of: appModel.routingCatalog.providers) {
            rebuildRows(reconcileSelection: true, update: .source)
        }
        .onChange(of: kind) {
            persistKind()
            rebuildRows(reconcileSelection: true, update: .visibleOnly)
        }
        .onChange(of: searchText) {
            rebuildRows(reconcileSelection: true, update: .visibleOnly)
        }
        .onChange(of: sortOrder) {
            persistSortOrder()
            rebuildRows(reconcileSelection: true, update: .visibleOnly)
        }
        .onChange(of: language) {
            rebuildRows(reconcileSelection: true, update: .source)
        }
        .onChange(of: selectedRowID) { _, selection in
            persistSelection(selection)
        }
    }

    private var commandBar: some View {
        WorkbenchCommandBar {
            WorkbenchCommandSummary(
                symbolName: "shippingbox",
                titleKey: "dashboard.tab_providers",
                value: String(rows.count),
                detail: nil
            )
        } controls: {
            Picker(
                MicaStrings.localizedKey("traffic.source_kind", language: language),
                selection: Binding(
                    get: { kind },
                    set: { next in
                        guard next != kind else { return }
                        selectedRowID = nil
                        kind = next
                    }
                )
            ) {
                ForEach(ProviderSessionKind.allCases) { option in
                    Text(MicaStrings.localizedKey(option.titleKey, language: language))
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(
                MicaStrings.localizedKey("traffic.source_kind", language: language)
            )
            .frame(minHeight: MicaBounds.controlMinHeight)

            WorkbenchDataActivityIndicator(
                isActive: appModel.reloadingProviders || appModel.providersSnapshotState.isLoading,
                titleKey: "snapshot.loading"
            )
        } commands: {
            WorkbenchIconCommand(
                titleKey: "action.provider_update_all",
                systemImage: "arrow.triangle.2.circlepath",
                isEnabled: canUpdateAll
            ) {
                appModel.updateAllProviders()
            }

            WorkbenchIconCommand(
                titleKey: "action.reload_providers",
                systemImage: "arrow.clockwise",
                isEnabled: canReload
            ) {
                appModel.reloadProviders()
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
                detailKey: "traffic.sources_loading_message"
            )
        case .unsupported:
            WorkbenchStateView(
                kind: .unsupported,
                titleKey: "traffic.sources_unsupported_title",
                detailKey: "traffic.sources_unsupported_message"
            )
        case .empty:
            WorkbenchStateView(
                kind: .empty,
                titleKey: "dashboard.no_providers_snapshot",
                detailKey: "traffic.sources_empty_message"
            )
        case .filterEmpty:
            WorkbenchStateView(
                kind: .filterEmpty,
                titleKey: "dashboard.no_matching_sources",
                detailKey: "traffic.empty_filtered"
            )
        case .failed(let message):
            WorkbenchStateView(
                kind: .failed,
                titleKey: "traffic.data_failed_title",
                message: message,
                actionTitleKey: canReload ? "action.reload_providers" : nil,
                isActionEnabled: canReload,
                action: canReload ? { appModel.reloadProviders() } : nil
            )
        case .content:
            sourceTable
                .inspector(isPresented: inspectorPresented) {
                    WorkbenchSourceInspector(
                        row: selectedRow,
                        updateFailure: selectedRow.flatMap {
                            appModel.providerUpdateFailures[$0.source.id]
                        },
                        healthFailure: selectedRow.flatMap {
                            appModel.providerHealthCheckFailures[$0.source.id]
                        },
                        close: { selectedRowID = nil }
                    )
                    .inspectorColumnWidth(
                        min: MicaBounds.inspectorMin,
                        ideal: MicaBounds.inspectorIdeal,
                        max: MicaBounds.inspectorMax
                    )
                }
        }
    }

    private var sourceTable: some View {
        let controllerID = appModel.selectedRouterID
        let generation = appModel.controllerSessionPresentation.generation
        return WorkbenchDataTableViewport(
            generation: generation,
            restorationID: restoredScrollAnchorID,
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
                            MicaStrings.localizedKey("dashboard.col_provider", language: language),
                            value: \.name
                        ) { row in
                            sourceIdentity(row)
                        }
                        .width(min: 190, ideal: 280)

                        TableColumn(
                            MicaStrings.localizedKey("traffic.source_section_configuration", language: language),
                            value: \.type
                        ) { row in
                            sourceConfiguration(row)
                        }
                        .width(min: 190, ideal: 270)

                        TableColumn(
                            MicaStrings.localizedKey("traffic.provider_items", language: language),
                            value: \.itemCount
                        ) { row in
                            WorkbenchDataMetric(value: row.itemCountText)
                        }
                        .width(min: 70, ideal: 84)

                        TableColumn(MicaStrings.localizedKey("traffic.updated_at", language: language)) { row in
                            WorkbenchDataText(
                                value: row.updatedText,
                                style: .caption, design: .monospaced,
                                tone: .secondary
                            )
                        }
                        .width(min: 140, ideal: 180)

                        TableColumn(MicaStrings.localizedKey("traffic.source_section_status", language: language)) { row in
                            sourceStatus(row)
                        }
                        .width(min: 140, ideal: 176)

                    case .compact:
                        TableColumn(
                            MicaStrings.localizedKey("traffic.source_section_configuration", language: language),
                            value: \.name
                        ) { row in
                            sourceIdentity(row)
                        }
                        .width(min: 270, ideal: 420)

                        TableColumn(MicaStrings.localizedKey("traffic.source_section_status", language: language)) { row in
                            sourceCompactSummary(row)
                        }
                        .width(min: 210, ideal: 280)

                    case .stacked:
                        TableColumn(
                            MicaStrings.localizedKey("dashboard.tab_providers", language: language),
                            value: \.name
                        ) { row in
                            sourceStackedRow(row)
                        }
                        .width(min: 220, ideal: 520)

                    }
                }
                .micaWorkbenchTable(
                    accessibilityLabel: MicaStrings.localizedKey(
                        "dashboard.tab_providers",
                        language: language
                    )
                )
            }
        }
    }

    private func sourceIdentity(_ row: WorkbenchSourceRow) -> some View {
        WorkbenchDataPrimaryCell(
            title: row.source.name,
            detail: row.kindText,
            systemImage: row.source.kind == .proxy ? "network" : "doc.text",
            tint: row.source.kind == .proxy
                ? MicaDesignTokens.signalCyan
                : MicaDesignTokens.signalViolet,
            detailIsMonospaced: false
        )
    }

    private func sourceConfiguration(_ row: WorkbenchSourceRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            WorkbenchDataText(
                value: row.typeText,
                style: .callout, weight: .semibold, design: .monospaced,
                maximumLineCount: 1
            )
            if let configurationDetailText = row.configurationDetailText {
                WorkbenchDataText(
                    value: configurationDetailText,
                    style: .caption, design: .monospaced,
                    tone: .secondary,
                    maximumLineCount: 1
                )
            }
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
    }

    private func sourceStatus(_ row: WorkbenchSourceRow) -> some View {
        HStack(spacing: MicaSpacing.row) {
            sourceUpdateState(row)
            sourceHealthState(row)
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.statusAccessibilityText)
    }

    private func sourceCompactSummary(_ row: WorkbenchSourceRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: MicaSpacing.row) {
                WorkbenchDataText(
                    value: row.compactConfigurationText,
                    style: .caption,
                    design: .monospaced
                )
                Spacer(minLength: MicaSpacing.tight)
                sourceUpdateState(row)
                sourceHealthState(row)
            }

            WorkbenchDataText(
                value: row.compactStatusText,
                style: .caption,
                design: .monospaced,
                tone: .secondary
            )
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(row.compactConfigurationText), \(row.compactStatusText), \(row.statusAccessibilityText)"
        )
    }

    private func sourceStackedRow(_ row: WorkbenchSourceRow) -> some View {
        HStack(spacing: MicaSpacing.module) {
            sourceIdentity(row)
            Spacer(minLength: MicaSpacing.row)

            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: MicaSpacing.tight) {
                    sourceUpdateState(row)
                    sourceHealthState(row)
                }

                WorkbenchDataText(
                    value: row.stackedSummaryText,
                    style: .caption,
                    design: .monospaced,
                    tone: .secondary,
                    alignment: .trailing
                )
            }
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(row.source.name), \(row.kindText), \(row.stackedSummaryText), \(row.statusAccessibilityText)"
        )
    }

    private func sourceUpdateState(_ row: WorkbenchSourceRow) -> some View {
        HStack(spacing: MicaSpacing.tight) {
            Circle()
                .fill(row.source.updatable ? MicaDesignTokens.signalMint : Color.secondary)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(verbatim: row.updatableText)
                .micaFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private func sourceHealthState(_ row: WorkbenchSourceRow) -> some View {
        WorkbenchSymbol(
            systemName: "waveform.path.ecg",
            tint: row.source.supportsHealthCheck
                ? MicaDesignTokens.signalCyan
                : .secondary,
            size: .inline
        )
        .help(row.healthCheckAvailabilityText)
        .accessibilityLabel(row.healthCheckAvailabilityText)
    }

    private func rebuildRows(
        reconcileSelection: Bool,
        update: WorkbenchSourceProjectionUpdate
    ) {
        guard isProjectionActive else { return }
        let previousRows = allRows
        let previousSelection = selectedRowID
        projectionCache.project(
            update: update,
            sources: appModel.routingCatalog.providers,
            kind: kind,
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
            isSupported: appModel.selectedUnifiedCapabilities.providers,
            sourceCount: allRows.count,
            visibleCount: rows.count,
            isFiltering: kind != .all || searchText.dataNonEmpty != nil,
            endpointStatus: appModel.controllerHealth.status(for: .providers),
            snapshotState: appModel.providersSnapshotState,
            sessionState: appModel.controllerSessionPresentation.state,
            language: language
        )
    }

    private var canReload: Bool {
        appModel.canRefreshSelectedRouter && appModel.supportsUnifiedAction(.reloadProviders)
    }

    private var canUpdateAll: Bool {
        projectionCache.updatableSourceCount > 0
            && appModel.canRefreshSelectedRouter
            && appModel.supportsUnifiedAction(.updateProvider)
    }

    private func canUpdate(_ row: WorkbenchSourceRow) -> Bool {
        row.source.updatable
            && appModel.canRefreshSelectedRouter
            && appModel.supportsUnifiedAction(.updateProvider)
    }

    private func canHealthCheck(_ row: WorkbenchSourceRow) -> Bool {
        row.source.supportsHealthCheck
            && appModel.canRefreshSelectedRouter
            && appModel.supportsUnifiedAction(.healthCheckProvider)
    }

    private var selectedRow: WorkbenchSourceRow? {
        projectionCache.row(id: selectedRowID)
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { selectedRowID != nil },
            set: { if !$0 { selectedRowID = nil } }
        )
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
            destination: .sources
        )
        kind = workspace.activeTab.flatMap(ProviderSessionKind.init(rawValue:)) ?? .all
        sortOrder = Self.sourceSortOrder(from: workspace.sort)
        selectedRowID = workspace.selectedItemID
        restoredScrollAnchorID = controllerID.flatMap {
            workspaceStore.scrollAnchorID(
                controllerID: $0,
                generation: generation,
                destination: .sources
            )
        }
    }

    private func persistKind() {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .sources
        ) { workspace in
            workspace.activeTab = kind.rawValue
        }
    }

    private func persistSelection(_ selection: String?) {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .sources
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
            destination: .sources,
            anchorID: anchorID
        )
    }

    private func persistSortOrder() {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .sources
        ) { workspace in
            workspace.sort = sortOrder.compactMap(Self.sourceWorkspaceSort)
        }
    }

    private static func sourceSortOrder(
        from workspaceSort: [WorkbenchWorkspaceSort]
    ) -> [KeyPathComparator<WorkbenchSourceRow>] {
        workspaceSort.compactMap { item -> KeyPathComparator<WorkbenchSourceRow>? in
            let order: SortOrder = item.ascending ? .forward : .reverse
            switch item.field {
            case "name": return KeyPathComparator(\WorkbenchSourceRow.name, order: order)
            case "type": return KeyPathComparator(\WorkbenchSourceRow.type, order: order)
            case "itemCount": return KeyPathComparator(\WorkbenchSourceRow.itemCount, order: order)
            default: return nil
            }
        }
    }

    private static func sourceWorkspaceSort(
        _ comparator: KeyPathComparator<WorkbenchSourceRow>
    ) -> WorkbenchWorkspaceSort? {
        let field: String
        if comparator.keyPath == \WorkbenchSourceRow.name {
            field = "name"
        } else if comparator.keyPath == \WorkbenchSourceRow.type {
            field = "type"
        } else if comparator.keyPath == \WorkbenchSourceRow.itemCount {
            field = "itemCount"
        } else {
            return nil
        }
        return WorkbenchWorkspaceSort(
            field: field,
            ascending: comparator.order == .forward
        )
    }

    private var allRows: [WorkbenchSourceRow] {
        projectionCache.allRows
    }

    private var rows: [WorkbenchSourceRow] {
        projectionCache.visibleRows
    }
}
