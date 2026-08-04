import Foundation
import MicaCore

struct ControllerAdapter: Equatable {
    var requestedKind: ControllerKind
    var detectedKind: ControllerKind
    var source: ControllerAdapterSource
    var confidence: ControllerAdapterConfidence
    var nextSafeAction: String
    var capabilities: [ControllerAdapterCapability]

    var supportedOperationsCount: Int {
        capabilities.filter { $0.status == .supported }.count
    }

    var unavailableOperationsCount: Int {
        capabilities.filter { $0.status == .unavailable || $0.status == .failed }.count
    }

    var unknownOperationsCount: Int {
        capabilities.filter { $0.status == .untested }.count
    }
}

struct ControllerAdapterCapability: Identifiable, Equatable {
    var id: String
    var title: String
    var status: CapabilityStatus
    var evidence: String

    static func defaultRows(
        status: CapabilityStatus,
        evidence: String,
        language: AppLanguage = MicaStrings.appLanguage
    ) -> [ControllerAdapterCapability] {
        [
            ControllerAdapterCapability(id: "test-connection", title: MicaStrings.localized("capability.test_connection", language: language), status: status, evidence: evidence),
            ControllerAdapterCapability(id: "refresh-snapshot", title: MicaStrings.localized("capability.refresh_snapshot", language: language), status: status, evidence: evidence),
            ControllerAdapterCapability(id: "switch-policy", title: MicaStrings.localized("capability.switch_policy", language: language), status: status, evidence: evidence),
            ControllerAdapterCapability(id: "delay-test", title: MicaStrings.localized("capability.delay_test", language: language), status: status, evidence: evidence),
            ControllerAdapterCapability(id: "mode-change", title: MicaStrings.localized("capability.mode_change", language: language), status: status, evidence: evidence),
            ControllerAdapterCapability(id: "close-connection", title: MicaStrings.localized("capability.close_connection", language: language), status: status, evidence: evidence),
            ControllerAdapterCapability(id: "close-all", title: MicaStrings.localized("capability.close_all", language: language), status: status, evidence: evidence),
            ControllerAdapterCapability(id: "provider-update", title: MicaStrings.localized("diagnostics.operation_provider_update", language: language), status: status, evidence: evidence),
            ControllerAdapterCapability(id: "rules-providers", title: MicaStrings.localized("capability.rules_providers", language: language), status: status, evidence: evidence),
            ControllerAdapterCapability(id: "traffic-logs", title: MicaStrings.localized("capability.traffic_logs", language: language), status: status, evidence: evidence),
        ]
    }
}

enum ControllerAdapterSource: String, Equatable {
    case autoProbe
    case mihomoExternalController
    case nikkiExternalController
    case openClashExternalController
    case surgeHTTPAPIAdapter
    case cmfaExternalController
    case stashExternalController
    case singBoxStartedServiceGRPC
    case stashCmfaAdapterUnavailable
    case unknown

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .autoProbe:
            return MicaStrings.localized("adapter.source_auto_probe", language: language)
        case .mihomoExternalController:
            return MicaStrings.localized("adapter.source_mihomo", language: language)
        case .nikkiExternalController:
            return MicaStrings.localized("adapter.source_nikki", language: language)
        case .openClashExternalController:
            return MicaStrings.localized("adapter.source_openclash", language: language)
        case .surgeHTTPAPIAdapter:
            return MicaStrings.localized("adapter.source_surge", language: language)
        case .cmfaExternalController:
            return MicaStrings.localized("adapter.source_cmfa", language: language)
        case .stashExternalController:
            return MicaStrings.localized("adapter.source_stash", language: language)
        case .singBoxStartedServiceGRPC:
            return "sing-box StartedService gRPC"
        case .stashCmfaAdapterUnavailable:
            return MicaStrings.localized("adapter.source_stash_cmfa_unavailable", language: language)
        case .unknown:
            return MicaStrings.localized("adapter.source_unknown", language: language)
        }
    }

    var diagnosticsLabel: String {
        rawValue
    }
}

