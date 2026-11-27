import AppKit
import MicaCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var preferences: AppPreferencesStore
    @SceneStorage("workbenchDestination") private var destinationRawValue = WorkbenchDestination.overview.rawValue

    @State private var uiState = WorkspaceUIState()
    @State private var closeGuard = MainWindowCloseGuard()
    @State private var didRegisterMainWindow = false
    @State private var windowDemandID = LiveSessionWindowDemandID()
    @State private var addControllerRequestID = 0
    @State private var editControllerRequestID = 0

    private var destination: Binding<WorkbenchDestination> {
        Binding(
            get: { WorkbenchDestination(rawValue: destinationRawValue) ?? .overview },
            set: { next in
                guard destinationRawValue != next.rawValue else { return }
                destinationRawValue = next.rawValue
            }
        )
    }

    var body: some View {
        @Bindable var uiState = uiState
        let currentDestination = destination.wrappedValue
        let isInspectorVisible = currentDestination.supportsInspector && uiState.isInspectorPresented

        NavigationSplitView {
            sidebar(selection: destination)
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 250)
        } detail: {
            detailContent(for: currentDestination, isInspectorVisible: isInspectorVisible)
                .navigationTitle(L(currentDestination.titleKey, language: preferences.language))
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    toolbarContent(for: currentDestination, isInspectorPresented: $uiState.isInspectorPresented)
                }
        }
        .navigationSplitViewStyle(.balanced)
        .environment(uiState)
        .sheet(item: $uiState.editingController) { sheetState in
            ControllerEditorSheet(state: sheetState)
                .environment(appModel)
        }
        .background {
            MainWindowCloseGuardAttachment(closeGuard: closeGuard)
                .frame(width: 0, height: 0)
        }
        .focusedValue(\.micaFocusedWorkbenchDestination, destination)
        .focusedValue(\.micaAddControllerRequestID, $addControllerRequestID)
        .focusedValue(\.micaEditControllerRequestID, $editControllerRequestID)
        .task {
            appModel.loadPersistedState()
        }
        .onAppear {
            if !didRegisterMainWindow {
                didRegisterMainWindow = true
                appModel.mainWindowDidAppear()
            }
            appModel.registerLiveSessionWindowDemand(
                windowDemandID,
                destination: currentDestination.liveSessionVisibleDestination
            )
            appModel.applyPresentationLanguage(preferences.language)
        }
        .onDisappear {
            appModel.unregisterLiveSessionWindowDemand(windowDemandID)
            if didRegisterMainWindow {
                didRegisterMainWindow = false
                appModel.mainWindowDidDisappear()
            }
            closeGuard.detach()
        }
        .onChange(of: destinationRawValue) { _, _ in
            let next = destination.wrappedValue
            uiState.clearInspectorIfNotOwned(by: next)
            appModel.updateLiveSessionWindowDemand(
                windowDemandID,
                destination: next.liveSessionVisibleDestination
            )
        }
        .onChange(of: preferences.language) { _, language in
            appModel.applyPresentationLanguage(language)
        }
        .onChange(of: addControllerRequestID) { _, _ in
            uiState.editingController = ControllerEditorSheetState(
                titleKey: "editor.add_router",
                draft: appModel.draft()
            )
        }
        .onChange(of: editControllerRequestID) { _, _ in
            guard let router = appModel.selectedRouter else { return }
            uiState.editingController = ControllerEditorSheetState(
                titleKey: "editor.edit_router",
                draft: appModel.draft(for: router)
            )
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            appModel.systemWillSleep()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            appModel.systemDidWake()
        }
    }

    // MARK: - Sidebar

    private func sidebar(selection: Binding<WorkbenchDestination>) -> some View {
        List(selection: Binding<WorkbenchDestination?>(
            get: { selection.wrappedValue },
            set: { if let next = $0 { selection.wrappedValue = next } }
        )) {
            ForEach(WorkbenchDestination.sidebarCases) { item in
                Label {
                    Text(verbatim: L(item.titleKey, language: preferences.language))
                } icon: {
                    Image(systemName: item.symbolName)
                }
                .tag(item)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            MicaSidebarControllerMenu(
                onAddController: {
                    uiState.editingController = ControllerEditorSheetState(
                        titleKey: "editor.add_router",
                        draft: appModel.draft()
                    )
                },
                onManageControllers: {
                    selection.wrappedValue = .controllers
                    uiState.activeControllerSection = .controllers
                }
            )
            .padding(.horizontal, MicaTheme.Spacing.md)
            .padding(.bottom, MicaTheme.Spacing.sm)
        }
        .navigationTitle("Mica")
    }

    // MARK: - Detail Workspace

    @ViewBuilder
    private func detailContent(for current: WorkbenchDestination, isInspectorVisible: Bool) -> some View {
        let workspace = HStack(spacing: 0) {
            Group {
                if current.requiresController, appModel.selectedRouter == nil {
                    MicaEmptyStateView(
                        systemImage: "server.rack",
                        title: L("dashboard.connect_router", language: preferences.language),
                        message: L("dashboard.connect_router_message", language: preferences.language),
                        actionTitle: L("sidebar.add_controller", language: preferences.language),
                        action: {
                            uiState.editingController = ControllerEditorSheetState(
                                titleKey: "editor.add_router",
                                draft: appModel.draft()
                            )
                        }
                    )
                } else {
                    switch current {
                    case .overview:
                        OverviewView(destination: destination)
                    case .proxies:
                        ProxiesView(searchText: uiState.searchBinding(for: .proxies))
                    case .connections:
                        ConnectionsView(searchText: uiState.searchBinding(for: .connections))
                    case .rules:
                        RulesView(searchText: uiState.searchBinding(for: .rules))
                    case .logs:
                        LogsView(searchText: uiState.searchBinding(for: .logs))
                    case .controllers:
                        ControllersView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                TransientOperationToast()
            }

            if isInspectorVisible {
                MicaHairlineDivider(axis: .vertical)
                WorkspaceInspectorView(destination: destination)
                    .frame(width: 320)
                    .frame(maxHeight: .infinity)
            }
        }

        if current.supportsSearch {
            workspace.searchable(
                text: uiState.searchBinding(for: current),
                placement: .toolbar,
                prompt: Text(L(searchPromptKey(for: current), language: preferences.language))
            )
        } else {
            workspace
        }
    }

    private func searchPromptKey(for destination: WorkbenchDestination) -> String {
        switch destination {
        case .proxies: "routing.search_active_nodes"
        case .rules: "dashboard.search_rules"
        default: "traffic.search_placeholder"
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(
        for current: WorkbenchDestination,
        isInspectorPresented: Binding<Bool>
    ) -> some ToolbarContent {
        if current.requiresController {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appModel.refreshSelectedRouter()
                } label: {
                    Label(L("action.refresh", language: preferences.language), systemImage: "arrow.clockwise")
                }
                .disabled(!appModel.canRefreshSelectedRouter)
                .help(L("dashboard.help_refresh_controller", language: preferences.language))

                let isPaused = appModel.controllerSessionPresentation.controls.dashboardUpdatesPaused
                Button {
                    appModel.toggleDashboardUpdatesPaused()
                } label: {
                    Label(
                        L(isPaused ? "live.resume" : "live.pause", language: preferences.language),
                        systemImage: isPaused ? "play.circle" : "pause.circle"
                    )
                }
                .disabled(!appModel.canTogglePresentationPause)
                .help(L(isPaused ? "live.resume" : "live.pause", language: preferences.language))
            }
        }

        if current.supportsInspector {
            if current.requiresController {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }

            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: isInspectorPresented) {
                    Label(L("workbench.inspector_toggle", language: preferences.language), systemImage: "sidebar.trailing")
                }
                .toggleStyle(.button)
                .help(L("workbench.inspector_toggle", language: preferences.language))
            }
        }
    }
}

