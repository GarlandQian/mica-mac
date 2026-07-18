import Foundation
import XCTest
@testable import MicaCore

final class ControllerHTTPProbeResolverTests: XCTestCase {
    func testAutoProbeDetectsMihomoFromVersionFixture() async throws {
        let fixture = ControllerProbeFixture(routes: [
            "/version": .json(try fixtureData("Mihomo/version-success")),
        ])

        let kind = try await resolver(fixture: fixture).resolve(
            profile: profile(),
            credential: "fixture-secret"
        )

        XCTAssertEqual(kind, .mihomoCompatible)
    }

    func testAutoProbeDetectsCMFAFromVersionText() async throws {
        let fixture = ControllerProbeFixture(routes: [
            "/version": .json(try fixtureData("Mihomo/cmfa-version")),
        ])

        let kind = try await resolver(fixture: fixture).resolve(
            profile: profile(),
            credential: "fixture-secret"
        )

        XCTAssertEqual(kind, .cmfaCompatible)
    }

    func testAutoProbeDetectsStashThroughRootFallback() async throws {
        let fixture = ControllerProbeFixture(routes: [
            "/version": .status(404),
            "/": .json(try fixtureData("Mihomo/stash-root")),
        ])

        let kind = try await resolver(fixture: fixture).resolve(
            profile: profile(),
            credential: "fixture-secret"
        )

        XCTAssertEqual(kind, .stashCompatible)
    }

    func testAutoProbeDetectsSurgeWhenClashEndpointsDoNotMatch() async throws {
        let fixture = ControllerProbeFixture(routes: [
            "/v1/outbound": .json(try fixtureData("Surge/outbound-success")),
        ])

        let kind = try await resolver(fixture: fixture).resolve(
            profile: profile(),
            credential: "fixture-key"
        )

        XCTAssertEqual(kind, .surgeCompatible)
    }

    func testCombinedStashCMFAHintSkipsSurgeProbe() async throws {
        let fixture = ControllerProbeFixture(routes: [
            "/version": .status(404),
            "/": .json(try fixtureData("Mihomo/stash-root")),
            "/v1/outbound": .json(try fixtureData("Surge/outbound-success")),
        ])

        let kind = try await resolver(fixture: fixture).resolve(
            profile: profile(kind: .stashCmfaCompatible),
            credential: "fixture-secret",
            includeSurge: false
        )
        let requests = await fixture.recordedRequests()

        XCTAssertEqual(kind, .stashCompatible)
        XCTAssertFalse(requests.contains { $0.url?.path == "/v1/outbound" })
    }

    func testAuthenticationFailureDoesNotBecomeAnotherBackend() async throws {
        let fixture = ControllerProbeFixture(defaultRoute: .status(401))

        do {
            _ = try await resolver(fixture: fixture).resolve(
                profile: profile(),
                credential: "wrong-secret"
            )
            XCTFail("Expected authentication failure")
        } catch MihomoClientError.unauthorized {
            // The resolver preserves the authentication error family.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func resolver(fixture: ControllerProbeFixture) -> ControllerHTTPProbeResolver {
        ControllerHTTPProbeResolver { request in
            try await fixture.load(request)
        }
    }

    private func profile(kind: ControllerKind = .autoDetect) -> RouterProfile {
        RouterProfile(
            displayName: "Fixture Controller",
            host: "controller.example",
            port: 9090,
            controllerKind: kind
        )
    }

    private func fixtureData(_ relativePath: String) throws -> Data {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let name = components.last else {
            throw CocoaError(.fileNoSuchFile)
        }
        let subdirectory = (["Fixtures"] + components.dropLast()).joined(separator: "/")
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: subdirectory
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}

private actor ControllerProbeFixture {
    struct Route: Sendable {
        var statusCode: Int
        var data: Data

        static func status(_ statusCode: Int) -> Route {
            Route(statusCode: statusCode, data: Data())
        }

        static func json(_ data: Data) -> Route {
            Route(statusCode: 200, data: data)
        }
    }

    private let routes: [String: Route]
    private let defaultRoute: Route
    private var requests: [URLRequest] = []

    init(routes: [String: Route] = [:], defaultRoute: Route = .status(404)) {
        self.routes = routes
        self.defaultRoute = defaultRoute
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        let path = url.path.isEmpty ? "/" : url.path
        let route = routes[path] ?? defaultRoute
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
