import Foundation
import Observation
import Synchronization
import Testing
@testable import Mica
@testable import MicaCore

private enum InjectedStoreFailure: Error {
    case save
}

private func makeSleepingTask() -> Task<Void, Never> {
    Task {
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            return
        }
    }
}

@MainActor
private func makeSleepingSessionTask(
    slot: LiveSessionTaskSlot,
    model: AppModel
) -> Task<Void, Never>? {
    guard let identity = model.liveSessionTasks.identity else { return nil }
    return model.liveSessionTasks.start(slot, for: identity) { _ in
        try? await Task.sleep(for: .seconds(60))
    }
}

private actor TransactionProfileStore: RouterProfileStore {
    private var profiles: [RouterProfile]
    private let failsOnSave: Bool

    init(profiles: [RouterProfile], failsOnSave: Bool) {
        self.profiles = profiles
        self.failsOnSave = failsOnSave
    }

    func loadProfiles() async throws -> [RouterProfile] {
        profiles
    }

    func saveProfiles(_ profiles: [RouterProfile]) async throws {
        if failsOnSave { throw InjectedStoreFailure.save }
        self.profiles = profiles
    }

    func storedProfiles() -> [RouterProfile] {
        profiles
    }
}

private actor TransactionSecretStore: SecretStore {
    private var values: [UUID: String]

    init(values: [UUID: String]) {
        self.values = values
    }

    func secret(for profileID: UUID) async throws -> String? {
        values[profileID]
    }

    func save(_ secret: String, for profileID: UUID) async throws {
        values[profileID] = secret
    }

    func removeSecret(for profileID: UUID) async throws {
        values.removeValue(forKey: profileID)
    }
}

private actor InterleavingProfileStore: RouterProfileStore {
    private var profiles: [RouterProfile]
    private var saveCount = 0
    private var firstSaveRelease: CheckedContinuation<Void, Never>?
    private var firstSaveDidSuspend = false
    private var firstSaveWaiters: [CheckedContinuation<Void, Never>] = []
    private var secondSaveOverlappedFirst = false

    init(profiles: [RouterProfile]) {
        self.profiles = profiles
    }

    func loadProfiles() async throws -> [RouterProfile] {
        profiles
    }

    func saveProfiles(_ profiles: [RouterProfile]) async throws {
        saveCount += 1
        if saveCount == 1 {
            self.profiles = profiles
            await withCheckedContinuation { continuation in
                firstSaveRelease = continuation
                firstSaveDidSuspend = true
                let waiters = firstSaveWaiters
                firstSaveWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
            return
        }

        if firstSaveRelease != nil {
            secondSaveOverlappedFirst = true
        }
        self.profiles = profiles
    }

    func waitUntilFirstSaveSuspends() async {
        guard !firstSaveDidSuspend else { return }
        await withCheckedContinuation { continuation in
            firstSaveWaiters.append(continuation)
        }
    }

    func releaseFirstSave() {
        let continuation = firstSaveRelease
        firstSaveRelease = nil
        continuation?.resume()
    }

    func snapshot() -> (profiles: [RouterProfile], overlapped: Bool) {
        (profiles, secondSaveOverlappedFirst)
    }
}

private actor ControllerProbeScript {
    private var attempts = 0

    func resolve(
        profile: RouterProfile,
        credential: String?,
        includeSurge: Bool
    ) throws -> ControllerKind {
        _ = profile
        _ = credential
        _ = includeSurge
        attempts += 1
        if attempts == 1 {
            throw MihomoClientError.connectionFailure(.connectionRefused)
        }
        return .mihomoCompatible
    }

    func attemptCount() -> Int {
        attempts
    }
}

private actor MixedMihomoEndpointScript {
    private var requestCounts: [String: Int] = [:]

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw MihomoClientError.invalidResponse
        }
        let path = url.path
        let requestCount = (requestCounts[path] ?? 0) + 1
        requestCounts[path] = requestCount

        let statusCode: Int
        let body: Data
        switch path {
        case "/version":
            statusCode = 200
            body = Data(#"{"version":"test"}"#.utf8)
        case "/configs" where requestCount == 1:
            statusCode = 200
            body = Data(#"{"mode":"rule"}"#.utf8)
        default:
            statusCode = 503
            body = Data()
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ) else {
            throw MihomoClientError.invalidResponse
        }
        return (body, response)
    }

    func requestCount(for path: String) -> Int {
        requestCounts[path] ?? 0
    }
}

private actor MihomoRefreshResponseScript {
    private let responseBodies: [String: [Data]]
    private var requestCounts: [String: Int] = [:]

    init(responseBodies: [String: [String]]) {
        self.responseBodies = responseBodies.mapValues { bodies in
            bodies.map { Data($0.utf8) }
        }
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url,
              let bodies = responseBodies[url.path],
              !bodies.isEmpty else {
            throw MihomoClientError.invalidResponse
        }

        let requestCount = (requestCounts[url.path] ?? 0) + 1
        requestCounts[url.path] = requestCount
        let body = bodies[min(requestCount - 1, bodies.count - 1)]
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ) else {
            throw MihomoClientError.invalidResponse
        }
        return (body, response)
    }

    func requestCount(for path: String) -> Int {
        requestCounts[path] ?? 0
    }
}

