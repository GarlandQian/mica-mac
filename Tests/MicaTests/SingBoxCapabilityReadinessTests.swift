import Foundation
import MicaCore
import Testing
@testable import Mica

struct SingBoxCapabilityReadinessTests {
    @MainActor
    @Test func nativeStartedServiceContractDrivesCapabilityAndReadinessPresentation() throws {
        let (model, profile) = makeModel(liveState: .live, publishesRuntimeState: true)
        let matrix = Dictionary(uniqueKeysWithValues: model.capabilityMatrixRows.map { ($0.id, $0) })
        let adapterRows = Dictionary(
            uniqueKeysWithValues: model.selectedControllerAdapter.capabilities.map { ($0.id, $0) }
        )

        #expect(model.effectiveUnifiedCapabilities(for: profile) == .singBoxCompatible)
        #expect(model.selectedUnifiedCapabilities == .singBoxCompatible)
        #expect(model.selectedControllerAdapter.source == .singBoxStartedServiceGRPC)
        #expect(model.selectedControllerAdapter.source.diagnosticsLabel == "singBoxStartedServiceGRPC")
        #expect(model.coreCompatibilitySummary == .unknownController)
        #expect(model.optionalStreamReadinessState == .ready)

        for id in [
            "test-connection",
            "refresh-snapshot",
            "switch-policy",
            "delay-test",
            "mode-change",
            "close-connection",
            "close-all",
            "traffic-logs",
        ] {
            #expect(try #require(adapterRows[id]).status == .supported)
        }
        #expect(try #require(adapterRows["provider-update"]).status == .unavailable)
        #expect(try #require(adapterRows["rules-providers"]).status == .unavailable)

        for id in [
            "controller-family",
            "adapter-source",
            "version",
            "configs-mode",
            "proxies-groups",
            "group-delay",
            "connections",
            "close-connection",
            "close-all",
            "traffic-stream",
            "logs-stream",
            "traffic-logs",
            "memory",
            "runtime-status",
            "tailscale",
        ] {
            #expect(try #require(matrix[id]).status == .supported)
        }

        for id in [
            "configuration-reload",
            "rules",
            "providers",
            "rules-providers",
            "provider-update",
            "dns-flush",
            "cache-flush",
            "geo-resources",
            "core-actions",
        ] {
            #expect(try #require(matrix[id]).status == .unavailable)
        }

        #expect(try #require(matrix["adapter-source"]).evidence == "sing-box-started-service-grpc")
        #expect(!model.capabilityMatrixRows.contains { $0.evidence.localizedCaseInsensitiveContains("future") })

        let observability = Dictionary(
            uniqueKeysWithValues: model.observabilityReadinessRows.map { ($0.id, $0) }
        )
        #expect(try #require(observability["snapshot-rules"]).state == .unavailable)
        #expect(try #require(observability["snapshot-providers"]).state == .unavailable)
        #expect(try #require(observability["optional-traffic-stream"]).state == .ready)
        #expect(try #require(observability["optional-log-stream"]).state == .ready)
    }

    @MainActor
    @Test func connectingStartedServiceKeepsSupportedStreamsUntestedInsteadOfUnavailable() throws {
        let (model, _) = makeModel(liveState: .connecting, publishesRuntimeState: false)
        let matrix = Dictionary(uniqueKeysWithValues: model.capabilityMatrixRows.map { ($0.id, $0) })
        let adapterRows = Dictionary(
            uniqueKeysWithValues: model.selectedControllerAdapter.capabilities.map { ($0.id, $0) }
        )

        #expect(model.selectedControllerAdapter.source == .singBoxStartedServiceGRPC)
        #expect(model.optionalStreamReadinessState == .controllerCapabilityUnknown)
        #expect(try #require(matrix["adapter-source"]).status == .supported)
        #expect(try #require(matrix["traffic-stream"]).status == .untested)
        #expect(try #require(matrix["logs-stream"]).status == .untested)
        #expect(try #require(matrix["memory"]).status == .untested)
        #expect(try #require(matrix["runtime-status"]).status == .untested)
        #expect(try #require(matrix["tailscale"]).status == .untested)
        #expect(try #require(matrix["rules"]).status == .unavailable)
        #expect(try #require(matrix["providers"]).status == .unavailable)
        #expect(try #require(matrix["configuration-reload"]).status == .unavailable)
        #expect(try #require(adapterRows["traffic-logs"]).status == .untested)
        #expect(try #require(adapterRows["provider-update"]).status == .unavailable)
    }

    @MainActor
    @Test func tailscaleFailureWithoutPriorValueIsFailed() throws {
        let (model, _) = makeModel(liveState: .live, publishesRuntimeState: false)
        model.controllerSession.singBoxTailscaleError = "stream unavailable"

        let matrix = Dictionary(uniqueKeysWithValues: model.capabilityMatrixRows.map { ($0.id, $0) })

        #expect(try #require(matrix["tailscale"]).status == .failed)
    }

    @MainActor
    @Test func tailscaleFailureRetainsPriorValueAsPartial() throws {
        let (model, _) = makeModel(liveState: .live, publishesRuntimeState: true)
        model.controllerSession.singBoxTailscaleError = "stream unavailable"

        let matrix = Dictionary(uniqueKeysWithValues: model.capabilityMatrixRows.map { ($0.id, $0) })

        #expect(try #require(matrix["tailscale"]).status == .partial)
        #expect(model.controllerSession.singBoxTailscaleStatus == SingBoxTailscaleStatus(endpoints: []))
    }

    @MainActor
    private func makeModel(
        liveState: LiveStreamState,
        publishesRuntimeState: Bool
    ) -> (AppModel, RouterProfile) {
        let profile = RouterProfile(
            displayName: "sing-box",
            host: "controller.example",
            controllerKind: .singBoxCompatible
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.activeSessionControllerKind = .singBoxCompatible
        model.liveStreamState = liveState

        var health = ControllerHealthSnapshot.checking(router: profile)
        if publishesRuntimeState {
            health.set(.version, status: .ready("1.14.0-alpha.31"))
            health.set(.configs, status: .ready("rule"))
            health.set(.proxies, status: .ready("2 groups"))
            health.set(.connections, status: .ready("0 active"))
            health.set(.rules, status: .idle)
            health.set(.providers, status: .idle)
            health.finalize()
            model.controllerSession.singBoxStatus = SingBoxStatusSnapshot(
                memoryBytes: 4_096,
                goroutines: 8,
                connectionsIn: 2,
                connectionsOut: 3,
                trafficAvailable: true,
                uplinkBytesPerSecond: 5,
                downlinkBytesPerSecond: 7,
                uplinkTotalBytes: 11,
                downlinkTotalBytes: 13
            )
            model.controllerSession.singBoxTailscaleStatus = SingBoxTailscaleStatus(endpoints: [])
        }
        model.controllerHealth = health

        return (model, profile)
    }
}
