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

typealias MihomoRuleDisableOperation = @Sendable (
    _ profile: RouterProfile,
    _ credential: String?,
    _ index: Int,
    _ disabled: Bool
) async throws -> RulesResponse

typealias SelectedRouterTestOperation = @Sendable (
    _ profile: RouterProfile,
    _ credential: String?,
    _ resolvedKind: ControllerKind
) async throws -> Void

typealias ImmediateSessionRefreshLaneOperation = @MainActor @Sendable (
    _ lane: SessionRefreshLane,
    _ profile: RouterProfile,
    _ generation: UUID,
    _ manual: Bool
) async -> Void

typealias ManualRefreshStreamRestartOperation = @MainActor @Sendable (
    _ profile: RouterProfile,
    _ generation: UUID
) -> Void

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

typealias MihomoConfigUpdateOperation = @Sendable (
    _ profile: RouterProfile,
    _ credential: String?,
    _ patch: MihomoConfigPatch
) async throws -> Void

typealias MihomoConfigSnapshotOperation = @Sendable (
    _ profile: RouterProfile,
    _ credential: String?
) async throws -> ConfigResponse

@MainActor
@Observable
final class AppModel {
    var routers: [RouterProfile]
    var selectedRouterID: RouterProfile.ID?
    var connectionState: ConnectionState
    @ObservationIgnored var dashboard: DashboardSnapshot
    var controllerMetadata: ControllerMetadataSnapshot
    var policyGroupCatalog: PolicyGroupCatalogSnapshot
    private(set) var policyGroupCatalogRevision: UInt64
    // Per-domain published snapshots split out of `dashboard` so a high-frequency
    // write to one domain (connections/logs every ~1s during downloads) does not
    // invalidate views observing an unrelated domain. Every dashboard publication
    // path re-derives the matching snapshot with an Equatable `!=` guard.
    var connectionsCatalog: ConnectionsCatalogSnapshot
    private(set) var connectionsStructureRevision: UInt64
    private(set) var connectionsMetricsRevision: UInt64
    var logsCatalog: LogsCatalogSnapshot
    var rulesCatalog: RulesCatalogSnapshot
    var providersCatalog: ProvidersCatalogSnapshot
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
    var isTestingSelectedRouter = false
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
    var unifiedSnapshot: UnifiedControllerSnapshot = .empty {
        didSet {
            let support = UnifiedControllerSupportSnapshot(snapshot: unifiedSnapshot)
            if support != unifiedControllerSupport {
                unifiedControllerSupport = support
            }
        }
    }
    private(set) var unifiedControllerSupport: UnifiedControllerSupportSnapshot?
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
            if oldValue.controllerID != controllerSession.controllerID
                || oldValue.generation != controllerSession.generation {
                liveSessionTasks.bind(to: controllerSession.controllerID.map {
                    LiveSessionRuntimeIdentity(
                        controllerID: $0,
                        generation: controllerSession.generation
                    )
                })
            }
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
    @ObservationIgnored private let mihomoConfigUpdateOperation: MihomoConfigUpdateOperation
    @ObservationIgnored private let mihomoConfigSnapshotOperation: MihomoConfigSnapshotOperation
    @ObservationIgnored private let providerUpdateOperation: ProviderUpdateOperation
    @ObservationIgnored private let providerSnapshotOperation: ProviderSnapshotOperation
    @ObservationIgnored private let mihomoRuleDisableOperation: MihomoRuleDisableOperation
    @ObservationIgnored private let selectedRouterTestOperation: SelectedRouterTestOperation?
    @ObservationIgnored private let immediateSessionRefreshLaneOperation: ImmediateSessionRefreshLaneOperation?
    @ObservationIgnored private let manualRefreshStreamRestartOperation: ManualRefreshStreamRestartOperation?
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
    @ObservationIgnored var lastPresentedRuntimeLogSequence: UInt64 = 0
    @ObservationIgnored var sessionRefreshCoordinator: SessionRefreshCoordinator?
    @ObservationIgnored var sessionMihomoClient: MihomoClient?
    @ObservationIgnored var sessionSurgeClient: SurgeHttpAPIClient?
    @ObservationIgnored var controllerSecrets: [RouterProfile.ID: String]
    @ObservationIgnored var didLoadPersistedState = false
    var didFinishLoadingPersistedState = false
    var isLoadingPersistedState = false
    var persistedStateLoadFailed = false
    var failedSecretRouterIDs: Set<RouterProfile.ID> = []
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
    @ObservationIgnored let liveSessionTasks = LiveSessionTaskSupervisor()
    @ObservationIgnored var liveRetryState = LiveStreamRetryState()
    @ObservationIgnored var selectedRouterRefreshOperationID: UUID?
    @ObservationIgnored var selectedRouterTestOperationID: UUID?
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
        mihomoConfigUpdateOperation: @escaping MihomoConfigUpdateOperation = { profile, credential, patch in
            try await MihomoClient(profile: profile, secret: credential).updateConfigs(patch)
        },
        mihomoConfigSnapshotOperation: @escaping MihomoConfigSnapshotOperation = { profile, credential in
            try await MihomoClient(profile: profile, secret: credential).configs()
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
        mihomoRuleDisableOperation: @escaping MihomoRuleDisableOperation = { profile, credential, index, disabled in
            let client = MihomoClient(profile: profile, secret: credential)
            try await client.setRuleDisabled(index: index, disabled: disabled)
            return try await client.rules()
        },
        selectedRouterTestOperation: SelectedRouterTestOperation? = nil,
        immediateSessionRefreshLaneOperation: ImmediateSessionRefreshLaneOperation? = nil,
        manualRefreshStreamRestartOperation: ManualRefreshStreamRestartOperation? = nil,
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
        self.connectionsStructureRevision = 0
        self.connectionsMetricsRevision = 0
        self.logsCatalog = .empty
        self.rulesCatalog = RulesCatalogSnapshot(dashboard: dashboard)
        self.providersCatalog = ProvidersCatalogSnapshot(dashboard: dashboard)
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
        self.mihomoConfigUpdateOperation = mihomoConfigUpdateOperation
        self.mihomoConfigSnapshotOperation = mihomoConfigSnapshotOperation
        self.providerUpdateOperation = providerUpdateOperation
        self.providerSnapshotOperation = providerSnapshotOperation
        self.mihomoRuleDisableOperation = mihomoRuleDisableOperation
        self.selectedRouterTestOperation = selectedRouterTestOperation
        self.immediateSessionRefreshLaneOperation = immediateSessionRefreshLaneOperation
        self.manualRefreshStreamRestartOperation = manualRefreshStreamRestartOperation
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

    func runImmediateSessionRefreshLane(
        _ lane: SessionRefreshLane,
        router: RouterProfile,
        generation: UUID,
        manual: Bool
    ) async {
        if let immediateSessionRefreshLaneOperation {
            await immediateSessionRefreshLaneOperation(lane, router, generation, manual)
        } else {
            await performSessionRefresh(
                lane,
                router: router,
                generation: generation,
                manual: manual
            )
        }
    }

    func updateMihomoConfig(
        profile: RouterProfile,
        credential: String?,
        patch: MihomoConfigPatch
    ) async throws {
        try await mihomoConfigUpdateOperation(profile, credential, patch)
    }

    func loadMihomoConfig(
        profile: RouterProfile,
        credential: String?
    ) async throws -> ConfigResponse {
        try await mihomoConfigSnapshotOperation(profile, credential)
    }

    func runSelectedRouterTestOverride(
        router: RouterProfile,
        credential: String?,
        resolvedKind: ControllerKind
    ) async throws -> Bool {
        guard let selectedRouterTestOperation else { return false }
        try await selectedRouterTestOperation(router, credential, resolvedKind)
        return true
    }

    var hasSelectedRouterTestOverride: Bool {
        selectedRouterTestOperation != nil
    }

    func restartStreamsForManualRefresh(
        router: RouterProfile,
        generation: UUID
    ) {
        if let manualRefreshStreamRestartOperation {
            manualRefreshStreamRestartOperation(router, generation)
        } else {
            restartRequestedMihomoLiveStreamsForManualRefresh(
                router: router,
                generation: generation
            )
        }
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
        if structureChanged {
            advanceConnectionsStructureRevision()
        }
        if metricsChanged {
            advanceConnectionsMetricsRevision()
        }
    }

    func advanceConnectionsStructureRevision() {
        connectionsStructureRevision &+= 1
    }

    func advanceConnectionsMetricsRevision() {
        connectionsMetricsRevision &+= 1
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

    func synchronizeRulesCatalog() {
        let next = RulesCatalogSnapshot(dashboard: dashboard)
        guard next != rulesCatalog else { return }
        rulesCatalog = next
    }

    func synchronizeProvidersCatalog() {
        let next = ProvidersCatalogSnapshot(dashboard: dashboard)
        guard next != providersCatalog else { return }
        providersCatalog = next
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
        if domains.contains(.rules) {
            synchronizeRulesCatalog()
        }
        if domains.contains(.providers) {
            synchronizeProvidersCatalog()
        }
        if domains.contains(.insight) {
            synchronizeInsightCatalog()
        }
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

    /// Readiness and capability admission for an already-current live intent.
    /// Persisted handlers first validate their captured identity through
    /// `matchesCurrentCommandScope`; this gate may then publish a truthful
    /// outcome when the current session cannot run the requested action.
    func admitLiveActionIntent(
        _ action: UnifiedControllerAction,
        router: RouterProfile,
        action actionTitle: String,
        requiresUnpausedPresentation: Bool = false
    ) -> Bool {
        guard isCurrentSession(routerID: router.id, generation: controllerSession.generation) else {
            return false
        }
        guard controllerSessionPresentation.state.allowsLiveCommands else {
            operationState = .partial(
                localized("command.disabled_unavailable"),
                action: actionTitle,
                target: router.displayName
            )
            return false
        }
        if requiresUnpausedPresentation, dashboardSessionControls.dashboardUpdatesPaused {
            operationState = .partial(
                localized("operation.dashboard_updates_paused"),
                action: actionTitle,
                target: router.displayName
            )
            return false
        }
        return controllerSupports(action, router: router, action: actionTitle)
    }

    func setMode(_ mode: String, scope: LiveCommandScope) {
        guard matchesCurrentCommandScope(scope),
              mode != sessionActionDashboard.mode,
              let router = selectedRouter,
              !changingMode,
              modeTask == nil else { return }

        if modeChangeAction(for: router) == .setOutboundMode {
            setSurgeOutboundMode(mode)
            return
        }

        guard canBeginLiveAction(.changeMode, router: router, familyInFlight: false) else { return }

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
                modeTask = nil
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.mode_changed_summary"))
                operationState = .success(localized("operation.mode_changed \(MicaStrings.displayMode(dashboard.mode, language: presentationLanguage))"), action: TrialCommandAction.setMode.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                changingMode = false
                modeTask = nil
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

    func selectNode(
        _ node: String,
        in groupID: String,
        scope: LiveCommandScope
    ) {
        guard matchesCurrentCommandScope(scope),
              let router = selectedRouter,
              switchTask == nil,
              canBeginLiveAction(.switchPolicy, router: router, familyInFlight: hasSwitchOperationInFlight) else { return }

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
                switchTask = nil
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
                switchTask = nil
            }
        }
    }

    func clearFixedSelection(
        in groupID: String,
        scope: LiveCommandScope
    ) {
        guard matchesCurrentCommandScope(scope),
              let router = selectedRouter,
              switchTask == nil,
              canBeginLiveAction(
                .clearFixedSelection,
                router: router,
                familyInFlight: hasSwitchOperationInFlight
              ) else { return }

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
                switchTask = nil
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
                switchTask = nil
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

    func measureDelay(in groupID: String, scope: LiveCommandScope) {
        guard matchesCurrentCommandScope(scope),
              let router = selectedRouter,
              delayTask == nil,
              canBeginLiveAction(.testLatency, router: router, familyInFlight: hasDelayOperationInFlight) else { return }

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
                delayTask = nil
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.updated_delay"))
                operationState = .success(localized("operation.updated_delay"), action: TrialCommandAction.testDelay.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                measuringDelayGroupID = nil
                delayTask = nil
                finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.delay_test_failed"))
                operationState = .error(Self.routerTrialFailureMessage(for: error, language: presentationLanguage), action: TrialCommandAction.testDelay.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry"))
            }
        }
    }

    func measureDelay(
        for node: String,
        in groupID: String,
        scope: LiveCommandScope
    ) {
        guard matchesCurrentCommandScope(scope),
              let router = selectedRouter,
              delayTask == nil,
              canBeginLiveAction(.testLatency, router: router, familyInFlight: hasDelayOperationInFlight) else { return }

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
                delayTask = nil
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
                delayTask = nil
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
        guard let router = selectedRouter,
              !hasConnectionOperationInFlight,
              connectionTask == nil else { return }

        let actionTitle = TrialCommandAction.closeConnection.title(
            language: presentationLanguage
        )
        let runtimeKind = runtimeControllerKind(for: router)
        let closeAction: UnifiedControllerAction = runtimeKind == .surgeCompatible
            ? .killActiveRequest
            : .closeConnection
        guard canBeginLiveAction(
            closeAction,
            router: router,
            familyInFlight: runtimeKind == .surgeCompatible
                ? hasSurgeOperationInFlight
                : false
        ) else { return }

        guard !connection.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            operationState = .partial(
                localized("operation.connection_id_unavailable"),
                action: actionTitle,
                target: router.displayName
            )
            return
        }
        guard let target = ConnectionMutationTargetResolver.resolve(
            requested: connection,
            currentConnections: connectionsCatalog.connections
        ) else { return }
        let connectionID = target.id

        if runtimeKind == .surgeCompatible {
            closeSurgeProjectedConnection(target)
            return
        }

        if runtimeKind == .singBoxCompatible {
            closeSingBoxConnection(target, router: router)
            return
        }

        let commandID = beginCommand(.closeConnection, router: router, summary: localized("operation.closing_connection"))
        closingConnectionID = target.id
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
                recordClosedSessionConnections([target])
                removeSessionConnections([target])

                let connections = try await mihomoConnectionsSnapshotOperation(router, secret)

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                mutateSessionDashboard(publishing: [.connections, .insight]) {
                    $0.replaceConnections(with: connections)
                }
                closingConnectionID = nil
                connectionTask = nil
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.closed_connection"))
                operationState = .success(localized("operation.closed_connection"), action: actionTitle, target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                closingConnectionID = nil
                connectionTask = nil
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
        guard let router = selectedRouter,
              !hasConnectionOperationInFlight,
              connectionTask == nil else { return }

        let actionTitle = TrialCommandAction.closeConnectionGroup.title(
            language: presentationLanguage
        )
        let runtimeKind = runtimeControllerKind(for: router)
        let closeAction: UnifiedControllerAction = runtimeKind == .surgeCompatible
            ? .killActiveRequest
            : .closeConnection
        guard canBeginLiveAction(
            closeAction,
            router: router,
            familyInFlight: runtimeKind == .surgeCompatible
                ? hasSurgeOperationInFlight
                : false
        ) else { return }

        guard !connections.isEmpty else {
            operationState = .success(
                localized("operation.no_active_connections"),
                action: actionTitle,
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
                action: actionTitle,
                target: groupLabel
            )
            return
        }
        guard let currentConnections = ConnectionMutationTargetResolver.resolve(
            requested: closableConnections,
            currentConnections: connectionsCatalog.connections
        ) else { return }

        if runtimeKind == .singBoxCompatible {
            operationState = .partial(
                localized("capability.unsupported_sing_box_data"),
                action: actionTitle,
                target: groupLabel
            )
            return
        }

        let commandID = beginCommand(
            .closeConnectionGroup,
            router: router,
            summary: localized("operation.closing_connection_group \(currentConnections.count)")
        )
        closingConnectionID = nil
        closingConnectionGroupID = groupID
        closingAllConnections = false
        operationState = .working(
            localized("operation.closing_connection_group_progress \(currentConnections.count) \(groupLabel)"),
            action: actionTitle,
            target: router.displayName
        )

        let generation = controllerSession.generation
        let credential = controllerSecrets[router.id]

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

                    for connection in currentConnections {
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
                    for connection in currentConnections {
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
                connectionTask = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .success,
                    summary: localized("operation.closed_connection_group \(closed.count)")
                )
                operationState = .success(
                    localized("operation.closed_connection_group \(closed.count)"),
                    action: actionTitle,
                    target: router.displayName
                )
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                recordClosedSessionConnections(closed)
                removeSessionConnections(closed)
                closingConnectionGroupID = nil
                connectionTask = nil
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
                        action: actionTitle,
                        target: router.displayName,
                        nextStep: localized("action.refresh")
                    )
                } else {
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .partial,
                        summary: localized("operation.close_connection_group_partial \(closed.count) \(currentConnections.count)")
                    )
                    operationState = .partial(
                        localized("operation.close_connection_group_partial \(closed.count) \(currentConnections.count)"),
                        action: actionTitle,
                        target: router.displayName,
                        nextStep: failure
                    )
                }
            }
        }
    }