// MARK: - Compact Controller Menu

private struct MicaSidebarControllerMenu: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let onAddController: () -> Void
    let onManageControllers: () -> Void

    var body: some View {
        Menu {
            if appModel.routers.isEmpty {
                Text(L("dashboard.no_controller", language: language))
            } else {
                ForEach(appModel.routers) { router in
                    Button {
                        appModel.selectRouter(router)
                    } label: {
                        HStack {
                            Text(verbatim: router.displayName)
                            if router.id == appModel.selectedRouterID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
            }

            Button(L("sidebar.add_controller", language: language), action: onAddController)
            Button(L("sidebar.controllers", language: language), action: onManageControllers)
        } label: {
            HStack(spacing: MicaTheme.Spacing.sm) {
                MicaStatusDot(color: statusColor, size: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: appModel.selectedRouter?.displayName ?? L("dashboard.no_controller", language: language))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(MicaTheme.textPrimary)
                        .lineLimit(1)
                    if let router = appModel.selectedRouter {
                        Text(verbatim: appModel.controllerAdapter(for: router).detectedKind.micaBadge)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(MicaTheme.textTertiary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(MicaTheme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(MicaTheme.subtleFill, in: RoundedRectangle(cornerRadius: MicaTheme.Radius.card, style: .continuous))
        }
        .menuStyle(.borderlessButton)
    }

    private var statusColor: Color {
        guard appModel.selectedRouter != nil else { return MicaTheme.textTertiary }
        switch appModel.controllerSessionPresentation.state {
        case .live: return MicaTheme.statusOK
        case .connecting, .partial, .staleReconnecting: return MicaTheme.statusWarning
        case .failedBeforeFirstSnapshot, .failed: return MicaTheme.statusError
        case .idle, .stopped: return MicaTheme.textTertiary
        }
    }
}

// MARK: - Transient Operation Pill

private struct TransientOperationToast: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    var body: some View {
        if let state = appModel.operationState {
            let pill = HStack(spacing: MicaTheme.Spacing.sm) {
                if state.kind == .working {
                    ProgressView().controlSize(.small)
                } else {
                    MicaStatusDot(color: toneColor(for: state.kind), size: 7)
                }

                Text(verbatim: state.message)
                    .font(.caption)
                    .foregroundStyle(MicaTheme.textPrimary)
                    .lineLimit(2)

                if state.kind != .working {
                    Button {
                        appModel.operationState = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(MicaTheme.textSecondary)
                    }
                    .buttonStyle(.borderless)
                    .help(L("action.dismiss", language: language))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(MicaTheme.separator, lineWidth: 0.75)
            }
            .padding(MicaTheme.Spacing.lg)

            pill
                .task(id: state) {
                    guard state.kind == .success else { return }
                    try? await Task.sleep(for: .seconds(3))
                    if appModel.operationState == state {
                        appModel.operationState = nil
                    }
                }
        }
    }

    private func toneColor(for kind: OperationState.Kind) -> Color {
        switch kind {
        case .working: MicaTheme.statusInfo
        case .success: MicaTheme.statusOK
        case .partial: MicaTheme.statusWarning
        case .error: MicaTheme.statusError
        }
    }
}
