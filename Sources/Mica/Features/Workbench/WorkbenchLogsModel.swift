import Foundation
import MicaCore
import Observation

struct WorkbenchLogsPresentationRequest: Equatable {
    let scope: WorkbenchSessionIdentity
    let revision: UInt64
    let query: String
    let language: AppLanguage
}

struct WorkbenchLogsFollowRequest: Equatable {
    let scope: WorkbenchSessionIdentity
    let deadline: Date
    let token: UUID
}

@MainActor
@Observable
final class WorkbenchLogsModel {
    private(set) var scope: WorkbenchSessionIdentity?
    private(set) var rows: [WorkbenchLogRow] = []
    private(set) var sourceCount = 0
    private(set) var selectedRowID: String?
    private(set) var level: LogSessionLevel = .all
    private(set) var followsNewest = true
    private(set) var restoredScrollAnchorID: String?
    private(set) var scrollRequest: WorkbenchDataScrollRequest?
    private(set) var followRequest: WorkbenchLogsFollowRequest?
    private var accessibilityCursor = WorkbenchAccessibilityWindowCursor()
    private var rowRevision: UInt64 = 0

    let interaction = WorkbenchDataInteractionCoordinator()
    @ObservationIgnored private var cache = WorkbenchLogProjectionCache()
    @ObservationIgnored private var cadence = WorkbenchLogFollowCadence()
    @ObservationIgnored private var latestCatalog: LogsCatalogSnapshot?
    @ObservationIgnored private var latestRequest: WorkbenchLogsPresentationRequest?
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var needsInitialFollow = false

    var accessibilityWindow: WorkbenchAccessibilityWindow {
        WorkbenchAccessibilityWindow.resolve(
            totalCount: rows.count,
            preferredLowerBound: accessibilityCursor.lowerBound
        )
    }

    var formattedRowCount: Int { cache.formattedRowCount }
    var filterEvaluationCount: Int { cache.filterEvaluationCount }

    func activate(
        scope: WorkbenchSessionIdentity,
        workspace: WorkbenchDestinationWorkspace,
        scrollAnchorID: String?,
        defaultLevel: LogSessionLevel,
        availableLevels: [LogSessionLevel]
    ) {
        if self.scope != scope {
            cache.reset()
            rows = []
            sourceCount = 0
            latestCatalog = nil
            latestRequest = nil
            accessibilityCursor.reset()
            scrollRequest = nil
            rowRevision &+= 1
        }
        self.scope = scope
        isActive = true
        needsInitialFollow = true
        cancelFollow()
        let storedLevel = workspace.filters["level"].flatMap(LogSessionLevel.init(rawValue:))
        level = storedLevel.map { availableLevels.contains($0) ? $0 : .all } ?? defaultLevel
        selectedRowID = workspace.selectedItemID
        followsNewest = selectedRowID == nil
            && (workspace.filters["followNewest"].flatMap(Bool.init) ?? true)
        restoredScrollAnchorID = scrollAnchorID
    }

    func deactivate() {
        isActive = false
        cancelFollow()
    }

    func update(
        catalog: LogsCatalogSnapshot,
        request: WorkbenchLogsPresentationRequest,
        now: Date = Date()
    ) {
        guard isActive, scope == request.scope,
              request.revision == catalog.entriesRevision else { return }
        if let latestRequest, latestRequest.scope == request.scope,
           request.revision < latestRequest.revision { return }
        latestCatalog = catalog
        latestRequest = request
        project(now: now)
    }

    func setLevel(_ level: LogSessionLevel) {
        guard self.level != level else { return }
        self.level = level
        project()
        reconcileAccessibilityWindow(revealing: selectedRowID)
    }

    func select(_ id: String?) {
        guard id == nil || rows.contains(where: { $0.id == id }) else { return }
        selectedRowID = id
        if id != nil {
            setFollowing(false)
        }
        reconcileAccessibilityWindow(revealing: id)
    }

