import Foundation
import Observation
import Synchronization
import Testing
@testable import Mica
@testable import MicaCore

@MainActor
struct WorkbenchSourcesModelTests {
    private func makeModel(
        workspace: WorkbenchDestinationWorkspace = WorkbenchDestinationWorkspace()
    ) -> (WorkbenchSourcesModel, WorkbenchSessionIdentity) {
        let scope = WorkbenchSessionIdentity(controllerID: UUID(), generation: UUID())
        let model = WorkbenchSourcesModel()
        model.activate(scope: scope, workspace: workspace, scrollAnchorID: workspace.scrollAnchorID)
        return (model, scope)
    }

    private func source(_ name: String, kind: ProviderKind = .proxy, count: Int = 10) -> ProxyProviderViewState {
        ProxyProviderViewState(kind: kind, name: name, type: "HTTP", updatable: true, itemCount: count)
    }

    private func publish(
        _ sources: [ProxyProviderViewState],
        to model: WorkbenchSourcesModel,
        scope: WorkbenchSessionIdentity,
        query: String = ""
    ) {
        model.update(WorkbenchSourcesPresentationInput(scope: scope, sources: sources, query: query, language: .english))
    }

    @Test func filteringAndExplicitSortingReuseRowsAndDefaultReturnsControllerOrder() {
        let (model, scope) = makeModel()
        let sources = [source("Zulu"), source("Alpha", kind: .rule), source("Beta")]
        publish(sources, to: model, scope: scope)
        #expect(model.rows.map(\.name) == ["Zulu", "Alpha", "Beta"])
        let projections = model.sourceProjectionCount
        model.setKind(.proxy)
        #expect(model.rows.map(\.name) == ["Zulu", "Beta"])
        model.setSortOrder([KeyPathComparator(\WorkbenchSourceRow.name)])
        #expect(model.rows.map(\.name) == ["Beta", "Zulu"])
        #expect(model.workspaceSort == [WorkbenchWorkspaceSort(field: "name", ascending: true)])
        model.setSortOrder([])
        #expect(model.rows.map(\.name) == ["Zulu", "Beta"])
        #expect(model.sourceProjectionCount == projections)
        #expect(model.sourceCount == 3)
        #expect(model.updatableSourceCount == 3)
    }

    @Test func restorationUsesPersistedKindSortSelectionAndScrollAnchor() {
        let selected = source("selected", kind: .rule)
        let workspace = WorkbenchDestinationWorkspace(
            sort: [WorkbenchWorkspaceSort(field: "itemCount", ascending: false)],
            selectedItemID: selected.id,
            scrollAnchorID: "anchor",
            activeTab: "rule"
        )
        let (model, scope) = makeModel(workspace: workspace)
        publish([source("hidden"), selected, source("larger", kind: .rule, count: 30)], to: model, scope: scope)
        #expect(model.kind == .rule)
        #expect(model.rows.map(\.name) == ["larger", "selected"])
        #expect(model.selectedRow?.source == selected)
        #expect(model.restoredScrollAnchorID == "anchor")
    }

    @Test func staleScopeCannotReplaceRowsOrDispatchSelectionAndSort() {
        let (model, oldScope) = makeModel()
        publish([source("old")], to: model, scope: oldScope)
        let newScope = WorkbenchSessionIdentity(controllerID: oldScope.controllerID, generation: UUID())
        model.activate(scope: newScope, workspace: WorkbenchDestinationWorkspace(), scrollAnchorID: nil)
        let current = source("new")
        publish([current], to: model, scope: newScope)
        publish([source("stale")], to: model, scope: oldScope)
        model.handleAccessibility(.selectRow(id: current.id, scope: oldScope))
        model.handleAccessibility(.setSort(id: "name", ascending: true, scope: oldScope))
        #expect(model.rows.map(\.name) == ["new"])
        #expect(model.selectedRowID == nil)
        #expect(model.sortOrder.isEmpty)
    }

    @Test func completeSourceRowsRemainAvailableAcrossBoundedAccessibilityPages() {
        let (model, scope) = makeModel()
        publish((0..<100).map { source("source-\($0)") }, to: model, scope: scope)
        model.handleAccessibility(.movePage(lowerBound: 64, scope: scope))
        #expect(model.rows.count == 100)
        #expect(model.accessibilityWindow.range == 64..<96)
        #expect(model.row(id: "proxy:source-99")?.name == "source-99")
        model.handleAccessibility(.selectRow(id: "proxy:source-99", scope: scope))
        #expect(model.selectedRow?.name == "source-99")
        #expect(model.accessibilityWindow.range.contains(99))
        #expect(model.accessibilityWindow.range.count <= 32)
    }

    @Test func inactiveUpdatesAreIgnoredAndReappearanceDropsUnavailableSelection() {
        let (model, scope) = makeModel()
        let sources = [source("current")]
        publish(sources, to: model, scope: scope)
        model.deactivate()
        publish([source("hidden")], to: model, scope: scope)
        #expect(model.rows.map(\.name) == ["current"])
        model.activate(scope: scope, workspace: WorkbenchDestinationWorkspace(selectedItemID: "missing"), scrollAnchorID: nil)
        publish(sources, to: model, scope: scope)
        #expect(model.selectedRowID == nil)
    }

    @Test func inspectorResolverObservesCurrentProviderValues() {
        let (model, scope) = makeModel()
        let initial = source("same", count: 10)
        publish([initial], to: model, scope: scope)
        model.select(initial.id)
        let changes = Mutex(0)
        withObservationTracking {
            _ = model.row(id: initial.id)
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        publish([source("same", count: 25)], to: model, scope: scope)
        #expect(changes.withLock { $0 } == 1)
        #expect(model.row(id: initial.id)?.itemCount == 25)
        #expect(model.selectedRow?.itemCount == 25)
    }
}
