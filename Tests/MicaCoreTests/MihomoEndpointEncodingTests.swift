import Foundation
import XCTest
@testable import MicaCore

final class MihomoEndpointEncodingTests: XCTestCase {
    func testDynamicNamesRemainSingleRouteParameters() throws {
        let base = try XCTUnwrap(URL(string: "http://controller.example:9090/api%2Fgateway/"))
        for name in ["Auto / Fallback", "香港 🇭🇰", "literal%2Fname", "a?b#c&d+e", ".", ".."] {
            let endpoints = [
                MihomoEndpoint.selectProxy(group: name),
                .clearFixedProxy(group: name),
                .closeConnection(id: name),
                .groupDelay(group: name, url: "https://example.com/a?b=1&c=2", timeout: 5000),
                .smartGroupWeights(group: name),
                .proxyDelay(name: name, url: "https://example.com", timeout: 5000),
                .providerProxyDelay(provider: name, name: name, url: "https://example.com", timeout: 5000),
                .updateProxyProvider(name: name),
                .healthCheckProxyProvider(name: name),
                .updateRuleProvider(name: name),
            ]
            for endpoint in endpoints {
                let url = try endpoint.url(relativeTo: base)
                let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
                let segments = components.percentEncodedPath.split(separator: "/").map(String.init)
                XCTAssertEqual(segments.first, "api%2Fgateway")
                XCTAssertEqual(segments.dropFirst().compactMap(\.removingPercentEncoding), endpoint.pathComponents)
                XCTAssertEqual(components.queryItems ?? [], endpoint.queryItems)
                XCTAssertNil(components.fragment)
            }
        }
    }

    func testBasePrefixesAndRootDoNotGainExtraSeparators() throws {
        for prefix in ["", "/", "/api", "/api/"] {
            let base = try XCTUnwrap(URL(string: "http://controller.example:9090\(prefix)?old=value"))
            let root = try MihomoEndpoint.root.url(relativeTo: base)
            XCTAssertNil(URLComponents(url: root, resolvingAgainstBaseURL: false)?.query)
            let expectedPrefix = prefix.isEmpty || prefix == "/" ? "" : "/api"
            XCTAssertEqual(try MihomoEndpoint.version.url(relativeTo: base).absoluteString,
                           "http://controller.example:9090\(expectedPrefix)/version")
        }
    }
}
