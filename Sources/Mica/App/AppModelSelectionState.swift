import Foundation
import MicaCore
import SwiftUI

extension AppModel {
    var selectedRouter: RouterProfile? {
        routers.first { $0.id == selectedRouterID }
    }

    var selectedRouterSecret: String {
        guard let selectedRouterID else {
            return ""
        }

        return controllerSecrets[selectedRouterID] ?? ""
    }

    var selectedTrialSession: TrialSessionSnapshot {
        guard let router = selectedRouter else {
            return .empty(routerName: localized("diagnostics.none"))
        }

        return trialSession(for: router)
    }

    var selectedControllerAdapter: ControllerAdapter {
        controllerAdapter(for: selectedRouter)
    }

    var activeUnifiedAdapter: (any ControllerAdapterProtocol)? {
        guard let selectedRouter else {
            return nil
        }

        return makeUnifiedAdapter(for: selectedRouter)
    }

    var controllerAdapterRows: [ControllerAdapterCapability] {
        selectedControllerAdapter.capabilities
    }

    var controllerAdapterDiagnostics: String {
        let adapter = selectedControllerAdapter
        let counts = Dictionary(grouping: adapter.capabilities) { $0.status }
            .mapValues { $0.count }

        return [
            "requested=\(adapter.requestedKind.rawValue)",
            "detected=\(adapter.detectedKind.rawValue)",
            "source=\(adapter.source.diagnosticsLabel)",
            "confidence=\(adapter.confidence.diagnosticsLabel)",
            "supported=\(counts[.supported] ?? 0)",
            "unavailable=\(counts[.unavailable] ?? 0)",
            "unknown=\(counts[.untested] ?? 0)",
            "partial=\(counts[.partial] ?? 0)",
            "failed=\(counts[.failed] ?? 0)",
        ].joined(separator: "; ")
    }

    var unifiedControllerDiagnostics: String {
        let snapshot = unifiedSnapshot

        return [
            "type=\(snapshot.controllerType.rawValue)",
            "source=\(snapshot.adapterSource)",
            "health=\(snapshot.health.state.rawValue)",
            "partial=\(snapshot.isPartial)",
            "capabilities=[\(snapshot.capabilities.diagnosticsLabel)]",
            "summary=[\(snapshot.diagnosticsSummary)]",
        ].joined(separator: "; ")
    }

    var selectedUnifiedControllerType: UnifiedControllerType {
        if unifiedSnapshot.checkedAt != nil {
            return unifiedSnapshot.controllerType
        }

        guard let selectedRouter else {
            return .unknown
        }

        return unifiedControllerType(for: selectedControllerAdapter.detectedKind, fallback: selectedRouter.unifiedControllerType)
    }

    var selectedUnifiedCapabilities: ControllerCapabilities {
        if unifiedSnapshot.checkedAt != nil {
            return unifiedSnapshot.capabilities
        }

        guard selectedRouter != nil else {
            return .none
        }

        return unifiedCapabilities(for: selectedControllerAdapter.detectedKind)
    }

    var capabilityDrivenOperationDiagnostics: String {
        let actions = UnifiedControllerAction.allCases
        let supported = actions.filter { selectedUnifiedCapabilities.supports($0) }.count
        let unavailable = actions.count - supported

        return [
            "type=\(selectedUnifiedControllerType.rawValue)",
            "supported-actions=\(supported)",
            "unavailable-actions=\(unavailable)",
            "boundary=\(selectedUnifiedControllerType.micaBoundarySummary(language: presentationLanguage))",
        ].joined(separator: "; ")
    }

    var unifiedOperationBoundarySummary: String {
        selectedUnifiedControllerType.micaBoundarySummary(language: presentationLanguage)
    }

    func supportsUnifiedAction(_ action: UnifiedControllerAction) -> Bool {
        selectedUnifiedCapabilities.supports(action)
    }

