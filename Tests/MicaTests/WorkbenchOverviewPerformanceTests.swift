import Foundation
import MicaCore
import Observation
import Synchronization
import Testing
@testable import Mica

struct WorkbenchOverviewPerformanceTests {
    @MainActor
    @Test func connectionHighlightsScopeIgnoresConnectionFrames() {
        let dashboard = DashboardSnapshot(
            versionLabel: "1.0",
            mode: "Rule",
            traffic: TrafficSnapshot(upload: 10, download: 20),
            groups: [],
            connections: [ConnectionSnapshot(id: "first", upload: 30, download: 40)]
        )
        let model = AppModel(
            dashboard: dashboard,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        let invalidated = Mutex(false)
        let initialScope = OverviewConnectionHighlightsScope.observing(model)

        withObservationTracking {
            _ = OverviewConnectionHighlightsScope.observing(model)
        } onChange: {
            invalidated.withLock { $0 = true }
        }

        model.mutateSessionDashboard(publishing: [.connections]) { dashboard in
            dashboard.connections[0].upload = 300
            dashboard.connections[0].download = 400
        }
        model.mutateSessionDashboard(publishing: [.connections]) { dashboard in
            dashboard.traffic = TrafficSnapshot(upload: 100, download: 200)
        }

        #expect(!invalidated.withLock { $0 })
        #expect(OverviewConnectionHighlightsScope.observing(model) == initialScope)
    }

    @MainActor
    @Test func connectionHighlightsRequestTracksMetricsButNotAggregateTraffic() {
        let dashboard = DashboardSnapshot(
            versionLabel: "1.0",
            mode: "Rule",
            traffic: TrafficSnapshot(upload: 10, download: 20),
            groups: [],
            connections: [ConnectionSnapshot(id: "first", upload: 30, download: 40)]
        )
        let model = AppModel(
            dashboard: dashboard,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        let initial = OverviewConnectionHighlightsRequest.observing(
            model,
            maximumCount: 3
        )
        let trafficInvalidationCount = Mutex(0)
        withObservationTracking {
            _ = OverviewConnectionHighlightsRequest.observing(
                model,
                maximumCount: 3
            )
        } onChange: {
            trafficInvalidationCount.withLock { $0 += 1 }
        }

        model.mutateSessionDashboard(publishing: [.connections]) { dashboard in
            dashboard.traffic = TrafficSnapshot(upload: 100, download: 200)
        }
        #expect(trafficInvalidationCount.withLock { $0 } == 0)
        #expect(
            OverviewConnectionHighlightsRequest.observing(
                model,
                maximumCount: 3
            ) == initial
        )

        let metricsInvalidationCount = Mutex(0)
        withObservationTracking {
            _ = OverviewConnectionHighlightsRequest.observing(
                model,
                maximumCount: 3
            )
        } onChange: {
            metricsInvalidationCount.withLock { $0 += 1 }
        }
        model.mutateSessionDashboard(publishing: [.connections]) { dashboard in
            dashboard.connections[0].upload = 300
        }
        #expect(metricsInvalidationCount.withLock { $0 } == 1)
        let metricUpdate = OverviewConnectionHighlightsRequest.observing(
            model,
            maximumCount: 3
        )
        #expect(metricUpdate.scope == initial.scope)
        #expect(metricUpdate.metricsRevision == initial.metricsRevision &+ 1)
        #expect(metricUpdate != initial)

        let structureInvalidationCount = Mutex(0)
        withObservationTracking {
            _ = OverviewConnectionHighlightsRequest.observing(
                model,
                maximumCount: 3
            )
        } onChange: {
            structureInvalidationCount.withLock { $0 += 1 }
        }
        model.mutateSessionDashboard(publishing: [.connections]) { dashboard in
            dashboard.connections.append(ConnectionSnapshot(id: "second"))
        }
        #expect(structureInvalidationCount.withLock { $0 } == 1)
        #expect(
            OverviewConnectionHighlightsRequest.observing(
                model,
                maximumCount: 3
            ).metricsRevision == metricUpdate.metricsRevision &+ 1
        )
    }

