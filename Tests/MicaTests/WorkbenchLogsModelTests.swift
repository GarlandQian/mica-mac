import Foundation
import Observation
import Synchronization
import Testing
@testable import Mica
@testable import MicaCore

@MainActor
struct WorkbenchLogsModelTests {
    private func makeModel(
        workspace: WorkbenchDestinationWorkspace = WorkbenchDestinationWorkspace()
    ) -> (WorkbenchLogsModel, WorkbenchSessionIdentity) {
        let scope = WorkbenchSessionIdentity(controllerID: UUID(), generation: UUID())
        let model = WorkbenchLogsModel()
        model.activate(
            scope: scope,
            workspace: workspace,
            scrollAnchorID: workspace.scrollAnchorID,
            defaultLevel: .all,
            availableLevels: LogSessionLevel.allCases
        )
        return (model, scope)
    }

    private func entry(_ id: String, level: String = "info", payload: String? = nil) -> ControllerLogEntry {
        ControllerLogEntry(
            id: id,
            receivedAt: Date(timeIntervalSince1970: 1_000),
            message: LogMessage(type: level, payload: payload ?? id)
        )
    }

    private func publish(
        _ entries: [ControllerLogEntry],
        revision: UInt64,
        to model: WorkbenchLogsModel,
        scope: WorkbenchSessionIdentity,
        query: String = "",
        now: Date = Date(timeIntervalSince1970: 1_000)
    ) {
        model.update(
            catalog: LogsCatalogSnapshot(entries: entries, entriesRevision: revision),
            request: WorkbenchLogsPresentationRequest(
                scope: scope, revision: revision, query: query, language: .english
            ),
            now: now
        )
    }

    @Test func filtersPreserveIncomingOrderAndReuseFormattedRows() {
        let (model, scope) = makeModel()
        let entries = [entry("Zulu", level: "warn"), entry("Alpha"), entry("Beta", level: "warn")]
        publish(entries, revision: 1, to: model, scope: scope)
        #expect(model.rows.map(\.id) == ["Zulu", "Alpha", "Beta"])
        let formatted = model.formattedRowCount

        model.setLevel(.warning)
        #expect(model.rows.map(\.id) == ["Zulu", "Beta"])
        #expect(model.sourceCount == 3)
        publish(entries, revision: 1, to: model, scope: scope, query: "Beta")
        #expect(model.rows.map(\.id) == ["Beta"])
        #expect(model.formattedRowCount == formatted)
    }

    @Test func followBurstKeepsOneDeadlineAndScrollsToLatestReceivedRow() throws {
        let (model, scope) = makeModel()
        let start = Date(timeIntervalSince1970: 1_000)
        publish([entry("one")], revision: 1, to: model, scope: scope, now: start)
        model.consumeFollow(try #require(model.followRequest), now: start)
        #expect(model.scrollRequest?.id == "one")

        publish([entry("one"), entry("two")], revision: 2, to: model, scope: scope, now: start.addingTimeInterval(0.05))
        let request = try #require(model.followRequest)
        publish([entry("one"), entry("two"), entry("three")], revision: 3, to: model, scope: scope, now: start.addingTimeInterval(0.10))
        #expect(model.followRequest == request)
        model.consumeFollow(request, now: start.addingTimeInterval(0.15))
        #expect(model.scrollRequest?.id == "one")
        model.consumeFollow(request, now: start.addingTimeInterval(0.20))
        #expect(model.scrollRequest?.id == "three")
        #expect(model.followRequest == nil)
    }

    @Test func selectionAndUserPagingStopFollowUntilExplicitResume() throws {
        let (model, scope) = makeModel()
        publish((0..<100).map { entry("entry-\($0)") }, revision: 1, to: model, scope: scope)
        model.select("entry-20")
        #expect(!model.followsNewest)
        #expect(model.followRequest == nil)
        model.handleAccessibility(.movePage(lowerBound: 32, scope: scope))
        #expect(model.accessibilityWindow.range.count <= 32)
        #expect(!model.followsNewest)

        model.setFollowing(true)
        #expect(model.selectedRowID == nil)
        #expect(model.scrollRequest?.id == "entry-99")
        #expect(model.followsNewest)
    }

    @Test func oldSessionSnapshotsAndDelayedScrollCannotAffectReplacement() throws {
        let (model, oldScope) = makeModel()
        publish([entry("old")], revision: 9, to: model, scope: oldScope)
        let oldFollow = try #require(model.followRequest)
        let newScope = WorkbenchSessionIdentity(controllerID: oldScope.controllerID, generation: UUID())
        model.activate(scope: newScope, workspace: WorkbenchDestinationWorkspace(), scrollAnchorID: "new-anchor", defaultLevel: .all, availableLevels: LogSessionLevel.allCases)
        publish([entry("new")], revision: 1, to: model, scope: newScope)
        publish([entry("stale")], revision: 10, to: model, scope: oldScope)
        model.consumeFollow(oldFollow, now: Date(timeIntervalSince1970: 2_000))
        model.handleAccessibility(.selectRow(id: "new", scope: oldScope))

        #expect(model.rows.map(\.id) == ["new"])
        #expect(model.restoredScrollAnchorID == "new-anchor")
        #expect(model.scrollRequest == nil)
        #expect(model.selectedRowID == nil)
        publish([entry("older revision")], revision: 0, to: model, scope: newScope)
        #expect(model.rows.map(\.id) == ["new"])
    }

    @Test func replacementSnapshotPreservesThePageChosenAfterSelectingAnOlderRow() {
        let (model, scope) = makeModel()
        let entries = (0..<100).map { entry("entry-\($0)") }
        publish(entries, revision: 1, to: model, scope: scope)
        model.select("entry-20")
        model.handleAccessibility(.movePage(lowerBound: 64, scope: scope))
        #expect(model.accessibilityWindow.range == 64..<96)

        publish(entries + [entry("entry-100")], revision: 2, to: model, scope: scope)

        #expect(model.selectedRowID == "entry-20")
        #expect(model.accessibilityWindow.range == 64..<96)
        #expect(!model.followsNewest)
        #expect(model.followRequest == nil)
        #expect(model.scrollRequest == nil)
    }

    @Test func inactiveModelIgnoresUpdatesAndRestorationReconcilesSelection() {
        let (model, scope) = makeModel()
        let entries = [entry("current")]
        publish(entries, revision: 1, to: model, scope: scope)
        model.deactivate()
        publish([entry("hidden")], revision: 2, to: model, scope: scope)
        #expect(model.rows.map(\.id) == ["current"])
        #expect(model.followRequest == nil)

        model.activate(scope: scope, workspace: WorkbenchDestinationWorkspace(selectedItemID: "missing"), scrollAnchorID: nil, defaultLevel: .all, availableLevels: LogSessionLevel.allCases)
        publish(entries, revision: 1, to: model, scope: scope)
        #expect(model.selectedRowID == nil)
        #expect(!model.followsNewest)
    }

    @Test func inspectorResolverObservesUpdatedPayloadWithoutRecreatingTheResolver() {
        let (model, scope) = makeModel()
        publish([entry("same", payload: "before")], revision: 1, to: model, scope: scope)
        let changes = Mutex(0)
        withObservationTracking {
            _ = model.row(id: "same")
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        publish([entry("same", payload: "after")], revision: 2, to: model, scope: scope)
        #expect(changes.withLock { $0 } == 1)
        #expect(model.row(id: "same")?.payloadText == "after")
    }
}
