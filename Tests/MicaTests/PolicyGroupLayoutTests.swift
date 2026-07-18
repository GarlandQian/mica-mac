import Testing
@testable import Mica

struct PolicyGroupLayoutTests {
    @Test func fixedColumnsUseVisibleIndexParityAndKeepSemanticOrder() {
        let assignment = PolicyGroupColumnAssignment(["A", "B", "C", "D", "E"])

        #expect(assignment.leadingColumn == ["A", "C", "E"])
        #expect(assignment.trailingColumn == ["B", "D"])
        #expect(assignment.semanticOrder == ["A", "B", "C", "D", "E"])
        #expect(assignment.rowMajorOrder == ["A", "B", "C", "D", "E"])
        #expect(assignment.accessibilitySortPriority(forSemanticIndex: 0) == 5)
        #expect(assignment.accessibilitySortPriority(forSemanticIndex: 4) == 1)
        #expect(assignment.accessibilitySortPriority(forSemanticIndex: 5) == 0)
    }

    @Test func narrowLayoutUsesTheFlatControllerOrder() {
        let assignment = PolicyGroupColumnAssignment(["Third", "First", "Second"])

        #expect(assignment.semanticOrder == ["Third", "First", "Second"])
        #expect(assignment.rowMajorOrder == assignment.semanticOrder)
    }

    @Test func globalIsStablePartitionedLastThenTreatedAsAnOrdinaryCard() {
        let groups = [
            Self.group(id: "A"),
            Self.group(id: "GLOBAL"),
            Self.group(id: "B"),
        ]
        let arranged = PolicyGroupPresentation.arrangedGroups(
            groups,
            mode: "Global",
            visibility: .followMode
        )
        let assignment = PolicyGroupColumnAssignment(arranged.map(\.id))

        #expect(arranged.map(\.id) == ["A", "B", "GLOBAL"])
        #expect(assignment.leadingColumn == ["A", "GLOBAL"])
        #expect(assignment.trailingColumn == ["B"])
        #expect(assignment.rowMajorOrder == ["A", "B", "GLOBAL"])
    }

    @Test func searchFiltersFirstThenCompactsTheVisibleParityColumns() {
        let groups = [
            Self.group(id: "A"),
            Self.group(id: "B", selected: "match"),
            Self.group(id: "C"),
            Self.group(id: "D", selected: "match"),
            Self.group(id: "E", selected: "match"),
            Self.group(id: "F"),
        ]

        let filtered = PolicyGroupPresentation.filteredGroups(groups, matching: "match")
        let filteredAssignment = PolicyGroupColumnAssignment(filtered.map(\.id))
        let restoredAssignment = PolicyGroupColumnAssignment(groups.map(\.id))

        #expect(filtered.map(\.id) == ["B", "D", "E"])
        #expect(filteredAssignment.leadingColumn == ["B", "E"])
        #expect(filteredAssignment.trailingColumn == ["D"])
        #expect(filteredAssignment.rowMajorOrder == ["B", "D", "E"])
        #expect(restoredAssignment.leadingColumn == ["A", "C", "E"])
        #expect(restoredAssignment.trailingColumn == ["B", "D", "F"])
    }

    @Test func ordinaryRefreshInputsAndExpansionDoNotRebalanceColumns() {
        let orderedIDs = ["C", "A", "D", "B", "GLOBAL"]
        let collapsed = PolicyGroupColumnAssignment(orderedIDs)
        let expanded = PolicyGroupColumnAssignment(orderedIDs)

        #expect(collapsed.leadingColumn == ["C", "D", "GLOBAL"])
        #expect(collapsed.trailingColumn == ["A", "B"])
        #expect(expanded.leadingColumn == collapsed.leadingColumn)
        #expect(expanded.trailingColumn == collapsed.trailingColumn)
    }

    @Test func memberFilteringPrecedesEachGroupsIndependentPaginationWindow() {
        var state = PolicyGroupRuntimeState()
        let groupAOptions = (0..<120).map { "alpha-\($0)" }
        let groupBOptions = (0..<120).map { "beta-\($0)" }

        state.ensureController("controller-A")
        state.showMoreMembers(groupID: "group-A", totalCount: groupAOptions.count, controllerID: "controller-A")

        let filteredA = PolicyGroupPresentation.filteredOptions(groupAOptions, matching: "alpha")
        let filteredB = PolicyGroupPresentation.filteredOptions(groupBOptions, matching: "beta")

        #expect(state.visibleOptions(filteredA, groupID: "group-A", controllerID: "controller-A").count == 96)
        #expect(state.visibleOptions(filteredB, groupID: "group-B", controllerID: "controller-A").count == 48)
        #expect(state.hasMoreOptions(filteredA, groupID: "group-A", controllerID: "controller-A"))
        #expect(state.hasMoreOptions(filteredB, groupID: "group-B", controllerID: "controller-A"))
    }

