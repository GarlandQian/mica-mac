import Foundation
import MicaCore
import Observation
import Synchronization
import Testing
@testable import Mica

@MainActor
struct WorkbenchRulesSourcesScrollTests {
    @Test func rulesCoalesceCountersAndConnectionsUntilScrollEnds() throws {
        let scope = identity()
        let model = RulesWorkspaceModel()
        model.activate(identity: scope, workspace: .init(), restoredScrollAnchorID: nil)
        model.update(rules(scope, revision: 1))
        let selectedID = try #require(model.rows.first?.id)
        model.select(selectedID, identity: scope)
        model.tableInteraction.apply(.began)
        let initialRows = model.rows
        let initialBuilds = model.staticProjectionCount
        let initialConnectionBuilds = model.connectionIndexRebuildCount
        let invalidations = Mutex(0)
        withObservationTracking {
            _ = model.rows
        } onChange: {
            invalidations.withLock { $0 += 1 }
        }
        for revision in 2...20 {
            model.update(rules(scope, revision: revision))
            model.finishDeferredPresentation(identity: scope)
        }
        #expect(model.rows == initialRows)
        #expect(model.staticProjectionCount == initialBuilds)
        #expect(model.connectionIndexRebuildCount == initialConnectionBuilds)
        #expect(invalidations.withLock { $0 } == 0)
        #expect(!model.update(rules(scope, revision: 10)))
        model.tableInteraction.apply(.ended)
        model.finishDeferredPresentation(identity: scope)
        #expect(model.selectedRowID == selectedID)
        #expect(model.rows.first?.hitCount == 20)
        #expect(model.rows.first?.activeConnections == 20)
        #expect(model.staticProjectionCount == initialBuilds + 1)
        #expect(model.connectionIndexRebuildCount == initialConnectionBuilds + 1)
        #expect(invalidations.withLock { $0 } == 1)
        model.finishDeferredPresentation(identity: scope)
        #expect(model.staticProjectionCount == initialBuilds + 1)
    }

    @Test func ruleQuerySortAndNavigationUseLatestDataDuringScroll() throws {
        let scope = identity()
        let model = RulesWorkspaceModel()
        model.activate(identity: scope, workspace: .init(), restoredScrollAnchorID: nil)
        model.update(rules(scope, revision: 1))
        model.tableInteraction.apply(.began)
        model.update(rules(scope, revision: 2))
        var query = rules(scope, revision: 2)
        query.query = "not-found"
        model.update(query)
        #expect(model.rows.isEmpty)
        model.sortOrder = [KeyPathComparator(\WorkbenchRuleRow.hitCount, order: .reverse)]
        model.update(rules(scope, revision: 3))
        #expect(model.rows.first?.hitCount == 3)

        let nextRule = RuleViewState(id: "new", index: 2, type: "DOMAIN", payload: "new.test", proxy: "DIRECT", hitCount: 99)
        let next = RulesWorkspaceInput(
            identity: scope, rules: [nextRule], connections: [], structureRevision: 4,
            query: "not-found", language: .english
        )
        let navigation = WorkbenchRuleNavigationSelection(
            controllerID: try #require(scope.controllerID), generation: scope.generation,
            sourceIndex: 0, reportedRuleID: nextRule.id, type: nextRule.type, payload: nextRule.payload
        )
        #expect(model.reveal(navigation, input: next) == "")
        #expect(model.selectedRow?.rule == nextRule)
        #expect(model.scrollRequest?.id == model.selectedRowID)
        model.tableInteraction.apply(.ended)
        model.finishDeferredPresentation(identity: scope)
        #expect(model.selectedRow?.rule == nextRule)
    }

    @Test func rulesDiscardDeferredInputAtPageAndSessionBoundaries() {
        let scope = identity()
        let model = RulesWorkspaceModel()
        model.activate(identity: scope, workspace: .init(), restoredScrollAnchorID: nil)
        model.update(rules(scope, revision: 1))
        model.tableInteraction.apply(.began)
        model.update(rules(scope, revision: 2))
        model.deactivate()
        model.finishDeferredPresentation(identity: scope)
        #expect(model.rows.first?.hitCount == 1)
        #expect(!model.tableInteraction.isUserScrolling)
        let next = identity()
        model.activate(identity: next, workspace: .init(), restoredScrollAnchorID: nil)
        model.update(rules(next, revision: 1))
        model.tableInteraction.apply(.began)
        model.update(rules(next, revision: 3))
        model.tableInteraction.apply(.ended)
        model.finishDeferredPresentation(identity: scope)
        #expect(model.rows.first?.hitCount == 1)
        #expect(!model.update(rules(scope, revision: 50)))
        model.finishDeferredPresentation(identity: next)
        #expect(model.rows.first?.hitCount == 3)
    }

