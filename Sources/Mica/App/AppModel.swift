import AppKit
import Foundation
import MicaCore
import SwiftUI

struct PolicyNodeLatencyTestTarget: Equatable, Sendable {
    var groupID: String
    var nodeName: String
}

typealias ControllerProbeOperation = @Sendable (
    _ profile: RouterProfile,
    _ credential: String?,
    _ includeSurge: Bool
) async throws -> ControllerKind

typealias ControllerProbeSleepOperation = @Sendable (_ attempt: Int) async throws -> Void

typealias LiveSessionPublicationSleepOperation = @Sendable (
    _ domain: LiveSessionPublicationDomain,
    _ cadence: Duration
) async throws -> Void

typealias LiveSessionBaselineLoadOperation = @Sendable (
    _ profile: RouterProfile,
    _ credential: String?,
    _ resolvedKind: ControllerKind
) async throws -> LiveSessionBaselinePayload

enum ControllerConnectionTestResult: Equatable, Sendable {
    case mihomo(VersionResponse)
    case surge(SurgeControlSnapshot)
    case singBox(SingBoxVersion)
}

typealias ControllerConnectionTestOperation = @Sendable (
    _ profile: RouterProfile,
    _ credential: String?,
    _ resolvedKind: ControllerKind
) async throws -> ControllerConnectionTestResult

typealias ProviderUpdateOperation = @Sendable (
    _ profile: RouterProfile,
    _ credential: String?,
    _ provider: ProxyProviderViewState
) async throws -> Void

typealias ProviderSnapshotOperation = @Sendable (
    _ profile: RouterProfile,
    _ credential: String?
) async -> AppModel.ProviderSnapshotResults

typealias MihomoConnectionCloseOperation = @Sendable (
    _ profile: RouterProfile,
    _ credential: String?,
    _ connectionID: String
) async throws -> Void

typealias MihomoCloseAllConnectionsOperation = @Sendable (
    _ profile: RouterProfile,
    _ credential: String?
) async throws -> Void

typealias MihomoConnectionsSnapshotOperation = @Sendable (
    _ profile: RouterProfile,
    _ credential: String?
) async throws -> ConnectionsResponse

@MainActor
@Observable
final class AppModel {
    var routers: [RouterProfile]
    var selectedRouterID: RouterProfile.ID?
    var connectionState: ConnectionState
    var dashboard: DashboardSnapshot
    var controllerMetadata: ControllerMetadataSnapshot
    var policyGroupCatalog: PolicyGroupCatalogSnapshot
    private(set) var policyGroupCatalogRevision: UInt64
    // Per-domain published snapshots split out of `dashboard` so a high-frequency
    // write to one domain (connections/logs every ~1s during downloads) does not
    // invalidate views observing an unrelated domain. Every dashboard publication
    // path re-derives the matching snapshot with an Equatable `!=` guard.
    var connectionsCatalog: ConnectionsCatalogSnapshot
    var logsCatalog: LogsCatalogSnapshot
    var routingCatalog: RoutingCatalogSnapshot
    var insightCatalog: InsightSummarySnapshot
    var operationState: OperationState?
    var switchingGroupID: String?
    var clearingFixedGroupID: String?
    var changingMode = false
    var updatingConfigFieldID: String?
    var measuringDelayGroupID: String?
    var measuringDelayNode: PolicyNodeLatencyTestTarget?
    var closingConnectionID: String?
    var closingConnectionGroupID: String?
    var closingAllConnections = false
    var updatingProviderName: String?
    var checkingProviderName: String?
    var isRefreshingDashboard = false
    var rulesSnapshotState: EnhancedSnapshotState = .available
    var providersSnapshotState: EnhancedSnapshotState = .available
    var reloadingRules = false
    var updatingRuleID: String?
    var ruleUpdateFailures: [String: String] = [:]
    var reloadingProviders = false
    var providerUpdateFailures: [String: String] = [:]
    var providerUpdateAllProgress: ProviderUpdateAllProgress?
    var providerHealthCheckFailures: [String: String] = [:]
    var controllerHealth: ControllerHealthSnapshot
    var unifiedSnapshot: UnifiedControllerSnapshot = .empty
    var surgeSnapshot: SurgeControlSnapshot = .empty
    var changingSurgeOutbound = false
    var testingSurgePolicyGroup: String?
    var switchingSurgePolicyGroup: String?
    var killingSurgeRequestID: String?
    var killingSurgeProjectedConnectionID: String?
    var reloadingSurgeProfile = false
    var changingControllerLogLevel = false
    var trialSessions: [RouterProfile.ID: TrialSessionSnapshot] = [:]
    var pendingDiagnosticsCopyTarget: DiagnosticsExportTarget?
    var lastDiagnosticsCopyTarget: DiagnosticsExportTarget?
    var diagnosticsTransientState: String?
    var liveStreamRequested = false
    var liveStreamState: LiveStreamState = .idle
    var liveTrafficRate = TrafficSnapshot(upload: 0, download: 0)
    var liveStreamUpdatedAt: Date?
    var trafficTimeline = TrafficTimeline()
    var memoryTimeline = MemoryTimeline()
    var connectionCountTimeline = ConnectionCountTimeline()
    var runningRuntimeOperationID: String?
    var controllerSession = ControllerSession() {
        didSet {
            if oldValue.generation != controllerSession.generation {
                resetSessionPublicationCoordinator(for: controllerSession)
            }
            synchronizeControllerSessionPresentation()
            if oldValue.runtime != controllerSession.runtime,
               !usesActorBackedLiveIngestion {
                noteSessionPublicationDirty(
                    .memory,
                    immediate: runningRuntimeOperationID != nil
                )
            }
        }
    }
    let controllerSessionPresentation = ControllerSessionPresentationState()
    var activeSessionControllerKind: ControllerKind?
    var controllerLogLevel: LogSessionLevel = .all
    var presentationLanguage: AppLanguage = MicaStrings.appLanguage

    var usesActorBackedLiveIngestion: Bool {
        guard liveSessionRuntime != nil,
              let router = selectedRouter else {
            return false
        }
        return runtimeControllerKind(for: router) != .surgeCompatible
    }

    var dashboardSessionControls: DashboardSessionControls {
        get { controllerSessionPresentation.controls }
        set { controllerSession.controls = newValue }
    }

    let profileStore: any RouterProfileStore
    let secretStore: any SecretStore
    @ObservationIgnored let userDefaults: UserDefaults
    @ObservationIgnored private let controllerProbeOperation: ControllerProbeOperation
    @ObservationIgnored private let controllerProbeSleepOperation: ControllerProbeSleepOperation
    @ObservationIgnored private let controllerConnectionTestOperation: ControllerConnectionTestOperation
    @ObservationIgnored private let mihomoConnectionCloseOperation: MihomoConnectionCloseOperation
    @ObservationIgnored private let mihomoCloseAllConnectionsOperation: MihomoCloseAllConnectionsOperation
    @ObservationIgnored private let mihomoConnectionsSnapshotOperation: MihomoConnectionsSnapshotOperation
    @ObservationIgnored private let providerUpdateOperation: ProviderUpdateOperation
    @ObservationIgnored private let providerSnapshotOperation: ProviderSnapshotOperation
    @ObservationIgnored private let sessionPublicationSleepOperation: LiveSessionPublicationSleepOperation
    @ObservationIgnored private let liveSessionBaselineLoadOperation: LiveSessionBaselineLoadOperation?
    @ObservationIgnored var sessionPresentationCoordinator = LiveSessionPublicationCoordinator()
    @ObservationIgnored var sessionPublicationTasks: [LiveSessionPublicationDomain: Task<Void, Never>] = [:]
    @ObservationIgnored var liveSessionRuntime: LiveSessionRuntime?
    @ObservationIgnored var liveSessionRuntimeIdentity: LiveSessionRuntimeIdentity?
    @ObservationIgnored var runtimePublicationTasks: [LiveSessionPublicationDomain: Task<Void, Never>] = [:]
    @ObservationIgnored var lastRuntimePublicationRevisions: [LiveSessionPublicationDomain: UInt64] = [:]
    @ObservationIgnored var lastRuntimeConnectionRevisions = LiveSessionConnectionRevisions()
    @ObservationIgnored var lastRuntimeLogSequence: UInt64 = 0
    @ObservationIgnored var sessionRefreshCoordinator: SessionRefreshCoordinator?
    @ObservationIgnored var sessionMihomoClient: MihomoClient?
    @ObservationIgnored var sessionSurgeClient: SurgeHttpAPIClient?
    @ObservationIgnored var controllerSecrets: [RouterProfile.ID: String]
    @ObservationIgnored var didLoadPersistedState = false
    var didFinishLoadingPersistedState = false
    @ObservationIgnored var mainWindowCount = 0
    @ObservationIgnored var sessionSuspendedForSleep = false

    private var localizationLocale: Locale {
        MicaStrings.locale
    }

    func localized(_ key: String.LocalizationValue) -> String {
        MicaStrings.localized(key, language: presentationLanguage)
    }

