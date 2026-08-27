import Foundation
import MicaCore
import SwiftUI

private extension ProxyHealthFilter {
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: "routing.health_filter_all"
        case .degraded: "routing.health_filter_attention"
        case .unavailable: "routing.health_filter_unavailable"
        case .slow: "routing.health_filter_slow"
        case .current: "routing.health_filter_current"
        }
    }
}

struct WorkbenchProxyNavigationReveal: Equatable, Sendable {
    let controllerID: RouterProfile.ID
    let generation: UUID
    let groupID: String
    let memberID: String
    let nodeName: String
    let token: UUID

    var targetID: String {
        ProxyProjection.revealTargetID(
            groupID: groupID,
            memberID: memberID
        )
    }

    func isCurrent(controllerID: RouterProfile.ID?, generation: UUID) -> Bool {
        self.controllerID == controllerID && self.generation == generation
    }
}

enum WorkbenchProxyScrollTarget {
    static func group(_ groupID: String) -> String {
        "proxy-group:\(groupID)"
    }

    static func member(groupID: String, memberID: String) -> String {
        ProxyProjection.revealTargetID(
            groupID: groupID,
            memberID: memberID
        )
    }
}

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
    @State private var healthFilter: ProxyHealthFilter = .all
    @State private var reveal: WorkbenchProxyNavigationReveal?
    @State private var lastScrolledRevealToken: UUID?
    @State private var pendingNavigation: WorkbenchProxyNavigationSelection?
    @State private var revealObstruction: WorkbenchProxyRevealObstruction?
    @State private var unresolvedReason: WorkbenchProxyUnresolvedReason?

    var body: some View {
        WorkbenchPageScaffold {
            VStack(spacing: 0) {
                commandBar

                if let staleMessage {
                    WorkbenchStaleNotice(message: staleMessage)
                }
            }
        } content: {
            content
        }
        .onAppear {
            receiveCatalog(appModel.policyGroupCatalog, forceImmediate: true)
            consumePendingProxyNavigation()
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
            consumePendingProxyNavigation()
            resolveReveal()
        }
        .onChange(of: preferences.globalGroupVisibility) { _, _ in
            rebuildCatalogIndex()
            resolveReveal()
        }
        .onChange(of: searchText) { _, _ in
            rebuildVisibleGroupProjection()
            resolveReveal()
        }
        .onChange(of: workspace.openGroupIDs) { _, _ in
            rebuildExpandedGroupIndexes()
            resolveReveal()
        }
        .onChange(of: workspace.groupFilters) { _, _ in
            rebuildExpandedProjections()
            resolveReveal()
        }
        .onChange(of: workspace.pendingProxySelection) { _, _ in
            consumePendingProxyNavigation()
        }
        .onChange(of: healthFilter) { _, _ in
            rebuildExpandedProjections()
            resolveReveal()
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

    private var commandBar: some View {
        WorkbenchCommandBar {
            WorkbenchCommandSummary(
                symbolName: "point.3.connected.trianglepath.dotted",
                titleKey: "routing.group_catalog",
                value: groupProjection.visibleGroups.count.formatted(),
                detail: groupVisibilitySummary
            )
        } controls: {
            healthFilterPicker
            WorkbenchStatusBadge(
                text: modeBadgeText,
                tint: MicaTheme.textSecondary
            )
        } commands: {
            WorkbenchIconCommand(
                titleKey: "routing.locate_current_node",
                systemImage: "scope",
                isEnabled: canLocateCurrentNode,
                action: { locateCurrentNode() }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if let revealObstruction {
                WorkbenchProxyRevealObstructionNotice(
                    obstruction: revealObstruction,
                    nodeName: reveal?.nodeName
                        ?? pendingNavigation?.nodeName
                        ?? "",
                    recoverAndLocate: recoverRevealObstruction
                )
            }

            if let unresolvedReason,
               let pendingNavigation {
                WorkbenchProxyUnresolvedNotice(
                    nodeName: pendingNavigation.nodeName,
                    reason: unresolvedReason
                )
            }

            if shouldShowNoMatchingGroups {
                noMatchingGroupsState
            } else if groupProjection.arrangedGroups.isEmpty {
                emptyState
            } else if groupProjection.visibleGroups.isEmpty {
                noMatchingGroupsState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: MicaTheme.Spacing.space4) {
                            ForEach(groupPresentations) { presentation in
                                ProxyPolicyGroupPanel(
                                    presentation: presentation,
                                    scrollInteractionTracker: scrollInteractionTracker,
                                    highlightedGroupID: reveal?.groupID,
                                    highlightedMemberID: reveal?.memberID,
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
                                    onLocateCurrent: {
                                        locateCurrentNode(in: presentation.id)
                                    }
                                )
                                .id(WorkbenchProxyScrollTarget.group(presentation.id))
                            }
                        }
                        .padding(MicaTheme.Spacing.space4)
                        .frame(maxWidth: 1_320, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .scrollIndicators(.automatic)
                    .background(MicaTheme.canvas)
                    .proxyScrollInteraction(
                        in: .nodes,
                        coordinator: presentationCoordinator,
                        tracker: scrollInteractionTracker
                    )
                    .task(id: reveal) {
                        guard let reveal else { return }
                        await Task.yield()
                        guard !Task.isCancelled,
                              self.reveal?.token == reveal.token,
                              reveal.isCurrent(
                                  controllerID: appModel.selectedRouterID,
                                  generation: appModel
                                      .controllerSessionPresentation.generation
                              ) else {
                            return
                        }
                        if lastScrolledRevealToken != reveal.token {
                            proxy.scrollTo(
                                WorkbenchProxyScrollTarget.group(reveal.groupID),
                                anchor: .center
                            )
                            try? await Task.sleep(for: .milliseconds(16))
                            guard !Task.isCancelled,
                                  self.reveal?.token == reveal.token,
                                  reveal.isCurrent(
                                      controllerID: appModel.selectedRouterID,
                                      generation: appModel
                                          .controllerSessionPresentation.generation
                                  ) else {
                                return
                            }
                            proxy.scrollTo(reveal.targetID, anchor: .center)
                            lastScrolledRevealToken = reveal.token
                        }
                        try? await Task.sleep(for: .milliseconds(900))
                        guard !Task.isCancelled,
                              self.reveal?.token == reveal.token else { return }
                        self.reveal = nil
                    }
                }
            }
        }
    }

    private var noMatchingGroupsState: some View {
        WorkbenchStateView(
            kind: .filterEmpty,
            titleKey: "dashboard.no_matching_groups",
            detailKey: "dashboard.no_matching_groups_hint"
        )
    }

    private var shouldShowNoMatchingGroups: Bool {
        !groupProjection.arrangedGroups.isEmpty
            && !ProxySearchText.normalize(searchText).isEmpty
            && groupProjection.visibleGroups.isEmpty
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

        if !acceptedCatalog.groups.isEmpty {
            return WorkbenchStateView(
                kind: .filterEmpty,
                titleKey: "routing.groups_hidden_by_preference",
                detailKey: "routing.groups_hidden_by_preference_detail",
                actionTitleKey: "routing.show_global_groups",
                action: showGlobalGroups
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

    private var healthFilterPicker: some View {
        Picker(
            MicaStrings.localizedKey(
                "routing.health_filter",
                language: language
            ),
            selection: $healthFilter
        ) {
            ForEach(ProxyHealthFilter.allCases, id: \.rawValue) { filter in
                Text(verbatim: filterTitle(filter))
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(
            MicaStrings.localizedKey(
                "routing.health_filter",
                language: language
            )
        )
        .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
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
                healthSummary: item.healthSummary,
                healthFilter: healthFilter,
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
        scrollInteractionTracker.end(
            in: .nodes,
            coordinator: presentationCoordinator
        )
        presentationCoordinator.reset()
        acceptedCatalog = .empty
        acceptedCatalogRevision = .zero
        projectionCache = ProxyCatalogProjectionCache()
        groupProjection = .empty
        expandedProjections = [:]
        reveal = nil
        lastScrolledRevealToken = nil
        pendingNavigation = nil
        revealObstruction = nil
        unresolvedReason = nil
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
        consumePendingProxyNavigation()
        resolveReveal()
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
                        query: currentWorkspace.groupFilters[groupID] ?? "",
                        healthFilter: healthFilter
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

    private var canLocateCurrentNode: Bool {
        currentNavigationSelection != nil && hasCurrentCatalogProjection
    }

    private var currentNavigationSelection: WorkbenchProxyNavigationSelection? {
        guard let controllerID = appModel.selectedRouterID else { return nil }
        let generation = appModel.controllerSessionPresentation.generation
        let controllerGroups = ProxyProjection.arrangedGroups(
            acceptedCatalog.groups,
            mode: acceptedCatalog.mode,
            visibility: .alwaysShow
        )
        if let activeGroupID = workspace.activeGroupID,
           let occurrence = controllerGroups.first(
               where: { $0.id == activeGroupID }
           ),
           let nodeName = occurrence.group.selected.proxyNonBlank {
            return ProxyProjection.navigationSelection(
                controllerID: controllerID,
                generation: generation,
                groupOccurrenceID: occurrence.id,
                nodeName: nodeName
            )
        }

        for occurrence in controllerGroups {
            if let nodeName = occurrence.group.selected.proxyNonBlank {
                return ProxyProjection.navigationSelection(
                    controllerID: controllerID,
                    generation: generation,
                    groupOccurrenceID: occurrence.id,
                    nodeName: nodeName
                )
            }
        }
        return nil
    }

    private func locateCurrentNode(in groupID: String? = nil) {
        guard let controllerID = appModel.selectedRouterID,
              hasCurrentCatalogProjection else { return }

        let selection: WorkbenchProxyNavigationSelection?
        if let groupID,
           let occurrence = projectionCache.groupIndex.arrangedGroups.first(
               where: { $0.id == groupID }
           ),
           let nodeName = occurrence.group.selected.proxyNonBlank {
            selection = ProxyProjection.navigationSelection(
                controllerID: controllerID,
                generation: appModel.controllerSessionPresentation.generation,
                groupOccurrenceID: occurrence.id,
                nodeName: nodeName
            )
        } else {
            selection = currentNavigationSelection
        }

        guard let selection else { return }
        acceptProxyNavigation(selection)
    }

    private func consumePendingProxyNavigation() {
        guard let controllerID = appModel.selectedRouterID,
              let selection = workspaceStore.consumeProxyNavigation(
                  controllerID: controllerID,
                  generation: appModel.controllerSessionPresentation.generation
              ) else {
            return
        }

        acceptProxyNavigation(selection)
    }

    private func acceptProxyNavigation(
        _ selection: WorkbenchProxyNavigationSelection
    ) {
        reveal = nil
        pendingNavigation = selection
        unresolvedReason = nil
        revealObstruction = nil
        resolveReveal()
    }

    private func resolveReveal() {
        guard let pendingNavigation else { return }
        guard let controllerID = appModel.selectedRouterID,
              controllerID == pendingNavigation.controllerID,
              appModel.controllerSessionPresentation.generation
                  == pendingNavigation.generation,
              hasCurrentCatalogProjection else {
            return
        }

        let resolution = ProxyProjection.resolveNavigationTarget(
            groupOccurrenceID: pendingNavigation.groupOccurrenceID,
            nodeName: pendingNavigation.nodeName,
            catalog: acceptedCatalog,
            visibility: preferences.globalGroupVisibility
        )

        switch resolution.status {
        case .emptyCatalog:
            unresolvedReason = .emptyCatalog
            revealObstruction = nil
            return
        case .hiddenGlobal:
            unresolvedReason = nil
            revealObstruction = .hiddenGlobal
            return
        case .missingGroup, .ambiguousGroup, .missingNode:
            unresolvedReason = unresolvedReason(for: resolution.status)
            revealObstruction = nil
            return
        case .resolved:
            break
        }

        guard resolution.isResolved,
              let occurrence = resolution.occurrence,
              let member = resolution.member,
              let row = resolution.row else {
            unresolvedReason = unresolvedReason(for: resolution.status)
            revealObstruction = nil
            return
        }
        unresolvedReason = nil

        let currentWorkspace = workspace
        if !currentWorkspace.openGroupIDs.contains(occurrence.id) {
            openGroup(occurrence.id)
            return
        }

        let index = projectionCache.expandedGroupIndex(for: occurrence.id)
        guard index.occurrence != nil else {
            rebuildExpandedGroupIndexes()
            return
        }

        var blockers: WorkbenchProxyFilterObstructions = []
        if !groupProjection.visibleGroups.contains(where: {
            $0.id == occurrence.id
        }) {
            blockers.insert(.globalSearch)
        }
        let textProjection = ProxyActiveGroupProjection(
            index: index,
            query: currentWorkspace.groupFilters[occurrence.id] ?? "",
            healthFilter: .all
        )
        if !textProjection.members.contains(where: { $0.id == member.id }) {
            blockers.insert(.groupFilter)
        }
        if !healthFilter.includes(row) {
            blockers.insert(.healthFilter)
        }
        guard blockers.isEmpty else {
            revealObstruction = .filters(
                groupOccurrenceID: occurrence.id,
                blockers: blockers
            )
            return
        }
        guard expandedProjections[occurrence.id]?.members.contains(where: {
            $0.id == member.id
        }) == true else {
            rebuildExpandedProjections()
            return
        }

        workspaceStore.update(
            controllerID: controllerID,
            destination: .proxies
        ) { stored in
            stored.activeGroupID = occurrence.id
            stored.selectedGroupMemberIDs[occurrence.id] = member.id
        }
        workspaceStore.selectInspector(
            .proxyNode(
                groupName: occurrence.group.id,
                groupOccurrenceID: occurrence.id,
                nodeName: row.name
            )
        )
        reveal = WorkbenchProxyNavigationReveal(
            controllerID: controllerID,
            generation: pendingNavigation.generation,
            groupID: occurrence.id,
            memberID: member.id,
            nodeName: row.name,
            token: UUID()
        )
        self.pendingNavigation = nil
        revealObstruction = nil
        unresolvedReason = nil
    }

    private func recoverRevealObstruction() {
        switch revealObstruction {
        case .hiddenGlobal:
            preferences.globalGroupVisibility = .alwaysShow
            rebuildCatalogIndex()
        case .filters(let groupOccurrenceID, _):
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                workspaceStore.update(
                    controllerID: appModel.selectedRouterID,
                    destination: .proxies
                ) { stored in
                    stored.groupFilters[groupOccurrenceID] = ""
                }
                healthFilter = .all
                searchText = ""
            }
            rebuildVisibleGroupProjection()
            rebuildExpandedProjections()
        case nil:
            break
        }
        revealObstruction = nil
        resolveReveal()
    }

    private func showGlobalGroups() {
        preferences.globalGroupVisibility = .alwaysShow
    }

    private func unresolvedReason(
        for status: ProxyNavigationTargetResolutionStatus
    ) -> WorkbenchProxyUnresolvedReason? {
        switch status {
        case .resolved: nil
        case .emptyCatalog: .emptyCatalog
        case .hiddenGlobal: nil
        case .missingGroup: .missingGroup
        case .ambiguousGroup: .ambiguousGroup
        case .missingNode: .missingNode
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

    private func filterTitle(_ filter: ProxyHealthFilter) -> String {
        MicaStrings.localizedKey(filter.titleKey, language: language)
    }

    private var modeBadgeText: String {
        let mode = groupProjection.mode
        return MicaStrings.localized(
            "routing.mode_current \(mode)",
            language: language
        )
    }
}

private struct WorkbenchProxyRevealObstructionNotice: View {
    @Environment(\.micaAppLanguage) private var language

    let obstruction: WorkbenchProxyRevealObstruction
    let nodeName: String
    let recoverAndLocate: () -> Void

    var body: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        MicaStrings.localized(
                            "routing.reveal_blocked_title \(nodeName)",
                            language: language
                        )
                    )
                    .micaThemeFont(.caption, weight: .semibold)

                    Text(
                        MicaStrings.localizedKey(
                            obstruction.detailKey,
                            language: language
                        )
                    )
                    .micaThemeFont(.caption)
                    .foregroundStyle(MicaTheme.textSecondary)
                }
            } icon: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(MicaTheme.statusWarning)
            }

            Spacer(minLength: MicaTheme.Spacing.space2)

            Button(action: recoverAndLocate) {
                Label(
                    MicaStrings.localizedKey(
                        obstruction.actionTitleKey,
                        language: language
                    ),
                    systemImage: "scope"
                )
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, MicaTheme.Metrics.chromeHorizontalPadding)
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaTheme.statusWarning.opacity(0.08))
        .accessibilityElement(children: .contain)
    }
}

private struct WorkbenchProxyUnresolvedNotice: View {
    @Environment(\.micaAppLanguage) private var language

    let nodeName: String
    let reason: WorkbenchProxyUnresolvedReason

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    MicaStrings.localized(
                        "routing.reveal_unresolved \(nodeName)",
                        language: language
                    )
                )
                .micaThemeFont(.caption, weight: .semibold)
                Text(
                    MicaStrings.localizedKey(
                        reason.detailKey,
                        language: language
                    )
                )
                .micaThemeFont(.caption)
                .foregroundStyle(MicaTheme.textSecondary)
            }
        } icon: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(MicaTheme.textTertiary)
        }
        .padding(.horizontal, MicaTheme.Metrics.chromeHorizontalPadding)
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaTheme.surface)
    }
}
