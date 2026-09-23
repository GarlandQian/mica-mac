import Foundation
import MicaCore
import Observation

struct RulesWorkspaceInput {
    let identity: WorkbenchSessionIdentity
    let rules: [RuleViewState]
    let connections: [ConnectionSnapshot]
    let structureRevision: UInt64
    var query: String
    let language: AppLanguage
}

@MainActor
@Observable
final class RulesWorkspaceModel {
    private(set) var identity: WorkbenchSessionIdentity?
    private(set) var isActive = false
    private var cache = WorkbenchRuleProjectionCache()
    private var accessibilityCursor = WorkbenchAccessibilityWindowCursor()
    private(set) var restoredScrollAnchorID: String?
    private(set) var scrollRequest: WorkbenchDataScrollRequest?
    private(set) var tableInteraction = WorkbenchDataInteractionCoordinator()

    var selectedRowID: String? {
        didSet {
            if oldValue != selectedRowID {
                reconcileAccessibilityWindow(revealing: selectedRowID)
            }
        }
    }
    var sortOrder: [KeyPathComparator<WorkbenchRuleRow>] = []

    @ObservationIgnored private var previousRules: [RuleViewState]?
    @ObservationIgnored private var previousLanguage: AppLanguage?
    @ObservationIgnored private var previousStructureRevision: UInt64?
    @ObservationIgnored private var visibleIDs: [String] = []
    @ObservationIgnored private var visiblePositions: [String: Int] = [:]

    var allRows: [WorkbenchRuleRow] { cache.allRows }
    var rows: [WorkbenchRuleRow] { cache.visibleRows }
    var selectedRow: WorkbenchRuleRow? { cache.row(id: selectedRowID) }
    var staticProjectionCount: Int { cache.staticProjectionCount }
    var connectionIndexRebuildCount: Int { cache.connectionIndexRebuildCount }
    var accessibilityWindow: WorkbenchAccessibilityWindow {
        WorkbenchAccessibilityWindow.resolve(
            totalCount: rows.count,
            preferredLowerBound: accessibilityCursor.lowerBound
        )
    }

    func activate(
        identity: WorkbenchSessionIdentity,
        workspace: WorkbenchDestinationWorkspace,
        restoredScrollAnchorID: String?
    ) {
        if self.identity != identity {
            cache.reset()
            scrollRequest = nil
            accessibilityCursor.reset()
            tableInteraction = WorkbenchDataInteractionCoordinator()
            previousRules = nil
            previousLanguage = nil
            previousStructureRevision = nil
            visibleIDs = []
            visiblePositions = [:]
        }
        self.identity = identity
        isActive = true
        sortOrder = Self.sortOrder(from: workspace.sort)
        selectedRowID = workspace.selectedItemID
        self.restoredScrollAnchorID = restoredScrollAnchorID
    }

    func deactivate() {
        isActive = false
    }

    @discardableResult
    func update(_ input: RulesWorkspaceInput, reconcileSelection: Bool = true) -> Bool {
        guard isActive, input.identity == identity,
              previousStructureRevision.map({ input.structureRevision >= $0 }) ?? true else {
            return false
        }
        let update: WorkbenchRuleProjectionUpdate
        if previousRules != input.rules || previousLanguage != input.language {
            update = .source
        } else if previousStructureRevision != input.structureRevision {
            update = .connectionStructure
        } else {
            update = .visibleOnly
        }
        let previousRows = allRows
        let previousSelection = selectedRowID
        let changed = cache.project(
            update: update,
            rules: input.rules,
            connections: input.connections,
            controllerID: input.identity.controllerID,
            generation: input.identity.generation,
            structureRevision: input.structureRevision,
            query: input.query,
            sortOrder: sortOrder,
            language: input.language,
            isActive: isActive
        )
        previousRules = input.rules
        previousLanguage = input.language
        previousStructureRevision = input.structureRevision
        if changed {
            let nextIDs = rows.map(\.id)
            if nextIDs != visibleIDs {
                visibleIDs = nextIDs
                visiblePositions = Dictionary(uniqueKeysWithValues: nextIDs.enumerated().map {
                    ($0.element, $0.offset)
                })
            }
        }
        if reconcileSelection {
            selectedRowID = WorkbenchDataSelection.reconciled(
                previousSelection,
                previousRows: previousRows,
                nextVisibleRows: rows,
                identityFamily: \.identityFamily
            )
        }
        if changed {
            reconcileAccessibilityWindow(revealing: selectedRowID)
        }
        return true
    }