    func setLiveStreamState(_ next: LiveStreamState) {
        guard next != liveStreamState else { return }
        liveStreamState = next
    }
    /// Offline GeoIP enrichment for Overview network info (G1). Session-scoped cache;
    /// never performs online HTTP lookups.
    @ObservationIgnored let geoIPCoordinator = GeoIPSessionCoordinator()
    @ObservationIgnored let routerProfileMutationCoordinator = RouterProfileMutationCoordinator()

    @ObservationIgnored var loadTask: Task<Void, Never>?
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var switchTask: Task<Void, Never>?
    @ObservationIgnored var modeTask: Task<Void, Never>?
    @ObservationIgnored var configTask: Task<Void, Never>?
    @ObservationIgnored var delayTask: Task<Void, Never>?
    @ObservationIgnored var connectionTask: Task<Void, Never>?
    @ObservationIgnored var providerTask: Task<Void, Never>?
    @ObservationIgnored var rulesTask: Task<Void, Never>?
    @ObservationIgnored var surgeTask: Task<Void, Never>?
    @ObservationIgnored var liveTrafficTask: Task<Void, Never>?
    @ObservationIgnored var liveLogsTask: Task<Void, Never>?
    @ObservationIgnored var liveMemoryTask: Task<Void, Never>?
    @ObservationIgnored var liveConnectionsTask: Task<Void, Never>?
    @ObservationIgnored var singBoxSessionTask: Task<Void, Never>?
    @ObservationIgnored var liveRetryTask: Task<Void, Never>?
    @ObservationIgnored var backendProbeTask: Task<Void, Never>?
    @ObservationIgnored var liveRetryState = LiveStreamRetryState()
    @ObservationIgnored var initialSessionRefreshTask: Task<Void, Never>?
    @ObservationIgnored var fastSessionRefreshTask: Task<Void, Never>?
    @ObservationIgnored var mediumSessionRefreshTask: Task<Void, Never>?
    @ObservationIgnored var slowSessionRefreshTask: Task<Void, Never>?
    @ObservationIgnored var manualSessionRefreshTask: Task<Void, Never>?
    @ObservationIgnored var runtimeOperationTask: Task<Void, Never>?

    static let selectedControllerDefaultsKey = "selectedControllerID"
    typealias ProviderSnapshotResults = (
        proxy: Result<ProxyProvidersResponse, Error>,
        rule: Result<RuleProvidersResponse, Error>
    )

    init(
        routers: [RouterProfile] = [],
        selectedRouterID: RouterProfile.ID? = nil,
        connectionState: ConnectionState = .disconnected,
        dashboard: DashboardSnapshot = .empty,
        controllerSecrets: [RouterProfile.ID: String] = [:],
        operationState: OperationState? = nil,
        profileStore: any RouterProfileStore = JSONRouterProfileStore(),
        secretStore: any SecretStore = FileSecretStore(),
        userDefaults: UserDefaults = .standard,
        controllerProbeOperation: @escaping ControllerProbeOperation = { profile, credential, includeSurge in
            try await ControllerProbeResolver().resolve(
                profile: profile,
                credential: credential,
                includeSurge: includeSurge
            )
        },
        controllerConnectionTestOperation: @escaping ControllerConnectionTestOperation = { profile, credential, resolvedKind in
            switch resolvedKind {
            case .surgeCompatible:
                let snapshot = try await SurgeHttpAPIClient(
                    profile: profile,
                    apiKey: credential
                ).snapshot()
                return .surge(snapshot)
            case .singBoxCompatible:
                let version = try await SingBoxGRPCClient.withConnectedClient(
                    profile: profile,
                    credential: credential
                ) { client in
                    try await client.version()
                }
                return .singBox(version)
            default:
                let version = try await MihomoClient(
                    profile: profile,
                    secret: credential
                ).version()
                return .mihomo(version)
            }
        },
        mihomoConnectionCloseOperation: @escaping MihomoConnectionCloseOperation = { profile, credential, connectionID in
            try await MihomoClient(profile: profile, secret: credential)
                .closeConnection(id: connectionID)
        },
        mihomoCloseAllConnectionsOperation: @escaping MihomoCloseAllConnectionsOperation = { profile, credential in
            try await MihomoClient(profile: profile, secret: credential)
                .closeAllConnections()
        },
        mihomoConnectionsSnapshotOperation: @escaping MihomoConnectionsSnapshotOperation = { profile, credential in
            try await MihomoClient(profile: profile, secret: credential).connections()
        },
        providerUpdateOperation: @escaping ProviderUpdateOperation = { profile, credential, provider in
            let client = MihomoClient(profile: profile, secret: credential)
            switch provider.kind {
            case .proxy:
                try await client.updateProxyProvider(name: provider.name)
            case .rule:
                try await client.updateRuleProvider(name: provider.name)
            }
        },
        providerSnapshotOperation: @escaping ProviderSnapshotOperation = { profile, credential in
            await AppModel.captureProviderSnapshots(
                client: MihomoClient(profile: profile, secret: credential)
            )
        },
        controllerProbeSleepOperation: @escaping ControllerProbeSleepOperation = { attempt in
            try await Task.sleep(for: SessionRetryPolicy.delay(forAttempt: attempt))
        },
        sessionPublicationSleepOperation: @escaping LiveSessionPublicationSleepOperation = { _, cadence in
            try await Task.sleep(for: cadence)
        },
        liveSessionBaselineLoadOperation: LiveSessionBaselineLoadOperation? = nil
    ) {
        let initialPresentationLanguage = MicaStrings.appLanguage
        self.routers = routers
        self.selectedRouterID = selectedRouterID
        self.connectionState = connectionState
        self.dashboard = dashboard
        self.controllerMetadata = ControllerMetadataSnapshot(dashboard: dashboard)
        self.policyGroupCatalog = PolicyGroupCatalogSnapshot(dashboard: dashboard)
        self.policyGroupCatalogRevision = 0
        self.connectionsCatalog = ConnectionsCatalogSnapshot(dashboard: dashboard)
        self.logsCatalog = .empty
        self.routingCatalog = RoutingCatalogSnapshot(dashboard: dashboard)
        self.insightCatalog = dashboard.insight
        self.controllerSecrets = controllerSecrets
        self.operationState = operationState
        self.profileStore = profileStore
        self.secretStore = secretStore
        self.userDefaults = userDefaults
        self.controllerProbeOperation = controllerProbeOperation
        self.controllerProbeSleepOperation = controllerProbeSleepOperation
        self.controllerConnectionTestOperation = controllerConnectionTestOperation
        self.mihomoConnectionCloseOperation = mihomoConnectionCloseOperation
        self.mihomoCloseAllConnectionsOperation = mihomoCloseAllConnectionsOperation
        self.mihomoConnectionsSnapshotOperation = mihomoConnectionsSnapshotOperation
        self.providerUpdateOperation = providerUpdateOperation
        self.providerSnapshotOperation = providerSnapshotOperation
        self.sessionPublicationSleepOperation = sessionPublicationSleepOperation
        self.liveSessionBaselineLoadOperation = liveSessionBaselineLoadOperation
        self.controllerHealth = .idle(language: initialPresentationLanguage)
        self.presentationLanguage = initialPresentationLanguage
        self.controllerSessionPresentation.synchronize(with: self.controllerSession)
    }

    func resolveControllerKind(
        for profile: RouterProfile,
        credential: String?,
        includeSurge: Bool
    ) async throws -> ControllerKind {
        try await controllerProbeOperation(profile, credential, includeSurge)
    }

    func sleepBeforeControllerProbeRetry(attempt: Int) async throws {
        try await controllerProbeSleepOperation(attempt)
    }

    func sleepBeforeSessionPublication(
        domain: LiveSessionPublicationDomain,
        cadence: Duration
    ) async throws {
        try await sessionPublicationSleepOperation(domain, cadence)
    }

    func loadLiveSessionBaseline(
        profile: RouterProfile,
        credential: String?,
        resolvedKind: ControllerKind
    ) async throws -> LiveSessionBaselinePayload {
        if let liveSessionBaselineLoadOperation {
            return try await liveSessionBaselineLoadOperation(
                profile,
                credential,
                resolvedKind
            )
        }

        switch resolvedKind {
        case .surgeCompatible:
            let client = sessionSurgeClient
                ?? SurgeHttpAPIClient(profile: profile, apiKey: credential)
            return .surge(try await client.snapshot())

        default:
            let client = sessionMihomoClient
                ?? MihomoClient(profile: profile, secret: credential)
            async let version = client.version()
            async let config = client.configs()
            async let proxies = client.proxies()
            async let connections = client.connections()
            let values = try await (version, config, proxies, connections)
            return .mihomo(
                MihomoSessionBaseline(
                    version: values.0,
                    config: values.1,
                    proxies: values.2,
                    connections: values.3
                )
            )
        }
    }

    func runControllerConnectionTest(
        profile: RouterProfile,
        credential: String?,
        resolvedKind: ControllerKind
    ) async throws -> ControllerConnectionTestResult {
        try await controllerConnectionTestOperation(profile, credential, resolvedKind)
    }

    func synchronizePolicyGroupCatalog() {
        let next = PolicyGroupCatalogSnapshot(dashboard: dashboard)
        guard next != policyGroupCatalog else { return }
        policyGroupCatalog = next
        policyGroupCatalogRevision &+= 1
    }

