import Foundation
import XCTest
@testable import MicaCore

final class MihomoGroupDelayFallbackTests: XCTestCase {
    func testGroupDelayFallsBackToBoundedNodeAndProviderRequestsAfter404() async throws {
        let fixture = GroupDelayFixture(
            proxies: try fixtureData("proxies-stash-group"),
            delays: [
                "/proxies/Node A/delay": .json(#"{"delay":42}"#),
                "/providers/proxies/airport/Node B/healthcheck": .json(#"{"delay":55}"#),
                "/proxies/Node C/delay": .status(500),
            ]
        )
        let client = makeClient(fixture: fixture)

        let response = try await client.groupDelay(
            group: "Proxy",
            url: "https://cp.cloudflare.com/generate_204",
            timeout: 3000
        )
        let requests = await fixture.recordedRequests()

        XCTAssertEqual(response.delay, ["Node A": 42, "Node B": 55, "Node C": 0])
        XCTAssertTrue(requests.contains { $0.url?.path == "/group/Proxy/delay" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/proxies" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/proxies/Node A/delay" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/providers/proxies/airport/Node B/healthcheck" })

        let delayRequests = requests.filter { $0.url?.path.hasSuffix("/delay") == true || $0.url?.path.hasSuffix("/healthcheck") == true }
        for request in delayRequests {
            let queryItems = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertTrue(queryItems?.contains(URLQueryItem(name: "url", value: "https://cp.cloudflare.com/generate_204")) == true)
            XCTAssertTrue(queryItems?.contains(URLQueryItem(name: "timeout", value: "3000")) == true)
        }
    }

    func testStashCanForceMemberFallbackWithoutCallingUnsupportedGroupEndpoint() async throws {
        let fixture = GroupDelayFixture(
            proxies: try fixtureData("proxies-stash-group"),
            delays: [
                "/proxies/Node A/delay": .json(#"{"delay":42}"#),
                "/providers/proxies/airport/Node B/healthcheck": .json(#"{"delay":55}"#),
                "/proxies/Node C/delay": .json(#"{"delay":63}"#),
            ]
        )
        let client = makeClient(fixture: fixture)

        let response = try await client.groupDelay(
            group: "Proxy",
            forceMemberFallback: true
        )
        let requests = await fixture.recordedRequests()

        XCTAssertEqual(response.delay, ["Node A": 42, "Node B": 55, "Node C": 63])
        XCTAssertFalse(requests.contains { $0.url?.path == "/group/Proxy/delay" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/proxies" })
    }

    private func makeClient(fixture: GroupDelayFixture) -> MihomoClient {
        let profile = RouterProfile(
            displayName: "Stash Fixture",
            host: "controller.example",
            controllerKind: .stashCompatible
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

private actor GroupDelayFixture {
    struct Route: Sendable {
        var statusCode: Int
        var data: Data

        static func status(_ statusCode: Int) -> Route {
            Route(statusCode: statusCode, data: Data())
        }

        static func json(_ value: String) -> Route {
            Route(statusCode: 200, data: Data(value.utf8))
        }
    }

    private let proxies: Data
    private let delays: [String: Route]
    private var requests: [URLRequest] = []

    init(proxies: Data, delays: [String: Route]) {
        self.proxies = proxies
        self.delays = delays
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard let url = request.url else {
            throw URLError(.badURL)
        }

        let route: Route
        switch url.path {
        case "/group/Proxy/delay":
            route = .status(404)
        case "/proxies":
            route = Route(statusCode: 200, data: proxies)
        default:
            route = delays[url.path] ?? .status(404)
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: route.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            throw URLError(.badServerResponse)
        }
        return (route.data, response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}
