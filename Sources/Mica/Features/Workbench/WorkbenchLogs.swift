import Foundation
import MicaCore
import SwiftUI

extension WorkbenchDataInspectorProjection {
    static func logEvent(
        _ row: WorkbenchLogRow,
        language: AppLanguage
    ) -> [WorkbenchDataInspectorValue] {
        let entry = row.entry
        return [
            value("log.id", "dashboard.col_id", entry.id, monospaced: true),
            value(
                "log.received-at",
                "traffic.log_received_time",
                WorkbenchDataFormat.receivedDateTime(entry.receivedAt, language: language),
                monospaced: true
            ),
            value("log.controller-time", "traffic.log_controller_time", WorkbenchDataFormat.reportedTimestamp(entry.message.time), monospaced: true),
            value("log.type", "traffic.log_type", entry.message.type, monospaced: true),
            value("log.level", "traffic.log_level", entry.message.level, monospaced: true),
        ]
    }

    static func logContent(
        _ row: WorkbenchLogRow
    ) -> [WorkbenchDataInspectorValue] {
        [
            value("log.payload", "traffic.log_payload", row.entry.message.payload, monospaced: true),
            value("log.message", "traffic.log_message", row.entry.message.message, monospaced: true),
            value("log.structured-fields", "routing.additional_fields", row.entry.structuredFieldsText, monospaced: true),
        ]
    }
}

// MARK: - Log projection

struct WorkbenchLogRow: Identifiable, Equatable {
    let id: String
    let identityFamily: String
    let entry: ControllerLogEntry
    let severity: WorkbenchLogSeverity
    let searchText: String
    let receivedTimeText: String
    let receivedDateTimeText: String
    let typeText: String
    let levelText: String
    let payloadText: String
    let accessibilityText: String
}

enum WorkbenchLogSeverity: String, CaseIterable, Equatable, Sendable {
    case error
    case warning
    case info
    case debug
    case trace

    init(type: String, level: String?) {
        let candidates = [level?.dataNonEmpty, type.dataNonEmpty]
        for candidate in candidates.compactMap({ $0 }) {
            if let severity = Self.normalized(candidate) {
                self = severity
                return
            }
        }
        self = .info
    }

    var tint: Color {
        switch self {
        case .error: MicaDesignTokens.signalRed
        case .warning: MicaDesignTokens.signalAmber
        case .info: MicaDesignTokens.signalCyan
        case .debug: MicaDesignTokens.signalViolet
        case .trace: MicaDesignTokens.signalViolet
        }
    }

    private static func normalized(_ value: String) -> Self? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "error", "err", "fatal", "panic": .error
        case "warning", "warn": .warning
        case "info", "information", "notice": .info
        case "debug", "verbose": .debug
        case "trace": .trace
        default: nil
        }
    }
}

enum WorkbenchLogProjection {
    static func rows(
        from entries: [ControllerLogEntry],
        language: AppLanguage = .english
    ) -> [WorkbenchLogRow] {
        var identities = WorkbenchStableRowIdentityBuilder(
            reportedIDs: entries.map(\.id)
        )
        return entries.map { entry in
            let structuredFieldsText = entry.structuredFieldsText ?? ""
            let identity = identities.make(
                reportedID: entry.id,
                fallbackComponents: [
                    entry.receivedAt.ISO8601Format(), entry.message.type,
                    entry.message.payload, entry.message.time ?? "",
                    entry.message.level ?? "", entry.message.message ?? "",
                    structuredFieldsText,
                ]
            )
            return projectedRow(
                entry: entry,
                identity: identity,
                language: language,
                structuredFieldsText: structuredFieldsText
            )
        }
    }

    static func visibleRows(
        from rows: [WorkbenchLogRow],
        level: LogSessionLevel,
        query: String
    ) -> [WorkbenchLogRow] {
        let query = query.dataNonEmpty
        if case .all = level, query == nil {
            return rows
        }
        return rows.filter { matches($0, level: level, query: query) }
    }

    static func matches(
        _ row: WorkbenchLogRow,
        level: LogSessionLevel,
        query: String?
    ) -> Bool {
        guard level.matches(row.entry.message.type) else { return false }
        guard let query else { return true }
        return row.searchText.localizedCaseInsensitiveContains(query)
    }