    func setFollowing(_ follows: Bool, now: Date = Date()) {
        guard followsNewest != follows else { return }
        followsNewest = follows
        if follows {
            selectedRowID = nil
            scrollToNewest(now: now)
        } else {
            cancelFollow()
        }
        reconcileAccessibilityWindow()
    }

    func jumpToNewest(now: Date = Date()) {
        selectedRowID = nil
        followsNewest = true
        scrollToNewest(now: now)
        reconcileAccessibilityWindow()
    }

    func row(id: String) -> WorkbenchLogRow? {
        _ = rowRevision
        return cache.row(id: id)
    }

    func consumeFollow(_ request: WorkbenchLogsFollowRequest, now: Date = Date()) {
        guard isActive, scope == request.scope, followRequest == request,
              let id = cadence.consume(
                isEnabled: followsNewest,
                hasSelection: selectedRowID != nil,
                now: now
              ) else { return }
        followRequest = nil
        scrollRequest = WorkbenchDataScrollRequest(id: id)
    }

    func handleAccessibility(_ intent: WorkbenchTableAccessibilityIntent) {
        guard isActive, intent.scope == scope else { return }
        switch intent {
        case .selectRow(let id, _):
            select(id)
        case .movePage(let lowerBound, _):
            setFollowing(false)
            accessibilityCursor.move(
                to: lowerBound,
                totalCount: rows.count,
                idAt: { rows.indices.contains($0) ? rows[$0].id : nil }
            )
        case .setSort, .performNamedAction:
            break
        }
    }

    private func project(now: Date = Date()) {
        guard isActive, let catalog = latestCatalog, let request = latestRequest else { return }
        let previousRows = cache.allRows
        let previousNewestID = rows.last?.id
        let changed = cache.project(
            entries: catalog.entries,
            revision: catalog.entriesRevision,
            level: level,
            query: request.query,
            language: request.language,
            change: catalog.lastChange
        )
        if changed {
            sourceCount = cache.allRows.count
            rows = cache.visibleRows
            rowRevision &+= 1
        }
        selectedRowID = cache.reconciledSelection(selectedRowID, previousRows: previousRows)
        switch cache.accessibilityOrderChange {
        case .unchanged:
            if needsInitialFollow {
                reconcileAccessibilityWindow(revealing: selectedRowID)
            }
        case .replace:
            // Incoming snapshots retain the reader's page; explicit selection
            // and initial restoration own selection-based navigation.
            reconcileAccessibilityWindow(revealing: needsInitialFollow ? selectedRowID : nil)
        case .prefixDelta(let droppedCount):
            accessibilityCursor.applyPrefixDelta(
                totalCount: rows.count,
                droppedCount: droppedCount,
                followsNewest: followsNewest,
                idAt: { rows.indices.contains($0) ? rows[$0].id : nil }
            )
        }
        if previousNewestID != rows.last?.id || needsInitialFollow {
            requestFollow(now: now)
        }
        needsInitialFollow = false
    }

    private func requestFollow(now: Date) {
        cadence.request(
            newestRowID: rows.last?.id,
            isEnabled: followsNewest,
            hasSelection: selectedRowID != nil,
            now: now
        )
        guard let deadline = cadence.pendingDeadline, let scope else {
            followRequest = nil
            return
        }
        if followRequest?.deadline != deadline || followRequest?.scope != scope {
            followRequest = WorkbenchLogsFollowRequest(scope: scope, deadline: deadline, token: UUID())
        }
    }

    private func scrollToNewest(now: Date) {
        cancelFollow()
        guard let id = rows.last?.id else { return }
        cadence.recordImmediateScroll(to: id, now: now)
        scrollRequest = WorkbenchDataScrollRequest(id: id)
    }

    private func cancelFollow() {
        cadence.cancel()
        followRequest = nil
    }

    private func reconcileAccessibilityWindow(revealing id: String? = nil) {
        accessibilityCursor.reconcile(
            orderedIDs: rows.map(\.id),
            revealing: id,
            followsNewest: followsNewest
        )
    }
}
