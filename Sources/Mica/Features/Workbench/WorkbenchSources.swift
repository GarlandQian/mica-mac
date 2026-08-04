import Foundation
import MicaCore
import SwiftUI

extension WorkbenchDataInspectorProjection {
    static func sourceConfiguration(
        _ row: WorkbenchSourceRow
    ) -> [WorkbenchDataInspectorValue] {
        let source = row.source
        return [
            value("source.id", "dashboard.col_id", source.id, monospaced: true),
            value("source.kind", "traffic.provider_kind", row.kindText),
            value("source.type", "dashboard.col_provider_type", source.type, monospaced: true),
            value("source.vehicle", "dashboard.col_vehicle", source.vehicleType, monospaced: true),
            value("source.behavior", "traffic.provider_behavior", source.behavior, monospaced: true),
            value("source.format", "traffic.provider_format", source.format, monospaced: true),
            value("source.test-url", "routing.test_url", source.testURL, monospaced: true),
            value("source.item-count", "traffic.provider_items", String(source.itemCount), monospaced: true),
        ]
    }

    static func sourceStatus(
        _ row: WorkbenchSourceRow
    ) -> [WorkbenchDataInspectorValue] {
        let source = row.source
        return [
            value("source.updated-at", "traffic.updated_at", WorkbenchDataFormat.reportedTimestamp(source.updatedAt), monospaced: true),
            value("source.health-check", "traffic.provider_health_check", source.healthCheckText, monospaced: true),
            value("source.subscription-info", "traffic.provider_subscription_info", source.subscriptionInfoText, monospaced: true),
        ]
    }

}

// MARK: - Source projection

struct WorkbenchSourceRow: Identifiable, Equatable {
    let id: String
    let identityFamily: String
    let sourceIndex: Int
    let source: ProxyProviderViewState
    let kindText: String
    let updatedText: String
    let typeText: String
    let configurationDetailText: String?
    let compactConfigurationText: String
    let itemCountText: String
    let compactStatusText: String
    let updatableText: String
    let healthCheckAvailabilityText: String
    let searchText: String

    var name: String { source.name }
    var type: String { source.type }
    var itemCount: Int { source.itemCount }
}

enum WorkbenchSourceProjection {
    static func rows(
        from sources: [ProxyProviderViewState],
        language: AppLanguage
    ) -> [WorkbenchSourceRow] {
        var identities = WorkbenchStableRowIdentityBuilder(
            reportedIDs: sources.map(\.id)
        )
        return sources.enumerated().map { index, source in
            let kindText = MicaStrings.localizedKey(
                source.kind == .proxy
                    ? "traffic.provider_kind_proxy"
                    : "traffic.provider_kind_rule",
                language: language
            )
            let updatedText = WorkbenchDataFormat.providerUpdatedAt(
                source.updatedAt,
                language: language
            ) ?? MicaStrings.localizedKey("overview.config_not_reported", language: language)
            let typeText = WorkbenchDataFormat.reported(
                source.type,
                language: language
            )
            let configurationDetailText = WorkbenchDataFormat.joined([
                source.vehicleType,
                source.format,
                source.behavior,
            ])
            let compactConfigurationText = WorkbenchDataFormat.joined([
                typeText,
                WorkbenchDataFormat.reported(
                    source.vehicleType,
                    language: language
                ),
                WorkbenchDataFormat.reported(
                    source.format,
                    language: language
                ),
            ]) ?? typeText
            let itemCountText = String(source.itemCount)
            let updatableText = MicaStrings.localizedKey(
                source.updatable
                    ? "traffic.provider_updatable_yes"
                    : "traffic.provider_updatable_no",
                language: language
            )
            let healthCheckAvailabilityText = MicaStrings.localizedKey(
                source.supportsHealthCheck
                    ? "traffic.provider_health_check_available"
                    : "traffic.provider_health_check_unavailable",
                language: language
            )
            let identity = identities.make(
                reportedID: source.id,
                fallbackComponents: [
                    source.kind.rawValue, source.name, source.type,
                    source.vehicleType ?? "", source.behavior ?? "",
                ]
            )
            return WorkbenchSourceRow(
                id: identity.id,
                identityFamily: identity.family,
                sourceIndex: index,
                source: source,
                kindText: kindText,
                updatedText: updatedText,
                typeText: typeText,
                configurationDetailText: configurationDetailText,
                compactConfigurationText: compactConfigurationText,
                itemCountText: itemCountText,
                compactStatusText: WorkbenchDataFormat.joined([
                    itemCountText,
                    updatedText,
                ]) ?? updatedText,
                updatableText: updatableText,
                healthCheckAvailabilityText: healthCheckAvailabilityText,
                searchText: [
                    source.id, source.name, kindText, source.type, source.behavior ?? "",
                    source.format ?? "", source.vehicleType ?? "", source.updatedAt ?? "",
                    updatedText, source.testURL ?? "", source.healthCheckText ?? "",
                    source.subscriptionInfoText ?? "", String(source.itemCount),
                ].joined(separator: "\n")
            )
        }
    }

