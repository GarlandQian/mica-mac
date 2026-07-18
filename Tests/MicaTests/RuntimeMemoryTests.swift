import Foundation
import MicaCore
import Testing
@testable import Mica

struct RuntimeMemoryTests {
    @Test func runtimeMemoryStoresResponseValuesAsBytesInDiagnostics() {
        var runtime = ControllerSessionRuntimeState()
        runtime.recordMemory(MemoryResponse(inuse: 1_048_576, oslimit: 2_097_152))

        #expect(runtime.memoryInUseBytes == 1_048_576)
        #expect(runtime.memoryLimitBytes == 2_097_152)
        #expect(runtime.diagnosticsSummary.contains("memory-inuse-bytes=1048576"))
        #expect(runtime.diagnosticsSummary.contains("memory-limit-bytes=2097152"))
    }

    @Test func pendingPresentationKeepsOnlyTheLatestMemoryFrame() {
        var pending = PendingSessionPresentation()
        pending.memory = MemoryResponse(inuse: 1_048_576, oslimit: 2_097_152)
        pending.memory = MemoryResponse(inuse: 3_145_728, oslimit: 4_194_304)

        #expect(!pending.isEmpty)
        #expect(pending.memory?.inuse == 3_145_728)
        #expect(pending.memory?.oslimit == 4_194_304)

        pending.reset()
        #expect(pending.isEmpty)
    }

    @Test func liveObservationCountsMemoryFrames() {
        var observation = ControllerSessionLiveObservation()
        observation.recordMemorySample(source: .mihomoWebSocket)
        observation.recordMemorySample(source: .mihomoWebSocket)

        #expect(observation.memorySampleCount == 2)
        #expect(observation.diagnosticsSummary.contains("memory-samples=2"))
    }

    @Test func runtimeMaintenanceObservationsTrackConfigurationAndGeoDataActions() {
        var runtime = ControllerSessionRuntimeState()
        runtime.recordConfigurationReload()
        runtime.recordGeoDataUpdate()

        #expect(runtime.configurationReloadCount == 1)
        #expect(runtime.geoDataUpdateCount == 1)
        #expect(runtime.diagnosticsSummary.contains("configuration-reloads=1"))
        #expect(runtime.diagnosticsSummary.contains("geo-data-updates=1"))

        runtime.reset()
        #expect(runtime.configurationReloadCount == 0)
        #expect(runtime.geoDataUpdateCount == 0)
    }

    @MainActor
    @Test func diagnosticsDisplayOneMegabyteForOneMiBOfControllerMemory() throws {
        let model = AppModel(
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.presentationLanguage = .english
        model.controllerSession.runtime.recordMemory(
            MemoryResponse(inuse: 1_048_576, oslimit: 2_097_152)
        )

        let memoryRow = try #require(model.diagnosticsRuntimeOperationRows.first { $0.id == "memory" })

        #expect(memoryRow.evidence.contains("1 MB"))
        #expect(!memoryRow.evidence.contains("1 GB"))
    }
}
