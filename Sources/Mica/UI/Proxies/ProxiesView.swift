import AppKit
import MicaCore
import SwiftUI

struct ProxiesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkspaceUIState.self) private var uiState
    @EnvironmentObject private var preferences: AppPreferencesStore
    @Environment(\.micaAppLanguage) private var language

    @Binding var searchText: String
    @State private var store = ProxiesStore()

    var body: some View {
        let _ = syncStore()

        Group {
            if store.groups.isEmpty {
                emptyCatalogView
            } else {
                HStack(spacing: 0) {
                    groupSidebar
                        .frame(width: 216)

                    MicaHairlineDivider(axis: .vertical)

                    if let activeGroup = store.activeGroupSummary {
                        nodeWorkspace(for: activeGroup)
                    } else {
                        MicaEmptyStateView(
                            systemImage: "point.3.connected.trianglepath.dotted",
                            title: L("dashboard.no_routing_modules_loaded", language: language)
                        )
                    }
                }
            }
        }
        .background(MicaTheme.canvas)
        .onChange(of: searchText) { _, newValue in
            store.searchQuery = newValue
        }
        .onChange(of: uiState.pendingProxyGroupID) { _, groupID in
            if let groupID {
                store.selectedGroupID = groupID
                uiState.pendingProxyGroupID = nil
            }
        }
        .onAppear {
            store.searchQuery = searchText
            if let pending = uiState.pendingProxyGroupID {
                store.selectedGroupID = pending
                uiState.pendingProxyGroupID = nil
            }
        }
    }

    private func syncStore() {
        store.sync(
            catalog: appModel.policyGroupCatalog,
            revision: appModel.policyGroupCatalogRevision,
            visibility: preferences.globalGroupVisibility,
            controllerID: appModel.selectedRouterID,
            preferredGroupID: uiState.pendingProxyGroupID
        )
    }

    @ViewBuilder
    private var emptyCatalogView: some View {
        switch appModel.controllerSessionPresentation.state {
        case .connecting:
            MicaEmptyStateView(
                systemImage: "arrow.triangle.2.circlepath",
                title: L("overview.connecting_title", language: language),
                message: L("overview.connecting_message", language: language)
            )
        default:
            MicaEmptyStateView(
                systemImage: "point.3.connected.trianglepath.dotted",
                title: L("dashboard.no_routing_modules_loaded", language: language),
                message: L("dashboard.no_routing_modules_hint", language: language),
                actionTitle: L("action.refresh", language: language),
                action: appModel.canRefreshSelectedRouter ? { appModel.refreshSelectedRouter() } : nil
            )
        }
    }

    // MARK: - Group Rail

    private var groupSidebar: some View {
        List(store.groups, selection: Binding(
            get: { store.selectedGroupID },
            set: { store.selectedGroupID = $0 }
        )) { group in
            ProxyGroupRailRow(group: group, language: language)
                .tag(group.id)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(MicaTheme.subtleFill)
    }

    // MARK: - Node Workspace

    @ViewBuilder
    private func nodeWorkspace(for group: ProxyGroupSummary) -> some View {
        let scope = currentCommandScope
        let commandsEnabled = appModel.controllerSessionPresentation.state.allowsLiveCommands
        let isSurge = appModel.selectedRouter.map { appModel.runtimeControllerKind(for: $0) == .surgeCompatible } ?? false
        let isTestingGroup = appModel.measuringDelayGroupID == group.id || appModel.testingSurgePolicyGroup == group.id
        let isSwitchingGroup = appModel.switchingGroupID == group.id || appModel.switchingSurgePolicyGroup == group.id
        let isClearingFixed = appModel.clearingFixedGroupID == group.id

        VStack(spacing: 0) {
            groupHeader(
                group: group,
                commandsEnabled: commandsEnabled,
                isSurge: isSurge,
                isTestingGroup: isTestingGroup,
                isSwitchingGroup: isSwitchingGroup,
                isClearingFixed: isClearingFixed,
                scope: scope
            )

            MicaHairlineDivider()

            if store.visibleNodes.isEmpty {
                MicaEmptyStateView(
                    systemImage: "magnifyingglass",
                    title: L("routing.members_filtered_empty", language: language),
                    actionTitle: store.filter != .all || !store.searchQuery.isEmpty
                        ? L("action.clear_search", language: language)
                        : nil,
                    action: {
                        store.filter = .all
                        searchText = ""
                    }
                )
            } else if store.layoutMode == .grid {
                nodeGrid(
                    group: group,
                    commandsEnabled: commandsEnabled,
                    isSurge: isSurge,
                    isSwitchingGroup: isSwitchingGroup,
                    scope: scope
                )
            } else {
                nodeList(
                    group: group,
                    commandsEnabled: commandsEnabled,
                    isSurge: isSurge,
                    isSwitchingGroup: isSwitchingGroup,
                    scope: scope
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func groupHeader(
        group: ProxyGroupSummary,
        commandsEnabled: Bool,
        isSurge: Bool,
        isTestingGroup: Bool,
        isSwitchingGroup: Bool,
        isClearingFixed: Bool,
        scope: LiveCommandScope?
    ) -> some View {
        HStack(spacing: MicaTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MicaTheme.Spacing.sm) {
                    Text(verbatim: group.name)
                        .font(.headline)
                        .foregroundStyle(MicaTheme.textPrimary)
                        .lineLimit(1)

                    Text(verbatim: group.type)
                        .font(.caption2)
                        .foregroundStyle(MicaTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MicaTheme.subtleFill, in: Capsule())
                }

                HStack(spacing: MicaTheme.Spacing.xs) {
                    if !group.selected.isEmpty {
                        Text(verbatim: group.selected)
                            .font(.caption)
                            .foregroundStyle(MicaTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Text(verbatim: "· \(store.visibleNodes.count)/\(group.nodeCount)")
                        .font(.caption)
                        .foregroundStyle(MicaTheme.textTertiary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: MicaTheme.Spacing.sm)

            Picker(L("routing.health_filter_all", language: language), selection: $store.filter) {
                ForEach(ProxyFilter.allCases) { item in
                    Text(L(item.titleKey, language: language)).tag(item)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 120)

            Picker(L("routing.source_order", language: language), selection: $store.sortOrder) {
                ForEach(ProxySortOrder.allCases) { order in
                    Text(L(order.titleKey, language: language)).tag(order)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 120)

            Picker("", selection: $store.layoutMode) {
                Image(systemName: "square.grid.2x2").tag(ProxyLayoutMode.grid)
                Image(systemName: "list.bullet").tag(ProxyLayoutMode.list)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 68)

            if group.hasFixedSelection, !isSurge {
                Button {
                    guard let scope else { return }
                    appModel.clearFixedSelection(in: group.id, scope: scope)
                } label: {
                    Image(systemName: MicaSymbols.Command.unpin)
                }
                .disabled(!commandsEnabled || isClearingFixed || isSwitchingGroup)
                .help(L("action.clear_fixed_selection", language: language))
            }

            Button {
                guard let scope else { return }
                if isSurge {
                    appModel.testSurgePolicyGroup(group.id, scope: scope)
                } else {
                    appModel.measureDelay(in: group.id, scope: scope)
                }
            } label: {
                if isTestingGroup {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L("routing.test_group", language: language), systemImage: "bolt")
                }
            }
            .disabled(!commandsEnabled || isTestingGroup || isSwitchingGroup)
        }
        .padding(.horizontal, MicaTheme.Spacing.lg)
        .padding(.vertical, MicaTheme.Spacing.md)
    }

    private func nodeGrid(
        group: ProxyGroupSummary,
        commandsEnabled: Bool,
        isSurge: Bool,
        isSwitchingGroup: Bool,
        scope: LiveCommandScope?
    ) -> some View {
        let columns = [GridItem(.adaptive(minimum: 185, maximum: 260), spacing: 8)]
        let inspectedName = inspectedNodeName(for: group.id)
        let measuringNode = appModel.measuringDelayNode

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(store.visibleNodes) { node in
                    let isMeasuring = measuringNode?.groupID == node.groupID && measuringNode?.nodeName == node.name
                    ProxyNodeGridTile(
                        node: node,
                        isInspected: inspectedName == node.name,
                        canSelect: group.selectable && commandsEnabled && !isSwitchingGroup,
                        canTest: !isSurge && commandsEnabled,
                        isMeasuring: isMeasuring,
                        language: language,
                        onPrimaryTap: {
                            if group.selectable, commandsEnabled, !isSwitchingGroup, !node.isSelected {
                                selectNode(node.name, in: node.groupID, isSurge: isSurge, scope: scope)
                            } else {
                                uiState.selectInspector(.proxyNode(groupID: node.groupID, nodeName: node.name))
                            }
                        },
                        onSelect: {
                            selectNode(node.name, in: node.groupID, isSurge: isSurge, scope: scope)
                        },
                        onTest: {
                            guard let scope, !isSurge else { return }
                            appModel.measureDelay(for: node.name, in: node.groupID, scope: scope)
                        },
                        onInspect: {
                            uiState.selectInspector(.proxyNode(groupID: node.groupID, nodeName: node.name))
                        }
                    )
                    .equatable()
                }
            }
            .padding(MicaTheme.Spacing.lg)
        }
    }

    private func nodeList(
        group: ProxyGroupSummary,
        commandsEnabled: Bool,
        isSurge: Bool,
        isSwitchingGroup: Bool,
        scope: LiveCommandScope?
    ) -> some View {
        let inspectedName = inspectedNodeName(for: group.id)
        let measuringNode = appModel.measuringDelayNode

        return List(store.visibleNodes) { node in
            let isMeasuring = measuringNode?.groupID == node.groupID && measuringNode?.nodeName == node.name
            ProxyNodeListRow(
                node: node,
                isInspected: inspectedName == node.name,
                canSelect: group.selectable && commandsEnabled && !isSwitchingGroup,
                canTest: !isSurge && commandsEnabled,
                isMeasuring: isMeasuring,
                language: language,
                onSelect: {
                    selectNode(node.name, in: node.groupID, isSurge: isSurge, scope: scope)
                },
                onTest: {
                    guard let scope, !isSurge else { return }
                    appModel.measureDelay(for: node.name, in: node.groupID, scope: scope)
                },
                onInspect: {
                    uiState.selectInspector(.proxyNode(groupID: node.groupID, nodeName: node.name))
                }
            )
            .equatable()
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func selectNode(_ name: String, in groupID: String, isSurge: Bool, scope: LiveCommandScope?) {
        guard let scope else { return }
        if isSurge {
            appModel.selectSurgePolicy(name, in: groupID, scope: scope)
        } else {
            appModel.selectNode(name, in: groupID, scope: scope)
        }
    }

    private func inspectedNodeName(for groupID: String) -> String? {
        if case let .proxyNode(inspectedGroupID, nodeName) = uiState.inspectorSelection,
           inspectedGroupID == groupID {
            return nodeName
        }
        return nil
    }

    private var currentCommandScope: LiveCommandScope? {
        LiveCommandScope(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
    }
}

// MARK: - Subviews (Equatable for minimal SwiftUI diffing)

private struct ProxyGroupRailRow: View, Equatable {
    let group: ProxyGroupSummary
    let language: AppLanguage

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.group == rhs.group && lhs.language == rhs.language
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(verbatim: group.name)
                    .font(.body)
                    .foregroundStyle(MicaTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let delay = group.selectedDelay {
                    Text(verbatim: MicaFormatters.formatLatency(delay, language: language))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(MicaTheme.latencyColor(for: delay))
                }
            }
            HStack(spacing: 4) {
                Text(verbatim: group.selected.isEmpty ? group.type : group.selected)
                    .font(.caption)
                    .foregroundStyle(MicaTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: "\(group.nodeCount)")
                    .font(.caption2)
                    .foregroundStyle(MicaTheme.textTertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ProxyNodeGridTile: View, Equatable {
    let node: ProxyNodeCardModel
    let isInspected: Bool
    let canSelect: Bool
    let canTest: Bool
    let isMeasuring: Bool
    let language: AppLanguage
    let onPrimaryTap: @MainActor @Sendable () -> Void
    let onSelect: @MainActor @Sendable () -> Void
    let onTest: @MainActor @Sendable () -> Void
    let onInspect: @MainActor @Sendable () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.node == rhs.node
            && lhs.isInspected == rhs.isInspected
            && lhs.canSelect == rhs.canSelect
            && lhs.canTest == rhs.canTest
            && lhs.isMeasuring == rhs.isMeasuring
            && lhs.language == rhs.language
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MicaTheme.Radius.card, style: .continuous)
        let borderColor: Color = node.isSelected
            ? MicaTheme.accent.opacity(0.6)
            : (isInspected ? MicaTheme.textSecondary.opacity(0.5) : MicaTheme.separator)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Text(verbatim: node.name)
                    .font(.system(.callout, weight: node.isSelected ? .semibold : .regular))
                    .foregroundStyle(MicaTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if node.isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(MicaTheme.accent)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: subtitleText)
                    .font(.caption2)
                    .foregroundStyle(MicaTheme.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Button(action: onTest) {
                    if isMeasuring {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Text(verbatim: MicaFormatters.formatLatency(node.delay, alive: node.alive, language: language))
                            .font(.system(.caption, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(MicaTheme.latencyColor(for: node.delay, alive: node.alive))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canTest || isMeasuring)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(node.isSelected ? MicaTheme.selectedFill : MicaTheme.surface, in: shape)
        .overlay {
            shape.strokeBorder(borderColor, lineWidth: node.isSelected ? 1.25 : 0.75)
        }
        .contentShape(shape)
        .onTapGesture(perform: onPrimaryTap)
        .contextMenu {
            if canSelect, !node.isSelected {
                Button(L("routing.use_node \(node.name)", language: language), action: onSelect)
            }
            if canTest {
                Button(L("action.test_delay", language: language), action: onTest)
            }
            Button(L("routing.inspect_details", language: language), action: onInspect)
            Divider()
            Button(L("action.copy_name", language: language)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.name, forType: .string)
            }
        }
    }

    private var subtitleText: String {
        if let type = node.type, let provider = node.providerName {
            return "\(type) · \(provider)"
        }
        return node.type ?? node.providerName ?? "-"
    }
}

private struct ProxyNodeListRow: View, Equatable {
    let node: ProxyNodeCardModel
    let isInspected: Bool
    let canSelect: Bool
    let canTest: Bool
    let isMeasuring: Bool
    let language: AppLanguage
    let onSelect: @MainActor @Sendable () -> Void
    let onTest: @MainActor @Sendable () -> Void
    let onInspect: @MainActor @Sendable () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.node == rhs.node
            && lhs.isInspected == rhs.isInspected
            && lhs.canSelect == rhs.canSelect
            && lhs.canTest == rhs.canTest
            && lhs.isMeasuring == rhs.isMeasuring
            && lhs.language == rhs.language
    }

    var body: some View {
        HStack(spacing: MicaTheme.Spacing.md) {
            MicaStatusDot(
                color: node.isSelected ? MicaTheme.accent : MicaTheme.latencyColor(for: node.delay, alive: node.alive),
                size: 7
            )

            Text(verbatim: node.name)
                .font(.system(.body, weight: node.isSelected ? .semibold : .regular))
                .foregroundStyle(MicaTheme.textPrimary)
                .lineLimit(1)

            if let type = node.type {
                Text(verbatim: type)
                    .font(.caption2)
                    .foregroundStyle(MicaTheme.textSecondary)
            }

            if let provider = node.providerName {
                Text(verbatim: provider)
                    .font(.caption2)
                    .foregroundStyle(MicaTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: MicaTheme.Spacing.sm)

            Button(action: onTest) {
                if isMeasuring {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(verbatim: MicaFormatters.formatLatency(node.delay, alive: node.alive, language: language))
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(MicaTheme.latencyColor(for: node.delay, alive: node.alive))
                }
            }
            .buttonStyle(.borderless)
            .disabled(!canTest || isMeasuring)

            Button(action: onInspect) {
                Image(systemName: isInspected ? "info.circle.fill" : "info.circle")
                    .foregroundStyle(isInspected ? MicaTheme.accent : MicaTheme.textSecondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if canSelect, !node.isSelected {
                onSelect()
            } else {
                onInspect()
            }
        }
        .contextMenu {
            if canSelect, !node.isSelected {
                Button(L("routing.use_node \(node.name)", language: language), action: onSelect)
            }
            if canTest {
                Button(L("action.test_delay", language: language), action: onTest)
            }
            Button(L("routing.inspect_details", language: language), action: onInspect)
            Divider()
            Button(L("action.copy_name", language: language)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.name, forType: .string)
            }
        }
    }
}
