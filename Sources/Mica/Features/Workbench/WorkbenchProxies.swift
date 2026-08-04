import Foundation
import MicaCore
import Observation
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
                coordinator: presentationCoordinator
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
        occurrence.group.details?.fixed?.nilIfBlank != nil
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

private struct ProxyCompactGroupDirectoryHeader: View {
    @Environment(\.micaAppLanguage) private var language

    let activeGroup: ProxyGroupDirectoryItem?
    let groupCount: Int
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: MicaSpacing.module) {
                WorkbenchSymbol(
                    systemName: "point.3.connected.trianglepath.dotted",
                    tint: MicaDesignTokens.signalCyan,
                    font: .callout.weight(.semibold),
                    frameSize: 18
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        MicaStrings.localizedKey(
                            "routing.group_catalog",
                            language: language
                        )
                    )
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)

                    if let activeGroup {
                        Text(verbatim: activeGroup.groupID)
                            .micaFont(.callout, weight: .semibold)
                            .lineLimit(1)

                        Text(verbatim: activeGroup.selected)
                            .micaFont(.caption, design: .monospaced)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(
                            MicaStrings.localizedKey(
                                "routing.choose_group",
                                language: language
                            )
                        )
                        .micaFont(.callout, weight: .semibold)
                    }
                }

                Spacer(minLength: MicaSpacing.row)

                Text(verbatim: groupCount.formatted())
                    .micaFont(.body, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Image(
                    systemName: isExpanded
                        ? "chevron.up"
                        : "chevron.down"
                )
                .micaFont(.caption, weight: .semibold)
                .foregroundStyle(MicaDesignTokens.accent)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, MicaSpacing.module)
            .frame(
                maxWidth: .infinity,
                minHeight: 54,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            MicaStrings.localizedKey(
                isExpanded
                    ? "routing.collapse_group_directory"
                    : "routing.expand_group_directory",
                language: language
            )
        )
        .background(MicaDesignTokens.contentFill)
    }
}

private struct ProxyGroupDirectory: View {
    @Environment(\.micaAppLanguage) private var language

