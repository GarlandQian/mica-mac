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

enum ProxyListLayoutMode: String, CaseIterable, Equatable, Sendable {
    case list
    case grid
}

private enum ProxyWorkspaceFilterKey {
    static let healthFilter = "healthFilter"
    static let memberOrder = "memberOrder"
    static let layoutMode = "layoutMode"
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

struct ProxyCatalogObservationRequest: Equatable, Sendable {
    let controllerID: RouterProfile.ID?
    let generation: UUID
    let revision: UInt64

    func belongsToSameSession(as other: Self) -> Bool {
        controllerID == other.controllerID && generation == other.generation
    }

    func matches(controllerID: RouterProfile.ID?, generation: UUID) -> Bool {
        self.controllerID == controllerID && self.generation == generation
    }

    func owns(_ selection: WorkbenchProxyNavigationSelection) -> Bool {
        matches(
            controllerID: selection.controllerID,
            generation: selection.generation
        )
    }

    func owns(_ reveal: WorkbenchProxyNavigationReveal) -> Bool {
        matches(controllerID: reveal.controllerID, generation: reveal.generation)
    }
}

struct WorkbenchPolicyGroupsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @EnvironmentObject private var preferences: AppPreferencesStore
    @Environment(\.micaAppLanguage) private var language

    @Binding var searchText: String

    @State private var model = ProxyWorkspaceModel()
    @State private var presentationCoordinator = ProxyCatalogPresentationCoordinator()
    @State private var scrollInteractionTracker = ProxyScrollInteractionTracker()
    @State private var hoverPreview = ProxyNodeHoverState()
    @State private var reveal: WorkbenchProxyNavigationReveal?
    @State private var lastScrolledRevealToken: UUID?
    @State private var pendingNavigation: WorkbenchProxyNavigationSelection?
    @State private var revealObstruction: WorkbenchProxyRevealObstruction?
    @State private var unresolvedReason: WorkbenchProxyUnresolvedReason?
    @FocusState private var isNodeSearchFocused: Bool

