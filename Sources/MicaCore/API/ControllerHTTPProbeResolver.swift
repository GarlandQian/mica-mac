import Foundation

public enum ControllerHTTPProbeError: Error, LocalizedError, Sendable {
    case unrecognizedController

    public var errorDescription: String? {
        "The remote endpoint did not match a supported Clash-compatible or Surge HTTP controller."
    }
}

public struct ControllerHTTPProbeResolver: Sendable {
    private let dataLoader: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?

    public init() {
        self.dataLoader = nil
    }

    init(dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.dataLoader = dataLoader
    }

    public func resolve(
        profile: RouterProfile,
        credential: String?,
        includeSurge: Bool = true
    ) async throws -> ControllerKind {
        async let clashAttempt = probeClash(profile: profile, credential: credential)
        async let surgeAttempt = probeSurge(
            profile: profile,
            credential: credential,
            enabled: includeSurge
        )

        let (clash, surge) = await (clashAttempt, surgeAttempt)

        if case .success(let version) = clash {
            return Self.clashKind(for: version)
        }
        if case .success = surge {
            return .surgeCompatible
        }

        let failures = [clash.failure, surge?.failure].compactMap { $0 }
        if let failure = failures.first(where: \.isAuthenticationFailure)
            ?? failures.first(where: \.isConnectionFailure) {
            throw failure.underlyingError
        }

        throw ControllerHTTPProbeError.unrecognizedController
    }

    private func probeClash(
        profile: RouterProfile,
        credential: String?
    ) async -> ControllerProbeAttempt<VersionResponse> {
        let client: MihomoClient
        if let dataLoader {
            client = MihomoClient(profile: profile, secret: credential, dataLoader: dataLoader)
        } else {
            client = MihomoClient(profile: profile, secret: credential)
        }

        do {
            return .success(try await client.version())
        } catch let error as MihomoClientError {
            return .failure(.mihomo(error))
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.other)
        }
    }

    private func probeSurge(
        profile: RouterProfile,
        credential: String?,
        enabled: Bool
    ) async -> ControllerProbeAttempt<Void>? {
        guard enabled else { return nil }

        let client: SurgeHttpAPIClient
        if let dataLoader {
            client = SurgeHttpAPIClient(profile: profile, apiKey: credential, dataLoader: dataLoader)
        } else {
            client = SurgeHttpAPIClient(profile: profile, apiKey: credential)
        }

        do {
            _ = try await client.outbound()
            return .success(())
        } catch let error as SurgeHttpAPIError {
            return .failure(.surge(error))
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.other)
        }
    }

    private static func clashKind(for response: VersionResponse) -> ControllerKind {
        let version = response.version.lowercased()
        if version.contains("cmfa") {
            return .cmfaCompatible
        }
        if version.hasPrefix("stash ") || version == "stash" {
            return .stashCompatible
        }
        return .mihomoCompatible
    }
}

private enum ControllerProbeAttempt<Value: Sendable>: Sendable {
    case success(Value)
    case failure(ControllerProbeFailure)

    var failure: ControllerProbeFailure? {
        guard case .failure(let failure) = self else { return nil }
        return failure
    }
}

private enum ControllerProbeFailure: Sendable {
    case mihomo(MihomoClientError)
    case surge(SurgeHttpAPIError)
    case cancelled
    case other

    var isAuthenticationFailure: Bool {
        switch self {
        case .mihomo(.unauthorized), .surge(.unauthorized): true
        case .mihomo, .surge, .cancelled, .other: false
        }
    }

    var isConnectionFailure: Bool {
        switch self {
        case .mihomo(.connectionFailure), .surge(.connectionFailure), .cancelled: true
        case .mihomo, .surge, .other: false
        }
    }

    var underlyingError: Error {
        switch self {
        case .mihomo(let error): error
        case .surge(let error): error
        case .cancelled: CancellationError()
        case .other: ControllerHTTPProbeError.unrecognizedController
        }
    }
}
