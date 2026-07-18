import Foundation

public enum UnifiedControllerType: String, Codable, CaseIterable, Sendable {
    case mihomoCompatible
    case surgeHTTPAPI
    case openClashMihomoCompatible
    case nikkiMihomoCompatible
    case singBoxCompatible
    case cmfaCompatible
    case stashCompatible
    case stashCmfaCompatible
    case smartProbe
    case unknown
    case unsupported

    public init(kind: ControllerKind) {
        switch kind {
        case .mihomoCompatible:
            self = .mihomoCompatible
        case .surgeCompatible:
            self = .surgeHTTPAPI
        case .openClashMihomoCompatible:
            self = .openClashMihomoCompatible
        case .nikkiMihomoCompatible:
            self = .nikkiMihomoCompatible
        case .singBoxCompatible:
            self = .singBoxCompatible
        case .cmfaCompatible:
            self = .cmfaCompatible
        case .stashCompatible:
            self = .stashCompatible
        case .stashCmfaCompatible:
            self = .stashCmfaCompatible
        case .autoDetect:
            self = .smartProbe
        case .unknown:
            self = .unknown
        case .unsupported:
            self = .unsupported
        }
    }

    public var label: String {
        switch self {
        case .mihomoCompatible:
            return "mihomo-compatible"
        case .surgeHTTPAPI:
            return "Surge HTTP API"
        case .openClashMihomoCompatible:
            return "OpenClash external-controller"
        case .nikkiMihomoCompatible:
            return "Nikki external-controller"
        case .singBoxCompatible:
            return "sing-box API"
        case .cmfaCompatible:
            return "CMFA external-controller"
        case .stashCompatible:
            return "Stash external-controller"
        case .stashCmfaCompatible:
            return "Stash / CMFA API"
        case .smartProbe:
            return "Smart probe"
        case .unknown:
            return "Unknown"
        case .unsupported:
            return "Unsupported"
        }
    }

    public var badge: String {
        switch self {
        case .mihomoCompatible:
            return "MHM"
        case .surgeHTTPAPI:
            return "SURGE"
        case .openClashMihomoCompatible:
            return "OCL"
        case .nikkiMihomoCompatible:
            return "NIKKI"
        case .singBoxCompatible:
            return "SBOX"
        case .cmfaCompatible:
            return "CMFA"
        case .stashCompatible:
            return "STASH"
        case .stashCmfaCompatible:
            return "CMFA"
        case .smartProbe:
            return "SMART"
        case .unknown:
            return "UNK"
        case .unsupported:
            return "NO"
        }
    }

    public var isCapabilityProbeOnly: Bool {
        switch self {
        case .smartProbe:
            return true
        case .mihomoCompatible, .surgeHTTPAPI, .openClashMihomoCompatible, .nikkiMihomoCompatible, .singBoxCompatible, .cmfaCompatible, .stashCompatible, .stashCmfaCompatible, .unknown, .unsupported:
            return false
        }
    }

    public var boundarySummary: String {
        switch self {
        case .mihomoCompatible:
            return "mihomo-compatible external-controller operations are available when endpoint probes pass."
        case .surgeHTTPAPI:
            return "Surge operations use only the user-enabled HTTP API and X-Key."
        case .openClashMihomoCompatible:
            return "OpenClash uses its already-enabled Clash/mihomo-compatible external-controller; LuCI, SSH, ubus, service, and firewall management stay outside Mica."
        case .nikkiMihomoCompatible:
            return "Nikki uses its mihomo-compatible external-controller; OpenWrt runtime, mixin, service, and file management stay outside Mica."
        case .singBoxCompatible:
            return "sing-box uses the remote StartedService gRPC API over HTTP/2; Mica does not manage a local core."
        case .cmfaCompatible:
            return "CMFA uses its Clash-compatible remote controller; cache and memory operations remain available, while runtime configuration and core management stay unavailable."
        case .stashCompatible:
            return "Stash uses its Clash-compatible remote controller with Stash-specific configuration and capability limits."
        case .stashCmfaCompatible:
            return "The saved Stash / CMFA hint is resolved to a concrete runtime variant before remote operations are enabled."
        case .smartProbe:
            return "Smart probing is readiness-only until a compatible remote controller is detected; Mica does not download, bundle, or run a local core."
        case .unknown:
            return "Run Test Connection to identify the remote controller before enabling operations."
        case .unsupported:
            return "This controller type has no supported remote operation path in Mica."
        }
    }
}

