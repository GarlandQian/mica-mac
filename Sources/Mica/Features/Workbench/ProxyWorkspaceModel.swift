import Foundation
import MicaCore
import Observation

struct ProxyWorkspacePresentationInput: Equatable {
    var controllerID: RouterProfile.ID?
    var generation: UUID
    var workspace: WorkbenchDestinationWorkspace
    var query: String
    var visibility: GlobalGroupVisibility
    var healthFilter: ProxyHealthFilter
    var activity: ProxyOperationActivity
    var canClearFixedSelection: Bool
}

@MainActor
@Observable
final class ProxyWorkspaceModel {
    private(set) var catalog = PolicyGroupCatalogSnapshot.empty
    private(set) var revision = ProxyCatalogRevision.zero
    private(set) var groupProjection = ProxyGroupCatalogProjection.empty
    private(set) var activeProjection = ProxyActiveGroupProjection.empty
    private(set) var accessibilityIndex = ProxyAccessibilityIndex.empty
    private(set) var directoryAccessibilityIndex = ProxyAccessibilityIndex.empty
    private(set) var activeGroup: ProxyActiveGroupPresentation?

    @ObservationIgnored private var cache = ProxyCatalogProjectionCache()
    @ObservationIgnored private var directoryItemsByID: [String: ProxyGroupDirectoryItem] = [:]
    @ObservationIgnored private var previousInput: ProxyWorkspacePresentationInput?
    @ObservationIgnored private var hasAcceptedCatalog = false
    @ObservationIgnored private(set) var memberProjectionBuildCount = 0
    @ObservationIgnored private(set) var groupPresentationBuildCount = 0
    @ObservationIgnored private(set) var workspaceReconciliationCount = 0

    var cacheWorkCounts: ProxyCatalogProjectionWorkCounts { cache.workCounts }

    /// A deferred snapshot cannot replace a newer accepted snapshot or cross
    /// the active controller/session boundary.
    @discardableResult
    func accept(
        _ update: ProxyCatalogUpdate,
        selectedControllerID: RouterProfile.ID?,
        sessionControllerID: RouterProfile.ID?,
        generation: UUID,
        input: ProxyWorkspacePresentationInput
    ) -> WorkbenchDestinationWorkspace? {
        guard update.revision.isCurrent(
            selectedControllerID: selectedControllerID,
            sessionControllerID: sessionControllerID,
            generation: generation
        ), update.revision.isCurrent(
            controllerID: input.controllerID,
            generation: input.generation
        ) else { return nil }
        let sameSession = revision.isCurrent(
            controllerID: selectedControllerID,
            generation: generation
        )
        guard !sameSession || !hasAcceptedCatalog
                || update.revision.value > revision.value else { return nil }
        if !sameSession { reset() }
        catalog = update.catalog
        revision = update.revision
        hasAcceptedCatalog = true
        return updatePresentation(input)
    }

