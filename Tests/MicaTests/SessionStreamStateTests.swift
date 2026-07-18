import Foundation
import MicaCore
import Testing
@testable import Mica

struct SessionStreamStateTests {
    @Test func logLevelsMapToUpstreamSubscriptionThresholds() {
        #expect(LogSessionLevel.all.upstreamValue == "debug")
        #expect(LogSessionLevel.debug.upstreamValue == "debug")
        #expect(LogSessionLevel.info.upstreamValue == "info")
        #expect(LogSessionLevel.warning.upstreamValue == "warning")
        #expect(LogSessionLevel.error.upstreamValue == "error")
        #expect(LogSessionLevel.all.surgeUpstreamValue == "verbose")
        #expect(LogSessionLevel.debug.surgeUpstreamValue == "verbose")
        #expect(LogSessionLevel.info.surgeUpstreamValue == "info")
        #expect(LogSessionLevel.warning.surgeUpstreamValue == "warning")
        #expect(LogSessionLevel.error.surgeUpstreamValue == "error")
    }

    @Test func logPauseIsIndependentFromGlobalPresentationPause() {
        var controls = DashboardSessionControls()
        controls.setLogsPresentationPaused(true, at: Date(timeIntervalSince1970: 42))

        #expect(controls.logsPresentationPaused)
        #expect(controls.logsPresentationPausedAt == Date(timeIntervalSince1970: 42))
        #expect(!controls.dashboardUpdatesPaused)
        #expect(controls.presentationPausedAt == nil)

        controls.resetForControllerSwitch()
        #expect(!controls.logsPresentationPaused)
        #expect(controls.logsPresentationPausedAt == nil)
    }

