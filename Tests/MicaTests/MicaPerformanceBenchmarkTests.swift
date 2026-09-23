import Foundation
import MicaCore
import Testing
@testable import Mica

@Suite(.serialized)
struct MicaPerformanceBenchmarkTests {
    private struct BenchmarkCase: Codable, Sendable {
        let name: String
        let fixtureCount: Int
        let samples: Int
        let medianMilliseconds: Double
        let p95Milliseconds: Double
        let minimumMilliseconds: Double
        let maximumMilliseconds: Double
        let checksum: Int
        let reportedWorkUnits: Int?
    }

    private struct BenchmarkReport: Codable {
        let schemaVersion: Int
        let label: String
        let generatedAt: Date
        let buildConfiguration: String
        let swiftVersion: String
        let operatingSystem: String
        let limitations: [String]
        let cases: [BenchmarkCase]
    }

    private struct LogDeltaBenchmarkState {
        var buffer: BoundedLogBuffer
        var cache: WorkbenchLogProjectionCache
        var revision: UInt64
    }

    private struct DecodedConnectionMetricFrames {
        let initial: [ConnectionSnapshot]
        let updated: [ConnectionSnapshot]
        let changedIndex: Int
    }

    private enum BenchmarkError: Error {
        case missingOutputPath
    }

    private static func decodedConnectionMetricFrames(
        connectionCount: Int
    ) throws -> DecodedConnectionMetricFrames {
        precondition(connectionCount > 0)

        var source = MicaPerformanceFixtures.connections(count: connectionCount)
        for index in source.indices {
            source[index].fields["controller-extra"] = .object([
                "sequence": .number(Double(index)),
                "stable": .bool(true),
            ])
        }

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let initial = try decoder.decode(
            [ConnectionSnapshot].self,
            from: encoder.encode(source)
        )
        let changedIndex = connectionCount / 2
        var updatedSource = initial
        updatedSource[changedIndex].upload = (updatedSource[changedIndex].upload ?? 0) + 101
        updatedSource[changedIndex].download = (updatedSource[changedIndex].download ?? 0) + 103
        updatedSource[changedIndex].uploadSpeed =
            (updatedSource[changedIndex].uploadSpeed ?? 0) + 107
        updatedSource[changedIndex].downloadSpeed =
            (updatedSource[changedIndex].downloadSpeed ?? 0) + 109
        let updated = try decoder.decode(
            [ConnectionSnapshot].self,
            from: encoder.encode(updatedSource)
        )

        return DecodedConnectionMetricFrames(
            initial: initial,
            updated: updated,
            changedIndex: changedIndex
        )
    }

    private static func projectDecodedConnectionMetricFrame(
        _ frames: DecodedConnectionMetricFrames,
        connectionCount: Int
    ) async -> (checksum: Int, workUnits: Int) {
        let identity = LiveSessionRuntimeIdentity(
            controllerID: UUID(),
            generation: UUID()
        )
        let runtime = LiveSessionRuntime(
            controllerKind: .mihomoCompatible,
            initialPresentationDemand: LiveSessionPresentationDemand(
                identity: identity,
                revision: 0,
                observedDomains: [.connections],
                presentationPaused: false,
                logsPresentationPaused: false,
                baselinePublicationRequired: false
            )
        )
        _ = await runtime.ingestMihomoConnections(
            ConnectionsResponse(
                uploadTotal: connectionCount,
                downloadTotal: connectionCount * 2,
                memory: 128 * 1_024 * 1_024,
                connections: frames.initial
            )
        )
        guard case .connections(let initialPublication) =
            await runtime.publication(for: .connections, force: true)?.payload,
              case .mihomo(let initialResponse) = initialPublication.source
        else {
            return (0, 0)
        }

        var cache = WorkbenchConnectionProjectionCache()
        cache.project(
            activeConnections: initialResponse.connections,
            closedConnections: [],
            scope: .active,
            structureRevision: initialPublication.revisions.structure,
            metricsRevision: initialPublication.revisions.metrics,
            closedRevision: 0,
            query: "",
            sortOrder: [],
            language: .english,
            change: ConnectionsCatalogChange(
                structureChanged: initialPublication.revisions.structure > 0,
                metricsChanged: initialPublication.revisions.metrics > 0,
                changedMetricIndices: initialPublication.changedMetricIndices,
                trafficChanged: initialPublication.revisions.traffic > 0
            )
        )
        let initialStaticRows = cache.staticRowProjectionCount
        let initialMetricCandidates = cache.metricsCandidateProjectionCount

        _ = await runtime.ingestMihomoConnections(
            ConnectionsResponse(
                uploadTotal: connectionCount,
                downloadTotal: connectionCount * 2,
                memory: 128 * 1_024 * 1_024,
                connections: frames.updated
            )
        )
        guard case .connections(let updatedPublication) =
            await runtime.publication(for: .connections, force: true)?.payload,
              case .mihomo(let updatedResponse) = updatedPublication.source
        else {
            return (0, 0)
        }

        cache.project(
            activeConnections: updatedResponse.connections,
            closedConnections: [],
            scope: .active,
            structureRevision: updatedPublication.revisions.structure,
            metricsRevision: updatedPublication.revisions.metrics,
            closedRevision: 0,
            query: "",
            sortOrder: [],
            language: .english,
            change: ConnectionsCatalogChange(
                structureChanged: updatedPublication.revisions.structure
                    != initialPublication.revisions.structure,
                metricsChanged: updatedPublication.revisions.metrics
                    != initialPublication.revisions.metrics,
                changedMetricIndices: updatedPublication.changedMetricIndices,
                trafficChanged: updatedPublication.revisions.traffic
                    != initialPublication.revisions.traffic
            )
        )

        let staticWork = cache.staticRowProjectionCount - initialStaticRows
        let metricCandidateWork = cache.metricsCandidateProjectionCount
            - initialMetricCandidates
        let workUnits = staticWork + metricCandidateWork
        let classifiedRows = updatedPublication.changedMetricIndices?.count
            ?? connectionCount
        let firstChangedIndex = updatedPublication.changedMetricIndices?.first
            ?? connectionCount
        let projectedUpload = cache.allRows[frames.changedIndex].connection.upload ?? 0
        let checksum = Int(updatedPublication.revisions.structure) * 100_000_000
            &+ Int(updatedPublication.revisions.metrics) * 10_000_000
            &+ classifiedRows * 10_000
            &+ firstChangedIndex
            &+ workUnits
            &+ projectedUpload
        return (checksum, workUnits)
    }

