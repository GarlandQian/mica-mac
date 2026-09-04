import Foundation
import MicaCore
import SwiftUI

extension WorkbenchLogSeverity {
    fileprivate var tint: Color {
        switch self {
        case .error: MicaTheme.statusError
        case .warning: MicaTheme.statusWarning
        case .info: MicaTheme.textSecondary
        case .debug: MicaTheme.textTertiary
        case .trace: MicaTheme.textTertiary
        }
    }
}

// MARK: - Logs

struct WorkbenchLogsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language
    @Binding var searchText: String

    @State private var projectionCache = WorkbenchLogProjectionCache()
    @State private var selectedRowID: String?
    @State private var logLevel: LogSessionLevel = .all
    @State private var followNewest = true
    @State private var followCadence = WorkbenchLogFollowCadence()
    @State private var restoredScrollAnchorID: String?
    @State private var scrollRequest: WorkbenchDataScrollRequest?
    @State private var tableInteraction = WorkbenchDataInteractionCoordinator()
    @State private var isProjectionActive = false
    @State private var accessibilityCursor = WorkbenchAccessibilityWindowCursor()

    private static let widthBudget = WorkbenchDataWidthBudget(
        fullMinimum: 760,
        compactMinimum: 420
    )

    var body: some View {
        WorkbenchDataBrowserScaffold(
            staleMessage: localizedStaleMessage,
            commands: { commandBar },
            supplementary: { EmptyView() }
        ) {
            pageContent
        }
        .onAppear {
            let projectionCacheBinding = $projectionCache
            workspaceStore.logEntryResolver = { id in
                projectionCacheBinding.wrappedValue.row(id: id)
            }
            if let selectedRowID {
                workspaceStore.selectInspector(.log(id: selectedRowID))
            }
            isProjectionActive = true
            restoreWorkspace()
            rebuildRows(reconcileSelection: true)
            reconcileAccessibilityWindow(revealing: selectedRowID)
        }
        .onDisappear {
            workspaceStore.logEntryResolver = nil
            isProjectionActive = false
            followCadence.cancel()
        }
        .onChange(of: appModel.selectedRouterID) {
            projectionCache.reset()
            followCadence.cancel()
            scrollRequest = nil
            accessibilityCursor.reset()
            restoreWorkspace()
            rebuildRows(reconcileSelection: true)
            reconcileAccessibilityWindow(revealing: selectedRowID)
        }
        .onChange(of: appModel.controllerSessionPresentation.generation) {
            projectionCache.reset()
            followCadence.cancel()
            scrollRequest = nil
            accessibilityCursor.reset()
            restoreWorkspace()
            rebuildRows(reconcileSelection: true)
            reconcileAccessibilityWindow(revealing: selectedRowID)
        }
        .onChange(of: appModel.logsCatalog.entriesRevision) {
            rebuildRows(reconcileSelection: true)
        }
        .onChange(of: logLevel) {
            persistLogLevel()
            rebuildRows(reconcileSelection: true)
            reconcileAccessibilityWindow(revealing: selectedRowID)
        }
        .onChange(of: searchText) {
            rebuildRows(reconcileSelection: true)
            reconcileAccessibilityWindow(revealing: selectedRowID)
        }
        .onChange(of: language) {
            rebuildRows(reconcileSelection: true)
            reconcileAccessibilityWindow(revealing: selectedRowID)
        }
        .onChange(of: followNewest) { _, follows in
            persistFollowNewest(follows)
            reconcileAccessibilityWindow()
            if !follows {
                followCadence.cancel()
            }
        }
        .onChange(of: selectedRowID) { _, selection in
            if selection != nil {
                followNewest = false
            }
            reconcileAccessibilityWindow(revealing: selection)
            persistSelection(selection)
            if let selection {
                workspaceStore.selectInspector(.log(id: selection))
            } else {
                workspaceStore.clearInspectorSelection(ownedBy: .logs)
            }
        }
        .onChange(of: workspaceStore.inspectorSelection) { _, selection in
            if case .none = selection, selectedRowID != nil {
                selectedRowID = nil
            }
        }
    }

    private var commandBar: some View {
        let commandScope = LiveCommandScope(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
        return WorkbenchCommandBar {
            WorkbenchCommandSummary(
                symbolName: "text.alignleft",
                titleKey: "dashboard.tab_logs",
                value: String(rows.count),
                detail: appModel.dashboardSessionControls.logsPresentationPaused
                    ? MicaStrings.localizedKey(
                        "traffic.log_presentation_paused_detail",
                        language: language
                    )
                    : nil
            )
        } controls: {
            Picker(
                MicaStrings.localizedKey("traffic.log_level", language: language),
                selection: Binding(
                    get: { logLevel },
                    set: { level in
                        guard let commandScope else { return }
                        logLevel = level
                        appModel.setControllerLogLevel(level, scope: commandScope)
                    }
                )
            ) {
                ForEach(availableLogLevels) { level in
                    Text(MicaStrings.localizedKey(level.titleKey, language: language))
                        .tag(level)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(appModel.selectedRouter == nil || appModel.isBusy || !canAdjustLogLevel)
            .accessibilityLabel(
                MicaStrings.localizedKey("traffic.log_level", language: language)
            )
            .frame(minHeight: MicaTheme.Metrics.controlMinHeight)

            WorkbenchDataActivityIndicator(
                isActive: appModel.changingControllerLogLevel,
                titleKey: "operation.setting_log_level"
            )

            Toggle(
                MicaStrings.localizedKey("traffic.follow_bottom", language: language),
                isOn: $followNewest
            )
            .toggleStyle(.checkbox)
            .disabled(!supportsLogs)
            .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
        } commands: {
            WorkbenchIconCommand(
                titleKey: appModel.dashboardSessionControls.logsPresentationPaused
                    ? "traffic.resume_logs"
                    : "traffic.pause_logs",
                systemImage: appModel.dashboardSessionControls.logsPresentationPaused
                    ? "play"
                    : "pause",
                isEnabled: supportsLogs && appModel.selectedRouter != nil && !appModel.isBusy
            ) {
                appModel.toggleControllerLogsPaused()
            }

            WorkbenchIconCommand(
                titleKey: "traffic.clear_logs",
                systemImage: "trash",
                isEnabled: supportsLogs && !allRows.isEmpty && !appModel.isBusy,
                role: .destructive
            ) {
                appModel.clearControllerLogs()
                selectedRowID = nil
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
                detailKey: "traffic.logs_loading_message"
            )
        case .unsupported:
            WorkbenchStateView(
                kind: .unsupported,
                titleKey: "traffic.logs_unsupported_title",
                detailKey: "traffic.logs_unsupported_message"
            )
        case .empty:
            WorkbenchStateView(
                kind: .empty,
                titleKey: "dashboard.no_logs_yet",
                detailKey: "dashboard.no_logs_yet_message"
            )
        case .filterEmpty:
            WorkbenchStateView(
                kind: .filterEmpty,
                titleKey: "dashboard.no_matching_logs",
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
            logStream
        }
    }

    private var logStream: some View {
        let controllerID = appModel.selectedRouterID
        let generation = appModel.controllerSessionPresentation.generation
        let localization = MicaStrings.localizationContext(for: language)
        let accessibilityPayload = WorkbenchTableAccessibilityPayload.materialize(
            scope: WorkbenchTableAccessibilityScope(
                controllerID: controllerID,
                generation: generation
            ),
            title: localization.localizedKey("dashboard.tab_logs"),
            sourceRows: rows,
            window: accessibilityWindow,
            selectedRowID: selectedRowID,
            localization: localization,
            summary: WorkbenchLogProjection.accessibilitySummary
        )
        return WorkbenchDataTableViewport(
            generation: generation,
            restorationID: restoredScrollAnchorID,
            request: scrollRequest,
            anchor: .bottom,
            interaction: tableInteraction,
            onInteractionBegan: { followNewest = false },
            onAnchorCommit: { anchorID in
                persistScrollAnchor(
                    anchorID,
                    controllerID: controllerID,
                    generation: generation
                )
            }
        ) {
            WorkbenchDataResponsive(budget: Self.widthBudget) { mode in
                Table(rows, selection: $selectedRowID) {
                    switch mode {
                    case .full:
                        TableColumn(MicaStrings.localizedKey("traffic.log_received_time", language: language)) { row in
                            logTimestamp(row)
                        }
                        .width(min: 104, ideal: 120)

                        TableColumn(MicaStrings.localizedKey("traffic.log_level", language: language)) { row in
                            logLevel(row)
                        }
                        .width(min: 82, ideal: 104)

                        TableColumn(MicaStrings.localizedKey("traffic.log_type", language: language)) { row in
                            logType(row)
                        }
                        .width(min: 112, ideal: 148)

                        TableColumn(MicaStrings.localizedKey("traffic.log_payload", language: language)) { row in
                            WorkbenchDataText(
                                value: row.payloadText,
                                role: .dataLabel
                            )
                        }
                        .width(min: 320, ideal: 720)

                    case .compact:
                        TableColumn(MicaStrings.localizedKey("traffic.log_section_event", language: language)) { row in
                            compactLogEvent(row)
                        }
                        .width(min: 340, ideal: 760)

                    case .stacked:
                        TableColumn(MicaStrings.localizedKey("dashboard.tab_logs", language: language)) { row in
                            stackedLogEvent(row)
                        }
                        .width(min: 220, ideal: 520)
                    }
                }
                .micaWorkbenchTable(
                    accessibilityLabel: MicaStrings.localizedKey(
                        "dashboard.tab_logs",
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
        .onChange(of: rows.last?.id, initial: true) { _, newestID in
            requestAutoScroll(to: newestID)
        }
        .task(id: followCadence.pendingDeadline) {
            guard let pendingDeadline = followCadence.pendingDeadline else { return }
            let remainingMilliseconds = Int64(
                ceil(max(0, pendingDeadline.timeIntervalSinceNow * 1_000))
            )
            if remainingMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(remainingMilliseconds))
            }
            guard !Task.isCancelled,
                  let pendingNewestRowID = followCadence.consume(
                    isEnabled: followNewest,
                    hasSelection: selectedRowID != nil
                  ) else {
                return
            }
            scrollRequest = WorkbenchDataScrollRequest(id: pendingNewestRowID)
        }
        .onChange(of: followNewest) { _, follows in
            if follows {
                scrollToNewest()
            } else {
                followCadence.cancel()
            }
        }
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            if !followNewest {
                Button {
                    followNewest = true
                    selectedRowID = nil
                } label: {
                    MicaLabel("traffic.jump_to_newest", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.bordered)
                .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
                .padding(MicaTheme.Spacing.space3)
            }
        }
    }

    private func logTimestamp(_ row: WorkbenchLogRow) -> some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            severityRail(row)
            WorkbenchDataText(
                value: row.receivedTimeText,
                role: .dataCaption
            )
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
    }

    private func logLevel(_ row: WorkbenchLogRow) -> some View {
        WorkbenchDataText(
            value: row.levelText,
            role: .dataCaption,
            weight: .semibold
        )
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
        .accessibilityLabel(row.levelText)
    }

    private func logType(_ row: WorkbenchLogRow) -> some View {
        HStack(spacing: MicaTheme.Spacing.space1) {
            WorkbenchSymbol(
                systemName: logTypeSymbol(row),
                tint: row.severity.tint,
                size: .inline
            )

            WorkbenchDataText(
                value: row.typeText,
                role: .dataCaption,
                tone: row.typeText == row.levelText ? .secondary : .primary
            )
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
        .accessibilityLabel(row.typeText)
    }

    private func compactLogEvent(_ row: WorkbenchLogRow) -> some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            severityRail(row)

            WorkbenchDataText(
                value: row.receivedTimeText,
                role: .dataCaption,
                tone: .secondary
            )
            .frame(width: 82, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                WorkbenchDataText(
                    value: row.levelText,
                    role: .dataCaption,
                    weight: .semibold
                )
                if row.typeText != row.levelText {
                    WorkbenchDataText(
                        value: row.typeText,
                        role: .dataCaption,
                        tone: .secondary
                    )
                }
            }
            .frame(width: 86, alignment: .leading)

            WorkbenchDataText(
                value: row.payloadText,
                role: .dataLabel
            )
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height
        )
    }

    private func stackedLogEvent(_ row: WorkbenchLogRow) -> some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            severityRail(row)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: MicaTheme.Spacing.space2) {
                    Text(verbatim: row.receivedTimeText)
                        .foregroundStyle(.secondary)
                    Text(verbatim: row.levelText)
                        .foregroundStyle(.primary)
                    if row.typeText != row.levelText {
                        Text(verbatim: row.typeText)
                            .foregroundStyle(.secondary)
                    }
                }
                .micaThemeFont(.dataCaption)
                .lineLimit(1)

                Text(verbatim: row.payloadText)
                    .micaThemeFont(.dataLabel)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
    }

    private func severityRail(_ row: WorkbenchLogRow) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(row.severity.tint.opacity(0.72))
            .frame(width: 3, height: 28)
            .accessibilityHidden(true)
    }

    private func logTypeSymbol(_ row: WorkbenchLogRow) -> String {
        switch row.severity {
        case .error: "exclamationmark.circle"
        case .warning: "exclamationmark.triangle"
        case .info: "info.circle"
        case .debug: "ladybug"
        case .trace: "point.3.connected.trianglepath.dotted"
        }
    }

    private func rebuildRows(reconcileSelection: Bool) {
        guard isProjectionActive else { return }
        let previousRows = projectionCache.allRows
        let previousSelection = selectedRowID
        projectionCache.project(
            entries: appModel.logsCatalog.entries,
            revision: appModel.logsCatalog.entriesRevision,
            level: logLevel,
            query: searchText,
            language: language,
            change: appModel.logsCatalog.lastChange,
            isActive: isProjectionActive
        )

        if reconcileSelection {
            selectedRowID = projectionCache.reconciledSelection(
                previousSelection,
                previousRows: previousRows
            )
        }
        switch projectionCache.accessibilityOrderChange {
        case .unchanged:
            break
        case .replace:
            reconcileAccessibilityWindow(revealing: selectedRowID)
        case .prefixDelta(let droppedCount):
            accessibilityCursor.applyPrefixDelta(
                totalCount: rows.count,
                droppedCount: droppedCount,
                followsNewest: followNewest,
                idAt: { rows.indices.contains($0) ? rows[$0].id : nil }
            )
        }
    }

    private var state: WorkbenchDataState {
        WorkbenchDataStateResolver.logs(
            hasController: appModel.selectedRouter != nil,
            isSupported: supportsLogs,
            sourceCount: allRows.count,
            visibleCount: rows.count,
            isFiltering: logLevel != .all || searchText.dataNonEmpty != nil,
            streamState: appModel.liveStreamState,
            sessionState: appModel.controllerSessionPresentation.state,
            language: language
        )
    }

    private var supportsLogs: Bool {
        appModel.selectedUnifiedCapabilities.logs
    }

    private var availableLogLevels: [LogSessionLevel] {
        LogSessionLevel.availableLevels(
            for: appModel.selectedUnifiedControllerType
        )
    }

    private var canAdjustLogLevel: Bool {
        supportsLogs || appModel.supportsUnifiedAction(.setLogLevel)
    }

    private func scrollToNewest() {
        guard let id = rows.last?.id else { return }
        followCadence.recordImmediateScroll(to: id)
        scrollRequest = WorkbenchDataScrollRequest(id: id)
    }

    private var accessibilityWindow: WorkbenchAccessibilityWindow {
        WorkbenchAccessibilityWindow.resolve(
            totalCount: rows.count,
            preferredLowerBound: accessibilityCursor.lowerBound
        )
    }

    private func reconcileAccessibilityWindow(revealing selectionID: String? = nil) {
        accessibilityCursor.reconcile(
            orderedIDs: rows.map(\.id),
            revealing: selectionID,
            followsNewest: followNewest
        )
    }

    private func moveAccessibilityWindow(to lowerBound: Int) {
        followNewest = false
        accessibilityCursor.move(
            to: lowerBound,
            totalCount: rows.count,
            idAt: { rows.indices.contains($0) ? rows[$0].id : nil }
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
        case .setSort, .performNamedAction:
            break
        }
    }

    private func requestAutoScroll(to newestID: String?) {
        followCadence.request(
            newestRowID: newestID,
            isEnabled: followNewest,
            hasSelection: selectedRowID != nil
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
            destination: .logs
        )
        let storedLevel = workspace.filters["level"].flatMap(LogSessionLevel.init(rawValue:))
        logLevel = storedLevel.map {
            availableLogLevels.contains($0) ? $0 : .all
        } ?? appModel.controllerLogLevel
        followNewest = workspace.filters["followNewest"].flatMap(Bool.init) ?? true
        selectedRowID = workspace.selectedItemID
        restoredScrollAnchorID = controllerID.flatMap {
            workspaceStore.scrollAnchorID(
                controllerID: $0,
                generation: generation,
                destination: .logs
            )
        }
    }

    private func persistLogLevel() {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .logs
        ) { workspace in
            workspace.filters["level"] = logLevel.rawValue
        }
    }

    private func persistFollowNewest(_ follows: Bool) {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .logs
        ) { workspace in
            workspace.filters["followNewest"] = String(follows)
        }
    }

    private func persistSelection(_ selection: String?) {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .logs
        ) { workspace in
            workspace.selectedItemID = selection
        }
    }

    private func persistScrollAnchor(
        _ id: String?,
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
            destination: .logs,
            anchorID: id
        )
    }

    private var allRows: [WorkbenchLogRow] {
        projectionCache.allRows
    }

    private var rows: [WorkbenchLogRow] {
        projectionCache.visibleRows
    }
}

/// Log detail content rendered by the workspace inspector container
/// (`WorkbenchInspectorContainer`, design.md §3); the live row resolves through
/// the destination-registered `logEntryResolver` (task 08-17 Phase 5A).
struct WorkbenchLogInspector: View {
    @Environment(\.micaAppLanguage) private var language

    let row: WorkbenchLogRow?
    let close: () -> Void

    var body: some View {
        if let row {
            let entry = row.entry
            WorkbenchDataInspectorShell(
                title: MicaStrings.localizedKey("traffic.detail_log", language: language),
                subtitle: WorkbenchDataFormat.receivedDateTime(entry.receivedAt, language: language),
                statusText: row.levelText,
                statusTint: row.severity.tint,
                close: close
            ) {
                WorkbenchDataInspectorSection("traffic.log_section_event") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.logEvent(
                            row,
                            language: language
                        )
                    )
                }

                WorkbenchDataInspectorSection("traffic.log_section_content") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.logContent(row)
                    )
                }
            }
        }
    }
}
