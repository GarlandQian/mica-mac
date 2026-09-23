import Foundation
import MicaCore
import Testing
@testable import Mica

struct WorkbenchOverviewPreferencesTests {
    @Test func fixedPreferencesDefaultAndNormalizationAreMinimal() {
        #expect(OverviewMetricID.allCases.map(\.rawValue) == [
            "upload", "download", "activeConnections",
        ])
        #expect(OverviewOptionalModuleID.allCases.map(\.rawValue) == [
            "instrumentRail", "operationalSummaries", "networkInformation",
        ])
        #expect(OverviewPreferences.default.visibleMetrics == Set(OverviewMetricID.allCases))
        #expect(OverviewPreferences.default.timelineWindow == .fiveMinutes)
        #expect(OverviewPreferences.default.visibleOptionalModules.isEmpty)

        let repaired = OverviewPreferences(
            visibleMetrics: [],
            timelineWindow: .oneMinute,
            visibleOptionalModules: [.networkInformation]
        ).normalized()
        #expect(repaired.visibleMetrics == [.upload])
        #expect(repaired.timelineWindow == .oneMinute)
        #expect(repaired.visibleOptionalModules == [.networkInformation])
    }

    @MainActor
    @Test func globalPreferencesRoundTripResetAndDeduplicateWrites() throws {
        let box = OverviewPreferencesPersistenceBox()
        let store = OverviewPreferencesStore(persistence: box.client)

        #expect(store.preferences == .default)
        store.setTimelineWindow(.threeMinutes)
        store.setMetric(.download, isVisible: false)
        store.setOptionalModule(.instrumentRail, isVisible: true)
        let saveCount = box.saveCount
        store.setOptionalModule(.instrumentRail, isVisible: true)
        #expect(box.saveCount == saveCount)

        let restored = OverviewPreferencesStore(persistence: box.client)
        #expect(restored.preferences.timelineWindow == .threeMinutes)
        #expect(restored.preferences.visibleMetrics == [.upload, .activeConnections])
        #expect(restored.preferences.visibleOptionalModules == [.instrumentRail])

        let data = try #require(box.data)
        let envelope = try JSONDecoder().decode(
            OverviewPreferencesPersistenceEnvelope.self,
            from: data
        )
        #expect(envelope.schema == OverviewPreferencesPersistenceEnvelope.schema)
        #expect(envelope.preferences == restored.preferences)

        restored.reset()
        #expect(restored.preferences == .default)
    }

    @MainActor
    @Test func supersededLayoutAndWrongSchemaResetWithoutMigration() {
        let legacy = Data(
            #"{"version":1,"globalRevision":9,"globalDefault":{"modules":[{"id":"telemetry","size":"full","isVisible":true}]},"controllerOverrides":[]}"#.utf8
        )
        let legacyStore = OverviewPreferencesStore(
            persistence: OverviewPreferencesPersistenceClient(
                loadData: { legacy },
                saveData: { _ in }
            )
        )
        #expect(legacyStore.preferences == .default)

        let wrongSchema = try! JSONEncoder().encode(
            WrongOverviewPreferencesEnvelope(
                schema: "mica.overview.future",
                preferences: OverviewPreferences(
                    visibleMetrics: [.download],
                    timelineWindow: .oneMinute,
                    visibleOptionalModules: [.networkInformation]
                )
            )
        )
        let wrongSchemaStore = OverviewPreferencesStore(
            persistence: OverviewPreferencesPersistenceClient(
                loadData: { wrongSchema },
                saveData: { _ in }
            )
        )
        #expect(wrongSchemaStore.preferences == .default)
    }

    @MainActor
    @Test func oneStoreIsSharedWhileEachWindowKeepsStableRuntimeIdentity() {
        let box = OverviewPreferencesPersistenceBox()
        let store = OverviewPreferencesStore(persistence: box.client)
        let firstConsumer = store
        let secondConsumer = store
        firstConsumer.setOptionalModule(.networkInformation, isVisible: true)
        #expect(secondConsumer.isOptionalModuleVisible(.networkInformation))

        let firstWindow = OverviewWindowRuntime()
        let secondWindow = OverviewWindowRuntime()
        #expect(firstWindow.liveSessionWindowDemandID != secondWindow.liveSessionWindowDemandID)
        let stableDemand = firstWindow.liveSessionWindowDemandID
        #expect(firstWindow.liveSessionWindowDemandID == stableDemand)

        let controllerID = UUID(uuidString: "6A47E9CA-582F-4D90-9F3D-EC2FA4B0C62B")!
        let generation = UUID(uuidString: "8068067A-82A1-45CC-9F80-AE54BDFB2978")!
        let firstTelemetry = firstWindow.registry.telemetryRuntime(
            controllerID: controllerID,
            generation: generation,
            preferredWindow: .fiveMinutes
        )
        let secondTelemetry = firstWindow.registry.telemetryRuntime(
            controllerID: controllerID,
            generation: generation,
            preferredWindow: .threeMinutes
        )
        #expect(firstTelemetry === secondTelemetry)
        #expect(secondTelemetry.timelineWindow == .threeMinutes)
        let firstTopology = firstWindow.registry.topologyRuntime(
            controllerID: controllerID,
            generation: generation
        )
        let secondTopology = firstWindow.registry.topologyRuntime(
            controllerID: controllerID,
            generation: generation
        )
        #expect(firstTopology === secondTopology)
    }

    @Test func policyInspectionResolvesOnlyUniqueExactNames() {
        let tokyo = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Tokyo",
                type: "VLESS",
                alive: true,
                history: [ProxyDelayHistorySnapshot(time: "now", delay: 42)],
                testURL: "https://example.test/generate_204",
                providerName: "Airport A",
                interfaceName: "utun7",
                udp: true,
                tfo: false,
                metadata: [
                    "region": .string("JP"),
                    "server": .string("tokyo.example"),
                    "port": .number(443),
                    "tls": .bool(true),
                ]
            )
        )
        let catalog = PolicyGroupCatalogSnapshot(
            mode: "Rule",
            groups: [
                ProxyGroupViewState(
                    id: "Auto",
                    type: "URLTest",
                    selected: "Tokyo",
                    options: ["Tokyo", "Osaka"],
                    optionDetails: ["Tokyo": tokyo],
                    optionUsageRanks: ["Tokyo": .mostUsed],
                    delays: ["Tokyo": 42]
                ),
                ProxyGroupViewState(
                    id: "Manual",
                    type: "Selector",
                    selected: "Solo",
                    options: ["Solo"]
                ),
                ProxyGroupViewState(
                    id: "Duplicate",
                    type: "Selector",
                    selected: "Shared",
                    options: ["Shared"]
                ),
                ProxyGroupViewState(
                    id: "Duplicate",
                    type: "Selector",
                    selected: "Shared",
                    options: ["Shared"]
                ),
            ]
        )
        let index = OverviewPolicyInspectionIndex(catalog: catalog)

        guard case .group(let group) = index.resolve(name: "Auto") else {
            Issue.record("Expected one exact group match")
            return
        }
        #expect(group.name == "Auto")
        #expect(group.selectedMember.detail == tokyo)
        #expect(group.selectedMember.delay == 42)
        #expect(group.selectedMember.usageRank == .mostUsed)

        guard case .member(let solo) = index.resolve(name: "Solo") else {
            Issue.record("Expected one exact member match")
            return
        }
        #expect(solo.groupName == "Manual")
        #expect(index.resolve(name: "Duplicate") == .ambiguous)
        #expect(index.resolve(name: "Shared") == .ambiguous)
        #expect(index.resolve(name: "auto") == .missing)
        #expect(index.resolve(name: "Missing") == .missing)
        #expect(index.operationCounts.groupWriteCount == catalog.groups.count)
        #expect(index.operationCounts.memberWriteCount == 5)
    }

    @MainActor
    @Test func policyInspectionCacheAndInspectionProjectionExposesCompleteFields() throws {
        let detail = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Tokyo",
                type: "VLESS",
                alive: true,
                history: [ProxyDelayHistorySnapshot(time: "2026-08-16T12:00:00Z", delay: 64)],
                testURL: "https://example.test/generate_204",
                providerName: "Airport A",
                interfaceName: "utun7",
                udp: true,
                tfo: false,
                metadata: [
                    "region": .string("JP"),
                    "server": .string("tokyo.example"),
                    "port": .number(443),
                    "tls": .bool(true),
                ]
            )
        )
        let catalog = PolicyGroupCatalogSnapshot(
            mode: "Rule",
            groups: [
                ProxyGroupViewState(
                    id: "Auto",
                    type: "URLTest",
                    selected: "Tokyo",
                    options: ["Tokyo"],
                    optionDetails: ["Tokyo": detail],
                    optionUsageRanks: ["Tokyo": .mostUsed],
                    delays: ["Tokyo": 64]
                ),
            ]
        )
        let cache = OverviewPolicyInspectionCache()
        let firstIndex = cache.resolve(revision: 7, catalog: catalog)
        _ = cache.resolve(revision: 7, catalog: catalog)
        #expect(cache.statistics == .init(buildCount: 1, cacheHitCount: 1))

        let snapshot = try #require(OverviewPolicyInspectionProjection.snapshot(
            name: "Auto",
            policyIndex: firstIndex,
            language: .english
        ))

        #expect(snapshot.kind == .policyGroup)
        #expect(snapshot.title == "Auto")
        #expect(snapshot.sections.map(\.id) == [
            "overview", "protocol", "transport", "testing", "reported-fields",
        ])
        #expect(snapshot.fields.contains { $0.id == "member-count" })
        #expect(snapshot.fields.contains { $0.id == "members" && $0.value == "Tokyo" })
        #expect(snapshot.fields.contains { $0.id == "provider" })
        #expect(snapshot.fields.contains { $0.id == "transport.udp" })
        #expect(snapshot.fields.contains {
            $0.id == "transport.tfo"
                && $0.value == MicaStrings.localizedKey(
                    "overview.config_disabled",
                    language: .english
                )
        })
        #expect(snapshot.fields.filter { $0.id.hasPrefix("metadata.") }.count == 4)
        #expect(snapshot.fields.contains { $0.id == "rank" })
        #expect(snapshot.fields.contains { $0.id == "test-time" })
        #expect(snapshot.fields.contains { $0.id == "test-url" })
        #expect(OverviewPolicyInspectionProjection.snapshot(
            name: "Missing",
            policyIndex: firstIndex,
            language: .english
        ) == nil)
    }

    @Test func motionProjectionIsStaticForPauseInactiveAndReduceMotion() {
        let initialSignal = OverviewTopologyLiveSignal(
            latestTrafficReceivedAt: Date(timeIntervalSinceReferenceDate: 100.2),
            connectionMetricsRevision: 3,
            connectionTrafficRevision: 4
        )
        let sameSecondSignal = OverviewTopologyLiveSignal(
            latestTrafficReceivedAt: Date(timeIntervalSinceReferenceDate: 100.9),
            connectionMetricsRevision: 3,
            connectionTrafficRevision: 4
        )
        let nextSignal = OverviewTopologyLiveSignal(
            latestTrafficReceivedAt: Date(timeIntervalSinceReferenceDate: 101.0),
            connectionMetricsRevision: 4,
            connectionTrafficRevision: 5
        )
        #expect(initialSignal == sameSecondSignal)
        #expect(initialSignal != nextSignal)
    }

}

private struct WrongOverviewPreferencesEnvelope: Codable {
    let schema: String
    let preferences: OverviewPreferences
}

private final class OverviewPreferencesPersistenceBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var data: Data?
    private(set) var saveCount = 0

    var client: OverviewPreferencesPersistenceClient {
        OverviewPreferencesPersistenceClient(
            loadData: { [weak self] in
                guard let self else { return nil }
                return self.withLock { self.data }
            },
            saveData: { [weak self] data in
                guard let self else { return }
                self.withLock {
                    self.data = data
                    self.saveCount += 1
                }
            }
        )
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
