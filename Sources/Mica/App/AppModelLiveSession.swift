import Foundation
import MicaCore

extension AppModel {
    private var hasSelectedLiveSession: Bool {
        selectedRouterID != nil
            && controllerSessionPresentation.controllerID == selectedRouterID
    }

    var canTestSelectedRouter: Bool {
        hasSelectedLiveSession && !isBusy && refreshTask == nil
    }

    var canRefreshSelectedRouter: Bool {
        hasSelectedLiveSession
            && !isBusy
            && !liveSessionTasks.contains(.manualRefresh)
            && !controllerSessionPresentation.controls.dashboardUpdatesPaused
            && controllerSessionPresentation.state.allowsLiveCommands
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
        leaveLiveSession(reason: .sessionEnd)
    }

    func systemWillSleep() {
        sessionSuspendedForSleep = true
        leaveLiveSession(reason: .sleep)
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
        installSessionRefreshCoordinator(generation: controllerSession.generation)
        geoIPCoordinator.invalidate()
        geoIPCoordinator.bind(generation: controllerSession.generation)
        let requiresRuntimeProbe = sessionRequiresRuntimeProbe(for: router)
        activeSessionControllerKind = requiresRuntimeProbe ? nil : router.controllerKind
        controllerHealth = .checking(router: router)
        connectionState = .connecting
        liveStreamRequested = true
        setLiveStreamState(.connecting)

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

    func leaveLiveSession(reason: LiveSessionEndReason = .sessionEnd) {
        let endedControllerID = controllerSession.controllerID ?? selectedRouterID
        cancelControllerOperationTasks()
        cancelLiveSessionTasks()
        controllerSession.invalidate(reason: reason)
        geoIPCoordinator.invalidate()
        activeSessionControllerKind = nil
        liveStreamRequested = false
        setLiveStreamState(.stopped)
        clearOperationalSessionPresentation(endedControllerID: endedControllerID)
    }

    func registerLiveSessionWindowDemand(
        _ id: LiveSessionWindowDemandID,
        destination: LiveSessionVisibleDestination
    ) {
        let change = sessionPresentationCoordinator.registerWindowDemand(
            id,
            destination: destination
        )
        synchronizeLiveSessionWindowDemandChange(change)
    }

    func updateLiveSessionWindowDemand(
        _ id: LiveSessionWindowDemandID,
        destination: LiveSessionVisibleDestination
    ) {
        let change = sessionPresentationCoordinator.updateWindowDemand(
            id,
            destination: destination
        )
        synchronizeLiveSessionWindowDemandChange(change)
    }

    func unregisterLiveSessionWindowDemand(_ id: LiveSessionWindowDemandID) {
        let change = sessionPresentationCoordinator.unregisterWindowDemand(id)
        synchronizeLiveSessionWindowDemandChange(change)
    }

    private func synchronizeLiveSessionWindowDemandChange(
        _ change: LiveSessionWindowDemandChange?
    ) {
        guard let change else { return }
        updateLiveSessionRuntimePresentationDemand(
            forceVisible: false,
            newlyVisibleDomains: change.newlyObservedDomains
        )
        guard !usesActorBackedLiveIngestion else { return }
        let generation = controllerSession.generation
        for domain in change.newlyObservedDomains {
            flushSessionPublicationDomain(domain, generation: generation, force: true)
        }
    }

    func resetSessionPublicationCoordinator(for session: ControllerSession) {
        cancelSessionPublicationTasks()
        guard session.controllerID != nil else {
            sessionPresentationCoordinator.invalidate()
            return
        }
        sessionPresentationCoordinator.begin(generation: session.generation)
    }

    func cancelSessionPublicationTasks() {
        for task in sessionPublicationTasks.values {
            task.cancel()
        }
        sessionPublicationTasks.removeAll(keepingCapacity: true)
    }

    func noteSessionPublicationDirty(
        _ domain: LiveSessionPublicationDomain,
        immediate: Bool = false
    ) {
        let generation = controllerSession.generation
        guard controllerSession.controllerID != nil,
              sessionPresentationCoordinator.markDirty(
                domain,
                generation: generation
              ) != nil else {
            return
        }

        if immediate {
            flushSessionPublicationDomain(domain, generation: generation, force: true)
            return
        }

        guard !controllerSession.baselineTransaction.isActive,
              !dashboardSessionControls.dashboardUpdatesPaused,
              let token = sessionPresentationCoordinator.reserveSchedule(
                for: domain,
                generation: generation
              ) else {
            return
        }

        sessionPublicationTasks[domain] = Task { [weak self] in
            guard let self else { return }
            do {
                try await sleepBeforeSessionPublication(
                    domain: domain,
                    cadence: domain.cadence
                )
            } catch {
                guard sessionPresentationCoordinator.releaseSchedule(
                    for: domain,
                    token: token,
                    generation: generation
                ) else {
                    return
                }
                sessionPublicationTasks[domain] = nil
                return
            }

            guard sessionPresentationCoordinator.releaseSchedule(
                for: domain,
                token: token,
                generation: generation
            ) else {
                return
            }
            sessionPublicationTasks[domain] = nil
            flushSessionPublicationDomain(domain, generation: generation, force: false)
        }
    }

    func flushSessionPublicationDomain(
        _ domain: LiveSessionPublicationDomain,
        generation: UUID,
        force: Bool
    ) {
        guard controllerSession.generation == generation,
              controllerSession.controllerID != nil,
              !controllerSession.baselineTransaction.isActive,
              !dashboardSessionControls.dashboardUpdatesPaused else {
            return
        }
        guard force || sessionPresentationCoordinator.needsPublication(
            domain,
            generation: generation
        ) else {
            return
        }

        switch domain {
        case .logs:
            guard !dashboardSessionControls.logsPresentationPaused else { return }
            publishControllerLogs(controllerSession.logBuffer.entries)

        case .traffic:
            trafficTimeline = controllerSession.trafficTimeline
            if let latest = controllerSession.trafficTimeline.samples.last {
                liveTrafficRate = TrafficSnapshot(
                    upload: latest.upload,
                    download: latest.download
                )
                liveStreamUpdatedAt = latest.receivedAt
            }

        case .connections:
            connectionCountTimeline = controllerSession.connectionCountTimeline
            publishLatestConnectionDomain()
            if controllerSession.pendingPresentation.clearClosedConnections {
                dashboardSessionControls.clearClosedConnections()
                controllerSession.pendingPresentation.clearClosedConnections = false
            }
            if !controllerSession.pendingPresentation.closedConnections.entries.isEmpty {
                dashboardSessionControls.recordClosed(
                    controllerSession.pendingPresentation.closedConnections.entries
                )
                controllerSession.pendingPresentation.closedConnections.removeAll()
            }

        case .memory:
            memoryTimeline = controllerSession.memoryTimeline
            controllerSessionPresentation.publishRuntime(controllerSession.runtime)
        }

        if let receivedAt = controllerSession.latestReceivedAt {
            let latestSuccessAt = max(
                controllerSession.lastSuccessAt ?? receivedAt,
                receivedAt
            )
            if controllerSession.lastSuccessAt != latestSuccessAt {
                controllerSession.lastSuccessAt = latestSuccessAt
            }
            liveStreamUpdatedAt = max(liveStreamUpdatedAt ?? receivedAt, receivedAt)
        }
        sessionPresentationCoordinator.markPublished(domain, generation: generation)
    }

    private func publishLatestConnectionDomain() {
        guard let router = selectedRouter else { return }

        switch runtimeControllerKind(for: router) {
        case .surgeCompatible:
            let projected = projectedSurgeDashboard(
                controllerSession.surgeRawSnapshot,
                connectionRatesReceivedAt: controllerSession.surgeConnectionRatesReceivedAt
            )
            dashboard.connections = projected.connections
            dashboard.traffic = projected.traffic
            dashboard.insight = projected.insight

        case .singBoxCompatible:
            dashboard.connections = controllerSession.singBoxActiveConnections
            if let status = controllerSession.singBoxStatus {
                dashboard.replaceSingBoxStatus(with: status)
            } else {
                dashboard.insight = InsightSummarySnapshot(snapshot: dashboard)
            }

        default:
            if let connections = controllerSession.endpointCache.connections {
                dashboard.replaceConnections(with: connections)
            }
        }

        publishDashboardDomains([.connections, .insight])
    }

    func requestImmediateSessionRefresh(isUserInitiated: Bool = false) {
        guard let router = selectedRouter,
              controllerSessionPresentation.controllerID == router.id else { return }

        if isUserInitiated {
            guard canRefreshSelectedRouter,
                  !(sessionRequiresRuntimeProbe(for: router) && activeSessionControllerKind == nil) else {
                return
            }
        } else {
            guard !controllerSessionPresentation.controls.dashboardUpdatesPaused else { return }
        }

        if sessionRequiresRuntimeProbe(for: router), activeSessionControllerKind == nil {
            startAutoDetectProbe(
                for: router,
                generation: controllerSession.generation,
                includeSurge: router.controllerKind == .autoDetect
            )
            return
        }

        let generation = controllerSession.generation
        let operationID = isUserInitiated ? UUID() : nil
        if let operationID {
            selectedRouterRefreshOperationID = operationID
            isRefreshingDashboard = true
        }
        if runtimeControllerKind(for: router) == .singBoxCompatible {
            if isUserInitiated {
                operationState = .working(
                    localized("operation.full_refresh_progress"),
                    action: TrialCommandAction.refresh.title(language: presentationLanguage),
                    target: router.displayName
                )
            }
            startLiveStreams(for: router, generation: generation)
            if let operationID,
               finishSelectedRouterRefresh(
                    operationID: operationID,
                    routerID: router.id,
                    generation: generation
               ) {
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
            restartStreamsForManualRefresh(
                router: router,
                generation: generation
            )
        }

        let identity = LiveSessionRuntimeIdentity(controllerID: router.id, generation: generation)
        liveSessionTasks.start(
            isUserInitiated ? .manualRefresh : .immediateRefresh,
            for: identity
        ) { @MainActor [self] _ in
            async let fast: Void = runImmediateSessionRefreshLane(
                .fast,
                router: router,
                generation: generation,
                manual: isUserInitiated
            )
            async let medium: Void = runImmediateSessionRefreshLane(
                .medium,
                router: router,
                generation: generation,
                manual: isUserInitiated
            )
            async let slow: Void = runImmediateSessionRefreshLane(
                .slow,
                router: router,
                generation: generation,
                manual: isUserInitiated
            )
            _ = await (fast, medium, slow)

            if let operationID,
               finishSelectedRouterRefresh(
                    operationID: operationID,
                    routerID: router.id,
                    generation: generation
               ) {
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

    @discardableResult
    private func finishSelectedRouterRefresh(
        operationID: UUID,
        routerID: RouterProfile.ID,
        generation: UUID
    ) -> Bool {
        guard selectedRouterRefreshOperationID == operationID,
              isCurrentSession(routerID: routerID, generation: generation) else {
            return false
        }
        selectedRouterRefreshOperationID = nil
        isRefreshingDashboard = false
        return true
    }

    func setPresentationPaused(_ paused: Bool) {
        guard selectedRouter != nil else { return }
        guard dashboardSessionControls.dashboardUpdatesPaused != paused else { return }

        dashboardSessionControls.setPresentationPaused(paused)
        updateLiveSessionRuntimePresentationDemand(forceVisible: !paused)
        if paused {
            operationState = nil
            return
        }

        if let router = selectedRouter,
           controllerSession.baselineTransaction.isActive {
            _ = attemptSessionBaselineCommit(
                for: router,
                generation: controllerSession.generation
            )
            controllerSession.resetPendingPresentation()
        } else {
            applyPendingSessionPresentation()
        }
        if !usesActorBackedLiveIngestion {
            for domain in sessionPresentationCoordinator.observedDomains {
                flushSessionPublicationDomain(
                    domain,
                    generation: controllerSession.generation,
                    force: true
                )
            }
        }
        operationState = nil
        requestImmediateSessionRefresh()
    }

    private func startSessionRefreshCoordinator(
        for router: RouterProfile,
        generation: UUID
    ) {
        guard isCurrentSession(routerID: router.id, generation: generation) else { return }
        let identity = LiveSessionRuntimeIdentity(controllerID: router.id, generation: generation)
        if sessionRefreshCoordinator == nil {
            installSessionRefreshCoordinator(generation: generation)
        }
        let resolvedKind = runtimeControllerKind(for: router)
        if resolvedKind == .singBoxCompatible {
            liveSessionTasks.cancel(group: .refresh)
            return
        }

        guard let baselineTask = liveSessionTasks.start(
            .baseline,
            for: identity,
            operation: { @MainActor [self] _ in
                await loadAndCommitSessionBaseline(
                    for: router,
                    generation: generation,
                    resolvedKind: resolvedKind
                )
            }
        ) else { return }

        if resolvedKind == .surgeCompatible {
            liveSessionTasks.start(.fastRefresh, for: identity) { @MainActor [self] _ in
                await baselineTask.value
                guard !Task.isCancelled else { return }
                await runSessionRefreshLoop(.fast, router: router, generation: generation)
            }
        } else {
            liveSessionTasks.cancel(.fastRefresh)
        }
        liveSessionTasks.start(.mediumRefresh, for: identity) { @MainActor [self] _ in
            await baselineTask.value
            guard !Task.isCancelled else { return }
            await runSessionRefreshLoop(.medium, router: router, generation: generation)
        }
        liveSessionTasks.start(.slowRefresh, for: identity) { @MainActor [self] _ in
            await baselineTask.value
            guard !Task.isCancelled else { return }
            await runSessionRefreshLoop(.slow, router: router, generation: generation)
        }
    }

    private func loadAndCommitSessionBaseline(
        for router: RouterProfile,
        generation: UUID,
        resolvedKind: ControllerKind
    ) async {
        var retryAttempt = 0

        while !Task.isCancelled, isCurrentSession(routerID: router.id, generation: generation) {
            do {
                let payload = try await loadLiveSessionBaseline(
                    profile: router,
                    credential: controllerSecrets[router.id],
                    resolvedKind: resolvedKind
                )
                try ensureCurrentSession(routerID: router.id, generation: generation)

                let receivedAt = Date()
                switch payload {
                case .mihomo(let baseline):
                    guard resolvedKind != .surgeCompatible else { return }
                    controllerSession.endpointCache.version = baseline.version
                    controllerSession.endpointCache.config = baseline.config
                    controllerSession.endpointCache.proxies = baseline.proxies
                    controllerSession.endpointCache.connections = baseline.connections
                    controllerSession.connectionCountTimeline.append(
                        activeCount: baseline.connections.connections.count,
                        receivedAt: receivedAt
                    )
                    controllerSession.recordReceived(at: receivedAt)

                case .surge(let snapshot):
                    guard resolvedKind == .surgeCompatible else { return }
                    stageSurgeSnapshot(
                        snapshot,
                        receivedAt: snapshot.checkedAt ?? receivedAt,
                        includesCompleteBaseline: true
                    )
                }

                _ = attemptSessionBaselineCommit(for: router, generation: generation)
                return
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                let category = RouterTrialFailureCategory(error: error)
                let message = Self.routerTrialFailureMessage(
                    for: error,
                    language: presentationLanguage
                )
                markSessionBaselineFailure(message, router: router)

                let shouldRetry = category.retryDisposition == .transient
                    || (category.retryDisposition == .retryOnce && retryAttempt == 0)
                guard shouldRetry else {
                    return
                }

                do {
                    try await Task.sleep(
                        for: SessionRetryPolicy.delay(forAttempt: retryAttempt)
                    )
                } catch {
                    return
                }
                retryAttempt += 1
            }
        }
    }

    private func markSessionBaselineFailure(_ message: String, router: RouterProfile) {
        connectionState = .failed(message)
        controllerSession.liveObservation.markFailure(
            partial: controllerSession.hasCommittedBaseline
        )

        if controllerSession.hasCommittedBaseline {
            controllerSession.beginReconnect(message: message)
            setLiveStreamState(.partial(message))
            operationState = .partial(
                message,
                target: router.displayName,
                nextStep: localized("action.retry")
            )
        } else {
            controllerSession.state = .failedBeforeFirstSnapshot(message)
            setLiveStreamState(.failed(message))
            operationState = .error(
                message,
                target: router.displayName,
                nextStep: localized("action.retry")
            )
        }
    }

    func runtimeControllerKind(for router: RouterProfile) -> ControllerKind {
        guard controllerSession.controllerID == router.id else {
            return router.controllerKind
        }
        return activeSessionControllerKind ?? router.controllerKind
    }

    static func usesMihomoLiveStreams(_ kind: ControllerKind) -> Bool {
        switch kind {
        case .mihomoCompatible, .nikkiMihomoCompatible,
             .openClashMihomoCompatible, .cmfaCompatible, .stashCompatible:
            true
        case .autoDetect, .surgeCompatible, .singBoxCompatible,
             .stashCmfaCompatible, .unknown, .unsupported:
            false
        }
    }

    func restartRequestedMihomoLiveStreamsForManualRefresh(
        router: RouterProfile,
        generation: UUID
    ) {
        guard Self.usesMihomoLiveStreams(runtimeControllerKind(for: router)),
              liveStreamRequested,
              isCurrentSession(routerID: router.id, generation: generation) else {
            return
        }

        liveRetryState.reset()
        startLiveStreams(
            for: router,
            isRetry: true,
            generation: generation
        )
    }

    private func sessionRequiresRuntimeProbe(for router: RouterProfile) -> Bool {
        router.controllerKind == .autoDetect || router.controllerKind == .stashCmfaCompatible
    }

    func startResolvedSession(
        for router: RouterProfile,
        generation: UUID
    ) {
        guard isCurrentSession(routerID: router.id, generation: generation) else { return }
        installLiveSessionRuntime(for: router, generation: generation)
        startSessionRefreshCoordinator(for: router, generation: generation)
        startLiveStreams(for: router, generation: generation)
    }

    private func startAutoDetectProbe(
        for router: RouterProfile,
        generation: UUID,
        includeSurge: Bool = true
    ) {
        guard isCurrentSession(routerID: router.id, generation: generation) else { return }
        let identity = LiveSessionRuntimeIdentity(controllerID: router.id, generation: generation)
        let credential = controllerSecrets[router.id]

        liveSessionTasks.start(.probe, for: identity) { @MainActor [self] _ in
            var retryAttempt = 0

            while !Task.isCancelled {
                do {
                    let detectedKind = try await probeControllerKind(
                        for: router,
                        credential: credential,
                        includeSurge: includeSurge
                    )

                    guard isCurrentSession(routerID: router.id, generation: generation),
                          !Task.isCancelled else { return }
                    activeSessionControllerKind = detectedKind
                    startResolvedSession(for: router, generation: generation)
                    return
                } catch is CancellationError {
                    return
                } catch {
                    guard isCurrentSession(routerID: router.id, generation: generation),
                          !Task.isCancelled else { return }
                    let category = RouterTrialFailureCategory(error: error)
                    let message = Self.routerTrialFailureMessage(
                        for: error,
                        language: presentationLanguage
                    )
                    activeSessionControllerKind = nil
                    connectionState = .failed(message)
                    setLiveStreamState(.failed(message))
                    controllerSession.state = .failedBeforeFirstSnapshot(message)
                    controllerSession.liveObservation.markFailure(partial: false)

                    let shouldRetry = category.retryDisposition == .transient
                        || (category.retryDisposition == .retryOnce && retryAttempt == 0)
                    guard shouldRetry else {
                        return
                    }
                }

                do {
                    try await sleepBeforeControllerProbeRetry(attempt: retryAttempt)
                    try Task.checkCancellation()
                } catch {
                    return
                }
                retryAttempt += 1

                guard isCurrentSession(routerID: router.id, generation: generation) else { return }
                controllerHealth = .checking(router: router)
                connectionState = .connecting
                setLiveStreamState(.connecting)
                controllerSession.state = .connecting
            }
        }
    }

    func probeControllerKind(
        for router: RouterProfile,
        credential: String?,
        includeSurge: Bool = true
    ) async throws -> ControllerKind {
        try await resolveControllerKind(
            for: router,
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

    func performSessionRefresh(
        _ lane: SessionRefreshLane,
        router: RouterProfile,
        generation: UUID,
        manual: Bool
    ) async {
        guard isCurrentSession(routerID: router.id, generation: generation),
              let coordinator = sessionRefreshCoordinator else {
            return
        }
        if lane == .fast, runtimeControllerKind(for: router) != .surgeCompatible {
            return
        }

        let laneState = controllerSession.refreshLanes[lane] ?? SessionRefreshLaneState()
        if !manual, laneState.terminalFailure {
            return
        }

        do {
            try await coordinator.request(
                lane,
                source: manual ? .manual : .periodic,
                generation: generation
            ) { [weak self] lane, generation, source in
                guard let self else { throw CancellationError() }
                try await self.performSessionRefreshAttempt(
                    lane,
                    router: router,
                    generation: generation,
                    source: source
                )
            }
        } catch is CancellationError {
            return
        } catch SessionRefreshCoordinatorError.generationInvalidated {
            return
        } catch {
            // The attempt records endpoint and presentation failures before the
            // coordinator decides whether to retry or terminate the flight.
        }
    }

    func performSessionRefreshAttempt(
        _ lane: SessionRefreshLane,
        router: RouterProfile,
        generation: UUID,
        source: SessionRefreshRequestSource
    ) async throws {
        try ensureCurrentSession(routerID: router.id, generation: generation)

        var laneState = controllerSession.refreshLanes[lane] ?? SessionRefreshLaneState()
        if source == .manual {
            laneState.terminalFailure = false
        } else if laneState.terminalFailure {
            throw CancellationError()
        }
        laneState.isInFlight = true
        controllerSession.refreshLanes[lane] = laneState

        do {
            let outcome: SessionRefreshLaneOutcome
            if runtimeControllerKind(for: router) == .surgeCompatible {
                outcome = try await refreshSurgeLane(
                    lane,
                    router: router,
                    generation: generation
                )
            } else {
                outcome = try await refreshMihomoLane(
                    lane,
                    router: router,
                    generation: generation
                )
            }

            guard isCurrentSession(routerID: router.id, generation: generation) else { return }
            var completed = controllerSession.refreshLanes[lane] ?? laneState
            switch outcome {
            case .success:
                completed.finishSuccess(at: Date())
            case .partial(let message):
                completed.finishPartial(message, at: Date())
            }
            controllerSession.refreshLanes[lane] = completed
            switch outcome {
            case .success:
                markSessionRefreshSuccess(router: router)
            case .partial(let message):
                markSessionRefreshFailure(message, router: router)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try ensureCurrentSession(routerID: router.id, generation: generation)
            let category = RouterTrialFailureCategory(error: error)
            let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
            markRefreshLaneEndpointFailure(lane, message: message)
            var failed = controllerSession.refreshLanes[lane] ?? laneState
            failed.finishFailure(message, disposition: category.retryDisposition)
            controllerSession.refreshLanes[lane] = failed
            markSessionRefreshFailure(message, router: router)
            throw error
        }
    }

    private func refreshMihomoLane(
        _ lane: SessionRefreshLane,
        router: RouterProfile,
        generation: UUID
    ) async throws -> SessionRefreshLaneOutcome {
        let client = sessionMihomoClient
            ?? MihomoClient(profile: router, secret: controllerSecrets[router.id])

        switch lane {
        case .fast:
            return .success

        case .medium:
            let proxies = try await client.proxies()
            try ensureCurrentSession(routerID: router.id, generation: generation)
            var nextHealth = currentPresentationHealth()
            let policyGroups = proxies.policyGroups
            nextHealth.set(.proxies, status: .ready(localized("endpoint.groups_count \(policyGroups.count)")))

            let smartGroups = policyGroups
                .filter { $0.type.caseInsensitiveCompare("Smart") == .orderedSame }
                .map(\.name)
            let proxyChangePlan = MihomoEndpointChangePlan.medium(
                cache: controllerSession.endpointCache,
                proxies: proxies,
                smartWeights: smartGroups.isEmpty ? .replace(nil) : .notReceived
            )
            if proxyChangePlan.shouldWriteProxies {
                controllerSession.endpointCache.proxies = proxies
            }
            if proxyChangePlan.shouldWriteSmartWeights {
                controllerSession.endpointCache.smartWeights = nil
            }
            publishMihomoPresentation(
                router: router,
                health: nextHealth,
                domains: proxyChangePlan.domains,
                rebuildUnifiedSnapshot: proxyChangePlan.shouldRebuildUnifiedSnapshot
            )

            guard !smartGroups.isEmpty else { return .success }

            do {
                let smartWeights = try await client.smartWeights(forGroups: smartGroups)
                try ensureCurrentSession(routerID: router.id, generation: generation)
                let smartWeightsChangePlan = MihomoEndpointChangePlan.medium(
                    cache: controllerSession.endpointCache,
                    smartWeights: .replace(smartWeights)
                )
                if smartWeightsChangePlan.shouldWriteSmartWeights {
                    controllerSession.endpointCache.smartWeights = smartWeights
                }
                publishMihomoPresentation(
                    router: router,
                    health: nextHealth,
                    domains: smartWeightsChangePlan.domains,
                    rebuildUnifiedSnapshot: smartWeightsChangePlan.shouldRebuildUnifiedSnapshot
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Smart weights are optional controller metadata. Keep the last
                // successful values visible when only this endpoint is absent.
            }
            return .success

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

            try Task.checkCancellation()
            try ensureCurrentSession(routerID: router.id, generation: generation)
            var nextHealth = currentPresentationHealth()
            var firstFailure: Error?
            var providerFailure: Error?
            var successCount = 0
            let nextVersion = try? results.version.get()
            let nextConfig = try? results.config.get()
            let nextRules = try? results.rules.get()
            let nextProxyProviders = try? results.providers.proxy.get()
            let nextRuleProviders = try? results.providers.rule.get()
            let changePlan = MihomoEndpointChangePlan.slow(
                cache: controllerSession.endpointCache,
                version: nextVersion,
                config: nextConfig,
                rules: nextRules,
                proxyProviders: nextProxyProviders,
                ruleProviders: nextRuleProviders
            )

            switch results.version {
            case .success(let value):
                successCount += 1
                if changePlan.shouldWriteVersion {
                    controllerSession.endpointCache.version = value
                }
                nextHealth.set(.version, status: .ready(value.version))
            case .failure(let error):
                firstFailure = firstFailure ?? error
                nextHealth.set(.version, status: .failed(Self.shortFailureLabel(for: error, language: presentationLanguage)))
            }

            switch results.config {
            case .success(let value):
                successCount += 1
                if changePlan.shouldWriteConfig {
                    controllerSession.endpointCache.config = value
                }
                nextHealth.set(.configs, status: .ready(MicaStrings.displayMode(DashboardSnapshot.displayMode(value.mode), language: presentationLanguage)))
            case .failure(let error):
                firstFailure = firstFailure ?? error
                nextHealth.set(.configs, status: .failed(Self.shortFailureLabel(for: error, language: presentationLanguage)))
            }

            switch results.rules {
            case .success(let value):
                successCount += 1
                if changePlan.shouldWriteRules {
                    controllerSession.endpointCache.rules = value
                }
                nextHealth.set(.rules, status: .ready(localized("endpoint.rules_count \(value.rules.count)")))
            case .failure(let error):
                firstFailure = firstFailure ?? error
                nextHealth.set(.rules, status: .failed(Self.shortFailureLabel(for: error, language: presentationLanguage)))
            }

            switch results.providers.proxy {
            case .success(let value):
                successCount += 1
                if changePlan.shouldWriteProxyProviders {
                    controllerSession.endpointCache.proxyProviders = value
                }
            case .failure(let error):
                firstFailure = firstFailure ?? error
                providerFailure = providerFailure ?? error
            }
            switch results.providers.rule {
            case .success(let value):
                successCount += 1
                if changePlan.shouldWriteRuleProviders {
                    controllerSession.endpointCache.ruleProviders = value
                }
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

            publishMihomoPresentation(
                router: router,
                health: nextHealth,
                domains: changePlan.domains,
                rebuildUnifiedSnapshot: changePlan.shouldRebuildUnifiedSnapshot
            )
            guard let firstFailure else { return .success }
            guard successCount > 0 else { throw firstFailure }
            return .partial(
                Self.routerTrialFailureMessage(
                    for: firstFailure,
                    language: presentationLanguage
                )
            )
        }
    }

    private func refreshSurgeLane(
        _ lane: SessionRefreshLane,
        router: RouterProfile,
        generation: UUID
    ) async throws -> SessionRefreshLaneOutcome {
        let client = sessionSurgeClient
            ?? SurgeHttpAPIClient(profile: router, apiKey: controllerSecrets[router.id])
        var snapshot = currentPendingSurgeSnapshot(router: router)

        switch lane {
        case .fast:
            let recentRequests = try await client.recentRequests()
            try ensureCurrentSession(routerID: router.id, generation: generation)
            snapshot.recentRequests = recentRequests.requests

        case .medium:
            async let outboundResult = Self.captureEndpoint { try await client.outbound() }
            async let policiesResult = Self.captureEndpoint { try await client.policies() }
            async let groupsResult = Self.captureEndpoint { try await client.policyGroups() }
            let results = await (outbound: outboundResult, policies: policiesResult, groups: groupsResult)
            try Task.checkCancellation()
            try ensureCurrentSession(routerID: router.id, generation: generation)
            var firstFailure: Error?
            var configFailure: Error?
            var proxyFailure: Error?
            var successCount = 0

            switch results.outbound {
            case .success(let value):
                successCount += 1
                snapshot.outboundMode = value.mode
            case .failure(let error):
                firstFailure = firstFailure ?? error
                configFailure = error
            }
            switch results.policies {
            case .success(let value):
                successCount += 1
                snapshot.policies = value.policies
            case .failure(let error):
                firstFailure = firstFailure ?? error
                proxyFailure = proxyFailure ?? error
            }
            switch results.groups {
            case .success(let value):
                successCount += 1
                snapshot.policyGroups = value.groups
            case .failure(let error):
                firstFailure = firstFailure ?? error
                proxyFailure = proxyFailure ?? error
            }

            snapshot.checkedAt = Date()
            var nextHealth = currentPresentationHealth()
            if let configFailure {
                nextHealth.set(
                    .configs,
                    status: .failed(
                        Self.shortFailureLabel(
                            for: configFailure,
                            language: presentationLanguage
                        )
                    )
                )
            } else {
                nextHealth.set(
                    .configs,
                    status: .ready(
                        MicaStrings.displayMode(
                            snapshot.outboundMode,
                            language: presentationLanguage
                        )
                    )
                )
            }
            if let proxyFailure {
                nextHealth.set(
                    .proxies,
                    status: .failed(
                        Self.shortFailureLabel(
                            for: proxyFailure,
                            language: presentationLanguage
                        )
                    )
                )
            } else {
                nextHealth.set(
                    .proxies,
                    status: .ready(
                        localized(
                            "endpoint.groups_count \(snapshot.policyGroups.count)"
                        )
                    )
                )
            }
            publishSurgePresentation(
                snapshot,
                router: router,
                health: nextHealth,
                domains: [.metadata, .policyGroups, .insight]
            )
            guard let firstFailure else { return .success }
            guard successCount > 0 else { throw firstFailure }
            return .partial(
                Self.routerTrialFailureMessage(
                    for: firstFailure,
                    language: presentationLanguage
                )
            )

        case .slow:
            async let rulesResult = Self.captureEndpoint { try await client.rules() }
            async let dnsResult = Self.captureEndpoint { try await client.dnsCache() }
            let results = await (rules: rulesResult, dns: dnsResult)
            try Task.checkCancellation()
            try ensureCurrentSession(routerID: router.id, generation: generation)
            var firstFailure: Error?
            var rulesFailure: Error?
            var successCount = 0

            switch results.rules {
            case .success(let value):
                successCount += 1
                snapshot.rules = value.rules
            case .failure(let error):
                firstFailure = firstFailure ?? error
                rulesFailure = error
            }
            switch results.dns {
            case .success(let value):
                successCount += 1
                snapshot.dnsCacheEntryCount = value.entryCount
            case .failure(let error): firstFailure = firstFailure ?? error
            }

            snapshot.checkedAt = Date()
            var nextHealth = currentPresentationHealth()
            if let rulesFailure {
                nextHealth.set(
                    .rules,
                    status: .failed(
                        Self.shortFailureLabel(
                            for: rulesFailure,
                            language: presentationLanguage
                        )
                    )
                )
            } else {
                nextHealth.set(
                    .rules,
                    status: .ready(
                        localized("endpoint.rules_count \(snapshot.rules.count)")
                    )
                )
            }
            publishSurgePresentation(
                snapshot,
                router: router,
                health: nextHealth,
                domains: [.rules, .insight]
            )
            if let rulesFailure {
                publishRulesSnapshotState(
                    .unavailable(Self.routerTrialFailureMessage(for: rulesFailure, language: presentationLanguage))
                )
            }
            guard let firstFailure else { return .success }
            guard successCount > 0 else { throw firstFailure }
            return .partial(
                Self.routerTrialFailureMessage(
                    for: firstFailure,
                    language: presentationLanguage
                )
            )
        }

        snapshot.checkedAt = Date()
        publishSurgePresentation(
            snapshot,
            router: router,
            connectionRatesReceivedAt: snapshot.checkedAt,
            domains: []
        )
        return .success
    }

    private func publishMihomoPresentation(
        router: RouterProfile,
        health: ControllerHealthSnapshot,
        domains: DashboardPublicationDomains,
        rebuildUnifiedSnapshot: Bool
    ) {
        controllerSession.recordReceived(at: Date())
        if controllerSession.baselineTransaction.isActive {
            _ = attemptSessionBaselineCommit(
                for: router,
                generation: controllerSession.generation
            )
            return
        }

        let cache = controllerSession.endpointCache
        var nextDashboard = controllerSession.pendingPresentation.dashboard ?? dashboard

        if domains.contains(.metadata) {
            if let version = cache.version {
                nextDashboard.versionLabel = version.version
            }
            if let config = cache.config {
                nextDashboard.replaceConfig(with: config)
            }
        }
        if domains.contains(.policyGroups), let proxies = cache.proxies {
            nextDashboard.replaceGroups(with: proxies, smartWeights: cache.smartWeights)
        }
        if domains.contains(.connections), let connections = cache.connections {
            nextDashboard.replaceConnections(with: connections)
        }
        if domains.contains(.rules), let rules = cache.rules {
            nextDashboard.replaceRules(with: rules)
        }
        if domains.contains(.providers) {
            nextDashboard.replaceProviders(
                proxyProviders: cache.proxyProviders,
                ruleProviders: cache.ruleProviders
            )
        }

        let unifiedInputDomains: DashboardPublicationDomains = [
            .metadata,
            .policyGroups,
            .connections,
            .rules,
            .providers,
        ]
        var nextUnified: UnifiedControllerSnapshot?
        if rebuildUnifiedSnapshot,
           !domains.intersection(unifiedInputDomains).isEmpty,
           let version = cache.version,
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
        }

        var finalizedHealth = health
        finalizedHealth.finalize()
        let nextConnectionState: ConnectionState = cache.version.map {
            .connected(version: $0.version)
        } ?? .connecting
        let currentRulesState = controllerSession.pendingPresentation.rulesSnapshotState
            ?? rulesSnapshotState
        let nextRulesState = enhancedSnapshotState(
            for: .rules,
            hasValue: cache.rules != nil,
            fallback: currentRulesState,
            health: finalizedHealth
        )
        let hasProviders = cache.proxyProviders != nil || cache.ruleProviders != nil
        let currentProvidersState = controllerSession.pendingPresentation.providersSnapshotState
            ?? providersSnapshotState
        let nextProvidersState = enhancedSnapshotState(
            for: .providers,
            hasValue: hasProviders,
            fallback: currentProvidersState,
            health: finalizedHealth
        )

        if dashboardSessionControls.dashboardUpdatesPaused {
            if !domains.isEmpty {
                controllerSession.pendingPresentation.dashboard = nextDashboard
            }
            if (controllerSession.pendingPresentation.controllerHealth ?? controllerHealth)
                != finalizedHealth {
                controllerSession.pendingPresentation.controllerHealth = finalizedHealth
            }
            if (controllerSession.pendingPresentation.connectionState ?? connectionState)
                != nextConnectionState {
                controllerSession.pendingPresentation.connectionState = nextConnectionState
            }
            if currentRulesState != nextRulesState {
                controllerSession.pendingPresentation.rulesSnapshotState = nextRulesState
            }
            if currentProvidersState != nextProvidersState {
                controllerSession.pendingPresentation.providersSnapshotState = nextProvidersState
            }
            if let nextUnified,
               nextUnified
                   != (controllerSession.pendingPresentation.unifiedSnapshot ?? unifiedSnapshot) {
                controllerSession.pendingPresentation.unifiedSnapshot = nextUnified
            }
            return
        }

        if !domains.isEmpty {
            dashboard = nextDashboard
            publishDashboardDomains(domains)
        }
        if controllerHealth != finalizedHealth {
            controllerHealth = finalizedHealth
        }
        if connectionState != nextConnectionState {
            connectionState = nextConnectionState
        }
        if rulesSnapshotState != nextRulesState {
            rulesSnapshotState = nextRulesState
        }
        if providersSnapshotState != nextProvidersState {
            providersSnapshotState = nextProvidersState
        }
        if let nextUnified, nextUnified != unifiedSnapshot {
            unifiedSnapshot = nextUnified
        }
    }

    private func publishSurgePresentation(
        _ snapshot: SurgeControlSnapshot,
        router: RouterProfile,
        connectionRatesReceivedAt: Date? = nil,
        health: ControllerHealthSnapshot? = nil,
        domains: DashboardPublicationDomains
    ) {
        let receivedAt = connectionRatesReceivedAt ?? snapshot.checkedAt ?? Date()
        stageSurgeSnapshot(
            snapshot,
            receivedAt: receivedAt,
            includesCompleteBaseline: false
        )
        if controllerSession.baselineTransaction.isActive {
            _ = attemptSessionBaselineCommit(
                for: router,
                generation: controllerSession.generation
            )
            return
        }

        if dashboardSessionControls.dashboardUpdatesPaused {
            controllerSession.pendingPresentation.surgeSnapshot = snapshot
            controllerSession.pendingPresentation.connectionState = .connected(version: "Surge HTTP API")
            if var health {
                health.finalize()
                controllerSession.pendingPresentation.controllerHealth = health
            }
            return
        }

        if !domains.isEmpty {
            publishStagedSurgePresentation(router: router, domains: domains)
        }
        if var health {
            health.finalize()
            controllerHealth = health
        }
        connectionState = .connected(version: "Surge HTTP API")
    }

    func publishStagedSurgePresentation(
        router: RouterProfile,
        domains: DashboardPublicationDomains
    ) {
        let snapshot = controllerSession.surgeRawSnapshot
        let projected = projectedSurgeDashboard(
            snapshot,
            connectionRatesReceivedAt: controllerSession.surgeConnectionRatesReceivedAt
        )

        if domains.contains(.metadata) {
            dashboard.versionLabel = projected.versionLabel
            dashboard.mode = projected.mode
            dashboard.config = projected.config
        }
        if domains.contains(.policyGroups) {
            dashboard.groups = projected.groups
        }
        if domains.contains(.connections) {
            dashboard.connections = projected.connections
            dashboard.traffic = projected.traffic
            trafficTimeline = controllerSession.trafficTimeline
            connectionCountTimeline = controllerSession.connectionCountTimeline
            if let latest = controllerSession.trafficTimeline.samples.last {
                liveTrafficRate = TrafficSnapshot(
                    upload: latest.upload,
                    download: latest.download
                )
                liveStreamUpdatedAt = latest.receivedAt
            }
        }
        if domains.contains(.rules) {
            dashboard.rules = projected.rules
        }
        if domains.contains(.providers) {
            dashboard.providers = projected.providers
        }
        if domains.contains(.insight) {
            dashboard.insight = projected.insight
        }

        surgeSnapshot = snapshot
        unifiedSnapshot = .surgeHTTPAPI(profile: router, snapshot: snapshot)
        controllerHealth = Self.surgeHealth(
            router: router,
            snapshot: snapshot,
            language: presentationLanguage
        )
        rulesSnapshotState = .available
        providersSnapshotState = .unavailable(localized("trial.surge_provider_not_included"))
        publishDashboardDomains(domains)
    }

    func applyPendingSessionPresentation() {
        guard let router = selectedRouter else {
            controllerSession.resetPendingPresentation()
            return
        }

        let pending = controllerSession.pendingPresentation
        if let snapshot = pending.surgeSnapshot {
            applySurgeSnapshot(snapshot, router: router)
        }
        if let value = pending.dashboard { replaceDashboard(value) }
        if let value = pending.unifiedSnapshot { unifiedSnapshot = value }
        if let value = pending.controllerHealth { controllerHealth = value }
        if let value = pending.connectionState { connectionState = value }
        if let value = pending.rulesSnapshotState { rulesSnapshotState = value }
        if let value = pending.providersSnapshotState { providersSnapshotState = value }
        if let sample = controllerSession.pendingMemorySample {
            controllerSession.runtime.recordMemory(
                sample.response,
                receivedAt: sample.receivedAt
            )
            // Timeline was already appended while paused (session buffer); only publish runtime.
        }
        if pending.clearClosedConnections {
            dashboardSessionControls.clearClosedConnections()
        }
        if !pending.closedConnections.entries.isEmpty {
            dashboardSessionControls.recordClosed(pending.closedConnections.entries)
        }

        trafficTimeline = controllerSession.trafficTimeline
        memoryTimeline = controllerSession.memoryTimeline
        connectionCountTimeline = controllerSession.connectionCountTimeline
        if let latest = controllerSession.trafficTimeline.samples.last {
            liveTrafficRate = TrafficSnapshot(upload: latest.upload, download: latest.download)
            liveStreamUpdatedAt = latest.receivedAt
        }
        if !dashboardSessionControls.logsPresentationPaused {
            publishControllerLogs(controllerSession.logBuffer.entries)
        }
        controllerSession.resetPendingPresentation()
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
        if controllerSession.surgeRawSnapshot.checkedAt != nil {
            return controllerSession.surgeRawSnapshot
        }
        var snapshot = SurgeControlSnapshot.empty
        snapshot.platform = router.surgePlatform
        return snapshot
    }

    func stageSurgeSnapshot(
        _ snapshot: SurgeControlSnapshot,
        receivedAt: Date,
        includesCompleteBaseline: Bool
    ) {
        var snapshot = snapshot
        if includesCompleteBaseline,
           let existingCheckedAt = controllerSession.surgeRawSnapshot.checkedAt,
           existingCheckedAt > (snapshot.checkedAt ?? .distantPast) {
            snapshot.events = controllerSession.surgeRawSnapshot.events
            snapshot.activeRequests = controllerSession.surgeRawSnapshot.activeRequests
            snapshot.recentRequests = controllerSession.surgeRawSnapshot.recentRequests
            snapshot.traffic = controllerSession.surgeRawSnapshot.traffic
            snapshot.checkedAt = existingCheckedAt
        }
        let existingSurgeEventLogs = Dictionary(
            uniqueKeysWithValues: controllerSession.logBuffer.entries
                .filter { $0.id.hasPrefix("surge-event:") }
                .map { ($0.id, $0) }
        )
        let surgeEventLogs = DashboardSnapshot.surgeEventLogEntries(for: snapshot.events).map { entry in
            guard let existing = existingSurgeEventLogs[entry.id] else { return entry }
            var stableEntry = entry
            stableEntry.receivedAt = existing.receivedAt
            return stableEntry
        }
        let nonSurgeEventLogs = controllerSession.logBuffer.entries.filter {
            !$0.id.hasPrefix("surge-event:")
        }
        controllerSession.logBuffer.replace(
            with: (nonSurgeEventLogs + surgeEventLogs).sorted {
                $0.receivedAt < $1.receivedAt
            }
        )

        controllerSession.surgeRawSnapshot = snapshot
        controllerSession.surgeConnectionRatesReceivedAt = receivedAt
        controllerSession.connectionCountTimeline.append(
            activeCount: snapshot.activeRequests.count,
            receivedAt: receivedAt
        )
        controllerSession.pendingPresentation.closedConnections.record(
            DashboardSnapshot.surgeRecentRequestConnections(
                for: snapshot.recentRequests,
                language: presentationLanguage
            )
        )
        controllerSession.recordReceived(at: receivedAt)
        if includesCompleteBaseline {
            controllerSession.baselineTransaction.recordSurgeSnapshot(at: receivedAt)
        }
        noteSessionPublicationDirty(.logs)
        noteSessionPublicationDirty(.traffic)
        noteSessionPublicationDirty(.connections)
    }

    @discardableResult
    func attemptSessionBaselineCommit(
        for router: RouterProfile,
        generation: UUID
    ) -> Bool {
        guard isCurrentSession(routerID: router.id, generation: generation),
              controllerSession.baselineTransaction.isActive,
              !dashboardSessionControls.dashboardUpdatesPaused else {
            return false
        }

        switch runtimeControllerKind(for: router) {
        case .surgeCompatible:
            guard controllerSession.baselineTransaction.surgeSnapshotReceived,
                  controllerSession.surgeRawSnapshot.checkedAt != nil else {
                return false
            }
            return commitSurgeSessionBaseline(router: router, generation: generation)

        case .singBoxCompatible:
            guard let version = controllerSession.singBoxVersion,
                  let status = controllerSession.singBoxStatus,
                  let groups = controllerSession.singBoxGroups,
                  let mode = controllerSession.singBoxMode,
                  controllerSession.baselineTransaction.singBoxConnectionsReceived else {
                return false
            }
            return commitSingBoxSessionBaseline(
                version: version,
                status: status,
                groups: groups,
                mode: mode,
                router: router,
                generation: generation
            )

        default:
            let cache = controllerSession.endpointCache
            guard let version = cache.version,
                  let config = cache.config,
                  let proxies = cache.proxies,
                  let connections = cache.connections else {
                return false
            }
            return commitMihomoSessionBaseline(
                version: version,
                config: config,
                proxies: proxies,
                connections: connections,
                router: router,
                generation: generation
            )
        }
    }

    private func commitMihomoSessionBaseline(
        version: VersionResponse,
        config: ConfigResponse,
        proxies: ProxiesResponse,
        connections: ConnectionsResponse,
        router: RouterProfile,
        generation: UUID
    ) -> Bool {
        let cache = controllerSession.endpointCache
        var nextDashboard = DashboardSnapshot(
            version: version,
            config: config,
            proxies: proxies,
            connections: connections,
            language: presentationLanguage
        )
        nextDashboard.replaceGroups(with: proxies, smartWeights: cache.smartWeights)
        if let rules = cache.rules {
            nextDashboard.replaceRules(with: rules)
        }
        nextDashboard.replaceProviders(
            proxyProviders: cache.proxyProviders,
            ruleProviders: cache.ruleProviders
        )

        var health = ControllerHealthSnapshot.checking(router: router)
        health.set(.version, status: .ready(version.version))
        health.set(
            .configs,
            status: .ready(
                MicaStrings.displayMode(
                    DashboardSnapshot.displayMode(config.mode),
                    language: presentationLanguage
                )
            )
        )
        health.set(
            .proxies,
            status: .ready(localized("endpoint.groups_count \(proxies.policyGroups.count)"))
        )
        health.set(
            .connections,
            status: .ready(localized("endpoint.active_count \(connections.connections.count)"))
        )
        if let rules = cache.rules {
            health.set(.rules, status: .ready(localized("endpoint.rules_count \(rules.rules.count)")))
        } else {
            health.set(.rules, status: .idle)
        }
        let providerCount = (cache.proxyProviders?.providerList.count ?? 0)
            + (cache.ruleProviders?.providerList.count ?? 0)
        if cache.proxyProviders != nil || cache.ruleProviders != nil {
            health.set(.providers, status: .ready(localized("endpoint.providers_count \(providerCount)")))
        } else {
            health.set(.providers, status: .idle)
        }
        health.finalize()

        let unified = UnifiedControllerSnapshot.mihomoCompatible(
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
        return commitSessionBaseline(
            dashboard: nextDashboard,
            unified: unified,
            health: health,
            connectionState: .connected(version: version.version),
            rulesState: cache.rules == nil ? .idle : .available,
            providersState: cache.proxyProviders == nil && cache.ruleProviders == nil
                ? .idle
                : .available,
            router: router,
            generation: generation,
            streamState: .live
        )
    }

    private func commitSurgeSessionBaseline(
        router: RouterProfile,
        generation: UUID
    ) -> Bool {
        let snapshot = controllerSession.surgeRawSnapshot
        let dashboard = projectedSurgeDashboard(
            snapshot,
            connectionRatesReceivedAt: controllerSession.surgeConnectionRatesReceivedAt
        )
        return commitSessionBaseline(
            dashboard: dashboard,
            unified: .surgeHTTPAPI(profile: router, snapshot: snapshot),
            health: Self.surgeHealth(
                router: router,
                snapshot: snapshot,
                language: presentationLanguage
            ),
            connectionState: .connected(version: "Surge HTTP API"),
            rulesState: .available,
            providersState: .unavailable(localized("trial.surge_provider_not_included")),
            router: router,
            generation: generation,
            streamState: .nearLive,
            surge: snapshot
        )
    }

    private func commitSingBoxSessionBaseline(
        version: SingBoxVersion,
        status: SingBoxStatusSnapshot,
        groups: SingBoxPolicyCatalog,
        mode: SingBoxClashModeStatus,
        router: RouterProfile,
        generation: UUID
    ) -> Bool {
        var nextDashboard = DashboardSnapshot.empty
        nextDashboard.versionLabel = version.version
        nextDashboard.replaceSingBoxStatus(with: status)
        nextDashboard.replaceSingBoxGroups(with: groups)
        nextDashboard.replaceSingBoxMode(with: mode)
        nextDashboard.connections = controllerSession.singBoxActiveConnections
        nextDashboard.insight = InsightSummarySnapshot(snapshot: nextDashboard)

        var health = ControllerHealthSnapshot.checking(router: router)
        health.set(.version, status: .ready(version.version))
        health.set(.configs, status: .ready(mode.currentMode))
        health.set(.proxies, status: .ready(localized("endpoint.groups_count \(groups.groups.count)")))
        health.set(
            .connections,
            status: .ready(localized("endpoint.active_count \(controllerSession.singBoxActiveConnections.count)"))
        )
        health.set(.rules, status: .idle)
        health.set(.providers, status: .idle)
        health.finalize()

        var unified = UnifiedControllerSnapshot.singBox(
            profile: router,
            version: version,
            status: status,
            groups: groups,
            mode: mode
        )
        unified.connectionsCount = controllerSession.singBoxActiveConnections.count
        let unsupported = localized("capability.unsupported_sing_box_data")
        return commitSessionBaseline(
            dashboard: nextDashboard,
            unified: unified,
            health: health,
            connectionState: .connected(version: version.version),
            rulesState: .unavailable(unsupported),
            providersState: .unavailable(unsupported),
            router: router,
            generation: generation,
            streamState: .live
        )
    }

    private func commitSessionBaseline(
        dashboard nextDashboard: DashboardSnapshot,
        unified nextUnified: UnifiedControllerSnapshot,
        health nextHealth: ControllerHealthSnapshot,
        connectionState nextConnectionState: ConnectionState,
        rulesState nextRulesState: EnhancedSnapshotState,
        providersState nextProvidersState: EnhancedSnapshotState,
        router: RouterProfile,
        generation: UUID,
        streamState: LiveStreamState,
        surge nextSurgeSnapshot: SurgeControlSnapshot? = nil
    ) -> Bool {
        guard isCurrentSession(routerID: router.id, generation: generation),
              controllerSession.baselineTransaction.isActive else {
            return false
        }

        let firstCommit = !controllerSession.hasCommittedBaseline
        let retainedTerminalChannelFailure = firstCommit
            ? isolatedTerminalMihomoChannelFailure(for: router)
            : nil
        let receivedAt = controllerSession.baselineTransaction.latestReceivedAt
            ?? controllerSession.latestReceivedAt
            ?? Date()
        for domain in LiveSessionPublicationDomain.allCases {
            _ = sessionPresentationCoordinator.markDirty(domain, generation: generation)
        }

        dashboard = nextDashboard
        publishDashboardDomains(.baseline)
        unifiedSnapshot = nextUnified
        controllerHealth = nextHealth
        connectionState = nextConnectionState
        rulesSnapshotState = nextRulesState
        providersSnapshotState = nextProvidersState
        surgeSnapshot = nextSurgeSnapshot ?? .empty
        trafficTimeline = controllerSession.trafficTimeline
        memoryTimeline = controllerSession.memoryTimeline
        connectionCountTimeline = controllerSession.connectionCountTimeline
        controllerSessionPresentation.publishRuntime(controllerSession.runtime)
        liveTrafficRate = controllerSession.trafficTimeline.samples.last.map {
            TrafficSnapshot(upload: $0.upload, download: $0.download)
        } ?? nextDashboard.traffic
        liveStreamUpdatedAt = receivedAt
        dashboardSessionControls.clearClosedConnections()
        if !controllerSession.pendingPresentation.closedConnections.entries.isEmpty {
            dashboardSessionControls.recordClosed(
                controllerSession.pendingPresentation.closedConnections.entries
            )
        }
        controllerSession.resetPendingPresentation()

        controllerSession.commitBaseline(at: receivedAt)
        liveRetryState.recordSuccess()
        if let retainedTerminalChannelFailure {
            controllerSession.state = .partial(retainedTerminalChannelFailure)
            setLiveStreamState(.partial(retainedTerminalChannelFailure))
            controllerSession.liveObservation.markFailure(partial: true)
            operationState = .partial(
                retainedTerminalChannelFailure,
                target: router.displayName,
                nextStep: localized("action.retry")
            )
        } else {
            controllerSession.state = .live
            setLiveStreamState(streamState)
            operationState = nil
        }
        updateLiveSessionRuntimePresentationDemand(forceVisible: true)

        for domain in [
            LiveSessionPublicationDomain.traffic,
            .connections,
            .memory,
        ] {
            sessionPresentationCoordinator.markPublished(domain, generation: generation)
        }
        if sessionPresentationCoordinator.observedDomains.contains(.logs),
           !dashboardSessionControls.logsPresentationPaused {
            publishControllerLogs(controllerSession.logBuffer.entries)
            sessionPresentationCoordinator.markPublished(.logs, generation: generation)
        }

        if firstCommit {
            Task { await recordSuccessfulConnection(for: router.id, generation: generation) }
        }
        return true
    }

    private func markSessionRefreshSuccess(router: RouterProfile) {
        let receivedAt = Date()
        controllerSession.recordReceived(at: receivedAt)
        if controllerSession.baselineTransaction.isActive {
            _ = attemptSessionBaselineCommit(
                for: router,
                generation: controllerSession.generation
            )
            return
        }

        let firstSuccess = controllerSession.lastSuccessAt == nil
        controllerSession.lastSuccessAt = max(
            controllerSession.lastSuccessAt ?? receivedAt,
            receivedAt
        )
        recomputeSessionState()
        if firstSuccess {
            let generation = controllerSession.generation
            Task { await recordSuccessfulConnection(for: router.id, generation: generation) }
        }
    }

    private func markSessionRefreshFailure(_ message: String, router: RouterProfile) {
        if controllerSession.baselineTransaction.isActive {
            markSessionBaselineFailure(message, router: router)
            return
        }
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

        if controllerSession.baselineTransaction.isActive {
            if controllerSession.baselineTransaction.isReconnect {
                let detail = controllerSession.state.failureDetail
                    ?? failure
                    ?? localized("operation.live_stream_reconnecting")
                controllerSession.state = .staleReconnecting(detail)
            } else if let failure {
                controllerSession.state = .failedBeforeFirstSnapshot(failure)
            } else {
                controllerSession.state = .connecting
            }
            return
        }

        if controllerSession.lastSuccessAt != nil {
            controllerSession.state = failure.map(LiveSessionState.partial) ?? .live
        } else if let failure {
            controllerSession.state = .failed(failure)
        } else {
            controllerSession.state = .connecting
        }
    }

    func recordControllerLog(
        _ log: LogMessage,
        receivedAt: Date = Date()
    ) {
        controllerSession.logBuffer.append(
            ControllerLogEntry(receivedAt: receivedAt, message: log)
        )
        controllerSession.recordReceived(at: receivedAt)
        noteSessionPublicationDirty(.logs)
    }

    func completeLiveTransportIngestion(
        receivedAt: Date,
        router: RouterProfile,
        streamState: LiveStreamState
    ) {
        let terminalChannelFailure = isolatedTerminalMihomoChannelFailure(
            for: router
        )
        controllerSession.recordReceived(at: receivedAt)
        if controllerSession.baselineTransaction.isActive {
            _ = attemptSessionBaselineCommit(
                for: router,
                generation: controllerSession.generation
            )
            if terminalChannelFailure != nil {
                controllerSession.liveObservation.markFailure(
                    partial: controllerSession.hasCommittedBaseline
                )
            }
            return
        }

        controllerSession.lastSuccessAt = max(
            controllerSession.lastSuccessAt ?? receivedAt,
            receivedAt
        )
        liveRetryState.recordSuccess()
        if terminalChannelFailure == nil {
            setLiveStreamState(streamState)
        } else {
            controllerSession.liveObservation.markFailure(partial: true)
        }
        recomputeSessionState()
    }

    private func isolatedTerminalMihomoChannelFailure(
        for router: RouterProfile
    ) -> String? {
        guard Self.usesMihomoLiveStreams(runtimeControllerKind(for: router)),
              liveSessionRuntime != nil,
              !liveRetryState.isScheduled,
              case .partial(let message) = liveStreamState else {
            return nil
        }
        return message
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
        let client = sessionMihomoClient
            ?? MihomoClient(profile: router, secret: controllerSecrets[router.id])
        startMihomoLogStream(client: client, routerID: router.id, generation: generation)
    }

    private func startMihomoLogStream(
        client: MihomoClient,
        routerID: RouterProfile.ID,
        generation: UUID
    ) {
        guard let runtime = liveSessionRuntime,
              let identity = liveSessionRuntimeIdentity,
              identity.controllerID == routerID,
              identity.generation == generation else {
            return
        }
        let upstreamLevel = controllerLogLevel.upstreamValue
        liveSessionTasks.start(.logs, for: identity) { @concurrent [weak self] _ in
            do {
                let stream = try await client.logsStream(level: upstreamLevel)
                for try await log in stream {
                    try Task.checkCancellation()
                    let scheduled = await runtime.ingestLog(
                        log,
                        source: .mihomoWebSocket
                    )
                    guard !scheduled.isEmpty else { continue }
                    await self?.scheduleLiveSessionRuntimePublications(
                        scheduled,
                        runtime: runtime,
                        identity: identity
                    )
                }
                try Task.checkCancellation()
                throw MihomoClientError.connectionFailure(.other)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await self?.handleLiveStreamFailure(
                    .logs,
                    error: error,
                    routerID: routerID,
                    generation: generation,
                    runtime: runtime
                )
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
        liveSessionTasks.cancel(group: .all)
        cancelLiveSessionRuntime()
        cancelSessionRefreshCoordinator()

        selectedRouterRefreshOperationID = nil
        isRefreshingDashboard = false
        liveRetryState.reset()
    }

    func startLiveStreams(
        for router: RouterProfile,
        isRetry: Bool = false,
        generation explicitGeneration: UUID? = nil
    ) {
        let generation = explicitGeneration ?? controllerSession.generation
        guard isCurrentSession(routerID: router.id, generation: generation) else { return }
        liveSessionTasks.cancel(group: .streaming)
        liveRetryState.consumeScheduledRetry()

        if isRetry || liveSessionRuntimeIdentity != LiveSessionRuntimeIdentity(
            controllerID: router.id,
            generation: generation
        ) {
            installLiveSessionRuntime(for: router, generation: generation)
        }

        if !isRetry {
            liveRetryState.reset()
            liveTrafficRate = TrafficSnapshot(upload: 0, download: 0)
            liveStreamUpdatedAt = nil
            trafficTimeline.reset()
            memoryTimeline.reset()
            connectionCountTimeline.reset()
            controllerSession.trafficTimeline.reset()
            controllerSession.memoryTimeline.reset()
            controllerSession.connectionCountTimeline.reset()
            controllerSession.liveObservation.reset()
        }

        let capabilities = effectiveUnifiedCapabilities(for: router)
        guard capabilities.traffic else {
            liveStreamRequested = true
            setLiveStreamState(.unavailable(localized("live.unsupported_backend")))
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
        if !controllerSession.baselineTransaction.isReconnect {
            setLiveStreamState(.connecting)
        }
        controllerSession.liveObservation.start(source: .mihomoWebSocket)

        let routerID = router.id
        let client = sessionMihomoClient
            ?? MihomoClient(profile: router, secret: controllerSecrets[router.id])
        guard let runtime = liveSessionRuntime,
              let identity = liveSessionRuntimeIdentity,
              identity.controllerID == routerID,
              identity.generation == generation else {
            return
        }

        liveSessionTasks.start(.traffic, for: identity) { @concurrent [weak self] _ in
            do {
                let stream = try await client.trafficStream()
                for try await event in stream {
                    try Task.checkCancellation()
                    let scheduled = await runtime.ingestTraffic(
                        event,
                        source: .mihomoWebSocket
                    )
                    guard !scheduled.isEmpty else { continue }
                    await self?.scheduleLiveSessionRuntimePublications(
                        scheduled,
                        runtime: runtime,
                        identity: identity
                    )
                }
                try Task.checkCancellation()
                throw MihomoClientError.connectionFailure(.other)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await self?.handleLiveStreamFailure(
                    .traffic,
                    error: error,
                    routerID: routerID,
                    generation: generation,
                    runtime: runtime
                )
            }
        }

        startMihomoLogStream(client: client, routerID: routerID, generation: generation)

        if capabilities.memory {
            liveSessionTasks.start(.memory, for: identity) { @concurrent [weak self] _ in
                do {
                    let stream = try await client.memoryStream()
                    for try await memory in stream {
                        try Task.checkCancellation()
                        let scheduled = await runtime.ingestMemory(
                            memory,
                            source: .mihomoWebSocket
                        )
                        guard !scheduled.isEmpty else { continue }
                        await self?.scheduleLiveSessionRuntimePublications(
                            scheduled,
                            runtime: runtime,
                            identity: identity
                        )
                    }
                    try Task.checkCancellation()
                    throw MihomoClientError.connectionFailure(.other)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    await self?.handleLiveStreamFailure(
                        .memory,
                        error: error,
                        routerID: routerID,
                        generation: generation,
                        runtime: runtime
                    )
                }
            }
        }

        if capabilities.connections {
            liveSessionTasks.start(.connections, for: identity) { @concurrent [weak self] _ in
                do {
                    let stream = try await client.connectionsStream()
                    for try await connections in stream {
                        try Task.checkCancellation()
                        let scheduled = await runtime.ingestMihomoConnections(
                            connections,
                            source: .mihomoWebSocket
                        )
                        guard !scheduled.isEmpty else { continue }
                        await self?.scheduleLiveSessionRuntimePublications(
                            scheduled,
                            runtime: runtime,
                            identity: identity
                        )
                    }
                    try Task.checkCancellation()
                    throw MihomoClientError.connectionFailure(.other)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    await self?.handleLiveStreamFailure(
                        .connections,
                        error: error,
                        routerID: routerID,
                        generation: generation,
                        runtime: runtime
                    )
                }
            }
        }
    }

    private func startSingBoxLiveSession(
        for router: RouterProfile,
        isRetry: Bool,
        generation: UUID
    ) {
        liveStreamRequested = true
        if !controllerSession.baselineTransaction.isReconnect {
            setLiveStreamState(.connecting)
        }
        controllerSession.liveObservation.start(source: .singBoxGRPC)

        let routerID = router.id
        let credential = controllerSecrets[router.id]
        guard let runtime = liveSessionRuntime,
              let identity = liveSessionRuntimeIdentity,
              identity.controllerID == routerID,
              identity.generation == generation else {
            return
        }
        liveSessionTasks.start(.singBox, for: identity) { @MainActor [weak self] _ in
            guard let self else { return }

            do {
                let client = try SingBoxGRPCClient(profile: router, credential: credential)
                defer { client.beginGracefulShutdown() }
                try await withTaskCancellationHandler {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            try await client.runConnections()
                            try Task.checkCancellation()
                            throw SingBoxGRPCError.transport(
                                "sing-box connection runtime ended"
                            )
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
                                try Task.checkCancellation()
                                let scheduled = await runtime.ingestSingBoxStatus(status)
                                guard !scheduled.isEmpty else { continue }
                                await self.scheduleLiveSessionRuntimePublications(
                                    scheduled,
                                    runtime: runtime,
                                    identity: identity
                                )
                            }
                            try Task.checkCancellation()
                            throw SingBoxGRPCError.transport(
                                "sing-box status stream ended"
                            )
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
                            try Task.checkCancellation()
                            throw SingBoxGRPCError.transport(
                                "sing-box group stream ended"
                            )
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
                            try Task.checkCancellation()
                            throw SingBoxGRPCError.transport(
                                "sing-box mode stream ended"
                            )
                        }
                        group.addTask {
                            let stream = try client.connectionStream(intervalMilliseconds: 1_000)
                            for try await connections in stream {
                                try Task.checkCancellation()
                                let scheduled = await runtime.ingestSingBoxConnections(connections)
                                guard !scheduled.isEmpty else { continue }
                                await self.scheduleLiveSessionRuntimePublications(
                                    scheduled,
                                    runtime: runtime,
                                    identity: identity
                                )
                            }
                            try Task.checkCancellation()
                            throw SingBoxGRPCError.transport(
                                "sing-box connection stream ended"
                            )
                        }
                        group.addTask {
                            let stream = client.logStream()
                            for try await logs in stream {
                                try Task.checkCancellation()
                                let messages = logs.messages.map(LogMessage.init(singBox:))
                                let scheduled = await runtime.ingestLogs(
                                    messages,
                                    reset: logs.reset,
                                    source: .singBoxGRPC
                                )
                                guard !scheduled.isEmpty else { continue }
                                await self.scheduleLiveSessionRuntimePublications(
                                    scheduled,
                                    runtime: runtime,
                                    identity: identity
                                )
                            }
                            try Task.checkCancellation()
                            throw SingBoxGRPCError.transport(
                                "sing-box log stream ended"
                            )
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

        let receivedAt = Date()
        var lowFrequencyDomains: DashboardPublicationDomains = []
        switch event {
        case .version(let version):
            controllerSession.singBoxVersion = version
            lowFrequencyDomains.insert(.metadata)

        case .groups(let groups):
            controllerSession.singBoxGroups = groups
            lowFrequencyDomains.formUnion([.policyGroups, .insight])

        case .mode(let mode):
            controllerSession.singBoxMode = mode
            lowFrequencyDomains.insert(.metadata)

        case .tailscale(let status):
            controllerSession.singBoxTailscaleStatus = status
            controllerSession.singBoxTailscaleError = nil

        case .tailscaleFailure(let message):
            controllerSession.singBoxTailscaleError = message
            return
        }

        completeLiveTransportIngestion(
            receivedAt: receivedAt,
            router: router,
            streamState: .live
        )
        guard !controllerSession.baselineTransaction.isActive,
              !lowFrequencyDomains.isEmpty else {
            return
        }
        publishSingBoxLowFrequencyPresentation(
            router: router,
            domains: lowFrequencyDomains
        )
    }

    private func publishSingBoxLowFrequencyPresentation(
        router: RouterProfile,
        domains: DashboardPublicationDomains
    ) {
        var nextDashboard = dashboard
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
        nextDashboard.insight = InsightSummarySnapshot(snapshot: nextDashboard)

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

        let nextConnectionState: ConnectionState = controllerSession.singBoxVersion.map {
            .connected(version: $0.version)
        } ?? .connecting
        let unsupported = localized("capability.unsupported_sing_box_data")

        if dashboardSessionControls.dashboardUpdatesPaused {
            controllerSession.pendingPresentation.dashboard = nextDashboard
            controllerSession.pendingPresentation.controllerHealth = health
            controllerSession.pendingPresentation.connectionState = nextConnectionState
            controllerSession.pendingPresentation.rulesSnapshotState = .unavailable(unsupported)
            controllerSession.pendingPresentation.providersSnapshotState = .unavailable(unsupported)
            if let nextUnified {
                controllerSession.pendingPresentation.unifiedSnapshot = nextUnified
            }
            return
        }

        dashboard = nextDashboard
        publishDashboardDomains(domains)
        controllerHealth = health
        connectionState = nextConnectionState
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
        if !controllerSession.baselineTransaction.isReconnect {
            setLiveStreamState(.connecting)
        }
        controllerSession.liveObservation.start(source: .surgeNearLive)

        let routerID = router.id
        let identity = LiveSessionRuntimeIdentity(controllerID: routerID, generation: generation)
        let client = sessionSurgeClient
            ?? SurgeHttpAPIClient(profile: router, apiKey: controllerSecrets[router.id])

        liveSessionTasks.start(.traffic, for: identity) { @concurrent [weak self] _ in
            guard let self else { return }
            do {
                while !Task.isCancelled {
                    async let traffic = client.traffic()
                    async let events = client.events()
                    async let activeRequests = client.activeRequests()
                    let update = try await (
                        traffic: traffic,
                        events: events,
                        activeRequests: activeRequests
                    )
                    try await ensureCurrentSession(routerID: routerID, generation: generation)

                    await applySurgeNearLive(
                        traffic: update.traffic,
                        events: update.events,
                        activeRequests: update.activeRequests,
                        recentRequests: nil,
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
                await handleLiveStreamFailure(
                    .surgeRefresh,
                    error: error,
                    routerID: routerID,
                    generation: generation
                )
            }
        }
    }

    func stopLiveStreams(resetRequest: Bool) {
        liveSessionTasks.cancel(group: .streaming)
        liveRetryState.reset()
        cancelLiveSessionRuntime()

        if resetRequest {
            liveStreamRequested = false
        }
        setLiveStreamState(resetRequest ? .stopped : .idle)
        controllerSession.liveObservation.stop()
        recomputeSessionState()
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
            connectionRatesReceivedAt: checkedAt,
            domains: [.connections]
        )
        completeLiveTransportIngestion(
            receivedAt: checkedAt,
            router: router,
            streamState: .nearLive
        )
    }

    func handleLiveStreamFailure(
        _ channel: LiveStreamChannel,
        error: Error,
        routerID: RouterProfile.ID,
        generation: UUID,
        runtime sourceRuntime: LiveSessionRuntime? = nil
    ) {
        guard isCurrentSession(routerID: routerID, generation: generation), liveStreamRequested else { return }
        if let sourceRuntime {
            guard let liveSessionRuntime,
                  liveSessionRuntime === sourceRuntime else {
                return
            }
        }

        let disposition = RouterTrialFailureCategory(error: error).retryDisposition
        guard disposition != .cancelled else { return }
        guard !liveRetryState.isScheduled else { return }

        let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
        let willRetry = disposition == .transient
            || (disposition == .retryOnce && liveRetryState.attempt == 0)
        let isolatesTerminalChannel = !willRetry
            && selectedRouter.map {
                Self.usesMihomoLiveStreams(runtimeControllerKind(for: $0))
            } == true
        controllerSession.liveObservation.markFailure(
            partial: controllerSession.hasCommittedBaseline
        )

        if isolatesTerminalChannel {
            if controllerSession.hasCommittedBaseline {
                controllerSession.state = .partial(message)
                setLiveStreamState(.partial(message))
                operationState = .partial(
                    message,
                    target: selectedRouter?.displayName,
                    nextStep: localized("action.retry")
                )
            } else {
                controllerSession.state = .failedBeforeFirstSnapshot(message)
                // The baseline is not usable yet, but the generation-owned
                // runtime and healthy sibling producers remain active.
                setLiveStreamState(.partial(message))
                connectionState = .failed(message)
                operationState = .error(
                    message,
                    target: selectedRouter?.displayName,
                    nextStep: localized("action.retry")
                )
            }
            return
        }

        cancelLiveSessionRuntime()
        if controllerSession.hasCommittedBaseline {
            if willRetry {
                cancelControllerOperationTasks()
                controllerSession.beginReconnect(message: message)
                cancelSessionRefreshAndStreamProducers()
                cancelSessionPublicationTasks()
                sessionPresentationCoordinator.begin(generation: generation)
                setLiveStreamState(.partial(message))
                operationState = .partial(
                    localized("operation.live_stream_reconnecting"),
                    target: selectedRouter?.displayName,
                    nextStep: message
                )
            } else {
                controllerSession.state = .failed(message)
                setLiveStreamState(.failed(message))
            }
        } else {
            controllerSession.state = .failedBeforeFirstSnapshot(message)
            setLiveStreamState(.failed(message))
        }

        connectionState = .failed(message)
        guard willRetry else { return }
        scheduleLiveStreamRetry(routerID: routerID, generation: generation)
    }

    private func cancelSessionRefreshAndStreamProducers() {
        liveSessionTasks.cancel(group: .producers)
        cancelSessionRefreshCoordinator()
        installSessionRefreshCoordinator(generation: controllerSession.generation)

        selectedRouterRefreshOperationID = nil
        isRefreshingDashboard = false
    }

    private func scheduleLiveStreamRetry(
        routerID: RouterProfile.ID,
        generation: UUID
    ) {
        guard isCurrentSession(routerID: routerID, generation: generation),
              liveStreamRequested,
              let router = selectedRouter,
              !liveSessionTasks.contains(.retry) else { return }

        guard let delay = liveRetryState.reserveDelay() else { return }

        let identity = LiveSessionRuntimeIdentity(controllerID: routerID, generation: generation)
        liveSessionTasks.start(.retry, for: identity) { @MainActor [self] token in
            do {
                try await Task.sleep(for: delay)
            } catch {
                if liveSessionTasks.owns(token),
                   isCurrentSession(routerID: routerID, generation: generation) {
                    liveRetryState.consumeScheduledRetry()
                }
                return
            }

            guard isCurrentSession(routerID: routerID, generation: generation),
                  liveStreamRequested,
                  liveSessionTasks.complete(token) else { return }
            liveRetryState.consumeScheduledRetry()
            startSessionRefreshCoordinator(for: router, generation: generation)
            startLiveStreams(for: router, isRetry: true, generation: generation)
        }
    }
}

private enum SingBoxSessionEvent: Sendable {
    case version(SingBoxVersion)
    case groups(SingBoxPolicyCatalog)
    case mode(SingBoxClashModeStatus)
    case tailscale(SingBoxTailscaleStatus)
    case tailscaleFailure(String)
}