    private static func searchText(
        for entry: ControllerLogEntry,
        structuredFieldsText: String
    ) -> String {
        [
            entry.id, entry.message.type, entry.message.level ?? "",
            entry.message.payload, entry.message.message ?? "",
            entry.message.time ?? "", structuredFieldsText,
        ].joined(separator: "\n")
    }

    fileprivate static func projectedRow(
        entry: ControllerLogEntry,
        identity: WorkbenchStableRowIdentity,
        language: AppLanguage,
        structuredFieldsText: String? = nil
    ) -> WorkbenchLogRow {
        let structuredFieldsText = structuredFieldsText ?? entry.structuredFieldsText ?? ""
        let severity = WorkbenchLogSeverity(
            type: entry.message.type,
            level: entry.message.level
        )
        let receivedTimeText = WorkbenchDataFormat.receivedTime(
            entry.receivedAt,
            language: language
        )
        let receivedDateTimeText = WorkbenchDataFormat.receivedDateTime(
            entry.receivedAt,
            language: language
        )
        let typeText = entry.message.type.dataNonEmpty ?? "-"
        let levelText = entry.message.level?.dataNonEmpty
            ?? entry.message.type.dataNonEmpty
            ?? severity.rawValue.uppercased()
        let payloadText = entry.message.payload.dataNonEmpty ?? "-"
        return WorkbenchLogRow(
            id: identity.id,
            identityFamily: identity.family,
            entry: entry,
            severity: severity,
            searchText: searchText(
                for: entry,
                structuredFieldsText: structuredFieldsText
            ),
            receivedTimeText: receivedTimeText,
            receivedDateTimeText: receivedDateTimeText,
            typeText: typeText,
            levelText: levelText,
            payloadText: payloadText,
            accessibilityText: [
                receivedDateTimeText, levelText, typeText, payloadText,
            ].joined(separator: ", ")
        )
    }
}

struct WorkbenchLogProjectionCache {
    private(set) var allRows: [WorkbenchLogRow] = []
    private(set) var visibleRows: [WorkbenchLogRow] = []
    private(set) var sourceProjectionCount = 0
    private(set) var filterProjectionCount = 0
    private(set) var fullProjectionCount = 0
    private(set) var incrementalProjectionCount = 0
    private(set) var deltaProjectionCount = 0
    private(set) var formattedRowCount = 0
    private(set) var reusedRowCount = 0
    private(set) var filterEvaluationCount = 0
    private(set) var usesStableControllerIDs = false

    private var sourceRevision: UInt64?
    private var language: AppLanguage?
    private var level: LogSessionLevel?
    private var query: String?
    private var stableRowsByID: [String: WorkbenchLogRow] = [:]
    private var stableCacheInitialized = false
    private var rowByID: [String: WorkbenchLogRow] = [:]
    private var filterMatchesByID: [String: Bool] = [:]
    private var visibleRowIDs: Set<String> = []
    private var visibleIncludesAllRows = false

