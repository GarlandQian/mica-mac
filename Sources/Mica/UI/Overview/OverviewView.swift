import MicaCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    @Binding var destination: WorkbenchDestination

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.xl) {
                headerSection

                OverviewLiveMetricsStrip(
                    onOpenConnections: { destination = .connections }
                )

                OverviewTrafficCanvas(language: language)

                OverviewQuickPoliciesSection(
                    onOpenGroup: { groupID in
                        destination = .proxies
                        _ = groupID
                    },
                    onViewAll: { destination = .proxies }
                )

                OverviewControllerFactsSection(language: language)
            }
            .padding(20)
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(MicaTheme.canvas)
    }

    private var headerSection: some View {
        let router = appModel.selectedRouter
        let session = appModel.controllerSessionPresentation
        let metadata = appModel.controllerMetadata
        let modeOptions = resolvedModeOptions

        return HStack(alignment: .center, spacing: MicaTheme.Spacing.md) {
            MicaStatusDot(color: statusColor(for: session.state), size: 9)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MicaTheme.Spacing.sm) {
                    Text(verbatim: router?.displayName ?? L("dashboard.no_controller", language: language))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(MicaTheme.textPrimary)

                    if let router {
                        Text(verbatim: appModel.controllerAdapter(for: router).detectedKind.micaLabel(language: language))
                            .font(.caption2)
                            .foregroundStyle(MicaTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MicaTheme.subtleFill, in: Capsule())
                    }
                }

                HStack(spacing: MicaTheme.Spacing.sm) {
                    Text(verbatim: session.state.label(language: language))
                        .font(.caption)
                        .foregroundStyle(MicaTheme.textSecondary)
                    if metadata.versionLabel != "-" && !metadata.versionLabel.isEmpty {
                        Text(verbatim: "· \(metadata.versionLabel)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(MicaTheme.textTertiary)
                    }
                }
            }

            Spacer(minLength: MicaTheme.Spacing.md)

            if !modeOptions.isEmpty {
                let scope = LiveCommandScope(
                    controllerID: appModel.selectedRouterID,
                    generation: session.generation
                )
                let currentMode = resolvedCurrentMode(in: modeOptions, reported: metadata.mode)

                Picker(L("dashboard.mode", language: language), selection: Binding(
                    get: { currentMode },
                    set: { next in
                        guard let scope else { return }
                        appModel.setMode(next, scope: scope)
                    }
                )) {
                    ForEach(modeOptions, id: \.self) { option in
                        Text(verbatim: MicaStrings.displayMode(option, language: language))
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
                .disabled(!canChangeMode || appModel.changingMode || appModel.changingSurgeOutbound)
            }
        }
    }

    private var canChangeMode: Bool {
        guard let router = appModel.selectedRouter,
              appModel.controllerSessionPresentation.state.allowsLiveCommands else {
            return false
        }
        return appModel.supportsUnifiedAction(appModel.modeChangeAction(for: router))
    }

    private var resolvedModeOptions: [String] {
        let reported = appModel.controllerMetadata.config.modeOptions
        if !reported.isEmpty {
            return reported
        }
        guard let router = appModel.selectedRouter else { return [] }
        if appModel.runtimeControllerKind(for: router) == .surgeCompatible {
            return ["rule", "global", "direct"]
        }
        return ["Rule", "Global", "Direct"]
    }

    private func resolvedCurrentMode(in options: [String], reported: String) -> String {
        if let exact = options.first(where: { $0.caseInsensitiveCompare(reported) == .orderedSame }) {
            return exact
        }
        return options.first ?? reported
    }

    private func statusColor(for state: LiveSessionState) -> Color {
        switch state {
        case .live: MicaTheme.statusOK
        case .partial, .staleReconnecting, .connecting: MicaTheme.statusWarning
        case .failedBeforeFirstSnapshot, .failed: MicaTheme.statusError
        case .stopped, .idle: MicaTheme.textTertiary
        }
    }
}

