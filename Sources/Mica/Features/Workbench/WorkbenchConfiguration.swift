import Foundation
import MicaCore
import SwiftUI

// MARK: - Configuration

struct WorkbenchConfigurationView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    var body: some View {
        WorkbenchPageScaffold {
            commandBar
        } content: {
            configurationContent
        }
    }

    private var commandBar: some View {
        WorkbenchCommandBar {
            WorkbenchControllerContextHeader(
                symbolName: appModel.selectedRouter?.controllerKind.editorSymbol ?? "server.rack",
                name: appModel.selectedRouter?.displayName,
                detail: appModel.selectedRouter?.endpointURL
            )
        } commands: {
            // A field count says nothing a reader can act on; failures surface
            // as the stale notice above the form instead.
            WorkbenchIconCommand(
                titleKey: "action.refresh",
                systemImage: "arrow.clockwise",
                isEnabled: appModel.canRefreshSelectedRouter,
                action: refreshIfAvailable
            )
        }
    }

    @ViewBuilder
    private var configurationContent: some View {
        if appModel.selectedRouter == nil {
            WorkbenchStateView(
                kind: .noController,
                titleKey: "dashboard.connect_router",
                detailKey: "configuration.no_controller_detail"
            )
        } else if (appModel.isRefreshingDashboard
                    || appModel.controllerSessionPresentation.state == .connecting),
                  !hasConfigurationPresentation {
            WorkbenchStateView(
                kind: .loading,
                titleKey: "configuration.loading_title",
                detailKey: "configuration.loading_detail"
            )
        } else if (configStatus.isFailure || sessionFailureDetail != nil),
                  !hasConfigurationPresentation {
            WorkbenchStateView(
                kind: .failed,
                titleKey: "configuration.failed_title",
                detailKey: "configuration.failed_detail",
                message: configStatus.isFailure
                    ? configStatus.detail(language: language)
                    : sessionFailureDetail,
                actionTitleKey: "action.retry",
                isActionEnabled: appModel.canRefreshSelectedRouter,
                action: refreshIfAvailable
            )
        } else if (!appModel.selectedUnifiedCapabilities.snapshot
                    || !hasSupportedConfigurationCapability),
                  !hasConfigurationPresentation {
            WorkbenchStateView(
                kind: .unsupported,
                titleKey: "configuration.unsupported_title",
                detailKey: "configuration.unsupported_detail"
            )
        } else if !hasConfigurationPresentation {
            WorkbenchStateView(
                kind: .empty,
                titleKey: "configuration.empty_title",
                detailKey: "configuration.empty_detail",
                actionTitleKey: "action.refresh",
                isActionEnabled: appModel.canRefreshSelectedRouter,
                action: refreshIfAvailable
            )
        } else {
            VStack(spacing: 0) {
                if configStatus.isFailure {
                    WorkbenchStaleNotice(message: configStatus.detail(language: language))
                }

                WorkbenchManagementFormCanvas {
                    if hasModePresentation {
                        modeSection
                    }

                    if hasGeneralPresentation {
                        generalSection
                    }

                    if !reportedPorts.isEmpty {
                        portsSection
                    }

                    if hasTailscalePresentation {
                        WorkbenchSingBoxTailscaleSection()
                    }
                }
            }
        }
    }

    private func refreshIfAvailable() {
        guard appModel.canRefreshSelectedRouter else { return }
        appModel.refreshSelectedRouter()
    }

    private var modeSection: some View {
        Section {
            configurationRow(
                "overview.config_outbound_mode",
                isBusy: appModel.changingMode || appModel.changingSurgeOutbound
            ) {
                if !modeOptions.isEmpty {
                    Picker(
                        MicaStrings.localizedKey("overview.config_outbound_mode", language: language),
                        selection: modeBinding
                    ) {
                        ForEach(modeOptions, id: \.self) { mode in
                            Text(verbatim: MicaStrings.displayMode(mode, language: language))
                                .tag(mode)
                        }
                    }
                    // A few modes read best side by side; longer lists stay a menu.
                    .modifier(WorkbenchChoicePickerStyle(isCompact: modeOptions.count <= 4))
                    .disabled(configWriteDisabled)
                } else {
                    WorkbenchFormValue(
                        value: reported(reportedMode),
                        placeholder: reportedMode == nil
                    )
                }
            }

        } header: {
            Label(
                MicaStrings.localizedKey("configuration.mode_section", language: language),
                systemImage: "arrow.triangle.branch"
            )
        }
    }

    private var generalSection: some View {
        Section {
            if let logLevel = appModel.controllerMetadata.config.logLevel,
               appModel.supportsUnifiedAction(.setLogLevel) {
                logLevelRow(logLevel)
            }
            if let value = appModel.controllerMetadata.config.allowLan,
               appModel.supportsUnifiedAction(.setAllowLAN) {
                booleanRow(
                    "overview.config_allow_lan",
                    value: value,
                    mutation: ControllerConfigMutation.allowLAN
                )
            }
            if let value = appModel.controllerMetadata.config.ipv6,
               appModel.supportsUnifiedAction(.setIPv6) {
                booleanRow(
                    "overview.config_ipv6",
                    value: value,
                    mutation: ControllerConfigMutation.ipv6
                )
            }
            if let value = appModel.controllerMetadata.config.tcpConcurrent,
               appModel.supportsUnifiedAction(.setTCPConcurrent) {
                booleanRow(
                    "overview.config_tcp_concurrent",
                    value: value,
                    mutation: ControllerConfigMutation.tcpConcurrent
                )
            }
            if let value = appModel.controllerMetadata.config.tunEnabled,
               appModel.supportsUnifiedAction(.setTUN) {
                booleanRow(
                    "overview.config_tun",
                    value: value,
                    mutation: ControllerConfigMutation.tun
                )
            }
        } header: {
            Label(
                MicaStrings.localizedKey("overview.config_snapshot", language: language),
                systemImage: "switch.2"
            )
        }
    }

    private var portsSection: some View {
        Section {
            let controllerID = appModel.selectedRouterID
            let generation = appModel.controllerSessionPresentation.generation
            let commandScope = LiveCommandScope(
                controllerID: controllerID,
                generation: generation
            )
            ForEach(
                Array(reportedPorts.enumerated()),
                id: \.element.0.id
            ) { _, item in
                configurationRow(
                    item.0.titleKey,
                    isBusy: appModel.updatingConfigFieldID == "port:\(item.0.rawValue)"
                ) {
                    WorkbenchPortField(
                        titleKey: item.0.titleKey,
                        value: item.1,
                        disabled: configWriteDisabled
                    ) { next in
                        guard let commandScope else { return }
                        appModel.updateControllerConfig(
                            .port(item.0, next),
                            scope: commandScope
                        )
                    }
                    .id("\(controllerID?.uuidString ?? "none"):\(generation.uuidString):\(item.0.rawValue)")
                }
            }
        } header: {
            Label(
                MicaStrings.localizedKey("settings.connection", language: language),
                systemImage: "network"
            )
        }
    }

    private func logLevelRow(_ current: String) -> some View {
        let commandScope = LiveCommandScope(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
        let options = logLevelOptions(current: current)
        let canonical = options.first {
            $0.caseInsensitiveCompare(current) == .orderedSame
        } ?? current
        return configurationRow(
            "overview.config_log_level",
            isBusy: appModel.updatingConfigFieldID == "log-level"
        ) {
            Picker(
                MicaStrings.localizedKey("overview.config_log_level", language: language),
                selection: Binding(
                    get: { canonical },
                    set: { next in
                        guard next.caseInsensitiveCompare(current) != .orderedSame,
                              let commandScope else { return }
                        appModel.updateControllerConfig(
                            .logLevel(next),
                            scope: commandScope
                        )
                    }
                )
            ) {
                ForEach(options, id: \.self) { level in
                    Text(verbatim: logLevelLabel(level)).tag(level)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(configWriteDisabled)
        }
    }

    private func booleanRow(
        _ titleKey: String,
        value: Bool,
        mutation: @escaping (Bool) -> ControllerConfigMutation
    ) -> some View {
        let commandScope = LiveCommandScope(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
        return configurationRow(
            titleKey,
            isBusy: appModel.updatingConfigFieldID == mutation(value).id
        ) {
            Toggle(
                MicaStrings.localizedKey(titleKey, language: language),
                isOn: Binding(
                    get: { value },
                    set: { next in
                        guard next != value, let commandScope else { return }
                        appModel.updateControllerConfig(
                            mutation(next),
                            scope: commandScope
                        )
                    }
                )
            )
            .disabled(configWriteDisabled)
        }
    }

    private func configurationRow<Control: View>(
        _ titleKey: String,
        isBusy: Bool = false,
        @ViewBuilder control: () -> Control
    ) -> some View {
        WorkbenchFormRow(titleKey, isBusy: isBusy) {
            control()
        }
    }

    private var modeOptions: [String] {
        var seen = Set<String>()
        var options = appModel.controllerMetadata.config.modeOptions.filter {
            guard let value = $0.managementNonEmpty else { return false }
            return seen.insert(normalizedMode(value)).inserted
        }

        if let reportedMode,
           !options.contains(where: { modesMatch($0, reportedMode) }) {
            options.insert(reportedMode, at: 0)
        }
        return options
    }

    private var modeBinding: Binding<String> {
        let commandScope = LiveCommandScope(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
        return Binding(
            get: { modeSelection },
            set: { next in
                guard !modesMatch(next, appModel.controllerMetadata.mode),
                      let commandScope else { return }
                appModel.setMode(next, scope: commandScope)
            }
        )
    }

    private var modeSelection: String {
        modeOptions.first { modesMatch($0, appModel.controllerMetadata.mode) }
            ?? appModel.controllerMetadata.mode
    }

    private var modeAction: UnifiedControllerAction {
        appModel.selectedRouter.map(appModel.modeChangeAction(for:)) ?? .changeMode
    }

    private var reportedPorts: [(ControllerConfigPort, Int)] {
        guard appModel.supportsUnifiedAction(.setPort) else {
            return []
        }

        let ports: [(ControllerConfigPort, Int?)] = [
            (.http, appModel.controllerMetadata.config.port),
            (.socks, appModel.controllerMetadata.config.socksPort),
            (.redir, appModel.controllerMetadata.config.redirPort),
            (.mixed, appModel.controllerMetadata.config.mixedPort),
        ]
        return ports.compactMap { port, value in value.map { (port, $0) } }
    }

    private var configStatus: ControllerEndpointStatus {
        appModel.controllerHealth.status(for: .configs)
    }

    private var sessionFailureDetail: String? {
        switch appModel.controllerSessionPresentation.state {
        case .failedBeforeFirstSnapshot(let message), .failed(let message):
            message.managementNonEmpty
        case .idle, .connecting, .live, .staleReconnecting, .partial, .stopped:
            nil
        }
    }

    private var hasConfigurationPresentation: Bool {
        hasModePresentation
            || hasGeneralPresentation
            || !reportedPorts.isEmpty
            || hasTailscalePresentation
    }

    private var hasModePresentation: Bool {
        appModel.supportsUnifiedAction(modeAction)
            && (reportedMode != nil || !appModel.controllerMetadata.config.modeOptions.isEmpty)
    }

    private var hasGeneralPresentation: Bool {
        appModel.controllerMetadata.config.logLevel != nil
                && appModel.supportsUnifiedAction(.setLogLevel)
            || appModel.controllerMetadata.config.allowLan != nil
                && appModel.supportsUnifiedAction(.setAllowLAN)
            || appModel.controllerMetadata.config.ipv6 != nil
                && appModel.supportsUnifiedAction(.setIPv6)
            || appModel.controllerMetadata.config.tcpConcurrent != nil
                && appModel.supportsUnifiedAction(.setTCPConcurrent)
            || appModel.controllerMetadata.config.tunEnabled != nil
                && appModel.supportsUnifiedAction(.setTUN)
    }

    private var hasTailscalePresentation: Bool {
        if appModel.singBoxTailscaleStatus != nil
            || appModel.singBoxTailscaleError != nil {
            return true
        }

        guard let status = appModel.capabilityMatrixRows.first(where: {
            $0.id == "tailscale"
        })?.status else {
            return false
        }
        return status != .unavailable
    }

    private var hasSupportedConfigurationCapability: Bool {
        appModel.supportsUnifiedAction(modeAction)
            || appModel.supportsUnifiedAction(.setLogLevel)
            || appModel.supportsUnifiedAction(.setAllowLAN)
            || appModel.supportsUnifiedAction(.setIPv6)
            || appModel.supportsUnifiedAction(.setTCPConcurrent)
            || appModel.supportsUnifiedAction(.setTUN)
            || appModel.supportsUnifiedAction(.setPort)
            || hasTailscalePresentation
    }

    private var configWriteDisabled: Bool {
        appModel.isBusy || !appModel.canRefreshSelectedRouter || !permitsConfigurationWrites
    }

    private var permitsConfigurationWrites: Bool {
        switch appModel.controllerSessionPresentation.state {
        case .live, .partial:
            true
        case .idle, .connecting, .staleReconnecting, .failedBeforeFirstSnapshot,
             .failed, .stopped:
            false
        }
    }

    private func logLevelOptions(current: String) -> [String] {
        var options = ["silent", "error", "warning", "info", "debug"]
        if let normalized = current.managementNonEmpty,
           !options.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            options.insert(normalized, at: 0)
        }
        return options
    }

    private func logLevelLabel(_ level: String) -> String {
        let key: String?
        switch level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "silent": key = "configuration.log_level_silent"
        case "error": key = "log_type.error"
        case "warning", "warn": key = "log_type.warning"
        case "info", "information": key = "log_type.info"
        case "debug": key = "log_type.debug"
        case "trace": key = "log_type.trace"
        default: key = nil
        }

        guard let key else { return level }
        return MicaStrings.localizedKey(key, language: language)
    }

    private var reportedMode: String? {
        guard let value = appModel.controllerMetadata.mode.managementNonEmpty else { return nil }
        switch value.lowercased() {
        case "unknown", "not loaded", "-":
            return nil
        default:
            return value
        }
    }

    private func normalizedMode(_ value: String) -> String {
        DashboardSnapshot.displayMode(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func modesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedMode(lhs) == normalizedMode(rhs)
    }

    private func reported(_ value: String?) -> String {
        value?.managementNonEmpty
            ?? MicaStrings.localizedKey("overview.config_not_reported", language: language)
    }
}

private struct WorkbenchPortField: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let value: Int
    let disabled: Bool
    let onCommit: (Int) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        titleKey: String,
        value: Int,
        disabled: Bool,
        onCommit: @escaping (Int) -> Void
    ) {
        self.titleKey = titleKey
        self.value = value
        self.disabled = disabled
        self.onCommit = onCommit
        _text = State(initialValue: String(value))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: MicaTheme.Spacing.space1) {
                TextField(
                    "",
                    text: $text
                )
                .textFieldStyle(.roundedBorder)
                .micaThemeFont(.body).monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 104)
                .focused($isFocused)
                .onSubmit(commit)
                .onExitCommand {
                    text = String(value)
                }
                .accessibilityLabel(MicaStrings.localizedKey(titleKey, language: language))

                if isDirty {
                    Button {
                        text = String(value)
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: MicaTheme.Metrics.iconControlSize, height: MicaTheme.Metrics.iconControlSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(disabled)
                    .help(MicaStrings.localizedKey("action.revert_port", language: language))
                    .accessibilityLabel(
                        MicaStrings.localizedKey("action.revert_port", language: language)
                    )
                }

                Button(action: commit) {
                    Image(systemName: "checkmark")
                        .frame(width: MicaTheme.Metrics.iconControlSize, height: MicaTheme.Metrics.iconControlSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(disabled || parsedValue == nil || !isDirty)
                .help(MicaStrings.localizedKey("action.apply_port", language: language))
                .accessibilityLabel(
                    MicaStrings.localizedKey("action.apply_port", language: language)
                )
            }

            if showsValidationError {
                Text(MicaStrings.localizedKey("configuration.validation_port_range", language: language))
                    .micaThemeFont(.caption)
                    .foregroundStyle(MicaTheme.statusError)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: value) { _, next in
            text = String(next)
        }
        .disabled(disabled)
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDirty: Bool {
        trimmedText != String(value)
    }

    private var parsedValue: Int? {
        guard let number = Int(trimmedText), (0...65_535).contains(number) else { return nil }
        return number
    }

    private var showsValidationError: Bool {
        isDirty && parsedValue == nil
    }

    private func commit() {
        guard !disabled, let parsedValue, parsedValue != value else { return }
        onCommit(parsedValue)
    }
}

/// Segmented while every choice fits at a glance, otherwise a native menu.
struct WorkbenchChoicePickerStyle: ViewModifier {
    let isCompact: Bool

    func body(content: Content) -> some View {
        if isCompact {
            ViewThatFits(in: .horizontal) {
                content
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)

                content
                    .pickerStyle(.menu)
            }
        } else {
            content.pickerStyle(.menu)
        }
    }
}