    static func visibleRows(
        from rows: [WorkbenchSourceRow],
        kind: ProviderSessionKind,
        query: String,
        sortOrder: [KeyPathComparator<WorkbenchSourceRow>]
    ) -> [WorkbenchSourceRow] {
        let query = query.dataNonEmpty
        let filtered = rows.filter { row in
            guard kind.matches(row.source.kind) else { return false }
            guard let query else { return true }
            return row.searchText.localizedCaseInsensitiveContains(query)
        }
        return sortOrder.isEmpty ? filtered : filtered.sorted(using: sortOrder)
    }

    static func updateTargets(
        from sources: [ProxyProviderViewState]
    ) -> [ProxyProviderViewState] {
        sources.filter(\.updatable)
    }
}

struct WorkbenchSourceFocusProjection: Equatable {
    let name: String
    let configuration: String
    let itemCount: String
    let updatedAt: String
    let health: String?

    init(row: WorkbenchSourceRow) {
        name = row.source.name
        configuration = WorkbenchDataFormat.joined([
            row.kindText,
            row.typeText,
        ]) ?? row.typeText
        itemCount = row.itemCountText
        updatedAt = row.updatedText
        health = row.source.healthCheckText?.dataNonEmpty
    }
}

enum WorkbenchSourceProjectionUpdate {
    case source
    case visibleOnly
}

struct WorkbenchSourceProjectionCache {
    private(set) var allRows: [WorkbenchSourceRow] = []
    private(set) var visibleRows: [WorkbenchSourceRow] = []
    private(set) var updatableSourceCount = 0
    private(set) var sourceProjectionCount = 0
    private(set) var staticRowProjectionCount = 0
    private(set) var filterProjectionCount = 0
    private(set) var sortProjectionCount = 0

    private var kind: ProviderSessionKind?
    private var query: String?
    private var sortOrder: [KeyPathComparator<WorkbenchSourceRow>] = []
    private var filteredSourceIndices: [Int] = []
    private var rowIndexByID: [String: Int] = [:]

    @discardableResult
    mutating func project(
        update: WorkbenchSourceProjectionUpdate,
        sources: [ProxyProviderViewState],
        kind: ProviderSessionKind,
        query: String,
        sortOrder: [KeyPathComparator<WorkbenchSourceRow>],
        language: AppLanguage,
        isActive: Bool = true
    ) -> Bool {
        guard isActive else { return false }

        let sourceChanged: Bool
        switch update {
        case .source:
            allRows = WorkbenchSourceProjection.rows(from: sources, language: language)
            updatableSourceCount = sources.lazy.filter(\.updatable).count
            rowIndexByID = Dictionary(
                uniqueKeysWithValues: allRows.enumerated().map {
                    ($0.element.id, $0.offset)
                }
            )
            sourceProjectionCount += 1
            staticRowProjectionCount += allRows.count
            sourceChanged = true
        case .visibleOnly:
            sourceChanged = false
        }

        let normalizedQuery = query.dataNonEmpty
        let filterChanged = self.kind != kind || self.query != normalizedQuery
        let sortChanged = self.sortOrder != sortOrder

        if sourceChanged || filterChanged {
            filteredSourceIndices = allRows.indices.filter { index in
                let row = allRows[index]
                guard kind.matches(row.source.kind) else { return false }
                guard let normalizedQuery else { return true }
                return row.searchText.localizedCaseInsensitiveContains(normalizedQuery)
            }
            filterProjectionCount += 1
        }

        if sourceChanged || filterChanged || sortChanged {
            visibleRows = filteredSourceIndices.map { allRows[$0] }
            if !sortOrder.isEmpty {
                visibleRows.sort(using: sortOrder)
                sortProjectionCount += 1
            }
        }

        self.kind = kind
        self.query = normalizedQuery
        self.sortOrder = sortOrder
        return sourceChanged || filterChanged || sortChanged
    }

    func row(id: String?) -> WorkbenchSourceRow? {
        guard let id, let index = rowIndexByID[id], allRows.indices.contains(index) else {
            return nil
        }
        return allRows[index]
    }