    @Test func sourcesCoalesceLatestFullSnapshotAndReconcileSelectionOnce() throws {
        let scope = identity()
        let model = WorkbenchSourcesModel()
        model.activate(scope: scope, workspace: .init(), scrollAnchorID: nil)
        model.update(sources(scope, count: 1))
        let id = try #require(model.rows.first?.id)
        model.select(id)
        model.interaction.apply(.began)
        let builds = model.sourceProjectionCount
        let invalidations = Mutex(0)
        withObservationTracking {
            _ = model.rows
        } onChange: {
            invalidations.withLock { $0 += 1 }
        }
        for count in 2...20 {
            model.update(sources(scope, count: count))
            model.finishDeferredPresentation(scope: scope)
        }
        #expect(model.selectedRow?.itemCount == 1)
        #expect(model.sourceProjectionCount == builds)
        #expect(invalidations.withLock { $0 } == 0)
        model.interaction.apply(.ended)
        model.finishDeferredPresentation(scope: scope)
        #expect(model.selectedRowID == id)
        #expect(model.selectedRow?.itemCount == 20)
        #expect(model.sourceProjectionCount == builds + 1)
        #expect(invalidations.withLock { $0 } == 1)
        model.interaction.apply(.began)
        model.update(.init(scope: scope, sources: [], query: "", language: .english))
        #expect(model.selectedRowID == id)
        model.interaction.apply(.ended)
        model.finishDeferredPresentation(scope: scope)
        #expect(model.rows.isEmpty)
        #expect(model.selectedRowID == nil)
    }

    @Test func sourceFiltersAndSortImmediatelyUseLatestDeferredValues() {
        let scope = identity()
        let model = WorkbenchSourcesModel()
        model.activate(scope: scope, workspace: .init(), scrollAnchorID: nil)
        model.update(sources(scope, count: 1))
        model.interaction.apply(.began)
        model.update(sources(scope, count: 20))
        model.setSortOrder([KeyPathComparator(\WorkbenchSourceRow.itemCount, order: .reverse)])
        #expect(model.rows.map(\.itemCount) == [20, 10])
        model.update(sources(scope, count: 30))
        model.setKind(.rule)
        #expect(model.rows.map(\.name) == ["Alpha"])
        #expect(model.sourceProjectionCount == 3)
        model.setKind(.all)
        model.update(sources(scope, count: 40, query: "Zulu"))
        #expect(model.rows.map(\.name) == ["Zulu"])
        #expect(model.rows.first?.itemCount == 40)
        model.interaction.apply(.ended)
        model.finishDeferredPresentation(scope: scope)
        #expect(model.rows.first?.itemCount == 40)
        model.update(sources(scope, count: 40))
        model.setSortOrder([])
        #expect(model.rows.map(\.name) == ["Zulu", "Alpha"])
    }

    @Test func sourceDeferredValuesCannotCrossPageOrSessionBoundaries() {
        let scope = identity()
        let model = WorkbenchSourcesModel()
        model.activate(scope: scope, workspace: .init(), scrollAnchorID: nil)
        model.update(sources(scope, count: 1))
        model.interaction.apply(.began)
        model.update(sources(scope, count: 20))
        model.deactivate()
        model.finishDeferredPresentation(scope: scope)
        #expect(model.rows.first?.itemCount == 1)
        #expect(!model.interaction.isUserScrolling)
        model.activate(scope: scope, workspace: .init(), scrollAnchorID: nil)
        model.setKind(.proxy)
        #expect(model.rows.first?.itemCount == 1)
        let next = identity()
        model.activate(scope: next, workspace: .init(), scrollAnchorID: nil)
        model.update(sources(next, count: 5))
        model.interaction.apply(.began)
        model.update(sources(next, count: 6))
        model.update(sources(scope, count: 99))
        model.interaction.apply(.ended)
        model.finishDeferredPresentation(scope: scope)
        #expect(model.rows.first?.itemCount == 5)
        model.finishDeferredPresentation(scope: next)
        #expect(model.rows.first?.itemCount == 6)
    }

    private func identity() -> WorkbenchSessionIdentity {
        WorkbenchSessionIdentity(controllerID: UUID(), generation: UUID())
    }

    private func rules(_ scope: WorkbenchSessionIdentity, revision: Int) -> RulesWorkspaceInput {
        RulesWorkspaceInput(
            identity: scope,
            rules: [.init(id: "rule", index: 1, type: "DOMAIN", payload: "example.test", proxy: "DIRECT", hitCount: revision)],
            connections: (0..<revision).map { ConnectionSnapshot(id: "connection-\($0)", rule: "DOMAIN", rulePayload: "example.test") },
            structureRevision: UInt64(revision), query: "", language: .english
        )
    }

    private func sources(_ scope: WorkbenchSessionIdentity, count: Int, query: String = "") -> WorkbenchSourcesPresentationInput {
        WorkbenchSourcesPresentationInput(
            scope: scope,
            sources: [
                .init(kind: .proxy, name: "Zulu", type: "HTTP", updatable: true, itemCount: count),
                .init(kind: .rule, name: "Alpha", type: "HTTP", updatable: true, itemCount: 10),
            ],
            query: query, language: .english
        )
    }
}
