import Foundation
import MicaCore

extension AppModel {
    private var hasSelectedLiveSession: Bool {
        selectedRouterID != nil && controllerSession.controllerID == selectedRouterID
    }

    var canTestSelectedRouter: Bool {
        hasSelectedLiveSession && !isBusy
    }

    var canRefreshSelectedRouter: Bool {
        hasSelectedLiveSession
            && !isBusy
            && !dashboardSessionControls.dashboardUpdatesPaused
    }

    var canTogglePresentationPause: Bool {
        hasSelectedLiveSession
    }

    func mainWindowDidAppear() {
        mainWindowCount += 1
        guard mainWindowCount == 1,
              didLoadPersistedState,
              !sessionSuspendedForSleep,
              controllerSession.controllerID == nil,
              let router = selectedRouter else { return }
        enterLiveSession(for: router)
    }

    func mainWindowDidDisappear() {
        mainWindowCount = max(mainWindowCount - 1, 0)
        guard mainWindowCount == 0 else { return }
        leaveLiveSession()
    }

    func systemWillSleep() {
        sessionSuspendedForSleep = true
        leaveLiveSession()
    }

    func systemDidWake() {
        sessionSuspendedForSleep = false
        guard mainWindowCount > 0, let router = selectedRouter else { return }
        enterLiveSession(for: router)
    }

    func enterLiveSession(for router: RouterProfile) {
        guard selectedRouterID == router.id else { return }

        cancelLiveSessionTasks()
        controllerSession.begin(controllerID: router.id)
        let requiresRuntimeProbe = router.controllerKind == .autoDetect
            || router.controllerKind == .stashCmfaCompatible
        activeSessionControllerKind = requiresRuntimeProbe ? nil : router.controllerKind
        controllerHealth = .checking(router: router)
        connectionState = .connecting
        liveStreamRequested = true
        liveStreamState = .connecting

        let generation = controllerSession.generation
        if requiresRuntimeProbe {
            startAutoDetectProbe(
                for: router,
                generation: generation,
                includeSurge: router.controllerKind == .autoDetect
            )
        } else {
            startResolvedSession(for: router, generation: generation)
        }
    }

    func leaveLiveSession() {
        controllerSession.invalidate()
        cancelControllerOperationTasks()
        cancelLiveSessionTasks()
        activeSessionControllerKind = nil
        liveStreamRequested = false
        liveStreamState = .stopped
        liveTrafficRate = TrafficSnapshot(upload: 0, download: 0)
        liveStreamUpdatedAt = nil
        trafficTimeline.reset()
    }

    func requestImmediateSessionRefresh(isUserInitiated: Bool = false) {
        guard let router = selectedRouter,
              controllerSession.controllerID == router.id else {
            operationState = .error(localized("operation.select_router_refresh"))
            return
        }

        guard runtimeControllerKind(for: router) != .autoDetect else {
            if isUserInitiated {
                operationState = .working(
                    localized("operation.testing_endpoints_progress"),
                    action: TrialCommandAction.refresh.title(language: presentationLanguage),
                    target: router.displayName
                )
            }
            return
        }

        guard !dashboardSessionControls.dashboardUpdatesPaused else {
            if isUserInitiated {
                operationState = .partial(localized("operation.dashboard_updates_paused"))
            }
            return
        }

        let generation = controllerSession.generation
        if runtimeControllerKind(for: router) == .singBoxCompatible {
            if isUserInitiated {
                operationState = .working(
                    localized("operation.full_refresh_progress"),
                    action: TrialCommandAction.refresh.title(language: presentationLanguage),
                    target: router.displayName
                )
            }
            startLiveStreams(for: router, generation: generation)
            if isUserInitiated {
                operationState = .success(
                    localized("operation.full_refresh_loaded"),
                    action: TrialCommandAction.refresh.title(language: presentationLanguage),
                    target: router.displayName
                )
            }
            return
        }

        if isUserInitiated {
            operationState = .working(
                localized("operation.full_refresh_progress"),
                action: TrialCommandAction.refresh.title(language: presentationLanguage),
                target: router.displayName
            )
        }

        manualSessionRefreshTask = Task {
            async let fast: Void = performSessionRefresh(
                .fast,
                router: router,
                generation: generation,
                manual: isUserInitiated
            )
            async let medium: Void = performSessionRefresh(
                .medium,
                router: router,
                generation: generation,
                manual: isUserInitiated
            )
            async let slow: Void = performSessionRefresh(
                .slow,
                router: router,
                generation: generation,
                manual: isUserInitiated
            )
            _ = await (fast, medium, slow)

            guard isCurrentSession(routerID: router.id, generation: generation) else { return }
            manualSessionRefreshTask = nil
            if isUserInitiated {
                operationState = controllerSession.state.failureDetail.map {
                    .partial($0, action: TrialCommandAction.refresh.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry"))
                } ?? .success(
                    localized("operation.full_refresh_loaded"),
                    action: TrialCommandAction.refresh.title(language: presentationLanguage),
                    target: router.displayName
                )
            }
        }
    }

    func setPresentationPaused(_ paused: Bool) {
        guard selectedRouter != nil else { return }
        guard dashboardSessionControls.dashboardUpdatesPaused != paused else { return }

        dashboardSessionControls.setPresentationPaused(paused)
        if paused {
            operationState = nil
            return
        }

        applyPendingSessionPresentation()
        operationState = nil
        requestImmediateSessionRefresh()
    }

    private func startSessionRefreshCoordinator(
        for router: RouterProfile,
        generation: UUID
    ) {
        if runtimeControllerKind(for: router) == .singBoxCompatible {
            initialSessionRefreshTask = nil
            fastSessionRefreshTask = nil
            mediumSessionRefreshTask = nil
            slowSessionRefreshTask = nil
            return
        }

        initialSessionRefreshTask = Task {
            requestImmediateSessionRefresh()
        }

        if runtimeControllerKind(for: router) == .surgeCompatible {
            fastSessionRefreshTask = Task {
                await runSessionRefreshLoop(.fast, router: router, generation: generation)
            }
        } else {
            fastSessionRefreshTask = nil
        }
        mediumSessionRefreshTask = Task {
            await runSessionRefreshLoop(.medium, router: router, generation: generation)
        }
        slowSessionRefreshTask = Task {
            await runSessionRefreshLoop(.slow, router: router, generation: generation)
        }
    }

    func runtimeControllerKind(for router: RouterProfile) -> ControllerKind {
        guard controllerSession.controllerID == router.id else {
            return router.controllerKind
        }
        return activeSessionControllerKind ?? router.controllerKind
    }

    func startResolvedSession(
        for router: RouterProfile,
        generation: UUID
    ) {
        guard isCurrentSession(routerID: router.id, generation: generation) else { return }
        startSessionRefreshCoordinator(for: router, generation: generation)
        startLiveStreams(for: router, generation: generation)
    }

    private func startAutoDetectProbe(
        for router: RouterProfile,
        generation: UUID,
        includeSurge: Bool = true
    ) {
        backendProbeTask?.cancel()
        let credential = controllerSecrets[router.id]

        backendProbeTask = Task {
            let detectedKind: ControllerKind
            do {
                detectedKind = try await probeControllerKind(
                    for: router,
                    credential: credential,
                    includeSurge: includeSurge
                )
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation) else { return }
                let message = localized("operation.base_endpoints_unavailable")
                activeSessionControllerKind = nil
                connectionState = .failed(message)
                liveStreamState = .failed(message)
                controllerSession.state = .failed(message)
                controllerSession.liveObservation.markFailure(partial: false)
                backendProbeTask = nil
                return
            }

            guard isCurrentSession(routerID: router.id, generation: generation) else { return }
            activeSessionControllerKind = detectedKind
            backendProbeTask = nil
            startResolvedSession(for: router, generation: generation)
        }
    }