public enum UnifiedControllerAction: String, Codable, CaseIterable, Sendable {
    case testConnection
    case refreshSnapshot
    case reloadRules
    case setRuleDisabled
    case reloadProviders
    case switchPolicy
    case clearFixedSelection
    case testLatency
    case changeMode
    case closeConnection
    case closeAllConnections
    case updateProvider
    case healthCheckProvider
    case reloadConfiguration
    case updateGeoData
    case dnsFlush
    case flushFakeIP
    case reloadProfile
    case setLogLevel
    case setAllowLAN
    case setIPv6
    case setTCPConcurrent
    case setTUN
    case setPort
    case setOutboundMode
    case selectSurgePolicy
    case testSurgePolicy
    case killActiveRequest
    case copyDiagnostics

    public var label: String {
        switch self {
        case .testConnection:
            return "Test Connection"
        case .refreshSnapshot:
            return "Refresh Snapshot"
        case .reloadRules:
            return "Reload Rules"
        case .setRuleDisabled:
            return "Set Rule Enabled State"
        case .reloadProviders:
            return "Reload Providers"
        case .switchPolicy:
            return "Proxy Group Switch"
        case .clearFixedSelection:
            return "Clear Fixed Selection"
        case .testLatency:
            return "Delay Test"
        case .changeMode:
            return "Mode Change"
        case .closeConnection:
            return "Close Connection"
        case .closeAllConnections:
            return "Close All Connections"
        case .updateProvider:
            return "Provider Update"
        case .healthCheckProvider:
            return "Provider Health Check"
        case .reloadConfiguration:
            return "Reload Configuration"
        case .updateGeoData:
            return "Update GeoData"
        case .dnsFlush:
            return "DNS Flush"
        case .flushFakeIP:
            return "FakeIP Flush"
        case .reloadProfile:
            return "Reload Surge Profile"
        case .setLogLevel:
            return "Set Controller Log Level"
        case .setAllowLAN:
            return "Set LAN Access"
        case .setIPv6:
            return "Set IPv6"
        case .setTCPConcurrent:
            return "Set TCP Concurrent"
        case .setTUN:
            return "Set TUN"
        case .setPort:
            return "Set Controller Port"
        case .setOutboundMode:
            return "Surge Outbound Mode"
        case .selectSurgePolicy:
            return "Surge Policy Selection"
        case .testSurgePolicy:
            return "Surge Policy Test"
        case .killActiveRequest:
            return "Surge Kill Active Request"
        case .copyDiagnostics:
            return "Copy Diagnostics"
        }
    }
}

public struct ControllerCapabilities: Codable, Equatable, Sendable {
    public var snapshot: Bool
    public var rules: Bool
    public var providers: Bool
    public var policyGroups: Bool
    public var fixedSelectionClear: Bool
    public var connections: Bool
    public var activeRequests: Bool
    public var traffic: Bool
    public var logs: Bool
    public var memory: Bool
    public var modeChange: Bool
    public var outboundMode: Bool
    public var providerUpdate: Bool
    public var providerHealthCheck: Bool
    public var configurationReload: Bool
    public var geoDataUpdate: Bool
    public var dnsFlush: Bool
    public var fakeIPFlush: Bool
    public var profileReload: Bool
    public var logLevelChange: Bool
    public var allowLANChange: Bool
    public var ipv6Change: Bool
    public var tcpConcurrentChange: Bool
    public var tunChange: Bool
    public var portChange: Bool
    public var latencyTest: Bool
    public var killConnection: Bool