    @discardableResult
    mutating func project(
        entries: [ControllerLogEntry],
        revision: UInt64,
        level: LogSessionLevel,
        query: String,
        language: AppLanguage,
        change: LogsCatalogChange? = nil,
        isActive: Bool = true
    ) -> Bool {
        guard isActive else { return false }

        let sourceChanged = sourceRevision != revision || self.language != language
        var changedRowIDs: Set<String> = []
        var projectedRowsByID: [String: WorkbenchLogRow]?
        var appliedDelta: DeltaReplacement?
        if sourceChanged {
            if self.language == language,
               let replacement = makeDeltaReplacement(
                    entries: entries,
                    revision: revision,
                    change: change,
                    language: language
               ) {
                allRows = replacement.rows
                stableRowsByID = replacement.rowsByID
                projectedRowsByID = replacement.rowsByID
                changedRowIDs = Set(replacement.appendedRows.map(\.id))
                reusedRowCount += replacement.reusedCount
                formattedRowCount += replacement.appendedRows.count
                incrementalProjectionCount += 1
                deltaProjectionCount += 1
                usesStableControllerIDs = true
                appliedDelta = replacement
            } else {
                let stableIDs = Self.stableIDs(for: entries)
                if self.language == language,
                   stableCacheInitialized,
                   let stableIDs {
                    let replacement = replaceRowsByStableID(
                        entries: entries,
                        stableIDs: stableIDs,
                        language: language
                    )
                    allRows = replacement.rows
                    stableRowsByID = replacement.rowsByID
                    projectedRowsByID = replacement.rowsByID
                    changedRowIDs = replacement.changedRowIDs
                    reusedRowCount += replacement.reusedCount
                    formattedRowCount += replacement.formattedCount
                    incrementalProjectionCount += 1
                    usesStableControllerIDs = true
                } else {
                    if let stableIDs {
                        let replacement = projectStableRows(
                            entries: entries,
                            stableIDs: stableIDs,
                            language: language
                        )
                        allRows = replacement.rows
                        stableRowsByID = replacement.rowsByID
                        projectedRowsByID = replacement.rowsByID
                        changedRowIDs = Set(replacement.rowsByID.keys)
                        formattedRowCount += replacement.rows.count
                        stableCacheInitialized = true
                        usesStableControllerIDs = true
                    } else {
                        allRows = WorkbenchLogProjection.rows(
                            from: entries,
                            language: language
                        )
                        stableRowsByID.removeAll(keepingCapacity: true)
                        stableCacheInitialized = false
                        usesStableControllerIDs = false
                        changedRowIDs = Set(allRows.map(\.id))
                        formattedRowCount += allRows.count
                    }
                    fullProjectionCount += 1
                }
            }
            rowByID = projectedRowsByID
                ?? Dictionary(uniqueKeysWithValues: allRows.map { ($0.id, $0) })
            sourceRevision = revision
            self.language = language
            sourceProjectionCount += 1
        }

        let normalizedQuery = query.dataNonEmpty
        let filterChanged = self.level != level || self.query != normalizedQuery
        guard sourceChanged || filterChanged else { return false }

        if case .all = level, normalizedQuery == nil {
            visibleRows = allRows
            visibleIncludesAllRows = true
            visibleRowIDs.removeAll(keepingCapacity: true)
            filterMatchesByID.removeAll(keepingCapacity: true)
        } else if let appliedDelta, !filterChanged {
            applyVisibleDelta(
                appliedDelta,
                level: level,
                query: normalizedQuery
            )
        } else {
            visibleIncludesAllRows = false
            var nextVisibleRows: [WorkbenchLogRow] = []
            var nextMatches: [String: Bool] = [:]
            nextVisibleRows.reserveCapacity(allRows.count)
            nextMatches.reserveCapacity(allRows.count)
            for row in allRows {
                let matches: Bool
                if !filterChanged,
                   !changedRowIDs.contains(row.id),
                   let cached = filterMatchesByID[row.id] {
                    matches = cached
                } else {
                    matches = WorkbenchLogProjection.matches(
                        row,
                        level: level,
                        query: normalizedQuery
                    )
                    filterEvaluationCount += 1
                }
                nextMatches[row.id] = matches
                if matches {
                    nextVisibleRows.append(row)
                }
            }
            visibleRows = nextVisibleRows
            visibleRowIDs = Set(nextVisibleRows.map(\.id))
            filterMatchesByID = nextMatches
        }
        self.level = level
        self.query = normalizedQuery
        filterProjectionCount += 1
        return sourceChanged || filterChanged
    }

    func row(id: String?) -> WorkbenchLogRow? {
        guard let id else { return nil }
        return rowByID[id]
    }

    func reconciledSelection(
        _ selection: String?,
        previousRows: [WorkbenchLogRow]
    ) -> String? {
        guard let selection else { return nil }
        if usesStableControllerIDs {
            let isVisible = visibleIncludesAllRows
                ? rowByID[selection] != nil
                : visibleRowIDs.contains(selection)
            return isVisible ? selection : nil
        }
        return WorkbenchDataSelection.reconciled(
            selection,
            previousRows: previousRows,
            nextVisibleRows: visibleRows,
            identityFamily: \.identityFamily
        )
    }

    mutating func reset() {
        self = WorkbenchLogProjectionCache()
    }

    private struct StableReplacement {
        let rows: [WorkbenchLogRow]
        let rowsByID: [String: WorkbenchLogRow]
        let changedRowIDs: Set<String>
        let reusedCount: Int
        let formattedCount: Int
    }