    func closeAllConnections() {
        guard let router = selectedRouter,
              !hasConnectionOperationInFlight,
              connectionTask == nil else { return }

        let runtimeKind = runtimeControllerKind(for: router)
        let closeAction: UnifiedControllerAction = runtimeKind == .surgeCompatible
            ? .killActiveRequest
            : .closeAllConnections
        guard canBeginLiveAction(closeAction, router: router, familyInFlight: false) else { return }

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
                connectionTask = nil
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.closed_all"))
                operationState = .success(localized("operation.closed_all"), action: TrialCommandAction.closeAll.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                closingAllConnections = false
                connectionTask = nil
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
        let actionTitle = TrialCommandAction.providerUpdateAll.title(language: presentationLanguage)
        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_providers"))
            return
        }

        let generation = controllerSession.generation
        guard isCurrentSession(routerID: router.id, generation: generation) else { return }

        guard !dashboardSessionControls.dashboardUpdatesPaused else {
            operationState = .partial(
                localized("operation.dashboard_updates_paused"),
                action: actionTitle,
                target: router.displayName
            )
            return
        }

        guard !hasProviderOperationInFlight, providerTask == nil, !isBusy else {
            operationState = .partial(
                localized("command.disabled_busy"),
                action: actionTitle,
                target: router.displayName
            )
            return
        }

        guard admitLiveActionIntent(
            .updateProvider,
            router: router,
            action: actionTitle,
            requiresUnpausedPresentation: true
        ) else { return }

        let providers = providersCatalog.providers.filter(\.updatable)
        guard let firstProvider = providers.first else {
            operationState = .partial(
                localized("traffic.no_updatable_providers"),
                action: actionTitle,
                target: router.displayName
            )
            return
        }

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

    func updateProxyProvider(_ provider: ProxyProviderViewState, scope: LiveCommandScope) {
        guard matchesCurrentCommandScope(scope) else { return }
        let actionTitle = TrialCommandAction.providerUpdate.title(language: presentationLanguage)
        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_provider"))
            return
        }

        guard !hasProviderOperationInFlight, providerTask == nil else {
            operationState = .partial(
                localized("command.disabled_busy"),
                action: actionTitle,
                target: router.displayName
            )
            return
        }

        guard admitLiveActionIntent(
            .updateProvider,
            router: router,
            action: actionTitle,
            requiresUnpausedPresentation: true
        ) else { return }

        guard provider.updatable else {
            operationState = .partial(
                localized("traffic.provider_not_updatable"),
                action: actionTitle,
                target: provider.name
            )
            return
        }

        guard providersCatalog.providers.contains(provider) else { return }

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

    func healthCheckProxyProvider(_ provider: ProxyProviderViewState, scope: LiveCommandScope) {
        guard matchesCurrentCommandScope(scope) else { return }
        let actionTitle = TrialCommandAction.providerHealthCheck.title(language: presentationLanguage)
        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_provider_health"))
            return
        }

        guard !hasProviderOperationInFlight, providerTask == nil else {
            operationState = .partial(
                localized("command.disabled_busy"),
                action: actionTitle,
                target: router.displayName
            )
            return
        }

        guard admitLiveActionIntent(
            .healthCheckProvider,
            router: router,
            action: actionTitle,
            requiresUnpausedPresentation: true
        ) else { return }

        guard provider.supportsHealthCheck else {
            operationState = .partial(
                localized("traffic.provider_health_check_unavailable"),
                action: actionTitle,
                target: provider.name
            )
            return
        }

        guard providersCatalog.providers.contains(provider) else { return }

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
            publishDashboardDomains([.providers, .insight])
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
        guard let router = selectedRouter,
              !hasRuleOperationInFlight,
              rulesTask == nil,
              canBeginLiveAction(
                .reloadRules,
                router: router,
                familyInFlight: false,
                requiresUnpausedPresentation: true
              ) else { return }

        if runtimeControllerKind(for: router) == .surgeCompatible {
            guard !hasSurgeOperationInFlight, surgeTask == nil else { return }
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
                publishDashboardDomains([.rules, .insight])
                controllerSession.endpointCache.rules = rules
                rulesSnapshotState = .available
                var nextHealth = controllerHealth
                nextHealth.set(.rules, status: .ready(localized("endpoint.rules_count \(rules.rules.count)")))
                nextHealth.finalize()
                controllerHealth = nextHealth
                reloadingRules = false
                rulesTask = nil
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
                rulesTask = nil
                finishCommand(commandID, routerID: router.id, status: .partial, summary: localized("operation.rules_unavailable"))
                operationState = .partial(localized("operation.rules_unavailable"), action: TrialCommandAction.reloadRules.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry"))
            }
        }
    }

