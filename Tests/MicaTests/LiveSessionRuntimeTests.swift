import Foundation
import MicaCore
import Testing
@testable import Mica

struct LiveSessionRuntimeTests {
    @Test func hiddenLogBurstPublishesOneBoundedSnapshotOnActivation() async throws {
        let identity = makeIdentity()
        let runtime = makeRuntime(identity: identity, observedDomains: [])
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        for index in 0..<10_000 {
            let scheduled = await runtime.ingestLog(
                LogMessage(type: "info", payload: "entry-\(index)"),
                source: .mihomoWebSocket,
                receivedAt: start.addingTimeInterval(Double(index) / 100),
                id: "log-\(index)"
            )
            #expect(scheduled.isEmpty)
        }

        let activated = try #require(
            await runtime.setPresentationDemand(
                makeDemand(
                    identity: identity,
                    revision: 2,
                    observedDomains: [.logs]
                )
            )
        )
        #expect(activated == [.logs])

        let publication = try #require(await runtime.publication(for: .logs))
        guard case .logs(let logs) = publication.payload else {
            Issue.record("Expected log publication")
            return
        }
        #expect(publication.identity == identity)
        #expect(publication.observation.logEvents == 10_000)
        #expect(logs.fullSnapshot?.count == BoundedLogBuffer.maximumEntryCount)
        #expect(logs.fullSnapshot?.first?.id == "log-8000")
        #expect(logs.fullSnapshot?.last?.id == "log-9999")
        #expect(await runtime.publication(for: .logs) == nil)
    }

    @Test func visibleTrafficBurstReservesOneFlightAndKeepsLatestBoundedTimeline() async throws {
        let runtime = makeRuntime(identity: makeIdentity())
        let start = Date(timeIntervalSince1970: 1_700_100_000)
        var scheduleCount = 0

        for index in 0..<1_000 {
            let scheduled = await runtime.ingestTraffic(
                LiveTrafficEvent(upload: index, download: index * 2),
                source: .mihomoWebSocket,
                receivedAt: start.addingTimeInterval(Double(index) / 10)
            )
            scheduleCount += scheduled.contains(.traffic) ? 1 : 0
        }

        #expect(scheduleCount == 1)
        let publication = try #require(await runtime.publication(for: .traffic))
        guard case .traffic(let traffic) = publication.payload else {
            Issue.record("Expected traffic publication")
            return
        }
        #expect(publication.observation.trafficSamples == 1_000)
        #expect(traffic.timeline.samples.count == TrafficTimeline.maximumSampleCount)
        #expect(traffic.latestRate == TrafficSnapshot(upload: 999, download: 1_998))
    }

    @Test func fullLogSnapshotTransitionsToExplicitAppendDropDelta() async throws {
        let runtime = makeRuntime(
            identity: makeIdentity(),
            observedDomains: [.logs]
        )
        let start = Date(timeIntervalSince1970: 1_700_200_000)
        for index in 0..<BoundedLogBuffer.maximumEntryCount {
            _ = await runtime.ingestLog(
                LogMessage(type: "info", payload: "entry-\(index)"),
                source: .mihomoWebSocket,
                receivedAt: start,
                id: "log-\(index)"
            )
        }
        let initial = try #require(await runtime.publication(for: .logs))
        guard case .logs(let initialLogs) = initial.payload else {
            Issue.record("Expected initial log publication")
            return
        }
        #expect(initialLogs.fullSnapshot?.count == BoundedLogBuffer.maximumEntryCount)

        let scheduled = await runtime.ingestLog(
            LogMessage(type: "warning", payload: "tail"),
            source: .mihomoWebSocket,
            receivedAt: start.addingTimeInterval(1),
            id: "tail"
        )
        #expect(scheduled == [.logs])
        let delta = try #require(await runtime.publication(for: .logs))
        guard case .logs(let deltaLogs) = delta.payload else {
            Issue.record("Expected delta log publication")
            return
        }
        #expect(deltaLogs.fullSnapshot == nil)
        #expect(deltaLogs.droppedEntryIDs == ["log-0"])
        #expect(deltaLogs.appendedEntries.map(\.id) == ["tail"])
    }

    @Test func connectionRevisionsSeparateStructureMetricsAndAggregateTraffic() async throws {
        let runtime = makeRuntime(identity: makeIdentity())
        let receivedAt = Date(timeIntervalSince1970: 1_700_300_000)
        let firstRows = MicaPerformanceFixtures.connections(count: 2)

        _ = await runtime.ingestMihomoConnections(
            ConnectionsResponse(
                uploadTotal: 10,
                downloadTotal: 20,
                memory: 30,
                connections: firstRows
            ),
            receivedAt: receivedAt
        )
        let first = try #require(await runtime.publication(for: .connections))
        guard case .connections(let firstConnections) = first.payload else {
            Issue.record("Expected connection publication")
            return
        }
        #expect(firstConnections.revisions.structure == 1)
        #expect(firstConnections.revisions.metrics == 1)
        #expect(firstConnections.revisions.traffic == 1)
        #expect(firstConnections.changedMetricIndices == nil)
        #expect(firstConnections.timeline.samples.map(\.activeCount) == [2])
        #expect(firstConnections.timeline.samples.map(\.receivedAt) == [receivedAt])

        var metricRows = firstRows
        metricRows[0].upload = (metricRows[0].upload ?? 0) + 500
        _ = await runtime.ingestMihomoConnections(
            ConnectionsResponse(
                uploadTotal: 11,
                downloadTotal: 20,
                memory: 30,
                connections: metricRows
            ),
            receivedAt: receivedAt.addingTimeInterval(1)
        )
        let metrics = try #require(await runtime.publication(for: .connections))
        guard case .connections(let metricConnections) = metrics.payload else {
            Issue.record("Expected metrics publication")
            return
        }
        #expect(metricConnections.revisions.structure == 1)
        #expect(metricConnections.revisions.metrics == 2)
        #expect(metricConnections.revisions.traffic == 2)
        #expect(metricConnections.changedMetricIndices == [0])
        #expect(metricConnections.timeline.samples.map(\.activeCount) == [2, 2])

        var structuralRows = metricRows
        structuralRows[0].rulePayload = "changed"
        structuralRows.removeLast()
        _ = await runtime.ingestMihomoConnections(
            ConnectionsResponse(
                uploadTotal: 11,
                downloadTotal: 20,
                memory: 30,
                connections: structuralRows
            ),
            receivedAt: receivedAt.addingTimeInterval(2)
        )
        let structure = try #require(await runtime.publication(for: .connections))
        guard case .connections(let structuralConnections) = structure.payload else {
            Issue.record("Expected structural publication")
            return
        }
        #expect(structuralConnections.revisions.structure == 2)
        #expect(structuralConnections.revisions.metrics == 3)
        #expect(structuralConnections.revisions.traffic == 2)
        #expect(structuralConnections.changedMetricIndices == nil)
        #expect(structuralConnections.timeline.samples.map(\.activeCount) == [2, 2, 1])
        #expect(structuralConnections.closedRecords.map(\.snapshot.id) == [firstRows[1].id])
    }

    @Test func decodedMetricOnlyFrameUsesIncrementalConnectionProjection() async throws {
        let frames = try DecodedConnectionFrameFixture.make()
        let runtime = makeRuntime(identity: makeIdentity())
        let receivedAt = Date(timeIntervalSince1970: 1_700_310_000)

        _ = await runtime.ingestMihomoConnections(
            ConnectionsResponse(
                uploadTotal: 10,
                downloadTotal: 20,
                memory: 30,
                connections: frames.initial
            ),
            receivedAt: receivedAt
        )
        let first = try #require(
            await runtime.publication(for: .connections, force: true)
        )
        guard case .connections(let firstConnections) = first.payload,
              case .mihomo(let firstResponse) = firstConnections.source else {
            Issue.record("Expected initial Mihomo connection publication")
            return
        }

        var cache = WorkbenchConnectionProjectionCache()
        cache.project(
            activeConnections: firstResponse.connections,
            closedConnections: [],
            scope: .active,
            structureRevision: firstConnections.revisions.structure,
            metricsRevision: firstConnections.revisions.metrics,
            closedRevision: 0,
            query: "",
            sortOrder: [],
            language: .english,
            change: .replacement
        )
        let initialStaticRows = cache.staticRowProjectionCount
        let initialMetricCandidates = cache.metricsCandidateProjectionCount
        let initialMetricRows = cache.metricsRowProjectionCount

        _ = await runtime.ingestMihomoConnections(
            ConnectionsResponse(
                uploadTotal: 10,
                downloadTotal: 20,
                memory: 30,
                connections: frames.metricUpdated
            ),
            receivedAt: receivedAt.addingTimeInterval(1)
        )
        let second = try #require(
            await runtime.publication(for: .connections, force: true)
        )
        guard case .connections(let secondConnections) = second.payload,
              case .mihomo(let secondResponse) = secondConnections.source else {
            Issue.record("Expected updated Mihomo connection publication")
            return
        }

        #expect(secondConnections.revisions.structure == firstConnections.revisions.structure)
        #expect(secondConnections.revisions.metrics == firstConnections.revisions.metrics &+ 1)
        #expect(secondConnections.revisions.traffic == firstConnections.revisions.traffic)
        #expect(secondConnections.changedMetricIndices == [frames.changedIndex])

        cache.project(
            activeConnections: secondResponse.connections,
            closedConnections: [],
            scope: .active,
            structureRevision: secondConnections.revisions.structure,
            metricsRevision: secondConnections.revisions.metrics,
            closedRevision: 0,
            query: "",
            sortOrder: [],
            language: .english,
            change: ConnectionsCatalogChange(
                structureChanged: false,
                metricsChanged: true,
                changedMetricIndices: secondConnections.changedMetricIndices,
                trafficChanged: false
            )
        )

        #expect(cache.staticRowProjectionCount == initialStaticRows)
        #expect(cache.metricsCandidateProjectionCount == initialMetricCandidates + 1)
        #expect(cache.metricsRowProjectionCount == initialMetricRows + 1)
        #expect(
            cache.allRows[frames.changedIndex].connection.upload
                == frames.metricUpdated[frames.changedIndex].upload
        )
    }

    @Test func decodedAdditionalConnectionFieldChangeAdvancesRuntimeStructureRevision() async throws {
        let frames = try DecodedConnectionFrameFixture.make()
        let runtime = makeRuntime(identity: makeIdentity())
        let receivedAt = Date(timeIntervalSince1970: 1_700_320_000)

        _ = await runtime.ingestMihomoConnections(
            ConnectionsResponse(
                uploadTotal: 10,
                downloadTotal: 20,
                memory: 30,
                connections: frames.initial
            ),
            receivedAt: receivedAt
        )
        let first = try #require(
            await runtime.publication(for: .connections, force: true)
        )
        guard case .connections(let firstConnections) = first.payload else {
            Issue.record("Expected initial connection publication")
            return
        }

        _ = await runtime.ingestMihomoConnections(
            ConnectionsResponse(
                uploadTotal: 10,
                downloadTotal: 20,
                memory: 30,
                connections: frames.additionalFieldUpdated
            ),
            receivedAt: receivedAt.addingTimeInterval(1)
        )
        let second = try #require(
            await runtime.publication(for: .connections, force: true)
        )
        guard case .connections(let secondConnections) = second.payload else {
            Issue.record("Expected updated connection publication")
            return
        }

        #expect(secondConnections.revisions.structure == firstConnections.revisions.structure &+ 1)
        #expect(secondConnections.revisions.metrics == firstConnections.revisions.metrics &+ 1)
        #expect(secondConnections.revisions.traffic == firstConnections.revisions.traffic)
        #expect(secondConnections.changedMetricIndices == nil)
    }

    @Test func invalidationRejectsPendingAndFuturePublications() async {
        let runtime = makeRuntime(identity: makeIdentity())
        #expect(
            await runtime.ingestTraffic(
                LiveTrafficEvent(upload: 1, download: 2),
                source: .mihomoWebSocket
            ) == [.traffic]
        )

        await runtime.invalidate()

        #expect(await runtime.publication(for: .traffic, force: true) == nil)
        #expect(
            await runtime.ingestTraffic(
                LiveTrafficEvent(upload: 3, download: 4),
                source: .mihomoWebSocket
            ).isEmpty
        )
    }

    @Test func initialPausedDemandAppliesBeforeFirstIngestion() async {
        let identity = makeIdentity()
        let runtime = makeRuntime(
            identity: identity,
            presentationPaused: true
        )

        #expect(
            await runtime.ingestTraffic(
                LiveTrafficEvent(upload: 1, download: 2),
                source: .mihomoWebSocket
            ).isEmpty
        )
        #expect(
            await runtime.ingestLog(
                LogMessage(type: "info", payload: "hidden"),
                source: .mihomoWebSocket
            ).isEmpty
        )
        let demand = await runtime.currentPresentationDemand()
        #expect(demand.identity == identity)
    }

    @Test func initialLogsOnlyDemandHasNoDefaultOverviewPublicationGap() async {
        let runtime = makeRuntime(
            identity: makeIdentity(),
            observedDomains: [.logs]
        )

        #expect(
            await runtime.ingestTraffic(
                LiveTrafficEvent(upload: 1, download: 2),
                source: .mihomoWebSocket
            ).isEmpty
        )
        #expect(
            await runtime.ingestLog(
                LogMessage(type: "info", payload: "visible"),
                source: .mihomoWebSocket
            ) == [.logs]
        )
    }

    @Test func unchangedDomainUnionStillAppliesPauseLogPauseAndBaselineChanges() async throws {
        let identity = makeIdentity()
        let overviewDomains = Set(LiveSessionVisibleDestination.overview.observedDomains)
        let runtime = makeRuntime(
            identity: identity,
            observedDomains: overviewDomains
        )

        _ = await runtime.ingestTraffic(
            LiveTrafficEvent(upload: 1, download: 2),
            source: .mihomoWebSocket
        )
        _ = try #require(await runtime.publication(for: .traffic))

        let paused = try #require(
            await runtime.setPresentationDemand(
                makeDemand(
                    identity: identity,
                    revision: 2,
                    observedDomains: overviewDomains,
                    presentationPaused: true
                )
            )
        )
        #expect(paused.isEmpty)
        #expect(
            await runtime.ingestTraffic(
                LiveTrafficEvent(upload: 3, download: 4),
                source: .mihomoWebSocket
            ).isEmpty
        )

        let baseline = try #require(
            await runtime.setPresentationDemand(
                makeDemand(
                    identity: identity,
                    revision: 3,
                    observedDomains: overviewDomains,
                    presentationPaused: true,
                    baselinePublicationRequired: true
                )
            )
        )
        #expect(baseline == [.traffic])
        _ = try #require(await runtime.publication(for: .traffic))

        let pausedAgain = try #require(
            await runtime.setPresentationDemand(
                makeDemand(
                    identity: identity,
                    revision: 4,
                    observedDomains: overviewDomains,
                    presentationPaused: true
                )
            )
        )
        #expect(pausedAgain.isEmpty)
        #expect(
            await runtime.ingestMemory(
                MemoryResponse(inuse: 1_024),
                source: .mihomoWebSocket
            ).isEmpty
        )

        let resumed = try #require(
            await runtime.setPresentationDemand(
                makeDemand(
                    identity: identity,
                    revision: 5,
                    observedDomains: overviewDomains
                )
            )
        )
        #expect(resumed == [.memory])
    }

    @Test func unchangedLogsUnionStillAppliesLogPauseChanges() async throws {
        let identity = makeIdentity()
        let runtime = makeRuntime(
            identity: identity,
            observedDomains: [.logs]
        )
        _ = await runtime.ingestLog(
            LogMessage(type: "info", payload: "published"),
            source: .mihomoWebSocket
        )
        _ = try #require(await runtime.publication(for: .logs))

        let logsPaused = makeDemand(
            identity: identity,
            revision: 2,
            observedDomains: [.logs],
            logsPresentationPaused: true
        )
        _ = try #require(await runtime.setPresentationDemand(logsPaused))
        #expect(
            await runtime.ingestLog(
                LogMessage(type: "info", payload: "paused"),
                source: .mihomoWebSocket
            ).isEmpty
        )
        let logsResumed = try #require(
            await runtime.setPresentationDemand(
                makeDemand(
                    identity: identity,
                    revision: 3,
                    observedDomains: [.logs]
                )
            )
        )
        #expect(logsResumed == [.logs])
    }

    @Test func actorRejectsStaleIdentityAndOutOfOrderDemandRevisions() async throws {
        let identity = makeIdentity()
        let runtime = makeRuntime(identity: identity, observedDomains: [])
        let latest = makeDemand(
            identity: identity,
            revision: 3,
            observedDomains: [.logs]
        )

        let accepted = try #require(await runtime.setPresentationDemand(latest))
        #expect(accepted.isEmpty)
        #expect(await runtime.setPresentationDemand(latest) == nil)
        #expect(
            await runtime.setPresentationDemand(
                makeDemand(
                    identity: identity,
                    revision: 2,
                    observedDomains: [],
                    presentationPaused: true
                )
            ) == nil
        )
        #expect(
            await runtime.setPresentationDemand(
                makeDemand(
                    identity: makeIdentity(),
                    revision: 4,
                    observedDomains: [],
                    presentationPaused: true
                )
            ) == nil
        )
        #expect(await runtime.currentPresentationDemand() == latest)
        #expect(
            await runtime.ingestLog(
                LogMessage(type: "info", payload: "latest-demand"),
                source: .mihomoWebSocket
            ) == [.logs]
        )
        #expect(
            await runtime.ingestTraffic(
                LiveTrafficEvent(upload: 1, download: 2),
                source: .mihomoWebSocket
            ).isEmpty
        )
    }

    @Test func newerDemandInvalidatesAnOlderImmediateFlushRevision() async throws {
        let identity = makeIdentity()
        let runtime = makeRuntime(identity: identity, observedDomains: [])
        #expect(
            await runtime.ingestLog(
                LogMessage(type: "info", payload: "retained"),
                source: .mihomoWebSocket
            ).isEmpty
        )
        let visible = makeDemand(
            identity: identity,
            revision: 2,
            observedDomains: [.logs]
        )
        let scheduled = try #require(
            await runtime.setPresentationDemand(visible)
        )
        #expect(scheduled == [.logs])
        _ = try #require(
            await runtime.setPresentationDemand(
                makeDemand(
                    identity: identity,
                    revision: 3,
                    observedDomains: []
                )
            )
        )

        #expect(
            await runtime.publication(
                for: .logs,
                force: true,
                demandRevision: visible.revision
            ) == nil
        )

        let visibleAgain = makeDemand(
            identity: identity,
            revision: 4,
            observedDomains: [.logs]
        )
        #expect(
            try #require(await runtime.setPresentationDemand(visibleAgain))
                == [.logs]
        )
        #expect(
            await runtime.publication(
                for: .logs,
                force: true,
                demandRevision: visibleAgain.revision
            ) != nil
        )
    }

    @Test func staleImmediateFlushUsesCurrentDemandWhenDomainRemainsVisible() async throws {
        let identity = makeIdentity()
        let runtime = makeRuntime(identity: identity, observedDomains: [])
        #expect(
            await runtime.ingestLog(
                LogMessage(type: "info", payload: "retained"),
                source: .mihomoWebSocket
            ).isEmpty
        )
        let firstVisible = makeDemand(
            identity: identity,
            revision: 2,
            observedDomains: [.logs]
        )
        #expect(
            try #require(await runtime.setPresentationDemand(firstVisible))
                == [.logs]
        )
        let currentVisible = makeDemand(
            identity: identity,
            revision: 3,
            observedDomains: [.logs, .traffic]
        )
        #expect(
            try #require(await runtime.setPresentationDemand(currentVisible))
                == []
        )

        let publication = try #require(
            await runtime.publication(
                for: .logs,
                force: true,
                demandRevision: firstVisible.revision
            )
        )
        #expect(publication.domain == .logs)
        #expect(publication.revision == 1)
    }

    private func makeIdentity() -> LiveSessionRuntimeIdentity {
        LiveSessionRuntimeIdentity(controllerID: UUID(), generation: UUID())
    }

    private func makeRuntime(
        identity: LiveSessionRuntimeIdentity,
        observedDomains: Set<LiveSessionPublicationDomain> = Set(
            LiveSessionVisibleDestination.overview.observedDomains
        ),
        presentationPaused: Bool = false,
        logsPresentationPaused: Bool = false,
        baselinePublicationRequired: Bool = false
    ) -> LiveSessionRuntime {
        LiveSessionRuntime(
            controllerKind: .mihomoCompatible,
            initialPresentationDemand: makeDemand(
                identity: identity,
                revision: 1,
                observedDomains: observedDomains,
                presentationPaused: presentationPaused,
                logsPresentationPaused: logsPresentationPaused,
                baselinePublicationRequired: baselinePublicationRequired
            )
        )
    }

    private func makeDemand(
        identity: LiveSessionRuntimeIdentity,
        revision: UInt64,
        observedDomains: Set<LiveSessionPublicationDomain>,
        presentationPaused: Bool = false,
        logsPresentationPaused: Bool = false,
        baselinePublicationRequired: Bool = false
    ) -> LiveSessionPresentationDemand {
        LiveSessionPresentationDemand(
            identity: identity,
            revision: revision,
            observedDomains: observedDomains,
            presentationPaused: presentationPaused,
            logsPresentationPaused: logsPresentationPaused,
            baselinePublicationRequired: baselinePublicationRequired
        )
    }
}
