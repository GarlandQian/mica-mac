import Foundation
import MicaCore
import SwiftUI

struct WorkbenchOverviewView: View {
    @Binding var destination: WorkbenchDestination

    var body: some View {
        WorkbenchPageScaffold(
            commands: {
                OverviewDashboardEditorBar()
            },
            content: {
                OverviewAvailabilityRegion(destination: $destination)
            }
        )
    }
}

private struct OverviewAvailabilityRegion: View {
    @Environment(AppModel.self) private var appModel
    @Environment(OverviewDashboardLayoutStore.self) private var layoutStore
    @Environment(OverviewDashboardWindowCoordinator.self) private var layoutCoordinator
    @Environment(\.micaAppLanguage) private var language

    @Binding var destination: WorkbenchDestination

    var body: some View {
        switch appModel.controllerSessionPresentation.state {
        case .live, .partial, .staleReconnecting:
            if let controllerID = appModel.selectedRouterID {
                let effectiveState = layoutStore.effectiveState(for: controllerID)
                let layout = layoutCoordinator.targetControllerID == controllerID
                    ? layoutCoordinator.draft ?? effectiveState.layout
                    : effectiveState.layout

                OverviewDashboardCanvas(
                    controllerID: controllerID,
                    generation: appModel.controllerSessionPresentation.generation,
                    layout: layout,
                    destination: $destination
                )
                .onChange(of: effectiveState.revisionToken) {
                    reconcileLayoutCoordinator()
                }
            } else {
                unavailableState
            }
        case .connecting:
            WorkbenchStateView(
                kind: .loading,
                titleKey: "overview.connecting_title",
                detailKey: "overview.connecting_message"
            )
        case .failedBeforeFirstSnapshot(let message), .failed(let message):
            WorkbenchStateView(
                kind: .failed,
                titleKey: "dashboard.failed",
                detailKey: "overview.no_controller_data",
                message: message,
                actionTitleKey: "action.refresh",
                isActionEnabled: appModel.canRefreshSelectedRouter,
                action: appModel.refreshSelectedRouter
            )
        case .stopped:
            WorkbenchStateView(
                kind: .empty,
                titleKey: "live.state_stopped",
                detailKey: "live.detail_stopped"
            )
        case .idle:
            unavailableState
        }
    }

    private var unavailableState: some View {
        if appModel.selectedRouter == nil {
            return WorkbenchStateView(
                kind: .noController,
                titleKey: "dashboard.connect_router",
                detailKey: "dashboard.connect_router_message"
            )
        }

        if selectedRuntimeIsUnsupported {
            return WorkbenchStateView(
                kind: .unsupported,
                titleKey: "compatibility.unsupported",
                detailKey: "unified.boundary_unsupported"
            )
        }

        return WorkbenchStateView(
            kind: .empty,
            titleKey: "overview.no_controller_data",
            detailKey: "dashboard.refresh_snapshot",
            actionTitleKey: "action.refresh",
            isActionEnabled: appModel.canRefreshSelectedRouter,
            action: appModel.refreshSelectedRouter
        )
    }

    private var selectedRuntimeIsUnsupported: Bool {
        guard let router = appModel.selectedRouter else { return false }
        return appModel.runtimeControllerKind(for: router) == .unsupported
    }

    private func reconcileLayoutCoordinator() {
        let targetExists = layoutCoordinator.targetControllerID.map { targetID in
            appModel.routers.contains { $0.id == targetID }
        } ?? true
        layoutCoordinator.reconcile(
            selectedControllerID: appModel.selectedRouterID,
            targetControllerExists: targetExists
        )
    }
}

private struct OverviewDashboardCanvas: View {
    @Environment(OverviewDashboardWindowCoordinator.self) private var coordinator

    let controllerID: RouterProfile.ID
    let generation: UUID
    let layout: OverviewDashboardLayout
    @Binding var destination: WorkbenchDestination

    var body: some View {
        GeometryReader { geometry in
            let pagePadding = MicaBounds.pagePadding(for: geometry.size.width)
            let availableWidth = max(geometry.size.width - pagePadding * 2, 0)
            let widthMode = widthMode(for: availableWidth)
            let rows = OverviewDashboardRowPacker.rows(
                for: layout,
                widthMode: widthMode
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: MicaSpacing.section) {
                    ForEach(rows) { row in
                        OverviewDashboardResponsiveRow(
                            row: row,
                            widthMode: widthMode,
                            availableWidth: availableWidth,
                            controllerID: controllerID,
                            generation: generation,
                            layout: layout,
                            destination: $destination
                        )
                    }
                }
                .id(generation)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(pagePadding)
            }
            .micaObserveScrollPerformance()
            .onAppear {
                coordinator.runtimeRegistry.prepare(
                    controllerID: controllerID,
                    generation: generation
                )
            }
        }
    }

    private func widthMode(for width: CGFloat) -> OverviewDashboardGridWidthMode {
        if width >= 900 {
            return .wide
        }
        if width >= 560 {
            return .medium
        }
        return .narrow
    }
}

