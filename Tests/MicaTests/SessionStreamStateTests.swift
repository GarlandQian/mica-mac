import Foundation
import MicaCore
import Testing
@testable import Mica

struct SessionStreamStateTests {
    private final class TestNow {
        var value: Date

        init(_ value: Date) {
            self.value = value
        }

        func advance(by interval: TimeInterval) {
            value = value.addingTimeInterval(interval)
        }
    }

    @Test func boundedLogBufferEvictsOldestEntriesInFIFOOrder() {
        var buffer = BoundedLogBuffer()
        let appendedCount = BoundedLogBuffer.maximumEntryCount + 2

        for index in 0..<appendedCount {
            buffer.append(logEntry(id: "log-\(index)", payload: "payload-\(index)"))
        }

        #expect(buffer.count == BoundedLogBuffer.maximumEntryCount)
        #expect(buffer.entries.first?.id == "log-2")
        #expect(buffer.entries.last?.id == "log-2001")
        #expect(buffer.rawRevision == UInt64(appendedCount))
        #expect(buffer.utf8ByteCount == buffer.entries.reduce(into: 0) {
            $0 += expectedLogByteCount($1)
        })
    }

    @Test func boundedLogBufferEvictsByUTF8BudgetWithoutLosingFIFOOrder() {
        let payload = String(repeating: "x", count: 3 * 1_024 * 1_024)
        let entries = (1...3).map {
            logEntry(id: "log-\($0)", payload: payload)
        }
        var buffer = BoundedLogBuffer()

        for entry in entries {
            buffer.append(entry)
        }

        #expect(buffer.entries.map(\.id) == ["log-2", "log-3"])
        #expect(buffer.utf8ByteCount <= BoundedLogBuffer.maximumUTF8Bytes)
        #expect(buffer.utf8ByteCount == entries.suffix(2).reduce(into: 0) {
            $0 += expectedLogByteCount($1)
        })

        buffer.append(
            logEntry(
                id: "oversized",
                payload: String(
                    repeating: "y",
                    count: BoundedLogBuffer.maximumUTF8Bytes + 1
                )
            )
        )

        #expect(buffer.isEmpty)
        #expect(buffer.utf8ByteCount == 0)
    }

    @Test func boundedLogBufferReplaceClearAndEqualityAreDeterministic() {
        let first = logEntry(id: "first", payload: "one")
        let second = logEntry(id: "second", payload: "two")
        var baseline = BoundedLogBuffer(entries: [first, second])

        #expect(baseline.rawRevision == 0)
        baseline.replace(with: [first, second])
        #expect(baseline.rawRevision == 0)

        var rebuilt = BoundedLogBuffer(entries: [first, second])
        rebuilt.removeAll()
        rebuilt.replace(with: [first, second])

        #expect(rebuilt.rawRevision == 2)
        #expect(rebuilt == baseline)

        baseline.replace(with: [second, first])
        #expect(baseline.rawRevision == 1)
        #expect(baseline.entries == [second, first])

        baseline.removeAll()
        #expect(baseline.rawRevision == 2)
        #expect(baseline.isEmpty)

        baseline.removeAll()
        #expect(baseline.rawRevision == 2)
    }

    @Test func closedConnectionHistoryEvictsByCountAndPresentsNewestFirst() {
        let start = Date(timeIntervalSince1970: 10_000)
        let clock = TestNow(start)
        var buffer = ClosedConnectionBuffer(now: { clock.value })

        for index in 0...ClosedConnectionBuffer.maximumEntryCount {
            clock.value = start.addingTimeInterval(TimeInterval(index))
            buffer.record([
                ConnectionSnapshot(id: "connection-\(index)", upload: index),
            ])
        }

        #expect(buffer.records.count == ClosedConnectionBuffer.maximumEntryCount)
        #expect(buffer.records.first?.id == "connection-200")
        #expect(buffer.records.last?.id == "connection-1")
        #expect(buffer.snapshots.map(\.id) == buffer.records.map(\.id))
    }

    @Test func closedConnectionHistoryEvictsRowsOlderThanThirtyMinutes() {
        let start = Date(timeIntervalSince1970: 20_000)
        let clock = TestNow(start)
        var buffer = ClosedConnectionBuffer(now: { clock.value })

        buffer.record([ConnectionSnapshot(id: "oldest")])
        clock.advance(by: 1)
        buffer.record([ConnectionSnapshot(id: "newer")])
        let revisionBeforeExpiry = buffer.revision

        clock.value = start.addingTimeInterval(ClosedConnectionBuffer.maximumAge)
        buffer.pruneExpired()
        #expect(buffer.records.map(\.id) == ["newer", "oldest"])
        #expect(buffer.revision == revisionBeforeExpiry)

        clock.advance(by: 0.001)
        buffer.pruneExpired()
        #expect(buffer.records.map(\.id) == ["newer"])
        #expect(buffer.revision == revisionBeforeExpiry &+ 1)

        clock.advance(by: 1)
        buffer.pruneExpired()
        #expect(buffer.records.isEmpty)
        #expect(buffer.revision == revisionBeforeExpiry &+ 2)
    }

    @Test func closedConnectionHistoryRetainsLatestDuplicateAndReceiptTimestamp() {
        let start = Date(timeIntervalSince1970: 30_000)
        let clock = TestNow(start)
        var buffer = ClosedConnectionBuffer(now: { clock.value })

        buffer.record([
            ConnectionSnapshot(id: "duplicate", upload: 1),
            ConnectionSnapshot(id: "duplicate", upload: 2),
        ])
        #expect(buffer.records.count == 1)
        #expect(buffer.records.first?.snapshot.upload == 2)
        #expect(buffer.records.first?.closedAt == start)

        clock.advance(by: 10)
        buffer.record([ConnectionSnapshot(id: "duplicate", upload: 3)])
        let latestRevision = buffer.revision
        buffer.record([
            ClosedConnectionRecord(
                snapshot: ConnectionSnapshot(id: "duplicate", upload: 0),
                closedAt: start.addingTimeInterval(5)
            ),
        ])

        #expect(buffer.records.first?.snapshot.upload == 3)
        #expect(buffer.records.first?.closedAt == start.addingTimeInterval(10))
        #expect(buffer.revision == latestRevision)
    }

    @Test func dashboardControlsPreserveClosedReceiptTimeAcrossBufferedTransfer() {
        let start = Date(timeIntervalSince1970: 40_000)
        let clock = TestNow(start)
        let row = ConnectionSnapshot(id: "connection-1", upload: 10, download: 20)
        var pending = ClosedConnectionBuffer(now: { clock.value })
        pending.record([row])

        clock.advance(by: 5 * 60)
        var controls = DashboardSessionControls(now: { clock.value })
        controls.recordClosed(pending.entries)

        #expect(controls.closedConnections == [row])
        #expect(controls.closedConnectionRecords.first?.closedAt == start)
    }

    @Test func logLevelsMapToUpstreamSubscriptionThresholds() {
        #expect(LogSessionLevel.all.upstreamValue == "debug")
        #expect(LogSessionLevel.debug.upstreamValue == "debug")
        #expect(LogSessionLevel.trace.upstreamValue == "debug")
        #expect(LogSessionLevel.info.upstreamValue == "info")
        #expect(LogSessionLevel.warning.upstreamValue == "warning")
        #expect(LogSessionLevel.error.upstreamValue == "error")
        #expect(LogSessionLevel.all.surgeUpstreamValue == "verbose")
        #expect(LogSessionLevel.debug.surgeUpstreamValue == "verbose")
        #expect(LogSessionLevel.trace.surgeUpstreamValue == "verbose")
        #expect(LogSessionLevel.info.surgeUpstreamValue == "info")
        #expect(LogSessionLevel.warning.surgeUpstreamValue == "warning")
        #expect(LogSessionLevel.error.surgeUpstreamValue == "error")
    }

    @Test func traceLogFilterMatchesOnlyReportedTraceEntries() {
        #expect(LogSessionLevel.trace.matches("trace"))
        #expect(LogSessionLevel.trace.matches(" TRACE "))
        #expect(!LogSessionLevel.trace.matches("debug"))
        #expect(!LogSessionLevel.debug.matches("trace"))
    }

    @Test func traceLogFilterIsOfferedOnlyForSingBoxSessions() {
        #expect(
            LogSessionLevel.availableLevels(for: .singBoxCompatible).contains(.trace)
        )
        #expect(
            !LogSessionLevel.availableLevels(for: .mihomoCompatible).contains(.trace)
        )
        #expect(
            !LogSessionLevel.availableLevels(for: .surgeHTTPAPI).contains(.trace)
        )
    }

    @Test func singBoxTraceLogsKeepTheirReportedLevel() {
        let projected = LogMessage(
            singBox: SingBoxLogMessage(
                level: .trace,
                message: "full trace payload"
            )
        )

        #expect(projected.type == "trace")
        #expect(projected.level == "trace")
        #expect(projected.payload == "full trace payload")
        #expect(LogSessionLevel.trace.matches(projected.type))
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

    @Test func closedConnectionRevisionChangesOnlyWithRetainedHistory() {
        let clock = TestNow(Date(timeIntervalSince1970: 50_000))
        var controls = DashboardSessionControls(now: { clock.value })
        let initialRevision = controls.closedConnectionsRevision
        let row = ConnectionSnapshot(id: "connection-1", upload: 10, download: 20)

        controls.recordClosed([row])
        #expect(controls.closedConnectionsRevision == initialRevision &+ 1)

        controls.recordClosed([row])
        #expect(controls.closedConnectionsRevision == initialRevision &+ 1)

        clock.advance(by: 1)
        controls.recordClosed([row])
        #expect(controls.closedConnectionsRevision == initialRevision &+ 2)

        controls.clearClosedConnections()
        #expect(controls.closedConnectionsRevision == initialRevision &+ 3)

        controls.clearClosedConnections()
        #expect(controls.closedConnectionsRevision == initialRevision &+ 3)
    }

    @MainActor
    @Test func resumingLogsPublishesBufferedControllerEntriesWithoutTouchingGlobalPause() {
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
        let entry = ControllerLogEntry(
            message: LogMessage(
                type: "warning",
                payload: "controller payload",
                time: "08:30:00",
                fields: .object(["source": .string("mihomo")])
            )
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: entry.receivedAt)
        model.controllerSession.state = .live
        model.registerLiveSessionWindowDemand(
            LiveSessionWindowDemandID(),
            destination: .logs
        )
        model.controllerSession.logBuffer.append(entry)
        model.dashboardSessionControls.setLogsPresentationPaused(true)

        model.toggleControllerLogsPaused()

        #expect(!model.dashboardSessionControls.logsPresentationPaused)
        #expect(!model.dashboardSessionControls.dashboardUpdatesPaused)
        #expect(model.logsCatalog.entries == [entry])
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
        model.publishControllerLogs([entry])

        model.applyPresentationLanguage(.english)

        #expect(model.logsCatalog.entries == [entry])
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

    @Test func memoryTimelineRetainsConnectionsFrameSamplesAndDeduplicatesConcurrentSources() {
        var timeline = MemoryTimeline()
        let receivedAt = Date(timeIntervalSince1970: 100)

        timeline.append(
            inUseBytes: 512,
            source: .connectionsFrame,
            receivedAt: receivedAt
        )
        timeline.append(
            inUseBytes: 512,
            source: .memoryEndpoint,
            receivedAt: receivedAt.addingTimeInterval(0.1)
        )
        timeline.append(
            inUseBytes: 768,
            source: .memoryEndpoint,
            receivedAt: receivedAt.addingTimeInterval(1)
        )

        #expect(timeline.samples.count == 2)
        #expect(timeline.samples.first?.source == .connectionsFrame)
        #expect(timeline.samples.last?.inUseBytes == 768)
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

    @Test func connectionTransferRatesAreDerivedPerOccurrenceForDuplicateReportedIDs() {
        var tracker = ConnectionTransferRateTracker()
        _ = tracker.enriching(
            ConnectionsResponse(
                connections: [
                    ConnectionSnapshot(id: "duplicate", upload: 100, download: 300),
                    ConnectionSnapshot(id: "duplicate", upload: 1_000, download: 2_000),
                ]
            ),
            receivedAt: Date(timeIntervalSince1970: 10)
        )

        let next = tracker.enriching(
            ConnectionsResponse(
                connections: [
                    ConnectionSnapshot(id: "duplicate", upload: 300, download: 700),
                    ConnectionSnapshot(id: "duplicate", upload: 1_600, download: 3_200),
                ]
            ),
            receivedAt: Date(timeIntervalSince1970: 12)
        )

        #expect(next.connections.map(\.id) == ["duplicate", "duplicate"])
        #expect(next.connections.map(\.upload) == [300, 1_600])
        #expect(next.connections.map(\.download) == [700, 3_200])
        #expect(next.connections.map(\.uploadSpeed) == [100, 300])
        #expect(next.connections.map(\.downloadSpeed) == [200, 600])
    }

    @Test func connectionTransferRatesDoNotGuessWhenDuplicateOccurrenceCountChanges() {
        var tracker = ConnectionTransferRateTracker()
        _ = tracker.enriching(
            ConnectionsResponse(
                connections: [
                    ConnectionSnapshot(id: "duplicate", upload: 100, download: 300),
                    ConnectionSnapshot(id: "duplicate", upload: 1_000, download: 2_000),
                ]
            ),
            receivedAt: Date(timeIntervalSince1970: 20)
        )

        let ambiguous = tracker.enriching(
            ConnectionsResponse(
                connections: [
                    ConnectionSnapshot(id: "duplicate", upload: 1_200, download: 2_400),
                ]
            ),
            receivedAt: Date(timeIntervalSince1970: 21)
        )

        #expect(ambiguous.connections.first?.uploadSpeed == nil)
        #expect(ambiguous.connections.first?.downloadSpeed == nil)

        let stable = tracker.enriching(
            ConnectionsResponse(
                connections: [
                    ConnectionSnapshot(id: "duplicate", upload: 1_300, download: 2_600),
                ]
            ),
            receivedAt: Date(timeIntervalSince1970: 22)
        )

        #expect(stable.connections.first?.uploadSpeed == 100)
        #expect(stable.connections.first?.downloadSpeed == 200)
    }

    @Test func connectionTransferRatesPreserveReportedRatesAcrossCounterReset() {
        var tracker = ConnectionTransferRateTracker()
        _ = tracker.enriching(
            ConnectionsResponse(
                connections: [
                    ConnectionSnapshot(id: "duplicate", upload: 1_000, download: 2_000),
                    ConnectionSnapshot(id: "duplicate", upload: 3_000, download: 4_000),
                ]
            ),
            receivedAt: Date(timeIntervalSince1970: 30)
        )

        let reset = tracker.enriching(
            ConnectionsResponse(
                connections: [
                    ConnectionSnapshot(
                        id: "duplicate",
                        upload: 10,
                        download: 20,
                        uploadSpeed: 7,
                        downloadSpeed: 9
                    ),
                    ConnectionSnapshot(id: "duplicate", upload: 30, download: 40),
                ]
            ),
            receivedAt: Date(timeIntervalSince1970: 31)
        )

        #expect(reset.connections[0].uploadSpeed == 7)
        #expect(reset.connections[0].downloadSpeed == 9)
        #expect(reset.connections[1].uploadSpeed == nil)
        #expect(reset.connections[1].downloadSpeed == nil)
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
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 9))
        model.controllerSession.state = .live
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

    @Test func surgeEventProjectionPreservesReportedOrderPayloadAndStableIDs() {
        let entries = DashboardSnapshot.surgeEventLogEntries(
            for: [
                SurgeEvent(
                    id: "event-1",
                    type: "warning",
                    message: "First event",
                    date: "1700000000"
                ),
                SurgeEvent(
                    id: "event-1",
                    type: "info",
                    message: "Second event",
                    date: "2024-01-01T00:00:00Z"
                ),
            ]
        )

        #expect(entries.map(\.id) == ["surge-event:event-1", "surge-event:event-1#2"])
        #expect(entries.map(\.message.payload) == ["First event", "Second event"])
        #expect(entries.map(\.message.type) == ["warning", "info"])
        #expect(entries[0].receivedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(entries[1].receivedAt == ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z"))
    }

    @MainActor
    @Test func surgeSnapshotPublishesEventsAndRecentRequestsWithoutDuplication() {
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
        model.controllerSession.commitBaseline(
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        model.controllerSession.state = .live
        model.activeSessionControllerKind = .surgeCompatible
        model.registerLiveSessionWindowDemand(
            LiveSessionWindowDemandID(),
            destination: .logs
        )

        let snapshot = SurgeControlSnapshot(
            events: SurgeEventsResponse(
                events: [
                    SurgeEvent(
                        id: "event-1",
                        type: "warning",
                        message: "Controller event",
                        date: "1700000000"
                    ),
                ]
            ),
            recentRequests: SurgeActiveRequestsResponse(
                requests: [
                    SurgeActiveRequest(
                        id: "recent-1",
                        method: "GET",
                        url: "https://example.test/resource",
                        ruleType: "DOMAIN",
                        rulePayload: "example.test",
                        policy: "Proxy",
                        upload: 128,
                        download: 512,
                        sourceAddress: "192.0.2.10",
                        destinationAddress: "198.51.100.20"
                    ),
                ]
            ),
            checkedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )

        model.applySurgeSnapshot(snapshot, router: profile)
        model.applySurgeSnapshot(snapshot, router: profile)

        #expect(model.logsCatalog.entries.map(\.id) == ["surge-event:event-1"])
        #expect(model.logsCatalog.entries.first?.message.payload == "Controller event")
        #expect(model.dashboardSessionControls.closedConnections.map(\.id) == ["recent-1"])
        #expect(
            model.dashboardSessionControls.closedConnections.first?.metadata?.remoteDestination
                == "https://example.test/resource"
        )
    }

    private func logEntry(id: String, payload: String) -> ControllerLogEntry {
        ControllerLogEntry(
            id: id,
            receivedAt: Date(timeIntervalSince1970: 1),
            message: LogMessage(
                type: "info",
                payload: payload,
                time: "00:00:01"
            )
        )
    }

    private func expectedLogByteCount(_ entry: ControllerLogEntry) -> Int {
        entry.id.utf8.count
            + entry.message.type.utf8.count
            + entry.message.payload.utf8.count
            + (entry.message.time?.utf8.count ?? 0)
            + (entry.structuredFieldsText?.utf8.count ?? 0)
    }
}
