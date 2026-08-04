import Foundation
import MicaCore

extension AppModel {
    @discardableResult
    func upsertRouter(from draft: RouterDraft) async throws -> RouterProfile {
        let draftProfile = draft.profile
        let commandID = beginCommand(.saveRouter, router: draftProfile, summary: localized("operation.saving_profile"))
        let isExistingRouter = routers.contains { $0.id == draftProfile.id }
        let affectsSelectedSession = selectedRouterID == draftProfile.id
        let shouldActivateAfterInsert = !isExistingRouter && selectedRouter == nil
        let originalRouters = routers
        let originalCachedSecret = controllerSecrets[draftProfile.id]
        operationState = .working(localized("operation.saving_profile"), action: TrialCommandAction.saveRouter.title(language: presentationLanguage), target: draftProfile.displayName)

        do {
            var profile = draftProfile
            let existingProfile = originalRouters.first { $0.id == profile.id }
            let existingSecret: String?
            if let originalCachedSecret {
                existingSecret = originalCachedSecret
            } else if existingProfile?.secretReference != nil {
                existingSecret = try await secretStore.secret(for: profile.id)
            } else {
                existingSecret = nil
            }

            if draft.shouldSaveSecret {
                try await secretStore.save(draft.secret, for: profile.id)
                profile.secretReference = Self.secretReference(for: profile.id)
            } else {
                profile.secretReference = existingProfile?.secretReference
            }

            var nextRouters = originalRouters
            if let index = nextRouters.firstIndex(where: { $0.id == profile.id }) {
                nextRouters[index] = profile
            } else {
                nextRouters.append(profile)
            }

            do {
                try await profileStore.saveProfiles(nextRouters)
            } catch {
                if draft.shouldSaveSecret {
                    if let existingSecret {
                        try? await secretStore.save(existingSecret, for: profile.id)
                    } else {
                        try? await secretStore.removeSecret(for: profile.id)
                    }
                }
                throw error
            }

            routers = nextRouters
            if draft.shouldSaveSecret {
                controllerSecrets[profile.id] = draft.secret
            } else if let existingSecret {
                controllerSecrets[profile.id] = existingSecret
            } else {
                controllerSecrets.removeValue(forKey: profile.id)
            }

            if affectsSelectedSession {
                replaceSelectedRouterSession(with: profile)
            } else if shouldActivateAfterInsert {
                selectRouter(profile)
            }

            finishCommand(commandID, routerID: profile.id, status: .success, summary: localized("operation.profile_saved"))
            operationState = .success(localized("operation.saved_profile \(profile.displayName)"), action: TrialCommandAction.saveRouter.title(language: presentationLanguage), target: profile.displayName)
            return profile
        } catch {
            finishCommand(commandID, routerID: draftProfile.id, status: .failed, summary: localized("operation.profile_save_failed"))
            operationState = .error(localized("operation.profile_save_failed"), action: TrialCommandAction.saveRouter.title(language: presentationLanguage), target: draftProfile.displayName, nextStep: localized("action.edit_router"))
            throw error
        }
    }

    func deleteRouter(_ router: RouterProfile) {
        Task {
            try? await deleteRouterTransaction(router)
        }
    }

