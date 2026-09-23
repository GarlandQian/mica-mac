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

    static func makeSession(for profile: RouterProfile) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20

        let delegate: ControllerSelfSignedCertificateDelegate?
        if profile.scheme == .https, profile.tlsPolicy == .allowSelfSigned {
            delegate = ControllerSelfSignedCertificateDelegate()
        } else {
            delegate = nil
        }
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

private final class ControllerSelfSignedCertificateDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
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
