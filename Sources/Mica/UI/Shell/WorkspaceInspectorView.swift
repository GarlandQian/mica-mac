import AppKit
import MicaCore
import SwiftUI

struct WorkspaceInspectorView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkspaceUIState.self) private var uiState
    @Environment(\.micaAppLanguage) private var language

    @Binding var destination: WorkbenchDestination

    var body: some View {
        VStack(spacing: 0) {
            inspectorHeader
            MicaHairlineDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.lg) {
                    inspectorBody
                }
                .padding(MicaTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(MicaTheme.canvas)
    }

    private var inspectorHeader: some View {
        HStack {
            Text(verbatim: headerTitle)
                .font(.headline)
                .foregroundStyle(MicaTheme.textPrimary)
                .lineLimit(1)

            Spacer()

            Button {
                uiState.dismissInspector()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MicaTheme.textSecondary)
            }
            .buttonStyle(.borderless)
            .help(L("action.close", language: language))
        }
        .padding(.horizontal, MicaTheme.Spacing.lg)
        .padding(.vertical, MicaTheme.Spacing.md)
    }

    private var headerTitle: String {
        switch uiState.inspectorSelection {
        case .none:
            L("workbench.inspector_empty_title", language: language)
        case .proxyNode(_, let nodeName):
            nodeName
        case .connection:
            L("traffic.detail_connection", language: language)
        case .rule:
            L("traffic.detail_rule", language: language)
        case .provider:
            L("dashboard.tab_providers", language: language)
        case .log:
            L("dashboard.tab_logs", language: language)
        case .controller:
            L("controllers.controller", language: language)
        }
    }

    @ViewBuilder
    private var inspectorBody: some View {
        switch uiState.inspectorSelection {
        case .none:
            MicaEmptyStateView(
                systemImage: "sidebar.trailing",
                title: L("workbench.inspector_empty_title", language: language),
                message: L("workbench.inspector_empty_message", language: language)
            )
        case .proxyNode(let groupID, let nodeName):
            proxyNodeDetails(groupID: groupID, nodeName: nodeName)
        case .connection(let id):
            connectionDetails(id: id)
        case .rule(let id):
            ruleDetails(id: id)
        case .provider(let id):
            providerDetails(id: id)
        case .log(let id):
            logDetails(id: id)
        case .controller(let id):
            controllerDetails(id: id)
        }
    }

    // MARK: - Proxy Node

    @ViewBuilder
    private func proxyNodeDetails(groupID: String, nodeName: String) -> some View {
        if let group = appModel.policyGroupCatalog.groups.first(where: { $0.id == groupID }) {
            let detail = group.detail(for: nodeName)
            let delay = group.delays[nodeName] ?? detail?.latestHistoryDelay
            let scope = currentCommandScope
            let isSurge = appModel.selectedRouter.map { appModel.runtimeControllerKind(for: $0) == .surgeCompatible } ?? false

            HStack(spacing: MicaTheme.Spacing.sm) {
                if group.selectable, group.selected != nodeName, appModel.controllerSessionPresentation.state.allowsLiveCommands {
                    Button(L("routing.use_node \(nodeName)", language: language)) {
                        guard let scope else { return }
                        if isSurge {
                            appModel.selectSurgePolicy(nodeName, in: groupID, scope: scope)
                        } else {
                            appModel.selectNode(nodeName, in: groupID, scope: scope)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                if !isSurge, appModel.controllerSessionPresentation.state.allowsLiveCommands {
                    Button(L("action.test_delay", language: language)) {
                        guard let scope else { return }
                        appModel.measureDelay(for: nodeName, in: groupID, scope: scope)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                MicaKeyValueRow(label: L("routing.group_catalog", language: language), value: groupID)
                MicaKeyValueRow(label: L("dashboard.col_type", language: language), value: detail?.type ?? "-")
                MicaKeyValueRow(
                    label: L("diagnostics.capability_state", language: language),
                    value: MicaFormatters.formatLatency(delay, alive: detail?.alive, language: language),
                    monospaced: true
                )
                if let provider = detail?.providerName, !provider.isEmpty {
                    MicaKeyValueRow(label: L("dashboard.tab_providers", language: language), value: provider)
                }
                if let iface = detail?.interfaceName, !iface.isEmpty {
                    MicaKeyValueRow(label: "Interface", value: iface, monospaced: true)
                }
                if let testURL = detail?.testURL, !testURL.isEmpty {
                    MicaKeyValueRow(label: "Test URL", value: testURL, monospaced: true)
                }
                if detail?.transportNames.isEmpty == false {
                    MicaKeyValueRow(label: "Transport", value: detail?.transportNames.joined(separator: ", ") ?? "-")
                }
            }

            if let history = detail?.history, !history.isEmpty {
                MicaHairlineDivider()
                Text(verbatim: "Latency History")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MicaTheme.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(history.suffix(8).reversed().enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(verbatim: MicaFormatters.formatISO8601Short(item.time) ?? "-")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(MicaTheme.textTertiary)
                            Spacer()
                            Text(verbatim: MicaFormatters.formatLatency(item.delay, language: language))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(MicaTheme.latencyColor(for: item.delay))
                        }
                    }
                }
            }
        } else {
            emptyFallback
        }
    }

    // MARK: - Connection

    @ViewBuilder
    private func connectionDetails(id: String) -> some View {
        let activeMatch = appModel.connectionsCatalog.connections.first { $0.id == id }
        let closedMatch = appModel.dashboardSessionControls.closedConnectionRecords.first { $0.id == id }?.snapshot
        if let conn = activeMatch ?? closedMatch {
            let isActive = activeMatch != nil
            let meta = conn.metadata

            if isActive, appModel.controllerSessionPresentation.state.allowsLiveCommands {
                Button(L("action.close_connection", language: language), role: .destructive) {
                    appModel.closeConnection(conn)
                }
                .disabled(appModel.closingConnectionID == conn.id)
            }

            VStack(alignment: .leading, spacing: 2) {
                MicaKeyValueRow(label: L("traffic.connection_host", language: language), value: meta?.host ?? meta?.destinationIP ?? conn.id, monospaced: true)
                MicaKeyValueRow(label: L("traffic.connection_process", language: language), value: meta?.process ?? "-")
                if let path = meta?.processPath, !path.isEmpty {
                    MicaKeyValueRow(label: L("traffic.connection_process_path", language: language), value: path, monospaced: true)
                }
                MicaKeyValueRow(label: L("dashboard.tab_rules", language: language), value: [conn.rule, conn.rulePayload].compactMap { $0?.nilIfEmpty }.joined(separator: " / "))
                MicaKeyValueRow(label: L("dashboard.col_chain", language: language), value: conn.chains?.reversed().joined(separator: " → ") ?? "-")
                MicaKeyValueRow(label: "Source", value: [meta?.sourceIP, meta?.sourcePort].compactMap { $0?.nilIfEmpty }.joined(separator: ":"), monospaced: true)
                MicaKeyValueRow(label: "Destination", value: [meta?.destinationIP, meta?.destinationPort].compactMap { $0?.nilIfEmpty }.joined(separator: ":"), monospaced: true)
                MicaKeyValueRow(label: L("dashboard.col_download", language: language), value: MicaFormatters.formatBytes(conn.download ?? 0), monospaced: true)
                MicaKeyValueRow(label: L("dashboard.col_upload", language: language), value: MicaFormatters.formatBytes(conn.upload ?? 0), monospaced: true)
                MicaKeyValueRow(label: L("dashboard.col_id", language: language), value: conn.id, monospaced: true)
            }
        } else {
            emptyFallback
        }
    }

    // MARK: - Rule

    @ViewBuilder
    private func ruleDetails(id: String) -> some View {
        if let rule = appModel.rulesCatalog.rules.first(where: { $0.id == id }) {
            let scope = currentCommandScope

            VStack(alignment: .leading, spacing: 2) {
                MicaKeyValueRow(label: L("dashboard.col_type", language: language), value: MicaStrings.displayRuleType(rule.type, language: language))
                MicaKeyValueRow(label: L("dashboard.col_payload", language: language), value: rule.payload.isEmpty ? "-" : rule.payload, monospaced: true)
                MicaKeyValueRow(label: L("dashboard.col_proxy", language: language), value: MicaStrings.displayRuleProxyTarget(rule.proxy, language: language))
                if let size = rule.size {
                    MicaKeyValueRow(label: L("dashboard.col_size", language: language), value: "\(size)", monospaced: true)
                }
                if let hitCount = rule.hitCount {
                    MicaKeyValueRow(label: "Hits", value: "\(hitCount)", monospaced: true)
                }
            }

            if rule.hasMutableExtra, rule.index != nil, appModel.supportsUnifiedAction(.setRuleDisabled) {
                Toggle(
                    L("action.disable_rule", language: language),
                    isOn: Binding(
                        get: { rule.disabled ?? false },
                        set: { disabled in
                            guard let scope else { return }
                            appModel.setRuleDisabled(rule, disabled: disabled, scope: scope)
                        }
                    )
                )
                .disabled(appModel.updatingRuleID == rule.id || !appModel.controllerSessionPresentation.state.allowsLiveCommands)
            }

            if appModel.policyGroupCatalog.groups.contains(where: { $0.id == rule.proxy }) {
                Button(L("navigation.proxies", language: language) + ": " + rule.proxy) {
                    uiState.pendingProxyGroupID = rule.proxy
                    destination = .proxies
                }
            }
        } else {
            emptyFallback
        }
    }

    // MARK: - Provider

    @ViewBuilder
    private func providerDetails(id: String) -> some View {
        if let provider = appModel.providersCatalog.providers.first(where: { $0.id == id }) {
            let scope = currentCommandScope

            HStack(spacing: MicaTheme.Spacing.sm) {
                if provider.updatable {
                    Button(L("action.provider_update", language: language)) {
                        guard let scope else { return }
                        appModel.updateProxyProvider(provider, scope: scope)
                    }
                    .disabled(appModel.hasProviderOperationInFlight || !appModel.controllerSessionPresentation.state.allowsLiveCommands)
                }
                if provider.supportsHealthCheck {
                    Button(L("action.provider_health_check", language: language)) {
                        guard let scope else { return }
                        appModel.healthCheckProxyProvider(provider, scope: scope)
                    }
                    .disabled(appModel.hasProviderOperationInFlight || !appModel.controllerSessionPresentation.state.allowsLiveCommands)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                MicaKeyValueRow(label: L("editor.name", language: language), value: provider.name)
                MicaKeyValueRow(label: L("traffic.provider_kind", language: language), value: provider.type)
                if let vehicle = provider.vehicleType {
                    MicaKeyValueRow(label: L("dashboard.col_vehicle", language: language), value: vehicle)
                }
                if let behavior = provider.behavior {
                    MicaKeyValueRow(label: L("traffic.provider_behavior", language: language), value: behavior)
                }
                MicaKeyValueRow(label: "Count", value: "\(provider.itemCount)", monospaced: true)
                if let updated = MicaFormatters.formatISO8601Short(provider.updatedAt) {
                    MicaKeyValueRow(label: L("traffic.updated_at", language: language), value: updated, monospaced: true)
                }
                if let testURL = provider.testURL {
                    MicaKeyValueRow(label: "Test URL", value: testURL, monospaced: true)
                }
            }
        } else {
            emptyFallback
        }
    }

    // MARK: - Log

    @ViewBuilder
    private func logDetails(id: String) -> some View {
        if let entry = appModel.logsCatalog.entries.first(where: { $0.id == id }) {
            let level = (entry.message.level ?? entry.message.type).uppercased()
            let payload = entry.message.message ?? entry.message.payload

            Button(L("action.copy_full_log", language: language)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(payload, forType: .string)
            }

            VStack(alignment: .leading, spacing: 2) {
                MicaKeyValueRow(label: L("traffic.log_time", language: language), value: MicaFormatters.formatDateTime(entry.receivedAt), monospaced: true)
                MicaKeyValueRow(label: L("traffic.log_level", language: language), value: level, monospaced: true)
            }

            Text(verbatim: payload)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(MicaTheme.textPrimary)
                .textSelection(.enabled)
                .padding(MicaTheme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MicaTheme.surface, in: RoundedRectangle(cornerRadius: MicaTheme.Radius.card, style: .continuous))
        } else {
            emptyFallback
        }
    }

    // MARK: - Controller

    @ViewBuilder
    private func controllerDetails(id: RouterProfile.ID) -> some View {
        if let profile = appModel.routers.first(where: { $0.id == id }) {
            let adapter = appModel.controllerAdapter(for: profile)
            let isSelected = appModel.selectedRouterID == profile.id

            HStack(spacing: MicaTheme.Spacing.sm) {
                if !isSelected {
                    Button(L("controllers.use", language: language)) {
                        appModel.selectRouter(profile)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(L("action.edit_router", language: language)) {
                    uiState.editingController = ControllerEditorSheetState(
                        titleKey: "editor.edit_router",
                        draft: appModel.draft(for: profile)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                MicaKeyValueRow(label: L("editor.name", language: language), value: profile.displayName)
                MicaKeyValueRow(label: L("settings.controller_endpoint", language: language), value: profile.endpointURL, monospaced: true)
                MicaKeyValueRow(label: L("editor.controller_type", language: language), value: adapter.detectedKind.micaLabel(language: language))
                MicaKeyValueRow(label: L("editor.hs_tls", language: language), value: profile.tlsPolicy == .allowSelfSigned ? L("editor.tls_self_signed_short", language: language) : L("editor.tls_system_short", language: language))
            }
        } else {
            emptyFallback
        }
    }

    private var emptyFallback: some View {
        MicaEmptyStateView(
            systemImage: "sidebar.trailing",
            title: L("workbench.inspector_empty_title", language: language)
        )
    }

    private var currentCommandScope: LiveCommandScope? {
        LiveCommandScope(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
    }
}