    private struct DeltaReplacement {
        let rows: [WorkbenchLogRow]
        let rowsByID: [String: WorkbenchLogRow]
        let droppedIDs: Set<String>
        let appendedRows: [WorkbenchLogRow]
        let reusedCount: Int
    }

    private func makeDeltaReplacement(
        entries: [ControllerLogEntry],
        revision: UInt64,
        change: LogsCatalogChange?,
        language: AppLanguage
    ) -> DeltaReplacement? {
        guard stableCacheInitialized,
              usesStableControllerIDs,
              let previousRevision = sourceRevision,
              previousRevision &+ 1 == revision,
              case .some(.delta(let droppedEntryIDs, let appendedEntries)) = change else {
            return nil
        }

        let droppedIDs = Set(droppedEntryIDs)
        guard droppedIDs.count == droppedEntryIDs.count,
              droppedEntryIDs.allSatisfy({ $0.dataNonEmpty != nil }),
              droppedIDs.allSatisfy({ stableRowsByID[$0] != nil }) else {
            return nil
        }

        var appendedIDs: Set<String> = []
        appendedIDs.reserveCapacity(appendedEntries.count)
        for entry in appendedEntries {
            guard let stableID = entry.id.dataNonEmpty,
                  appendedIDs.insert(stableID).inserted else {
                return nil
            }
        }

        let retainedRows: [WorkbenchLogRow]
        if Array(allRows.prefix(droppedEntryIDs.count).map(\.id)) == droppedEntryIDs {
            retainedRows = Array(allRows.dropFirst(droppedEntryIDs.count))
        } else {
            retainedRows = allRows.filter { !droppedIDs.contains($0.id) }
        }
        guard retainedRows.count == allRows.count - droppedIDs.count,
              appendedIDs.allSatisfy({
                  stableRowsByID[$0] == nil || droppedIDs.contains($0)
              }),
              retainedRows.count + appendedEntries.count == entries.count,
              entries.suffix(appendedEntries.count).elementsEqual(appendedEntries) else {
            return nil
        }

        var appendedRows: [WorkbenchLogRow] = []
        appendedRows.reserveCapacity(appendedEntries.count)
        for entry in appendedEntries {
            let stableID = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
            appendedRows.append(
                WorkbenchLogProjection.projectedRow(
                    entry: entry,
                    identity: WorkbenchStableRowIdentity(
                        id: stableID,
                        family: stableID
                    ),
                    language: language
                )
            )
        }

        let rows = retainedRows + appendedRows
        guard rows.first?.entry.id == entries.first?.id,
              rows.last?.entry.id == entries.last?.id else {
            return nil
        }

        var rowsByID = stableRowsByID
        for id in droppedIDs {
            rowsByID.removeValue(forKey: id)
        }
        for row in appendedRows {
            rowsByID[row.id] = row
        }
        return DeltaReplacement(
            rows: rows,
            rowsByID: rowsByID,
            droppedIDs: droppedIDs,
            appendedRows: appendedRows,
            reusedCount: retainedRows.count
        )
    }

    private mutating func applyVisibleDelta(
        _ replacement: DeltaReplacement,
        level: LogSessionLevel,
        query: String?
    ) {
        visibleIncludesAllRows = false
        if !replacement.droppedIDs.isEmpty {
            visibleRows.removeAll { replacement.droppedIDs.contains($0.id) }
            visibleRowIDs.subtract(replacement.droppedIDs)
            for id in replacement.droppedIDs {
                filterMatchesByID.removeValue(forKey: id)
            }
        }

        for row in replacement.appendedRows {
            let matches = WorkbenchLogProjection.matches(
                row,
                level: level,
                query: query
            )
            filterEvaluationCount += 1
            filterMatchesByID[row.id] = matches
            if matches {
                visibleRows.append(row)
                visibleRowIDs.insert(row.id)
            }
        }
    }

    private static func stableIDs(for entries: [ControllerLogEntry]) -> [String]? {
        var seen: Set<String> = []
        var stableIDs: [String] = []
        seen.reserveCapacity(entries.count)
        stableIDs.reserveCapacity(entries.count)
        for entry in entries {
            guard let stableID = entry.id.dataNonEmpty,
                  seen.insert(stableID).inserted else {
                return nil
            }
            stableIDs.append(stableID)
        }
        return stableIDs
    }

