import Charts
import Foundation
import SwiftUI

struct OverviewInstrumentRailSection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let availableWidth: CGFloat
    let visibleMetrics: Set<OverviewMetricID>

    var body: some View {
        let orderedMetrics = OverviewMetricID.allCases.filter(
            visibleMetrics.contains
        )

        Group {
            if availableWidth >= 760 {
                HStack(spacing: 0) {
                    OverviewSessionStateReadout()
                    ForEach(orderedMetrics) { metric in
                        MicaHairlineSeparator(axis: .vertical)
                            .frame(height: 34)
                        readout(for: metric)
                    }
                    MicaHairlineSeparator(axis: .vertical)
                        .frame(height: 34)
                    memoryReadout
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    OverviewSessionStateReadout()
                    MicaHairlineSeparator()
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 148), spacing: 0),
                        ],
                        spacing: 0
                    ) {
                        ForEach(orderedMetrics) { metric in
                            readout(for: metric)
                        }
                        memoryReadout
                    }
                }
            }
        }
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .micaPanel(padding: 0)
    }

    @ViewBuilder
    private func readout(
        for metric: OverviewMetricID
    ) -> some View {
        switch metric {
        case .upload:
            OverviewInstrumentReadout(
                titleKey: "overview.upload_rate",
                symbol: "arrow.up.right",
                value: currentTrafficRateText(\.upload)
            )
        case .download:
            OverviewInstrumentReadout(
                titleKey: "overview.download_rate",
                symbol: "arrow.down.left",
                value: currentTrafficRateText(\.download)
            )
        case .activeConnections:
            OverviewInstrumentReadout(
                titleKey: "dashboard.active_sessions",
                symbol: "network",
                value: currentConnectionCountText
            )
        }
    }

    private func currentTrafficRateText(
        _ value: KeyPath<TrafficTimeline.Sample, Int>
    ) -> String {
        guard let sample = appModel.trafficTimeline.samples.last else {
            return unavailableText
        }
        return OverviewFormat.rate(sample[keyPath: value])
    }

    private var currentConnectionCountText: String {
        if let count = appModel.connectionCountTimeline.samples.last?.activeCount {
            return count.formatted()
        }
        return appModel.connectionsCatalog.connections.count.formatted()
    }

    private var memoryReadout: some View {
        OverviewInstrumentReadout(
            titleKey: "overview.memory_current",
            symbol: "memorychip",
            value: currentMemoryText
        )
    }

    private var currentMemoryText: String {
        guard let bytes = appModel.memoryTimeline.samples.last?.inUseBytes else {
            return unavailableText
        }
        return OverviewFormat.bytes(bytes)
    }

    private var unavailableText: String {
        MicaStrings.localizedKey(
            "overview.config_not_reported",
            language: language
        )
    }
}

