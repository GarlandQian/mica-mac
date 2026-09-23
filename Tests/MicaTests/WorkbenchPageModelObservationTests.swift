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

    @Test func continuousScrollingCoalescesMetricSortsAndFlushesAtDeadlineOrScrollEnd() throws {
        let identity = makeIdentity()
        let model = ConnectionsWorkspaceModel()
        model.activate(identity: identity, workspace: metricSortWorkspace(), restoredScrollAnchorID: nil)
        let start = Date(timeIntervalSince1970: 1_000)
        model.update(connections(identity: identity, revision: 1, firstUpload: 10, secondUpload: 30), now: start)
        #expect(model.rows.map(\.connection.id) == ["second", "first"])
        model.tableInteraction.apply(.began)

        model.update(connections(identity: identity, revision: 2, firstUpload: 100, secondUpload: 40), now: start)
        let deadline = try #require(model.metricSortDeadline)
        #expect(model.rows.map(\.connection.id) == ["second", "first"])
        #expect(model.rows.last?.connection.upload == 100)

        model.update(connections(identity: identity, revision: 3, firstUpload: 200, secondUpload: 60), now: start.addingTimeInterval(0.10))
        #expect(model.metricSortDeadline == deadline)
        model.commitScheduledMetricSort(identity: identity, deadline: deadline, now: start.addingTimeInterval(0.15))
        #expect(model.rows.map(\.connection.id) == ["second", "first"])
        model.commitScheduledMetricSort(identity: identity, deadline: deadline, now: deadline)
        #expect(model.rows.map(\.connection.id) == ["first", "second"])
        #expect(model.metricSortDeadline == nil)
        #expect(model.tableInteraction.isUserScrolling)

        model.update(connections(identity: identity, revision: 4, firstUpload: 200, secondUpload: 300), now: deadline.addingTimeInterval(0.05))
        let nextDeadline = try #require(model.metricSortDeadline)
        #expect(model.rows.map(\.connection.id) == ["first", "second"])
        model.commitScheduledMetricSort(identity: identity, deadline: deadline, now: nextDeadline)
        #expect(model.metricSortDeadline == nextDeadline)
        #expect(model.rows.map(\.connection.id) == ["first", "second"])

        model.tableInteraction.apply(.ended)
        model.finishDeferredMetricSort(identity: identity)
        #expect(model.rows.map(\.connection.id) == ["second", "first"])
        #expect(model.metricSortDeadline == nil)
        #expect(!model.tableInteraction.isUserScrolling)
    }

    @Test func oldSessionSortCallbackCannotFlushReplacementSessionPendingSort() throws {
        let identity = makeIdentity()
        let model = ConnectionsWorkspaceModel()
        model.activate(identity: identity, workspace: metricSortWorkspace(), restoredScrollAnchorID: nil)
        let start = Date(timeIntervalSince1970: 2_000)
        model.update(connections(identity: identity, revision: 1, firstUpload: 10, secondUpload: 30), now: start)
        model.tableInteraction.apply(.began)
        model.update(connections(identity: identity, revision: 2, firstUpload: 100, secondUpload: 30), now: start)
        let oldDeadline = try #require(model.metricSortDeadline)

        let next = WorkbenchSessionIdentity(controllerID: identity.controllerID, generation: UUID())
        model.activate(identity: next, workspace: metricSortWorkspace(), restoredScrollAnchorID: nil)
        #expect(!model.tableInteraction.isUserScrolling)
        model.update(connections(identity: next, revision: 1, firstUpload: 10, secondUpload: 30), now: start)
        model.tableInteraction.apply(.began)
        model.update(connections(identity: next, revision: 2, firstUpload: 100, secondUpload: 30), now: start)
        let newDeadline = try #require(model.metricSortDeadline)
        #expect(newDeadline == oldDeadline)

        model.commitScheduledMetricSort(identity: identity, deadline: oldDeadline, now: oldDeadline)
        model.finishDeferredMetricSort(identity: identity)
        #expect(model.rows.map(\.connection.id) == ["second", "first"])
        #expect(model.metricSortDeadline == newDeadline)
        model.commitScheduledMetricSort(identity: next, deadline: newDeadline, now: newDeadline)
        #expect(model.rows.map(\.connection.id) == ["first", "second"])
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
