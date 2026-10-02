import Foundation
import MicaCore
import Testing
@testable import Mica

@MainActor
struct WorkbenchPageModelsTests {
    @Test func connectionsRejectObsoleteSessionsAndClearSessionBoundInteractions() throws {
        let identity = Self.identity()
        let model = ConnectionsWorkspaceModel()
        model.activate(identity: identity, workspace: .init(), restoredScrollAnchorID: "anchor")
        let input = Self.connections(identity: identity, rows: [ConnectionSnapshot(id: "one")])
        #expect(model.update(input))
        let rowID = try #require(model.rows.first?.id)
        model.select(rowID, identity: identity)
        model.requestClose(.connection(rowID), identity: identity)
        #expect(model.closeIntent != nil)

        let next = WorkbenchSessionIdentity(controllerID: identity.controllerID, generation: UUID())
        model.activate(identity: next, workspace: .init(), restoredScrollAnchorID: nil)
        #expect(model.rows.isEmpty)
        #expect(model.selectedRowID == nil)
        #expect(model.closeIntent == nil)
        #expect(model.scrollRequest == nil)
        #expect(model.restoredScrollAnchorID == nil)
        #expect(!model.update(input))
        model.select(rowID, identity: identity)
        model.requestClose(.all, identity: identity)
        #expect(model.selectedRowID == nil)
        #expect(model.closeIntent == nil)

        let current = Self.connections(identity: next, rows: [ConnectionSnapshot(id: "new")], revision: 0)
        #expect(model.update(current))
        #expect(model.rows.first?.connection.id == "new")
        model.deactivate()
        #expect(!model.update(Self.connections(identity: next, rows: [])))
        #expect(model.rows.first?.connection.id == "new")
    }

    @Test func connectionsReuseStaticRowsForMetricsAndRejectOlderFrames() throws {
        let identity = Self.identity()
        let model = ConnectionsWorkspaceModel()
        model.activate(identity: identity, workspace: .init(), restoredScrollAnchorID: nil)
        let first = Self.connections(identity: identity, rows: [ConnectionSnapshot(id: "one", upload: 10)])
        #expect(model.update(first))
        let count = model.staticProjectionCount
        let current = Self.connections(
            identity: identity,
            rows: [ConnectionSnapshot(id: "one", upload: 200)],
            revision: 2
        )
        #expect(model.update(current))
        #expect(model.staticProjectionCount == count)
        #expect(model.rows.first?.connection.upload == 200)
        #expect(!model.update(first))
        #expect(model.rows.first?.connection.upload == 200)
    }

    @Test func connectionRevealFindsExactDuplicateBehindSearchAndUpdatesAccessibility() throws {
        let identity = Self.identity()
        let controllerID = try #require(identity.controllerID)
        let model = ConnectionsWorkspaceModel()
        model.activate(identity: identity, workspace: .init(), restoredScrollAnchorID: nil)
        let input = Self.connections(
            identity: identity,
            rows: [
                ConnectionSnapshot(id: "duplicate", metadata: ConnectionMetadataSnapshot(host: "alpha.example")),
                ConnectionSnapshot(id: "duplicate", metadata: ConnectionMetadataSnapshot(host: "beta.example")),
            ],
            query: "alpha"
        )
        #expect(model.update(input))
        #expect(model.rows.count == 1)
        let pending = WorkbenchConnectionNavigationSelection(
            controllerID: controllerID,
            generation: identity.generation,
            sourceIndex: 1,
            reportedConnectionID: "duplicate"
        )
        #expect(model.reveal(pending, input: input) == "")
        #expect(model.rows.count == 2)
        #expect(model.selectedRow?.sourceIndex == 1)
        #expect(model.selectedRow?.connection.metadata?.host == "beta.example")
        #expect(model.scrollRequest?.id == model.selectedRowID)
        #expect(model.accessibilityWindow.range.contains(1))
    }