struct OverviewTelemetrySection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState

    let availableWidth: CGFloat
    let visibleMetrics: Set<OverviewMetricID>
    let preferredTimelineWindow: OverviewTimelineWindow
    let runtime: OverviewTelemetryRuntime

    var body: some View {
        let projection = runtime.projectionCache.resolve(
            generation: appModel.controllerSessionPresentation.generation,
            window: runtime.timelineWindow,
            traffic: appModel.trafficTimeline.samples,
            memory: appModel.memoryTimeline.samples,
            connections: appModel.connectionCountTimeline.samples,
            isPaused: runtime.isPaused
        )

        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space3) {
            telemetryHeading(dates: projection.dates)
            chartLayout(
                trafficSamples: projection.trafficSamples,
                memorySamples: projection.memorySamples,
                connectionSamples: projection.connectionSamples,
                dates: projection.dates
            )
            .micaPanel(padding: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: preferredTimelineWindow) {
            runtime.synchronize(preferredWindow: preferredTimelineWindow)
        }
        .onChange(of: projection.dates) { _, nextDates in
            runtime.interaction.retainPinnedDate(in: nextDates)
        }
    }

    private func telemetryHeading(dates: [Date]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaTheme.Spacing.space3) {
                telemetryTitle
                Spacer(minLength: MicaTheme.Spacing.space3)
                OverviewTelemetryControls(
                    dates: dates,
                    runtime: runtime,
                    layout: .regular
                )
            }

            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                telemetryTitle
                OverviewTelemetryControls(
                    dates: dates,
                    runtime: runtime,
                    layout: .compact
                )
            }
        }
    }

    private var telemetryTitle: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .micaThemeFont(.title3, weight: .semibold)
                .foregroundStyle(MicaTheme.textSecondary)
                .accessibilityHidden(true)
            Text(
                MicaStrings.localizedKey(
                    "overview.traffic_summary",
                    language: language
                )
            )
            .micaThemeFont(.title3)
            .foregroundStyle(MicaTheme.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func chartLayout(
        trafficSamples: [TrafficTimeline.Sample],
        memorySamples: [MemoryTimeline.Sample],
        connectionSamples: [ConnectionCountTimeline.Sample],
        dates: [Date]
    ) -> some View {
        let orderedMetrics = OverviewMetricID.allCases.filter(
            visibleMetrics.contains
        )

        Group {
            if orderedMetrics == OverviewMetricID.allCases, availableWidth >= 960 {
                HStack(alignment: .top, spacing: 0) {
                    trafficChart(
                        .upload,
                        samples: trafficSamples,
                        dates: dates,
                        plotHeight: plotHeight
                    )
                    MicaHairlineSeparator(axis: .vertical)
                        .padding(.vertical, MicaTheme.Spacing.space3)
                    trafficChart(
                        .download,
                        samples: trafficSamples,
                        dates: dates,
                        plotHeight: plotHeight
                    )
                    MicaHairlineSeparator(axis: .vertical)
                        .padding(.vertical, MicaTheme.Spacing.space3)
                    connectionChart(
                        samples: connectionSamples,
                        memorySamples: memorySamples,
                        dates: dates,
                        plotHeight: plotHeight
                    )
                }
            } else if orderedMetrics == OverviewMetricID.allCases, availableWidth >= 700 {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        trafficChart(
                            .upload,
                            samples: trafficSamples,
                            dates: dates,
                            plotHeight: plotHeight
                        )
                        MicaHairlineSeparator(axis: .vertical)
                            .padding(.vertical, MicaTheme.Spacing.space3)
                        trafficChart(
                            .download,
                            samples: trafficSamples,
                            dates: dates,
                            plotHeight: plotHeight
                        )
                    }
                    MicaHairlineSeparator()
                        .padding(.horizontal, MicaTheme.Spacing.space3)
                    connectionChart(
                        samples: connectionSamples,
                        memorySamples: memorySamples,
                        dates: dates,
                        plotHeight: plotHeight
                    )
                }
            } else if orderedMetrics.count == 2, availableWidth >= 700 {
                HStack(alignment: .top, spacing: 0) {
                    metricPanel(
                        orderedMetrics[0],
                        trafficSamples: trafficSamples,
                        memorySamples: memorySamples,
                        connectionSamples: connectionSamples,
                        dates: dates,
                        plotHeight: plotHeight
                    )
                    MicaHairlineSeparator(axis: .vertical)
                        .padding(.vertical, MicaTheme.Spacing.space3)
                    metricPanel(
                        orderedMetrics[1],
                        trafficSamples: trafficSamples,
                        memorySamples: memorySamples,
                        connectionSamples: connectionSamples,
                        dates: dates,
                        plotHeight: plotHeight
                    )
                }
            } else if let onlyMetric = orderedMetrics.first, orderedMetrics.count == 1 {
                metricPanel(
                    onlyMetric,
                    trafficSamples: trafficSamples,
                    memorySamples: memorySamples,
                    connectionSamples: connectionSamples,
                    dates: dates,
                    plotHeight: plotHeight
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(orderedMetrics.enumerated()), id: \.element) {
                        index,
                        metric in
                        if index > 0 {
                            MicaHairlineSeparator()
                                .padding(.horizontal, MicaTheme.Spacing.space3)
                        }
                        metricPanel(
                            metric,
                            trafficSamples: trafficSamples,
                            memorySamples: memorySamples,
                            connectionSamples: connectionSamples,
                            dates: dates,
                            plotHeight: plotHeight
                        )
                    }
                }
            }
        }
    }

    private var plotHeight: CGFloat {
        let columnCount: CGFloat
        if visibleMetrics.count >= 3, availableWidth >= 960 {
            columnCount = 3
        } else if visibleMetrics.count >= 2, availableWidth >= 700 {
            columnCount = 2
        } else {
            columnCount = 1
        }
        let panelWidth = max(availableWidth / columnCount, 0)
        return min(max(panelWidth * 0.60, 240), 300)
    }

    @ViewBuilder
    private func metricPanel(
        _ metric: OverviewMetricID,
        trafficSamples: [TrafficTimeline.Sample],
        memorySamples: [MemoryTimeline.Sample],
        connectionSamples: [ConnectionCountTimeline.Sample],
        dates: [Date],
        plotHeight: CGFloat
    ) -> some View {
        switch metric {
        case .upload:
            trafficChart(
                .upload,
                samples: trafficSamples,
                dates: dates,
                plotHeight: plotHeight
            )
        case .download:
            trafficChart(
                .download,
                samples: trafficSamples,
                dates: dates,
                plotHeight: plotHeight
            )
        case .activeConnections:
            connectionChart(
                samples: connectionSamples,
                memorySamples: memorySamples,
                dates: dates,
                plotHeight: plotHeight
            )
        }
    }

    @ViewBuilder
    private func trafficChart(
        _ metric: OverviewTrafficMetric,
        samples: [TrafficTimeline.Sample],
        dates: [Date],
        plotHeight: CGFloat
    ) -> some View {
        OverviewTrafficChart(
            metric: metric,
            samples: samples,
            dates: dates,
            window: runtime.timelineWindow,
            interaction: runtime.interaction,
            allowsMotion: allowsMotion,
            plotHeight: plotHeight
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func connectionChart(
        samples: [ConnectionCountTimeline.Sample],
        memorySamples: [MemoryTimeline.Sample],
        dates: [Date],
        plotHeight: CGFloat
    ) -> some View {
        OverviewConnectionChart(
            samples: samples,
            memorySamples: memorySamples,
            dates: dates,
            window: runtime.timelineWindow,
            interaction: runtime.interaction,
            allowsMotion: allowsMotion,
            plotHeight: plotHeight
        )
        .frame(maxWidth: .infinity)
    }

    /// Design.md §2 motion rule: a finite data-arrival pulse only. Reduce
    /// Motion, a paused stream, and an inactive window render fully static.
    private var allowsMotion: Bool {
        !reduceMotion
            && controlActiveState != .inactive
            && !runtime.isPaused
            && !appModel.controllerSessionPresentation.controls.dashboardUpdatesPaused
    }
}

private enum OverviewTelemetryControlsLayout {
    case regular
    case compact
}

private struct OverviewTelemetryControls: View {
    @Environment(AppModel.self) private var appModel
    @Environment(OverviewPreferencesStore.self) private var preferencesStore
    @Environment(\.micaAppLanguage) private var language

    let dates: [Date]
    let runtime: OverviewTelemetryRuntime
    let layout: OverviewTelemetryControlsLayout

    var body: some View {
        let snapshot = runtime.interaction.snapshot

        switch layout {
        case .regular:
            HStack(spacing: MicaTheme.Spacing.space2) {
                chartState(snapshot: snapshot)
                chartCommands(snapshot: snapshot)
                timelinePicker
            }
        case .compact:
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                HStack(spacing: MicaTheme.Spacing.space2) {
                    chartState(snapshot: snapshot)
                    Spacer(minLength: MicaTheme.Spacing.space2)
                    chartCommands(snapshot: snapshot)
                }
                timelinePicker
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func chartCommands(
        snapshot: OverviewTimelineInteractionSnapshot
    ) -> some View {
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
    }

    private var timelinePicker: some View {
        Picker(
            MicaStrings.localizedKey("overview.timeline_window", language: language),
            selection: Binding(
                get: { preferencesStore.preferences.timelineWindow },
                set: { window in
                    preferencesStore.setTimelineWindow(window)
                    runtime.setTimelineWindow(window)
                }
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

    private func chartState(
        snapshot: OverviewTimelineInteractionSnapshot
    ) -> some View {
        let key: String
        let tint: Color
        let systemImage: String
        if runtime.isPaused
            || appModel.controllerSessionPresentation.controls.dashboardUpdatesPaused {
            key = "overview.chart_paused"
            tint = MicaTheme.statusWarning
            systemImage = "pause.circle.fill"
        } else if snapshot.isPinned {
            key = "overview.chart_selected"
            tint = MicaTheme.accent
            systemImage = "scope"
        } else if liveSamplesAreCurrent {
            key = "overview.chart_live"
            tint = MicaTheme.accent
            systemImage = "dot.radiowaves.left.and.right"
        } else {
            key = "overview.chart_stale"
            tint = MicaTheme.statusWarning
            systemImage = "exclamationmark.triangle.fill"
        }

        return HStack(spacing: MicaTheme.Spacing.space1) {
            Image(systemName: systemImage)
                .micaThemeFont(.caption, weight: .semibold)
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(MicaStrings.localizedKey(key, language: language))
                .micaThemeFont(.caption, weight: .semibold)
                .foregroundStyle(MicaTheme.textPrimary)
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

        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
            HStack(spacing: MicaTheme.Spacing.space1) {
                Image(systemName: status.systemImage)
                    .micaThemeFont(.caption, weight: .semibold)
                    .foregroundStyle(status.tint)
                    .frame(width: 16)
                Text(verbatim: status.title)
                    .micaThemeFont(.caption, weight: .semibold)
                    .foregroundStyle(MicaTheme.textPrimary)
                    .lineLimit(1)
            }

            if let timestamp = OverviewFormat.displayableTimestamp(status.timestamp) {
                Label {
                    Text(timestamp, format: .dateTime.hour().minute().second())
                        .micaThemeFont(.dataLabel)
                } icon: {
                    Image(systemName: "clock")
                        .accessibilityHidden(true)
                }
                .foregroundStyle(MicaTheme.textSecondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, MicaTheme.Spacing.space3)
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
                tint: MicaTheme.statusWarning,
                timestamp: session.controls.presentationPausedAt
            )
        }

        let title = session.state.label(language: language)
        switch session.state {
        case .idle:
            return Presentation(
                title: title,
                systemImage: "circle",
                tint: MicaTheme.textTertiary,
                timestamp: session.lastSuccessAt
            )
        case .connecting:
            return Presentation(
                title: title,
                systemImage: "arrow.triangle.2.circlepath",
                tint: MicaTheme.textSecondary,
                timestamp: session.lastSuccessAt
            )
        case .live:
            return Presentation(
                title: title,
                systemImage: "checkmark.circle.fill",
                tint: MicaTheme.statusOK,
                timestamp: session.lastSuccessAt
            )
        case .staleReconnecting, .partial:
            return Presentation(
                title: title,
                systemImage: "exclamationmark.triangle.fill",
                tint: MicaTheme.statusWarning,
                timestamp: session.lastSuccessAt
            )
        case .failedBeforeFirstSnapshot, .failed:
            return Presentation(
                title: title,
                systemImage: "xmark.octagon.fill",
                tint: MicaTheme.statusError,
                timestamp: session.lastSuccessAt
            )
        case .stopped:
            return Presentation(
                title: title,
                systemImage: "stop.circle",
                tint: MicaTheme.textTertiary,
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
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let titleKey: String
    let symbol: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
            HStack(spacing: MicaTheme.Spacing.space1) {
                Image(systemName: symbol)
                    .micaThemeFont(.caption, weight: .semibold)
                    .foregroundStyle(MicaTheme.textTertiary)
                    .accessibilityHidden(true)
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaThemeFont(.caption)
                    .foregroundStyle(MicaTheme.textSecondary)
                    .lineLimit(1)
            }
            Text(verbatim: value)
                .micaThemeFont(.dataBody, weight: .semibold)
                .foregroundStyle(MicaTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .textSelection(.enabled)
        }
        .padding(.horizontal, MicaTheme.Spacing.space3)
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
        case .upload: "arrow.up.right"
        case .download: "arrow.down.left"
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
    let value: String?
    let timestamp: Date?
    let contextText: String?
    let plotHeight: CGFloat
    private let plot: Plot

    init(
        titleKey: String,
        systemImage: String,
        value: String?,
        timestamp: Date?,
        contextText: String? = nil,
        plotHeight: CGFloat,
        @ViewBuilder plot: () -> Plot
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.value = value
        self.timestamp = timestamp
        self.contextText = contextText
        self.plotHeight = plotHeight
        self.plot = plot()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            HStack(spacing: MicaTheme.Spacing.space2) {
                Image(systemName: systemImage)
                    .micaThemeFont(.caption, weight: .semibold)
                    .foregroundStyle(MicaTheme.textTertiary)
                    .accessibilityHidden(true)
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaThemeFont(.caption, weight: .semibold)
                    .foregroundStyle(MicaTheme.textSecondary)
            }
            .accessibilityElement(children: .combine)

            Text(
                verbatim: value ?? MicaStrings.localizedKey(
                    "overview.config_not_reported",
                    language: language
                )
            )
            .micaThemeFont(.dataHero, weight: .semibold)
            .foregroundStyle(value == nil ? MicaTheme.textTertiary : MicaTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .textSelection(.enabled)

            plot
                .frame(maxWidth: .infinity)
                .frame(height: plotHeight)

            HStack(spacing: MicaTheme.Spacing.space2) {
                if let timestamp {
                    Text(timestamp, format: .dateTime.hour().minute().second())
                        .micaThemeFont(.dataCaption)
                        .foregroundStyle(MicaTheme.textSecondary)
                }
                Spacer(minLength: MicaTheme.Spacing.space2)
                if let contextText {
                    Text(verbatim: contextText)
                        .micaThemeFont(.dataCaption)
                        .foregroundStyle(MicaTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .textSelection(.enabled)
                }
            }
            .frame(minHeight: 18)
        }
        .padding(MicaTheme.Spacing.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OverviewTelemetryEmptyPlot: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String

    var body: some View {
        VStack(spacing: MicaTheme.Spacing.space2) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .micaThemeFont(.title3)
                .foregroundStyle(MicaTheme.textTertiary)
                .accessibilityHidden(true)
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaThemeFont(.caption, weight: .medium)
                .foregroundStyle(MicaTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Flat latest-sample mark for the Mica Ops charts (design.md §2): one finite
/// pulse keyed to a real new sample, rendered statically when Reduce Motion is
/// on, the stream is paused, or the window is inactive.
private struct OverviewLatestDataMark: View {
    let trigger: Int
    let allowsMotion: Bool

    var body: some View {
        if allowsMotion {
            mark
                .phaseAnimator([0.0, 1.0, 0.0], trigger: trigger) { content, phase in
                    content
                        .scaleEffect(1 + phase * 0.35)
                        .opacity(1 - phase * 0.15)
                } animation: { phase in
                    phase > 0
                        ? .easeOut(duration: 0.22)
                        : .easeInOut(duration: 0.34)
                }
        } else {
            mark
        }
    }

    private var mark: some View {
        ZStack {
            Circle()
                .stroke(MicaTheme.accent.opacity(0.45), lineWidth: 1)
                .frame(width: 12, height: 12)
            Circle()
                .fill(MicaTheme.accent)
                .frame(width: 6, height: 6)
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

private struct OverviewTrafficChart: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let metric: OverviewTrafficMetric
    let samples: [TrafficTimeline.Sample]
    let dates: [Date]
    let window: OverviewTimelineWindow
    let interaction: OverviewTimelineInteractionState
    let allowsMotion: Bool
    let plotHeight: CGFloat

    var body: some View {
        let displayedSample = displayedSample

        OverviewTelemetryPanel(
            titleKey: metric.titleKey,
            systemImage: metric.systemImage,
            value: displayedSample.map { OverviewFormat.rate(metric.value(in: $0)) },
            timestamp: displayedSample?.receivedAt,
            plotHeight: plotHeight
        ) {
            if samples.isEmpty {
                OverviewTelemetryEmptyPlot(titleKey: "overview.no_traffic_samples")
            } else {
                OverviewTrafficBaseChart(
                    metric: metric,
                    samples: samples,
                    window: window,
                    language: language,
                    allowsMotion: allowsMotion
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

    private var displayedSample: TrafficTimeline.Sample? {
        guard let target = interaction.snapshot.selectedDate else {
            return appModel.trafficTimeline.samples.last ?? samples.last
        }
        return OverviewTimelineProjection.nearestTrafficSample(to: target, in: samples)
    }

    private var accessibilityValue: String {
        guard let displayedSample else { return "" }
        let time = displayedSample.receivedAt.formatted(date: .omitted, time: .standard)
        let title = MicaStrings.localizedKey(metric.titleKey, language: language)
        return "\(time), \(title): \(OverviewFormat.rate(metric.value(in: displayedSample)))"
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
    let metric: OverviewTrafficMetric
    let samples: [TrafficTimeline.Sample]
    let window: OverviewTimelineWindow
    let language: AppLanguage
    let allowsMotion: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.metric == rhs.metric
            && lhs.samples == rhs.samples
            && lhs.window == rhs.window
            && lhs.language == rhs.language
            && lhs.allowsMotion == rhs.allowsMotion
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
                .foregroundStyle(MicaTheme.accent.opacity(0.12))

                LinePlot(
                    samples,
                    x: .value(timeLabel, \.receivedAt),
                    y: .value(metricLabel, \.upload)
                )
                .foregroundStyle(MicaTheme.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.6))

            } else {
                AreaPlot(
                    samples,
                    x: .value(timeLabel, \.receivedAt),
                    y: .value(metricLabel, \.download)
                )
                .foregroundStyle(MicaTheme.accent.opacity(0.12))

                LinePlot(
                    samples,
                    x: .value(timeLabel, \.receivedAt),
                    y: .value(metricLabel, \.download)
                )
                .foregroundStyle(MicaTheme.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.6))

            }

            if let latestSample = samples.last {
                PointMark(
                    x: .value(timeLabel, latestSample.receivedAt),
                    y: .value(metricLabel, metric.value(in: latestSample))
                )
                .foregroundStyle(MicaTheme.accent)
                .symbol {
                    OverviewLatestDataMark(
                        trigger: latestSample.id,
                        allowsMotion: allowsMotion
                    )
                }
            }
        }
        .chartXScale(domain: dateDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: scale.axisValues) { value in
                AxisGridLine().foregroundStyle(MicaTheme.separator)
                AxisValueLabel {
                    if let bytes = value.as(Int.self) {
                        Text(verbatim: OverviewFormat.rate(bytes))
                            .micaThemeFont(.dataCaption)
                            .foregroundStyle(MicaTheme.textTertiary)
                    }
                }
            }
        }
        .chartYScale(domain: scale.domain)
        .chartLegend(.hidden)
        .frame(maxWidth: .infinity)
    }

    private var timeLabel: String { MicaStrings.localizedKey("traffic.log_time", language: language) }
    private var metricLabel: String {
        MicaStrings.localizedKey(metric.titleKey, language: language)
    }
}

private struct OverviewConnectionChart: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let samples: [ConnectionCountTimeline.Sample]
    let memorySamples: [MemoryTimeline.Sample]
    let dates: [Date]
    let window: OverviewTimelineWindow
    let interaction: OverviewTimelineInteractionState
    let allowsMotion: Bool
    let plotHeight: CGFloat

    var body: some View {
        let displayedSample = displayedSample

        OverviewTelemetryPanel(
            titleKey: "overview.connection_count",
            systemImage: "network",
            value: displayedSample?.activeCount.formatted(),
            timestamp: displayedSample?.receivedAt,
            contextText: memoryContextText,
            plotHeight: plotHeight
        ) {
            if samples.isEmpty {
                OverviewTelemetryEmptyPlot(titleKey: "overview.no_connection_samples")
            } else {
                OverviewConnectionBaseChart(
                    samples: samples,
                    window: window,
                    language: language,
                    allowsMotion: allowsMotion
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

    private var displayedSample: ConnectionCountTimeline.Sample? {
        guard let target = interaction.snapshot.selectedDate else {
            return appModel.connectionCountTimeline.samples.last ?? samples.last
        }
        return OverviewTimelineProjection.nearestConnectionSample(
            to: target,
            in: samples
        )
    }

    private var selectedMemorySample: MemoryTimeline.Sample? {
        guard let target = interaction.snapshot.selectedDate else {
            return appModel.memoryTimeline.samples.last ?? memorySamples.last
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
        guard let displayedSample else { return "" }
        let time = displayedSample.receivedAt.formatted(date: .omitted, time: .standard)
        return "\(time), \(displayedSample.activeCount.formatted()), \(memoryContextText)"
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
    let samples: [ConnectionCountTimeline.Sample]
    let window: OverviewTimelineWindow
    let language: AppLanguage
    let allowsMotion: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.samples == rhs.samples
            && lhs.window == rhs.window
            && lhs.language == rhs.language
            && lhs.allowsMotion == rhs.allowsMotion
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
            .foregroundStyle(MicaTheme.accent.opacity(0.12))

            LinePlot(
                samples,
                x: .value(timeLabel, \.receivedAt),
                y: .value(connectionLabel, \.activeCount)
            )
            .foregroundStyle(MicaTheme.accent)
            .lineStyle(StrokeStyle(lineWidth: 1.5))

            if let latestSample = samples.last {
                PointMark(
                    x: .value(timeLabel, latestSample.receivedAt),
                    y: .value(connectionLabel, latestSample.activeCount)
                )
                .foregroundStyle(MicaTheme.accent)
                .symbol {
                    OverviewLatestDataMark(
                        trigger: latestSample.id,
                        allowsMotion: allowsMotion
                    )
                }
            }
        }
        .chartXScale(domain: dateDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: scale.axisValues) { value in
                AxisGridLine().foregroundStyle(MicaTheme.separator)
                AxisValueLabel {
                    if let count = value.as(Int.self) {
                        Text(verbatim: count.formatted())
                            .micaThemeFont(.dataCaption)
                            .foregroundStyle(MicaTheme.textTertiary)
                    }
                }
            }
        }
        .chartYScale(domain: scale.domain)
        .chartLegend(.hidden)
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
                with: .color(MicaTheme.textSecondary.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )

            drawPoint(
                at: CGPoint(x: resolvedX, y: plotFrame.minY + y),
                color: MicaTheme.accent,
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
                with: .color(MicaTheme.textSecondary.opacity(0.7)),
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
                with: .color(MicaTheme.accent)
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
