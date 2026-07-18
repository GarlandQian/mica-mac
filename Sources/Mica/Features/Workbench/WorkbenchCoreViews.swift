import MicaCore
import SwiftUI

struct WorkbenchCoreConfigView: View {
    var appModel: AppModel

    @Environment(\.micaAppLanguage) private var appLanguage

    var body: some View {
        Form {
            Section {
                LabeledContent(MicaStrings.localizedKey("dashboard.mode", language: appLanguage)) {
                    if appModel.dashboard.config.modeOptions.isEmpty {
                        Text(verbatim: appModel.dashboard.mode.nilIfEmpty ?? unavailableValue)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(
                            MicaStrings.localizedKey("dashboard.mode", language: appLanguage),
                            selection: Binding(
                                get: { modeSelection },
                                set: { newMode in appModel.setMode(newMode) }
                            )
                        ) {
                            ForEach(appModel.dashboard.config.modeOptions, id: \.self) { option in
                                Text(verbatim: MicaStrings.displayMode(option, language: appLanguage))
                                    .tag(option)
                            }
                        }
                        .labelsHidden()
                        .disabled(appModel.isBusy || !appModel.supportsUnifiedAction(modeChangeAction))
                        .accessibilityLabel(MicaStrings.localizedKey("routing.acc_mode_picker", language: appLanguage))
                    }
                }

                LabeledContent(MicaStrings.localizedKey("overview.config_mode_options", language: appLanguage)) {
                    Text(verbatim: modeOptions)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                MicaText("workbench.configuration")
            }

            if hasGeneralConfig {
                Section {
                    if let logLevel = appModel.dashboard.config.logLevel {
                        logLevelRow(logLevel)
                    }
                    if let allowLAN = appModel.dashboard.config.allowLan {
                        booleanConfigRow(
                            "overview.config_allow_lan",
                            value: allowLAN,
                            action: .setAllowLAN,
                            mutation: { ControllerConfigMutation.allowLAN($0) }
                        )
                    }
                    if let ipv6 = appModel.dashboard.config.ipv6 {
                        booleanConfigRow(
                            "overview.config_ipv6",
                            value: ipv6,
                            action: .setIPv6,
                            mutation: { ControllerConfigMutation.ipv6($0) }
                        )
                    }
                    if let tcpConcurrent = appModel.dashboard.config.tcpConcurrent {
                        booleanConfigRow(
                            "overview.config_tcp_concurrent",
                            value: tcpConcurrent,
                            action: .setTCPConcurrent,
                            mutation: { ControllerConfigMutation.tcpConcurrent($0) }
                        )
                    }
                    if let tunEnabled = appModel.dashboard.config.tunEnabled {
                        booleanConfigRow(
                            "overview.config_tun",
                            value: tunEnabled,
                            action: .setTUN,
                            mutation: { ControllerConfigMutation.tun($0) }
                        )
                    }
                } header: {
                    MicaText("overview.config_snapshot")
                }
            }

            if hasPorts {
                Section {
                    portRow(.http, value: appModel.dashboard.config.port)
                    portRow(.socks, value: appModel.dashboard.config.socksPort)
                    portRow(.redir, value: appModel.dashboard.config.redirPort)
                    portRow(.mixed, value: appModel.dashboard.config.mixedPort)
                } header: {
                    MicaText("settings.connection")
                }
            }

            if appModel.selectedRouter.map({
                appModel.runtimeControllerKind(for: $0) == .singBoxCompatible
            }) == true {
                WorkbenchSingBoxTailscaleSection(appModel: appModel)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(MicaStrings.localizedKey("workbench.configuration", language: appLanguage))
    }

    private func reportedRow(_ titleKey: String, value: String?) -> some View {
        LabeledContent(MicaStrings.localizedKey(titleKey, language: appLanguage)) {
            Text(verbatim: value?.nilIfEmpty ?? unavailableValue)
                .foregroundStyle(value == nil ? .secondary : .primary)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func logLevelRow(_ current: String) -> some View {
        if appModel.supportsUnifiedAction(.setLogLevel) {
            LabeledContent(MicaStrings.localizedKey("overview.config_log_level", language: appLanguage)) {
                HStack(spacing: 8) {
                    if appModel.updatingConfigFieldID == "log-level" {
                        ProgressView()
                    }
                    Picker(
                        MicaStrings.localizedKey("overview.config_log_level", language: appLanguage),
                        selection: Binding(
                            get: { current },
                            set: { value in
                                guard value != current else { return }
                                appModel.updateControllerConfig(.logLevel(value))
                            }
                        )
                    ) {
                        ForEach(logLevelOptions(current: current), id: \.self) { level in
                            Text(verbatim: level).tag(level)
                        }
                    }
                    .labelsHidden()
                    .disabled(configWriteDisabled)
                }
            }
        } else {
            reportedRow("overview.config_log_level", value: current)
        }
    }

    @ViewBuilder
    private func booleanConfigRow(
        _ titleKey: String,
        value: Bool,
        action: UnifiedControllerAction,
        mutation: @escaping (Bool) -> ControllerConfigMutation
    ) -> some View {
        if appModel.supportsUnifiedAction(action) {
            LabeledContent(MicaStrings.localizedKey(titleKey, language: appLanguage)) {
                HStack(spacing: 8) {
                    if appModel.updatingConfigFieldID == mutation(value).id {
                        ProgressView()
                    }
                    Toggle(
                        MicaStrings.localizedKey(titleKey, language: appLanguage),
                        isOn: Binding(
                            get: { value },
                            set: { appModel.updateControllerConfig(mutation($0)) }
                        )
                    )
                    .labelsHidden()
                    .disabled(configWriteDisabled)
                }
            }
        } else {
            reportedRow(titleKey, value: booleanLabel(value))
        }
    }

    @ViewBuilder
    private func portRow(_ port: ControllerConfigPort, value: Int?) -> some View {
        if let value {
            if appModel.supportsUnifiedAction(.setPort) {
                WorkbenchConfigPortRow(
                    titleKey: port.titleKey,
                    value: value,
                    disabled: configWriteDisabled,
                    isUpdating: appModel.updatingConfigFieldID == "port:\(port.rawValue)"
                ) { newValue in
                    appModel.updateControllerConfig(.port(port, newValue))
                }
            } else {
                reportedRow(port.titleKey, value: String(value))
            }
        }
    }

    private var modeOptions: String {
        let options = appModel.dashboard.config.modeOptions
        return options.isEmpty
            ? unavailableValue
            : options.map { MicaStrings.displayMode($0, language: appLanguage) }
                .joined(separator: " / ")
    }

    private var modeSelection: String {
        appModel.dashboard.config.modeOptions.first {
            DashboardSnapshot.displayMode($0) == appModel.dashboard.mode
                || $0.caseInsensitiveCompare(appModel.dashboard.mode) == .orderedSame
        } ?? appModel.dashboard.mode
    }

    private var modeChangeAction: UnifiedControllerAction {
        guard let router = appModel.selectedRouter else {
            return .changeMode
        }
        return appModel.modeChangeAction(for: router)
    }

    private var hasGeneralConfig: Bool {
        [
            appModel.dashboard.config.logLevel.map { _ in true },
            appModel.dashboard.config.allowLan.map { _ in true },
            appModel.dashboard.config.ipv6.map { _ in true },
            appModel.dashboard.config.tcpConcurrent.map { _ in true },
            appModel.dashboard.config.tunEnabled.map { _ in true },
        ].contains(true)
    }

    private var hasPorts: Bool {
        [
            appModel.dashboard.config.port,
            appModel.dashboard.config.socksPort,
            appModel.dashboard.config.redirPort,
            appModel.dashboard.config.mixedPort,
        ].contains { $0 != nil }
    }

    private var configWriteDisabled: Bool {
        appModel.isBusy || !appModel.canRefreshSelectedRouter
    }

    private func logLevelOptions(current: String) -> [String] {
        var levels = ["silent", "error", "warning", "info", "debug"]
        if !current.isEmpty, !levels.contains(current) {
            levels.insert(current, at: 0)
        }
        return levels
    }

    private func booleanLabel(_ value: Bool?) -> String? {
        guard let value else { return nil }
        return MicaStrings.localizedKey(
            value ? "overview.config_enabled" : "overview.config_disabled",
            language: appLanguage
        )
    }

    private var unavailableValue: String {
        MicaStrings.localizedKey("overview.config_not_reported", language: appLanguage)
    }
}

private struct WorkbenchConfigPortRow: View {
    let titleKey: String
    let value: Int
    let disabled: Bool
    let isUpdating: Bool
    let onCommit: (Int) -> Void

    @Environment(\.micaAppLanguage) private var appLanguage
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        titleKey: String,
        value: Int,
        disabled: Bool,
        isUpdating: Bool,
        onCommit: @escaping (Int) -> Void
    ) {
        self.titleKey = titleKey
        self.value = value
        self.disabled = disabled
        self.isUpdating = isUpdating
        self.onCommit = onCommit
        _text = State(initialValue: String(value))
    }

    var body: some View {
        LabeledContent(MicaStrings.localizedKey(titleKey, language: appLanguage)) {
            HStack(spacing: 6) {
                if isUpdating {
                    ProgressView()
                }

                TextField(
                    MicaStrings.localizedKey(titleKey, language: appLanguage),
                    text: $text
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
                .focused($isFocused)
                .onSubmit(commit)

                Button(action: commit) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .disabled(disabled || parsedValue == nil || parsedValue == value)
                .help(MicaStrings.localizedKey("action.apply_port", language: appLanguage))
                .accessibilityLabel(MicaStrings.localizedKey("action.apply_port", language: appLanguage))
            }
        }
        .onChange(of: value) { _, newValue in
            if !isFocused {
                text = String(newValue)
            }
        }
        .disabled(disabled)
    }

    private var parsedValue: Int? {
        guard let value = Int(text), (0...65_535).contains(value) else { return nil }
        return value
    }

    private func commit() {
        guard !disabled, let parsedValue, parsedValue != value else { return }
        onCommit(parsedValue)
    }
}

struct WorkbenchCoreActionsView: View {
    var appModel: AppModel

    @Environment(\.micaAppLanguage) private var appLanguage

    var body: some View {
        Form {
            Section {
                actionRow(.testConnection, titleKey: "action.test", detailKey: "dashboard.help_test_controller") {
                    appModel.testSelectedRouter()
                }
                actionRow(.refreshSnapshot, titleKey: "action.refresh", detailKey: "dashboard.help_refresh_controller") {
                    appModel.refreshSelectedRouter()
                }
            } header: {
                MicaText("settings.connection")
            }

            Section {
                actionRow(
                    .reloadConfiguration,
                    titleKey: "action.reload_configuration",
                    detailKey: "action.help_reload_configuration"
                ) {
                    appModel.performDiagnosticsRuntimeOperation("configuration-reload")
                }
            } header: {
                MicaText("workbench.configuration")
            }

            Section {
                actionRow(.reloadRules, titleKey: "action.reload_rules", detailKey: "dashboard.help_reload_rules") {
                    appModel.reloadRules()
                }
                actionRow(.reloadProviders, titleKey: "action.reload_providers", detailKey: "dashboard.help_reload_providers") {
                    appModel.reloadProviders()
                }
                actionRow(
                    .updateGeoData,
                    titleKey: "action.update_geo_data",
                    detailKey: "action.help_update_geo_data"
                ) {
                    appModel.performDiagnosticsRuntimeOperation("geo-resources")
                }
            } header: {
                MicaText("diagnostics.operation_external_resources")
            }

            Section {
                actionRow(.dnsFlush, titleKey: "diagnostics.operation_dns_flush", detailKey: "diagnostics.operation_dns_flush_detail") {
                    appModel.performDiagnosticsRuntimeOperation("dns-flush")
                }
                actionRow(.flushFakeIP, titleKey: "action.fakeip_flush", detailKey: "diagnostics.operation_cache_flush_detail") {
                    appModel.performDiagnosticsRuntimeOperation("cache-flush")
                }
            } header: {
                MicaText("diagnostics.operation_cache_flush")
            }

            if appModel.supportsUnifiedAction(.reloadProfile) {
                Section {
                    actionRow(
                        .reloadProfile,
                        titleKey: "action.surge_reload_profile",
                        detailKey: "action.help_surge_reload_profile"
                    ) {
                        appModel.reloadSurgeProfile()
                    }
                } header: {
                    MicaText("action.remote_profile")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(MicaStrings.localizedKey("workbench.actions", language: appLanguage))
    }

    private func actionRow(
        _ action: UnifiedControllerAction,
        titleKey: String,
        detailKey: String,
        perform: @escaping () -> Void
    ) -> some View {
        let isSupported = appModel.selectedRouter != nil && appModel.supportsUnifiedAction(action)

        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                MicaText(titleKey)
                    .fontWeight(.medium)
                MicaText(detailKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !isSupported {
                    Text(appModel.selectedRouter == nil
                        ? MicaStrings.localizedKey("settings.none", language: appLanguage)
                        : appModel.unifiedUnavailableReason(for: action))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            Button(MicaStrings.localizedKey(titleKey, language: appLanguage), action: perform)
                .buttonStyle(.bordered)
                .disabled(!isSupported || !isCommandEnabled(action))
                .accessibilityHint(MicaStrings.localizedKey(detailKey, language: appLanguage))
        }
    }

    private func isCommandEnabled(_ action: UnifiedControllerAction) -> Bool {
        switch action {
        case .testConnection:
            appModel.canTestSelectedRouter
        case .refreshSnapshot, .reloadRules, .setRuleDisabled, .reloadProviders, .updateProvider,
             .healthCheckProvider, .reloadConfiguration, .updateGeoData:
            appModel.canRefreshSelectedRouter
        case .switchPolicy, .clearFixedSelection, .testLatency, .changeMode, .closeConnection,
             .closeAllConnections, .dnsFlush, .flushFakeIP, .reloadProfile, .setLogLevel,
             .setAllowLAN, .setIPv6, .setTCPConcurrent, .setTUN, .setPort, .setOutboundMode,
             .selectSurgePolicy, .testSurgePolicy, .killActiveRequest,
             .copyDiagnostics:
            !appModel.isBusy
        }
    }
}