    @Test func connectionHighlightsPresentationRetainsOnlyTheCurrentSession() {
        let controllerID = UUID(uuidString: "00000000-0000-0000-0000-000000000061")!
        let generation = UUID(uuidString: "00000000-0000-0000-0000-000000000062")!
        let scope = OverviewConnectionHighlightsScope(
            controllerID: controllerID,
            generation: generation
        )
        let presentation = OverviewConnectionHighlightsPresentation(
            scope: scope,
            rows: [
                OverviewActiveConnection(
                    id: "row",
                    sourceIndex: 4,
                    connectionID: "connection",
                    label: "example.test",
                    totalTraffic: 300
                ),
            ]
        )

        #expect(presentation.visible(for: scope) == presentation)
        #expect(
            presentation.visible(for: OverviewConnectionHighlightsScope(
                controllerID: UUID(),
                generation: generation
            )) == nil
        )
        #expect(
            presentation.visible(for: OverviewConnectionHighlightsScope(
                controllerID: controllerID,
                generation: UUID()
            )) == nil
        )
    }

    @Test func connectionHighlightNavigationRequiresTheVisibleSessionScope() throws {
        let controllerID = UUID(uuidString: "00000000-0000-0000-0000-000000000063")!
        let generation = UUID(uuidString: "00000000-0000-0000-0000-000000000064")!
        let scope = OverviewConnectionHighlightsScope(
            controllerID: controllerID,
            generation: generation
        )
        let row = OverviewActiveConnection(
            id: "presentation-row",
            sourceIndex: 17,
            connectionID: "",
            label: "example.test",
            totalTraffic: 300
        )

        let selection = try #require(
            scope.navigationSelection(for: row, currentScope: scope)
        )
        #expect(selection.controllerID == controllerID)
        #expect(selection.generation == generation)
        #expect(selection.sourceIndex == 17)
        #expect(selection.reportedConnectionID.isEmpty)
        #expect(
            scope.navigationSelection(
                for: row,
                currentScope: OverviewConnectionHighlightsScope(
                    controllerID: controllerID,
                    generation: UUID()
                )
            ) == nil
        )
        #expect(
            scope.navigationSelection(
                for: row,
                currentScope: OverviewConnectionHighlightsScope(
                    controllerID: UUID(),
                    generation: generation
                )
            ) == nil
        )
        #expect(
            OverviewConnectionHighlightsScope(
                controllerID: nil,
                generation: generation
            ).navigationSelection(
                for: row,
                currentScope: OverviewConnectionHighlightsScope(
                    controllerID: nil,
                    generation: generation
                )
            ) == nil
        )
    }

    @MainActor
    @Test func topologyStructureObservationIgnoresMetricsAndTraffic() {
        let dashboard = DashboardSnapshot(
            versionLabel: "1.0",
            mode: "Rule",
            traffic: TrafficSnapshot(upload: 10, download: 20),
            groups: [],
            connections: [
                ConnectionSnapshot(
                    id: "first",
                    upload: 30,
                    download: 40,
                    chains: ["Policy", "Node"]
                ),
            ]
        )
        let model = AppModel(
            dashboard: dashboard,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        let invalidationCount = Mutex(0)
        let initialRequest = OverviewTopologyCatalogRequest.observing(model)

        withObservationTracking {
            _ = OverviewTopologyCatalogRequest.observing(model)
        } onChange: {
            invalidationCount.withLock { $0 += 1 }
        }

        model.mutateSessionDashboard(publishing: [.connections]) { dashboard in
            dashboard.connections[0].upload = 300
            dashboard.connections[0].download = 400
        }
        #expect(invalidationCount.withLock { $0 } == 0)
        #expect(OverviewTopologyCatalogRequest.observing(model) == initialRequest)

        model.mutateSessionDashboard(publishing: [.connections]) { dashboard in
            dashboard.traffic = TrafficSnapshot(upload: 100, download: 200)
        }
        #expect(invalidationCount.withLock { $0 } == 0)
        #expect(OverviewTopologyCatalogRequest.observing(model) == initialRequest)

        model.mutateSessionDashboard(publishing: [.connections]) { dashboard in
            dashboard.connections.append(
                ConnectionSnapshot(id: "second", chains: ["Policy", "Other"])
            )
        }
        #expect(invalidationCount.withLock { $0 } == 1)
        #expect(
            OverviewTopologyCatalogRequest.observing(model).structureRevision
                == initialRequest.structureRevision &+ 1
        )
    }

    @Test func topologyStructureInputRetainsOnlyTheCurrentSession() {
        let controllerID = UUID(uuidString: "00000000-0000-0000-0000-000000000051")!
        let generation = UUID(uuidString: "00000000-0000-0000-0000-000000000052")!
        let request = OverviewTopologyCatalogRequest(
            controllerID: controllerID,
            generation: generation,
            structureRevision: 4
        )
        let input = OverviewTopologyCatalogInput(
            request: request,
            catalogRevision: 3,
            connections: [ConnectionSnapshot(id: "connection")]
        )

        #expect(input.visible(for: request) == input)
        #expect(
            input.visible(for: OverviewTopologyCatalogRequest(
                controllerID: controllerID,
                generation: generation,
                structureRevision: 5
            )) == input
        )
        #expect(
            input.visible(for: OverviewTopologyCatalogRequest(
                controllerID: UUID(),
                generation: generation,
                structureRevision: 4
            )) == nil
        )
        #expect(
            input.visible(for: OverviewTopologyCatalogRequest(
                controllerID: controllerID,
                generation: UUID(),
                structureRevision: 4
            )) == nil
        )
    }

    @Test func timelineProjectionCacheRecomputesOnlyChangedSourcesAndWindow() {
        let generation = UUID(uuidString: "59D8645A-5DC9-4B3F-9D3B-DC6370D0809A")!
        let traffic = (0..<150).map { index in
            TrafficTimeline.Sample(
                id: index,
                receivedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                upload: index,
                download: index * 2
            )
        }
        let memory = traffic.map { sample in
            MemoryTimeline.Sample(
                id: sample.id,
                receivedAt: sample.receivedAt,
                inUseBytes: sample.download,
                source: .memoryEndpoint
            )
        }
        let connections = traffic.map { sample in
            ConnectionCountTimeline.Sample(
                id: sample.id,
                receivedAt: sample.receivedAt,
                activeCount: sample.id
            )
        }
        let cache = OverviewTimelineProjectionCache()

        let first = cache.resolve(
            generation: generation,
            window: .fiveMinutes,
            traffic: traffic,
            memory: memory,
            connections: connections
        )
        #expect(first.trafficSamples.count == 120)
        #expect(first.memorySamples.count == 120)
        #expect(first.connectionSamples.count == 120)
        #expect(first.trafficSamples.first?.id == 0)
        #expect(first.trafficSamples.last?.id == 149)
        #expect(cache.statistics == OverviewTimelineProjectionStatistics(
            trafficProjectionCount: 1,
            memoryProjectionCount: 1,
            connectionProjectionCount: 1,
            mergedDateProjectionCount: 1
        ))

        let exactHit = cache.resolve(
            generation: generation,
            window: .fiveMinutes,
            traffic: traffic,
            memory: memory,
            connections: connections
        )
        #expect(exactHit == first)
        #expect(cache.statistics == OverviewTimelineProjectionStatistics(
            trafficProjectionCount: 1,
            memoryProjectionCount: 1,
            connectionProjectionCount: 1,
            mergedDateProjectionCount: 1
        ))

        let appendedTraffic = traffic + [
            TrafficTimeline.Sample(
                id: 150,
                receivedAt: Date(timeIntervalSince1970: 150),
                upload: 150,
                download: 300
            ),
        ]
        let trafficOnlyChange = cache.resolve(
            generation: generation,
            window: .fiveMinutes,
            traffic: appendedTraffic,
            memory: memory,
            connections: connections
        )
        #expect(trafficOnlyChange.trafficSamples.last?.id == 150)
        #expect(trafficOnlyChange.memorySamples == first.memorySamples)
        #expect(cache.statistics == OverviewTimelineProjectionStatistics(
            trafficProjectionCount: 2,
            memoryProjectionCount: 1,
            connectionProjectionCount: 1,
            mergedDateProjectionCount: 2
        ))

        let oneMinute = cache.resolve(
            generation: generation,
            window: .oneMinute,
            traffic: appendedTraffic,
            memory: memory,
            connections: connections
        )
        #expect(oneMinute.trafficSamples.map(\.id) == Array(90...150))
        #expect(oneMinute.memorySamples.map(\.id) == Array(89...149))
        #expect(cache.statistics == OverviewTimelineProjectionStatistics(
            trafficProjectionCount: 3,
            memoryProjectionCount: 2,
            connectionProjectionCount: 2,
            mergedDateProjectionCount: 3
        ))

        _ = cache.resolve(
            generation: UUID(uuidString: "01F1C976-C3F1-4CA1-9DAB-72BDC8B27AE6")!,
            window: .oneMinute,
            traffic: appendedTraffic,
            memory: memory,
            connections: connections
        )
        #expect(cache.statistics == OverviewTimelineProjectionStatistics(
            trafficProjectionCount: 4,
            memoryProjectionCount: 3,
            connectionProjectionCount: 3,
            mergedDateProjectionCount: 4
        ))
    }

    @Test func timelinePauseFreezesPresentationAndResumeCatchesLatestRealSamples() {
        let generation = UUID(uuidString: "9284EDB2-58DB-46DE-A019-D365E3FDE735")!
        let firstDate = Date(timeIntervalSince1970: 100)
        let firstTraffic = [
            TrafficTimeline.Sample(
                id: 0,
                receivedAt: firstDate,
                upload: 10,
                download: 20
            ),
        ]
        let firstMemory = [
            MemoryTimeline.Sample(
                id: 0,
                receivedAt: firstDate,
                inUseBytes: 1_024,
                source: .memoryEndpoint
            ),
        ]
        let firstConnections = [
            ConnectionCountTimeline.Sample(
                id: 0,
                receivedAt: firstDate,
                activeCount: 2
            ),
        ]
        let cache = OverviewTimelineProjectionCache()
        let initial = cache.resolve(
            generation: generation,
            window: .oneMinute,
            traffic: firstTraffic,
            memory: firstMemory,
            connections: firstConnections
        )
        let initialStatistics = cache.statistics
        let secondDate = firstDate.addingTimeInterval(1)
        let paused = cache.resolve(
            generation: generation,
            window: .oneMinute,
            traffic: firstTraffic + [
                TrafficTimeline.Sample(
                    id: 1,
                    receivedAt: secondDate,
                    upload: 30,
                    download: 40
                ),
            ],
            memory: firstMemory + [
                MemoryTimeline.Sample(
                    id: 1,
                    receivedAt: secondDate,
                    inUseBytes: 2_048,
                    source: .memoryEndpoint
                ),
            ],
            connections: firstConnections + [
                ConnectionCountTimeline.Sample(
                    id: 1,
                    receivedAt: secondDate,
                    activeCount: 3
                ),
            ],
            isPaused: true
        )

        #expect(paused == initial)
        #expect(cache.statistics == initialStatistics)

        let resumed = cache.resolve(
            generation: generation,
            window: .oneMinute,
            traffic: firstTraffic + [
                TrafficTimeline.Sample(
                    id: 1,
                    receivedAt: secondDate,
                    upload: 30,
                    download: 40
                ),
            ],
            memory: firstMemory + [
                MemoryTimeline.Sample(
                    id: 1,
                    receivedAt: secondDate,
                    inUseBytes: 2_048,
                    source: .memoryEndpoint
                ),
            ],
            connections: firstConnections + [
                ConnectionCountTimeline.Sample(
                    id: 1,
                    receivedAt: secondDate,
                    activeCount: 3
                ),
            ]
        )

        #expect(resumed.trafficSamples.last?.id == 1)
        #expect(resumed.memorySamples.last?.id == 1)
        #expect(resumed.connectionSamples.last?.id == 1)
        #expect(resumed.dates.last == secondDate)
        #expect(cache.statistics == OverviewTimelineProjectionStatistics(
            trafficProjectionCount: 2,
            memoryProjectionCount: 2,
            connectionProjectionCount: 2,
            mergedDateProjectionCount: 2
        ))
    }

    @Test func timelineProjectionCacheRejectsSameIdentityWithNewReceiptTimes() {
        let generation = UUID(uuidString: "A5EA65E5-E30F-4197-A3E4-0BE5DA178F44")!
        let cache = OverviewTimelineProjectionCache()
        let initial = [
            TrafficTimeline.Sample(
                id: 0,
                receivedAt: Date(timeIntervalSince1970: 100),
                upload: 10,
                download: 20
            ),
            TrafficTimeline.Sample(
                id: 1,
                receivedAt: Date(timeIntervalSince1970: 101),
                upload: 30,
                download: 40
            ),
        ]
        let replacement = [
            TrafficTimeline.Sample(
                id: 0,
                receivedAt: Date(timeIntervalSince1970: 200),
                upload: 50,
                download: 60
            ),
            TrafficTimeline.Sample(
                id: 1,
                receivedAt: Date(timeIntervalSince1970: 201),
                upload: 70,
                download: 80
            ),
        ]

        _ = cache.resolve(
            generation: generation,
            window: .fiveMinutes,
            traffic: initial,
            memory: [],
            connections: []
        )
        let resolved = cache.resolve(
            generation: generation,
            window: .fiveMinutes,
            traffic: replacement,
            memory: [],
            connections: []
        )

        #expect(resolved.trafficSamples == replacement)
        #expect(cache.statistics.trafficProjectionCount == 2)
    }

    @MainActor
    @Test func timelineInteractionKeepsHoverAndPinOutsideProjectionState() {
        let dates = (0..<4).map {
            Date(timeIntervalSince1970: TimeInterval($0))
        }
        let interaction = OverviewTimelineInteractionState()

        #expect(interaction.snapshot == .empty)
        #expect(interaction.canMoveSelection(by: -1, in: dates))
        #expect(!interaction.canMoveSelection(by: 1, in: dates))

        interaction.setPinnedDate(dates[1])
        #expect(interaction.snapshot.selectedDate == dates[1])
        #expect(interaction.canMoveSelection(by: 1, in: dates))

        interaction.setHoveredDate(dates[0])
        #expect(interaction.snapshot.hoveredDate == dates[0])
        #expect(interaction.snapshot.pinnedDate == dates[1])
        #expect(interaction.snapshot.selectedDate == dates[0])

        interaction.moveSelection(by: 1, in: dates)
        #expect(interaction.snapshot.hoveredDate == nil)
        #expect(interaction.snapshot.pinnedDate == dates[1])

        interaction.setHoveredDate(dates[3])
        interaction.retainPinnedDate(in: [dates[0], dates[3]])
        #expect(interaction.snapshot.hoveredDate == dates[3])
        #expect(interaction.snapshot.pinnedDate == nil)
        #expect(interaction.snapshot.selectedDate == dates[3])

        interaction.reset()
        #expect(interaction.snapshot == .empty)
    }

    @Test func timelineChartScaleKeepsZeroAndSingleSampleSeriesVisible() {
        let zeroTraffic = [
            TrafficTimeline.Sample(
                id: 0,
                receivedAt: Date(timeIntervalSince1970: 0),
                upload: 0,
                download: 0
            ),
        ]
        let zeroScale = OverviewTimelineChartScale.traffic(zeroTraffic)
        #expect(zeroScale.domain.lowerBound < 0)
        #expect(zeroScale.domain.upperBound > 0)
        #expect(zeroScale.axisValues == [0])

        let activeTraffic = [
            TrafficTimeline.Sample(
                id: 1,
                receivedAt: Date(timeIntervalSince1970: 1),
                upload: 64,
                download: 128
            ),
        ]
        let activeScale = OverviewTimelineChartScale.traffic(activeTraffic)
        #expect(activeScale.domain.lowerBound < 0)
        #expect(activeScale.domain.upperBound > 60_000)
        #expect(activeScale.axisValues.first == 0)

        let memoryScale = OverviewTimelineChartScale.memory([
            MemoryTimeline.Sample(
                id: 0,
                receivedAt: Date(timeIntervalSince1970: 0),
                inUseBytes: 96,
                source: .memoryEndpoint
            ),
        ])
        #expect(memoryScale.domain.lowerBound < 0)
        #expect(memoryScale.domain.upperBound > 100 * 1_024 * 1_024)

        let connectionScale = OverviewTimelineChartScale.connections([
            ConnectionCountTimeline.Sample(
                id: 0,
                receivedAt: Date(timeIntervalSince1970: 0),
                activeCount: 1
            ),
        ])
        #expect(connectionScale.domain.lowerBound < 0)
        #expect(connectionScale.domain.upperBound > 100)

        let latest = Date(timeIntervalSince1970: 500)
        let domain = OverviewTimelineProjection.dateDomain(
            endingAt: latest,
            window: .threeMinutes
        )
        #expect(domain.upperBound == latest)
        #expect(domain.lowerBound == latest.addingTimeInterval(-180))
    }

    @Test func overviewTopKProjectionsKeepBoundedWorkingSets() {
        let maximumCount = 5
        let connections = MicaPerformanceFixtures.connections(count: 2_048)
        let connectionProjection = OverviewProjection.topActiveConnectionsWithOperationCounts(
            from: connections,
            maximumCount: maximumCount
        )
        #expect(connectionProjection.rows.map(\.connectionID) == [
            "connection-2047",
            "connection-2046",
            "connection-2045",
            "connection-2044",
            "connection-2043",
        ])
        assertBoundedTopK(
            connectionProjection.operationCounts,
            sourceCount: connections.count,
            candidateCount: connections.count,
            maximumCount: maximumCount
        )

        let groups = (0..<1_024).map { index in
            ProxyGroupViewState(
                id: "group-\(index)",
                type: "Selector",
                selected: "node-\(index)",
                options: ["node-\(index)"],
                delays: ["node-\(index)": 180 + index]
            )
        }
        let latencyProjection = OverviewProjection.latencyAnomaliesWithOperationCounts(
            from: groups,
            maximumCount: maximumCount
        )
        #expect(latencyProjection.rows.map(\.delay) == [1_203, 1_202, 1_201, 1_200, 1_199])
        assertBoundedTopK(
            latencyProjection.operationCounts,
            sourceCount: groups.count,
            candidateCount: groups.count,
            maximumCount: maximumCount
        )

        let rules = (0..<1_024).map { index in
            RuleViewState(
                id: "rule-\(index)",
                type: "DOMAIN",
                payload: "host-\(index).example.test",
                proxy: "proxy-\(index)",
                hitCount: index,
                missCount: index * 2
            )
        }
        let ruleProjection = OverviewProjection.ruleHitSummaryWithOperationCounts(
            from: rules,
            maximumCount: maximumCount
        )
        #expect(ruleProjection.rows.map(\.total) == [3_069, 3_066, 3_063, 3_060, 3_057])
        assertBoundedTopK(
            ruleProjection.operationCounts,
            sourceCount: rules.count,
            candidateCount: rules.count,
            maximumCount: maximumCount
        )
    }

    @Test func connectionHighlightsCancellableProjectionMatchesBoundedTopK() async throws {
        var connections = MicaPerformanceFixtures.connections(count: 2_048)
        connections[2_046].id = ""
        connections[2_047].id = ""
        let expected = OverviewProjection.topActiveConnections(
            from: connections,
            maximumCount: 5
        )

        let rows = try await OverviewProjection.topActiveConnectionsCancellable(
            from: connections,
            maximumCount: 5
        )

        #expect(rows == expected)
        #expect(rows.count == 5)
        #expect(rows[0].sourceIndex == 2_047)
        #expect(rows[1].sourceIndex == 2_046)
        #expect(rows[0].id != rows[1].id)
    }

    @Test func connectionHighlightsCancellableProjectionRejectsCancelledWork() async {
        let connections = MicaPerformanceFixtures.connections(count: 2_048)
        let projectionTask = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try await OverviewProjection.topActiveConnectionsCancellable(
                from: connections,
                maximumCount: 5
            )
        }

        do {
            _ = try await projectionTask.value
            Issue.record("Expected the cancelled projection to stop")
        } catch is CancellationError {
            // Expected control flow.
        } catch {
            Issue.record("Unexpected projection cancellation error: \(error)")
        }
    }

    @Test func topologyHighlightWorkScalesWithSelectedPathsInsteadOfWholeGraph() throws {
        let topology = ConnectionTopologyBuilder.build(
            from: MicaPerformanceFixtures.connections(count: 2_048)
        )
        let index = OverviewTopologyIndex(topology: topology)
        let selectedPath = try #require(topology.paths.last)

        let result = index.highlightWithOperationCounts(for: .path(selectedPath.id))

        #expect(index.operationCounts.nodeWriteCount == topology.nodes.count)
        #expect(index.operationCounts.edgeWriteCount == topology.edges.count)
        #expect(index.operationCounts.pathWriteCount == topology.paths.count)
        #expect(result.highlight.pathIDs == [selectedPath.id])
        #expect(result.highlight.nodeIDs == Set(selectedPath.nodeIDs))
        #expect(result.highlight.edgeIDs == Set(selectedPath.edgeIDs))
        #expect(result.highlight.paths == [selectedPath])
        #expect(result.operationCounts.selectedPathIDCount == 1)
        #expect(result.operationCounts.pathRecordLookupCount == 1)
        #expect(result.operationCounts.stageVisitCount == selectedPath.stages.count)
        #expect(result.operationCounts.edgeVisitCount == selectedPath.edgeIDs.count)
        #expect(result.operationCounts.pathRecordLookupCount < topology.paths.count)

        let cache = OverviewTopologyHighlightCache()
        let structure = OverviewTopologyStructureRequest(
            generation: UUID(uuidString: "24770C52-B9A9-45DC-9800-4A46DCE876DD")!,
            revision: 7
        )
        let cached = cache.resolve(
            structure: structure,
            selection: .path(selectedPath.id),
            index: index
        )
        let metricsFrameReuse = cache.resolve(
            structure: structure,
            selection: .path(selectedPath.id),
            index: index
        )
        #expect(cached.paths == [selectedPath])
        #expect(metricsFrameReuse.paths == [selectedPath])
        #expect(cache.statistics == OverviewTopologyHighlightCacheStatistics(
            projectionCount: 1,
            cacheHitCount: 1
        ))
        _ = cache.resolve(
            structure: OverviewTopologyStructureRequest(
                generation: structure.generation,
                revision: structure.revision + 1
            ),
            selection: .path(selectedPath.id),
            index: index
        )
        #expect(cache.statistics == OverviewTopologyHighlightCacheStatistics(
            projectionCount: 2,
            cacheHitCount: 1
        ))
    }

    @MainActor
    @Test func topologyInteractionReusesUnchangedHighlightProjection() throws {
        let topology = ConnectionTopologyBuilder.build(
            from: MicaPerformanceFixtures.connections(count: 16)
        )
        let index = OverviewTopologyIndex(topology: topology)
        let path = try #require(topology.paths.last)
        let interaction = OverviewTopologyInteractionState()
        let structure = OverviewTopologyStructureRequest(
            generation: UUID(uuidString: "7F833621-BCEC-40C4-A6B3-0FF31DDFDD1D")!,
            revision: 18
        )

        interaction.configure(structure: structure, index: index)
        #expect(interaction.statistics == OverviewTopologyHighlightCacheStatistics(
            projectionCount: 1,
            cacheHitCount: 0
        ))

        interaction.setHoveredSelection(.path(path.id))
        #expect(interaction.snapshot.activeSelection == .path(path.id))
        #expect(interaction.snapshot.isHovering)
        #expect(!interaction.snapshot.isPinned)
        #expect(interaction.snapshot.highlight.paths == [path])
        #expect(interaction.statistics == OverviewTopologyHighlightCacheStatistics(
            projectionCount: 2,
            cacheHitCount: 0
        ))

        interaction.setHoveredSelection(.path(path.id))
        #expect(interaction.statistics == OverviewTopologyHighlightCacheStatistics(
            projectionCount: 2,
            cacheHitCount: 0
        ))

        interaction.togglePinnedPath(path.id)
        #expect(interaction.snapshot.activeSelection == .path(path.id))
        #expect(!interaction.snapshot.isHovering)
        #expect(interaction.snapshot.isPinned)
        #expect(interaction.statistics == OverviewTopologyHighlightCacheStatistics(
            projectionCount: 2,
            cacheHitCount: 1
        ))

        interaction.togglePinnedPath(path.id)
        #expect(interaction.snapshot == .empty)
        #expect(interaction.statistics == OverviewTopologyHighlightCacheStatistics(
            projectionCount: 3,
            cacheHitCount: 1
        ))
    }

    @MainActor
    @Test func topologyPathNavigationPinsAndClearsSelection() throws {
        let topology = ConnectionTopologyBuilder.build(
            from: MicaPerformanceFixtures.connections(count: 6)
        )
        let paths = topology.paths
        let firstPath = try #require(paths.first)
        let lastPath = try #require(paths.last)
        let interaction = OverviewTopologyInteractionState()
        let index = OverviewTopologyIndex(topology: topology)
        let structure = OverviewTopologyStructureRequest(
            generation: UUID(uuidString: "1B3A8F9C-9F0F-4D4A-8E72-4A0E1B4E5A90")!,
            revision: 22
        )

        interaction.configure(structure: structure, index: index)
        #expect(index.pathCount == paths.count)
        #expect(index.pathID(at: paths.startIndex) == firstPath.id)
        #expect(index.pathIndex(id: lastPath.id) == paths.index(before: paths.endIndex))
        #expect(interaction.canMovePath(by: -1))
        #expect(interaction.canMovePath(by: 1))

        interaction.movePathSelection(by: 1)
        #expect(interaction.snapshot.activeSelection == .path(firstPath.id))
        #expect(interaction.snapshot.isPinned)
        #expect(!interaction.canMovePath(by: -1))

        interaction.movePathSelection(by: 1)
        #expect(interaction.snapshot.activeSelection == .path(paths[1].id))

        interaction.movePathSelection(by: paths.count)
        #expect(interaction.snapshot.activeSelection == .path(paths[1].id))

        for _ in 2..<paths.count {
            interaction.movePathSelection(by: 1)
        }
        #expect(interaction.snapshot.activeSelection == .path(lastPath.id))
        #expect(!interaction.canMovePath(by: 1))

        interaction.clearSelection()
        #expect(interaction.snapshot == .empty)
    }

    @MainActor
    @Test func topologyPresentationCacheSeparatesStructureFromMetricsAndWidth() async throws {
        let generation = UUID(uuidString: "23C2F9E6-1BFC-4C3B-97CA-EE1D15DAD3BB")!
        let connections = MicaPerformanceFixtures.connections(
            count: 2_000,
            topology: .shared
        )
        let cache = OverviewTopologyPresentationCache()
        let initialRequest = OverviewTopologyRequest(
            generation: generation,
            revision: 41,
            availableWidth: 544
        )

        let initial = try await cache.resolve(
            request: initialRequest,
            connections: connections
        )
        var metricsOnlyFrame = connections
        for index in metricsOnlyFrame.indices {
            metricsOnlyFrame[index].upload = 1_000_000 + index
            metricsOnlyFrame[index].download = 2_000_000 + index
            metricsOnlyFrame[index].uploadSpeed = 3_000_000 + index
            metricsOnlyFrame[index].downloadSpeed = 4_000_000 + index
        }
        let metricsOnly = try await cache.resolve(
            request: initialRequest,
            connections: metricsOnlyFrame
        )
        let initialAccessibilityWindow = initial.index.accessibilityWindow(
            preferredLowerBound: 1_984
        )
        let metricsOnlyAccessibilityWindow = metricsOnly.index.accessibilityWindow(
            preferredLowerBound: initialAccessibilityWindow.lowerBound
        )

        #expect(metricsOnly.topology == initial.topology)
        #expect(metricsOnly.topology.paths.count == connections.count)
        #expect(metricsOnlyAccessibilityWindow == initialAccessibilityWindow)
        #expect(cache.statistics == OverviewTopologyPresentationCache.Statistics(
            topologyBuildCount: 1,
            topologyIndexBuildCount: 1,
            layoutBuildCount: 1,
            exactRequestHitCount: 1,
            structureReuseCount: 0
        ))

        // Task 08-23 R10: this fixture has 5 columns, so the minimum column
        // step floors the graph at 732; resize above the floor to keep
        // exercising width-following re-layout.
        let resizedRequest = OverviewTopologyRequest(
            generation: generation,
            revision: 41,
            availableWidth: 768
        )
        let resized = try await cache.resolve(
            request: resizedRequest,
            connections: metricsOnlyFrame
        )
        #expect(resized.topology == initial.topology)
        #expect(resized.layout.size.width == 768)
        #expect(cache.statistics == OverviewTopologyPresentationCache.Statistics(
            topologyBuildCount: 1,
            topologyIndexBuildCount: 1,
            layoutBuildCount: 2,
            exactRequestHitCount: 1,
            structureReuseCount: 1
        ))

        let structureChangedConnections = metricsOnlyFrame + [
            ConnectionSnapshot(
                id: "structure-change",
                chains: ["DIRECT"],
                metadata: ConnectionMetadataSnapshot(sourceIP: "203.0.113.250")
            ),
        ]
        let structureChangedRequest = OverviewTopologyRequest(
            generation: generation,
            revision: 42,
            availableWidth: 608
        )
        let structureChanged = try await cache.resolve(
            request: structureChangedRequest,
            connections: structureChangedConnections
        )
        #expect(structureChanged.topology.paths.count == structureChangedConnections.count)
        #expect(cache.statistics == OverviewTopologyPresentationCache.Statistics(
            topologyBuildCount: 2,
            topologyIndexBuildCount: 2,
            layoutBuildCount: 3,
            exactRequestHitCount: 1,
            structureReuseCount: 1
        ))
    }

    @MainActor
    @Test func topologyPresentationStaysVisibleUntilSameSessionReplacementIsReady() async throws {
        let generation = UUID(uuidString: "D831B5A9-0D50-46E0-BDFD-EA6B5410319C")!
        let cache = OverviewTopologyPresentationCache()
        let presentation = try await cache.resolve(
            request: OverviewTopologyRequest(
                generation: generation,
                revision: 8,
                availableWidth: 544
            ),
            connections: MicaPerformanceFixtures.connections(count: 8)
        )

        #expect(
            presentation.canRemainVisible(
                whileResolving: OverviewTopologyRequest(
                    generation: generation,
                    revision: 9,
                    availableWidth: 608
                )
            )
        )
        #expect(
            !presentation.canRemainVisible(
                whileResolving: OverviewTopologyRequest(
                    generation: generation,
                    revision: 9,
                    availableWidth: 480
                )
            )
        )
        #expect(
            !presentation.canRemainVisible(
                whileResolving: OverviewTopologyRequest(
                    generation: UUID(
                        uuidString: "E37C903E-29AE-492B-A8F3-1C9A2D75FF70"
                    )!,
                    revision: 1,
                    availableWidth: 608
                )
            )
        )
    }

    @Test func topologyHeightReservationCollapsesOnlyResolvedEmptyContent() {
        #expect(
            OverviewTopologyHeightReservation.minimumHeight(
                visibleTopologyIsEmpty: nil,
                requestedMinimum: 920
            ) == 920
        )
        #expect(
            OverviewTopologyHeightReservation.minimumHeight(
                visibleTopologyIsEmpty: false,
                requestedMinimum: 920
            ) == 920
        )
        #expect(
            OverviewTopologyHeightReservation.minimumHeight(
                visibleTopologyIsEmpty: true,
                requestedMinimum: 920
            ) == nil
        )
    }

    @Test func topologyHitTestingUsesBoundedSegmentsAndLocalCandidates() async throws {
        let topology = Self.diagonalTopology()
        let layout = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: topology,
            availableWidth: 520
        )
        let edge = try #require(layout.edges.first)

        #expect(layout.operationCounts.edgeHitSegmentCount >= layout.edges.count)
        #expect(layout.operationCounts.edgeHitSegmentCount <= layout.edges.count * 8)
        for progress in [CGFloat(0.19), 0.43, 0.81] {
            #expect(layout.hitTest(at: edge.point(at: progress)) == .edge(edge.edge.id))
        }
        #expect(
            layout.hitTest(
                at: CGPoint(x: edge.hitRect.minX + 1, y: edge.hitRect.minY + 1)
            ) != .edge(edge.edge.id)
        )

        let fanTopology = ConnectionTopologyBuilder.build(
            from: (0..<128).map { index in
                ConnectionSnapshot(
                    id: "fan-\(index)",
                    chains: ["DIRECT"],
                    metadata: ConnectionMetadataSnapshot(sourceIP: "source-\(index)")
                )
            }
        )
        let fanLayout = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: fanTopology,
            availableWidth: 520
        )
        #expect(fanLayout.size.width == 520)
        #expect(fanLayout.size.height > 320)
        #expect(
            fanLayout.nodes.allSatisfy {
                $0.rect.minX >= 0 && $0.rect.maxX <= fanLayout.size.width
            }
        )
        let fanEdge = try #require(fanLayout.edges.last)
        let hit = fanLayout.hitTestWithOperationCounts(at: fanEdge.point(at: 0.25))
        #expect(hit.selection == .edge(fanEdge.edge.id))
        #expect(hit.operationCounts.shapeCheckCount <= hit.operationCounts.indexedTargetCount)
        #expect(hit.operationCounts.shapeCheckCount < fanLayout.edges.count)
        #expect(
            hit.operationCounts.indexedTargetCount
                < fanLayout.operationCounts.hitIndexEntryCount
        )
    }

    @Test func topologyViewportTargetsNodesEdgesAndPolicyFirstPaths() async throws {
        let topology = ConnectionTopologyBuilder.build(
            from: MicaPerformanceFixtures.connections(count: 6, topology: .shared)
        )
        let index = OverviewTopologyIndex(topology: topology)
        let layout = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: topology,
            availableWidth: 420
        )
        let node = try #require(topology.nodes.first)
        let edge = try #require(topology.edges.first)
        let path = try #require(
            topology.paths.first { path in
                path.stages.contains { stage in
                    if case .policyHop = stage.columnID { return true }
                    return false
                }
            }
        )
        let policyStage = try #require(
            path.stages.first { stage in
                if case .policyHop = stage.columnID { return true }
                return false
            }
        )

        let nodeTarget = try #require(
            OverviewTopologyViewportTargetResolver.target(
                for: .node(node.id),
                index: index,
                layout: layout
            )
        )
        #expect(nodeTarget.id == .node(node.id))
        #expect(nodeTarget.centerX == layout.nodeGeometry(id: node.id)?.rect.midX)

        let edgeTarget = try #require(
            OverviewTopologyViewportTargetResolver.target(
                for: .edge(edge.id),
                index: index,
                layout: layout
            )
        )
        let sourceX = try #require(layout.nodeGeometry(id: edge.sourceID)?.rect.midX)
        let targetX = try #require(layout.nodeGeometry(id: edge.targetID)?.rect.midX)
        #expect(edgeTarget.id == .edge(edge.id))
        #expect(edgeTarget.centerX == (sourceX + targetX) / 2)

        let pathTarget = try #require(
            OverviewTopologyViewportTargetResolver.target(
                for: .path(path.id),
                index: index,
                layout: layout
            )
        )
        #expect(pathTarget.id == .path(path.id))
        #expect(
            pathTarget.centerX
                == layout.nodeGeometry(id: policyStage.nodeID)?.rect.midX
        )
        #expect(
            OverviewTopologyViewportTargetResolver.target(
                for: .node("missing-node"),
                index: index,
                layout: layout
            ) == nil
        )
    }

    @Test func topologyViewportScrollsOnlyForOffscreenOverflowTargets() {
        let target = OverviewTopologyViewportTarget(
            id: .node("far-node"),
            centerX: 720
        )

        #expect(
            OverviewTopologyViewportTargetResolver.contentOffsetX(
                for: target,
                visibleRect: CGRect(x: 0, y: 0, width: 900, height: 400),
                contentWidth: 900
            ) == nil
        )
        #expect(
            OverviewTopologyViewportTargetResolver.contentOffsetX(
                for: target,
                visibleRect: CGRect(x: 500, y: 0, width: 300, height: 400),
                contentWidth: 900
            ) == nil
        )
        #expect(
            OverviewTopologyViewportTargetResolver.contentOffsetX(
                for: target,
                visibleRect: CGRect(x: 0, y: 0, width: 300, height: 400),
                contentWidth: 900
            ) == 570
        )

        let leadingTarget = OverviewTopologyViewportTarget(
            id: .edge("leading-edge"),
            centerX: 40
        )
        #expect(
            OverviewTopologyViewportTargetResolver.contentOffsetX(
                for: leadingTarget,
                visibleRect: CGRect(x: 500, y: 0, width: 300, height: 400),
                contentWidth: 900
            ) == 0
        )
    }

    @Test func topologyLayoutUsesZashboardSankeyScaleOrderingAndBands() async throws {
        let connections = (0..<9).map { index in
            ConnectionSnapshot(
                id: "source-b-\(index)",
                chains: ["DIRECT"],
                metadata: ConnectionMetadataSnapshot(sourceIP: "Source B")
            )
        } + [
            ConnectionSnapshot(
                id: "source-a",
                chains: ["DIRECT"],
                metadata: ConnectionMetadataSnapshot(sourceIP: "Source A")
            ),
        ]
        let topology = ConnectionTopologyBuilder.build(from: connections)
        let layout = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: topology,
            availableWidth: 520
        )

        let sourceNodes = layout.nodes.filter {
            $0.node.columnID == .source
        }
        #expect(sourceNodes.map(\.node.name) == ["Source A", "Source B"])
        #expect(sourceNodes.allSatisfy { $0.rect.width == 20 })
        #expect(OverviewTopologyLayout.columnHeaderHeight == 40)
        #expect(
            layout.nodes.allSatisfy {
                $0.rect.minY >= OverviewTopologyLayout.columnHeaderHeight
                    + 12
            }
        )

        let sourceA = try #require(
            sourceNodes.first { $0.node.name == "Source A" }
        )
        let sourceB = try #require(
            sourceNodes.first { $0.node.name == "Source B" }
        )
        #expect(layout.nodeGeometry(id: sourceA.node.id)?.rect == sourceA.rect)
        #expect(layout.nodeGeometry(id: sourceB.node.id)?.rect == sourceB.rect)
        #expect(layout.nodeGeometry(id: "missing-node") == nil)
        let edgeA = try #require(
            layout.edges.first { $0.edge.sourceName == "Source A" }
        )
        let edgeB = try #require(
            layout.edges.first { $0.edge.sourceName == "Source B" }
        )

        let oneConnectionValue = OverviewTopologyFlowScale.value(
            forConnectionCount: 1
        )
        let nineConnectionValue = OverviewTopologyFlowScale.value(
            forConnectionCount: 9
        )
        let ninetyNineConnectionValue = OverviewTopologyFlowScale.value(
            forConnectionCount: 99
        )
        #expect(abs(oneConnectionValue - 3.010_299_956_6) < 0.000_001)
        #expect(abs(nineConnectionValue - 10) < 0.000_001)
        #expect(abs(ninetyNineConnectionValue - 20) < 0.000_001)
        #expect(
            abs(
                sourceB.rect.height / sourceA.rect.height
                    - nineConnectionValue / oneConnectionValue
            ) < 0.000_1
        )
        #expect(
            abs(
                edgeB.width / edgeA.width
                    - nineConnectionValue / oneConnectionValue
            ) < 0.000_1
        )
        #expect(
            abs(edgeA.target.y - edgeB.target.y)
                >= (edgeA.width + edgeB.width) / 2 - 0.001
        )
        #expect(edgeA.drawingPath.boundingRect.height >= edgeA.width)
        #expect(edgeB.drawingPath.boundingRect.height >= edgeB.width)
        #expect(layout.size.width == 520)

        let expanded = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: topology,
            availableWidth: 520,
            minimumFlowHeight: 640
        )
        #expect(expanded.size.height >= 724)
    }

    @Test func topologyRenderBandsAndAccessibilityCoverCompleteTopology() async throws {
        var connections = MicaPerformanceFixtures.connections(
            count: 2_000,
            topology: .shared
        )
        connections.append(
            ConnectionSnapshot(
                id: "route-unavailable",
                chains: nil,
                metadata: ConnectionMetadataSnapshot(sourceIP: "203.0.113.251")
            )
        )
        let topology = ConnectionTopologyBuilder.build(from: connections)
        let index = OverviewTopologyIndex(topology: topology)
        let layout = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: topology,
            availableWidth: 544
        )

        #expect(topology.paths.count == connections.count)
        #expect(topology.paths.map(\.sourceIndex) == Array(connections.indices))
        #expect(topology.routeUnavailableCount == 1)
        #expect(layout.renderBands.count > 1)
        #expect(layout.renderBands.first?.bounds.minY == 0)
        #expect(layout.renderBands.last?.bounds.maxY == layout.size.height)

        for (current, next) in zip(
            layout.renderBands,
            layout.renderBands.dropFirst()
        ) {
            #expect(current.bounds.maxY == next.bounds.minY)
        }

        let admittedNodeIDs = Set(
            layout.renderBands.flatMap { band in
                band.nodes.map(\.node.id)
            }
        )
        let admittedEdgeIDs = Set(
            layout.renderBands.flatMap { band in
                band.edges.map(\.edge.id)
            }
        )
        #expect(admittedNodeIDs == Set(layout.nodes.map(\.node.id)))
        #expect(admittedEdgeIDs == Set(layout.edges.map(\.edge.id)))
        let nodeOrder = Dictionary(
            uniqueKeysWithValues: layout.nodes.enumerated().map {
                ($0.element.node.id, $0.offset)
            }
        )
        let edgeOrder = Dictionary(
            uniqueKeysWithValues: layout.edges.enumerated().map {
                ($0.element.edge.id, $0.offset)
            }
        )
        for band in layout.renderBands {
            let nodeIndices = band.nodes.compactMap { nodeOrder[$0.node.id] }
            let edgeIndices = band.edges.compactMap { edgeOrder[$0.edge.id] }
            #expect(nodeIndices == nodeIndices.sorted())
            #expect(edgeIndices == edgeIndices.sorted())
        }
        #expect(layout.renderBands.first?.columns.map(\.id) == layout.columns.map(\.id))
        #expect(layout.renderBands.dropFirst().allSatisfy { $0.columns.isEmpty })
        #expect(
            layout.operationCounts.renderBandNodeAdmissionCount
                == layout.renderBands.reduce(0) { $0 + $1.nodes.count }
        )
        #expect(
            layout.operationCounts.renderBandEdgeAdmissionCount
                == layout.renderBands.reduce(0) { $0 + $1.edges.count }
        )

        var accessiblePathIndices: [Int] = []
        var accessibilityWindow = index.accessibilityWindow()
        while true {
            #expect(accessibilityWindow.range.count <= WorkbenchAccessibilityWindow.capacity)
            accessiblePathIndices.append(contentsOf: accessibilityWindow.range)
            guard let nextLowerBound = accessibilityWindow.nextLowerBound else { break }
            accessibilityWindow = index.accessibilityWindow(
                preferredLowerBound: nextLowerBound
            )
        }
        #expect(accessiblePathIndices == Array(topology.paths.indices))
        #expect(accessibilityWindow.pageNumber == accessibilityWindow.pageCount)

        while let previousLowerBound = accessibilityWindow.previousLowerBound {
            accessibilityWindow = index.accessibilityWindow(
                preferredLowerBound: previousLowerBound
            )
        }
        #expect(accessibilityWindow.range == 0..<WorkbenchAccessibilityWindow.capacity)

        let selectedPath = try #require(topology.paths.last)
        let selectedWindow = index.accessibilityWindow(
            revealing: selectedPath.id
        )
        let selectedIndex = try #require(index.pathIndex(id: selectedPath.id))
        #expect(selectedWindow.range.contains(selectedIndex))
        #expect(selectedWindow.range.count <= WorkbenchAccessibilityWindow.capacity)

        let edge = try #require(layout.edges.first)
        let hit = layout.hitTestWithOperationCounts(at: edge.point(at: 0.5))
        #expect(hit.selection != nil)
        #expect(hit.operationCounts.shapeCheckCount <= hit.operationCounts.indexedTargetCount)
        #expect(hit.operationCounts.indexedTargetCount < connections.count)
    }

    @Test func topologyAccessibilityPolicyNodeWindowTraversesAndRevealsSelection() throws {
        let connections = (0..<96).map { index in
            ConnectionSnapshot(
                id: "accessibility-policy-\(index)",
                chains: ["outbound-\(index)", "policy-\(index)"],
                metadata: ConnectionMetadataSnapshot(
                    sourceIP: "192.0.2.\((index % 250) + 1)"
                )
            )
        }
        let topology = ConnectionTopologyBuilder.build(
            from: connections
        )
        let index = OverviewTopologyIndex(topology: topology)
        let expectedPolicyNodes = topology.nodes.filter { node in
            if case .policyHop = node.columnID {
                true
            } else {
                false
            }
        }
        #expect(expectedPolicyNodes.count > WorkbenchAccessibilityWindow.capacity)

        var accessibleNodeIDs: [String] = []
        var window = index.accessibilityPolicyNodeWindow()
        while true {
            #expect(window.range.count <= WorkbenchAccessibilityWindow.capacity)
            accessibleNodeIDs.append(
                contentsOf: index.accessibilityPolicyNodes(in: window.range).map(\.id)
            )
            guard let nextLowerBound = window.nextLowerBound else { break }
            window = index.accessibilityPolicyNodeWindow(
                preferredLowerBound: nextLowerBound
            )
        }
        #expect(accessibleNodeIDs == expectedPolicyNodes.map(\.id))
        #expect(window.pageNumber == window.pageCount)

        while let previousLowerBound = window.previousLowerBound {
            window = index.accessibilityPolicyNodeWindow(
                preferredLowerBound: previousLowerBound
            )
        }
        #expect(window.lowerBound == 0)

        let selectedNode = try #require(expectedPolicyNodes.last)
        let selectedWindow = index.accessibilityPolicyNodeWindow(
            revealing: selectedNode.id
        )
        let selectedIndex = try #require(
            expectedPolicyNodes.firstIndex { $0.id == selectedNode.id }
        )
        #expect(selectedWindow.range.contains(selectedIndex))
        #expect(selectedWindow.range.count <= WorkbenchAccessibilityWindow.capacity)
    }

    @Test func overviewSourceSeparatesVerticalAndInteractionOwnership() throws {
        let dashboardSource = try workbenchSource(named: "WorkbenchDashboard.swift")
        let editorSource = try workbenchSource(named: "WorkbenchOverviewEditor.swift")
        let preferencesSource = try workbenchSource(
            named: "WorkbenchOverviewPreferences.swift"
        )
        let runtimeSource = try workbenchSource(
            named: "WorkbenchOverviewWindowRuntime.swift"
        )
        let telemetrySource = try workbenchSource(
            named: "WorkbenchOverviewTelemetry.swift"
        )
        let topologySource = try workbenchSource(
            named: "WorkbenchOverviewTopology.swift"
        )
        let topologyViewSource = try workbenchSource(
            named: "WorkbenchOverviewTopologyView.swift"
        )
        let source = [
            dashboardSource,
            editorSource,
            preferencesSource,
            runtimeSource,
            telemetrySource,
            topologySource,
            topologyViewSource,
        ].joined(separator: "\n")

        let fixedCanvas = try sourceSection(
            dashboardSource,
            from: "private struct OverviewFixedCanvas",
            to: "struct OverviewSymbolMark"
        )
        #expect(occurrenceCount(of: "ScrollView {", in: fixedCanvas) == 1)
        #expect(fixedCanvas.contains("LazyVStack(alignment: .leading"))
        #expect(fixedCanvas.contains("OverviewTelemetrySection("))
        #expect(fixedCanvas.contains("OverviewTopologySection("))
        #expect(fixedCanvas.contains("ForEach(visibleOptionalModules)"))
        #expect(fixedCanvas.contains(".micaObserveScrollPerformance()"))
        let telemetryPosition = try #require(
            fixedCanvas.range(of: "OverviewTelemetrySection(")
        )
        let topologyPosition = try #require(
            fixedCanvas.range(of: "OverviewTopologySection(")
        )
        let optionalPosition = try #require(
            fixedCanvas.range(of: "ForEach(visibleOptionalModules)")
        )
        #expect(telemetryPosition.lowerBound < topologyPosition.lowerBound)
        #expect(topologyPosition.lowerBound < optionalPosition.lowerBound)

        #expect(preferencesSource.contains("struct OverviewPreferences"))
        #expect(preferencesSource.contains("final class OverviewPreferencesStore"))
        #expect(preferencesSource.contains("mica.overview.fixed-core.v1"))
        #expect(preferencesSource.contains("visibleMetrics"))
        #expect(preferencesSource.contains("timelineWindow"))
        #expect(preferencesSource.contains("visibleOptionalModules"))
        #expect(runtimeSource.contains("final class OverviewWindowRuntime"))
        #expect(runtimeSource.contains("let liveSessionWindowDemandID"))
        #expect(runtimeSource.contains("let registry = OverviewRuntimeRegistry()"))

        #expect(editorSource.contains("struct OverviewPreferencesBar"))
        #expect(editorSource.contains("ForEach(OverviewMetricID.allCases)"))
        #expect(editorSource.contains("ForEach(OverviewOptionalModuleID.allCases)"))
        #expect(editorSource.contains("store.setTimelineWindow"))
        #expect(editorSource.contains("store.reset()"))
        #expect(!editorSource.contains("UndoManager"))
        #expect(!editorSource.contains("DropDelegate"))

        let telemetrySection = try sourceSection(
            telemetrySource,
            from: "struct OverviewTelemetrySection",
            to: "private enum OverviewTelemetryControlsLayout"
        )
        #expect(telemetrySection.contains("visibleMetrics"))
        #expect(telemetrySection.contains("OverviewMetricID.allCases.filter"))
        #expect(telemetrySection.contains(".micaPanel("))
        #expect(telemetrySection.contains("ViewThatFits(in: .horizontal)"))
        #expect(telemetrySection.contains("return min(max(panelWidth * 0.60, 240), 300)"))
        #expect(telemetrySource.contains("OverviewLatestDataMark("))
        #expect(telemetrySource.contains("PointMark("))
        #expect(telemetrySource.contains("AreaPlot("))
        #expect(telemetrySource.contains("LinePlot("))
        #expect(telemetrySource.contains("controlActiveState != .inactive"))

        let topologyViewport = try sourceSection(
            topologyViewSource,
            from: "private struct OverviewTopologyViewport",
            to: "private struct OverviewTopologyIdleSummary")
        #expect(topologyViewport.contains("LazyVStack"))
        #expect(topologyViewport.contains("ScrollView(.horizontal)"))
        #expect(topologyViewport.contains(".scrollPosition($scrollPosition)"))
        #expect(topologyViewport.contains("hasHorizontalOverflow ? .visible : .hidden"))
        #expect(topologyViewport.contains("if reduceMotion"))
        #expect(topologyViewport.contains("MicaTheme.surface"))
        #expect(topologyViewport.contains(".help(hoverTooltip"))
        #expect(topologyViewport.contains(".onMoveCommand(perform: movePathSelection)"))
        #expect(topologyViewport.contains(".onExitCommand"))
        #expect(topologyViewport.contains(".contextMenu"))

        #expect(!topologyViewSource.contains("OverviewTopologyHUDOverlay"))
        #expect(!topologyViewSource.contains("OverviewHolographicHUD"))
        #expect(!topologyViewSource.contains("OverviewPolicyHUDPlacementResolver"))
        #expect(topologyViewSource.contains("workspaceStore.selectInspector("))
        #expect(topologyViewSource.contains("revision: appModel.policyGroupCatalogRevision"))
        #expect(topologyViewSource.contains("catalog: appModel.policyGroupCatalog"))
        #expect(topologyViewSource.contains("interaction.clearSelection"))

        let bandLayers = try sourceSection(
            topologyViewSource,
            from: "private struct OverviewTopologyBandLayers",
            to: "private struct OverviewTopologyBaseBand"
        )
        #expect(bandLayers.contains("allowsMotion: allowsMotion"))
        #expect(bandLayers.contains("policyStatusRevision == rhs.policyStatusRevision"))
        #expect(!bandLayers.contains("nodeStatusByID == rhs.nodeStatusByID"))
        #expect(topologyViewSource.contains("revision: visibleInput.catalogRevision"))
        // Task 08-20: the highlight overlay + second Canvas merged into the
        // single opaque/linear base canvas; labels render in a dedicated layer.
        let baseBand = try sourceSection(
            topologyViewSource,
            from: "private struct OverviewTopologyBaseBand",
            to: "private struct OverviewTopologyLabelBand"
        )
        #expect(baseBand.contains("opaque: true"))
        #expect(baseBand.contains("colorMode: .linear"))
        #expect(baseBand.contains("allowsMotion ? MicaTheme.Motion.stateChange : nil"))
        #expect(baseBand.contains("value: snapshot.activeSelection"))
        #expect(!topologyViewSource.contains("OverviewTopologyHighlightBand"))
        #expect(!topologyViewSource.contains("TimelineView"))

        #expect(topologySource.contains("private let nodeGeometryByID"))
        #expect(topologySource.contains("func nodeGeometry(id: String)"))
        #expect(topologySource.contains("OverviewTopologyLayout.columnHeaderHeight + 12"))
        #expect(!source.contains("TimelineView"))
        #expect(!source.contains(".glassEffect"))
        #expect(!source.contains("GlassEffectContainer"))

        let topologyAccessibility = try sourceSection(
            topologyViewSource,
            from: "private struct OverviewTopologyAccessibilityRepresentation",
            to: "private enum OverviewTopologyDrawing"
        )
        #expect(topologyAccessibility.contains("OverviewTopologyAccessibilityNodes("))
        #expect(topologyAccessibility.contains("ForEach(nodes)"))
        #expect(topologyAccessibility.contains("ForEach(paths[pathRange])"))
        #expect(topologyAccessibility.contains("topologyIndex.accessibilityPolicyNodes("))
        #expect(topologyAccessibility.contains("pathRange: pathWindow.range"))
        #expect(topologyAccessibility.contains("WorkbenchAccessibilityPageControls("))
        #expect(topologyAccessibility.contains(".onChange(of: interaction.snapshot)"))
        #expect(topologyAccessibility.contains("guard snapshot.isPinned else { return }"))
        #expect(!topologyAccessibility.contains("nodes.filter"))
        #expect(!topologyAccessibility.contains("ForEach(groups)"))
        #expect(!topologyAccessibility.contains("LazyVStack"))
        #expect(topologyAccessibility.contains(".accessibilityAddTraits(isPinned ? .isSelected : [])"))
        #expect(topologyViewSource.contains("OverviewTopologyPathRows("))
        #expect(topologyViewSource.contains(".accessibilityHidden(true)"))
    }

    @Test func overviewRouteOwnsTheOnlyOverviewViewInstantiation() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workspaceURL = repositoryRoot.appending(
            path: "Sources/Mica/Features/Workbench/WorkbenchWorkspaceView.swift"
        )
        let source = try String(contentsOf: workspaceURL, encoding: .utf8)
        let contentStart = try #require(source.range(of: "private var content: some View"))
        let contentEnd = try #require(
            source.range(of: "private var searchText", range: contentStart.upperBound..<source.endIndex)
        )
        let content = String(source[contentStart.lowerBound..<contentEnd.lowerBound])
        let overviewCase = try #require(content.range(of: "case .overview:"))
        let overviewView = try #require(content.range(of: "WorkbenchOverviewView("))
        let proxiesCase = try #require(content.range(of: "case .proxies:"))

        #expect(content.components(separatedBy: "WorkbenchOverviewView(").count - 1 == 1)
        #expect(overviewCase.lowerBound < overviewView.lowerBound)
        #expect(overviewView.lowerBound < proxiesCase.lowerBound)

        let topologyViewURL = repositoryRoot.appending(
            path: "Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift"
        )
        let topologyViewSource = try String(contentsOf: topologyViewURL, encoding: .utf8)
        let topologyCallStart = try #require(
            topologyViewSource.range(of: "OverviewTopologyWorkspace(")
        )
        let topologyTypeStart = try #require(
            topologyViewSource.range(
                of: "private struct OverviewTopologyWorkspace",
                range: topologyCallStart.upperBound..<topologyViewSource.endIndex
            )
        )
        let topologyCall = String(
            topologyViewSource[topologyCallStart.lowerBound..<topologyTypeStart.lowerBound]
        )
        #expect(topologyCall.contains("revision: visibleInput.catalogRevision"))
        #expect(!topologyCall.contains("metricsRevision"))
        #expect(!topologyCall.contains("trafficRevision"))

        let topologySectionBody = try sourceSection(
            topologyViewSource,
            from: "var body: some View {",
            to: "@MainActor\n    private func loadStructureInput"
        )
        #expect(topologySectionBody.contains("OverviewTopologyCatalogRequest.observing(appModel)"))
        #expect(topologySectionBody.contains(".task(id: request)"))
        #expect(!topologySectionBody.contains("connectionsCatalog"))
        #expect(topologyViewSource.contains("structureRevision: appModel.connectionsStructureRevision"))
        #expect(topologyViewSource.contains("let catalog = appModel.connectionsCatalog"))
    }

    @Test func overviewHighlightsStageExactNavigationBeforeChangingDestination() throws {
        let dashboard = try workbenchSource(named: "WorkbenchDashboard.swift")
        let projection = try workbenchSource(named: "WorkbenchOverviewProjection.swift")
        let latencySection = try sourceSection(
            dashboard,
            from: "private struct OverviewLatencyHighlightsSection",
            to: "private struct OverviewRuleHighlightsSection"
        )
        let ruleSection = try sourceSection(
            dashboard,
            from: "private struct OverviewRuleHighlightsSection",
            to: "private struct OverviewConnectionHighlightsSection"
        )
        let connectionSection = try sourceSection(
            dashboard,
            from: "private struct OverviewConnectionHighlightsSection",
            to: "private struct OverviewConnectionHighlightsLoader"
        )

        #expect(latencySection.contains("workspaceStore.stageProxyNavigation("))
        #expect(latencySection.contains("groupOccurrenceID: row.groupOccurrenceID"))
        #expect(latencySection.contains("nodeName: row.nodeName"))
        let proxyStage = try #require(
            latencySection.range(of: "workspaceStore.stageProxyNavigation(")
        )
        let proxyDestination = try #require(
            latencySection.range(of: "destination = .proxies")
        )
        #expect(proxyStage.lowerBound < proxyDestination.lowerBound)

        #expect(ruleSection.contains("workspaceStore.stageRuleNavigation("))
        for exactField in [
            "sourceIndex: row.sourceIndex",
            "reportedRuleID: row.reportedRuleID",
            "type: row.type",
            "payload: row.payload",
        ] {
            #expect(ruleSection.contains(exactField))
        }
        let ruleStage = try #require(
            ruleSection.range(of: "workspaceStore.stageRuleNavigation(")
        )
        let ruleDestination = try #require(
            ruleSection.range(of: "destination = .rules")
        )
        #expect(ruleStage.lowerBound < ruleDestination.lowerBound)

        #expect(connectionSection.contains("workspaceStore.stageConnectionNavigation("))
        #expect(connectionSection.contains("openConnection(row, scope: visiblePresentation.scope)"))
        #expect(connectionSection.contains("scope.navigationSelection("))
        #expect(connectionSection.contains("currentScope: OverviewConnectionHighlightsScope.observing(appModel)"))
        let connectionStage = try #require(
            connectionSection.range(of: "workspaceStore.stageConnectionNavigation(")
        )
        let connectionDestination = try #require(
            connectionSection.range(of: "destination = .connections")
        )
        #expect(connectionStage.lowerBound < connectionDestination.lowerBound)

        #expect(projection.contains("ProxyGroupKey("))
        #expect(projection.contains("groupOccurrenceID:"))
    }

    @Test func connectionHighlightsKeepFullCatalogWorkOutsideSwiftUIBodies() throws {
        let dashboard = try workbenchSource(named: "WorkbenchDashboard.swift")
        let projection = try workbenchSource(named: "WorkbenchOverviewProjection.swift")
        let section = try sourceSection(
            dashboard,
            from: "private struct OverviewConnectionHighlightsSection",
            to: "private struct OverviewConnectionHighlightsLoader"
        )
        let loader = try sourceSection(
            dashboard,
            from: "private struct OverviewConnectionHighlightsLoader",
            to: "struct OverviewConnectionHighlightsScope"
        )
        let loaderBody = try sourceSection(
            loader,
            from: "var body: some View {",
            to: "@MainActor\n    private func rebuildPresentation"
        )
        let request = try sourceSection(
            dashboard,
            from: "struct OverviewConnectionHighlightsRequest",
            to: "struct OverviewConnectionHighlightsPresentation"
        )

        #expect(section.contains("OverviewConnectionHighlightsScope.observing(appModel)"))
        #expect(section.contains("presentation?.visible(for: scope)"))
        #expect(!section.contains("connectionsCatalog"))
        #expect(!section.contains("OverviewProjection.topActiveConnections"))

        #expect(loaderBody.contains("OverviewConnectionHighlightsRequest.observing("))
        #expect(loaderBody.contains(".task(id: request)"))
        #expect(!loaderBody.contains("connectionsCatalog.connections"))
        #expect(!loaderBody.contains("OverviewProjection.topActiveConnections"))
        #expect(loader.contains("let connections = appModel.connectionsCatalog.connections"))
        #expect(!loader.contains("Task.detached"))
        #expect(loader.contains("OverviewProjection.topActiveConnectionsCancellable("))
        #expect(loader.contains("guard presentation != nextPresentation else { return }"))
        #expect(request.contains("metricsRevision: appModel.connectionsMetricsRevision"))
        #expect(!request.contains("connectionsCatalog"))
        #expect(projection.contains("@concurrent\n    static func topActiveConnectionsCancellable("))
        #expect(projection.contains("try Task.checkCancellation()"))
        #expect(projection.contains("checksCancellation: true"))
        #expect(projection.contains("Task<Never, Never>.isCancelled"))
    }

    private func workbenchSource(named fileName: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appending(
            path: "Sources/Mica/Features/Workbench/\(fileName)"
        )
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func sourceSection(
        _ source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> String {
        let start = try #require(source.range(of: startMarker))
        let end = try #require(
            source.range(
                of: endMarker,
                range: start.upperBound..<source.endIndex
            )
        )
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func sourceSuffix(
        _ source: String,
        from startMarker: String
    ) throws -> String {
        let start = try #require(source.range(of: startMarker))
        return String(source[start.lowerBound...])
    }

    private func occurrenceCount(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    private func assertBoundedTopK(
        _ counts: OverviewTopKOperationCounts,
        sourceCount: Int,
        candidateCount: Int,
        maximumCount: Int
    ) {
        #expect(counts.scannedCount == sourceCount)
        #expect(counts.candidateCount == candidateCount)
        #expect(counts.maximumRetainedCount <= maximumCount)
        #expect(counts.comparisonCount <= candidateCount * maximumCount)
    }

    private static func diagonalTopology() -> ConnectionTopology {
        let pathID = ConnectionTopology.ConnectionOccurrenceID(
            reportedID: "diagonal",
            occurrence: 0
        )
        let source = ConnectionTopology.Node(
            id: "source",
            columnID: .source,
            name: "Source",
            pathIDs: [pathID]
        )
        let paddingNodes = (0..<20).map { index in
            ConnectionTopology.Node(
                id: "padding-\(index)",
                columnID: .finalOutbound,
                name: "Padding \(index)",
                pathIDs: []
            )
        }
        let target = ConnectionTopology.Node(
            id: "target",
            columnID: .finalOutbound,
            name: "Target",
            pathIDs: [pathID]
        )
        let edge = ConnectionTopology.Edge(
            id: "source-target",
            sourceID: source.id,
            targetID: target.id,
            sourceName: source.name,
            targetName: target.name,
            sourceColumnID: source.columnID,
            targetColumnID: target.columnID,
            pathIDs: [pathID]
        )
        let path = ConnectionTopology.PathRecord(
            id: pathID,
            sourceIndex: 0,
            reportedConnectionID: "diagonal",
            stages: [
                ConnectionTopology.Stage(
                    nodeID: source.id,
                    columnID: source.columnID,
                    name: source.name
                ),
                ConnectionTopology.Stage(
                    nodeID: target.id,
                    columnID: target.columnID,
                    name: target.name
                ),
            ],
            edgeIDs: [edge.id],
            routeState: .available
        )
        return ConnectionTopology(
            columns: [
                ConnectionTopology.Column(id: .source, nodes: [source]),
                ConnectionTopology.Column(
                    id: .finalOutbound,
                    nodes: paddingNodes + [target]
                ),
            ],
            edges: [edge],
            paths: [path]
        )
    }
}
