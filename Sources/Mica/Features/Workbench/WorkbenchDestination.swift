import SwiftUI

/// The eleven stable top-level destinations of the controller workbench.
///
/// The former five areas plus their second-level sections are flattened into a
/// single sidebar destination model (Mail/Xcode style). Each destination knows
/// its own sidebar group so the sidebar can render grouped `Section`s without
/// bespoke selection plumbing.
enum WorkbenchDestination: String, CaseIterable, Identifiable {
    // Workbench group
    case overview
    case proxies
    case connections
    case logs
    case rules
    case sources
    // Controller management group
    case controllers
    case configuration
    case actions
    case diagnostics
    // App settings
    case settings

    var id: String { rawValue }

    /// Sidebar grouping used to render grouped `Section`s.
    enum Group: CaseIterable, Identifiable {
        case workbench
        case controllerManagement
        case appSettings

        var id: Self { self }

        var titleKey: String {
            switch self {
            case .workbench: "sidebar.group_workbench"
            case .controllerManagement: "sidebar.group_controller_management"
            case .appSettings: "sidebar.group_app_settings"
            }
        }
    }

    var group: Group {
        switch self {
        case .overview, .proxies, .connections, .logs, .rules, .sources:
            .workbench
        case .controllers, .configuration, .actions, .diagnostics:
            .controllerManagement
        case .settings:
            .appSettings
        }
    }

    /// The workbench-group destinations, in fixed order, used for ⌘1–⌘6 and menu iteration.
    static let workbenchTabCases: [WorkbenchDestination] = [
        .overview, .proxies, .connections, .logs, .rules, .sources,
    ]

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
        case .settings: "workbench.settings"
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
        case .settings: "gearshape"
        }
    }

    /// Keyboard shortcut for the workbench-group destinations (⌘1–⌘6). Other
    /// destinations do not bind a number key.
    var shortcut: KeyEquivalent? {
        switch self {
        case .overview: "1"
        case .proxies: "2"
        case .connections: "3"
        case .logs: "4"
        case .rules: "5"
        case .sources: "6"
        case .controllers, .configuration, .actions, .diagnostics, .settings: nil
        }
    }

    var supportsSearch: Bool {
        switch self {
        case .proxies, .connections, .logs, .rules, .sources:
            true
        case .overview, .controllers, .configuration, .actions, .diagnostics, .settings:
            false
        }
    }

    var searchPromptKey: String {
        switch self {
        case .proxies: "routing.search_placeholder"
        case .rules: "dashboard.search_rules"
        case .connections, .logs, .sources, .overview, .controllers, .configuration, .actions, .diagnostics, .settings:
            "traffic.search_placeholder"
        }
    }

    /// Whether reaching this destination requires a selected controller.
    /// Controller management and app settings remain reachable without an
    /// active controller; controller-backed workbench destinations do not.
    var requiresController: Bool {
        self != .controllers && self != .settings
    }

    /// Maps legacy persisted navigation state to a destination.
    ///
    /// Old persistence used four keys: `workbenchArea` plus one section per
    /// area (activity/resources/system). This resolves those combinations to
    /// the flattened destination, falling back to `overview` for unknown input.
    static func migrated(
        fromArea area: String?,
        activitySection: String?,
        resourcesSection: String?,
        systemSection: String?
    ) -> WorkbenchDestination {
        switch area {
        case "overview":
            return .overview
        case "proxies":
            return .proxies
        case "activity":
            switch activitySection {
            case "logs": return .logs
            default: return .connections
            }
        case "resources":
            switch resourcesSection {
            case "sources": return .sources
            default: return .rules
            }
        case "system":
            switch systemSection {
            case "actions": return .actions
            case "diagnostics": return .diagnostics
            case "settings": return .settings
            default: return .configuration
            }
        default:
            return migratedFromLegacyString(area)
        }
    }

    /// Fallback for the older single `workbenchDestination` legacy string that
    /// predated the five-area model.
    static func migratedFromLegacyString(_ legacyValue: String?) -> WorkbenchDestination {
        switch legacyValue {
        case "policyGroups": .proxies
        case "connections": .connections
        case "logs": .logs
        case "rules": .rules
        case "sources": .sources
        case "controllers": .controllers
        case "coreConfig": .configuration
        case "coreActions": .actions
        case "tailscale", "diagnostics": .diagnostics
        case "settings": .settings
        default: .overview
        }
    }
}
