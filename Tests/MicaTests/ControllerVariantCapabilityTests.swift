import MicaCore
import Testing
@testable import Mica

struct ControllerVariantCapabilityTests {
    @MainActor
    @Test func stashCapabilityMatrixUsesDelayFallbackButHidesUnsupportedRuntimeOperations() throws {
        let model = readyModel(runtimeKind: .stashCompatible)
        let rows = Dictionary(uniqueKeysWithValues: model.capabilityMatrixRows.map { ($0.id, $0) })

        #expect(try #require(rows["configs-mode"]).status == .supported)
        #expect(try #require(rows["group-delay"]).status == .supported)
        #expect(try #require(rows["configuration-reload"]).status == .unavailable)
        #expect(try #require(rows["dns-flush"]).status == .unavailable)
        #expect(try #require(rows["cache-flush"]).status == .unavailable)
        #expect(try #require(rows["memory"]).status == .unavailable)
        #expect(try #require(rows["core-actions"]).status == .unavailable)
    }

    @MainActor
    @Test func cmfaCapabilityMatrixKeepsCacheAndMemoryButNotConfigurationWrites() throws {
        let model = readyModel(runtimeKind: .cmfaCompatible)
        let rows = Dictionary(uniqueKeysWithValues: model.capabilityMatrixRows.map { ($0.id, $0) })

        #expect(try #require(rows["configuration-reload"]).status == .unavailable)
        #expect(try #require(rows["dns-flush"]).status == .supported)
        #expect(try #require(rows["cache-flush"]).status == .supported)
        #expect(try #require(rows["memory"]).status == .supported)
        #expect(try #require(rows["core-actions"]).status == .unavailable)
    }

    @MainActor
    @Test func legacyCombinedProfileUsesDetectedAdapterWithoutRewritingSavedKind() {
        let profile = RouterProfile(
            displayName: "Legacy Stash / CMFA",
            host: "controller.example",
            controllerKind: .stashCmfaCompatible
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.activeSessionControllerKind = .stashCompatible

        let adapter = model.makeUnifiedAdapter(for: profile)

        #expect(profile.controllerKind == .stashCmfaCompatible)
        #expect(model.routers.first?.controllerKind == .stashCmfaCompatible)
        #expect(adapter.controllerType == .stashCompatible)
        #expect(adapter.capabilities == .stashCompatible)
    }

    @MainActor
    private func readyModel(runtimeKind: ControllerKind) -> AppModel {
        let profile = RouterProfile(
            displayName: runtimeKind.label,
            host: "controller.example",
            controllerKind: .stashCmfaCompatible
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.controllerSession.begin(controllerID: profile.id)
        model.activeSessionControllerKind = runtimeKind
        model.liveStreamState = .live

        var health = ControllerHealthSnapshot.checking(router: profile)
        for endpoint in ControllerEndpointKind.allCases {
            health.set(endpoint, status: .ready("ready"))
        }
        health.finalize()
        model.controllerHealth = health
        return model
    }
}
