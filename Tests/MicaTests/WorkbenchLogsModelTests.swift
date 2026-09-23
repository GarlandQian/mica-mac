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

    @Test func scrollingCoalescesDeltasWithoutFormattingRowsOrLosingRetainedEntries() {
        let (model, scope) = makeModel()
        publish([entry("one"), entry("two")], revision: 1, to: model, scope: scope)
        model.select("one")
        model.interaction.apply(.began)
        let formatted = model.formattedRowCount
        let changes = Mutex(0)
        withObservationTracking {
            _ = model.rows
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        model.update(
            catalog: LogsCatalogSnapshot(
                entries: [entry("one"), entry("two"), entry("three")],
                entriesRevision: 2,
                lastChange: .delta(droppedEntryIDs: [], appendedEntries: [entry("three")])
            ),
            request: .init(scope: scope, revision: 2, query: "", language: .english)
        )
        model.update(
            catalog: LogsCatalogSnapshot(
                entries: [entry("two"), entry("three"), entry("four")],
                entriesRevision: 3,
                lastChange: .delta(droppedEntryIDs: ["one"], appendedEntries: [entry("four")])
            ),
            request: .init(scope: scope, revision: 3, query: "", language: .english)
        )
        model.finishDeferredPresentation(scope: scope)
        #expect(model.rows.map(\.id) == ["one", "two"])
        #expect(model.formattedRowCount == formatted)
        #expect(changes.withLock { $0 } == 0)

        model.interaction.apply(.ended)
        model.finishDeferredPresentation(scope: scope)
        #expect(model.rows.map(\.id) == ["two", "three", "four"])
        #expect(model.sourceCount == 3)
        #expect(model.selectedRowID == nil)
        #expect(!model.followsNewest)
        #expect(model.followRequest == nil)
        #expect(changes.withLock { $0 } == 1)
    }

    @Test func filteringAndJumpToNewestApplyPendingSnapshotImmediately() {
        let (model, scope) = makeModel()
        publish([entry("one")], revision: 1, to: model, scope: scope)
        model.interaction.apply(.began)
        model.setFollowing(false)
        let entries = [entry("one"), entry("warning", level: "warn")]
        publish(entries, revision: 2, to: model, scope: scope)
        #expect(model.rows.map(\.id) == ["one"])
        model.setLevel(.warning)
        #expect(model.rows.map(\.id) == ["warning"])
        #expect(model.sourceCount == 2)

        let newest = entries + [entry("latest warning", level: "warn")]
        publish(newest, revision: 3, to: model, scope: scope)
        #expect(model.rows.map(\.id) == ["warning"])
        model.jumpToNewest()
        #expect(model.rows.map(\.id) == ["warning", "latest warning"])
        #expect(model.scrollRequest?.id == "latest warning")
        #expect(model.followsNewest)

        publish(newest, revision: 3, to: model, scope: scope, query: "latest")
        #expect(model.rows.map(\.id) == ["latest warning"])
        model.interaction.apply(.ended)
        model.finishDeferredPresentation(scope: scope)
        #expect(model.rows.map(\.id) == ["latest warning"])
    }

    @Test func authoritativeEmptyClearCannotBeOverwrittenByDeferredRows() {
        let (model, scope) = makeModel()
        publish([entry("one")], revision: 1, to: model, scope: scope)
        model.interaction.apply(.began)
        model.setFollowing(false)
        publish([entry("one"), entry("two")], revision: 2, to: model, scope: scope)
        model.update(
            catalog: LogsCatalogSnapshot(entries: [], entriesRevision: 3),
            request: .init(scope: scope, revision: 3, query: "", language: .english)
        )
        #expect(model.rows.isEmpty)
        #expect(model.sourceCount == 0)
        model.interaction.apply(.ended)
        model.finishDeferredPresentation(scope: scope)
        publish([entry("obsolete")], revision: 2, to: model, scope: scope)
        #expect(model.rows.isEmpty)
    }

    @Test func asynchronousRuntimeClearPublishesResetBeforeScrollEndsEvenWhenNewLogsArrive() async throws {
        let (model, scope) = makeModel()
        let runtime = LiveSessionRuntime(
            controllerKind: .mihomoCompatible,
            initialPresentationDemand: LiveSessionPresentationDemand(
                identity: .init(controllerID: try #require(scope.controllerID), generation: scope.generation),
                revision: 1,
                observedDomains: [.logs],
                presentationPaused: false,
                logsPresentationPaused: false,
                baselinePublicationRequired: false
            )
        )
        let receivedAt = Date(timeIntervalSince1970: 1_000)
        _ = await runtime.ingestLog(
            .init(type: "info", payload: "before"), source: .mihomoWebSocket,
            receivedAt: receivedAt, id: "before"
        )
        let initial = try #require(await runtime.publication(for: .logs))
        guard case .logs(let initialLogs) = initial.payload else {
            Issue.record("Expected initial runtime log publication")
            return
        }
        var catalog = LogsCatalogSnapshot.empty.applying(initialLogs)
        model.update(catalog: catalog, request: .init(scope: scope, revision: catalog.entriesRevision, query: "", language: .english))
        model.interaction.apply(.began)
        model.setFollowing(false)

        _ = await runtime.ingestLog(
            .init(type: "info", payload: "pending"), source: .mihomoWebSocket,
            receivedAt: receivedAt.addingTimeInterval(1), id: "pending"
        )
        let appended = try #require(await runtime.publication(for: .logs))
        guard case .logs(let pendingLogs) = appended.payload else {
            Issue.record("Expected appended runtime log publication")
            return
        }
        catalog = catalog.applying(pendingLogs)
        let obsoleteCatalog = catalog
        model.update(catalog: catalog, request: .init(scope: scope, revision: catalog.entriesRevision, query: "", language: .english))
        #expect(model.rows.map(\.id) == ["before"])

        let clearing = Task {
            _ = await runtime.clearLogs(receivedAt: receivedAt.addingTimeInterval(2))
            // A stream event may arrive after the clear but before the scheduled
            // publication. The clear's complete snapshot is then non-empty.
            _ = await runtime.ingestLog(
                .init(type: "info", payload: "after clear"), source: .mihomoWebSocket,
                receivedAt: receivedAt.addingTimeInterval(3), id: "after-clear"
            )
            return await runtime.publication(for: .logs)
        }
        // This is all the button can observe before its asynchronous operation
        // finishes: it must neither clear optimistically nor flush pending rows.
        model.update(catalog: catalog, request: .init(scope: scope, revision: catalog.entriesRevision, query: "", language: .english))
        #expect(model.rows.map(\.id) == ["before"])
        let cleared = try #require(await clearing.value)
        guard case .logs(let resetLogs) = cleared.payload else {
            Issue.record("Expected runtime clear publication")
            return
        }
        #expect(resetLogs.fullSnapshot?.map(\.id) == ["after-clear"])
        catalog = catalog.applying(resetLogs)
        model.update(catalog: catalog, request: .init(scope: scope, revision: catalog.entriesRevision, query: "", language: .english))
        #expect(model.interaction.isUserScrolling)
        #expect(model.rows.map(\.id) == ["after-clear"])
        model.update(catalog: obsoleteCatalog, request: .init(scope: scope, revision: obsoleteCatalog.entriesRevision, query: "", language: .english))
        #expect(model.rows.map(\.id) == ["after-clear"])

        _ = await runtime.ingestLog(
            .init(type: "info", payload: "later"), source: .mihomoWebSocket,
            receivedAt: receivedAt.addingTimeInterval(4), id: "later"
        )
        let latest = try #require(await runtime.publication(for: .logs))
        guard case .logs(let latestLogs) = latest.payload else {
            Issue.record("Expected ordinary post-clear append")
            return
        }
        #expect(latestLogs.fullSnapshot == nil)
        catalog = catalog.applying(latestLogs)
        model.update(catalog: catalog, request: .init(scope: scope, revision: catalog.entriesRevision, query: "", language: .english))
        #expect(model.rows.map(\.id) == ["after-clear"])
        model.interaction.apply(.ended)
        model.finishDeferredPresentation(scope: scope)
        #expect(model.rows.map(\.id) == ["after-clear", "later"])
    }

    @Test func pendingRowsAndOldScrollCallbackCannotCrossSessionOrDeactivation() {
        let (model, scope) = makeModel()
        publish([entry("old")], revision: 1, to: model, scope: scope)
        model.interaction.apply(.began)
        model.setFollowing(false)
        publish([entry("old"), entry("old deferred")], revision: 2, to: model, scope: scope)

        let next = WorkbenchSessionIdentity(controllerID: scope.controllerID, generation: UUID())
        model.activate(scope: next, workspace: .init(), scrollAnchorID: nil, defaultLevel: .all, availableLevels: LogSessionLevel.allCases)
        #expect(!model.interaction.isUserScrolling)
        publish([entry("current")], revision: 1, to: model, scope: next)
        model.interaction.apply(.began)
        model.setFollowing(false)
        publish([entry("current"), entry("new deferred")], revision: 2, to: model, scope: next)
        model.interaction.apply(.ended)
        model.finishDeferredPresentation(scope: scope)
        #expect(model.rows.map(\.id) == ["current"])
        model.finishDeferredPresentation(scope: next)
        #expect(model.rows.map(\.id) == ["current", "new deferred"])

        model.interaction.apply(.began)
        publish([entry("current"), entry("new deferred"), entry("hidden")], revision: 3, to: model, scope: next)
        model.deactivate()
        model.finishDeferredPresentation(scope: next)
        #expect(model.rows.map(\.id) == ["current", "new deferred"])
    }
}
