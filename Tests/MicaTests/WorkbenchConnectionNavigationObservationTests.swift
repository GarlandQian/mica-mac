import Foundation
import Observation
import Synchronization
import Testing
@testable import Mica

@MainActor
struct WorkbenchConnectionNavigationObservationTests {
    @Test func ruleCountersDoNotInvalidateConnectionNavigation() throws {
        let identity = WorkbenchSessionIdentity(controllerID: UUID(), generation: UUID())
        let model = ConnectionsWorkspaceModel()
        model.activate(identity: identity, workspace: .init(), restoredScrollAnchorID: nil)
        var rules = [
            RuleViewState(id: "one", type: "DOMAIN", payload: "example.test", proxy: "Route", hitCount: 1),
            RuleViewState(id: "two", type: "DOMAIN", payload: "other.test", proxy: "Route", hitCount: 1),
        ]
        let catalog = PolicyGroupCatalogSnapshot(mode: "Rule", groups: [
            ProxyGroupViewState(id: "Route", type: "Selector", selected: "Node", options: ["Node"]),
        ])
        model.updateNavigation(rules: rules, catalog: catalog, visibility: .followMode, identity: identity)
        let initial = model.navigationDirectory
        let changes = Mutex(0)
        withObservationTracking {
            _ = model.navigationDirectory
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        for count in 2...40 {
            rules[0].hitCount = count
            rules[1].hitCount = count * 2
            model.updateRuleNavigation(rules: rules, identity: identity)
        }

        #expect(changes.withLock { $0 } == 0)
        #expect(model.navigationDirectory == initial)
        #expect(model.navigationDirectory.policyTarget(named: "Route")?.group.selected == "Node")

        rules.swapAt(0, 1)
        model.updateRuleNavigation(rules: rules, identity: identity)
        #expect(changes.withLock { $0 } == 1)
        #expect(model.navigationDirectory.ruleTarget(type: "DOMAIN", payload: "example.test")?.sourceIndex == 1)
        #expect(model.navigationDirectory.ruleTarget(type: "DOMAIN", payload: "other.test")?.sourceIndex == 0)
    }

    @Test func ruleNavigationReplacementPreservesAmbiguityAndCurrentIdentities() {
        let identity = WorkbenchSessionIdentity(controllerID: UUID(), generation: UUID())
        let model = ConnectionsWorkspaceModel()
        model.activate(identity: identity, workspace: .init(), restoredScrollAnchorID: nil)
        var rules = [RuleViewState(id: "one", type: "DOMAIN", payload: "example.test", proxy: "DIRECT")]
        model.updateRuleNavigation(rules: rules, identity: identity)
        #expect(model.navigationDirectory.ruleTarget(type: "DOMAIN", payload: "example.test")?.reportedRuleID == "one")

        rules[0].id = "replacement"
        model.updateRuleNavigation(rules: rules, identity: identity)
        #expect(model.navigationDirectory.ruleTarget(type: "DOMAIN", payload: "example.test")?.reportedRuleID == "replacement")
        rules.append(RuleViewState(id: "duplicate", type: "DOMAIN", payload: "example.test", proxy: "REJECT"))
        model.updateRuleNavigation(rules: rules, identity: identity)
        #expect(model.navigationDirectory.ruleTarget(type: "DOMAIN", payload: "example.test") == nil)

        rules[1].payload = "different.test"
        model.updateRuleNavigation(rules: rules, identity: identity)
        #expect(model.navigationDirectory.ruleTarget(type: "DOMAIN", payload: "example.test")?.reportedRuleID == "replacement")
        #expect(model.navigationDirectory.ruleTarget(type: "DOMAIN", payload: "different.test")?.sourceIndex == 1)

        model.updateRuleNavigation(rules: [], identity: identity)
        #expect(model.navigationDirectory.ruleTarget(type: "DOMAIN", payload: "example.test") == nil)
        #expect(model.navigationDirectory.ruleTarget(type: "DOMAIN", payload: "different.test") == nil)
    }

    @Test func independentPolicyRefreshRetainsRulesAndRejectsOldSessions() {
        let identity = WorkbenchSessionIdentity(controllerID: UUID(), generation: UUID())
        let model = ConnectionsWorkspaceModel()
        model.activate(identity: identity, workspace: .init(), restoredScrollAnchorID: nil)
        let rules = [RuleViewState(id: "one", type: "DOMAIN", payload: "example.test", proxy: "Route")]
        let groups = [
            ProxyGroupViewState(id: "Route", type: "Selector", selected: "Node", options: ["Node"]),
            ProxyGroupViewState(id: "GLOBAL", type: "Selector", selected: "Route", options: ["Route"]),
        ]
        let catalog = PolicyGroupCatalogSnapshot(mode: "Rule", groups: groups)
        model.updateNavigation(rules: rules, catalog: catalog, visibility: .followMode, identity: identity)
        #expect(model.navigationDirectory.policyTarget(named: "GLOBAL") == nil)
        model.updatePolicyNavigation(catalog: catalog, visibility: .alwaysShow, identity: identity)
        #expect(model.navigationDirectory.visiblePolicyGroups.map(\.group.id) == ["Route", "GLOBAL"])
        #expect(model.navigationDirectory.ruleTarget(type: "DOMAIN", payload: "example.test")?.reportedRuleID == "one")

        let next = WorkbenchSessionIdentity(controllerID: identity.controllerID, generation: UUID())
        model.activate(identity: next, workspace: .init(), restoredScrollAnchorID: nil)
        model.updateRuleNavigation(rules: rules, identity: identity)
        model.updatePolicyNavigation(catalog: catalog, visibility: .alwaysShow, identity: identity)
        #expect(model.navigationDirectory == WorkbenchConnectionNavigationDirectory())
        model.updateNavigation(rules: rules, catalog: catalog, visibility: .followMode, identity: next)
        model.deactivate()
        model.updateRuleNavigation(rules: [], identity: next)
        model.updatePolicyNavigation(catalog: .empty, visibility: .alwaysShow, identity: next)
        #expect(model.navigationDirectory.ruleTarget(type: "DOMAIN", payload: "example.test")?.reportedRuleID == "one")
        #expect(model.navigationDirectory.visiblePolicyGroups.map(\.group.id) == ["Route"])
    }
}
