import MicaCore
import SwiftUI

struct OverviewDashboardToolbarControl: View {
    @Environment(AppModel.self) private var appModel
    @Environment(OverviewDashboardWindowCoordinator.self) private var coordinator
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Button {
            guard let controllerID = appModel.selectedRouterID else { return }
            coordinator.beginEditing(
                controllerID: controllerID,
                undoManager: undoManager
            )
        } label: {
            Label(
                MicaStrings.localizedKey(
                    "overview.layout_edit",
                    language: language
                ),
                systemImage: "rectangle.3.group"
            )
        }
        .disabled(
            appModel.selectedRouterID == nil
                || coordinator.isEditing
                || coordinator.isCommitting
        )
        .help(
            MicaStrings.localizedKey(
                "overview.layout_edit_help",
                language: language
            )
        )
    }
}

struct OverviewDashboardEditorBar: View {
    @Environment(OverviewDashboardWindowCoordinator.self) private var coordinator
    @Environment(\.micaAppLanguage) private var language

    @State private var selectedPreset: OverviewDashboardPreset?
    @State private var dropTarget: OverviewDashboardModuleID?
    @State private var showsContentOptions = false

    var body: some View {
        if let draft = coordinator.draft {
            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                if let conflict = coordinator.conflict {
                    conflictBar(conflict)
                }

                commandRow
                moduleStrip(draft)

                DisclosureGroup(isExpanded: $showsContentOptions) {
                    contentOptions(draft.contentPreferences)
                        .padding(.top, MicaSpacing.row)
                } label: {
                    Label(
                        MicaStrings.localizedKey(
                            "overview.layout_content_options",
                            language: language
                        ),
                        systemImage: "slider.horizontal.3"
                    )
                    .micaFont(.callout, weight: .semibold)
                }

                if let failure = coordinator.lastCommitFailure {
                    failureRow(failure)
                }
            }
            .padding(.horizontal, MicaBounds.chromeHorizontalPadding)
            .padding(.vertical, MicaSpacing.row)
            .background(MicaDesignTokens.pageFill)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var commandRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.module) {
                editorLabel
                presetPicker
                Spacer(minLength: MicaSpacing.module)
                defaultToggle
                resetButton
                cancelButton
                doneButton
            }

            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                HStack(spacing: MicaSpacing.module) {
                    editorLabel
                    Spacer(minLength: MicaSpacing.row)
                    cancelButton
                    doneButton
                }
                ScrollView(.horizontal) {
                    HStack(spacing: MicaSpacing.module) {
                        presetPicker
                        defaultToggle
                        resetButton
                    }
                }
                .scrollIndicators(.visible)
            }
        }
    }

    private var editorLabel: some View {
        Label(
            MicaStrings.localizedKey(
                "overview.layout_editor",
                language: language
            ),
            systemImage: "rectangle.3.group"
        )
        .micaFont(.callout, weight: .semibold)
    }

    private var presetPicker: some View {
        Picker(
            MicaStrings.localizedKey(
                "overview.layout_preset",
                language: language
            ),
            selection: $selectedPreset
        ) {
            ForEach(OverviewDashboardPreset.allCases) { preset in
                Text(presetTitle(preset))
                    .tag(Optional(preset))
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .onChange(of: selectedPreset) { _, preset in
            guard let preset else { return }
            coordinator.applyPreset(
                preset,
                actionName: MicaStrings.localizedKey(
                    "overview.layout_undo_preset",
                    language: language
                )
            )
            selectedPreset = nil
        }
    }

    private var defaultToggle: some View {
        Toggle(
            MicaStrings.localizedKey(
                "overview.layout_set_default",
                language: language
            ),
            isOn: Binding(
                get: { coordinator.setsGlobalDefault },
                set: { enabled in
                    coordinator.setAsGlobalDefault(
                        enabled,
                        actionName: MicaStrings.localizedKey(
                            "overview.layout_undo_default",
                            language: language
                        )
                    )
                }
            )
        )
        .toggleStyle(.checkbox)
        .fixedSize()
    }

    private var resetButton: some View {
        Button {
            coordinator.resetCurrentController(
                actionName: MicaStrings.localizedKey(
                    "overview.layout_undo_reset",
                    language: language
                )
            )
        } label: {
            Label(
                MicaStrings.localizedKey(
                    "overview.layout_reset",
                    language: language
                ),
                systemImage: "arrow.counterclockwise"
            )
        }
    }

    private var cancelButton: some View {
        Button {
            coordinator.cancel()
        } label: {
            Text(
                MicaStrings.localizedKey(
                    "action.cancel",
                    language: language
                )
            )
        }
        .disabled(coordinator.isCommitting)
    }

    private var doneButton: some View {
        Button {
            Task {
                await coordinator.done()
            }
        } label: {
            Text(
                MicaStrings.localizedKey(
                    "action.done",
                    language: language
                )
            )
        }
        .buttonStyle(.borderedProminent)
        .disabled(!coordinator.hasDirtyDraft || coordinator.isCommitting)
    }

    private func moduleStrip(
        _ draft: OverviewDashboardLayout
    ) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: MicaSpacing.module) {
                ForEach(Array(draft.modules.enumerated()), id: \.element.id) {
                    index,
                    configuration in
                    moduleEditor(
                        configuration,
                        index: index,
                        moduleCount: draft.modules.count,
                        visibleCount: draft.visibleModules.count
                    )
                }
            }
        }
        .scrollIndicators(.visible)
    }

    private func moduleEditor(
        _ configuration: OverviewDashboardModuleConfiguration,
        index: Int,
        moduleCount: Int,
        visibleCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            HStack(spacing: MicaSpacing.row) {
                Image(systemName: moduleSymbol(configuration.id))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(moduleTitle(configuration.id))
                    .micaFont(.callout, weight: .semibold)
                    .lineLimit(1)
                Spacer(minLength: MicaSpacing.row)
                Button {
                    coordinator.moveModule(
                        configuration.id,
                        to: index - 1,
                        actionName: moveActionName
                    )
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .frame(
                    width: MicaBounds.iconControlSize,
                    height: MicaBounds.iconControlSize
                )
                .contentShape(Rectangle())
                .disabled(index == 0)
                .help(moveEarlierTitle)
                .accessibilityLabel(moveEarlierTitle)

                Button {
                    coordinator.moveModule(
                        configuration.id,
                        to: index + 1,
                        actionName: moveActionName
                    )
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .frame(
                    width: MicaBounds.iconControlSize,
                    height: MicaBounds.iconControlSize
                )
                .contentShape(Rectangle())
                .disabled(index >= moduleCount - 1)
                .help(moveLaterTitle)
                .accessibilityLabel(moveLaterTitle)
            }

            HStack(spacing: MicaSpacing.module) {
                if configuration.id.legalSizes.count > 1 {
                    Picker(
                        MicaStrings.localizedKey(
                            "overview.layout_size",
                            language: language
                        ),
                        selection: Binding(
                            get: { configuration.size },
                            set: { size in
                                coordinator.setModuleSize(
                                    configuration.id,
                                    size: size,
                                    actionName: MicaStrings.localizedKey(
                                        "overview.layout_undo_size",
                                        language: language
                                    )
                                )
                            }
                        )
                    ) {
                        ForEach(configuration.id.legalSizes) { size in
                            Text(sizeTitle(size)).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                } else {
                    Text(sizeTitle(configuration.size))
                        .micaFont(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    MicaStrings.localizedKey(
                        "overview.layout_visible",
                        language: language
                    ),
                    isOn: Binding(
                        get: { configuration.isVisible },
                        set: { isVisible in
                            coordinator.setModuleVisibility(
                                configuration.id,
                                isVisible: isVisible,
                                actionName: MicaStrings.localizedKey(
                                    "overview.layout_undo_visibility",
                                    language: language
                                )
                            )
                        }
                    )
                )
                .toggleStyle(.checkbox)
                .disabled(configuration.isVisible && visibleCount == 1)
            }
        }
        .padding(MicaSpacing.module)
        .frame(minWidth: 250, alignment: .leading)
        .background(
            dropTarget == configuration.id
                ? MicaDesignTokens.elevatedFill
                : MicaDesignTokens.contentFill,
            in: RoundedRectangle(
                cornerRadius: MicaBounds.moduleRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: MicaBounds.moduleRadius,
                style: .continuous
            )
            .stroke(
                dropTarget == configuration.id
                    ? MicaStyle.signalCyan
                    : MicaStyle.separator.opacity(0.5),
                lineWidth: 1
            )
        }
        .contentShape(Rectangle())
        .draggable(configuration.id.rawValue)
        .dropDestination(for: String.self) { items, _ in
            dropTarget = nil
            guard let rawID = items.first,
                  let draggedID = OverviewDashboardModuleID(rawValue: rawID) else {
                return false
            }
            coordinator.moveModule(
                draggedID,
                to: index,
                actionName: moveActionName
            )
            return true
        } isTargeted: { targeted in
            dropTarget = targeted ? configuration.id : nil
        }
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left where index > 0:
                coordinator.moveModule(
                    configuration.id,
                    to: index - 1,
                    actionName: moveActionName
                )
            case .right where index < moduleCount - 1:
                coordinator.moveModule(
                    configuration.id,
                    to: index + 1,
                    actionName: moveActionName
                )
            default:
                break
            }
        }
    }

    private func contentOptions(
        _ preferences: OverviewDashboardContentPreferences
    ) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: MicaSpacing.section) {
                instrumentOptions(preferences.instrumentMetrics)
                Divider()
                timelineOptions(preferences.timelineWindow)
                Divider()
                summaryOptions(preferences.summaryCategories)
                Divider()
                networkOptions(preferences.networkGroups)
            }
        }
        .scrollIndicators(.visible)
    }

    private func instrumentOptions(
        _ metrics: [OverviewDashboardInstrumentMetricConfiguration]
    ) -> some View {
        optionGroup(
            titleKey: "overview.layout_metrics",
            systemImage: "gauge.with.dots.needle.50percent"
        ) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                orderedToggleRow(
                    title: metricTitle(metric.id),
                    isOn: metric.isVisible,
                    canMoveEarlier: index > 0,
                    canMoveLater: index < metrics.count - 1,
                    canDisable: metric.isVisible
                        ? metrics.filter(\.isVisible).count > 1
                        : true,
                    onToggle: { isVisible in
                        coordinator.updateContentPreferences(
                            actionName: contentActionName
                        ) { content in
                            guard let metricIndex = content.instrumentMetrics.firstIndex(
                                where: { $0.id == metric.id }
                            ) else {
                                return
                            }
                            content.instrumentMetrics[metricIndex].isVisible = isVisible
                        }
                    },
                    onMove: { offset in
                        moveMetric(metric.id, from: index, by: offset)
                    }
                )
            }
        }
    }

    private func timelineOptions(
        _ window: OverviewDashboardTimelineWindow
    ) -> some View {
        optionGroup(
            titleKey: "overview.timeline_window",
            systemImage: "clock.arrow.circlepath"
        ) {
            Picker(
                MicaStrings.localizedKey(
                    "overview.timeline_window",
                    language: language
                ),
                selection: Binding(
                    get: { window },
                    set: { next in
                        coordinator.updateContentPreferences(
                            actionName: contentActionName
                        ) {
                            $0.timelineWindow = next
                        }
                    }
                )
            ) {
                ForEach(OverviewDashboardTimelineWindow.allCases) { value in
                    Text(timelineTitle(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    private func summaryOptions(
        _ categories: [OverviewDashboardSummaryCategoryConfiguration]
    ) -> some View {
        optionGroup(
            titleKey: "overview.operational_summary",
            systemImage: "list.number"
        ) {
            ForEach(Array(categories.enumerated()), id: \.element.id) {
                index,
                category in
                HStack(spacing: MicaSpacing.row) {
                    orderedToggleRow(
                        title: summaryTitle(category.id),
                        isOn: category.isVisible,
                        canMoveEarlier: index > 0,
                        canMoveLater: index < categories.count - 1,
                        canDisable: category.isVisible
                            ? categories.filter(\.isVisible).count > 1
                            : true,
                        onToggle: { isVisible in
                            coordinator.updateContentPreferences(
                                actionName: contentActionName
                            ) { content in
                                guard let categoryIndex =
                                    content.summaryCategories.firstIndex(
                                        where: { $0.id == category.id }
                                    )
                                else {
                                    return
                                }
                                content.summaryCategories[categoryIndex].isVisible =
                                    isVisible
                            }
                        },
                        onMove: { offset in
                            moveSummaryCategory(
                                category.id,
                                from: index,
                                by: offset
                            )
                        }
                    )

                    Picker(
                        MicaStrings.localizedKey(
                            "overview.layout_row_count",
                            language: language
                        ),
                        selection: Binding(
                            get: { category.itemCount },
                            set: { itemCount in
                                coordinator.updateContentPreferences(
                                    actionName: contentActionName
                                ) { content in
                                    guard let categoryIndex =
                                        content.summaryCategories.firstIndex(
                                            where: { $0.id == category.id }
                                        )
                                    else {
                                        return
                                    }
                                    content.summaryCategories[categoryIndex].itemCount =
                                        itemCount
                                }
                            }
                        )
                    ) {
                        ForEach(OverviewDashboardSummaryItemCount.allCases) { count in
                            Text(verbatim: count.rawValue.formatted()).tag(count)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    private func networkOptions(
        _ groups: [OverviewDashboardNetworkGroupID]
    ) -> some View {
        optionGroup(
            titleKey: "overview.network_information",
            systemImage: "network"
        ) {
            ForEach(Array(groups.enumerated()), id: \.element) { index, group in
                HStack(spacing: MicaSpacing.row) {
                    Text(networkGroupTitle(group))
                        .micaFont(.caption)
                    Spacer(minLength: MicaSpacing.row)
                    moveButtons(
                        canMoveEarlier: index > 0,
                        canMoveLater: index < groups.count - 1
                    ) { offset in
                        moveNetworkGroup(group, from: index, by: offset)
                    }
                }
            }
        }
    }

    private func optionGroup<Content: View>(
        titleKey: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            Label(
                MicaStrings.localizedKey(titleKey, language: language),
                systemImage: systemImage
            )
            .micaFont(.caption, weight: .semibold)
            .foregroundStyle(.secondary)
            content()
        }
        .frame(minWidth: 210, alignment: .topLeading)
    }

    private func orderedToggleRow(
        title: String,
        isOn: Bool,
        canMoveEarlier: Bool,
        canMoveLater: Bool,
        canDisable: Bool,
        onToggle: @escaping (Bool) -> Void,
        onMove: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: MicaSpacing.row) {
            Toggle(
                title,
                isOn: Binding(
                    get: { isOn },
                    set: { next in
                        MainActor.assumeIsolated {
                            onToggle(next)
                        }
                    }
                )
            )
            .toggleStyle(.checkbox)
            .disabled(!canDisable)
            Spacer(minLength: MicaSpacing.row)
            moveButtons(
                canMoveEarlier: canMoveEarlier,
                canMoveLater: canMoveLater,
                onMove: onMove
            )
        }
    }

    private func moveButtons(
        canMoveEarlier: Bool,
        canMoveLater: Bool,
        onMove: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: MicaSpacing.tight) {
            Button { onMove(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .frame(
                width: MicaBounds.iconControlSize,
                height: MicaBounds.iconControlSize
            )
            .contentShape(Rectangle())
            .disabled(!canMoveEarlier)
            .help(moveEarlierTitle)
            .accessibilityLabel(moveEarlierTitle)

            Button { onMove(1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .frame(
                width: MicaBounds.iconControlSize,
                height: MicaBounds.iconControlSize
            )
            .contentShape(Rectangle())
            .disabled(!canMoveLater)
            .help(moveLaterTitle)
            .accessibilityLabel(moveLaterTitle)
        }
    }

    private func moveMetric(
        _ id: OverviewDashboardInstrumentMetricID,
        from index: Int,
        by offset: Int
    ) {
        coordinator.updateContentPreferences(actionName: contentActionName) { content in
            guard let source = content.instrumentMetrics.firstIndex(
                where: { $0.id == id }
            ) else {
                return
            }
            let metric = content.instrumentMetrics.remove(at: source)
            let target = min(
                max(index + offset, 0),
                content.instrumentMetrics.endIndex
            )
            content.instrumentMetrics.insert(metric, at: target)
        }
    }

    private func moveSummaryCategory(
        _ id: OverviewDashboardSummaryCategoryID,
        from index: Int,
        by offset: Int
    ) {
        coordinator.updateContentPreferences(actionName: contentActionName) { content in
            guard let source = content.summaryCategories.firstIndex(
                where: { $0.id == id }
            ) else {
                return
            }
            let category = content.summaryCategories.remove(at: source)
            let target = min(
                max(index + offset, 0),
                content.summaryCategories.endIndex
            )
            content.summaryCategories.insert(category, at: target)
        }
    }

    private func moveNetworkGroup(
        _ id: OverviewDashboardNetworkGroupID,
        from index: Int,
        by offset: Int
    ) {
        coordinator.updateContentPreferences(actionName: contentActionName) { content in
            guard let source = content.networkGroups.firstIndex(of: id) else { return }
            let group = content.networkGroups.remove(at: source)
            let target = min(
                max(index + offset, 0),
                content.networkGroups.endIndex
            )
            content.networkGroups.insert(group, at: target)
        }
    }

    private func conflictBar(
        _ conflict: OverviewDashboardWindowConflict
    ) -> some View {
        HStack(spacing: MicaSpacing.module) {
            Label(
                conflictTitle(conflict.kind),
                systemImage: "exclamationmark.triangle"
            )
            .micaFont(.callout, weight: .semibold)
            .foregroundStyle(MicaStyle.signalAmber)
            Spacer(minLength: MicaSpacing.module)

            if conflict.kind == .committedLayoutChanged {
                Button {
                    coordinator.reloadFromCommitted()
                } label: {
                    Text(
                        MicaStrings.localizedKey(
                            "overview.layout_reload",
                            language: language
                        )
                    )
                }

            }

            if conflict.kind != .targetControllerUnavailable {
                keepMineButton
            }
        }
        .padding(.vertical, MicaSpacing.tight)
    }

    private var keepMineButton: some View {
        Button {
            Task {
                await coordinator.keepMineAndCommit()
            }
        } label: {
            Text(
                MicaStrings.localizedKey(
                    "overview.layout_keep_mine",
                    language: language
                )
            )
        }
        .disabled(coordinator.isCommitting)
    }

    private func failureRow(
        _ failure: OverviewDashboardWindowCommitFailure
    ) -> some View {
        Label(
            failureTitle(failure),
            systemImage: "exclamationmark.circle"
        )
        .micaFont(.caption)
        .foregroundStyle(MicaStyle.signalRed)
    }

    private var moveActionName: String {
        MicaStrings.localizedKey("overview.layout_undo_move", language: language)
    }

    private var contentActionName: String {
        MicaStrings.localizedKey("overview.layout_undo_content", language: language)
    }

    private var moveEarlierTitle: String {
        MicaStrings.localizedKey("overview.layout_move_earlier", language: language)
    }

    private var moveLaterTitle: String {
        MicaStrings.localizedKey("overview.layout_move_later", language: language)
    }

    private func moduleTitle(_ id: OverviewDashboardModuleID) -> String {
        let key: String
        switch id {
        case .instrumentRail:
            key = "overview.layout_module_instruments"
        case .telemetry:
            key = "overview.layout_module_telemetry"
        case .operationalSummaries:
            key = "overview.layout_module_summaries"
        case .routeTopology:
            key = "overview.layout_module_topology"
        case .networkInformation:
            key = "overview.layout_module_network"
        }
        return MicaStrings.localizedKey(key, language: language)
    }

    private func moduleSymbol(_ id: OverviewDashboardModuleID) -> String {
        switch id {
        case .instrumentRail:
            "gauge.with.dots.needle.50percent"
        case .telemetry:
            "chart.xyaxis.line"
        case .operationalSummaries:
            "list.number"
        case .routeTopology:
            "point.3.connected.trianglepath.dotted"
        case .networkInformation:
            "network"
        }
    }

    private func presetTitle(_ preset: OverviewDashboardPreset) -> String {
        let key: String
        switch preset {
        case .realTimeSituation:
            key = "overview.layout_preset_realtime"
        case .routeAnalysis:
            key = "overview.layout_preset_routes"
        case .lightweightMonitoring:
            key = "overview.layout_preset_lightweight"
        }
        return MicaStrings.localizedKey(key, language: language)
    }

    private func sizeTitle(_ size: OverviewDashboardModuleSize) -> String {
        let key: String
        switch size {
        case .compact:
            key = "overview.layout_size_compact"
        case .standard:
            key = "overview.layout_size_standard"
        case .full:
            key = "overview.layout_size_full"
        }
        return MicaStrings.localizedKey(key, language: language)
    }

    private func metricTitle(
        _ metric: OverviewDashboardInstrumentMetricID
    ) -> String {
        let key: String
        switch metric {
        case .upload:
            key = "overview.upload_rate"
        case .download:
            key = "overview.download_rate"
        case .activeConnections:
            key = "dashboard.active_sessions"
        case .memoryUsage:
            key = "overview.memory_current"
        }
        return MicaStrings.localizedKey(key, language: language)
    }

    private func timelineTitle(
        _ window: OverviewDashboardTimelineWindow
    ) -> String {
        MicaStrings.localizedKey(
            window.projectionWindow.titleKey,
            language: language
        )
    }

    private func summaryTitle(
        _ category: OverviewDashboardSummaryCategoryID
    ) -> String {
        let key: String
        switch category {
        case .latency:
            key = "overview.latency_distribution"
        case .ruleHits:
            key = "overview.rule_hits"
        case .activeConnections:
            key = "overview.top_connections"
        }
        return MicaStrings.localizedKey(key, language: language)
    }

    private func networkGroupTitle(
        _ group: OverviewDashboardNetworkGroupID
    ) -> String {
        let key: String
        switch group {
        case .controllerIdentity:
            key = "overview.network_group_controller"
        case .runtimeAndFeatures:
            key = "overview.network_group_runtime"
        case .listenerPorts:
            key = "overview.network_group_listeners"
        }
        return MicaStrings.localizedKey(key, language: language)
    }

    private func conflictTitle(
        _ conflict: OverviewDashboardWindowConflictKind
    ) -> String {
        let key: String
        switch conflict {
        case .committedLayoutChanged:
            key = "overview.layout_conflict_external"
        case .selectedControllerChanged:
            key = "overview.layout_conflict_controller"
        case .targetControllerUnavailable:
            key = "overview.layout_conflict_deleted"
        }
        return MicaStrings.localizedKey(key, language: language)
    }

    private func failureTitle(
        _ failure: OverviewDashboardWindowCommitFailure
    ) -> String {
        let key: String
        switch failure {
        case .conflict:
            key = "overview.layout_failure_conflict"
        case .targetControllerUnavailable:
            key = "overview.layout_failure_deleted"
        case .persistence:
            key = "overview.layout_failure_persistence"
        }
        return MicaStrings.localizedKey(key, language: language)
    }
}
