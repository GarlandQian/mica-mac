import Foundation
import MicaCore

enum LiveSessionVisibleDestination: Equatable, Sendable {
    case overview
    case connections
    case logs
    case other

    func observes(_ domain: LiveSessionPublicationDomain) -> Bool {
        switch (self, domain) {
        case (.overview, .traffic), (.overview, .connections), (.overview, .memory):
            true
        case (.connections, .connections), (.logs, .logs):
            true
        case (.overview, .logs), (.connections, .logs), (.connections, .traffic),
             (.connections, .memory), (.logs, .traffic), (.logs, .connections),
             (.logs, .memory), (.other, _):
            false
        }
    }

    var observedDomains: [LiveSessionPublicationDomain] {
        LiveSessionPublicationDomain.allCases.filter { observes($0) }
    }
}

struct LiveSessionWindowDemandID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

enum LiveSessionPublicationDomain: String, CaseIterable, Hashable, Sendable {
    case logs
    case traffic
    case connections
    case memory

    var cadence: Duration {
        switch self {
        case .logs: .milliseconds(200)
        case .traffic: .milliseconds(250)
        case .connections: .milliseconds(500)
        case .memory: .seconds(1)
        }
    }
}

struct LiveSessionPresentationDemand: Equatable, Sendable {
    let identity: LiveSessionRuntimeIdentity
    let revision: UInt64
    let observedDomains: Set<LiveSessionPublicationDomain>
    let presentationPaused: Bool
    let logsPresentationPaused: Bool
    let baselinePublicationRequired: Bool

    func observes(_ domain: LiveSessionPublicationDomain) -> Bool {
        observedDomains.contains(domain)
    }

    func permitsImmediateVisibilityFlush(
        _ domain: LiveSessionPublicationDomain
    ) -> Bool {
        guard observes(domain),
              !presentationPaused,
              !baselinePublicationRequired else {
            return false
        }
        return domain != .logs || !logsPresentationPaused
    }
}

struct LiveSessionWindowDemandChange: Equatable, Sendable {
    let observedDomains: Set<LiveSessionPublicationDomain>
    let newlyObservedDomains: Set<LiveSessionPublicationDomain>
}

struct LiveSessionPublicationCoordinator: Equatable {
    private(set) var generation: UUID?
    private(set) var windowDestinations: [
        LiveSessionWindowDemandID: LiveSessionVisibleDestination
    ] = [:]
    private(set) var demandRevision: UInt64 = 0
    private var rawRevisions: [LiveSessionPublicationDomain: UInt64] = [:]
    private var publishedRevisions: [LiveSessionPublicationDomain: UInt64] = [:]
    private var scheduledTokens: [LiveSessionPublicationDomain: UUID] = [:]

    var observedDomains: Set<LiveSessionPublicationDomain> {
        Self.observedDomains(for: windowDestinations)
    }

    mutating func begin(generation: UUID) {
        let replacesGeneration = self.generation != generation
        self.generation = generation
        if replacesGeneration {
            demandRevision = 0
        }
        rawRevisions = [:]
        publishedRevisions = [:]
        scheduledTokens = [:]
    }

    mutating func invalidate() {
        generation = nil
        demandRevision = 0
        rawRevisions = [:]
        publishedRevisions = [:]
        scheduledTokens = [:]
    }

    mutating func registerWindowDemand(
        _ id: LiveSessionWindowDemandID,
        destination: LiveSessionVisibleDestination
    ) -> LiveSessionWindowDemandChange? {
        replaceWindowDemand(id, destination: destination)
    }

    mutating func updateWindowDemand(
        _ id: LiveSessionWindowDemandID,
        destination: LiveSessionVisibleDestination
    ) -> LiveSessionWindowDemandChange? {
        guard windowDestinations[id] != nil else { return nil }
        return replaceWindowDemand(id, destination: destination)
    }

