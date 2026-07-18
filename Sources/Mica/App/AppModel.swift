import AppKit
import Foundation
import MicaCore
import SwiftUI

struct PolicyNodeLatencyTestTarget: Equatable, Sendable {
    var groupID: String
    var nodeName: String
}

@MainActor
@Observable
final class AppModel {
    var routers: [RouterProfile]
    var selectedRouterID: RouterProfile.ID?
    var connectionState: ConnectionState
    var dashboard: DashboardSnapshot
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
    var policyGroupPresentation = PolicyGroupPresentation()
    var runningRuntimeOperationID: String?
    var controllerSession = ControllerSession()
    var activeSessionControllerKind: ControllerKind?
    var controllerLogLevel: LogSessionLevel = .all
    var presentationLanguage: AppLanguage = MicaStrings.appLanguage

    var dashboardSessionControls: DashboardSessionControls {
        get { controllerSession.controls }
        set { controllerSession.controls = newValue }
    }

    let profileStore: any RouterProfileStore
    let secretStore: any SecretStore
    @ObservationIgnored let userDefaults: UserDefaults
    @ObservationIgnored var controllerSecrets: [RouterProfile.ID: String]
    @ObservationIgnored var didLoadPersistedState = false
    @ObservationIgnored var mainWindowCount = 0
    @ObservationIgnored var sessionSuspendedForSleep = false

    private var localizationLocale: Locale {
        MicaStrings.locale
    }

