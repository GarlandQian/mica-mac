import AppKit
import Foundation
import MicaCore
import SwiftUI

// MARK: - Sources

struct WorkbenchSourcesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.micaAppFontScale) private var fontScale
    @Binding var searchText: String

    @State private var model = WorkbenchSourcesModel()

    private static let widthBudget = WorkbenchDataWidthBudget(
        fullMinimum: 960,
        compactMinimum: 560
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
                    WorkbenchProviderUpdateAllProgressView(
                        progress: progress,
                        onDismiss: {
                            appModel.dismissProviderUpdateAllProgress()
                        }
                    )
                }

                if let selectedRow = model.selectedRow {
                    WorkbenchSourceFocusRail(
                        projection: WorkbenchSourceFocusProjection(
                            row: selectedRow,
                            language: language
                        ),
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
                value: model.rows.count == model.sourceCount
                    ? model.sourceCount.formatted()
                    : "\(model.rows.count.formatted()) / \(model.sourceCount.formatted())",
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
            WorkbenchLabeledCommand(
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
            if model.kind != .all || searchText.dataNonEmpty != nil {
                WorkbenchStateView(
                    kind: .filterEmpty,
                    titleKey: "dashboard.no_matching_sources",
                    detailKey: "traffic.empty_filtered",
                    actionTitleKey: model.kind != .all
                        ? "traffic.rule_facets_clear"
                        : "action.clear_search",
                    actionSystemImage: model.kind != .all
                        ? "line.3.horizontal.decrease.circle"
                        : "xmark.circle",
                    action: {
                        model.setKind(.all)
                        searchText = ""
                    }
                )
            } else {
                WorkbenchStateView(
                    kind: .filterEmpty,
                    titleKey: "dashboard.no_matching_sources",
                    detailKey: "traffic.empty_filtered"
                )
            }
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
            rowIndex: { id in model.visibleIndex(id: id) },
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
                        .width(min: 180, ideal: 260)

                        TableColumn(
                            MicaStrings.localizedKey("traffic.source_section_configuration", language: language),
                            value: \.type
                        ) { row in
                            sourceConfiguration(row)
                        }
                        .width(min: 180, ideal: 250)

                        TableColumn(
                            MicaStrings.localizedKey("traffic.provider_items", language: language),
                            value: \.itemCount
                        ) { row in
                            WorkbenchDataMetric(value: row.itemCountText)
                        }
                        .width(min: 68, ideal: 84)

                        TableColumn(
                            MicaStrings.localizedKey("traffic.updated_at", language: language),
                            value: \.updatedAtSortKey
                        ) { row in
                            WorkbenchDataText(
                                value: row.displayUpdatedText,
                                role: .dataCaption,
                                tone: row.source.updatedAt?.dataNonEmpty == nil ? .tertiary : .secondary
                            )
                        }
                        .width(min: 136, ideal: 176)

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
                        .width(min: 260, ideal: 400)

                        TableColumn(MicaStrings.localizedKey("traffic.source_section_status", language: language)) { row in
                            sourceCompactSummary(row)
                        }
                        .width(min: 220, ideal: 280)

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
                .contextMenu(forSelectionType: WorkbenchSourceRow.ID.self) { ids in
                    if let id = ids.first, let row = model.row(id: id) {
                        sourceContextMenu(for: row)
                    }
                }
                .micaWorkbenchTable(
                    accessibilityLabel: MicaStrings.localizedKey(
                        "dashboard.tab_providers",
                        language: language
                    ),
                    lines: mode == .full ? 2 : 2
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
            minHeight: WorkbenchDataRowGeometry.height(for: fontScale, lines: 2),
            maxHeight: WorkbenchDataRowGeometry.height(for: fontScale, lines: 2),
            alignment: .leading
        )
    }

    private func sourceStatus(_ row: WorkbenchSourceRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            sourceUpdateState(row)
            sourceHealthState(row, showsTitle: true)
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height(for: fontScale, lines: 2),
            maxHeight: WorkbenchDataRowGeometry.height(for: fontScale, lines: 2),
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
                value: WorkbenchDataFormat.joined([
                    row.itemCountText,
                    row.displayUpdatedText,
                ]) ?? row.displayUpdatedText,
                role: .dataCaption,
                tone: .secondary
            )
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height(for: fontScale, lines: 2),
            maxHeight: WorkbenchDataRowGeometry.height(for: fontScale, lines: 2),
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
                    value: WorkbenchDataFormat.joined([
                        row.itemCountText,
                        row.displayUpdatedText,
                    ]) ?? row.displayUpdatedText,
                    role: .dataCaption,
                    tone: .secondary,
                    alignment: .trailing
                )
            }
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height(for: fontScale, lines: 2),
            maxHeight: WorkbenchDataRowGeometry.height(for: fontScale, lines: 2)
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
                .foregroundStyle(MicaTheme.textSecondary.opacity(row.source.supportsHealthCheck ? 1 : 0.45))
                .frame(width: 12)
                .accessibilityHidden(true)

            if showsTitle {
                Text(
                    verbatim: row.source.supportsHealthCheck
                        ? row.healthCheckAvailabilityText
                        : "—"
                )
                .micaThemeFont(.caption)
                .foregroundStyle(row.source.supportsHealthCheck ? .secondary : .tertiary)
                .lineLimit(1)
            }
        }
        .help(row.healthCheckAvailabilityText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.healthCheckAvailabilityText)
    }

    @ViewBuilder
    private func sourceContextMenu(for row: WorkbenchSourceRow) -> some View {
        let commandScope = model.scope.flatMap {
            LiveCommandScope(controllerID: $0.controllerID, generation: $0.generation)
        }
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.source.name, forType: .string)
        } label: {
            Label(MicaStrings.localizedKey("action.copy_name", language: language), systemImage: "doc.on.doc")
        }
        if let testURL = row.source.testURL?.dataNonEmpty {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(testURL, forType: .string)
            } label: {
                Label(MicaStrings.localizedKey("action.copy_test_url", language: language), systemImage: "doc.on.doc")
            }
        }
        if row.source.updatable || row.source.supportsHealthCheck {
            Divider()
        }
        if row.source.updatable {
            Button {
                guard let commandScope else { return }
                appModel.updateProxyProvider(row.source, scope: commandScope)
            } label: {
                Label(MicaStrings.localizedKey("action.provider_update", language: language), systemImage: "arrow.clockwise")
            }
            .disabled(!canUpdate(row) || appModel.updatingProviderName == row.source.id)
        }
        if row.source.supportsHealthCheck {
            Button {
                guard let commandScope else { return }
                appModel.healthCheckProxyProvider(row.source, scope: commandScope)
            } label: {
                Label(MicaStrings.localizedKey("action.provider_health_check", language: language), systemImage: "waveform.path.ecg")
            }
            .disabled(!canHealthCheck(row) || appModel.checkingProviderName == row.source.id)
        }
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