    @MainActor
    @Test func resumingLogsPublishesBufferedControllerEntriesWithoutTouchingGlobalPause() {
        let model = AppModel(
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        let entry = ControllerLogEntry(
            message: LogMessage(
                type: "warning",
                payload: "controller payload",
                time: "08:30:00",
                fields: .object(["source": .string("mihomo")])
            )
        )
        model.controllerSession.logBuffer.append(entry)
        model.dashboardSessionControls.setLogsPresentationPaused(true)

        model.toggleControllerLogsPaused()

        #expect(!model.dashboardSessionControls.logsPresentationPaused)
        #expect(!model.dashboardSessionControls.dashboardUpdatesPaused)
        #expect(model.dashboard.controllerLogs == [entry])
    }

    @MainActor
    @Test func languageChangesNeverRewriteControllerLogPayloads() {
        let model = AppModel(
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        let entry = ControllerLogEntry(
            message: LogMessage(type: "info", payload: "原始 controller payload")
        )
        model.dashboard.controllerLogs = [entry]

        model.applyPresentationLanguage(.english)

        #expect(model.dashboard.controllerLogs == [entry])
    }

    @MainActor
    @Test func readOnlyProviderNeverStartsAnUpdateTask() {
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
        model.activeSessionControllerKind = .mihomoCompatible
        let source = ProxyProviderViewState(
            kind: .proxy,
            name: "Local File",
            type: "Proxy",
            vehicleType: "File",
            updatable: false,
            itemCount: 2
        )

        model.updateProxyProvider(source)

        #expect(model.providerTask == nil)
        #expect(model.updatingProviderName == nil)
        #expect(model.operationState?.kind == .partial)
    }

    @MainActor
    @Test func providerWithoutHealthCheckConfigurationNeverStartsAHealthCheckTask() {
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
        model.activeSessionControllerKind = .mihomoCompatible
        let source = ProxyProviderViewState(
            kind: .proxy,
            name: "Local File",
            type: "Proxy",
            vehicleType: "File",
            updatable: false,
            healthCheck: nil,
            itemCount: 2
        )

        model.healthCheckProxyProvider(source)

        #expect(model.providerTask == nil)
        #expect(model.checkingProviderName == nil)
        #expect(model.operationState?.kind == .partial)
    }

    @MainActor
    @Test func immutableRuleNeverStartsAMutationTask() {
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
        model.activeSessionControllerKind = .mihomoCompatible
        let rule = RuleViewState(
            id: "immutable-rule",
            index: 3,
            type: "DOMAIN",
            payload: "example.com",
            proxy: "Proxy",
            hasMutableExtra: false
        )

        model.setRuleDisabled(rule, disabled: true)

        #expect(model.rulesTask == nil)
        #expect(model.updatingRuleID == nil)
        #expect(model.operationState?.kind == .partial)
    }

    @Test func pendingPresentationBuffersClosedConnectionsUntilResume() {
        var pending = PendingSessionPresentation()
        pending.closedConnections.record([
            ConnectionSnapshot(id: "connection-1", upload: 10, download: 20),
            ConnectionSnapshot(id: "connection-2", upload: 30, download: 40),
        ])

        #expect(!pending.isEmpty)
        #expect(pending.closedConnections.entries.map(\.id) == ["connection-1", "connection-2"])

        pending.reset()
        #expect(pending.isEmpty)
    }

    @Test func liveObservationCountsConnectionFrames() {
        var observation = ControllerSessionLiveObservation()
        observation.recordConnectionFrame(source: .mihomoWebSocket)
        observation.recordConnectionFrame(source: .mihomoWebSocket)

        #expect(observation.connectionFrameCount == 2)
        #expect(observation.diagnosticsSummary.contains("connection-frames=2"))
    }

    @Test func connectionTransferRatesAreDerivedPerIDFromSuccessiveFrames() {
        var tracker = ConnectionTransferRateTracker()
        let initial = tracker.enriching(
            ConnectionsResponse(
                connections: [ConnectionSnapshot(id: "visible-id", upload: 100, download: 300)]
            ),
            receivedAt: Date(timeIntervalSince1970: 10)
        )

        #expect(initial.connections.first?.uploadSpeed == nil)
        #expect(initial.connections.first?.downloadSpeed == nil)

        let next = tracker.enriching(
            ConnectionsResponse(
                connections: [ConnectionSnapshot(id: "visible-id", upload: 300, download: 900)]
            ),
            receivedAt: Date(timeIntervalSince1970: 12)
        )

        #expect(next.connections.first?.uploadSpeed == 100)
        #expect(next.connections.first?.downloadSpeed == 300)
    }

    @Test func connectionTransferRatesHandleCounterResetAndPreserveReportedRates() {
        var tracker = ConnectionTransferRateTracker()
        _ = tracker.enriching(
            ConnectionsResponse(
                connections: [ConnectionSnapshot(id: "visible-id", upload: 1_000, download: 2_000)]
            ),
            receivedAt: Date(timeIntervalSince1970: 20)
        )

        let reset = tracker.enriching(
            ConnectionsResponse(
                connections: [
                    ConnectionSnapshot(
                        id: "visible-id",
                        upload: 10,
                        download: 20,
                        uploadSpeed: 7,
                        downloadSpeed: 9
                    )
                ]
            ),
            receivedAt: Date(timeIntervalSince1970: 21)
        )

        #expect(reset.connections.first?.uploadSpeed == 7)
        #expect(reset.connections.first?.downloadSpeed == 9)

        tracker.reset()
        let firstAfterReset = tracker.enriching(
            ConnectionsResponse(
                connections: [ConnectionSnapshot(id: "visible-id", upload: 20, download: 40)]
            ),
            receivedAt: Date(timeIntervalSince1970: 22)
        )
        #expect(firstAfterReset.connections.first?.uploadSpeed == nil)
        #expect(firstAfterReset.connections.first?.downloadSpeed == nil)
    }

    @MainActor
    @Test func surgeConnectionProjectionDerivesMissingPerRequestRates() {
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
        model.activeSessionControllerKind = .surgeCompatible

        let initial = SurgeControlSnapshot(
            activeRequests: SurgeActiveRequestsResponse(
                requests: [SurgeActiveRequest(id: "request-1", upload: 100, download: 300)]
            ),
            checkedAt: Date(timeIntervalSince1970: 10)
        )
        model.applySurgeSnapshot(
            initial,
            router: profile,
            connectionRatesReceivedAt: Date(timeIntervalSince1970: 10)
        )
        #expect(model.dashboard.connections.first?.uploadSpeed == nil)

        let next = SurgeControlSnapshot(
            activeRequests: SurgeActiveRequestsResponse(
                requests: [SurgeActiveRequest(id: "request-1", upload: 300, download: 900)]
            ),
            checkedAt: Date(timeIntervalSince1970: 12)
        )
        model.applySurgeSnapshot(
            next,
            router: profile,
            connectionRatesReceivedAt: Date(timeIntervalSince1970: 12)
        )

        #expect(model.dashboard.connections.first?.uploadSpeed == 100)
        #expect(model.dashboard.connections.first?.downloadSpeed == 300)
    }
}