enum ControllerAdapterConfidence: String, Equatable {
    case configured
    case detected
    case partial
    case unknown
    case unsupported

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .configured:
            return MicaStrings.localized("adapter.confidence_configured", language: language)
        case .detected:
            return MicaStrings.localized("adapter.confidence_detected", language: language)
        case .partial:
            return MicaStrings.localized("adapter.confidence_partial", language: language)
        case .unknown:
            return MicaStrings.localized("adapter.confidence_unknown", language: language)
        case .unsupported:
            return MicaStrings.localized("adapter.confidence_unsupported", language: language)
        }
    }

    var diagnosticsLabel: String {
        rawValue
    }

    var capabilityStatus: CapabilityStatus {
        switch self {
        case .configured, .detected:
            return .supported
        case .partial:
            return .partial
        case .unknown:
            return .untested
        case .unsupported:
            return .unavailable
        }
    }
}

enum LiveStreamState: Equatable {
    case idle
    case connecting
    case live
    case nearLive
    case partial(String)
    case failed(String)
    case unavailable(String)
    case stopped

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .idle:
            MicaStrings.localized("live.state_idle", language: language)
        case .connecting:
            MicaStrings.localized("live.state_connecting", language: language)
        case .live:
            MicaStrings.localized("live.state_live", language: language)
        case .nearLive:
            MicaStrings.localized("live.state_near_live", language: language)
        case .partial:
            MicaStrings.localized("live.state_partial", language: language)
        case .failed:
            MicaStrings.localized("live.state_failed", language: language)
        case .unavailable:
            MicaStrings.localized("live.state_unavailable", language: language)
        case .stopped:
            MicaStrings.localized("live.state_stopped", language: language)
        }
    }

    var detail: String {
        detail(language: MicaStrings.appLanguage)
    }

    func detail(language: AppLanguage) -> String {
        switch self {
        case .idle:
            MicaStrings.localized("live.detail_idle", language: language)
        case .connecting:
            MicaStrings.localized("live.detail_connecting", language: language)
        case .live:
            MicaStrings.localized("live.detail_live", language: language)
        case .nearLive:
            MicaStrings.localized("live.detail_near_live", language: language)
        case .partial(let message), .failed(let message), .unavailable(let message):
            message
        case .stopped:
            MicaStrings.localized("live.detail_stopped", language: language)
        }
    }

    var isPartial: Bool {
        if case .partial = self {
            return true
        }
        return false
    }
}

enum LiveStreamChannel {
    case traffic
    case memory
    case connections
    case logs
    case surgeRefresh
    case singBoxGRPC

    var title: String {
        title(language: MicaStrings.appLanguage)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .traffic:
            MicaStrings.localized("live.channel_traffic", language: language)
        case .memory:
            MicaStrings.localized("diagnostics.operation_memory", language: language)
        case .connections:
            MicaStrings.localized("workbench.connections", language: language)
        case .logs:
            MicaStrings.localized("live.channel_logs", language: language)
        case .surgeRefresh:
            MicaStrings.localized("live.channel_surge_refresh", language: language)
        case .singBoxGRPC:
            MicaStrings.localized("live.channel_sing_box_grpc", language: language)
        }
    }
}

enum SingBoxStartedServiceAdapter {
    static let sourceEvidence = UnifiedControllerAdapterRegistry.adapterSource(for: .singBoxCompatible)