    @Test func rulesChooseProjectionLayerFromActualChanges() throws {
        let identity = Self.identity()
        let model = RulesWorkspaceModel()
        model.activate(identity: identity, workspace: .init(), restoredScrollAnchorID: nil)
        let rule = Self.rule(id: "one", index: 1, payload: "example.com")
        let first = RulesWorkspaceInput(
            identity: identity,
            rules: [rule],
            connections: [ConnectionSnapshot(id: "a", rule: "DOMAIN", rulePayload: "example.com")],
            structureRevision: 1,
            query: "",
            language: .english
        )
        #expect(model.update(first))
        let sourceBuilds = model.staticProjectionCount
        let countBuilds = model.connectionIndexRebuildCount
        #expect(model.rows.first?.activeConnections == 1)

        var filtered = first
        filtered.query = "example"
        #expect(model.update(filtered))
        #expect(model.staticProjectionCount == sourceBuilds)
        #expect(model.connectionIndexRebuildCount == countBuilds)
        let next = RulesWorkspaceInput(
            identity: identity,
            rules: [rule],
            connections: [
                ConnectionSnapshot(id: "a", rule: "DOMAIN", rulePayload: "example.com"),
                ConnectionSnapshot(id: "b", rule: "DOMAIN", rulePayload: "example.com"),
            ],
            structureRevision: 2,
            query: "example",
            language: .english
        )
        #expect(model.update(next))
        #expect(model.staticProjectionCount == sourceBuilds)
        #expect(model.connectionIndexRebuildCount == countBuilds + 1)
        #expect(model.rows.first?.activeConnections == 2)
        #expect(!model.update(first))
        #expect(model.rows.first?.activeConnections == 2)
    }

    @Test func ruleRevealAndInspectorPreserveDuplicateOccurrenceIdentity() throws {
        let identity = Self.identity()
        let controllerID = try #require(identity.controllerID)
        let model = RulesWorkspaceModel()
        model.activate(identity: identity, workspace: .init(), restoredScrollAnchorID: nil)
        let input = RulesWorkspaceInput(
            identity: identity,
            rules: [
                Self.rule(id: "duplicate", index: 1, payload: "example.com"),
                Self.rule(id: "duplicate", index: 2, payload: "example.com"),
            ],
            connections: [],
            structureRevision: 1,
            query: "no match",
            language: .english
        )
        #expect(model.update(input))
        #expect(model.rows.isEmpty)
        #expect(model.inspectorRow(type: "DOMAIN", payload: "example.com") == nil)
        let selection = WorkbenchRuleNavigationSelection(
            controllerID: controllerID,
            generation: identity.generation,
            sourceIndex: 1,
            reportedRuleID: "duplicate",
            type: "DOMAIN",
            payload: "example.com"
        )
        #expect(model.reveal(selection, input: input) == "")
        #expect(model.rows.map(\.rule.index) == [1, 2])
        #expect(model.selectedRow?.sourceIndex == 1)
        #expect(model.inspectorRow(type: "DOMAIN", payload: "example.com")?.rule.index == 2)
        #expect(model.scrollRequest?.id == model.selectedRowID)
        #expect(model.accessibilityWindow.range.contains(1))
    }