private actor MixedSurgeEndpointScript {
    private var requestCounts: [String: Int] = [:]

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw SurgeHttpAPIError.invalidResponse
        }
        let path = url.path
        let requestCount = (requestCounts[path] ?? 0) + 1
        requestCounts[path] = requestCount

        let statusCode: Int
        let body: Data
        switch path {
        case "/v1/outbound":
            statusCode = 200
            body = Data(#"{"mode":"rule"}"#.utf8)
        case "/v1/policies":
            statusCode = 200
            body = Data(#"{"policies":[]}"#.utf8)
        case "/v1/policy_groups" where requestCount == 1:
            statusCode = 200
            body = Data(
                #"{"groups":[{"name":"Proxy","type":"select","selected":"A","policies":["A"]}]}"#.utf8
            )
        default:
            statusCode = 503
            body = Data()
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ) else {
            throw SurgeHttpAPIError.invalidResponse
        }
        return (body, response)
    }

    func requestCount(for path: String) -> Int {
        requestCounts[path] ?? 0
    }
}

struct LiveSessionTransactionTests {
    @Test func genericCancellationAndEndpointValidationUseTerminalCategories() {
        #expect(RouterTrialFailureCategory(error: CancellationError()) == .cancelled)
        #expect(
            RouterTrialFailureCategory(error: RouterProfileEndpointError.invalidHost)
                == .invalidURL
        )
        #expect(
            RouterTrialFailureCategory(error: RouterProfileEndpointError.invalidHost)
                .retryDisposition == .terminal
        )
    }

    @Test func laneStateCoalescesOneFollowUpAndResetsRetryAfterSuccess() {
        var state = SessionRefreshLaneState()

        let firstBegin = state.begin()
        let secondBegin = state.begin()
        #expect(firstBegin)
        #expect(!secondBegin)
        #expect(state.pendingFollowUp)

        state.finishFailure("offline", disposition: .transient)
        #expect(state.retryAttempt == 1)
        let firstFollowUp = state.consumeFollowUp()
        let secondFollowUp = state.consumeFollowUp()
        #expect(firstFollowUp)
        #expect(!secondFollowUp)

        let success = Date(timeIntervalSince1970: 42)
        state.finishSuccess(at: success)
        #expect(state.retryAttempt == 0)
        #expect(state.lastSuccessAt == success)
        #expect(state.lastFailure == nil)
    }

    @Test func mixedEndpointLaneRecordsPartialSuccessWithoutTerminalizing() {
        var state = SessionRefreshLaneState()
        let began = state.begin()
        #expect(began)

        let completedAt = Date(timeIntervalSince1970: 42)
        state.finishPartial(
            "The optional provider endpoint is unavailable.",
            at: completedAt
        )

        #expect(!state.isInFlight)
        #expect(!state.terminalFailure)
        #expect(state.retryAttempt == 0)
        #expect(state.lastSuccessAt == completedAt)
        #expect(
            state.lastFailure == "The optional provider endpoint is unavailable."
        )
    }

    @MainActor
    @Test func mixedMihomoEndpointResultsRetainLastGoodAndKeepLaneCycling() async throws {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
        model.controllerSession.state = .live
        model.activeSessionControllerKind = .mihomoCompatible
        model.controllerHealth = .checking(router: profile)

        let script = MixedMihomoEndpointScript()
        model.sessionMihomoClient = MihomoClient(
            profile: profile,
            dataLoader: { request in
                try await script.load(request)
            }
        )
        let generation = model.controllerSession.generation

        try await model.performSessionRefreshAttempt(
            .slow,
            router: profile,
            generation: generation,
            source: .manual
        )
        let retainedConfig = try #require(
            model.controllerSession.endpointCache.config
        )

        try await model.performSessionRefreshAttempt(
            .slow,
            router: profile,
            generation: generation,
            source: .periodic
        )

        let laneState = try #require(model.controllerSession.refreshLanes[.slow])
        #expect(!laneState.terminalFailure)
        #expect(!laneState.isInFlight)
        #expect(laneState.lastFailure != nil)
        #expect(model.controllerSession.endpointCache.config == retainedConfig)
        #expect(model.controllerHealth.status(for: .version).isReady)
        #expect(model.controllerHealth.status(for: .configs).isFailure)
        #expect(await script.requestCount(for: "/version") == 2)
        #expect(await script.requestCount(for: "/configs") == 2)
    }

    @MainActor
    @Test func identicalMihomoMediumResponsesAdvanceFreshnessWithoutRepublishingGroups() async throws {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let model = makeLiveMihomoModel(profile: profile)
        let script = MihomoRefreshResponseScript(responseBodies: [
            "/proxies": [Self.selectorProxyResponse(selected: "Node A")],
        ])
        model.sessionMihomoClient = MihomoClient(profile: profile) { request in
            try await script.load(request)
        }
        let generation = model.controllerSession.generation

        try await model.performSessionRefreshAttempt(
            .medium,
            router: profile,
            generation: generation,
            source: .manual
        )
        let firstRevision = model.policyGroupCatalogRevision
        let firstReceipt = try #require(model.controllerSession.latestReceivedAt)
        let firstLaneSuccess = try #require(
            model.controllerSession.refreshLanes[.medium]?.lastSuccessAt
        )
        let cachedProxies = try #require(model.controllerSession.endpointCache.proxies)

        try await Task.sleep(for: .milliseconds(2))
        try await model.performSessionRefreshAttempt(
            .medium,
            router: profile,
            generation: generation,
            source: .periodic
        )

        let latestReceipt = try #require(model.controllerSession.latestReceivedAt)
        let latestLaneSuccess = try #require(
            model.controllerSession.refreshLanes[.medium]?.lastSuccessAt
        )
        #expect(await script.requestCount(for: "/proxies") == 2)
        #expect(model.controllerSession.endpointCache.proxies == cachedProxies)
        #expect(model.policyGroupCatalogRevision == firstRevision)
        #expect(model.controllerHealth.status(for: .proxies).isReady)
        #expect(latestReceipt > firstReceipt)
        #expect(latestLaneSuccess > firstLaneSuccess)
    }

    @MainActor
    @Test func disappearingSmartGroupsClearWeightsWithOneGroupPublication() async throws {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let model = makeLiveMihomoModel(profile: profile)
        let script = MihomoRefreshResponseScript(responseBodies: [
            "/proxies": [
                Self.smartProxyResponse,
                Self.selectorProxyResponse(selected: "Node A"),
            ],
            "/group/weights": [Self.smartWeightsResponse],
        ])
        model.sessionMihomoClient = MihomoClient(profile: profile) { request in
            try await script.load(request)
        }
        let generation = model.controllerSession.generation

        try await model.performSessionRefreshAttempt(
            .medium,
            router: profile,
            generation: generation,
            source: .manual
        )
        let smartRevision = model.policyGroupCatalogRevision
        #expect(model.controllerSession.endpointCache.smartWeights != nil)
        #expect(model.policyGroupCatalog.groups.first?.optionUsageRanks.isEmpty == false)

        try await model.performSessionRefreshAttempt(
            .medium,
            router: profile,
            generation: generation,
            source: .periodic
        )

        #expect(await script.requestCount(for: "/group/weights") == 1)
        #expect(model.controllerSession.endpointCache.smartWeights == nil)
        #expect(model.policyGroupCatalog.groups.first?.optionUsageRanks.isEmpty == true)
        #expect(model.policyGroupCatalogRevision == smartRevision &+ 1)
    }

    @MainActor
    @Test func identicalMediumResponseStillCommitsAnActiveBaseline() async throws {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let proxyBody = Self.selectorProxyResponse(selected: "Node A")
        let proxies = try ProxiesResponse.decodePreservingProxyOrder(
            from: Data(proxyBody.utf8)
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.activeSessionControllerKind = .mihomoCompatible
        model.controllerHealth = .checking(router: profile)
        model.controllerSession.endpointCache.version = VersionResponse(version: "test")
        model.controllerSession.endpointCache.config = try JSONDecoder().decode(
            ConfigResponse.self,
            from: Data(#"{"mode":"rule"}"#.utf8)
        )
        model.controllerSession.endpointCache.proxies = proxies
        model.controllerSession.endpointCache.connections = ConnectionsResponse(connections: [])
        let script = MihomoRefreshResponseScript(responseBodies: [
            "/proxies": [proxyBody],
        ])
        model.sessionMihomoClient = MihomoClient(profile: profile) { request in
            try await script.load(request)
        }

        try await model.performSessionRefreshAttempt(
            .medium,
            router: profile,
            generation: model.controllerSession.generation,
            source: .manual
        )

        #expect(model.controllerSession.hasCommittedBaseline)
        #expect(!model.controllerSession.baselineTransaction.isActive)
        #expect(model.controllerSession.latestReceivedAt != nil)
        #expect(model.policyGroupCatalog.groups.first?.selected == "Node A")
        #expect(model.controllerHealth.status(for: .proxies).isReady)
    }

    @MainActor
    @Test func unchangedMediumResponseDoesNotOverwritePausedPendingDashboard() async throws {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let model = makeLiveMihomoModel(profile: profile)
        let script = MihomoRefreshResponseScript(responseBodies: [
            "/proxies": [
                Self.selectorProxyResponse(selected: "Node A"),
                Self.selectorProxyResponse(selected: "Node B"),
                Self.selectorProxyResponse(selected: "Node B"),
            ],
        ])
        model.sessionMihomoClient = MihomoClient(profile: profile) { request in
            try await script.load(request)
        }
        let generation = model.controllerSession.generation

        try await model.performSessionRefreshAttempt(
            .medium,
            router: profile,
            generation: generation,
            source: .manual
        )
        model.dashboardSessionControls.setPresentationPaused(true)
        try await model.performSessionRefreshAttempt(
            .medium,
            router: profile,
            generation: generation,
            source: .periodic
        )
        #expect(
            model.controllerSession.pendingPresentation.dashboard?.groups.first?.selected
                == "Node B"
        )

        try await model.performSessionRefreshAttempt(
            .medium,
            router: profile,
            generation: generation,
            source: .periodic
        )
        #expect(
            model.controllerSession.pendingPresentation.dashboard?.groups.first?.selected
                == "Node B"
        )

        model.dashboardSessionControls.setPresentationPaused(false)
        model.applyPendingSessionPresentation()
        #expect(model.policyGroupCatalog.groups.first?.selected == "Node B")
        #expect(model.controllerSession.pendingPresentation.isEmpty)
    }

    @MainActor
    @Test func slowRuleAndProviderChangesPublishIndependently() async throws {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let model = makeLiveMihomoModel(profile: profile)
        let script = MihomoRefreshResponseScript(responseBodies: [
            "/version": [#"{"version":"test"}"#],
            "/configs": [#"{"mode":"rule"}"#],
            "/rules": [
                Self.rulesResponse(payload: "first.example"),
                Self.rulesResponse(payload: "second.example"),
                Self.rulesResponse(payload: "second.example"),
            ],
            "/providers/proxies": [
                Self.proxyProvidersResponse(updatedAt: "2026-09-01T00:00:00Z"),
                Self.proxyProvidersResponse(updatedAt: "2026-09-01T00:00:00Z"),
                Self.proxyProvidersResponse(updatedAt: "2026-09-02T00:00:00Z"),
            ],
            "/providers/rules": [Self.ruleProvidersResponse],
        ])
        model.sessionMihomoClient = MihomoClient(profile: profile) { request in
            try await script.load(request)
        }
        let generation = model.controllerSession.generation

        try await model.performSessionRefreshAttempt(
            .slow,
            router: profile,
            generation: generation,
            source: .manual
        )
        let providersInvalidated = Mutex(false)
        withObservationTracking {
            _ = model.providersCatalog
        } onChange: {
            providersInvalidated.withLock { $0 = true }
        }

        try await model.performSessionRefreshAttempt(
            .slow,
            router: profile,
            generation: generation,
            source: .periodic
        )
        #expect(model.rulesCatalog.rules.first?.payload == "second.example")
        #expect(!providersInvalidated.withLock { $0 })

        let rulesInvalidated = Mutex(false)
        withObservationTracking {
            _ = model.rulesCatalog
        } onChange: {
            rulesInvalidated.withLock { $0 = true }
        }
        try await model.performSessionRefreshAttempt(
            .slow,
            router: profile,
            generation: generation,
            source: .periodic
        )

        #expect(!rulesInvalidated.withLock { $0 })
        #expect(
            model.providersCatalog.providers.first?.updatedAt
                == "2026-09-02T00:00:00Z"
        )
    }

    @MainActor
    @Test func mixedSurgeEndpointResultsRetainLastGoodAndKeepLaneCycling() async throws {
        let profile = RouterProfile(
            displayName: "Surge",
            host: "127.0.0.1",
            controllerKind: .surgeCompatible
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
        model.controllerSession.state = .live
        model.activeSessionControllerKind = .surgeCompatible

        let script = MixedSurgeEndpointScript()
        model.sessionSurgeClient = SurgeHttpAPIClient(
            profile: profile,
            dataLoader: { request in
                try await script.load(request)
            }
        )
        let generation = model.controllerSession.generation

        try await model.performSessionRefreshAttempt(
            .medium,
            router: profile,
            generation: generation,
            source: .manual
        )
        let retainedGroups = model.controllerSession.surgeRawSnapshot.policyGroups

        try await model.performSessionRefreshAttempt(
            .medium,
            router: profile,
            generation: generation,
            source: .periodic
        )

        let laneState = try #require(model.controllerSession.refreshLanes[.medium])
        #expect(!laneState.terminalFailure)
        #expect(!laneState.isInFlight)
        #expect(laneState.lastFailure != nil)
        #expect(model.controllerSession.surgeRawSnapshot.policyGroups == retainedGroups)
        #expect(model.controllerHealth.status(for: .configs).isReady)
        #expect(model.controllerHealth.status(for: .proxies).isFailure)
        #expect(await script.requestCount(for: "/v1/outbound") == 2)
        #expect(await script.requestCount(for: "/v1/policy_groups") == 2)
    }

    @Test func retryPolicyCapsAtThirtySecondsWithInjectableJitter() {
        #expect(SessionRetryPolicy.delay(forAttempt: 0, jitter: 0) == .seconds(2))
        #expect(SessionRetryPolicy.delay(forAttempt: 4, jitter: 0) == .seconds(30))
        #expect(SessionRetryPolicy.delay(forAttempt: 40, jitter: 0) == .seconds(30))
    }

    @Test func liveStreamRetryStateDeduplicatesConcurrentChannelFailures() {
        var state = LiveStreamRetryState()

        #expect(state.reserveDelay(jitter: 0) == .seconds(2))
        #expect(state.reserveDelay(jitter: 0) == nil)
        #expect(state.attempt == 1)
        #expect(state.isScheduled)

        state.consumeScheduledRetry()
        #expect(state.reserveDelay(jitter: 0) == .seconds(4))
        #expect(state.attempt == 2)

        state.consumeScheduledRetry()
        state.recordSuccess()
        #expect(state.reserveDelay(jitter: 0) == .seconds(2))
    }

    @MainActor
    @Test func retryOnceWaveIgnoresLaterTerminalCallbackFromCancelledProducer() {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
        model.controllerSession.state = .live
        model.activeSessionControllerKind = .mihomoCompatible
        model.liveStreamRequested = true
        let generation = model.controllerSession.generation
        model.installLiveSessionRuntime(for: profile, generation: generation)

        model.handleLiveStreamFailure(
            .traffic,
            error: InjectedStoreFailure.save,
            routerID: profile.id,
            generation: generation
        )
        #expect(model.liveRetryState.isScheduled)
        #expect(model.liveRetryState.attempt == 1)

        model.handleLiveStreamFailure(
            .logs,
            error: MihomoClientError.unauthorized,
            routerID: profile.id,
            generation: generation
        )

        #expect(model.liveRetryState.isScheduled)
        #expect(model.liveRetryState.attempt == 1)
        if case .staleReconnecting = model.controllerSession.state {
            // The second channel joined the first failure wave.
        } else {
            Issue.record("Expected the shared retry wave to remain reconnecting")
        }
        model.leaveLiveSession()
    }

    @MainActor
    @Test func manualMihomoRefreshReplacesRuntimeAndCancelsOldProducersOffline() throws {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
        model.controllerSession.state = .live
        model.activeSessionControllerKind = .mihomoCompatible
        model.unifiedSnapshot = UnifiedControllerSnapshot(
            controllerType: .mihomoCompatible,
            capabilities: .none,
            checkedAt: Date(timeIntervalSince1970: 1)
        )
        model.liveStreamRequested = true
        let generation = model.controllerSession.generation
        model.installLiveSessionRuntime(for: profile, generation: generation)
        let oldRuntime = try #require(model.liveSessionRuntime)

        let producerSlots: [LiveSessionTaskSlot] = [.traffic, .logs, .memory, .connections]
        let oldProducers = try producerSlots.map {
            try #require(makeSleepingSessionTask(slot: $0, model: model))
        }

        model.restartRequestedMihomoLiveStreamsForManualRefresh(
            router: profile,
            generation: generation
        )

        let replacementRuntime = try #require(model.liveSessionRuntime)
        let allOldProducersCancelled = oldProducers.allSatisfy { $0.isCancelled }
        #expect(allOldProducersCancelled)
        #expect(replacementRuntime !== oldRuntime)
        #expect(
            model.liveSessionRuntimeIdentity
                == LiveSessionRuntimeIdentity(
                    controllerID: profile.id,
                    generation: generation
                )
        )
        #expect(producerSlots.allSatisfy { !model.liveSessionTasks.contains($0) })

        model.handleLiveStreamFailure(
            .logs,
            error: MihomoClientError.unauthorized,
            routerID: profile.id,
            generation: generation,
            runtime: oldRuntime
        )
        #expect(model.liveSessionRuntime === replacementRuntime)
        #expect(!model.liveRetryState.isScheduled)
        model.leaveLiveSession()
    }

    @MainActor
    @Test func cancelledLiveChannelFailureDoesNotMutateTheSession() throws {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
        model.controllerSession.state = .live
        model.activeSessionControllerKind = .mihomoCompatible
        model.liveStreamRequested = true
        let generation = model.controllerSession.generation
        model.installLiveSessionRuntime(for: profile, generation: generation)
        let runtime = try #require(model.liveSessionRuntime)

        model.handleLiveStreamFailure(
            .connections,
            error: CancellationError(),
            routerID: profile.id,
            generation: generation
        )

        #expect(model.liveSessionRuntime === runtime)
        #expect(model.controllerSession.state == .live)
        #expect(!model.liveRetryState.isScheduled)
        model.leaveLiveSession()
    }

    @MainActor
    @Test func profileWritesSerializeAcrossEditorSaveAndConnectionMetadata() async throws {
        let active = RouterProfile(
            displayName: "Active",
            host: "127.0.0.1",
            controllerKind: .mihomoCompatible
        )
        let inactive = RouterProfile(
            displayName: "Inactive",
            host: "127.0.0.2",
            controllerKind: .mihomoCompatible
        )
        let store = InterleavingProfileStore(profiles: [active, inactive])
        let model = AppModel(
            routers: [active, inactive],
            selectedRouterID: active.id,
            profileStore: store,
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: active.id)
        let generation = model.controllerSession.generation

        var draft = RouterDraft(profile: inactive, secret: "")
        draft.displayName = "Edited Inactive"
        let editorSave = Task {
            try await model.upsertRouter(from: draft)
        }

        await store.waitUntilFirstSaveSuspends()
        let connectionMetadataSave = Task {
            await model.recordSuccessfulConnection(for: active.id, generation: generation)
        }

        for _ in 0 ..< 20 {
            await Task.yield()
        }
        await store.releaseFirstSave()
        _ = try await editorSave.value
        await connectionMetadataSave.value

        let stored = await store.snapshot()
        let storedActive = try #require(stored.profiles.first { $0.id == active.id })
        let storedInactive = try #require(stored.profiles.first { $0.id == inactive.id })
        let visibleActive = try #require(model.routers.first { $0.id == active.id })
        let visibleInactive = try #require(model.routers.first { $0.id == inactive.id })

        #expect(!stored.overlapped)
        #expect(storedActive.lastConnectedAt != nil)
        #expect(storedInactive.displayName == "Edited Inactive")
        #expect(visibleActive.lastConnectedAt != nil)
        #expect(visibleInactive.displayName == "Edited Inactive")
    }

    @MainActor
    @Test func autoDetectRetriesConnectionRefusedUntilTheSelectedControllerAppears() async throws {
        let profile = RouterProfile(
            displayName: "Delayed Mihomo",
            host: "192.0.2.1",
            port: 65_535,
            controllerKind: .autoDetect
        )
        let probe = ControllerProbeScript()
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore(),
            controllerProbeOperation: { profile, credential, includeSurge in
                try await probe.resolve(
                    profile: profile,
                    credential: credential,
                    includeSurge: includeSurge
                )
            },
            controllerProbeSleepOperation: { _ in
                await Task.yield()
            }
        )

        model.enterLiveSession(for: profile)
        let generation = model.controllerSession.generation
        defer { model.leaveLiveSession() }

        for _ in 0 ..< 100 where model.activeSessionControllerKind != .mihomoCompatible {
            try await Task.sleep(for: .milliseconds(10))
        }

        let attemptCount = await probe.attemptCount()
        #expect(attemptCount == 2)
        #expect(model.activeSessionControllerKind == .mihomoCompatible)
        #expect(model.controllerSession.controllerID == profile.id)
        #expect(model.controllerSession.generation == generation)
        #expect(!model.liveSessionTasks.contains(.probe))
    }

    @MainActor
    @Test func selectedControllerPersistenceRoundTripsAndClears() {
        let suiteName = "MicaTests.SelectedController.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore(),
            userDefaults: defaults
        )
        let id = UUID()

        model.persistSelectedRouterID(id)
        #expect(model.persistedSelectedRouterID() == id)

        model.persistSelectedRouterID(nil)
        #expect(model.persistedSelectedRouterID() == nil)
    }

    @MainActor
    @Test func commandCapabilitiesKeepTestingAvailableWhilePresentationIsPaused() {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .unsupported
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
        model.controllerSession.state = .live

        #expect(model.canTestSelectedRouter)
        #expect(model.canRefreshSelectedRouter)
        #expect(model.canTogglePresentationPause)

        var controls = model.dashboardSessionControls
        let pausedAt = Date(timeIntervalSince1970: 123)
        controls.setPresentationPaused(true, at: pausedAt)
        model.dashboardSessionControls = controls

        #expect(model.canTestSelectedRouter)
        #expect(!model.canRefreshSelectedRouter)
        #expect(model.canTogglePresentationPause)
        #expect(model.dashboardSessionControls.presentationPausedAt == pausedAt)

        controls.setPresentationPaused(false, at: pausedAt)
        #expect(controls.presentationPausedAt == nil)

        model.selectedRouterID = nil
        #expect(!model.canTestSelectedRouter)
        #expect(!model.canRefreshSelectedRouter)
        #expect(!model.canTogglePresentationPause)
    }

    @MainActor
    @Test func autoDetectedSurgeDrivesRuntimeRoutingWithoutChangingTheProfile() {
        let profile = RouterProfile(
            displayName: "Auto",
            host: "127.0.0.1",
            controllerKind: .autoDetect
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.activeSessionControllerKind = .surgeCompatible

        #expect(model.runtimeControllerKind(for: profile) == .surgeCompatible)
        #expect(model.effectiveUnifiedControllerType(for: profile) == .surgeHTTPAPI)
        #expect(model.effectiveUnifiedCapabilities(for: profile) == .surgeHTTPAPI)
        #expect(model.selectedControllerAdapter.detectedKind == .surgeCompatible)
        #expect(model.activeUnifiedAdapter?.controllerType == .surgeHTTPAPI)
        #expect(model.modeChangeAction(for: profile) == .setOutboundMode)
        #expect(model.routers.first?.controllerKind == .autoDetect)
    }

    @MainActor
    @Test func autoDetectedMihomoBuildsAMihomoRuntimeAdapterWithoutMutatingProfile() {
        let profile = RouterProfile(
            displayName: "Auto",
            host: "127.0.0.1",
            controllerKind: .autoDetect
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.activeSessionControllerKind = .mihomoCompatible

        #expect(model.activeUnifiedAdapter?.controllerType == .mihomoCompatible)
        #expect(model.activeUnifiedAdapter?.capabilities == .mihomoCompatible)
        #expect(model.modeChangeAction(for: profile) == .changeMode)
        #expect(model.routers.first?.controllerKind == .autoDetect)
    }

    @MainActor
    @Test func leavingSessionClearsAutoDetectedRuntimeKind() {
        let profile = RouterProfile(
            displayName: "Auto",
            host: "127.0.0.1",
            controllerKind: .autoDetect
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        let generation = model.controllerSession.generation
        model.activeSessionControllerKind = .mihomoCompatible

        model.leaveLiveSession()

        #expect(model.activeSessionControllerKind == nil)
        #expect(model.controllerSession.controllerID == nil)
        #expect(!model.isCurrentSession(routerID: profile.id, generation: generation))
    }

    @MainActor
    @Test func leavingSessionCancelsEveryControllerOperationTaskAndMarker() {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .unsupported
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)

        let refreshTask = makeSleepingTask()
        let switchTask = makeSleepingTask()
        let modeTask = makeSleepingTask()
        let configTask = makeSleepingTask()
        let delayTask = makeSleepingTask()
        let connectionTask = makeSleepingTask()
        let providerTask = makeSleepingTask()
        let rulesTask = makeSleepingTask()
        let surgeTask = makeSleepingTask()
        let runtimeOperationTask = makeSleepingTask()

        model.refreshTask = refreshTask
        model.switchTask = switchTask
        model.modeTask = modeTask
        model.configTask = configTask
        model.delayTask = delayTask
        model.connectionTask = connectionTask
        model.providerTask = providerTask
        model.rulesTask = rulesTask
        model.surgeTask = surgeTask
        model.runtimeOperationTask = runtimeOperationTask
        model.switchingGroupID = "group"
        model.clearingFixedGroupID = "group"
        model.changingMode = true
        model.updatingConfigFieldID = "allow-lan"
        model.measuringDelayGroupID = "group"
        model.measuringDelayNode = PolicyNodeLatencyTestTarget(
            groupID: "group",
            nodeName: "node"
        )
        model.closingConnectionID = "connection"
        model.closingConnectionGroupID = "owner-group"
        model.closingAllConnections = true
        model.updatingProviderName = "provider"
        model.checkingProviderName = "provider-health"
        model.providerHealthCheckFailures["provider-health"] = "failed"
        model.isRefreshingDashboard = true
        model.reloadingRules = true
        model.updatingRuleID = "rule"
        model.ruleUpdateFailures["rule"] = "failed"
        model.reloadingProviders = true
        model.changingSurgeOutbound = true
        model.testingSurgePolicyGroup = "group"
        model.switchingSurgePolicyGroup = "group"
        model.killingSurgeRequestID = "request"
        model.killingSurgeProjectedConnectionID = "connection"
        model.reloadingSurgeProfile = true
        model.changingControllerLogLevel = true
        model.runningRuntimeOperationID = "memory"

        model.leaveLiveSession()

        #expect(refreshTask.isCancelled)
        #expect(switchTask.isCancelled)
        #expect(modeTask.isCancelled)
        #expect(configTask.isCancelled)
        #expect(delayTask.isCancelled)
        #expect(connectionTask.isCancelled)
        #expect(providerTask.isCancelled)
        #expect(rulesTask.isCancelled)
        #expect(surgeTask.isCancelled)
        #expect(runtimeOperationTask.isCancelled)
        #expect(model.refreshTask == nil)
        #expect(model.switchTask == nil)
        #expect(model.modeTask == nil)
        #expect(model.configTask == nil)
        #expect(model.delayTask == nil)
        #expect(model.connectionTask == nil)
        #expect(model.providerTask == nil)
        #expect(model.rulesTask == nil)
        #expect(model.surgeTask == nil)
        #expect(model.runtimeOperationTask == nil)
        #expect(model.clearingFixedGroupID == nil)
        #expect(model.updatingConfigFieldID == nil)
        #expect(model.measuringDelayNode == nil)
        #expect(model.closingConnectionGroupID == nil)
        #expect(model.checkingProviderName == nil)
        #expect(model.providerHealthCheckFailures.isEmpty)
        #expect(!model.reloadingSurgeProfile)
        #expect(!model.changingControllerLogLevel)
        #expect(model.updatingRuleID == nil)
        #expect(model.ruleUpdateFailures.isEmpty)
        #expect(!model.isBusy)
    }

    @MainActor
    @Test func leavingSessionCancelsTheCompleteLiveTaskTree() throws {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .unsupported
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)

        let tasks = try LiveSessionTaskSlot.allCases.map {
            try #require(makeSleepingSessionTask(slot: $0, model: model))
        }

        model.leaveLiveSession()

        #expect(tasks.allSatisfy { $0.isCancelled })
        #expect(model.liveSessionTasks.activeSlots.isEmpty)
        #expect(model.liveSessionTasks.identity == nil)
    }

    @MainActor
    @Test func staleStreamStartCannotCancelCurrentSessionProducers() throws {
        let profile = RouterProfile(
            displayName: "Controller",
            host: "127.0.0.1",
            controllerKind: .unsupported
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.liveStreamRequested = true
        model.liveStreamState = .connecting
        let producer = try #require(makeSleepingSessionTask(slot: .traffic, model: model))

        model.startLiveStreams(for: profile, isRetry: true, generation: UUID())

        #expect(!producer.isCancelled)
        #expect(model.liveSessionTasks.contains(.traffic))
        #expect(model.liveStreamRequested)
        #expect(model.liveStreamState == .connecting)
        #expect(model.liveSessionRuntime == nil)
        model.leaveLiveSession()
    }

    @MainActor
    @Test func profileSaveFailureRollsBackSecretAndLeavesLiveModelUntouched() async {
        let id = UUID()
        let profile = RouterProfile(
            id: id,
            displayName: "Existing",
            host: "127.0.0.1",
            secretReference: AppModel.secretReference(for: id),
            controllerKind: .unsupported
        )
        let profileStore = TransactionProfileStore(profiles: [profile], failsOnSave: true)
        let secretStore = TransactionSecretStore(values: [id: "old-secret"])
        let model = AppModel(
            routers: [profile],
            controllerSecrets: [id: "old-secret"],
            profileStore: profileStore,
            secretStore: secretStore
        )
        var draft = RouterDraft(profile: profile, secret: "new-secret", hasStoredSecret: true)
        draft.displayName = "Changed"

        do {
            try await model.upsertRouter(from: draft)
            Issue.record("Expected the injected profile-store failure")
        } catch {
            #expect(model.routers == [profile])
            #expect(model.controllerSecrets[id] == "old-secret")
            let storedSecret = try? await secretStore.secret(for: id)
            let storedProfiles = await profileStore.storedProfiles()
            #expect(storedSecret == "old-secret")
            #expect(storedProfiles == [profile])
        }
    }

    @MainActor
    @Test func deleteFailureRestoresSecretAndPreservesSelectionAndOrder() async {
        let first = RouterProfile(
            displayName: "First",
            host: "127.0.0.1",
            secretReference: nil,
            controllerKind: .unsupported
        )
        let second = RouterProfile(
            displayName: "Second",
            host: "127.0.0.2",
            secretReference: AppModel.secretReference(for: UUID()),
            controllerKind: .unsupported
        )
        var storedSecond = second
        storedSecond.secretReference = AppModel.secretReference(for: second.id)
        let profiles = [first, storedSecond]
        let profileStore = TransactionProfileStore(profiles: profiles, failsOnSave: true)
        let secretStore = TransactionSecretStore(values: [storedSecond.id: "keep-me"])
        let model = AppModel(
            routers: profiles,
            selectedRouterID: first.id,
            controllerSecrets: [storedSecond.id: "keep-me"],
            profileStore: profileStore,
            secretStore: secretStore
        )

        do {
            try await model.deleteRouterTransaction(storedSecond)
            Issue.record("Expected the injected profile-store failure")
        } catch {
            #expect(model.routers == profiles)
            #expect(model.selectedRouterID == first.id)
            #expect(model.controllerSecrets[storedSecond.id] == "keep-me")
            let storedSecret = try? await secretStore.secret(for: storedSecond.id)
            #expect(storedSecret == "keep-me")
        }
    }

    private static func selectorProxyResponse(selected: String) -> String {
        #"""
        {
          "proxies": {
            "Auto": {
              "type": "Selector",
              "now": "\#(selected)",
              "all": ["Node A", "Node B"],
              "controller-extra": { "nested": { "enabled": true } }
            },
            "Node A": { "type": "VLESS", "all": [] },
            "Node B": { "type": "VLESS", "all": [] }
          }
        }
        """#
    }

    private static let smartProxyResponse = #"""
    {
      "proxies": {
        "Auto": {
          "type": "Smart",
          "now": "Node A",
          "all": ["Node A", "Node B"]
        },
        "Node A": { "type": "VLESS", "all": [] },
        "Node B": { "type": "VLESS", "all": [] }
      }
    }
    """#

    private static let smartWeightsResponse = #"""
    {
      "message": "ok",
      "weights": {
        "Auto": [{ "Name": "Node A", "Rank": "MostUsed" }]
      }
    }
    """#

    private static func rulesResponse(payload: String) -> String {
        #"""
        {
          "rules": [{
            "type": "DOMAIN",
            "payload": "\#(payload)",
            "proxy": "DIRECT"
          }]
        }
        """#
    }

    private static func proxyProvidersResponse(updatedAt: String) -> String {
        #"""
        {
          "providers": {
            "Remote": {
              "type": "Proxy",
              "vehicleType": "HTTP",
              "updatedAt": "\#(updatedAt)",
              "proxies": [{ "name": "Node A", "type": "VLESS" }]
            }
          }
        }
        """#
    }

    private static let ruleProvidersResponse = #"""
    {
      "providers": {
        "Rules": {
          "type": "Rule",
          "behavior": "domain",
          "vehicleType": "HTTP",
          "rule-count": 1
        }
      }
    }
    """#

    @MainActor
    private func makeLiveMihomoModel(profile: RouterProfile) -> AppModel {
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
        model.controllerSession.state = .live
        model.activeSessionControllerKind = .mihomoCompatible
        model.controllerHealth = .checking(router: profile)
        return model
    }
}