private struct OverviewDashboardResponsiveRow: View {
    @Environment(OverviewDashboardWindowCoordinator.self) private var coordinator

    let row: OverviewDashboardPackedRow
    let widthMode: OverviewDashboardGridWidthMode
    let availableWidth: CGFloat
    let controllerID: RouterProfile.ID
    let generation: UUID
    let layout: OverviewDashboardLayout
    @Binding var destination: WorkbenchDestination

    var body: some View {
        OverviewDashboardSpanLayout(
            spans: row.modules.map(\.columnSpan),
            columnCount: widthMode.columnCount,
            spacing: MicaSpacing.section
        ) {
            ForEach(row.modules) { module in
                moduleView(
                    module.configuration,
                    availableWidth: estimatedWidth(for: module)
                )
                .allowsHitTesting(!coordinator.isEditing)
                .disabled(coordinator.isEditing)
            }
        }
    }

    @ViewBuilder
    private func moduleView(
        _ configuration: OverviewDashboardModuleConfiguration,
        availableWidth: CGFloat
    ) -> some View {
        switch configuration.id {
        case .instrumentRail:
            OverviewInstrumentRailSection(
                availableWidth: availableWidth,
                metrics: layout.contentPreferences.instrumentMetrics
            )
        case .telemetry:
            let runtime = coordinator.runtimeRegistry.telemetryRuntime(
                controllerID: controllerID,
                generation: generation,
                preferredWindow: layout.contentPreferences.timelineWindow
            )
            OverviewTelemetrySection(
                availableWidth: availableWidth,
                preferredTimelineWindow: layout.contentPreferences.timelineWindow,
                runtime: runtime
            )
        case .operationalSummaries:
            OverviewHighlightsSection(
                availableWidth: availableWidth,
                configurations: layout.contentPreferences.summaryCategories,
                destination: $destination
            )
        case .routeTopology:
            let runtime = coordinator.runtimeRegistry.topologyRuntime(
                controllerID: controllerID,
                generation: generation
            )
            OverviewTopologySection(
                runtime: runtime,
                destination: $destination
            )
        case .networkInformation:
            OverviewNetworkFactsSection(
                groupOrder: layout.contentPreferences.networkGroups
            )
        }
    }

    private func estimatedWidth(
        for module: OverviewDashboardPackedModule
    ) -> CGFloat {
        let unit = (availableWidth + MicaSpacing.section)
            / CGFloat(widthMode.columnCount)
        return max(unit * CGFloat(module.columnSpan) - MicaSpacing.section, 0)
    }
}

private struct OverviewDashboardSpanLayout: Layout {
    let spans: [Int]
    let columnCount: Int
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width
            ?? subviews.reduce(CGFloat.zero) {
                $0 + $1.sizeThatFits(.unspecified).width
            }
        let widths = childWidths(totalWidth: width, count: subviews.count)
        let height = zip(subviews, widths).reduce(CGFloat.zero) { result, pair in
            max(
                result,
                pair.0.sizeThatFits(
                    ProposedViewSize(width: pair.1, height: proposal.height)
                ).height
            )
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let widths = childWidths(totalWidth: bounds.width, count: subviews.count)
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: nil)
            )
            x += width + spacing
        }
    }

    private func childWidths(totalWidth: CGFloat, count: Int) -> [CGFloat] {
        guard count > 0, columnCount > 0 else { return [] }
        let unit = (totalWidth + spacing) / CGFloat(columnCount)
        return (0..<count).map { index in
            let span = index < spans.count ? spans[index] : columnCount
            return max(unit * CGFloat(span) - spacing, 0)
        }
    }
}

struct OverviewSymbolMark: View {
    enum Size {
        case section
        case metric

        var font: Font {
            switch self {
            case .section: .title3.weight(.semibold)
            case .metric: .callout.weight(.semibold)
            }
        }

        var frameSize: CGFloat {
            switch self {
            case .section: 34
            case .metric: 28
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .section: 8
            case .metric: 6
            }
        }

        var fillOpacity: Double {
            switch self {
            case .section: 0.14
            case .metric: 0.11
            }
        }
    }