    func probeControllerKind(
        for router: RouterProfile,
        credential: String?,
        includeSurge: Bool = true
    ) async throws -> ControllerKind {
        try await ControllerProbeResolver().resolve(
            profile: router,
            credential: credential,
            includeSurge: includeSurge
        )
    }

    private func runSessionRefreshLoop(
        _ lane: SessionRefreshLane,
        router: RouterProfile,
        generation: UUID
    ) async {
        do {
            try await Task.sleep(for: lane.initialOffset)
        } catch {
            return
        }

        while !Task.isCancelled, isCurrentSession(routerID: router.id, generation: generation) {
            let laneState = controllerSession.refreshLanes[lane] ?? SessionRefreshLaneState()
            if !laneState.terminalFailure {
                await performSessionRefresh(lane, router: router, generation: generation, manual: false)
            }

            do {
                try await Task.sleep(for: lane.interval)
            } catch {
                return
            }
        }
    }

    private func performSessionRefresh(
        _ lane: SessionRefreshLane,
        router: RouterProfile,
        generation: UUID,
        manual: Bool
    ) async {
        guard isCurrentSession(routerID: router.id, generation: generation) else { return }
        if lane == .fast, runtimeControllerKind(for: router) != .surgeCompatible {
            return
        }

        var laneState = controllerSession.refreshLanes[lane] ?? SessionRefreshLaneState()
        if manual {
            laneState.terminalFailure = false
        } else if laneState.terminalFailure {
            return
        }

        guard laneState.begin() else {
            controllerSession.refreshLanes[lane] = laneState
            return
        }
        controllerSession.refreshLanes[lane] = laneState

        do {
            if runtimeControllerKind(for: router) == .surgeCompatible {
                try await refreshSurgeLane(lane, router: router, generation: generation)
            } else {
                try await refreshMihomoLane(lane, router: router, generation: generation)
            }

            guard isCurrentSession(routerID: router.id, generation: generation) else { return }
            var completed = controllerSession.refreshLanes[lane] ?? laneState
            completed.finishSuccess(at: Date())
            let followUp = completed.consumeFollowUp()
            controllerSession.refreshLanes[lane] = completed
            markSessionRefreshSuccess(router: router)

            if followUp {
                await performSessionRefresh(lane, router: router, generation: generation, manual: true)
            }
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentSession(routerID: router.id, generation: generation) else { return }
            let category = RouterTrialFailureCategory(error: error)
            let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
            markRefreshLaneEndpointFailure(lane, message: message)
            var failed = controllerSession.refreshLanes[lane] ?? laneState
            failed.finishFailure(message, disposition: category.retryDisposition)
            controllerSession.refreshLanes[lane] = failed
            markSessionRefreshFailure(message, router: router)

            guard category.retryDisposition == .transient
                    || (category.retryDisposition == .retryOnce && failed.retryAttempt <= 1) else {
                return
            }

            do {
                try await Task.sleep(for: SessionRetryPolicy.delay(forAttempt: failed.retryAttempt - 1))
            } catch {
                return
            }

            guard isCurrentSession(routerID: router.id, generation: generation) else { return }
            await performSessionRefresh(lane, router: router, generation: generation, manual: false)
        }
    }

    private func refreshMihomoLane(
        _ lane: SessionRefreshLane,
        router: RouterProfile,
        generation: UUID
    ) async throws {
        let client = MihomoClient(profile: router, secret: controllerSecrets[router.id])

        switch lane {
        case .fast:
            return

        case .medium:
            let proxies = try await client.proxies()
            try ensureCurrentSession(routerID: router.id, generation: generation)
            controllerSession.endpointCache.proxies = proxies

            var nextHealth = currentPresentationHealth()
            nextHealth.set(.proxies, status: .ready(localized("endpoint.groups_count \(proxies.policyGroups.count)")))
            publishMihomoPresentation(router: router, health: nextHealth)

        case .slow:
            async let versionResult = Self.captureEndpoint { try await client.version() }
            async let configResult = Self.captureEndpoint { try await client.configs() }
            async let rulesResult = Self.captureEndpoint { try await client.rules() }
            async let providersResult = Self.captureProviderSnapshots(client: client)
            let results = await (
                version: versionResult,
                config: configResult,
                rules: rulesResult,
                providers: providersResult
            )

            try ensureCurrentSession(routerID: router.id, generation: generation)
            var nextHealth = currentPresentationHealth()
            var firstFailure: Error?
            var providerFailure: Error?

            switch results.version {
            case .success(let value):
                controllerSession.endpointCache.version = value
                nextHealth.set(.version, status: .ready(value.version))
            case .failure(let error):
                firstFailure = firstFailure ?? error
                nextHealth.set(.version, status: .failed(Self.shortFailureLabel(for: error, language: presentationLanguage)))
            }

            switch results.config {
            case .success(let value):
                controllerSession.endpointCache.config = value
                nextHealth.set(.configs, status: .ready(MicaStrings.displayMode(DashboardSnapshot.displayMode(value.mode), language: presentationLanguage)))
            case .failure(let error):
                firstFailure = firstFailure ?? error
                nextHealth.set(.configs, status: .failed(Self.shortFailureLabel(for: error, language: presentationLanguage)))
            }

            switch results.rules {
            case .success(let value):
                controllerSession.endpointCache.rules = value
                nextHealth.set(.rules, status: .ready(localized("endpoint.rules_count \(value.rules.count)")))
            case .failure(let error):
                firstFailure = firstFailure ?? error
                nextHealth.set(.rules, status: .failed(Self.shortFailureLabel(for: error, language: presentationLanguage)))
            }

            switch results.providers.proxy {
            case .success(let value):
                controllerSession.endpointCache.proxyProviders = value
            case .failure(let error):
                firstFailure = firstFailure ?? error
                providerFailure = providerFailure ?? error
            }
            switch results.providers.rule {
            case .success(let value):
                controllerSession.endpointCache.ruleProviders = value
            case .failure(let error):
                firstFailure = firstFailure ?? error
                providerFailure = providerFailure ?? error
            }

            let providerCount = (controllerSession.endpointCache.proxyProviders?.providerList.count ?? 0)
                + (controllerSession.endpointCache.ruleProviders?.providerList.count ?? 0)
            if let providerFailure {
                nextHealth.set(.providers, status: .failed(Self.shortFailureLabel(for: providerFailure, language: presentationLanguage)))
            } else {
                nextHealth.set(.providers, status: .ready(localized("endpoint.providers_count \(providerCount)")))
            }

            publishMihomoPresentation(router: router, health: nextHealth)
            if let firstFailure { throw firstFailure }
        }
    }