    static func capabilities(
        versionStatus: CapabilityStatus,
        snapshotStatus: CapabilityStatus,
        policyStatus: CapabilityStatus,
        latencyStatus: CapabilityStatus,
        modeStatus: CapabilityStatus,
        closeConnectionStatus: CapabilityStatus,
        closeAllStatus: CapabilityStatus,
        liveStatus: CapabilityStatus,
        language: AppLanguage = MicaStrings.appLanguage
    ) -> [ControllerAdapterCapability] {
        [
            ControllerAdapterCapability(
                id: "test-connection",
                title: MicaStrings.localized("capability.test_connection", language: language),
                status: versionStatus,
                evidence: MicaStrings.localized(
                    "capability.evidence_api_path \("StartedService/GetVersion")",
                    language: language
                )
            ),
            ControllerAdapterCapability(
                id: "refresh-snapshot",
                title: MicaStrings.localized("capability.refresh_snapshot", language: language),
                status: snapshotStatus,
                evidence: MicaStrings.localized(
                    "capability.evidence_api_paths \("StartedService/GetVersion, StartedService/SubscribeStatus, StartedService/SubscribeGroups, StartedService/GetClashModeStatus")",
                    language: language
                )
            ),
            ControllerAdapterCapability(
                id: "switch-policy",
                title: MicaStrings.localized("capability.switch_policy", language: language),
                status: policyStatus,
                evidence: MicaStrings.localized(
                    "capability.evidence_api_path \("StartedService/SelectOutbound")",
                    language: language
                )
            ),
            ControllerAdapterCapability(
                id: "delay-test",
                title: MicaStrings.localized("capability.delay_test", language: language),
                status: latencyStatus,
                evidence: MicaStrings.localized(
                    "capability.evidence_api_path \("StartedService/URLTest")",
                    language: language
                )
            ),
            ControllerAdapterCapability(
                id: "mode-change",
                title: MicaStrings.localized("capability.mode_change", language: language),
                status: modeStatus,
                evidence: MicaStrings.localized(
                    "capability.evidence_api_paths \("StartedService/GetClashModeStatus, StartedService/SubscribeClashMode, StartedService/SetClashMode")",
                    language: language
                )
            ),
            ControllerAdapterCapability(
                id: "close-connection",
                title: MicaStrings.localized("capability.close_connection", language: language),
                status: closeConnectionStatus,
                evidence: MicaStrings.localized(
                    "capability.evidence_api_path \("StartedService/CloseConnection")",
                    language: language
                )
            ),
            ControllerAdapterCapability(
                id: "close-all",
                title: MicaStrings.localized("capability.close_all", language: language),
                status: closeAllStatus,
                evidence: MicaStrings.localized(
                    "capability.evidence_api_path \("StartedService/CloseAllConnections")",
                    language: language
                )
            ),
            ControllerAdapterCapability(
                id: "provider-update",
                title: MicaStrings.localized("diagnostics.operation_provider_update", language: language),
                status: .unavailable,
                evidence: "\(sourceEvidence); capabilities.providerUpdate=false"
            ),
            ControllerAdapterCapability(
                id: "rules-providers",
                title: MicaStrings.localized("capability.rules_providers", language: language),
                status: .unavailable,
                evidence: "\(sourceEvidence); capabilities.rules=false; capabilities.providers=false"
            ),
            ControllerAdapterCapability(
                id: "traffic-logs",
                title: MicaStrings.localized("capability.traffic_logs", language: language),
                status: liveStatus,
                evidence: MicaStrings.localized(
                    "capability.evidence_api_paths \("StartedService/SubscribeStatus, StartedService/SubscribeLog, StartedService/SubscribeConnections")",
                    language: language
                )
            ),
        ]
    }
}

enum SurgeHTTPAPIAdapter {
    static var operationNotice: String {
        operationNotice(language: MicaStrings.appLanguage)
    }

    static func operationNotice(language: AppLanguage) -> String {
        MicaStrings.localized("surge.operation_notice", language: language)
    }

