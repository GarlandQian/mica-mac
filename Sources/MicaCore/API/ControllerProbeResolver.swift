import Foundation

public struct ControllerProbeResolver: Sendable {
    private let httpProbe: @Sendable (RouterProfile, String?, Bool) async throws -> ControllerKind
    private let singBoxProbe: @Sendable (RouterProfile, String?) async throws -> SingBoxVersion

    public init() {
        httpProbe = { profile, credential, includeSurge in
            try await ControllerHTTPProbeResolver().resolve(
                profile: profile,
                credential: credential,
                includeSurge: includeSurge
            )
        }
        singBoxProbe = { profile, credential in
            try await Self.probeSingBox(profile: profile, credential: credential)
        }
    }

    init(
        httpProbe: @escaping @Sendable (RouterProfile, String?, Bool) async throws -> ControllerKind,
        singBoxProbe: @escaping @Sendable (RouterProfile, String?) async throws -> SingBoxVersion
    ) {
        self.httpProbe = httpProbe
        self.singBoxProbe = singBoxProbe
    }

    public func resolve(
        profile: RouterProfile,
        credential: String?,
        includeSurge: Bool = true
    ) async throws -> ControllerKind {
        let httpAttempt = await Self.capture {
            try await httpProbe(profile, credential, includeSurge)
        }

        if case .success(let kind) = httpAttempt {
            return kind
        }

        guard case .failure(let httpError) = httpAttempt else {
            throw ControllerHTTPProbeError.unrecognizedController
        }

        // A refused/unavailable HTTP port is conclusive for this reconnect
        // attempt. In particular, do not wait for sing-box's 20-second
        // wait-for-ready RPC when mihomo is simply starting up.
        if !Self.shouldProbeSingBox(after: httpError) {
            throw httpError
        }

        let singBoxAttempt = await Self.capture {
            try await singBoxProbe(profile, credential)
        }
        if case .success = singBoxAttempt {
            return .singBoxCompatible
        }

        if case .failure(let error) = singBoxAttempt,
           Self.isAuthenticationFailure(error) {
            throw error
        }

        if !(httpError is ControllerHTTPProbeError) {
            throw httpError
        }

        throw ControllerHTTPProbeError.unrecognizedController
    }

    private static func shouldProbeSingBox(after error: Error) -> Bool {
        switch error {
        case let error as MihomoClientError:
            switch error {
            case .connectionFailure(let reason):
                return Self.shouldProbeAlternativeProtocol(after: reason)
            case .unauthorized:
                return false
            case .invalidURL:
                return false
            case .unexpectedStatus, .emptyResponse, .invalidResponse, .malformedResponse:
                return true
            }
        case let error as SurgeHttpAPIError:
            switch error {
            case .connectionFailure(let reason):
                return Self.shouldProbeAlternativeProtocol(after: reason)
            case .unauthorized, .invalidURL:
                return false
            case .unexpectedStatus, .emptyResponse, .invalidResponse, .malformedResponse:
                return true
            }
        case is ControllerHTTPProbeError:
            return true
        default:
            return true
        }
    }

    private static func shouldProbeAlternativeProtocol(
        after reason: ControllerConnectionFailureReason
    ) -> Bool {
        switch reason {
        case .other:
            true
        case .hostNotFound,
             .connectionRefused,
             .timedOut,
             .tlsTrustFailed,
             .networkUnavailable,
             .cancelled:
            false
        }
    }

    private static func probeSingBox(
        profile: RouterProfile,
        credential: String?
    ) async throws -> SingBoxVersion {
        try await SingBoxGRPCClient.withConnectedClient(
            profile: profile,
            credential: credential
        ) { client in
            try await client.version()
        }
    }

    private static func capture<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async -> Result<Value, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private static func isAuthenticationFailure(_ error: Error) -> Bool {
        guard let error = error as? SingBoxGRPCError,
              case .rpc(let code, _) = error else {
            return false
        }
        return code == 7 || code == 16
    }
}
