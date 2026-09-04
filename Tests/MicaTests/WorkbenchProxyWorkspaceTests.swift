import Foundation
import MicaCore
import SwiftUI
import Testing
@testable import Mica

struct WorkbenchProxyWorkspaceTests {
    @Test func latencyDistributionUsesReportedOrderAndHealthBuckets() throws {
        var group = Self.group(
            id: "Latency",
            selected: "Fast",
            options: ["Fast", "Normal", "Slow", "Timeout", "Missing"]
        )
        group.delays = [
            "Fast": 40,
            "Normal": 100,
            "Slow": 300,
            "Timeout": 1_200,
        ]

        let distribution = ProxyLatencyDistribution(group: group)

        #expect(distribution.buckets.map(\.kind) == [
            .fast, .normal, .slow, .timeout, .unavailable,
        ])
        #expect(distribution.buckets.map(\.count) == [1, 1, 1, 1, 1])
        #expect(distribution.buckets.allSatisfy { $0.fraction == 0.2 })
    }

    @Test func healthSummaryClassifiesOptionalAvailabilityAndLatencyConservatively() {
        var group = Self.group(
            id: "Health",
            selected: "Fast",
            options: ["Fast", "Slow", "Timeout", "Dead", "Unknown"]
        )
        group.delays = [
            "Fast": 40,
            "Slow": 240,
            "Timeout": 1_200,
        ]
        group.optionDetails = [
            "Fast": Self.node(name: "Fast", alive: true),
            "Slow": Self.node(name: "Slow", alive: true),
            "Dead": Self.node(name: "Dead", alive: false),
        ]

        let summary = ProxyGroupHealthSummary(group: group)

        #expect(summary.status == .degraded)
        #expect(summary.memberCount == 5)
        #expect(summary.availableCount == 2)
        #expect(summary.unavailableCount == 2)
        #expect(summary.unknownCount == 1)
        #expect(summary.slowCount == 1)
    }

    @Test func healthSummarySeparatesHealthyFailedAndUnknownGroups() {
        var healthy = Self.group(
            id: "Healthy",
            selected: "Fast",
            options: ["Fast", "Alive"]
        )
        healthy.delays = ["Fast": 50]
        healthy.optionDetails = [
            "Fast": Self.node(name: "Fast", alive: true),
            "Alive": Self.node(name: "Alive", alive: true),
        ]

        var failed = Self.group(
            id: "Failed",
            selected: "Dead",
            options: ["Dead", "Timeout"]
        )
        failed.delays = ["Timeout": 1_000]
        failed.optionDetails = [
            "Dead": Self.node(name: "Dead", alive: false),
        ]

        let unknown = Self.group(
            id: "Unknown",
            selected: "No data",
            options: ["No data"]
        )

        #expect(ProxyGroupHealthSummary(group: healthy).status == .healthy)
        #expect(ProxyGroupHealthSummary(group: failed).status == .failed)
        #expect(ProxyGroupHealthSummary(group: unknown).status == .unknown)
    }

    @Test func healthFilterPreservesControllerMemberOrder() throws {
        var group = Self.group(
            id: "Filter",
            selected: "Current",
            options: ["Current", "Slow", "Timeout", "Dead", "Unknown", "Normal"]
        )
        group.delays = ["Slow": 180, "Timeout": 1_200, "Normal": 90]
        group.optionDetails = [
            "Current": Self.node(name: "Current", alive: true),
            "Slow": Self.node(name: "Slow", alive: true),
            "Dead": Self.node(name: "Dead", alive: false),
            "Normal": Self.node(name: "Normal", alive: true),
        ]
        let arranged = ProxyProjection.arrangedGroups(
            [group],
            mode: "Rule",
            visibility: .followMode
        )
        let occurrence = try #require(arranged.first)
        let index = ProxyProjection.activeGroupIndex(
            in: arranged,
            groupID: occurrence.id
        )

        #expect(
            ProxyProjection.filteredRows(index.rows, healthFilter: .all)
                .map(\.name)
                == ["Current", "Slow", "Timeout", "Dead", "Unknown", "Normal"]
        )
        #expect(
            ProxyProjection.filteredRows(index.rows, healthFilter: .degraded)
                .map(\.name) == ["Slow", "Timeout", "Dead", "Unknown"]
        )
        #expect(
            ProxyProjection.filteredRows(index.rows, healthFilter: .unavailable)
                .map(\.name) == ["Timeout", "Dead"]
        )
        #expect(
            ProxyProjection.filteredRows(index.rows, healthFilter: .slow)
                .map(\.name) == ["Slow"]
        )
        #expect(
            ProxyProjection.filteredRows(index.rows, healthFilter: .current)
                .map(\.name) == ["Current"]
        )
    }

    @Test func navigationTargetResolutionUsesStableOccurrenceAndMemberIDs() throws {
        let groups = ProxyProjection.arrangedGroups(
            [
                Self.group(id: "Duplicate", selected: "A", options: ["A", "B"]),
                Self.group(id: "Duplicate", selected: "C", options: ["C"]),
                Self.group(id: "Unique", selected: "Node", options: ["Node"]),
            ],
            mode: "Rule",
            visibility: .followMode
        )
        let unique = try #require(groups.last)
        let resolved = ProxyProjection.resolveNavigationTarget(
            groupID: unique.id,
            nodeName: "Node",
            in: groups
        )
        let firstDuplicate = try #require(groups.first)
        let ambiguous = ProxyProjection.resolveNavigationTarget(
            groupID: "Duplicate",
            nodeName: "A",
            in: groups
        )

        #expect(resolved.status == .resolved)
        #expect(resolved.occurrence?.id == unique.id)
        #expect(resolved.member?.id == "4:Node:0")
        #expect(resolved.row?.name == "Node")
        #expect(
            resolved.revealTargetID
                == ProxyProjection.revealTargetID(
                    groupID: unique.id,
                    memberID: "4:Node:0"
                )
        )
        #expect(ambiguous.status == .ambiguousGroup)
        #expect(firstDuplicate.id != groups[1].id)
    }

    @Test func catalogNavigationResolutionKeepsEmptyAndHiddenGlobalTruthful() throws {
        let catalog = PolicyGroupCatalogSnapshot(
            mode: "Rule",
            groups: [
                Self.group(
                    id: "GLOBAL",
                    selected: "Node A",
                    options: ["Node A"]
                ),
            ]
        )
        let occurrence = try #require(
            ProxyProjection.arrangedGroups(
                catalog.groups,
                mode: catalog.mode,
                visibility: .alwaysShow
            ).first
        )

        let hidden = ProxyProjection.resolveNavigationTarget(
            groupOccurrenceID: occurrence.id,
            nodeName: "Node A",
            catalog: catalog,
            visibility: .followMode
        )
        let visible = ProxyProjection.resolveNavigationTarget(
            groupOccurrenceID: occurrence.id,
            nodeName: "Node A",
            catalog: catalog,
            visibility: .alwaysShow
        )
        let empty = ProxyProjection.resolveNavigationTarget(
            groupOccurrenceID: occurrence.id,
            nodeName: "Node A",
            catalog: .empty,
            visibility: .alwaysShow
        )

        #expect(hidden.status == .hiddenGlobal)
        #expect(hidden.occurrence?.id == occurrence.id)
        #expect(visible.status == .resolved)
        #expect(empty.status == .emptyCatalog)
    }

    @Test func policyInspectionResolvesDuplicateGroupsOnlyByExactOccurrence() throws {
        let catalog = PolicyGroupCatalogSnapshot(
            mode: "Rule",
            groups: [
                Self.group(id: "Duplicate", selected: "A", options: ["A"]),
                Self.group(id: "Duplicate", selected: "B", options: ["B"]),
            ]
        )
        let occurrences = ProxyProjection.arrangedGroups(
            catalog.groups,
            mode: catalog.mode,
            visibility: .alwaysShow
        )
        let second = try #require(occurrences.last)
        let index = OverviewPolicyInspectionIndex(catalog: catalog)

        #expect(index.resolve(name: "Duplicate") == .ambiguous)
        guard case .group(let resolved) = index.resolve(
            groupOccurrenceID: second.id
        ) else {
            Issue.record("Expected the exact duplicate group occurrence")
            return
        }
        #expect(resolved.occurrenceID == second.id)
        #expect(resolved.selected == "B")
    }

    @Test func revealObstructionRepresentsEveryBlockingFilterAndDedicatedGlobalAction() {
        let blockers: WorkbenchProxyFilterObstructions = [
            .globalSearch,
            .groupFilter,
            .healthFilter,
        ]
        let filtered = WorkbenchProxyRevealObstruction.filters(
            groupOccurrenceID: "group:0",
            blockers: blockers
        )

        #expect(filtered.detailKey == "routing.reveal_blocked_multiple_filters_detail")
        #expect(filtered.actionTitleKey == "routing.clear_filters_and_locate")
        #expect(
            WorkbenchProxyRevealObstruction.hiddenGlobal.actionTitleKey
                == "routing.show_global_and_locate"
        )
    }

    @MainActor
    @Test func proxyNavigationIsSessionBoundAndNotPersisted() {
        let suiteName = "MicaTests.WorkbenchProxyNavigation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WorkbenchWorkspaceStore(
            defaults: defaults,
            persistenceKey: "workspace",
            persistenceDelay: .seconds(60)
        )
        let controllerID = UUID()
        let generation = UUID()
        let selection = WorkbenchProxyNavigationSelection(
            controllerID: controllerID,
            generation: generation,
            groupOccurrenceID: "group",
            nodeName: "node"
        )

        store.stageProxyNavigation(selection)
        #expect(
            store.workspace(controllerID: controllerID, destination: .proxies)
                .pendingProxySelection == selection
        )
        #expect(!store.hasPendingPersistence)
        #expect(
            store.consumeProxyNavigation(
                controllerID: controllerID,
                generation: UUID()
            ) == nil
        )
        #expect(
            !store.clearProxyNavigation(
                controllerID: controllerID,
                generation: UUID()
            )
        )

        store.activateSession(controllerID: controllerID, generation: generation)
        #expect(store.consumeProxyNavigation(
            controllerID: controllerID,
            generation: generation
        ) == selection)
        #expect(store.consumeProxyNavigation(
            controllerID: controllerID,
            generation: generation
        ) == nil)

        store.stageProxyNavigation(selection)
        store.activateSession(controllerID: controllerID, generation: UUID())
        #expect(
            store.workspace(controllerID: controllerID, destination: .proxies)
                .pendingProxySelection == nil
        )
        #expect(defaults.data(forKey: "workspace") == nil)
    }

    @Test func nodeDetailSeparatesKnownFieldsFromAdditionalControllerFields() {
        let detail = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Node A",
                type: "VLESS",
                alive: true,
                udp: true,
                metadata: [
                    "type": .string("VLESS"),
                    "alive": .bool(true),
                    "udp": .bool(true),
                    "dialer-proxy": .string("Relay"),
                ]
            )
        )
        let projection = ProxyMemberDetailProjection(detail: detail)

        #expect(detail.reportedMetadata.keys.sorted() == ["dialer-proxy"])
        #expect(projection.reportedFields == [
            ProxyReportedMetadataField(
                key: "dialer-proxy",
                value: "Relay"
            ),
        ])
    }

    @Test func latencyScaleUsesOnlyPositiveReportedValuesWithoutReordering() throws {
        var group = Self.group(
            id: "Latency",
            selected: "Fast",
            options: ["Fast", "Slow", "Missing", "Zero"]
        )
        group.delays = [
            "Fast": 50,
            "Slow": 200,
            "Zero": 0,
        ]
        let arranged = ProxyProjection.arrangedGroups(
            [group],
            mode: "Rule",
            visibility: .followMode
        )
        let occurrence = try #require(arranged.first)
        let index = ProxyProjection.activeGroupIndex(
            in: arranged,
            groupID: occurrence.id
        )
        let scale = ProxyLatencyScale(
            delays: [nil, -1, 0, 50, 200]
        )

        #expect(scale.maximumDelay == 200)
        #expect(scale.fraction(for: 50) == 0.25)
        #expect(scale.fraction(for: 200) == 1)
        #expect(scale.fraction(for: nil) == nil)
        #expect(scale.fraction(for: 0) == nil)
        #expect(index.rows.map(\.name) == ["Fast", "Slow", "Missing", "Zero"])
        #expect(index.rows.map(\.delay) == [50, 200, nil, nil])
        #expect(index.rows.last?.health == .unavailable)
        #expect(index.rows.map(\.latencyFraction) == [0.25, 1, nil, nil])
    }

    @Test func fullPolicyInspectorPreservesNonpositiveReportedLatency() throws {
        var group = Self.group(
            id: "Raw latency",
            selected: "Zero",
            options: ["Zero"]
        )
        group.delays = ["Zero": 0]
        let catalog = PolicyGroupCatalogSnapshot(mode: "Rule", groups: [group])
        let occurrence = try #require(
            ProxyProjection.arrangedGroups(
                catalog.groups,
                mode: catalog.mode,
                visibility: .alwaysShow
            ).first
        )
        let snapshot = try #require(
            OverviewPolicyInspectionProjection.snapshot(
                groupOccurrenceID: occurrence.id,
                nodeName: "Zero",
                policyIndex: OverviewPolicyInspectionIndex(catalog: catalog),
                language: .english
            )
        )
        let latency = try #require(
            snapshot.sections.flatMap(\.fields).first { $0.id == "latency" }
        )

        #expect(latency.value == OverviewFormat.latency(0))
        #expect(latency.tone == .neutral)
    }

    @Test func proxyRevealSourceKeepsOneScrollOwnerAndStagesExactTargets() throws {
        let root = try Self.source(named: "WorkbenchProxies.swift")
        let panels = try Self.source(named: "WorkbenchProxyGroupPanels.swift")
        let topology = try Self.source(named: "WorkbenchOverviewTopologyView.swift")
        let inspection = try Self.source(
            named: "WorkbenchOverviewPolicyInspection.swift"
        )
        let interaction = try Self.source(named: "WorkbenchProxyInteraction.swift")
        let workspace = try Self.source(named: "WorkbenchWorkspaceStore.swift")

        #expect(root.contains("ScrollViewReader"))
        #expect(
            root.contains(
                "WorkbenchProxyScrollTarget.group(reveal.groupID)"
            )
        )
        #expect(root.contains("proxy.scrollTo(reveal.targetID, anchor: .center)"))
        #expect(root.contains("lastScrolledRevealToken"))
        #expect(root.contains("groupProjection.visibleGroups.isEmpty"))
        #expect(!root.contains(".scrollPosition(id: $scrollAnchorID"))
        #expect(!panels.contains(".scrollTargetLayout()"))
        #expect(root.contains("ProxyProjection.revealTargetID("))
        #expect(topology.contains("workspaceStore.stageProxyNavigation("))
        #expect(topology.contains("groupOccurrenceID:"))
        #expect(inspection.contains("groupOccurrenceID:"))
        #expect(workspace.contains("let groupOccurrenceID: String"))
        #expect(panels.contains("\"routing.test_node \\(member.name)\""))
        #expect(panels.contains(".accessibilityLabel("))
        #expect(panels.contains(".accessibilityHint("))
        #expect(root.contains("stored.groupFilters[groupOccurrenceID] = \"\""))
        #expect(root.contains("healthFilter = .all"))
        #expect(root.contains("searchText = \"\""))
        #expect(root.contains("!groupProjection.arrangedGroups.isEmpty"))
        #expect(root.contains("workspace.pendingProxySelection"))
        #expect(interaction.contains("routing.show_global_and_locate"))

        let catalogApply = try #require(
            Self.sourceSection(
                in: root,
                startingAt: "private func applyCatalogUpdate",
                endingAt: "private func rebuildCatalogIndex"
            )
        )
        #expect(catalogApply.contains("consumePendingProxyNavigation()"))
        #expect(catalogApply.contains("resolveReveal()"))

        let consumeNavigation = try #require(
            Self.sourceSection(
                in: root,
                startingAt: "private func consumePendingProxyNavigation",
                endingAt: "private func resolveReveal"
            )
        )
        #expect(!consumeNavigation.contains("pendingNavigation == nil"))

        let acceptNavigation = try #require(
            Self.sourceSection(
                in: root,
                startingAt: "private func acceptProxyNavigation",
                endingAt: "private func resolveReveal"
            )
        )
        let revealReset = try #require(
            acceptNavigation.range(of: "reveal = nil")?.lowerBound
        )
        let pendingReplacement = try #require(
            acceptNavigation.range(of: "pendingNavigation = selection")?.lowerBound
        )
        #expect(revealReset < pendingReplacement)

        let currentSelection = try #require(
            Self.sourceSection(
                in: root,
                startingAt: "private var currentNavigationSelection",
                endingAt: "private func locateCurrentNode"
            )
        )
        #expect(!currentSelection.contains("inspectorSelection"))
        #expect(currentSelection.contains("visibility: .alwaysShow"))
    }

    @Test func proxyExpandedWorkspaceUsesOneRootLazyGridAndNarrowCatalogObserver() throws {
        let root = try Self.source(named: "WorkbenchProxies.swift")
        let panels = try Self.source(named: "WorkbenchProxyGroupPanels.swift")
        let content = try #require(
            Self.sourceSection(
                in: root,
                startingAt: "private var content:",
                endingAt: "private var noMatchingGroupsState"
            )
        )
        let visualRoot = try #require(
            Self.sourceSection(
                in: root,
                startingAt: "struct WorkbenchPolicyGroupsView",
                endingAt: "private struct ProxyPolicyCatalogObserver"
            )
        )
        let observer = try #require(
            Self.sourceSection(
                in: root,
                startingAt: "private struct ProxyPolicyCatalogObserver",
                endingAt: "private struct WorkbenchProxyRevealObstructionNotice"
            )
        )
        let sectionHeader = try #require(
            Self.sourceSection(
                in: panels,
                startingAt: "struct ProxyPolicyGroupSectionHeader",
                endingAt: "private struct ProxyLatencyDistributionView"
            )
        )
        let sessionReset = try #require(
            Self.sourceSection(
                in: root,
                startingAt: "private func resetCatalogPresentationForSessionBoundary",
                endingAt: "private func applyCatalogUpdate"
            )
        )
        let memberSelection = try #require(
            Self.sourceSection(
                in: root,
                startingAt: "private func selectMember",
                endingAt: "private func testMember"
            )
        )

        #expect(String(content).components(separatedBy: "LazyVGrid(").count == 2)
        #expect(content.contains("Section {"))
        #expect(content.contains("ProxyPolicyGroupSectionHeader("))
        #expect(content.contains("ProxyPolicyNodeTile("))
        #expect(!content.contains("LazyVStack"))
        #expect(!sectionHeader.contains("LazyVGrid"))
        #expect(!sectionHeader.contains("ProxyPolicyNodeTile("))
        #expect(sectionHeader.contains("private var groupFilter"))
        #expect(!visualRoot.contains("appModel.policyGroupCatalog"))
        #expect(observer.contains("appModel.policyGroupCatalogRevision"))
        #expect(observer.contains("let current = currentObservation"))
        #expect(observer.contains("onCatalog(appModel.policyGroupCatalog, current, true)"))
        #expect(observer.contains("onSessionBoundary(current)"))
        #expect(observer.contains(".frame(width: 0, height: 0)"))
        #expect(observer.contains(".allowsHitTesting(false)"))
        #expect(observer.contains(".accessibilityHidden(true)"))
        #expect(sessionReset.contains("retainedPendingNavigation"))
        #expect(sessionReset.contains("retainedReveal"))
        #expect(memberSelection.contains("index.recordsByID[memberID]?.row"))

        let scopeAdmission = try #require(
            memberSelection.range(of: "appModel.matchesCurrentCommandScope(scope)")
        )
        let workspaceSelection = try #require(
            memberSelection.range(of: "workspaceStore.update(")
        )
        let inspectorSelection = try #require(
            memberSelection.range(of: "workspaceStore.selectInspector(")
        )
        let mutationResolution = try #require(
            memberSelection.range(of: "ProxyProjection.currentMemberMutationTarget(")
        )
        #expect(scopeAdmission.lowerBound < workspaceSelection.lowerBound)
        #expect(workspaceSelection.lowerBound < inspectorSelection.lowerBound)
        #expect(inspectorSelection.lowerBound < mutationResolution.lowerBound)
    }

    @Test func catalogObservationClassifiesSessionBoundariesAndOwnsCurrentIntents() {
        let controllerID = UUID()
        let generation = UUID()
        let initial = ProxyCatalogObservationRequest(
            controllerID: controllerID,
            generation: generation,
            revision: 1
        )
        let nextRevision = ProxyCatalogObservationRequest(
            controllerID: controllerID,
            generation: generation,
            revision: 2
        )
        let nextGeneration = ProxyCatalogObservationRequest(
            controllerID: controllerID,
            generation: UUID(),
            revision: 2
        )
        let nextController = ProxyCatalogObservationRequest(
            controllerID: UUID(),
            generation: generation,
            revision: 2
        )
        let currentSelection = WorkbenchProxyNavigationSelection(
            controllerID: controllerID,
            generation: generation,
            groupOccurrenceID: "group:0",
            nodeName: "Node"
        )
        let currentReveal = WorkbenchProxyNavigationReveal(
            controllerID: controllerID,
            generation: generation,
            groupID: "group:0",
            memberID: "member:0",
            nodeName: "Node",
            token: UUID()
        )

        #expect(nextRevision.belongsToSameSession(as: initial))
        #expect(!nextGeneration.belongsToSameSession(as: initial))
        #expect(!nextController.belongsToSameSession(as: initial))
        #expect(nextRevision.owns(currentSelection))
        #expect(nextRevision.owns(currentReveal))
        #expect(!nextGeneration.owns(currentSelection))
        #expect(!nextGeneration.owns(currentReveal))
    }

    @Test func revealIdentityRejectsObsoleteControllerAndGeneration() {
        let controllerID = UUID()
        let generation = UUID()
        let reveal = WorkbenchProxyNavigationReveal(
            controllerID: controllerID,
            generation: generation,
            groupID: "group:0",
            memberID: "member:0",
            nodeName: "Node",
            token: UUID()
        )

        #expect(reveal.isCurrent(controllerID: controllerID, generation: generation))
        #expect(!reveal.isCurrent(controllerID: UUID(), generation: generation))
        #expect(!reveal.isCurrent(controllerID: controllerID, generation: UUID()))
    }

    @Test func activeGroupIndexBuildsOnlyTheActiveMembersAndFiltersCachedRows() throws {
        let largeMembers = (0..<798).map { "Node \($0)" }
        let indexedNode = "Node 417"
        let indexedDetail = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: indexedNode,
                type: "VLESS",
                providerName: "Provider East"
            )
        )
        let arranged = ProxyProjection.arrangedGroups(
            [
                Self.group(
                    id: "Other",
                    selected: "Other 1",
                    options: ["Other 1", "Other 2"]
                ),
                ProxyGroupViewState(
                    id: "Large",
                    type: "Selector",
                    selected: "Node 0",
                    options: largeMembers,
                    optionDetails: [indexedNode: indexedDetail]
                ),
            ],
            mode: "Rule",
            visibility: .followMode
        )
        let large = try #require(arranged.first { $0.group.id == "Large" })

        let index = ProxyProjection.activeGroupIndex(
            in: arranged,
            groupID: large.id
        )
        let filtered = ProxyActiveGroupProjection(
            index: index,
            query: "provider east"
        )

        #expect(index.occurrence?.id == large.id)
        #expect(index.records.count == 798)
        #expect(index.records.first?.row.name == "Node 0")
        #expect(index.records.last?.row.name == "Node 797")
        #expect(!index.records.contains { $0.row.name.hasPrefix("Other") })
        #expect(filtered.members.map(\.name) == [indexedNode])
        #expect(index.records.count == 798)
    }

    @Test func proxyWorkspaceKeepsIndependentFilterAndSelectionPerGroup() throws {
        let arranged = ProxyProjection.arrangedGroups(
            [
                Self.group(
                    id: "Alpha",
                    selected: "Alpha 1",
                    options: ["Alpha 1", "Alpha 2"]
                ),
                Self.group(
                    id: "Beta",
                    selected: "Beta 1",
                    options: ["Beta 1", "Beta 2"]
                ),
            ],
            mode: "Rule",
            visibility: .followMode
        )
        let alpha = try #require(arranged.first)
        let beta = try #require(arranged.last)
        let alphaSecond = try #require(
            ProxyProjection.members(in: alpha.group, query: "").last?.id
        )
        let betaSecond = try #require(
            ProxyProjection.members(in: beta.group, query: "").last?.id
        )

        var workspace = WorkbenchDestinationWorkspace()
        workspace = ProxyWorkspaceProjection.opening(
            beta.id,
            in: workspace,
            groups: arranged,
            preferredMemberID: nil
        )
        workspace = ProxyWorkspaceProjection.opening(
            alpha.id,
            in: workspace,
            groups: arranged,
            preferredMemberID: nil
        )
        workspace.groupFilters[alpha.id] = "Alpha 2"
        workspace.groupFilters[beta.id] = "Beta 2"
        workspace.selectedGroupMemberIDs[alpha.id] = alphaSecond
        workspace.selectedGroupMemberIDs[beta.id] = betaSecond

        workspace = ProxyWorkspaceProjection.closing(
            alpha.id,
            in: workspace,
            groups: arranged
        )
        workspace = ProxyWorkspaceProjection.opening(
            alpha.id,
            in: workspace,
            groups: arranged,
            preferredMemberID: nil
        )

        #expect(workspace.openGroupIDs == [alpha.id, beta.id])
        #expect(workspace.activeGroupID == alpha.id)
        #expect(workspace.groupFilters[alpha.id] == "Alpha 2")
        #expect(workspace.groupFilters[beta.id] == "Beta 2")
        #expect(workspace.selectedGroupMemberIDs[alpha.id] == alphaSecond)
        #expect(workspace.selectedGroupMemberIDs[beta.id] == betaSecond)
    }

    @Test func closingInspectorPreservesGroupStateAndDoesNotAutoReopen() throws {
        let arranged = ProxyProjection.arrangedGroups(
            [
                Self.group(
                    id: "Proxy",
                    selected: "Node A",
                    options: ["Node A", "Node B"]
                ),
            ],
            mode: "Rule",
            visibility: .followMode
        )
        let group = try #require(arranged.first)
        let selectedMemberID = try #require(
            ProxyProjection.preferredMemberID(in: group.group)
        )
        var workspace = WorkbenchDestinationWorkspace()
        workspace = ProxyWorkspaceProjection.opening(
            group.id,
            in: workspace,
            groups: arranged,
            preferredMemberID: selectedMemberID
        )
        workspace = ProxyWorkspaceProjection.closingInspector(
            for: group.id,
            in: workspace
        )
        workspace = ProxyWorkspaceProjection.opening(
            group.id,
            in: workspace,
            groups: arranged,
            preferredMemberID: nil
        )

        #expect(workspace.activeGroupID == group.id)
        #expect(workspace.selectedGroupMemberIDs[group.id] == nil)
        #expect(group.group.selected == "Node A")
    }

    @Test func reportedSmartRanksNeverReorderOrInferNodeRows() throws {
        let longRareName = String(repeating: "Rare node full name ", count: 8)
        let longMostName = String(repeating: "Most node full name ", count: 8)
        let unreportedName = "Most Used by Name Only"
        let arranged = ProxyProjection.arrangedGroups(
            [
                ProxyGroupViewState(
                    id: "Smart",
                    type: "Smart",
                    selected: longRareName,
                    options: [longRareName, unreportedName, longMostName],
                    optionUsageRanks: [
                        longRareName: .rarelyUsed,
                        longMostName: .mostUsed,
                    ]
                ),
                Self.group(id: "GLOBAL", selected: "Smart", options: ["Smart"]),
            ],
            mode: "Global",
            visibility: .followMode
        )
        let smart = try #require(arranged.first)
        let projection = ProxyProjection.activeGroup(
            in: arranged,
            groupID: smart.id,
            query: ""
        )

        #expect(arranged.map { $0.group.id } == ["Smart", "GLOBAL"])
        #expect(
            projection.members.map(\.name)
                == [longRareName, unreportedName, longMostName]
        )
        #expect(projection.members.map(\.usageRank) == [.rarelyUsed, nil, .mostUsed])
        #expect(projection.members.first?.name == longRareName)
        #expect(projection.members.last?.name == longMostName)
    }

    @Test func catalogRevisionBuildsRowsOnlyForExpandedGroups() throws {
        let groups = (0..<100).map { groupIndex in
            let groupID = groupIndex == 50 ? "GLOBAL" : "Group \(groupIndex)"
            let members = (0..<1_000).map { "Node \(groupIndex)-\($0)" }
            return Self.group(
                id: groupID,
                selected: members[0],
                options: members
            )
        }
        let catalog = PolicyGroupCatalogSnapshot(
            mode: "Global",
            groups: groups
        )
        let generation = UUID()
        let revision = ProxyCatalogRevision(
            controllerID: nil,
            generation: generation,
            value: 1
        )
        var cache = ProxyCatalogProjectionCache()

        let didUpdateCatalog = cache.updateCatalog(
            catalog,
            revision: revision,
            visibility: .followMode
        )
        #expect(didUpdateCatalog)
        #expect(cache.groupIndex.arrangedGroups.count == 100)
        #expect(cache.groupIndex.arrangedGroups.last?.group.id == "GLOBAL")
        #expect(cache.workCounts.catalogIndexBuilds == 1)
        #expect(cache.workCounts.groupRecordsBuilt == 100)
        #expect(cache.workCounts.activeGroupIndexBuilds == 0)
        #expect(cache.workCounts.memberRowsBuilt == 0)

        let workAfterCatalogBuild = cache.workCounts
        let matchingGroups = cache.groupProjection(query: "42-999")
        _ = cache.groupProjection(query: "42-998")
        #expect(matchingGroups.visibleGroups.map { $0.group.id } == ["Group 42"])
        #expect(cache.workCounts == workAfterCatalogBuild)

        let firstExpandedGroup = try #require(
            cache.groupIndex.arrangedGroups.first {
                $0.group.id == "Group 42"
            }
        )
        let secondExpandedGroup = try #require(
            cache.groupIndex.arrangedGroups.first {
                $0.group.id == "Group 7"
            }
        )
        let didUpdateExpandedGroups = cache.updateExpandedGroups(
            groupIDs: [firstExpandedGroup.id, secondExpandedGroup.id]
        )
        #expect(didUpdateExpandedGroups)
        #expect(
            cache.expandedGroupIndex(for: firstExpandedGroup.id).rows.count
                == 1_000
        )
        #expect(
            cache.expandedGroupIndex(for: secondExpandedGroup.id).rows.count
                == 1_000
        )
        #expect(cache.workCounts.activeGroupIndexBuilds == 2)
        #expect(cache.workCounts.memberRowsBuilt == 2_000)

        let workAfterExpandedBuild = cache.workCounts
        let firstExpandedIndex = cache.expandedGroupIndex(
            for: firstExpandedGroup.id
        )
        let matchingMembers = ProxyActiveGroupProjection(
            index: firstExpandedIndex,
            query: "42-999"
        )
        _ = ProxyActiveGroupProjection(
            index: firstExpandedIndex,
            query: "42-998"
        )
        #expect(matchingMembers.members.map(\.name) == ["Node 42-999"])
        #expect(cache.workCounts == workAfterExpandedBuild)
        let didReuseExpandedGroups = cache.updateExpandedGroups(
            groupIDs: [firstExpandedGroup.id, secondExpandedGroup.id]
        )
        #expect(!didReuseExpandedGroups)
        #expect(cache.workCounts == workAfterExpandedBuild)

        let lastMember = try #require(firstExpandedIndex.rows.last)
        #expect(
            ProxyProjection.memberMutationTarget(
                groupID: firstExpandedGroup.id,
                memberID: lastMember.id,
                index: firstExpandedIndex,
                actionAvailable: true,
                requiresSelectableGroup: true
            ) == ProxyMemberMutationTarget(
                groupID: "Group 42",
                memberName: "Node 42-999"
            )
        )

        let didCloseFirstGroup = cache.updateExpandedGroups(
            groupIDs: [secondExpandedGroup.id]
        )
        #expect(didCloseFirstGroup)
        #expect(
            cache.expandedGroupIndex(for: firstExpandedGroup.id).occurrence
                == nil
        )
        #expect(
            cache.expandedGroupIndex(for: secondExpandedGroup.id).rows.count
                == 1_000
        )
        #expect(cache.workCounts == workAfterExpandedBuild)

        let didReuseCatalog = cache.updateCatalog(
            catalog,
            revision: revision,
            visibility: .followMode
        )
        #expect(!didReuseCatalog)
        #expect(cache.workCounts == workAfterExpandedBuild)
    }

    @Test func catalogRevisionRequiresCurrentControllerAndGeneration() {
        let controllerID = UUID()
        let generation = UUID()
        let revision = ProxyCatalogRevision(
            controllerID: controllerID,
            generation: generation,
            value: 1
        )

        #expect(
            revision.isCurrent(
                controllerID: controllerID,
                generation: generation
            )
        )
        #expect(
            !revision.isCurrent(
                controllerID: UUID(),
                generation: generation
            )
        )
        #expect(
            !revision.isCurrent(
                controllerID: controllerID,
                generation: UUID()
            )
        )
        #expect(
            revision.isCurrent(
                selectedControllerID: controllerID,
                sessionControllerID: controllerID,
                generation: generation
            )
        )
        #expect(
            !revision.isCurrent(
                selectedControllerID: controllerID,
                sessionControllerID: UUID(),
                generation: generation
            )
        )
    }

    @Test func retainedCatalogIsMarkedStaleAndCommandsFollowSessionState() {
        let stopped = ProxySessionPresentation(
            hasRetainedCatalog: true,
            state: .stopped,
            language: .english
        )
        let stoppedDetail = MicaStrings.localizedKey(
            "live.detail_stopped",
            language: .english
        )
        #expect(!stopped.commandsEnabled)
        #expect(
            stopped.retainedDataMessage
                == MicaStrings.localized(
                    "data.stale_detail \(stoppedDetail)",
                    language: .english
                )
        )

        let disconnected = ProxySessionPresentation(
            hasRetainedCatalog: true,
            state: .idle,
            language: .english
        )
        let disconnectedDetail = MicaStrings.localizedKey(
            "connection.disconnected",
            language: .english
        )
        #expect(!disconnected.commandsEnabled)
        #expect(
            disconnected.retainedDataMessage
                == MicaStrings.localized(
                    "data.stale_detail \(disconnectedDetail)",
                    language: .english
                )
        )

        let reconnecting = ProxySessionPresentation(
            hasRetainedCatalog: true,
            state: .staleReconnecting("Connection lost"),
            language: .english
        )
        #expect(!reconnecting.commandsEnabled)
        #expect(
            reconnecting.retainedDataMessage
                == MicaStrings.localized(
                    "data.stale_detail \("Connection lost")",
                    language: .english
                )
        )

        let live = ProxySessionPresentation(
            hasRetainedCatalog: true,
            state: .live,
            language: .english
        )
        #expect(live.commandsEnabled)
        #expect(live.retainedDataMessage == nil)

        let noRetainedData = ProxySessionPresentation(
            hasRetainedCatalog: false,
            state: .stopped,
            language: .english
        )
        #expect(!noRetainedData.commandsEnabled)
        #expect(noRetainedData.retainedDataMessage == nil)
    }

    @Test func memberMutationRequiresTheCurrentControllerGeneration() throws {
        let controllerID = UUID()
        let generation = UUID()
        let arranged = ProxyProjection.arrangedGroups(
            [
                Self.group(
                    id: "Proxy",
                    selected: "Node A",
                    options: ["Node A", "Node B"]
                ),
            ],
            mode: "Rule",
            visibility: .followMode
        )
        let group = try #require(arranged.first)
        let index = ProxyProjection.activeGroupIndex(
            in: arranged,
            groupID: group.id,
            revision: ProxyCatalogRevision(
                controllerID: controllerID,
                generation: generation,
                value: 1
            )
        )
        let memberID = try #require(index.rows.last?.id)

        #expect(
            ProxyProjection.currentMemberMutationTarget(
                groupID: group.id,
                memberID: memberID,
                index: index,
                selectedControllerID: controllerID,
                sessionControllerID: controllerID,
                generation: generation,
                actionAvailable: true,
                requiresSelectableGroup: true
            ) == ProxyMemberMutationTarget(
                groupID: "Proxy",
                memberName: "Node B"
            )
        )
        #expect(
            ProxyProjection.currentMemberMutationTarget(
                groupID: group.id,
                memberID: memberID,
                index: index,
                selectedControllerID: UUID(),
                sessionControllerID: controllerID,
                generation: generation,
                actionAvailable: true,
                requiresSelectableGroup: true
            ) == nil
        )
        #expect(
            ProxyProjection.currentMemberMutationTarget(
                groupID: group.id,
                memberID: memberID,
                index: index,
                selectedControllerID: controllerID,
                sessionControllerID: controllerID,
                generation: UUID(),
                actionAvailable: true,
                requiresSelectableGroup: true
            ) == nil
        )
    }

    @Test func workspaceReconciliationDoesNotBuildRowsForEveryStoredGroup() {
        let groups = ProxyProjection.arrangedGroups(
            (0..<100).map { groupIndex in
                Self.group(
                    id: "Group \(groupIndex)",
                    selected: "Node \(groupIndex)-0",
                    options: (0..<1_000).map { "Node \(groupIndex)-\($0)" }
                )
            },
            mode: "Rule",
            visibility: .followMode
        )
        var workspace = WorkbenchDestinationWorkspace()
        workspace.openGroupIDs = groups.map(\.id)
        workspace.activeGroupID = groups[42].id
        workspace.selectedGroupMemberIDs = Dictionary(
            uniqueKeysWithValues: groups.compactMap { occurrence in
                ProxyProjection.preferredMemberID(in: occurrence.group).map {
                    (occurrence.id, $0)
                }
            }
        )

        let result = ProxyWorkspaceProjection.reconciliation(
            workspace,
            groups: groups
        )

        #expect(result.workspace.openGroupIDs == groups.map(\.id))
        #expect(result.workspace.selectedGroupMemberIDs.count == 100)
        #expect(result.inspectedMemberCount == 100)
    }

    @Test func proxyAccessibilityIndexKeepsEveryPageGloballyBounded() {
        for count in [0, 1, 32, 33, 2_000] {
            let projection = ProxyGroupCatalogProjection(
                catalog: PolicyGroupCatalogSnapshot(
                    mode: "Rule",
                    groups: (0..<count).map { index in
                        Self.group(
                            id: "Group \(index)",
                            selected: "Node \(index)",
                            options: ["Node \(index)"]
                        )
                    }
                ),
                visibility: .alwaysShow,
                query: ""
            )
            let accessibilityIndex = ProxyAccessibilityIndex(
                groups: projection.visibleGroups,
                directoryItems: projection.visibleDirectoryItems,
                openGroupIDs: [],
                expandedGroups: [:]
            )
            var lowerBound = 0
            var traversedIDs: [String] = []

            while true {
                let window = WorkbenchAccessibilityWindow.resolve(
                    totalCount: accessibilityIndex.totalCount,
                    preferredLowerBound: lowerBound
                )
                let elements = accessibilityIndex.elements(in: window.range)
                #expect(elements.count <= WorkbenchAccessibilityWindow.capacity)
                traversedIDs.append(contentsOf: elements.map(\.id))
                guard let nextLowerBound = window.nextLowerBound else { break }
                lowerBound = nextLowerBound
            }

            #expect(accessibilityIndex.totalCount == count)
            #expect(traversedIDs == accessibilityIndex.orderedIDs)
            #expect(Set(traversedIDs).count == count)
        }
    }

    @Test func proxyAccessibilityIndexFlattensExpandedMembersIntoOneGlobalWindow() throws {
        let projection = ProxyGroupCatalogProjection(
            catalog: PolicyGroupCatalogSnapshot(
                mode: "Rule",
                groups: (0..<2).map { groupIndex in
                    Self.group(
                        id: "Group \(groupIndex)",
                        selected: "Node \(groupIndex)-0",
                        options: (0..<80).map { "Node \(groupIndex)-\($0)" }
                    )
                }
            ),
            visibility: .alwaysShow,
            query: ""
        )
        let expandedGroups = Dictionary(
            uniqueKeysWithValues: projection.visibleGroups.map { occurrence in
                let index = ProxyProjection.activeGroupIndex(
                    in: projection.arrangedGroups,
                    groupID: occurrence.id
                )
                return (
                    occurrence.id,
                    ProxyActiveGroupProjection(index: index, query: "")
                )
            }
        )
        let openGroupIDs = projection.visibleGroups.map(\.id)
        let accessibilityIndex = ProxyAccessibilityIndex(
            groups: projection.visibleGroups,
            directoryItems: projection.visibleDirectoryItems,
            openGroupIDs: openGroupIDs,
            expandedGroups: expandedGroups
        )

        #expect(accessibilityIndex.totalCount == 162)
        #expect(
            accessibilityIndex.orderedIDs.first
                == ProxyAccessibilityIndex.groupElementID(openGroupIDs[0])
        )
        #expect(
            accessibilityIndex.orderedIDs[81]
                == ProxyAccessibilityIndex.groupElementID(openGroupIDs[1])
        )

        var lowerBound = 0
        var traversedIDs: [String] = []
        while true {
            let window = WorkbenchAccessibilityWindow.resolve(
                totalCount: accessibilityIndex.totalCount,
                preferredLowerBound: lowerBound
            )
            let page = accessibilityIndex.elements(in: window.range)
            #expect(page.count <= WorkbenchAccessibilityWindow.capacity)
            traversedIDs.append(contentsOf: page.map(\.id))
            guard let nextLowerBound = window.nextLowerBound else { break }
            lowerBound = nextLowerBound
        }

        #expect(traversedIDs == accessibilityIndex.orderedIDs)
        #expect(Set(traversedIDs).count == accessibilityIndex.totalCount)
        #expect(try #require(accessibilityIndex.element(at: 0)).id == traversedIDs[0])
        #expect(try #require(accessibilityIndex.element(at: 161)).id == traversedIDs[161])
    }

    @Test func proxyAccessibilityIndexRevealsSelectionAndClampsAfterCollapse() throws {
        let projection = ProxyGroupCatalogProjection(
            catalog: PolicyGroupCatalogSnapshot(
                mode: "Rule",
                groups: [
                    Self.group(
                        id: "Large",
                        selected: "Node 0",
                        options: (0..<70).map { "Node \($0)" }
                    ),
                ]
            ),
            visibility: .alwaysShow,
            query: ""
        )
        let group = try #require(projection.visibleGroups.first)
        let activeIndex = ProxyProjection.activeGroupIndex(
            in: projection.arrangedGroups,
            groupID: group.id
        )
        let expanded = ProxyActiveGroupProjection(index: activeIndex, query: "")
        let selectedMemberID = try #require(expanded.members.last?.id)
        let accessibilityIndex = ProxyAccessibilityIndex(
            groups: projection.visibleGroups,
            directoryItems: projection.visibleDirectoryItems,
            openGroupIDs: [group.id],
            expandedGroups: [group.id: expanded]
        )
        let selectedElementID = try #require(
            accessibilityIndex.selectedElementID(
                activeGroupID: group.id,
                selectedMemberID: selectedMemberID
            )
        )
        let selectedIndex = try #require(
            accessibilityIndex.index(of: selectedElementID)
        )
        let selectedWindow = WorkbenchAccessibilityWindow.resolve(
            totalCount: accessibilityIndex.totalCount,
            revealing: selectedIndex
        )

        #expect(selectedIndex == 70)
        #expect(selectedWindow.range.contains(selectedIndex))
        #expect(selectedWindow.range.count <= WorkbenchAccessibilityWindow.capacity)

        let collapsed = ProxyAccessibilityIndex(
            groups: projection.visibleGroups,
            directoryItems: projection.visibleDirectoryItems,
            openGroupIDs: [],
            expandedGroups: [group.id: expanded]
        )
        let clampedWindow = WorkbenchAccessibilityWindow.resolve(
            totalCount: collapsed.totalCount,
            preferredLowerBound: selectedWindow.lowerBound
        )

        #expect(collapsed.totalCount == 1)
        #expect(clampedWindow.range == 0..<1)
        #expect(
            collapsed.selectedElementID(
                activeGroupID: group.id,
                selectedMemberID: selectedMemberID
            ) == ProxyAccessibilityIndex.groupElementID(group.id)
        )
    }

    @Test func catalogUpdateClassifierDefersOnlyDisplayChanges() {
        let base = PolicyGroupCatalogSnapshot(
            mode: "Rule",
            groups: [
                Self.group(
                    id: "Proxy",
                    selected: "Node A",
                    options: ["Node A", "Node B"]
                ),
            ]
        )
        var latencyOnly = base
        latencyOnly.groups[0].delays["Node A"] = 42
        var selectedNodeChanged = latencyOnly
        selectedNodeChanged.groups[0].selected = "Node B"
        var membershipChanged = latencyOnly
        membershipChanged.groups[0].options.append("Node C")

        #expect(
            ProxyCatalogUpdateClassifier.priority(
                previous: base,
                next: latencyOnly
            ) == .deferrable
        )
        #expect(
            ProxyCatalogUpdateClassifier.priority(
                previous: latencyOnly,
                next: selectedNodeChanged
            ) == .immediate
        )
        #expect(
            ProxyCatalogUpdateClassifier.priority(
                previous: latencyOnly,
                next: membershipChanged
            ) == .immediate
        )
    }

    @Test func interactionSchedulerKeepsLatestScrollUpdateUntilIdle() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let baseCatalog = PolicyGroupCatalogSnapshot(
            mode: "Rule",
            groups: [Self.group(id: "Proxy", selected: "Node A")]
        )
        let first = ProxyCatalogUpdate(
            revision: ProxyCatalogRevision(
                controllerID: nil,
                generation: nil,
                value: 1
            ),
            catalog: baseCatalog
        )
        var secondCatalog = baseCatalog
        secondCatalog.groups[0].delays["Node A"] = 42
        let second = ProxyCatalogUpdate(
            revision: ProxyCatalogRevision(
                controllerID: nil,
                generation: nil,
                value: 2
            ),
            catalog: secondCatalog
        )
        var scheduler = ProxyCatalogPresentationScheduler()

        scheduler.beginScrolling(in: .nodes, at: start)
        let deferredFirst = scheduler.deferIfInteracting(first, at: start)
        #expect(deferredFirst)
        let deadline = try #require(scheduler.pendingDeadline)
        #expect(
            deadline
                == start.addingTimeInterval(
                    ProxyCatalogPresentationScheduler.maximumDeferral
                )
        )

        let deferredSecond = scheduler.deferIfInteracting(
            second,
            at: start.addingTimeInterval(0.05)
        )
        #expect(deferredSecond)
        #expect(scheduler.pendingDeadline == deadline)
        #expect(
            scheduler.takePendingUpdateIfDue(
                at: deadline.addingTimeInterval(-0.001)
            ) == nil
        )
        #expect(
            scheduler.takePendingUpdateIfDue(at: deadline) == nil
        )
        #expect(scheduler.pendingUpdate == second)

        scheduler.endScrolling(
            in: .nodes,
            at: deadline.addingTimeInterval(0.01)
        )
        #expect(
            scheduler.takePendingUpdateIfIdle(
                at: deadline.addingTimeInterval(0.01)
            ) == second
        )
        #expect(scheduler.pendingUpdate == nil)
    }

    @Test func interactionSchedulerStillBoundsTransientDeferral() throws {
        let start = Date(timeIntervalSince1970: 2_000)
        let update = ProxyCatalogUpdate(
            revision: ProxyCatalogRevision(
                controllerID: nil,
                generation: nil,
                value: 1
            ),
            catalog: PolicyGroupCatalogSnapshot(
                mode: "Rule",
                groups: [Self.group(id: "Proxy", selected: "Node A")]
            )
        )
        var scheduler = ProxyCatalogPresentationScheduler()

        scheduler.beginTransientInteraction(at: start)
        let deferred = scheduler.deferIfInteracting(update, at: start)
        #expect(deferred)
        let deadline = try #require(scheduler.pendingDeadline)
        #expect(
            scheduler.takePendingUpdateIfDue(
                at: deadline.addingTimeInterval(-0.001)
            ) == nil
        )
        #expect(scheduler.takePendingUpdateIfDue(at: deadline) == update)
    }

    @Test func criticalUserOperationWindowBypassesInteractionDeferral() {
        let start = Date(timeIntervalSince1970: 2_000)
        let update = ProxyCatalogUpdate(
            revision: ProxyCatalogRevision(
                controllerID: nil,
                generation: nil,
                value: 1
            ),
            catalog: PolicyGroupCatalogSnapshot(
                mode: "Rule",
                groups: [Self.group(id: "Proxy", selected: "Node A")]
            )
        )
        var scheduler = ProxyCatalogPresentationScheduler()

        scheduler.beginScrolling(in: .directory, at: start)
        scheduler.beginCriticalWindow(at: start)

        let deferred = scheduler.deferIfInteracting(update, at: start)
        #expect(!deferred)
        #expect(scheduler.pendingUpdate == nil)
        #expect(scheduler.pendingDeadline == nil)
    }

    @MainActor
    @Test func localScrollTrackerSignalsTheRootOnlyForARealDeferredCommit() throws {
        let start = Date(timeIntervalSince1970: 3_000)
        let firstUpdate = ProxyCatalogUpdate(
            revision: ProxyCatalogRevision(
                controllerID: nil,
                generation: nil,
                value: 1
            ),
            catalog: PolicyGroupCatalogSnapshot(
                mode: "Rule",
                groups: [Self.group(id: "Proxy", selected: "Node A")]
            )
        )
        let secondUpdate = ProxyCatalogUpdate(
            revision: ProxyCatalogRevision(
                controllerID: nil,
                generation: nil,
                value: 2
            ),
            catalog: PolicyGroupCatalogSnapshot(
                mode: "Rule",
                groups: [Self.group(id: "Proxy", selected: "Node B")]
            )
        )
        let coordinator = ProxyCatalogPresentationCoordinator()
        let tracker = ProxyScrollInteractionTracker()

        tracker.update(
            .tracking,
            in: .nodes,
            coordinator: coordinator,
            at: start
        )
        tracker.update(
            .interacting,
            in: .nodes,
            coordinator: coordinator,
            at: start.addingTimeInterval(0.01)
        )

        #expect(tracker.isScrolling)
        #expect(coordinator.commitRevision == 0)
        #expect(
            coordinator.deferIfInteracting(
                firstUpdate,
                at: start.addingTimeInterval(0.02)
            )
        )
        #expect(coordinator.commitRevision == 0)

        tracker.update(
            .idle,
            in: .nodes,
            coordinator: coordinator,
            at: start.addingTimeInterval(0.03)
        )

        #expect(!tracker.isScrolling)
        #expect(coordinator.commitRevision == 1)

        tracker.update(
            .tracking,
            in: .nodes,
            coordinator: coordinator,
            at: start.addingTimeInterval(0.04)
        )
        #expect(
            coordinator.deferIfInteracting(
                secondUpdate,
                at: start.addingTimeInterval(0.05)
            )
        )
        #expect(try #require(coordinator.takeReadyUpdate()) == firstUpdate)

        tracker.update(
            .idle,
            in: .nodes,
            coordinator: coordinator,
            at: start.addingTimeInterval(0.06)
        )

        #expect(coordinator.commitRevision == 2)
        #expect(try #require(coordinator.takeReadyUpdate()) == secondUpdate)

        tracker.update(
            .idle,
            in: .nodes,
            coordinator: coordinator,
            at: start.addingTimeInterval(0.07)
        )
        #expect(coordinator.commitRevision == 2)
    }

    private static func group(
        id: String,
        selected: String,
        options: [String] = ["Node A"]
    ) -> ProxyGroupViewState {
        ProxyGroupViewState(
            id: id,
            type: "Selector",
            selected: selected,
            options: options
        )
    }

    private static func node(name: String, alive: Bool) -> ProxyNodeViewState {
        ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: name,
                type: "HTTP",
                alive: alive
            )
        )
    }

    private static func source(named fileName: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("Sources/Mica/Features/Workbench")
            .appendingPathComponent(fileName)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func sourceSection(
        in source: String,
        startingAt start: String,
        endingAt end: String
    ) -> Substring? {
        guard let startRange = source.range(of: start),
              let endRange = source.range(
                  of: end,
                  range: startRange.upperBound..<source.endIndex
              ) else {
            return nil
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
}