// MARK: - Isolated High-Frequency Leaf: Metrics Strip

private struct OverviewLiveMetricsStrip: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let onOpenConnections: () -> Void

    var body: some View {
        let rate = appModel.liveTrafficRate
        let totals = appModel.connectionsCatalog.traffic
        let activeCount = appModel.connectionsCatalog.connections.count
        let memoryBytes = appModel.memoryTimeline.samples.last?.inUseBytes

        HStack(spacing: MicaTheme.Spacing.md) {
            MetricTile(
                label: L("overview.upload_rate", language: language),
                value: MicaFormatters.formatRate(rate.upload),
                subtitle: totals.upload > 0 ? MicaFormatters.formatBytes(totals.upload) : nil,
                accent: MicaTheme.chartUpload
            )

            MetricTile(
                label: L("overview.download_rate", language: language),
                value: MicaFormatters.formatRate(rate.download),
                subtitle: totals.download > 0 ? MicaFormatters.formatBytes(totals.download) : nil,
                accent: MicaTheme.chartDownload
            )

            Button(action: onOpenConnections) {
                MetricTile(
                    label: L("dashboard.active_sessions", language: language),
                    value: activeCount.formatted(),
                    subtitle: L("dashboard.tab_connections", language: language),
                    accent: MicaTheme.chartConnections
                )
            }
            .buttonStyle(.plain)

            MetricTile(
                label: L("overview.memory_current", language: language),
                value: memoryBytes.map(MicaFormatters.formatBytes) ?? "-",
                subtitle: nil,
                accent: MicaTheme.chartMemory
            )
        }
    }
}

private struct MetricTile: View {
    let label: String
    let value: String
    let subtitle: String?
    let accent: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MicaTheme.Radius.card, style: .continuous)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                MicaStatusDot(color: accent, size: 6)
                Text(verbatim: label)
                    .font(.caption)
                    .foregroundStyle(MicaTheme.textSecondary)
                    .lineLimit(1)
            }

            Text(verbatim: value)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(MicaTheme.textPrimary)
                .lineLimit(1)

            Text(verbatim: subtitle ?? " ")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(subtitle == nil ? .clear : MicaTheme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaTheme.surface, in: shape)
        .overlay {
            shape.strokeBorder(MicaTheme.separator, lineWidth: 0.75)
        }
    }
}

// MARK: - Isolated High-Frequency Leaf: Lightweight Traffic Canvas

private struct OverviewTrafficCanvas: View {
    @Environment(AppModel.self) private var appModel
    let language: AppLanguage

