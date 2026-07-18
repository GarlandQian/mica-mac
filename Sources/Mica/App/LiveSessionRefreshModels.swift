import Foundation
import MicaCore

enum SessionRefreshLane: String, CaseIterable, Hashable {
    case fast
    case medium
    case slow

    var interval: Duration {
        switch self {
        case .fast: .seconds(2)
        case .medium: .seconds(5)
        case .slow: .seconds(30)
        }
    }

    var initialOffset: Duration {
        switch self {
        case .fast: .seconds(1)
        case .medium: .seconds(2)
        case .slow: .seconds(4)
        }
    }
}

struct SessionRefreshLaneState: Equatable {
    var isInFlight = false
    var pendingFollowUp = false
    var retryAttempt = 0
    var lastSuccessAt: Date?
    var lastFailure: String?
    var terminalFailure = false

    mutating func begin() -> Bool {
        guard !isInFlight else {
            pendingFollowUp = true
            return false
        }

        isInFlight = true
        return true
    }

    mutating func finishSuccess(at date: Date) {
        isInFlight = false
        retryAttempt = 0
        lastSuccessAt = date
        lastFailure = nil
        terminalFailure = false
    }

    mutating func finishFailure(_ message: String, disposition: RouterRetryDisposition) {
        isInFlight = false
        lastFailure = message

        switch disposition {
        case .terminal, .cancelled:
            terminalFailure = true
        case .transient, .retryOnce:
            retryAttempt += 1
        }
    }

    mutating func consumeFollowUp() -> Bool {
        defer { pendingFollowUp = false }
        return pendingFollowUp
    }
}

enum SessionRetryPolicy {
    static let delays: [TimeInterval] = [2, 4, 8, 15, 30]

    static func delay(
        forAttempt attempt: Int,
        jitter: Double = Double.random(in: -0.08...0.08)
    ) -> Duration {
        let base = delays[min(max(attempt, 0), delays.count - 1)]
        let boundedJitter = min(max(jitter, -0.2), 0.2)
        return .milliseconds(Int64((base * (1 + boundedJitter) * 1_000).rounded()))
    }
}

enum LiveSessionState: Equatable {
    case idle
    case connecting
    case live
    case partial(String)
    case failed(String)
    case stopped

    func label(language: AppLanguage) -> String {
        switch self {
        case .idle:
            MicaStrings.localized("live.state_idle", language: language)
        case .connecting:
            MicaStrings.localized("live.state_connecting", language: language)
        case .live:
            MicaStrings.localized("live.state_live", language: language)
        case .partial:
            MicaStrings.localized("live.state_partial", language: language)
        case .failed:
            MicaStrings.localized("live.state_failed", language: language)
        case .stopped:
            MicaStrings.localized("live.state_stopped", language: language)
        }
    }

    var diagnosticsLabel: String {
        switch self {
        case .idle: "idle"
        case .connecting: "connecting"
        case .live: "live"
        case .partial: "partial"
        case .failed: "failed"
        case .stopped: "stopped"
        }
    }

    var failureDetail: String? {
        switch self {
        case .partial(let message), .failed(let message): message
        case .idle, .connecting, .live, .stopped: nil
        }
    }
}

struct PendingSessionPresentation: Equatable {
    var dashboard: DashboardSnapshot?
    var unifiedSnapshot: UnifiedControllerSnapshot?
    var surgeSnapshot: SurgeControlSnapshot?
    var controllerHealth: ControllerHealthSnapshot?
    var connectionState: ConnectionState?
    var rulesSnapshotState: EnhancedSnapshotState?
    var providersSnapshotState: EnhancedSnapshotState?
    var memory: MemoryResponse?
    var closedConnections = ClosedConnectionBuffer()
    var clearClosedConnections = false

    var isEmpty: Bool {
        dashboard == nil
            && unifiedSnapshot == nil
            && surgeSnapshot == nil
            && controllerHealth == nil
            && connectionState == nil
            && rulesSnapshotState == nil
            && providersSnapshotState == nil
            && memory == nil
            && closedConnections.entries.isEmpty
            && !clearClosedConnections
    }

    mutating func reset() {
        self = PendingSessionPresentation()
    }
}

struct SessionEndpointCache: Equatable {
    var version: VersionResponse?
    var config: ConfigResponse?
    var proxies: ProxiesResponse?
    var connections: ConnectionsResponse?
    var rules: RulesResponse?
    var proxyProviders: ProxyProvidersResponse?
    var ruleProviders: RuleProvidersResponse?

    mutating func reset() {
        self = SessionEndpointCache()
    }
}
