import Foundation
import MicaCore
import SwiftUI

// MARK: - Sources

struct WorkbenchSourcesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language
    @Binding var searchText: String

    @State private var model = WorkbenchSourcesModel()

    private static let widthBudget = WorkbenchDataWidthBudget(
        fullMinimum: 960,
        compactMinimum: 520
    )

    var body: some View {
        let commandScope = model.scope.flatMap {
            LiveCommandScope(controllerID: $0.controllerID, generation: $0.generation)
        }
        WorkbenchDataBrowserScaffold(
            staleMessage: localizedStaleMessage,
            commands: { commandBar },
            supplementary: {
                if let progress = appModel.providerUpdateAllProgress {
                    WorkbenchProviderUpdateAllProgressView(progress: progress)
                }

                if let selectedRow = model.selectedRow {
                    WorkbenchSourceFocusRail(
                        projection: WorkbenchSourceFocusProjection(row: selectedRow),
                        supportsUpdate: selectedRow.source.updatable,
                        supportsHealthCheck: selectedRow.source.supportsHealthCheck,
                        canUpdate: canUpdate(selectedRow),
                        canHealthCheck: canHealthCheck(selectedRow),
                        isUpdating: appModel.updatingProviderName == selectedRow.source.id,
                        isChecking: appModel.checkingProviderName == selectedRow.source.id,
                        update: {
                            guard let commandScope else { return }
                            appModel.updateProxyProvider(selectedRow.source, scope: commandScope)
                        },
                        healthCheck: {
                            guard let commandScope else { return }
                            appModel.healthCheckProxyProvider(selectedRow.source, scope: commandScope)
                        }
                    )
                }
            }
        ) {
            pageContent
        }
        .background {
            WorkbenchSourcesCatalogObserver(
                appModel: appModel,
                workspaceStore: workspaceStore,
                model: model,
                query: searchText,
                language: language
            )
        }
        .onChange(of: model.kind) {
            persistKind()
        }
        .onChange(of: model.sortOrder) {
            persistSortOrder()
        }
        .onChange(of: model.selectedRowID) { _, selection in
            persistSelection(selection)
            if let selection {
                workspaceStore.selectInspector(.source(id: selection))
            } else {
                workspaceStore.clearInspectorSelection(ownedBy: .sources)
            }
        }
        .onChange(of: workspaceStore.inspectorSelection) { _, selection in
            if case .none = selection, model.selectedRowID != nil {
                model.select(nil)
            }
        }
    }

    private var commandBar: some View {
        WorkbenchCommandBar {
            WorkbenchCommandSummary(
                symbolName: "shippingbox",
                titleKey: "dashboard.tab_providers",
                value: String(model.rows.count),
                detail: nil
            )
        } controls: {
            ViewThatFits(in: .horizontal) {
                sourceKindPicker
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)

                sourceKindPicker
                    .pickerStyle(.menu)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

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

    private var sourceKindPicker: some View {
        Picker(
            MicaStrings.localizedKey("traffic.source_kind", language: language),
            selection: Binding(
                get: { model.kind },
                set: { model.setKind($0) }
            )
        ) {
            ForEach(ProviderSessionKind.allCases) { option in
                Text(MicaStrings.localizedKey(option.titleKey, language: language))
                    .tag(option)
            }
        }
        .labelsHidden()
        .accessibilityLabel(
            MicaStrings.localizedKey("traffic.source_kind", language: language)
        )
        .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
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
        }
    }

    private var sourceTable: some View {
        let controllerID = appModel.selectedRouterID
        let generation = appModel.controllerSessionPresentation.generation
        let localization = MicaStrings.localizationContext(for: language)
        let accessibilityPayload = WorkbenchTableAccessibilityPayload.materialize(
            scope: WorkbenchSessionIdentity(
                controllerID: controllerID,
                generation: generation
            ),
            title: localization.localizedKey("dashboard.tab_providers"),
            sourceRows: model.rows,
            window: model.accessibilityWindow,
            selectedRowID: model.selectedRowID,
            localization: localization,
            sortOptions: model.accessibilitySortOptions(language: language),
            summary: WorkbenchSourceProjection.accessibilitySummary
        )
        return WorkbenchDataTableViewport(
            generation: generation,
            restorationID: model.restoredScrollAnchorID,
            interaction: model.interaction,
            rowIndex: { id in model.rows.firstIndex { $0.id == id } },
            rowID: { index in model.rows.indices.contains(index) ? model.rows[index].id : nil },
            onInteractionEnded: {
                model.finishDeferredPresentation(
                    scope: WorkbenchSessionIdentity(controllerID: controllerID, generation: generation)
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
                Table(model.rows, selection: selectionBinding, sortOrder: sortBinding) {
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
                                role: .dataCaption,
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
                            MicaStrings.localizedKey("dashboard.col_provider", language: language),
                            value: \.name
                        ) { row in
                            sourceIdentity(row, includesConfiguration: true)
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

    private func sourceIdentity(
        _ row: WorkbenchSourceRow,
        includesConfiguration: Bool = false
    ) -> some View {
        WorkbenchDataPrimaryCell(
            title: row.source.name,
            detail: includesConfiguration
                ? WorkbenchDataFormat.joined([row.kindText, row.compactConfigurationText])
                : row.kindText,
            systemImage: row.source.kind == .proxy ? "network" : "doc.text",
            tint: MicaTheme.textSecondary,
            detailIsMonospaced: includesConfiguration
        )
    }

    private func sourceConfiguration(_ row: WorkbenchSourceRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            WorkbenchDataText(
                value: row.typeText,
                role: .dataLabel,
                weight: .semibold,
                maximumLineCount: 1
            )
            if let configurationDetailText = row.configurationDetailText {
                WorkbenchDataText(
                    value: configurationDetailText,
                    role: .dataCaption,
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
        VStack(alignment: .leading, spacing: 1) {
            sourceUpdateState(row)
            sourceHealthState(row, showsTitle: true)
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
            HStack(spacing: MicaTheme.Spacing.space2) {
                sourceUpdateState(row)
                sourceHealthState(row, showsTitle: true)
            }

            WorkbenchDataText(
                value: row.compactStatusText,
                role: .dataCaption,
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
        HStack(spacing: MicaTheme.Spacing.space3) {
            sourceIdentity(row, includesConfiguration: true)
            Spacer(minLength: MicaTheme.Spacing.space2)

            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: MicaTheme.Spacing.space1) {
                    sourceUpdateState(row)
                    sourceHealthState(row, showsTitle: true)
                }

                WorkbenchDataText(
                    value: row.stackedSummaryText,
                    role: .dataCaption,
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
        HStack(spacing: MicaTheme.Spacing.space1) {
            Image(systemName: row.source.updatable ? "arrow.clockwise" : "lock")
                .micaThemeFont(.caption)
                .foregroundStyle(MicaTheme.textSecondary)
                .frame(width: 12)
                .accessibilityHidden(true)

            Text(verbatim: row.updatableText)
                .micaThemeFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private func sourceHealthState(
        _ row: WorkbenchSourceRow,
        showsTitle: Bool = false
    ) -> some View {
        HStack(spacing: MicaTheme.Spacing.space1) {
            Image(systemName: "waveform.path.ecg")
                .micaThemeFont(.caption)
                .foregroundStyle(MicaTheme.textSecondary)
                .frame(width: 12)
                .accessibilityHidden(true)

            if showsTitle {
                Text(
                    verbatim: row.source.supportsHealthCheck
                        ? row.healthCheckAvailabilityText
                        : MicaStrings.localizedKey(
                            "overview.config_not_reported",
                            language: language
                        )
                )
                .micaThemeFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .help(row.healthCheckAvailabilityText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.healthCheckAvailabilityText)
    }

    private var selectionBinding: Binding<String?> {
        Binding(get: { model.selectedRowID }, set: { model.select($0) })
    }

    private var sortBinding: Binding<[KeyPathComparator<WorkbenchSourceRow>]> {
        Binding(get: { model.sortOrder }, set: { model.setSortOrder($0) })
    }

    private var state: WorkbenchDataState {
        WorkbenchDataStateResolver.endpoint(
            hasController: appModel.selectedRouter != nil,
            isSupported: appModel.selectedUnifiedCapabilities.providers,
            sourceCount: model.sourceCount,
            visibleCount: model.rows.count,
            isFiltering: model.kind != .all || searchText.dataNonEmpty != nil,
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
        model.updatableSourceCount > 0
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

    private var localizedStaleMessage: String? {
        state.staleMessage.map {
            MicaStrings.localized("data.stale_detail \($0)", language: language)
        }
    }

    private func persistKind() {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .sources
        ) { workspace in
            workspace.activeTab = model.kind.rawValue
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
            workspace.sort = model.workspaceSort
        }
    }

    private func dispatchAccessibilityIntent(_ intent: WorkbenchTableAccessibilityIntent) {
        let currentScope = WorkbenchSessionIdentity(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
        guard intent.scope == currentScope else { return }

        model.handleAccessibility(intent)
    }
}