    @discardableResult
    func updatePresentation(
        _ input: ProxyWorkspacePresentationInput
    ) -> WorkbenchDestinationWorkspace {
        guard hasAcceptedCatalog,
              revision.isCurrent(controllerID: input.controllerID, generation: input.generation)
        else { return input.workspace }
        let catalogChanged = cache.updateCatalog(
            catalog, revision: revision, visibility: input.visibility
        )
        var next = input
        let previous = previousInput
        if catalogChanged
            || previous?.workspace.activeGroupID != input.workspace.activeGroupID
            || previous?.workspace.inspectedProxyMemberID != input.workspace.inspectedProxyMemberID {
            next.workspace = ProxyWorkspaceProjection.reconciled(
                input.workspace, groups: cache.groupIndex.arrangedGroups
            )
            workspaceReconciliationCount += 1
        }
        let groupSearchChanged = catalogChanged || previous?.query != next.query
        if groupSearchChanged {
            groupProjection = cache.groupProjection(query: next.query)
        }
        if groupSearchChanged || previous?.workspace.activeGroupID != next.workspace.activeGroupID {
            directoryAccessibilityIndex = ProxyAccessibilityIndex(
                groups: groupProjection.visibleGroups,
                directoryItems: groupProjection.visibleDirectoryItems,
                activeGroupID: next.workspace.activeGroupID,
                activeGroup: .empty
            )
        }
        if catalogChanged {
            directoryItemsByID = Dictionary(
                uniqueKeysWithValues: cache.groupIndex.directoryItems.map { ($0.id, $0) }
            )
        }

        let activeChanged = cache.updateActiveGroup(groupID: next.workspace.activeGroupID)
        let filtersChanged = previous?.healthFilter != next.healthFilter
            || previous?.workspace.proxyMemberQuery != next.workspace.proxyMemberQuery
        let membersChanged = catalogChanged || activeChanged || filtersChanged
        if membersChanged {
            activeProjection = ProxyActiveGroupProjection(
                index: cache.activeGroupIndex,
                query: next.workspace.proxyMemberQuery,
                healthFilter: next.healthFilter
            )
            memberProjectionBuildCount += 1
            let occurrence = cache.activeGroupIndex.occurrence
            accessibilityIndex = ProxyAccessibilityIndex(
                groups: occurrence.map { [$0] } ?? [],
                directoryItems: occurrence.flatMap { directoryItemsByID[$0.id] }.map { [$0] } ?? [],
                activeGroupID: next.workspace.activeGroupID,
                activeGroup: activeProjection
            )
        }
        if membersChanged
            || previous?.workspace.inspectedProxyMemberID != next.workspace.inspectedProxyMemberID
            || previous?.activity != next.activity
            || previous?.canClearFixedSelection != next.canClearFixedSelection {
            activeGroup = makeActiveGroupPresentation(next)
            groupPresentationBuildCount += 1
        }
        previousInput = next
        return next.workspace
    }

    func activeGroupIndex(for groupID: String) -> ProxyActiveGroupIndex {
        cache.activeGroupIndex.occurrence?.id == groupID ? cache.activeGroupIndex : .empty
    }

    func groupOccurrence(for groupID: String, scope: LiveCommandScope) -> ProxyGroupOccurrence? {
        guard hasAcceptedCatalog,
              revision.isCurrent(controllerID: scope.controllerID, generation: scope.generation),
              cache.groupIndex.revision == revision else { return nil }
        return cache.groupIndex.arrangedGroups.first { $0.id == groupID }
    }

    func reset() {
        catalog = .empty
        revision = .zero
        groupProjection = .empty
        activeProjection = .empty
        accessibilityIndex = .empty
        directoryAccessibilityIndex = .empty
        activeGroup = nil
        cache = ProxyCatalogProjectionCache()
        directoryItemsByID = [:]
        previousInput = nil
        hasAcceptedCatalog = false
        memberProjectionBuildCount = 0
        groupPresentationBuildCount = 0
        workspaceReconciliationCount = 0
    }

    private func makeActiveGroupPresentation(
        _ input: ProxyWorkspacePresentationInput
    ) -> ProxyActiveGroupPresentation? {
        guard let occurrence = cache.activeGroupIndex.occurrence,
              let item = directoryItemsByID[occurrence.id] else { return nil }
        return ProxyActiveGroupPresentation(
            occurrence: occurrence,
            item: item,
            members: activeProjection.members,
            filter: input.workspace.proxyMemberQuery,
            inspectedMemberID: input.workspace.inspectedProxyMemberID,
            healthSummary: item.healthSummary,
            healthFilter: input.healthFilter,
            isSwitching: input.activity.isSwitching(groupID: occurrence.group.id),
            isTesting: input.activity.isTesting(groupID: occurrence.group.id),
            isClearingFixed: input.activity.clearingFixedGroupID == occurrence.group.id,
            canClearFixed: input.canClearFixedSelection
                && occurrence.group.details?.fixed?.proxyNonBlank != nil
        )
    }
}