    mutating func reset() {
        self = WorkbenchSourceProjectionCache()
    }
}

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
                            VStack(alignment: .leading, spacing: 1) {
                                WorkbenchDataText(
                                    value: row.compactConfigurationText,
                                    style: .caption, design: .monospaced
                                )
                                WorkbenchDataText(
                                    value: row.compactStatusText,
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
                        .width(min: 210, ideal: 280)

                    case .stacked:
                        TableColumn(
                            MicaStrings.localizedKey("dashboard.tab_providers", language: language),
                            value: \.name
                        ) { row in
                            HStack(spacing: MicaSpacing.module) {
                                sourceIdentity(row)
                                Spacer(minLength: MicaSpacing.row)
                                VStack(alignment: .trailing, spacing: 1) {
                                    WorkbenchDataMetric(value: row.itemCountText)
                                    WorkbenchDataText(
                                        value: row.updatedText,
                                        style: .caption, design: .monospaced,
                                        tone: .secondary,
                                        alignment: .trailing
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
            WorkbenchStatusBadge(
                text: row.updatableText,
                tint: row.source.updatable ? MicaDesignTokens.signalMint : .secondary
            )

            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(
                    row.source.supportsHealthCheck
                        ? MicaDesignTokens.signalCyan
                        : Color.secondary
                )
                .help(row.healthCheckAvailabilityText)
                .accessibilityLabel(row.healthCheckAvailabilityText)
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
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

private struct WorkbenchSourceFocusRail: View {
    @Environment(\.micaAppLanguage) private var language

    let projection: WorkbenchSourceFocusProjection
    let supportsUpdate: Bool
    let supportsHealthCheck: Bool
    let canUpdate: Bool
    let canHealthCheck: Bool
    let isUpdating: Bool
    let isChecking: Bool
    let update: () -> Void
    let healthCheck: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.module) {
                lifecyclePath
                Spacer(minLength: MicaSpacing.module)
                healthAndActions
            }

            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                lifecyclePath
                healthAndActions
            }
        }
        .padding(.horizontal, MicaBounds.chromeHorizontalPadding)
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaDesignTokens.contentFill)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var lifecyclePath: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.row) {
                sourceStep
                    .frame(minWidth: 170, maxWidth: 260)
                WorkbenchDecisionPathConnector()
                configurationStep
                    .frame(minWidth: 150, maxWidth: 220)
                WorkbenchDecisionPathConnector()
                itemStep
                    .frame(minWidth: 132, maxWidth: 190)
                WorkbenchDecisionPathConnector()
                updatedStep
                    .frame(minWidth: 160, maxWidth: 240)
            }

            VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                sourceStep
                configurationStep
                itemStep
                updatedStep
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "dashboard.col_provider",
            value: projection.name,
            systemImage: "shippingbox",
            tint: MicaDesignTokens.signalViolet
        )
    }

    private var itemStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "traffic.provider_items",
            value: projection.itemCount,
            systemImage: "list.number",
            tint: MicaDesignTokens.signalCyan,
            monospaced: true
        )
    }

    private var configurationStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "traffic.source_section_configuration",
            value: projection.configuration,
            systemImage: "slider.horizontal.3",
            tint: MicaDesignTokens.signalCyan,
            monospaced: true
        )
    }

    private var updatedStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "traffic.updated_at",
            value: projection.updatedAt,
            systemImage: "clock.arrow.circlepath",
            tint: .secondary,
            monospaced: true
        )
    }

    private var healthAndActions: some View {
        HStack(spacing: MicaSpacing.tight) {
            if let health = projection.health {
                WorkbenchDecisionReadout(
                    titleKey: "traffic.provider_health_check",
                    value: health,
                    systemImage: "waveform.path.ecg",
                    tint: MicaDesignTokens.signalMint,
                    monospaced: true
                )
            }

            if isChecking {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: MicaBounds.iconControlSize, minHeight: MicaBounds.iconControlSize)
            } else if supportsHealthCheck {
                WorkbenchIconCommand(
                    titleKey: "action.provider_health_check",
                    systemImage: "waveform.path.ecg",
                    isEnabled: canHealthCheck,
                    action: healthCheck
                )
            }

            if isUpdating {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: MicaBounds.iconControlSize, minHeight: MicaBounds.iconControlSize)
            } else if supportsUpdate {
                WorkbenchIconCommand(
                    titleKey: "action.provider_update",
                    systemImage: "arrow.clockwise",
                    isEnabled: canUpdate,
                    action: update
                )
            }
        }
        .frame(minHeight: MicaBounds.controlMinHeight, alignment: .trailing)
    }
}

private struct WorkbenchProviderUpdateAllProgressView: View {
    @Environment(\.micaAppLanguage) private var language

