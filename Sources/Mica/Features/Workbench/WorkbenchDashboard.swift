import Charts
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
            let constrainedWidth = min(availableWidth, 1_180)
            let widthMode = widthMode(for: constrainedWidth)
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
                            availableWidth: constrainedWidth,
                            controllerID: controllerID,
                            generation: generation,
                            layout: layout,
                            destination: $destination
                        )
                    }
                }
                .id(generation)
                .frame(maxWidth: 1_180, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let row: OverviewDashboardPackedRow
    let widthMode: OverviewDashboardGridWidthMode
    let availableWidth: CGFloat
    let controllerID: RouterProfile.ID
    let generation: UUID
    let layout: OverviewDashboardLayout
    @Binding var destination: WorkbenchDestination

    @State private var appeared = false

    var body: some View {
        OverviewDashboardSpanLayout(
            spans: row.modules.map(\.columnSpan),
            columnCount: widthMode.columnCount,
            spacing: MicaSpacing.section
        ) {
            ForEach(Array(row.modules.enumerated()), id: \.element.id) { index, module in
                moduleView(
                    module.configuration,
                    availableWidth: estimatedWidth(for: module)
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
                .animation(
                    reduceMotion
                        ? nil
                        : WorkbenchMotion.pageIn.delay(Double(index) * 0.04),
                    value: appeared
                )
                .allowsHitTesting(!coordinator.isEditing)
                .disabled(coordinator.isEditing)
            }
        }
        .onAppear {
            guard !appeared else { return }
            appeared = true
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

private struct OverviewFlatSection<Content: View>: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let systemImage: String
    private let content: Content

    init(
        _ titleKey: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.module) {
            HStack(spacing: MicaSpacing.row) {
                WorkbenchSymbol(
                    systemName: systemImage,
                    font: .callout.weight(.semibold),
                    frameSize: 18
                )
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaFont(.headline, weight: .semibold)
            }
            .accessibilityElement(children: .combine)

            content
        }
        .padding(.top, MicaSpacing.module)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct OverviewInstrumentRailSection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let availableWidth: CGFloat
    let metrics: [OverviewDashboardInstrumentMetricConfiguration]

    var body: some View {
        let visibleMetrics = metrics.filter(\.isVisible)

        Group {
            if availableWidth >= 760 {
                HStack(spacing: 0) {
                    OverviewSessionStateReadout()
                    ForEach(visibleMetrics) { metric in
                        Divider().frame(height: 34)
                        readout(for: metric.id)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    OverviewSessionStateReadout()
                    Divider()
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 148), spacing: 0),
                        ],
                        spacing: 0
                    ) {
                        ForEach(visibleMetrics) { metric in
                            readout(for: metric.id)
                        }
                    }
                }
            }
        }
        .padding(.vertical, MicaSpacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaStyle.secondaryContentFill.opacity(0.42))
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(MicaStyle.separator.opacity(0.45), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func readout(
        for metric: OverviewDashboardInstrumentMetricID
    ) -> some View {
        switch metric {
        case .upload:
            OverviewInstrumentReadout(
                titleKey: "overview.upload_rate",
                symbol: "arrow.up",
                value: OverviewFormat.rate(appModel.connectionsCatalog.traffic.upload),
                tint: MicaStyle.signalViolet
            )
        case .download:
            OverviewInstrumentReadout(
                titleKey: "overview.download_rate",
                symbol: "arrow.down",
                value: OverviewFormat.rate(appModel.connectionsCatalog.traffic.download),
                tint: MicaStyle.signalCyan
            )
        case .activeConnections:
            OverviewInstrumentReadout(
                titleKey: "dashboard.active_sessions",
                symbol: "network",
                value: appModel.connectionsCatalog.connections.count.formatted(),
                tint: MicaStyle.signalMint
            )
        case .memoryUsage:
            OverviewInstrumentReadout(
                titleKey: "overview.memory_current",
                symbol: "memorychip",
                value: currentMemoryText,
                tint: MicaStyle.signalAmber
            )
        }
    }

    private var currentMemoryText: String {
        guard let bytes = appModel.memoryTimeline.samples.last?.inUseBytes else {
            return MicaStrings.localizedKey(
                "overview.config_not_reported",
                language: language
            )
        }
        return OverviewFormat.bytes(bytes)
    }
}

private struct OverviewTelemetrySection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let availableWidth: CGFloat
    let preferredTimelineWindow: OverviewDashboardTimelineWindow
    let runtime: OverviewTelemetryModuleRuntime

    var body: some View {
        let projection = runtime.projectionCache.resolve(
            generation: appModel.controllerSessionPresentation.generation,
            window: runtime.timelineWindow,
            traffic: appModel.trafficTimeline.samples,
            memory: appModel.memoryTimeline.samples,
            connections: appModel.connectionCountTimeline.samples,
            isPaused: runtime.isPaused
        )

        VStack(alignment: .leading, spacing: MicaSpacing.module) {
            telemetryHeading(dates: projection.dates)
            chartLayout(
                trafficSamples: projection.trafficSamples,
                memorySamples: projection.memorySamples,
                connectionSamples: projection.connectionSamples,
                dates: projection.dates
            )
        }
        .padding(.top, MicaSpacing.module)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
        .onChange(of: preferredTimelineWindow) {
            runtime.synchronize(preferredWindow: preferredTimelineWindow)
        }
        .onChange(of: projection.dates) { _, nextDates in
            runtime.interaction.retainPinnedDate(in: nextDates)
        }
    }

    private func telemetryHeading(dates: [Date]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.module) {
                telemetryTitle
                Spacer(minLength: MicaSpacing.module)
                OverviewTelemetryControls(
                    dates: dates,
                    runtime: runtime
                )
            }

            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                telemetryTitle
                OverviewTelemetryControls(
                    dates: dates,
                    runtime: runtime
                )
            }
        }
    }

    private var telemetryTitle: some View {
        HStack(spacing: MicaSpacing.row) {
            WorkbenchSymbol(systemName: "chart.xyaxis.line")
            Text(
                MicaStrings.localizedKey(
                    "overview.traffic_summary",
                    language: language
                )
            )
            .micaFont(.subheadline, weight: .semibold)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func chartLayout(
        trafficSamples: [TrafficTimeline.Sample],
        memorySamples: [MemoryTimeline.Sample],
        connectionSamples: [ConnectionCountTimeline.Sample],
        dates: [Date]
    ) -> some View {
        Group {
            if availableWidth >= 960 {
                HStack(alignment: .top, spacing: MicaSpacing.module) {
                    trafficChart(.upload, samples: trafficSamples, dates: dates)
                    trafficChart(.download, samples: trafficSamples, dates: dates)
                    connectionChart(
                        samples: connectionSamples,
                        memorySamples: memorySamples,
                        dates: dates
                    )
                }
            } else if availableWidth >= 700 {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: MicaSpacing.module,
                    verticalSpacing: MicaSpacing.module
                ) {
                    GridRow {
                        trafficChart(.upload, samples: trafficSamples, dates: dates)
                        trafficChart(.download, samples: trafficSamples, dates: dates)
                    }
                    GridRow {
                        connectionChart(
                            samples: connectionSamples,
                            memorySamples: memorySamples,
                            dates: dates
                        )
                        .gridCellColumns(2)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: MicaSpacing.module) {
                    trafficChart(.upload, samples: trafficSamples, dates: dates)
                    trafficChart(.download, samples: trafficSamples, dates: dates)
                    connectionChart(
                        samples: connectionSamples,
                        memorySamples: memorySamples,
                        dates: dates
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func trafficChart(
        _ metric: OverviewTrafficMetric,
        samples: [TrafficTimeline.Sample],
        dates: [Date]
    ) -> some View {
        OverviewTrafficChart(
            metric: metric,
            samples: samples,
            dates: dates,
            window: runtime.timelineWindow,
            interaction: runtime.interaction
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func connectionChart(
        samples: [ConnectionCountTimeline.Sample],
        memorySamples: [MemoryTimeline.Sample],
        dates: [Date]
    ) -> some View {
        OverviewConnectionChart(
            samples: samples,
            memorySamples: memorySamples,
            dates: dates,
            window: runtime.timelineWindow,
            interaction: runtime.interaction
        )
        .frame(maxWidth: .infinity)
    }
}

private struct OverviewTelemetryControls: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let dates: [Date]
    let runtime: OverviewTelemetryModuleRuntime

    var body: some View {
        let snapshot = runtime.interaction.snapshot

        HStack(spacing: MicaSpacing.row) {
            chartState(snapshot: snapshot)
            WorkbenchIconCommand(
                titleKey: runtime.isPaused ? "live.resume_updates" : "live.pause_updates",
                systemImage: runtime.isPaused ? "play" : "pause"
            ) {
                runtime.togglePause()
            }
            WorkbenchIconCommand(
                titleKey: "overview.chart_previous_sample",
                systemImage: "chevron.left",
                isEnabled: runtime.interaction.canMoveSelection(by: -1, in: dates)
            ) {
                runtime.interaction.moveSelection(by: -1, in: dates)
            }
            WorkbenchIconCommand(
                titleKey: "overview.chart_next_sample",
                systemImage: "chevron.right",
                isEnabled: runtime.interaction.canMoveSelection(by: 1, in: dates)
            ) {
                runtime.interaction.moveSelection(by: 1, in: dates)
            }
            if snapshot.isPinned || runtime.isPaused {
                WorkbenchIconCommand(
                    titleKey: "overview.chart_return_live",
                    systemImage: "dot.radiowaves.left.and.right"
                ) {
                    runtime.returnToLive()
                }
            }
            Picker(
                MicaStrings.localizedKey("overview.timeline_window", language: language),
                selection: Binding(
                    get: { runtime.timelineWindow },
                    set: { runtime.setTimelineWindow($0) }
                )
            ) {
                ForEach(OverviewTimelineWindow.allCases) { window in
                    Text(MicaStrings.localizedKey(window.titleKey, language: language))
                        .tag(window)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    private func chartState(
        snapshot: OverviewTimelineInteractionSnapshot
    ) -> some View {
        let key: String
        let tint: Color
        let systemImage: String
        if runtime.isPaused
            || appModel.controllerSessionPresentation.controls.dashboardUpdatesPaused {
            key = "overview.chart_paused"
            tint = MicaStyle.signalAmber
            systemImage = "pause.circle.fill"
        } else if snapshot.selectedDate != nil {
            key = "overview.chart_selected"
            tint = MicaStyle.signalCyan
            systemImage = "scope"
        } else if liveSamplesAreCurrent {
            key = "overview.chart_live"
            tint = MicaStyle.signalMint
            systemImage = "dot.radiowaves.left.and.right"
        } else {
            key = "overview.chart_stale"
            tint = MicaStyle.signalAmber
            systemImage = "exclamationmark.triangle.fill"
        }

        return HStack(spacing: MicaSpacing.tight) {
            WorkbenchSymbol(
                systemName: systemImage,
                tint: tint,
                font: .caption.weight(.semibold),
                frameSize: 16
            )
            Text(MicaStrings.localizedKey(key, language: language))
                .micaFont(.caption, weight: .semibold)
                .foregroundStyle(.primary)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var liveSamplesAreCurrent: Bool {
        switch appModel.controllerSessionPresentation.state {
        case .live, .partial:
            true
        case .idle, .connecting, .staleReconnecting,
             .failedBeforeFirstSnapshot, .failed, .stopped:
            false
        }
    }
}

private struct OverviewSessionStateReadout: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    var body: some View {
        let status = statusPresentation

        VStack(alignment: .leading, spacing: MicaSpacing.tight) {
            HStack(spacing: MicaSpacing.tight) {
                WorkbenchSymbol(
                    systemName: status.systemImage,
                    tint: status.tint,
                    font: .caption.weight(.semibold),
                    frameSize: 16
                )
                Text(verbatim: status.title)
                    .micaFont(.caption, weight: .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if let timestamp = OverviewFormat.displayableTimestamp(status.timestamp) {
                Label {
                    Text(timestamp, format: .dateTime.hour().minute().second())
                        .micaFont(.callout, design: .monospaced)
                } icon: {
                    Image(systemName: "clock")
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, MicaSpacing.module)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var statusPresentation: Presentation {
        let session = appModel.controllerSessionPresentation
        if session.controls.dashboardUpdatesPaused {
            return Presentation(
                title: MicaStrings.localizedKey(
                    "operation.dashboard_updates_paused",
                    language: language
                ),
                systemImage: "pause.circle.fill",
                tint: MicaStyle.signalAmber,
                timestamp: session.controls.presentationPausedAt
            )
        }

        let title = session.state.label(language: language)
        switch session.state {
        case .idle:
            return Presentation(
                title: title,
                systemImage: "circle",
                tint: .secondary,
                timestamp: session.lastSuccessAt
            )
        case .connecting:
            return Presentation(
                title: title,
                systemImage: "arrow.triangle.2.circlepath",
                tint: MicaStyle.signalCyan,
                timestamp: session.lastSuccessAt
            )
        case .live:
            return Presentation(
                title: title,
                systemImage: "checkmark.circle.fill",
                tint: MicaStyle.signalMint,
                timestamp: session.lastSuccessAt
            )
        case .staleReconnecting, .partial:
            return Presentation(
                title: title,
                systemImage: "exclamationmark.triangle.fill",
                tint: MicaStyle.signalAmber,
                timestamp: session.lastSuccessAt
            )
        case .failedBeforeFirstSnapshot, .failed:
            return Presentation(
                title: title,
                systemImage: "xmark.octagon.fill",
                tint: MicaStyle.signalRed,
                timestamp: session.lastSuccessAt
            )
        case .stopped:
            return Presentation(
                title: title,
                systemImage: "stop.circle",
                tint: .secondary,
                timestamp: session.lastSuccessAt
            )
        }
    }

    private struct Presentation {
        let title: String
        let systemImage: String
        let tint: Color
        let timestamp: Date?
    }
}

private struct OverviewInstrumentReadout: View {
    let titleKey: String
    let symbol: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.tight) {
            WorkbenchMetricLabel(titleKey: titleKey, systemImage: symbol, tint: tint)
            Text(verbatim: value)
                .micaFont(.callout, weight: .semibold, design: .monospaced)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .textSelection(.enabled)
        }
        .padding(.horizontal, MicaSpacing.module)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private enum OverviewTrafficMetric: Equatable, Sendable {
    case upload
    case download

    var titleKey: String {
        switch self {
        case .upload: "overview.upload_rate"
        case .download: "overview.download_rate"
        }
    }

    var systemImage: String {
        switch self {
        case .upload: "arrow.up"
        case .download: "arrow.down"
        }
    }

    var tint: Color {
        switch self {
        case .upload: MicaStyle.signalViolet
        case .download: MicaStyle.signalCyan
        }
    }

    func value(in sample: TrafficTimeline.Sample) -> Int {
        switch self {
        case .upload: sample.upload
        case .download: sample.download
        }
    }
}

private struct OverviewTelemetryPanel<Plot: View>: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let titleKey: String
    let systemImage: String
    let tint: Color
    let value: String?
    let timestamp: Date?
    let contextText: String?
    private let plot: Plot

    init(
        titleKey: String,
        systemImage: String,
        tint: Color,
        value: String?,
        timestamp: Date?,
        contextText: String? = nil,
        @ViewBuilder plot: () -> Plot
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.tint = tint
        self.value = value
        self.timestamp = timestamp
        self.contextText = contextText
        self.plot = plot()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            WorkbenchMetricLabel(
                titleKey: titleKey,
                systemImage: systemImage,
                tint: tint
            )

            Text(
                verbatim: value ?? MicaStrings.localizedKey(
                    "overview.config_not_reported",
                    language: language
                )
            )
            .micaFont(.title2, weight: .semibold, design: .monospaced)
            .monospacedDigit()
            .foregroundStyle(value == nil ? .secondary : .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .micaNumericTransition(reduceMotion: reduceMotion)
            .textSelection(.enabled)

            plot
                .frame(maxWidth: .infinity)
                .frame(height: 144)

            HStack(spacing: MicaSpacing.row) {
                if let timestamp {
                    Text(timestamp, format: .dateTime.hour().minute().second())
                        .micaFont(.caption, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: MicaSpacing.row)
                if let contextText {
                    Text(verbatim: contextText)
                        .micaFont(.caption, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .textSelection(.enabled)
                }
            }
            .frame(minHeight: 18)
        }
        .padding(MicaSpacing.module)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaStyle.secondaryContentFill.opacity(0.42))
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(MicaStyle.separator.opacity(0.5), lineWidth: 1)
        }
    }
}

private struct OverviewTelemetryEmptyPlot: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String

    var body: some View {
        VStack(spacing: MicaSpacing.row) {
            WorkbenchSymbol(
                systemName: "chart.xyaxis.line",
                tint: .secondary,
                font: .title3,
                frameSize: 24
            )
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaFont(.caption, weight: .medium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MicaStyle.contentFill.opacity(0.24))
        .clipShape(.rect(cornerRadius: 4))
        .accessibilityElement(children: .combine)
    }
}

private struct OverviewTrafficChart: View {
    @Environment(\.micaAppLanguage) private var language

    let metric: OverviewTrafficMetric
    let samples: [TrafficTimeline.Sample]
    let dates: [Date]
    let window: OverviewTimelineWindow
    let interaction: OverviewTimelineInteractionState

    var body: some View {
        let selectedSample = selectedSample

        OverviewTelemetryPanel(
            titleKey: metric.titleKey,
            systemImage: metric.systemImage,
            tint: metric.tint,
            value: selectedSample.map { OverviewFormat.rate(metric.value(in: $0)) },
            timestamp: selectedSample?.receivedAt,
            contextText: MicaStrings.localized(
                "overview.real_samples_count \(samples.count)",
                language: language
            )
        ) {
            if samples.isEmpty {
                OverviewTelemetryEmptyPlot(titleKey: "overview.no_traffic_samples")
            } else {
                OverviewTrafficBaseChart(
                    metric: metric,
                    samples: samples,
                    window: window,
                    language: language
                )
                .equatable()
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        ZStack {
                            OverviewTrafficSelectionIndicator(
                                proxy: proxy,
                                geometry: geometry,
                                metric: metric,
                                samples: samples,
                                interaction: interaction
                            )
                            OverviewDateSelectionOverlay(
                                proxy: proxy,
                                geometry: geometry,
                                dates: dates,
                                interaction: interaction
                            )
                        }
                    }
                }
                .focusable()
                .onMoveCommand { direction in
                    moveSelection(direction)
                }
                .accessibilityLabel(
                    MicaStrings.localizedKey(metric.titleKey, language: language)
                )
                .accessibilityValue(accessibilityValue)
            }
        }
    }

    private var selectedSample: TrafficTimeline.Sample? {
        guard let target = interaction.snapshot.selectedDate
                ?? samples.last?.receivedAt else {
            return nil
        }
        return OverviewTimelineProjection.nearestTrafficSample(to: target, in: samples)
    }

    private var accessibilityValue: String {
        guard let selectedSample else { return "" }
        let time = selectedSample.receivedAt.formatted(date: .omitted, time: .standard)
        let title = MicaStrings.localizedKey(metric.titleKey, language: language)
        return "\(time), \(title): \(OverviewFormat.rate(metric.value(in: selectedSample)))"
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            interaction.moveSelection(by: -1, in: dates)
        case .right:
            interaction.moveSelection(by: 1, in: dates)
        default:
            break
        }
    }
}

private struct OverviewTrafficBaseChart: View, @MainActor Equatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let metric: OverviewTrafficMetric
    let samples: [TrafficTimeline.Sample]
    let window: OverviewTimelineWindow
    let language: AppLanguage

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.metric == rhs.metric
            && lhs.samples == rhs.samples
            && lhs.window == rhs.window
            && lhs.language == rhs.language
    }

    var body: some View {
        let scale = OverviewTimelineChartScale.traffic(samples)
        let dateDomain = OverviewTimelineProjection.dateDomain(
            endingAt: samples.last?.receivedAt ?? Date.distantPast,
            window: window
        )

        Chart {
            if metric == .upload {
                AreaPlot(
                    samples,
                    x: .value(timeLabel, \.receivedAt),
                    y: .value(metricLabel, \.upload)
                )
                .foregroundStyle(metric.tint.opacity(0.15))

                LinePlot(
                    samples,
                    x: .value(timeLabel, \.receivedAt),
                    y: .value(metricLabel, \.upload)
                )
                .foregroundStyle(metric.tint)
                .lineStyle(StrokeStyle(lineWidth: 1.6))

                PointPlot(
                    samples.suffix(1),
                    x: .value(timeLabel, \.receivedAt),
                    y: .value(metricLabel, \.upload)
                )
                .foregroundStyle(metric.tint)
                .symbolSize(24)
            } else {
                AreaPlot(
                    samples,
                    x: .value(timeLabel, \.receivedAt),
                    y: .value(metricLabel, \.download)
                )
                .foregroundStyle(metric.tint.opacity(0.15))

                LinePlot(
                    samples,
                    x: .value(timeLabel, \.receivedAt),
                    y: .value(metricLabel, \.download)
                )
                .foregroundStyle(metric.tint)
                .lineStyle(StrokeStyle(lineWidth: 1.6))

                PointPlot(
                    samples.suffix(1),
                    x: .value(timeLabel, \.receivedAt),
                    y: .value(metricLabel, \.download)
                )
                .foregroundStyle(metric.tint)
                .symbolSize(24)
            }
        }
        .chartXScale(domain: dateDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: scale.axisValues) { value in
                AxisGridLine().foregroundStyle(MicaStyle.separator.opacity(0.35))
                AxisValueLabel {
                    if let bytes = value.as(Int.self) {
                        Text(verbatim: OverviewFormat.rate(bytes))
                    }
                }
            }
        }
        .chartYScale(domain: scale.domain)
        .chartPlotStyle { plotArea in
            plotArea
                .background(MicaStyle.secondaryContentFill.opacity(0.28))
                .clipShape(.rect(cornerRadius: 4))
        }
        .chartLegend(.hidden)
        .frame(maxWidth: .infinity)
        .animation(
            reduceMotion ? nil : WorkbenchMotion.liveDraw,
            value: samples
        )
    }

    private var timeLabel: String { MicaStrings.localizedKey("traffic.log_time", language: language) }
    private var metricLabel: String {
        MicaStrings.localizedKey(metric.titleKey, language: language)
    }
}

private struct OverviewConnectionChart: View {
    @Environment(\.micaAppLanguage) private var language

    let samples: [ConnectionCountTimeline.Sample]
    let memorySamples: [MemoryTimeline.Sample]
    let dates: [Date]
    let window: OverviewTimelineWindow
    let interaction: OverviewTimelineInteractionState

    var body: some View {
        let selectedSample = selectedSample

        OverviewTelemetryPanel(
            titleKey: "overview.connection_count",
            systemImage: "network",
            tint: MicaStyle.signalMint,
            value: selectedSample?.activeCount.formatted(),
            timestamp: selectedSample?.receivedAt,
            contextText: memoryContextText
        ) {
            if samples.isEmpty {
                OverviewTelemetryEmptyPlot(titleKey: "overview.no_connection_samples")
            } else {
                OverviewConnectionBaseChart(
                    samples: samples,
                    window: window,
                    language: language
                )
                .equatable()
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        ZStack {
                            OverviewConnectionSelectionIndicator(
                                proxy: proxy,
                                geometry: geometry,
                                samples: samples,
                                interaction: interaction
                            )
                            OverviewDateSelectionOverlay(
                                proxy: proxy,
                                geometry: geometry,
                                dates: dates,
                                interaction: interaction
                            )
                        }
                    }
                }
                .focusable()
                .onMoveCommand { direction in
                    moveSelection(direction)
                }
                .accessibilityLabel(
                    MicaStrings.localizedKey(
                        "overview.connection_count",
                        language: language
                    )
                )
                .accessibilityValue(accessibilityValue)
            }
        }
    }

    private var selectedSample: ConnectionCountTimeline.Sample? {
        guard let target = interaction.snapshot.selectedDate
                ?? samples.last?.receivedAt else {
            return nil
        }
        return OverviewTimelineProjection.nearestConnectionSample(
            to: target,
            in: samples
        )
    }

    private var selectedMemorySample: MemoryTimeline.Sample? {
        guard let target = interaction.snapshot.selectedDate
                ?? memorySamples.last?.receivedAt else {
            return nil
        }
        return OverviewTimelineProjection.nearestMemorySample(
            to: target,
            in: memorySamples
        )
    }

    private var memoryContextText: String {
        let title = MicaStrings.localizedKey(
            "overview.memory_current",
            language: language
        )
        let value = selectedMemorySample.map {
            OverviewFormat.bytes($0.inUseBytes)
        } ?? MicaStrings.localizedKey(
            "overview.config_not_reported",
            language: language
        )
        return "\(title): \(value)"
    }

    private var accessibilityValue: String {
        guard let selectedSample else { return "" }
        let time = selectedSample.receivedAt.formatted(date: .omitted, time: .standard)
        return "\(time), \(selectedSample.activeCount.formatted()), \(memoryContextText)"
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            interaction.moveSelection(by: -1, in: dates)
        case .right:
            interaction.moveSelection(by: 1, in: dates)
        default:
            break
        }
    }
}

private struct OverviewConnectionBaseChart: View, @MainActor Equatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let samples: [ConnectionCountTimeline.Sample]
    let window: OverviewTimelineWindow
    let language: AppLanguage

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.samples == rhs.samples
            && lhs.window == rhs.window
            && lhs.language == rhs.language
    }

    var body: some View {
        let scale = OverviewTimelineChartScale.connections(samples)
        let dateDomain = OverviewTimelineProjection.dateDomain(
            endingAt: samples.last?.receivedAt ?? Date.distantPast,
            window: window
        )

        Chart {
            AreaPlot(
                samples,
                x: .value(timeLabel, \.receivedAt),
                y: .value(connectionLabel, \.activeCount)
            )
            .foregroundStyle(MicaStyle.signalMint.opacity(0.16))

            LinePlot(
                samples,
                x: .value(timeLabel, \.receivedAt),
                y: .value(connectionLabel, \.activeCount)
            )
            .foregroundStyle(MicaStyle.signalMint)
            .lineStyle(StrokeStyle(lineWidth: 1.5))

            PointPlot(
                samples.suffix(1),
                x: .value(timeLabel, \.receivedAt),
                y: .value(connectionLabel, \.activeCount)
            )
            .foregroundStyle(MicaStyle.signalMint)
            .symbolSize(24)
        }
        .chartXScale(domain: dateDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: scale.axisValues) { value in
                AxisGridLine().foregroundStyle(MicaStyle.separator.opacity(0.35))
                AxisValueLabel {
                    if let count = value.as(Int.self) {
                        Text(verbatim: count.formatted())
                    }
                }
            }
        }
        .chartYScale(domain: scale.domain)
        .chartPlotStyle { plotArea in
            plotArea
                .background(MicaStyle.secondaryContentFill.opacity(0.22))
                .clipShape(.rect(cornerRadius: 4))
        }
        .chartLegend(.hidden)
        .animation(
            reduceMotion ? nil : WorkbenchMotion.liveDraw,
            value: samples
        )
    }

    private var timeLabel: String {
        MicaStrings.localizedKey("traffic.log_time", language: language)
    }

    private var connectionLabel: String {
        MicaStrings.localizedKey("overview.connection_count", language: language)
    }
}

private struct OverviewTrafficSelectionIndicator: View {
    let proxy: ChartProxy
    let geometry: GeometryProxy
    let metric: OverviewTrafficMetric
    let samples: [TrafficTimeline.Sample]
    let interaction: OverviewTimelineInteractionState

    var body: some View {
        let selectedSample = selectedSample

        Canvas { context, _ in
            guard let selectedSample,
                  let plotAnchor = proxy.plotFrame,
                  let x = proxy.position(forX: selectedSample.receivedAt),
                  let y = proxy.position(forY: metric.value(in: selectedSample)) else {
                return
            }

            let plotFrame = geometry[plotAnchor]
            let resolvedX = plotFrame.minX + x
            var rule = Path()
            rule.move(to: CGPoint(x: resolvedX, y: plotFrame.minY))
            rule.addLine(to: CGPoint(x: resolvedX, y: plotFrame.maxY))
            context.stroke(
                rule,
                with: .color(Color.secondary.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )

            drawPoint(
                at: CGPoint(x: resolvedX, y: plotFrame.minY + y),
                color: metric.tint,
                in: &context
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var selectedSample: TrafficTimeline.Sample? {
        guard let target = interaction.snapshot.selectedDate
                ?? samples.last?.receivedAt else {
            return nil
        }
        return OverviewTimelineProjection.nearestTrafficSample(to: target, in: samples)
    }

    private func drawPoint(
        at point: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let diameter: CGFloat = 7
        let rect = CGRect(
            x: point.x - diameter / 2,
            y: point.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }
}

private struct OverviewConnectionSelectionIndicator: View {
    let proxy: ChartProxy
    let geometry: GeometryProxy
    let samples: [ConnectionCountTimeline.Sample]
    let interaction: OverviewTimelineInteractionState

    var body: some View {
        Canvas { context, _ in
            guard let selectedSample,
                  let plotAnchor = proxy.plotFrame,
                  let x = proxy.position(forX: selectedSample.receivedAt),
                  let y = proxy.position(forY: selectedSample.activeCount) else {
                return
            }

            let plotFrame = geometry[plotAnchor]
            let resolvedX = plotFrame.minX + x
            var rule = Path()
            rule.move(to: CGPoint(x: resolvedX, y: plotFrame.minY))
            rule.addLine(to: CGPoint(x: resolvedX, y: plotFrame.maxY))
            context.stroke(
                rule,
                with: .color(Color.secondary.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )

            let diameter: CGFloat = 7
            let point = CGPoint(x: resolvedX, y: plotFrame.minY + y)
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: point.x - diameter / 2,
                        y: point.y - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                ),
                with: .color(MicaStyle.signalMint)
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var selectedSample: ConnectionCountTimeline.Sample? {
        guard let target = interaction.snapshot.selectedDate
                ?? samples.last?.receivedAt else {
            return nil
        }
        return OverviewTimelineProjection.nearestConnectionSample(
            to: target,
            in: samples
        )
    }
}

private struct OverviewDateSelectionOverlay: View {
    let proxy: ChartProxy
    let geometry: GeometryProxy
    let dates: [Date]
    let interaction: OverviewTimelineInteractionState

    var body: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let nextDate = date(at: location)
                    interaction.setHoveredDate(nextDate)
                case .ended:
                    interaction.setHoveredDate(nil)
                }
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let selectedDate = date(at: value.location) else { return }
                        interaction.togglePinnedDate(selectedDate)
                    }
            )
            .accessibilityHidden(true)
    }

    private func date(at location: CGPoint) -> Date? {
        guard let anchor = proxy.plotFrame else { return nil }
        let frame = geometry[anchor]
        guard frame.contains(location),
              let projectedDate = proxy.value(atX: location.x - frame.minX, as: Date.self),
              let index = OverviewTimelineProjection.nearestDateIndex(
                to: projectedDate,
                in: dates
              ) else {
            return nil
        }
        return dates[index]
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
                                Text(verbatim: row.label.nilIfBlank ?? unavailableText)
                                    .micaFont(.callout, weight: .medium)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                                Text(verbatim: row.proxy.nilIfBlank ?? unavailableText)
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
                        "\(row.label.nilIfBlank ?? unavailableText), \(ruleCountText(row))"
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
                                Text(verbatim: row.label.nilIfBlank ?? unavailableText)
                                    .micaFont(.callout, weight: .medium)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                                if let connectionID = row.connectionID.nilIfBlank {
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
                    .accessibilityLabel("\(row.label.nilIfBlank ?? unavailableText), \(row.totalTraffic.map(OverviewFormat.bytes) ?? unavailableText)")
                }
            }
        }
    }

    private var unavailableText: String {
        MicaStrings.localizedKey("overview.config_not_reported", language: language)
    }

    private func openConnection(_ connectionID: String) {
        if let controllerID = appModel.selectedRouterID,
           let reportedID = connectionID.nilIfBlank {
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

private struct OverviewTopologySection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let runtime: OverviewTopologyModuleRuntime
    @Binding var destination: WorkbenchDestination

    var body: some View {
        let catalog = appModel.connectionsCatalog
        OverviewFlatSection(
            "overview.topology_title",
            systemImage: "point.3.connected.trianglepath.dotted"
        ) {
            OverviewTopologyWorkspace(
                connections: catalog.connections,
                controllerID: appModel.selectedRouterID,
                generation: appModel.controllerSessionPresentation.generation,
                revision: catalog.structureRevision,
                language: language,
                runtime: runtime,
                destination: $destination
            )
        }
    }
}

private struct OverviewTopologyWorkspace: View {
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore

    let connections: [ConnectionSnapshot]
    let controllerID: RouterProfile.ID?
    let generation: UUID
    let revision: UInt64
    let language: AppLanguage
    let runtime: OverviewTopologyModuleRuntime
    @Binding var destination: WorkbenchDestination

    var body: some View {
        if connections.isEmpty {
            OverviewInlineState(
                titleKey: "overview.topology_empty",
                detailKey: "overview.topology_empty_detail"
            )
        } else {
            let freezesPresentation = runtime.isPaused
                || runtime.interaction.snapshot.isHovering
            let presentationRevision = freezesPresentation
                ? runtime.presentation?.request.revision ?? revision
                : revision
            let request = OverviewTopologyRequest(
                generation: generation,
                revision: presentationRevision,
                availableWidth: runtime.availableWidth,
                minimumFlowHeight: 352
            )

            topologyBody(for: request)
                .frame(minHeight: 420, alignment: .top)
                .task(id: request) {
                    await rebuildPresentation(for: request)
                }
                .onChange(of: request.generation) { _, _ in
                    runtime.interaction.reset()
                }
                .onGeometryChange(for: Int.self) { geometry in
                    let boundedWidth = max(geometry.size.width, 1)
                    return max(Int((boundedWidth / 8).rounded(.down)) * 8, 1)
                } action: { nextAvailableWidth in
                    guard runtime.availableWidth != nextAvailableWidth else { return }
                    runtime.availableWidth = nextAvailableWidth
                }
        }
    }

    @ViewBuilder
    private func topologyBody(for request: OverviewTopologyRequest) -> some View {
        if let presentation = runtime.presentation,
           presentation.canRemainVisible(whileResolving: request) {
            VStack(alignment: .leading, spacing: MicaSpacing.module) {
                topologySummary(presentation.topology)
                if presentation.topology.isEmpty {
                    if runtime.isExpanded {
                        VStack(alignment: .leading, spacing: MicaSpacing.row) {
                            OverviewInlineState(
                                titleKey: "overview.topology_empty",
                                detailKey: "overview.topology_empty_detail"
                            )
                            OverviewTopologyPathRows(
                                paths: presentation.topology.paths,
                                language: language,
                                interaction: runtime.interaction,
                                onOpenPath: openPathInConnections
                            )
                        }
                    } else {
                        OverviewInlineState(
                            titleKey: "overview.topology_empty",
                            detailKey: "overview.topology_empty_detail"
                        )
                        .accessibilityRepresentation {
                            OverviewTopologyAccessibilityRepresentation(
                                paths: presentation.topology.paths,
                                groups: presentation.index.accessibilityGroups,
                                language: language,
                                interaction: runtime.interaction,
                                onOpenPath: openPathInConnections
                            )
                        }
                    }
                } else {
                    OverviewTopologyViewport(
                        topology: presentation.topology,
                        request: presentation.request,
                        index: presentation.index,
                        layout: presentation.layout,
                        language: language,
                        interaction: runtime.interaction,
                        showsPathRows: runtime.isExpanded,
                        onOpenPath: openPathInConnections
                    )
                }
            }
        } else {
            HStack(spacing: MicaSpacing.row) {
                ProgressView().controlSize(.small)
                Text(MicaStrings.localizedKey("overview.current_data", language: language))
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        }
    }

    private func topologySummary(_ topology: ConnectionTopology) -> some View {
        HStack(spacing: MicaSpacing.module) {
            WorkbenchCommandSummary(
                symbolName: "point.3.connected.trianglepath.dotted",
                titleKey: "overview.connection_count",
                value: topology.connectionCount.formatted(),
                detail: topology.routeUnavailableCount > 0
                    ? topology.routeUnavailableCount.formatted()
                    : nil
            )
            Spacer(minLength: 0)
            if runtime.isPaused {
                Text(
                    MicaStrings.localizedKey(
                        "overview.chart_paused",
                        language: language
                    )
                )
                .micaFont(.caption, weight: .semibold)
                .foregroundStyle(MicaStyle.signalAmber)
            }
            WorkbenchIconCommand(
                titleKey: runtime.isPaused
                    ? "live.resume_updates"
                    : "live.pause_updates",
                systemImage: runtime.isPaused ? "play" : "pause"
            ) {
                runtime.togglePause()
            }
            WorkbenchIconCommand(
                titleKey: runtime.isExpanded
                    ? "overview.show_less"
                    : "overview.show_all",
                systemImage: runtime.isExpanded
                    ? "list.bullet.indent"
                    : "list.bullet"
            ) {
                runtime.isExpanded.toggle()
            }
        }
    }

    @MainActor
    private func rebuildPresentation(for request: OverviewTopologyRequest) async {
        do {
            let nextPresentation = try await runtime.presentationCache.resolve(
                request: request,
                connections: connections
            )
            guard !Task.isCancelled else { return }
            runtime.interaction.configure(
                structure: nextPresentation.request.structure,
                index: nextPresentation.index
            )
            runtime.presentation = nextPresentation
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if runtime.presentation?.request.generation != request.generation {
                runtime.presentation = nil
            }
        }
    }

    private func openPathInConnections(_ path: ConnectionTopology.PathRecord) {
        if let controllerID,
           let connectionID = path.reportedConnectionID.nilIfBlank {
            workspaceStore.stageConnectionNavigation(
                WorkbenchConnectionNavigationSelection(
                    controllerID: controllerID,
                    generation: generation,
                    connectionID: connectionID
                )
            )
        }
        destination = .connections
    }
}

private struct OverviewTopologyViewport: View {
    let topology: ConnectionTopology
    let request: OverviewTopologyRequest
    let index: OverviewTopologyIndex
    let layout: OverviewTopologyLayout
    let language: AppLanguage
    let interaction: OverviewTopologyInteractionState
    let showsPathRows: Bool
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void

    @Environment(\.micaAppFontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            OverviewTopologySelectionDetail(
                index: index,
                language: language,
                interaction: interaction,
                onOpenPath: onOpenPath
            )
            .frame(minHeight: 56, alignment: .topLeading)

            if showsPathRows {
                topologyGraph
                    .accessibilityHidden(true)
                OverviewTopologyPathRows(
                    paths: topology.paths,
                    language: language,
                    interaction: interaction,
                    onOpenPath: onOpenPath
                )
            } else {
                topologyGraph
                    .accessibilityRepresentation {
                        OverviewTopologyAccessibilityRepresentation(
                            paths: topology.paths,
                            groups: index.accessibilityGroups,
                            language: language,
                            interaction: interaction,
                            onOpenPath: onOpenPath
                        )
                    }
            }
        }
    }

    private var topologyGraph: some View {
        LazyVStack(spacing: 0) {
            ForEach(layout.renderBands) { band in
                OverviewTopologyBandLayers(
                    request: request,
                    band: band,
                    layout: layout,
                    language: language,
                    fontScale: fontScale,
                    interaction: interaction
                )
                .equatable()
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .background(MicaStyle.contentFill)
        .frame(height: layout.size.height)
        .frame(maxWidth: .infinity, alignment: .center)
        .clipShape(.rect(cornerRadius: MicaBounds.moduleRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MicaBounds.moduleRadius)
                .stroke(MicaStyle.separator.opacity(0.5), lineWidth: 1)
        }
    }
}

private struct OverviewTopologySelectionDetail: View {
    let index: OverviewTopologyIndex
    let language: AppLanguage
    let interaction: OverviewTopologyInteractionState
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void

    @ViewBuilder
    var body: some View {
        let snapshot = interaction.snapshot

        if let selection = snapshot.activeSelection {
            HStack(alignment: .top, spacing: MicaSpacing.row) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        verbatim: OverviewTopologyProjection.selectionLabel(
                            selection,
                            in: index,
                            language: language
                        )
                    )
                    .micaFont(.caption, weight: .medium)
                    .textSelection(.enabled)
                    Text(
                        verbatim: OverviewTopologyProjection.selectionDescription(
                            selection,
                            in: index,
                            language: language
                        )
                    )
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                if snapshot.highlight.paths.count == 1,
                   let path = snapshot.highlight.paths.first {
                    WorkbenchIconCommand(
                        titleKey: WorkbenchDestination.connections.titleKey,
                        systemImage: "arrow.right"
                    ) {
                        onOpenPath(path)
                    }
                }
            }
            .padding(.horizontal, MicaSpacing.row)
            .padding(.vertical, MicaSpacing.tight)
            .background(MicaStyle.secondaryContentFill.opacity(0.72))
            .clipShape(.rect(cornerRadius: 6))
        }
    }
}

private struct OverviewTopologyPathRows: View {
    let paths: [ConnectionTopology.PathRecord]
    let language: AppLanguage
    let interaction: OverviewTopologyInteractionState
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            HStack(spacing: MicaSpacing.row) {
                WorkbenchSymbol(
                    systemName: "point.3.connected.trianglepath.dotted",
                    font: .caption.weight(.semibold),
                    frameSize: 16
                )
                Text(
                    MicaStrings.localizedKey(
                        "dashboard.chain_label",
                        language: language
                    )
                )
                .micaFont(.caption, weight: .semibold)
                Text(verbatim: paths.count.formatted())
                    .micaFont(.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            LazyVStack(spacing: 0) {
                ForEach(paths) { path in
                    pathRow(path)
                    if path.id != paths.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pathRow(
        _ path: ConnectionTopology.PathRecord
    ) -> some View {
        let isSelected = interaction.snapshot.activeSelection == .path(path.id)

        return HStack(alignment: .top, spacing: MicaSpacing.row) {
            Button {
                interaction.togglePinnedPath(path.id)
            } label: {
                HStack(alignment: .top, spacing: MicaSpacing.row) {
                    Image(systemName: isSelected ? "pin.fill" : "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(isSelected ? MicaStyle.signalCyan : .secondary)
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            verbatim: OverviewTopologyProjection.pathLabel(
                                path,
                                language: language
                            )
                        )
                        .micaFont(.callout, weight: .medium)
                        .textSelection(.enabled)
                        Text(
                            verbatim: OverviewTopologyProjection.pathDescription(
                                path,
                                language: language
                            )
                        )
                        .micaFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            WorkbenchIconCommand(
                titleKey: WorkbenchDestination.connections.titleKey,
                systemImage: "arrow.right"
            ) {
                onOpenPath(path)
            }
        }
        .padding(.horizontal, MicaSpacing.row)
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(isSelected ? MicaStyle.accentSoft : .clear)
        .contentShape(Rectangle())
    }
}

private struct OverviewTopologyBandLayers: View, @MainActor Equatable {
    let request: OverviewTopologyRequest
    let band: OverviewTopologyLayout.RenderBand
    let layout: OverviewTopologyLayout
    let language: AppLanguage
    let fontScale: AppFontScale
    let interaction: OverviewTopologyInteractionState

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.request == rhs.request
            && lhs.band.id == rhs.band.id
            && lhs.language == rhs.language
            && lhs.fontScale == rhs.fontScale
            && lhs.interaction === rhs.interaction
    }

    var body: some View {
        ZStack {
            OverviewTopologyBaseBand(
                request: request,
                band: band,
                language: language,
                fontScale: fontScale
            )
            .equatable()

            OverviewTopologyHighlightBand(
                band: band,
                fontScale: fontScale,
                interaction: interaction
            )

            OverviewTopologyHitBand(
                request: request,
                band: band,
                layout: layout,
                interaction: interaction
            )
            .equatable()
        }
        .frame(
            width: band.bounds.width,
            height: band.bounds.height,
            alignment: .topLeading
        )
    }
}

private struct OverviewTopologyBaseBand: View, @MainActor Equatable {
    let request: OverviewTopologyRequest
    let band: OverviewTopologyLayout.RenderBand
    let language: AppLanguage
    let fontScale: AppFontScale

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.request == rhs.request
            && lhs.band.id == rhs.band.id
            && lhs.language == rhs.language
            && lhs.fontScale == rhs.fontScale
    }

    var body: some View {
        Canvas(
            opaque: false,
            colorMode: .nonLinear,
            rendersAsynchronously: true
        ) { context, _ in
            MicaPerformanceObservation.recordDebug(
                .topologyCanvasPresentation,
                metadata: MicaPerformanceMetadata(
                    count: UInt64(band.nodes.count + band.edges.count),
                    revision: request.revision
                )
            )
            MicaPerformanceObservation.recordDebug(
                .topologyBasePresentation,
                metadata: MicaPerformanceMetadata(
                    count: UInt64(band.nodes.count + band.edges.count),
                    revision: request.revision
                )
            )
            context.translateBy(x: 0, y: -band.bounds.minY)

            for edge in band.edges {
                OverviewTopologyDrawing.drawEdge(edge, in: &context)
            }

            for column in band.columns {
                let title = context.resolve(
                    Text(
                        verbatim: OverviewTopologyProjection.columnTitle(
                            column.id,
                            language: language
                        )
                    )
                    .font(
                        .system(
                            size: fontScale.pointSize(for: MicaTextStyle.caption.basePointSize),
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.secondary)
                )
                context.draw(
                    title,
                    at: CGPoint(x: column.centerX, y: 16),
                    anchor: .center
                )
            }

            for node in band.nodes {
                OverviewTopologyDrawing.drawNode(
                    node,
                    fontPointSize: fontScale.pointSize(
                        for: MicaTextStyle.caption.basePointSize
                    ),
                    in: &context
                )
            }
        }
        .background(MicaStyle.contentFill)
        .accessibilityHidden(true)
    }
}

private struct OverviewTopologyHighlightBand: View {
    let band: OverviewTopologyLayout.RenderBand
    let fontScale: AppFontScale
    let interaction: OverviewTopologyInteractionState

    var body: some View {
        let snapshot = interaction.snapshot

        ZStack {
            MicaStyle.contentFill
                .opacity(snapshot.activeSelection == nil ? 0 : 0.68)

            Canvas { context, _ in
                guard snapshot.activeSelection != nil else { return }
                MicaPerformanceObservation.recordDebug(
                    .topologyHighlightPresentation,
                    metadata: MicaPerformanceMetadata(
                        count: UInt64(
                            snapshot.highlight.nodeIDs.count
                                + snapshot.highlight.edgeIDs.count
                        )
                    )
                )
                context.translateBy(x: 0, y: -band.bounds.minY)

                for edge in band.edges
                    where snapshot.highlight.edgeIDs.contains(edge.edge.id) {
                    OverviewTopologyDrawing.drawEdge(
                        edge,
                        isHighlighted: true,
                        in: &context
                    )
                }
                for node in band.nodes
                    where snapshot.highlight.nodeIDs.contains(node.node.id) {
                    OverviewTopologyDrawing.drawNode(
                        node,
                        isHighlighted: true,
                        fontPointSize: fontScale.pointSize(
                            for: MicaTextStyle.caption.basePointSize
                        ),
                        in: &context
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct OverviewTopologyHitBand: View, @MainActor Equatable {
    let request: OverviewTopologyRequest
    let band: OverviewTopologyLayout.RenderBand
    let layout: OverviewTopologyLayout
    let interaction: OverviewTopologyInteractionState

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.request == rhs.request
            && lhs.band.id == rhs.band.id
            && lhs.interaction === rhs.interaction
    }

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    interaction.setHoveredSelection(
                        layout.hitTest(at: globalPoint(for: location))
                    )
                case .ended:
                    interaction.setHoveredSelection(nil)
                }
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { event in
                        interaction.togglePinnedSelection(
                            layout.hitTest(at: globalPoint(for: event.location))
                        )
                    }
            )
            .accessibilityHidden(true)
    }

    private func globalPoint(for localPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: localPoint.x + band.bounds.minX,
            y: localPoint.y + band.bounds.minY
        )
    }
}

private struct OverviewTopologyAccessibilityRepresentation: View {
    let paths: [ConnectionTopology.PathRecord]
    let groups: [OverviewTopologyIndex.AccessibilityGroup]
    let language: AppLanguage
    let interaction: OverviewTopologyInteractionState
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void

    var body: some View {
        LazyVStack {
            ForEach(groups) { group in
                OverviewTopologyAccessibilityGroup(
                    paths: paths,
                    pathRange: group.pathRange,
                    language: language,
                    interaction: interaction,
                    onOpenPath: onOpenPath
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            MicaStrings.localizedKey("dashboard.chain_label", language: language)
        )
    }
}

private struct OverviewTopologyAccessibilityGroup: View {
    let paths: [ConnectionTopology.PathRecord]
    let pathRange: Range<Int>
    let language: AppLanguage
    let interaction: OverviewTopologyInteractionState
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void

    var body: some View {
        VStack {
            ForEach(paths[pathRange]) { path in
                HStack {
                    Button {
                        interaction.togglePinnedPath(path.id)
                    } label: {
                        Text(
                            verbatim: OverviewTopologyProjection.pathLabel(
                                path,
                                language: language
                            )
                        )
                    }
                    .accessibilityValue(
                        OverviewTopologyProjection.pathDescription(
                            path,
                            language: language
                        )
                    )

                    Button {
                        onOpenPath(path)
                    } label: {
                        Text(
                            MicaStrings.localizedKey(
                                WorkbenchDestination.connections.titleKey,
                                language: language
                            )
                        )
                    }
                    .accessibilityLabel(openPathLabel(path))
                }
            }
        }
        .onAppear {
            MicaPerformanceObservation.recordDebug(
                .topologyAccessibilityPresentation,
                metadata: MicaPerformanceMetadata(count: UInt64(pathRange.count))
            )
        }
    }

    private func openPathLabel(_ path: ConnectionTopology.PathRecord) -> String {
        let destination = MicaStrings.localizedKey(
            WorkbenchDestination.connections.titleKey,
            language: language
        )
        let path = OverviewTopologyProjection.pathLabel(path, language: language)
        return "\(destination), \(path)"
    }
}

private enum OverviewTopologyDrawing {
    static func drawEdge(
        _ edge: OverviewTopologyLayout.EdgeGeometry,
        isHighlighted: Bool = false,
        in context: inout GraphicsContext
    ) {
        let sourceColor = isHighlighted
            ? MicaStyle.signalCyan
            : stageColor(for: edge.edge.sourceLayer)
        let targetColor = isHighlighted
            ? MicaStyle.signalCyan
            : stageColor(for: edge.edge.targetLayer)
        context.fill(
            edge.drawingPath,
            with: .linearGradient(
                Gradient(colors: [
                    sourceColor.opacity(isHighlighted ? 0.92 : 0.38),
                    targetColor.opacity(isHighlighted ? 0.92 : 0.38),
                ]),
                startPoint: edge.source,
                endPoint: edge.target
            )
        )
    }

    static func drawNode(
        _ node: OverviewTopologyLayout.NodeGeometry,
        isHighlighted: Bool = false,
        fontPointSize: CGFloat,
        in context: inout GraphicsContext
    ) {
        let color = isHighlighted
            ? MicaStyle.signalCyan
            : stageColor(for: node.node.layer)
        context.fill(
            node.drawingPath,
            with: .color(color.opacity(isHighlighted ? 1 : 0.82))
        )
        if isHighlighted {
            context.stroke(
                node.drawingPath,
                with: .color(Color.primary.opacity(0.9)),
                lineWidth: 1.5
            )
        }
        let label = context.resolve(
            Text(
                verbatim: displayLabel(
                    node.node.name,
                    availableWidth: node.labelRect.width
                )
            )
                .font(.system(size: fontPointSize))
                .foregroundStyle(.primary)
        )
        let labelPoint: CGPoint
        let labelAnchor: UnitPoint
        switch node.labelSide {
        case .leading:
            labelPoint = CGPoint(x: node.labelRect.minX, y: node.labelRect.midY)
            labelAnchor = .leading
        case .trailing:
            labelPoint = CGPoint(x: node.labelRect.maxX, y: node.labelRect.midY)
            labelAnchor = .trailing
        }
        var labelContext = context
        labelContext.clip(to: Path(node.labelRect))
        labelContext.draw(
            label,
            at: labelPoint,
            anchor: labelAnchor
        )
    }

    private static func displayLabel(
        _ value: String,
        availableWidth: CGFloat
    ) -> String {
        let approximateCharacterWidth: CGFloat = 7
        let maximumCount = max(Int(availableWidth / approximateCharacterWidth), 1)
        guard value.count > maximumCount else { return value }
        guard maximumCount > 3 else {
            return String(value.prefix(maximumCount))
        }
        return "\(value.prefix(maximumCount - 3))..."
    }

    private static func stageColor(
        for layer: ConnectionTopology.Layer
    ) -> Color {
        switch layer {
        case .source:
            MicaStyle.signalViolet
        case .rule:
            MicaStyle.signalAmber
        case .proxyEntry:
            MicaStyle.signalCyan
        case .proxyExit:
            MicaStyle.signalMint
        }
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

        OverviewFlatSection("overview.network_information", systemImage: "network") {
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
                        Section {
                            ForEach(group.facts) { fact in
                                OverviewNetworkFactCell(fact: fact)
                            }
                        } header: {
                            OverviewNetworkFactGroupHeader(group: group)
                        }
                    }
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
        .padding(.top, MicaSpacing.module)
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

private struct OverviewInlineState: View {
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

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
