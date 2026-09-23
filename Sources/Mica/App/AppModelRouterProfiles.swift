import Foundation
import MicaCore

actor RouterProfileMutationCoordinator {
    private var tail: Task<Void, Never>?

    func run<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        let predecessor = tail
        let task = Task<Value, Error> {
            if let predecessor {
                await predecessor.value
            }
            try Task.checkCancellation()
            return try await operation()
        }

        tail = Task {
            _ = try? await task.value
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

extension AppModel {
    @discardableResult
    func upsertRouter(from draft: RouterDraft) async throws -> RouterProfile {
        try await routerProfileMutationCoordinator.run { [self] in
            try await upsertRouterTransaction(from: draft)
        }
    }

    private func upsertRouterTransaction(from draft: RouterDraft) async throws -> RouterProfile {
        let draftProfile = draft.profile
        let commandID = beginCommand(.saveRouter, router: draftProfile, summary: localized("operation.saving_profile"))
        let isExistingRouter = routers.contains { $0.id == draftProfile.id }
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
            failedSecretRouterIDs.remove(profile.id)

            // Selection can change in another window while persistence awaits.
            // Reconcile the committed profile with the selection at commit time.
            if selectedRouterID == profile.id {
                replaceSelectedRouterSession(with: profile)
            } else if !isExistingRouter && selectedRouter == nil {
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
        try await routerProfileMutationCoordinator.run { [self] in
            try await performDeleteRouterTransaction(router)
        }
    }

    private func performDeleteRouterTransaction(_ router: RouterProfile) async throws {
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
            failedSecretRouterIDs.remove(router.id)
            trialSessions.removeValue(forKey: router.id)

            if selectedRouterID == router.id {
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
        try await routerProfileMutationCoordinator.run { [self] in
            try await performMoveRouter(routerID, to: targetIndex)
        }
    }

    private func performMoveRouter(_ routerID: RouterProfile.ID, to targetIndex: Int) async throws {
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

    var canRetryPersistedStateLoading: Bool {
        !isLoadingPersistedState
            && (persistedStateLoadFailed || !failedSecretRouterIDs.isEmpty)
    }

    func loadPersistedState() {
        guard !isLoadingPersistedState,
              !didLoadPersistedState || !failedSecretRouterIDs.isEmpty else { return }

        isLoadingPersistedState = true
        persistedStateLoadFailed = false
        loadTask = Task { [self] in
            defer { loadTask = nil }
            do {
                try await routerProfileMutationCoordinator.run { [self] in
                    if didLoadPersistedState {
                        await retryFailedSecretReads()
                    } else {
                        await loadPersistedStateTransaction()
                    }
                }
            } catch {
                persistedStateLoadFailed = !didLoadPersistedState
                presentPersistedStateLoadFailure()
            }
            isLoadingPersistedState = false
            // Use the latest selection: a different window may have selected
            // another profile while a retry was waiting for the secret store.
            if didLoadPersistedState,
               controllerSession.controllerID == nil,
               mainWindowCount > 0,
               !sessionSuspendedForSleep,
               let router = selectedRouter {
                enterLiveSession(for: router)
            }
        }
    }

    private func loadPersistedStateTransaction() async {
        do {
            let loadedProfiles = try await profileStore.loadProfiles()
            let secrets = await loadCachedSecrets(for: loadedProfiles)

            routers = loadedProfiles
            controllerSecrets = secrets.values
            failedSecretRouterIDs = secrets.failedIDs
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
            didLoadPersistedState = true
            didFinishLoadingPersistedState = true
            operationState = nil
            if !failedSecretRouterIDs.isEmpty {
                presentPersistedStateLoadFailure()
            }
        } catch {
            persistedStateLoadFailed = true
            presentPersistedStateLoadFailure()
        }
    }

    private func loadCachedSecrets(
        for profiles: [RouterProfile]
    ) async -> (values: [RouterProfile.ID: String], failedIDs: Set<RouterProfile.ID>) {
        var values: [RouterProfile.ID: String] = [:]
        var failedIDs: Set<RouterProfile.ID> = []
        for profile in profiles where profile.secretReference != nil {
            do {
                values[profile.id] = try await secretStore.secret(for: profile.id)
            } catch {
                failedIDs.insert(profile.id)
            }
        }
        return (values, failedIDs)
    }

    private func retryFailedSecretReads() async {
        let profiles = routers.filter { failedSecretRouterIDs.contains($0.id) }
        let secrets = await loadCachedSecrets(for: profiles)
        for profile in profiles where !secrets.failedIDs.contains(profile.id) {
            controllerSecrets[profile.id] = secrets.values[profile.id]
            failedSecretRouterIDs.remove(profile.id)
        }
        operationState = nil
        if !failedSecretRouterIDs.isEmpty {
            presentPersistedStateLoadFailure()
        }
    }

    func presentPersistedStateLoadFailure() {
        let message = localized("operation.profiles_load_failed")
        let selectedSecretFailed = selectedRouterID.map(failedSecretRouterIDs.contains) ?? false
        if persistedStateLoadFailed || selectedSecretFailed {
            operationState = .error(message, nextStep: localized("action.refresh"))
        } else {
            operationState = .partial(message, nextStep: localized("action.refresh"))
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
        try? await routerProfileMutationCoordinator.run { [self] in
            try Task.checkCancellation()
            await performRecordSuccessfulConnection(for: routerID, generation: generation)
        }
    }

    private func performRecordSuccessfulConnection(
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