    let systemName: String
    let tint: Color
    let size: Size

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.hierarchical)
            .font(size.font)
            .foregroundStyle(tint)
            .frame(width: size.frameSize, height: size.frameSize)
            .background {
                RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                    .fill(tint.opacity(size.fillOpacity))
            }
            .accessibilityHidden(true)
    }
}

struct OverviewFlatSection<Accessory: View, Content: View>: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let systemImage: String
    let tint: Color
    private let accessory: Accessory
    private let content: Content

    init(
        _ titleKey: String,
        systemImage: String,
        tint: Color = MicaStyle.signalCyan,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.module) {
            HStack(spacing: MicaSpacing.row) {
                HStack(spacing: MicaSpacing.row) {
                    OverviewSymbolMark(
                        systemName: systemImage,
                        tint: tint,
                        size: .section
                    )
                    Text(MicaStrings.localizedKey(titleKey, language: language))
                        .micaFont(.title3, weight: .semibold)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: MicaSpacing.module)
                accessory
            }

            content
        }
        .padding(.top, MicaSpacing.module)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
    }
}

extension OverviewFlatSection where Accessory == EmptyView {
    init(
        _ titleKey: String,
        systemImage: String,
        tint: Color = MicaStyle.signalCyan,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            titleKey,
            systemImage: systemImage,
            tint: tint,
            accessory: { EmptyView() },
            content: content
        )
    }
}

private struct OverviewHighlightsSection: View {
    @Environment(\.micaAppLanguage) private var language

    let availableWidth: CGFloat
    let configurations: [OverviewDashboardSummaryCategoryConfiguration]
    @Binding var destination: WorkbenchDestination
    @State private var selectedPane = OverviewDashboardSummaryCategoryID.latency