    func localized(_ key: String.LocalizationValue) -> String {
        MicaStrings.localized(key, language: presentationLanguage)
    }
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
    @ObservationIgnored var liveRetryAttempt = 0
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
        userDefaults: UserDefaults = .standard
    ) {
        let initialPresentationLanguage = MicaStrings.appLanguage
        self.routers = routers
        self.selectedRouterID = selectedRouterID
        self.connectionState = connectionState
        self.dashboard = dashboard
        self.controllerSecrets = controllerSecrets
        self.operationState = operationState
        self.profileStore = profileStore
        self.secretStore = secretStore
        self.userDefaults = userDefaults
        self.controllerHealth = .idle(language: initialPresentationLanguage)
        self.presentationLanguage = initialPresentationLanguage
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

        guard controllerSupports(.changeMode, router: router, action: TrialCommandAction.setMode.title(language: presentationLanguage)) else {
            return
        }

        if runtimeControllerKind(for: router) == .singBoxCompatible {
            setSingBoxMode(mode, router: router)
            return
        }

        let commandID = beginCommand(.setMode, router: router, summary: localized("operation.changing_mode"))
        let previousMode = sessionActionDashboard.mode
        mutateSessionDashboard { $0.mode = mode }
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

                mutateSessionDashboard { $0.replaceConfig(with: config) }
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
                    mutateSessionDashboard { $0.mode = previousMode }
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
        switchTask?.cancel()
        clearingFixedGroupID = nil

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_switch"))
            return
        }

        guard controllerSupports(.switchPolicy, router: router, action: TrialCommandAction.switchNode.title(language: presentationLanguage)) else {
            return
        }

        guard let previousNode = sessionActionDashboard.groups.first(where: { $0.id == groupID })?.selected else {
            operationState = .error(localized("operation.policy_group_gone \(groupID)"))
            return
        }

        if runtimeControllerKind(for: router) == .singBoxCompatible {
            selectSingBoxNode(node, in: groupID, router: router)
            return
        }

        let commandID = beginCommand(.switchNode, router: router, summary: localized("operation.switching_route"))
        mutateSessionDashboard { dashboard in
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

                mutateSessionDashboard { $0.replaceGroups(with: proxies) }
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
                    mutateSessionDashboard { dashboard in
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

        guard controllerSupports(
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

                mutateSessionDashboard { $0.replaceGroups(with: proxies) }
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
                    mutateSessionDashboard { dashboard in
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

        guard controllerSupports(.testLatency, router: router, action: TrialCommandAction.testDelay.title(language: presentationLanguage)) else {
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

                mutateSessionDashboard { $0.replaceDelays(response.delay, in: groupID) }
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

        guard controllerSupports(
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

                mutateSessionDashboard { $0.replaceDelay(delay, for: node, in: groupID) }
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
        connectionTask?.cancel()

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_close"))
            return
        }

        if runtimeControllerKind(for: router) == .surgeCompatible {
            closeSurgeProjectedConnection(connection)
            return
        }

        if runtimeControllerKind(for: router) == .singBoxCompatible {
            closeSingBoxConnection(connection, router: router)
            return
        }

        guard controllerSupports(.closeConnection, router: router, action: TrialCommandAction.closeConnection.title(language: presentationLanguage)) else {
            return
        }

        let commandID = beginCommand(.closeConnection, router: router, summary: localized("operation.closing_connection"))
        closingConnectionID = connection.id
        closingConnectionGroupID = nil
        closingAllConnections = false
        operationState = .working(localized("operation.closing_connection_progress"), action: TrialCommandAction.closeConnection.title(language: presentationLanguage), target: router.displayName)
        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]

        connectionTask = Task {
            let client = MihomoClient(profile: router, secret: secret)

            do {
                try await client.closeConnection(id: connection.id)
                let connections = try await client.connections()

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                recordClosedSessionConnections([connection])
                mutateSessionDashboard { $0.replaceConnections(with: connections) }
                closingConnectionID = nil
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.closed_connection"))
                operationState = .success(localized("operation.closed_connection"), action: TrialCommandAction.closeConnection.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                closingConnectionID = nil
                finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.close_connection_failed"))
                operationState = .error(Self.routerTrialFailureMessage(for: error, language: presentationLanguage), action: TrialCommandAction.closeConnection.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.refresh"))
            }
        }
    }

    func closeConnectionGroup(
        _ connections: [ConnectionSnapshot],
        groupID: String,
        groupLabel: String
    ) {
        connectionTask?.cancel()

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

        if runtimeControllerKind(for: router) == .singBoxCompatible {
            operationState = .partial(
                localized("capability.unsupported_sing_box_data"),
                action: TrialCommandAction.closeConnectionGroup.title(language: presentationLanguage),
                target: groupLabel
            )
            return
        }

        guard controllerSupports(
            runtimeControllerKind(for: router) == .surgeCompatible ? .killActiveRequest : .closeConnection,
            router: router,
            action: TrialCommandAction.closeConnectionGroup.title(language: presentationLanguage)
        ) else {
            return
        }

        let commandID = beginCommand(
            .closeConnectionGroup,
            router: router,
            summary: localized("operation.closing_connection_group \(connections.count)")
        )
        closingConnectionID = nil
        closingConnectionGroupID = groupID
        closingAllConnections = false
        operationState = .working(
            localized("operation.closing_connection_group_progress \(connections.count) \(groupLabel)"),
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
                            surgeSnapshot.activeRequests,
                            DashboardSnapshot.surgeRequestDisplayIDs(for: surgeSnapshot.activeRequests)
                        ).map { request, projectedID in (projectedID, request) }
                    )
                    let client = SurgeHttpAPIClient(profile: router, apiKey: credential)

                    for connection in connections {
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
                    var snapshot = surgeSnapshot
                    snapshot.activeRequests = activeRequests.requests
                    snapshot.checkedAt = Date()
                    applySurgeSnapshot(snapshot, router: router)
                } else {
                    let client = MihomoClient(profile: router, secret: credential)
                    for connection in connections {
                        try Task.checkCancellation()
                        try await client.closeConnection(id: connection.id)
                        closed.append(connection)
                    }

                    let latest = try await client.connections()
                    guard isCurrentSession(routerID: router.id, generation: generation),
                          !Task.isCancelled else {
                        return
                    }
                    mutateSessionDashboard { $0.replaceConnections(with: latest) }
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
                        summary: localized("operation.close_connection_group_partial \(closed.count) \(connections.count)")
                    )
                    operationState = .partial(
                        localized("operation.close_connection_group_partial \(closed.count) \(connections.count)"),
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
        guard controllerSupports(closeAction, router: router, action: TrialCommandAction.closeAll.title(language: presentationLanguage)) else {
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
            let client = MihomoClient(profile: router, secret: secret)

            do {
                try await client.closeAllConnections()
                let connections = try await client.connections()

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                recordClosedSessionConnections(closingSnapshot)
                mutateSessionDashboard { $0.replaceConnections(with: connections) }
                closingAllConnections = false
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.closed_all"))
                operationState = .success(localized("operation.closed_all"), action: TrialCommandAction.closeAll.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                closingAllConnections = false
                finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.close_all_failed"))
                operationState = .error(Self.routerTrialFailureMessage(for: error, language: presentationLanguage), action: TrialCommandAction.closeAll.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.refresh"))
            }
        }
    }

    func updateProxyProvider(_ provider: ProxyProviderViewState) {
        providerTask?.cancel()
        checkingProviderName = nil

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_provider"))
            return
        }

        guard canRefreshSelectedRouter else {
            operationState = .partial(localized("operation.dashboard_updates_paused"))
            return
        }

        guard controllerSupports(.updateProvider, router: router, action: TrialCommandAction.providerUpdate.title(language: presentationLanguage)) else {
            return
        }

        guard provider.updatable else {
            operationState = .partial(
                localized("traffic.provider_not_updatable"),
                action: TrialCommandAction.providerUpdate.title(language: presentationLanguage),
                target: provider.name
            )
            return
        }

        let commandID = beginCommand(.providerUpdate, router: router, summary: localized("operation.updating_provider"))
        updatingProviderName = provider.id
        reloadingProviders = false
        providerUpdateFailures.removeValue(forKey: provider.id)
        operationState = .working(localized("operation.updating_provider_progress"), action: TrialCommandAction.providerUpdate.title(language: presentationLanguage), target: router.displayName)
        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]

        providerTask = Task {
            let client = MihomoClient(profile: router, secret: secret)

            do {
                switch provider.kind {
                case .proxy:
                    try await client.updateProxyProvider(name: provider.name)
                case .rule:
                    try await client.updateRuleProvider(name: provider.name)
                }

                let providerSnapshots = await Self.captureProviderSnapshots(client: client)

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                applyProviderSnapshots(providerSnapshots)
                updatingProviderName = nil
                if providersSnapshotState.isUnavailable {
                    finishCommand(commandID, routerID: router.id, status: .partial, summary: localized("operation.providers_unavailable"))
                    operationState = .partial(localized("operation.providers_unavailable"), action: TrialCommandAction.providerUpdate.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.refresh"))
                } else {
                    finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.updated_provider"))
                    operationState = .success(localized("operation.updated_provider"), action: TrialCommandAction.providerUpdate.title(language: presentationLanguage), target: router.displayName)
                }
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                providerUpdateFailures[provider.id] = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                updatingProviderName = nil
                finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.provider_update_failed"))
                operationState = .error(Self.routerTrialFailureMessage(for: error, language: presentationLanguage), action: TrialCommandAction.providerUpdate.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry"))
            }
        }
    }

    func healthCheckProxyProvider(_ provider: ProxyProviderViewState) {
        providerTask?.cancel()
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

        guard controllerSupports(
            .healthCheckProvider,
            router: router,
            action: TrialCommandAction.providerHealthCheck.title(language: presentationLanguage)
        ) else {
            return
        }

        guard provider.supportsHealthCheck else {
            operationState = .partial(
                localized("traffic.provider_health_check_unavailable"),
                action: TrialCommandAction.providerHealthCheck.title(language: presentationLanguage),
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
            action: TrialCommandAction.providerHealthCheck.title(language: presentationLanguage),
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
                if providersSnapshotState.isUnavailable {
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .partial,
                        summary: localized("operation.provider_health_checked_refresh_failed")
                    )
                    operationState = .partial(
                        localized("operation.provider_health_checked_refresh_failed"),
                        action: TrialCommandAction.providerHealthCheck.title(language: presentationLanguage),
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
                        action: TrialCommandAction.providerHealthCheck.title(language: presentationLanguage),
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
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: localized("operation.provider_health_check_failed")
                )
                operationState = .error(
                    message,
                    action: TrialCommandAction.providerHealthCheck.title(language: presentationLanguage),
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

        guard controllerSupports(.reloadRules, router: router, action: TrialCommandAction.reloadRules.title(language: presentationLanguage)) else {
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

        guard controllerSupports(
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
        providerTask?.cancel()

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_providers"))
            return
        }

        guard canRefreshSelectedRouter else {
            operationState = .partial(localized("operation.dashboard_updates_paused"))
            return
        }

        guard controllerSupports(.reloadProviders, router: router, action: TrialCommandAction.reloadProviders.title(language: presentationLanguage)) else {
            return
        }

        let commandID = beginCommand(.reloadProviders, router: router, summary: localized("operation.reloading_providers"))
        reloadingProviders = true
        updatingProviderName = nil
        checkingProviderName = nil
        providersSnapshotState = .loading
        providerUpdateFailures = [:]
        providerHealthCheckFailures = [:]
        operationState = .working(localized("operation.reloading_providers_progress"), action: TrialCommandAction.reloadProviders.title(language: presentationLanguage), target: router.displayName)
        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]

        providerTask = Task {
            let client = MihomoClient(profile: router, secret: secret)

            let providerSnapshots = await Self.captureProviderSnapshots(client: client)

            guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                return
            }

            applyProviderSnapshots(providerSnapshots)
            reloadingProviders = false

            if providersSnapshotState.isUnavailable {
                finishCommand(commandID, routerID: router.id, status: .partial, summary: localized("operation.providers_unavailable"))
                operationState = .partial(localized("operation.providers_unavailable"), action: TrialCommandAction.reloadProviders.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry"))
            } else {
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.providers_reloaded"))
                operationState = .success(localized("operation.reloaded_providers \(dashboard.providers.count)"), action: TrialCommandAction.reloadProviders.title(language: presentationLanguage), target: router.displayName)
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
                    liveStreamState = .connecting
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
                    liveStreamState = .failed(message)
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
