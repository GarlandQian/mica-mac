import Foundation
import MicaCore
import Observation

struct WorkbenchSourcesPresentationInput: Equatable {
    let scope: WorkbenchSessionIdentity
    let sources: [ProxyProviderViewState]
    let query: String
    let language: AppLanguage
}

@MainActor
@Observable
final class WorkbenchSourcesModel {
    private(set) var scope: WorkbenchSessionIdentity?
    private(set) var rows: [WorkbenchSourceRow] = []
    private(set) var sourceCount = 0
    private(set) var updatableSourceCount = 0
    private(set) var selectedRowID: String?
    private(set) var kind: ProviderSessionKind = .all
    private(set) var sortOrder: [KeyPathComparator<WorkbenchSourceRow>] = []
    private(set) var restoredScrollAnchorID: String?
    private var accessibilityCursor = WorkbenchAccessibilityWindowCursor()
    private var rowRevision: UInt64 = 0

    let interaction = WorkbenchDataInteractionCoordinator()
    @ObservationIgnored private var cache = WorkbenchSourceProjectionCache()
    @ObservationIgnored private var latestInput: WorkbenchSourcesPresentationInput?
    @ObservationIgnored private var presentedInput: WorkbenchSourcesPresentationInput?
    @ObservationIgnored private var presentedConfiguration: PresentationConfiguration?
    @ObservationIgnored private var hasDeferredPresentation = false
    @ObservationIgnored private(set) var isActive = false

    private struct PresentationConfiguration: Equatable {
        let kind: ProviderSessionKind
        let query: String
        let language: AppLanguage
        let sortOrder: [KeyPathComparator<WorkbenchSourceRow>]
    }

    var selectedRow: WorkbenchSourceRow? {
        guard let selectedRowID else { return nil }
        return rows.first { $0.id == selectedRowID }
    }

    var accessibilityWindow: WorkbenchAccessibilityWindow {
        WorkbenchAccessibilityWindow.resolve(
            totalCount: rows.count,
            preferredLowerBound: accessibilityCursor.lowerBound
        )
    }

    var workspaceSort: [WorkbenchWorkspaceSort] {
        sortOrder.compactMap(Self.workspaceSort)
    }

    var sourceProjectionCount: Int { cache.sourceProjectionCount }

    func activate(
        scope: WorkbenchSessionIdentity,
        workspace: WorkbenchDestinationWorkspace,
        scrollAnchorID: String?
    ) {
        if self.scope != scope {
            cache.reset()
            rows = []
            sourceCount = 0
            updatableSourceCount = 0
            latestInput = nil
            presentedInput = nil
            presentedConfiguration = nil
            accessibilityCursor.reset()
            rowRevision &+= 1
        }
        latestInput = presentedInput
        hasDeferredPresentation = false
        interaction.apply(.ended)
        self.scope = scope
        isActive = true
        kind = workspace.activeTab.flatMap(ProviderSessionKind.init(rawValue:)) ?? .all
        sortOrder = Self.sortOrder(from: workspace.sort)
        selectedRowID = workspace.selectedItemID
        restoredScrollAnchorID = scrollAnchorID
    }

    func deactivate() {
        isActive = false
        hasDeferredPresentation = false
        latestInput = presentedInput
        interaction.apply(.ended)
    }

    func update(_ input: WorkbenchSourcesPresentationInput) {
        guard isActive, scope == input.scope else { return }
        latestInput = input
        if interaction.isUserScrolling,
           presentedConfiguration == configuration(for: input) {
            hasDeferredPresentation = true
            return
        }
        project()
    }

    func finishDeferredPresentation(scope: WorkbenchSessionIdentity) {
        guard isActive, self.scope == scope, !interaction.isUserScrolling,
              hasDeferredPresentation else { return }
        project()
    }

    func setKind(_ kind: ProviderSessionKind) {
        guard self.kind != kind else { return }
        selectedRowID = nil
        self.kind = kind
        project()
    }

