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
        async let httpAttempt = Self.capture {
            try await httpProbe(profile, credential, includeSurge)
        }
        async let singBoxAttempt = Self.capture {
            try await singBoxProbe(profile, credential)
        }
        let attempts = await (http: httpAttempt, singBox: singBoxAttempt)

        if case .success(let kind) = attempts.http {
            return kind
        }
        if case .success = attempts.singBox {
            return .singBoxCompatible
        }

        if case .failure(let error) = attempts.http,
           !(error is ControllerHTTPProbeError) {
            throw error
        }
        if case .failure(let error) = attempts.singBox,
           Self.isAuthenticationFailure(error) {
            throw error
        }
        throw ControllerHTTPProbeError.unrecognizedController
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
