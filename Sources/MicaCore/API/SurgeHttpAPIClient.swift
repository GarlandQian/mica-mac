import Foundation

typealias SurgeHTTPDataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

public enum SurgeHttpAPIError: Error, LocalizedError, Sendable {
    case invalidURL(String)
    case unauthorized
    case unexpectedStatus(Int)
    case emptyResponse
    case invalidResponse
    case malformedResponse(String)
    case connectionFailure(ControllerConnectionFailureReason)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            "Invalid Surge HTTP API URL for path \(path)."
        case .unauthorized:
            "Surge rejected the configured API key. Edit the profile and update the saved key."
        case .unexpectedStatus(let status):
            "Surge HTTP API returned HTTP \(status)."
        case .emptyResponse:
            "Surge returned an empty response for a read endpoint."
        case .invalidResponse:
            "The target did not return an HTTP response. Check the Surge HTTP API host and port."
        case .malformedResponse(let path):
            "The response from \(path) was not valid Surge HTTP API JSON."
        case .connectionFailure(let reason):
            reason.errorDescription
        }
    }
}

public actor SurgeHttpAPIClient {
    private let profile: RouterProfile
    private let http: ControllerHTTPRequestExecutor<SurgeEndpoint>
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(profile: RouterProfile, apiKey: String? = nil, session: URLSession? = nil) {
        self.profile = profile
        let session = session ?? URLSessionControllerHTTPTransport.makeSession(for: profile)
        self.http = ControllerHTTPRequestExecutor(
            profile: profile,
            authentication: .apiKey(apiKey),
            transport: URLSessionControllerHTTPTransport(session: session)
        )
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    init(profile: RouterProfile, apiKey: String? = nil, dataLoader: @escaping SurgeHTTPDataLoader) {
        self.profile = profile
        self.http = ControllerHTTPRequestExecutor(
            profile: profile,
            authentication: .apiKey(apiKey),
            transport: ClosureControllerHTTPTransport(loader: dataLoader)
        )
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public func events() async throws -> SurgeEventsResponse {
        try await request(.events)
    }

    public func outbound() async throws -> SurgeOutboundResponse {
        try await request(.outbound)
    }

    public func setOutboundMode(_ mode: String) async throws {
        let body = try encoder.encode(SurgeOutboundModeRequest(mode: mode))
        try await requestNoContent(.setOutbound(), body: body)
    }

    public func policies() async throws -> SurgePoliciesResponse {
        try await request(.policies)
    }

    public func policyGroups() async throws -> SurgePolicyGroupsResponse {
        try await request(.policyGroups)
    }

    public func selectPolicy(group: String, policy: String) async throws {
        let body = try encoder.encode(SurgePolicySelectionRequest(groupName: group, policy: policy))
        try await requestNoContent(.selectPolicyGroup(group: group), body: body)
    }

    public func testPolicyGroup(_ group: String) async throws -> SurgePolicyGroupTestResponse {
        let body = try encoder.encode(SurgePolicyGroupTestRequest(groupName: group))
        return try await request(.testPolicyGroup(group: group), body: body)
    }

    public func activeRequests() async throws -> SurgeActiveRequestsResponse {
        try await request(.activeRequests)
    }

    public func recentRequests() async throws -> SurgeActiveRequestsResponse {
        try await request(.recentRequests)
    }

    public func killActiveRequest(id: String) async throws {
        let body = try encoder.encode(SurgeKillRequest(id: id))
        try await requestNoContent(.killActiveRequest(id: id), body: body)
    }

    public func rules() async throws -> SurgeRulesResponse {
        try await request(.rules)
    }

    public func traffic() async throws -> SurgeTrafficResponse {
        try await request(.traffic)
    }

    public func dnsCache() async throws -> SurgeDNSCacheResponse {
        try await request(.dnsCache)
    }

    public func flushDNSCache() async throws {
        try await requestNoContent(.flushDNSCache())
    }

    public func reloadProfile() async throws {
        try await requestNoContent(.reloadProfile(), body: Data("{}".utf8))
    }

    public func setLogLevel(_ level: String) async throws {
        let body = try encoder.encode(SurgeLogLevelRequest(level: level))
        try await requestNoContent(.setLogLevel(), body: body)
    }

    public func snapshot() async throws -> SurgeControlSnapshot {
        let events = try await events()
        let outbound = try await outbound()
        let policies = try await policies()
        let policyGroups = try await policyGroups()
        let activeRequests = try await activeRequests()
        let recentRequestResponse = try await loadOptionalValue { try await self.recentRequests() }
        let rules = try await rules()
        let traffic = try await traffic()
        let dnsCacheResponse = try await loadOptionalValue { try await self.dnsCache() }

        return SurgeControlSnapshot(
            platform: profile.surgePlatform,
            events: events,
            outbound: outbound,
            policies: policies,
            policyGroups: policyGroups,
            activeRequests: activeRequests,
            recentRequests: recentRequestResponse ?? SurgeActiveRequestsResponse(requests: []),
            rules: rules,
            traffic: traffic,
            dnsCache: dnsCacheResponse ?? SurgeDNSCacheResponse()
        )
    }

    private func loadOptionalValue<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value? {
        do {
            return try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func request<Response: Decodable & Sendable>(
        _ endpoint: SurgeEndpoint,
        body: Data? = nil
    ) async throws -> Response {
        try await http.decode(endpoint, body: body, using: decoder)
    }

    private func requestNoContent(_ endpoint: SurgeEndpoint, body: Data? = nil) async throws {
        _ = try await http.data(for: endpoint, body: body, allowsEmptyResponse: true)
    }
}

public struct SurgeEndpoint: Sendable {
    public var method: HTTPMethod
    public var pathComponents: [String]
    public var queryItems: [URLQueryItem]

    public init(method: HTTPMethod = .get, pathComponents: [String], queryItems: [URLQueryItem] = []) {
        self.method = method
        self.pathComponents = pathComponents
        self.queryItems = queryItems
    }

    public var pathDescription: String {
        "/\(pathComponents.joined(separator: "/"))"
    }

    public func url(relativeTo baseURL: URL) throws -> URL {
        var url = baseURL

        for component in pathComponents {
            url.appendPathComponent(component)
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SurgeHttpAPIError.invalidURL(pathComponents.joined(separator: "/"))
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let resolved = components.url else {
            throw SurgeHttpAPIError.invalidURL(pathComponents.joined(separator: "/"))
        }

        return resolved
    }

    public static let events = SurgeEndpoint(pathComponents: ["v1", "events"])
    public static let outbound = SurgeEndpoint(pathComponents: ["v1", "outbound"])
    public static let policies = SurgeEndpoint(pathComponents: ["v1", "policies"])
    public static let policyGroups = SurgeEndpoint(pathComponents: ["v1", "policy_groups"])
    public static let activeRequests = SurgeEndpoint(pathComponents: ["v1", "requests", "active"])
    public static let recentRequests = SurgeEndpoint(pathComponents: ["v1", "requests", "recent"])
    public static let rules = SurgeEndpoint(pathComponents: ["v1", "rules"])
    public static let traffic = SurgeEndpoint(pathComponents: ["v1", "traffic"])
    public static let dnsCache = SurgeEndpoint(pathComponents: ["v1", "dns"])

    public static func flushDNSCache() -> SurgeEndpoint {
        SurgeEndpoint(method: .post, pathComponents: ["v1", "dns", "flush"])
    }

    public static func reloadProfile() -> SurgeEndpoint {
        SurgeEndpoint(method: .post, pathComponents: ["v1", "profiles", "reload"])
    }

    public static func setLogLevel() -> SurgeEndpoint {
        SurgeEndpoint(method: .post, pathComponents: ["v1", "log", "level"])
    }

    public static func setOutbound() -> SurgeEndpoint {
        SurgeEndpoint(method: .post, pathComponents: ["v1", "outbound"])
    }

    public static func selectPolicyGroup(group _: String) -> SurgeEndpoint {
        SurgeEndpoint(method: .post, pathComponents: ["v1", "policy_groups", "select"])
    }

    public static func testPolicyGroup(group _: String) -> SurgeEndpoint {
        SurgeEndpoint(method: .post, pathComponents: ["v1", "policy_groups", "test"])
    }

    public static func killActiveRequest(id _: String) -> SurgeEndpoint {
        SurgeEndpoint(method: .post, pathComponents: ["v1", "requests", "kill"])
    }
}

private struct SurgeOutboundModeRequest: Encodable {
    var mode: String
}

private struct SurgeLogLevelRequest: Encodable {
    var level: String
}

private struct SurgePolicySelectionRequest: Encodable {
    var groupName: String
    var policy: String

    enum CodingKeys: String, CodingKey {
        case groupName = "group_name"
        case policy
    }
}

private struct SurgePolicyGroupTestRequest: Encodable {
    var groupName: String

    enum CodingKeys: String, CodingKey {
        case groupName = "group_name"
    }
}

private struct SurgeKillRequest: Encodable {
    var id: String

    enum CodingKeys: String, CodingKey {
        case id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let numericID = Int(id), String(numericID) == id {
            try container.encode(numericID, forKey: .id)
        } else {
            try container.encode(id, forKey: .id)
        }
    }
}

extension SurgeHttpAPIError: ControllerHTTPRequestFailure {
    var connectionFailureReason: ControllerConnectionFailureReason? {
        guard case .connectionFailure(let reason) = self else { return nil }
        return reason
    }
}

extension SurgeEndpoint: ControllerHTTPEndpoint {
    typealias Failure = SurgeHttpAPIError
}
