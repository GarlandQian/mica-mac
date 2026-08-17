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
        case workbench
        case controllerManagement

        var id: Self { self }

        var titleKey: String {
            switch self {
            case .workbench: "sidebar.group_workbench"
            case .controllerManagement: "sidebar.group_controller_management"
            }
        }
    }

    var id: String { rawValue }

    static let workbenchTabCases: [Self] = [
        .overview, .proxies, .connections, .logs, .rules, .sources,
    ]

    static let controllerManagementCases: [Self] = [
        .controllers, .configuration, .actions, .diagnostics,
    ]

    static let sidebarCases = workbenchTabCases + controllerManagementCases

    var group: Group {
        switch self {
        case .overview, .proxies, .connections, .logs, .rules, .sources:
            .workbench
        case .controllers, .configuration, .actions, .diagnostics:
            .controllerManagement
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

    @Binding var destination: WorkbenchDestination

    let onAddController: () -> Void
    let onEditController: (RouterProfile) -> Void

    var body: some View {
        WorkbenchWorkspaceView(
            destination: $destination,
            onAddController: onAddController,
            onEditController: onEditController
        )
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