    func deleteRouterTransaction(_ router: RouterProfile) async throws {
        guard let originalIndex = routers.firstIndex(where: { $0.id == router.id }) else { return }

        let originalRouters = routers
        let originalSecret: String?
        if let cachedSecret = controllerSecrets[router.id] {
            originalSecret = cachedSecret
        } else if router.secretReference != nil {
            originalSecret = try await secretStore.secret(for: router.id)
        } else {
            originalSecret = nil
        }
        var nextRouters = originalRouters
        nextRouters.remove(at: originalIndex)
        let deletingActiveRouter = selectedRouterID == router.id
        let replacement = nextRouters.indices.contains(originalIndex)
            ? nextRouters[originalIndex]
            : nextRouters.last

        do {
            try await secretStore.removeSecret(for: router.id)
            do {
                try await profileStore.saveProfiles(nextRouters)
            } catch {
                if let originalSecret {
                    try? await secretStore.save(originalSecret, for: router.id)
                }
                throw error
            }

            routers = nextRouters
            controllerSecrets.removeValue(forKey: router.id)
            trialSessions.removeValue(forKey: router.id)

            if deletingActiveRouter {
                if let replacement {
                    selectRouter(replacement)
                } else {
                    clearSelectedRouterAfterDeletion()
                }
            }

            operationState = .success(localized("operation.removed_router \(router.displayName)"))
        } catch {
            operationState = .error(localized("operation.profile_delete_failed"), action: TrialCommandAction.saveRouter.title(language: presentationLanguage), target: router.displayName, nextStep: localized("action.edit_router"))
            throw error
        }
    }

    func moveRouter(_ routerID: RouterProfile.ID, to targetIndex: Int) async throws {
        guard let sourceIndex = routers.firstIndex(where: { $0.id == routerID }) else { return }
        guard routers.indices.contains(targetIndex) else { return }

        var reordered = routers
        let moved = reordered.remove(at: sourceIndex)
        reordered.insert(moved, at: min(targetIndex, reordered.count))
        try await profileStore.saveProfiles(reordered)
        routers = reordered
    }

    func draft(for router: RouterProfile? = nil) -> RouterDraft {
        guard let router else {
            return RouterDraft(displayName: localized("editor.default_controller_name"))
        }

        return RouterDraft(
            profile: router,
            secret: "",
            hasStoredSecret: router.secretReference != nil
        )
    }

    func testConnection(draft: RouterDraft) async -> ConnectionTestReport {
        let profile = draft.profile
        let commandID = beginCommand(.test, router: profile, summary: localized("operation.testing_editor_profile"))
        let credential = draft.shouldSaveSecret
            ? draft.secret
            : controllerSecrets[profile.id]
        let resolvedKind: ControllerKind

        if draft.controllerKind == .autoDetect || draft.controllerKind == .stashCmfaCompatible {
            do {
                resolvedKind = try await probeControllerKind(
                    for: profile,
                    credential: credential,
                    includeSurge: draft.controllerKind == .autoDetect
                )
            } catch {
                finishCommand(commandID, routerID: profile.id, status: .failed, summary: localized("operation.editor_test_failed"))
                return ConnectionTestReport.failure(draft: draft, error: error, language: presentationLanguage)
            }
        } else {
            resolvedKind = draft.controllerKind
        }

        do {
            let result = try await runControllerConnectionTest(
                profile: profile,
                credential: credential,
                resolvedKind: resolvedKind
            )

            switch result {
            case .mihomo(let version):
                finishCommand(commandID, routerID: profile.id, status: .success, summary: localized("operation.editor_test_passed"))
                return ConnectionTestReport.success(draft: draft, version: version.version, language: presentationLanguage)
            case .surge(let snapshot):
                finishCommand(commandID, routerID: profile.id, status: .success, summary: localized("operation.surge_profile_test_passed"))
                return ConnectionTestReport.surgeSuccess(draft: draft, snapshot: snapshot, language: presentationLanguage)
            case .singBox(let version):
                finishCommand(commandID, routerID: profile.id, status: .success, summary: localized("operation.editor_test_passed"))
                return ConnectionTestReport.singBoxSuccess(draft: draft, version: version, language: presentationLanguage)
            }
        } catch {
            let summary = resolvedKind == .surgeCompatible
                ? localized("operation.surge_profile_test_failed")
                : localized("operation.editor_test_failed")
            finishCommand(commandID, routerID: profile.id, status: .failed, summary: summary)
            return ConnectionTestReport.failure(
                draft: draft,
                error: error,
                resolvedKind: resolvedKind,
                language: presentationLanguage
            )
        }
    }