    var body: some View {
        let _ = MicaPerformanceObservation.recordDebug(.proxyPageEvaluation)
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
        .overlay(alignment: .topLeading) {
            ProxyPolicyCatalogObserver(
                onSessionBoundary: resetCatalogPresentationForSessionBoundary,
                onCatalog: receiveCatalog
            )
        }
        .background {
            if model.activeGroup != nil {
                Button("") {
                    isNodeSearchFocused = true
                }
                .keyboardShortcut("f", modifiers: .command)
                .labelsHidden()
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            }
        }
        .onExitCommand(perform: handleEscapeKey)
        .onAppear {
            synchronizePresentation()
            consumePendingProxyNavigation()
        }
        .onDisappear {
            scrollInteractionTracker.reset(coordinator: presentationCoordinator)
            hoverPreview.reset()
        }
        .onChange(of: model.activeGroup?.id) { _, _ in
            hoverPreview.reset()
        }
        .onChange(of: presentationInput) { _, _ in
            synchronizePresentation()
            resolveReveal()
        }
        .onChange(of: workspace.pendingProxySelection) { _, _ in
            consumePendingProxyNavigation()
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
                value: model.groupProjection.visibleGroups.count.formatted(),
                detail: groupVisibilitySummary
            )
        } controls: {
            WorkbenchStatusBadge(
                text: modeBadgeText,
                tint: MicaTheme.textSecondary
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if let revealObstruction {
                WorkbenchProxyRevealObstructionNotice(
                    obstruction: revealObstruction,
                    nodeName: reveal?.nodeName ?? pendingNavigation?.nodeName ?? "",
                    recoverAndLocate: recoverRevealObstruction
                )
            }
            if let unresolvedReason, let pendingNavigation {
                WorkbenchProxyUnresolvedNotice(
                    nodeName: pendingNavigation.nodeName,
                    reason: unresolvedReason
                )
            }
            if model.groupProjection.arrangedGroups.isEmpty {
                emptyState
            } else {
                HSplitView {
                    groupDirectory
                        .frame(minWidth: 196, idealWidth: 224, maxWidth: 300)
                    Group {
                        if let presentation = model.activeGroup {
                            activeGroupWorkspace(presentation)
                                .id(presentation.id)
                        } else {
                            noMatchingGroupsState
                        }
                    }
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var groupDirectory: some View {
        let scope = currentCommandScope
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .micaThemeFont(.caption, weight: .medium)
                    .foregroundStyle(MicaTheme.textTertiary)
                    .accessibilityHidden(true)
                TextField(
                    MicaStrings.localizedKey("routing.search_groups", language: language),
                    text: $searchText
                )
                .textFieldStyle(.plain)
                .micaThemeFont(.label)
                .accessibilityLabel(MicaStrings.localizedKey("routing.search_groups", language: language))
                if !searchText.isEmpty {
                    Button {
                        clearDirectoryQuery()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .micaThemeFont(.caption)
                            .foregroundStyle(MicaTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(MicaStrings.localizedKey("action.clear_search", language: language))
                    .help(MicaStrings.localizedKey("action.clear_search", language: language))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(MicaTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(MicaTheme.surfaceBorder, lineWidth: MicaTheme.Shape.hairline)
            }
            .padding(MicaTheme.Spacing.space2)

            if model.groupProjection.visibleDirectoryItems.isEmpty {
                noMatchingGroupsState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(model.groupProjection.visibleDirectoryItems) { item in
                                ProxyPolicyGroupDirectoryRow(
                                    item: item,
                                    isActive: workspace.activeGroupID == item.id
                                ) {
                                    guard let scope else { return }
                                    activateAccessibilityGroup(item.id, scope: scope)
                                }
                                .id(item.id)
                            }
                        }
                        .padding(.vertical, MicaTheme.Spacing.space1)
                    }
                    .accessibilityRepresentation {
                        accessibilityCatalog(index: model.directoryAccessibilityIndex, regionLabelKey: "routing.group_catalog")
                    }
                    .proxyScrollInteraction(
                        in: .directory,
                        coordinator: presentationCoordinator,
                        tracker: scrollInteractionTracker
                    )
                    .onChange(of: workspace.activeGroupID) { _, groupID in
                        if let groupID { proxy.scrollTo(groupID, anchor: .center) }
                    }
                }
            }
        }
        .background(MicaTheme.surface)
    }

    private func activeGroupWorkspace(_ presentation: ProxyActiveGroupPresentation) -> some View {
        let scope = currentCommandScope
        let memberQueryBinding = Binding(
            get: { workspace.proxyMemberQuery },
            set: {
                guard let scope, appModel.matchesCurrentCommandScope(scope) else { return }
                setGroupFilter($0, for: presentation.id)
            }
        )
        let memberSearchField = HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .micaThemeFont(.caption, weight: .medium)
                .foregroundStyle(MicaTheme.textTertiary)
                .accessibilityHidden(true)
            TextField(
                MicaStrings.localizedKey("routing.search_active_nodes", language: language),
                text: memberQueryBinding
            )
            .textFieldStyle(.plain)
            .micaThemeFont(.label)
            .focused($isNodeSearchFocused)
            .accessibilityLabel(MicaStrings.localizedKey("routing.search_active_nodes", language: language))
            if !workspace.proxyMemberQuery.isEmpty {
                Button {
                    setGroupFilter("", for: presentation.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .micaThemeFont(.caption)
                        .foregroundStyle(MicaTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MicaStrings.localizedKey("action.clear_search", language: language))
                .help(MicaStrings.localizedKey("action.clear_search", language: language))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(MicaTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(MicaTheme.surfaceBorder, lineWidth: MicaTheme.Shape.hairline)
        }
        .frame(minWidth: 140)
        .layoutPriority(1)

        let filterControls = HStack(spacing: MicaTheme.Spacing.space2) {
            healthFilterPicker
            memberOrderPicker
            layoutModePicker
            ViewThatFits(in: .horizontal) {
                memberCount(presentation, compact: false)
                memberCount(presentation, compact: true)
            }
            .help(MicaStrings.localized(
                "routing.member_window \(presentation.members.count) \(presentation.item.memberCount)",
                language: language
            ))
        }

        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                ProxyPolicyActiveGroupHeader(
                    presentation: presentation,
                    commandsEnabled: liveCommandsAvailable,
                    canTestGroup: canTestGroup,
                    onTestGroup: {
                        guard let scope else { return }
                        testGroup(presentation.id, scope: scope)
                    },
                    onClearFixed: {
                        guard let scope else { return }
                        clearFixedSelection(in: presentation.id, scope: scope)
                    },
                    onLocateCurrent: {
                        guard let scope else { return }
                        locateAccessibilityCurrentNode(in: presentation.id, scope: scope)
                    }
                )
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: MicaTheme.Spacing.space2) {
                        memberSearchField
                        filterControls
                    }
                    VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                        memberSearchField
                        filterControls
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, MicaTheme.Spacing.space3)
                .padding(.bottom, MicaTheme.Spacing.space2)
            }
            .background(MicaTheme.surface)

            MicaHairlineSeparator()
            nodeList(presentation)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func nodeList(_ presentation: ProxyActiveGroupPresentation) -> some View {
        ScrollViewReader { proxy in
            Group {
                if presentation.members.isEmpty {
                    nodeEmptyState(presentation)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(MicaTheme.canvas)
                } else {
                    ScrollView {
                        if layoutMode == .grid {
                            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space3) {
                                if let inspectedID = presentation.inspectedMemberID,
                                   let inspectedMember = presentation.members.first(where: { $0.id == inspectedID }) {
                                    gridInspectedPanel(inspectedMember, in: presentation)
                                }
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: MicaTheme.Spacing.space2)],
                                    spacing: MicaTheme.Spacing.space2
                                ) {
                                    ForEach(presentation.members) { member in
                                        nodeGridCard(member, in: presentation)
                                            .id(ProxyProjection.revealTargetID(
                                                groupID: presentation.id, memberID: member.id
                                            ))
                                    }
                                }
                            }
                            .padding(MicaTheme.Spacing.space3)
                        } else {
                            LazyVStack(spacing: MicaTheme.Spacing.space1 / 2) {
                                ForEach(presentation.members) { member in
                                    let isInspected = presentation.inspectedMemberID == member.id
                                    VStack(spacing: 0) {
                                        nodeRow(member, in: presentation)
                                        if isInspected {
                                            MicaHairlineSeparator()
                                            inlineDetails(member, in: presentation)
                                        }
                                    }
                                    .modifier(ProxyInspectedNodeFrame(isInspected: isInspected))
                                    .id(ProxyProjection.revealTargetID(
                                        groupID: presentation.id, memberID: member.id
                                    ))
                                }
                            }
                            .padding(MicaTheme.Spacing.space2)
                        }
                    }
                    .background(MicaTheme.canvas)
                    .proxyScrollInteraction(
                        in: .nodes,
                        coordinator: presentationCoordinator,
                        tracker: scrollInteractionTracker
                    )
                    .overlayPreferenceValue(ProxyNodePreviewAnchorKey.self) { anchors in
                        if layoutMode == .list {
                            ProxyNodeHoverOverlay(
                                state: hoverPreview,
                                scrollInteractionTracker: scrollInteractionTracker,
                                presentation: presentation,
                                anchors: anchors
                            )
                        }
                    }
                    .task(id: reveal) {
                        guard let reveal else { return }
                        await Task.yield()
                        guard !Task.isCancelled,
                              self.reveal?.token == reveal.token,
                              reveal.groupID == presentation.id,
                              reveal.isCurrent(
                                controllerID: appModel.selectedRouterID,
                                generation: appModel.controllerSessionPresentation.generation
                              ) else { return }
                        if lastScrolledRevealToken != reveal.token {
                            proxy.scrollTo(reveal.targetID, anchor: .top)
                            lastScrolledRevealToken = reveal.token
                        }
                        try? await Task.sleep(for: .milliseconds(900))
                        guard !Task.isCancelled, self.reveal?.token == reveal.token else { return }
                        self.reveal = nil
                    }
                }
            }
            .accessibilityRepresentation {
                if presentation.members.isEmpty {
                    nodeEmptyState(presentation)
                } else {
                    VStack(spacing: 0) {
                        accessibilityCatalog(index: model.accessibilityIndex, regionLabelKey: "routing.members_loaded")
                        if let selectedID = presentation.inspectedMemberID,
                           let member = presentation.members.first(where: { $0.id == selectedID }) {
                            inlineDetails(member, in: presentation)
                        }
                    }
                }
            }
        }
    }