    @Test func expansionFiltersAndPaginationRemainIndependentByGroup() {
        var state = PolicyGroupRuntimeState()
        state.ensureController("controller-A")

        for groupID in ["A", "B", "C"] {
            state.setExpanded(true, groupID: groupID, controllerID: "controller-A")
        }
        state.setFilterText("alpha", groupID: "A", controllerID: "controller-A")
        state.setFilterText("beta", groupID: "B", controllerID: "controller-A")
        state.showMoreMembers(groupID: "A", totalCount: 144, controllerID: "controller-A")

        let options = (0..<144).map { "node-\($0)" }
        #expect(state.expandedGroupIDs(for: "controller-A") == ["A", "B", "C"])
        #expect(state.filterText(groupID: "A", controllerID: "controller-A") == "alpha")
        #expect(state.filterText(groupID: "B", controllerID: "controller-A") == "beta")
        #expect(state.visibleOptions(options, groupID: "A", controllerID: "controller-A").count == 96)
        #expect(state.visibleOptions(options, groupID: "B", controllerID: "controller-A").count == 48)

        state.setExpanded(false, groupID: "B", controllerID: "controller-A")

        #expect(state.expandedGroupIDs(for: "controller-A") == ["A", "C"])
        #expect(state.filterText(groupID: "A", controllerID: "controller-A") == "alpha")
        #expect(state.filterText(groupID: "B", controllerID: "controller-A").isEmpty)
        #expect(state.visibleOptions(options, groupID: "A", controllerID: "controller-A").count == 96)
    }

    @Test func controllerStateAndSnapshotPruningDoNotLeakAcrossGroups() {
        var state = PolicyGroupRuntimeState()
        state.ensureController("controller-A")
        state.ensureController("controller-B")
        state.setExpanded(true, groupID: "G1", controllerID: "controller-A")
        state.setExpanded(true, groupID: "G2", controllerID: "controller-A")
        state.setExpanded(true, groupID: "G3", controllerID: "controller-B")
        state.setFilterText("keep", groupID: "G1", controllerID: "controller-A")
        state.setFilterText("remove", groupID: "G2", controllerID: "controller-A")

        state.pruneGroups(
            controllerID: "controller-A",
            keeping: ["G1"]
        )

        #expect(state.expandedGroupIDs(for: "controller-A") == ["G1"])
        #expect(state.filterText(groupID: "G1", controllerID: "controller-A") == "keep")
        #expect(state.filterText(groupID: "G2", controllerID: "controller-A").isEmpty)
        #expect(state.expandedGroupIDs(for: "controller-B") == ["G3"])
    }

    @Test func archiveRestoresOnlyControllerScopedExpansionState() {
        var archive = PolicyGroupExpansionArchive()
        archive.setExpandedGroupIDs(["G1", "G2"], for: "controller-A")
        archive.setExpandedGroupIDs(["G3"], for: "controller-B")

        let restoredArchive = PolicyGroupExpansionArchive(rawValue: archive.rawValue)
        var freshRuntime = PolicyGroupRuntimeState()
        freshRuntime.ensureController(
            "controller-A",
            restoredExpandedGroupIDs: restoredArchive.expandedGroupIDs(for: "controller-A")
        )
        freshRuntime.ensureController(
            "controller-B",
            restoredExpandedGroupIDs: restoredArchive.expandedGroupIDs(for: "controller-B")
        )

        let options = (0..<96).map { "node-\($0)" }
        #expect(freshRuntime.expandedGroupIDs(for: "controller-A") == ["G1", "G2"])
        #expect(freshRuntime.expandedGroupIDs(for: "controller-B") == ["G3"])
        #expect(freshRuntime.filterText(groupID: "G1", controllerID: "controller-A").isEmpty)
        #expect(freshRuntime.visibleOptions(options, groupID: "G1", controllerID: "controller-A").count == 48)
    }

    @Test func collapsingOneGroupClearsOnlyItsFilterAndKeepsItsMemberWindow() {
        var state = PolicyGroupRuntimeState()
        let options = (0..<144).map { "node-\($0)" }
        state.ensureController("controller-A")
        state.setExpanded(true, groupID: "A", controllerID: "controller-A")
        state.setExpanded(true, groupID: "B", controllerID: "controller-A")
        state.setFilterText("alpha", groupID: "A", controllerID: "controller-A")
        state.setFilterText("beta", groupID: "B", controllerID: "controller-A")
        state.showMoreMembers(groupID: "A", totalCount: options.count, controllerID: "controller-A")

        state.setExpanded(false, groupID: "A", controllerID: "controller-A")
        state.setExpanded(true, groupID: "A", controllerID: "controller-A")

        #expect(state.filterText(groupID: "A", controllerID: "controller-A").isEmpty)
        #expect(state.filterText(groupID: "B", controllerID: "controller-A") == "beta")
        #expect(state.visibleOptions(options, groupID: "A", controllerID: "controller-A").count == 96)
        #expect(state.visibleOptions(options, groupID: "B", controllerID: "controller-A").count == 48)
    }

    @Test func removingAControllerClearsOnlyItsPersistedExpansionSet() {
        var archive = PolicyGroupExpansionArchive()
        archive.setExpandedGroupIDs(["G1", "G2"], for: "controller-A")
        archive.setExpandedGroupIDs(["G3"], for: "controller-B")

        archive.removeController("controller-A")
        let restored = PolicyGroupExpansionArchive(rawValue: archive.rawValue)

        #expect(restored.expandedGroupIDs(for: "controller-A").isEmpty)
        #expect(restored.expandedGroupIDs(for: "controller-B") == ["G3"])
    }

    private static func group(
        id: String,
        selected: String = "node"
    ) -> ProxyGroupViewState {
        ProxyGroupViewState(
            id: id,
            type: "Selector",
            selected: selected,
            options: [selected]
        )
    }
}