    private static func largeProxyResponseFixture(entryCount: Int) throws -> Data {
        precondition(entryCount > 0)

        var proxies: [String: Any] = [:]
        proxies.reserveCapacity(entryCount)
        for index in 0..<entryCount {
            let isGroup = index.isMultiple(of: 20)
            let name = isGroup ? "Group \(index)" : "Node \(index)"
            let nextNode = "Node \(min(index + 1, entryCount - 1))"
            let history: [[String: Any]] = [
                [
                    "time": "2026-09-02T12:00:00Z",
                    "delay": 20 + index % 180,
                    "meanDelay": 25 + index % 180,
                    "controller-detail": [
                        "samples": [1, true, NSNull(), "ok"] as [Any],
                    ],
                ],
            ]
            let controllerMetadata: [String: Any] = [
                "nested": [
                    "enabled": true,
                    "weight": index,
                    "empty": NSNull(),
                ],
                "values": [
                    "alpha",
                    42,
                    false,
                    NSNull(),
                    ["depth": [1, 2, 3]],
                ] as [Any],
            ]

            proxies[name] = [
                "type": isGroup ? "Selector" : "VLESS",
                "now": nextNode,
                "all": isGroup ? [nextNode, "DIRECT"] : [],
                "alive": index.isMultiple(of: 3),
                "history": history,
                "icon": "https://controller.example/icons/node.png",
                "testUrl": "https://controller.example/generate_204",
                "provider-name": "Provider A",
                "fixed": nextNode,
                "interface": "utun7",
                "udp": true,
                "uot": false,
                "xudp": true,
                "tfo": false,
                "mptcp": true,
                "smux": false,
                "hidden": false,
                "controller-meta": controllerMetadata,
                "scalar-number": index,
                "scalar-bool": true,
                "scalar-null": NSNull(),
            ]
        }

        return try JSONSerialization.data(
            withJSONObject: ["proxies": proxies],
            options: [.sortedKeys]
        )
    }

    private static func metadataRichPolicyCatalog(nodeCount: Int) -> PolicyGroupCatalogSnapshot {
        let names = (0..<nodeCount).map { "Node \($0)" }
        let details = Dictionary(uniqueKeysWithValues: names.enumerated().map { index, name in
            let snapshot = ProxySnapshot(
                name: name,
                type: "VLESS",
                alive: !index.isMultiple(of: 3),
                history: [
                    ProxyDelayHistorySnapshot(
                        time: "2026-09-03T00:00:\(String(format: "%02d", index % 60))Z",
                        delay: 20 + index % 1_200,
                        meanDelay: 25 + index % 1_200
                    ),
                ],
                providerName: "Provider \(index % 11)",
                interfaceName: "utun\(index % 8)",
                udp: true,
                xudp: index.isMultiple(of: 2),
                metadata: [
                    "controller-meta": .object([
                        "index": .number(Double(index)),
                        "nested": .object([
                            "enabled": .bool(true),
                            "values": .array([
                                .string("alpha"),
                                .number(Double(index % 97)),
                                .bool(index.isMultiple(of: 2)),
                                .null,
                            ]),
                        ]),
                    ]),
                    "reported-sequence": .number(Double(index)),
                ]
            )
            return (name, ProxyNodeViewState(snapshot: snapshot))
        })
        let selected = names.first ?? ""
        return PolicyGroupCatalogSnapshot(
            mode: "Rule",
            groups: [
                ProxyGroupViewState(
                    id: "Metadata Rich",
                    type: "Selector",
                    selected: selected,
                    options: names,
                    details: details[selected],
                    optionDetails: details
                ),
            ]
        )
    }

