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

    @State private var model = WorkbenchLogsModel()

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
        .background {
            WorkbenchLogsCatalogObserver(
                appModel: appModel,
                workspaceStore: workspaceStore,
                model: model,
                query: searchText,
                language: language
            )
        }
        .onChange(of: model.level) {
            persistLogLevel()
        }
        .onChange(of: model.followsNewest) { _, follows in
            persistFollowNewest(follows)
        }
        .onChange(of: model.selectedRowID) { _, selection in
            persistSelection(selection)
            if let selection {
                workspaceStore.selectInspector(.log(id: selection))
            } else {
                workspaceStore.clearInspectorSelection(ownedBy: .logs)
            }
        }
        .onChange(of: workspaceStore.inspectorSelection) { _, selection in
            if case .none = selection, model.selectedRowID != nil {
                model.select(nil)
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
                value: String(model.rows.count),
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
                    get: { model.level },
                    set: { level in
                        guard let commandScope else { return }
                        guard appModel.matchesCurrentCommandScope(commandScope) else { return }
                        model.setLevel(level)
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
                isOn: Binding(get: { model.followsNewest }, set: { model.setFollowing($0) })
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
                isEnabled: supportsLogs && model.sourceCount > 0 && !appModel.isBusy,
                role: .destructive
            ) {
                appModel.clearControllerLogs()
                model.select(nil)
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
            scope: WorkbenchSessionIdentity(
                controllerID: controllerID,
                generation: generation
            ),
            title: localization.localizedKey("dashboard.tab_logs"),
            sourceRows: model.rows,
            window: model.accessibilityWindow,
            selectedRowID: model.selectedRowID,
            localization: localization,
            summary: WorkbenchLogProjection.accessibilitySummary
        )
        return WorkbenchDataTableViewport(
            generation: generation,
            restorationID: model.restoredScrollAnchorID,
            request: model.scrollRequest,
            anchor: .bottom,
            interaction: model.interaction,
            rowIndex: { id in model.rows.firstIndex { $0.id == id } },
            rowID: { index in model.rows.indices.contains(index) ? model.rows[index].id : nil },
            onInteractionBegan: { model.setFollowing(false) },
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
                Table(model.rows, selection: selectionBinding) {
                    switch mode {
                    case .full:
                        TableColumn(MicaStrings.localizedKey("traffic.log_payload", language: language)) { row in
                            logPayload(row)
                        }
                        .width(min: 320, ideal: 720)

                        TableColumn(MicaStrings.localizedKey("traffic.log_level", language: language)) { row in
                            logLevel(row)
                        }
                        .width(min: 82, ideal: 96, max: 124)

                        TableColumn(MicaStrings.localizedKey("traffic.log_type", language: language)) { row in
                            logType(row)
                        }
                        .width(min: 112, ideal: 136, max: 180)

                        TableColumn(MicaStrings.localizedKey("traffic.log_received_time", language: language)) { row in
                            logTimestamp(row)
                        }
                        .width(min: 104, ideal: 120, max: 148)

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
        .task(id: model.followRequest) {
            guard let request = model.followRequest else { return }
            let remainingMilliseconds = Int64(
                ceil(max(0, request.deadline.timeIntervalSinceNow * 1_000))
            )
            if remainingMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(remainingMilliseconds))
            }
            guard !Task.isCancelled else { return }
            model.consumeFollow(request)
        }
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            if !model.followsNewest {
                Button {
                    model.jumpToNewest()
                } label: {
                    MicaLabel("traffic.jump_to_newest", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.bordered)
                .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
                .padding(MicaTheme.Spacing.space3)
            }
        }
    }

    private func logPayload(_ row: WorkbenchLogRow) -> some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            severityRail(row)
            WorkbenchDataText(
                value: row.payloadText,
                role: .dataLabel
            )
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
    }

    private func logTimestamp(_ row: WorkbenchLogRow) -> some View {
        WorkbenchDataText(
            value: row.receivedTimeText,
            role: .dataCaption,
            tone: .secondary
        )
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
        stackedLogEvent(row)
    }

    private func stackedLogEvent(_ row: WorkbenchLogRow) -> some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            severityRail(row)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.payloadText)
                    .micaThemeFont(.dataLabel)
                    .lineLimit(1)
                    .textSelection(.enabled)

                HStack(spacing: MicaTheme.Spacing.space2) {
                    Text(verbatim: row.levelText)
                        .foregroundStyle(row.severity.tint)
                    if row.typeText != row.levelText {
                        Text(verbatim: row.typeText)
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: row.receivedTimeText)
                        .foregroundStyle(.secondary)
                }
                .micaThemeFont(.dataCaption)
                .lineLimit(1)
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

    private var selectionBinding: Binding<String?> {
        Binding(get: { model.selectedRowID }, set: { model.select($0) })
    }

    private var state: WorkbenchDataState {
        WorkbenchDataStateResolver.logs(
            hasController: appModel.selectedRouter != nil,
            isSupported: supportsLogs,
            sourceCount: model.sourceCount,
            visibleCount: model.rows.count,
            isFiltering: model.level != .all || searchText.dataNonEmpty != nil,
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

    private func dispatchAccessibilityIntent(_ intent: WorkbenchTableAccessibilityIntent) {
        let currentScope = WorkbenchSessionIdentity(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
        guard intent.scope == currentScope else { return }

        model.handleAccessibility(intent)
    }

    private var localizedStaleMessage: String? {
        state.staleMessage.map {
            MicaStrings.localized("data.stale_detail \($0)", language: language)
        }
    }

    private func persistLogLevel() {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .logs
        ) { workspace in
            workspace.filters["level"] = model.level.rawValue
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