    private func projectStableRows(
        entries: [ControllerLogEntry],
        stableIDs: [String],
        language: AppLanguage
    ) -> StableReplacement {
        var rows: [WorkbenchLogRow] = []
        var rowsByID: [String: WorkbenchLogRow] = [:]
        rows.reserveCapacity(entries.count)
        rowsByID.reserveCapacity(entries.count)
        for (entry, stableID) in zip(entries, stableIDs) {
            let row = WorkbenchLogProjection.projectedRow(
                entry: entry,
                identity: WorkbenchStableRowIdentity(
                    id: stableID,
                    family: stableID
                ),
                language: language
            )
            rows.append(row)
            rowsByID[stableID] = row
        }
        return StableReplacement(
            rows: rows,
            rowsByID: rowsByID,
            changedRowIDs: Set(stableIDs),
            reusedCount: 0,
            formattedCount: rows.count
        )
    }

    private func replaceRowsByStableID(
        entries: [ControllerLogEntry],
        stableIDs: [String],
        language: AppLanguage
    ) -> StableReplacement {
        var rows: [WorkbenchLogRow] = []
        var rowsByID: [String: WorkbenchLogRow] = [:]
        var changedRowIDs: Set<String> = []
        var reusedCount = 0
        var formattedCount = 0
        rows.reserveCapacity(entries.count)
        rowsByID.reserveCapacity(entries.count)
        changedRowIDs.reserveCapacity(entries.count)

        for (entry, stableID) in zip(entries, stableIDs) {
            let row: WorkbenchLogRow
            if let previous = stableRowsByID[stableID], previous.entry == entry {
                row = previous
                reusedCount += 1
            } else {
                row = WorkbenchLogProjection.projectedRow(
                    entry: entry,
                    identity: WorkbenchStableRowIdentity(
                        id: stableID,
                        family: stableID
                    ),
                    language: language
                )
                changedRowIDs.insert(stableID)
                formattedCount += 1
            }
            rows.append(row)
            rowsByID[stableID] = row
        }

        return StableReplacement(
            rows: rows,
            rowsByID: rowsByID,
            changedRowIDs: changedRowIDs,
            reusedCount: reusedCount,
            formattedCount: formattedCount
        )
    }
}

struct WorkbenchLogFollowCadence: Equatable {
    static let minimumInterval: TimeInterval = 0.2

    private(set) var lastScrollAt = Date.distantPast
    private(set) var pendingDeadline: Date?
    private(set) var pendingNewestRowID: String?

    mutating func request(
        newestRowID: String?,
        isEnabled: Bool,
        hasSelection: Bool,
        now: Date = Date()
    ) {
        guard isEnabled, !hasSelection, let newestRowID else {
            cancel()
            return
        }

        pendingNewestRowID = newestRowID
        guard pendingDeadline == nil else { return }
        pendingDeadline = max(
            now,
            lastScrollAt.addingTimeInterval(Self.minimumInterval)
        )
    }

    mutating func consume(
        isEnabled: Bool,
        hasSelection: Bool,
        now: Date = Date()
    ) -> String? {
        guard isEnabled, !hasSelection,
              let pendingDeadline,
              pendingDeadline <= now,
              let pendingNewestRowID else {
            if !isEnabled || hasSelection {
                cancel()
            }
            return nil
        }

        lastScrollAt = now
        self.pendingDeadline = nil
        self.pendingNewestRowID = nil
        return pendingNewestRowID
    }

    mutating func recordImmediateScroll(
        to rowID: String,
        now: Date = Date()
    ) {
        lastScrollAt = now
        pendingDeadline = nil
        pendingNewestRowID = nil
    }

