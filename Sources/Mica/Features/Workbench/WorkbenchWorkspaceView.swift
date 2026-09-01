import MicaCore
import SwiftUI

struct WorkbenchWorkspaceView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language

    @Binding var destination: WorkbenchDestination

    let onAddController: () -> Void
    let onEditController: (RouterProfile) -> Void

    var body: some View {
        searchableContent
    }

    @ViewBuilder
    private var searchableContent: some View {
        if destination.supportsSearch {
            content
                .searchable(
                    text: searchText,
                    placement: .toolbar,
                    prompt: Text(
                        MicaStrings.localizedKey(
                            destination.searchPromptKey,
                            language: language
                        )
                    )
                )
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if destination.requiresController, appModel.selectedRouter == nil {
            WorkbenchStateView(
                kind: .noController,
                titleKey: "dashboard.connect_router",
                detailKey: "dashboard.connect_router_message",
                actionTitleKey: "sidebar.add_controller",
                actionSystemImage: "plus",
                action: onAddController
            )
        } else {
            switch destination {
            case .overview:
                WorkbenchOverviewView(destination: $destination)
            case .proxies:
                WorkbenchPolicyGroupsView(searchText: searchText)
            case .connections:
                WorkbenchConnectionsView(
                    destination: $destination,
                    searchText: searchText
                )
            case .logs:
                WorkbenchLogsView(searchText: searchText)
            case .rules:
                WorkbenchRulesView(
                    destination: $destination,
                    searchText: searchText
                )
            case .sources:
                WorkbenchSourcesView(searchText: searchText)
            case .controllers:
                WorkbenchControllersView(
                    searchText: searchText,
                    onAddController: onAddController,
                    onEditController: onEditController
                )
            case .configuration:
                WorkbenchConfigurationView()
            case .actions:
                WorkbenchActionsView(
                    destination: $destination,
                    onEditController: onEditController
                )
            case .diagnostics:
                WorkbenchDiagnosticsView(
                    destination: $destination,
                    onEditController: onEditController
                )
            }
        }
    }

    private var searchText: Binding<String> {
        workspaceStore.searchBinding(
            controllerID: appModel.selectedRouterID,
            destination: destination
        )
    }
}

// MARK: - Workspace Inspector

/// Workspace-level inspector container (Mica Ops redesign, design.md §3).
/// The right-side inspector is the single detail-reveal mechanism for the whole
/// workbench. Phase 2 ships the container, toolbar toggle, empty state, and
/// typed selection plumbing only; Phases 3-6 migrate each surface's typed
/// detail content here, replacing the page-level inspectors.
struct WorkbenchInspectorContainer: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore

    @Binding var destination: WorkbenchDestination

    let onEditController: (RouterProfile) -> Void

    var body: some View {
        let selection = workspaceStore.inspectorSelection(for: destination)

        Group {
            switch selection {
            case .none:
                emptyState
            case .proxyGroup, .proxyNode:
                WorkbenchPolicyInspectorView(
                    selection: selection,
                    destination: $destination
                )
            case .connection(let id):
                connectionInspectorContent(id: id)
            case .rule(let type, let payload):
                ruleInspectorContent(type: type, payload: payload)
            case .log(let id):
                logInspectorContent(id: id)
            case .source(let id):
                sourceInspectorContent(id: id)
            case .controller(let id):
                if let profile = appModel.routers.first(where: { $0.id == id }) {
                    WorkbenchControllerInspector(
                        profile: profile,
                        onEditController: onEditController
                    )
                } else {
                    emptyState
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MicaTheme.surfaceRaised)
    }

    /// Connection detail resolved live through the destination's registered
    /// projection-cache resolver (task 08-17 Phase 4C). A vanished or not yet
    /// registered selection renders the truthful empty state; active state
    /// derives from the row's own `closedAt`.
    @ViewBuilder
    private func connectionInspectorContent(id: String) -> some View {
        if let row = workspaceStore.connectionRowResolver?(id) {
            WorkbenchConnectionInspector(
                row: row,
                isActive: row.closedAt == nil,
                close: { workspaceStore.dismissInspector() }
            )
        } else {
            emptyState
        }
    }

    /// Rule detail resolved live through the destination's registered
    /// resolver (task 08-17 Phase 4D). Mutation inputs mirror the retired
    /// page-level inspector exactly: capability gating, in-flight state,
    /// per-rule failure, and the AppModel-validated toggle intent.
    @ViewBuilder
    private func ruleInspectorContent(type: String, payload: String) -> some View {
        if let row = workspaceStore.ruleRowResolver?(type, payload) {
            WorkbenchRuleInspector(
                row: row,
                canMutate: row.rule.hasMutableExtra
                    && row.rule.index != nil
                    && appModel.canRefreshSelectedRouter
                    && appModel.supportsUnifiedAction(.setRuleDisabled),
                isUpdating: appModel.updatingRuleID == row.rule.id,
                failure: appModel.ruleUpdateFailures[row.rule.id],
                close: { workspaceStore.dismissInspector() },
                disabled: Binding(
                    get: { row.rule.disabled ?? false },
                    set: { appModel.setRuleDisabled(row.rule, disabled: $0) }
                )
            )
        } else {
            emptyState
        }
    }

    /// Log detail resolved live through the destination's registered
    /// projection-cache resolver (task 08-17 Phase 5A). A vanished or not yet
    /// registered selection renders the truthful empty state.
    @ViewBuilder
    private func logInspectorContent(id: String) -> some View {
        if let row = workspaceStore.logEntryResolver?(id) {
            WorkbenchLogInspector(
                row: row,
                close: { workspaceStore.dismissInspector() }
            )
        } else {
            emptyState
        }
    }

    /// Source detail resolved live through the destination's registered
    /// projection-cache resolver (task 08-17 Phase 5B). Failure inputs mirror
    /// the retired page-level inspector exactly: per-provider update and
    /// health-check failures resolve from AppModel keyed by the
    /// controller-reported provider ID. Mutation affordances stay on the
    /// focus rail; the inspector stays read-only (verifier contract).
    @ViewBuilder
    private func sourceInspectorContent(id: String) -> some View {
        if let row = workspaceStore.sourceRowResolver?(id) {
            WorkbenchSourceInspector(
                row: row,
                updateFailure: appModel.providerUpdateFailures[row.source.id],
                healthFailure: appModel.providerHealthCheckFailures[row.source.id],
                close: { workspaceStore.dismissInspector() }
            )
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        MicaEmptyState(
            systemImage: "sidebar.trailing",
            titleKey: "workbench.inspector_empty_title",
            messageKey: "workbench.inspector_empty_message"
        )
    }
}

/// Toolbar toggle for the workspace inspector (macOS trailing-sidebar idiom).
/// The engaged state tints with the accent token: accent marks selection and
/// active state only (design.md §2).
struct WorkbenchInspectorToggleButton: View {
    @Environment(\.micaAppLanguage) private var language

    @Binding var isPresented: Bool

    var body: some View {
        let title = MicaStrings.localizedKey(
            "workbench.inspector_toggle",
            language: language
        )

        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "sidebar.trailing")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isPresented ? MicaTheme.accent : .primary)
                .frame(
                    width: MicaTheme.Metrics.iconControlSize,
                    height: MicaTheme.Metrics.iconControlSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isPresented ? .isSelected : [])
    }
}