    let groups: [ProxyGroupDirectoryItem]
    let openGroupIDs: Set<String>
    let activeGroupID: String?
    let onActivate: (String) -> Void
    let onClose: (String) -> Void
    let presentationCoordinator: ProxyCatalogPresentationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: MicaSpacing.row) {
                WorkbenchSymbol(
                    systemName: "point.3.connected.trianglepath.dotted",
                    font: .caption.weight(.semibold),
                    frameSize: 16
                )

                Text(
                    MicaStrings.localizedKey(
                        "routing.group_catalog",
                        language: language
                    )
                )
                .micaFont(.callout, weight: .semibold)

                Spacer(minLength: MicaSpacing.row)

                Text(verbatim: groups.count.formatted())
                    .micaFont(.body, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, MicaSpacing.module)
            .padding(.vertical, MicaSpacing.space2)

            Divider()

            if groups.isEmpty {
                VStack(spacing: MicaSpacing.row) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .micaFont(.title3)
                        .foregroundStyle(.secondary)

                    Text(
                        MicaStrings.localizedKey(
                            "dashboard.no_matching_groups",
                            language: language
                        )
                    )
                    .micaFont(.callout, weight: .semibold)

                    Text(
                        MicaStrings.localizedKey(
                            "dashboard.no_matching_groups_hint",
                            language: language
                        )
                    )
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .padding(MicaSpacing.section)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { group in
                        ProxyGroupDirectoryRow(
                            item: group,
                            isOpen: openGroupIDs.contains(group.id),
                            isActive: activeGroupID == group.id,
                            onActivate: {
                                onActivate(group.id)
                            },
                            onToggle: {
                                if openGroupIDs.contains(group.id) {
                                    onClose(group.id)
                                } else {
                                    onActivate(group.id)
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(MicaDesignTokens.contentFill)
                .proxyScrollInteraction(
                    in: .directory,
                    coordinator: presentationCoordinator
                )
            }
        }
        .background(MicaDesignTokens.contentFill)
    }
}

private struct ProxyGroupDirectoryRow: View {
    @Environment(\.micaAppLanguage) private var language

    let item: ProxyGroupDirectoryItem
    let isOpen: Bool
    let isActive: Bool
    let onActivate: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onActivate) {
                identity
                    .padding(.leading, MicaSpacing.module)
                    .padding(.trailing, MicaSpacing.row)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 76,
                        maxHeight: 76,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityLabel(
                "\(item.groupID), \(item.selected)"
            )
            .help(
                "\(MicaStrings.localizedKey("routing.activate_group", language: language)): \(item.groupID)\n\(item.selected)"
            )

            Button(action: onToggle) {
                Image(
                    systemName: isOpen
                        ? "chevron.down"
                        : "chevron.right"
                )
                .micaFont(.caption, weight: .semibold)
                .foregroundStyle(
                    isActive
                        ? AnyShapeStyle(MicaStyle.accent)
                        : AnyShapeStyle(.secondary)
                )
                .frame(
                    minWidth: MicaBounds.iconControlSize,
                    minHeight: MicaBounds.iconControlSize
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(
                "\(MicaStrings.localizedKey(isOpen ? "routing.close_group" : "routing.open_group", language: language)): \(item.groupID)"
            )
            .accessibilityLabel(
                "\(MicaStrings.localizedKey(isOpen ? "routing.close_group" : "routing.open_group", language: language)): \(item.groupID)"
            )
        }
        .frame(height: 76)
        .background(
            isActive
                ? MicaDesignTokens.elevatedFill
                : Color.clear
        )
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle()
                    .fill(MicaStyle.accent)
                    .frame(width: 3)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.tight) {
            HStack(spacing: MicaSpacing.row) {
                Text(verbatim: item.groupID)
                    .micaFont(.callout, weight: .semibold)
                    .foregroundStyle(
                        isActive
                            ? AnyShapeStyle(MicaStyle.accent)
                            : AnyShapeStyle(.primary)
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: MicaSpacing.tight)

                if item.hasFixedSelection {
                    Image(systemName: "pin.fill")
                        .micaFont(.caption)
                        .foregroundStyle(MicaStyle.accent)
                        .help(
                            MicaStrings.localizedKey(
                                "routing.fixed_selection",
                                language: language
                            )
                        )
                }

                if item.hidden {
                    Image(systemName: "eye.slash.fill")
                        .micaFont(.caption)
                        .foregroundStyle(MicaStyle.signalAmber)
                        .help(
                            MicaStrings.localizedKey(
                                "routing.hidden_group",
                                language: language
                            )
                        )
                }
            }

            HStack(spacing: MicaSpacing.row) {
                Text(verbatim: item.selected)
                    .micaFont(.body, design: .monospaced)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: MicaSpacing.tight)

                if let delay = item.selectedDelay {
                    Text(verbatim: OverviewFormat.latency(delay))
                        .micaFont(.body, weight: .semibold, design: .monospaced)
                        .foregroundStyle(OverviewFormat.latencyTint(delay))
                        .monospacedDigit()
                }
            }

            HStack(spacing: MicaSpacing.row) {
                Text(verbatim: item.type)
                    .lineLimit(1)

                Text(
                    MicaStrings.localized(
                        "routing.nodes_count \(item.memberCount)",
                        language: language
                    )
                )

                if let usageSummary {
                    Text(verbatim: usageSummary)
                        .foregroundStyle(MicaStyle.accent)
                        .lineLimit(1)
                }
            }
            .micaFont(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var usageSummary: String? {
        let labels = item.reportedUsageRanks
            .map { $0.label(language: language) }
            .compactMap(\.nilIfBlank)
        guard !labels.isEmpty else { return nil }
        return labels.joined(separator: " / ")
    }
}

private struct ProxyNodeWorkspace: View {
    @Environment(\.micaAppLanguage) private var language

    let openGroups: [ProxyGroupDirectoryItem]
    let activeProjection: ProxyActiveGroupProjection
    let selectedMemberID: String?
    let inspectedMember: ProxyNodeRowProjection?
    let commandsEnabled: Bool
    let canSelect: Bool
    let canTestGroup: Bool
    let canTestNode: Bool
    let canClearFixed: Bool
    let isSwitching: Bool
    let isTestingGroup: Bool
    let isClearingFixed: Bool
    let measuringNode: PolicyNodeLatencyTestTarget?
    let filter: String

    let onActivateGroup: (String) -> Void
    let onCloseGroup: (String) -> Void
    let onFilterChange: (String) -> Void
    let onSelectMember: (String) -> Void
    let onTestMember: (String) -> Void
    let onTestGroup: () -> Void
    let onClearFixed: () -> Void
    let onCloseInspector: () -> Void
    let presentationCoordinator: ProxyCatalogPresentationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            if openGroups.count > 1 {
                ProxyOpenPathRibbon(
                    groups: openGroups,
                    activeGroupID: activeProjection.occurrence?.id,
                    onActivate: onActivateGroup,
                    onClose: onCloseGroup
                )

                Divider()
            }

            if let occurrence = activeProjection.occurrence {
                ProxyActiveGroupFocusRail(
                    occurrence: occurrence,
                    isSwitching: isSwitching,
                    isTesting: isTestingGroup,
                    isClearingFixed: isClearingFixed,
                    commandsEnabled: commandsEnabled,
                    canTest: canTestGroup,
                    canClearFixed: canClearFixed,
                    onTest: onTestGroup,
                    onClearFixed: onClearFixed
                )

                Divider()

                GeometryReader { geometry in
                    if let inspectedMember,
                       geometry.size.width >= 760 {
                        HStack(spacing: 0) {
                            nodeList(occurrence: occurrence)
                                .frame(minWidth: 380, maxWidth: .infinity)

                            Divider()

                            memberInspector(
                                occurrence: occurrence,
                                member: inspectedMember
                            )
                            .frame(
                                minWidth: MicaBounds.inspectorMin,
                                idealWidth: MicaBounds.inspectorIdeal,
                                maxWidth: MicaBounds.inspectorMax
                            )
                        }
                    } else if let inspectedMember {
                        VStack(spacing: 0) {
                            nodeList(occurrence: occurrence)

                            Divider()

                            memberInspector(
                                occurrence: occurrence,
                                member: inspectedMember
                            )
                            .frame(height: min(300, geometry.size.height * 0.45))
                        }
                    } else {
                        nodeList(occurrence: occurrence)
                    }
                }
            } else {
                WorkbenchStateView(
                    kind: .empty,
                    titleKey: "routing.no_inspector",
                    detailKey: "routing.no_inspector_message"
                )
            }
        }
        .background(MicaDesignTokens.contentFill)
    }

    private func nodeList(
        occurrence: ProxyGroupOccurrence
    ) -> some View {
        ProxyNodeList(
            members: activeProjection.members,
            totalCount: occurrence.group.options.count,
            selectedMemberID: selectedMemberID,
            filter: filter,
            canSelect: canSelect && occurrence.group.selectable,
            canTest: canTestNode,
            commandsEnabled: commandsEnabled,
            isSwitching: isSwitching,
            measuringNode: measuringNode,
            groupID: occurrence.group.id,
            onFilterChange: onFilterChange,
            onSelect: onSelectMember,
            onTest: onTestMember,
            presentationCoordinator: presentationCoordinator
        )
    }

    private func memberInspector(
        occurrence: ProxyGroupOccurrence,
        member: ProxyNodeRowProjection
    ) -> some View {
        ProxyNodeInspector(
            member: member,
            group: occurrence.group,
            canSelect: canSelect && occurrence.group.selectable,
            canTest: canTestNode,
            commandsEnabled: commandsEnabled,
            isSwitching: isSwitching,
            isMeasuring: measuringNode?.groupID == occurrence.group.id
                && measuringNode?.nodeName == member.name,
            onSelect: {
                onSelectMember(member.id)
            },
            onTest: {
                onTestMember(member.id)
            },
            onClose: onCloseInspector,
            presentationCoordinator: presentationCoordinator
        )
    }
}

private struct ProxyOpenPathRibbon: View {
    @Environment(\.micaAppLanguage) private var language

    let groups: [ProxyGroupDirectoryItem]
    let activeGroupID: String?
    let onActivate: (String) -> Void
    let onClose: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ribbon(maximumVisibleCount: 4)
            ribbon(maximumVisibleCount: 3)
            ribbon(maximumVisibleCount: 2)
            ribbon(maximumVisibleCount: 1)
        }
        .padding(.horizontal, MicaSpacing.row)
        .padding(.vertical, MicaSpacing.tight)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(MicaDesignTokens.elevatedFill)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            MicaStrings.localizedKey(
                "routing.open_group_paths",
                language: language
            )
        )
    }

    private func ribbon(maximumVisibleCount: Int) -> some View {
        let projection = ProxyOpenPathRibbonProjection(
            groups: groups,
            maximumVisibleCount: maximumVisibleCount
        )

        return HStack(spacing: 0) {
            ForEach(projection.visible) { group in
                ProxyOpenPathRibbonItem(
                    group: group,
                    isActive: activeGroupID == group.id,
                    onActivate: {
                        onActivate(group.id)
                    },
                    onClose: {
                        onClose(group.id)
                    }
                )
            }

            if !projection.overflow.isEmpty {
                overflowMenu(projection.overflow)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func overflowMenu(
        _ overflow: [ProxyGroupDirectoryItem]
    ) -> some View {
        Menu {
            ForEach(overflow) { group in
                Menu {
                    Button {
                        onActivate(group.id)
                    } label: {
                        Label(
                            MicaStrings.localizedKey(
                                "routing.activate_group",
                                language: language
                            ),
                            systemImage: "arrow.right"
                        )
                    }

                    Button {
                        onClose(group.id)
                    } label: {
                        Label(
                            MicaStrings.localizedKey(
                                "routing.close_group",
                                language: language
                            ),
                            systemImage: "xmark"
                        )
                    }
                } label: {
                    Label {
                        Text(
                            verbatim: "\(group.groupID) → \(group.selected)"
                        )
                    } icon: {
                        Image(
                            systemName: activeGroupID == group.id
                                ? "checkmark"
                                : "circle"
                        )
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(
                    minWidth: MicaBounds.iconControlSize,
                    minHeight: MicaBounds.iconControlSize
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(
            MicaStrings.localizedKey(
                "routing.more_open_groups",
                language: language
            )
        )
        .accessibilityLabel(
            MicaStrings.localizedKey(
                "routing.more_open_groups",
                language: language
            )
        )
    }
}

private struct ProxyOpenPathRibbonItem: View {
    @Environment(\.micaAppLanguage) private var language

    let group: ProxyGroupDirectoryItem
    let isActive: Bool
    let onActivate: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onActivate) {
                HStack(spacing: MicaSpacing.tight) {
                    Text(verbatim: group.groupID)
                        .micaFont(.callout, weight: .semibold)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    WorkbenchDecisionPathConnector()

                    Text(verbatim: group.selected)
                        .micaFont(.caption, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.leading, MicaSpacing.module)
                .frame(
                    minWidth: 136,
                    idealWidth: 180,
                    maxWidth: 220,
                    minHeight: MicaBounds.controlMinHeight,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($isFocused)
            .foregroundStyle(isActive ? MicaStyle.accent : .primary)
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .help("\(group.groupID)\n\(group.selected)")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .micaFont(.caption, weight: .semibold)
                    .frame(
                        minWidth: MicaBounds.iconControlSize,
                        minHeight: MicaBounds.iconControlSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .opacity(showsClose ? 1 : 0)
            .allowsHitTesting(showsClose)
            .accessibilityHidden(!showsClose)
            .help(
                MicaStrings.localizedKey(
                    "routing.close_group",
                    language: language
                )
            )
            .accessibilityLabel(
                MicaStrings.localizedKey(
                    "routing.close_group",
                    language: language
                )
            )
        }
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(MicaStyle.accent)
                    .frame(height: 2)
                    .accessibilityHidden(true)
            }
        }
        .onHover { isHovered = $0 }
    }

    private var showsClose: Bool {
        isActive || isHovered || isFocused
    }
}

private struct ProxyActiveGroupFocusRail: View {
    @Environment(\.micaAppLanguage) private var language

    let occurrence: ProxyGroupOccurrence
    let isSwitching: Bool
    let isTesting: Bool
    let isClearingFixed: Bool
    let commandsEnabled: Bool
    let canTest: Bool
    let canClearFixed: Bool
    let onTest: () -> Void
    let onClearFixed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: MicaSpacing.section) {
                    horizontalPath
                    Spacer(minLength: MicaSpacing.module)
                    controls
                }

                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    compactPath
                    controls
                }
            }

            readouts
        }
        .padding(.horizontal, MicaSpacing.module)
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaDesignTokens.contentFill)
    }

    private var horizontalPath: some View {
        HStack(spacing: MicaSpacing.row) {
            groupStep
            WorkbenchDecisionPathConnector()
            selectionStep
            WorkbenchDecisionPathConnector()
            candidatesStep
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactPath: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupStep
            compactConnector
            selectionStep
            compactConnector
            candidatesStep
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactConnector: some View {
        Image(systemName: "chevron.down")
            .micaFont(.caption2, weight: .semibold)
            .foregroundStyle(.tertiary)
            .padding(.leading, 10)
            .accessibilityHidden(true)
    }

    private var groupStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "routing.path_group",
            value: occurrence.group.id,
            systemImage: "point.3.connected.trianglepath.dotted",
            tint: MicaDesignTokens.signalViolet
        )
    }

    private var selectionStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "dashboard.current_node",
            value: selectedText,
            systemImage: "checkmark.circle",
            tint: MicaDesignTokens.accent,
            monospaced: true
        )
    }

    private var candidatesStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "routing.path_candidates",
            value: occurrence.group.options.count.formatted(),
            systemImage: "list.bullet",
            tint: MicaDesignTokens.signalCyan,
            monospaced: true
        )
    }

    @ViewBuilder
    private var readouts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.section) {
                typeReadout
                if let selectedDelay {
                    latencyReadout(selectedDelay)
                }
                if let fixedSelection {
                    fixedReadout(fixedSelection)
                }
                if occurrence.group.hidden {
                    hiddenReadout
                }
            }

            VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                HStack(spacing: MicaSpacing.section) {
                    typeReadout
                    if let selectedDelay {
                        latencyReadout(selectedDelay)
                    }
                }
                HStack(spacing: MicaSpacing.section) {
                    if let fixedSelection {
                        fixedReadout(fixedSelection)
                    }
                    if occurrence.group.hidden {
                        hiddenReadout
                    }
                }
            }
        }
    }

    private var typeReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "dashboard.col_type",
            value: occurrence.group.type,
            systemImage: "tag",
            tint: .secondary,
            monospaced: false
        )
    }

    private func latencyReadout(_ delay: Int) -> some View {
        WorkbenchDecisionReadout(
            titleKey: "routing.current_latency",
            value: OverviewFormat.latency(delay),
            systemImage: "gauge.with.dots.needle.33percent",
            tint: OverviewFormat.latencyTint(delay)
        )
    }

    private func fixedReadout(_ fixed: String) -> some View {
        WorkbenchDecisionReadout(
            titleKey: "routing.fixed_selection",
            value: fixed,
            systemImage: "pin.fill",
            tint: MicaDesignTokens.accent
        )
    }

    private var hiddenReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "routing.hidden_group",
            value: MicaStrings.localizedKey(
                "overview.config_enabled",
                language: language
            ),
            systemImage: "eye.slash",
            tint: MicaDesignTokens.signalAmber,
            monospaced: false
        )
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: MicaSpacing.row) {
            if canTest || isTesting {
                Button(action: onTest) {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(
                    !canTest
                        || !commandsEnabled
                        || isTesting
                        || isSwitching
                        || isClearingFixed
                )
                .frame(
                    minWidth: MicaBounds.iconControlSize,
                    minHeight: MicaBounds.iconControlSize
                )
                .help(
                    MicaStrings.localizedKey(
                        "routing.test_group",
                        language: language
                    )
                )
                .accessibilityLabel(
                    MicaStrings.localizedKey(
                        "routing.test_group",
                        language: language
                    )
                )
            }

            if canClearFixed || isClearingFixed {
                Button(action: onClearFixed) {
                    if isClearingFixed {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "pin.slash")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(
                    !canClearFixed
                        || !commandsEnabled
                        || isClearingFixed
                        || isSwitching
                        || isTesting
                )
                .frame(
                    minWidth: MicaBounds.iconControlSize,
                    minHeight: MicaBounds.iconControlSize
                )
                .help(
                    MicaStrings.localizedKey(
                        "routing.clear_fixed_selection",
                        language: language
                    )
                )
                .accessibilityLabel(
                    MicaStrings.localizedKey(
                        "routing.clear_fixed_selection",
                        language: language
                    )
                )
            }

            if isSwitching {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(
                        MicaStrings.localizedKey(
                            "dashboard.switch_node",
                            language: language
                        )
                    )
            }
        }
    }

    private var selectedText: String {
        occurrence.group.selected.nilIfBlank
            ?? MicaStrings.localizedKey(
                "routing.node_unavailable",
                language: language
            )
    }

    private var selectedDelay: Int? {
        occurrence.group.delays[occurrence.group.selected]
            ?? occurrence.group.detail(
                for: occurrence.group.selected
            )?.latestHistoryDelay
    }

    private var fixedSelection: String? {
        occurrence.group.details?.fixed?.nilIfBlank
    }
}