    public init(
        snapshot: Bool,
        rules: Bool,
        providers: Bool,
        policyGroups: Bool,
        fixedSelectionClear: Bool,
        connections: Bool,
        activeRequests: Bool,
        traffic: Bool,
        logs: Bool,
        memory: Bool,
        modeChange: Bool,
        outboundMode: Bool,
        providerUpdate: Bool,
        providerHealthCheck: Bool,
        configurationReload: Bool,
        geoDataUpdate: Bool,
        dnsFlush: Bool,
        fakeIPFlush: Bool,
        profileReload: Bool,
        logLevelChange: Bool,
        allowLANChange: Bool,
        ipv6Change: Bool,
        tcpConcurrentChange: Bool,
        tunChange: Bool,
        portChange: Bool,
        latencyTest: Bool,
        killConnection: Bool
    ) {
        self.snapshot = snapshot
        self.rules = rules
        self.providers = providers
        self.policyGroups = policyGroups
        self.fixedSelectionClear = fixedSelectionClear
        self.connections = connections
        self.activeRequests = activeRequests
        self.traffic = traffic
        self.logs = logs
        self.memory = memory
        self.modeChange = modeChange
        self.outboundMode = outboundMode
        self.providerUpdate = providerUpdate
        self.providerHealthCheck = providerHealthCheck
        self.configurationReload = configurationReload
        self.geoDataUpdate = geoDataUpdate
        self.dnsFlush = dnsFlush
        self.fakeIPFlush = fakeIPFlush
        self.profileReload = profileReload
        self.logLevelChange = logLevelChange
        self.allowLANChange = allowLANChange
        self.ipv6Change = ipv6Change
        self.tcpConcurrentChange = tcpConcurrentChange
        self.tunChange = tunChange
        self.portChange = portChange
        self.latencyTest = latencyTest
        self.killConnection = killConnection
    }

    public static let none = ControllerCapabilities(
        snapshot: false,
        rules: false,
        providers: false,
        policyGroups: false,
        fixedSelectionClear: false,
        connections: false,
        activeRequests: false,
        traffic: false,
        logs: false,
        memory: false,
        modeChange: false,
        outboundMode: false,
        providerUpdate: false,
        providerHealthCheck: false,
        configurationReload: false,
        geoDataUpdate: false,
        dnsFlush: false,
        fakeIPFlush: false,
        profileReload: false,
        logLevelChange: false,
        allowLANChange: false,
        ipv6Change: false,
        tcpConcurrentChange: false,
        tunChange: false,
        portChange: false,
        latencyTest: false,
        killConnection: false
    )

    public static let mihomoCompatible = ControllerCapabilities(
        snapshot: true,
        rules: true,
        providers: true,
        policyGroups: true,
        fixedSelectionClear: true,
        connections: true,
        activeRequests: false,
        traffic: true,
        logs: true,
        memory: true,
        modeChange: true,
        outboundMode: false,
        providerUpdate: true,
        providerHealthCheck: true,
        configurationReload: true,
        geoDataUpdate: true,
        dnsFlush: true,
        fakeIPFlush: true,
        profileReload: false,
        logLevelChange: true,
        allowLANChange: true,
        ipv6Change: true,
        tcpConcurrentChange: true,
        tunChange: true,
        portChange: true,
        latencyTest: true,
        killConnection: true
    )

    public static let cmfaCompatible = ControllerCapabilities(
        snapshot: true,
        rules: true,
        providers: true,
        policyGroups: true,
        fixedSelectionClear: true,
        connections: true,
        activeRequests: false,
        traffic: true,
        logs: true,
        memory: true,
        modeChange: false,
        outboundMode: false,
        providerUpdate: true,
        providerHealthCheck: true,
        configurationReload: false,
        geoDataUpdate: false,
        dnsFlush: true,
        fakeIPFlush: true,
        profileReload: false,
        logLevelChange: false,
        allowLANChange: false,
        ipv6Change: false,
        tcpConcurrentChange: false,
        tunChange: false,
        portChange: false,
        latencyTest: true,
        killConnection: true
    )

