import Foundation
import MicaCore
import Observation

struct ConnectionsWorkspaceInput {
    let identity: WorkbenchSessionIdentity
    let catalog: ConnectionsCatalogSnapshot
    let closedConnections: [ClosedConnectionRecord]
    let closedRevision: UInt64
    var query: String
    let language: AppLanguage
}

@MainActor
@Observable
final class ConnectionsWorkspaceModel {
    private(set) var identity: WorkbenchSessionIdentity?
    private(set) var isActive = false
    private var cache = WorkbenchConnectionProjectionCache()
    private var accessibilityCursor = WorkbenchAccessibilityWindowCursor()
    private(set) var navigationDirectory = WorkbenchConnectionNavigationDirectory()
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
    var sortOrder: [KeyPathComparator<WorkbenchConnectionRow>] = []
    var closeIntent: WorkbenchConnectionCloseIntent?
    var scope: ConnectionSessionTab = .active {
        didSet {
            guard oldValue != scope else { return }
            selectedRowID = nil
            closeIntent = nil
            scrollRequest = nil
            deferredInput = nil
            presentedConfiguration = nil
            accessibilityCursor.reset()
        }
    }

    @ObservationIgnored private var acceptedMetricsRevision: UInt64?
    @ObservationIgnored private var acceptedClosedRevision: UInt64?
    @ObservationIgnored private var deferredInput: ConnectionsWorkspaceInput?
    @ObservationIgnored private var deferredReconcilesSelection = true
    @ObservationIgnored private var presentedConfiguration: PresentationConfiguration?

    private struct PresentationConfiguration: Equatable {
        let scope: ConnectionSessionTab
        let query: String
        let language: AppLanguage
        let sortOrder: [KeyPathComparator<WorkbenchConnectionRow>]
    }

