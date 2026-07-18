import Foundation
import MicaCore

struct ConnectionTestReport: Equatable {
    var summary: ControllerHealthSummary
    var headline: String
    var targetURL: String
    var steps: [ConnectionCheckStep]
    var nextStep: String

    static func success(
        draft: RouterDraft,
        version: String,
        language: AppLanguage = MicaStrings.appLanguage
    ) -> ConnectionTestReport {
        ConnectionTestReport(
            summary: .ready,
            headline: MicaStrings.localized("editor.report_ready \(version)", language: language),
            targetURL: draft.visibleControllerTargetLabel(language: language),
            steps: [
                ConnectionCheckStep(id: "url", title: MicaStrings.localized("editor.hs_url", language: language), value: draft.visibleControllerTargetLabel(language: language), state: .ready),
                ConnectionCheckStep(id: "tls", title: MicaStrings.localized("editor.hs_tls", language: language), value: draft.tlsCheckLabel(language: language), state: .ready),
                ConnectionCheckStep(id: "secret", title: MicaStrings.localized("editor.hs_secret", language: language), value: draft.secretCheckLabel(language: language), state: draft.secretCheckState),
                ConnectionCheckStep(id: "json", title: MicaStrings.localized("editor.hs_json", language: language), value: MicaStrings.localized("editor.valid_controller_json", language: language), state: .ready),
                ConnectionCheckStep(id: "version", title: MicaStrings.localized("editor.hs_version", language: language), value: version, state: .ready),
            ],
            nextStep: MicaStrings.localized("action.refresh", language: language)
        )
    }

    static func failure(
        draft: RouterDraft,
        error: Error,
        language: AppLanguage = MicaStrings.appLanguage
    ) -> ConnectionTestReport {
        let diagnosis = ConnectionFailureDiagnosis(error: error, language: language)

        return ConnectionTestReport(
            summary: diagnosis.summary,
            headline: diagnosis.headline,
            targetURL: draft.visibleControllerTargetLabel(language: language),
            steps: [
                ConnectionCheckStep(id: "url", title: MicaStrings.localized("editor.hs_url", language: language), value: draft.visibleControllerTargetLabel(language: language), state: diagnosis.urlState),
                ConnectionCheckStep(id: "tls", title: MicaStrings.localized("editor.hs_tls", language: language), value: draft.tlsCheckLabel(language: language), state: diagnosis.tlsState),
                ConnectionCheckStep(id: "secret", title: MicaStrings.localized("editor.hs_secret", language: language), value: draft.secretCheckLabel(language: language), state: diagnosis.secretState(defaultState: draft.secretCheckState)),
                ConnectionCheckStep(id: "json", title: MicaStrings.localized("editor.hs_json", language: language), value: diagnosis.controllerJSONMessage, state: .failed),
                ConnectionCheckStep(id: "version", title: MicaStrings.localized("editor.hs_version", language: language), value: MicaStrings.localized("editor.unavailable", language: language), state: .failed),
            ],
            nextStep: diagnosis.nextStep
        )
    }

    static func surgeSuccess(
        draft: RouterDraft,
        snapshot: SurgeControlSnapshot,
        language: AppLanguage = MicaStrings.appLanguage
    ) -> ConnectionTestReport {
        ConnectionTestReport(
            summary: .ready,
            headline: MicaStrings.localized("editor.report_surge_ready", language: language),
            targetURL: draft.visibleControllerTargetLabel(language: language),
            steps: [
                ConnectionCheckStep(id: "controller-type", title: MicaStrings.localized("editor.controller_type", language: language), value: MicaStrings.localized("editor.surge_http_api_label", language: language), state: .ready),
                ConnectionCheckStep(id: "platform", title: MicaStrings.localized("editor.platform", language: language), value: snapshot.platform.micaLabel(language: language), state: .ready),
                ConnectionCheckStep(id: "url", title: MicaStrings.localized("editor.hs_url", language: language), value: draft.visibleControllerTargetLabel(language: language), state: .ready),
                ConnectionCheckStep(id: "secret", title: MicaStrings.localized("editor.x_key_label", language: language), value: draft.secretCheckLabel(language: language), state: draft.secretCheckState),
                ConnectionCheckStep(id: "outbound", title: MicaStrings.localized("editor.outbound", language: language), value: MicaStrings.displayMode(snapshot.outboundMode, language: language), state: .ready),
                ConnectionCheckStep(id: "snapshot", title: MicaStrings.localized("editor.snapshot", language: language), value: MicaStrings.localized("editor.surge_snapshot_value \(snapshot.policyGroups.count) \(snapshot.activeRequests.count) \(snapshot.rules.count)", language: language), state: .ready),
            ],
            nextStep: MicaStrings.localized("action.refresh", language: language)
        )
    }

