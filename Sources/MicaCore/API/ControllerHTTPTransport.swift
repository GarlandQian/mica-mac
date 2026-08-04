import Foundation

protocol ControllerHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionControllerHTTPTransport: ControllerHTTPTransport {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

struct ClosureControllerHTTPTransport: ControllerHTTPTransport {
    private let loader: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(loader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.loader = loader
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await loader(request)
    }
}
