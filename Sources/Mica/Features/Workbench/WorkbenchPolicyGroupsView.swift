import MicaCore
import SwiftUI

struct WorkbenchPolicyGroupsView: View {
    var appModel: AppModel
    @Binding var searchText: String

    @Environment(\.micaAppLanguage) private var appLanguage
    @Environment(\.micaFontMultiplier) private var fontMultiplier
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(AppPreferencesStore.globalGroupVisibilityKey) private var globalGroupVisibilityRawValue = GlobalGroupVisibility.followMode.rawValue
    @AppStorage(PolicyGroupExpansionArchive.storageKey) private var expandedGroupsArchiveRawValue = ""

    @State private var policyStateStore = PolicyGroupInteractionStore.shared
    @State private var containerWidth: CGFloat = 0
    @State private var containerHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    catalogHeader

                    policyContent
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .onAppear {
                    containerWidth = geometry.size.width
                    containerHeight = geometry.size.height
                }
                .onChange(of: geometry.size.width) { _, newWidth in
                    containerWidth = newWidth
                }
                .onChange(of: geometry.size.height) { _, newHeight in
                    containerHeight = newHeight
                }
            }
            .scrollContentBackground(.hidden)
            .background(MicaStyle.pageFill)
            .onAppear {
                appModel.reconcilePolicyGroupPresentation()
                synchronizePolicyState(pruneMissingGroups: hasCompletePolicySnapshot)
            }
            .onChange(of: appModel.dashboard.groups) { _, _ in
                // Search only changes visibility. Selection is reconciled against the
                // complete controller snapshot so it survives filtering unchanged.
                appModel.reconcilePolicyGroupPresentation()
                synchronizePolicyState(pruneMissingGroups: hasCompletePolicySnapshot)
            }
            .onChange(of: appModel.controllerHealth.status(for: .proxies)) { _, status in
                guard case .ready = status else { return }
                synchronizePolicyState(pruneMissingGroups: true)
            }
            .onChange(of: appModel.selectedRouterID) { _, _ in
                appModel.reconcilePolicyGroupPresentation()
                synchronizePolicyState(pruneMissingGroups: false)
            }
            .onChange(of: appModel.routers.map(\.id)) { _, _ in
                pruneRemovedControllers()
            }
            .onChange(of: appModel.didLoadPersistedState) { _, didLoad in
                guard didLoad else { return }
                pruneRemovedControllers()
            }
        }
    }

    private var catalogHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                MicaText("routing.group_catalog")
                    .font(.system(size: 18 * fontMultiplier, weight: .semibold))
                MicaText("routing.help_all_groups_visible")
                    .font(.system(size: 12 * fontMultiplier))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let stalePolicyMessage {
                    Label(stalePolicyMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5 * fontMultiplier, weight: .medium))
                        .foregroundStyle(MicaStyle.signalAmber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            Text(
                MicaStrings.localized(
                    "routing.visible_groups_count \(arrangedGroups.count) \(appModel.dashboard.groups.count)",
                    language: appLanguage
                )
            )
            .font(.system(size: 12 * fontMultiplier, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var policyContent: some View {
        switch policyAvailability {
        case .unavailable(let message):
            policyUnavailable(message)
        case .loading:
            ProgressView {
                MicaText("dashboard.skeleton_proxies")
            }
            .frame(maxWidth: .infinity, minHeight: emptyStateMinimumHeight, alignment: .center)
        case .empty:
            emptyState(
                icon: "point.3.connected.trianglepath.dotted",
                titleKey: "dashboard.no_routing_modules_loaded",
                messageKey: "dashboard.no_routing_modules_hint"
            )
        case .filteredEmpty:
            emptyState(
                icon: "magnifyingglass",
                titleKey: "dashboard.no_matching_groups",
                messageKey: "dashboard.no_matching_groups_hint"
            )
        case .available:
            groupList
        }
    }

    // MARK: Collapsible group list

    @ViewBuilder
    private var groupList: some View {
        if usesTwoColumns {
            HStack(alignment: .top, spacing: MicaStyle.cardSpacing) {
                LazyVStack(alignment: .leading, spacing: MicaStyle.cardSpacing) {
                    ForEach(Array(columnAssignment.leadingColumn.enumerated()), id: \.element.id) { entry in
                        groupCard(entry.element, semanticIndex: entry.offset * 2)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                LazyVStack(alignment: .leading, spacing: MicaStyle.cardSpacing) {
                    ForEach(Array(columnAssignment.trailingColumn.enumerated()), id: \.element.id) { entry in
                        groupCard(entry.element, semanticIndex: entry.offset * 2 + 1)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .accessibilityElement(children: .contain)
        } else {
            LazyVStack(alignment: .leading, spacing: MicaStyle.cardSpacing) {
                ForEach(Array(columnAssignment.semanticOrder.enumerated()), id: \.element.id) { entry in
                    groupCard(entry.element, semanticIndex: entry.offset)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    /// Repeated policy content stays on a semantic fill. The expanded card only
    /// changes its border tint; it never adds per-card material, glass, or shadow.
    private func groupCard(
        _ group: ProxyGroupViewState,
        semanticIndex: Int
    ) -> some View {
        let expanded = isExpanded(group.id)

        return PolicyGroupCardSurface(
            tint: expanded ? MicaStyle.accent : nil
        ) {
            DisclosureGroup(isExpanded: expansionBinding(for: group)) {
                expandedContent(group)
            } label: {
                collapsedRow(group)
            }
            .disclosureGroupStyle(PolicyDisclosureStyle(fontMultiplier: fontMultiplier))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(group.id)
        .accessibilitySortPriority(
            columnAssignment.accessibilitySortPriority(forSemanticIndex: semanticIndex)
        )
    }

    private func expansionBinding(for group: ProxyGroupViewState) -> Binding<Bool> {
        Binding(
            get: { isExpanded(group.id) },
            set: { isOn in
                let apply = {
                    guard let controllerID = selectedControllerStateID else { return }

                    policyStateStore.setExpanded(
                        isOn,
                        groupID: group.id,
                        controllerID: controllerID
                    )
                    appModel.selectPolicyGroup(group.id)
                    persistExpandedGroupIDs(for: controllerID)
                }

                if reduceMotion {
                    apply()
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        apply()
                    }
                }
            }
        )
    }

    // MARK: Collapsed row (rich info card row — not a plain disclosure label)

    private func collapsedRow(_ group: ProxyGroupViewState) -> some View {
        let currentNode = group.detail(for: group.selected)
        let currentDelay = group.delays[group.selected] ?? currentNode?.latestHistoryDelay
        let isSurge = usesSurgePolicyOperations
        let isTesting = isSurge
            ? appModel.testingSurgePolicyGroup == group.id
            : appModel.measuringDelayGroupID == group.id
                || appModel.measuringDelayNode?.groupID == group.id
        let isSwitching = isSurge ? appModel.switchingSurgePolicyGroup == group.id : appModel.switchingGroupID == group.id
        let isClearing = appModel.clearingFixedGroupID == group.id

        return HStack(alignment: .center, spacing: 11) {
            Image(systemName: groupSymbol(group))
                .font(.system(size: 14 * fontMultiplier, weight: .semibold))
                .foregroundStyle(MicaStyle.accent)
                .frame(width: 30 * fontMultiplier, height: 30 * fontMultiplier)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MicaStyle.accent.opacity(0.18))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(group.id)
                        .font(.system(size: 13.5 * fontMultiplier, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    if group.hidden {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 10 * fontMultiplier, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(MicaStrings.localizedKey("routing.hidden_group", language: appLanguage))
                    }
                }

                Text(reportedSelection(group))
                    .font(.system(size: 11.5 * fontMultiplier, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isTesting || isSwitching || isClearing {
                Text(operationLabel(isTesting: isTesting, isSwitching: isSwitching, isClearing: isClearing))
                    .font(.system(size: 10 * fontMultiplier, weight: .medium))
                    .foregroundStyle(MicaStyle.signalAmber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            memberCountBadge(group.options.count)

            delayIndicator(currentDelay, alive: currentNode?.alive)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            MicaStrings.localized(
                "routing.acc_module_row \(group.id) \(reportedSelection(group)) \(operationLabel(isTesting: isTesting, isSwitching: isSwitching, isClearing: isClearing))",
                language: appLanguage
            )
        )
    }

    private func memberCountBadge(_ count: Int) -> some View {
        Text(MicaStrings.localized("routing.module_count \(count)", language: appLanguage))
            .font(.system(size: 10.5 * fontMultiplier, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.secondary.opacity(0.12))
            )
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Current-node health at a glance: a color dot plus the delay value, so the
    /// user can judge a group without expanding it.
    private func delayIndicator(_ delay: Int?, alive: Bool?) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(delayTint(delay, alive: alive))
                .frame(width: 8 * fontMultiplier, height: 8 * fontMultiplier)
                .accessibilityHidden(true)

            Text(delayLabel(delay, alive: alive))
                .font(.system(size: 11.5 * fontMultiplier, weight: .semibold, design: .monospaced))
                .foregroundStyle(delayTint(delay, alive: alive))
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minWidth: 60 * fontMultiplier, alignment: .trailing)
    }

    private func groupSymbol(_ group: ProxyGroupViewState) -> String {
        let type = group.type.lowercased()
        if type.contains("url") {
            return "bolt.horizontal.circle"
        }
        if type.contains("fallback") {
            return "arrow.triangle.branch"
        }
        if type.contains("load") {
            return "scalemass"
        }
        if type.contains("select") {
            return "hand.tap"
        }
        return "square.grid.2x2"
    }

    // MARK: Expanded content

    private func expandedContent(_ group: ProxyGroupViewState) -> some View {
        let isSurge = usesSurgePolicyOperations
        let isTesting = isSurge
            ? appModel.testingSurgePolicyGroup == group.id
            : appModel.measuringDelayGroupID == group.id
                || appModel.measuringDelayNode?.groupID == group.id
        let isSwitching = isSurge ? appModel.switchingSurgePolicyGroup == group.id : appModel.switchingGroupID == group.id
        let isClearing = appModel.clearingFixedGroupID == group.id

        return HStack(alignment: .top, spacing: 12) {
            // Accent edge distinguishes the expanded body from the collapsed row.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(MicaStyle.accent.opacity(0.7))
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                Text(group.type)
                    .font(.system(size: 11.5 * fontMultiplier, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                detailMetrics(group, isTesting: isTesting, isSwitching: isSwitching, isClearing: isClearing)

                HStack(spacing: 10) {
                    Button {
                        appModel.selectPolicyGroup(group.id)
                        testLatency(in: group.id, surge: isSurge)
                    } label: {
                        MicaLabel("routing.test_group", systemImage: "gauge.with.dots.needle.33percent")
                    }
                    .buttonStyle(.borderless)
                    .frame(minHeight: minimumHitHeight)
                    .disabled(appModel.isBusy || !appModel.supportsUnifiedAction(isSurge ? .testSurgePolicy : .testLatency))
                    .help(MicaStrings.localizedKey("routing.help_inspector_test_delay", language: appLanguage))
                    .accessibilityLabel(MicaStrings.localizedKey("routing.test_group", language: appLanguage))

                    if !isSurge, group.details?.fixed?.nilIfEmpty != nil {
                        Button {
                            appModel.selectPolicyGroup(group.id)
                            appModel.clearFixedSelection(in: group.id)
                        } label: {
                            MicaLabel("routing.clear_fixed_selection", systemImage: "pin.slash")
                        }
                        .buttonStyle(.borderless)
                        .frame(minHeight: minimumHitHeight)
                        .disabled(appModel.isBusy || !appModel.supportsUnifiedAction(.clearFixedSelection))
                        .help(MicaStrings.localizedKey("routing.help_clear_fixed_selection", language: appLanguage))
                        .accessibilityLabel(MicaStrings.localizedKey("routing.clear_fixed_selection", language: appLanguage))
                    }

                    if isTesting || isSwitching || isClearing {
                        ProgressView()
                            .accessibilityLabel(operationLabel(isTesting: isTesting, isSwitching: isSwitching, isClearing: isClearing))
                    }
                }

                Divider()

                membersList(group, surge: isSurge)
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func membersList(_ group: ProxyGroupViewState, surge: Bool) -> some View {
        let filteredOptions = PolicyGroupPresentation.filteredOptions(
            in: group,
            matching: memberFilterText(for: group.id)
        )
        let members = visibleMembers(filteredOptions, in: group)

        if group.options.isEmpty {
            MicaText("routing.members_empty")
                .font(.system(size: 12.5 * fontMultiplier))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80 * fontMultiplier, alignment: .leading)
        } else {
            memberFilterField(for: group)

            if filteredOptions.isEmpty {
                MicaText("routing.members_filtered_empty")
                    .font(.system(size: 12.5 * fontMultiplier))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80 * fontMultiplier, alignment: .leading)
            } else {
                PolicyGroupMemberScroller(
                    maximumHeight: memberScrollMaximumHeight,
                    initialHeight: min(memberScrollMaximumHeight, minimumHitHeight * 3),
                    accessibilityLabel: memberScrollAccessibilityLabel(
                        group: group,
                        visibleCount: members.count,
                        totalCount: filteredOptions.count
                    ),
                    scrollPosition: memberScrollPositionBinding(for: group.id)
                ) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(members) { member in
                            memberRow(member, group: group, surge: surge)
                            if member.id != members.last?.id {
                                Divider()
                            }
                        }

                        if hasMoreMembers(filteredOptions, in: group.id) {
                            Divider()
                            HStack(alignment: .center, spacing: 10) {
                                Text(
                                    MicaStrings.localized(
                                        "routing.member_window \(members.count) \(filteredOptions.count)",
                                        language: appLanguage
                                    )
                                )
                                .font(.system(size: 11.5 * fontMultiplier, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 8)

                                Button {
                                    showMoreMembers(
                                        in: group.id,
                                        totalCount: filteredOptions.count
                                    )
                                } label: {
                                    MicaLabel("routing.load_more_members", systemImage: "arrow.down")
                                }
                                .buttonStyle(.borderless)
                                .frame(minHeight: minimumHitHeight)
                                .help(MicaStrings.localizedKey("routing.help_load_more_members", language: appLanguage))
                                .accessibilityLabel(
                                    MicaStrings.localized(
                                        "routing.acc_load_more_members \(members.count) \(filteredOptions.count)",
                                        language: appLanguage
                                    )
                                )
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                    }
                    .scrollTargetLayout()
                }
            }
        }
    }

    private func memberFilterField(for group: ProxyGroupViewState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 12 * fontMultiplier, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(
                MicaStrings.localizedKey("routing.filter_nodes_placeholder", language: appLanguage),
                text: memberFilterBinding(for: group.id)
            )
            .font(.system(size: 12.5 * fontMultiplier))
            .textFieldStyle(.roundedBorder)
            .frame(minHeight: minimumHitHeight)
            .accessibilityLabel(MicaStrings.localizedKey("routing.filter_nodes", language: appLanguage))
            .simultaneousGesture(
                TapGesture().onEnded {
                    appModel.selectPolicyGroup(group.id)
                }
            )
        }
        .frame(minHeight: minimumHitHeight)
    }

    private func memberFilterBinding(for groupID: String) -> Binding<String> {
        Binding(
            get: { memberFilterText(for: groupID) },
            set: { text in
                guard let controllerID = selectedControllerStateID else { return }
                policyStateStore.setFilterText(
                    text,
                    groupID: groupID,
                    controllerID: controllerID
                )
                appModel.selectPolicyGroup(groupID)
            }
        )
    }

    private func memberFilterText(for groupID: String) -> String {
        guard let controllerID = selectedControllerStateID else { return "" }
        return policyStateStore.filterText(
            groupID: groupID,
            controllerID: controllerID
        )
    }

    private func memberScrollAccessibilityLabel(
        group: ProxyGroupViewState,
        visibleCount: Int,
        totalCount: Int
    ) -> String {
        let count = MicaStrings.localized(
            "routing.member_window \(visibleCount) \(totalCount)",
            language: appLanguage
        )
        return "\(group.id), \(count)"
    }

    private func memberScrollPositionBinding(for groupID: String) -> Binding<ScrollPosition> {
        Binding(
            get: {
                guard let controllerID = selectedControllerStateID else {
                    return ScrollPosition(idType: String.self)
                }
                return policyStateStore.scrollPosition(
                    groupID: groupID,
                    controllerID: controllerID
                )
            },
            set: { position in
                guard let controllerID = selectedControllerStateID else { return }
                policyStateStore.setScrollPosition(
                    position,
                    groupID: groupID,
                    controllerID: controllerID
                )
            }
        )
    }

    private func showMoreMembers(in groupID: String, totalCount: Int) {
        guard let controllerID = selectedControllerStateID else { return }
        appModel.selectPolicyGroup(groupID)
        policyStateStore.showMoreMembers(
            groupID: groupID,
            totalCount: totalCount,
            controllerID: controllerID
        )
    }

    private func hasMoreMembers(_ options: [String], in groupID: String) -> Bool {
        guard let controllerID = selectedControllerStateID else {
            return options.count > PolicyGroupControllerInteractionState.memberWindowSize
        }
        return policyStateStore.hasMoreOptions(
            options,
            groupID: groupID,
            controllerID: controllerID
        )
    }

    private func memberRow(_ member: PolicyGroupMember, group: ProxyGroupViewState, surge: Bool) -> some View {
        let selected = member.name == group.selected
        let selectionSupported = group.selectable && (surge
            ? appModel.supportsUnifiedAction(.selectSurgePolicy)
            : appModel.supportsUnifiedAction(.switchPolicy))
        let switching = surge ? appModel.switchingSurgePolicyGroup == group.id : appModel.switchingGroupID == group.id
        let latencyTarget = PolicyNodeLatencyTestTarget(groupID: group.id, nodeName: member.name)
        let testingNode = appModel.measuringDelayNode == latencyTarget
        let nodeTestSupported = !surge && appModel.supportsUnifiedAction(.testLatency)

        return HStack(alignment: .center, spacing: 4) {
            Button {
                appModel.selectPolicyGroup(group.id)
                if surge {
                    appModel.selectSurgePolicy(member.name, in: group.id)
                } else {
                    appModel.selectNode(member.name, in: group.id)
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13 * fontMultiplier, weight: .semibold))
                        .foregroundStyle(selected ? MicaStyle.accent : Color.secondary.opacity(0.55))
                        .frame(width: 16 * fontMultiplier, height: 18 * fontMultiplier)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(member.name)
                                .font(.system(size: 12.5 * fontMultiplier, weight: selected ? .semibold : .regular))
                                .fixedSize(horizontal: false, vertical: true)

                            if let alive = member.alive {
                                Label {
                                    Text(
                                        MicaStrings.localizedKey(
                                            alive ? "routing.node_alive" : "routing.node_unavailable",
                                            language: appLanguage
                                        )
                                    )
                                } icon: {
                                    Image(systemName: alive ? "checkmark.circle.fill" : "xmark.circle.fill")
                                }
                                .font(.system(size: 10.5 * fontMultiplier, weight: .medium))
                                .foregroundStyle(alive ? MicaStyle.signalMint : MicaStyle.signalRed)
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }

                        if let type = member.type {
                            Text(type)
                                .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        memberMetadata(member)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(delayLabel(member.delay, alive: member.alive))
                            .font(.system(size: 11.5 * fontMultiplier, weight: .semibold, design: .monospaced))
                            .foregroundStyle(delayTint(member.delay, alive: member.alive))
                            .fixedSize(horizontal: false, vertical: true)

                        delayBar(member.delay, alive: member.alive)

                        if switching && selected {
                            MicaText("dashboard.switching")
                                .font(.system(size: 10.5 * fontMultiplier))
                                .foregroundStyle(MicaStyle.signalAmber)
                        }
                    }
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(selected || appModel.isBusy || !selectionSupported)
            .accessibilityLabel(
                MicaStrings.localized(
                    "routing.acc_select_member \(member.name) \(delayLabel(member.delay, alive: member.alive))",
                    language: appLanguage
                )
            )
            .help(MicaStrings.localizedKey("dashboard.help_switch_node", language: appLanguage))

            if nodeTestSupported {
                Button {
                    appModel.selectPolicyGroup(group.id)
                    appModel.measureDelay(for: member.name, in: group.id)
                } label: {
                    if testingNode {
                        ProgressView()
                    } else {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                    }
                }
                .buttonStyle(.borderless)
                .frame(width: minimumHitHeight, height: minimumHitHeight)
                .disabled(appModel.isBusy)
                .help(
                    MicaStrings.localized(
                        "routing.help_test_node \(member.name)",
                        language: appLanguage
                    )
                )
                .accessibilityLabel(
                    MicaStrings.localized(
                        "routing.test_node \(member.name)",
                        language: appLanguage
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: minimumHitHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? MicaStyle.accent.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    selected ? MicaStyle.accent.opacity(0.45) : Color.clear,
                    lineWidth: selected ? 1 : 0
                )
        )
    }

    @ViewBuilder
    private func memberMetadata(_ member: PolicyGroupMember) -> some View {
        if let providerName = member.providerName {
            metadataLine(systemImage: "shippingbox", titleKey: "routing.node_provider", value: providerName)
        }

        if let interfaceName = member.interfaceName {
            metadataLine(systemImage: "network", titleKey: "routing.node_interface", value: interfaceName)
        }

        if !member.transportNames.isEmpty {
            metadataLine(
                systemImage: "point.3.connected.trianglepath.dotted",
                titleKey: "routing.node_transports",
                value: member.transportNames.joined(separator: " · ")
            )
        }

        if let fixed = member.fixed {
            metadataLine(systemImage: "pin.fill", titleKey: "routing.fixed_selection", value: fixed)
        }

        if let testURL = member.testURL {
            metadataLine(systemImage: "link", titleKey: "routing.test_url", value: testURL)
        }

        if let icon = member.icon {
            metadataLine(systemImage: "photo", titleKey: "routing.icon_url", value: icon)
        }

        if let historySummary = memberHistorySummary(member) {
            metadataLine(systemImage: "clock.arrow.circlepath", titleKey: "routing.delay_history", value: historySummary)
        }

        if let additionalMetadataText = member.additionalMetadataText {
            metadataLine(systemImage: "curlybraces", titleKey: "routing.additional_fields", value: additionalMetadataText)
        }
    }

    private func metadataLine(systemImage: String, titleKey: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: systemImage)
                .frame(width: 13 * fontMultiplier)
                .accessibilityHidden(true)
            MicaText(titleKey)
                .fontWeight(.medium)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.system(size: 10.5 * fontMultiplier))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func memberHistorySummary(_ member: PolicyGroupMember) -> String? {
        guard member.historyCount > 0 else { return nil }
        let delay = delayLabel(member.latestHistoryDelay, alive: member.alive)
        let time = member.latestHistoryTime
            ?? MicaStrings.localizedKey("overview.config_not_reported", language: appLanguage)
        return MicaStrings.localized(
            "routing.history_summary \(member.historyCount) \(delay) \(time)",
            language: appLanguage
        )
    }

    /// A three-tier width capsule encoding latency band (fast → full, timeout →
    /// short). Purely graphic, so the tint only needs the 3.0:1 graphic bar.
    private func delayBar(_ delay: Int?, alive: Bool?) -> some View {
        let width: CGFloat
        switch delay {
        case .some(let value) where value > 0 && value < 180:
            width = 34
        case .some(let value) where value > 0 && value < 420:
            width = 22
        case .some(let value) where value > 0:
            width = 12
        default:
            width = 8
        }

        return Capsule()
            .fill(delayTint(delay, alive: alive))
            .frame(width: width * fontMultiplier, height: 3)
            .accessibilityHidden(true)
    }

    private var filteredGroups: [ProxyGroupViewState] {
        PolicyGroupPresentation.filteredGroups(appModel.dashboard.groups, matching: searchText)
    }

    /// Applies GLOBAL-group visibility on top of the filtered list. Non-GLOBAL
    /// groups keep the controller's `proxyOrder`; GLOBAL is only ever appended
    /// after them (never sorted) or removed, per the current mode and preference.
    private var arrangedGroups: [ProxyGroupViewState] {
        PolicyGroupPresentation.arrangedGroups(
            filteredGroups,
            mode: appModel.dashboard.mode,
            visibility: GlobalGroupVisibility.stored(globalGroupVisibilityRawValue)
        )
    }

    private var columnAssignment: PolicyGroupColumnAssignment<ProxyGroupViewState> {
        PolicyGroupColumnAssignment(arrangedGroups)
    }

    private var usesTwoColumns: Bool {
        containerWidth >= 1_000
    }

    private var selectedControllerStateID: String? {
        appModel.selectedRouterID?.uuidString
    }

    private var hasCompletePolicySnapshot: Bool {
        if case .ready = appModel.controllerHealth.status(for: .proxies) {
            return true
        }
        return false
    }

    private var stalePolicyMessage: String? {
        guard !appModel.dashboard.groups.isEmpty,
              case .failed(let message) = appModel.controllerHealth.status(for: .proxies) else {
            return nil
        }
        return MicaStrings.localized("data.stale_detail \(message)", language: appLanguage)
    }

    private func isExpanded(_ groupID: String) -> Bool {
        guard let controllerID = selectedControllerStateID else { return false }
        return policyStateStore.isExpanded(groupID, controllerID: controllerID)
    }

    private func synchronizePolicyState(pruneMissingGroups: Bool) {
        pruneRemovedControllers()

        guard let controllerID = selectedControllerStateID else { return }
        var archive = PolicyGroupExpansionArchive(rawValue: expandedGroupsArchiveRawValue)
        policyStateStore.ensureController(
            controllerID,
            restoredExpandedGroupIDs: archive.expandedGroupIDs(for: controllerID)
        )

        guard pruneMissingGroups else { return }

        let validGroupIDs = Set(appModel.dashboard.groups.map(\.id))
        policyStateStore.pruneGroups(
            controllerID: controllerID,
            keeping: validGroupIDs
        )
        archive.pruneGroups(
            controllerID: controllerID,
            keeping: validGroupIDs
        )
        saveExpansionArchive(archive)
    }

    private func persistExpandedGroupIDs(for controllerID: String) {
        var archive = PolicyGroupExpansionArchive(rawValue: expandedGroupsArchiveRawValue)
        archive.setExpandedGroupIDs(
            policyStateStore.expandedGroupIDs(for: controllerID),
            for: controllerID
        )
        saveExpansionArchive(archive)
    }

    private func pruneRemovedControllers() {
        guard appModel.didLoadPersistedState else { return }

        let validControllerIDs = Set(appModel.routers.map { $0.id.uuidString })
        policyStateStore.removeControllers(notIn: validControllerIDs)

        var archive = PolicyGroupExpansionArchive(rawValue: expandedGroupsArchiveRawValue)
        archive.removeControllers(notIn: validControllerIDs)
        saveExpansionArchive(archive)
    }

    private func saveExpansionArchive(_ archive: PolicyGroupExpansionArchive) {
        let rawValue = archive.rawValue
        guard rawValue != expandedGroupsArchiveRawValue else { return }
        expandedGroupsArchiveRawValue = rawValue
    }

    private var policyAvailability: PolicyAvailability {
        guard appModel.selectedRouter != nil else {
            return .unavailable(MicaStrings.localizedKey("live.no_controller", language: appLanguage))
        }

        switch appModel.controllerHealth.status(for: .proxies) {
        case .failed(let message):
            guard !appModel.dashboard.groups.isEmpty else { return .unavailable(message) }
            return arrangedGroups.isEmpty ? .filteredEmpty : .available
        case .checking:
            return .loading
        case .idle:
            return appModel.dashboard.groups.isEmpty ? .unavailable(MicaStrings.localizedKey("overview.no_controller_data", language: appLanguage)) : .available
        case .ready:
            if appModel.dashboard.groups.isEmpty {
                return .empty
            }
            return arrangedGroups.isEmpty ? .filteredEmpty : .available
        }
    }

    private func policyUnavailable(_ message: String) -> some View {
        ContentUnavailableView {
            Label {
                MicaText("dashboard.no_routing_modules_loaded")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, minHeight: emptyStateMinimumHeight, alignment: .center)
    }

    private func emptyState(icon: String, titleKey: String, messageKey: String) -> some View {
        ContentUnavailableView {
            Label {
                MicaText(titleKey)
            } icon: {
                Image(systemName: icon)
            }
        } description: {
            MicaText(messageKey)
        }
        .frame(maxWidth: .infinity, minHeight: emptyStateMinimumHeight, alignment: .center)
    }

    private var emptyStateMinimumHeight: CGFloat {
        max(280 * fontMultiplier, containerHeight - (118 * fontMultiplier))
    }

    private func detailValue(titleKey: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            MicaText(titleKey)
                .font(.system(size: 11 * fontMultiplier, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12 * fontMultiplier, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func detailMetrics(
        _ group: ProxyGroupViewState,
        isTesting: Bool,
        isSwitching: Bool,
        isClearing: Bool
    ) -> some View {
        let metrics = groupDetailMetrics(
            group,
            isTesting: isTesting,
            isSwitching: isSwitching,
            isClearing: isClearing
        )

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180 * fontMultiplier), alignment: .topLeading)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(metrics) { metric in
                detailValue(titleKey: metric.titleKey, value: metric.value)
            }
        }
    }

    private func groupDetailMetrics(
        _ group: ProxyGroupViewState,
        isTesting: Bool,
        isSwitching: Bool,
        isClearing: Bool
    ) -> [PolicyDetailMetric] {
        var metrics = [
            PolicyDetailMetric(titleKey: "dashboard.current_node", value: reportedSelection(group)),
            PolicyDetailMetric(
                titleKey: "dashboard.inspector_options",
                value: MicaStrings.localized("routing.module_count \(group.options.count)", language: appLanguage)
            ),
            PolicyDetailMetric(
                titleKey: "dashboard.col_status",
                value: operationLabel(isTesting: isTesting, isSwitching: isSwitching, isClearing: isClearing)
            ),
            PolicyDetailMetric(
                titleKey: "routing.hidden_group",
                value: group.hidden
                    ? MicaStrings.localizedKey("routing.hidden_group", language: appLanguage)
                    : MicaStrings.localizedKey("dashboard.ready", language: appLanguage)
            ),
        ]

        guard let details = group.details else { return metrics }

        if let alive = details.alive {
            metrics.append(
                PolicyDetailMetric(
                    titleKey: "routing.node_status",
                    value: MicaStrings.localizedKey(
                        alive ? "routing.node_alive" : "routing.node_unavailable",
                        language: appLanguage
                    )
                )
            )
        }
        appendMetric("routing.fixed_selection", value: details.fixed, to: &metrics)
        appendMetric("routing.node_provider", value: details.providerName, to: &metrics)
        appendMetric("routing.node_interface", value: details.interfaceName, to: &metrics)
        appendMetric("routing.test_url", value: details.testURL, to: &metrics)
        appendMetric("routing.icon_url", value: details.icon, to: &metrics)
        appendMetric(
            "routing.node_transports",
            value: details.transportNames.isEmpty ? nil : details.transportNames.joined(separator: " · "),
            to: &metrics
        )
        if !details.history.isEmpty {
            let member = PolicyGroupMember(
                id: details.id,
                name: details.name,
                details: details,
                measuredDelay: nil
            )
            appendMetric("routing.delay_history", value: memberHistorySummary(member), to: &metrics)
        }
        appendMetric("routing.additional_fields", value: details.additionalMetadataText, to: &metrics)
        return metrics
    }

    private func appendMetric(
        _ titleKey: String,
        value: String?,
        to metrics: inout [PolicyDetailMetric]
    ) {
        guard let value = value?.nilIfEmpty else { return }
        metrics.append(PolicyDetailMetric(titleKey: titleKey, value: value))
    }

    private func visibleMembers(
        _ filteredOptions: [String],
        in group: ProxyGroupViewState
    ) -> [PolicyGroupMember] {
        let visibleOptions: [String]
        if let controllerID = selectedControllerStateID {
            visibleOptions = policyStateStore.visibleOptions(
                filteredOptions,
                groupID: group.id,
                controllerID: controllerID
            )
        } else {
            visibleOptions = Array(
                filteredOptions.prefix(PolicyGroupControllerInteractionState.memberWindowSize)
            )
        }
        var occurrences: [String: Int] = [:]

        return visibleOptions.map { option in
            let occurrence = occurrences[option, default: 0]
            occurrences[option] = occurrence + 1
            return PolicyGroupMember(
                id: "\(group.id)\u{1F}\(option)\u{1F}\(occurrence)",
                name: option,
                details: group.detail(for: option),
                measuredDelay: group.delays[option]
            )
        }
    }

    private func reportedSelection(_ group: ProxyGroupViewState) -> String {
        let selection = group.selected.trimmingCharacters(in: .whitespacesAndNewlines)
        return selection.isEmpty || selection == "-"
            ? MicaStrings.localizedKey("overview.config_not_reported", language: appLanguage)
            : selection
    }

    private func testLatency(in groupID: String, surge: Bool) {
        if surge {
            appModel.testSurgePolicyGroup(groupID)
        } else {
            appModel.measureDelay(in: groupID)
        }
    }

    private func operationLabel(isTesting: Bool, isSwitching: Bool, isClearing: Bool = false) -> String {
        if isClearing {
            return MicaStrings.localizedKey("routing.clearing_fixed_selection", language: appLanguage)
        }
        if isSwitching {
            return MicaStrings.localizedKey("dashboard.switching", language: appLanguage)
        }
        if isTesting {
            return MicaStrings.localizedKey("dashboard.testing_label", language: appLanguage)
        }
        return MicaStrings.localizedKey("dashboard.ready", language: appLanguage)
    }

    private func delayLabel(_ delay: Int?, alive: Bool? = nil) -> String {
        if alive == false {
            return MicaStrings.localizedKey("routing.node_unavailable", language: appLanguage)
        }
        guard let delay else {
            return MicaStrings.localizedKey("dashboard.latency_unknown", language: appLanguage)
        }
        return delay <= 0 ? MicaStrings.localizedKey("latency.timeout", language: appLanguage) : "\(delay) ms"
    }

    private func delayTint(_ delay: Int?, alive: Bool? = nil) -> Color {
        if alive == false {
            return MicaStyle.signalRed
        }
        guard let delay, delay > 0 else {
            return .secondary
        }
        if delay < 180 {
            return MicaStyle.signalMint
        }
        if delay < 420 {
            return MicaStyle.signalAmber
        }
        return MicaStyle.signalRed
    }

    private var minimumHitHeight: CGFloat {
        max(44, 44 * fontMultiplier)
    }

    private var memberScrollMaximumHeight: CGFloat {
        min(560, 432 * max(1, fontMultiplier))
    }

    private var usesSurgePolicyOperations: Bool {
        guard let router = appModel.selectedRouter else { return false }
        return appModel.runtimeControllerKind(for: router) == .surgeCompatible
    }
}

/// Custom disclosure style: a leading chevron that rotates on expand (native
/// disclosure mechanism, non-plain presentation) with the rich label filling
/// the row. Keeps the whole header tappable and respects the selected font.
private struct PolicyDisclosureStyle: DisclosureGroupStyle {
    let fontMultiplier: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11 * fontMultiplier, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: 12 * fontMultiplier)
                        .accessibilityHidden(true)

                    configuration.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: max(44, 44 * fontMultiplier))

            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private enum PolicyAvailability {
    case unavailable(String)
    case loading
    case empty
    case filteredEmpty
    case available
}

private struct PolicyGroupMember: Identifiable {
    let id: String
    let name: String
    let details: ProxyNodeViewState?
    let measuredDelay: Int?

    var type: String? { details?.type.nilIfEmpty }
    var alive: Bool? { details?.alive }
    var providerName: String? { details?.providerName }
    var interfaceName: String? { details?.interfaceName }
    var transportNames: [String] { details?.transportNames ?? [] }
    var fixed: String? { details?.fixed }
    var testURL: String? { details?.testURL }
    var icon: String? { details?.icon }
    var historyCount: Int { details?.history.count ?? 0 }
    var latestHistoryDelay: Int? { details?.latestHistoryDelay }
    var latestHistoryTime: String? { details?.latestHistoryTime }
    var additionalMetadataText: String? { details?.additionalMetadataText }
    var delay: Int? { measuredDelay ?? latestHistoryDelay }
}

private struct PolicyDetailMetric: Identifiable {
    var id: String { titleKey }
    let titleKey: String
    let value: String
}