    func unifiedUnavailableReason(for action: UnifiedControllerAction) -> String {
        let controllerType = selectedUnifiedControllerType

        switch controllerType {
        case .mihomoCompatible:
            return localized("capability.unsupported_mihomo \(action.micaLabel(language: presentationLanguage))")
        case .surgeHTTPAPI:
            return localized("capability.unsupported_surge \(action.micaLabel(language: presentationLanguage))")
        case .openClashMihomoCompatible:
            return localized("capability.unsupported_openclash \(action.micaLabel(language: presentationLanguage))")
        case .nikkiMihomoCompatible:
            return localized("capability.unsupported_nikki \(action.micaLabel(language: presentationLanguage))")
        case .singBoxCompatible:
            return "\(action.micaLabel(language: presentationLanguage)): \(localized("capability.impact_unavailable"))"
        case .cmfaCompatible, .stashCompatible:
            return localized("capability.unsupported_stash_cmfa \(action.micaLabel(language: presentationLanguage))")
        case .stashCmfaCompatible:
            return localized("capability.unsupported_stash_cmfa \(action.micaLabel(language: presentationLanguage))")
        case .smartProbe:
            return localized("capability.unsupported_smart \(action.micaLabel(language: presentationLanguage))")
        case .unknown:
            return localized("capability.unsupported_unknown \(action.micaLabel(language: presentationLanguage))")
        case .unsupported:
            return localized("capability.unsupported_profile \(action.micaLabel(language: presentationLanguage))")
        }
    }

    var surgeSnapshotDiagnostics: String {
        guard let selectedRouter,
              runtimeControllerKind(for: selectedRouter) == .surgeCompatible else {
            return "adapter=not-surge"
        }

        let checked = surgeSnapshot.checkedAt == nil ? "not-loaded" : "loaded"

        return [
            "adapter=surge-http-api",
            "platform=\(selectedRouter.surgePlatform.rawValue)",
            "checked=\(checked)",
            "outbound=\(surgeSnapshot.outboundMode)",
            "policies=\(surgeSnapshot.policies.count)",
            "policy-groups=\(surgeSnapshot.policyGroups.count)",
            "active-requests=\(surgeSnapshot.activeRequests.count)",
            "recent-requests=\(surgeSnapshot.recentRequests.count)",
            "rules=\(surgeSnapshot.rules.count)",
            "dns-cache=\(surgeSnapshot.dnsCacheEntryCount.map { "\($0)" } ?? "unknown")",
            "traffic-upload=\(surgeSnapshot.traffic.upload)",
            "traffic-download=\(surgeSnapshot.traffic.download)",
        ].joined(separator: "; ")
    }

    var surgeEnhancedSnapshotAggregate: String {
        [
            "surge-policy-groups=\(surgeSnapshot.policyGroups.count)",
            "surge-rules=\(surgeSnapshot.rules.count)",
            "dns-cache=\(surgeSnapshot.dnsCacheEntryCount.map { "\($0)" } ?? "unknown")",
        ].joined(separator: "; ")
    }

    var surgeEnhancedSnapshotDisplaySummary: String {
        localized(
            "surge.enhanced_snapshot_summary \(surgeSnapshot.policyGroups.count) \(surgeSnapshot.rules.count) \(surgeSnapshot.dnsCacheEntryCount.map(String.init) ?? localized("diagnostics.none"))"
        )
    }

    var enhancedSnapshotDisplaySummary: String {
        [
            localized("diagnostics.rules_snapshot \(rulesSnapshotState.label(language: presentationLanguage))"),
            localized("diagnostics.provider_snapshot \(providersSnapshotState.label(language: presentationLanguage))"),
        ].joined(separator: " · ")
    }

    var snapshotStatsDiagnostics: String {
        if let selectedRouter,
           runtimeControllerKind(for: selectedRouter) == .surgeCompatible {
            return "surge=[\(surgeSnapshotDiagnostics)]; unified=[\(unifiedSnapshot.diagnosticsSummary)]; session=[\(controllerSession.diagnosticsSummary)]"
        }

        return "groups=\(dashboard.groups.count); connections=\(dashboard.connections.count); rules=\(dashboard.rules.count); providers=\(dashboard.providers.count); config=[\(dashboard.config.diagnosticsSummary)]; insight=[\(dashboard.insight.diagnosticsStats)]; unified=[\(unifiedSnapshot.diagnosticsSummary)]; session=[\(controllerSession.diagnosticsSummary)]"
    }

    func trialSession(for router: RouterProfile) -> TrialSessionSnapshot {
        trialSessions[router.id] ?? .empty(routerName: router.displayName)
    }

