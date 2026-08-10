import Charts
import Foundation
import SwiftUI

struct OverviewInstrumentRailSection: View {
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
                symbol: "arrow.up.right",
                value: OverviewFormat.rate(appModel.connectionsCatalog.traffic.upload),
                tint: MicaStyle.signalViolet
            )
        case .download:
            OverviewInstrumentReadout(
                titleKey: "overview.download_rate",
                symbol: "arrow.down.left",
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

struct OverviewTelemetrySection: View {
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
            .background(MicaStyle.contentFill)
            .clipShape(.rect(cornerRadius: MicaBounds.moduleRadius))
            .overlay {
                RoundedRectangle(cornerRadius: MicaBounds.moduleRadius)
                    .stroke(MicaStyle.separator.opacity(0.5), lineWidth: 1)
            }
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
                    runtime: runtime,
                    layout: .regular
                )
            }

            VStack(alignment: .leading, spacing: MicaSpacing.row) {
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
        HStack(spacing: MicaSpacing.row) {
            OverviewSymbolMark(
                systemName: "chart.line.uptrend.xyaxis",
                tint: MicaStyle.signalCyan,
                size: .section
            )
            Text(
                MicaStrings.localizedKey(
                    "overview.traffic_summary",
                    language: language
                )
            )
            .micaFont(.title3, weight: .semibold)
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
        Group {
            if availableWidth >= 960 {
                HStack(alignment: .top, spacing: 0) {
                    trafficChart(
                        .upload,
                        samples: trafficSamples,
                        dates: dates,
                        plotHeight: plotHeight
                    )
                    Divider()
                        .padding(.vertical, MicaSpacing.module)
                    trafficChart(
                        .download,
                        samples: trafficSamples,
                        dates: dates,
                        plotHeight: plotHeight
                    )
                    Divider()
                        .padding(.vertical, MicaSpacing.module)
                    connectionChart(
                        samples: connectionSamples,
                        memorySamples: memorySamples,
                        dates: dates,
                        plotHeight: plotHeight
                    )
                }
            } else if availableWidth >= 700 {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        trafficChart(
                            .upload,
                            samples: trafficSamples,
                            dates: dates,
                            plotHeight: plotHeight
                        )
                        Divider()
                            .padding(.vertical, MicaSpacing.module)
                        trafficChart(
                            .download,
                            samples: trafficSamples,
                            dates: dates,
                            plotHeight: plotHeight
                        )
                    }
                    Divider()
                        .padding(.horizontal, MicaSpacing.module)
                    connectionChart(
                        samples: connectionSamples,
                        memorySamples: memorySamples,
                        dates: dates,
                        plotHeight: plotHeight
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    trafficChart(
                        .upload,
                        samples: trafficSamples,
                        dates: dates,
                        plotHeight: plotHeight
                    )
                    Divider()
                        .padding(.horizontal, MicaSpacing.module)
                    trafficChart(
                        .download,
                        samples: trafficSamples,
                        dates: dates,
                        plotHeight: plotHeight
                    )
                    Divider()
                        .padding(.horizontal, MicaSpacing.module)
                    connectionChart(
                        samples: connectionSamples,
                        memorySamples: memorySamples,
                        dates: dates,
                        plotHeight: plotHeight
                    )
                }
            }
        }
    }

    private var plotHeight: CGFloat {
        let columnCount: CGFloat
        if availableWidth >= 960 {
            columnCount = 3
        } else if availableWidth >= 700 {
            columnCount = 2
        } else {
            columnCount = 1
        }
        let panelWidth = max(availableWidth / columnCount, 0)
        return min(max(panelWidth * 0.60, 240), 300)
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
            plotHeight: plotHeight
        )
        .frame(maxWidth: .infinity)
    }
}

private enum OverviewTelemetryControlsLayout {
    case regular
    case compact
}

private struct OverviewTelemetryControls: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let dates: [Date]
    let runtime: OverviewTelemetryModuleRuntime
    let layout: OverviewTelemetryControlsLayout

    var body: some View {
        let snapshot = runtime.interaction.snapshot

        switch layout {
        case .regular:
            HStack(spacing: MicaSpacing.row) {
                chartState(snapshot: snapshot)
                chartCommands(snapshot: snapshot)
                timelinePicker
            }
        case .compact:
            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                HStack(spacing: MicaSpacing.row) {
                    chartState(snapshot: snapshot)
                    Spacer(minLength: MicaSpacing.row)
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
        } else if snapshot.isPinned {
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
        case .upload: "arrow.up.right"
        case .download: "arrow.down.left"
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
    let plotHeight: CGFloat
    private let plot: Plot

    init(
        titleKey: String,
        systemImage: String,
        tint: Color,
        value: String?,
        timestamp: Date?,
        contextText: String? = nil,
        plotHeight: CGFloat,
        @ViewBuilder plot: () -> Plot
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.tint = tint
        self.value = value
        self.timestamp = timestamp
        self.contextText = contextText
        self.plotHeight = plotHeight
        self.plot = plot()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            HStack(spacing: MicaSpacing.tight) {
                OverviewSymbolMark(
                    systemName: systemImage,
                    tint: tint,
                    size: .metric
                )
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaFont(.callout, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

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
                .frame(height: plotHeight)

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
    }
}

private struct OverviewTelemetryEmptyPlot: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String

    var body: some View {
        VStack(spacing: MicaSpacing.row) {
            OverviewSymbolMark(
                systemName: "chart.line.uptrend.xyaxis",
                tint: .secondary,
                size: .section
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
    let plotHeight: CGFloat

    var body: some View {
        let selectedSample = selectedSample

        OverviewTelemetryPanel(
            titleKey: metric.titleKey,
            systemImage: metric.systemImage,
            tint: metric.tint,
            value: selectedSample.map { OverviewFormat.rate(metric.value(in: $0)) },
            timestamp: selectedSample?.receivedAt,
            plotHeight: plotHeight
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
    let plotHeight: CGFloat

    var body: some View {
        let selectedSample = selectedSample

        OverviewTelemetryPanel(
            titleKey: "overview.connection_count",
            systemImage: "network",
            tint: MicaStyle.signalMint,
            value: selectedSample?.activeCount.formatted(),
            timestamp: selectedSample?.receivedAt,
            contextText: memoryContextText,
            plotHeight: plotHeight
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