    static func adapterReadiness(
        draft: RouterDraft,
        language: AppLanguage = MicaStrings.appLanguage
    ) -> ConnectionTestReport {
        ConnectionTestReport(
            summary: .partial,
            headline: MicaStrings.localized("editor.report_surge_profile_ready", language: language),
            targetURL: draft.visibleControllerTargetLabel(language: language),
            steps: [
                ConnectionCheckStep(id: "controller-type", title: MicaStrings.localized("editor.controller_type", language: language), value: draft.controllerKind.micaLabel(language: language), state: .ready),
                ConnectionCheckStep(id: "url", title: MicaStrings.localized("editor.hs_url", language: language), value: draft.visibleControllerTargetLabel(language: language), state: .warning),
                ConnectionCheckStep(id: "secret", title: MicaStrings.localized("editor.x_key_label", language: language), value: draft.secretCheckLabel(language: language), state: draft.secretCheckState),
                ConnectionCheckStep(id: "adapter", title: MicaStrings.localized("editor.adapter", language: language), value: MicaStrings.localized("editor.surge_adapter", language: language), state: .ready),
                ConnectionCheckStep(id: "snapshot", title: MicaStrings.localized("editor.snapshot", language: language), value: MicaStrings.localized("editor.run_test_surge_snapshot", language: language), state: .warning),
            ],
            nextStep: MicaStrings.localized("editor.run_test", language: language)
        )
    }
}

struct ConnectionCheckStep: Identifiable, Equatable {
    var id: String
    var title: String
    var value: String
    var state: ConnectionCheckState
}

enum ConnectionCheckState: Equatable {
    case ready
    case warning
    case failed
}

struct BaseControllerProbe {
    var health: ControllerHealthSnapshot
    var responses: BaseControllerResponses?
}

struct BaseControllerResponses {
    var version: VersionResponse
    var config: ConfigResponse
    var proxies: ProxiesResponse
    var connections: ConnectionsResponse
}

private struct ConnectionFailureDiagnosis {
    var summary: ControllerHealthSummary
    var headline: String
    var controllerJSONMessage: String
    var nextStep: String
    var urlState: ConnectionCheckState = .ready
    var tlsState: ConnectionCheckState = .ready
    var secretOverride: ConnectionCheckState?

    init(error: Error, language: AppLanguage) {
        let category = RouterTrialFailureCategory(error: error)

        summary = category.summary
        headline = category.reportHeadline(language: language)
        controllerJSONMessage = category.controllerJSONMessage(language: language)
        nextStep = category.nextStep(language: language)

        switch category {
        case .authFailed:
            secretOverride = .failed
        case .wrongTarget, .malformedJSON, .invalidURL, .dns, .connectionRefused, .timeout, .networkUnavailable, .networkFailed:
            urlState = .failed
        case .tls:
            tlsState = .failed
        case .partialEnhancedSnapshot, .providerUpdateFailed, .unexpectedHTTP:
            urlState = .warning
        case .cancelled, .localFailure:
            break
        }
    }

    func secretState(defaultState: ConnectionCheckState) -> ConnectionCheckState {
        secretOverride ?? defaultState
    }
}

struct ControllerHealthSnapshot: Equatable {
    var summary: ControllerHealthSummary
    var routerName: String
    var checkedAt: Date?
    var endpoints: [ControllerEndpointHealth]

    static var idle: ControllerHealthSnapshot {
        idle(language: MicaStrings.appLanguage)
    }