    func synchronizeControllerMetadata() {
        let next = ControllerMetadataSnapshot(dashboard: dashboard)
        guard next != controllerMetadata else { return }
        controllerMetadata = next
    }

    func synchronizeConnectionsCatalog() {
        let structureChanged = !ConnectionsCatalogSnapshot.structuresMatch(
            dashboard.connections,
            connectionsCatalog.connections
        )
        let changedMetricIndices = structureChanged
            ? nil
            : ConnectionsCatalogSnapshot.changedMetricIndices(
                connectionsCatalog.connections,
                dashboard.connections
            )
        let metricsChanged = structureChanged || changedMetricIndices?.isEmpty == false
        let trafficChanged = dashboard.traffic != connectionsCatalog.traffic
        guard structureChanged || metricsChanged || trafficChanged else { return }
        if structureChanged || metricsChanged {
            MicaPerformanceObservation.recordDebug(
                structureChanged
                    ? .fullPresentationProjection
                    : .incrementalPresentationProjection,
                metadata: MicaPerformanceMetadata(
                    count: UInt64(
                        structureChanged
                            ? dashboard.connections.count
                            : changedMetricIndices?.count ?? dashboard.connections.count
                    )
                )
            )
        }
        let next = ConnectionsCatalogSnapshot(
            dashboard: dashboard,
            structureRevision: structureChanged
                ? connectionsCatalog.structureRevision &+ 1
                : connectionsCatalog.structureRevision,
            metricsRevision: metricsChanged
                ? connectionsCatalog.metricsRevision &+ 1
                : connectionsCatalog.metricsRevision,
            trafficRevision: trafficChanged
                ? connectionsCatalog.trafficRevision &+ 1
                : connectionsCatalog.trafficRevision,
            lastChange: ConnectionsCatalogChange(
                structureChanged: structureChanged,
                metricsChanged: metricsChanged,
                changedMetricIndices: changedMetricIndices,
                trafficChanged: trafficChanged
            )
        )
        connectionsCatalog = next
    }

    func synchronizeLogsCatalog(with entries: [ControllerLogEntry]) {
        guard entries != logsCatalog.entries else { return }
        MicaPerformanceObservation.recordDebug(
            .fullPresentationProjection,
            metadata: MicaPerformanceMetadata(count: UInt64(entries.count))
        )
        let next = LogsCatalogSnapshot(
            entries: entries,
            entriesRevision: logsCatalog.entriesRevision &+ 1,
            lastChange: .replace
        )
        logsCatalog = next
    }

    func synchronizeRoutingCatalog() {
        let next = RoutingCatalogSnapshot(dashboard: dashboard)
        guard next != routingCatalog else { return }
        routingCatalog = next
    }

    func synchronizeInsightCatalog() {
        guard dashboard.insight != insightCatalog else { return }
        insightCatalog = dashboard.insight
    }

    func publishDashboardDomains(_ domains: DashboardPublicationDomains) {
        if domains.contains(.metadata) {
            synchronizeControllerMetadata()
        }
        if domains.contains(.policyGroups) {
            synchronizePolicyGroupCatalog()
        }
        if domains.contains(.connections) {
            synchronizeConnectionsCatalog()
        }
        if domains.contains(.routing) {
            synchronizeRoutingCatalog()
        }
        if domains.contains(.insight) {
            synchronizeInsightCatalog()
        }
    }

    /// Compatibility entry point for low-frequency callers that still replace a
    /// complete dashboard. High-frequency session ingestion uses named domains.
    func synchronizeDomainCatalogs() {
        publishDashboardDomains(.baseline)
    }

    private func synchronizeControllerSessionPresentation() {
        controllerSessionPresentation.synchronizeLifecycle(with: controllerSession)
    }

    func publishControllerLogs(_ entries: [ControllerLogEntry]) {
        synchronizeLogsCatalog(with: entries)
    }

    func replaceDashboard(_ next: DashboardSnapshot) {
        dashboard = next
        publishDashboardDomains(.baseline)
    }

    func controllerSupportsLiveAction(
        _ action: UnifiedControllerAction,
        router: RouterProfile,
        action actionTitle: String
    ) -> Bool {
        guard controllerSession.state.allowsLiveCommands else {
            operationState = .partial(
                localized("command.disabled_unavailable"),
                action: actionTitle,
                target: router.displayName
            )
            return false
        }
        return controllerSupports(action, router: router, action: actionTitle)
    }

    func setMode(_ mode: String) {
        modeTask?.cancel()

        guard mode != sessionActionDashboard.mode else {
            return
        }

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_mode"))
            return
        }

        if modeChangeAction(for: router) == .setOutboundMode {
            setSurgeOutboundMode(mode)
            return
        }

        guard controllerSupportsLiveAction(.changeMode, router: router, action: TrialCommandAction.setMode.title(language: presentationLanguage)) else {
            return
        }

        if runtimeControllerKind(for: router) == .singBoxCompatible {
            setSingBoxMode(mode, router: router)
            return
        }

