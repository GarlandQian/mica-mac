import Foundation
import MicaCore
import Observation
import Synchronization
import Testing
@testable import Mica

@MainActor
struct WorkbenchPageModelObservationTests {
    @Test func connectionInspectorObservesSameIDMetricUpdates() throws {
        let identity = makeIdentity()
        let model = ConnectionsWorkspaceModel()
        model.activate(identity: identity, workspace: .init(), restoredScrollAnchorID: nil)
        model.update(connections(identity: identity, revision: 1, firstUpload: 10, secondUpload: 30))
        let id = try #require(model.rows.first?.id)
        model.select(id, identity: identity)
        let staticProjections = model.staticProjectionCount
        let changes = Mutex(0)
        withObservationTracking {
            _ = model.row(id: id)
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        model.update(connections(identity: identity, revision: 2, firstUpload: 100, secondUpload: 30))

        #expect(changes.withLock { $0 } == 1)
        #expect(model.selectedRowID == id)
        #expect(model.row(id: id)?.connection.upload == 100)
        #expect(model.selectedRow?.connection.upload == 100)
        #expect(model.staticProjectionCount == staticProjections)
    }

    @Test func ruleInspectorObservesSameIDReportedCounterUpdates() throws {
        let identity = makeIdentity()
        let model = RulesWorkspaceModel()
        model.activate(identity: identity, workspace: .init(), restoredScrollAnchorID: nil)
        model.update(rules(identity: identity, hitCount: 1))
        let id = try #require(model.rows.first?.id)
        model.select(id, identity: identity)
        let changes = Mutex(0)
        withObservationTracking {
            _ = model.inspectorRow(type: "DOMAIN", payload: "example.test")
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        model.update(rules(identity: identity, hitCount: 9))

        #expect(changes.withLock { $0 } == 1)
        #expect(model.selectedRowID == id)
        #expect(model.inspectorRow(type: "DOMAIN", payload: "example.test")?.hitCount == 9)
    }

    @Test func continuousScrollingKeepsTableStableAndPublishesOnlyLatestFrameAtScrollEnd() throws {
        let identity = makeIdentity()
        let model = ConnectionsWorkspaceModel()
        model.activate(identity: identity, workspace: metricSortWorkspace(), restoredScrollAnchorID: nil)
        model.update(connections(identity: identity, revision: 1, firstUpload: 10, secondUpload: 30))
        #expect(model.rows.map(\.connection.id) == ["second", "first"])
        model.tableInteraction.apply(.began)
        let changes = Mutex(0)
        withObservationTracking {
            _ = model.rows
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        for revision in 2...20 {
            model.update(connections(identity: identity, revision: UInt64(revision), firstUpload: revision * 100, secondUpload: 40))
            // Neither a delayed callback nor another publication may reorder
            // the rows while the user is still scrolling.
            model.finishDeferredPresentation(identity: identity)
        }
        #expect(changes.withLock { $0 } == 0)
        #expect(model.rows.map(\.connection.id) == ["second", "first"])
        #expect(model.rows.last?.connection.upload == 10)
        #expect(model.tableInteraction.isUserScrolling)

        model.tableInteraction.apply(.ended)
        model.finishDeferredPresentation(identity: identity)
        #expect(changes.withLock { $0 } == 1)
        #expect(model.rows.map(\.connection.id) == ["first", "second"])
        #expect(model.rows.first?.connection.upload == 2_000)
        #expect(!model.tableInteraction.isUserScrolling)
        #expect(!model.update(connections(identity: identity, revision: 19, firstUpload: 10, secondUpload: 30)))
        #expect(model.rows.first?.connection.upload == 2_000)
    }

    @Test func oldSessionScrollCallbackCannotFlushReplacementSessionPendingRows() {
        let identity = makeIdentity()
        let model = ConnectionsWorkspaceModel()
        model.activate(identity: identity, workspace: metricSortWorkspace(), restoredScrollAnchorID: nil)
        model.update(connections(identity: identity, revision: 1, firstUpload: 10, secondUpload: 30))
        model.tableInteraction.apply(.began)
        model.update(connections(identity: identity, revision: 2, firstUpload: 100, secondUpload: 30))

        let next = WorkbenchSessionIdentity(controllerID: identity.controllerID, generation: UUID())
        model.activate(identity: next, workspace: metricSortWorkspace(), restoredScrollAnchorID: nil)
        #expect(!model.tableInteraction.isUserScrolling)
        model.update(connections(identity: next, revision: 1, firstUpload: 10, secondUpload: 30))
        model.tableInteraction.apply(.began)
        model.update(connections(identity: next, revision: 2, firstUpload: 300, secondUpload: 30))

        model.tableInteraction.apply(.ended)
        model.finishDeferredPresentation(identity: identity)
        #expect(model.rows.map(\.connection.id) == ["second", "first"])
        model.finishDeferredPresentation(identity: next)
        #expect(model.rows.map(\.connection.id) == ["first", "second"])
        #expect(model.rows.first?.connection.upload == 300)

        model.tableInteraction.apply(.began)
        model.update(connections(identity: next, revision: 3, firstUpload: 900, secondUpload: 30))
        model.deactivate()
        model.finishDeferredPresentation(identity: next)
        #expect(model.rows.first?.connection.upload == 300)
    }

    @Test func explicitFiltersAndSortsApplyLatestSnapshotDuringScrolling() {
        let identity = makeIdentity()
        let model = ConnectionsWorkspaceModel()
        model.activate(identity: identity, workspace: metricSortWorkspace(), restoredScrollAnchorID: nil)
        model.update(connections(identity: identity, revision: 1, firstUpload: 10, secondUpload: 30))
        model.tableInteraction.apply(.began)
        let next = connections(identity: identity, revision: 2, firstUpload: 100, secondUpload: 30)
        model.update(next)

        model.sortOrder = ConnectionsWorkspaceModel.sortOrder(from: [.init(field: "upload", ascending: true)])
        model.update(next)
        #expect(model.rows.map(\.connection.upload) == [30, 100])

        var filtered = connections(identity: identity, revision: 3, firstUpload: 200, secondUpload: 40)
        filtered.query = "no match"
        model.update(filtered)
        #expect(model.rows.isEmpty)
        #expect(model.allRows.first?.connection.upload == 200)

        filtered.query = ""
        model.update(filtered)
        #expect(model.rows.map(\.connection.upload) == [40, 200])
        model.tableInteraction.apply(.ended)
        model.finishDeferredPresentation(identity: identity)
        #expect(model.rows.map(\.connection.upload) == [40, 200])
    }

    @Test func deferredStructureCannotRetargetAConnectionCloseToReusedID() throws {
        let identity = makeIdentity()
        let model = ConnectionsWorkspaceModel()
        model.activate(identity: identity, workspace: .init(), restoredScrollAnchorID: nil)
        let original = ConnectionSnapshot(id: "reused", start: "2026-09-23T01:00:00Z")
        let replacement = ConnectionSnapshot(id: "reused", start: "2026-09-23T02:00:00Z")
        let first = ConnectionsWorkspaceInput(
            identity: identity,
            catalog: .init(connections: [original], traffic: .init(upload: 0, download: 0), structureRevision: 1, metricsRevision: 1),
            closedConnections: [], closedRevision: 0, query: "", language: .english
        )
        model.update(first)
        let rowID = try #require(model.rows.first?.id)
        model.requestClose(.connection(rowID), identity: identity)
        model.tableInteraction.apply(.began)
        let next = ConnectionsWorkspaceInput(
            identity: identity,
            catalog: .init(connections: [replacement], traffic: .init(upload: 0, download: 0), structureRevision: 2, metricsRevision: 2),
            closedConnections: [], closedRevision: 0, query: "", language: .english
        )
        model.update(next)
        #expect(model.rows.first?.connection == original)
        #expect(model.closeTargets(for: .connection(rowID), currentConnections: [replacement], identity: identity) == nil)
        #expect(model.closeTargets(for: .connection(rowID), currentConnections: [], identity: identity) == nil)
        #expect(model.closeTargets(for: .connection(rowID), currentConnections: [original, original], identity: identity) == nil)
        #expect(model.closeTargets(for: .connection(rowID), currentConnections: [original], identity: identity) == [original])
        model.tableInteraction.apply(.ended)
        model.finishDeferredPresentation(identity: identity)
        #expect(model.rows.first?.connection == replacement)
        #expect(model.closeIntent == nil)
    }

    private func makeIdentity() -> WorkbenchSessionIdentity {
        WorkbenchSessionIdentity(controllerID: UUID(), generation: UUID())
    }

    private func metricSortWorkspace() -> WorkbenchDestinationWorkspace {
        WorkbenchDestinationWorkspace(sort: [WorkbenchWorkspaceSort(field: "upload", ascending: false)])
    }

    private func connections(
        identity: WorkbenchSessionIdentity,
        revision: UInt64,
        firstUpload: Int,
        secondUpload: Int
    ) -> ConnectionsWorkspaceInput {
        ConnectionsWorkspaceInput(
            identity: identity,
            catalog: ConnectionsCatalogSnapshot(
                connections: [
                    ConnectionSnapshot(id: "first", upload: firstUpload),
                    ConnectionSnapshot(id: "second", upload: secondUpload),
                ],
                traffic: TrafficSnapshot(upload: 0, download: 0),
                structureRevision: 1,
                metricsRevision: revision
            ),
            closedConnections: [],
            closedRevision: 0,
            query: "",
            language: .english
        )
    }

    private func rules(identity: WorkbenchSessionIdentity, hitCount: Int) -> RulesWorkspaceInput {
        RulesWorkspaceInput(
            identity: identity,
            rules: [RuleViewState(id: "rule", index: 1, type: "DOMAIN", payload: "example.test", proxy: "DIRECT", hitCount: hitCount)],
            connections: [],
            structureRevision: 1,
            query: "",
            language: .english
        )
    }
}