    static func idle(language: AppLanguage) -> ControllerHealthSnapshot {
        ControllerHealthSnapshot(
            summary: .unknown,
            routerName: MicaStrings.localized("dashboard.no_controller", language: language),
            checkedAt: nil,
            endpoints: ControllerEndpointKind.allCases.map {
                ControllerEndpointHealth(endpoint: $0, status: .idle)
            }
        )
    }

    static func checking(router: RouterProfile) -> ControllerHealthSnapshot {
        ControllerHealthSnapshot(
            summary: .checking,
            routerName: router.displayName,
            checkedAt: nil,
            endpoints: ControllerEndpointKind.allCases.map {
                ControllerEndpointHealth(endpoint: $0, status: .checking)
            }
        )
    }

    static func versionReady(router: RouterProfile, version: String) -> ControllerHealthSnapshot {
        var snapshot = checking(router: router)
        snapshot.set(.version, status: .ready(version))
        for endpoint in ControllerEndpointKind.allCases where endpoint != .version {
            snapshot.set(endpoint, status: .idle)
        }
        snapshot.summary = .ready
        snapshot.checkedAt = Date()
        return snapshot
    }

    var baseEndpoints: [ControllerEndpointHealth] {
        endpoints.filter(\.endpoint.isBase)
    }

    var enhancedEndpoints: [ControllerEndpointHealth] {
        endpoints.filter { !$0.endpoint.isBase }
    }

    var baseDiagnosticsLabel: String {
        baseEndpoints.map { "\($0.endpoint.shortName)=\($0.status.diagnosticsLabel)" }.joined(separator: ", ")
    }

    var enhancedDiagnosticsLabel: String {
        enhancedEndpoints.map { "\($0.endpoint.shortName)=\($0.status.diagnosticsLabel)" }.joined(separator: ", ")
    }

    var failureMessage: String? {
        endpoints.first { $0.status.isFailure }?.status.detail
    }

    func status(for endpoint: ControllerEndpointKind) -> ControllerEndpointStatus {
        endpoints.first { $0.endpoint == endpoint }?.status ?? .idle
    }

    mutating func set<Response>(
        _ endpoint: ControllerEndpointKind,
        result: Result<Response, Error>,
        language: AppLanguage = MicaStrings.appLanguage
    ) {
        switch result {
        case .success:
            set(endpoint, status: .ready(MicaStrings.localized("endpoint.ok", language: language)))
        case .failure(let error):
            set(endpoint, status: .failed(RouterTrialFailureCategory(error: error).shortLabel(language: language)))
        }
    }

    mutating func set(_ endpoint: ControllerEndpointKind, status: ControllerEndpointStatus) {
        guard let index = endpoints.firstIndex(where: { $0.endpoint == endpoint }) else {
            return
        }

        endpoints[index].status = status
    }

    mutating func markBaseFailure(_ error: Error, language: AppLanguage = MicaStrings.appLanguage) {
        let label = RouterTrialFailureCategory(error: error).shortLabel(language: language)
        for endpoint in ControllerEndpointKind.allCases where endpoint.isBase {
            set(endpoint, status: .failed(label))
        }

        for endpoint in ControllerEndpointKind.allCases where !endpoint.isBase {
            set(endpoint, status: .idle)
        }

        summary = ControllerHealthSummary(error: error)
        checkedAt = Date()
    }

    mutating func markVersionFailure(_ error: Error, language: AppLanguage = MicaStrings.appLanguage) {
        set(.version, status: .failed(RouterTrialFailureCategory(error: error).shortLabel(language: language)))

        for endpoint in ControllerEndpointKind.allCases where endpoint != .version {
            set(endpoint, status: .idle)
        }

        summary = ControllerHealthSummary(error: error)
        checkedAt = Date()
    }

    mutating func finalize() {
        checkedAt = Date()

        if let baseFailure = baseEndpoints.first(where: { $0.status.isFailure }) {
            summary = ControllerHealthSummary(endpointStatus: baseFailure.status)
            return
        }

        if enhancedEndpoints.contains(where: { $0.status.isFailure }) {
            summary = .partial
            return
        }

        summary = .ready
    }
}

enum ControllerHealthSummary: Equatable {
    case unknown
    case checking
    case ready
    case partial
    case authFailed
    case wrongTarget
    case offline