        let commandID = beginCommand(.setMode, router: router, summary: localized("operation.changing_mode"))
        let previousMode = sessionActionDashboard.mode
        mutateSessionDashboard(publishing: [.metadata]) { $0.mode = mode }
        changingMode = true
        operationState = .working(localized("operation.changing_mode_progress"), action: TrialCommandAction.setMode.title(language: presentationLanguage), target: router.displayName)

        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]
        modeTask = Task {
            let client = MihomoClient(profile: router, secret: secret)
            var didUpdateMode = false

            do {
                try await client.updateMode(mode)
                didUpdateMode = true
                let config = try await client.configs()

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                mutateSessionDashboard(publishing: [.metadata]) {
                    $0.replaceConfig(with: config)
                }
                changingMode = false
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.mode_changed_summary"))
                operationState = .success(localized("operation.mode_changed \(MicaStrings.displayMode(dashboard.mode, language: presentationLanguage))"), action: TrialCommandAction.setMode.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                changingMode = false
                if didUpdateMode {
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .partial,
                        summary: localized("operation.mode_changed_refresh_failed")
                    )
                    operationState = .partial(
                        localized("operation.mode_changed_refresh_failed"),
                        action: TrialCommandAction.setMode.title(language: presentationLanguage),
                        target: router.displayName,
                        nextStep: Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                    )
                } else {
                    mutateSessionDashboard(publishing: [.metadata]) {
                        $0.mode = previousMode
                    }
                    finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.mode_change_failed"))
                    operationState = .error(Self.routerTrialFailureMessage(for: error, language: presentationLanguage), action: TrialCommandAction.setMode.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry"))
                }
            }
        }
    }

    func modeChangeAction(for router: RouterProfile) -> UnifiedControllerAction {
        runtimeControllerKind(for: router) == .surgeCompatible
            ? .setOutboundMode
            : .changeMode
    }

    func selectNode(_ node: String, in groupID: String) {
        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_switch"))
            return
        }

        guard controllerSupportsLiveAction(.switchPolicy, router: router, action: TrialCommandAction.switchNode.title(language: presentationLanguage)) else {
            return
        }

        guard let group = sessionActionDashboard.groups.first(where: { $0.id == groupID }) else {
            operationState = .error(localized("operation.policy_group_gone \(groupID)"))
            return
        }
        guard group.selectable else {
            operationState = .partial(
                localized("operation.policy_group_not_selectable"),
                action: TrialCommandAction.switchNode.title(
                    language: presentationLanguage
                ),
                target: groupID
            )
            return
        }
        guard group.options.contains(node) else {
            operationState = .error(localized("operation.policy_node_gone \(node)"))
            return
        }

        switchTask?.cancel()
        clearingFixedGroupID = nil
        let previousNode = group.selected

        if runtimeControllerKind(for: router) == .singBoxCompatible {
            selectSingBoxNode(node, in: groupID, router: router)
            return
        }

        let commandID = beginCommand(.switchNode, router: router, summary: localized("operation.switching_route"))
        mutateSessionDashboard(publishing: [.policyGroups, .insight]) { dashboard in
            if let index = dashboard.groups.firstIndex(where: { $0.id == groupID }) {
                dashboard.groups[index].selected = node
            }
        }
        switchingGroupID = groupID
        operationState = .working(localized("operation.switching_route_progress"), action: TrialCommandAction.switchNode.title(language: presentationLanguage), target: router.displayName)

        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]
        switchTask = Task {
            let client = MihomoClient(profile: router, secret: secret)
            var didSelectNode = false

            do {
                try await client.selectProxy(group: groupID, name: node)
                didSelectNode = true

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                let proxies = try await client.proxies()

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                mutateSessionDashboard(publishing: [.policyGroups, .insight]) {
                    $0.replaceGroups(with: proxies)
                }
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.switched_route"))
                operationState = .success(localized("operation.switched_route"), action: TrialCommandAction.switchNode.title(language: presentationLanguage), target: router.displayName)
                switchingGroupID = nil
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                if didSelectNode {
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .partial,
                        summary: localized("operation.route_switched_refresh_failed")
                    )
                    operationState = .partial(
                        localized("operation.route_switched_refresh_failed"),
                        action: TrialCommandAction.switchNode.title(language: presentationLanguage),
                        target: groupID,
                        nextStep: Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                    )
                } else {
                    mutateSessionDashboard(publishing: [.policyGroups, .insight]) { dashboard in
                        if let rollbackIndex = dashboard.groups.firstIndex(where: { $0.id == groupID }) {
                            dashboard.groups[rollbackIndex].selected = previousNode
                        }
                    }
                    finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.route_switch_failed"))
                    operationState = .error(Self.routerTrialFailureMessage(for: error, language: presentationLanguage), action: TrialCommandAction.switchNode.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry"))
                }
                switchingGroupID = nil
            }
        }
    }

    func clearFixedSelection(in groupID: String) {
        switchTask?.cancel()
        switchingGroupID = nil

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_switch"))
            return
        }

        guard controllerSupportsLiveAction(
            .clearFixedSelection,
            router: router,
            action: TrialCommandAction.clearFixedSelection.title(language: presentationLanguage)
        ) else {
            return
        }

        guard let group = sessionActionDashboard.groups.first(where: { $0.id == groupID }),
              group.details?.fixed?.nilIfEmpty != nil else {
            operationState = .partial(localized("operation.fixed_selection_not_reported"))
            return
        }

        let commandID = beginCommand(
            .clearFixedSelection,
            router: router,
            summary: localized("operation.clearing_fixed_selection")
        )
        clearingFixedGroupID = groupID
        operationState = .working(
            localized("operation.clearing_fixed_selection"),
            action: TrialCommandAction.clearFixedSelection.title(language: presentationLanguage),
            target: groupID
        )

        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]
        switchTask = Task {
            let client = MihomoClient(profile: router, secret: secret)
            var didClearFixedSelection = false

            do {
                try await client.clearFixedProxy(group: groupID)
                didClearFixedSelection = true
                let proxies = try await client.proxies()

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                mutateSessionDashboard(publishing: [.policyGroups, .insight]) {
                    $0.replaceGroups(with: proxies)
                }
                clearingFixedGroupID = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .success,
                    summary: localized("operation.fixed_selection_cleared")
                )
                operationState = .success(
                    localized("operation.fixed_selection_cleared"),
                    action: TrialCommandAction.clearFixedSelection.title(language: presentationLanguage),
                    target: groupID
                )
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                clearingFixedGroupID = nil
                if didClearFixedSelection {
                    mutateSessionDashboard(publishing: [.policyGroups, .insight]) { dashboard in
                        if let index = dashboard.groups.firstIndex(where: { $0.id == groupID }) {
                            dashboard.groups[index].details?.fixed = nil
                        }
                    }
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .partial,
                        summary: localized("operation.fixed_selection_cleared_refresh_failed")
                    )
                    operationState = .partial(
                        localized("operation.fixed_selection_cleared_refresh_failed"),
                        action: TrialCommandAction.clearFixedSelection.title(language: presentationLanguage),
                        target: groupID,
                        nextStep: Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                    )
                } else {
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .failed,
                        summary: localized("operation.fixed_selection_clear_failed")
                    )
                    operationState = .error(
                        Self.routerTrialFailureMessage(for: error, language: presentationLanguage),
                        action: TrialCommandAction.clearFixedSelection.title(language: presentationLanguage),
                        target: groupID,
                        nextStep: localized("action.retry")
                    )
                }
            }
        }
    }

    func measureDelay(in groupID: String) {
        delayTask?.cancel()
        measuringDelayGroupID = nil
        measuringDelayNode = nil

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_delay"))
            return
        }

        guard controllerSupportsLiveAction(.testLatency, router: router, action: TrialCommandAction.testDelay.title(language: presentationLanguage)) else {
            return
        }

        guard sessionActionDashboard.groups.contains(where: { $0.id == groupID }) else {
            operationState = .error(localized("operation.policy_group_gone \(groupID)"))
            return
        }

        if runtimeControllerKind(for: router) == .singBoxCompatible {
            testSingBoxPolicyGroup(groupID, router: router)
            return
        }

        let commandID = beginCommand(.testDelay, router: router, summary: localized("operation.testing_delay"))
        measuringDelayGroupID = groupID
        operationState = .working(localized("operation.testing_delay_progress"), action: TrialCommandAction.testDelay.title(language: presentationLanguage), target: router.displayName)
        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]
        let forceMemberFallback = runtimeControllerKind(for: router) == .stashCompatible

        delayTask = Task {
            let client = MihomoClient(profile: router, secret: secret)

            do {
                let response = try await client.groupDelay(
                    group: groupID,
                    forceMemberFallback: forceMemberFallback
                )

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                mutateSessionDashboard(publishing: [.policyGroups, .insight]) {
                    $0.replaceDelays(response.delay, in: groupID)
                }
                measuringDelayGroupID = nil
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.updated_delay"))
                operationState = .success(localized("operation.updated_delay"), action: TrialCommandAction.testDelay.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                measuringDelayGroupID = nil
                finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.delay_test_failed"))
                operationState = .error(Self.routerTrialFailureMessage(for: error, language: presentationLanguage), action: TrialCommandAction.testDelay.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry"))
            }
        }
    }

    func measureDelay(for node: String, in groupID: String) {
        delayTask?.cancel()
        measuringDelayGroupID = nil
        measuringDelayNode = nil

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_delay"))
            return
        }

        guard controllerSupportsLiveAction(
            .testLatency,
            router: router,
            action: TrialCommandAction.testDelay.title(language: presentationLanguage)
        ) else {
            return
        }

        guard let group = sessionActionDashboard.groups.first(where: { $0.id == groupID }) else {
            operationState = .error(localized("operation.policy_group_gone \(groupID)"))
            return
        }
        guard group.options.contains(node) else {
            operationState = .error(localized("operation.policy_node_gone \(node)"))
            return
        }

        if runtimeControllerKind(for: router) == .singBoxCompatible {
            testSingBoxPolicyNode(node, in: groupID, router: router)
            return
        }

        let target = PolicyNodeLatencyTestTarget(groupID: groupID, nodeName: node)
        let commandID = beginCommand(
            .testDelay,
            router: router,
            summary: localized("operation.testing_node_delay \(node)")
        )
        measuringDelayNode = target
        operationState = .working(
            localized("operation.testing_node_delay \(node)"),
            action: TrialCommandAction.testDelay.title(language: presentationLanguage),
            target: node
        )

        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]
        let details = group.detail(for: node)
        delayTask = Task {
            let client = MihomoClient(profile: router, secret: secret)

            do {
                let delay = try await measureMihomoNodeDelay(
                    client: client,
                    node: node,
                    details: details
                )

                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                mutateSessionDashboard(publishing: [.policyGroups, .insight]) {
                    $0.replaceDelay(delay, for: node, in: groupID)
                }
                measuringDelayNode = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .success,
                    summary: localized("operation.updated_node_delay \(node) \(delay)")
                )
                operationState = .success(
                    localized("operation.updated_node_delay \(node) \(delay)"),
                    action: TrialCommandAction.testDelay.title(language: presentationLanguage),
                    target: node
                )
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                measuringDelayNode = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: localized("operation.node_delay_test_failed \(node)")
                )
                operationState = .error(
                    Self.routerTrialFailureMessage(for: error, language: presentationLanguage),
                    action: TrialCommandAction.testDelay.title(language: presentationLanguage),
                    target: node,
                    nextStep: localized("action.retry")
                )
            }
        }
    }

    private func measureMihomoNodeDelay(
        client: MihomoClient,
        node: String,
        details: ProxyNodeViewState?
    ) async throws -> Int {
        let provider = details?.providerName?.nilIfEmpty
        let testURL = details?.testURL?.nilIfEmpty
        let response: ProxyDelayResponse

        switch (provider, testURL) {
        case (.some(let provider), .some(let testURL)):
            response = try await client.providerProxyDelay(
                provider: provider,
                name: node,
                url: testURL
            )
        case (.some(let provider), .none):
            response = try await client.providerProxyDelay(provider: provider, name: node)
        case (.none, .some(let testURL)):
            response = try await client.proxyDelay(name: node, url: testURL)
        case (.none, .none):
            response = try await client.proxyDelay(name: node)
        }

        return response.delay
    }

    func closeConnection(_ connection: ConnectionSnapshot) {
        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_close"))
            return
        }

        let actionTitle = TrialCommandAction.closeConnection.title(
            language: presentationLanguage
        )
        guard !connection.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            operationState = .partial(
                localized("operation.connection_id_unavailable"),
                action: actionTitle,
                target: router.displayName
            )
            return
        }
        let connectionID = connection.id

        connectionTask?.cancel()

        if runtimeControllerKind(for: router) == .surgeCompatible {
            closeSurgeProjectedConnection(connection)
            return
        }

        if runtimeControllerKind(for: router) == .singBoxCompatible {
            closeSingBoxConnection(connection, router: router)
            return
        }

        guard controllerSupportsLiveAction(.closeConnection, router: router, action: actionTitle) else {
            return
        }

        let commandID = beginCommand(.closeConnection, router: router, summary: localized("operation.closing_connection"))
        closingConnectionID = connection.id
        closingConnectionGroupID = nil
        closingAllConnections = false
        operationState = .working(localized("operation.closing_connection_progress"), action: actionTitle, target: router.displayName)
        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]

        connectionTask = Task {
            var didCloseConnection = false

            do {
                try await mihomoConnectionCloseOperation(router, secret, connectionID)

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                didCloseConnection = true
                recordClosedSessionConnections([connection])
                removeSessionConnections([connection])

                let connections = try await mihomoConnectionsSnapshotOperation(router, secret)

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                mutateSessionDashboard(publishing: [.connections, .insight]) {
                    $0.replaceConnections(with: connections)
                }
                closingConnectionID = nil
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.closed_connection"))
                operationState = .success(localized("operation.closed_connection"), action: actionTitle, target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                closingConnectionID = nil
                if didCloseConnection {
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .partial,
                        summary: localized("operation.connection_closed_refresh_failed")
                    )
                    operationState = .partial(
                        localized("operation.connection_closed_refresh_failed"),
                        action: actionTitle,
                        target: router.displayName,
                        nextStep: Self.routerTrialFailureMessage(
                            for: error,
                            language: presentationLanguage
                        )
                    )
                } else {
                    finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.close_connection_failed"))
                    operationState = .error(Self.routerTrialFailureMessage(for: error, language: presentationLanguage), action: actionTitle, target: router.displayName, nextStep: localized("action.refresh"))
                }
            }
        }
    }

    func closeConnectionGroup(
        _ connections: [ConnectionSnapshot],
        groupID: String,
        groupLabel: String
    ) {
        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_close"))
            return
        }

        guard !connections.isEmpty else {
            operationState = .success(
                localized("operation.no_active_connections"),
                action: TrialCommandAction.closeConnectionGroup.title(language: presentationLanguage),
                target: router.displayName
            )
            return
        }

        let closableConnections = connections.filter {
            !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !closableConnections.isEmpty else {
            operationState = .partial(
                localized("operation.connection_id_unavailable"),
                action: TrialCommandAction.closeConnectionGroup.title(
                    language: presentationLanguage
                ),
                target: groupLabel
            )
            return
        }

        if runtimeControllerKind(for: router) == .singBoxCompatible {
            operationState = .partial(
                localized("capability.unsupported_sing_box_data"),
                action: TrialCommandAction.closeConnectionGroup.title(language: presentationLanguage),
                target: groupLabel
            )
            return
        }

        guard controllerSupportsLiveAction(
            runtimeControllerKind(for: router) == .surgeCompatible ? .killActiveRequest : .closeConnection,
            router: router,
            action: TrialCommandAction.closeConnectionGroup.title(language: presentationLanguage)
        ) else {
            return
        }

        connectionTask?.cancel()

        let commandID = beginCommand(
            .closeConnectionGroup,
            router: router,
            summary: localized("operation.closing_connection_group \(closableConnections.count)")
        )
        closingConnectionID = nil
        closingConnectionGroupID = groupID
        closingAllConnections = false
        operationState = .working(
            localized("operation.closing_connection_group_progress \(closableConnections.count) \(groupLabel)"),
            action: TrialCommandAction.closeConnectionGroup.title(language: presentationLanguage),
            target: router.displayName
        )

        let generation = controllerSession.generation
        let credential = controllerSecrets[router.id]
        let runtimeKind = runtimeControllerKind(for: router)

        connectionTask = Task {
            var closed: [ConnectionSnapshot] = []

            do {
                if runtimeKind == .surgeCompatible {
                    let requestsByProjectedID = Dictionary(
                        uniqueKeysWithValues: zip(
                            sessionActionSurgeSnapshot.activeRequests,
                            DashboardSnapshot.surgeRequestDisplayIDs(
                                for: sessionActionSurgeSnapshot.activeRequests
                            )
                        ).map { request, projectedID in (projectedID, request) }
                    )
                    let client = SurgeHttpAPIClient(profile: router, apiKey: credential)

                    for connection in closableConnections {
                        try Task.checkCancellation()
                        guard let request = requestsByProjectedID[connection.id],
                              !request.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            throw SurgeHttpAPIError.malformedResponse("/v1/requests/active")
                        }
                        try await client.killActiveRequest(id: request.id)
                        closed.append(connection)
                    }

                    let activeRequests = try await client.activeRequests()
                    guard isCurrentSession(routerID: router.id, generation: generation),
                          !Task.isCancelled else {
                        return
                    }
                    var snapshot = sessionActionSurgeSnapshot
                    snapshot.activeRequests = activeRequests.requests
                    snapshot.checkedAt = Date()
                    applySurgeSnapshot(snapshot, router: router)
                } else {
                    for connection in closableConnections {
                        try Task.checkCancellation()
                        try await mihomoConnectionCloseOperation(
                            router,
                            credential,
                            connection.id
                        )
                        closed.append(connection)
                    }

                    let latest = try await mihomoConnectionsSnapshotOperation(
                        router,
                        credential
                    )
                    guard isCurrentSession(routerID: router.id, generation: generation),
                          !Task.isCancelled else {
                        return
                    }
                    mutateSessionDashboard(publishing: [.connections, .insight]) {
                        $0.replaceConnections(with: latest)
                    }
                }

                recordClosedSessionConnections(closed)
                removeSessionConnections(closed)
                closingConnectionGroupID = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .success,
                    summary: localized("operation.closed_connection_group \(closed.count)")
                )
                operationState = .success(
                    localized("operation.closed_connection_group \(closed.count)"),
                    action: TrialCommandAction.closeConnectionGroup.title(language: presentationLanguage),
                    target: router.displayName
                )
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                recordClosedSessionConnections(closed)
                removeSessionConnections(closed)
                closingConnectionGroupID = nil
                let failure = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                if closed.isEmpty {
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .failed,
                        summary: localized("operation.close_connection_group_failed")
                    )
                    operationState = .error(
                        failure,
                        action: TrialCommandAction.closeConnectionGroup.title(language: presentationLanguage),
                        target: router.displayName,
                        nextStep: localized("action.refresh")
                    )
                } else {
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .partial,
                        summary: localized("operation.close_connection_group_partial \(closed.count) \(closableConnections.count)")
                    )
                    operationState = .partial(
                        localized("operation.close_connection_group_partial \(closed.count) \(closableConnections.count)"),
                        action: TrialCommandAction.closeConnectionGroup.title(language: presentationLanguage),
                        target: router.displayName,
                        nextStep: failure
                    )
                }
            }
        }
    }

    func closeAllConnections() {
        connectionTask?.cancel()

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_close_all"))
            return
        }

        let runtimeKind = runtimeControllerKind(for: router)
        let closeAction: UnifiedControllerAction = runtimeKind == .surgeCompatible
            ? .killActiveRequest
            : .closeAllConnections
        guard controllerSupportsLiveAction(closeAction, router: router, action: TrialCommandAction.closeAll.title(language: presentationLanguage)) else {
            return
        }

        if runtimeKind == .surgeCompatible {
            closeAllSurgeProjectedConnections(router: router)
            return
        }

        if runtimeKind == .singBoxCompatible {
            closeAllSingBoxConnections(router: router)
            return
        }

        let commandID = beginCommand(.closeAll, router: router, summary: localized("operation.closing_all"))
        guard !dashboard.connections.isEmpty else {
            finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.no_active_connections"))
            operationState = .success(localized("operation.no_active_connections"), action: TrialCommandAction.closeAll.title(language: presentationLanguage), target: router.displayName)
            return
        }

        closingConnectionID = nil
        closingConnectionGroupID = nil
        closingAllConnections = true
        operationState = .working(localized("operation.closing_all_progress"), action: TrialCommandAction.closeAll.title(language: presentationLanguage), target: router.displayName)
        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]
        let closingSnapshot = dashboard.connections

        connectionTask = Task {
            var didCloseAllConnections = false

            do {
                try await mihomoCloseAllConnectionsOperation(router, secret)

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                didCloseAllConnections = true
                recordClosedSessionConnections(closingSnapshot)
                removeSessionConnections(closingSnapshot)

                let connections = try await mihomoConnectionsSnapshotOperation(
                    router,
                    secret
                )

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                mutateSessionDashboard(publishing: [.connections, .insight]) {
                    $0.replaceConnections(with: connections)
                }
                closingAllConnections = false
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.closed_all"))
                operationState = .success(localized("operation.closed_all"), action: TrialCommandAction.closeAll.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                closingAllConnections = false
                if didCloseAllConnections {
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .partial,
                        summary: localized("operation.connections_closed_refresh_failed")
                    )
                    operationState = .partial(
                        localized("operation.connections_closed_refresh_failed"),
                        action: TrialCommandAction.closeAll.title(
                            language: presentationLanguage
                        ),
                        target: router.displayName,
                        nextStep: Self.routerTrialFailureMessage(
                            for: error,
                            language: presentationLanguage
                        )
                    )
                } else {
                    finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.close_all_failed"))
                    operationState = .error(Self.routerTrialFailureMessage(for: error, language: presentationLanguage), action: TrialCommandAction.closeAll.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.refresh"))
                }
            }
        }
    }

    func updateAllProviders() {
        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_providers"))
            return
        }

        let generation = controllerSession.generation
        guard isCurrentSession(routerID: router.id, generation: generation) else {
            operationState = .error(localized("operation.select_router_providers"))
            return
        }

        let actionTitle = TrialCommandAction.providerUpdateAll.title(language: presentationLanguage)
        guard !dashboardSessionControls.dashboardUpdatesPaused else {
            operationState = .partial(
                localized("operation.dashboard_updates_paused"),
                action: actionTitle,
                target: router.displayName
            )
            return
        }

        guard !isBusy else {
            operationState = .partial(
                localized("command.disabled_busy"),
                action: actionTitle,
                target: router.displayName
            )
            return
        }

        guard controllerSupportsLiveAction(.updateProvider, router: router, action: actionTitle) else {
            return
        }

        let providers = routingCatalog.providers.filter(\.updatable)
        guard let firstProvider = providers.first else {
            operationState = .partial(
                localized("traffic.no_updatable_providers"),
                action: actionTitle,
                target: router.displayName
            )
            return
        }

        providerTask?.cancel()
        let commandID = beginCommand(
            .providerUpdateAll,
            router: router,
            summary: localized("operation.provider_update_all_started \(providers.count)")
        )
        var progress = ProviderUpdateAllProgress(providers: providers)
        progress.begin(firstProvider)
        providerUpdateAllProgress = progress
        updatingProviderName = firstProvider.id
        checkingProviderName = nil
        reloadingProviders = false
        providerUpdateFailures = [:]
        operationState = .working(
            localized("operation.provider_update_all_progress \(0) \(providers.count) \(firstProvider.name)"),
            action: actionTitle,
            target: router.displayName
        )
        let secret = controllerSecrets[router.id]

        providerTask = Task {
            guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                return
            }

            for (index, provider) in providers.enumerated() {
                if index > 0 {
                    progress.begin(provider)
                    providerUpdateAllProgress = progress
                    updatingProviderName = provider.id
                    operationState = .working(
                        localized(
                            "operation.provider_update_all_progress \(progress.completed) \(progress.total) \(provider.name)"
                        ),
                        action: actionTitle,
                        target: router.displayName
                    )
                }

                do {
                    try await providerUpdateOperation(router, secret, provider)
                    guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                        return
                    }

                    progress.completeCurrentSuccessfully()
                } catch {
                    guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                        return
                    }

                    let message = Self.routerTrialFailureMessage(
                        for: error,
                        language: presentationLanguage
                    )
                    progress.failCurrent(with: message)
                    providerUpdateFailures[provider.id] = message
                }

                providerUpdateAllProgress = progress
                updatingProviderName = nil
            }

            let providerSnapshots = await providerSnapshotOperation(router, secret)
            guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                return
            }

            applyProviderSnapshots(providerSnapshots)
            let refreshUnavailable = providersSnapshotState.isUnavailable
            progress.finish()
            providerUpdateAllProgress = progress
            updatingProviderName = nil
            providerTask = nil

            let summary: String
            let status: CommandLifecycle
            let nextStep: String?
            let stateKind: OperationState.Kind

            if progress.failed == 0, !refreshUnavailable {
                summary = localized("operation.provider_update_all_succeeded \(progress.succeeded)")
                status = .success
                nextStep = nil
                stateKind = .success
            } else if progress.succeeded == 0 {
                summary = localized("operation.provider_update_all_failed \(progress.failed)")
                status = .failed
                nextStep = localized("action.retry")
                stateKind = .error
            } else {
                summary = localized(
                    "operation.provider_update_all_partial \(progress.succeeded) \(progress.failed)"
                )
                status = .partial
                nextStep = progress.failed > 0
                    ? localized("action.retry")
                    : localized("action.refresh")
                stateKind = .partial
            }

            var messageLines = [summary]
            if refreshUnavailable {
                messageLines.append(localized("operation.providers_unavailable"))
            }
            messageLines.append(contentsOf: progress.failures.map {
                "\($0.target.name): \($0.message)"
            })
            let message = messageLines.joined(separator: "\n")

            finishCommand(
                commandID,
                routerID: router.id,
                status: status,
                summary: summary
            )
            operationState = OperationState(
                kind: stateKind,
                message: message,
                action: actionTitle,
                target: router.displayName,
                nextStep: nextStep
            )
        }
    }

    func updateProxyProvider(_ provider: ProxyProviderViewState) {
        let actionTitle = TrialCommandAction.providerUpdate.title(language: presentationLanguage)
        guard providerUpdateAllProgress?.isRunning != true else {
            operationState = .partial(
                localized("command.disabled_busy"),
                action: actionTitle,
                target: selectedRouter?.displayName
            )
            return
        }

        providerTask?.cancel()
        providerUpdateAllProgress = nil
        checkingProviderName = nil

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_provider"))
            return
        }

        guard canRefreshSelectedRouter else {
            operationState = .partial(localized("operation.dashboard_updates_paused"))
            return
        }

        guard controllerSupportsLiveAction(.updateProvider, router: router, action: actionTitle) else {
            return
        }

        guard provider.updatable else {
            operationState = .partial(
                localized("traffic.provider_not_updatable"),
                action: actionTitle,
                target: provider.name
            )
            return
        }

        let commandID = beginCommand(.providerUpdate, router: router, summary: localized("operation.updating_provider"))
        updatingProviderName = provider.id
        reloadingProviders = false
        providerUpdateFailures.removeValue(forKey: provider.id)
        operationState = .working(localized("operation.updating_provider_progress"), action: actionTitle, target: router.displayName)
        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]

        providerTask = Task {
            do {
                try await providerUpdateOperation(router, secret, provider)
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                let providerSnapshots = await providerSnapshotOperation(router, secret)

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                applyProviderSnapshots(providerSnapshots)
                updatingProviderName = nil
                providerTask = nil
                if providersSnapshotState.isUnavailable {
                    finishCommand(commandID, routerID: router.id, status: .partial, summary: localized("operation.providers_unavailable"))
                    operationState = .partial(localized("operation.providers_unavailable"), action: actionTitle, target: router.displayName, nextStep: localized("action.refresh"))
                } else {
                    finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.updated_provider"))
                    operationState = .success(localized("operation.updated_provider"), action: actionTitle, target: router.displayName)
                }
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                providerUpdateFailures[provider.id] = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                updatingProviderName = nil
                providerTask = nil
                finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.provider_update_failed"))
                operationState = .error(Self.routerTrialFailureMessage(for: error, language: presentationLanguage), action: actionTitle, target: router.displayName, nextStep: localized("action.retry"))
            }
        }
    }

    func healthCheckProxyProvider(_ provider: ProxyProviderViewState) {
        let actionTitle = TrialCommandAction.providerHealthCheck.title(language: presentationLanguage)
        guard providerUpdateAllProgress?.isRunning != true else {
            operationState = .partial(
                localized("command.disabled_busy"),
                action: actionTitle,
                target: selectedRouter?.displayName
            )
            return
        }

        providerTask?.cancel()
        providerUpdateAllProgress = nil
        updatingProviderName = nil
        checkingProviderName = nil

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_provider_health"))
            return
        }

        guard canRefreshSelectedRouter else {
            operationState = .partial(localized("operation.dashboard_updates_paused"))
            return
        }

        guard controllerSupportsLiveAction(
            .healthCheckProvider,
            router: router,
            action: actionTitle
        ) else {
            return
        }

        guard provider.supportsHealthCheck else {
            operationState = .partial(
                localized("traffic.provider_health_check_unavailable"),
                action: actionTitle,
                target: provider.name
            )
            return
        }

        let commandID = beginCommand(
            .providerHealthCheck,
            router: router,
            summary: localized("operation.checking_provider_health")
        )
        checkingProviderName = provider.id
        reloadingProviders = false
        providerHealthCheckFailures.removeValue(forKey: provider.id)
        operationState = .working(
            localized("operation.checking_provider_health_progress"),
            action: actionTitle,
            target: provider.name
        )

        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]

        providerTask = Task {
            let client = MihomoClient(profile: router, secret: secret)

            do {
                try await client.healthCheckProxyProvider(name: provider.name)
                let providerSnapshots = await Self.captureProviderSnapshots(client: client)

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                applyProviderSnapshots(providerSnapshots)
                checkingProviderName = nil
                providerTask = nil
                if providersSnapshotState.isUnavailable {
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .partial,
                        summary: localized("operation.provider_health_checked_refresh_failed")
                    )
                    operationState = .partial(
                        localized("operation.provider_health_checked_refresh_failed"),
                        action: actionTitle,
                        target: provider.name,
                        nextStep: localized("action.refresh")
                    )
                } else {
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .success,
                        summary: localized("operation.provider_health_checked")
                    )
                    operationState = .success(
                        localized("operation.provider_health_checked"),
                        action: actionTitle,
                        target: provider.name
                    )
                }
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                providerHealthCheckFailures[provider.id] = message
                checkingProviderName = nil
                providerTask = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: localized("operation.provider_health_check_failed")
                )
                operationState = .error(
                    message,
                    action: actionTitle,
                    target: provider.name,
                    nextStep: localized("action.retry")
                )
            }
        }
    }

    private func applyProviderSnapshots(_ results: ProviderSnapshotResults) {
        var proxyProviders = controllerSession.endpointCache.proxyProviders
        var ruleProviders = controllerSession.endpointCache.ruleProviders
        var failureMessage: String?

        switch results.proxy {
        case .success(let providers):
            proxyProviders = providers
            controllerSession.endpointCache.proxyProviders = providers
        case .failure(let error):
            failureMessage = failureMessage ?? Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
        }

        switch results.rule {
        case .success(let providers):
            ruleProviders = providers
            controllerSession.endpointCache.ruleProviders = providers
        case .failure(let error):
            failureMessage = failureMessage ?? Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
        }

        if proxyProviders != nil || ruleProviders != nil || dashboard.providers.isEmpty {
            dashboard.replaceProviders(proxyProviders: proxyProviders, ruleProviders: ruleProviders)
            publishDashboardDomains([.routing, .insight])
        }

        var nextHealth = controllerHealth
        if let failureMessage {
            providersSnapshotState = .unavailable(failureMessage)
            nextHealth.set(.providers, status: .failed(failureMessage))
        } else if dashboard.providers.isEmpty {
            let message = localized("snapshot.base_refresh_providers_unavailable")
            providersSnapshotState = .unavailable(message)
            nextHealth.set(.providers, status: .failed(message))
        } else {
            providersSnapshotState = .available
            nextHealth.set(.providers, status: .ready(localized("endpoint.providers_count \(dashboard.providers.count)")))
        }
        nextHealth.finalize()
        controllerHealth = nextHealth
    }

    func reloadRules() {
        rulesTask?.cancel()
        updatingRuleID = nil

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_rules"))
            return
        }

        guard canRefreshSelectedRouter else {
            operationState = .partial(localized("operation.dashboard_updates_paused"))
            return
        }

        guard controllerSupportsLiveAction(.reloadRules, router: router, action: TrialCommandAction.reloadRules.title(language: presentationLanguage)) else {
            return
        }

        if runtimeControllerKind(for: router) == .surgeCompatible {
            reloadSurgeRules(router)
            return
        }

        let commandID = beginCommand(.reloadRules, router: router, summary: localized("operation.reloading_rules"))
        reloadingRules = true
        rulesSnapshotState = .loading
        operationState = .working(localized("operation.reloading_rules_progress"), action: TrialCommandAction.reloadRules.title(language: presentationLanguage), target: router.displayName)
        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]

        rulesTask = Task {
            let client = MihomoClient(profile: router, secret: secret)

            do {
                let rules = try await client.rules()

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                dashboard.replaceRules(with: rules)
                publishDashboardDomains([.routing, .insight])
                controllerSession.endpointCache.rules = rules
                rulesSnapshotState = .available
                var nextHealth = controllerHealth
                nextHealth.set(.rules, status: .ready(localized("endpoint.rules_count \(rules.rules.count)")))
                nextHealth.finalize()
                controllerHealth = nextHealth
                reloadingRules = false
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.rules_reloaded"))
                operationState = .success(localized("operation.reloaded_rules \(dashboard.rules.count)"), action: TrialCommandAction.reloadRules.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                rulesSnapshotState = .unavailable(message)
                var nextHealth = controllerHealth
                nextHealth.set(.rules, status: .failed(message))
                nextHealth.finalize()
                controllerHealth = nextHealth
                reloadingRules = false
                finishCommand(commandID, routerID: router.id, status: .partial, summary: localized("operation.rules_unavailable"))
                operationState = .partial(localized("operation.rules_unavailable"), action: TrialCommandAction.reloadRules.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry"))
            }
        }
    }

    func setRuleDisabled(_ rule: RuleViewState, disabled: Bool) {
        rulesTask?.cancel()
        reloadingRules = false

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_rules"))
            return
        }

        guard canRefreshSelectedRouter else {
            operationState = .partial(localized("operation.dashboard_updates_paused"))
            return
        }

        guard controllerSupportsLiveAction(
            .setRuleDisabled,
            router: router,
            action: TrialCommandAction.setRuleState.title(language: presentationLanguage)
        ) else {
            return
        }

        guard rule.hasMutableExtra, let index = rule.index else {
            operationState = .partial(localized("operation.rule_state_not_supported"))
            return
        }

        let commandID = beginCommand(
            .setRuleState,
            router: router,
            summary: localized("operation.updating_rule_state")
        )
        updatingRuleID = rule.id
        ruleUpdateFailures.removeValue(forKey: rule.id)
        operationState = .working(
            localized("operation.updating_rule_state"),
            action: TrialCommandAction.setRuleState.title(language: presentationLanguage),
            target: rule.payload
        )

        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]
        rulesTask = Task {
            let client = MihomoClient(profile: router, secret: secret)

            do {
                try await client.setRuleDisabled(index: index, disabled: disabled)
                let rules = try await client.rules()

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                dashboard.replaceRules(with: rules)
                publishDashboardDomains([.routing, .insight])
                controllerSession.endpointCache.rules = rules
                updatingRuleID = nil
                rulesSnapshotState = .available
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .success,
                    summary: localized("operation.rule_state_updated")
                )
                operationState = .success(
                    localized("operation.rule_state_updated"),
                    action: TrialCommandAction.setRuleState.title(language: presentationLanguage),
                    target: rule.payload
                )
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                ruleUpdateFailures[rule.id] = message
                updatingRuleID = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: localized("operation.rule_state_update_failed")
                )
                operationState = .error(
                    message,
                    action: TrialCommandAction.setRuleState.title(language: presentationLanguage),
                    target: rule.payload,
                    nextStep: localized("action.retry")
                )
            }
        }
    }

    func reloadProviders() {
        let actionTitle = TrialCommandAction.reloadProviders.title(language: presentationLanguage)
        guard providerUpdateAllProgress?.isRunning != true else {
            operationState = .partial(
                localized("command.disabled_busy"),
                action: actionTitle,
                target: selectedRouter?.displayName
            )
            return
        }

        providerTask?.cancel()
        providerUpdateAllProgress = nil

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_providers"))
            return
        }

        guard canRefreshSelectedRouter else {
            operationState = .partial(localized("operation.dashboard_updates_paused"))
            return
        }

        guard controllerSupportsLiveAction(.reloadProviders, router: router, action: actionTitle) else {
            return
        }

        let commandID = beginCommand(.reloadProviders, router: router, summary: localized("operation.reloading_providers"))
        reloadingProviders = true
        updatingProviderName = nil
        checkingProviderName = nil
        providersSnapshotState = .loading
        providerUpdateFailures = [:]
        providerHealthCheckFailures = [:]
        operationState = .working(localized("operation.reloading_providers_progress"), action: actionTitle, target: router.displayName)
        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]

        providerTask = Task {
            let providerSnapshots = await providerSnapshotOperation(router, secret)

            guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                return
            }

            applyProviderSnapshots(providerSnapshots)
            reloadingProviders = false
            providerTask = nil

            if providersSnapshotState.isUnavailable {
                finishCommand(commandID, routerID: router.id, status: .partial, summary: localized("operation.providers_unavailable"))
                operationState = .partial(localized("operation.providers_unavailable"), action: actionTitle, target: router.displayName, nextStep: localized("action.retry"))
            } else {
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.providers_reloaded"))
                operationState = .success(localized("operation.reloaded_providers \(dashboard.providers.count)"), action: actionTitle, target: router.displayName)
            }
        }
    }

    func refreshSelectedRouter() {
        requestImmediateSessionRefresh(isUserInitiated: true)
    }

    func testSelectedRouter() {
        refreshTask?.cancel()

        guard let router = selectedRouter else {
            connectionState = .disconnected
            operationState = .error(localized("operation.select_router_test"))
            return
        }

        let commandID = beginCommand(.test, router: router, summary: localized("operation.testing_base_endpoints"))
        let generation = controllerSession.generation
        operationState = .working(
            localized("operation.testing_endpoints_progress"),
            action: TrialCommandAction.test.title(language: presentationLanguage),
            target: router.displayName
        )

        if (router.controllerKind == .autoDetect || router.controllerKind == .stashCmfaCompatible),
           activeSessionControllerKind == nil {
            let credential = controllerSecrets[router.id]
            refreshTask = Task {
                do {
                    let detectedKind = try await probeControllerKind(
                        for: router,
                        credential: credential,
                        includeSurge: router.controllerKind == .autoDetect
                    )
                    guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else { return }

                    activeSessionControllerKind = detectedKind
                    controllerHealth = .checking(router: router)
                    connectionState = .connecting
                    liveStreamRequested = true
                    setLiveStreamState(.connecting)
                    refreshTask = nil
                    finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.capabilities_ready"))
                    operationState = .success(
                        localized("operation.capabilities_ready"),
                        action: TrialCommandAction.test.title(language: presentationLanguage),
                        target: router.displayName
                    )
                    startResolvedSession(for: router, generation: generation)
                } catch {
                    guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else { return }
                    let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                    activeSessionControllerKind = nil
                    connectionState = .failed(message)
                    setLiveStreamState(.failed(message))
                    controllerSession.state = .failed(message)
                    controllerSession.liveObservation.markFailure(partial: false)
                    refreshTask = nil
                    finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.base_endpoint_test_failed"))
                    operationState = .error(
                        message,
                        action: TrialCommandAction.test.title(language: presentationLanguage),
                        target: router.displayName,
                        nextStep: localized("action.edit_router")
                    )
                }
            }
            return
        }

        if runtimeControllerKind(for: router) == .surgeCompatible {
            let apiKey = controllerSecrets[router.id]
            refreshTask = Task {
                let client = SurgeHttpAPIClient(profile: router, apiKey: apiKey)
                do {
                    _ = try await client.outbound()
                    guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else { return }
                    if !dashboardSessionControls.dashboardUpdatesPaused {
                        controllerHealth = .versionReady(router: router, version: "Surge HTTP API")
                    }
                    finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.surge_probe_completed"))
                    operationState = .success(localized("operation.surge_probe_completed"), action: TrialCommandAction.test.title(language: presentationLanguage), target: router.displayName)
                } catch {
                    guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else { return }
                    let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                    finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.surge_probe_failed"))
                    operationState = .error(message, action: TrialCommandAction.test.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.edit_router"))
                }
            }
            return
        }

        closingConnectionID = nil
        closingConnectionGroupID = nil
        closingAllConnections = false
        updatingProviderName = nil
        checkingProviderName = nil
        isRefreshingDashboard = false
        reloadingRules = false
        reloadingProviders = false
        providerUpdateFailures = [:]
        providerHealthCheckFailures = [:]
        let secret = controllerSecrets[router.id]

        refreshTask = Task {
            let client = MihomoClient(profile: router, secret: secret)
            let baseProbe = await Self.probeBaseEndpoints(
                client: client,
                router: router,
                language: presentationLanguage
            )

            guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else { return }

            if let responses = baseProbe.responses {
                let compatibilityHealth = await Self.probeEnhancedCompatibilityEndpoints(
                    client: client,
                    health: baseProbe.health,
                    language: presentationLanguage
                )

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else { return }

                if !dashboardSessionControls.dashboardUpdatesPaused {
                    controllerHealth = compatibilityHealth
                    unifiedSnapshot = UnifiedControllerSnapshot.mihomoCompatible(
                        profile: router,
                        controllerType: effectiveUnifiedControllerType(for: router),
                        version: responses.version,
                        config: responses.config,
                        proxies: responses.proxies,
                        connections: responses.connections,
                        rules: controllerSession.endpointCache.rules,
                        providers: controllerSession.endpointCache.proxyProviders,
                        ruleProviders: controllerSession.endpointCache.ruleProviders
                    )
                }
                await recordSuccessfulConnection(for: router.id, generation: generation)
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else { return }
                let hasEnhancedFailure = compatibilityHealth.enhancedEndpoints.contains(where: { $0.status.isFailure })
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: hasEnhancedFailure ? .partial : .success,
                    summary: hasEnhancedFailure ? localized("operation.endpoints_ready_partial") : localized("operation.capabilities_ready")
                )
                if hasEnhancedFailure {
                    operationState = .partial(localized("operation.endpoints_ready_partial"), action: TrialCommandAction.test.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.refresh"))
                } else {
                    operationState = .success(localized("operation.probe_completed \(responses.version.version)"), action: TrialCommandAction.test.title(language: presentationLanguage), target: router.displayName)
                }
            } else {
                let message = baseProbe.health.failureMessage ?? localized("operation.base_endpoints_unavailable")
                finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.base_endpoint_test_failed"))
                operationState = .error(message, action: TrialCommandAction.test.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.edit_router"))
            }
        }
    }

    static func secretReference(for profileID: RouterProfile.ID) -> String {
        "keychain:\(profileID.uuidString)"
    }

    static func captureEndpoint<Response>(
        _ operation: () async throws -> Response
    ) async -> Result<Response, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    static func captureProviderSnapshots(client: MihomoClient) async -> ProviderSnapshotResults {
        async let proxyProviders = captureEndpoint { try await client.proxyProviders() }
        async let ruleProviders = captureEndpoint { try await client.ruleProviders() }

        return await (proxy: proxyProviders, rule: ruleProviders)
    }

    static func probeBaseEndpoints(
        client: MihomoClient,
        router: RouterProfile,
        language: AppLanguage = MicaStrings.appLanguage
    ) async -> BaseControllerProbe {
        async let versionResult = captureEndpoint { try await client.version() }
        async let configsResult = captureEndpoint { try await client.configs() }
        async let proxiesResult = captureEndpoint { try await client.proxies() }
        async let connectionsResult = captureEndpoint { try await client.connections() }

        let baseResults = await (
            version: versionResult,
            config: configsResult,
            proxies: proxiesResult,
            connections: connectionsResult
        )

        var health = ControllerHealthSnapshot.checking(router: router)
        health.set(.version, result: baseResults.version, language: language)
        health.set(.configs, result: baseResults.config, language: language)
        health.set(.proxies, result: baseResults.proxies, language: language)
        health.set(.connections, result: baseResults.connections, language: language)

        if case .success(let version) = baseResults.version {
            health.set(.version, status: .ready(version.version))
        }

        if case .success(let config) = baseResults.config {
            health.set(.configs, status: .ready(MicaStrings.displayMode(DashboardSnapshot.displayMode(config.mode), language: language)))
        }

        if case .success(let proxies) = baseResults.proxies {
            health.set(.proxies, status: .ready(MicaStrings.localized("endpoint.groups_count \(proxies.policyGroups.count)", language: language)))
        }

        if case .success(let connections) = baseResults.connections {
            health.set(.connections, status: .ready(MicaStrings.localized("endpoint.active_count \(connections.connections.count)", language: language)))
        }

        health.set(.rules, status: .idle)
        health.set(.providers, status: .idle)
        health.finalize()

        if case .success(let version) = baseResults.version,
           case .success(let config) = baseResults.config,
           case .success(let proxies) = baseResults.proxies,
           case .success(let connections) = baseResults.connections {
            return BaseControllerProbe(
                health: health,
                responses: BaseControllerResponses(
                    version: version,
                    config: config,
                    proxies: proxies,
                    connections: connections
                )
            )
        }

        return BaseControllerProbe(health: health, responses: nil)
    }

    private static func probeEnhancedCompatibilityEndpoints(
        client: MihomoClient,
        health: ControllerHealthSnapshot,
        language: AppLanguage = MicaStrings.appLanguage
    ) async -> ControllerHealthSnapshot {
        async let rulesResult = captureEndpoint { try await client.rules() }
        async let providersResult = captureProviderSnapshots(client: client)

        let enhancedResults = await (
            rules: rulesResult,
            providers: providersResult
        )

        var nextHealth = health

        switch enhancedResults.rules {
        case .success(let rules):
            nextHealth.set(.rules, status: .ready(MicaStrings.localized("endpoint.rules_count \(rules.rules.count)", language: language)))
        case .failure(let error):
            nextHealth.set(.rules, status: .failed(routerTrialFailureCategory(for: error).shortLabel(language: language)))
        }

        let providerCount: Int
        switch enhancedResults.providers.proxy {
        case .success(let providers):
            providerCount = providers.providerList.count
        case .failure(let error):
            providerCount = 0
            nextHealth.set(.providers, status: .failed(routerTrialFailureCategory(for: error).shortLabel(language: language)))
        }

        let ruleProviderCount: Int
        switch enhancedResults.providers.rule {
        case .success(let providers):
            ruleProviderCount = providers.providerList.count
        case .failure:
            ruleProviderCount = 0
        }

        if providerCount + ruleProviderCount > 0 {
            nextHealth.set(.providers, status: .ready(MicaStrings.localized("endpoint.providers_count \(providerCount + ruleProviderCount)", language: language)))
        }

        nextHealth.finalize()
        return nextHealth
    }

    static func surgeHealth(
        router: RouterProfile,
        snapshot: SurgeControlSnapshot,
        language: AppLanguage = MicaStrings.appLanguage
    ) -> ControllerHealthSnapshot {
        var health = ControllerHealthSnapshot.checking(router: router)
        health.set(.version, status: .ready("Surge HTTP API"))
        health.set(.configs, status: .ready(MicaStrings.displayMode(snapshot.outboundMode, language: language)))
        health.set(.proxies, status: .ready(MicaStrings.localized("endpoint.groups_count \(snapshot.policyGroups.count)", language: language)))
        health.set(.connections, status: .ready(MicaStrings.localized("endpoint.active_count \(snapshot.activeRequests.count)", language: language)))
        health.set(.rules, status: .ready(MicaStrings.localized("endpoint.rules_count \(snapshot.rules.count)", language: language)))
        health.set(.providers, status: .failed(MicaStrings.localized("trial.surge_provider_not_included", language: language)))
        health.finalize()
        return health
    }

    nonisolated static func shortFailureLabel(for error: Error, language: AppLanguage = MicaStrings.appLanguage) -> String {
        routerTrialFailureCategory(for: error).shortLabel(language: language)
    }

    nonisolated static func routerTrialFailureMessage(for error: Error, language: AppLanguage = MicaStrings.appLanguage) -> String {
        routerTrialFailureCategory(for: error).safeMessage(language: language)
    }

    nonisolated static func routerTrialFailureCategory(for error: Error) -> RouterTrialFailureCategory {
        RouterTrialFailureCategory(error: error)
    }
}