    func loadPersistedState() {
        guard !didLoadPersistedState else {
            return
        }

        didLoadPersistedState = true

        loadTask = Task {
            do {
                let loadedProfiles = try await profileStore.loadProfiles()

                if loadedProfiles.isEmpty {
                    routers = []
                    selectedRouterID = nil
                    persistSelectedRouterID(nil)
                    operationState = nil
                    didFinishLoadingPersistedState = true
                    return
                }

                routers = loadedProfiles
                let restoredID = persistedSelectedRouterID()
                let restoredRouter = loadedProfiles.first { $0.id == restoredID }
                    ?? loadedProfiles.first
                selectedRouterID = restoredRouter?.id
                persistSelectedRouterID(restoredRouter?.id)
                connectionState = .disconnected
                replaceDashboard(.empty)
                unifiedSnapshot = .empty
                surgeSnapshot = .empty
                rulesSnapshotState = .idle
                providersSnapshotState = .idle
                providerUpdateFailures = [:]
                providerHealthCheckFailures = [:]
                controllerHealth = .idle(language: presentationLanguage)
                didFinishLoadingPersistedState = true
                try await loadCachedSecrets(for: loadedProfiles)
                operationState = nil
                if let restoredRouter, mainWindowCount > 0, !sessionSuspendedForSleep {
                    enterLiveSession(for: restoredRouter)
                }
            } catch {
                operationState = .error(localized("operation.profiles_load_failed"), nextStep: localized("action.edit_router"))
            }
        }
    }

    private func loadCachedSecrets(for profiles: [RouterProfile]) async throws {
        controllerSecrets = [:]

        for profile in profiles {
            guard profile.secretReference != nil else {
                continue
            }

            controllerSecrets[profile.id] = try await secretStore.secret(for: profile.id)
        }
    }

    func makeUnifiedAdapter(for router: RouterProfile) -> any ControllerAdapterProtocol {
        var resolvedProfile = router
        if controllerSession.controllerID == router.id {
            resolvedProfile.controllerKind = runtimeControllerKind(for: router)
        }
        return UnifiedControllerAdapterRegistry.makeAdapter(
            profile: resolvedProfile,
            credential: controllerSecrets[router.id]
        )
    }

    func recordSuccessfulConnection(
        for routerID: RouterProfile.ID,
        generation: UUID
    ) async {
        guard isCurrentSession(routerID: routerID, generation: generation) else {
            return
        }
        guard let index = routers.firstIndex(where: { $0.id == routerID }) else {
            return
        }

        var updatedRouters = routers
        updatedRouters[index].lastConnectedAt = Date()
        do {
            try await profileStore.saveProfiles(updatedRouters)
        } catch {
            return
        }
        guard isCurrentSession(routerID: routerID, generation: generation),
              routers.indices.contains(index),
              routers[index].id == routerID else {
            return
        }
        routers[index].lastConnectedAt = updatedRouters[index].lastConnectedAt
    }

    @discardableResult
    func beginCommand(
        _ action: TrialCommandAction,
        router: RouterProfile,
        summary: String
    ) -> UUID {
        var session = trialSessions[router.id] ?? .empty(routerName: router.displayName)
        session.routerName = router.displayName

        let entry = CommandLogEntry(
            action: action,
            status: .queued,
            timestamp: Date(),
            safeTarget: router.displayName,
            safeSummary: summary
        )

        session.record(entry)
        trialSessions[router.id] = session
        finishCommand(entry.id, routerID: router.id, status: .working, summary: summary)
        return entry.id
    }

    func finishCommand(
        _ commandID: UUID,
        routerID: RouterProfile.ID,
        status: CommandLifecycle,
        summary: String
    ) {
        guard var session = trialSessions[routerID] else {
            return
        }

        session.update(commandID, status: status, summary: summary, timestamp: Date())
        trialSessions[routerID] = session
    }
}