    @Test func largeProxyResponseFixtureIsValid() throws {
        let entryCount = 2_000
        let data = try Self.largeProxyResponseFixture(entryCount: entryCount)
        let response = try ProxiesResponse.decodePreservingProxyOrder(from: data)
        let node = try #require(response.proxies["Node 1999"])

        #expect(response.proxies.count == entryCount)
        #expect(response.proxyOrder.count == entryCount)
        #expect(response.policyGroups.count == entryCount / 20)
        #expect(node.metadata["scalar-number"] == .number(1_999))
        #expect(node.metadata["scalar-bool"] == .bool(true))
        #expect(node.metadata["scalar-null"] == .null)
        #expect(
            node.metadata["controller-meta"] == .object([
                "nested": .object([
                    "enabled": .bool(true),
                    "weight": .number(1_999),
                    "empty": .null,
                ]),
                "values": .array([
                    .string("alpha"),
                    .number(42),
                    .bool(false),
                    .null,
                    .object(["depth": .array([.number(1), .number(2), .number(3)])]),
                ]),
            ])
        )
    }

    @Test func decodedConnectionMetricFrameFixturePreservesAdditionalFields() async throws {
        let connectionCount = 2_000
        let frames = try Self.decodedConnectionMetricFrames(
            connectionCount: connectionCount
        )
        let initial = frames.initial[frames.changedIndex]
        let updated = frames.updated[frames.changedIndex]

        #expect(initial.fields["upload"] != updated.fields["upload"])
        #expect(initial.fields["download"] != updated.fields["download"])
        #expect(initial.fields["uploadSpeed"] != updated.fields["uploadSpeed"])
        #expect(initial.fields["downloadSpeed"] != updated.fields["downloadSpeed"])
        #expect(initial.additionalFields == updated.additionalFields)
        #expect(
            ConnectionsCatalogSnapshot.changedMetricIndices(
                frames.initial,
                frames.updated
            ) == [frames.changedIndex]
        )
        let projection = await Self.projectDecodedConnectionMetricFrame(
            frames,
            connectionCount: connectionCount
        )
        #expect(projection.workUnits == 1)
    }

    @Test func offlineReleaseBaseline() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MICA_RUN_PERFORMANCE_BENCHMARKS"] == "1" else {
            return
        }
        guard let outputPath = environment["MICA_PERFORMANCE_OUTPUT"], !outputPath.isEmpty else {
            throw BenchmarkError.missingOutputPath
        }

        let connectionCounts = [1_000, 5_000, 10_000]
        var cases: [BenchmarkCase] = []

        for count in connectionCounts {
            let connections = MicaPerformanceFixtures.connections(count: count)
            cases.append(
                measure(
                    name: "connection-row-projection",
                    fixtureCount: count,
                    sampleCount: count == 10_000 ? 7 : 9
                ) {
                    WorkbenchConnectionProjection.rows(from: connections).count
                }
            )
        }

        let fullConnectionCount = 10_000
        let fullConnections = MicaPerformanceFixtures.connections(
            count: fullConnectionCount
        )
        cases.append(
            measure(
                name: "connection-initial-cache-projection",
                fixtureCount: fullConnectionCount,
                sampleCount: 7
            ) {
                var cache = WorkbenchConnectionProjectionCache()
                cache.project(
                    activeConnections: fullConnections,
                    closedConnections: [],
                    scope: .active,
                    structureRevision: 1,
                    metricsRevision: 1,
                    closedRevision: 0,
                    query: "",
                    sortOrder: [],
                    language: .english
                )
                return cache.allRows.count
                    &+ cache.visibleRows.count
                    &+ cache.closeGroups.count
            }
        )
        cases.append(
            measurePrepared(
                name: "connection-search-projection",
                fixtureCount: fullConnectionCount,
                reportedWorkUnits: fullConnectionCount,
                prepare: {
                    var cache = WorkbenchConnectionProjectionCache()
                    cache.project(
                        activeConnections: fullConnections,
                        closedConnections: [],
                        scope: .active,
                        structureRevision: 1,
                        metricsRevision: 1,
                        closedRevision: 0,
                        query: "",
                        sortOrder: [],
                        language: .english
                    )
                    return cache
                }
            ) { cache in
                cache.project(
                    activeConnections: fullConnections,
                    closedConnections: [],
                    scope: .active,
                    structureRevision: 1,
                    metricsRevision: 1,
                    closedRevision: 0,
                    query: "host-9999.example.test",
                    sortOrder: [],
                    language: .english
                )
                return cache.visibleRows.count &+ cache.filterProjectionCount
            }
        )

        let keyedConnectionCount = 10_000
        var keyedConnections = MicaPerformanceFixtures.connections(
            count: keyedConnectionCount
        )
        var keyedConnectionCache = WorkbenchConnectionProjectionCache()
        var keyedMetricsRevision: UInt64 = 1
        keyedConnectionCache.project(
            activeConnections: keyedConnections,
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: keyedMetricsRevision,
            closedRevision: 0,
            query: "",
            sortOrder: [],
            language: .english
        )
        cases.append(
            measure(
                name: "connection-keyed-metric-update",
                fixtureCount: keyedConnectionCount,
                reportedWorkUnits: 1
            ) {
                let index = Int(keyedMetricsRevision % UInt64(keyedConnectionCount))
                keyedConnections[index].upload = (keyedConnections[index].upload ?? 0) + 1
                keyedMetricsRevision &+= 1
                var change = ConnectionsCatalogChange.none
                change.metricsChanged = true
                change.changedMetricIndices = [index]
                keyedConnectionCache.project(
                    activeConnections: keyedConnections,
                    closedConnections: [],
                    scope: .active,
                    structureRevision: 1,
                    metricsRevision: keyedMetricsRevision,
                    closedRevision: 0,
                    query: "",
                    sortOrder: [],
                    language: .english,
                    change: change
                )
                return keyedConnectionCache.metricsCandidateProjectionCount
            }
        )

        let logs = MicaPerformanceFixtures.logs(count: BoundedLogBuffer.maximumEntryCount)
        cases.append(
            measure(name: "log-ring-materialization", fixtureCount: logs.count) {
                var buffer = BoundedLogBuffer(entries: logs)
                var checksum = 0
                for index in 0..<32 {
                    buffer.append(
                        ControllerLogEntry(
                            id: "appended-\(index)",
                            receivedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)),
                            message: LogMessage(type: "info", payload: "append fixture \(index)")
                        )
                    )
                    checksum &+= buffer.entries.count
                }
                return checksum
            }
        )

        cases.append(
            measure(
                name: "log-full-ring-incremental-projection",
                fixtureCount: logs.count,
                reportedWorkUnits: 32
            ) {
                var buffer = BoundedLogBuffer(entries: logs)
                var cache = WorkbenchLogProjectionCache()
                cache.project(
                    entries: buffer.entries,
                    revision: 1,
                    level: .all,
                    query: "",
                    language: .english,
                    change: .replace
                )
                for index in 0..<32 {
                    let mutation = buffer.append(
                        ControllerLogEntry(
                            id: "delta-\(index)",
                            receivedAt: Date(timeIntervalSince1970: 1_900_000_000 + Double(index)),
                            message: LogMessage(type: "info", payload: "delta fixture \(index)")
                        )
                    )
                    cache.project(
                        entries: buffer.entries,
                        revision: UInt64(index + 2),
                        level: .all,
                        query: "",
                        language: .english,
                        change: .delta(
                            droppedEntryIDs: mutation.droppedEntryIDs,
                            appendedEntries: mutation.appendedEntries
                        )
                    )
                }
                return cache.formattedRowCount &+ cache.deltaProjectionCount
            }
        )

        cases.append(
            measurePrepared(
                name: "log-steady-state-delta-projection",
                fixtureCount: logs.count,
                reportedWorkUnits: 32,
                prepare: {
                    let buffer = BoundedLogBuffer(entries: logs)
                    var cache = WorkbenchLogProjectionCache()
                    cache.project(
                        entries: buffer.entries,
                        revision: 1,
                        level: .all,
                        query: "",
                        language: .english,
                        change: .replace
                    )
                    return LogDeltaBenchmarkState(
                        buffer: buffer,
                        cache: cache,
                        revision: 1
                    )
                }
            ) { state in
                for index in 0..<32 {
                    let mutation = state.buffer.append(
                        ControllerLogEntry(
                            id: "steady-delta-\(index)",
                            receivedAt: Date(
                                timeIntervalSince1970: 1_950_000_000 + Double(index)
                            ),
                            message: LogMessage(
                                type: "info",
                                payload: "steady delta fixture \(index)"
                            )
                        )
                    )
                    state.revision &+= 1
                    state.cache.project(
                        entries: state.buffer.entries,
                        revision: state.revision,
                        level: .all,
                        query: "",
                        language: .english,
                        change: .delta(
                            droppedEntryIDs: mutation.droppedEntryIDs,
                            appendedEntries: mutation.appendedEntries
                        )
                    )
                }
                return state.cache.formattedRowCount &+ state.cache.deltaProjectionCount
            }
        )

        cases.append(
            measurePrepared(
                name: "log-search-projection",
                fixtureCount: logs.count,
                reportedWorkUnits: logs.count,
                prepare: {
                    var cache = WorkbenchLogProjectionCache()
                    cache.project(
                        entries: logs,
                        revision: 1,
                        level: .all,
                        query: "",
                        language: .english,
                        change: .replace
                    )
                    return cache
                }
            ) { cache in
                cache.project(
                    entries: logs,
                    revision: 1,
                    level: .all,
                    query: "route=policy-12",
                    language: .english
                )
                return cache.visibleRows.count &+ cache.filterEvaluationCount
            }
        )
        let ruleCount = 10_000
        let rules = MicaPerformanceFixtures.rules(count: ruleCount)
        let ruleConnections = MicaPerformanceFixtures.connections(count: ruleCount)
        cases.append(
            measure(
                name: "rule-connection-index-and-counts",
                fixtureCount: ruleCount,
                reportedWorkUnits: ruleConnections.count &+ rules.count
            ) {
                let index = WorkbenchRuleConnectionIndex(
                    connections: ruleConnections
                )
                return rules.reduce(into: 0) { count, rule in
                    count &+= index.count(for: rule)
                }
            }
        )
        let ruleConnectionIndex = WorkbenchRuleConnectionIndex(
            connections: ruleConnections
        )
        cases.append(
            measure(
                name: "rule-row-projection",
                fixtureCount: ruleCount,
                sampleCount: 7
            ) {
                WorkbenchRuleProjection.rows(
                    from: rules,
                    connectionIndex: ruleConnectionIndex,
                    language: .english
                ).count
            }
        )
        let projectedRuleRows = WorkbenchRuleProjection.rows(
            from: rules,
            connectionIndex: ruleConnectionIndex,
            language: .english
        )
        cases.append(
            measure(
                name: "rule-search-projection",
                fixtureCount: ruleCount,
                reportedWorkUnits: ruleCount
            ) {
                WorkbenchRuleProjection.visibleRows(
                    from: projectedRuleRows,
                    query: "fixture-100",
                    sortOrder: []
                ).count
            }
        )
        let sourceCount = 1_000
        let sources = MicaPerformanceFixtures.sources(count: sourceCount)
        cases.append(
            measure(
                name: "source-row-projection",
                fixtureCount: sourceCount,
                sampleCount: 7
            ) {
                WorkbenchSourceProjection.rows(
                    from: sources,
                    language: .english
                ).count
            }
        )
        let projectedSourceRows = WorkbenchSourceProjection.rows(
            from: sources,
            language: .english
        )
        cases.append(
            measure(
                name: "source-search-projection",
                fixtureCount: sourceCount,
                reportedWorkUnits: sourceCount
            ) {
                WorkbenchSourceProjection.visibleRows(
                    from: projectedSourceRows,
                    kind: .all,
                    query: "provider-999",
                    sortOrder: []
                ).count
            }
        )
        let proxyCatalog = MicaPerformanceFixtures.proxyCatalog(
            groupCount: 100,
            membersPerGroup: 1_000
        )
        let proxyRevision = ProxyCatalogRevision(
            controllerID: nil,
            generation: nil,
            value: 1
        )
        cases.append(
            measure(
                name: "proxy-catalog-index-projection",
                fixtureCount: 100_000,
                sampleCount: 5,
                reportedWorkUnits: 100_000
            ) {
                let index = ProxyGroupCatalogIndex(
                    catalog: proxyCatalog,
                    visibility: .followMode,
                    revision: proxyRevision
                )
                return index.records.count &+ index.directoryItems.count
            }
        )

        let proxyDecodeCount = 2_000
        let proxyResponseData = try Self.largeProxyResponseFixture(
            entryCount: proxyDecodeCount
        )
        cases.append(
            measure(
                name: "proxy-response-decode",
                fixtureCount: proxyDecodeCount,
                sampleCount: 7,
                reportedWorkUnits: proxyDecodeCount
            ) {
                let response = try! ProxiesResponse.decodePreservingProxyOrder(
                    from: proxyResponseData
                )
                return response.proxyOrder.count
                    &+ response.policyGroups.count
                    &+ (response.proxies["Node 1999"]?.metadata.count ?? 0)
            }
        )
        let cachedMediumProxies = try ProxiesResponse.decodePreservingProxyOrder(
            from: proxyResponseData
        )
        let unchangedMediumProxies = try ProxiesResponse.decodePreservingProxyOrder(
            from: proxyResponseData
        )
        var unchangedMediumCache = SessionEndpointCache()
        unchangedMediumCache.proxies = cachedMediumProxies
        cases.append(
            measure(
                name: "mihomo-medium-unchanged-change-plan",
                fixtureCount: proxyDecodeCount,
                sampleCount: 7,
                reportedWorkUnits: proxyDecodeCount
            ) {
                let plan = MihomoEndpointChangePlan.medium(
                    cache: unchangedMediumCache,
                    proxies: unchangedMediumProxies
                )
                guard plan.cacheWriteCount == 0,
                      plan.policyGroupProjectionWorkUnits == 0,
                      !plan.shouldRebuildUnifiedSnapshot else {
                    return 0
                }
                return unchangedMediumProxies.proxies.count
            }
        )
        let metadataComparisonCount = 2_000
        let metadataCatalogLeft = Self.metadataRichPolicyCatalog(
            nodeCount: metadataComparisonCount
        )
        let metadataCatalogRight = Self.metadataRichPolicyCatalog(
            nodeCount: metadataComparisonCount
        )
        cases.append(
            measure(
                name: "policy-catalog-equality",
                fixtureCount: metadataComparisonCount,
                sampleCount: 7,
                reportedWorkUnits: metadataComparisonCount
            ) {
                metadataCatalogLeft == metadataCatalogRight
                    ? metadataComparisonCount
                    : 0
            }
        )
        cases.append(
            measure(
                name: "policy-catalog-projection-and-equality",
                fixtureCount: metadataComparisonCount,
                sampleCount: 5,
                reportedWorkUnits: metadataComparisonCount * 2
            ) {
                let left = Self.metadataRichPolicyCatalog(
                    nodeCount: metadataComparisonCount
                )
                let right = Self.metadataRichPolicyCatalog(
                    nodeCount: metadataComparisonCount
                )
                guard left == right else { return 0 }
                return left.groups.reduce(0) { $0 &+ $1.optionDetails.count }
                    &+ right.groups.reduce(0) { $0 &+ $1.optionDetails.count }
            }
        )
        cases.append(
            measurePrepared(
                name: "proxy-active-group-projection",
                fixtureCount: 1_000,
                sampleCount: 7,
                reportedWorkUnits: 1_000,
                prepare: {
                    var cache = ProxyCatalogProjectionCache()
                    cache.updateCatalog(
                        proxyCatalog,
                        revision: proxyRevision,
                        visibility: .followMode
                    )
                    return cache
                }
            ) { cache in
                cache.updateActiveGroup(
                    groupID: cache.groupIndex.arrangedGroups.first?.id
                )
                return cache.workCounts.memberRowsBuilt
            }
        )

        cases.append(
            await measureAsync(
                name: "runtime-hidden-log-ingestion",
                fixtureCount: 10_000,
                sampleCount: 5
            ) {
                let identity = LiveSessionRuntimeIdentity(
                    controllerID: UUID(),
                    generation: UUID()
                )
                let runtime = LiveSessionRuntime(
                    controllerKind: .mihomoCompatible,
                    initialPresentationDemand: LiveSessionPresentationDemand(
                        identity: identity,
                        revision: 0,
                        observedDomains: [.logs],
                        presentationPaused: false,
                        logsPresentationPaused: false,
                        baselinePublicationRequired: false
                    )
                )
                for index in 0..<10_000 {
                    _ = await runtime.ingestLog(
                        LogMessage(type: "info", payload: "runtime fixture \(index)"),
                        source: .mihomoWebSocket,
                        id: "runtime-log-\(index)"
                    )
                }
                let publication = await runtime.publication(for: .logs, force: true)
                guard case .logs(let logs) = publication?.payload else { return 0 }
                return logs.fullSnapshot?.count ?? logs.appendedEntries.count
            }
        )

        for count in connectionCounts {
            let connections = MicaPerformanceFixtures.connections(count: count)
            cases.append(
                await measureAsync(
                    name: "runtime-connection-frame",
                    fixtureCount: count,
                    sampleCount: count == 10_000 ? 5 : 7
                ) {
                    let identity = LiveSessionRuntimeIdentity(
                        controllerID: UUID(),
                        generation: UUID()
                    )
                    let runtime = LiveSessionRuntime(
                        controllerKind: .mihomoCompatible,
                        initialPresentationDemand: LiveSessionPresentationDemand(
                            identity: identity,
                            revision: 0,
                            observedDomains: [.connections],
                            presentationPaused: false,
                            logsPresentationPaused: false,
                            baselinePublicationRequired: false
                        )
                    )
                    _ = await runtime.ingestMihomoConnections(
                        ConnectionsResponse(
                            uploadTotal: count,
                            downloadTotal: count * 2,
                            memory: 128 * 1_024 * 1_024,
                            connections: connections
                        )
                    )
                    let publication = await runtime.publication(for: .connections, force: true)
                    guard case .connections(let snapshot) = publication?.payload,
                          case .mihomo(let response) = snapshot.source else {
                        return 0
                    }
                    return response.connections.count
                }
            )
        }

        let decodedMetricFrameCount = 2_000
        let decodedMetricFrames = try Self.decodedConnectionMetricFrames(
            connectionCount: decodedMetricFrameCount
        )
        let decodedMetricProbe = await Self.projectDecodedConnectionMetricFrame(
            decodedMetricFrames,
            connectionCount: decodedMetricFrameCount
        )
        cases.append(
            await measureAsync(
                name: "runtime-decoded-connection-metric-frame",
                fixtureCount: decodedMetricFrameCount,
                sampleCount: 7,
                reportedWorkUnits: decodedMetricProbe.workUnits
            ) {
                await Self.projectDecodedConnectionMetricFrame(
                    decodedMetricFrames,
                    connectionCount: decodedMetricFrameCount
                ).checksum
            }
        )

        for shape in [MicaPerformanceFixtures.TopologyShape.shared, .unique] {
            for count in [1_000, 2_000] {
                let connections = MicaPerformanceFixtures.topologyConnections(
                    count: count,
                    shape: shape
                )
                cases.append(
                    measure(
                        name: shape == .shared ? "topology-shared-route" : "topology-unique-route",
                        fixtureCount: count,
                        sampleCount: 7
                    ) {
                        let topology = ConnectionTopologyBuilder.build(from: connections)
                        return topology.paths.count &+ topology.nodes.count &+ topology.edges.count
                    }
                )
            }
        }

        let denseLayoutConnectionCount = 1_000
        let denseLayoutConnections = (0..<denseLayoutConnectionCount).map { index in
            let source = index % 16
            let rule = (index / 16) % 20
            let pass = index / 320
            let entry = (source * 3 + rule + pass) % 8
            let region = (source + rule * 5 + pass * 2) % 6
            let selection = (source / 2 + rule + pass) % 4
            let outbound = (source * 5 + rule * 7 + pass * 3) % 12
            return ConnectionSnapshot(
                id: "dense-layout-\(index)",
                chains: [
                    "outbound-\(outbound)",
                    "automatic-\(selection)",
                    "region-\(region)",
                    "entry-\(entry)",
                ],
                rule: "RuleSet",
                rulePayload: "rule-\(rule)",
                metadata: ConnectionMetadataSnapshot(sourceIP: "192.0.2.\(source + 10)")
            )
        }
        // Normalize outside the sample so this measures ordering, card/edge
        // geometry, render-band admission and hit-index construction together.
        let denseLayoutTopology = ConnectionTopologyBuilder.build(from: denseLayoutConnections)
        #expect(denseLayoutTopology.paths.count == denseLayoutConnectionCount)
        #expect(denseLayoutTopology.nodes.count == 66)
        #expect(denseLayoutTopology.edges.count >= 400)
        cases.append(
            await measureAsync(
                name: "topology-dense-card-layout",
                fixtureCount: denseLayoutConnectionCount,
                sampleCount: 7
            ) {
                do {
                    let layout = try await OverviewTopologyLayoutBuilder.buildCancellable(
                        topology: denseLayoutTopology,
                        availableWidth: 1_400,
                        minimumFlowHeight: 300
                    )
                    return layout.nodes.count &+ layout.edges.count
                        &+ layout.operationCounts.edgeHitSegmentCount
                } catch {
                    Issue.record("Dense topology card layout benchmark failed: \(error)")
                    return 0
                }
            }
        )
        cases += try await overviewProjectionBenchmarks(
            connections: denseLayoutConnections,
            expectedTopology: denseLayoutTopology
        )

        let report = BenchmarkReport(
            schemaVersion: 2,
            label: environment["MICA_PERFORMANCE_LABEL"] ?? "unlabeled",
            generatedAt: Date(),
            buildConfiguration: "release",
            swiftVersion: environment["MICA_SWIFT_VERSION"] ?? "unknown",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            limitations: [
                "Offline synthetic fixtures only; no real controller or network was used.",
                "Wall-clock timings are supporting evidence; scaling and operation counts are the durable contract.",
                "SwiftUI Instruments acceptance remains deferred until separately authorized by the user.",
            ],
            cases: cases
        )

        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: outputURL, options: .atomic)
    }

    /// Exercises the same presentation cache used by the homepage, including
    /// normalization, summary membership, ordering, layout and hit targets.
    /// Preparation and full membership validation stay outside the timed span,
    /// so a cache-hit result is not dominated by a test-only checksum traversal.
    @MainActor
    private func overviewProjectionBenchmarks(
        connections: [ConnectionSnapshot],
        expectedTopology: ConnectionTopology
    ) async throws -> [BenchmarkCase] {
        let generation = UUID(uuidString: "7A8B0526-4E90-4B68-BE28-7417A6BE0820")!
        let initialRequest = OverviewTopologyRequest(
            generation: generation,
            revision: 1,
            availableWidth: 600,
            minimumFlowHeight: 360,
            displayMode: .overview,
            languageID: "en"
        )
        let resizedRequest = OverviewTopologyRequest(
            generation: generation,
            revision: 1,
            availableWidth: 920,
            minimumFlowHeight: 420,
            displayMode: .overview,
            languageID: "en"
        )
        var metricFrame = connections
        for index in metricFrame.indices {
            metricFrame[index].upload = (metricFrame[index].upload ?? 0) + index + 101
            metricFrame[index].download = (metricFrame[index].download ?? 0) + index + 103
            metricFrame[index].uploadSpeed = 107 + index
            metricFrame[index].downloadSpeed = 109 + index
        }

        enum Scenario: String, CaseIterable {
            case cold = "topology-overview-cold-projection"
            case metrics = "topology-overview-metrics-cache-hit"
            case resize = "topology-overview-resize"
        }
        let sampleCount = 7
        var results: [BenchmarkCase] = []
        for scenario in Scenario.allCases {
            var milliseconds: [Double] = []
            var checksum = 0
            for sample in 0...sampleCount {
                let cache = OverviewTopologyPresentationCache()
                if scenario != .cold {
                    _ = try await cache.resolve(request: initialRequest, connections: connections)
                }
                let before = cache.statistics
                let orderingBefore = cache.orderingPreparationCount
                let request = scenario == .resize ? resizedRequest : initialRequest
                let input = scenario == .metrics ? metricFrame : connections

                let start = DispatchTime.now().uptimeNanoseconds
                let presentation = try await cache.resolve(request: request, connections: input)
                let elapsed = DispatchTime.now().uptimeNanoseconds - start
                if sample > 0 {
                    milliseconds.append(Double(elapsed) / 1_000_000)
                }

                checksum &+= Self.verifiedOverviewMembershipChecksum(
                    presentation,
                    expectedTopology: expectedTopology
                )
                #expect(presentation.layout.size.width <= CGFloat(request.availableWidth))
                #expect(presentation.layout.nodes.count <= 18)
                #expect(presentation.layout.edges.count <= 72)
                switch scenario {
                case .cold:
                    #expect(cache.statistics.topologyBuildCount - before.topologyBuildCount == 1)
                    #expect(cache.statistics.layoutBuildCount - before.layoutBuildCount == 1)
                    #expect(cache.orderingPreparationCount - orderingBefore == 1)
                case .metrics:
                    #expect(cache.statistics.topologyBuildCount == before.topologyBuildCount)
                    #expect(cache.statistics.layoutBuildCount == before.layoutBuildCount)
                    #expect(cache.orderingPreparationCount == orderingBefore)
                    #expect(cache.statistics.exactRequestHitCount - before.exactRequestHitCount == 1)
                case .resize:
                    #expect(cache.statistics.topologyBuildCount == before.topologyBuildCount)
                    #expect(cache.orderingPreparationCount == orderingBefore)
                    #expect(cache.statistics.layoutBuildCount - before.layoutBuildCount == 1)
                    #expect(cache.statistics.structureReuseCount - before.structureReuseCount == 1)
                }
            }

            let sorted = milliseconds.sorted()
            results.append(BenchmarkCase(
                name: scenario.rawValue,
                fixtureCount: connections.count,
                samples: sorted.count,
                medianMilliseconds: percentile(0.5, sorted: sorted),
                p95Milliseconds: percentile(0.95, sorted: sorted),
                minimumMilliseconds: sorted.first ?? 0,
                maximumMilliseconds: sorted.last ?? 0,
                checksum: checksum,
                reportedWorkUnits: nil
            ))
        }
        return results
    }

    /// Include full connection identities, rule/hop names and the memberships
    /// reachable from every diagram node and edge, not merely the card count.
    /// The rolling checksum is deterministic across processes (unlike Hasher).
    private static func verifiedOverviewMembershipChecksum(
        _ presentation: OverviewTopologyPresentation,
        expectedTopology: ConnectionTopology
    ) -> Int {
        #expect(presentation.topology == expectedTopology)
        let expectedIDs = Set(expectedTopology.paths.map(\.id))
        #expect(Set(presentation.diagram.paths.map(\.id)) == expectedIDs)
        #expect(presentation.diagram.paths.count == expectedTopology.paths.count)
        var checksum = 17

        func consume(_ value: String) {
            checksum = checksum &* 31 &+ value.utf8.count
            for byte in value.utf8 { checksum = checksum &* 31 &+ Int(byte) }
        }

        for path in presentation.topology.paths {
            #expect(presentation.index.path(id: path.id) == path)
            checksum = checksum &* 31 &+ path.sourceIndex
            consume(path.id.stableKey)
            consume(path.reportedConnectionID)
            for stage in path.stages {
                consume(stage.nodeID)
                consume(stage.name)
            }
        }
        for column in presentation.diagram.columns {
            #expect(Set(column.nodes.flatMap(\.pathIDs)) == expectedIDs)
            #expect(column.nodes.reduce(0) { $0 + $1.pathIDs.count } == expectedIDs.count)
            for node in column.nodes {
                let related = presentation.diagramIndex.highlight(for: .node(node.id))
                #expect(related.pathIDs == Set(node.pathIDs))
                consume(node.id)
                for path in related.paths {
                    #expect(presentation.index.path(id: path.id) != nil)
                    consume(path.id.stableKey)
                }
            }
        }
        for edge in presentation.diagram.edges {
            let related = presentation.diagramIndex.highlight(for: .edge(edge.id))
            #expect(related.pathIDs == Set(edge.pathIDs))
            consume(edge.id)
            for path in related.paths { consume(path.id.stableKey) }
        }
        return checksum
    }

    private func measure(
        name: String,
        fixtureCount: Int,
        warmupCount: Int = 2,
        sampleCount: Int = 9,
        reportedWorkUnits: Int? = nil,
        operation: () -> Int
    ) -> BenchmarkCase {
        var checksum = 0
        for _ in 0..<warmupCount {
            checksum &+= operation()
        }

        var samples: [Double] = []
        samples.reserveCapacity(sampleCount)
        for _ in 0..<sampleCount {
            let start = DispatchTime.now().uptimeNanoseconds
            checksum &+= operation()
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            samples.append(Double(elapsed) / 1_000_000)
        }

        let sorted = samples.sorted()
        let median = percentile(0.5, sorted: sorted)
        let p95 = percentile(0.95, sorted: sorted)
        return BenchmarkCase(
            name: name,
            fixtureCount: fixtureCount,
            samples: samples.count,
            medianMilliseconds: median,
            p95Milliseconds: p95,
            minimumMilliseconds: sorted.first ?? 0,
            maximumMilliseconds: sorted.last ?? 0,
            checksum: checksum,
            reportedWorkUnits: reportedWorkUnits
        )
    }

    private func measureAsync(
        name: String,
        fixtureCount: Int,
        warmupCount: Int = 1,
        sampleCount: Int,
        reportedWorkUnits: Int? = nil,
        operation: () async -> Int
    ) async -> BenchmarkCase {
        var checksum = 0
        for _ in 0..<warmupCount {
            checksum &+= await operation()
        }

        var samples: [Double] = []
        samples.reserveCapacity(sampleCount)
        for _ in 0..<sampleCount {
            let start = DispatchTime.now().uptimeNanoseconds
            checksum &+= await operation()
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            samples.append(Double(elapsed) / 1_000_000)
        }

        let sorted = samples.sorted()
        return BenchmarkCase(
            name: name,
            fixtureCount: fixtureCount,
            samples: samples.count,
            medianMilliseconds: percentile(0.5, sorted: sorted),
            p95Milliseconds: percentile(0.95, sorted: sorted),
            minimumMilliseconds: sorted.first ?? 0,
            maximumMilliseconds: sorted.last ?? 0,
            checksum: checksum,
            reportedWorkUnits: reportedWorkUnits
        )
    }

    private func measurePrepared<State>(
        name: String,
        fixtureCount: Int,
        warmupCount: Int = 2,
        sampleCount: Int = 9,
        reportedWorkUnits: Int? = nil,
        prepare: () -> State,
        operation: (inout State) -> Int
    ) -> BenchmarkCase {
        var checksum = 0
        for _ in 0..<warmupCount {
            var state = prepare()
            checksum &+= operation(&state)
        }

        var samples: [Double] = []
        samples.reserveCapacity(sampleCount)
        for _ in 0..<sampleCount {
            var state = prepare()
            let start = DispatchTime.now().uptimeNanoseconds
            checksum &+= operation(&state)
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            samples.append(Double(elapsed) / 1_000_000)
        }

        let sorted = samples.sorted()
        return BenchmarkCase(
            name: name,
            fixtureCount: fixtureCount,
            samples: samples.count,
            medianMilliseconds: percentile(0.5, sorted: sorted),
            p95Milliseconds: percentile(0.95, sorted: sorted),
            minimumMilliseconds: sorted.first ?? 0,
            maximumMilliseconds: sorted.last ?? 0,
            checksum: checksum,
            reportedWorkUnits: reportedWorkUnits
        )
    }

    private func percentile(_ percentile: Double, sorted samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let index = min(
            samples.count - 1,
            max(0, Int(ceil(Double(samples.count) * percentile)) - 1)
        )
        return samples[index]
    }
}