    func row(id: String?) -> WorkbenchRuleRow? { cache.row(id: id) }

    func inspectorRow(type: String, payload: String) -> WorkbenchRuleRow? {
        if let selectedRow,
           selectedRow.rule.type == type,
           selectedRow.rule.payload == payload {
            return selectedRow
        }
        return WorkbenchRuleInspectorResolver.resolve(type: type, payload: payload, in: allRows)
    }

    func select(_ id: String, identity: WorkbenchSessionIdentity) {
        guard isActive, self.identity == identity, visiblePositions[id] != nil else { return }
        selectedRowID = id
    }

    func reveal(
        _ selection: WorkbenchRuleNavigationSelection,
        input: RulesWorkspaceInput
    ) -> String? {
        guard isActive, identity == input.identity,
              let controllerID = input.identity.controllerID,
              let row = WorkbenchRuleNavigationResolver.resolve(
                  selection,
                  controllerID: controllerID,
                  generation: input.identity.generation,
                  in: allRows
              ) else { return nil }
        var next = input
        if visiblePositions[row.id] == nil {
            next.query = ""
            guard update(next, reconcileSelection: false) else { return nil }
        }
        guard visiblePositions[row.id] != nil else { return nil }
        selectedRowID = row.id
        scrollRequest = WorkbenchDataScrollRequest(id: row.id)
        return next.query
    }

    func reconcileAccessibilityWindow(revealing selectionID: String? = nil) {
        accessibilityCursor.reconcile(
            totalCount: visibleIDs.count,
            revealing: selectionID,
            indexOf: { visiblePositions[$0] },
            idAt: { visibleIDs.indices.contains($0) ? visibleIDs[$0] : nil }
        )
    }

    func moveAccessibilityWindow(to lowerBound: Int) {
        accessibilityCursor.move(
            to: lowerBound,
            totalCount: visibleIDs.count,
            idAt: { visibleIDs.indices.contains($0) ? visibleIDs[$0] : nil }
        )
    }

    static func sortOrder(
        from workspaceSort: [WorkbenchWorkspaceSort]
    ) -> [KeyPathComparator<WorkbenchRuleRow>] {
        workspaceSort.compactMap { item -> KeyPathComparator<WorkbenchRuleRow>? in
            let order: SortOrder = item.ascending ? .forward : .reverse
            switch item.field {
            case "index": return KeyPathComparator(\WorkbenchRuleRow.indexSortValue, order: order)
            case "payload": return KeyPathComparator(\WorkbenchRuleRow.payload, order: order)
            case "type": return KeyPathComparator(\WorkbenchRuleRow.type, order: order)
            case "proxy": return KeyPathComparator(\WorkbenchRuleRow.proxy, order: order)
            case "activeConnections": return KeyPathComparator(\WorkbenchRuleRow.activeConnections, order: order)
            case "hitCount": return KeyPathComparator(\WorkbenchRuleRow.hitCount, order: order)
            default: return nil
            }
        }
    }


    static func workspaceSort(
        _ comparator: KeyPathComparator<WorkbenchRuleRow>
    ) -> WorkbenchWorkspaceSort? {
        let field: String
        if comparator.keyPath == \WorkbenchRuleRow.indexSortValue {
            field = "index"
        } else if comparator.keyPath == \WorkbenchRuleRow.payload {
            field = "payload"
        } else if comparator.keyPath == \WorkbenchRuleRow.type {
            field = "type"
        } else if comparator.keyPath == \WorkbenchRuleRow.proxy {
            field = "proxy"
        } else if comparator.keyPath == \WorkbenchRuleRow.activeConnections {
            field = "activeConnections"
        } else if comparator.keyPath == \WorkbenchRuleRow.hitCount {
            field = "hitCount"
        } else {
            return nil
        }
        return WorkbenchWorkspaceSort(
            field: field,
            ascending: comparator.order == .forward
        )
    }


}
