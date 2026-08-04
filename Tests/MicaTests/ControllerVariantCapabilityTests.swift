import MicaCore
import Testing
@testable import Mica

private actor ControllerConnectionTestRecorder {
    private var requestedKind: ControllerKind?

    func record(_ kind: ControllerKind) {
        requestedKind = kind
    }

    func lastRequestedKind() -> ControllerKind? {
        requestedKind
    }
}

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
    @Test func autoDetectedSingBoxConnectionTestUsesStartedServiceTransport() async {
        let profile = RouterProfile(
            displayName: "sing-box",
            host: "controller.example",
            controllerKind: .autoDetect
        )
        let recorder = ControllerConnectionTestRecorder()
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore(),
            controllerProbeOperation: { _, _, _ in .singBoxCompatible },
            controllerConnectionTestOperation: { _, _, resolvedKind in
                await recorder.record(resolvedKind)
                return .singBox(SingBoxVersion(version: "1.12.0", apiVersion: 7))
            }
        )

        let report = await model.testConnection(draft: model.draft(for: profile))

        #expect(await recorder.lastRequestedKind() == .singBoxCompatible)
        #expect(report.summary == .ready)
        #expect(report.steps.first { $0.id == "adapter" }?.state == .ready)
        #expect(report.steps.first { $0.id == "api-version" }?.value == "7")
        #expect(!report.steps.contains { $0.id == "json" })
    }

    @MainActor
    @Test func singBoxConnectionFailureUsesRPCReportInsteadOfJSONReport() async {
        let profile = RouterProfile(
            displayName: "sing-box",
            host: "controller.example",
            controllerKind: .singBoxCompatible
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore(),
            controllerConnectionTestOperation: { _, _, _ in
                throw SingBoxGRPCError.rpc(code: 16, message: "unauthorized")
            }
        )

        let report = await model.testConnection(draft: model.draft(for: profile))

        #expect(report.summary == .authFailed)
        #expect(report.steps.first { $0.id == "adapter" }?.state == .failed)
        #expect(!report.steps.contains { $0.id == "json" })
    }

    @MainActor
    @Test func autoDetectSingBoxProbeFailureUsesRPCReportInsteadOfJSONReport() async {
        let profile = RouterProfile(
            displayName: "Auto Detect",
            host: "controller.example",
            controllerKind: .autoDetect
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore(),
            controllerProbeOperation: { _, _, _ in
                throw SingBoxGRPCError.rpc(code: 16, message: "unauthorized")
            },
            controllerConnectionTestOperation: { _, _, _ in
                return .singBox(SingBoxVersion(version: "unreachable", apiVersion: 0))
            }
        )

        let report = await model.testConnection(draft: model.draft(for: profile))

        #expect(report.summary == .authFailed)
        #expect(report.steps.first { $0.id == "adapter" }?.state == .failed)
        #expect(!report.steps.contains { $0.id == "json" })
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