    var isBusy: Bool {
        switch connectionState {
        case .connecting:
            return true
        case .disconnected, .connected, .failed:
            return switchingGroupID != nil
                || clearingFixedGroupID != nil
                || changingMode
                || updatingConfigFieldID != nil
                || measuringDelayGroupID != nil
                || measuringDelayNode != nil
                || closingConnectionID != nil
                || closingConnectionGroupID != nil
                || closingAllConnections
                || updatingProviderName != nil
                || checkingProviderName != nil
                || providerUpdateAllProgress?.isRunning == true
                || isRefreshingDashboard
                || reloadingRules
                || updatingRuleID != nil
                || reloadingProviders
                || runningRuntimeOperationID != nil
                || changingSurgeOutbound
                || testingSurgePolicyGroup != nil
                || switchingSurgePolicyGroup != nil
                || killingSurgeRequestID != nil
                || killingSurgeProjectedConnectionID != nil
                || reloadingSurgeProfile
                || changingControllerLogLevel
        }
    }

    func cancelControllerOperationTasks() {
        refreshTask?.cancel()
        switchTask?.cancel()
        modeTask?.cancel()
        configTask?.cancel()
        delayTask?.cancel()
        connectionTask?.cancel()
        providerTask?.cancel()
        rulesTask?.cancel()
        surgeTask?.cancel()
        runtimeOperationTask?.cancel()

        refreshTask = nil
        switchTask = nil
        modeTask = nil
        configTask = nil
        delayTask = nil
        connectionTask = nil
        providerTask = nil
        rulesTask = nil
        surgeTask = nil
        runtimeOperationTask = nil

        operationState = nil
        switchingGroupID = nil
        clearingFixedGroupID = nil
        changingMode = false
        updatingConfigFieldID = nil
        measuringDelayGroupID = nil
        measuringDelayNode = nil
        closingConnectionID = nil
        closingConnectionGroupID = nil
        closingAllConnections = false
        updatingProviderName = nil
        checkingProviderName = nil
        isRefreshingDashboard = false
        reloadingRules = false
        updatingRuleID = nil
        ruleUpdateFailures = [:]
        reloadingProviders = false
        providerUpdateAllProgress = nil
        providerUpdateFailures = [:]
        providerHealthCheckFailures = [:]
        changingSurgeOutbound = false
        testingSurgePolicyGroup = nil
        switchingSurgePolicyGroup = nil
        killingSurgeRequestID = nil
        killingSurgeProjectedConnectionID = nil
        reloadingSurgeProfile = false
        changingControllerLogLevel = false
        runningRuntimeOperationID = nil
    }

    func selectRouter(_ router: RouterProfile) {
        guard routers.contains(where: { $0.id == router.id }) else { return }
        if selectedRouterID == router.id,
           controllerSession.controllerID == router.id,
           controllerSession.state != .stopped {
            return
        }

        leaveLiveSession(reason: .controllerSwitch)
        selectedRouterID = router.id
        persistSelectedRouterID(router.id)
        enterLiveSession(for: router)
    }

    func replaceSelectedRouterSession(with router: RouterProfile) {
        guard selectedRouterID == router.id else { return }
        leaveLiveSession(reason: .controllerSwitch)
        persistSelectedRouterID(router.id)
        enterLiveSession(for: router)
    }

    func clearSelectedRouterAfterDeletion() {
        leaveLiveSession(reason: .controllerDeletion)
        selectedRouterID = nil
        persistSelectedRouterID(nil)
    }

    func clearOperationalSessionPresentation(
        endedControllerID: RouterProfile.ID?
    ) {
        connectionState = .disconnected
        replaceDashboard(.empty)
        publishControllerLogs([])
        connectionsCatalog = .empty
        logsCatalog = .empty
        unifiedSnapshot = .empty
        surgeSnapshot = .empty
        operationState = nil
        switchingGroupID = nil
        clearingFixedGroupID = nil
        changingMode = false
        updatingConfigFieldID = nil
        measuringDelayGroupID = nil
        measuringDelayNode = nil
        closingConnectionID = nil
        closingConnectionGroupID = nil
        closingAllConnections = false
        updatingProviderName = nil
        checkingProviderName = nil
        isRefreshingDashboard = false
        reloadingRules = false
        updatingRuleID = nil
        ruleUpdateFailures = [:]
        reloadingProviders = false
        providerUpdateAllProgress = nil
        changingSurgeOutbound = false
        testingSurgePolicyGroup = nil
        switchingSurgePolicyGroup = nil
        killingSurgeRequestID = nil
        killingSurgeProjectedConnectionID = nil
        reloadingSurgeProfile = false
        changingControllerLogLevel = false
        rulesSnapshotState = .idle
        providersSnapshotState = .idle
        providerUpdateFailures = [:]
        providerHealthCheckFailures = [:]
        controllerHealth = .idle(language: presentationLanguage)
        controllerLogLevel = .all
        liveTrafficRate = TrafficSnapshot(upload: 0, download: 0)
        liveStreamUpdatedAt = nil
        trafficTimeline.reset()
        memoryTimeline.reset()
        connectionCountTimeline.reset()
        controllerSessionPresentation.publishRuntime(ControllerSessionRuntimeState())
        geoIPCoordinator.invalidate()
        pendingDiagnosticsCopyTarget = nil
        lastDiagnosticsCopyTarget = nil
        diagnosticsTransientState = nil

        if let endedControllerID {
            let routerName = routers.first { $0.id == endedControllerID }?.displayName
                ?? trialSessions[endedControllerID]?.routerName
                ?? localized("dashboard.no_controller")
            trialSessions[endedControllerID] = .empty(routerName: routerName)
        }
    }