private struct ProxyNodeList: View {
    @Environment(\.micaAppLanguage) private var language

    let members: [ProxyNodeRowProjection]
    let totalCount: Int
    let selectedMemberID: String?
    let filter: String
    let canSelect: Bool
    let canTest: Bool
    let commandsEnabled: Bool
    let isSwitching: Bool
    let measuringNode: PolicyNodeLatencyTestTarget?
    let groupID: String

    let onFilterChange: (String) -> Void
    let onSelect: (String) -> Void
    let onTest: (String) -> Void
    let presentationCoordinator: ProxyCatalogPresentationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: MicaSpacing.module) {
                TextField(
                    MicaStrings.localizedKey(
                        "routing.filter_nodes_placeholder",
                        language: language
                    ),
                    text: Binding(
                        get: { filter },
                        set: { value in onFilterChange(value) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, minHeight: MicaBounds.controlMinHeight)
                .accessibilityLabel(
                    MicaStrings.localizedKey(
                        "routing.filter_nodes",
                        language: language
                    )
                )

                Text(
                    MicaStrings.localized(
                        "routing.member_window \(members.count) \(totalCount)",
                        language: language
                    )
                )
                .micaFont(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .textSelection(.enabled)
            }
            .padding(.horizontal, MicaSpacing.module)
            .frame(minHeight: 52)

            Divider()

            if members.isEmpty {
                Label(
                    MicaStrings.localizedKey(
                        filter.nilIfBlank == nil
                            ? "routing.members_empty"
                            : "routing.members_filtered_empty",
                        language: language
                    ),
                    systemImage: "tray"
                )
                .foregroundStyle(.secondary)
                .padding(MicaSpacing.section)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(members) { member in
                        ProxyNodeRow(
                            member: member,
                            isWorkspaceSelected: selectedMemberID == member.id,
                            canSelect: canSelect,
                            canTest: canTest,
                            commandsEnabled: commandsEnabled,
                            isSwitching: isSwitching,
                            isMeasuring: measuringNode?.groupID == groupID
                                && measuringNode?.nodeName == member.name,
                            onSelect: { onSelect(member.id) },
                            onTest: { onTest(member.id) }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(MicaDesignTokens.contentFill)
                .proxyScrollInteraction(
                    in: .nodes,
                    coordinator: presentationCoordinator
                )
            }
        }
        .background(MicaDesignTokens.contentFill)
    }
}

private struct ProxyNodeRow: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var measuringPulse = false

    let member: ProxyNodeRowProjection
    let isWorkspaceSelected: Bool
    let canSelect: Bool
    let canTest: Bool
    let commandsEnabled: Bool
    let isSwitching: Bool
    let isMeasuring: Bool
    let onSelect: () -> Void
    let onTest: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: MicaSpacing.module) {
                    Image(
                        systemName: member.isControllerSelected
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .foregroundStyle(
                        member.isControllerSelected
                            ? MicaStyle.accent
                            : Color.secondary
                    )
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                        Text(verbatim: member.name)
                            .micaFont(
                                .body,
                                weight: member.isControllerSelected
                                    ? .semibold
                                    : .regular,
                                design: .monospaced
                            )
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        HStack(spacing: MicaSpacing.row) {
                            if let subtitle = member.subtitle {
                                Text(verbatim: subtitle)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            if let rank = member.usageRank,
                               let label = rank.label(language: language).nilIfBlank {
                                Text(verbatim: label)
                                    .foregroundStyle(usageTint(rank))
                                    .lineLimit(1)
                            }
                        }
                        .micaFont(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: MicaSpacing.row)

                    if let delay = member.delay {
                        Text(verbatim: OverviewFormat.latency(delay))
                            .micaFont(.body, weight: .semibold, design: .monospaced)
                            .foregroundStyle(OverviewFormat.latencyTint(delay))
                            .monospacedDigit()
                            .opacity(isMeasuring && measuringPulse ? 0.5 : 1)
                            .animation(
                                reduceMotion
                                    ? nil
                                    : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                value: measuringPulse
                            )
                    }

                    if let alive = member.alive {
                        Image(
                            systemName: alive
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .micaFont(.caption)
                        .foregroundStyle(
                            alive
                                ? MicaStyle.signalMint
                                : MicaStyle.signalRed
                        )
                        .accessibilityLabel(availabilityText(alive: alive))
                    }

                    if canSelect
                        && commandsEnabled
                        && !member.isControllerSelected {
                        Image(systemName: "arrow.right")
                            .micaFont(.caption, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.leading, MicaSpacing.module)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 52,
                    maxHeight: 52,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selectionAccessibilityLabel)
            .accessibilityAddTraits(
                isWorkspaceSelected ? .isSelected : []
            )
            .help(member.name)

            if canTest || isMeasuring {
                Button(action: onTest) {
                    if isMeasuring {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(
                    !canTest
                        || !commandsEnabled
                        || isMeasuring
                        || isSwitching
                )
                .help(
                    MicaStrings.localized(
                        "routing.help_test_node \(member.name)",
                        language: language
                    )
                )
                .accessibilityLabel(
                    MicaStrings.localized(
                        "routing.test_node \(member.name)",
                        language: language
                    )
                )
                .frame(
                    minWidth: MicaBounds.iconControlSize,
                    minHeight: MicaBounds.iconControlSize
                )
            }
        }
        .frame(height: 52)
        .background {
            ZStack(alignment: .leading) {
                if let latencyFraction = member.latencyFraction {
                    Rectangle()
                        .fill(
                            (member.delay.map(OverviewFormat.latencyTint)
                                ?? MicaDesignTokens.signalCyan)
                                .opacity(0.10)
                        )
                        .scaleEffect(
                            x: latencyFraction,
                            y: 1,
                            anchor: .leading
                        )
                        .animation(
                            reduceMotion ? nil : WorkbenchMotion.latencyShift,
                            value: latencyFraction
                        )
                        .accessibilityHidden(true)
                }

                if isWorkspaceSelected {
                    Rectangle()
                        .fill(MicaStyle.accent.opacity(0.10))
                        .accessibilityHidden(true)
                }
            }
        }
        .overlay(alignment: .leading) {
            if isWorkspaceSelected {
                Rectangle()
                    .fill(MicaStyle.accent)
                    .frame(width: 3)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { measuringPulse = isMeasuring }
        .onChange(of: isMeasuring) { _, newValue in measuringPulse = newValue }
    }

    private var selectionAccessibilityLabel: String {
        if !canSelect || !commandsEnabled {
            let inspect = MicaStrings.localizedKey(
                "dashboard.inspect",
                language: language
            )
            return "\(inspect): \(member.name)"
        }

        let latency = member.delay.map(OverviewFormat.latency)
            ?? MicaStrings.localizedKey(
                "routing.node_unavailable",
                language: language
            )
        return MicaStrings.localized(
            "routing.acc_select_member \(member.name) \(latency)",
            language: language
        )
    }

    private func availabilityText(alive: Bool) -> String {
        MicaStrings.localizedKey(
            alive ? "routing.node_alive" : "routing.node_unavailable",
            language: language
        )
    }

    private func usageTint(_ rank: PolicyGroupUsageRank) -> Color {
        switch rank {
        case .mostUsed:
            MicaStyle.accent
        case .occasionallyUsed, .rarelyUsed, .reported:
            .secondary
        }
    }
}

private struct ProxyNodeInspector: View {
    @Environment(\.micaAppLanguage) private var language

    let member: ProxyNodeRowProjection
    let group: ProxyGroupViewState
    let canSelect: Bool
    let canTest: Bool
    let commandsEnabled: Bool
    let isSwitching: Bool
    let isMeasuring: Bool
    let onSelect: () -> Void
    let onTest: () -> Void
    let onClose: () -> Void
    let presentationCoordinator: ProxyCatalogPresentationCoordinator

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MicaSpacing.section) {
                HStack(alignment: .top, spacing: MicaSpacing.row) {
                    VStack(alignment: .leading, spacing: MicaSpacing.row) {
                        Text(verbatim: member.name)
                            .micaFont(.title3, weight: .semibold)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: MicaSpacing.row) {
                            if member.isControllerSelected {
                                WorkbenchStatusBadge(
                                    text: MicaStrings.localizedKey(
                                        "dashboard.inspector_current",
                                        language: language
                                    ),
                                    tint: MicaStyle.signalMint
                                )
                            }

                            if let rank = member.usageRank,
                               let label = rank.label(language: language).nilIfBlank {
                                WorkbenchStatusBadge(
                                    text: label,
                                    tint: usageTint(rank)
                                )
                            }
                        }
                    }

                    Spacer(minLength: MicaSpacing.row)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .frame(
                                minWidth: MicaBounds.iconControlSize,
                                minHeight: MicaBounds.iconControlSize
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(
                        MicaStrings.localizedKey(
                            "routing.help_close_inspector",
                            language: language
                        )
                    )
                    .accessibilityLabel(
                        MicaStrings.localizedKey(
                            "dashboard.close_inspector",
                            language: language
                        )
                    )
                }

                HStack(spacing: MicaSpacing.row) {
                    if canSelect {
                        Button(action: onSelect) {
                            Image(systemName: "arrow.triangle.swap")
                                .frame(
                                    minWidth: MicaBounds.iconControlSize,
                                    minHeight: MicaBounds.iconControlSize
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(
                            !commandsEnabled
                                || member.isControllerSelected
                                || isSwitching
                        )
                        .help(
                            MicaStrings.localizedKey(
                                "dashboard.switch_node",
                                language: language
                            )
                        )
                        .accessibilityLabel(
                            MicaStrings.localizedKey(
                                "dashboard.switch_node",
                                language: language
                            )
                        )
                    }

                    if canTest || isMeasuring {
                        Button(action: onTest) {
                            if isMeasuring {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(
                                        minWidth: MicaBounds.iconControlSize,
                                        minHeight: MicaBounds.iconControlSize
                                    )
                            } else {
                                Image(systemName: "bolt")
                                    .frame(
                                        minWidth: MicaBounds.iconControlSize,
                                        minHeight: MicaBounds.iconControlSize
                                    )
                                    .contentShape(Rectangle())
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(
                            !canTest
                                || !commandsEnabled
                                || isMeasuring
                                || isSwitching
                        )
                        .help(
                            MicaStrings.localizedKey(
                                "dashboard.test_delay",
                                language: language
                            )
                        )
                        .accessibilityLabel(
                            MicaStrings.localizedKey(
                                "dashboard.test_delay",
                                language: language
                            )
                        )
                    }
                }

                Divider()

                ProxyNodeDetailSections(
                    detail: group.detail(for: member.name)
                )
            }
            .padding(MicaSpacing.section)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(MicaDesignTokens.elevatedFill)
        .proxyScrollInteraction(
            in: .inspector,
            coordinator: presentationCoordinator
        )
    }

    private func usageTint(_ rank: PolicyGroupUsageRank) -> Color {
        switch rank {
        case .mostUsed:
            MicaStyle.accent
        case .occasionallyUsed, .rarelyUsed, .reported:
            .secondary
        }
    }
}

private struct ProxyNodeDetailSections: View {
    @Environment(\.micaAppLanguage) private var language

    let detail: ProxyNodeViewState?

    var body: some View {
        let projection = ProxyMemberDetailProjection(detail: detail)

        VStack(alignment: .leading, spacing: MicaSpacing.section) {
            WorkbenchDataInspectorSection("routing.node_section_overview") {
                WorkbenchDataInspectorField(
                    titleKey: "dashboard.col_type",
                    value: detail?.type
                )
                WorkbenchDataInspectorField(
                    titleKey: "routing.node_status",
                    value: projection.availabilityText(language: language)
                )
                WorkbenchDataInspectorField(
                    titleKey: "routing.node_provider",
                    value: detail?.providerName
                )
                WorkbenchDataInspectorField(
                    titleKey: "routing.fixed_selection",
                    value: projection.fixedSelectionText(language: language)
                )
                WorkbenchDataInspectorField(
                    titleKey: "routing.node_interface",
                    value: detail?.interfaceName,
                    monospaced: true
                )
                WorkbenchDataInspectorField(
                    titleKey: "routing.node_hidden",
                    value: detail?.hidden.map(localizedBoolean)
                )
            }

            if let capabilities = detail?.transportCapabilities,
               !capabilities.isEmpty {
                WorkbenchDataInspectorSection("routing.node_section_transport") {
                    ForEach(capabilities) { capability in
                        ProxyNodeVerbatimDetailField(
                            title: capability.name,
                            value: localizedBoolean(capability.isEnabled)
                        )
                    }
                }
            }

            WorkbenchDataInspectorSection("routing.node_section_testing") {
                WorkbenchDataInspectorField(
                    titleKey: "routing.test_url",
                    value: detail?.testURL,
                    monospaced: true
                )
                WorkbenchDataInspectorField(
                    titleKey: "routing.icon_url",
                    value: detail?.icon,
                    monospaced: true
                )
                WorkbenchDataInspectorField(
                    titleKey: "routing.delay_history",
                    value: projection.historySummaryText(language: language),
                    monospaced: true
                )
            }

            if !projection.reportedFields.isEmpty {
                WorkbenchDataInspectorSection("routing.node_section_reported_fields") {
                    ForEach(projection.reportedFields) { field in
                        ProxyNodeVerbatimDetailField(
                            title: field.key,
                            value: field.value,
                            monospaced: true
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func localizedBoolean(_ value: Bool) -> String {
        MicaStrings.localizedKey(
            value ? "overview.config_enabled" : "overview.config_disabled",
            language: language
        )
    }
}

private struct ProxyNodeVerbatimDetailField: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .top, spacing: MicaSpacing.module) {
            Text(verbatim: title)
                .micaFont(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
                .textSelection(.enabled)

            Text(verbatim: value)
                .micaFont(.callout, design: monospaced ? .monospaced : .default)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProxySessionPresentation: Equatable {
    let commandsEnabled: Bool
    let retainedDataMessage: String?

    init(
        hasRetainedCatalog: Bool,
        state: LiveSessionState,
        language: AppLanguage
    ) {
        commandsEnabled = state.allowsLiveCommands

        guard hasRetainedCatalog else {
            retainedDataMessage = nil
            return
        }

        let detail: String?
        switch state {
        case .live:
            detail = nil
        case .idle:
            detail = MicaStrings.localizedKey(
                "connection.disconnected",
                language: language
            )
        case .connecting:
            detail = state.label(language: language)
        case .staleReconnecting(let message), .partial(let message),
             .failedBeforeFirstSnapshot(let message), .failed(let message):
            detail = message.nilIfBlank ?? state.label(language: language)
        case .stopped:
            detail = MicaStrings.localizedKey(
                "live.detail_stopped",
                language: language
            )
        }

        retainedDataMessage = detail.map {
            MicaStrings.localized(
                "data.stale_detail \($0)",
                language: language
            )
        }
    }
}

struct ProxyCatalogRevision: Hashable, Sendable {
    let controllerID: RouterProfile.ID?
    let generation: UUID?
    let value: UInt64

    static let zero = ProxyCatalogRevision(
        controllerID: nil,
        generation: nil,
        value: 0
    )

    func isCurrent(
        controllerID: RouterProfile.ID?,
        generation: UUID
    ) -> Bool {
        self.controllerID == controllerID
            && self.generation == generation
    }

    func isCurrent(
        selectedControllerID: RouterProfile.ID?,
        sessionControllerID: RouterProfile.ID?,
        generation: UUID
    ) -> Bool {
        selectedControllerID == sessionControllerID
            && isCurrent(
                controllerID: sessionControllerID,
                generation: generation
            )
    }
}

struct ProxyCatalogUpdate: Equatable {
    let revision: ProxyCatalogRevision
    let catalog: PolicyGroupCatalogSnapshot
}

enum ProxyCatalogUpdatePriority: Equatable {
    case immediate
    case deferrable
}

enum ProxyCatalogUpdateClassifier {
    static func priority(
        previous: PolicyGroupCatalogSnapshot,
        next: PolicyGroupCatalogSnapshot
    ) -> ProxyCatalogUpdatePriority {
        guard previous.mode == next.mode,
              previous.groups.count == next.groups.count else {
            return .immediate
        }

        for (previousGroup, nextGroup) in zip(previous.groups, next.groups) {
            guard previousGroup.id == nextGroup.id,
                  previousGroup.type == nextGroup.type,
                  previousGroup.selected == nextGroup.selected,
                  previousGroup.options == nextGroup.options,
                  previousGroup.hidden == nextGroup.hidden,
                  previousGroup.selectable == nextGroup.selectable,
                  previousGroup.details?.fixed == nextGroup.details?.fixed else {
                return .immediate
            }
        }

        return .deferrable
    }
}

enum ProxyInteractionRegion: Hashable {
    case directory
    case nodes
    case inspector
}

@MainActor
@Observable
final class ProxyCatalogPresentationCoordinator {
    private(set) var commitRevision: UInt64 = 0

    @ObservationIgnored private var scheduler = ProxyCatalogPresentationScheduler()
    @ObservationIgnored private var readyUpdate: ProxyCatalogUpdate?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?

    func deferIfInteracting(
        _ update: ProxyCatalogUpdate,
        at now: Date
    ) -> Bool {
        guard scheduler.deferIfInteracting(update, at: now) else {
            return false
        }
        schedulePendingDeadlineIfNeeded(at: now)
        return true
    }

    func beginTransientInteraction(at now: Date) {
        scheduler.beginTransientInteraction(at: now)
    }

    func updateScrolling(
        _ isScrolling: Bool,
        in region: ProxyInteractionRegion,
        at now: Date
    ) {
        if isScrolling {
            scheduler.beginScrolling(in: region, at: now)
            return
        }

        scheduler.endScrolling(in: region, at: now)
        guard let update = scheduler.takePendingUpdateIfIdle(at: now) else {
            return
        }
        cancelPendingDeadline()
        publish(update)
    }

    func prioritizeUserOperationResult(at now: Date) -> ProxyCatalogUpdate? {
        scheduler.beginCriticalWindow(at: now)
        let update = scheduler.takePendingUpdate()
        cancelPendingDeadline()
        return update
    }

    func takeReadyUpdate() -> ProxyCatalogUpdate? {
        defer { readyUpdate = nil }
        return readyUpdate
    }

    func clearPendingUpdate() {
        scheduler.clearPendingUpdate()
        readyUpdate = nil
        cancelPendingDeadline()
    }

    func reset(preservingScrollState: Bool = false) {
        scheduler.reset(preservingScrollState: preservingScrollState)
        readyUpdate = nil
        cancelPendingDeadline()
    }

    private func schedulePendingDeadlineIfNeeded(at now: Date) {
        guard deadlineTask == nil,
              let deadline = scheduler.pendingDeadline else {
            return
        }

        let remainingMilliseconds = Int64(
            ceil(max(0, deadline.timeIntervalSince(now) * 1_000))
        )
        deadlineTask = Task { @concurrent [weak self] in
            if remainingMilliseconds > 0 {
                do {
                    try await Task.sleep(
                        for: .milliseconds(remainingMilliseconds)
                    )
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await self?.pendingDeadlineReached()
        }
    }

    private func pendingDeadlineReached() {
        deadlineTask = nil
        let now = Date()
        guard let update = scheduler.takePendingUpdateIfDue(at: now) else {
            schedulePendingDeadlineIfNeeded(at: now)
            return
        }
        publish(update)
    }

    private func publish(_ update: ProxyCatalogUpdate) {
        readyUpdate = update
        commitRevision &+= 1
    }

    private func cancelPendingDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
    }
}

@MainActor
final class ProxyScrollInteractionTracker {
    private(set) var isScrolling = false

    func update(
        _ phase: ScrollPhase,
        in region: ProxyInteractionRegion,
        coordinator: ProxyCatalogPresentationCoordinator,
        at now: Date = Date()
    ) {
        let nextIsScrolling: Bool
        switch phase {
        case .tracking, .interacting, .decelerating, .animating:
            nextIsScrolling = true
        case .idle:
            nextIsScrolling = false
        }

        guard nextIsScrolling != isScrolling else { return }
        isScrolling = nextIsScrolling
        MicaPerformanceObservation.recordDebug(
            .scrollPhase,
            metadata: MicaPerformanceMetadata(
                count: 1,
                revision: nextIsScrolling ? 1 : 2
            )
        )
        coordinator.updateScrolling(
            nextIsScrolling,
            in: region,
            at: now
        )
    }

    func end(
        in region: ProxyInteractionRegion,
        coordinator: ProxyCatalogPresentationCoordinator,
        at now: Date = Date()
    ) {
        guard isScrolling else { return }
        isScrolling = false
        MicaPerformanceObservation.recordDebug(
            .scrollPhase,
            metadata: MicaPerformanceMetadata(count: 1, revision: 2)
        )
        coordinator.updateScrolling(false, in: region, at: now)
    }
}

@MainActor
private struct ProxyScrollInteractionModifier: ViewModifier {
    let region: ProxyInteractionRegion
    let coordinator: ProxyCatalogPresentationCoordinator

    @State private var tracker = ProxyScrollInteractionTracker()

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                tracker.update(
                    phase,
                    in: region,
                    coordinator: coordinator
                )
            }
            .onDisappear {
                tracker.end(
                    in: region,
                    coordinator: coordinator
                )
            }
    }
}

private extension View {
    func proxyScrollInteraction(
        in region: ProxyInteractionRegion,
        coordinator: ProxyCatalogPresentationCoordinator
    ) -> some View {
        modifier(
            ProxyScrollInteractionModifier(
                region: region,
                coordinator: coordinator
            )
        )
    }
}

struct ProxyCatalogPresentationScheduler: Equatable {
    static let maximumDeferral: TimeInterval = 0.2
    static let transientInteractionDuration: TimeInterval = 0.18
    static let criticalResultDuration: TimeInterval = 0.75

    private(set) var scrollingRegions: Set<ProxyInteractionRegion> = []
    private(set) var transientInteractionUntil: Date?
    private(set) var criticalResultUntil: Date?
    private(set) var pendingUpdate: ProxyCatalogUpdate?
    private(set) var pendingDeadline: Date?

    mutating func beginScrolling(
        in region: ProxyInteractionRegion,
        at now: Date
    ) {
        expireWindows(at: now)
        scrollingRegions.insert(region)
    }

    mutating func endScrolling(
        in region: ProxyInteractionRegion,
        at now: Date
    ) {
        scrollingRegions.remove(region)
        expireWindows(at: now)
    }

    mutating func beginTransientInteraction(at now: Date) {
        expireWindows(at: now)
        guard transientInteractionUntil == nil else { return }
        transientInteractionUntil = now.addingTimeInterval(
            Self.transientInteractionDuration
        )
    }

    mutating func beginCriticalWindow(at now: Date) {
        expireWindows(at: now)
        let candidate = now.addingTimeInterval(Self.criticalResultDuration)
        if let criticalResultUntil {
            self.criticalResultUntil = max(criticalResultUntil, candidate)
        } else {
            criticalResultUntil = candidate
        }
    }

    mutating func deferIfInteracting(
        _ update: ProxyCatalogUpdate,
        at now: Date
    ) -> Bool {
        expireWindows(at: now)
        guard !isInCriticalWindow,
              isInteracting else { return false }

        pendingUpdate = update
        if pendingDeadline == nil {
            pendingDeadline = now.addingTimeInterval(Self.maximumDeferral)
        }
        return true
    }

    mutating func takePendingUpdateIfIdle(at now: Date) -> ProxyCatalogUpdate? {
        expireWindows(at: now)
        guard !isInteracting else { return nil }
        return takePendingUpdate()
    }

    mutating func takePendingUpdateIfDue(at now: Date) -> ProxyCatalogUpdate? {
        expireWindows(at: now)
        guard let pendingDeadline,
              pendingDeadline <= now else { return nil }
        return takePendingUpdate()
    }

    mutating func takePendingUpdate() -> ProxyCatalogUpdate? {
        defer {
            pendingUpdate = nil
            pendingDeadline = nil
        }
        return pendingUpdate
    }

    mutating func clearPendingUpdate() {
        pendingUpdate = nil
        pendingDeadline = nil
    }

    mutating func reset(preservingScrollState: Bool = false) {
        if !preservingScrollState {
            scrollingRegions.removeAll(keepingCapacity: false)
        }
        transientInteractionUntil = nil
        criticalResultUntil = nil
        clearPendingUpdate()
    }

    private var isInteracting: Bool {
        !scrollingRegions.isEmpty || transientInteractionUntil != nil
    }

    private var isInCriticalWindow: Bool {
        criticalResultUntil != nil
    }

    private mutating func expireWindows(at now: Date) {
        if let transientInteractionUntil,
           transientInteractionUntil <= now {
            self.transientInteractionUntil = nil
        }
        if let criticalResultUntil,
           criticalResultUntil <= now {
            self.criticalResultUntil = nil
        }
    }
}

struct ProxyOperationActivity: Equatable {
    let switchingGroupID: String?
    let switchingSurgePolicyGroup: String?
    let measuringDelayGroupID: String?
    let testingSurgePolicyGroup: String?
    let clearingFixedGroupID: String?
    let measuringDelayNode: PolicyNodeLatencyTestTarget?

    var isActive: Bool {
        switchingGroupID != nil
            || switchingSurgePolicyGroup != nil
            || measuringDelayGroupID != nil
            || testingSurgePolicyGroup != nil
            || clearingFixedGroupID != nil
            || measuringDelayNode != nil
    }
}

enum ProxyWorkspaceLayoutMode: Equatable {
    case split
    case stacked
}

struct ProxyMasterDetailMetrics: Equatable {
    static let maximumCanvasWidth: CGFloat = 1_240
    static let minimumDirectoryWidth: CGFloat = 240
    static let maximumDirectoryWidth: CGFloat = 320
    static let minimumWorkspaceWidth: CGFloat = 360
    static let splitLayoutMinimumWidth: CGFloat = 780

    let mode: ProxyWorkspaceLayoutMode
    let canvasWidth: CGFloat
    let directoryWidth: CGFloat
    let workspaceWidth: CGFloat

    init(availableWidth: CGFloat) {
        let availableWidth = max(0, availableWidth)
        canvasWidth = min(Self.maximumCanvasWidth, availableWidth)

        guard canvasWidth >= Self.splitLayoutMinimumWidth else {
            mode = .stacked
            directoryWidth = canvasWidth
            workspaceWidth = canvasWidth
            return
        }

        mode = .split
        let preferredDirectoryWidth = min(
            Self.maximumDirectoryWidth,
            max(Self.minimumDirectoryWidth, canvasWidth * 0.28)
        )
        let availableDirectoryWidth = max(
            0,
            canvasWidth - Self.minimumWorkspaceWidth - 1
        )
        directoryWidth = min(
            preferredDirectoryWidth,
            availableDirectoryWidth
        )
        workspaceWidth = max(0, canvasWidth - directoryWidth - 1)
    }
}

struct ProxyOpenPathRibbonProjection: Equatable {
    let visible: [ProxyGroupDirectoryItem]
    let overflow: [ProxyGroupDirectoryItem]

    init(
        groups: [ProxyGroupDirectoryItem],
        maximumVisibleCount: Int
    ) {
        let count = max(0, maximumVisibleCount)
        visible = Array(groups.prefix(count))
        overflow = Array(groups.dropFirst(count))
    }
}

struct ProxyLatencyScale: Equatable {
    let maximumDelay: Int?

    init(delays: [Int?]) {
        maximumDelay = delays.compactMap { delay in
            guard let delay, delay > 0 else { return nil }
            return delay
        }.max()
    }

    func fraction(for delay: Int?) -> Double? {
        guard let delay,
              delay > 0,
              let maximumDelay,
              maximumDelay > 0 else {
            return nil
        }
        return min(1, max(0, Double(delay) / Double(maximumDelay)))
    }
}

struct ProxyGroupKey: Hashable {
    let groupID: String
    let occurrence: Int

    var rawValue: String {
        "\(groupID.utf8.count):\(groupID):\(occurrence)"
    }
}

struct ProxyGroupOccurrence: Identifiable, Equatable {
    let key: ProxyGroupKey
    let group: ProxyGroupViewState

    var id: String { key.rawValue }
}

struct ProxyMemberOccurrence: Identifiable, Equatable {
    let name: String
    let occurrence: Int

    var id: String {
        "\(name.utf8.count):\(name):\(occurrence)"
    }
}

struct ProxyGroupDirectoryItem: Identifiable, Equatable {
    let key: ProxyGroupKey
    let groupID: String
    let type: String
    let selected: String
    let memberCount: Int
    let selectedDelay: Int?
    let availableMemberCount: Int
    let latencyDistribution: ProxyLatencyDistribution
    let hidden: Bool
    let selectable: Bool
    let hasFixedSelection: Bool
    let reportedUsageRanks: [PolicyGroupUsageRank]

    var id: String { key.rawValue }
}

struct ProxyNodeRowProjection: Identifiable, Equatable {
    let id: String
    let name: String
    let occurrence: Int
    let type: String?
    let providerName: String?
    let transportNames: [String]
    let delay: Int?
    let latencyFraction: Double?
    let alive: Bool?
    let usageRank: PolicyGroupUsageRank?
    let isControllerSelected: Bool

    var subtitle: String? {
        let values = [type?.nilIfBlank, providerName?.nilIfBlank]
            .compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: " / ")
    }
}

struct ProxyLatencyDistribution: Equatable {
    let buckets: [ProxyLatencyDistributionBucket]

    init(group: ProxyGroupViewState) {
        var counts: [ProxyLatencyDistributionBucket.Kind: Int] = [:]
        for member in group.options {
            let delay = group.delays[member]
                ?? group.detail(for: member)?.latestHistoryDelay
            let kind: ProxyLatencyDistributionBucket.Kind
            guard let delay, delay > 0 else {
                counts[.unavailable, default: 0] += 1
                continue
            }
            switch LatencyHealthGrade.allCases.first(where: {
                $0.includes(delay: delay)
            }) {
            case .fast: kind = .fast
            case .normal: kind = .normal
            case .slow: kind = .slow
            case .timeout, .none: kind = .timeout
            }
            counts[kind, default: 0] += 1
        }

        let total = max(1, group.options.count)
        buckets = ProxyLatencyDistributionBucket.Kind.allCases.compactMap {
            kind in
            let count = counts[kind, default: 0]
            guard count > 0 else { return nil }
            return ProxyLatencyDistributionBucket(
                kind: kind,
                count: count,
                fraction: Double(count) / Double(total)
            )
        }
    }
}

struct ProxyLatencyDistributionBucket: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case fast
        case normal
        case slow
        case timeout
        case unavailable
    }

    let kind: Kind
    let count: Int
    let fraction: Double

    var id: String { kind.rawValue }

    var tint: Color {
        switch kind {
        case .fast: MicaDesignTokens.signalOK
        case .normal: MicaDesignTokens.signalCyan
        case .slow: MicaDesignTokens.signalWarning
        case .timeout: MicaDesignTokens.signalError
        case .unavailable: MicaDesignTokens.separator
        }
    }
}

struct ProxyMemberInteractionAvailability: Equatable {
    let canSelect: Bool
    let canTest: Bool
}

struct ProxyMemberMutationTarget: Equatable {
    let groupID: String
    let memberName: String
}

struct ProxyGroupCatalogRecord: Identifiable, Equatable {
    let occurrence: ProxyGroupOccurrence
    let directoryItem: ProxyGroupDirectoryItem
    let searchableText: String

    var id: String { occurrence.id }
}

struct ProxyNodeCatalogRecord: Identifiable, Equatable {
    let row: ProxyNodeRowProjection
    let searchableText: String

    var id: String { row.id }
}

struct ProxyGroupCatalogIndex: Equatable {
    let revision: ProxyCatalogRevision
    let visibilityRawValue: String
    let mode: String
    let arrangedGroups: [ProxyGroupOccurrence]
    let directoryItems: [ProxyGroupDirectoryItem]
    let records: [ProxyGroupCatalogRecord]

    static let empty = ProxyGroupCatalogIndex(
        revision: .zero,
        visibilityRawValue: "",
        mode: "unknown",
        arrangedGroups: [],
        directoryItems: [],
        records: []
    )

    init(
        catalog: PolicyGroupCatalogSnapshot,
        visibility: GlobalGroupVisibility,
        revision: ProxyCatalogRevision = .zero
    ) {
        let arranged = ProxyProjection.arrangedGroups(
            catalog.groups,
            mode: catalog.mode,
            visibility: visibility
        )
        let records = arranged.map { occurrence in
            ProxyGroupCatalogRecord(
                occurrence: occurrence,
                directoryItem: ProxyProjection.directoryItem(
                    for: occurrence
                ),
                searchableText: ProxyProjection.groupSearchText(
                    for: occurrence.group
                )
            )
        }
        self.init(
            revision: revision,
            visibilityRawValue: visibility.rawValue,
            mode: catalog.mode,
            arrangedGroups: arranged,
            directoryItems: records.map(\.directoryItem),
            records: records
        )
    }

    private init(
        revision: ProxyCatalogRevision,
        visibilityRawValue: String,
        mode: String,
        arrangedGroups: [ProxyGroupOccurrence],
        directoryItems: [ProxyGroupDirectoryItem],
        records: [ProxyGroupCatalogRecord]
    ) {
        self.revision = revision
        self.visibilityRawValue = visibilityRawValue
        self.mode = mode
        self.arrangedGroups = arrangedGroups
        self.directoryItems = directoryItems
        self.records = records
    }
}

struct ProxyGroupCatalogProjection: Equatable {
    let mode: String
    let arrangedGroups: [ProxyGroupOccurrence]
    let visibleGroups: [ProxyGroupOccurrence]
    let directoryItems: [ProxyGroupDirectoryItem]
    let visibleDirectoryItems: [ProxyGroupDirectoryItem]

    static let empty = ProxyGroupCatalogProjection(
        index: .empty,
        query: ""
    )

    init(
        catalog: PolicyGroupCatalogSnapshot,
        visibility: GlobalGroupVisibility,
        query: String
    ) {
        self.init(
            index: ProxyGroupCatalogIndex(
                catalog: catalog,
                visibility: visibility
            ),
            query: query
        )
    }

    init(index: ProxyGroupCatalogIndex, query: String) {
        let needle = ProxySearchText.normalize(query)
        mode = index.mode
        arrangedGroups = index.arrangedGroups
        directoryItems = index.directoryItems

        if needle.isEmpty {
            visibleGroups = index.arrangedGroups
            visibleDirectoryItems = index.directoryItems
        } else {
            let visibleRecords = index.records.filter {
                $0.searchableText.contains(needle)
            }
            visibleGroups = visibleRecords.map(\.occurrence)
            visibleDirectoryItems = visibleRecords.map(\.directoryItem)
        }
    }
}

struct ProxyActiveGroupProjection: Equatable {
    let occurrence: ProxyGroupOccurrence?
    let members: [ProxyNodeRowProjection]

    static let empty = ProxyActiveGroupProjection(
        occurrence: nil,
        members: []
    )

    init(index: ProxyActiveGroupIndex, query: String) {
        let needle = ProxySearchText.normalize(query)
        occurrence = index.occurrence
        if needle.isEmpty {
            members = index.rows
        } else {
            members = index.records
                .filter { $0.searchableText.contains(needle) }
                .map(\.row)
        }
    }

    private init(
        occurrence: ProxyGroupOccurrence?,
        members: [ProxyNodeRowProjection]
    ) {
        self.occurrence = occurrence
        self.members = members
    }
}

struct ProxyActiveGroupIndex: Equatable {
    let revision: ProxyCatalogRevision
    let occurrence: ProxyGroupOccurrence?
    let records: [ProxyNodeCatalogRecord]
    let rows: [ProxyNodeRowProjection]
    let recordsByID: [String: ProxyNodeCatalogRecord]

    static let empty = ProxyActiveGroupIndex(
        revision: .zero,
        occurrence: nil,
        records: [],
        rows: [],
        recordsByID: [:]
    )

    func reconciledSelectionID(_ selectedID: String?) -> String? {
        if let selectedID, recordsByID[selectedID] != nil {
            return selectedID
        }
        return rows.first(where: \.isControllerSelected)?.id ?? rows.first?.id
    }
}

struct ProxyCatalogProjectionWorkCounts: Equatable {
    var catalogIndexBuilds = 0
    var groupRecordsBuilt = 0
    var activeGroupIndexBuilds = 0
    var memberRowsBuilt = 0
}

struct ProxyCatalogProjectionCache {
    private struct CatalogKey: Equatable {
        let revision: ProxyCatalogRevision
        let visibilityRawValue: String
    }

    private struct ActiveGroupKey: Equatable {
        let catalog: CatalogKey
        let groupID: String?
    }

    private var catalogKey: CatalogKey?
    private var activeGroupKey: ActiveGroupKey?
    private var expandedGroupKeys: [String: ActiveGroupKey] = [:]
    private(set) var groupIndex = ProxyGroupCatalogIndex.empty
    private(set) var activeGroupIndex = ProxyActiveGroupIndex.empty
    private var expandedGroupIndexes: [String: ProxyActiveGroupIndex] = [:]
    private(set) var workCounts = ProxyCatalogProjectionWorkCounts()

    @discardableResult
    mutating func updateCatalog(
        _ catalog: PolicyGroupCatalogSnapshot,
        revision: ProxyCatalogRevision,
        visibility: GlobalGroupVisibility
    ) -> Bool {
        let nextKey = CatalogKey(
            revision: revision,
            visibilityRawValue: visibility.rawValue
        )
        guard nextKey != catalogKey else { return false }

        groupIndex = ProxyGroupCatalogIndex(
            catalog: catalog,
            visibility: visibility,
            revision: revision
        )
        catalogKey = nextKey
        activeGroupKey = nil
        activeGroupIndex = .empty
        expandedGroupKeys.removeAll(keepingCapacity: true)
        expandedGroupIndexes.removeAll(keepingCapacity: true)
        workCounts.catalogIndexBuilds += 1
        workCounts.groupRecordsBuilt += groupIndex.records.count
        return true
    }

    func groupProjection(query: String) -> ProxyGroupCatalogProjection {
        ProxyGroupCatalogProjection(index: groupIndex, query: query)
    }

    @discardableResult
    mutating func updateActiveGroup(groupID: String?) -> Bool {
        guard let catalogKey else {
            activeGroupIndex = .empty
            activeGroupKey = nil
            return false
        }
        let nextKey = ActiveGroupKey(
            catalog: catalogKey,
            groupID: groupID
        )
        guard nextKey != activeGroupKey else { return false }

        activeGroupIndex = ProxyProjection.activeGroupIndex(
            in: groupIndex.arrangedGroups,
            groupID: groupID,
            revision: groupIndex.revision
        )
        activeGroupKey = nextKey
        if activeGroupIndex.occurrence != nil {
            workCounts.activeGroupIndexBuilds += 1
            workCounts.memberRowsBuilt += activeGroupIndex.rows.count
        }
        return true
    }

    func activeProjection(query: String) -> ProxyActiveGroupProjection {
        ProxyActiveGroupProjection(index: activeGroupIndex, query: query)
    }

    @discardableResult
    mutating func updateExpandedGroups(groupIDs: [String]) -> Bool {
        guard let catalogKey else {
            let changed = !expandedGroupIndexes.isEmpty
            expandedGroupKeys.removeAll(keepingCapacity: true)
            expandedGroupIndexes.removeAll(keepingCapacity: true)
            return changed
        }

        let requestedIDs = Set(groupIDs)
        var changed = false
        let staleGroupIDs = expandedGroupIndexes.keys.filter {
            !requestedIDs.contains($0)
        }
        for groupID in staleGroupIDs {
            expandedGroupIndexes.removeValue(forKey: groupID)
            expandedGroupKeys.removeValue(forKey: groupID)
            changed = true
        }

        for groupID in groupIDs {
            let nextKey = ActiveGroupKey(
                catalog: catalogKey,
                groupID: groupID
            )
            guard expandedGroupKeys[groupID] != nextKey else { continue }

            let index = ProxyProjection.activeGroupIndex(
                in: groupIndex.arrangedGroups,
                groupID: groupID,
                revision: groupIndex.revision
            )
            guard index.occurrence != nil else {
                expandedGroupIndexes.removeValue(forKey: groupID)
                expandedGroupKeys.removeValue(forKey: groupID)
                changed = true
                continue
            }

            expandedGroupIndexes[groupID] = index
            expandedGroupKeys[groupID] = nextKey
            workCounts.activeGroupIndexBuilds += 1
            workCounts.memberRowsBuilt += index.rows.count
            changed = true
        }
        return changed
    }

    func expandedGroupIndex(for groupID: String) -> ProxyActiveGroupIndex {
        expandedGroupIndexes[groupID] ?? .empty
    }
}

struct ProxyReportedMetadataField: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let value: String

    static func fields(
        in metadata: [String: MihomoJSONValue]
    ) -> [ProxyReportedMetadataField] {
        metadata
            .sorted { $0.key < $1.key }
            .compactMap { key, value in
                guard let text = displayText(for: value) else { return nil }
                return ProxyReportedMetadataField(key: key, value: text)
            }
    }

    private static func displayText(for value: MihomoJSONValue) -> String? {
        switch value {
        case .string(let text):
            return text.isEmpty ? "\"\"" : text
        case .number(let number):
            guard number.isFinite else { return String(number) }
            if number.rounded() == number,
               number >= Double(Int64.min),
               number <= Double(Int64.max) {
                return String(Int64(number))
            }
            return String(number)
        case .bool(let enabled):
            return String(enabled)
        case .null:
            return "null"
        case .object, .array:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}

struct ProxyMemberDetailProjection: Equatable {
    let alive: Bool?
    let fixed: String?
    let history: [ProxyDelayHistorySnapshot]?
    let latestHistoryDelay: Int?
    let latestHistoryTime: String?
    let reportedFields: [ProxyReportedMetadataField]

    init(detail: ProxyNodeViewState?) {
        alive = detail?.alive
        fixed = detail?.fixed
        history = detail?.history
        latestHistoryDelay = detail?.latestHistoryDelay
        latestHistoryTime = detail?.latestHistoryTime
        reportedFields = ProxyReportedMetadataField.fields(
            in: detail?.reportedMetadata ?? [:]
        )
    }

    func availabilityText(language: AppLanguage) -> String {
        guard let alive else { return unavailableText(language: language) }
        return MicaStrings.localizedKey(
            alive ? "routing.node_alive" : "routing.node_unavailable",
            language: language
        )
    }

    func fixedSelectionText(language: AppLanguage) -> String {
        fixed?.nilIfBlank ?? unavailableText(language: language)
    }

    func historySummaryText(language: AppLanguage) -> String {
        guard let history, !history.isEmpty else {
            return unavailableText(language: language)
        }

        let delay = latestHistoryDelay.map(OverviewFormat.latency)
            ?? unavailableText(language: language)
        let time = latestHistoryTime?.nilIfBlank
            ?? unavailableText(language: language)
        return MicaStrings.localized(
            "routing.history_summary \(history.count) \(delay) \(time)",
            language: language
        )
    }

    private func unavailableText(language: AppLanguage) -> String {
        MicaStrings.localizedKey(
            "routing.node_unavailable",
            language: language
        )
    }
}

struct ProxyWorkspaceReconciliationResult: Equatable {
    let workspace: WorkbenchDestinationWorkspace
    let inspectedMemberCount: Int
}

enum ProxyWorkspaceProjection {
    static func reconciled(
        _ workspace: WorkbenchDestinationWorkspace,
        groups: [ProxyGroupOccurrence]
    ) -> WorkbenchDestinationWorkspace {
        reconciliation(workspace, groups: groups).workspace
    }

    static func reconciliation(
        _ workspace: WorkbenchDestinationWorkspace,
        groups: [ProxyGroupOccurrence]
    ) -> ProxyWorkspaceReconciliationResult {
        var next = workspace
        let orderedIDs = groups.map(\.id)
        let validIDs = Set(orderedIDs)
        let requestedOpenIDs = Set(workspace.openGroupIDs)

        next.openGroupIDs = orderedIDs.filter(requestedOpenIDs.contains)
        if let activeGroupID = workspace.activeGroupID,
           next.openGroupIDs.contains(activeGroupID) {
            next.activeGroupID = activeGroupID
        } else {
            next.activeGroupID = next.openGroupIDs.first
        }

        next.groupFilters = workspace.groupFilters.filter {
            validIDs.contains($0.key)
        }
        var selectedGroupMemberIDs = workspace.selectedGroupMemberIDs.filter {
            validIDs.contains($0.key)
        }
        var inspectedMemberCount = 0
        var staleSelectionGroupIDs: [String] = []
        for (groupID, selectedID) in selectedGroupMemberIDs {
            guard let occurrence = groups.first(where: { $0.id == groupID }) else {
                staleSelectionGroupIDs.append(groupID)
                continue
            }
            let resolution = ProxyProjection.memberResolution(
                memberID: selectedID,
                in: occurrence.group
            )
            inspectedMemberCount += resolution.inspectedCount
            if resolution.member == nil {
                staleSelectionGroupIDs.append(groupID)
            }
        }
        for groupID in staleSelectionGroupIDs {
            selectedGroupMemberIDs.removeValue(forKey: groupID)
        }
        next.selectedGroupMemberIDs = selectedGroupMemberIDs
        return ProxyWorkspaceReconciliationResult(
            workspace: next,
            inspectedMemberCount: inspectedMemberCount
        )
    }

    static func opening(
        _ groupID: String,
        in workspace: WorkbenchDestinationWorkspace,
        groups: [ProxyGroupOccurrence],
        preferredMemberID: String?
    ) -> WorkbenchDestinationWorkspace {
        guard let occurrence = groups.first(where: { $0.id == groupID }) else {
            return reconciled(workspace, groups: groups)
        }

        var next = reconciled(workspace, groups: groups)
        let requested = Set(next.openGroupIDs).union([groupID])
        next.openGroupIDs = groups.map(\.id).filter(requested.contains)
        next.activeGroupID = groupID
        if let selectedID = next.selectedGroupMemberIDs[groupID],
           ProxyProjection.memberResolution(
               memberID: selectedID,
               in: occurrence.group
           ).member == nil {
            next.selectedGroupMemberIDs.removeValue(forKey: groupID)
        }
        if next.selectedGroupMemberIDs[groupID] == nil,
           let preferredMemberID {
            next.selectedGroupMemberIDs[groupID] = preferredMemberID
        }
        return next
    }

    static func closingInspector(
        for groupID: String,
        in workspace: WorkbenchDestinationWorkspace
    ) -> WorkbenchDestinationWorkspace {
        var next = workspace
        next.selectedGroupMemberIDs.removeValue(forKey: groupID)
        return next
    }

    static func closing(
        _ groupID: String,
        in workspace: WorkbenchDestinationWorkspace,
        groups: [ProxyGroupOccurrence]
    ) -> WorkbenchDestinationWorkspace {
        var next = reconciled(workspace, groups: groups)
        guard let closingIndex = next.openGroupIDs.firstIndex(of: groupID) else {
            return next
        }

        let wasActive = next.activeGroupID == groupID
        next.openGroupIDs.remove(at: closingIndex)
        if wasActive {
            if closingIndex < next.openGroupIDs.count {
                next.activeGroupID = next.openGroupIDs[closingIndex]
            } else {
                next.activeGroupID = next.openGroupIDs.last
            }
        }
        _ = reconcileActiveSelection(in: &next, groups: groups)
        return next
    }

    static func openGroups(
        _ openGroupIDs: [String],
        in groups: [ProxyGroupDirectoryItem]
    ) -> [ProxyGroupDirectoryItem] {
        let openIDs = Set(openGroupIDs)
        return groups.filter { openIDs.contains($0.id) }
    }

    private static func reconcileActiveSelection(
        in workspace: inout WorkbenchDestinationWorkspace,
        groups: [ProxyGroupOccurrence]
    ) -> Int {
        guard let activeGroupID = workspace.activeGroupID,
              let selectedID = workspace.selectedGroupMemberIDs[activeGroupID],
              let occurrence = groups.first(where: { $0.id == activeGroupID }) else {
            return 0
        }

        let resolution = ProxyProjection.memberResolution(
            memberID: selectedID,
            in: occurrence.group
        )
        if resolution.member == nil {
            workspace.selectedGroupMemberIDs.removeValue(forKey: activeGroupID)
        }
        return resolution.inspectedCount
    }
}

struct ProxyMemberResolution: Equatable {
    let member: ProxyMemberOccurrence?
    let inspectedCount: Int
}

enum ProxyProjection {
    static func memberInteractions(
        in group: ProxyGroupViewState,
        selectionActionAvailable: Bool,
        testActionAvailable: Bool
    ) -> ProxyMemberInteractionAvailability {
        ProxyMemberInteractionAvailability(
            canSelect: selectionActionAvailable && group.selectable,
            canTest: testActionAvailable
        )
    }

    static func arrangedGroups(
        _ groups: [ProxyGroupViewState],
        mode: String,
        visibility: GlobalGroupVisibility
    ) -> [ProxyGroupOccurrence] {
        let occurrences = occurrences(in: groups)
        let globalGroups = occurrences.filter {
            $0.group.id.caseInsensitiveCompare("GLOBAL") == .orderedSame
        }
        let peers = occurrences.filter {
            $0.group.id.caseInsensitiveCompare("GLOBAL") != .orderedSame
        }

        let showsGlobal = visibility == .alwaysShow
            || mode.caseInsensitiveCompare("Global") == .orderedSame
        return showsGlobal ? peers + globalGroups : peers
    }

    static func filteredGroups(
        _ groups: [ProxyGroupOccurrence],
        query: String
    ) -> [ProxyGroupOccurrence] {
        let needle = ProxySearchText.normalize(query)
        guard !needle.isEmpty else { return groups }
        return groups.filter { groupSearchText(for: $0.group).contains(needle) }
    }

    static func members(
        in group: ProxyGroupViewState,
        query: String
    ) -> [ProxyMemberOccurrence] {
        let needle = ProxySearchText.normalize(query)
        let members = memberOccurrences(in: group)
        guard !needle.isEmpty else { return members }

        return members.filter { member in
            ProxySearchText.normalize(member.name).contains(needle)
                || group.detail(for: member.name)?.searchableText.contains(needle) == true
        }
    }

    static func activeGroupIndex(
        in groups: [ProxyGroupOccurrence],
        groupID: String?,
        revision: ProxyCatalogRevision = .zero
    ) -> ProxyActiveGroupIndex {
        guard let groupID,
              let occurrence = groups.first(where: { $0.id == groupID }) else {
            return ProxyActiveGroupIndex(
                revision: revision,
                occurrence: nil,
                records: [],
                rows: [],
                recordsByID: [:]
            )
        }

        let baseRows = memberOccurrences(in: occurrence.group).map { member in
            let detail = occurrence.group.detail(for: member.name)
            return ProxyNodeRowProjection(
                id: member.id,
                name: member.name,
                occurrence: member.occurrence,
                type: detail?.type,
                providerName: detail?.providerName,
                transportNames: detail?.transportNames ?? [],
                delay: occurrence.group.delays[member.name]
                    ?? detail?.latestHistoryDelay,
                latencyFraction: nil,
                alive: detail?.alive,
                usageRank: occurrence.group.usageRank(for: member.name),
                isControllerSelected: occurrence.group.selected == member.name
            )
        }
        let latencyScale = ProxyLatencyScale(
            delays: baseRows.map(\.delay)
        )
        let records = baseRows.map { base in
            let row = ProxyNodeRowProjection(
                id: base.id,
                name: base.name,
                occurrence: base.occurrence,
                type: base.type,
                providerName: base.providerName,
                transportNames: base.transportNames,
                delay: base.delay,
                latencyFraction: latencyScale.fraction(for: base.delay),
                alive: base.alive,
                usageRank: base.usageRank,
                isControllerSelected: base.isControllerSelected
            )
            return ProxyNodeCatalogRecord(
                row: row,
                searchableText: occurrence.group.detail(
                    for: base.name
                )?.searchableText
                    ?? ProxySearchText.normalize(base.name)
            )
        }

        return ProxyActiveGroupIndex(
            revision: revision,
            occurrence: occurrence,
            records: records,
            rows: records.map(\.row),
            recordsByID: Dictionary(
                uniqueKeysWithValues: records.map { ($0.id, $0) }
            )
        )
    }

    static func activeGroup(
        in groups: [ProxyGroupOccurrence],
        groupID: String?,
        query: String
    ) -> ProxyActiveGroupProjection {
        ProxyActiveGroupProjection(
            index: activeGroupIndex(
                in: groups,
                groupID: groupID
            ),
            query: query
        )
    }

    static func preferredMemberID(in group: ProxyGroupViewState) -> String? {
        var counts: [String: Int] = [:]
        var firstMemberID: String?

        for name in group.options {
            let occurrence = counts[name, default: 0]
            counts[name] = occurrence + 1
            let member = ProxyMemberOccurrence(
                name: name,
                occurrence: occurrence
            )
            if firstMemberID == nil {
                firstMemberID = member.id
            }
            if name == group.selected {
                return member.id
            }
        }
        return firstMemberID
    }

    static func memberMutationTarget(
        groupID: String,
        memberID: String,
        index: ProxyActiveGroupIndex,
        actionAvailable: Bool,
        requiresSelectableGroup: Bool
    ) -> ProxyMemberMutationTarget? {
        guard actionAvailable,
              let occurrence = index.occurrence,
              occurrence.id == groupID,
              !requiresSelectableGroup || occurrence.group.selectable,
              let record = index.recordsByID[memberID] else {
            return nil
        }

        return ProxyMemberMutationTarget(
            groupID: occurrence.group.id,
            memberName: record.row.name
        )
    }

    static func currentMemberMutationTarget(
        groupID: String,
        memberID: String,
        index: ProxyActiveGroupIndex,
        selectedControllerID: RouterProfile.ID?,
        sessionControllerID: RouterProfile.ID?,
        generation: UUID,
        actionAvailable: Bool,
        requiresSelectableGroup: Bool
    ) -> ProxyMemberMutationTarget? {
        guard index.revision.isCurrent(
            selectedControllerID: selectedControllerID,
            sessionControllerID: sessionControllerID,
            generation: generation
        ) else {
            return nil
        }
        return memberMutationTarget(
            groupID: groupID,
            memberID: memberID,
            index: index,
            actionAvailable: actionAvailable,
            requiresSelectableGroup: requiresSelectableGroup
        )
    }

    static func memberMutationTarget(
        groupID: String,
        memberID: String,
        groups: [ProxyGroupOccurrence],
        actionAvailable: Bool,
        requiresSelectableGroup: Bool
    ) -> ProxyMemberMutationTarget? {
        guard actionAvailable,
              let occurrence = groups.first(where: { $0.id == groupID }),
              !requiresSelectableGroup || occurrence.group.selectable,
              let member = memberResolution(
                memberID: memberID,
                in: occurrence.group
              ).member else {
            return nil
        }

        return ProxyMemberMutationTarget(
            groupID: occurrence.group.id,
            memberName: member.name
        )
    }

    static func memberResolution(
        memberID: String,
        in group: ProxyGroupViewState
    ) -> ProxyMemberResolution {
        var counts: [String: Int] = [:]
        var inspectedCount = 0

        for name in group.options {
            inspectedCount += 1
            let occurrence = counts[name, default: 0]
            counts[name] = occurrence + 1
            let member = ProxyMemberOccurrence(
                name: name,
                occurrence: occurrence
            )
            if member.id == memberID {
                return ProxyMemberResolution(
                    member: member,
                    inspectedCount: inspectedCount
                )
            }
        }

        return ProxyMemberResolution(
            member: nil,
            inspectedCount: inspectedCount
        )
    }

    static func directoryItem(
        for occurrence: ProxyGroupOccurrence
    ) -> ProxyGroupDirectoryItem {
        ProxyGroupDirectoryItem(
            key: occurrence.key,
            groupID: occurrence.group.id,
            type: occurrence.group.type,
            selected: occurrence.group.selected,
            memberCount: occurrence.group.options.count,
            selectedDelay: occurrence.group.delays[occurrence.group.selected]
                ?? occurrence.group.detail(
                    for: occurrence.group.selected
                )?.latestHistoryDelay,
            availableMemberCount: occurrence.group.options.reduce(into: 0) {
                count, member in
                if occurrence.group.detail(for: member)?.alive != false {
                    count += 1
                }
            },
            latencyDistribution: ProxyLatencyDistribution(
                group: occurrence.group
            ),
            hidden: occurrence.group.hidden,
            selectable: occurrence.group.selectable,
            hasFixedSelection: occurrence.group.details?.fixed?.nilIfBlank != nil,
            reportedUsageRanks: reportedUsageRanks(in: occurrence.group)
        )
    }

    static func reportedUsageRanks(
        in group: ProxyGroupViewState
    ) -> [PolicyGroupUsageRank] {
        var result: [PolicyGroupUsageRank] = []
        for member in group.options {
            guard let rank = group.usageRank(for: member),
                  !result.contains(rank) else { continue }
            result.append(rank)
        }
        return result
    }

    static func groupSearchText(for group: ProxyGroupViewState) -> String {
        var values = [
            ProxySearchText.normalize(group.id),
            ProxySearchText.normalize(group.type),
            ProxySearchText.normalize(group.selected),
        ]
        values.reserveCapacity(values.count + (group.options.count * 2))

        for member in group.options {
            values.append(ProxySearchText.normalize(member))
            if let detail = group.detail(for: member) {
                values.append(detail.searchableText)
            }
        }
        return values.joined(separator: " ")
    }

    private static func occurrences(
        in groups: [ProxyGroupViewState]
    ) -> [ProxyGroupOccurrence] {
        var counts: [String: Int] = [:]

        return groups.map { group in
            let occurrence = counts[group.id, default: 0]
            counts[group.id] = occurrence + 1
            return ProxyGroupOccurrence(
                key: ProxyGroupKey(
                    groupID: group.id,
                    occurrence: occurrence
                ),
                group: group
            )
        }
    }

    private static func memberOccurrences(
        in group: ProxyGroupViewState
    ) -> [ProxyMemberOccurrence] {
        var counts: [String: Int] = [:]

        return group.options.map { name in
            let occurrence = counts[name, default: 0]
            counts[name] = occurrence + 1
            return ProxyMemberOccurrence(
                name: name,
                occurrence: occurrence
            )
        }
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