    mutating func unregisterWindowDemand(
        _ id: LiveSessionWindowDemandID
    ) -> LiveSessionWindowDemandChange? {
        guard windowDestinations[id] != nil else { return nil }
        let previousDomains = observedDomains
        windowDestinations[id] = nil
        return demandChange(from: previousDomains)
    }

    mutating func nextPresentationDemand(
        identity: LiveSessionRuntimeIdentity,
        presentationPaused: Bool,
        logsPresentationPaused: Bool,
        baselinePublicationRequired: Bool
    ) -> LiveSessionPresentationDemand? {
        guard generation == identity.generation else { return nil }
        demandRevision &+= 1
        return LiveSessionPresentationDemand(
            identity: identity,
            revision: demandRevision,
            observedDomains: observedDomains,
            presentationPaused: presentationPaused,
            logsPresentationPaused: logsPresentationPaused,
            baselinePublicationRequired: baselinePublicationRequired
        )
    }

    @discardableResult
    mutating func markDirty(
        _ domain: LiveSessionPublicationDomain,
        generation: UUID
    ) -> UInt64? {
        guard self.generation == generation else { return nil }
        let revision = (rawRevisions[domain] ?? 0) &+ 1
        rawRevisions[domain] = revision
        return revision
    }

    func rawRevision(for domain: LiveSessionPublicationDomain) -> UInt64 {
        rawRevisions[domain] ?? 0
    }

    func publishedRevision(for domain: LiveSessionPublicationDomain) -> UInt64 {
        publishedRevisions[domain] ?? 0
    }

    func needsPublication(
        _ domain: LiveSessionPublicationDomain,
        generation: UUID,
        requireVisibility: Bool = true
    ) -> Bool {
        guard self.generation == generation,
              rawRevision(for: domain) != publishedRevision(for: domain) else {
            return false
        }
        return !requireVisibility || observedDomains.contains(domain)
    }

    mutating func reserveSchedule(
        for domain: LiveSessionPublicationDomain,
        generation: UUID
    ) -> UUID? {
        guard needsPublication(domain, generation: generation),
              scheduledTokens[domain] == nil else {
            return nil
        }
        let token = UUID()
        scheduledTokens[domain] = token
        return token
    }

    mutating func releaseSchedule(
        for domain: LiveSessionPublicationDomain,
        token: UUID,
        generation: UUID
    ) -> Bool {
        guard self.generation == generation,
              scheduledTokens[domain] == token else {
            return false
        }
        scheduledTokens[domain] = nil
        return true
    }

    mutating func markPublished(
        _ domain: LiveSessionPublicationDomain,
        generation: UUID
    ) {
        guard self.generation == generation else { return }
        publishedRevisions[domain] = rawRevision(for: domain)
    }

    private mutating func replaceWindowDemand(
        _ id: LiveSessionWindowDemandID,
        destination: LiveSessionVisibleDestination
    ) -> LiveSessionWindowDemandChange? {
        let previousDomains = observedDomains
        windowDestinations[id] = destination
        return demandChange(from: previousDomains)
    }

    private func demandChange(
        from previousDomains: Set<LiveSessionPublicationDomain>
    ) -> LiveSessionWindowDemandChange? {
        let nextDomains = observedDomains
        guard nextDomains != previousDomains else { return nil }
        return LiveSessionWindowDemandChange(
            observedDomains: nextDomains,
            newlyObservedDomains: nextDomains.subtracting(previousDomains)
        )
    }

    private static func observedDomains(
        for windowDestinations: [
            LiveSessionWindowDemandID: LiveSessionVisibleDestination
        ]
    ) -> Set<LiveSessionPublicationDomain> {
        windowDestinations.values.reduce(
            into: Set<LiveSessionPublicationDomain>()
        ) { domains, destination in
            domains.formUnion(destination.observedDomains)
        }
    }
}

enum LiveSessionEndReason: Equatable, Sendable {
    case sessionEnd
    case controllerSwitch
    case controllerDeletion
    case sleep
}

enum LiveSessionBaselinePhase: Equatable, Sendable {
    case initial
    case reconnect
}