    func toggleDashboardUpdatesPaused() {
        setPresentationPaused(!dashboardSessionControls.dashboardUpdatesPaused)
    }

    func clearClosedConnections() {
        guard !dashboardSessionControls.closedConnections.isEmpty else {
            operationState = .success(localized("operation.no_closed_connections"))
            return
        }

        dashboardSessionControls.clearClosedConnections()
        operationState = .success(localized("operation.closed_connections_cleared"))
    }

    func clearControllerLogs() {
        if let router = selectedRouter,
           runtimeControllerKind(for: router) == .singBoxCompatible {
            clearSingBoxControllerLogs(router: router)
            return
        }

        clearLiveSessionRuntimeLogs()
    }

    func toggleControllerLogsPaused() {
        let paused = !dashboardSessionControls.logsPresentationPaused
        dashboardSessionControls.setLogsPresentationPaused(paused)
        updateLiveSessionRuntimePresentationDemand(forceVisible: !paused)
        guard !paused, !dashboardSessionControls.dashboardUpdatesPaused else { return }
        noteSessionPublicationDirty(.logs, immediate: true)
    }

    func setControllerLogLevel(_ level: LogSessionLevel) {
        guard controllerLogLevel != level else { return }

        guard let router = selectedRouter,
              runtimeControllerKind(for: router) == .surgeCompatible else {
            controllerLogLevel = level
            restartControllerLogStream()
            return
        }

        guard controllerSupportsLiveAction(
            .setLogLevel,
            router: router,
            action: TrialCommandAction.surgeLogLevel.title(language: presentationLanguage)
        ), !isBusy else {
            return
        }

        surgeTask?.cancel()
        let previousLevel = controllerLogLevel
        controllerLogLevel = level
        changingControllerLogLevel = true
        let generation = controllerSession.generation
        let apiKey = controllerSecrets[router.id]
        let commandID = beginCommand(
            .surgeLogLevel,
            router: router,
            summary: localized("operation.setting_surge_log_level \(level.surgeUpstreamValue)")
        )
        operationState = .working(
            localized("operation.setting_surge_log_level \(level.surgeUpstreamValue)"),
            action: TrialCommandAction.surgeLogLevel.title(language: presentationLanguage),
            target: router.displayName
        )

        surgeTask = Task {
            let client = SurgeHttpAPIClient(profile: router, apiKey: apiKey)
            do {
                try await client.setLogLevel(level.surgeUpstreamValue)
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                changingControllerLogLevel = false
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .success,
                    summary: localized("operation.surge_log_level_updated \(level.surgeUpstreamValue)")
                )
                operationState = .success(
                    localized("operation.surge_log_level_updated \(level.surgeUpstreamValue)"),
                    action: TrialCommandAction.surgeLogLevel.title(language: presentationLanguage),
                    target: router.displayName
                )
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                controllerLogLevel = previousLevel
                changingControllerLogLevel = false
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: localized("operation.surge_log_level_update_failed")
                )
                operationState = .error(
                    Self.routerTrialFailureMessage(for: error, language: presentationLanguage),
                    action: TrialCommandAction.surgeLogLevel.title(language: presentationLanguage),
                    target: router.displayName,
                    nextStep: localized("action.retry")
                )
            }
        }
    }

    func persistSelectedRouterID(_ routerID: RouterProfile.ID?) {
        if let routerID {
            userDefaults.set(routerID.uuidString, forKey: Self.selectedControllerDefaultsKey)
        } else {
            userDefaults.removeObject(forKey: Self.selectedControllerDefaultsKey)
        }
    }

    func persistedSelectedRouterID() -> RouterProfile.ID? {
        guard let rawValue = userDefaults.string(forKey: Self.selectedControllerDefaultsKey) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }
}
