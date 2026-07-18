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
