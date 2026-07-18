import Charts
import Foundation
import MicaCore
import SwiftUI

struct WorkbenchOverviewView: View {
    var appModel: AppModel

    @Environment(\.micaAppLanguage) private var appLanguage
    @Environment(\.micaFontMultiplier) private var fontMultiplier

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                identityCard

                if showsConnectingGuide {
                    connectingGuideCard
                } else {
                    kpiRow
                    trafficCard
                    insightGrid
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            inventoryCard
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            endpointCard
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            inventoryCard
                            endpointCard
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
    }

    private var showsConnectingGuide: Bool {
        appModel.selectedRouter != nil
            && appModel.controllerSession.state == .connecting
            && !appModel.dashboard.hasBaseSnapshot
    }

    private var insight: InsightSummarySnapshot {
        appModel.dashboard.insight
    }

    // MARK: Connecting guide

    private var connectingGuideCard: some View {
        dashboardCard(spacing: 14) {
            VStack(alignment: .center, spacing: 12) {
                ProgressView()
                    .controlSize(.large)

                VStack(spacing: 6) {
                    MicaText("overview.connecting_title")
                        .font(.system(size: 16 * fontMultiplier, weight: .semibold))
                        .multilineTextAlignment(.center)

                    MicaText("overview.connecting_message")
                        .font(.system(size: 12.5 * fontMultiplier))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Card container

    /// Unified content-layer card built on `MicaContentCard`: a system
    /// `.regularMaterial` fill + soft semantic hairline that follows the system
    /// light/dark appearance like every other v4 surface. Passing a `tint`
    /// applies a faint semantic border so the card reads as owned by its accent.
    /// This is a passive *content-layer* surface (materials), deliberately not
    /// `.glassEffect` — native Liquid Glass stays reserved for interactive
    /// selection blocks via `MicaGlassSelectionSurface` (workbench-ui-contract).
    private func dashboardCard<Content: View>(
        tint: Color? = nil,
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) -> some View {
        MicaContentCard(tint: tint, spacing: spacing, content: content)
    }

    private func cardTitle(_ key: String, systemImage: String, tint: Color = MicaStyle.accent) -> some View {
        Label {
            MicaText(key)
                .font(.system(size: 13 * fontMultiplier, weight: .semibold))
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 12.5 * fontMultiplier, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    // MARK: Identity bar

    private var identityCard: some View {
        dashboardCard(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: appModel.selectedRouter?.controllerKind.sidebarSymbol ?? MicaSymbols.Controller.unknown)
                    .font(.system(size: 22 * fontMultiplier, weight: .semibold))
                    .foregroundStyle(appModel.selectedRouter?.controllerKind.sidebarTint ?? .secondary)
                    .frame(width: 34 * fontMultiplier, height: 34 * fontMultiplier)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill((appModel.selectedRouter?.controllerKind.sidebarTint ?? .secondary).opacity(0.14))
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(appModel.selectedRouter?.displayName ?? MicaStrings.localizedKey("dashboard.no_controller", language: appLanguage))
                        .font(.system(size: 18 * fontMultiplier, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    if let router = appModel.selectedRouter {
                        Text(router.endpointURL)
                            .font(.system(size: 12 * fontMultiplier, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                healthBadge
            }

            if reportedVersion != nil || reportedMode != nil {
                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    identityValue(titleKey: "settings.controller_type", value: appModel.selectedRouter?.controllerKind.micaLabel(language: appLanguage))
                    identityValue(titleKey: "dashboard.cmd_version", value: reportedVersion)
                    identityValue(titleKey: "dashboard.mode", value: reportedMode)
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var healthBadge: some View {
        Label {
            Text(appModel.controllerHealth.summary.label(language: appLanguage))
        } icon: {
            Image(systemName: appModel.controllerHealth.summary.sidebarIconName)
        }
        .font(.system(size: 12 * fontMultiplier, weight: .semibold))
        .foregroundStyle(appModel.controllerHealth.summary.sidebarTint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(appModel.controllerHealth.summary.sidebarTint.opacity(0.14))
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: KPI tile row

    private var kpiRow: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150 * fontMultiplier, maximum: 260), spacing: 12)],
            spacing: 12
        ) {
            kpiTile(
                titleKey: "dashboard.upload",
                systemImage: "arrow.up.circle.fill",
                value: currentRate(appModel.liveTrafficRate.upload),
                tint: MicaStyle.signalCyan
            )
            kpiTile(
                titleKey: "dashboard.download",
                systemImage: "arrow.down.circle.fill",
                value: currentRate(appModel.liveTrafficRate.download),
                tint: MicaStyle.signalViolet
            )
            kpiTile(
                titleKey: "dashboard.tab_connections",
                systemImage: "point.3.filled.connected.trianglepath.dotted",
                value: countValue(appModel.dashboard.connections.count, endpoint: .connections),
                tint: MicaStyle.signalMint
            )
            kpiTile(
                titleKey: "dashboard.routing_modules_header",
                systemImage: "square.grid.2x2.fill",
                value: countValue(appModel.dashboard.groups.count, endpoint: .proxies),
                tint: MicaStyle.accent
            )
            kpiTile(
                titleKey: "dashboard.tab_rules",
                systemImage: "list.bullet.rectangle.fill",
                value: countValue(appModel.dashboard.rules.count, endpoint: .rules),
                tint: MicaStyle.signalAmber
            )
            kpiTile(
                titleKey: "dashboard.tab_providers",
                systemImage: "shippingbox.fill",
                value: countValue(appModel.dashboard.providers.count, endpoint: .providers),
                tint: MicaStyle.signalCyan
            )
        }
    }

    private func kpiTile(titleKey: String, systemImage: String, value: OverviewMetricValue, tint: Color) -> some View {
        dashboardCard(tint: tint, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13 * fontMultiplier, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24 * fontMultiplier, height: 24 * fontMultiplier)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tint.opacity(0.16))
                    )
                    .accessibilityHidden(true)
                MicaText(titleKey)
                    .font(.system(size: 11.5 * fontMultiplier, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if value.isFallback {
                Text(value.text)
                    .font(.system(size: 13 * fontMultiplier))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(value.text)
                    .font(.system(size: 23 * fontMultiplier, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MicaStrings.localized("overview.acc_telemetry_value \(MicaStrings.localizedKey(titleKey, language: appLanguage)) \(value.text)", language: appLanguage))
    }

    // MARK: Traffic card

    private var trafficCard: some View {
        dashboardCard {
            cardTitle("overview.traffic_summary", systemImage: "arrow.up.arrow.down")

            if appModel.trafficTimeline.isEmpty {
                trafficAvailability
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    trafficLegend

                    trafficChart
                        .frame(minHeight: 190 * fontMultiplier)
                        .accessibilityLabel(MicaStrings.localizedKey("overview.traffic_summary", language: appLanguage))
                        .accessibilityValue(
                            MicaStrings.localized(
                                "overview.traffic_timeline_samples \(appModel.trafficTimeline.samples.count) \(TrafficTimeline.maximumSampleCount)",
                                language: appLanguage
                            )
                        )
                }
            }

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    trafficMetric(titleKey: "overview.config_upload_total", value: cumulativeTraffic(appModel.dashboard.traffic.upload), tint: MicaStyle.signalCyan)
                    Divider().frame(height: 40 * fontMultiplier)
                    trafficMetric(titleKey: "overview.config_download_total", value: cumulativeTraffic(appModel.dashboard.traffic.download), tint: MicaStyle.signalViolet)
                }

                VStack(alignment: .leading, spacing: 10) {
                    trafficMetric(titleKey: "overview.config_upload_total", value: cumulativeTraffic(appModel.dashboard.traffic.upload), tint: MicaStyle.signalCyan)
                    trafficMetric(titleKey: "overview.config_download_total", value: cumulativeTraffic(appModel.dashboard.traffic.download), tint: MicaStyle.signalViolet)
                }
            }

            if let updatedAt = appModel.liveStreamUpdatedAt {
                Text(updatedAt, format: .dateTime.hour().minute().second())
                    .font(.system(size: 11.5 * fontMultiplier, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel(
                        MicaStrings.localized(
                            "live.last_update \(updatedAt.formatted(date: .omitted, time: .standard))",
                            language: appLanguage
                        )
                    )
            }
        }
    }

    @ViewBuilder
    private var trafficAvailability: some View {
        if appModel.selectedRouter == nil {
            availabilityRow("live.no_controller")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(appModel.liveStreamState.label(language: appLanguage))
                    .font(.system(size: 13 * fontMultiplier, weight: .semibold))
                Text(appModel.liveStreamState.detail(language: appLanguage))
                    .font(.system(size: 12 * fontMultiplier))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 112 * fontMultiplier, alignment: .leading)
        }
    }

    private var trafficChart: some View {
        Chart {
            ForEach(appModel.trafficTimeline.samples) { sample in
                LineMark(
                    x: .value("Time", sample.receivedAt),
                    y: .value("Rate", sample.upload),
                    series: .value("Direction", "upload")
                )
                .foregroundStyle(MicaStyle.signalCyan)
                .interpolationMethod(.linear)

                LineMark(
                    x: .value("Time", sample.receivedAt),
                    y: .value("Rate", sample.download),
                    series: .value("Direction", "download")
                )
                .foregroundStyle(MicaStyle.signalViolet)
                .interpolationMethod(.linear)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(MicaStyle.separator)
                AxisValueLabel {
                    if let rate = value.as(Int.self) {
                        Text(byteCount(rate) + "/s")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
    }

    private var trafficLegend: some View {
        HStack(spacing: 14) {
            trafficLegendItem(titleKey: "dashboard.upload", tint: MicaStyle.signalCyan)
            trafficLegendItem(titleKey: "dashboard.download", tint: MicaStyle.signalViolet)
        }
        .accessibilityElement(children: .combine)
    }

    private func trafficLegendItem(titleKey: String, tint: Color) -> some View {
        Label {
            MicaText(titleKey)
                .font(.system(size: 11.5 * fontMultiplier, weight: .medium))
                .foregroundStyle(.secondary)
        } icon: {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(tint)
                .frame(width: 14 * fontMultiplier, height: 3 * fontMultiplier)
        }
    }

    // MARK: Insight grid

    @ViewBuilder
    private var insightGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                latencyDistributionModule
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                connectionDistributionModule
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                topConnectionsModule
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 16) {
                latencyDistributionModule
                connectionDistributionModule
                topConnectionsModule
            }
        }
    }

    @ViewBuilder
    private var latencyDistributionModule: some View {
        dashboardCard {
            cardTitle("overview.latency_distribution", systemImage: "gauge.with.dots.needle.67percent", tint: MicaStyle.signalMint)
            if insight.hasLatencySamples {
                Chart(insight.routeHealth) { bucket in
                    BarMark(
                        x: .value("Grade", bucket.grade.label(language: appLanguage)),
                        y: .value("Count", bucket.count)
                    )
                    .foregroundStyle(latencyTint(bucket.grade))
                    .accessibilityLabel(bucket.grade.label(language: appLanguage))
                    .accessibilityValue(String(bucket.count))
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                }
                .frame(minHeight: 150 * fontMultiplier)
                .accessibilityLabel(MicaStrings.localizedKey("overview.latency_distribution", language: appLanguage))
                .accessibilityValue(latencyDistributionAccessibilityValue)
            } else {
                insightPlaceholder("overview.latency_distribution_empty")
            }
        }
    }

    private var latencyDistributionAccessibilityValue: String {
        insight.routeHealth
            .map { "\($0.grade.label(language: appLanguage)) \($0.count)" }
            .joined(separator: ", ")
    }

    @ViewBuilder
    private var connectionDistributionModule: some View {
        dashboardCard {
            cardTitle("overview.connection_distribution", systemImage: "chart.pie.fill", tint: MicaStyle.signalCyan)
            if insight.hasConnectionDistribution {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(insight.connectionDistribution) { slice in
                        shareRow(
                            label: slice.label,
                            value: slice.value,
                            total: connectionDistributionTotal,
                            tint: MicaStyle.signalCyan
                        )
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(MicaStrings.localizedKey("overview.connection_distribution", language: appLanguage))
            } else {
                insightPlaceholder("overview.connection_distribution_empty")
            }
        }
    }

    private var connectionDistributionTotal: Int {
        max(insight.connectionDistribution.reduce(0) { $0 + $1.value }, 1)
    }

    @ViewBuilder
    private var topConnectionsModule: some View {
        dashboardCard {
            cardTitle("overview.top_connections", systemImage: "trophy.fill", tint: MicaStyle.signalViolet)
            if insight.topConnections.isEmpty {
                insightPlaceholder("overview.top_connections_empty")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(insight.topConnections) { connection in
                        shareRow(
                            label: topConnectionLabel(connection),
                            value: InsightSummarySnapshot.totalTraffic(connection),
                            total: topConnectionsTotal,
                            tint: MicaStyle.signalViolet,
                            valueText: byteCount(InsightSummarySnapshot.totalTraffic(connection))
                        )
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(MicaStrings.localizedKey("overview.top_connections", language: appLanguage))
            }
        }
    }

    private var topConnectionsTotal: Int {
        max(insight.topConnections.map { InsightSummarySnapshot.totalTraffic($0) }.max() ?? 1, 1)
    }

    private func topConnectionLabel(_ connection: ConnectionSnapshot) -> String {
        connection.metadata?.host?.nilIfEmpty
            ?? connection.metadata?.sniffHost?.nilIfEmpty
            ?? connection.metadata?.destinationIP?.nilIfEmpty
            ?? connection.id
    }

    private func insightPlaceholder(_ key: String) -> some View {
        MicaText(key)
            .font(.system(size: 12 * fontMultiplier))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 120 * fontMultiplier, alignment: .leading)
    }

    private func shareRow(
        label: String,
        value: Int,
        total: Int,
        tint: Color,
        valueText: String? = nil
    ) -> some View {
        let fraction = total > 0 ? min(max(Double(value) / Double(total), 0), 1) : 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.system(size: 11.5 * fontMultiplier, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(valueText ?? String(value))
                    .font(.system(size: 11 * fontMultiplier, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MicaStyle.separator.opacity(0.5))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 3 : 0))
                }
            }
            .frame(height: 6 * fontMultiplier)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(valueText ?? String(value))
    }

    private func latencyTint(_ grade: LatencyHealthGrade) -> Color {
        switch grade {
        case .fast:
            MicaStyle.signalMint
        case .normal:
            MicaStyle.signalCyan
        case .slow:
            MicaStyle.signalAmber
        case .timeout:
            MicaStyle.signalRed
        }
    }

    // MARK: Inventory card

    private var inventoryCard: some View {
        dashboardCard {
            cardTitle("overview.current_data", systemImage: "square.stack.3d.up.fill")
            Divider()

            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                GridRow {
                    inventoryMetric(titleKey: "dashboard.tab_connections", value: countValue(appModel.dashboard.connections.count, endpoint: .connections))
                    inventoryMetric(titleKey: "dashboard.routing_modules_header", value: countValue(appModel.dashboard.groups.count, endpoint: .proxies))
                }
                GridRow {
                    inventoryMetric(titleKey: "dashboard.tab_rules", value: countValue(appModel.dashboard.rules.count, endpoint: .rules))
                    inventoryMetric(titleKey: "dashboard.tab_providers", value: countValue(appModel.dashboard.providers.count, endpoint: .providers))
                }
            }
        }
    }

    // MARK: Endpoint card

    private var endpointCard: some View {
        dashboardCard {
            cardTitle("overview.endpoint_status", systemImage: "network")
            Divider()

            if appModel.controllerHealth.endpoints.isEmpty {
                availabilityRow("overview.no_controller_data")
            } else {
                endpointList
            }
        }
    }

    private var endpointList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(appModel.controllerHealth.endpoints) { endpoint in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        endpointIdentity(endpoint)
                        Spacer(minLength: 8)
                        endpointStatus(endpoint)
                    }
                    Text(endpoint.status.detail(language: appLanguage))
                        .font(.system(size: 12 * fontMultiplier))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(MicaStyle.separator).frame(height: 1)
                }
            }
        }
    }

    private func endpointIdentity(_ endpoint: ControllerEndpointHealth) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            MicaText(endpoint.endpoint.displayTitleKey)
                .font(.system(size: 12.5 * fontMultiplier, weight: .semibold))
            Text(endpoint.endpoint.apiPath)
                .font(.system(size: 11.5 * fontMultiplier, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func endpointStatus(_ endpoint: ControllerEndpointHealth) -> some View {
        Label(endpoint.status.label(language: appLanguage), systemImage: endpointIcon(endpoint.status))
            .font(.system(size: 11.5 * fontMultiplier, weight: .semibold))
            .foregroundStyle(endpointTint(endpoint.status))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Metric value helpers

    /// A metric display value: either a real controller-reported figure or a
    /// fallback (not-reported / availability wording) that renders
    /// de-emphasized instead of at full metric weight.
    private struct OverviewMetricValue {
        let text: String
        let isFallback: Bool
        /// Whether the underlying real value is exactly zero. Derived from the
        /// numeric source at construction time, not by string-matching the
        /// formatted text (which is locale-dependent), so zero styling stays
        /// correct in every language.
        var isZero: Bool = false
    }

    private func trafficMetric(titleKey: String, value: OverviewMetricValue, tint: Color) -> some View {
        let isZeroOrFallback = value.isFallback || value.isZero

        return VStack(alignment: .leading, spacing: 4) {
            MicaText(titleKey)
                .font(.system(size: 11.5 * fontMultiplier, weight: .medium))
                .foregroundStyle(.secondary)
            if isZeroOrFallback {
                Text(value.text)
                    .font(.system(size: 12 * fontMultiplier))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(value.text)
                    .font(.system(size: 16 * fontMultiplier, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MicaStrings.localized("overview.acc_telemetry_value \(MicaStrings.localizedKey(titleKey, language: appLanguage)) \(value.text)", language: appLanguage))
    }

    private func inventoryMetric(titleKey: String, value: OverviewMetricValue) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            MicaText(titleKey)
                .font(.system(size: 11.5 * fontMultiplier, weight: .medium))
                .foregroundStyle(.secondary)
            if value.isFallback {
                Text(value.text)
                    .font(.system(size: 12 * fontMultiplier))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(value.text)
                    .font(.system(size: 16 * fontMultiplier, weight: .semibold, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func identityValue(titleKey: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            MicaText(titleKey)
                .font(.system(size: 11.5 * fontMultiplier, weight: .medium))
                .foregroundStyle(.secondary)
            if let value {
                Text(value)
                    .font(.system(size: 12.5 * fontMultiplier, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                MicaText("overview.config_not_reported")
                    .font(.system(size: 11.5 * fontMultiplier))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func availabilityRow(_ key: String) -> some View {
        MicaText(key)
            .font(.system(size: 12.5 * fontMultiplier))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 112 * fontMultiplier, alignment: .leading)
    }

    private var reportedVersion: String? {
        let version = appModel.dashboard.versionLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return version == "-" || version.isEmpty ? nil : version
    }

    private var reportedMode: String? {
        let mode = appModel.dashboard.mode.trimmingCharacters(in: .whitespacesAndNewlines)
        return mode.caseInsensitiveCompare("unknown") == .orderedSame || mode.isEmpty ? nil : mode
    }

    private func currentRate(_ bytes: Int) -> OverviewMetricValue {
        guard !appModel.trafficTimeline.isEmpty else {
            return OverviewMetricValue(
                text: MicaStrings.localizedKey("overview.config_not_reported", language: appLanguage),
                isFallback: true
            )
        }
        return OverviewMetricValue(text: byteCount(bytes) + "/s", isFallback: false, isZero: bytes <= 0)
    }

    private func cumulativeTraffic(_ bytes: Int) -> OverviewMetricValue {
        guard appModel.controllerHealth.status(for: .connections).isReady else {
            return OverviewMetricValue(text: availabilityValue(for: .connections), isFallback: true)
        }
        return OverviewMetricValue(text: byteCount(bytes), isFallback: false, isZero: bytes <= 0)
    }

    private func countValue(_ count: Int, endpoint: ControllerEndpointKind) -> OverviewMetricValue {
        guard appModel.controllerHealth.status(for: endpoint).isReady else {
            return OverviewMetricValue(text: availabilityValue(for: endpoint), isFallback: true)
        }
        return OverviewMetricValue(text: String(count), isFallback: false)
    }

    private func availabilityValue(for endpoint: ControllerEndpointKind) -> String {
        switch appModel.controllerHealth.status(for: endpoint) {
        case .failed:
            MicaStrings.localizedKey("dashboard.enhanced_unavailable", language: appLanguage)
        case .checking:
            MicaStrings.localizedKey("endpoint.checking", language: appLanguage)
        case .idle, .ready:
            MicaStrings.localizedKey("overview.config_not_reported", language: appLanguage)
        }
    }

    private func byteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowsNonnumericFormatting = false
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(max(bytes, 0)))
    }

    private func endpointIcon(_ status: ControllerEndpointStatus) -> String {
        switch status {
        case .idle:
            "minus.circle"
        case .checking:
            "arrow.clockwise"
        case .ready:
            "checkmark.circle.fill"
        case .failed:
            "xmark.octagon.fill"
        }
    }

    private func endpointTint(_ status: ControllerEndpointStatus) -> Color {
        switch status {
        case .idle:
            .secondary
        case .checking:
            MicaStyle.signalCyan
        case .ready:
            MicaStyle.signalMint
        case .failed:
            MicaStyle.signalRed
        }
    }
}
