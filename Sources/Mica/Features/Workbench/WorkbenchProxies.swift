import Foundation
import MicaCore
import SwiftUI

struct WorkbenchPolicyGroupsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @EnvironmentObject private var preferences: AppPreferencesStore
    @Environment(\.micaAppLanguage) private var language

    @Binding var searchText: String

    @State private var projectionCache = ProxyCatalogProjectionCache()
    @State private var groupProjection = ProxyGroupCatalogProjection.empty
    @State private var expandedProjections: [String: ProxyActiveGroupProjection] = [:]
    @State private var acceptedCatalog = PolicyGroupCatalogSnapshot.empty
    @State private var acceptedCatalogRevision = ProxyCatalogRevision.zero
    @State private var catalogRevisionSequence: UInt64 = 0
    @State private var presentationCoordinator = ProxyCatalogPresentationCoordinator()
    @State private var scrollInteractionTracker = ProxyScrollInteractionTracker()

    var body: some View {
        WorkbenchPageScaffold {
            VStack(spacing: 0) {
                WorkbenchCommandBar {
                    WorkbenchCommandSummary(
                        symbolName: "point.3.connected.trianglepath.dotted",
                        titleKey: "routing.group_catalog",
                        value: groupProjection.visibleGroups.count.formatted(),
                        detail: groupVisibilitySummary
                    )
                } controls: {
                    WorkbenchStatusBadge(
                        text: modeBadgeText,
                        tint: MicaStyle.signalCyan
                    )
                }

                if let staleMessage {
                    WorkbenchStaleNotice(message: staleMessage)
                }
            }
        } content: {
            content
        }
        .onAppear {
            receiveCatalog(appModel.policyGroupCatalog, forceImmediate: true)
        }
        .onDisappear {
            presentationCoordinator.reset()
        }
        .onChange(of: appModel.selectedRouterID) { _, _ in
            resetCatalogPresentationForSessionBoundary()
        }
        .onChange(of: appModel.controllerSessionPresentation.generation) { _, _ in
            resetCatalogPresentationForSessionBoundary()
        }
        .onChange(of: appModel.policyGroupCatalog) { _, catalog in
            receiveCatalog(catalog)
        }
        .onChange(of: preferences.globalGroupVisibility) { _, _ in
            rebuildCatalogIndex()
        }
        .onChange(of: searchText) { _, _ in
            rebuildVisibleGroupProjection()
        }
        .onChange(of: workspace.openGroupIDs) { _, _ in
            rebuildExpandedGroupIndexes()
        }
        .onChange(of: workspace.groupFilters) { _, _ in
            rebuildExpandedProjections()
        }
        .onChange(of: proxyOperationActivity) { oldActivity, newActivity in
            guard oldActivity != newActivity,
                  oldActivity.isActive || newActivity.isActive else { return }
            prioritizeUserOperationResult()
        }
        .onChange(of: presentationCoordinator.commitRevision) { _, _ in
            guard let update = presentationCoordinator.takeReadyUpdate() else {
                return
            }
            applyCatalogUpdate(update, supersedingDeferredUpdates: false)
        }
    }

    @ViewBuilder
    private var content: some View {
        if groupProjection.arrangedGroups.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: MicaSpacing.section) {
                    ForEach(groupPresentations) { presentation in
                        ProxyPolicyGroupPanel(
                            presentation: presentation,
                            scrollInteractionTracker: scrollInteractionTracker,
                            commandsEnabled: liveCommandsAvailable,
                            canSelect: canSelectMember,
                            canTestGroup: canTestGroup,
                            canTestNode: canTestNode,
                            measuringNode: appModel.measuringDelayNode,
                            onToggle: { toggleGroup(presentation.id) },
                            onFilterChange: {
                                setGroupFilter($0, for: presentation.id)
                            },
                            onSelectMember: {
                                selectMember($0, in: presentation.id)
                            },
                            onTestMember: {
                                testMember($0, in: presentation.id)
                            },
                            onTestGroup: {
                                testGroup(presentation.id)
                            },
                            onClearFixed: {
                                clearFixedSelection(in: presentation.id)
                            },
                            onCloseInspector: {
                                closeMemberInspector(in: presentation.id)
                            }
                        )
                    }
                }
                .padding(MicaSpacing.section)
                .frame(maxWidth: 1_320, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.automatic)
            .background(MicaDesignTokens.contentFill)
            .proxyScrollInteraction(
                in: .nodes,
                coordinator: presentationCoordinator,
                tracker: scrollInteractionTracker
            )
        }
    }

    private var emptyState: some View {
        if appModel.selectedRouter == nil {
            return WorkbenchStateView(
                kind: .noController,
                titleKey: "routing.groups_no_controller",
                detailKey: "routing.groups_no_controller_detail"
            )
        }

        switch appModel.controllerSessionPresentation.state {
        case .connecting:
            return WorkbenchStateView(
                kind: .loading,
                titleKey: "routing.groups_loading",
                detailKey: "routing.groups_loading_detail"
            )
        case .staleReconnecting(let message):
            return WorkbenchStateView(
                kind: .failed,
                titleKey: "routing.groups_unavailable",
                detailKey: "routing.groups_unavailable_detail",
                message: message
            )
        default:
            break
        }

        if !appModel.selectedUnifiedCapabilities.policyGroups {
            return WorkbenchStateView(
                kind: .unsupported,
                titleKey: "routing.groups_unsupported_title",
                detailKey: "routing.groups_unsupported_detail"
            )
        }

        switch appModel.controllerSessionPresentation.state {
        case .partial(let message), .failedBeforeFirstSnapshot(let message),
             .failed(let message):
            return WorkbenchStateView(
                kind: .failed,
                titleKey: "routing.groups_unavailable",
                detailKey: "routing.groups_unavailable_detail",
                message: message,
                actionTitleKey: "action.refresh",
                isActionEnabled: appModel.canRefreshSelectedRouter,
                action: appModel.refreshSelectedRouter
            )
        default:
            return WorkbenchStateView(
                kind: .empty,
                titleKey: "routing.groups_not_loaded",
                detailKey: "routing.groups_unavailable_detail",
                actionTitleKey: "action.refresh",
                isActionEnabled: appModel.canRefreshSelectedRouter,
                action: appModel.refreshSelectedRouter
            )
        }
    }

    private var workspace: WorkbenchDestinationWorkspace {
        workspaceStore.workspace(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        )
    }

    private var groupPresentations: [ProxyExpandedGroupPresentation] {
        let itemsByID = Dictionary(
            uniqueKeysWithValues: groupProjection.directoryItems.map {
                ($0.id, $0)
            }
        )
        let openGroupIDs = Set(workspace.openGroupIDs)

        return groupProjection.visibleGroups.compactMap { occurrence in
            guard let item = itemsByID[occurrence.id] else { return nil }
            let index = projectionCache.expandedGroupIndex(for: occurrence.id)
            let inspectedMemberID = workspace.selectedGroupMemberIDs[occurrence.id]
            return ProxyExpandedGroupPresentation(
                occurrence: occurrence,
                item: item,
                isExpanded: openGroupIDs.contains(occurrence.id),
                members: expandedProjections[occurrence.id]?.members ?? [],
                filter: workspace.groupFilters[occurrence.id] ?? "",
                inspectedMemberID: inspectedMemberID,
                inspectedMember: inspectedMemberID.flatMap {
                    index.recordsByID[$0]?.row
                },
                isSwitching: isSwitchingGroup(occurrence.group.id),
                isTesting: isTestingGroup(occurrence.group.id),
                isClearingFixed: appModel.clearingFixedGroupID
                    == occurrence.group.id,
                canClearFixed: canClearFixed(occurrence)
            )
        }
    }

    private func receiveCatalog(
        _ catalog: PolicyGroupCatalogSnapshot,
        forceImmediate: Bool = false
    ) {
        catalogRevisionSequence &+= 1
        let update = ProxyCatalogUpdate(
            revision: ProxyCatalogRevision(
                controllerID: appModel.selectedRouterID,
                generation: appModel.controllerSessionPresentation.generation,
                value: catalogRevisionSequence
            ),
            catalog: catalog
        )
        let priority = ProxyCatalogUpdateClassifier.priority(
            previous: acceptedCatalog,
            next: catalog
        )
        let now = Date()

        if !forceImmediate,
           priority == .deferrable,
           !proxyOperationActivity.isActive,
           presentationCoordinator.deferIfInteracting(update, at: now) {
            return
        }

        applyCatalogUpdate(update)
    }

    private func resetCatalogPresentationForSessionBoundary() {
        presentationCoordinator.reset(preservingScrollState: true)
        acceptedCatalog = .empty
        acceptedCatalogRevision = .zero
        projectionCache = ProxyCatalogProjectionCache()
        groupProjection = .empty
        expandedProjections = [:]
        receiveCatalog(appModel.policyGroupCatalog, forceImmediate: true)
    }

    private func applyCatalogUpdate(
        _ update: ProxyCatalogUpdate,
        supersedingDeferredUpdates: Bool = true
    ) {
        if supersedingDeferredUpdates {
            presentationCoordinator.clearPendingUpdate()
        }
        guard update.revision.isCurrent(
            selectedControllerID: appModel.selectedRouterID,
            sessionControllerID: appModel.controllerSessionPresentation.controllerID,
            generation: appModel.controllerSessionPresentation.generation
        ) else {
            return
        }
        acceptedCatalog = update.catalog
        acceptedCatalogRevision = update.revision
        rebuildCatalogIndex()
    }

    private func rebuildCatalogIndex() {
        projectionCache.updateCatalog(
            acceptedCatalog,
            revision: acceptedCatalogRevision,
            visibility: preferences.globalGroupVisibility
        )
        rebuildVisibleGroupProjection()
        let reconciled = reconcileWorkspace()
        rebuildExpandedGroupIndexes(using: reconciled)
    }

    private func rebuildVisibleGroupProjection() {
        groupProjection = projectionCache.groupProjection(query: searchText)
    }

    @discardableResult
    private func reconcileWorkspace() -> WorkbenchDestinationWorkspace {
        let current = workspace
        let next = ProxyWorkspaceProjection.reconciled(
            current,
            groups: groupProjection.arrangedGroups
        )
        guard next != current else { return current }

        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { stored in
            stored = next
        }
        return next
    }

    private func rebuildExpandedGroupIndexes(
        using currentWorkspace: WorkbenchDestinationWorkspace? = nil
    ) {
        let currentWorkspace = currentWorkspace ?? workspace
        projectionCache.updateExpandedGroups(
            groupIDs: currentWorkspace.openGroupIDs
        )
        rebuildExpandedProjections(using: currentWorkspace)
    }

    private func rebuildExpandedProjections(
        using currentWorkspace: WorkbenchDestinationWorkspace? = nil
    ) {
        let currentWorkspace = currentWorkspace ?? workspace
        expandedProjections = Dictionary(
            uniqueKeysWithValues: currentWorkspace.openGroupIDs.compactMap {
                groupID in
                let index = projectionCache.expandedGroupIndex(for: groupID)
                guard index.occurrence != nil else { return nil }
                return (
                    groupID,
                    ProxyActiveGroupProjection(
                        index: index,
                        query: currentWorkspace.groupFilters[groupID] ?? ""
                    )
                )
            }
        )
    }

    private func openGroup(_ groupID: String) {
        guard hasCurrentCatalogProjection,
              groupProjection.arrangedGroups.contains(where: {
            $0.id == groupID
        }) else { return }

        beginTransientPresentationInteraction()
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { stored in
            stored = ProxyWorkspaceProjection.opening(
                groupID,
                in: stored,
                groups: groupProjection.arrangedGroups,
                preferredMemberID: nil
            )
        }
    }

    private func toggleGroup(_ groupID: String) {
        if workspace.openGroupIDs.contains(groupID) {
            closeGroup(groupID)
        } else {
            openGroup(groupID)
        }
    }

    private func closeGroup(_ groupID: String) {
        guard hasCurrentCatalogProjection else { return }
        beginTransientPresentationInteraction()
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { stored in
            stored = ProxyWorkspaceProjection.closing(
                groupID,
                in: stored,
                groups: groupProjection.arrangedGroups
            )
        }
    }

    private func setGroupFilter(_ value: String, for groupID: String) {
        guard hasCurrentGroupProjection(groupID) else { return }
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { stored in
            stored.groupFilters[groupID] = value
        }
    }

    private func closeMemberInspector(in groupID: String) {
        guard hasCurrentGroupProjection(groupID) else { return }
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { stored in
            stored = ProxyWorkspaceProjection.closingInspector(
                for: groupID,
                in: stored
            )
        }
    }

    private func selectMember(_ memberID: String, in groupID: String) {
        guard hasCurrentGroupProjection(groupID) else { return }

        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { stored in
            stored.activeGroupID = groupID
            stored.selectedGroupMemberIDs[groupID] = memberID
        }

        guard let target = ProxyProjection.currentMemberMutationTarget(
            groupID: groupID,
            memberID: memberID,
            index: projectionCache.expandedGroupIndex(for: groupID),
            selectedControllerID: appModel.selectedRouterID,
            sessionControllerID: appModel.controllerSessionPresentation.controllerID,
            generation: appModel.controllerSessionPresentation.generation,
            actionAvailable: liveCommandsAvailable
                && canSelectMember
                && !isSwitchingGroup(groupID),
            requiresSelectableGroup: true
        ) else { return }

        guard projectionCache.expandedGroupIndex(for: groupID)
            .occurrence?.group.selected != target.memberName else {
            return
        }
        prioritizeUserOperationResult()
        select(target.memberName, in: target.groupID)
    }

    private func testMember(_ memberID: String, in groupID: String) {
        guard hasCurrentGroupProjection(groupID),
              liveCommandsAvailable,
              let target = ProxyProjection.currentMemberMutationTarget(
                groupID: groupID,
                memberID: memberID,
                index: projectionCache.expandedGroupIndex(for: groupID),
                selectedControllerID: appModel.selectedRouterID,
                sessionControllerID: appModel.controllerSessionPresentation.controllerID,
                generation: appModel.controllerSessionPresentation.generation,
                actionAvailable: canTestNode,
                requiresSelectableGroup: false
              ) else { return }

        prioritizeUserOperationResult()
        appModel.measureDelay(for: target.memberName, in: target.groupID)
    }

    private func testGroup(_ groupID: String) {
        let index = projectionCache.expandedGroupIndex(for: groupID)
        guard hasCurrentGroupProjection(groupID),
              let occurrence = index.occurrence,
              groupProjection.arrangedGroups.contains(where: {
                $0.key == occurrence.key
              }),
              liveCommandsAvailable,
              canTestGroup else { return }
        prioritizeUserOperationResult()
        performGroupTest(occurrence.group.id)
    }

    private func clearFixedSelection(in groupID: String) {
        let index = projectionCache.expandedGroupIndex(for: groupID)
        guard hasCurrentGroupProjection(groupID),
              let occurrence = index.occurrence,
              liveCommandsAvailable,
              canClearFixed(occurrence) else { return }
        prioritizeUserOperationResult()
        appModel.clearFixedSelection(in: occurrence.group.id)
    }

    private func beginTransientPresentationInteraction() {
        presentationCoordinator.beginTransientInteraction(at: Date())
    }

    private func prioritizeUserOperationResult() {
        if let pending = presentationCoordinator.prioritizeUserOperationResult(
            at: Date()
        ) {
            applyCatalogUpdate(pending)
        }
    }

    private var proxyOperationActivity: ProxyOperationActivity {
        ProxyOperationActivity(
            switchingGroupID: appModel.switchingGroupID,
            switchingSurgePolicyGroup: appModel.switchingSurgePolicyGroup,
            measuringDelayGroupID: appModel.measuringDelayGroupID,
            testingSurgePolicyGroup: appModel.testingSurgePolicyGroup,
            clearingFixedGroupID: appModel.clearingFixedGroupID,
            measuringDelayNode: appModel.measuringDelayNode
        )
    }

    private var isSurge: Bool {
        guard let router = appModel.selectedRouter else { return false }
        return appModel.runtimeControllerKind(for: router) == .surgeCompatible
    }

    private var canSelectMember: Bool {
        isSurge
            ? appModel.supportsUnifiedAction(.selectSurgePolicy)
            : appModel.supportsUnifiedAction(.switchPolicy)
    }

    private var canTestGroup: Bool {
        isSurge
            ? appModel.supportsUnifiedAction(.testSurgePolicy)
            : appModel.supportsUnifiedAction(.testLatency)
    }

    private var canTestNode: Bool {
        !isSurge
            && appModel.supportsUnifiedAction(.testLatency)
    }

    private func canClearFixed(_ occurrence: ProxyGroupOccurrence) -> Bool {
        occurrence.group.details?.fixed?.proxyNonBlank != nil
            && appModel.supportsUnifiedAction(.clearFixedSelection)
    }

    private var liveCommandsAvailable: Bool {
        hasCurrentCatalogProjection
            && proxySessionPresentation.commandsEnabled
    }

    private var hasCurrentCatalogProjection: Bool {
        projectionCache.groupIndex.revision.isCurrent(
            selectedControllerID: appModel.selectedRouterID,
            sessionControllerID: appModel.controllerSessionPresentation.controllerID,
            generation: appModel.controllerSessionPresentation.generation
        )
    }

    private func hasCurrentGroupProjection(_ groupID: String) -> Bool {
        let index = projectionCache.expandedGroupIndex(for: groupID)
        return hasCurrentCatalogProjection
            && index.revision
                == projectionCache.groupIndex.revision
            && index.occurrence?.id == groupID
    }

    private func isSwitchingGroup(_ groupID: String) -> Bool {
        appModel.switchingGroupID == groupID
            || appModel.switchingSurgePolicyGroup == groupID
    }

    private func isTestingGroup(_ groupID: String) -> Bool {
        appModel.measuringDelayGroupID == groupID
            || appModel.testingSurgePolicyGroup == groupID
    }

    private func select(_ member: String, in groupID: String) {
        if isSurge {
            appModel.selectSurgePolicy(member, in: groupID)
        } else {
            appModel.selectNode(member, in: groupID)
        }
    }

    private func performGroupTest(_ groupID: String) {
        if isSurge {
            appModel.testSurgePolicyGroup(groupID)
        } else {
            appModel.measureDelay(in: groupID)
        }
    }

    private var staleMessage: String? {
        proxySessionPresentation.retainedDataMessage
    }

    private var proxySessionPresentation: ProxySessionPresentation {
        ProxySessionPresentation(
            hasRetainedCatalog: !acceptedCatalog.groups.isEmpty,
            state: appModel.controllerSessionPresentation.state,
            language: language
        )
    }

    private var groupVisibilitySummary: String {
        MicaStrings.localized(
            "routing.visible_groups_count \(groupProjection.visibleGroups.count) \(groupProjection.arrangedGroups.count)",
            language: language
        )
    }

    private var modeBadgeText: String {
        let mode = groupProjection.mode
        return MicaStrings.localized(
            "routing.mode_current \(mode)",
            language: language
        )
    }
}
