import MicaCore

extension AppModel {
    func updateControllerConfig(
        _ mutation: ControllerConfigMutation,
        scope: LiveCommandScope
    ) {
        guard matchesCurrentCommandScope(scope),
              let router = selectedRouter,
              updatingConfigFieldID == nil,
              configTask == nil,
              canBeginLiveAction(
            mutation.action,
            router: router,
            familyInFlight: false,
            requiresUnpausedPresentation: true
        ) else { return }

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
            do {
                try await updateMihomoConfig(
                    profile: router,
                    credential: secret,
                    patch: mutation.patch
                )
                guard isCurrentSession(routerID: router.id, generation: generation),
                      !Task.isCancelled else {
                    return
                }

                do {
                    let config = try await loadMihomoConfig(
                        profile: router,
                        credential: secret
                    )
                    guard isCurrentSession(routerID: router.id, generation: generation),
                          !Task.isCancelled else {
                        return
                    }
                    controllerSession.endpointCache.config = config
                    let previousMode = dashboard.mode
                    dashboard.replaceConfig(with: config)
                    var publicationDomains: DashboardPublicationDomains = [.metadata]
                    if dashboard.mode != previousMode {
                        publicationDomains.insert(.policyGroups)
                    }
                    publishDashboardDomains(publicationDomains)
                    updatingConfigFieldID = nil
                    configTask = nil
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
                    configTask = nil
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
                configTask = nil
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