struct LiveSessionBaselineTransaction: Equatable {
    private(set) var generation: UUID?
    private(set) var phase: LiveSessionBaselinePhase?
    private(set) var latestReceivedAt: Date?
    private(set) var surgeSnapshotReceived = false
    private(set) var singBoxConnectionsReceived = false

    var isActive: Bool {
        generation != nil && phase != nil
    }

    var isReconnect: Bool {
        phase == .reconnect
    }

    mutating func begin(
        generation: UUID,
        phase: LiveSessionBaselinePhase,
        receivedAt: Date? = nil
    ) {
        self.generation = generation
        self.phase = phase
        latestReceivedAt = receivedAt
        surgeSnapshotReceived = false
        singBoxConnectionsReceived = false
    }

    mutating func recordReceived(at date: Date) {
        latestReceivedAt = max(latestReceivedAt ?? date, date)
    }

    mutating func recordSingBoxConnections(at date: Date) {
        singBoxConnectionsReceived = true
        recordReceived(at: date)
    }

    mutating func recordSurgeSnapshot(at date: Date) {
        surgeSnapshotReceived = true
        recordReceived(at: date)
    }

    mutating func finish() {
        self = LiveSessionBaselineTransaction()
    }
}

struct MihomoSessionBaseline: Equatable, Sendable {
    var version: VersionResponse
    var config: ConfigResponse
    var proxies: ProxiesResponse
    var connections: ConnectionsResponse
}

enum LiveSessionBaselinePayload: Equatable, Sendable {
    case mihomo(MihomoSessionBaseline)
    case surge(SurgeControlSnapshot)
}

enum SessionRefreshLane: String, CaseIterable, Hashable, Sendable {
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

enum SessionRefreshLaneOutcome: Equatable, Sendable {
    case success
    case partial(String)
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
        lastSuccessAt = max(lastSuccessAt ?? date, date)
        lastFailure = nil
        terminalFailure = false
    }

    mutating func finishPartial(_ message: String, at date: Date) {
        isInFlight = false
        retryAttempt = 0
        lastSuccessAt = max(lastSuccessAt ?? date, date)
        lastFailure = message
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

struct LiveStreamRetryState: Equatable {
    private(set) var attempt = 0
    private(set) var isScheduled = false

    mutating func reserveDelay(
        jitter: Double = Double.random(in: -0.08...0.08)
    ) -> Duration? {
        guard !isScheduled else { return nil }

        let delay = SessionRetryPolicy.delay(forAttempt: attempt, jitter: jitter)
        attempt += 1
        isScheduled = true
        return delay
    }

    mutating func consumeScheduledRetry() {
        isScheduled = false
    }

    mutating func recordSuccess() {
        attempt = 0
    }

    mutating func reset() {
        attempt = 0
        isScheduled = false
    }
}

enum LiveSessionState: Equatable {
    case idle
    case connecting
    case live
    case staleReconnecting(String)
    case partial(String)
    case failedBeforeFirstSnapshot(String)
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
        case .staleReconnecting:
            MicaStrings.localized("operation.live_stream_reconnecting", language: language)
        case .partial:
            MicaStrings.localized("live.state_partial", language: language)
        case .failedBeforeFirstSnapshot:
            MicaStrings.localized("live.state_failed", language: language)
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
        case .staleReconnecting: "stale-reconnecting"
        case .partial: "partial"
        case .failedBeforeFirstSnapshot: "failed-before-first-snapshot"
        case .failed: "failed"
        case .stopped: "stopped"
        }
    }

    var allowsLiveCommands: Bool {
        switch self {
        case .live, .partial:
            true
        case .idle, .connecting, .staleReconnecting, .failedBeforeFirstSnapshot,
             .failed, .stopped:
            false
        }
    }

