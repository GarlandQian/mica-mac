import Foundation

protocol ControllerHTTPRequestFailure: Error, Sendable {
    static func invalidURL(_ path: String) -> Self
    static var unauthorized: Self { get }
    static func unexpectedStatus(_ status: Int) -> Self
    static var emptyResponse: Self { get }
    static var invalidResponse: Self { get }
    static func malformedResponse(_ path: String) -> Self
    static func connectionFailure(_ reason: ControllerConnectionFailureReason) -> Self
    var connectionFailureReason: ControllerConnectionFailureReason? { get }
}

protocol ControllerHTTPEndpoint: Sendable {
    associatedtype Failure: ControllerHTTPRequestFailure
    var method: HTTPMethod { get }
    var pathDescription: String { get }
    func url(relativeTo baseURL: URL) throws -> URL
}

enum ControllerHTTPAuthentication: Sendable {
    case bearer(String?)
    case apiKey(String?)

    func apply(to request: inout URLRequest) {
        switch self {
        case .bearer(let secret):
            if let secret, !secret.isEmpty {
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            }
        case .apiKey(let key):
            if let key, !key.isEmpty {
                request.setValue(key, forHTTPHeaderField: "X-Key")
            }
        }
    }
}

struct ControllerHTTPRequestExecutor<Endpoint: ControllerHTTPEndpoint>: Sendable {
    private let profile: RouterProfile
    private let authentication: ControllerHTTPAuthentication
    private let transport: any ControllerHTTPTransport

    init(
        profile: RouterProfile,
        authentication: ControllerHTTPAuthentication,
        transport: any ControllerHTTPTransport
    ) {
        self.profile = profile
        self.authentication = authentication
        self.transport = transport
    }

    func makeRequest(for endpoint: Endpoint, body: Data? = nil) throws -> URLRequest {
        let baseURL: URL
        do {
            baseURL = try profile.baseURL()
        } catch {
            throw Endpoint.Failure.invalidURL(endpoint.pathDescription)
        }
        let url = try endpoint.url(relativeTo: baseURL)
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        authentication.apply(to: &request)
        return request
    }

    func data(for endpoint: Endpoint, body: Data? = nil, allowsEmptyResponse: Bool = false) async throws -> Data {
        try Task.checkCancellation()
        let request = try makeRequest(for: endpoint, body: body)
        let result: (Data, URLResponse)
        do {
            result = try await transport.data(for: request)
        } catch {
            try Task.checkCancellation()
            let failure = Self.failure(for: error)
            if failure.connectionFailureReason == .cancelled {
                throw CancellationError()
            }
            throw failure
        }
        try Task.checkCancellation()
        guard let response = result.1 as? HTTPURLResponse else {
            throw Endpoint.Failure.invalidResponse
        }
        switch response.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw Endpoint.Failure.unauthorized
        default:
            throw Endpoint.Failure.unexpectedStatus(response.statusCode)
        }
        guard allowsEmptyResponse || !result.0.isEmpty else {
            throw Endpoint.Failure.emptyResponse
        }
        return result.0
    }

    func decode<Response: Decodable & Sendable>(
        _ endpoint: Endpoint,
        body: Data? = nil,
        using decoder: JSONDecoder
    ) async throws -> Response {
        let data = try await data(for: endpoint, body: body)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw Endpoint.Failure.malformedResponse(endpoint.pathDescription)
        }
    }

    static func failure(for error: Error) -> Endpoint.Failure {
        if let failure = error as? Endpoint.Failure {
            return failure
        }
        return .connectionFailure(ControllerConnectionFailureReason.classify(error))
    }
}