    func setRuleDisabled(
        _ rule: RuleViewState,
        disabled: Bool,
        scope: LiveCommandScope
    ) {
        let actionTitle = TrialCommandAction.setRuleState.title(language: presentationLanguage)
        guard matchesCurrentCommandScope(scope),
              let router = selectedRouter,
              !hasRuleOperationInFlight,
              rulesTask == nil else { return }

        guard admitLiveActionIntent(
            .setRuleDisabled,
            router: router,
            action: actionTitle,
            requiresUnpausedPresentation: true
        ) else { return }

        guard rule.hasMutableExtra, rule.index != nil else {
            operationState = .partial(localized("operation.rule_state_not_supported"))
            return
        }

        guard let target = RuleMutationTargetResolver.resolve(
            requested: rule,
            currentRules: rulesCatalog.rules
        ), let index = target.index else { return }

        let commandID = beginCommand(
            .setRuleState,
            router: router,
            summary: localized("operation.updating_rule_state")
        )
        updatingRuleID = target.id
        ruleUpdateFailures.removeValue(forKey: target.id)
        operationState = .working(
            localized("operation.updating_rule_state"),
            action: actionTitle,
            target: target.payload
        )

        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]
        rulesTask = Task {
            do {
                let rules = try await mihomoRuleDisableOperation(
                    router,
                    secret,
                    index,
                    disabled
                )

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                dashboard.replaceRules(with: rules)
                publishDashboardDomains([.rules, .insight])
                controllerSession.endpointCache.rules = rules
                updatingRuleID = nil
                rulesTask = nil
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
                    target: target.payload
                )
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                ruleUpdateFailures[target.id] = message
                updatingRuleID = nil
                rulesTask = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: localized("operation.rule_state_update_failed")
                )
                operationState = .error(
                    message,
                    action: TrialCommandAction.setRuleState.title(language: presentationLanguage),
                    target: target.payload,
                    nextStep: localized("action.retry")
                )
            }
        }
    }

    func reloadProviders() {
        let actionTitle = TrialCommandAction.reloadProviders.title(language: presentationLanguage)
        guard let router = selectedRouter,
              !hasProviderOperationInFlight,
              providerTask == nil,
              canBeginLiveAction(
                .reloadProviders,
                router: router,
                familyInFlight: false,
                requiresUnpausedPresentation: true
              ) else { return }

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
        if canRetryPersistedStateLoading {
            loadPersistedState()
            return
        }
        requestImmediateSessionRefresh(isUserInitiated: true)
    }

    func testSelectedRouter() {
        guard canTestSelectedRouter,
              let router = selectedRouter,
              controllerSessionPresentation.controllerID == router.id else { return }

        let commandID = beginCommand(.test, router: router, summary: localized("operation.testing_base_endpoints"))
        let generation = controllerSession.generation
        let operationID = UUID()
        selectedRouterTestOperationID = operationID
        isTestingSelectedRouter = true
        operationState = .working(
            localized("operation.testing_endpoints_progress"),
            action: TrialCommandAction.test.title(language: presentationLanguage),
            target: router.displayName
        )

        if hasSelectedRouterTestOverride {
            let credential = controllerSecrets[router.id]
            let resolvedKind = runtimeControllerKind(for: router)
            refreshTask = Task {
                defer {
                    finishSelectedRouterTest(
                        operationID: operationID,
                        routerID: router.id,
                        generation: generation
                    )
                }
                do {
                    _ = try await runSelectedRouterTestOverride(
                        router: router,
                        credential: credential,
                        resolvedKind: resolvedKind
                    )
                    guard isCurrentSession(routerID: router.id, generation: generation),
                          !Task.isCancelled else { return }
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .success,
                        summary: localized("operation.capabilities_ready")
                    )
                    operationState = .success(
                        localized("operation.capabilities_ready"),
                        action: TrialCommandAction.test.title(language: presentationLanguage),
                        target: router.displayName
                    )
                } catch {
                    guard isCurrentSession(routerID: router.id, generation: generation),
                          !Task.isCancelled else { return }
                    let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .failed,
                        summary: localized("operation.base_endpoint_test_failed")
                    )
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

        if (router.controllerKind == .autoDetect || router.controllerKind == .stashCmfaCompatible),
           activeSessionControllerKind == nil {
            let credential = controllerSecrets[router.id]
            refreshTask = Task {
                defer {
                    finishSelectedRouterTest(
                        operationID: operationID,
                        routerID: router.id,
                        generation: generation
                    )
                }
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
                defer {
                    finishSelectedRouterTest(
                        operationID: operationID,
                        routerID: router.id,
                        generation: generation
                    )
                }
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

        let secret = controllerSecrets[router.id]

        refreshTask = Task {
            defer {
                finishSelectedRouterTest(
                    operationID: operationID,
                    routerID: router.id,
                    generation: generation
                )
            }
            let client = sessionMihomoClient
                ?? MihomoClient(profile: router, secret: secret)
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

    private func finishSelectedRouterTest(
        operationID: UUID,
        routerID: RouterProfile.ID,
        generation: UUID
    ) {
        guard selectedRouterTestOperationID == operationID,
              isCurrentSession(routerID: routerID, generation: generation) else {
            return
        }
        selectedRouterTestOperationID = nil
        isTestingSelectedRouter = false
        refreshTask = nil
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