    public static let stashCompatible = ControllerCapabilities(
        snapshot: true,
        rules: true,
        providers: true,
        policyGroups: true,
        fixedSelectionClear: true,
        connections: true,
        activeRequests: false,
        traffic: true,
        logs: true,
        memory: false,
        modeChange: true,
        outboundMode: false,
        providerUpdate: true,
        providerHealthCheck: true,
        configurationReload: false,
        geoDataUpdate: false,
        dnsFlush: false,
        fakeIPFlush: false,
        profileReload: false,
        logLevelChange: true,
        allowLANChange: false,
        ipv6Change: false,
        tcpConcurrentChange: false,
        tunChange: false,
        portChange: true,
        latencyTest: true,
        killConnection: true
    )

    public static let singBoxCompatible = ControllerCapabilities(
        snapshot: true,
        rules: false,
        providers: false,
        policyGroups: true,
        fixedSelectionClear: false,
        connections: true,
        activeRequests: false,
        traffic: true,
        logs: true,
        memory: true,
        modeChange: true,
        outboundMode: false,
        providerUpdate: false,
        providerHealthCheck: false,
        configurationReload: false,
        geoDataUpdate: false,
        dnsFlush: false,
        fakeIPFlush: false,
        profileReload: false,
        logLevelChange: false,
        allowLANChange: false,
        ipv6Change: false,
        tcpConcurrentChange: false,
        tunChange: false,
        portChange: false,
        latencyTest: true,
        killConnection: true
    )

    public static let surgeHTTPAPI = ControllerCapabilities(
        snapshot: true,
        rules: true,
        providers: false,
        policyGroups: true,
        fixedSelectionClear: false,
        connections: false,
        activeRequests: true,
        traffic: true,
        logs: true,
        memory: false,
        modeChange: false,
        outboundMode: true,
        providerUpdate: false,
        providerHealthCheck: false,
        configurationReload: false,
        geoDataUpdate: false,
        dnsFlush: true,
        fakeIPFlush: false,
        profileReload: true,
        logLevelChange: true,
        allowLANChange: false,
        ipv6Change: false,
        tcpConcurrentChange: false,
        tunChange: false,
        portChange: false,
        latencyTest: true,
        killConnection: true
    )

    public static let probeReadiness = ControllerCapabilities(
        snapshot: true,
        rules: false,
        providers: false,
        policyGroups: false,
        fixedSelectionClear: false,
        connections: false,
        activeRequests: false,
        traffic: false,
        logs: false,
        memory: false,
        modeChange: false,
        outboundMode: false,
        providerUpdate: false,
        providerHealthCheck: false,
        configurationReload: false,
        geoDataUpdate: false,
        dnsFlush: false,
        fakeIPFlush: false,
        profileReload: false,
        logLevelChange: false,
        allowLANChange: false,
        ipv6Change: false,
        tcpConcurrentChange: false,
        tunChange: false,
        portChange: false,
        latencyTest: false,
        killConnection: false
    )

    public var supportedCount: Int {
        [
            snapshot,
            rules,
            providers,
            policyGroups,
            fixedSelectionClear,
            connections,
            activeRequests,
            traffic,
            logs,
            memory,
            modeChange,
            outboundMode,
            providerUpdate,
            providerHealthCheck,
            configurationReload,
            geoDataUpdate,
            dnsFlush,
            fakeIPFlush,
            profileReload,
            logLevelChange,
            allowLANChange,
            ipv6Change,
            tcpConcurrentChange,
            tunChange,
            portChange,
            latencyTest,
            killConnection,
        ].filter { $0 }.count
    }

