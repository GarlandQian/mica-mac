import Foundation

public enum ControllerScheme: String, Codable, CaseIterable, Sendable {
    case http
    case https
}

public enum TLSValidationPolicy: String, Codable, CaseIterable, Sendable {
    case system
    case allowSelfSigned
}

public enum SurgeControllerPlatform: String, Codable, CaseIterable, Sendable {
    case macLocal = "mac-local"
    case iosReachable = "ios-reachable"
    case remoteMac = "remote-mac"

    public var label: String {
        switch self {
        case .macLocal:
            return "Mac Local"
        case .iosReachable:
            return "iOS Reachable"
        case .remoteMac:
            return "Remote Mac"
        }
    }

    public var capabilityBadge: String {
        switch self {
        case .macLocal:
            return "MAC LOCAL"
        case .iosReachable:
            return "IOS LIMITED"
        case .remoteMac:
            return "REMOTE MAC"
        }
    }
}

public enum RouterProfileEndpointError: Error, LocalizedError, Equatable, Sendable {
    case invalidHost
    case invalidPort(Int)
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .invalidHost:
            "The controller host is empty or contains a scheme, path, or whitespace."
        case .invalidPort(let port):
            "The controller port \(port) is outside the valid 1...65535 range."
        case .invalidURL:
            "The controller host and port do not form a valid URL."
        }
    }
}

public enum ControllerKind: String, Codable, CaseIterable, Sendable {
    case autoDetect = "auto-detect"
    case mihomoCompatible = "mihomo-compatible"
    case nikkiMihomoCompatible = "nikki-mihomo-compatible"
    case openClashMihomoCompatible = "openclash-mihomo-compatible"
    case surgeCompatible = "surge-compatible"
    case singBoxCompatible = "sing-box-compatible"
    case cmfaCompatible = "cmfa-compatible"
    case stashCompatible = "stash-compatible"
    case stashCmfaCompatible = "stash-cmfa-compatible"
    case unknown = "unknown"
    case unsupported = "unsupported"

    public var label: String {
        switch self {
        case .autoDetect:
            return "Auto Detect"
        case .mihomoCompatible:
            return "mihomo"
        case .nikkiMihomoCompatible:
            return "Nikki"
        case .openClashMihomoCompatible:
            return "OpenClash"
        case .surgeCompatible:
            return "Surge"
        case .singBoxCompatible:
            return "sing-box"
        case .cmfaCompatible:
            return "CMFA"
        case .stashCompatible:
            return "Stash"
        case .stashCmfaCompatible:
            return "Stash / CMFA"
        case .unknown:
            return "Unknown"
        case .unsupported:
            return "Unsupported"
        }
    }

    public var badge: String {
        switch self {
        case .autoDetect:
            return "AUTO"
        case .mihomoCompatible:
            return "MHM"
        case .nikkiMihomoCompatible:
            return "NIKKI"
        case .openClashMihomoCompatible:
            return "OCL"
        case .surgeCompatible:
            return "SURGE"
        case .singBoxCompatible:
            return "SBOX"
        case .cmfaCompatible:
            return "CMFA"
        case .stashCompatible:
            return "STASH"
        case .stashCmfaCompatible:
            return "CMFA"
        case .unknown:
            return "UNK"
        case .unsupported:
            return "NO"
        }
    }
}

public struct RouterProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var scheme: ControllerScheme
    public var host: String
    public var port: Int
    public var secretReference: String?
    public var tlsPolicy: TLSValidationPolicy
    public var lastConnectedAt: Date?
    public var controllerKind: ControllerKind
    public var surgePlatform: SurgeControllerPlatform

    public init(
        id: UUID = UUID(),
        displayName: String,
        scheme: ControllerScheme = .http,
        host: String,
        port: Int = 9090,
        secretReference: String? = nil,
        tlsPolicy: TLSValidationPolicy = .system,
        lastConnectedAt: Date? = nil,
        controllerKind: ControllerKind = .autoDetect,
        surgePlatform: SurgeControllerPlatform = .remoteMac
    ) {
        self.id = id
        self.displayName = displayName
        self.scheme = scheme
        self.host = host
        self.port = port
        self.secretReference = secretReference
        self.tlsPolicy = tlsPolicy
        self.lastConnectedAt = lastConnectedAt
        self.controllerKind = controllerKind
        self.surgePlatform = surgePlatform
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case scheme
        case host
        case port
        case secretReference
        case tlsPolicy
        case lastConnectedAt
        case controllerKind
        case surgePlatform
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        scheme = try container.decode(ControllerScheme.self, forKey: .scheme)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        secretReference = try container.decodeIfPresent(String.self, forKey: .secretReference)
        tlsPolicy = try container.decode(TLSValidationPolicy.self, forKey: .tlsPolicy)
        lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        controllerKind = try container.decodeIfPresent(ControllerKind.self, forKey: .controllerKind) ?? .autoDetect
        surgePlatform = try container.decodeIfPresent(SurgeControllerPlatform.self, forKey: .surgePlatform) ?? .remoteMac

        do {
            _ = try baseURL()
        } catch {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Invalid controller endpoint in persisted router profile.",
                    underlyingError: error
                )
            )
        }
    }

    public func baseURL() throws -> URL {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty,
              normalizedHost == host,
              !normalizedHost.contains("://"),
              !normalizedHost.contains("/"),
              normalizedHost.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw RouterProfileEndpointError.invalidHost
        }
        guard (1...65_535).contains(port) else {
            throw RouterProfileEndpointError.invalidPort(port)
        }

        var components = URLComponents()
        components.scheme = scheme.rawValue
        components.host = normalizedHost
        components.port = port

        guard let url = components.url,
              url.host?.isEmpty == false else {
            throw RouterProfileEndpointError.invalidURL
        }

        return url
    }
}