    private func refreshSurgeLane(
        _ lane: SessionRefreshLane,
        router: RouterProfile,
        generation: UUID
    ) async throws {
        let client = SurgeHttpAPIClient(profile: router, apiKey: controllerSecrets[router.id])
        var snapshot = currentPendingSurgeSnapshot(router: router)

        switch lane {
        case .fast:
            let activeRequests = try await client.activeRequests()
            try ensureCurrentSession(routerID: router.id, generation: generation)
            snapshot.activeRequests = activeRequests.requests

        case .medium:
            async let outboundResult = Self.captureEndpoint { try await client.outbound() }
            async let policiesResult = Self.captureEndpoint { try await client.policies() }
            async let groupsResult = Self.captureEndpoint { try await client.policyGroups() }
            let results = await (outbound: outboundResult, policies: policiesResult, groups: groupsResult)
            try ensureCurrentSession(routerID: router.id, generation: generation)
            var firstFailure: Error?

            switch results.outbound {
            case .success(let value): snapshot.outboundMode = value.mode
            case .failure(let error): firstFailure = firstFailure ?? error
            }
            switch results.policies {
            case .success(let value): snapshot.policies = value.policies
            case .failure(let error): firstFailure = firstFailure ?? error
            }
            switch results.groups {
            case .success(let value): snapshot.policyGroups = value.groups
            case .failure(let error): firstFailure = firstFailure ?? error
            }

            snapshot.checkedAt = Date()
            publishSurgePresentation(snapshot, router: router)
            if let firstFailure { throw firstFailure }
            return

        case .slow:
            async let rulesResult = Self.captureEndpoint { try await client.rules() }
            async let dnsResult = Self.captureEndpoint { try await client.dnsCache() }
            let results = await (rules: rulesResult, dns: dnsResult)
            try ensureCurrentSession(routerID: router.id, generation: generation)
            var firstFailure: Error?
            var rulesFailure: Error?

            switch results.rules {
            case .success(let value): snapshot.rules = value.rules
            case .failure(let error):
                firstFailure = firstFailure ?? error
                rulesFailure = error
            }
            switch results.dns {
            case .success(let value): snapshot.dnsCacheEntryCount = value.entryCount
            case .failure(let error): firstFailure = firstFailure ?? error
            }

            snapshot.checkedAt = Date()
            publishSurgePresentation(snapshot, router: router)
            if let rulesFailure {
                publishRulesSnapshotState(
                    .unavailable(Self.routerTrialFailureMessage(for: rulesFailure, language: presentationLanguage))
                )
            }
            if let firstFailure { throw firstFailure }
            return
        }

        snapshot.checkedAt = Date()
        publishSurgePresentation(
            snapshot,
            router: router,
            connectionRatesReceivedAt: snapshot.checkedAt
        )
    }

    private func publishMihomoPresentation(
        router: RouterProfile,
        health: ControllerHealthSnapshot
    ) {
        let cache = controllerSession.endpointCache
        var nextDashboard = controllerSession.pendingPresentation.dashboard ?? dashboard

        if let version = cache.version {
            nextDashboard.versionLabel = version.version
        }
        if let config = cache.config {
            nextDashboard.replaceConfig(with: config)
        }
        if let proxies = cache.proxies {
            nextDashboard.replaceGroups(with: proxies)
        }
        if let connections = cache.connections {
            nextDashboard.replaceConnections(with: connections)
        }
        if let rules = cache.rules {
            nextDashboard.replaceRules(with: rules)
        }
        nextDashboard.replaceProviders(
            proxyProviders: cache.proxyProviders,
            ruleProviders: cache.ruleProviders
        )
        if !dashboardSessionControls.logsPresentationPaused {
            nextDashboard.controllerLogs = controllerSession.logBuffer.entries
        }

        let nextUnified: UnifiedControllerSnapshot?
        if let version = cache.version,
           let config = cache.config,
           let proxies = cache.proxies,
           let connections = cache.connections {
            nextUnified = UnifiedControllerSnapshot.mihomoCompatible(
                profile: router,
                controllerType: effectiveUnifiedControllerType(for: router),
                version: version,
                config: config,
                proxies: proxies,
                connections: connections,
                rules: cache.rules,
                providers: cache.proxyProviders,
                ruleProviders: cache.ruleProviders
            )
        } else {
            nextUnified = nil
        }

        var finalizedHealth = health
        finalizedHealth.finalize()
        let nextConnectionState: ConnectionState = cache.version.map {
            .connected(version: $0.version)
        } ?? .connecting
        let nextRulesState = enhancedSnapshotState(
            for: .rules,
            hasValue: cache.rules != nil,
            fallback: rulesSnapshotState,
            health: finalizedHealth
        )
        let hasProviders = cache.proxyProviders != nil || cache.ruleProviders != nil
        let nextProvidersState = enhancedSnapshotState(
            for: .providers,
            hasValue: hasProviders,
            fallback: providersSnapshotState,
            health: finalizedHealth
        )

        if dashboardSessionControls.dashboardUpdatesPaused {
            controllerSession.pendingPresentation.dashboard = nextDashboard
            controllerSession.pendingPresentation.controllerHealth = finalizedHealth
            controllerSession.pendingPresentation.connectionState = nextConnectionState
            controllerSession.pendingPresentation.rulesSnapshotState = nextRulesState
            controllerSession.pendingPresentation.providersSnapshotState = nextProvidersState
            if let nextUnified {
                controllerSession.pendingPresentation.unifiedSnapshot = nextUnified
            }
            return
        }

        dashboard = nextDashboard
        controllerHealth = finalizedHealth
        connectionState = nextConnectionState
        rulesSnapshotState = nextRulesState
        providersSnapshotState = nextProvidersState
        if let nextUnified {
            unifiedSnapshot = nextUnified
        }
    }