    public func supports(_ action: UnifiedControllerAction) -> Bool {
        switch action {
        case .testConnection:
            return snapshot
        case .refreshSnapshot:
            return snapshot
        case .reloadRules:
            return rules
        case .setRuleDisabled:
            return rules && !outboundMode
        case .reloadProviders:
            return providers
        case .switchPolicy:
            return policyGroups && !outboundMode
        case .clearFixedSelection:
            return policyGroups && fixedSelectionClear
        case .testLatency:
            return policyGroups && latencyTest && !outboundMode
        case .changeMode:
            return modeChange
        case .closeConnection, .closeAllConnections:
            return connections && killConnection
        case .updateProvider:
            return providers && providerUpdate
        case .healthCheckProvider:
            return providers && providerHealthCheck
        case .reloadConfiguration:
            return configurationReload
        case .updateGeoData:
            return geoDataUpdate
        case .dnsFlush:
            return dnsFlush
        case .flushFakeIP:
            return fakeIPFlush
        case .reloadProfile:
            return profileReload
        case .setLogLevel:
            return logLevelChange
        case .setAllowLAN:
            return allowLANChange
        case .setIPv6:
            return ipv6Change
        case .setTCPConcurrent:
            return tcpConcurrentChange
        case .setTUN:
            return tunChange
        case .setPort:
            return portChange
        case .setOutboundMode:
            return outboundMode
        case .selectSurgePolicy:
            return policyGroups && outboundMode
        case .testSurgePolicy:
            return policyGroups && latencyTest && outboundMode
        case .killActiveRequest:
            return activeRequests && killConnection
        case .copyDiagnostics:
            return true
        }
    }

    public var diagnosticsLabel: String {
        [
            "snapshot=\(snapshot)",
            "rules=\(rules)",
            "providers=\(providers)",
            "policy-groups=\(policyGroups)",
            "fixed-selection-clear=\(fixedSelectionClear)",
            "connections=\(connections)",
            "active-requests=\(activeRequests)",
            "traffic=\(traffic)",
            "logs=\(logs)",
            "memory=\(memory)",
            "mode-change=\(modeChange)",
            "outbound-mode=\(outboundMode)",
            "provider-update=\(providerUpdate)",
            "provider-health-check=\(providerHealthCheck)",
            "configuration-reload=\(configurationReload)",
            "geo-data-update=\(geoDataUpdate)",
            "dns-flush=\(dnsFlush)",
            "fakeip-flush=\(fakeIPFlush)",
            "profile-reload=\(profileReload)",
            "log-level-change=\(logLevelChange)",
            "allow-lan-change=\(allowLANChange)",
            "ipv6-change=\(ipv6Change)",
            "tcp-concurrent-change=\(tcpConcurrentChange)",
            "tun-change=\(tunChange)",
            "port-change=\(portChange)",
            "latency-test=\(latencyTest)",
            "kill-connection=\(killConnection)",
        ].joined(separator: ", ")
    }
}

public enum UnifiedControllerHealthState: String, Codable, Sendable {
    case ready
    case partial
    case authFailed
    case wrongTarget
    case offline
    case checking
    case unknown
    case unavailable
}

public enum UnifiedControllerEndpoint: String, Codable, CaseIterable, Sendable {
    case version
    case configs
    case proxies
    case connections
    case rules
    case providers
    case surgeEvents
    case surgeOutbound
    case surgePolicyGroups
    case surgeActiveRequests
    case surgeTraffic
    case surgeDNSCache
    case singBoxVersion
    case singBoxStatus
    case singBoxGroups
    case singBoxMode
    case singBoxConnections
    case singBoxLogs
    case singBoxTailscale
}

public struct UnifiedControllerEndpointStatus: Codable, Equatable, Sendable, Identifiable {
    public var id: String { endpoint.rawValue }
    public var endpoint: UnifiedControllerEndpoint
    public var state: UnifiedControllerHealthState
    public var safeDetail: String

    public init(
        endpoint: UnifiedControllerEndpoint,
        state: UnifiedControllerHealthState,
        safeDetail: String
    ) {
        self.endpoint = endpoint
        self.state = state
        self.safeDetail = safeDetail
    }
}

