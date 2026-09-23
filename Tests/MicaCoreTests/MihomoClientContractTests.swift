import Foundation
import XCTest
@testable import MicaCore

final class MihomoClientContractTests: XCTestCase {
    func testVersionUsesBearerAuthenticationAndDecodesFixture() async throws {
        let fixture = MihomoHTTPFixture(data: try fixtureData("version-success"))
        let client = makeClient(fixture: fixture)

        let response = try await client.version()
        let requests = await fixture.recordedRequests()
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(response.version, "v1.19.0")
        XCTAssertEqual(response.premium, false)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/version")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.httpBody)
    }

    func testDirectTransportCancellationRemainsCancellation() async throws {
        let profile = RouterProfile(
            displayName: "Cancelled",
            host: "controller.example"
        )
        let client = MihomoClient(profile: profile) { _ in
            throw CancellationError()
        }

        do {
            _ = try await client.version()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // The client must not reclassify cancellation as a network outage.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInvalidProfileFailsBeforeTransport() async throws {
        let profile = RouterProfile(
            displayName: "Invalid",
            host: "bad host"
        )
        let client = MihomoClient(profile: profile)

        do {
            _ = try await client.version()
            XCTFail("Expected invalid URL")
        } catch MihomoClientError.invalidURL(let path) {
            XCTAssertEqual(path, "/version")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConfigsDecodesUpstreamShapedFixture() async throws {
        let fixture = MihomoHTTPFixture(data: try fixtureData("configs-success"))
        let client = makeClient(fixture: fixture)

        let response = try await client.configs()

        XCTAssertEqual(response.mode, "rule")
        XCTAssertEqual(response.modeOptions, ["rule", "global", "direct"])
        XCTAssertEqual(response.allowLan, true)
        XCTAssertEqual(response.tcpConcurrent, true)
        XCTAssertEqual(response.tun?.enable, true)
        XCTAssertEqual(response.mixedPort, 7893)
    }

    func testHTTPReadsKeepProxyAndProviderOrderFromTheController() async throws {
        let profile = RouterProfile(displayName: "Ordered fixture", host: "controller.example")
        let client = MihomoClient(profile: profile) { request in
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            let body: String
            switch url.path {
            case "/proxies":
                body = #"{"proxies":{"Zulu":{"type":"Selector","all":["Last","First"]},"Alpha":{"type":"Direct"}}}"#
            case "/providers/proxies":
                body = #"{"providers":{"Zulu":{"type":"Proxy","proxies":[]},"Alpha":{"type":"Proxy","proxies":[]}}}"#
            case "/providers/rules":
                body = #"{"providers":{"Zulu":{"type":"Rule"},"Alpha":{"type":"Rule"}}}"#
            default:
                throw URLError(.badURL)
            }
            return (Data(body.utf8), response)
        }

        let proxies = try await client.proxies()
        let proxyProviders = try await client.proxyProviders()
        let ruleProviders = try await client.ruleProviders()

        XCTAssertEqual(proxies.proxyOrder, ["Zulu", "Alpha"])
        XCTAssertEqual(proxies.proxies["Zulu"]?.all, ["Last", "First"])
        XCTAssertEqual(proxyProviders.providerList.map(\.name), ["Zulu", "Alpha"])
        XCTAssertEqual(ruleProviders.providerList.map(\.name), ["Zulu", "Alpha"])
    }

    func testSmartWeightsUseControllerEndpointAndPreserveReportedRanks() async throws {
        let data = Data(#"""
        {
          "message": "ok",
          "weights": {
            "Smart Select": [
              { "Name": "Node A", "Rank": "MostUsed" },
              { "Name": "Node B", "Rank": "OccasionalUsed" },
              { "Name": "Node C", "Rank": "RarelyUsed" }
            ]
          }
        }
        """#.utf8)
        let fixture = MihomoHTTPFixture(data: data)
        let client = makeClient(fixture: fixture)

        let response = try await client.smartWeights()
        let requests = await fixture.recordedRequests()
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/group/weights")
        XCTAssertEqual(
            response.weights["Smart Select"],
            [
                SmartNodeRankSnapshot(name: "Node A", rank: "MostUsed"),
                SmartNodeRankSnapshot(name: "Node B", rank: "OccasionalUsed"),
                SmartNodeRankSnapshot(name: "Node C", rank: "RarelyUsed"),
            ]
        )
    }

    func testDeprecatedSmartGroupWeightsEndpointRemainsAvailableAsFallback() async throws {
        let data = Data(#"""
        {
          "message": "ok",
          "weights": [{ "Name": "Node A", "Rank": "MostUsed" }]
        }
        """#.utf8)
        let fixture = MihomoHTTPFixture(data: data)
        let client = makeClient(fixture: fixture)

        let response = try await client.smartGroupWeights(group: "Smart / Select")
        let requests = await fixture.recordedRequests()
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/group/Smart / Select/weights")
        XCTAssertEqual(
            response.weights,
            [SmartNodeRankSnapshot(name: "Node A", rank: "MostUsed")]
        )
    }

    func testSmartWeightsRetriesDeprecatedGroupEndpointsAfterAggregateStatusFailure() async throws {
        let fixture = MihomoSmartWeightsFallbackFixture()
        let profile = RouterProfile(
            displayName: "Fixture Controller",
            host: "controller.example",
            port: 9090,
            controllerKind: .mihomoCompatible
        )
        let client = MihomoClient(profile: profile, secret: "fixture-secret") { request in
            try await fixture.load(request)
        }

        let response = try await client.smartWeights(forGroups: ["Smart A", "Smart B"])
        let requests = await fixture.recordedRequests()
        let paths = requests.compactMap { $0.url?.path }

        XCTAssertEqual(paths.first, "/group/weights")
        XCTAssertEqual(
            Set(paths.dropFirst()),
            Set(["/group/Smart A/weights", "/group/Smart B/weights"])
        )
        XCTAssertEqual(
            response.weights["Smart A"],
            [SmartNodeRankSnapshot(name: "Node A", rank: "MostUsed")]
        )
        XCTAssertEqual(
            response.weights["Smart B"],
            [SmartNodeRankSnapshot(name: "Node B", rank: "RarelyUsed")]
        )
    }

    func testSmartWeightsFallbackPropagatesCancellation() async throws {
        let profile = RouterProfile(
            displayName: "Cancelled",
            host: "controller.example"
        )
        let client = MihomoClient(profile: profile) { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            if url.path == "/group/weights" {
                let response = try XCTUnwrap(
                    HTTPURLResponse(
                        url: url,
                        statusCode: 500,
                        httpVersion: "HTTP/1.1",
                        headerFields: nil
                    )
                )
                return (Data(), response)
            }
            throw CancellationError()
        }

        do {
            _ = try await client.smartWeights(forGroups: ["Smart A"])
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // A fallback child cancellation must fail the structured group.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConfigurationReloadSendsPutWithAnEmptyJSONObject() async throws {
        let fixture = MihomoHTTPFixture(statusCode: 204)
        let client = makeClient(fixture: fixture)

        try await client.reloadConfigs()
        let requests = await fixture.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/configs")
        XCTAssertNil(request.url?.query)
        XCTAssertTrue(object.isEmpty)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testGeoDataUpdateUsesPostWithoutRequestBody() async throws {
        let fixture = MihomoHTTPFixture(statusCode: 204)
        let client = makeClient(fixture: fixture)

        try await client.updateGeoData()
        let requests = await fixture.recordedRequests()
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/configs/geo")
        XCTAssertNil(request.httpBody)
    }

    func testProviderHealthCheckUsesGetWithoutRequestBody() async throws {
        let fixture = MihomoHTTPFixture(statusCode: 204)
        let client = makeClient(fixture: fixture)

        try await client.healthCheckProxyProvider(name: "Airport A")
        let requests = await fixture.recordedRequests()
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/providers/proxies/Airport A/healthcheck")
        XCTAssertNil(request.httpBody)
    }

    func testCloseConnectionRejectsBlankIDBeforeSendingARequest() async throws {
        let fixture = MihomoHTTPFixture(statusCode: 204)
        let client = makeClient(fixture: fixture)

        do {
            try await client.closeConnection(id: "  \n")
            XCTFail("Expected blank connection ID to be rejected")
        } catch MihomoClientError.invalidURL(let path) {
            XCTAssertEqual(path, "/connections")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await fixture.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testSingleProxyDelayUsesOfficialPathAndQuery() async throws {
        let fixture = MihomoHTTPFixture(data: Data(#"{"delay":86}"#.utf8))
        let client = makeClient(fixture: fixture)

        let response = try await client.proxyDelay(
            name: "Node A",
            url: "https://probe.example/generate_204",
            timeout: 3_210
        )
        let requests = await fixture.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))

        XCTAssertEqual(response.delay, 86)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/proxies/Node A/delay")
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: (query.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }),
            [
                "url": "https://probe.example/generate_204",
                "timeout": "3210",
            ]
        )
        XCTAssertNil(request.httpBody)
    }

    func testProviderProxyDelayUsesProviderScopedOfficialPath() async throws {
        let fixture = MihomoHTTPFixture(data: Data(#"{"delay":123}"#.utf8))
        let client = makeClient(fixture: fixture)

        let response = try await client.providerProxyDelay(
            provider: "Remote Nodes",
            name: "Node B",
            url: "https://probe.example/204",
            timeout: 4_000
        )
        let requests = await fixture.recordedRequests()
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(response.delay, 123)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/providers/proxies/Remote Nodes/Node B/healthcheck")
        XCTAssertNil(request.httpBody)
    }

    func testUnauthorizedResponseUsesTheAuthenticationErrorBoundary() async throws {
        let fixture = MihomoHTTPFixture(statusCode: 401)
        let client = makeClient(fixture: fixture)

        do {
            _ = try await client.version()
            XCTFail("Expected unauthorized error")
        } catch MihomoClientError.unauthorized {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedReadFixtureReportsTheEndpointPath() async throws {
        let fixture = MihomoHTTPFixture(data: try fixtureData("malformed"))
        let client = makeClient(fixture: fixture)

        do {
            _ = try await client.version()
            XCTFail("Expected malformed response error")
        } catch MihomoClientError.malformedResponse(let path) {
            XCTAssertEqual(path, "/version")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWebSocketNSErrorTransportFailureUsesTransientNetworkBoundary() async {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.networkConnectionLost.rawValue
        )

        switch MihomoClient.clientError(for: error) {
        case .connectionFailure(let reason):
            XCTAssertEqual(reason, .other)
        default:
            XCTFail("Expected a transient network failure")
        }
    }

    private func makeClient(fixture: MihomoHTTPFixture) -> MihomoClient {
        let profile = RouterProfile(
            displayName: "Fixture Controller",
            host: "controller.example",
            port: 9090,
            controllerKind: .mihomoCompatible
        )

        return MihomoClient(profile: profile, secret: "fixture-secret") { request in
            try await fixture.load(request)
        }
    }

    private func fixtureData(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/Mihomo"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}

private actor MihomoHTTPFixture {
    private let statusCode: Int
    private let data: Data
    private var requests: [URLRequest] = []

    init(statusCode: Int = 200, data: Data = Data()) {
        self.statusCode = statusCode
        self.data = data
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private actor MihomoSmartWeightsFallbackFixture {
    private var requests: [URLRequest] = []

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard let url = request.url else {
            throw URLError(.badURL)
        }

        let statusCode: Int
        let data: Data
        switch url.path {
        case "/group/weights":
            statusCode = 404
            data = Data()
        case "/group/Smart A/weights":
            statusCode = 200
            data = Data(#"{"weights":[{"Name":"Node A","Rank":"MostUsed"}]}"#.utf8)
        case "/group/Smart B/weights":
            statusCode = 200
            data = Data(#"{"weights":[{"Name":"Node B","Rank":"RarelyUsed"}]}"#.utf8)
        default:
            statusCode = 500
            data = Data()
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}
