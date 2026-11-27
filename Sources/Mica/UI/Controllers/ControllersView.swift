import MicaCore
import SwiftUI

struct ControllersView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkspaceUIState.self) private var uiState
    @Environment(\.micaAppLanguage) private var language

    @State private var selectedRouterID: RouterProfile.ID?
    @State private var pendingDeleteRouter: RouterProfile?
    @State private var pendingRuntimeOperation: DiagnosticsRuntimeOperationRow?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            MicaHairlineDivider()

            switch uiState.activeControllerSection {
            case .controllers:
                controllersListSection
            case .config:
                configurationSection
            case .diagnostics:
                diagnosticsSection
            }
        }
        .background(MicaTheme.canvas)
        .onChange(of: selectedRouterID) { _, id in
            if let id {
                uiState.selectInspector(.controller(id: id))
            } else if case .controller = uiState.inspectorSelection {
                uiState.dismissInspector()
            }
        }
        .alert(
            L("sidebar.delete_button", language: language),
            isPresented: Binding(
                get: { pendingDeleteRouter != nil },
                set: { if !$0 { pendingDeleteRouter = nil } }
            ),
            presenting: pendingDeleteRouter
        ) { router in
            Button(L("action.cancel", language: language), role: .cancel) {}
            Button(L("sidebar.delete_button", language: language), role: .destructive) {
                appModel.deleteRouter(router)
            }
        } message: { router in
            Text(verbatim: router.displayName)
        }
        .alert(
            pendingRuntimeOperation.map { L($0.titleKey, language: language) } ?? "",
            isPresented: Binding(
                get: { pendingRuntimeOperation != nil },
                set: { if !$0 { pendingRuntimeOperation = nil } }
            ),
            presenting: pendingRuntimeOperation
        ) { operation in
            Button(L("action.cancel", language: language), role: .cancel) {}
            Button(L(operation.actionButtonKey ?? "action.run", language: language), role: operation.isDestructive ? .destructive : nil) {
                appModel.performDiagnosticsRuntimeOperation(operation.id)
            }
        } message: { operation in
            Text(verbatim: operation.confirmationMessageKey.map { L($0, language: language) } ?? L(operation.detailKey, language: language))
        }
    }

    private var headerBar: some View {
        @Bindable var uiState = uiState

        return HStack(spacing: MicaTheme.Spacing.md) {
            Picker("", selection: $uiState.activeControllerSection) {
                ForEach(ControllersSubtab.allCases) { tab in
                    Text(L(tab.titleKey, language: language)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 300)

            Spacer(minLength: MicaTheme.Spacing.sm)

            if uiState.activeControllerSection == .controllers {
                Button {
                    uiState.editingController = ControllerEditorSheetState(
                        titleKey: "editor.add_router",
                        draft: appModel.draft()
                    )
                } label: {
                    Label(L("sidebar.add_controller", language: language), systemImage: "plus")
                }
            } else if uiState.activeControllerSection == .diagnostics {
                Button {
                    appModel.testSelectedRouter()
                } label: {
                    Label(L("action.test", language: language), systemImage: "checkmark.circle")
                }
                .disabled(!appModel.canTestSelectedRouter)

                Button {
                    appModel.copyDiagnosticsReport()
                } label: {
                    Label(L("action.diagnostics_copy", language: language), systemImage: "doc.on.doc")
                }
                .disabled(appModel.selectedRouter == nil)
            }
        }
        .padding(.horizontal, MicaTheme.Spacing.lg)
        .padding(.vertical, MicaTheme.Spacing.sm)
    }

    // MARK: - Controllers Tab

    @ViewBuilder
    private var controllersListSection: some View {
        if appModel.routers.isEmpty {
            MicaEmptyStateView(
                systemImage: "server.rack",
                title: L("dashboard.connect_router", language: language),
                message: L("dashboard.connect_router_message", language: language),
                actionTitle: L("sidebar.add_controller", language: language),
                action: {
                    uiState.editingController = ControllerEditorSheetState(
                        titleKey: "editor.add_router",
                        draft: appModel.draft()
                    )
                }
            )
        } else {
            List(appModel.routers, selection: $selectedRouterID) { router in
                let isSelected = router.id == appModel.selectedRouterID
                let adapter = appModel.controllerAdapter(for: router)

                HStack(spacing: MicaTheme.Spacing.md) {
                    MicaStatusDot(
                        color: isSelected ? activeStatusColor : MicaTheme.textTertiary,
                        size: 8
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: MicaTheme.Spacing.sm) {
                            Text(verbatim: router.displayName)
                                .font(.body.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(MicaTheme.textPrimary)

                            Text(verbatim: adapter.detectedKind.micaBadge)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(MicaTheme.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(MicaTheme.subtleFill, in: Capsule())

                            if isSelected {
                                Text(verbatim: L("controllers.active", language: language))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(MicaTheme.accent)
                            }
                        }

                        Text(verbatim: router.endpointURL)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(MicaTheme.textSecondary)
                    }

                    Spacer()

                    if !isSelected {
                        Button(L("controllers.use", language: language)) {
                            appModel.selectRouter(router)
                        }
                        .controlSize(.small)
                    }

                    Button {
                        uiState.editingController = ControllerEditorSheetState(
                            titleKey: "editor.edit_router",
                            draft: appModel.draft(for: router)
                        )
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help(L("action.edit_router", language: language))

                    Button(role: .destructive) {
                        pendingDeleteRouter = router
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(L("sidebar.delete_button", language: language))
                }
                .padding(.vertical, 4)
                .tag(router.id)
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Core Config Tab

    @ViewBuilder
    private var configurationSection: some View {
        if let router = appModel.selectedRouter {
            let isSurge = appModel.runtimeControllerKind(for: router) == .surgeCompatible
            let config = appModel.controllerMetadata.config
            let scope = currentCommandScope
            let canMutate = appModel.controllerSessionPresentation.state.allowsLiveCommands
                && !appModel.controllerSessionPresentation.controls.dashboardUpdatesPaused
                && appModel.updatingConfigFieldID == nil

            Form {
                Section(L("workbench.configuration", language: language)) {
                    let modeOptions = !config.modeOptions.isEmpty
                        ? config.modeOptions
                        : (isSurge ? ["rule", "global", "direct"] : ["Rule", "Global", "Direct"])
                    let currentMode = modeOptions.first {
                        $0.caseInsensitiveCompare(appModel.controllerMetadata.mode) == .orderedSame
                    } ?? modeOptions.first ?? appModel.controllerMetadata.mode

                    Picker(L("dashboard.mode", language: language), selection: Binding(
                        get: { currentMode },
                        set: { next in
                            guard let scope else { return }
                            appModel.setMode(next, scope: scope)
                        }
                    )) {
                        ForEach(modeOptions, id: \.self) { mode in
                            Text(verbatim: MicaStrings.displayMode(mode, language: language)).tag(mode)
                        }
                    }
                    .disabled(!appModel.controllerSessionPresentation.state.allowsLiveCommands || appModel.changingMode)

                    if isSurge {
                        Picker(L("overview.config_log_level", language: language), selection: Binding(
                            get: { appModel.controllerLogLevel },
                            set: { next in
                                guard let scope else { return }
                                appModel.setControllerLogLevel(next, scope: scope)
                            }
                        )) {
                            ForEach(LogSessionLevel.allCases) { level in
                                Text(L(level.titleKey, language: language)).tag(level)
                            }
                        }
                        .disabled(!canMutate || appModel.changingControllerLogLevel)

                        Button(L("action.surge_reload_profile", language: language)) {
                            appModel.reloadSurgeProfile()
                        }
                        .disabled(!appModel.controllerSessionPresentation.state.allowsLiveCommands || appModel.reloadingSurgeProfile)
                    } else {
                        if let logLevel = config.logLevel, appModel.supportsUnifiedAction(.setLogLevel) {
                            let options = ["debug", "info", "warning", "error", "silent"]
                            let currentLevel = options.first { $0.caseInsensitiveCompare(logLevel) == .orderedSame } ?? "info"
                            Picker(L("overview.config_log_level", language: language), selection: Binding(
                                get: { currentLevel },
                                set: { next in
                                    guard let scope else { return }
                                    appModel.updateControllerConfig(.logLevel(next), scope: scope)
                                }
                            )) {
                                ForEach(options, id: \.self) { level in
                                    Text(verbatim: level).tag(level)
                                }
                            }
                            .disabled(!canMutate)
                        }

                        if let allowLan = config.allowLan, appModel.supportsUnifiedAction(.setAllowLAN) {
                            Toggle(L("action.set_allow_lan", language: language), isOn: Binding(
                                get: { allowLan },
                                set: { next in
                                    guard let scope else { return }
                                    appModel.updateControllerConfig(.allowLAN(next), scope: scope)
                                }
                            ))
                            .disabled(!canMutate)
                        }

                        if let ipv6 = config.ipv6, appModel.supportsUnifiedAction(.setIPv6) {
                            Toggle(L("action.set_ipv6", language: language), isOn: Binding(
                                get: { ipv6 },
                                set: { next in
                                    guard let scope else { return }
                                    appModel.updateControllerConfig(.ipv6(next), scope: scope)
                                }
                            ))
                            .disabled(!canMutate)
                        }

                        if let tcpConcurrent = config.tcpConcurrent, appModel.supportsUnifiedAction(.setTCPConcurrent) {
                            Toggle(L("action.set_tcp_concurrent", language: language), isOn: Binding(
                                get: { tcpConcurrent },
                                set: { next in
                                    guard let scope else { return }
                                    appModel.updateControllerConfig(.tcpConcurrent(next), scope: scope)
                                }
                            ))
                            .disabled(!canMutate)
                        }

                        if let tunEnabled = config.tunEnabled, appModel.supportsUnifiedAction(.setTUN) {
                            Toggle(L("overview.config_tun", language: language), isOn: Binding(
                                get: { tunEnabled },
                                set: { next in
                                    guard let scope else { return }
                                    appModel.updateControllerConfig(.tun(next), scope: scope)
                                }
                            ))
                            .disabled(!canMutate)
                        }
                    }
                }

                if !isSurge, hasAnyPort(config) {
                    Section(L("editor.port", language: language)) {
                        PortConfigFieldRow(portKind: .mixed, value: config.mixedPort, scope: scope, disabled: !canMutate || !appModel.supportsUnifiedAction(.setPort))
                        PortConfigFieldRow(portKind: .http, value: config.port, scope: scope, disabled: !canMutate || !appModel.supportsUnifiedAction(.setPort))
                        PortConfigFieldRow(portKind: .socks, value: config.socksPort, scope: scope, disabled: !canMutate || !appModel.supportsUnifiedAction(.setPort))
                        PortConfigFieldRow(portKind: .redir, value: config.redirPort, scope: scope, disabled: !canMutate || !appModel.supportsUnifiedAction(.setPort))
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            MicaEmptyStateView(
                systemImage: "slider.horizontal.3",
                title: L("dashboard.connect_router", language: language)
            )
        }
    }

    private func hasAnyPort(_ config: DashboardConfigSnapshot) -> Bool {
        config.mixedPort != nil || config.port != nil || config.socksPort != nil || config.redirPort != nil
    }

    // MARK: - Actions & Diagnostics Tab

    @ViewBuilder
    private var diagnosticsSection: some View {
        if appModel.selectedRouter == nil {
            MicaEmptyStateView(
                systemImage: "stethoscope",
                title: L("dashboard.connect_router", language: language)
            )
        } else {
            let runnableRows = appModel.diagnosticsRuntimeOperationRows.filter { $0.actionButtonKey != nil }
            let endpoints = appModel.controllerHealth.baseEndpoints + appModel.controllerHealth.enhancedEndpoints

            Form {
                if !runnableRows.isEmpty {
                    Section(L("controllers.actions", language: language)) {
                        ForEach(runnableRows) { row in
                            HStack(spacing: MicaTheme.Spacing.md) {
                                Image(systemName: row.systemImage)
                                    .foregroundStyle(MicaTheme.textSecondary)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: L(row.titleKey, language: language))
                                        .font(.callout.weight(.medium))
                                    Text(verbatim: L(row.detailKey, language: language))
                                        .font(.caption)
                                        .foregroundStyle(MicaTheme.textSecondary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Button(L(row.actionButtonKey ?? "action.run", language: language), role: row.isDestructive ? .destructive : nil) {
                                    if row.requiresConfirmation {
                                        pendingRuntimeOperation = row
                                    } else {
                                        appModel.performDiagnosticsRuntimeOperation(row.id)
                                    }
                                }
                                .disabled(
                                    row.status != .supported
                                        || appModel.runningRuntimeOperationID != nil
                                        || !appModel.controllerSessionPresentation.state.allowsLiveCommands
                                )
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section(L("diagnostics.endpoint_checks", language: language)) {
                    ForEach(endpoints) { endpoint in
                        HStack {
                            MicaStatusDot(color: endpointColor(endpoint.status), size: 7)
                            Text(verbatim: L(endpoint.endpoint.displayTitleKey, language: language))
                                .font(.callout)
                            Spacer()
                            Text(verbatim: endpoint.status.detail)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(MicaTheme.textSecondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func endpointColor(_ status: ControllerEndpointStatus) -> Color {
        switch status {
        case .ready: MicaTheme.statusOK
        case .checking: MicaTheme.statusWarning
        case .failed: MicaTheme.statusError
        case .idle: MicaTheme.textTertiary
        }
    }

    private var activeStatusColor: Color {
        switch appModel.controllerSessionPresentation.state {
        case .live: MicaTheme.statusOK
        case .connecting, .partial, .staleReconnecting: MicaTheme.statusWarning
        case .failedBeforeFirstSnapshot, .failed: MicaTheme.statusError
        case .idle, .stopped: MicaTheme.textTertiary
        }
    }

    private var currentCommandScope: LiveCommandScope? {
        LiveCommandScope(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
    }
}

private struct PortConfigFieldRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let portKind: ControllerConfigPort
    let value: Int?
    let scope: LiveCommandScope?
    let disabled: Bool

    @State private var textValue = ""

    var body: some View {
        if let value {
            HStack {
                Text(verbatim: L(portKind.titleKey, language: language))
                Spacer()
                TextField("", text: $textValue)
                    .font(.system(.callout, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .disabled(disabled)
                Button(L("action.apply_port", language: language)) {
                    guard let scope, let port = Int(textValue.trimmingCharacters(in: .whitespacesAndNewlines)), (0...65_535).contains(port) else {
                        return
                    }
                    appModel.updateControllerConfig(.port(portKind, port), scope: scope)
                }
                .controlSize(.small)
                .disabled(disabled || Int(textValue.trimmingCharacters(in: .whitespacesAndNewlines)) == value)
            }
            .onAppear {
                textValue = "\(value)"
            }
            .onChange(of: value) { _, newValue in
                textValue = "\(newValue)"
            }
        }
    }
}
