import MicaCore

extension AppModel {
    func updateControllerConfig(_ mutation: ControllerConfigMutation) {
        configTask?.cancel()

        guard let router = selectedRouter else {
            operationState = .error(localized("operation.select_router_config"))
            return
        }

        guard !dashboardSessionControls.dashboardUpdatesPaused else {
            operationState = .partial(
                localized("operation.dashboard_updates_paused"),
                action: TrialCommandAction.setConfig.title(language: presentationLanguage),
                target: router.displayName,
                nextStep: localized("action.resume")
            )
            return
        }

        guard controllerSupports(
            mutation.action,
            router: router,
            action: mutation.action.micaLabel(language: presentationLanguage)
        ) else {
            return
        }

        let commandID = beginCommand(
            .setConfig,
            router: router,
            summary: localized("operation.updating_config_field")
        )
        let previousConfig = dashboard.config
        mutation.apply(to: &dashboard.config)
        updatingConfigFieldID = mutation.id
        operationState = .working(
            localized("operation.updating_config_field"),
            action: mutation.action.micaLabel(language: presentationLanguage),
            target: router.displayName
        )

        let generation = controllerSession.generation
        let secret = controllerSecrets[router.id]
        configTask = Task {
            let client = MihomoClient(profile: router, secret: secret)

            do {
                try await client.updateConfigs(mutation.patch)
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                do {
                    let config = try await client.configs()
                    guard isCurrentSession(routerID: router.id, generation: generation),
                          !Task.isCancelled else {
                        return
                    }
                    controllerSession.endpointCache.config = config
                    dashboard.replaceConfig(with: config)
                    updatingConfigFieldID = nil
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .success,
                        summary: localized("operation.config_field_updated")
                    )
                    operationState = .success(
                        localized("operation.config_field_updated"),
                        action: mutation.action.micaLabel(language: presentationLanguage),
                        target: router.displayName
                    )
                } catch {
                    guard isCurrentSession(routerID: router.id, generation: generation),
                          !Task.isCancelled else {
                        return
                    }
                    updatingConfigFieldID = nil
                    finishCommand(
                        commandID,
                        routerID: router.id,
                        status: .partial,
                        summary: localized("operation.config_field_updated_refresh_pending")
                    )
                    operationState = .partial(
                        localized("operation.config_field_updated_refresh_pending"),
                        action: mutation.action.micaLabel(language: presentationLanguage),
                        target: router.displayName,
                        nextStep: localized("action.refresh")
                    )
                }
            } catch {
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                dashboard.config = previousConfig
                updatingConfigFieldID = nil
                finishCommand(
                    commandID,
                    routerID: router.id,
                    status: .failed,
                    summary: localized("operation.config_field_update_failed")
                )
                operationState = .error(
                    Self.routerTrialFailureMessage(for: error, language: presentationLanguage),
                    action: mutation.action.micaLabel(language: presentationLanguage),
                    target: router.displayName,
                    nextStep: localized("action.retry")
                )
            }
        }
    }
}