    var failureDetail: String? {
        switch self {
        case .staleReconnecting(let message), .partial(let message),
             .failedBeforeFirstSnapshot(let message), .failed(let message):
            message
        case .idle, .connecting, .live, .stopped:
            nil
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
    var smartWeights: SmartWeightsResponse?
    var connections: ConnectionsResponse?
    var rules: RulesResponse?
    var proxyProviders: ProxyProvidersResponse?
    var ruleProviders: RuleProvidersResponse?

    mutating func reset() {
        self = SessionEndpointCache()
    }
}

enum MihomoSmartWeightsCacheUpdate: Equatable, Sendable {
    case notReceived
    case replace(SmartWeightsResponse?)
}

struct MihomoEndpointChangePlan: Equatable, Sendable {
    let shouldWriteVersion: Bool
    let shouldWriteConfig: Bool
    let shouldWriteProxies: Bool
    let shouldWriteSmartWeights: Bool
    let shouldWriteRules: Bool
    let shouldWriteProxyProviders: Bool
    let shouldWriteRuleProviders: Bool
    let shouldRebuildUnifiedSnapshot: Bool
    let domains: DashboardPublicationDomains

    var cacheWriteCount: Int {
        [
            shouldWriteVersion,
            shouldWriteConfig,
            shouldWriteProxies,
            shouldWriteSmartWeights,
            shouldWriteRules,
            shouldWriteProxyProviders,
            shouldWriteRuleProviders,
        ].count(where: { $0 })
    }

    var policyGroupProjectionWorkUnits: Int {
        domains.contains(.policyGroups) ? 1 : 0
    }

    static func medium(
        cache: SessionEndpointCache,
        proxies: ProxiesResponse? = nil,
        smartWeights: MihomoSmartWeightsCacheUpdate = .notReceived
    ) -> Self {
        let proxiesChanged = proxies.map { cache.proxies != $0 } ?? false
        let smartWeightsChanged: Bool
        switch smartWeights {
        case .notReceived:
            smartWeightsChanged = false
        case .replace(let next):
            smartWeightsChanged = cache.smartWeights != next
        }

        return Self(
            shouldWriteVersion: false,
            shouldWriteConfig: false,
            shouldWriteProxies: proxiesChanged,
            shouldWriteSmartWeights: smartWeightsChanged,
            shouldWriteRules: false,
            shouldWriteProxyProviders: false,
            shouldWriteRuleProviders: false,
            shouldRebuildUnifiedSnapshot: proxiesChanged,
            domains: proxiesChanged || smartWeightsChanged
                ? [.policyGroups, .insight]
                : []
        )
    }

    static func slow(
        cache: SessionEndpointCache,
        version: VersionResponse?,
        config: ConfigResponse?,
        rules: RulesResponse?,
        proxyProviders: ProxyProvidersResponse?,
        ruleProviders: RuleProvidersResponse?
    ) -> Self {
        let versionChanged = version.map { cache.version != $0 } ?? false
        let configChanged = config.map { cache.config != $0 } ?? false
        let rulesChanged = rules.map { cache.rules != $0 } ?? false
        let proxyProvidersChanged = proxyProviders.map {
            cache.proxyProviders != $0
        } ?? false
        let ruleProvidersChanged = ruleProviders.map {
            cache.ruleProviders != $0
        } ?? false

        var domains: DashboardPublicationDomains = []
        if versionChanged || configChanged {
            domains.insert(.metadata)
        }
        if rulesChanged {
            domains.formUnion([.rules, .insight])
        }
        if proxyProvidersChanged || ruleProvidersChanged {
            domains.formUnion([.providers, .insight])
        }

        return Self(
            shouldWriteVersion: versionChanged,
            shouldWriteConfig: configChanged,
            shouldWriteProxies: false,
            shouldWriteSmartWeights: false,
            shouldWriteRules: rulesChanged,
            shouldWriteProxyProviders: proxyProvidersChanged,
            shouldWriteRuleProviders: ruleProvidersChanged,
            shouldRebuildUnifiedSnapshot: versionChanged
                || configChanged
                || rulesChanged
                || proxyProvidersChanged
                || ruleProvidersChanged,
            domains: domains
        )
    }
}