    var body: some View {
        let visibleConfigurations = configurations.filter(\.isVisible)

        OverviewFlatSection(
            "overview.operational_summary",
            systemImage: "gauge.with.dots.needle.67percent"
        ) {
            if availableWidth >= 860 {
                HStack(alignment: .top, spacing: MicaSpacing.section) {
                    ForEach(
                        Array(visibleConfigurations.enumerated()),
                        id: \.element.id
                    ) { index, configuration in
                        if index > 0 {
                            Divider()
                        }
                        summaryView(for: configuration)
                            .frame(
                                minWidth: 220,
                                maxWidth: .infinity,
                                alignment: .topLeading
                            )
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: MicaSpacing.module) {
                    Picker(
                        MicaStrings.localizedKey(
                            "overview.operational_summary",
                            language: language
                        ),
                        selection: $selectedPane
                    ) {
                        ForEach(visibleConfigurations) { configuration in
                            Text(
                                MicaStrings.localizedKey(
                                    configuration.id.titleKey,
                                    language: language
                                )
                            )
                            .tag(configuration.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()

                    if let selectedConfiguration {
                        summaryView(for: selectedConfiguration)
                    }
                }
            }
        }
        .onChange(of: visibleConfigurations.map(\.id), initial: true) {
            guard !visibleConfigurations.contains(where: { $0.id == selectedPane }),
                  let first = visibleConfigurations.first else {
                return
            }
            selectedPane = first.id
        }
    }

    private var selectedConfiguration:
        OverviewDashboardSummaryCategoryConfiguration?
    {
        configurations.first {
            $0.isVisible && $0.id == selectedPane
        } ?? configurations.first(where: \.isVisible)
    }

    @ViewBuilder
    private func summaryView(
        for configuration: OverviewDashboardSummaryCategoryConfiguration
    ) -> some View {
        switch configuration.id {
        case .latency:
            OverviewLatencyHighlightsSection(
                maximumCount: configuration.itemCount.rawValue,
                destination: $destination
            )
        case .ruleHits:
            OverviewRuleHighlightsSection(
                maximumCount: configuration.itemCount.rawValue,
                destination: $destination
            )
        case .activeConnections:
            OverviewConnectionHighlightsSection(
                maximumCount: configuration.itemCount.rawValue,
                destination: $destination
            )
        }
    }
}

private extension OverviewDashboardSummaryCategoryID {
    var titleKey: String {
        switch self {
        case .latency:
            "overview.latency_distribution"
        case .ruleHits:
            "overview.rule_hits"
        case .activeConnections:
            "overview.top_connections"
        }
    }
}

private struct OverviewSummaryColumn<Content: View>: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let systemImage: String
    private let content: Content

    init(
        titleKey: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            HStack(spacing: MicaSpacing.tight) {
                WorkbenchSymbol(
                    systemName: systemImage,
                    font: .caption.weight(.semibold),
                    frameSize: 16
                )
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct OverviewLatencyHighlightsSection: View {
    @Environment(AppModel.self) private var appModel

    let maximumCount: Int
    @Binding var destination: WorkbenchDestination

    var body: some View {
        let rows = OverviewProjection.latencyAnomalies(
            from: appModel.policyGroupCatalog.groups,
            maximumCount: maximumCount
        )

        OverviewSummaryColumn(
            titleKey: "overview.latency_distribution",
            systemImage: "exclamationmark.triangle"
        ) {
            if rows.isEmpty {
                OverviewInlineState(
                    titleKey: "overview.latency_distribution_empty",
                    detailKey: "overview.no_latency_history_detail"
                )
            } else {
                ForEach(rows) { row in
                    Button {
                        destination = .proxies
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.row) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: row.groupName)
                                    .micaFont(.callout, weight: .medium)
                                    .textSelection(.enabled)
                                Text(verbatim: row.nodeName)
                                    .micaFont(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: MicaSpacing.row)
                            Text(verbatim: OverviewFormat.latency(row.delay))
                                .micaFont(.body, design: .monospaced)
                                .foregroundStyle(OverviewFormat.latencyTint(row.delay))
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: MicaBounds.controlMinHeight)
                    .accessibilityLabel("\(row.groupName), \(row.nodeName), \(OverviewFormat.latency(row.delay))")
                }
            }
        }
    }
}

private struct OverviewRuleHighlightsSection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let maximumCount: Int
    @Binding var destination: WorkbenchDestination

    var body: some View {
        let rows = OverviewProjection.ruleHitSummary(
            from: appModel.routingCatalog.rules,
            maximumCount: maximumCount
        )

        OverviewSummaryColumn(titleKey: "overview.rule_hits", systemImage: "scope") {
            if rows.isEmpty {
                OverviewInlineState(titleKey: "overview.no_rules", detailKey: "overview.no_rules_detail")
            } else {
                ForEach(rows) { row in
                    Button {
                        destination = .rules
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.row) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: row.label.overviewNonBlank ?? unavailableText)
                                    .micaFont(.callout, weight: .medium)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                                Text(verbatim: row.proxy.overviewNonBlank ?? unavailableText)
                                    .micaFont(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: MicaSpacing.row)
                            Text(verbatim: ruleCountText(row))
                                .micaFont(.body, design: .monospaced)
                                .foregroundStyle(MicaStyle.signalCyan)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: MicaBounds.controlMinHeight)
                    .accessibilityLabel(
                        "\(row.label.overviewNonBlank ?? unavailableText), \(ruleCountText(row))"
                    )
                }
            }
        }
    }

    private var unavailableText: String {
        MicaStrings.localizedKey("overview.config_not_reported", language: language)
    }

    private func ruleCountText(_ row: OverviewRuleHitSummary) -> String {
        let hits = row.hits?.formatted() ?? unavailableText
        let misses = row.misses?.formatted() ?? unavailableText
        return "\(hits) / \(misses)"
    }
}

private struct OverviewConnectionHighlightsSection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language

    let maximumCount: Int
    @Binding var destination: WorkbenchDestination

    var body: some View {
        let rows = OverviewProjection.topActiveConnections(
            from: appModel.connectionsCatalog.connections,
            maximumCount: maximumCount
        )

        OverviewSummaryColumn(
            titleKey: "overview.top_connections",
            systemImage: "arrow.up.right.circle"
        ) {
            if rows.isEmpty {
                OverviewInlineState(
                    titleKey: "overview.top_connections_empty",
                    detailKey: "overview.connections_unavailable_detail"
                )
            } else {
                ForEach(rows) { row in
                    Button {
                        openConnection(row.connectionID)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.row) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: row.label.overviewNonBlank ?? unavailableText)
                                    .micaFont(.callout, weight: .medium)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                                if let connectionID = row.connectionID.overviewNonBlank {
                                    Text(verbatim: connectionID)
                                        .micaFont(.caption, design: .monospaced)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            Spacer(minLength: MicaSpacing.row)
                            Text(verbatim: row.totalTraffic.map(OverviewFormat.bytes) ?? unavailableText)
                                .micaFont(.body, design: .monospaced)
                                .foregroundStyle(MicaStyle.signalCyan)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: MicaBounds.controlMinHeight)
                    .accessibilityLabel("\(row.label.overviewNonBlank ?? unavailableText), \(row.totalTraffic.map(OverviewFormat.bytes) ?? unavailableText)")
                }
            }
        }
    }

    private var unavailableText: String {
        MicaStrings.localizedKey("overview.config_not_reported", language: language)
    }

    private func openConnection(_ connectionID: String) {
        if let controllerID = appModel.selectedRouterID,
           let reportedID = connectionID.overviewNonBlank {
            workspaceStore.stageConnectionNavigation(
                WorkbenchConnectionNavigationSelection(
                    controllerID: controllerID,
                    generation: appModel.controllerSessionPresentation.generation,
                    connectionID: reportedID
                )
            )
        }
        destination = .connections
    }
}