    static func capabilities(
        snapshot: SurgeControlSnapshot,
        health: ControllerHealthSnapshot,
        platform: SurgeControllerPlatform,
        language: AppLanguage = MicaStrings.appLanguage
    ) -> [ControllerAdapterCapability] {
        let readyStatus = status(snapshot: snapshot, health: health)
        let policyStatus: CapabilityStatus = snapshot.policyGroups.isEmpty ? readyStatus.emptyFallback : .supported
        let requestStatus: CapabilityStatus = snapshot.isEmpty ? readyStatus : .supported

        return [
            ControllerAdapterCapability(id: "test-connection", title: MicaStrings.localized("capability.test_connection", language: language), status: readyStatus, evidence: MicaStrings.localized("capability.evidence_surge_test", language: language)),
            ControllerAdapterCapability(id: "refresh-snapshot", title: MicaStrings.localized("capability.refresh_snapshot", language: language), status: readyStatus, evidence: MicaStrings.localized("capability.evidence_surge_snapshot", language: language)),
            ControllerAdapterCapability(id: "outbound-mode", title: MicaStrings.localized("capability.outbound_mode", language: language), status: readyStatus, evidence: MicaStrings.localized("capability.evidence_surge_outbound", language: language)),
            ControllerAdapterCapability(id: "policy-groups", title: MicaStrings.localized("capability.policy_groups", language: language), status: policyStatus, evidence: MicaStrings.localized("capability.evidence_surge_policy_groups \(snapshot.policyGroups.count)", language: language)),
            ControllerAdapterCapability(id: "policy-select", title: MicaStrings.localized("capability.policy_select", language: language), status: policyStatus, evidence: MicaStrings.localized("capability.evidence_surge_policy_select", language: language)),
            ControllerAdapterCapability(id: "policy-test", title: MicaStrings.localized("capability.policy_test", language: language), status: policyStatus, evidence: MicaStrings.localized("capability.evidence_surge_policy_test", language: language)),
            ControllerAdapterCapability(id: "active-requests", title: MicaStrings.localized("capability.active_requests", language: language), status: requestStatus, evidence: MicaStrings.localized("capability.evidence_surge_active_requests \(snapshot.activeRequests.count)", language: language)),
            ControllerAdapterCapability(id: "recent-requests", title: MicaStrings.localized("capability.recent_requests", language: language), status: requestStatus, evidence: MicaStrings.localized("capability.evidence_surge_recent_requests \(snapshot.recentRequests.count)", language: language)),
            ControllerAdapterCapability(id: "kill-request", title: MicaStrings.localized("capability.kill_request", language: language), status: requestStatus, evidence: MicaStrings.localized("capability.evidence_surge_kill_request", language: language)),
            ControllerAdapterCapability(id: "rules-traffic", title: MicaStrings.localized("capability.rules_traffic", language: language), status: readyStatus, evidence: MicaStrings.localized("capability.evidence_surge_rules_traffic \(snapshot.rules.count)", language: language)),
            ControllerAdapterCapability(id: "dns-flush", title: MicaStrings.localized("diagnostics.operation_dns_flush", language: language), status: readyStatus, evidence: MicaStrings.localized("capability.evidence_api_path \("POST /v1/dns/flush")", language: language)),
            ControllerAdapterCapability(id: "platform-scope", title: platform.micaLabel(language: language), status: platformStatus(platform), evidence: platformEvidence(platform, language: language)),
        ]
    }

    private static func status(
        snapshot: SurgeControlSnapshot,
        health: ControllerHealthSnapshot
    ) -> CapabilityStatus {
        switch health.summary {
        case .authFailed, .wrongTarget, .offline:
            return .failed
        case .ready:
            return .supported
        case .partial:
            return .partial
        case .checking, .unknown:
            return snapshot.isEmpty ? .untested : .supported
        }
    }

    private static func platformStatus(_ platform: SurgeControllerPlatform) -> CapabilityStatus {
        switch platform {
        case .macLocal, .remoteMac:
            return .supported
        case .iosReachable:
            return .partial
        }
    }

    private static func platformEvidence(_ platform: SurgeControllerPlatform, language: AppLanguage) -> String {
        switch platform {
        case .macLocal:
            return MicaStrings.localized("surge.platform_evidence_mac_local", language: language)
        case .remoteMac:
            return MicaStrings.localized("surge.platform_evidence_remote_mac", language: language)
        case .iosReachable:
            return MicaStrings.localized("surge.platform_evidence_ios", language: language)
        }
    }
}