public struct UnifiedControllerHealth: Codable, Equatable, Sendable {
    public var state: UnifiedControllerHealthState
    public var checkedAt: Date?
    public var endpointStatuses: [UnifiedControllerEndpointStatus]
    public var safeSummary: String

    public init(
        state: UnifiedControllerHealthState = .unknown,
        checkedAt: Date? = nil,
        endpointStatuses: [UnifiedControllerEndpointStatus] = [],
        safeSummary: String = "not-checked"
    ) {
        self.state = state
        self.checkedAt = checkedAt
        self.endpointStatuses = endpointStatuses
        self.safeSummary = safeSummary
    }

    public static let empty = UnifiedControllerHealth()

    public static func unavailable(reason: String) -> UnifiedControllerHealth {
        UnifiedControllerHealth(
            state: .unavailable,
            checkedAt: Date(),
            endpointStatuses: [],
            safeSummary: reason
        )
    }

    public var diagnosticsLabel: String {
        let endpoints = endpointStatuses
            .map { "\($0.endpoint.rawValue)=\($0.state.rawValue)" }
            .joined(separator: ", ")

        if endpoints.isEmpty {
            return "state=\(state.rawValue); summary=\(safeSummary)"
        }

        return "state=\(state.rawValue); summary=\(safeSummary); endpoints=[\(endpoints)]"
    }
}

public struct UnifiedTrafficSnapshot: Codable, Equatable, Sendable {
    public var upload: Int
    public var download: Int

    public init(upload: Int = 0, download: Int = 0) {
        self.upload = upload
        self.download = download
    }
}

public struct UnifiedPolicyGroupSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayLabel: String
    public var selectedDisplayLabel: String?
    public var optionCount: Int
    public var latencyBuckets: [String: Int]

    public init(
        id: String,
        displayLabel: String,
        selectedDisplayLabel: String? = nil,
        optionCount: Int,
        latencyBuckets: [String: Int] = [:]
    ) {
        self.id = id
        self.displayLabel = displayLabel
        self.selectedDisplayLabel = selectedDisplayLabel
        self.optionCount = optionCount
        self.latencyBuckets = latencyBuckets
    }
}

public struct UnifiedControllerSnapshot: Codable, Equatable, Sendable {
    public var controllerType: UnifiedControllerType
    public var adapterSource: String
    public var capabilities: ControllerCapabilities
    public var health: UnifiedControllerHealth
    public var checkedAt: Date?
    public var versionLabel: String
    public var modeLabel: String
    public var traffic: UnifiedTrafficSnapshot
    public var policyGroups: [UnifiedPolicyGroupSnapshot]
    public var rulesCount: Int
    public var providersCount: Int
    public var connectionsCount: Int
    public var isPartial: Bool
    public var unavailableReason: String?

    public init(
        controllerType: UnifiedControllerType = .unknown,
        adapterSource: String = "unknown",
        capabilities: ControllerCapabilities = .none,
        health: UnifiedControllerHealth = .empty,
        checkedAt: Date? = nil,
        versionLabel: String = "Not Loaded",
        modeLabel: String = "Unknown",
        traffic: UnifiedTrafficSnapshot = UnifiedTrafficSnapshot(),
        policyGroups: [UnifiedPolicyGroupSnapshot] = [],
        rulesCount: Int = 0,
        providersCount: Int = 0,
        connectionsCount: Int = 0,
        isPartial: Bool = false,
        unavailableReason: String? = nil
    ) {
        self.controllerType = controllerType
        self.adapterSource = adapterSource
        self.capabilities = capabilities
        self.health = health
        self.checkedAt = checkedAt
        self.versionLabel = versionLabel
        self.modeLabel = modeLabel
        self.traffic = traffic
        self.policyGroups = policyGroups
        self.rulesCount = rulesCount
        self.providersCount = providersCount
        self.connectionsCount = connectionsCount
        self.isPartial = isPartial
        self.unavailableReason = unavailableReason
    }

