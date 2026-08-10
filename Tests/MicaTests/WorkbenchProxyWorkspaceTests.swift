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
        #expect(index.rows.map(\.latencyFraction) == [0.25, 1, nil, nil])
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
}