    func setSortOrder(_ sortOrder: [KeyPathComparator<WorkbenchSourceRow>]) {
        guard self.sortOrder != sortOrder else { return }
        self.sortOrder = sortOrder
        project()
    }

    func select(_ id: String?) {
        guard id == nil || rows.contains(where: { $0.id == id }) else { return }
        selectedRowID = id
        reconcileAccessibilityWindow(revealing: id)
    }

    func row(id: String) -> WorkbenchSourceRow? {
        _ = rowRevision
        return cache.row(id: id)
    }

    func handleAccessibility(_ intent: WorkbenchTableAccessibilityIntent) {
        guard isActive, intent.scope == scope else { return }
        switch intent {
        case .selectRow(let id, _):
            select(id)
        case .movePage(let lowerBound, _):
            accessibilityCursor.move(to: lowerBound, orderedIDs: rows.map(\.id))
        case .setSort(let field, let ascending, _):
            guard ["name", "type", "itemCount"].contains(field) else { return }
            setSortOrder(Self.sortOrder(from: [
                WorkbenchWorkspaceSort(field: field, ascending: ascending),
            ]))
        case .performNamedAction:
            break
        }
    }

    func accessibilitySortOptions(language: AppLanguage) -> [WorkbenchAccessibilitySortOption] {
        [
            ("name", "dashboard.col_provider"),
            ("type", "dashboard.col_provider_type"),
            ("itemCount", "traffic.provider_items"),
        ].map { field, titleKey in
            let stored = workspaceSort.first { $0.field == field }
            return WorkbenchAccessibilitySortOption(
                id: field,
                title: MicaStrings.localizedKey(titleKey, language: language),
                direction: stored.map { $0.ascending ? .ascending : .descending }
            )
        }
    }

    private func configuration(for input: WorkbenchSourcesPresentationInput) -> PresentationConfiguration {
        PresentationConfiguration(kind: kind, query: input.query, language: input.language, sortOrder: sortOrder)
    }

    private func project() {
        guard isActive, let input = latestInput else { return }
        let sourceChanged = presentedInput?.sources != input.sources
            || presentedInput?.language != input.language
        hasDeferredPresentation = false
        presentedInput = input
        presentedConfiguration = configuration(for: input)
        let previousRows = cache.allRows
        let changed = cache.project(
            update: sourceChanged ? .source : .visibleOnly,
            sources: input.sources,
            kind: kind,
            query: input.query,
            sortOrder: sortOrder,
            language: input.language
        )
        if changed {
            sourceCount = cache.allRows.count
            updatableSourceCount = cache.updatableSourceCount
            rows = cache.visibleRows
            rowRevision &+= 1
        }
        selectedRowID = WorkbenchDataSelection.reconciled(
            selectedRowID,
            previousRows: previousRows,
            nextVisibleRows: rows,
            identityFamily: \.identityFamily
        )
        reconcileAccessibilityWindow(revealing: selectedRowID)
    }

    private func reconcileAccessibilityWindow(revealing id: String? = nil) {
        accessibilityCursor.reconcile(orderedIDs: rows.map(\.id), revealing: id)
    }

    private static func sortOrder(
        from workspaceSort: [WorkbenchWorkspaceSort]
    ) -> [KeyPathComparator<WorkbenchSourceRow>] {
        workspaceSort.compactMap { item in
            let order: SortOrder = item.ascending ? .forward : .reverse
            switch item.field {
            case "name": return KeyPathComparator(\WorkbenchSourceRow.name, order: order)
            case "type": return KeyPathComparator(\WorkbenchSourceRow.type, order: order)
            case "itemCount": return KeyPathComparator(\WorkbenchSourceRow.itemCount, order: order)
            default: return nil
            }
        }
    }

    private static func workspaceSort(
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
        return WorkbenchWorkspaceSort(field: field, ascending: comparator.order == .forward)
    }
}