    public static let empty = UnifiedControllerSnapshot()

    public var diagnosticsSummary: String {
        [
            "type=\(controllerType.rawValue)",
            "source=\(adapterSource)",
            "health=\(health.state.rawValue)",
            "partial=\(isPartial)",
            "version=\(versionLabel)",
            "mode=\(modeLabel)",
            "policy-groups=\(policyGroups.count)",
            "connections=\(connectionsCount)",
            "rules=\(rulesCount)",
            "providers=\(providersCount)",
            "traffic-upload=\(traffic.upload)",
            "traffic-download=\(traffic.download)",
            "capabilities-supported=\(capabilities.supportedCount)",
        ].joined(separator: "; ")
    }
}

public protocol ControllerAdapterProtocol: Sendable {
    var profile: RouterProfile { get }
    var controllerType: UnifiedControllerType { get }
    var capabilities: ControllerCapabilities { get }

    func testConnection() async throws -> UnifiedControllerHealth
    func snapshot() async throws -> UnifiedControllerSnapshot
}

public struct UnifiedControllerAdapterRegistry: Sendable {
    public static func controllerType(for profile: RouterProfile) -> UnifiedControllerType {
        profile.unifiedControllerType
    }

    public static func capabilities(for profile: RouterProfile) -> ControllerCapabilities {
        capabilities(for: profile.unifiedControllerType)
    }

    public static func capabilities(for type: UnifiedControllerType) -> ControllerCapabilities {
        switch type {
        case .mihomoCompatible, .openClashMihomoCompatible, .nikkiMihomoCompatible:
            return .mihomoCompatible
        case .cmfaCompatible:
            return .cmfaCompatible
        case .stashCompatible:
            return .stashCompatible
        case .surgeHTTPAPI:
            return .surgeHTTPAPI
        case .singBoxCompatible:
            return .singBoxCompatible
        case .stashCmfaCompatible:
            return .none
        case .smartProbe:
            return .probeReadiness
        case .unknown, .unsupported:
            return .none
        }
    }

    public static func adapterSource(for type: UnifiedControllerType) -> String {
        switch type {
        case .mihomoCompatible:
            return "mihomo-compatible-external-controller"
        case .surgeHTTPAPI:
            return "surge-http-api-x-key"
        case .openClashMihomoCompatible:
            return "openclash-mihomo-compatible-external-controller"
        case .nikkiMihomoCompatible:
            return "nikki-mihomo-compatible-external-controller"
        case .singBoxCompatible:
            return "sing-box-started-service-grpc"
        case .cmfaCompatible:
            return "cmfa-clash-compatible-external-controller"
        case .stashCompatible:
            return "stash-clash-compatible-external-controller"
        case .stashCmfaCompatible:
            return "stash-cmfa-api-unavailable"
        case .smartProbe:
            return "smart-capability-probe"
        case .unknown:
            return "unknown"
        case .unsupported:
            return "unsupported"
        }
    }

    public static func unavailableSnapshot(profile: RouterProfile, reason: String) -> UnifiedControllerSnapshot {
        let type = profile.unifiedControllerType
        return UnifiedControllerSnapshot(
            controllerType: type,
            adapterSource: adapterSource(for: type),
            capabilities: capabilities(for: type),
            health: .unavailable(reason: reason),
            checkedAt: Date(),
            versionLabel: type.label,
            modeLabel: "Unavailable",
            isPartial: true,
            unavailableReason: reason
        )
    }
}

public extension RouterProfile {
    var controllerType: UnifiedControllerType {
        unifiedControllerType
    }

    var unifiedControllerType: UnifiedControllerType {
        UnifiedControllerType(kind: controllerKind)
    }

    var controllerCredentialLabel: String {
        unifiedControllerType == .surgeHTTPAPI ? "X-Key/API Key" : "external-controller secret"
    }
}
