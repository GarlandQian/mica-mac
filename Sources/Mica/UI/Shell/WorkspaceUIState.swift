import Foundation
import MicaCore
import SwiftUI

enum RulesSubtab: String, CaseIterable, Identifiable, Sendable {
    case rules
    case providers

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .rules: "dashboard.tab_rules"
        case .providers: "dashboard.tab_providers"
        }
    }
}

enum ControllersSubtab: String, CaseIterable, Identifiable, Sendable {
    case controllers
    case config
    case diagnostics

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .controllers: "sidebar.controllers"
        case .config: "workbench.configuration"
        case .diagnostics: "workspace.diagnostics"
        }
    }
}

enum WorkspaceInspectorSelection: Equatable, Sendable {
    case none
    case proxyNode(groupID: String, nodeName: String)
    case connection(id: String)
    case rule(id: String)
    case provider(id: String)
    case log(id: String)
    case controller(id: RouterProfile.ID)

    var isPresented: Bool {
        self != .none
    }
}

struct ControllerEditorSheetState: Identifiable, Equatable {
    let id = UUID()
    let titleKey: String
    let draft: RouterDraft
}

/// Lightweight UI navigation, filter, and inspector coordination state.
@MainActor
@Observable
final class WorkspaceUIState {
    var inspectorSelection: WorkspaceInspectorSelection = .none
    var isInspectorPresented = false
    var searchTextByDestination: [WorkbenchDestination: String] = [:]
    var activeRuleSection: RulesSubtab = .rules
    var activeControllerSection: ControllersSubtab = .controllers
    var editingController: ControllerEditorSheetState?
    var pendingProxyGroupID: String?

    func searchBinding(for destination: WorkbenchDestination) -> Binding<String> {
        Binding(
            get: { self.searchTextByDestination[destination] ?? "" },
            set: { self.searchTextByDestination[destination] = $0 }
        )
    }

    func searchText(for destination: WorkbenchDestination) -> String {
        searchTextByDestination[destination] ?? ""
    }

    func selectInspector(_ selection: WorkspaceInspectorSelection) {
        inspectorSelection = selection
        isInspectorPresented = selection != .none
    }

    func dismissInspector() {
        inspectorSelection = .none
        isInspectorPresented = false
    }

    func clearInspectorIfNotOwned(by destination: WorkbenchDestination) {
        let keep: Bool = switch inspectorSelection {
        case .none:
            false
        case .proxyNode:
            destination == .proxies
        case .connection:
            destination == .connections
        case .rule, .provider:
            destination == .rules
        case .log:
            destination == .logs
        case .controller:
            destination == .controllers
        }
        if !keep {
            inspectorSelection = .none
            if !destination.supportsInspector {
                isInspectorPresented = false
            }
        }
    }
}
