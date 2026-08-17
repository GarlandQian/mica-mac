import XCTest
@testable import MicaCore

final class SurgeHttpAPIClientTests: XCTestCase {
    func testDirectTransportCancellationRemainsCancellation() async throws {
        let profile = RouterProfile(
            displayName: "Cancelled Surge",
            host: "controller.example",
            port: 6171,
            controllerKind: .surgeCompatible
        )
        let client = SurgeHttpAPIClient(profile: profile) { _ in
            throw CancellationError()
        }

        do {
            _ = try await client.outbound()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // The client must not reclassify cancellation as a network outage.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSnapshotPropagatesCancellationFromOptionalEndpoint() async throws {
        let profile = RouterProfile(
            displayName: "Cancelled Surge Snapshot",
            host: "controller.example",
            port: 6171,
            controllerKind: .surgeCompatible
        )
        let fixture = SurgeSnapshotCancellationFixture()
        let client = SurgeHttpAPIClient(profile: profile) { request in
            try await fixture.load(request)
        }

        do {
            _ = try await client.snapshot()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            let paths = await fixture.recordedPaths()
            XCTAssertEqual(paths.last, "/v1/requests/recent")
            XCTAssertFalse(paths.contains("/v1/rules"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private let decoder = JSONDecoder()

    func testSelectPolicyUsesOfficialMethodPathAndBody() async throws {
        let fixture = SurgeHTTPFixture(statusCode: 204)
        let client = makeClient(fixture: fixture)

        try await client.selectPolicy(group: "Proxy Group", policy: "JP-01")

        let requests = await fixture.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try jsonBody(of: request)

        XCTAssertEqual(request.httpMethod, HTTPMethod.post.rawValue)
        XCTAssertEqual(request.url?.path, "/v1/policy_groups/select")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(body["group_name"] as? String, "Proxy Group")
        XCTAssertEqual(body["policy"] as? String, "JP-01")
    }

    func testPolicyGroupTestUsesOfficialMethodPathAndBody() async throws {
        let fixture = SurgeHTTPFixture(
            data: Data(#"{"delay":{"JP-01":42,"US-02":0}}"#.utf8)
        )
        let client = makeClient(fixture: fixture)

        let response = try await client.testPolicyGroup("Proxy Group")

        let requests = await fixture.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try jsonBody(of: request)

        XCTAssertEqual(response.delay, ["JP-01": 42, "US-02": 0])
        XCTAssertEqual(request.httpMethod, HTTPMethod.post.rawValue)
        XCTAssertEqual(request.url?.path, "/v1/policy_groups/test")
        XCTAssertEqual(body["group_name"] as? String, "Proxy Group")
    }

    func testKillActiveRequestUsesOfficialMethodPathAndNumericBody() async throws {
        let fixture = SurgeHTTPFixture(statusCode: 204)
        let client = makeClient(fixture: fixture)

        try await client.killActiveRequest(id: "12345")

        let requests = await fixture.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try jsonBody(of: request)

        XCTAssertEqual(request.httpMethod, HTTPMethod.post.rawValue)
        XCTAssertEqual(request.url?.path, "/v1/requests/kill")
        XCTAssertEqual((body["id"] as? NSNumber)?.intValue, 12345)
    }

    func testKillActiveRequestPreservesOpaqueStringIdentifier() async throws {
        let fixture = SurgeHTTPFixture(statusCode: 204)
        let client = makeClient(fixture: fixture)

        try await client.killActiveRequest(id: "request-A7")

        let requests = await fixture.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try jsonBody(of: request)

        XCTAssertEqual(body["id"] as? String, "request-A7")
    }

    func testDNSCacheEndpointUsesOfficialSurgeHTTPAPIPath() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://controller.example:6171"))
        let endpoint = SurgeEndpoint.dnsCache

        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.pathDescription, "/v1/dns")
        XCTAssertEqual(try endpoint.url(relativeTo: baseURL).absoluteString, "http://controller.example:6171/v1/dns")
    }

    func testDNSFlushEndpointUsesOfficialSurgeHTTPAPIPath() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://controller.example:6171"))
        let endpoint = SurgeEndpoint.flushDNSCache()

        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.pathDescription, "/v1/dns/flush")
        XCTAssertEqual(try endpoint.url(relativeTo: baseURL).absoluteString, "http://controller.example:6171/v1/dns/flush")
    }

    func testReloadProfileUsesOfficialMethodPathAndEmptyObjectBody() async throws {
        let fixture = SurgeHTTPFixture(statusCode: 204)
        let client = makeClient(fixture: fixture)

        try await client.reloadProfile()

        let requests = await fixture.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try jsonBody(of: request)

        XCTAssertEqual(request.httpMethod, HTTPMethod.post.rawValue)
        XCTAssertEqual(request.url?.path, "/v1/profiles/reload")
        XCTAssertTrue(body.isEmpty)
    }

    func testSetLogLevelUsesOfficialMethodPathAndBody() async throws {
        let fixture = SurgeHTTPFixture(statusCode: 204)
        let client = makeClient(fixture: fixture)

        try await client.setLogLevel("verbose")

        let requests = await fixture.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try jsonBody(of: request)

        XCTAssertEqual(request.httpMethod, HTTPMethod.post.rawValue)
        XCTAssertEqual(request.url?.path, "/v1/log/level")
        XCTAssertEqual(body["level"] as? String, "verbose")
    }

    func testActiveRequestsDecodeTopLevelArrayAliasesSpeedsAndUnknownFields() async throws {
        let fixture = SurgeHTTPFixture(
            data: Data(#"""
            [
              {
                "requestId": 123,
                "protocol": "HTTPS",
                "URL": "example.com:443 (sni.example)",
                "ruleName": "DOMAIN-SUFFIX example.com",
                "policyName": "Node A",
                "originalPolicyName": "Proxy",
                "outBytes": { "total": 1024 },
                "inBytes": 2048,
                "outCurrentSpeed": 128,
                "inCurrentSpeed": 256,
                "clientAddress": "192.0.2.10",
                "clientPort": 54321,
                "remoteAddress": "203.0.113.10",
                "remotePort": "443",
                "localAddress": "127.0.0.1",
                "interface": "en0",
                "application": "Safari",
                "applicationPath": "/Applications/Safari.app/Contents/MacOS/Safari",
                "pid": "501",
                "notes": ["opened", 2, true],
                "remark": "active",
                "createdAt": "2026-07-18T12:00:00Z",
                "controllerField": { "full": true }
              }
            ]
            """#.utf8)
        )
        let client = makeClient(fixture: fixture)

        let response = try await client.activeRequests()
        let request = try XCTUnwrap(response.requests.first)

        XCTAssertEqual(request.id, "123")
        XCTAssertEqual(request.method, "HTTPS")
        XCTAssertEqual(request.url, "example.com:443 (sni.example)")
        XCTAssertEqual(request.ruleType, "DOMAIN-SUFFIX")
        XCTAssertEqual(request.rulePayload, "example.com")
        XCTAssertEqual(request.policy, "Node A")
        XCTAssertEqual(request.originalPolicy, "Proxy")
        XCTAssertEqual(request.upload, 1024)
        XCTAssertEqual(request.download, 2048)
        XCTAssertEqual(request.uploadSpeed, 128)
        XCTAssertEqual(request.downloadSpeed, 256)
        XCTAssertEqual(request.sourceAddress, "192.0.2.10")
        XCTAssertEqual(request.sourcePort, "54321")
        XCTAssertEqual(request.destinationAddress, "203.0.113.10")
        XCTAssertEqual(request.destinationPort, "443")
        XCTAssertEqual(request.process, "Safari")
        XCTAssertEqual(request.processPath, "/Applications/Safari.app/Contents/MacOS/Safari")
        XCTAssertEqual(request.uid, 501)
        XCTAssertEqual(request.notes, ["opened", "2", "true"])
        XCTAssertEqual(request.status, "active")
        XCTAssertEqual(request.start, "2026-07-18T12:00:00Z")
        XCTAssertEqual(request.additionalFields["controllerField"], .object(["full": .bool(true)]))

        let wrapped = try decoder.decode(
            SurgeActiveRequestsResponse.self,
            from: Data(#"{"data":[{"id":"wrapped-id"}]}"#.utf8)
        )
        XCTAssertEqual(wrapped.requests.map(\.id), ["wrapped-id"])
    }

    func testRecentRequestsEndpointUsesOfficialSurgeHTTPAPIPath() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://controller.example:6171"))
        let endpoint = SurgeEndpoint.recentRequests

        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.pathDescription, "/v1/requests/recent")
        XCTAssertEqual(try endpoint.url(relativeTo: baseURL).absoluteString, "http://controller.example:6171/v1/requests/recent")
    }

    func testDNSCacheResponseCountsTopLevelArrayWithoutRetainingRecords() throws {
        let data = Data(#"[{"a":"redacted"},{"b":"redacted"},{"c":"redacted"}]"#.utf8)
        let response = try decoder.decode(SurgeDNSCacheResponse.self, from: data)

        XCTAssertEqual(response.entryCount, 3)
    }

    func testDNSCacheResponseCountsNestedCacheDictionaryWithoutRetainingKeys() throws {
        let data = Data(#"{"cache":{"example.test":["198.51.100.1"],"internal.test":["203.0.113.1"]}}"#.utf8)
        let response = try decoder.decode(SurgeDNSCacheResponse.self, from: data)

        XCTAssertEqual(response.entryCount, 2)
    }

    func testDNSCacheResponseCountsCommonNestedEntryArrays() throws {
        let data = Data(#"{"records":[{"name":"redacted"},{"name":"redacted"},{"name":"redacted"},{"name":"redacted"}]}"#.utf8)
        let response = try decoder.decode(SurgeDNSCacheResponse.self, from: data)

        XCTAssertEqual(response.entryCount, 4)
    }

    private func makeClient(fixture: SurgeHTTPFixture) -> SurgeHttpAPIClient {
        let profile = RouterProfile(
            displayName: "Surge",
            host: "controller.example",
            port: 6171,
            controllerKind: .surgeCompatible
        )

        return SurgeHttpAPIClient(profile: profile, apiKey: "fixture-key") { request in
            try await fixture.load(request)
        }
    }

    private func jsonBody(of request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private actor SurgeHTTPFixture {
    private let data: Data
    private let statusCode: Int
    private var requests: [URLRequest] = []

    init(data: Data = Data(), statusCode: Int = 200) {
        self.data = data
        self.statusCode = statusCode
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            throw SurgeHTTPFixtureError.invalidResponse
        }

        requests.append(request)
        return (data, response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private enum SurgeHTTPFixtureError: Error {
    case invalidResponse
}

private actor SurgeSnapshotCancellationFixture {
    private var paths: [String] = []

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            throw SurgeHTTPFixtureError.invalidResponse
        }

        paths.append(url.path)
        let data: Data
        switch url.path {
        case "/v1/events": data = Data(#"{"events":[]}"#.utf8)
        case "/v1/outbound": data = Data(#"{"mode":"rule"}"#.utf8)
        case "/v1/policies": data = Data(#"{"policies":[]}"#.utf8)
        case "/v1/policy_groups": data = Data(#"{"groups":[]}"#.utf8)
        case "/v1/requests/active": data = Data("[]".utf8)
        case "/v1/requests/recent": throw CancellationError()
        default: data = Data("{}".utf8)
        }
        return (data, response)
    }

    func recordedPaths() -> [String] {
        paths
    }
}
