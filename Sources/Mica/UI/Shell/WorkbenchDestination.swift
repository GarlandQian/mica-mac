import Foundation
import SwiftUI

enum MicaSceneID {
    static let workbench = "workbench"
}

/// Primary sidebar destinations (consolidated into 6 streamlined workspaces).
enum WorkbenchDestination: String, CaseIterable, Identifiable, Sendable {
    case overview
    case proxies
    case connections
    case rules
    case logs
    case controllers

    static let sidebarCases: [Self] = allCases

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .overview: "navigation.overview"
        case .proxies: "navigation.proxies"
        case .connections: "dashboard.tab_connections"
        case .rules: "dashboard.tab_rules"
        case .logs: "dashboard.tab_logs"
        case .controllers: "sidebar.controllers"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .proxies: "point.3.connected.trianglepath.dotted"
        case .connections: "arrow.up.arrow.down.circle"
        case .rules: "arrow.triangle.branch"
        case .logs: "doc.text.magnifyingglass"
        case .controllers: "server.rack"
        }
    }

    var shortcut: KeyEquivalent? {
        switch self {
        case .overview: "1"
        case .proxies: "2"
        case .connections: "3"
        case .rules: "4"
        case .logs: "5"
        case .controllers: "6"
        }
    }

    var supportsSearch: Bool {
        switch self {
        case .proxies, .connections, .rules, .logs:
            true
        case .overview, .controllers:
            false
        }
    }

    var supportsInspector: Bool {
        switch self {
        case .proxies, .connections, .rules, .logs, .controllers:
            true
        case .overview:
            false
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
        case .proxies, .rules, .controllers:
            .other
        }
    }
}
