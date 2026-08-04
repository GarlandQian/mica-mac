import Foundation
import MicaCore
import Testing
@testable import Mica

@Suite(.serialized)
struct MicaPerformanceBenchmarkTests {
    private struct BenchmarkCase: Codable {
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

    private enum BenchmarkError: Error {
        case missingOutputPath
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

    private func percentile(_ percentile: Double, sorted samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let index = min(
            samples.count - 1,
            max(0, Int(ceil(Double(samples.count) * percentile)) - 1)
        )
        return samples[index]
    }
}
