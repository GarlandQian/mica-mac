import Foundation
import Testing
@testable import Mica
@testable import MicaCore

private enum ProfileLifecycleFailure: Error {
    case read
}

private actor LifecycleProfileStore: RouterProfileStore {
    private var profiles: [RouterProfile]
    private var remainingLoadFailures: Int
    private var suspendsSave: Bool
    private var saveRelease: CheckedContinuation<Void, Never>?
    private var saveWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var loadCount = 0

    init(
        profiles: [RouterProfile],
        loadFailures: Int = 0,
        suspendsSave: Bool = false
    ) {
        self.profiles = profiles
        remainingLoadFailures = loadFailures
        self.suspendsSave = suspendsSave
    }

    func loadProfiles() async throws -> [RouterProfile] {
        loadCount += 1
        if remainingLoadFailures > 0 {
            remainingLoadFailures -= 1
            throw ProfileLifecycleFailure.read
        }
        return profiles
    }

    func saveProfiles(_ profiles: [RouterProfile]) async throws {
        if suspendsSave {
            suspendsSave = false
            await withCheckedContinuation { continuation in
                saveRelease = continuation
                let waiters = saveWaiters
                saveWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
        self.profiles = profiles
    }

    func waitForSuspendedSave() async {
        guard saveRelease == nil else { return }
        await withCheckedContinuation { saveWaiters.append($0) }
    }

    func releaseSave() {
        let continuation = saveRelease
        saveRelease = nil
        continuation?.resume()
    }
}

private actor LifecycleSecretStore: SecretStore {
    private var values: [UUID: String]
    private var failingIDs: Set<UUID>
    private var suspendedID: UUID?
    private var readRelease: CheckedContinuation<Void, Never>?
    private var readWaiters: [CheckedContinuation<Void, Never>] = []

    init(values: [UUID: String] = [:], failingIDs: Set<UUID> = [], suspendedID: UUID? = nil) {
        self.values = values
        self.failingIDs = failingIDs
        self.suspendedID = suspendedID
    }

    func secret(for profileID: UUID) async throws -> String? {
        if suspendedID == profileID {
            suspendedID = nil
            await withCheckedContinuation { continuation in
                readRelease = continuation
                let waiters = readWaiters
                readWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
        if failingIDs.contains(profileID) { throw ProfileLifecycleFailure.read }
        return values[profileID]
    }

    func save(_ secret: String, for profileID: UUID) async throws {
        values[profileID] = secret
    }

    func removeSecret(for profileID: UUID) async throws {
        values.removeValue(forKey: profileID)
    }

    func allowReads(for profileID: UUID) {
        failingIDs.remove(profileID)
    }

    func waitForSuspendedRead() async {
        guard readRelease == nil else { return }
        await withCheckedContinuation { readWaiters.append($0) }
    }

    func releaseRead() {
        let continuation = readRelease
        readRelease = nil
        continuation?.resume()
    }
}

@MainActor
private struct ProfileLifecycleFixture {
    let model: AppModel
    private let defaultsName: String

    init(
        profiles: [RouterProfile] = [],
        selectedID: UUID? = nil,
        profileStore: any RouterProfileStore,
        secretStore: any SecretStore = InMemorySecretStore()
    ) {
        let defaultsName = "MicaTests.ProfileLifecycle.\(UUID().uuidString)"
        self.defaultsName = defaultsName
        model = AppModel(
            routers: profiles,
            selectedRouterID: selectedID,
            profileStore: profileStore,
            secretStore: secretStore,
            userDefaults: UserDefaults(suiteName: defaultsName)!,
            liveSessionBaselineLoadOperation: { _, _, _ in
                // Unsupported profiles have no stream producers. Hold their
                // injected baseline until teardown so no periodic HTTP can run.
                try await Task.sleep(for: .seconds(60))
                throw CancellationError()
            }
        )
    }

    func finish() {
        model.leaveLiveSession()
        model.userDefaults.removePersistentDomain(forName: defaultsName)
    }
}

@MainActor
struct AppModelProfileLifecycleTests {
    private func profile(_ name: String, withSecret: Bool = false) -> RouterProfile {
        let id = UUID()
        return RouterProfile(
            id: id,
            displayName: name,
            host: "192.0.2.1",
            secretReference: withSecret ? AppModel.secretReference(for: id) : nil,
            controllerKind: .unsupported
        )
    }

    @Test func savingProfileSelectedDuringPersistenceReplacesItsSession() async throws {
        let first = profile("A")
        let edited = profile("B")
        let store = LifecycleProfileStore(profiles: [first, edited], suspendsSave: true)
        let fixture = ProfileLifecycleFixture(
            profiles: [first, edited], selectedID: first.id, profileStore: store
        )
        defer { fixture.finish() }
        let model = fixture.model
        var draft = RouterDraft(profile: edited, secret: "new-secret")
        draft.host = "192.0.2.2"
        let save = Task { try await model.upsertRouter(from: draft) }

        await store.waitForSuspendedSave()
        model.selectRouter(edited)
        let previousGeneration = model.controllerSession.generation
        await store.releaseSave()
        _ = try await save.value

        #expect(model.selectedRouterID == edited.id)
        #expect(model.selectedRouter?.host == "192.0.2.2")
        #expect(model.selectedRouterSecret == "new-secret")
        #expect(model.controllerSession.controllerID == edited.id)
        #expect(model.controllerSession.generation != previousGeneration)
    }

    @Test func savingProfileAfterSwitchAwayPreservesNewSelection() async throws {
        let edited = profile("A")
        let next = profile("B")
        let store = LifecycleProfileStore(profiles: [edited, next], suspendsSave: true)
        let fixture = ProfileLifecycleFixture(
            profiles: [edited, next], selectedID: edited.id, profileStore: store
        )
        defer { fixture.finish() }
        let model = fixture.model
        let draft = RouterDraft(profile: edited, secret: "")
        let save = Task { try await model.upsertRouter(from: draft) }

        await store.waitForSuspendedSave()
        model.selectRouter(next)
        let generation = model.controllerSession.generation
        await store.releaseSave()
        _ = try await save.value

        #expect(model.selectedRouterID == next.id)
        #expect(model.controllerSession.generation == generation)
    }

    @Test func deletingProfileSelectedDuringPersistenceEndsDeletedSession() async throws {
        let first = profile("A")
        let deleted = profile("B")
        let next = profile("C")
        let profiles = [first, deleted, next]
        let store = LifecycleProfileStore(profiles: profiles, suspendsSave: true)
        let fixture = ProfileLifecycleFixture(
            profiles: profiles, selectedID: first.id, profileStore: store
        )
        defer { fixture.finish() }
        let model = fixture.model
        let deletion = Task { try await model.deleteRouterTransaction(deleted) }

        await store.waitForSuspendedSave()
        model.selectRouter(deleted)
        let deletedGeneration = model.controllerSession.generation
        await store.releaseSave()
        try await deletion.value

        #expect(!model.routers.contains { $0.id == deleted.id })
        #expect(model.selectedRouterID == next.id)
        #expect(model.controllerSession.controllerID == next.id)
        #expect(model.controllerSession.generation != deletedGeneration)
    }

    @Test func deletingPreviouslySelectedProfilePreservesLaterSelection() async throws {
        let deleted = profile("A")
        let replacement = profile("B")
        let selected = profile("C")
        let profiles = [deleted, replacement, selected]
        let store = LifecycleProfileStore(profiles: profiles, suspendsSave: true)
        let fixture = ProfileLifecycleFixture(
            profiles: profiles, selectedID: deleted.id, profileStore: store
        )
        defer { fixture.finish() }
        let model = fixture.model
        let deletion = Task { try await model.deleteRouterTransaction(deleted) }

        await store.waitForSuspendedSave()
        model.selectRouter(selected)
        let generation = model.controllerSession.generation
        await store.releaseSave()
        try await deletion.value

        #expect(model.selectedRouterID == selected.id)
        #expect(model.controllerSession.generation == generation)
    }

    @Test func refreshRetriesFailedInitialProfileRead() async {
        let stored = profile("Stored")
        let store = LifecycleProfileStore(profiles: [stored], loadFailures: 1)
        let fixture = ProfileLifecycleFixture(profileStore: store)
        defer { fixture.finish() }
        let model = fixture.model
        model.mainWindowDidAppear()
        model.loadPersistedState()
        await model.loadTask?.value

        #expect(!model.didFinishLoadingPersistedState)
        #expect(model.canRefreshSelectedRouter)
        model.refreshSelectedRouter()
        await model.loadTask?.value

        #expect(await store.loadCount == 2)
        #expect(model.didFinishLoadingPersistedState)
        #expect(model.selectedRouterID == stored.id)
        #expect(model.controllerSession.controllerID == stored.id)
    }

    @Test func unrelatedSecretReadFailureDoesNotBlockSelectedSession() async {
        let selected = profile("A", withSecret: true)
        let other = profile("B", withSecret: true)
        let store = LifecycleProfileStore(profiles: [selected, other])
        let secrets = LifecycleSecretStore(
            values: [selected.id: "selected-secret", other.id: "other-secret"],
            failingIDs: [other.id]
        )
        let fixture = ProfileLifecycleFixture(profileStore: store, secretStore: secrets)
        defer { fixture.finish() }
        let model = fixture.model
        model.mainWindowDidAppear()
        model.loadPersistedState()
        await model.loadTask?.value

        #expect(model.didFinishLoadingPersistedState)
        #expect(model.selectedRouterSecret == "selected-secret")
        #expect(model.controllerSession.controllerID == selected.id)
        let generation = model.controllerSession.generation
        await secrets.allowReads(for: other.id)
        model.refreshSelectedRouter()
        await model.loadTask?.value

        #expect(await store.loadCount == 1)
        #expect(model.controllerSecrets[other.id] == "other-secret")
        #expect(model.controllerSession.generation == generation)
    }

    @Test func selectedSecretFailureBlocksCredentiallessSessionUntilRefreshRetry() async {
        let selected = profile("A", withSecret: true)
        let secrets = LifecycleSecretStore(
            values: [selected.id: "recovered-secret"], failingIDs: [selected.id]
        )
        let fixture = ProfileLifecycleFixture(
            profileStore: LifecycleProfileStore(profiles: [selected]), secretStore: secrets
        )
        defer { fixture.finish() }
        let model = fixture.model
        model.mainWindowDidAppear()
        model.loadPersistedState()
        await model.loadTask?.value

        #expect(model.controllerSession.controllerID == nil)
        #expect(model.canRefreshSelectedRouter)
        model.mainWindowDidDisappear()
        model.mainWindowDidAppear()
        #expect(model.controllerSession.controllerID == nil)
        await secrets.allowReads(for: selected.id)
        model.refreshSelectedRouter()
        await model.loadTask?.value

        #expect(model.selectedRouterSecret == "recovered-secret")
        #expect(model.controllerSession.controllerID == selected.id)
    }

    @Test func profilesAndReadinessWaitForInitialSecretAttempts() async {
        let selected = profile("A", withSecret: true)
        let secrets = LifecycleSecretStore(
            values: [selected.id: "loaded-secret"], suspendedID: selected.id
        )
        let fixture = ProfileLifecycleFixture(
            profileStore: LifecycleProfileStore(profiles: [selected]), secretStore: secrets
        )
        defer { fixture.finish() }
        let model = fixture.model
        model.mainWindowDidAppear()
        model.loadPersistedState()
        await secrets.waitForSuspendedRead()

        #expect(model.routers.isEmpty)
        #expect(!model.didFinishLoadingPersistedState)
        #expect(model.controllerSession.controllerID == nil)
        #expect(!model.canRefreshSelectedRouter)
        model.loadPersistedState()
        await secrets.releaseRead()
        await model.loadTask?.value

        #expect(model.didFinishLoadingPersistedState)
        #expect(model.selectedRouterSecret == "loaded-secret")
        #expect(model.controllerSession.controllerID == selected.id)
    }

    @Test func repeatedWindowSleepWakeNotificationsOnlyReplaceSessionOnce() async {
        let selected = profile("A")
        let fixture = ProfileLifecycleFixture(
            profileStore: LifecycleProfileStore(profiles: [selected])
        )
        defer { fixture.finish() }
        let model = fixture.model
        model.mainWindowDidAppear()
        model.mainWindowDidAppear()
        model.loadPersistedState()
        await model.loadTask?.value
        let initialGeneration = model.controllerSession.generation

        model.systemWillSleep()
        let sleepingGeneration = model.controllerSession.generation
        model.systemWillSleep()
        #expect(model.controllerSession.generation == sleepingGeneration)
        #expect(model.controllerSession.controllerID == nil)
        model.systemDidWake()
        let resumedGeneration = model.controllerSession.generation
        model.systemDidWake()

        #expect(resumedGeneration != initialGeneration)
        #expect(model.controllerSession.generation == resumedGeneration)
        #expect(model.controllerSession.controllerID == selected.id)
        #expect(!model.sessionSuspendedForSleep)
    }

    @Test func retryAfterSelectingDifferentControllerUsesItsRecoveredSecret() async {
        let first = profile("A")
        let failed = profile("B", withSecret: true)
        let secrets = LifecycleSecretStore(
            values: [failed.id: "recovered-secret"], failingIDs: [failed.id]
        )
        let fixture = ProfileLifecycleFixture(
            profileStore: LifecycleProfileStore(profiles: [first, failed]), secretStore: secrets
        )
        defer { fixture.finish() }
        let model = fixture.model
        model.mainWindowDidAppear()
        model.loadPersistedState()
        await model.loadTask?.value

        model.selectRouter(failed)
        #expect(model.selectedRouterID == failed.id)
        #expect(model.controllerSession.controllerID == nil)
        await secrets.allowReads(for: failed.id)
        model.refreshSelectedRouter()
        await model.loadTask?.value

        #expect(model.selectedRouterID == failed.id)
        #expect(model.selectedRouterSecret == "recovered-secret")
        #expect(model.controllerSession.controllerID == failed.id)
    }

    @Test func closingWindowsBeforeLoadCompletesDoesNotStartSession() async {
        let selected = profile("A", withSecret: true)
        let secrets = LifecycleSecretStore(
            values: [selected.id: "loaded-secret"], suspendedID: selected.id
        )
        let fixture = ProfileLifecycleFixture(
            profileStore: LifecycleProfileStore(profiles: [selected]), secretStore: secrets
        )
        defer { fixture.finish() }
        let model = fixture.model
        model.mainWindowDidAppear()
        model.loadPersistedState()
        await secrets.waitForSuspendedRead()
        model.mainWindowDidDisappear()
        await secrets.releaseRead()
        await model.loadTask?.value

        #expect(model.didFinishLoadingPersistedState)
        #expect(model.controllerSession.controllerID == nil)
        model.mainWindowDidAppear()
        #expect(model.controllerSession.controllerID == selected.id)
    }
}