    let progress: ProviderUpdateAllProgress

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MicaSpacing.module) {
                    currentStatus
                    Spacer(minLength: MicaSpacing.module)
                    counters
                }

                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    currentStatus
                    counters
                }
            }

            ProgressView(
                value: Double(progress.completed),
                total: Double(max(progress.total, 1))
            )
            .progressViewStyle(.linear)
            .tint(progress.failed > 0 ? MicaDesignTokens.signalAmber : MicaDesignTokens.accent)
            .accessibilityLabel(
                MicaStrings.localizedKey(
                    "traffic.provider_update_all_progress",
                    language: language
                )
            )
            .accessibilityValue(
                MicaStrings.localized(
                    "traffic.provider_update_completed_count \(progress.completed) \(progress.total)",
                    language: language
                )
            )

            if !progress.failures.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: MicaSpacing.tight) {
                        ForEach(progress.failures) { failure in
                            Label {
                                Text(verbatim: "\(failure.target.name): \(failure.message)")
                                    .micaFont(.caption)
                                    .textSelection(.enabled)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(MicaDesignTokens.signalAmber)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 112)
            }
        }
        .padding(.horizontal, MicaBounds.chromeHorizontalPadding)
        .padding(.vertical, MicaSpacing.row)
        .background(MicaDesignTokens.elevatedFill)
        .overlay(alignment: .bottom) { Divider() }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(progressTint)
                .frame(width: 3)
                .accessibilityHidden(true)
        }
    }

    private var progressTint: Color {
        if progress.isRunning {
            return MicaDesignTokens.signalCyan
        }
        return progress.failed > 0
            ? MicaDesignTokens.signalAmber
            : MicaDesignTokens.signalMint
    }

    private var currentStatus: some View {
        HStack(spacing: MicaSpacing.row) {
            if progress.isRunning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: progress.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(
                        progress.failed == 0
                            ? MicaDesignTokens.signalMint
                            : MicaDesignTokens.signalAmber
                    )
                    .accessibilityHidden(true)
            }

            Text(verbatim: currentStatusText)
                .micaFont(.callout, weight: .semibold)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private var currentStatusText: String {
        if let current = progress.current {
            return MicaStrings.localized(
                "traffic.provider_update_current \(current.name)",
                language: language
            )
        }

        return MicaStrings.localizedKey(
            progress.isRunning
                ? "traffic.provider_update_refreshing"
                : "traffic.provider_update_complete",
            language: language
        )
    }

    private var counters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.module) {
                completedCounter
                succeededCounter
                failedCounter
            }

            VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                completedCounter
                succeededCounter
                failedCounter
            }
        }
    }

    private var completedCounter: some View {
        progressCounter(
            MicaStrings.localized(
                "traffic.provider_update_completed_count \(progress.completed) \(progress.total)",
                language: language
            ),
            systemImage: "list.bullet"
        )
    }

    private var succeededCounter: some View {
        progressCounter(
            MicaStrings.localized(
                "traffic.provider_update_succeeded_count \(progress.succeeded)",
                language: language
            ),
            systemImage: "checkmark.circle",
            tint: MicaDesignTokens.signalMint
        )
    }

    private var failedCounter: some View {
        progressCounter(
            MicaStrings.localized(
                "traffic.provider_update_failed_count \(progress.failed)",
                language: language
            ),
            systemImage: "exclamationmark.triangle",
            tint: progress.failed > 0 ? MicaDesignTokens.signalAmber : .secondary
        )
    }

    private func progressCounter(
        _ text: String,
        systemImage: String,
        tint: Color = .secondary
    ) -> some View {
        Label {
            Text(verbatim: text)
                .micaFont(.caption).monospacedDigit()
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WorkbenchSourceInspector: View {
    @Environment(\.micaAppLanguage) private var language

    let row: WorkbenchSourceRow?
    let updateFailure: String?
    let healthFailure: String?
    let close: () -> Void

    var body: some View {
        if let row {
            let source = row.source
            WorkbenchDataInspectorShell(
                title: source.name,
                statusText: MicaStrings.localizedKey(
                    source.updatable
                        ? "traffic.provider_updatable_yes"
                        : "traffic.provider_updatable_no",
                    language: language
                ),
                statusTint: source.updatable ? MicaDesignTokens.signalMint : .secondary,
                close: close
            ) {
                WorkbenchDataInspectorSection("traffic.source_section_configuration") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.sourceConfiguration(row)
                    )
                }

                WorkbenchDataInspectorSection("traffic.source_section_status") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.sourceStatus(row)
                    )
                    if let updateFailure {
                        WorkbenchDataInspectorField(
                            titleKey: "traffic.update_status",
                            value: updateFailure
                        )
                    }
                    if let healthFailure {
                        WorkbenchDataInspectorField(
                            titleKey: "traffic.health_check_status",
                            value: healthFailure
                        )
                    }
                }
            }
        }
    }
}