private struct OverviewNetworkFactsSection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let groupOrder: [OverviewDashboardNetworkGroupID]

    var body: some View {
        let groups = OverviewProjection.networkFactGroups(
            router: appModel.selectedRouter,
            metadata: appModel.controllerMetadata,
            language: language,
            order: groupOrder
        )

        OverviewFlatSection(
            "overview.network_information",
            systemImage: "globe.americas"
        ) {
            if groups.isEmpty {
                OverviewInlineState(
                    titleKey: "overview.no_network_information",
                    detailKey: "overview.no_network_information_detail"
                )
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 320), spacing: MicaSpacing.section),
                    ],
                    alignment: .leading,
                    spacing: 0
                ) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            OverviewNetworkFactGroupHeader(group: group)
                            ForEach(group.facts) { fact in
                                OverviewNetworkFactCell(fact: fact)
                            }
                        }
                        .padding(.horizontal, MicaSpacing.module)
                        .padding(.bottom, MicaSpacing.row)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .background(MicaStyle.contentFill)
                .clipShape(.rect(cornerRadius: MicaBounds.moduleRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: MicaBounds.moduleRadius)
                        .stroke(MicaStyle.separator.opacity(0.5), lineWidth: 1)
                }
            }
        }
    }
}

private extension OverviewDashboardNetworkGroupID {
    var titleKey: String {
        switch self {
        case .controllerIdentity:
            "overview.network_group_controller"
        case .runtimeAndFeatures:
            "overview.network_group_runtime"
        case .listenerPorts:
            "overview.network_group_listeners"
        }
    }

    var systemImage: String {
        switch self {
        case .controllerIdentity:
            "server.rack"
        case .runtimeAndFeatures:
            "switch.2"
        case .listenerPorts:
            "point.3.filled.connected.trianglepath.dotted"
        }
    }
}

private struct OverviewNetworkFactGroupHeader: View {
    @Environment(\.micaAppLanguage) private var language

    let group: OverviewNetworkFactGroup

    var body: some View {
        HStack(spacing: MicaSpacing.tight) {
            WorkbenchSymbol(
                systemName: group.id.systemImage,
                font: .caption.weight(.semibold),
                frameSize: 16
            )
            Text(
                MicaStrings.localizedKey(
                    group.id.titleKey,
                    language: language
                )
            )
            .micaFont(.caption, weight: .semibold)
            .foregroundStyle(.secondary)
        }
        .padding(.top, MicaSpacing.row)
        .padding(.bottom, MicaSpacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct OverviewNetworkFactCell: View {
    @Environment(\.micaAppLanguage) private var language

    let fact: OverviewNetworkFact

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.tight) {
            Text(MicaStrings.localizedKey(fact.titleKey, language: language))
                .micaFont(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: fact.value)
                .micaFont(
                    fact.monospaced ? .body : .callout,
                    design: fact.monospaced ? .monospaced : .default
                )
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

struct OverviewInlineState: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let detailKey: String

    var body: some View {
        HStack(alignment: .top, spacing: MicaSpacing.row) {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaFont(.callout, weight: .medium)
                Text(MicaStrings.localizedKey(detailKey, language: language))
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum OverviewFormat {
    /// Controller adapters use 1970-era dates as missing-value sentinels.
    static func displayableTimestamp(_ date: Date?) -> Date? {
        guard let date,
              date.timeIntervalSince1970 >= 31_536_000 else {
            return nil
        }
        return date
    }

    static func bytes(_ value: Int) -> String {
        guard value > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    static func rate(_ value: Int) -> String {
        "\(bytes(value))/s"
    }

    static func latency(_ value: Int) -> String {
        "\(value) ms"
    }

    static func latencyTint(_ value: Int) -> Color {
        switch LatencyHealthGrade.allCases.first(where: { $0.includes(delay: value) }) {
        case .fast:
            MicaStyle.signalMint
        case .normal:
            MicaStyle.signalCyan
        case .slow:
            MicaStyle.signalAmber
        case .timeout, .none:
            MicaStyle.signalRed
        }
    }
}

extension String {
    var overviewNonBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