    @Test func ruleFacetsNarrowControllerOrderAndRevealLiftsThem() throws {
        let identity = Self.identity()
        let controllerID = try #require(identity.controllerID)
        let model = RulesWorkspaceModel()
        var workspace = WorkbenchDestinationWorkspace()
        workspace.filters[RulesWorkspaceModel.policyFacetKey] = "Proxy"
        model.activate(identity: identity, workspace: workspace, restoredScrollAnchorID: nil)
        #expect(model.facets == WorkbenchRuleFacets(type: nil, policy: "Proxy"))

        let rules = [
            RuleViewState(id: "a", index: 1, type: "DOMAIN", payload: "a.example", proxy: "Proxy"),
            RuleViewState(id: "b", index: 2, type: "GEOIP", payload: "CN", proxy: "DIRECT"),
            RuleViewState(id: "c", index: 3, type: "DOMAIN-SUFFIX", payload: "c.example", proxy: "Proxy"),
            RuleViewState(id: "d", index: 4, type: "DOMAIN-SUFFIX", payload: "d.example", proxy: "DIRECT"),
            RuleViewState(id: "e", index: 5, type: "DOMAIN-SUFFIX", payload: "e.example", proxy: "Proxy"),
            RuleViewState(id: "f", index: 6, type: "MATCH", payload: "", proxy: "Proxy"),
        ]
        let input = RulesWorkspaceInput(
            identity: identity,
            rules: rules,
            connections: [],
            structureRevision: 1,
            query: "",
            language: .english
        )
        #expect(model.update(input))
        #expect(model.rows.map(\.rule.id) == ["a", "c", "e", "f"])
        #expect(model.allRows.count == rules.count)
        #expect(model.facetOptions.types.map(\.value) == ["DOMAIN-SUFFIX", "DOMAIN", "GEOIP", "MATCH"])
        #expect(model.facetOptions.types.map(\.count) == [3, 1, 1, 1])
        #expect(model.facetOptions.policies.map(\.value) == ["Proxy", "DIRECT"])

        model.facets.type = "DOMAIN-SUFFIX"
        #expect(model.update(input))
        #expect(model.rows.map(\.rule.id) == ["c", "e"])
        let staticBuilds = model.staticProjectionCount
        var searched = input
        searched.query = "e.example"
        #expect(model.update(searched))
        #expect(model.rows.map(\.rule.id) == ["e"])
        #expect(model.staticProjectionCount == staticBuilds)

        let hidden = WorkbenchRuleNavigationSelection(
            controllerID: controllerID,
            generation: identity.generation,
            sourceIndex: 1,
            reportedRuleID: "b",
            type: "GEOIP",
            payload: "CN"
        )
        #expect(model.reveal(hidden, input: searched) == "")
        #expect(model.facets == .none)
        #expect(model.rows.count == rules.count)
        #expect(model.selectedRow?.rule.id == "b")
    }

    @Test func rulesIgnoreUpdatesAfterDeactivationOrControllerSwitch() throws {
        let identity = Self.identity()
        let model = RulesWorkspaceModel()
        model.activate(identity: identity, workspace: .init(), restoredScrollAnchorID: "saved")
        let input = RulesWorkspaceInput(
            identity: identity,
            rules: [Self.rule(id: "one", index: 1, payload: "example.com")],
            connections: [],
            structureRevision: 1,
            query: "",
            language: .english
        )
        #expect(model.update(input))
        let selectedID = try #require(model.rows.first?.id)
        model.select(selectedID, identity: identity)
        model.deactivate()
        #expect(!model.update(input))
        model.activate(identity: Self.identity(), workspace: .init(), restoredScrollAnchorID: nil)
        #expect(model.rows.isEmpty)
        #expect(model.selectedRowID == nil)
        #expect(model.scrollRequest == nil)
        #expect(model.restoredScrollAnchorID == nil)
        #expect(!model.update(input))
        model.select(selectedID, identity: identity)
        #expect(model.selectedRowID == nil)
    }

    private static func identity() -> WorkbenchSessionIdentity {
        WorkbenchSessionIdentity(controllerID: UUID(), generation: UUID())
    }

    private static func connections(
        identity: WorkbenchSessionIdentity,
        rows: [ConnectionSnapshot],
        revision: UInt64 = 1,
        query: String = ""
    ) -> ConnectionsWorkspaceInput {
        ConnectionsWorkspaceInput(
            identity: identity,
            catalog: ConnectionsCatalogSnapshot(
                connections: rows,
                traffic: TrafficSnapshot(upload: 0, download: 0),
                structureRevision: 1,
                metricsRevision: revision
            ),
            closedConnections: [],
            closedRevision: 0,
            query: query,
            language: .english
        )
    }

    private static func rule(id: String, index: Int, payload: String) -> RuleViewState {
        RuleViewState(id: id, index: index, type: "DOMAIN", payload: payload, proxy: "DIRECT")
    }
}
