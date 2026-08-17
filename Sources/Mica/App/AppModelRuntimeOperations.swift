import Foundation
import MicaCore

extension AppModel {
    func performDiagnosticsRuntimeOperation(_ operationID: String) {
        switch operationID {
        case "memory":
            checkMihomoMemory()
        case "dns-flush":
            if let selectedRouter, effectiveUnifiedControllerType(for: selectedRouter) == .surgeHTTPAPI {
                flushSurgeDNSCache()
            } else {
                flushMihomoDNSCache()
            }
        case "configuration-reload":
            reloadMihomoConfiguration()
        case "geo-resources":
            updateMihomoGeoData()
        case "cache-flush":
            flushMihomoFakeIPCache()
        case "core-restart":
            restartMihomoCore()
        case "core-upgrade":
            upgradeMihomoCore()
        default:
            operationState = .partial(localized("operation.capability_operation_unavailable"), nextStep: localized("action.refresh"))
        }
    }

    private func checkMihomoMemory() {
        guard let router = selectedMihomoRuntimeRouter(action: TrialCommandAction.memoryCheck.title(language: presentationLanguage)) else {
            return
        }

        guard effectiveUnifiedCapabilities(for: router).memory else {
            operationState = .partial(
                localized("operation.capability_operation_unavailable"),
                action: TrialCommandAction.memoryCheck.title(language: presentationLanguage),
                target: router.displayName,
                nextStep: localized("action.refresh")
            )
            return
        }

        let commandID = beginCommand(.memoryCheck, router: router, summary: localized("operation.memory_checking"))
        let routerID = router.id
        let generation = controllerSession.generation
        let client = MihomoClient(profile: router, secret: controllerSecrets[router.id])

        runtimeOperationTask?.cancel()
        runningRuntimeOperationID = "memory"
        operationState = .working(localized("operation.memory_checking"), action: TrialCommandAction.memoryCheck.title(language: presentationLanguage), target: router.displayName)

        runtimeOperationTask = Task {
            do {
                let memory = try await client.memory()
                guard isCurrentSession(routerID: routerID, generation: generation), !Task.isCancelled else {
                    return
                }

                controllerSession.runtime.recordMemory(memory)
                runningRuntimeOperationID = nil
                finishCommand(commandID, routerID: routerID, status: .success, summary: localized("operation.memory_checked \(formatMemoryBytes(memory.inuse))"))
                operationState = .success(
                    localized("operation.memory_checked \(formatMemoryBytes(memory.inuse))"),
                    action: TrialCommandAction.memoryCheck.title(language: presentationLanguage),
                    target: router.displayName
                )
            } catch {
                guard isCurrentSession(routerID: routerID, generation: generation), !Task.isCancelled else {
                    return
                }

                runningRuntimeOperationID = nil
                let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                finishCommand(commandID, routerID: routerID, status: .failed, summary: message)
                operationState = .error(message, action: TrialCommandAction.memoryCheck.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry"))
            }
        }
    }

    private func flushMihomoDNSCache() {
        runMihomoMaintenanceOperation(
            operationID: "dns-flush",
            action: .dnsFlush,
            unifiedAction: .dnsFlush,
            workingKey: "operation.dns_flush_running",
            successKey: "operation.dns_flush_done"
        ) { client in
            try await client.flushDNSCache()
        }
    }

    private func flushSurgeDNSCache() {
        guard let router = selectedSurgeRuntimeRouter(action: TrialCommandAction.dnsFlush.title(language: presentationLanguage)) else {
            return
        }

        guard controllerSupportsLiveAction(
            .dnsFlush,
            router: router,
            action: TrialCommandAction.dnsFlush.title(language: presentationLanguage)
        ) else {
            return
        }

        let commandID = beginCommand(.dnsFlush, router: router, summary: localized("operation.dns_flush_running"))
        let routerID = router.id
        let generation = controllerSession.generation
        let client = SurgeHttpAPIClient(profile: router, apiKey: controllerSecrets[router.id])

        runtimeOperationTask?.cancel()
        runningRuntimeOperationID = "dns-flush"
        operationState = .working(localized("operation.dns_flush_running"), action: TrialCommandAction.dnsFlush.title(language: presentationLanguage), target: router.displayName)

        runtimeOperationTask = Task {
            do {
                try await client.flushDNSCache()
                guard isCurrentSession(routerID: routerID, generation: generation), !Task.isCancelled else {
                    return
                }

                controllerSession.runtime.recordDNSFlush()
                runningRuntimeOperationID = nil
                finishCommand(commandID, routerID: routerID, status: .success, summary: localized("operation.dns_flush_done"))
                operationState = .success(localized("operation.dns_flush_done"), action: TrialCommandAction.dnsFlush.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: routerID, generation: generation), !Task.isCancelled else {
                    return
                }

                runningRuntimeOperationID = nil
                let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                finishCommand(commandID, routerID: routerID, status: .failed, summary: message)
                operationState = .error(message, action: TrialCommandAction.dnsFlush.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry"))
            }
        }
    }

    private func flushMihomoFakeIPCache() {
        runMihomoMaintenanceOperation(
            operationID: "cache-flush",
            action: .fakeIPFlush,
            unifiedAction: .flushFakeIP,
            workingKey: "operation.fakeip_flush_running",
            successKey: "operation.fakeip_flush_done"
        ) { client in
            try await client.flushFakeIPCache()
        }
    }

    private func reloadMihomoConfiguration() {
        runMihomoMaintenanceOperation(
            operationID: "configuration-reload",
            action: .configurationReload,
            unifiedAction: .reloadConfiguration,
            workingKey: "operation.configuration_reload_running",
            successKey: "operation.configuration_reload_done"
        ) { client in
            try await client.reloadConfigs()
        }
    }

    private func updateMihomoGeoData() {
        runMihomoMaintenanceOperation(
            operationID: "geo-resources",
            action: .geoDataUpdate,
            unifiedAction: .updateGeoData,
            workingKey: "operation.geo_data_update_running",
            successKey: "operation.geo_data_update_done"
        ) { client in
            try await client.updateGeoData()
        }
    }

    private func restartMihomoCore() {
        runMihomoCoreLifecycle(
            operationID: "core-restart",
            action: .coreRestart,
            workingKey: "operation.core_restart_running",
            successKey: "operation.core_restart_done"
        ) { client in
            try await client.restartCore()
        }
    }

    private func upgradeMihomoCore() {
        runMihomoCoreLifecycle(
            operationID: "core-upgrade",
            action: .coreUpgrade,
            workingKey: "operation.core_upgrade_running",
            successKey: "operation.core_upgrade_done"
        ) { client in
            try await client.upgradeCore()
        }
    }

    private func runMihomoMaintenanceOperation(
        operationID: String,
        action: TrialCommandAction,
        unifiedAction: UnifiedControllerAction,
        workingKey: String.LocalizationValue,
        successKey: String.LocalizationValue,
        perform: @escaping (MihomoClient) async throws -> Void
    ) {
        guard let router = selectedMihomoRuntimeRouter(action: action.title(language: presentationLanguage)) else {
            return
        }

        guard controllerSupportsLiveAction(
            unifiedAction,
            router: router,
            action: action.title(language: presentationLanguage)
        ) else {
            return
        }

        if unifiedAction == .reloadConfiguration || unifiedAction == .updateGeoData,
           !canRefreshSelectedRouter {
            operationState = .partial(localized("operation.dashboard_updates_paused"))
            return
        }

        let commandID = beginCommand(action, router: router, summary: localized(workingKey))
        let routerID = router.id
        let generation = controllerSession.generation
        let client = MihomoClient(profile: router, secret: controllerSecrets[router.id])

        runtimeOperationTask?.cancel()
        runningRuntimeOperationID = operationID
        operationState = .working(localized(workingKey), action: action.title(language: presentationLanguage), target: router.displayName)

        runtimeOperationTask = Task {
            do {
                try await perform(client)
                guard isCurrentSession(routerID: routerID, generation: generation), !Task.isCancelled else {
                    return
                }

                switch operationID {
                case "configuration-reload":
                    controllerSession.runtime.recordConfigurationReload()
                    requestImmediateSessionRefresh()
                case "geo-resources":
                    controllerSession.runtime.recordGeoDataUpdate()
                case "dns-flush":
                    controllerSession.runtime.recordDNSFlush()
                case "cache-flush":
                    controllerSession.runtime.recordFakeIPFlush()
                default:
                    break
                }
                runningRuntimeOperationID = nil
                finishCommand(commandID, routerID: routerID, status: .success, summary: localized(successKey))
                operationState = .success(localized(successKey), action: action.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: routerID, generation: generation), !Task.isCancelled else {
                    return
                }

                runningRuntimeOperationID = nil
                let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                finishCommand(commandID, routerID: routerID, status: .failed, summary: message)
                operationState = .error(message, action: action.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry"))
            }
        }
    }

    private func runMihomoCoreLifecycle(
        operationID: String,
        action: TrialCommandAction,
        workingKey: String.LocalizationValue,
        successKey: String.LocalizationValue,
        perform: @escaping (MihomoClient) async throws -> Void
    ) {
        guard let router = selectedMihomoRuntimeRouter(action: action.title(language: presentationLanguage)) else {
            return
        }

        switch effectiveUnifiedControllerType(for: router) {
        case .mihomoCompatible, .openClashMihomoCompatible, .nikkiMihomoCompatible:
            break
        case .surgeHTTPAPI, .singBoxCompatible, .cmfaCompatible, .stashCompatible,
             .stashCmfaCompatible, .smartProbe, .unknown, .unsupported:
            operationState = .partial(
                localized("operation.capability_operation_unavailable"),
                action: action.title(language: presentationLanguage),
                target: router.displayName,
                nextStep: localized("action.refresh")
            )
            return
        }

        let commandID = beginCommand(action, router: router, summary: localized(workingKey))
        let routerID = router.id
        let generation = controllerSession.generation
        let client = MihomoClient(profile: router, secret: controllerSecrets[router.id])

        runtimeOperationTask?.cancel()
        runningRuntimeOperationID = operationID
        operationState = .working(localized(workingKey), action: action.title(language: presentationLanguage), target: router.displayName)

        runtimeOperationTask = Task {
            do {
                try await perform(client)
                guard isCurrentSession(routerID: routerID, generation: generation), !Task.isCancelled else {
                    return
                }

                if operationID == "core-restart" {
                    controllerSession.runtime.recordCoreRestart()
                } else if operationID == "core-upgrade" {
                    controllerSession.runtime.recordCoreUpgrade()
                }
                runningRuntimeOperationID = nil
                finishCommand(commandID, routerID: routerID, status: .success, summary: localized(successKey))
                operationState = .success(localized(successKey), action: action.title(language: presentationLanguage), target: router.displayName)
            } catch {
                guard isCurrentSession(routerID: routerID, generation: generation), !Task.isCancelled else {
                    return
                }

                runningRuntimeOperationID = nil
                let message = Self.routerTrialFailureMessage(for: error, language: presentationLanguage)
                finishCommand(commandID, routerID: routerID, status: .failed, summary: message)
                operationState = .error(message, action: action.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.retry"))
            }
        }
    }

    private func selectedMihomoRuntimeRouter(action: String) -> RouterProfile? {
        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_refresh"), action: action, nextStep: localized("action.edit_router"))
            return nil
        }

        guard controllerSession.state.allowsLiveCommands else {
            operationState = .partial(
                localized("command.disabled_unavailable"),
                action: action,
                target: router.displayName,
                nextStep: localized("action.refresh")
            )
            return nil
        }

        switch effectiveUnifiedControllerType(for: router) {
        case .mihomoCompatible, .openClashMihomoCompatible, .nikkiMihomoCompatible, .cmfaCompatible, .stashCompatible:
            return router
        default:
            operationState = .partial(
                localized("operation.capability_operation_unavailable"),
                action: action,
                target: router.displayName,
                nextStep: localized("action.edit_router")
            )
            return nil
        }
    }

    private func selectedSurgeRuntimeRouter(action: String) -> RouterProfile? {
        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_refresh"), action: action, nextStep: localized("action.edit_router"))
            return nil
        }

        guard controllerSession.state.allowsLiveCommands else {
            operationState = .partial(
                localized("command.disabled_unavailable"),
                action: action,
                target: router.displayName,
                nextStep: localized("action.refresh")
            )
            return nil
        }

        guard effectiveUnifiedControllerType(for: router) == .surgeHTTPAPI else {
            operationState = .partial(
                localized("operation.capability_operation_unavailable"),
                action: action,
                target: router.displayName,
                nextStep: localized("action.edit_router")
            )
            return nil
        }

        return router
    }

    private func formatMemoryBytes(_ bytes: Int?) -> String {
        guard let bytes else {
            return localized("diagnostics.none")
        }

        let formatter = ByteCountFormatter()
        formatter.allowsNonnumericFormatting = false
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(max(bytes, 0)))
    }
}