    private func publishSurgePresentation(
        _ snapshot: SurgeControlSnapshot,
        router: RouterProfile,
        connectionRatesReceivedAt: Date? = nil
    ) {
        applySurgeSnapshot(
            snapshot,
            router: router,
            connectionRatesReceivedAt: connectionRatesReceivedAt
        )

        if dashboardSessionControls.dashboardUpdatesPaused {
            controllerSession.pendingPresentation.connectionState = .connected(version: "Surge HTTP API")
            return
        }

        if !dashboardSessionControls.logsPresentationPaused {
            dashboard.controllerLogs = controllerSession.logBuffer.entries
        }
        connectionState = .connected(version: "Surge HTTP API")
    }

    private func applyPendingSessionPresentation() {
        guard let router = selectedRouter else {
            controllerSession.pendingPresentation.reset()
            return
        }

        let pending = controllerSession.pendingPresentation
        if let snapshot = pending.surgeSnapshot {
            applySurgeSnapshot(snapshot, router: router)
        }
        if let value = pending.dashboard { dashboard = value }
        if let value = pending.unifiedSnapshot { unifiedSnapshot = value }
        if let value = pending.controllerHealth { controllerHealth = value }
        if let value = pending.connectionState { connectionState = value }
        if let value = pending.rulesSnapshotState { rulesSnapshotState = value }
        if let value = pending.providersSnapshotState { providersSnapshotState = value }
        if let value = pending.memory { controllerSession.runtime.recordMemory(value) }
        if pending.clearClosedConnections {
            dashboardSessionControls.clearClosedConnections()
        }
        if !pending.closedConnections.entries.isEmpty {
            dashboardSessionControls.recordClosed(pending.closedConnections.entries)
        }

        trafficTimeline = controllerSession.trafficTimeline
        if let latest = controllerSession.trafficTimeline.samples.last {
            liveTrafficRate = TrafficSnapshot(upload: latest.upload, download: latest.download)
            liveStreamUpdatedAt = latest.receivedAt
        }
        if !dashboardSessionControls.logsPresentationPaused {
            dashboard.controllerLogs = controllerSession.logBuffer.entries
        }
        controllerSession.pendingPresentation.reset()
    }

    private func currentPresentationHealth() -> ControllerHealthSnapshot {
        controllerSession.pendingPresentation.controllerHealth ?? controllerHealth
    }

    private func enhancedSnapshotState(
        for endpoint: ControllerEndpointKind,
        hasValue: Bool,
        fallback: EnhancedSnapshotState,
        health: ControllerHealthSnapshot
    ) -> EnhancedSnapshotState {
        switch health.status(for: endpoint) {
        case .failed(let message):
            .unavailable(message)
        case .ready:
            hasValue ? .available : fallback
        case .idle, .checking:
            fallback
        }
    }

    private func markRefreshLaneEndpointFailure(
        _ lane: SessionRefreshLane,
        message: String
    ) {
        let endpoint: ControllerEndpointKind
        switch lane {
        case .fast:
            endpoint = .connections
        case .medium:
            endpoint = .proxies
        case .slow:
            return
        }

        var health = currentPresentationHealth()
        health.set(endpoint, status: .failed(message))
        health.finalize()
        if dashboardSessionControls.dashboardUpdatesPaused {
            controllerSession.pendingPresentation.controllerHealth = health
        } else {
            controllerHealth = health
        }
    }

    private func publishRulesSnapshotState(_ state: EnhancedSnapshotState) {
        if dashboardSessionControls.dashboardUpdatesPaused {
            controllerSession.pendingPresentation.rulesSnapshotState = state
        } else {
            rulesSnapshotState = state
        }
    }

    private func currentPendingSurgeSnapshot(router: RouterProfile) -> SurgeControlSnapshot {
        if let pending = controllerSession.pendingPresentation.surgeSnapshot {
            return pending
        }
        if surgeSnapshot.checkedAt != nil {
            return surgeSnapshot
        }
        var snapshot = SurgeControlSnapshot.empty
        snapshot.platform = router.surgePlatform
        return snapshot
    }

    private func markSessionRefreshSuccess(router: RouterProfile) {
        let firstSuccess = controllerSession.lastSuccessAt == nil
        controllerSession.lastSuccessAt = Date()
        recomputeSessionState()
        if firstSuccess {
            let generation = controllerSession.generation
            Task { await recordSuccessfulConnection(for: router.id, generation: generation) }
        }
    }

    private func markSessionRefreshFailure(_ message: String, router: RouterProfile) {
        recomputeSessionState(fallbackFailure: message)
        if !dashboardSessionControls.dashboardUpdatesPaused {
            operationState = controllerSession.lastSuccessAt == nil
                ? .error(message, target: router.displayName, nextStep: localized("action.retry"))
                : .partial(message, target: router.displayName, nextStep: localized("action.retry"))
        }
    }

    private func recomputeSessionState(fallbackFailure: String? = nil) {
        let laneFailures = SessionRefreshLane.allCases.compactMap {
            controllerSession.refreshLanes[$0]?.lastFailure
        }
        let streamFailure: String?
        switch liveStreamState {
        case .partial(let message), .failed(let message): streamFailure = message
        case .idle, .connecting, .live, .nearLive, .unavailable, .stopped: streamFailure = nil
        }
        let failure = laneFailures.first ?? streamFailure ?? fallbackFailure

        if controllerSession.lastSuccessAt != nil {
            controllerSession.state = failure.map(LiveSessionState.partial) ?? .live
        } else if let failure {
            controllerSession.state = .failed(failure)
        } else {
            controllerSession.state = .connecting
        }
    }

    private func recordControllerLog(_ log: LogMessage) {
        controllerSession.logBuffer.append(ControllerLogEntry(message: log))
        guard !dashboardSessionControls.dashboardUpdatesPaused,
              !dashboardSessionControls.logsPresentationPaused else { return }
        dashboard.controllerLogs = controllerSession.logBuffer.entries
    }