    init(error: Error) {
        self = RouterTrialFailureCategory(error: error).summary
    }

    init(endpointStatus: ControllerEndpointStatus) {
        switch endpointStatus {
        case .failed(let message):
            let lowered = message.lowercased()
            if lowered.contains("auth") {
                self = .authFailed
            } else if lowered.contains("json") || lowered.contains("http 404") || lowered.contains("http 405") {
                self = .wrongTarget
            } else {
                self = .offline
            }
        case .idle:
            self = .unknown
        case .checking:
            self = .checking
        case .ready:
            self = .ready
        }
    }

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .unknown:
            MicaStrings.localized("health.unknown", language: language)
        case .checking:
            MicaStrings.localized("health.checking", language: language)
        case .ready:
            MicaStrings.localized("health.ready", language: language)
        case .partial:
            MicaStrings.localized("health.partial", language: language)
        case .authFailed:
            MicaStrings.localized("health.auth_failed", language: language)
        case .wrongTarget:
            MicaStrings.localized("health.wrong_target", language: language)
        case .offline:
            MicaStrings.localized("health.offline", language: language)
        }
    }

    var diagnosticsLabel: String {
        switch self {
        case .unknown:
            "unknown"
        case .checking:
            "checking"
        case .ready:
            "ready"
        case .partial:
            "partial"
        case .authFailed:
            "auth-failed"
        case .wrongTarget:
            "wrong-target"
        case .offline:
            "offline"
        }
    }
}

struct ControllerEndpointHealth: Identifiable, Equatable {
    var id: String { endpoint.rawValue }
    var endpoint: ControllerEndpointKind
    var status: ControllerEndpointStatus
}

enum ControllerEndpointKind: String, CaseIterable, Equatable {
    case version = "/version"
    case configs = "/configs"
    case proxies = "/proxies"
    case connections = "/connections"
    case rules = "/rules"
    case providers = "/providers"

    var apiPath: String {
        rawValue
    }

    var displayTitleKey: String {
        switch self {
        case .version:
            "endpoint.display_version"
        case .configs:
            "endpoint.display_configs"
        case .proxies:
            "endpoint.display_proxies"
        case .connections:
            "endpoint.display_connections"
        case .rules:
            "endpoint.display_rules"
        case .providers:
            "endpoint.display_providers"
        }
    }

    var shortName: String {
        switch self {
        case .version:
            "version"
        case .configs:
            "configs"
        case .proxies:
            "proxies"
        case .connections:
            "connections"
        case .rules:
            "rules"
        case .providers:
            "providers"
        }
    }

    var isBase: Bool {
        switch self {
        case .version, .configs, .proxies, .connections:
            true
        case .rules, .providers:
            false
        }
    }
}

enum ControllerEndpointStatus: Equatable {
    case idle
    case checking
    case ready(String)
    case failed(String)

    var isFailure: Bool {
        if case .failed = self {
            return true
        }

        return false
    }

    var isReady: Bool {
        if case .ready = self {
            return true
        }

        return false
    }

    var isIdle: Bool {
        self == .idle
    }

    var isChecking: Bool {
        self == .checking
    }

    var readyDetail: String? {
        if case .ready(let detail) = self {
            return detail
        }

        return nil
    }

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .idle:
            MicaStrings.localized("endpoint.idle", language: language)
        case .checking:
            MicaStrings.localized("endpoint.checking", language: language)
        case .ready:
            MicaStrings.localized("endpoint.ready", language: language)
        case .failed:
            MicaStrings.localized("endpoint.failed", language: language)
        }
    }

    var detail: String {
        detail(language: MicaStrings.appLanguage)
    }

    func detail(language: AppLanguage) -> String {
        switch self {
        case .idle:
            MicaStrings.localized("endpoint.not_checked", language: language)
        case .checking:
            MicaStrings.localized("endpoint.probe_pending", language: language)
        case .ready(let detail), .failed(let detail):
            detail
        }
    }

    var diagnosticsLabel: String {
        switch self {
        case .idle:
            "idle"
        case .checking:
            "checking"
        case .ready:
            "ready"
        case .failed:
            "failed"
        }
    }
}