    mutating func cancel() {
        pendingDeadline = nil
        pendingNewestRowID = nil
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
            isProjectionActive = true
            restoreWorkspace()
            rebuildRows(reconcileSelection: true)
        }
        .onDisappear {
            isProjectionActive = false
            followCadence.cancel()
        }
        .onChange(of: appModel.selectedRouterID) {
            projectionCache.reset()
            followCadence.cancel()
            scrollRequest = nil
            restoreWorkspace()
            rebuildRows(reconcileSelection: true)
        }
        .onChange(of: appModel.controllerSessionPresentation.generation) {
            projectionCache.reset()
            followCadence.cancel()
            scrollRequest = nil
            restoreWorkspace()
            rebuildRows(reconcileSelection: true)
        }
        .onChange(of: appModel.logsCatalog.entriesRevision) {
            rebuildRows(reconcileSelection: true)
        }
        .onChange(of: logLevel) {
            persistLogLevel()
            rebuildRows(reconcileSelection: true)
        }
        .onChange(of: searchText) { rebuildRows(reconcileSelection: true) }
        .onChange(of: language) { rebuildRows(reconcileSelection: true) }
        .onChange(of: followNewest) { _, follows in
            persistFollowNewest(follows)
            if !follows {
                followCadence.cancel()
            }
        }
        .onChange(of: selectedRowID) { _, selection in
            if selection != nil {
                followNewest = false
            }
            persistSelection(selection)
        }
    }

    private var commandBar: some View {
        WorkbenchCommandBar {
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
                        logLevel = level
                        appModel.setControllerLogLevel(level)
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
            .frame(minHeight: MicaBounds.controlMinHeight)

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
            .frame(minHeight: MicaBounds.controlMinHeight)
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
                .inspector(isPresented: inspectorPresented) {
                    WorkbenchLogInspector(
                        row: selectedRow,
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

    private var logStream: some View {
        let controllerID = appModel.selectedRouterID
        let generation = appModel.controllerSessionPresentation.generation
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
                                style: .callout, design: .monospaced
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
                .frame(minHeight: MicaBounds.controlMinHeight)
                .padding(MicaSpacing.module)
            }
        }
    }

    private func logTimestamp(_ row: WorkbenchLogRow) -> some View {
        HStack(spacing: MicaSpacing.row) {
            severityRail(row)
            WorkbenchDataText(
                value: row.receivedTimeText,
                style: .caption, design: .monospaced
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
            style: .caption, weight: .semibold, design: .monospaced
        )
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
        .accessibilityLabel(row.levelText)
    }

    private func logType(_ row: WorkbenchLogRow) -> some View {
        HStack(spacing: MicaSpacing.tight) {
            WorkbenchSymbol(
                systemName: logTypeSymbol(row),
                tint: row.severity.tint,
                size: .inline
            )

            WorkbenchDataText(
                value: row.typeText,
                style: .caption,
                design: .monospaced,
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
        HStack(spacing: MicaSpacing.row) {
            severityRail(row)

            WorkbenchDataText(
                value: row.receivedTimeText,
                style: .caption, design: .monospaced,
                tone: .secondary
            )
            .frame(width: 82, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                WorkbenchDataText(
                    value: row.levelText,
                    style: .caption, weight: .semibold, design: .monospaced
                )
                if row.typeText != row.levelText {
                    WorkbenchDataText(
                        value: row.typeText,
                        style: .caption2, design: .monospaced,
                        tone: .secondary
                    )
                }
            }
            .frame(width: 86, alignment: .leading)

            WorkbenchDataText(
                value: row.payloadText,
                style: .callout, design: .monospaced
            )
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height
        )
        .accessibilityLabel(row.accessibilityText)
    }

    private func stackedLogEvent(_ row: WorkbenchLogRow) -> some View {
        HStack(spacing: MicaSpacing.row) {
            severityRail(row)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: MicaSpacing.row) {
                    Text(verbatim: row.receivedTimeText)
                        .foregroundStyle(.secondary)
                    Text(verbatim: row.levelText)
                        .foregroundStyle(.primary)
                    if row.typeText != row.levelText {
                        Text(verbatim: row.typeText)
                            .foregroundStyle(.secondary)
                    }
                }
                .micaFont(.caption, design: .monospaced)
                .lineLimit(1)

                Text(verbatim: row.payloadText)
                    .micaFont(.callout, design: .monospaced)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
        .frame(
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
        .accessibilityLabel(row.accessibilityText)
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

    private var selectedRow: WorkbenchLogRow? {
        projectionCache.row(id: selectedRowID)
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { selectedRowID != nil },
            set: { if !$0 { selectedRowID = nil } }
        )
    }

    private func scrollToNewest() {
        guard let id = rows.last?.id else { return }
        followCadence.recordImmediateScroll(to: id)
        scrollRequest = WorkbenchDataScrollRequest(id: id)
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

private struct WorkbenchLogInspector: View {
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
