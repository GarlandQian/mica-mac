import Foundation
import MicaCore
import Observation
import Synchronization
import Testing
@testable import Mica

struct WorkbenchNavigationTests {
    @Test func destinationsKeepTheFixedProductOrder() {
        #expect(WorkbenchDestination.allCases.map(\.rawValue) == [
            "overview",
            "proxies",
            "connections",
            "logs",
            "rules",
            "sources",
            "controllers",
            "configuration",
            "actions",
            "diagnostics",
        ])

        #expect(WorkbenchDestination.workbenchTabCases.map(\.rawValue) == [
            "overview", "proxies", "connections", "logs", "rules", "sources",
        ])
        #expect(WorkbenchDestination.operateCases.map(\.rawValue) == [
            "overview", "proxies", "connections", "rules", "sources",
        ])
        #expect(WorkbenchDestination.observeCases.map(\.rawValue) == [
            "logs", "diagnostics",
        ])
        #expect(WorkbenchDestination.manageCases.map(\.rawValue) == [
            "controllers", "configuration", "actions",
        ])
        #expect(
            WorkbenchDestination.sidebarCases.map(\.rawValue) == [
                "overview", "proxies", "connections", "rules", "sources",
                "logs", "diagnostics",
                "controllers", "configuration", "actions",
            ]
        )
    }

    @Test func destinationsKeepStableGroupsAndControllerRequirements() {
        #expect(WorkbenchDestination.Group.allCases.map(\.titleKey) == [
            "sidebar.group_workspace",
            "sidebar.group_monitor",
            "sidebar.group_controller",
        ])
        #expect(
            WorkbenchDestination.allCases
                .filter { $0.group == .operate }
                .map(\.rawValue)
                == WorkbenchDestination.operateCases.map(\.rawValue)
        )
        #expect(
            WorkbenchDestination.allCases
                .filter { $0.group == .observe }
                .map(\.rawValue)
                == WorkbenchDestination.observeCases.map(\.rawValue)
        )
        #expect(
            WorkbenchDestination.allCases
                .filter { $0.group == .manage }
                .map(\.rawValue)
                == WorkbenchDestination.manageCases.map(\.rawValue)
        )
        #expect(!WorkbenchDestination.controllers.requiresController)
        #expect(
            WorkbenchDestination.allCases
                .filter(\.requiresController)
                .map(\.rawValue)
                == [
                    "overview", "proxies", "connections", "logs", "rules", "sources",
                    "configuration", "actions", "diagnostics",
                ]
        )
    }

    @Test func searchAndKeyboardDestinationsRemainDeliberate() {
        #expect(
            WorkbenchDestination.allCases
                .filter(\.supportsSearch)
                .map(\.rawValue)
                == ["connections", "logs", "rules", "sources", "controllers"]
        )
        // Proxies has separate, explicitly scoped directory and node searches.
        #expect(!WorkbenchDestination.proxies.supportsSearch)
        #expect(WorkbenchDestination.overview.shortcut == "1")
        #expect(WorkbenchDestination.proxies.shortcut == "2")
        #expect(WorkbenchDestination.connections.shortcut == "3")
        #expect(WorkbenchDestination.logs.shortcut == "4")
        #expect(WorkbenchDestination.rules.shortcut == "5")
        #expect(WorkbenchDestination.sources.shortcut == "6")
        #expect(
            WorkbenchDestination.manageCases.allSatisfy { $0.shortcut == nil }
        )
        #expect(WorkbenchDestination.diagnostics.shortcut == nil)
    }

    @Test func sidebarGroupsReachEveryDestinationExactlyOnce() {
        let destinations = WorkbenchDestination.Group.allCases.flatMap(\.destinations)
        #expect(destinations == WorkbenchDestination.sidebarCases)
        #expect(Set(destinations) == Set(WorkbenchDestination.allCases))
        #expect(destinations.count == Set(destinations).count)
    }

    @Test func inspectorsOnlyBelongToDestinationsWithDetailContent() {
        #expect(WorkbenchDestination.allCases.filter(\.supportsInspector) == [
            .overview, .connections, .logs, .rules, .sources, .controllers,
        ])
        #expect(!WorkbenchDestination.proxies.supportsInspector)
        #expect(!WorkbenchDestination.actions.supportsInspector)
        #expect(!WorkbenchDestination.configuration.supportsInspector)
        #expect(!WorkbenchDestination.diagnostics.supportsInspector)
    }

    @Test func inspectorSelectionsDeclareStableDefaultDestinations() {
        let controllerID = UUID()

        #expect(WorkbenchInspectorSelection.none.owningDestination == nil)
        #expect(
            WorkbenchInspectorSelection.proxyGroup(
                groupName: "Group",
                groupOccurrenceID: "group-0"
            ).owningDestination == .overview
        )
        #expect(
            WorkbenchInspectorSelection.proxyNode(
                groupName: "Group",
                groupOccurrenceID: "group-0",
                nodeName: "Node"
            ).owningDestination == .overview
        )
        #expect(WorkbenchInspectorSelection.connection(id: "connection").owningDestination == .connections)
        #expect(
            WorkbenchInspectorSelection.rule(type: "DOMAIN", payload: "example.com")
                .owningDestination == .rules
        )
        #expect(WorkbenchInspectorSelection.log(id: "log").owningDestination == .logs)
        #expect(WorkbenchInspectorSelection.source(id: "source").owningDestination == .sources)
        #expect(WorkbenchInspectorSelection.controller(id: controllerID).owningDestination == .controllers)
    }

    @MainActor
    @Test func inspectorDestinationTransitionsHideAndRestoreWithoutErasingWorkspaceSelection() {
        let fixture = makeWorkspaceStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = fixture.store
        let controllerID = UUID()

        store.update(controllerID: controllerID, destination: .connections) {
            $0.selectedItemID = "connection-1"
        }
        store.selectInspector(.connection(id: "connection-1"))

        #expect(store.isInspectorPresented)
        #expect(store.inspectorOwningDestination == .connections)
        #expect(store.inspectorSelection(for: .connections) == .connection(id: "connection-1"))

        store.prepareInspectorForDestinationChange(to: .logs)
        #expect(!store.isInspectorPresented)
        #expect(store.inspectorSelection == .connection(id: "connection-1"))
        #expect(store.inspectorSelection(for: .logs) == .none)
        #expect(
            store.workspace(controllerID: controllerID, destination: .connections)
                .selectedItemID == "connection-1"
        )

        store.prepareInspectorForDestinationChange(to: .connections)
        #expect(store.isInspectorPresented)
        #expect(store.inspectorSelection(for: .connections) == .connection(id: "connection-1"))
    }

    @MainActor
    @Test func proxyInlineDetailsCannotTakeOwnershipOfOverviewInspector() {
        let fixture = makeWorkspaceStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = fixture.store
        let selection = WorkbenchInspectorSelection.proxyNode(
            groupName: "Group",
            groupOccurrenceID: "group-0",
            nodeName: "Node"
        )

        store.selectInspector(selection, from: .overview)
        #expect(store.inspectorOwningDestination == .overview)
        #expect(store.inspectorSelection(for: .overview) == selection)
        #expect(store.inspectorSelection(for: .proxies) == .none)

        store.prepareInspectorForDestinationChange(to: .proxies)
        #expect(!store.isInspectorPresented)

        store.selectInspector(selection, from: .proxies)
        #expect(!store.isInspectorPresented)
        #expect(store.inspectorOwningDestination == .overview)
        #expect(store.inspectorSelection(for: .proxies) == .none)
        #expect(store.inspectorSelection(for: .overview) == selection)

        store.prepareInspectorForDestinationChange(to: .overview)
        #expect(store.isInspectorPresented)
        #expect(store.inspectorSelection(for: .overview) == selection)
    }

    @MainActor
    @Test func latePageOwnedInspectorClearCannotEraseAnotherDestinationSelection() {
        let fixture = makeWorkspaceStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = fixture.store
        let overviewSelection = WorkbenchInspectorSelection.proxyNode(
            groupName: "Overview Group",
            groupOccurrenceID: "overview-group-0",
            nodeName: "Overview Node"
        )

        store.selectInspector(.connection(id: "connection-1"))
        store.selectInspector(overviewSelection, from: .overview)

        #expect(!store.clearInspectorSelection(ownedBy: .connections))
        #expect(!store.clearInspectorSelection(ownedBy: .proxies))
        #expect(store.inspectorSelection(for: .overview) == overviewSelection)
        #expect(store.isInspectorPresented)

        #expect(store.clearInspectorSelection(ownedBy: .overview))
        #expect(store.inspectorSelection == .none)
        #expect(store.inspectorOwningDestination == nil)
        #expect(store.isInspectorPresented)
    }

    @MainActor
    @Test func inspectorDismissClearsOriginAndSessionEndCannotRestoreDetail() {
        let fixture = makeWorkspaceStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = fixture.store
        let controllerID = UUID()

        store.selectInspector(.log(id: "log-1"))
        store.dismissInspector()
        store.prepareInspectorForDestinationChange(to: .logs)

        #expect(store.inspectorSelection == .none)
        #expect(store.inspectorOwningDestination == nil)
        #expect(!store.isInspectorPresented)

        store.selectInspector(.source(id: "source-1"))
        store.clearSessionBoundState(controllerID: controllerID)
        #expect(store.inspectorSelection == .none)
        #expect(store.inspectorOwningDestination == nil)
        #expect(!store.isInspectorPresented)
    }

    @Test func editorPresentationsUseUniqueViewIdentityForTheSameDraft() {
        let draft = RouterDraft(displayName: "Controller")
        let first = RouterEditorPresentation(titleKey: "editor.edit_router", draft: draft)
        let second = RouterEditorPresentation(titleKey: "editor.edit_router", draft: draft)

        #expect(first.draft.id == second.draft.id)
        #expect(first.id != second.id)
    }

    @Test func controllerEditorUsesCurrentWorkbenchPresentation() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appending(
            path: "Sources/Mica/Features/Routers/Views/RouterEditorView.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("WorkbenchPageScaffold"))
        #expect(source.contains("WorkbenchCommandBar"))
        #expect(source.contains("WorkbenchManagementFormCanvas"))
        #expect(source.contains("if testState.shouldShow"))
        #expect(!source.contains("editorCanvas(availableWidth:"))
        #expect(!source.contains("GeometryReader"))
        #expect(!source.contains("HSplitView"))
    }

    @MainActor
    @Test func workspaceStateIsIsolatedByControllerAndDestination() {
        let fixture = makeWorkspaceStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = fixture.store
        let first = UUID()
        let second = UUID()

        store.update(controllerID: first, destination: .connections) {
            $0.searchText = "github"
            $0.selectedItemID = "connection-1"
        }
        store.update(controllerID: second, destination: .connections) {
            $0.searchText = "apple"
        }
        store.update(controllerID: first, destination: .logs) {
            $0.searchText = "warning"
        }

        #expect(
            store.workspace(controllerID: first, destination: .connections).searchText
                == "github"
        )
        #expect(
            store.workspace(controllerID: second, destination: .connections).searchText
                == "apple"
        )
        #expect(
            store.workspace(controllerID: first, destination: .logs).searchText
                == "warning"
        )
    }

    @MainActor
    @Test func sessionEndClearsOnlyDataBoundWorkspaceState() {
        let fixture = makeWorkspaceStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = fixture.store
        let controllerID = UUID()

        store.update(controllerID: controllerID, destination: .proxies) {
            $0.searchText = "smart"
            $0.filters["scope"] = "available"
            $0.sort = [WorkbenchWorkspaceSort(field: "latency", ascending: true)]
            $0.selectedItemID = "node-1"
            $0.scrollAnchorID = "node-1"
            $0.activeGroupID = "group-1"
            $0.proxyMemberQuery = "node"
            $0.inspectedProxyMemberID = "node-1"
        }

        store.clearSessionBoundState(controllerID: controllerID)
        let workspace = store.workspace(controllerID: controllerID, destination: .proxies)

        #expect(workspace.searchText == "smart")
        #expect(workspace.filters["scope"] == "available")
        #expect(workspace.sort == [WorkbenchWorkspaceSort(field: "latency", ascending: true)])
        #expect(workspace.selectedItemID == nil)
        #expect(workspace.scrollAnchorID == nil)
        #expect(workspace.activeGroupID == nil)
        #expect(workspace.proxyMemberQuery.isEmpty)
        #expect(workspace.inspectedProxyMemberID == nil)
    }

    @MainActor
    @Test func connectionNavigationRejectsAStaleGeneration() {
        let fixture = makeWorkspaceStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = fixture.store
        let controllerID = UUID()
        let generation = UUID()

        store.stageConnectionNavigation(
            WorkbenchConnectionNavigationSelection(
                controllerID: controllerID,
                generation: generation,
                sourceIndex: 7,
                reportedConnectionID: "connection-1"
            )
        )

        #expect(
            store.consumeConnectionNavigation(
                controllerID: controllerID,
                generation: UUID()
            ) == nil
        )
        #expect(
            store.consumeConnectionNavigation(
                controllerID: controllerID,
                generation: generation
            )?.matches(sourceIndex: 7, reportedConnectionID: "connection-1") == true
        )
        #expect(
            store.consumeConnectionNavigation(
                controllerID: controllerID,
                generation: generation
            ) == nil
        )
    }

    @MainActor
    @Test func connectionNavigationUsesReportedOccurrenceForDuplicateAndBlankIDs() {
        let fixture = makeWorkspaceStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = fixture.store
        let controllerID = UUID()
        let generation = UUID()
        let duplicate = WorkbenchConnectionNavigationSelection(
            controllerID: controllerID,
            generation: generation,
            sourceIndex: 3,
            reportedConnectionID: "duplicate"
        )

        #expect(duplicate.matches(sourceIndex: 3, reportedConnectionID: "duplicate"))
        #expect(!duplicate.matches(sourceIndex: 1, reportedConnectionID: "duplicate"))
        #expect(!duplicate.matches(sourceIndex: 3, reportedConnectionID: "other"))

        let blank = WorkbenchConnectionNavigationSelection(
            controllerID: controllerID,
            generation: generation,
            sourceIndex: 4,
            reportedConnectionID: ""
        )
        store.stageConnectionNavigation(blank)

        let workspace = store.workspace(
            controllerID: controllerID,
            destination: .connections
        )
        #expect(workspace.selectedItemID == nil)
        #expect(
            workspace.pendingConnectionSelection?.matches(
                sourceIndex: 4,
                reportedConnectionID: ""
            ) == true
        )
        #expect(
            store.consumeConnectionNavigation(
                controllerID: controllerID,
                generation: generation
            ) == blank
        )
    }

    @MainActor
    @Test func ruleNavigationIsSessionBoundAndInvalidatedByGenerationChange() {
        let fixture = makeWorkspaceStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = fixture.store
        let controllerID = UUID()
        let generation = UUID()

        store.activateSession(controllerID: controllerID, generation: generation)
        store.stageRuleNavigation(
            WorkbenchRuleNavigationSelection(
                controllerID: controllerID,
                generation: generation,
                sourceIndex: 7,
                reportedRuleID: "rule-id",
                type: "DOMAIN",
                payload: "example.com"
            )
        )

        #expect(
            store.workspace(controllerID: controllerID, destination: .rules)
                .pendingRuleSelection?.matches(
                    sourceIndex: 7,
                    reportedRuleID: "rule-id",
                    type: "DOMAIN",
                    payload: "example.com"
                ) == true
        )
        #expect(
            store.consumeRuleNavigation(
                controllerID: UUID(),
                generation: generation
            ) == nil
        )
        #expect(
            store.workspace(controllerID: controllerID, destination: .rules)
                .pendingRuleSelection != nil
        )
        #expect(
            store.consumeRuleNavigation(
                controllerID: controllerID,
                generation: UUID()
            ) == nil
        )
        #expect(
            store.workspace(controllerID: controllerID, destination: .rules)
                .pendingRuleSelection != nil
        )

        store.activateSession(controllerID: controllerID, generation: UUID())

        #expect(
            store.workspace(controllerID: controllerID, destination: .rules)
                .pendingRuleSelection == nil
        )
        #expect(
            store.consumeRuleNavigation(
                controllerID: controllerID,
                generation: generation
            ) == nil
        )
    }

    @MainActor
    @Test func ruleNavigationRemainsPendingUntilItsExactCatalogRowResolves() throws {
        let fixture = makeWorkspaceStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = fixture.store
        let controllerID = UUID()
        let generation = UUID()
        let selection = WorkbenchRuleNavigationSelection(
            controllerID: controllerID,
            generation: generation,
            sourceIndex: 1,
            reportedRuleID: "target",
            type: "DOMAIN",
            payload: "example.com"
        )

        store.activateSession(controllerID: controllerID, generation: generation)
        store.stageRuleNavigation(selection)
        #expect(
            WorkbenchRuleNavigationResolver.resolve(
                selection,
                controllerID: controllerID,
                generation: generation,
                in: []
            ) == nil
        )
        #expect(
            store.workspace(controllerID: controllerID, destination: .rules)
                .pendingRuleSelection == selection
        )

        let rows = WorkbenchRuleProjection.rows(
            from: [
                RuleViewState(
                    id: "other",
                    type: "DOMAIN",
                    payload: "other.example",
                    proxy: "DIRECT"
                ),
                RuleViewState(
                    id: "target",
                    type: "DOMAIN",
                    payload: "example.com",
                    proxy: "Policy"
                ),
            ],
            connections: [],
            language: .english
        )
        let resolved = try #require(
            WorkbenchRuleNavigationResolver.resolve(
                selection,
                controllerID: controllerID,
                generation: generation,
                in: rows
            )
        )
        #expect(resolved.id == rows[1].id)
        #expect(
            store.workspace(controllerID: controllerID, destination: .rules)
                .pendingRuleSelection == selection
        )
        #expect(
            store.consumeRuleNavigation(
                controllerID: controllerID,
                generation: generation
            ) == selection
        )
        #expect(
            store.workspace(controllerID: controllerID, destination: .rules)
                .pendingRuleSelection == nil
        )
    }

    @MainActor
    @Test func deletingAControllerRemovesItsWorkspaceOnly() {
        let fixture = makeWorkspaceStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = fixture.store
        let removed = UUID()
        let retained = UUID()

        store.update(controllerID: removed, destination: .rules) {
            $0.searchText = "removed"
        }
        store.update(controllerID: retained, destination: .rules) {
            $0.searchText = "retained"
        }

        store.retainControllers([retained])

        #expect(
            store.workspace(controllerID: removed, destination: .rules).searchText.isEmpty
        )
        #expect(
            store.workspace(controllerID: retained, destination: .rules).searchText
                == "retained"
        )
    }

    @MainActor
    @Test func searchObservationIsScopedToOneWorkspaceField() {
        let fixture = makeWorkspaceStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = fixture.store
        let first = UUID()
        let second = UUID()
        let invalidated = Mutex(false)
        let binding = store.searchBinding(
            controllerID: first,
            destination: .connections
        )

        withObservationTracking {
            _ = binding.wrappedValue
        } onChange: {
            invalidated.withLock { $0 = true }
        }

        store.update(controllerID: first, destination: .connections) {
            $0.selectedItemID = "connection-1"
        }
        store.update(controllerID: second, destination: .connections) {
            $0.searchText = "another controller"
        }
        store.update(controllerID: first, destination: .logs) {
            $0.searchText = "another page"
        }

        #expect(!invalidated.withLock { $0 })

        binding.wrappedValue = "tracked search"

        #expect(invalidated.withLock { $0 })
    }

    @Test func controllerSelectorSnapshotKeepsOrderAndStableIdentity() {
        let first = RouterProfile(
            displayName: "Primary",
            scheme: .https,
            host: "2001:db8::1",
            port: 6171,
            controllerKind: .surgeCompatible
        )
        let second = RouterProfile(
            displayName: "Backup",
            host: "127.0.0.1",
            port: 9090,
            controllerKind: .mihomoCompatible
        )
        let snapshot = WorkbenchControllerSelectorSnapshot(
            profiles: [first, second],
            selectedID: second.id
        )

        #expect(snapshot.items.map(\.id) == [first.id, second.id])
        #expect(snapshot.items.map(\.displayName) == ["Primary", "Backup"])
        #expect(snapshot.items[0].endpointURL == "https://[2001:db8::1]:6171")
        #expect(snapshot.items[0].profile == first)
        #expect(snapshot.selectedItem?.id == second.id)

        let reselection = WorkbenchControllerSelectorSnapshot(
            profiles: [first, second],
            selectedID: first.id
        )
        #expect(reselection.items.map(\.id) == snapshot.items.map(\.id))
        #expect(reselection.selectedItem?.id == first.id)
    }

    @MainActor
    private func makeWorkspaceStore() -> (
        store: WorkbenchWorkspaceStore,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "MicaTests.WorkbenchNavigation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = WorkbenchWorkspaceStore(
            defaults: defaults,
            persistenceKey: "workspace",
            persistenceDelay: .seconds(60)
        )
        return (store, defaults, suiteName)
    }
}
