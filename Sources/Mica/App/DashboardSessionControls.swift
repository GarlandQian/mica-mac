import Foundation
import MicaCore

struct DashboardSessionControls: Equatable {
    private var closedConnectionBuffer = ClosedConnectionBuffer()
    var closedConnections: [ConnectionSnapshot] {
        get { closedConnectionBuffer.entries }
        set { closedConnectionBuffer.replace(with: newValue) }
    }
    var dashboardUpdatesPaused = false
    var presentationPausedAt: Date?
    var logsPresentationPaused = false
    var logsPresentationPausedAt: Date?

    mutating func resetForControllerSwitch() {
        closedConnectionBuffer.removeAll()
        dashboardUpdatesPaused = false
        presentationPausedAt = nil
        logsPresentationPaused = false
        logsPresentationPausedAt = nil
    }

    mutating func setPresentationPaused(_ paused: Bool, at date: Date = Date()) {
        dashboardUpdatesPaused = paused
        presentationPausedAt = paused ? date : nil
    }

    mutating func setLogsPresentationPaused(_ paused: Bool, at date: Date = Date()) {
        logsPresentationPaused = paused
        logsPresentationPausedAt = paused ? date : nil
    }

    mutating func recordClosed(_ rows: [ConnectionSnapshot]) {
        closedConnectionBuffer.record(rows)
    }

    mutating func clearClosedConnections() {
        closedConnectionBuffer.removeAll()
    }
}

enum ConnectionSessionTab: String, CaseIterable, Identifiable {
    case active
    case closed

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .active: "traffic.connection_tab_active"
        case .closed: "traffic.connection_tab_closed"
        }
    }
}

enum ProviderSessionKind: String, CaseIterable, Identifiable {
    case all
    case proxy
    case rule

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: "traffic.source_kind_all"
        case .proxy: "traffic.source_kind_proxy"
        case .rule: "traffic.source_kind_rule"
        }
    }

    func matches(_ kind: ProviderKind) -> Bool {
        switch self {
        case .all: true
        case .proxy: kind == .proxy
        case .rule: kind == .rule
        }
    }
}

enum LogSessionLevel: String, CaseIterable, Identifiable {
    case all
    case error
    case warning
    case info
    case debug

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: "traffic.log_level_all"
        case .error: "log_type.error"
        case .warning: "log_type.warning"
        case .info: "log_type.info"
        case .debug: "log_type.debug"
        }
    }

    var upstreamValue: String {
        switch self {
        case .all, .debug: "debug"
        case .error: "error"
        case .warning: "warning"
        case .info: "info"
        }
    }

    var surgeUpstreamValue: String {
        switch self {
        case .all, .debug: "verbose"
        case .error: "error"
        case .warning: "warning"
        case .info: "info"
        }
    }

    func matches(_ type: String) -> Bool {
        switch self {
        case .all: true
        case .error: Self.normalizedType(type) == "error"
        case .warning: Self.normalizedType(type) == "warning"
        case .info: Self.normalizedType(type) == "info"
        case .debug: Self.normalizedType(type) == "debug"
        }
    }

    private static func normalizedType(_ type: String) -> String {
        switch type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "err": "error"
        case "warn": "warning"
        case "information": "info"
        default: type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }
}