    func restartControllerLogStream() {
        guard let router = selectedRouter,
              runtimeControllerKind(for: router) != .surgeCompatible,
              liveStreamRequested else {
            return
        }

        if runtimeControllerKind(for: router) == .singBoxCompatible {
            return
        }

        let generation = controllerSession.generation
        guard isCurrentSession(routerID: router.id, generation: generation) else { return }
        let client = MihomoClient(profile: router, secret: controllerSecrets[router.id])
        startMihomoLogStream(client: client, routerID: router.id, generation: generation)
    }

    private func startMihomoLogStream(
        client: MihomoClient,
        routerID: RouterProfile.ID,
        generation: UUID
    ) {
        liveLogsTask?.cancel()
        let upstreamLevel = controllerLogLevel.upstreamValue
        liveLogsTask = Task {
            do {
                let stream = try await client.logsStream(level: upstreamLevel)
                for try await log in stream {
                    try ensureCurrentSession(routerID: routerID, generation: generation)
                    applyLiveLog(log, routerID: routerID, generation: generation)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                handleLiveStreamFailure(.logs, error: error, routerID: routerID, generation: generation)
            }
        }
    }

    private func ensureCurrentSession(
        routerID: RouterProfile.ID,
        generation: UUID
    ) throws {
        guard isCurrentSession(routerID: routerID, generation: generation), !Task.isCancelled else {
            throw CancellationError()
        }
    }

    func isCurrentSession(
        routerID: RouterProfile.ID,
        generation: UUID
    ) -> Bool {
        selectedRouterID == routerID
            && controllerSession.controllerID == routerID
            && controllerSession.generation == generation
    }

    private func cancelLiveSessionTasks() {
        initialSessionRefreshTask?.cancel()
        fastSessionRefreshTask?.cancel()
        mediumSessionRefreshTask?.cancel()
        slowSessionRefreshTask?.cancel()
        manualSessionRefreshTask?.cancel()
        liveTrafficTask?.cancel()
        liveLogsTask?.cancel()
        liveMemoryTask?.cancel()
        liveConnectionsTask?.cancel()
        singBoxSessionTask?.cancel()
        liveRetryTask?.cancel()
        backendProbeTask?.cancel()

        initialSessionRefreshTask = nil
        fastSessionRefreshTask = nil
        mediumSessionRefreshTask = nil
        slowSessionRefreshTask = nil
        manualSessionRefreshTask = nil
        liveTrafficTask = nil
        liveLogsTask = nil
        liveMemoryTask = nil
        liveConnectionsTask = nil
        singBoxSessionTask = nil
        liveRetryTask = nil
        backendProbeTask = nil
        liveRetryAttempt = 0
    }

    func startLiveStreams(
        for router: RouterProfile,
        isRetry: Bool = false,
        generation explicitGeneration: UUID? = nil
    ) {
        liveTrafficTask?.cancel()
        liveLogsTask?.cancel()
        liveMemoryTask?.cancel()
        liveConnectionsTask?.cancel()
        singBoxSessionTask?.cancel()
        liveTrafficTask = nil
        liveLogsTask = nil
        liveMemoryTask = nil
        liveConnectionsTask = nil
        singBoxSessionTask = nil
        liveRetryTask = nil

        let generation = explicitGeneration ?? controllerSession.generation
        guard isCurrentSession(routerID: router.id, generation: generation) else {
            liveStreamRequested = false
            liveStreamState = .idle
            return
        }

        if !isRetry {
            liveRetryAttempt = 0
            liveTrafficRate = TrafficSnapshot(upload: 0, download: 0)
            liveStreamUpdatedAt = nil
            trafficTimeline.reset()
            controllerSession.trafficTimeline.reset()
            controllerSession.liveObservation.reset()
        }

        let capabilities = effectiveUnifiedCapabilities(for: router)
        guard capabilities.traffic else {
            liveStreamRequested = true
            liveStreamState = .unavailable(localized("live.unsupported_backend"))
            controllerSession.liveObservation.markUnavailable(source: .none)
            recomputeSessionState()
            return
        }

        guard runtimeControllerKind(for: router) != .surgeCompatible else {
            startSurgeNearLive(for: router, isRetry: isRetry, generation: generation)
            return
        }

        if runtimeControllerKind(for: router) == .singBoxCompatible {
            startSingBoxLiveSession(for: router, isRetry: isRetry, generation: generation)
            return
        }

        liveStreamRequested = true
        liveStreamState = .connecting
        controllerSession.liveObservation.start(source: .mihomoWebSocket)

        let routerID = router.id
        let client = MihomoClient(profile: router, secret: controllerSecrets[router.id])

        liveTrafficTask = Task {
            do {
                let stream = try await client.trafficStream()
                for try await event in stream {
                    try ensureCurrentSession(routerID: routerID, generation: generation)
                    applyLiveTraffic(event, routerID: routerID, generation: generation)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                handleLiveStreamFailure(.traffic, error: error, routerID: routerID, generation: generation)
            }
        }

        startMihomoLogStream(client: client, routerID: routerID, generation: generation)

        if capabilities.memory {
            liveMemoryTask = Task {
                do {
                    let stream = try await client.memoryStream()
                    for try await memory in stream {
                        try ensureCurrentSession(routerID: routerID, generation: generation)
                        applyLiveMemory(memory, routerID: routerID, generation: generation)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    handleLiveStreamFailure(.memory, error: error, routerID: routerID, generation: generation)
                }
            }
        }

        if capabilities.connections {
            liveConnectionsTask = Task {
                do {
                    let stream = try await client.connectionsStream()
                    for try await connections in stream {
                        try ensureCurrentSession(routerID: routerID, generation: generation)
                        applyLiveConnections(
                            connections,
                            routerID: routerID,
                            router: router,
                            generation: generation
                        )
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    handleLiveStreamFailure(.connections, error: error, routerID: routerID, generation: generation)
                }
            }
        }
    }

    private func startSingBoxLiveSession(
        for router: RouterProfile,
        isRetry: Bool,
        generation: UUID
    ) {
        singBoxSessionTask?.cancel()
        liveStreamRequested = true
        liveStreamState = .connecting
        controllerSession.liveObservation.start(source: .singBoxGRPC)

        let routerID = router.id
        let credential = controllerSecrets[router.id]
        singBoxSessionTask = Task { [weak self] in
            guard let self else { return }

            do {
                let client = try SingBoxGRPCClient(profile: router, credential: credential)
                defer { client.beginGracefulShutdown() }
                try await withTaskCancellationHandler {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            try await client.runConnections()
                        }
                        group.addTask {
                            let version = try await client.version()
                            try await self.consumeSingBoxSessionEvent(
                                .version(version),
                                router: router,
                                generation: generation
                            )
                        }
                        group.addTask {
                            let stream = try client.statusStream(intervalMilliseconds: 1_000)
                            for try await status in stream {
                                try await self.consumeSingBoxSessionEvent(
                                    .status(status),
                                    router: router,
                                    generation: generation
                                )
                            }
                        }
                        group.addTask {
                            let stream = client.groupStream()
                            for try await groups in stream {
                                try await self.consumeSingBoxSessionEvent(
                                    .groups(groups),
                                    router: router,
                                    generation: generation
                                )
                            }
                        }
                        group.addTask {
                            let initial = try await client.clashModeStatus()
                            try await self.consumeSingBoxSessionEvent(
                                .mode(initial),
                                router: router,
                                generation: generation
                            )
                            let stream = client.clashModeStream()
                            for try await mode in stream {
                                try await self.consumeSingBoxSessionEvent(
                                    .mode(
                                        SingBoxClashModeStatus(
                                            availableModes: initial.availableModes,
                                            currentMode: mode
                                        )
                                    ),
                                    router: router,
                                    generation: generation
                                )
                            }
                        }
                        group.addTask {
                            let stream = try client.connectionStream(intervalMilliseconds: 1_000)
                            for try await connections in stream {
                                try await self.consumeSingBoxSessionEvent(
                                    .connections(connections),
                                    router: router,
                                    generation: generation
                                )
                            }
                        }
                        group.addTask {
                            let stream = client.logStream()
                            for try await logs in stream {
                                try await self.consumeSingBoxSessionEvent(
                                    .logs(logs),
                                    router: router,
                                    generation: generation
                                )
                            }
                        }
                        group.addTask {
                            var retryAttempt = 0
                            while !Task.isCancelled {
                                do {
                                    let stream = client.tailscaleStatusStream()
                                    for try await status in stream {
                                        retryAttempt = 0
                                        try await self.consumeSingBoxSessionEvent(
                                            .tailscale(status),
                                            router: router,
                                            generation: generation
                                        )
                                    }
                                    try Task.checkCancellation()
                                    throw SingBoxGRPCError.transport(
                                        "sing-box Tailscale status stream ended"
                                    )
                                } catch is CancellationError {
                                    return
                                } catch let error as SingBoxGRPCError {
                                    if case .rpc(let code, _) = error, code == 5 {
                                        try await self.consumeSingBoxSessionEvent(
                                            .tailscale(SingBoxTailscaleStatus(endpoints: [])),
                                            router: router,
                                            generation: generation
                                        )
                                        return
                                    }
                                    try await self.consumeSingBoxSessionEvent(
                                        .tailscaleFailure(error.localizedDescription),
                                        router: router,
                                        generation: generation
                                    )
                                } catch {
                                    try await self.consumeSingBoxSessionEvent(
                                        .tailscaleFailure(String(describing: error)),
                                        router: router,
                                        generation: generation
                                    )
                                }

                                try await Task.sleep(
                                    for: SessionRetryPolicy.delay(forAttempt: retryAttempt)
                                )
                                retryAttempt += 1
                            }
                        }

                        try await group.waitForAll()
                    }
                    try Task.checkCancellation()
                    throw SingBoxGRPCError.transport("sing-box StartedService session ended")
                } onCancel: {
                    client.beginGracefulShutdown()
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                handleLiveStreamFailure(
                    .singBoxGRPC,
                    error: error,
                    routerID: routerID,
                    generation: generation
                )
            }
        }
    }

    private func consumeSingBoxSessionEvent(
        _ event: SingBoxSessionEvent,
        router: RouterProfile,
        generation: UUID
    ) throws {
        try ensureCurrentSession(routerID: router.id, generation: generation)
        applySingBoxSessionEvent(event, router: router, generation: generation)
    }

    private func applySingBoxSessionEvent(
        _ event: SingBoxSessionEvent,
        router: RouterProfile,
        generation: UUID
    ) {
        guard isCurrentSession(routerID: router.id, generation: generation), liveStreamRequested else {
            return
        }

        switch event {
        case .version(let version):
            controllerSession.singBoxVersion = version

        case .status(let status):
            controllerSession.singBoxStatus = status
            controllerSession.runtime.recordSingBoxStatus(status)
            let receivedAt = Date()
            controllerSession.trafficTimeline.append(
                upload: Int(clamping: status.uplinkBytesPerSecond),
                download: Int(clamping: status.downlinkBytesPerSecond),
                receivedAt: receivedAt
            )
            controllerSession.liveObservation.recordTrafficSample(source: .singBoxGRPC)
            controllerSession.liveObservation.recordMemorySample(source: .singBoxGRPC)
            if !dashboardSessionControls.dashboardUpdatesPaused {
                trafficTimeline = controllerSession.trafficTimeline
                liveTrafficRate = TrafficSnapshot(
                    upload: Int(clamping: status.uplinkBytesPerSecond),
                    download: Int(clamping: status.downlinkBytesPerSecond)
                )
                liveStreamUpdatedAt = receivedAt
            }

        case .groups(let groups):
            controllerSession.singBoxGroups = groups

        case .mode(let mode):
            controllerSession.singBoxMode = mode

        case .connections(let batch):
            applySingBoxConnectionBatch(batch)
            controllerSession.liveObservation.recordConnectionFrame(source: .singBoxGRPC)

        case .logs(let batch):
            if batch.reset {
                controllerSession.logBuffer.removeAll()
            }
            for message in batch.messages {
                recordControllerLog(LogMessage(singBox: message))
                controllerSession.liveObservation.recordLogEvent(source: .singBoxGRPC)
            }

        case .tailscale(let status):
            controllerSession.singBoxTailscaleStatus = status
            controllerSession.singBoxTailscaleError = nil

        case .tailscaleFailure(let message):
            controllerSession.singBoxTailscaleError = message
            return
        }

        liveRetryAttempt = 0
        liveStreamState = .live
        publishSingBoxPresentation(router: router)
        markSessionRefreshSuccess(router: router)
    }

    private func applySingBoxConnectionBatch(_ batch: SingBoxConnectionEventBatch) {
        if batch.reset {
            controllerSession.singBoxActiveConnections.removeAll(keepingCapacity: true)
            if dashboardSessionControls.dashboardUpdatesPaused {
                controllerSession.pendingPresentation.closedConnections.removeAll()
                controllerSession.pendingPresentation.clearClosedConnections = true
            } else {
                dashboardSessionControls.clearClosedConnections()
            }
        }

        var closedRows: [ConnectionSnapshot] = []
        for event in batch.events {
            switch event.type.rawValue {
            case SingBoxConnectionEventType.closed.rawValue:
                let existing = controllerSession.singBoxActiveConnections.first {
                    $0.id == event.id
                }
                controllerSession.singBoxActiveConnections.removeAll { $0.id == event.id }
                if let connection = event.connection {
                    closedRows.append(ConnectionSnapshot(singBox: connection))
                } else if let existing {
                    closedRows.append(existing)
                }

            default:
                guard let connection = event.connection else { continue }
                let row = ConnectionSnapshot(singBox: connection)
                if let index = controllerSession.singBoxActiveConnections.firstIndex(where: {
                    $0.id == row.id
                }) {
                    controllerSession.singBoxActiveConnections[index] = row
                } else {
                    controllerSession.singBoxActiveConnections.append(row)
                }
            }
        }

        if !closedRows.isEmpty {
            if dashboardSessionControls.dashboardUpdatesPaused {
                controllerSession.pendingPresentation.closedConnections.record(closedRows)
            } else {
                dashboardSessionControls.recordClosed(closedRows)
            }
        }
    }

    private func publishSingBoxPresentation(router: RouterProfile) {
        var nextDashboard = controllerSession.pendingPresentation.dashboard ?? dashboard
        if let version = controllerSession.singBoxVersion {
            nextDashboard.versionLabel = version.version
        }
        if let status = controllerSession.singBoxStatus {
            nextDashboard.replaceSingBoxStatus(with: status)
        }
        if let groups = controllerSession.singBoxGroups {
            nextDashboard.replaceSingBoxGroups(with: groups)
        }
        if let mode = controllerSession.singBoxMode {
            nextDashboard.replaceSingBoxMode(with: mode)
        }
        nextDashboard.connections = controllerSession.singBoxActiveConnections
        nextDashboard.rules = []
        nextDashboard.providers = []
        if !dashboardSessionControls.logsPresentationPaused {
            nextDashboard.controllerLogs = controllerSession.logBuffer.entries
        }

        var health = currentPresentationHealth()
        if let version = controllerSession.singBoxVersion {
            health.set(.version, status: .ready(version.version))
        }
        if let mode = controllerSession.singBoxMode {
            health.set(.configs, status: .ready(mode.currentMode))
        }
        if let groups = controllerSession.singBoxGroups {
            health.set(.proxies, status: .ready(localized("endpoint.groups_count \(groups.groups.count)")))
        }
        health.set(
            .connections,
            status: .ready(localized("endpoint.active_count \(controllerSession.singBoxActiveConnections.count)"))
        )
        health.set(.rules, status: .idle)
        health.set(.providers, status: .idle)
        health.finalize()

        let nextUnified: UnifiedControllerSnapshot?
        if let version = controllerSession.singBoxVersion,
           let status = controllerSession.singBoxStatus,
           let groups = controllerSession.singBoxGroups,
           let mode = controllerSession.singBoxMode {
            var snapshot = UnifiedControllerSnapshot.singBox(
                profile: router,
                version: version,
                status: status,
                groups: groups,
                mode: mode
            )
            snapshot.connectionsCount = controllerSession.singBoxActiveConnections.count
            nextUnified = snapshot
        } else {
            nextUnified = nil
        }

        let connectionState: ConnectionState = controllerSession.singBoxVersion.map {
            .connected(version: $0.version)
        } ?? .connecting
        let unsupported = localized("capability.unsupported_sing_box_data")

        if dashboardSessionControls.dashboardUpdatesPaused {
            controllerSession.pendingPresentation.dashboard = nextDashboard
            controllerSession.pendingPresentation.controllerHealth = health
            controllerSession.pendingPresentation.connectionState = connectionState
            controllerSession.pendingPresentation.rulesSnapshotState = .unavailable(unsupported)
            controllerSession.pendingPresentation.providersSnapshotState = .unavailable(unsupported)
            if let nextUnified {
                controllerSession.pendingPresentation.unifiedSnapshot = nextUnified
            }
            return
        }

        dashboard = nextDashboard
        controllerHealth = health
        self.connectionState = connectionState
        rulesSnapshotState = .unavailable(unsupported)
        providersSnapshotState = .unavailable(unsupported)
        if let nextUnified {
            unifiedSnapshot = nextUnified
        }
    }

    func startSurgeNearLive(
        for router: RouterProfile,
        isRetry: Bool = false,
        generation explicitGeneration: UUID? = nil
    ) {
        let generation = explicitGeneration ?? controllerSession.generation
        guard isCurrentSession(routerID: router.id, generation: generation) else { return }

        liveStreamRequested = true
        liveStreamState = .connecting
        controllerSession.liveObservation.start(source: .surgeNearLive)

        let routerID = router.id
        let client = SurgeHttpAPIClient(profile: router, apiKey: controllerSecrets[router.id])

        liveTrafficTask = Task {
            do {
                while !Task.isCancelled {
                    async let traffic = client.traffic()
                    async let events = client.events()
                    async let activeRequests = client.activeRequests()
                    async let recentRequests = client.recentRequests()
                    let update = try await (
                        traffic: traffic,
                        events: events,
                        activeRequests: activeRequests
                    )
                    let recentUpdate = try? await recentRequests
                    try ensureCurrentSession(routerID: routerID, generation: generation)

                    applySurgeNearLive(
                        traffic: update.traffic,
                        events: update.events,
                        activeRequests: update.activeRequests,
                        recentRequests: recentUpdate,
                        routerID: routerID,
                        router: router,
                        generation: generation
                    )
                    try await Task.sleep(for: .seconds(1))
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                handleLiveStreamFailure(.surgeRefresh, error: error, routerID: routerID, generation: generation)
            }
        }
    }

    func stopLiveStreams(resetRequest: Bool) {
        liveTrafficTask?.cancel()
        liveLogsTask?.cancel()
        liveMemoryTask?.cancel()
        liveConnectionsTask?.cancel()
        singBoxSessionTask?.cancel()
        liveRetryTask?.cancel()
        liveTrafficTask = nil
        liveLogsTask = nil
        liveMemoryTask = nil
        liveConnectionsTask = nil
        singBoxSessionTask = nil
        liveRetryTask = nil
        liveRetryAttempt = 0

        if resetRequest {
            liveStreamRequested = false
        }
        liveStreamState = resetRequest ? .stopped : .idle
        controllerSession.liveObservation.stop()
        recomputeSessionState()
    }

    private func applyLiveTraffic(
        _ event: LiveTrafficEvent,
        routerID: RouterProfile.ID,
        generation: UUID
    ) {
        guard isCurrentSession(routerID: routerID, generation: generation), liveStreamRequested else { return }

        let receivedAt = Date()
        controllerSession.trafficTimeline.append(
            upload: event.upload,
            download: event.download,
            receivedAt: receivedAt
        )
        controllerSession.liveObservation.recordTrafficSample(source: .mihomoWebSocket)
        liveRetryAttempt = 0
        liveStreamState = .live
        recomputeSessionState()

        guard !dashboardSessionControls.dashboardUpdatesPaused else { return }
        trafficTimeline = controllerSession.trafficTimeline
        liveTrafficRate = TrafficSnapshot(upload: event.upload, download: event.download)
        liveStreamUpdatedAt = receivedAt
    }

    private func applyLiveLog(
        _ log: LogMessage,
        routerID: RouterProfile.ID,
        generation: UUID
    ) {
        guard isCurrentSession(routerID: routerID, generation: generation), liveStreamRequested else { return }

        recordControllerLog(log)
        controllerSession.liveObservation.recordLogEvent(source: .mihomoWebSocket)
        if !dashboardSessionControls.dashboardUpdatesPaused {
            liveStreamUpdatedAt = liveStreamUpdatedAt ?? Date()
        }
        liveRetryAttempt = 0
        liveStreamState = .live
        recomputeSessionState()
    }

    private func applyLiveMemory(
        _ memory: MemoryResponse,
        routerID: RouterProfile.ID,
        generation: UUID
    ) {
        guard isCurrentSession(routerID: routerID, generation: generation), liveStreamRequested else { return }

        controllerSession.liveObservation.recordMemorySample(source: .mihomoWebSocket)
        liveRetryAttempt = 0
        liveStreamState = .live
        recomputeSessionState()

        if dashboardSessionControls.dashboardUpdatesPaused {
            controllerSession.pendingPresentation.memory = memory
        } else {
            controllerSession.runtime.recordMemory(memory)
        }
    }

    private func applyLiveConnections(
        _ connections: ConnectionsResponse,
        routerID: RouterProfile.ID,
        router: RouterProfile,
        generation: UUID
    ) {
        guard isCurrentSession(routerID: routerID, generation: generation), liveStreamRequested else { return }

        let receivedAt = Date()
        let connections = controllerSession.connectionTransferRates.enriching(
            connections,
            receivedAt: receivedAt
        )

        let activeIDs = Set(connections.connections.map(\.id))
        let closed = controllerSession.endpointCache.connections?.connections.filter {
            !activeIDs.contains($0.id)
        } ?? []
        controllerSession.endpointCache.connections = connections
        controllerSession.liveObservation.recordConnectionFrame(source: .mihomoWebSocket)
        liveRetryAttempt = 0
        liveStreamState = .live

        var health = currentPresentationHealth()
        health.set(.connections, status: .ready(localized("endpoint.active_count \(connections.connections.count)")))
        publishMihomoPresentation(router: router, health: health)
        if !closed.isEmpty {
            if dashboardSessionControls.dashboardUpdatesPaused {
                controllerSession.pendingPresentation.closedConnections.record(closed)
            } else {
                dashboardSessionControls.recordClosed(closed)
            }
        }
        markSessionRefreshSuccess(router: router)
    }

    private func applySurgeNearLive(
        traffic: SurgeTrafficResponse,
        events: SurgeEventsResponse,
        activeRequests: SurgeActiveRequestsResponse,
        recentRequests: SurgeActiveRequestsResponse?,
        routerID: RouterProfile.ID,
        router: RouterProfile,
        generation: UUID
    ) {
        guard isCurrentSession(routerID: routerID, generation: generation), liveStreamRequested else { return }

        let checkedAt = Date()
        controllerSession.trafficTimeline.append(
            upload: traffic.upload,
            download: traffic.download,
            receivedAt: checkedAt
        )
        controllerSession.liveObservation.recordSurgeNearLive(
            eventCount: events.events.count,
            activeRequestCount: activeRequests.requests.count,
            recentRequestCount: recentRequests?.requests.count ?? surgeSnapshot.recentRequests.count
        )
        liveRetryAttempt = 0
        liveStreamState = .nearLive

        var snapshot = currentPendingSurgeSnapshot(router: router)
        snapshot.events = events.events
        snapshot.activeRequests = activeRequests.requests
        if let recentRequests {
            snapshot.recentRequests = recentRequests.requests
        }
        snapshot.traffic = traffic
        snapshot.checkedAt = checkedAt
        publishSurgePresentation(
            snapshot,
            router: router,
            connectionRatesReceivedAt: checkedAt
        )
        markSessionRefreshSuccess(router: router)

        guard !dashboardSessionControls.dashboardUpdatesPaused else { return }
        trafficTimeline = controllerSession.trafficTimeline
        liveTrafficRate = TrafficSnapshot(upload: traffic.upload, download: traffic.download)
        liveStreamUpdatedAt = checkedAt
    }

    private func handleLiveStreamFailure(
        _ channel: LiveStreamChannel,
        error: Error,
        routerID: RouterProfile.ID,
        generation: UUID
    ) {
        guard isCurrentSession(routerID: routerID, generation: generation), liveStreamRequested else { return }

        let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
        liveStreamState = liveStreamUpdatedAt == nil ? .failed(message) : .partial(message)
        controllerSession.liveObservation.markFailure(partial: liveStreamUpdatedAt != nil)
        recomputeSessionState(fallbackFailure: message)

        let disposition = RouterTrialFailureCategory(error: error).retryDisposition
        guard disposition == .transient || (disposition == .retryOnce && liveRetryAttempt == 0) else { return }
        scheduleLiveStreamRetry(routerID: routerID, generation: generation)
    }

    private func scheduleLiveStreamRetry(
        routerID: RouterProfile.ID,
        generation: UUID
    ) {
        guard isCurrentSession(routerID: routerID, generation: generation),
              liveStreamRequested,
              let router = selectedRouter else { return }

        liveRetryTask?.cancel()
        let delay = SessionRetryPolicy.delay(forAttempt: liveRetryAttempt)
        liveRetryAttempt += 1

        liveRetryTask = Task {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard isCurrentSession(routerID: routerID, generation: generation), liveStreamRequested else { return }
            startLiveStreams(for: router, isRetry: true, generation: generation)
        }
    }
}

private enum SingBoxSessionEvent: Sendable {
    case version(SingBoxVersion)
    case status(SingBoxStatusSnapshot)
    case groups(SingBoxPolicyCatalog)
    case mode(SingBoxClashModeStatus)
    case connections(SingBoxConnectionEventBatch)
    case logs(SingBoxLogBatch)
    case tailscale(SingBoxTailscaleStatus)
    case tailscaleFailure(String)
}
