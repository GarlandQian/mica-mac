import Foundation
import XCTest
@testable import MicaCore

final class UnifiedControllerModelsTests: XCTestCase {
    func testMihomoAdapterSnapshotPropagatesOptionalEndpointCancellation() async throws {
        let profile = RouterProfile(
            displayName: "Cancelled Adapter",
            host: "controller.example",
            controllerKind: .mihomoCompatible
        )
        let fixture = MihomoAdapterCancellationFixture()
        let client = MihomoClient(profile: profile) { request in
            try await fixture.load(request)
        }
        let adapter = MihomoCompatibleControllerAdapter(profile: profile, client: client)

        do {
            _ = try await adapter.snapshot()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            let paths = await fixture.recordedPaths()
            XCTAssertTrue(paths.contains("/rules"))
            XCTAssertFalse(paths.contains("/providers/proxies"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSingBoxAdapterIsNativeAndCombinedStashHintStaysCapabilityOnly() {
        let singBox = RouterProfile(
            displayName: "sing-box",
            host: "controller.example",
            controllerKind: .singBoxCompatible
        )
        let stash = RouterProfile(
            displayName: "Stash",
            host: "controller.example",
            controllerKind: .stashCmfaCompatible
        )

        XCTAssertEqual(singBox.unifiedControllerType, .singBoxCompatible)
        XCTAssertEqual(stash.unifiedControllerType, .stashCmfaCompatible)
        XCTAssertEqual(UnifiedControllerAdapterRegistry.capabilities(for: singBox), .singBoxCompatible)
        XCTAssertEqual(UnifiedControllerAdapterRegistry.capabilities(for: stash), .none)
        XCTAssertEqual(UnifiedControllerAdapterRegistry.adapterSource(for: .singBoxCompatible), "sing-box-started-service-grpc")
        XCTAssertEqual(UnifiedControllerAdapterRegistry.adapterSource(for: .stashCmfaCompatible), "stash-cmfa-api-unavailable")
        XCTAssertTrue(
            UnifiedControllerAdapterRegistry.makeAdapter(profile: singBox, credential: nil)
                is SingBoxControllerAdapter
        )
        XCTAssertTrue(ControllerCapabilities.singBoxCompatible.supports(.switchPolicy))
        XCTAssertTrue(ControllerCapabilities.singBoxCompatible.supports(.testLatency))
        XCTAssertTrue(ControllerCapabilities.singBoxCompatible.supports(.changeMode))
        XCTAssertTrue(ControllerCapabilities.singBoxCompatible.supports(.closeConnection))
        XCTAssertTrue(ControllerCapabilities.singBoxCompatible.logs)
        XCTAssertFalse(ControllerCapabilities.singBoxCompatible.supports(.clearFixedSelection))
        XCTAssertFalse(ControllerCapabilities.singBoxCompatible.supports(.setLogLevel))
        XCTAssertFalse(ControllerCapabilities.singBoxCompatible.supports(.reloadConfiguration))
        XCTAssertFalse(ControllerCapabilities.singBoxCompatible.supports(.dnsFlush))
    }

    func testDNSFlushCapabilityMatchesSupportedRemoteAPIs() {
        XCTAssertTrue(ControllerCapabilities.mihomoCompatible.supports(.dnsFlush))
        XCTAssertTrue(ControllerCapabilities.surgeHTTPAPI.supports(.dnsFlush))
        XCTAssertFalse(ControllerCapabilities.none.supports(.dnsFlush))
        XCTAssertFalse(ControllerCapabilities.probeReadiness.supports(.dnsFlush))
    }

    func testFixedSelectionCancellationIsClashCompatibleOnly() {
        XCTAssertTrue(ControllerCapabilities.mihomoCompatible.supports(.clearFixedSelection))
        XCTAssertTrue(ControllerCapabilities.cmfaCompatible.supports(.clearFixedSelection))
        XCTAssertTrue(ControllerCapabilities.stashCompatible.supports(.clearFixedSelection))
        XCTAssertFalse(ControllerCapabilities.singBoxCompatible.supports(.clearFixedSelection))
        XCTAssertFalse(ControllerCapabilities.surgeHTTPAPI.supports(.clearFixedSelection))
        XCTAssertFalse(ControllerCapabilities.none.supports(.clearFixedSelection))
        XCTAssertFalse(ControllerCapabilities.probeReadiness.supports(.clearFixedSelection))
    }

    func testMihomoSnapshotProjectionUsesTheResolvedVariantCapabilities() {
        let profile = RouterProfile(
            displayName: "Stash",
            host: "controller.example",
            controllerKind: .stashCompatible
        )
        let snapshot = UnifiedControllerSnapshot.mihomoCompatible(
            profile: profile,
            controllerType: .stashCompatible,
            version: VersionResponse(version: "stash"),
            config: ConfigResponse(),
            proxies: ProxiesResponse(proxies: [:], proxyOrder: []),
            connections: ConnectionsResponse(connections: []),
            rules: nil,
            providers: nil
        )

        XCTAssertEqual(snapshot.controllerType, .stashCompatible)
        XCTAssertEqual(snapshot.capabilities, .stashCompatible)
        XCTAssertFalse(snapshot.capabilities.memory)
        XCTAssertFalse(snapshot.capabilities.supports(.flushFakeIP))
        XCTAssertTrue(snapshot.capabilities.supports(.testLatency))
    }

    func testCapabilityDiagnosticsIncludeIndependentLogsAndFixedSelectionFlags() {
        let diagnostics = ControllerCapabilities.singBoxCompatible.diagnosticsLabel

        XCTAssertTrue(diagnostics.contains("logs=true"))
        XCTAssertTrue(diagnostics.contains("fixed-selection-clear=false"))
    }

    func testRuleMutationIsMihomoOnly() {
        XCTAssertTrue(ControllerCapabilities.mihomoCompatible.supports(.setRuleDisabled))
        XCTAssertFalse(ControllerCapabilities.surgeHTTPAPI.supports(.setRuleDisabled))
        XCTAssertFalse(ControllerCapabilities.none.supports(.setRuleDisabled))
        XCTAssertFalse(ControllerCapabilities.probeReadiness.supports(.setRuleDisabled))
    }

    func testSurgeProfileReloadAndControllerLogLevelCapabilitiesAreExplicit() {
        XCTAssertTrue(ControllerCapabilities.surgeHTTPAPI.supports(.reloadProfile))
        XCTAssertFalse(ControllerCapabilities.mihomoCompatible.supports(.reloadProfile))
        XCTAssertFalse(ControllerCapabilities.none.supports(.reloadProfile))

        XCTAssertTrue(ControllerCapabilities.surgeHTTPAPI.supports(.setLogLevel))
        XCTAssertTrue(ControllerCapabilities.mihomoCompatible.supports(.setLogLevel))
        XCTAssertFalse(ControllerCapabilities.probeReadiness.supports(.setLogLevel))
    }

    func testMihomoRuntimeConfigCapabilitiesAreFieldSpecific() {
        for action in [
            UnifiedControllerAction.setAllowLAN,
            .setIPv6,
            .setTCPConcurrent,
            .setTUN,
            .setPort,
        ] {
            XCTAssertTrue(ControllerCapabilities.mihomoCompatible.supports(action))
            XCTAssertFalse(ControllerCapabilities.surgeHTTPAPI.supports(action))
            XCTAssertFalse(ControllerCapabilities.none.supports(action))
        }
    }

    func testProviderHealthCheckCapabilityIsMihomoOnly() {
        XCTAssertTrue(ControllerCapabilities.mihomoCompatible.supports(.healthCheckProvider))
        XCTAssertFalse(ControllerCapabilities.surgeHTTPAPI.supports(.healthCheckProvider))
        XCTAssertFalse(ControllerCapabilities.none.supports(.healthCheckProvider))
        XCTAssertFalse(ControllerCapabilities.probeReadiness.supports(.healthCheckProvider))
    }

    func testMihomoRemoteMaintenanceCapabilitiesAreExplicit() {
        for action in [
            UnifiedControllerAction.reloadConfiguration,
            .updateGeoData,
            .flushFakeIP,
        ] {
            XCTAssertTrue(ControllerCapabilities.mihomoCompatible.supports(action))
            XCTAssertFalse(ControllerCapabilities.surgeHTTPAPI.supports(action))
            XCTAssertFalse(ControllerCapabilities.none.supports(action))
            XCTAssertFalse(ControllerCapabilities.probeReadiness.supports(action))
        }
    }

    func testCMFAAndStashRuntimeCapabilitiesStayDistinct() {
        let cmfa = RouterProfile(
            displayName: "CMFA",
            host: "controller.example",
            controllerKind: .cmfaCompatible
        )
        let stash = RouterProfile(
            displayName: "Stash",
            host: "controller.example",
            controllerKind: .stashCompatible
        )

        XCTAssertEqual(cmfa.unifiedControllerType, .cmfaCompatible)
        XCTAssertEqual(stash.unifiedControllerType, .stashCompatible)
        XCTAssertEqual(UnifiedControllerAdapterRegistry.capabilities(for: cmfa), .cmfaCompatible)
        XCTAssertEqual(UnifiedControllerAdapterRegistry.capabilities(for: stash), .stashCompatible)

        XCTAssertTrue(ControllerCapabilities.cmfaCompatible.memory)
        XCTAssertTrue(ControllerCapabilities.cmfaCompatible.supports(.flushFakeIP))
        XCTAssertFalse(ControllerCapabilities.cmfaCompatible.supports(.changeMode))
        XCTAssertFalse(ControllerCapabilities.cmfaCompatible.supports(.reloadConfiguration))

        XCTAssertFalse(ControllerCapabilities.stashCompatible.memory)
        XCTAssertTrue(ControllerCapabilities.stashCompatible.supports(.changeMode))
        XCTAssertTrue(ControllerCapabilities.stashCompatible.supports(.setLogLevel))
        XCTAssertTrue(ControllerCapabilities.stashCompatible.supports(.testLatency))
        XCTAssertFalse(ControllerCapabilities.stashCompatible.supports(.flushFakeIP))
    }

    func testSingBoxSnapshotProjectionPreservesGroupAndNodeOrder() {
        let profile = RouterProfile(
            displayName: "sing-box",
            host: "controller.example",
            controllerKind: .singBoxCompatible
        )
        let groups = SingBoxPolicyCatalog(groups: [
            SingBoxPolicyGroup(
                tag: "Proxy B",
                type: "selector",
                selectable: true,
                selected: "Node 2",
                isExpandedByController: false,
                items: [
                    SingBoxPolicyNode(tag: "Node 2", type: "shadowsocks", urlTestTimestamp: 2, urlTestDelayMilliseconds: 88),
                    SingBoxPolicyNode(tag: "Node 1", type: "vmess", urlTestTimestamp: 1, urlTestDelayMilliseconds: 42),
                ]
            ),
            SingBoxPolicyGroup(
                tag: "GLOBAL",
                type: "selector",
                selectable: true,
                selected: "Proxy B",
                isExpandedByController: false,
                items: [
                    SingBoxPolicyNode(tag: "Proxy B", type: "selector", urlTestTimestamp: 0, urlTestDelayMilliseconds: 0),
                ]
            ),
        ])

        let snapshot = UnifiedControllerSnapshot.singBox(
            profile: profile,
            version: SingBoxVersion(version: "1.14.0-alpha.31", apiVersion: 7),
            status: SingBoxStatusSnapshot(
                memoryBytes: 1_024,
                goroutines: 4,
                connectionsIn: 1,
                connectionsOut: 2,
                trafficAvailable: true,
                uplinkBytesPerSecond: 3,
                downlinkBytesPerSecond: 5,
                uplinkTotalBytes: 7,
                downlinkTotalBytes: 11
            ),
            groups: groups,
            mode: SingBoxClashModeStatus(availableModes: ["rule", "global"], currentMode: "rule")
        )

        XCTAssertEqual(snapshot.controllerType, .singBoxCompatible)
        XCTAssertEqual(snapshot.policyGroups.map(\.displayLabel), ["Proxy B", "GLOBAL"])
        XCTAssertEqual(snapshot.policyGroups[0].selectedDisplayLabel, "Node 2")
        XCTAssertEqual(snapshot.policyGroups[0].optionCount, 2)
        XCTAssertEqual(snapshot.policyGroups[0].latencyBuckets["fast"], 1)
        XCTAssertEqual(snapshot.policyGroups[0].latencyBuckets["normal"], 1)
        XCTAssertEqual(snapshot.traffic, UnifiedTrafficSnapshot(upload: 3, download: 5))
        XCTAssertEqual(snapshot.modeLabel, "rule")
    }
}

private actor MihomoAdapterCancellationFixture {
    private var paths: [String] = []

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            throw URLError(.badServerResponse)
        }

        paths.append(url.path)
        let data: Data
        switch url.path {
        case "/version": data = Data(#"{"version":"v1"}"#.utf8)
        case "/configs": data = Data(#"{"mode":"rule"}"#.utf8)
        case "/proxies": data = Data(#"{"proxies":{}}"#.utf8)
        case "/connections": data = Data(#"{"connections":[]}"#.utf8)
        case "/rules": throw CancellationError()
        case "/providers/proxies", "/providers/rules": data = Data(#"{"providers":{}}"#.utf8)
        default: throw URLError(.unsupportedURL)
        }
        return (data, response)
    }

    func recordedPaths() -> [String] {
        paths
    }
}