    var body: some View {
        let samples = Array(appModel.trafficTimeline.samples.suffix(120))
        let peakRate = max(
            samples.map { max($0.upload, $0.download) }.max() ?? 0,
            1_024
        )
        let shape = RoundedRectangle(cornerRadius: MicaTheme.Radius.panel, style: .continuous)

        VStack(alignment: .leading, spacing: MicaTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.md) {
                Text(verbatim: L("overview.traffic_summary", language: language))
                    .font(.headline)
                    .foregroundStyle(MicaTheme.textPrimary)

                Spacer(minLength: 0)

                HStack(spacing: MicaTheme.Spacing.md) {
                    legendChip(color: MicaTheme.chartDownload, label: L("dashboard.col_download", language: language))
                    legendChip(color: MicaTheme.chartUpload, label: L("dashboard.col_upload", language: language))
                    Text(verbatim: "Peak \(MicaFormatters.formatRate(peakRate))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(MicaTheme.textTertiary)
                }
            }

            Canvas { context, size in
                drawTrafficGraph(in: &context, size: size, samples: samples, peak: peakRate)
            }
            .frame(height: 140)
            .overlay {
                if samples.count < 2 {
                    Text(verbatim: L("dashboard.no_active_flow", language: language))
                        .font(.caption)
                        .foregroundStyle(MicaTheme.textTertiary)
                }
            }
        }
        .padding(MicaTheme.Spacing.lg)
        .background(MicaTheme.surface, in: shape)
        .overlay {
            shape.strokeBorder(MicaTheme.separator, lineWidth: 0.75)
        }
    }

    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            MicaStatusDot(color: color, size: 6)
            Text(verbatim: label)
                .font(.caption)
                .foregroundStyle(MicaTheme.textSecondary)
        }
    }

    private func drawTrafficGraph(
        in context: inout GraphicsContext,
        size: CGSize,
        samples: [TrafficTimeline.Sample],
        peak: Int
    ) {
        let width = size.width
        let height = size.height
        guard width > 0, height > 0 else { return }

        // Subtle horizontal baseline guides
        for step in [0.25, 0.5, 0.75] {
            let y = height * step
            var guide = Path()
            guide.move(to: CGPoint(x: 0, y: y))
            guide.addLine(to: CGPoint(x: width, y: y))
            context.stroke(guide, with: .color(MicaTheme.separator.opacity(0.45)), lineWidth: 0.5)
        }

        guard samples.count >= 2 else { return }
        let maxVal = Double(max(peak, 1))
        let count = samples.count

        func points(for keyPath: KeyPath<TrafficTimeline.Sample, Int>) -> [CGPoint] {
            samples.enumerated().map { idx, sample in
                let x = width * CGFloat(idx) / CGFloat(count - 1)
                let normalized = min(max(Double(sample[keyPath: keyPath]) / maxVal, 0), 1)
                let y = height - 4 - CGFloat(normalized) * (height - 12)
                return CGPoint(x: x, y: y)
            }
        }

        drawSeries(points(for: \.download), color: MicaTheme.chartDownload, in: &context, height: height)
        drawSeries(points(for: \.upload), color: MicaTheme.chartUpload, in: &context, height: height)
    }

    private func drawSeries(
        _ points: [CGPoint],
        color: Color,
        in context: inout GraphicsContext,
        height: CGFloat
    ) {
        guard let first = points.first, let last = points.last else { return }

        var strokePath = Path()
        strokePath.move(to: first)
        for point in points.dropFirst() {
            strokePath.addLine(to: point)
        }

        var fillPath = strokePath
        fillPath.addLine(to: CGPoint(x: last.x, y: height))
        fillPath.addLine(to: CGPoint(x: first.x, y: height))
        fillPath.closeSubpath()

        context.fill(fillPath, with: .color(color.opacity(0.10)))
        context.stroke(strokePath, with: .color(color), style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Quick Policy Switcher

private struct OverviewQuickPoliciesSection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkspaceUIState.self) private var uiState
    @EnvironmentObject private var preferences: AppPreferencesStore
    @Environment(\.micaAppLanguage) private var language

    let onOpenGroup: (String) -> Void
    let onViewAll: () -> Void

    var body: some View {
        let groups = Array(
            ProxiesStore.arrangedGroups(
                from: appModel.policyGroupCatalog,
                visibility: preferences.globalGroupVisibility
            )
            .filter { $0.selectable && !$0.options.isEmpty }
            .prefix(6)
        )

        if !groups.isEmpty {
            let scope = LiveCommandScope(
                controllerID: appModel.selectedRouterID,
                generation: appModel.controllerSessionPresentation.generation
            )
            let isSurge = appModel.selectedRouter.map { appModel.runtimeControllerKind(for: $0) == .surgeCompatible } ?? false
            let commandsEnabled = appModel.controllerSessionPresentation.state.allowsLiveCommands

            VStack(alignment: .leading, spacing: MicaTheme.Spacing.md) {
                HStack {
                    MicaSectionLabel(title: L("navigation.proxies", language: language))
                    Button(L("overview.topology_view_all", language: language), action: onViewAll)
                        .buttonStyle(.borderless)
                        .font(.callout)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 230, maximum: 360), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(groups) { group in
                        quickGroupCard(
                            group: group,
                            commandsEnabled: commandsEnabled,
                            isSurge: isSurge,
                            scope: scope
                        )
                    }
                }
            }
        }
    }

    private func quickGroupCard(
        group: ProxyGroupViewState,
        commandsEnabled: Bool,
        isSurge: Bool,
        scope: LiveCommandScope?
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: MicaTheme.Radius.card, style: .continuous)
        let delay = group.delays[group.selected] ?? group.optionDetails[group.selected]?.latestHistoryDelay

        return HStack(spacing: MicaTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    uiState.pendingProxyGroupID = group.id
                    onOpenGroup(group.id)
                } label: {
                    Text(verbatim: group.id)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(MicaTheme.textPrimary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                Text(verbatim: group.type)
                    .font(.caption2)
                    .foregroundStyle(MicaTheme.textTertiary)
            }

            Spacer(minLength: MicaTheme.Spacing.sm)

            Menu {
                ForEach(group.options, id: \.self) { option in
                    Button {
                        guard let scope else { return }
                        if isSurge {
                            appModel.selectSurgePolicy(option, in: group.id, scope: scope)
                        } else {
                            appModel.selectNode(option, in: group.id, scope: scope)
                        }
                    } label: {
                        HStack {
                            Text(verbatim: option)
                            if option == group.selected {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: group.selected.isEmpty ? "-" : group.selected)
                        .font(.callout)
                        .foregroundStyle(MicaTheme.textPrimary)
                        .lineLimit(1)
                    if let delay {
                        Text(verbatim: MicaFormatters.formatLatency(delay, language: language))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(MicaTheme.latencyColor(for: delay))
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .disabled(!commandsEnabled)
            .frame(maxWidth: 180, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MicaTheme.surface, in: shape)
        .overlay {
            shape.strokeBorder(MicaTheme.separator, lineWidth: 0.75)
        }
    }
}

// MARK: - Controller Summary Facts

private struct OverviewControllerFactsSection: View {
    @Environment(AppModel.self) private var appModel
    let language: AppLanguage

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MicaTheme.Radius.panel, style: .continuous)
        let config = appModel.controllerMetadata.config

        VStack(alignment: .leading, spacing: MicaTheme.Spacing.md) {
            MicaSectionLabel(title: L("controllers.controller", language: language))

            HStack(alignment: .top, spacing: MicaTheme.Spacing.xl) {
                VStack(alignment: .leading, spacing: 2) {
                    if let router = appModel.selectedRouter {
                        MicaKeyValueRow(
                            label: L("settings.controller_endpoint", language: language),
                            value: router.endpointURL,
                            monospaced: true
                        )
                    }
                    MicaKeyValueRow(
                        label: L("dashboard.tab_rules", language: language),
                        value: appModel.rulesCatalog.rules.count.formatted(),
                        monospaced: true
                    )
                    MicaKeyValueRow(
                        label: L("dashboard.tab_providers", language: language),
                        value: appModel.providersCatalog.providers.count.formatted(),
                        monospaced: true
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let tun = config.tunEnabled {
                        MicaKeyValueRow(
                            label: L("overview.config_tun", language: language),
                            value: tun ? L("overview.config_enabled", language: language) : L("overview.config_disabled", language: language)
                        )
                    }
                    if let mixed = config.mixedPort {
                        MicaKeyValueRow(
                            label: L("overview.config_mixed_port", language: language),
                            value: "\(mixed)",
                            monospaced: true
                        )
                    } else if let httpPort = config.port {
                        MicaKeyValueRow(
                            label: L("overview.config_http_port", language: language),
                            value: "\(httpPort)",
                            monospaced: true
                        )
                    }
                    if let logLevel = config.logLevel {
                        MicaKeyValueRow(
                            label: L("overview.config_log_level", language: language),
                            value: logLevel,
                            monospaced: true
                        )
                    }
                }
            }
        }
        .padding(MicaTheme.Spacing.lg)
        .background(MicaTheme.surface, in: shape)
        .overlay {
            shape.strokeBorder(MicaTheme.separator, lineWidth: 0.75)
        }
    }
}