    private func nodeEmptyState(_ presentation: ProxyActiveGroupPresentation) -> some View {
        let hasActiveFilters = presentation.filter.proxyNonBlank != nil || healthFilter != .all
        let clearAction: (() -> Void)? = hasActiveFilters ? { clearMemberFilters(for: presentation.id) } : nil
        return WorkbenchStateView(
            kind: .filterEmpty,
            titleKey: hasActiveFilters ? "routing.members_filtered_empty" : "routing.members_empty",
            actionTitleKey: hasActiveFilters ? "dashboard.clear_filter" : nil,
            actionSystemImage: "xmark.circle",
            action: clearAction
        )
    }

    private func gridInspectedPanel(
        _ member: ProxyNodeRowProjection,
        in presentation: ProxyActiveGroupPresentation
    ) -> some View {
        let scope = currentCommandScope
        return VStack(spacing: 0) {
            HStack(spacing: MicaTheme.Spacing.space2) {
                Circle()
                    .fill(MicaTheme.accent)
                    .frame(width: 7, height: 7)
                Text(verbatim: member.name)
                    .micaThemeFont(.body, weight: .semibold)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    guard let scope else { return }
                    _ = inspectMember(member.id, in: presentation.id, scope: scope)
                } label: {
                    Image(systemName: "xmark")
                        .micaThemeFont(.caption, weight: .semibold)
                        .foregroundStyle(MicaTheme.textSecondary)
                }
                .buttonStyle(.borderless)
                .help(MicaStrings.localizedKey("routing.collapse_details", language: language))
                .accessibilityLabel(MicaStrings.localizedKey("routing.collapse_details", language: language))
            }
            .padding(.horizontal, MicaTheme.Spacing.space3)
            .padding(.vertical, MicaTheme.Spacing.space2)
            .background(MicaTheme.accent.opacity(0.10))

            MicaHairlineSeparator()
            inlineDetails(member, in: presentation)
        }
        .background(MicaTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: MicaTheme.Shape.rowRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: MicaTheme.Shape.rowRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MicaTheme.Shape.rowRadius, style: .continuous)
                .strokeBorder(MicaTheme.accent.opacity(0.45), lineWidth: MicaTheme.Shape.hairline)
        }
    }

    private func nodeRow(
        _ member: ProxyNodeRowProjection,
        in presentation: ProxyActiveGroupPresentation
    ) -> some View {
        let scope = currentCommandScope
        return ProxyPolicyNodeTile(
            member: member,
            scrollInteractionTracker: scrollInteractionTracker,
            isInspected: presentation.inspectedMemberID == member.id,
            isHighlighted: reveal?.groupID == presentation.id && reveal?.memberID == member.id,
            commandsEnabled: liveCommandsAvailable,
            canSelect: canSelectMember && presentation.occurrence.group.selectable,
            canTest: canTestNode,
            isSwitching: presentation.isSwitching,
            isMeasuring: proxyOperationActivity.isMeasuring(
                groupID: presentation.occurrence.group.id, nodeName: member.name
            ),
            isClearingFixed: presentation.isClearingFixed,
            onSelect: {
                guard let scope else { return }
                selectMember(member.id, in: presentation.id, scope: scope)
            },
            onInspect: {
                guard let scope else { return }
                _ = inspectMember(member.id, in: presentation.id, scope: scope)
            },
            onTest: {
                guard let scope else { return }
                testMember(member.id, in: presentation.id, scope: scope)
            },
            onHoverChanged: { isHovered in
                hoverPreview.setHovered(member.id, isHovered: isHovered)
            }
        )
    }

    private func nodeGridCard(
        _ member: ProxyNodeRowProjection,
        in presentation: ProxyActiveGroupPresentation
    ) -> some View {
        let scope = currentCommandScope
        return ProxyPolicyNodeGridCard(
            member: member,
            scrollInteractionTracker: scrollInteractionTracker,
            isInspected: presentation.inspectedMemberID == member.id,
            isHighlighted: reveal?.groupID == presentation.id && reveal?.memberID == member.id,
            commandsEnabled: liveCommandsAvailable,
            canSelect: canSelectMember && presentation.occurrence.group.selectable,
            canTest: canTestNode,
            isSwitching: presentation.isSwitching,
            isMeasuring: proxyOperationActivity.isMeasuring(
                groupID: presentation.occurrence.group.id, nodeName: member.name
            ),
            isClearingFixed: presentation.isClearingFixed,
            onSelect: {
                guard let scope else { return }
                selectMember(member.id, in: presentation.id, scope: scope)
            },
            onInspect: {
                guard let scope else { return }
                _ = inspectMember(member.id, in: presentation.id, scope: scope)
            },
            onTest: {
                guard let scope else { return }
                testMember(member.id, in: presentation.id, scope: scope)
            }
        )
    }

    private func inlineDetails(
        _ member: ProxyNodeRowProjection,
        in presentation: ProxyActiveGroupPresentation
    ) -> some View {
        ProxyInlineNodeDetails(
            snapshot: ProxyNodeInspectionProjection.snapshot(
                member: member, in: presentation.occurrence, language: language
            ),
            history: ProxyNodeInspectionProjection.history(
                member: member, in: presentation.occurrence
            )
        )
        .id(ProxyNodeDetailIdentity(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation,
            groupID: presentation.id,
            memberID: member.id
        ))
    }

    private var currentCommandScope: LiveCommandScope? {
        LiveCommandScope(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
    }

    private func accessibilityCatalog(
        index: ProxyAccessibilityIndex,
        regionLabelKey: String = "routing.group_catalog"
    ) -> some View {
        ProxyBoundedAccessibilityCatalog(
            index: index,
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation,
            selectedElementID: index.selectedElementID(
                activeGroupID: workspace.activeGroupID,
                selectedMemberID: workspace.inspectedProxyMemberID
            ),
            activeGroupID: workspace.activeGroupID,
            inspectedMemberID: workspace.inspectedProxyMemberID,
            commandsEnabled: liveCommandsAvailable,
            canSelectMember: canSelectMember,
            canTestGroup: canTestGroup,
            canTestNode: canTestNode,
            canClearFixedSelection: appModel.supportsUnifiedAction(.clearFixedSelection),
            activity: proxyOperationActivity,
            onActivateGroup: { groupID, scope in
                activateAccessibilityGroup(groupID, scope: scope)
            },
            onLocateCurrent: { groupID, scope in
                locateAccessibilityCurrentNode(in: groupID, scope: scope)
            },
            onTestGroup: { groupID, scope in testGroup(groupID, scope: scope) },
            onClearFixed: { groupID, scope in clearFixedSelection(in: groupID, scope: scope) },
            onSelectMember: { groupID, memberID, scope in
                selectMember(memberID, in: groupID, scope: scope)
            },
            onInspectMember: { groupID, memberID, scope in
                _ = inspectMember(memberID, in: groupID, scope: scope)
            },
            onTestMember: { groupID, memberID, scope in
                testMember(memberID, in: groupID, scope: scope)
            }
        )
        .accessibilityLabel(MicaStrings.localizedKey(regionLabelKey, language: language))
    }

    private var noMatchingGroupsState: some View {
        let clearAction: (() -> Void)? = searchText.isEmpty ? nil : { clearDirectoryQuery() }
        return WorkbenchStateView(
            kind: .filterEmpty,
            titleKey: "dashboard.no_matching_groups",
            detailKey: "dashboard.no_matching_groups_hint",
            actionTitleKey: searchText.isEmpty ? nil : "action.clear_search",
            actionSystemImage: "xmark.circle",
            action: clearAction
        )
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
                message: message,
                actionTitleKey: "action.refresh",
                isActionEnabled: appModel.canRefreshSelectedRouter,
                action: appModel.refreshSelectedRouter
            )
        default:
            break
        }

        if appModel.controllerSessionPresentation.state == .live,
           !model.hasAcceptedCatalog {
            return WorkbenchStateView(
                kind: .loading,
                titleKey: "routing.groups_loading",
                detailKey: "routing.groups_loading_detail"
            )
        }

        if !appModel.selectedUnifiedCapabilities.policyGroups {
            return WorkbenchStateView(
                kind: .unsupported,
                titleKey: "routing.groups_unsupported_title",
                detailKey: "routing.groups_unsupported_detail"
            )
        }

        if !model.catalog.groups.isEmpty {
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

    private var healthFilter: ProxyHealthFilter {
        workspace.filters[ProxyWorkspaceFilterKey.healthFilter].flatMap(ProxyHealthFilter.init(rawValue:)) ?? .all
    }

    private var healthFilterBinding: Binding<ProxyHealthFilter> {
        Binding(
            get: { healthFilter },
            set: { setHealthFilter($0) }
        )
    }

    private var memberOrder: ProxyMemberOrder {
        workspace.filters[ProxyWorkspaceFilterKey.memberOrder].flatMap(ProxyMemberOrder.init(rawValue:)) ?? .controller
    }

    private var memberOrderBinding: Binding<ProxyMemberOrder> {
        Binding(
            get: { memberOrder },
            set: { setMemberOrder($0) }
        )
    }

    private var layoutMode: ProxyListLayoutMode {
        workspace.filters[ProxyWorkspaceFilterKey.layoutMode].flatMap(ProxyListLayoutMode.init(rawValue:)) ?? .list
    }

    private var layoutModeBinding: Binding<ProxyListLayoutMode> {
        Binding(
            get: { layoutMode },
            set: { setLayoutMode($0) }
        )
    }

    private func setHealthFilter(_ filter: ProxyHealthFilter) {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { stored in
            stored.filters[ProxyWorkspaceFilterKey.healthFilter] = filter == .all ? nil : filter.rawValue
        }
    }

    private func setMemberOrder(_ order: ProxyMemberOrder) {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { stored in
            stored.filters[ProxyWorkspaceFilterKey.memberOrder] = order == .controller ? nil : order.rawValue
        }
    }

    private func setLayoutMode(_ mode: ProxyListLayoutMode) {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { stored in
            stored.filters[ProxyWorkspaceFilterKey.layoutMode] = mode == .list ? nil : mode.rawValue
        }
    }

    private func clearDirectoryQuery() {
        searchText = ""
    }

    private func clearMemberFilters(for groupID: String) {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { stored in
            stored.proxyMemberQuery = ""
            stored.filters[ProxyWorkspaceFilterKey.healthFilter] = nil
        }
    }

    private func handleEscapeKey() {
        if revealObstruction != nil || unresolvedReason != nil {
            dismissPendingReveal()
            return
        }
        if !workspace.proxyMemberQuery.isEmpty {
            workspaceStore.update(controllerID: appModel.selectedRouterID, destination: .proxies) {
                $0.proxyMemberQuery = ""
            }
            return
        }
        if healthFilter != .all {
            setHealthFilter(.all)
            return
        }
        if workspace.inspectedProxyMemberID != nil {
            workspaceStore.update(controllerID: appModel.selectedRouterID, destination: .proxies) {
                $0.inspectedProxyMemberID = nil
            }
            return
        }
        if !searchText.isEmpty {
            clearDirectoryQuery()
        }
    }

    private var healthFilterPicker: some View {
        Picker(
            MicaStrings.localizedKey(
                "routing.health_filter",
                language: language
            ),
            selection: healthFilterBinding
        ) {
            ForEach(ProxyHealthFilter.allCases, id: \.rawValue) { filter in
                Text(verbatim: filterTitleWithCount(filter))
                    .tag(filter)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .labelsHidden()
        .accessibilityLabel(
            MicaStrings.localizedKey(
                "routing.health_filter",
                language: language
            )
        )
        .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
    }

    private func memberCount(_ presentation: ProxyActiveGroupPresentation, compact: Bool) -> some View {
        Text(
            compact
                ? "\(presentation.members.count)/\(presentation.item.memberCount)"
                : MicaStrings.localized(
                    "routing.member_window \(presentation.members.count) \(presentation.item.memberCount)",
                    language: language
                )
        )
        .micaThemeFont(.caption)
        .monospacedDigit()
        .foregroundStyle(MicaTheme.textTertiary)
        .fixedSize()
    }

    private var layoutModePicker: some View {
        Picker(
            MicaStrings.localizedKey("routing.list_layout", language: language),
            selection: layoutModeBinding
        ) {
            Label(
                MicaStrings.localizedKey("routing.list_layout", language: language),
                systemImage: "list.bullet"
            )
            .labelStyle(.iconOnly)
            .tag(ProxyListLayoutMode.list)

            Label(
                MicaStrings.localizedKey("routing.grid_layout", language: language),
                systemImage: "square.grid.2x2"
            )
            .labelStyle(.iconOnly)
            .tag(ProxyListLayoutMode.grid)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .controlSize(.small)
    }

    /// Latency sorting is a view of the filtered members; selection, tests,
    /// and the controller catalog keep the reported order. The icon shows the
    /// active order so the control stays narrow.
    private var memberOrderPicker: some View {
        let title = MicaStrings.localizedKey("routing.member_order", language: language)
        let current = MicaStrings.localizedKey(memberOrder.titleKey, language: language)

        return Menu {
            Picker(title, selection: memberOrderBinding) {
                ForEach(ProxyMemberOrder.allCases, id: \.rawValue) { order in
                    Label(
                        MicaStrings.localizedKey(order.titleKey, language: language),
                        systemImage: order.systemImage
                    )
                    .tag(order)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(title, systemImage: memberOrder.systemImage)
                .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .menuIndicator(.visible)
        .tint(memberOrder == .controller ? nil : MicaTheme.accent)
        .fixedSize()
        .help(MicaStrings.localized("format.label_value \(title) \(current)", language: language))
        .accessibilityLabel(title)
        .accessibilityValue(current)
        .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
    }

    private var workspace: WorkbenchDestinationWorkspace {
        workspaceStore.workspace(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        )
    }

    private var presentationInput: ProxyWorkspacePresentationInput {
        ProxyWorkspacePresentationInput(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation,
            workspace: workspace,
            query: searchText,
            visibility: preferences.globalGroupVisibility,
            healthFilter: healthFilter,
            memberOrder: memberOrder,
            activity: proxyOperationActivity,
            canClearFixedSelection: appModel.supportsUnifiedAction(.clearFixedSelection)
        )
    }

    private func synchronizePresentation(
        _ input: ProxyWorkspacePresentationInput? = nil
    ) {
        let input = input ?? presentationInput
        persistReconciledWorkspace(
            model.updatePresentation(input),
            replacing: input.workspace
        )
    }

    private func persistReconciledWorkspace(
        _ next: WorkbenchDestinationWorkspace,
        replacing previous: WorkbenchDestinationWorkspace
    ) {
        guard next != previous else { return }
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { stored in
            stored = next
        }
    }

    private func receiveCatalog(
        _ catalog: PolicyGroupCatalogSnapshot,
        request: ProxyCatalogObservationRequest,
        forceImmediate: Bool = false
    ) {
        guard request.matches(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        ) else { return }
        let update = ProxyCatalogUpdate(
            revision: ProxyCatalogRevision(
                controllerID: request.controllerID,
                generation: request.generation,
                value: request.revision
            ),
            catalog: catalog
        )
        let priority = ProxyCatalogUpdateClassifier.priority(
            previous: model.catalog,
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

    private func resetCatalogPresentationForSessionBoundary(
        _ request: ProxyCatalogObservationRequest
    ) {
        guard request.matches(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        ) else { return }

        let retainedPendingNavigation = pendingNavigation.flatMap {
            request.owns($0) ? $0 : nil
        }
        let retainedReveal = reveal.flatMap { request.owns($0) ? $0 : nil }
        let retainedScrolledToken = retainedReveal?.token == lastScrolledRevealToken
            ? lastScrolledRevealToken
            : nil

        scrollInteractionTracker.reset(coordinator: presentationCoordinator)
        model.reset()
        hoverPreview.reset()
        reveal = retainedReveal
        lastScrolledRevealToken = retainedScrolledToken
        pendingNavigation = retainedPendingNavigation
        revealObstruction = nil
        unresolvedReason = nil
    }

    private func applyCatalogUpdate(
        _ update: ProxyCatalogUpdate,
        supersedingDeferredUpdates: Bool = true
    ) {
        if supersedingDeferredUpdates {
            presentationCoordinator.clearPendingUpdate()
        }
        let input = presentationInput
        guard let reconciled = model.accept(
            update,
            selectedControllerID: appModel.selectedRouterID,
            sessionControllerID: appModel.controllerSessionPresentation.controllerID,
            generation: appModel.controllerSessionPresentation.generation,
            input: input
        ) else {
            return
        }
        persistReconciledWorkspace(reconciled, replacing: input.workspace)
        consumePendingProxyNavigation()
        resolveReveal()
    }

    private func activateGroup(_ groupID: String) {
        guard hasCurrentCatalogProjection,
              model.groupProjection.arrangedGroups.contains(where: { $0.id == groupID })
        else { return }
        beginTransientPresentationInteraction()
        hoverPreview.reset()
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { stored in
            stored = ProxyWorkspaceProjection.activating(
                groupID,
                in: stored,
                groups: model.groupProjection.arrangedGroups
            )
        }
        synchronizePresentation()
    }

    private func activateAccessibilityGroup(_ groupID: String, scope: LiveCommandScope) {
        guard appModel.matchesCurrentCommandScope(scope) else { return }
        dismissPendingReveal()
        activateGroup(groupID)
    }

    private func dismissPendingReveal() {
        pendingNavigation = nil
        reveal = nil
        revealObstruction = nil
        unresolvedReason = nil
    }

    private func setGroupFilter(_ value: String, for groupID: String) {
        guard hasCurrentGroupProjection(groupID) else { return }
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { stored in
            stored.proxyMemberQuery = value
        }
    }

    private func selectMember(
        _ memberID: String,
        in groupID: String,
        scope: LiveCommandScope
    ) {
        guard appModel.matchesCurrentCommandScope(scope),
              hasCurrentGroupProjection(groupID) else { return }
        let index = model.activeGroupIndex(for: groupID)

        guard let target = ProxyProjection.currentMemberMutationTarget(
            groupID: groupID,
            memberID: memberID,
            index: index,
            selectedControllerID: appModel.selectedRouterID,
            sessionControllerID: appModel.controllerSessionPresentation.controllerID,
            generation: appModel.controllerSessionPresentation.generation,
            actionAvailable: liveCommandsAvailable
                && canSelectMember
                && !isSwitchingGroup(groupID),
            requiresSelectableGroup: true
        ) else { return }

        guard index.occurrence?.group.selected != target.memberName else {
            return
        }
        prioritizeUserOperationResult()
        select(target.memberName, in: target.groupID, scope: scope)
    }

    /// Toggles the exact member's inline detail without selecting a remote node.
    /// Default tile/VoiceOver activation remains usable for read-only groups.
    @discardableResult
    private func inspectMember(
        _ memberID: String,
        in groupID: String,
        scope: LiveCommandScope
    ) -> ProxyGroupOccurrence? {
        let index = model.activeGroupIndex(for: groupID)
        guard appModel.matchesCurrentCommandScope(scope),
              hasCurrentGroupProjection(groupID),
              let occurrence = index.occurrence,
              index.recordsByID[memberID]?.row != nil else { return nil }

        dismissPendingReveal()
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .proxies
        ) { stored in
            stored.activeGroupID = groupID
            stored.inspectedProxyMemberID = stored.inspectedProxyMemberID == memberID ? nil : memberID
        }
        return occurrence
    }

    private func testMember(
        _ memberID: String,
        in groupID: String,
        scope: LiveCommandScope
    ) {
        guard appModel.matchesCurrentCommandScope(scope),
              hasCurrentGroupProjection(groupID),
              liveCommandsAvailable,
              let target = ProxyProjection.currentMemberMutationTarget(
                groupID: groupID,
                memberID: memberID,
                index: model.activeGroupIndex(for: groupID),
                selectedControllerID: appModel.selectedRouterID,
                sessionControllerID: appModel.controllerSessionPresentation.controllerID,
                generation: appModel.controllerSessionPresentation.generation,
                actionAvailable: canTestNode,
                requiresSelectableGroup: false
              ) else { return }

        prioritizeUserOperationResult()
        appModel.measureDelay(
            for: target.memberName,
            in: target.groupID,
            scope: scope
        )
    }

    private func testGroup(_ groupID: String, scope: LiveCommandScope) {
        guard appModel.matchesCurrentCommandScope(scope),
              liveCommandsAvailable,
              canTestGroup,
              let occurrence = model.groupOccurrence(for: groupID, scope: scope) else { return }
        prioritizeUserOperationResult()
        performGroupTest(occurrence.group.id, scope: scope)
    }

    private func clearFixedSelection(
        in groupID: String,
        scope: LiveCommandScope
    ) {
        guard appModel.matchesCurrentCommandScope(scope),
              liveCommandsAvailable,
              let occurrence = model.groupOccurrence(for: groupID, scope: scope),
              canClearFixed(occurrence) else { return }
        prioritizeUserOperationResult()
        appModel.clearFixedSelection(
            in: occurrence.group.id,
            scope: scope
        )
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
        model.revision.isCurrent(
            selectedControllerID: appModel.selectedRouterID,
            sessionControllerID: appModel.controllerSessionPresentation.controllerID,
            generation: appModel.controllerSessionPresentation.generation
        )
    }

    private func hasCurrentGroupProjection(_ groupID: String) -> Bool {
        let index = model.activeGroupIndex(for: groupID)
        return hasCurrentCatalogProjection
            && index.revision
                == model.revision
            && index.occurrence?.id == groupID
    }

    private func isSwitchingGroup(_ groupID: String) -> Bool {
        let reportedID = model.activeGroupIndex(for: groupID).occurrence?.group.id ?? groupID
        return proxyOperationActivity.isSwitching(groupID: reportedID)
    }

    private func select(
        _ member: String,
        in groupID: String,
        scope: LiveCommandScope
    ) {
        if isSurge {
            appModel.selectSurgePolicy(member, in: groupID, scope: scope)
        } else {
            appModel.selectNode(member, in: groupID, scope: scope)
        }
    }

    private func performGroupTest(
        _ groupID: String,
        scope: LiveCommandScope
    ) {
        if isSurge {
            appModel.testSurgePolicyGroup(groupID, scope: scope)
        } else {
            appModel.measureDelay(in: groupID, scope: scope)
        }
    }

    private var currentNavigationSelection: WorkbenchProxyNavigationSelection? {
        guard let controllerID = appModel.selectedRouterID else { return nil }
        let generation = appModel.controllerSessionPresentation.generation
        let controllerGroups = ProxyProjection.arrangedGroups(
            model.catalog.groups,
            mode: model.catalog.mode,
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
           let occurrence = model.groupProjection.arrangedGroups.first(
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

    private func locateAccessibilityCurrentNode(
        in groupID: String,
        scope: LiveCommandScope
    ) {
        guard appModel.matchesCurrentCommandScope(scope) else { return }
        locateCurrentNode(in: groupID)
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
            catalog: model.catalog,
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

        for _ in 0..<3 {
            let currentWorkspace = workspace
            if currentWorkspace.activeGroupID != occurrence.id {
                activateGroup(occurrence.id)
                continue
            }

            let index = model.activeGroupIndex(for: occurrence.id)
            guard index.occurrence != nil else {
                synchronizePresentation()
                continue
            }

            // Directory search only filters the left rail; it does not hide the
            // active group's node list or prevent cross-group navigation.
            let blockers = WorkbenchProxyFilterObstructions.resolve(
                member: row,
                index: index,
                query: currentWorkspace.proxyMemberQuery,
                healthFilter: healthFilter
            )
            guard blockers.isEmpty else {
                revealObstruction = .filters(
                    groupOccurrenceID: occurrence.id,
                    blockers: blockers
                )
                return
            }
            guard model.activeProjection.members.contains(where: {
                $0.id == member.id
            }) else {
                synchronizePresentation()
                continue
            }

            workspaceStore.update(
                controllerID: controllerID,
                destination: .proxies
            ) { stored in
                stored.activeGroupID = occurrence.id
                stored.inspectedProxyMemberID = member.id
            }

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
            return
        }
    }

    private func recoverRevealObstruction() {
        switch revealObstruction {
        case .hiddenGlobal:
            preferences.globalGroupVisibility = .alwaysShow
            synchronizePresentation()
        case .filters:
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                workspaceStore.update(
                    controllerID: appModel.selectedRouterID,
                    destination: .proxies
                ) { stored in
                    stored.proxyMemberQuery = ""
                    stored.filters[ProxyWorkspaceFilterKey.healthFilter] = nil
                }
            }
            synchronizePresentation()
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
            hasRetainedCatalog: !model.catalog.groups.isEmpty,
            state: appModel.controllerSessionPresentation.state,
            language: language
        )
    }

    private var groupVisibilitySummary: String {
        MicaStrings.localized(
            "routing.visible_groups_count \(model.groupProjection.visibleGroups.count) \(model.groupProjection.arrangedGroups.count)",
            language: language
        )
    }

    private func filterTitleWithCount(_ filter: ProxyHealthFilter) -> String {
        let base = MicaStrings.localizedKey(filter.titleKey, language: language)
        guard let count = model.healthFilterCounts[filter] else { return base }
        return "\(base) (\(count))"
    }

    private var modeBadgeText: String {
        let mode = MicaStrings.displayMode(model.groupProjection.mode, language: language)
        return MicaStrings.localized(
            "routing.mode_current \(mode)",
            language: language
        )
    }
}

private struct ProxyPolicyCatalogObserver: View {
    @Environment(AppModel.self) private var appModel

    let onSessionBoundary: (ProxyCatalogObservationRequest) -> Void
    let onCatalog: (
        PolicyGroupCatalogSnapshot,
        ProxyCatalogObservationRequest,
        Bool
    ) -> Void

    var body: some View {
        let observation = currentObservation

        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                let current = currentObservation
                onCatalog(appModel.policyGroupCatalog, current, true)
            }
            .onChange(of: observation) { previous, current in
                let crossedSessionBoundary = !current.belongsToSameSession(
                    as: previous
                )
                if crossedSessionBoundary {
                    onSessionBoundary(current)
                }
                onCatalog(
                    appModel.policyGroupCatalog,
                    current,
                    crossedSessionBoundary
                )
            }
    }

    private var currentObservation: ProxyCatalogObservationRequest {
        ProxyCatalogObservationRequest(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation,
            revision: appModel.policyGroupCatalogRevision
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
