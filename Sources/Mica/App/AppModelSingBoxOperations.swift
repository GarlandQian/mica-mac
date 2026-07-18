import MicaCore

extension AppModel {
    var singBoxTailscaleStatus: SingBoxTailscaleStatus? {
        controllerSession.singBoxTailscaleStatus
    }

    var singBoxTailscaleError: String? {
        controllerSession.singBoxTailscaleError
    }

    func setSingBoxMode(_ mode: String, router: RouterProfile) {
        let previousMode = sessionActionDashboard.mode
        let commandID = beginCommand(
            .setMode,
            router: router,
            summary: localized("operation.changing_mode")
        )
        mutateSessionDashboard { $0.mode = mode }
        changingMode = true
        operationState = .working(
            localized("operation.changing_mode_progress"),
            action: TrialCommandAction.setMode.title(language: presentationLanguage),
            target: router.displayName
        )

        let generation = controllerSession.generation
        let credential = controllerSecrets[router.id]
        modeTask = Task {
            do {
                try await SingBoxGRPCClient.withConnectedClient(
                    profile: router,
                    credential: credential
                ) { client in
                    try await client.setClashMode(mode)
                }
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                if var status = controllerSession.singBoxMode {
                    status.currentMode = mode
                    controllerSession.singBoxMode = status
                }
                mutateSessionDashboard { $0.mode = mode }
                changingMode = false
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .success,
                    summary: localized("operation.mode_changed_summary")
                )
                operationState = .success(
                    localized("operation.mode_changed \(MicaStrings.displayMode(mode, language: presentationLanguage))"),
                    action: TrialCommandAction.setMode.title(language: presentationLanguage),
                    target: router.displayName
                )
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                mutateSessionDashboard { $0.mode = previousMode }
                changingMode = false
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: localized("operation.mode_change_failed")
                )
                operationState = .error(
                    Self.routerTrialFailureMessage(for: error, language: presentationLanguage),
                    action: TrialCommandAction.setMode.title(language: presentationLanguage),
                    target: router.displayName,
                    nextStep: localized("action.retry")
                )
            }
        }
    }

    func selectSingBoxNode(
        _ node: String,
        in groupID: String,
        router: RouterProfile
    ) {
        guard let previousNode = sessionActionDashboard.groups.first(where: { $0.id == groupID })?.selected else {
            operationState = .error(localized("operation.policy_group_gone \(groupID)"))
            return
        }
        let commandID = beginCommand(
            .switchNode,
            router: router,
            summary: localized("operation.switching_route")
        )
        mutateSessionDashboard { dashboard in
            if let index = dashboard.groups.firstIndex(where: { $0.id == groupID }) {
                dashboard.groups[index].selected = node
            }
        }
        switchingGroupID = groupID
        operationState = .working(
            localized("operation.switching_route_progress"),
            action: TrialCommandAction.switchNode.title(language: presentationLanguage),
            target: router.displayName
        )

        let generation = controllerSession.generation
        let credential = controllerSecrets[router.id]
        switchTask = Task {
            do {
                try await SingBoxGRPCClient.withConnectedClient(
                    profile: router,
                    credential: credential
                ) { client in
                    try await client.selectOutbound(groupTag: groupID, outboundTag: node)
                }
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                if var catalog = controllerSession.singBoxGroups,
                   let index = catalog.groups.firstIndex(where: { $0.tag == groupID }) {
                    catalog.groups[index].selected = node
                    controllerSession.singBoxGroups = catalog
                }
                switchingGroupID = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .success,
                    summary: localized("operation.switched_route")
                )
                operationState = .success(
                    localized("operation.switched_route"),
                    action: TrialCommandAction.switchNode.title(language: presentationLanguage),
                    target: router.displayName
                )
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                mutateSessionDashboard { dashboard in
                    if let index = dashboard.groups.firstIndex(where: { $0.id == groupID }) {
                        dashboard.groups[index].selected = previousNode
                    }
                }
                switchingGroupID = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: localized("operation.route_switch_failed")
                )
                operationState = .error(
                    Self.routerTrialFailureMessage(for: error, language: presentationLanguage),
                    action: TrialCommandAction.switchNode.title(language: presentationLanguage),
                    target: router.displayName,
                    nextStep: localized("action.retry")
                )
            }
        }
    }

    func testSingBoxPolicyGroup(_ groupID: String, router: RouterProfile) {
        testSingBoxOutbound(
            outboundTag: groupID,
            groupID: groupID,
            nodeName: nil,
            router: router
        )
    }

    func testSingBoxPolicyNode(_ nodeName: String, in groupID: String, router: RouterProfile) {
        testSingBoxOutbound(
            outboundTag: nodeName,
            groupID: groupID,
            nodeName: nodeName,
            router: router
        )
    }

    private func testSingBoxOutbound(
        outboundTag: String,
        groupID: String,
        nodeName: String?,
        router: RouterProfile
    ) {
        let commandID = beginCommand(
            .testDelay,
            router: router,
            summary: nodeName.map { localized("operation.testing_node_delay \($0)") }
                ?? localized("operation.testing_delay")
        )
        measuringDelayGroupID = nodeName == nil ? groupID : nil
        measuringDelayNode = nodeName.map {
            PolicyNodeLatencyTestTarget(groupID: groupID, nodeName: $0)
        }
        operationState = .working(
            nodeName.map { localized("operation.testing_node_delay \($0)") }
                ?? localized("operation.testing_delay_progress"),
            action: TrialCommandAction.testDelay.title(language: presentationLanguage),
            target: nodeName ?? groupID
        )

        let generation = controllerSession.generation
        let credential = controllerSecrets[router.id]
        delayTask = Task {
            do {
                try await SingBoxGRPCClient.withConnectedClient(
                    profile: router,
                    credential: credential
                ) { client in
                    try await client.runURLTest(outboundTag: outboundTag)
                }
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                measuringDelayGroupID = nil
                measuringDelayNode = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .success,
                    summary: localized("operation.sing_box_url_test_requested \(outboundTag)")
                )
                operationState = .success(
                    localized("operation.sing_box_url_test_requested \(outboundTag)"),
                    action: TrialCommandAction.testDelay.title(language: presentationLanguage),
                    target: outboundTag
                )
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                measuringDelayGroupID = nil
                measuringDelayNode = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: nodeName.map { localized("operation.node_delay_test_failed \($0)") }
                        ?? localized("operation.delay_test_failed")
                )
                operationState = .error(
                    Self.routerTrialFailureMessage(for: error, language: presentationLanguage),
                    action: TrialCommandAction.testDelay.title(language: presentationLanguage),
                    target: outboundTag,
                    nextStep: localized("action.retry")
                )
            }
        }
    }

    func closeSingBoxConnection(_ connection: ConnectionSnapshot, router: RouterProfile) {
        let commandID = beginCommand(
            .closeConnection,
            router: router,
            summary: localized("operation.closing_connection")
        )
        closingConnectionID = connection.id
        closingConnectionGroupID = nil
        closingAllConnections = false
        operationState = .working(
            localized("operation.closing_connection_progress"),
            action: TrialCommandAction.closeConnection.title(language: presentationLanguage),
            target: router.displayName
        )

        let generation = controllerSession.generation
        let credential = controllerSecrets[router.id]
        connectionTask = Task {
            do {
                try await SingBoxGRPCClient.withConnectedClient(
                    profile: router,
                    credential: credential
                ) { client in
                    try await client.closeConnection(id: connection.id)
                }
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                controllerSession.singBoxActiveConnections.removeAll { $0.id == connection.id }
                recordClosedSingBoxConnections([connection])
                closingConnectionID = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .success,
                    summary: localized("operation.closed_connection")
                )
                operationState = .success(
                    localized("operation.closed_connection"),
                    action: TrialCommandAction.closeConnection.title(language: presentationLanguage),
                    target: router.displayName
                )
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                closingConnectionID = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: localized("operation.close_connection_failed")
                )
                operationState = .error(
                    Self.routerTrialFailureMessage(for: error, language: presentationLanguage),
                    action: TrialCommandAction.closeConnection.title(language: presentationLanguage),
                    target: router.displayName,
                    nextStep: localized("action.refresh")
                )
            }
        }
    }

    func closeAllSingBoxConnections(router: RouterProfile) {
        let commandID = beginCommand(
            .closeAll,
            router: router,
            summary: localized("operation.closing_all")
        )
        let closingSnapshot = dashboard.connections
        guard !closingSnapshot.isEmpty else {
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
        let credential = controllerSecrets[router.id]
        connectionTask = Task {
            do {
                try await SingBoxGRPCClient.withConnectedClient(
                    profile: router,
                    credential: credential
                ) { client in
                    try await client.closeAllConnections()
                }
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                controllerSession.singBoxActiveConnections.removeAll(keepingCapacity: true)
                recordClosedSingBoxConnections(closingSnapshot)
                closingAllConnections = false
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
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                closingAllConnections = false
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: localized("operation.close_all_failed")
                )
                operationState = .error(
                    Self.routerTrialFailureMessage(for: error, language: presentationLanguage),
                    action: TrialCommandAction.closeAll.title(language: presentationLanguage),
                    target: router.displayName,
                    nextStep: localized("action.refresh")
                )
            }
        }
    }

    func clearSingBoxControllerLogs(router: RouterProfile) {
        runtimeOperationTask?.cancel()
        let commandID = beginCommand(
            .singBoxClearLogs,
            router: router,
            summary: localized("traffic.clear_logs")
        )
        runningRuntimeOperationID = "sing-box-clear-logs"
        operationState = .working(
            localized("traffic.clear_logs"),
            action: TrialCommandAction.singBoxClearLogs.title(language: presentationLanguage),
            target: router.displayName
        )

        let generation = controllerSession.generation
        let credential = controllerSecrets[router.id]
        runtimeOperationTask = Task {
            do {
                try await SingBoxGRPCClient.withConnectedClient(
                    profile: router,
                    credential: credential
                ) { client in
                    try await client.clearLogs()
                }
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                controllerSession.logBuffer.removeAll()
                mutateSessionDashboard { $0.controllerLogs = [] }
                runningRuntimeOperationID = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .success,
                    summary: localized("traffic.clear_logs")
                )
                operationState = .success(
                    localized("traffic.clear_logs"),
                    action: TrialCommandAction.singBoxClearLogs.title(language: presentationLanguage),
                    target: router.displayName
                )
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                runningRuntimeOperationID = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: localized("traffic.clear_logs")
                )
                operationState = .error(
                    Self.routerTrialFailureMessage(for: error, language: presentationLanguage),
                    action: TrialCommandAction.singBoxClearLogs.title(language: presentationLanguage),
                    target: router.displayName,
                    nextStep: localized("action.retry")
                )
            }
        }
    }

    func setSingBoxTailscaleExitNode(endpointTag: String, stableID: String) {
        runSingBoxTailscaleOperation(
            action: .singBoxTailscaleExitNode,
            endpointTag: endpointTag
        ) { client in
            try await client.setTailscaleExitNode(endpointTag: endpointTag, stableID: stableID)
        }
    }

    func logoutSingBoxTailscale(endpointTag: String) {
        runSingBoxTailscaleOperation(
            action: .singBoxTailscaleLogout,
            endpointTag: endpointTag
        ) { client in
            try await client.tailscaleLogout(endpointTag: endpointTag)
        }
    }

    private func runSingBoxTailscaleOperation(
        action: TrialCommandAction,
        endpointTag: String,
        operation: @Sendable @escaping (SingBoxGRPCClient) async throws -> Void
    ) {
        runtimeOperationTask?.cancel()
        guard let router = selectedRouter,
              runtimeControllerKind(for: router) == .singBoxCompatible,
              isCurrentSession(routerID: router.id, generation: controllerSession.generation) else {
            operationState = .error(localized("operation.select_router_config"))
            return
        }

        let commandID = beginCommand(
            action,
            router: router,
            summary: localized("diagnostics.operation_tailscale")
        )
        runningRuntimeOperationID = action.rawValue
        operationState = .working(
            localized("diagnostics.operation_tailscale_detail"),
            action: action.title(language: presentationLanguage),
            target: endpointTag
        )

        let generation = controllerSession.generation
        let credential = controllerSecrets[router.id]
        runtimeOperationTask = Task {
            do {
                try await SingBoxGRPCClient.withConnectedClient(
                    profile: router,
                    credential: credential,
                    operation: operation
                )
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                runningRuntimeOperationID = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .success,
                    summary: localized("diagnostics.operation_tailscale")
                )
                operationState = .success(
                    localized("diagnostics.operation_tailscale"),
                    action: action.title(language: presentationLanguage),
                    target: endpointTag
                )
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                runningRuntimeOperationID = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: localized("diagnostics.operation_tailscale")
                )
                operationState = .error(
                    Self.routerTrialFailureMessage(for: error, language: presentationLanguage),
                    action: action.title(language: presentationLanguage),
                    target: endpointTag,
                    nextStep: localized("action.retry")
                )
            }
        }
    }

    private func recordClosedSingBoxConnections(_ connections: [ConnectionSnapshot]) {
        guard !connections.isEmpty else { return }

        recordClosedSessionConnections(connections)
        removeSessionConnections(connections)
    }

    func removeSessionConnections(_ connections: [ConnectionSnapshot]) {
        guard !connections.isEmpty else { return }

        let closedIDs = Set(connections.map(\.id))
        mutateSessionDashboard { dashboard in
            dashboard.connections.removeAll { closedIDs.contains($0.id) }
        }
    }

    var sessionActionDashboard: DashboardSnapshot {
        controllerSession.pendingPresentation.dashboard ?? dashboard
    }

    var sessionActionSurgeSnapshot: SurgeControlSnapshot {
        controllerSession.pendingPresentation.surgeSnapshot ?? surgeSnapshot
    }

    func mutateSessionDashboard(
        _ mutation: (inout DashboardSnapshot) -> Void
    ) {
        if dashboardSessionControls.dashboardUpdatesPaused {
            var pendingDashboard = controllerSession.pendingPresentation.dashboard ?? dashboard
            mutation(&pendingDashboard)
            controllerSession.pendingPresentation.dashboard = pendingDashboard
        } else {
            mutation(&dashboard)
        }
    }

    func recordClosedSessionConnections(_ connections: [ConnectionSnapshot]) {
        guard !connections.isEmpty else { return }

        if dashboardSessionControls.dashboardUpdatesPaused {
            controllerSession.pendingPresentation.closedConnections.record(connections)
        } else {
            dashboardSessionControls.recordClosed(connections)
        }
    }
}
