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
                WorkbenchActionsView()
            case .diagnostics:
                WorkbenchDiagnosticsView()
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
