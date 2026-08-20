import MicaCore
import SwiftUI

// MARK: - Navigation

enum WorkbenchDestination: String, CaseIterable, Identifiable, Sendable {
    case overview
    case proxies
    case connections
    case logs
    case rules
    case sources
    case controllers
    case configuration
    case actions
    case diagnostics

    enum Group: CaseIterable, Identifiable {
        case operate
        case observe
        case manage

        var id: Self { self }

        var titleKey: String {
            switch self {
            case .operate: "sidebar.group_operate"
            case .observe: "sidebar.group_observe"
            case .manage: "sidebar.group_manage"
            }
        }
    }

    var id: String { rawValue }

    /// The six controller-data destinations reachable via ⌘1…⌘6 and listed in
    /// the View menu, in fixed product order.
    static let workbenchTabCases: [Self] = [
        .overview, .proxies, .connections, .logs, .rules, .sources,
    ]

    /// Operate: the primary operations workflow surfaces (Mica Ops IA).
    static let operateCases: [Self] = [
        .overview, .proxies, .connections, .rules,
    ]

    /// Observe: read-only monitoring and troubleshooting surfaces.
    static let observeCases: [Self] = [
        .logs, .sources, .diagnostics,
    ]

    /// Manage: controller and application management surfaces.
    static let manageCases: [Self] = [
        .controllers, .configuration, .actions,
    ]

    static let sidebarCases = operateCases + observeCases + manageCases

    var group: Group {
        switch self {
        case .overview, .proxies, .connections, .rules:
            .operate
        case .logs, .sources, .diagnostics:
            .observe
        case .controllers, .configuration, .actions:
            .manage
        }
    }

    var titleKey: String {
        switch self {
        case .overview: "navigation.overview"
        case .proxies: "navigation.proxies"
        case .connections: "dashboard.tab_connections"
        case .logs: "dashboard.tab_logs"
        case .rules: "dashboard.tab_rules"
        case .sources: "dashboard.tab_providers"
        case .controllers: "sidebar.controllers"
        case .configuration: "workbench.configuration"
        case .actions: "workbench.actions"
        case .diagnostics: "workspace.diagnostics"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .proxies: "point.3.connected.trianglepath.dotted"
        case .connections: "bolt.horizontal.circle"
        case .logs: "list.bullet.rectangle.portrait"
        case .rules: "arrow.triangle.branch"
        case .sources: "shippingbox"
        case .controllers: "server.rack"
        case .configuration: "slider.horizontal.3"
        case .actions: "bolt.badge.checkmark"
        case .diagnostics: "stethoscope"
        }
    }

    var shortcut: KeyEquivalent? {
        switch self {
        case .overview: "1"
        case .proxies: "2"
        case .connections: "3"
        case .logs: "4"
        case .rules: "5"
        case .sources: "6"
        case .controllers, .configuration, .actions, .diagnostics: nil
        }
    }

    var supportsSearch: Bool {
        switch self {
        case .proxies, .connections, .logs, .rules, .sources, .controllers:
            true
        case .overview, .configuration, .actions, .diagnostics:
            false
        }
    }

    var searchPromptKey: String {
        switch self {
        case .proxies: "routing.search_placeholder"
        case .rules: "dashboard.search_rules"
        case .controllers: "controllers.search_prompt"
        case .connections, .logs, .sources:
            "traffic.search_placeholder"
        case .overview, .configuration, .actions, .diagnostics:
            "traffic.search_placeholder"
        }
    }

    var requiresController: Bool {
        switch self {
        case .controllers:
            false
        default:
            true
        }
    }

    var liveSessionVisibleDestination: LiveSessionVisibleDestination {
        switch self {
        case .overview:
            .overview
        case .connections:
            .connections
        case .logs:
            .logs
        case .proxies, .rules, .sources, .controllers, .configuration,
             .actions, .diagnostics:
            .other
        }
    }
}

// MARK: - Workbench Shell

struct WorkbenchRootView: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore

    @Binding var destination: WorkbenchDestination

    let onAddController: () -> Void
    let onEditController: (RouterProfile) -> Void

    var body: some View {
        @Bindable var workspaceStore = workspaceStore

        WorkbenchWorkspaceView(
            destination: $destination,
            onAddController: onAddController,
            onEditController: onEditController
        )
            .inspector(isPresented: $workspaceStore.isInspectorPresented) {
                WorkbenchInspectorContainer(
                            destination: $destination,
                            onEditController: onEditController
                        )
                    .inspectorColumnWidth(
                        min: MicaTheme.Metrics.inspectorMin,
                        ideal: MicaTheme.Metrics.inspectorIdeal,
                        max: MicaTheme.Metrics.inspectorMax
                    )
            }
            .navigationTitle(
                MicaStrings.localizedKey(destination.titleKey, language: language)
            )
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if destination == .overview {
                    ToolbarItem(placement: .primaryAction) {
                        OverviewPreferencesToolbarControl()
                    }
                    .sharedBackgroundVisibility(.hidden)
                }

                if destination != .diagnostics {
                    ToolbarItem(placement: .primaryAction) {
                        WorkbenchSessionControlButton(kind: .test)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }

                ToolbarItem(placement: .primaryAction) {
                    WorkbenchSessionControlButton(kind: .refresh)
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .primaryAction) {
                    WorkbenchSessionControlButton(kind: .pause)
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .primaryAction) {
                    WorkbenchInspectorToggleButton(
                        isPresented: $workspaceStore.isInspectorPresented
                    )
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                WorkbenchBottomChrome()
            }
            .focusedValue(\.micaFocusedWorkbenchDestination, $destination)
            .background {
                WorkbenchRootLifecycleObserver(destination: destination)
            }
    }
}

private struct WorkbenchRootLifecycleObserver: View {
    @Environment(AppModel.self) private var appModel
    @Environment(OverviewWindowRuntime.self) private var overviewRuntime
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore

    let destination: WorkbenchDestination

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                if !appModel.routers.isEmpty {
                    retainControllers(appModel.routers)
                }
                appModel.registerLiveSessionWindowDemand(
                    overviewRuntime.liveSessionWindowDemandID,
                    destination: destination.liveSessionVisibleDestination
                )
            }
            .onDisappear {
                workspaceStore.flushPendingPersistence()
                appModel.unregisterLiveSessionWindowDemand(
                    overviewRuntime.liveSessionWindowDemandID
                )
            }
            .onChange(of: destination) { _, destination in
                workspaceStore.flushPendingPersistence()
                appModel.updateLiveSessionWindowDemand(
                    overviewRuntime.liveSessionWindowDemandID,
                    destination: destination.liveSessionVisibleDestination
                )
            }
            .onChange(of: appModel.routers) { _, routers in
                retainControllers(routers)
            }
            .onChange(of: appModel.selectedRouterID) { previous, current in
                workspaceStore.flushPendingPersistence()
                if let previous, previous != current {
                    workspaceStore.clearSessionBoundState(controllerID: previous)
                }
                appModel.updateLiveSessionWindowDemand(
                    overviewRuntime.liveSessionWindowDemandID,
                    destination: destination.liveSessionVisibleDestination
                )
            }
            .onChange(of: appModel.controllerSessionPresentation.state) { _, state in
                guard state == .stopped else { return }
                overviewRuntime.registry.clear()
                if let controllerID = appModel.selectedRouterID {
                    workspaceStore.clearSessionBoundState(controllerID: controllerID)
                }
            }
    }

    private func retainControllers(_ routers: [RouterProfile]) {
        workspaceStore.retainControllers(Set(routers.map(\.id)))
    }
}
