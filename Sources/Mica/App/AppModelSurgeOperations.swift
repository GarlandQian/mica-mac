import Foundation
import MicaCore

extension AppModel {
    /// Clears every Surge in-flight marker to its idle baseline. All Surge
    /// operations share a single `surgeTask` and cancel the previous one on
    /// entry, so at most one Surge op is ever live. Calling this at the start
    /// of each mutating op (mirroring `refreshSurgeRouter`/`probeSurgeRouter`,
    /// which already reset these inline) guarantees a superseded op's marker
    /// can never linger: the cancelled task's continuation returns without
    /// touching any flag, and the new op re-establishes only its own. This
    /// also self-heals the case where `deleteRouter`/`selectRouter` cancel an
    /// in-flight Surge op without running its continuation.
    private func resetSurgeInFlightMarkers() {
        changingSurgeOutbound = false
        switchingSurgePolicyGroup = nil
        testingSurgePolicyGroup = nil
        killingSurgeRequestID = nil
        killingSurgeProjectedConnectionID = nil
        reloadingRules = false
        reloadingSurgeProfile = false
        changingControllerLogLevel = false
    }

    func setSurgeOutboundMode(_ mode: String) {
        surgeTask?.cancel()
        resetSurgeInFlightMarkers()

        guard let router = selectedRouter, runtimeControllerKind(for: router) == .surgeCompatible else {
            operationState = .error(localized("operation.select_surge_mode"))
            return
        }

        guard controllerSupportsLiveAction(.setOutboundMode, router: router, action: TrialCommandAction.surgeOutboundMode.title(language: presentationLanguage)) else {
            return
        }

        let commandID = beginCommand(.surgeOutboundMode, router: router, summary: localized("operation.changing_surge_mode"))
        changingSurgeOutbound = true
        operationState = .working(localized("operation.changing_surge_mode"), action: TrialCommandAction.surgeOutboundMode.title(language: presentationLanguage), target: router.displayName)
        let generation = controllerSession.generation
        let apiKey = controllerSecrets[router.id]

        surgeTask = Task {
            let client = SurgeHttpAPIClient(profile: router, apiKey: apiKey)
            var didSetMode = false

            do {
                try await client.setOutboundMode(mode)
                didSetMode = true
                let snapshot = try await client.snapshot()

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                applySurgeSnapshot(snapshot, router: router)
                changingSurgeOutbound = false
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.surge_mode_changed"))
                operationState = .success(localized("operation.surge_mode_changed"), action: TrialCommandAction.surgeOutboundMode.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                changingSurgeOutbound = false
                if didSetMode {
                    var snapshot = sessionActionSurgeSnapshot
                    snapshot.outboundMode = mode
                    snapshot.checkedAt = Date()
                    applySurgeSnapshot(snapshot, router: router)
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .partial,
                        summary: localized("operation.surge_mode_changed_refresh_failed")
                    )
                    operationState = .partial(
                        localized("operation.surge_mode_changed_refresh_failed"),
                        action: TrialCommandAction.surgeOutboundMode.title(language: presentationLanguage),
                        target: router.displayName,
                        nextStep: Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                    )
                } else {
                    finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.surge_mode_change_failed"))
                    operationState = .error(Self.routerTrialFailureMessage(for: error, language: presentationLanguage), action: TrialCommandAction.surgeOutboundMode.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry_test"))
                }
            }
        }
    }

    func selectSurgePolicy(_ policy: String, in group: String) {
        surgeTask?.cancel()
        resetSurgeInFlightMarkers()

        guard let router = selectedRouter, runtimeControllerKind(for: router) == .surgeCompatible else {
            operationState = .error(localized("operation.select_surge_policy"))
            return
        }

        guard controllerSupportsLiveAction(.selectSurgePolicy, router: router, action: TrialCommandAction.surgePolicySelect.title(language: presentationLanguage)) else {
            return
        }

        let commandID = beginCommand(.surgePolicySelect, router: router, summary: localized("operation.switching_surge_policy"))
        switchingSurgePolicyGroup = group
        operationState = .working(localized("operation.switching_surge_policy"), action: TrialCommandAction.surgePolicySelect.title(language: presentationLanguage), target: router.displayName)
        let generation = controllerSession.generation
        let apiKey = controllerSecrets[router.id]

        surgeTask = Task {
            let client = SurgeHttpAPIClient(profile: router, apiKey: apiKey)
            var didSelectPolicy = false

            do {
                try await client.selectPolicy(group: group, policy: policy)
                didSelectPolicy = true
                let snapshot = try await client.snapshot()

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                applySurgeSnapshot(snapshot, router: router)
                switchingSurgePolicyGroup = nil
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.surge_policy_switched"))
                operationState = .success(localized("operation.surge_policy_switched"), action: TrialCommandAction.surgePolicySelect.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                switchingSurgePolicyGroup = nil
                if didSelectPolicy {
                    var snapshot = sessionActionSurgeSnapshot
                    if let index = snapshot.policyGroups.firstIndex(where: { $0.name == group }) {
                        snapshot.policyGroups[index].selected = policy
                    }
                    snapshot.checkedAt = Date()
                    applySurgeSnapshot(snapshot, router: router)
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .partial,
                        summary: localized("operation.surge_policy_switched_refresh_failed")
                    )
                    operationState = .partial(
                        localized("operation.surge_policy_switched_refresh_failed"),
                        action: TrialCommandAction.surgePolicySelect.title(language: presentationLanguage),
                        target: group,
                        nextStep: Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                    )
                } else {
                    finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.surge_policy_switch_failed"))
                    operationState = .error(Self.routerTrialFailureMessage(for: error, language: presentationLanguage), action: TrialCommandAction.surgePolicySelect.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry_test"))
                }
            }
        }
    }

    func testSurgePolicyGroup(_ group: String) {
        surgeTask?.cancel()
        resetSurgeInFlightMarkers()

        guard let router = selectedRouter, runtimeControllerKind(for: router) == .surgeCompatible else {
            operationState = .error(localized("operation.select_surge_test"))
            return
        }

        guard controllerSupportsLiveAction(.testSurgePolicy, router: router, action: TrialCommandAction.surgePolicyTest.title(language: presentationLanguage)) else {
            return
        }

        let commandID = beginCommand(.surgePolicyTest, router: router, summary: localized("operation.testing_surge_policy"))
        testingSurgePolicyGroup = group
        operationState = .working(localized("operation.testing_surge_policy"), action: TrialCommandAction.surgePolicyTest.title(language: presentationLanguage), target: router.displayName)
        let generation = controllerSession.generation
        let apiKey = controllerSecrets[router.id]

        surgeTask = Task {
            let client = SurgeHttpAPIClient(profile: router, apiKey: apiKey)

            do {
                let result = try await client.testPolicyGroup(group)

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                var snapshot = sessionActionSurgeSnapshot
                if let index = snapshot.policyGroups.firstIndex(where: { $0.name == group }) {
                    snapshot.policyGroups[index].latency = result.delay
                }
                applySurgeSnapshot(snapshot, router: router)
                testingSurgePolicyGroup = nil
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.surge_policy_tested"))
                operationState = .success(localized("operation.surge_policy_tested"), action: TrialCommandAction.surgePolicyTest.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                testingSurgePolicyGroup = nil
                finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.surge_policy_test_failed"))
                operationState = .error(Self.routerTrialFailureMessage(for: error, language: presentationLanguage), action: TrialCommandAction.surgePolicyTest.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry_test"))
            }
        }
    }

    func killSurgeRequest(
        _ request: SurgeActiveRequest,
        projectedID: String? = nil,
        closedConnection: ConnectionSnapshot? = nil
    ) {
        surgeTask?.cancel()
        resetSurgeInFlightMarkers()

        guard let router = selectedRouter, runtimeControllerKind(for: router) == .surgeCompatible else {
            operationState = .error(localized("operation.select_surge_kill"))
            return
        }

        guard controllerSupportsLiveAction(.killActiveRequest, router: router, action: TrialCommandAction.surgeRequestKill.title(language: presentationLanguage)) else {
            return
        }

        let commandID = beginCommand(.surgeRequestKill, router: router, summary: localized("operation.killing_surge_request"))
        killingSurgeRequestID = request.id
        killingSurgeProjectedConnectionID = projectedID ?? DashboardSnapshot.surgeRequestDisplayID(for: request)
        operationState = .working(localized("operation.killing_surge_request"), action: TrialCommandAction.surgeRequestKill.title(language: presentationLanguage), target: router.displayName)
        let generation = controllerSession.generation
        let apiKey = controllerSecrets[router.id]

        surgeTask = Task {
            let client = SurgeHttpAPIClient(profile: router, apiKey: apiKey)
            var didKillRequest = false

            do {
                try await client.killActiveRequest(id: request.id)
                didKillRequest = true
                let activeRequests = try await client.activeRequests()
                let recentRequests: SurgeActiveRequestsResponse?
                do {
                    recentRequests = try await client.recentRequests()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    recentRequests = nil
                }

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                var snapshot = sessionActionSurgeSnapshot
                snapshot.activeRequests = activeRequests.requests
                if let recentRequests {
                    snapshot.recentRequests = recentRequests.requests
                }
                applySurgeSnapshot(snapshot, router: router)
                if let closedConnection {
                    recordClosedSessionConnections([closedConnection])
                }
                killingSurgeRequestID = nil
                killingSurgeProjectedConnectionID = nil
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.surge_request_killed"))
                operationState = .success(localized("operation.surge_request_killed"), action: TrialCommandAction.surgeRequestKill.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                if didKillRequest, let closedConnection {
                    recordClosedSessionConnections([closedConnection])
                    removeSessionConnections([closedConnection])
                }
                killingSurgeRequestID = nil
                killingSurgeProjectedConnectionID = nil
                if didKillRequest {
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .partial,
                        summary: localized("operation.surge_request_killed_refresh_failed")
                    )
                    operationState = .partial(
                        localized("operation.surge_request_killed_refresh_failed"),
                        action: TrialCommandAction.surgeRequestKill.title(language: presentationLanguage),
                        target: router.displayName,
                        nextStep: Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                    )
                } else {
                    finishCommand(commandID, routerID: router.id, status: .failed, summary: localized("operation.surge_request_kill_failed"))
                    operationState = .error(Self.routerTrialFailureMessage(for: error, language: presentationLanguage), action: TrialCommandAction.surgeRequestKill.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.refresh"))
                }
            }
        }
    }

    func reloadSurgeProfile() {
        surgeTask?.cancel()
        resetSurgeInFlightMarkers()

        guard let router = selectedRouter,
              runtimeControllerKind(for: router) == .surgeCompatible else {
            operationState = .error(localized("operation.select_surge_profile_reload"))
            return
        }

        guard controllerSupportsLiveAction(
            .reloadProfile,
            router: router,
            action: TrialCommandAction.surgeProfileReload.title(language: presentationLanguage)
        ) else {
            return
        }

        let commandID = beginCommand(
            .surgeProfileReload,
            router: router,
            summary: localized("operation.reloading_surge_profile")
        )
        reloadingSurgeProfile = true
        operationState = .working(
            localized("operation.reloading_surge_profile"),
            action: TrialCommandAction.surgeProfileReload.title(language: presentationLanguage),
            target: router.displayName
        )
        let generation = controllerSession.generation
        let apiKey = controllerSecrets[router.id]

        surgeTask = Task {
            let client = SurgeHttpAPIClient(profile: router, apiKey: apiKey)
            do {
                try await client.reloadProfile()
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                reloadingSurgeProfile = false
                requestImmediateSessionRefresh(isUserInitiated: true)
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .success,
                    summary: localized("operation.surge_profile_reloaded")
                )
                operationState = .success(
                    localized("operation.surge_profile_reloaded"),
                    action: TrialCommandAction.surgeProfileReload.title(language: presentationLanguage),
                    target: router.displayName
                )
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                reloadingSurgeProfile = false
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: localized("operation.surge_profile_reload_failed")
                )
                operationState = .error(
                    Self.routerTrialFailureMessage(for: error, language: presentationLanguage),
                    action: TrialCommandAction.surgeProfileReload.title(language: presentationLanguage),
                    target: router.displayName,
                    nextStep: localized("action.retry")
                )
            }
        }
    }

    func reloadSurgeRules(_ router: RouterProfile) {
        surgeTask?.cancel()
        resetSurgeInFlightMarkers()

        let commandID = beginCommand(.reloadRules, router: router, summary: localized("operation.reloading_rules"))
        reloadingRules = true
        rulesSnapshotState = .loading
        operationState = .working(localized("operation.reloading_rules_progress"), action: TrialCommandAction.reloadRules.title(language: presentationLanguage), target: router.displayName)
        let generation = controllerSession.generation
        let apiKey = controllerSecrets[router.id]

        surgeTask = Task {
            let client = SurgeHttpAPIClient(profile: router, apiKey: apiKey)

            do {
                let snapshot = try await client.snapshot()

                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                applySurgeSnapshot(snapshot, router: router)
                reloadingRules = false
                finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.surge_snapshot_loaded"))
                operationState = .success(localized("operation.reloaded_rules \(dashboard.rules.count)"), action: TrialCommandAction.reloadRules.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation), !Task.isCancelled else {
                    return
                }

                reloadingRules = false
                rulesSnapshotState = .unavailable(Self.routerTrialFailureMessage(for: error, language: presentationLanguage))
                finishCommand(commandID, routerID: router.id, status: .partial, summary: localized("operation.surge_rules_unavailable"))
                operationState = .partial(localized("operation.rules_unavailable"), action: TrialCommandAction.reloadRules.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.refresh"))
            }
        }
    }

    func applySurgeSnapshot(
        _ snapshot: SurgeControlSnapshot,
        router: RouterProfile,
        connectionRatesReceivedAt: Date? = nil
    ) {
        let receivedAt = connectionRatesReceivedAt ?? snapshot.checkedAt ?? Date()
        stageSurgeSnapshot(
            snapshot,
            receivedAt: receivedAt,
            includesCompleteBaseline: false
        )

        if dashboardSessionControls.dashboardUpdatesPaused {
            controllerSession.pendingPresentation.surgeSnapshot = snapshot
            return
        }

        dashboardSessionControls.recordClosed(
            DashboardSnapshot.surgeRecentRequestConnections(
                for: snapshot.recentRequests,
                language: presentationLanguage
            )
        )
        publishStagedSurgePresentation(router: router, domains: .baseline)
        noteSessionPublicationDirty(.logs, immediate: true)
    }

    func projectedSurgeDashboard(
        _ snapshot: SurgeControlSnapshot,
        connectionRatesReceivedAt: Date?
    ) -> DashboardSnapshot {
        var projected = DashboardSnapshot(surge: snapshot, language: presentationLanguage)
        guard let connectionRatesReceivedAt else { return projected }

        let response = controllerSession.connectionTransferRates.enriching(
            ConnectionsResponse(connections: projected.connections),
            receivedAt: connectionRatesReceivedAt
        )
        projected.connections = response.connections
        return projected
    }

    func closeSurgeProjectedConnection(_ connection: ConnectionSnapshot) {
        guard let request = surgeRequest(forProjectedConnectionID: connection.id),
              !request.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            operationState = .error(localized("operation.surge_request_not_found"), nextStep: localized("action.refresh"))
            return
        }

        killSurgeRequest(
            request,
            projectedID: connection.id,
            closedConnection: connection
        )
    }

    func closeAllSurgeProjectedConnections(router: RouterProfile) {
        let projectedConnections = dashboard.connections
        let snapshot = sessionActionSurgeSnapshot
        let projectedIDs = DashboardSnapshot.surgeRequestDisplayIDs(for: snapshot.activeRequests)
        let requests = Array(zip(snapshot.activeRequests, projectedIDs))
        let commandID = beginCommand(
            .closeAll,
            router: router,
            summary: localized("operation.closing_all")
        )

        guard !projectedConnections.isEmpty, !requests.isEmpty else {
            finishCommand(
                commandID,
                routerID: router.id,
                status: .success,
                summary: localized("operation.no_active_connections")
            )
            operationState = .success(
                localized("operation.no_active_connections"),
                action: TrialCommandAction.closeAll.title(language: presentationLanguage),
                target: router.displayName
            )
            return
        }

        closingConnectionID = nil
        closingConnectionGroupID = nil
        closingAllConnections = true
        operationState = .working(
            localized("operation.closing_all_progress"),
            action: TrialCommandAction.closeAll.title(language: presentationLanguage),
            target: router.displayName
        )

        let generation = controllerSession.generation
        let apiKey = controllerSecrets[router.id]
        connectionTask = Task {
            let client = SurgeHttpAPIClient(profile: router, apiKey: apiKey)
            var closed: [ConnectionSnapshot] = []
            var firstFailure: Error?

            for (request, projectedID) in requests {
                do {
                    try Task.checkCancellation()
                    guard !request.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw SurgeHttpAPIError.malformedResponse("/v1/requests/active")
                    }
                    try await client.killActiveRequest(id: request.id)
                    if let connection = projectedConnections.first(where: { $0.id == projectedID }) {
                        closed.append(connection)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    firstFailure = firstFailure ?? error
                }
            }

            do {
                let activeRequests = try await client.activeRequests()
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                var snapshot = sessionActionSurgeSnapshot
                snapshot.activeRequests = activeRequests.requests
                snapshot.checkedAt = Date()
                applySurgeSnapshot(snapshot, router: router)
            } catch is CancellationError {
                return
            } catch {
                firstFailure = firstFailure ?? error
            }

            guard isCurrentSession(routerID: router.id, generation: generation),
                  !Task.isCancelled else {
                return
            }

            recordClosedSessionConnections(closed)
            removeSessionConnections(closed)
            closingAllConnections = false

            if let firstFailure {
                let failure = Self.routerTrialFailureMessage(
                    for: firstFailure,
                    language: presentationLanguage
                )
                if closed.isEmpty {
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .failed,
                        summary: localized("operation.close_all_failed")
                    )
                    operationState = .error(
                        failure,
                        action: TrialCommandAction.closeAll.title(language: presentationLanguage),
                        target: router.displayName,
                        nextStep: localized("action.refresh")
                    )
                } else {
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .partial,
                        summary: localized(
                            "operation.close_connection_group_partial \(closed.count) \(projectedConnections.count)"
                        )
                    )
                    operationState = .partial(
                        localized(
                            "operation.close_connection_group_partial \(closed.count) \(projectedConnections.count)"
                        ),
                        action: TrialCommandAction.closeAll.title(language: presentationLanguage),
                        target: router.displayName,
                        nextStep: failure
                    )
                }
            } else {
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .success,
                    summary: localized("operation.closed_all")
                )
                operationState = .success(
                    localized("operation.closed_all"),
                    action: TrialCommandAction.closeAll.title(language: presentationLanguage),
                    target: router.displayName
                )
            }
        }
    }

    func isKillingSurgeProjectedConnection(_ projectedID: String) -> Bool {
        killingSurgeProjectedConnectionID == projectedID
    }

    private func surgeRequest(forProjectedConnectionID projectedID: String) -> SurgeActiveRequest? {
        let snapshot = sessionActionSurgeSnapshot
        let projectedIDs = DashboardSnapshot.surgeRequestDisplayIDs(for: snapshot.activeRequests)
        return zip(snapshot.activeRequests, projectedIDs).first { _, id in
            id == projectedID
        }?.0
    }
}
