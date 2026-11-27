import MicaCore
import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkspaceUIState.self) private var uiState
    @Environment(\.micaAppLanguage) private var language

    @Binding var searchText: String
    @State private var rulesStore = RulesStore()
    @State private var selectedRuleID: String?
    @State private var selectedProviderID: String?

    var body: some View {
        let _ = rulesStore.sync(rules: appModel.rulesCatalog.rules)

        VStack(spacing: 0) {
            headerBar
            MicaHairlineDivider()

            switch uiState.activeRuleSection {
            case .rules:
                rulesContent
            case .providers:
                providersContent
            }
        }
        .background(MicaTheme.canvas)
        .onAppear {
            rulesStore.searchQuery = searchText
        }
        .onChange(of: searchText) { _, newValue in
            rulesStore.searchQuery = newValue
        }
        .onChange(of: selectedRuleID) { _, id in
            if let id {
                uiState.selectInspector(.rule(id: id))
            } else if case .rule = uiState.inspectorSelection {
                uiState.dismissInspector()
            }
        }
        .onChange(of: selectedProviderID) { _, id in
            if let id {
                uiState.selectInspector(.provider(id: id))
            } else if case .provider = uiState.inspectorSelection {
                uiState.dismissInspector()
            }
        }
    }

    private var headerBar: some View {
        @Bindable var uiState = uiState
        let countText = uiState.activeRuleSection == .rules
            ? "\(rulesStore.rows.count) / \(rulesStore.totalRuleCount)"
            : "\(filteredProviders.count)"

        return HStack(spacing: MicaTheme.Spacing.md) {
            Picker("", selection: $uiState.activeRuleSection) {
                ForEach(RulesSubtab.allCases) { tab in
                    Text(L(tab.titleKey, language: language)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 210)

            Text(verbatim: countText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(MicaTheme.textSecondary)

            Spacer(minLength: MicaTheme.Spacing.sm)

            if uiState.activeRuleSection == .rules {
                if !rulesStore.availableTypes.isEmpty {
                    Picker(L("dashboard.col_type", language: language), selection: $rulesStore.selectedType) {
                        Text(L("routing.health_filter_all", language: language)).tag("")
                        ForEach(rulesStore.availableTypes, id: \.self) { type in
                            Text(verbatim: MicaStrings.displayRuleType(type, language: language)).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 160)
                }

                Button {
                    appModel.reloadRules()
                } label: {
                    if appModel.reloadingRules {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(L("action.reload_rules", language: language), systemImage: "arrow.clockwise")
                    }
                }
                .disabled(appModel.reloadingRules || !appModel.controllerSessionPresentation.state.allowsLiveCommands || !appModel.supportsUnifiedAction(.reloadRules))
            } else {
                Button {
                    appModel.updateAllProviders()
                } label: {
                    if appModel.providerUpdateAllProgress?.isRunning == true {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(L("action.provider_update_all", language: language), systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(
                    appModel.providersCatalog.providers.filter(\.updatable).isEmpty
                        || appModel.hasProviderOperationInFlight
                        || !appModel.controllerSessionPresentation.state.allowsLiveCommands
                )

                Button {
                    appModel.reloadProviders()
                } label: {
                    if appModel.reloadingProviders {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(L("action.refresh", language: language), systemImage: "arrow.clockwise")
                    }
                }
                .disabled(appModel.hasProviderOperationInFlight || !appModel.controllerSessionPresentation.state.allowsLiveCommands)
            }
        }
        .padding(.horizontal, MicaTheme.Spacing.lg)
        .padding(.vertical, MicaTheme.Spacing.sm)
    }

    @ViewBuilder
    private var rulesContent: some View {
        if rulesStore.totalRuleCount == 0 {
            MicaEmptyStateView(
                systemImage: "arrow.triangle.branch",
                title: L("dashboard.no_rules_snapshot", language: language),
                actionTitle: appModel.supportsUnifiedAction(.reloadRules) ? L("action.reload_rules", language: language) : nil,
                action: appModel.supportsUnifiedAction(.reloadRules) ? { appModel.reloadRules() } : nil
            )
        } else if rulesStore.rows.isEmpty {
            MicaEmptyStateView(
                systemImage: "magnifyingglass",
                title: L("dashboard.no_matching_rules", language: language),
                actionTitle: L("action.clear_search", language: language),
                action: {
                    rulesStore.selectedType = ""
                    searchText = ""
                }
            )
        } else {
            Table(rulesStore.rows, selection: $selectedRuleID) {
                TableColumn(L("dashboard.col_type", language: language)) { row in
                    Text(verbatim: MicaStrings.displayRuleType(row.type, language: language))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(row.isDisabled ? MicaTheme.textTertiary : MicaTheme.textSecondary)
                }
                .width(min: 110, ideal: 140, max: 200)

                TableColumn(L("dashboard.col_payload", language: language)) { row in
                    Text(verbatim: row.payload.isEmpty ? "-" : row.payload)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(row.isDisabled ? MicaTheme.textTertiary : MicaTheme.textPrimary)
                        .lineLimit(1)
                }

                TableColumn(L("dashboard.col_proxy", language: language)) { row in
                    Text(verbatim: MicaStrings.displayRuleProxyTarget(row.proxy, language: language))
                        .font(.callout)
                        .foregroundStyle(row.isDisabled ? MicaTheme.textTertiary : MicaTheme.accent)
                        .lineLimit(1)
                }
                .width(min: 110, ideal: 160, max: 240)
            }
        }
    }

    @ViewBuilder
    private var providersContent: some View {
        let providers = filteredProviders
        let scope = LiveCommandScope(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
        let commandsEnabled = appModel.controllerSessionPresentation.state.allowsLiveCommands

        if appModel.providersCatalog.providers.isEmpty {
            MicaEmptyStateView(
                systemImage: "shippingbox",
                title: L("dashboard.no_providers_snapshot", language: language),
                message: L("traffic.sources_empty_message", language: language)
            )
        } else if providers.isEmpty {
            MicaEmptyStateView(
                systemImage: "magnifyingglass",
                title: L("dashboard.no_matching_sources", language: language),
                actionTitle: L("action.clear_search", language: language),
                action: { searchText = "" }
            )
        } else {
            List(providers, selection: $selectedProviderID) { provider in
                ProviderListRow(
                    provider: provider,
                    isUpdating: appModel.updatingProviderName == provider.name,
                    isChecking: appModel.checkingProviderName == provider.name,
                    commandsEnabled: commandsEnabled && !appModel.hasProviderOperationInFlight,
                    language: language,
                    onUpdate: {
                        guard let scope else { return }
                        appModel.updateProxyProvider(provider, scope: scope)
                    },
                    onHealthCheck: {
                        guard let scope else { return }
                        appModel.healthCheckProxyProvider(provider, scope: scope)
                    }
                )
                .tag(provider.id)
            }
            .listStyle(.inset)
        }
    }

    private var filteredProviders: [ProxyProviderViewState] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return appModel.providersCatalog.providers
        }
        return appModel.providersCatalog.providers.filter { provider in
            provider.name.lowercased().contains(query)
                || provider.type.lowercased().contains(query)
                || (provider.vehicleType?.lowercased().contains(query) ?? false)
        }
    }
}

private struct ProviderListRow: View {
    let provider: ProxyProviderViewState
    let isUpdating: Bool
    let isChecking: Bool
    let commandsEnabled: Bool
    let language: AppLanguage
    let onUpdate: () -> Void
    let onHealthCheck: () -> Void

    var body: some View {
        HStack(spacing: MicaTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: MicaTheme.Spacing.sm) {
                    Text(verbatim: provider.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(MicaTheme.textPrimary)

                    Text(verbatim: provider.kind == .rule ? L("dashboard.tab_rules", language: language) : L("navigation.proxies", language: language))
                        .font(.caption2)
                        .foregroundStyle(MicaTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(MicaTheme.subtleFill, in: Capsule())

                    if let vehicle = provider.vehicleType, !vehicle.isEmpty {
                        Text(verbatim: vehicle)
                            .font(.caption2)
                            .foregroundStyle(MicaTheme.textTertiary)
                    }
                }

                HStack(spacing: MicaTheme.Spacing.md) {
                    Text(verbatim: "\(provider.itemCount)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(MicaTheme.textSecondary)
                    if let updated = MicaFormatters.formatISO8601Short(provider.updatedAt) {
                        Text(verbatim: updated)
                            .font(.caption)
                            .foregroundStyle(MicaTheme.textTertiary)
                    }
                }
            }

            Spacer(minLength: MicaTheme.Spacing.sm)

            if provider.supportsHealthCheck {
                Button(action: onHealthCheck) {
                    if isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "waveform.path.ecg")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(!commandsEnabled)
                .help(L("action.provider_health_check", language: language))
            }

            if provider.updatable {
                Button(action: onUpdate) {
                    if isUpdating {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(!commandsEnabled)
                .help(L("action.provider_update", language: language))
            }
        }
        .padding(.vertical, 4)
    }
}