    var allRows: [WorkbenchConnectionRow] { cache.allRows }
    var rows: [WorkbenchConnectionRow] { cache.visibleRows }
    var pulse: WorkbenchConnectionPulseProjection { cache.pulseProjection }
    var closeGroups: [WorkbenchConnectionCloseGroup] { cache.closeGroups }
    var selectedRow: WorkbenchConnectionRow? { cache.row(id: selectedRowID) }
    var staticProjectionCount: Int { cache.staticProjectionCount }
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
            closeIntent = nil
            scrollRequest = nil
            accessibilityCursor.reset()
            tableInteraction = WorkbenchDataInteractionCoordinator()
            navigationDirectory = WorkbenchConnectionNavigationDirectory()
            acceptedMetricsRevision = nil
            acceptedClosedRevision = nil
            presentedConfiguration = nil
        }
        deferredInput = nil
        tableInteraction.apply(.ended)
        self.identity = identity
        isActive = true
        scope = workspace.activeTab.flatMap(ConnectionSessionTab.init(rawValue:)) ?? .active
        sortOrder = Self.sortOrder(from: workspace.sort)
        selectedRowID = workspace.selectedItemID
        self.restoredScrollAnchorID = restoredScrollAnchorID
    }

    func deactivate() {
        isActive = false
        deferredInput = nil
        tableInteraction.apply(.ended)
    }

    @discardableResult
    func update(
        _ input: ConnectionsWorkspaceInput,
        reconcileSelection: Bool = true,
        forcePresentation: Bool = false
    ) -> Bool {
        guard isActive, input.identity == identity else { return false }
        if scope == .active {
            guard acceptedMetricsRevision.map({ input.catalog.metricsRevision >= $0 }) ?? true else {
                return false
            }
            acceptedMetricsRevision = input.catalog.metricsRevision
        } else {
            guard acceptedClosedRevision.map({ input.closedRevision >= $0 }) ?? true else {
                return false
            }
            acceptedClosedRevision = input.closedRevision
        }

        let configuration = PresentationConfiguration(
            scope: scope,
            query: input.query,
            language: input.language,
            sortOrder: sortOrder
        )
        if tableInteraction.isUserScrolling, !forcePresentation,
           presentedConfiguration == configuration {
            // Keep only the newest complete snapshot. The cache falls back to
            // that snapshot when a skipped revision makes its delta obsolete.
            deferredInput = input
            deferredReconcilesSelection = reconcileSelection
            return true
        }
        deferredInput = nil
        presentedConfiguration = configuration

        if let intent = closeIntent,
           closeTargets(
                for: intent.target,
                currentConnections: input.catalog.connections,
                identity: input.identity
           ) == nil {
            closeIntent = nil
        }

        let previousRows = allRows
        let previousSelection = selectedRowID
        let previousStaticCount = cache.staticProjectionCount
        cache.project(
            activeConnections: input.catalog.connections,
            closedConnections: input.closedConnections,
            scope: scope,
            structureRevision: input.catalog.structureRevision,
            metricsRevision: input.catalog.metricsRevision,
            closedRevision: input.closedRevision,
            query: input.query,
            sortOrder: sortOrder,
            language: input.language,
            change: input.catalog.lastChange,
            isActive: isActive
        )
        if reconcileSelection {
            selectedRowID = WorkbenchDataSelection.reconciled(
                previousSelection,
                previousRows: previousRows,
                nextVisibleRows: rows,
                identityFamily: \.identityFamily
            )
        }
        if cache.staticProjectionCount != previousStaticCount {
            reconcileAccessibilityWindow(revealing: selectedRowID)
        } else {
            reconcileAccessibilityWindow()
        }
        closeIntent = closeIntent?.reconciled(
            routerID: input.identity.controllerID,
            generation: input.identity.generation,
            connectionIDs: cache.connectionIDs,
            groupIDs: cache.groupIDs
        )
        return true
    }

    func updateNavigation(
        rules: [RuleViewState],
        catalog: PolicyGroupCatalogSnapshot,
        visibility: GlobalGroupVisibility,
        identity: WorkbenchSessionIdentity
    ) {
        updateRuleNavigation(rules: rules, identity: identity)
        updatePolicyNavigation(catalog: catalog, visibility: visibility, identity: identity)
    }

    func updateRuleNavigation(
        rules: [RuleViewState],
        identity: WorkbenchSessionIdentity
    ) {
        guard isActive, self.identity == identity else { return }
        var directory = navigationDirectory
        guard directory.replaceRules(rules) else { return }
        navigationDirectory = directory
    }

    func updatePolicyNavigation(
        catalog: PolicyGroupCatalogSnapshot,
        visibility: GlobalGroupVisibility,
        identity: WorkbenchSessionIdentity
    ) {
        guard isActive, self.identity == identity else { return }
        let groups = ProxyProjection.arrangedGroups(
            catalog.groups,
            mode: catalog.mode,
            visibility: visibility
        )
        var directory = navigationDirectory
        guard directory.replaceGroups(groups) else { return }
        navigationDirectory = directory
    }

    func row(id: String?) -> WorkbenchConnectionRow? { cache.row(id: id) }

    func visibleIndex(id: String) -> Int? { cache.visibleIndex(id: id) }

    func select(_ id: String, identity: WorkbenchSessionIdentity) {
        guard isActive, self.identity == identity, cache.visibleIndex(id: id) != nil else { return }
        selectedRowID = id
    }

    func requestClose(
        _ target: WorkbenchConnectionCloseIntent.Target,
        identity: WorkbenchSessionIdentity
    ) {
        guard isActive, self.identity == identity, let controllerID = identity.controllerID else {
            return
        }
        closeIntent = WorkbenchConnectionCloseIntent(
            routerID: controllerID,
            generation: identity.generation,
            target: target
        )
    }

    /// A paused table keeps its original action targets. An ID reused by the
    /// controller must never turn that target into a different connection.
    func closeTargets(
        for target: WorkbenchConnectionCloseIntent.Target,
        currentConnections: [ConnectionSnapshot],
        identity: WorkbenchSessionIdentity
    ) -> [ConnectionSnapshot]? {
        guard isActive, self.identity == identity, scope == .active else { return nil }
        let requested: [ConnectionSnapshot]
        switch target {
        case .connection(let id):
            guard let row = row(id: id) else { return nil }
            requested = [row.connection]
        case .group(let id):
            guard let group = closeGroups.first(where: { $0.id == id }) else { return nil }
            requested = group.connections
        case .all:
            return currentConnections
        }
        let requestedIDs = Set(requested.map(\.id))
        guard !requestedIDs.isEmpty, requestedIDs.count == requested.count,
              requestedIDs.allSatisfy({ $0.dataNonEmpty != nil }) else { return nil }
        var currentByID: [String: ConnectionSnapshot] = [:]
        for connection in currentConnections where requestedIDs.contains(connection.id) {
            guard currentByID.updateValue(connection, forKey: connection.id) == nil else { return nil }
        }
        let current = requested.compactMap { currentByID[$0.id] }
        guard ConnectionsCatalogSnapshot.structuresMatch(requested, current) else { return nil }
        return requested
    }

    /// Return the query that makes an exact navigation target visible.
    func reveal(
        _ selection: WorkbenchConnectionNavigationSelection,
        input: ConnectionsWorkspaceInput
    ) -> String? {
        guard isActive, input.identity == identity, scope == .active,
              selection.controllerID == input.identity.controllerID,
              selection.generation == input.identity.generation,
              update(input, reconcileSelection: false, forcePresentation: true),
              let row = allRows.first(where: {
                  selection.matches(sourceIndex: $0.sourceIndex, reportedConnectionID: $0.connection.id)
              }) else { return nil }
        var next = input
        if cache.visibleIndex(id: row.id) == nil {
            next.query = ""
            guard update(next, reconcileSelection: false, forcePresentation: true) else { return nil }
        }
        guard cache.visibleIndex(id: row.id) != nil else { return nil }
        selectedRowID = row.id
        scrollRequest = WorkbenchDataScrollRequest(id: row.id)
        return next.query
    }

    func finishDeferredPresentation(identity: WorkbenchSessionIdentity) {
        guard isActive, self.identity == identity, !tableInteraction.isUserScrolling,
              let input = deferredInput else { return }
        update(input, reconcileSelection: deferredReconcilesSelection)
    }

    func reconcileAccessibilityWindow(revealing selectionID: String? = nil) {
        accessibilityCursor.reconcile(
            totalCount: rows.count,
            revealing: selectionID,
            indexOf: cache.visibleIndex(id:),
            idAt: { rows.indices.contains($0) ? rows[$0].id : nil }
        )
    }

    func moveAccessibilityWindow(to lowerBound: Int) {
        accessibilityCursor.move(
            to: lowerBound,
            totalCount: rows.count,
            idAt: { rows.indices.contains($0) ? rows[$0].id : nil }
        )
    }

    static func sortOrder(
        from workspaceSort: [WorkbenchWorkspaceSort]
    ) -> [KeyPathComparator<WorkbenchConnectionRow>] {
        workspaceSort.compactMap { item -> KeyPathComparator<WorkbenchConnectionRow>? in
            let order: SortOrder = item.ascending ? .forward : .reverse
            switch item.field {
            case "host": return KeyPathComparator(\WorkbenchConnectionRow.host, order: order)
            case "process": return KeyPathComparator(\WorkbenchConnectionRow.process, order: order)
            case "upload": return KeyPathComparator(\WorkbenchConnectionRow.upload, order: order)
            case "download": return KeyPathComparator(\WorkbenchConnectionRow.download, order: order)
            default: return nil
            }
        }
    }


    static func workspaceSort(
        _ comparator: KeyPathComparator<WorkbenchConnectionRow>
    ) -> WorkbenchWorkspaceSort? {
        let field: String
        if comparator.keyPath == \WorkbenchConnectionRow.host {
            field = "host"
        } else if comparator.keyPath == \WorkbenchConnectionRow.process {
            field = "process"
        } else if comparator.keyPath == \WorkbenchConnectionRow.upload {
            field = "upload"
        } else if comparator.keyPath == \WorkbenchConnectionRow.download {
            field = "download"
        } else {
            return nil
        }
        return WorkbenchWorkspaceSort(
            field: field,
            ascending: comparator.order == .forward
        )
    }


}
