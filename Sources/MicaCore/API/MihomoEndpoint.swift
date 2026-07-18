import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case patch = "PATCH"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

public struct MihomoEndpoint: Sendable {
    public var method: HTTPMethod
    public var pathComponents: [String]
    public var queryItems: [URLQueryItem]

    public init(method: HTTPMethod = .get, path: String, queryItems: [URLQueryItem] = []) {
        self.method = method
        self.pathComponents = path.split(separator: "/").map(String.init)
        self.queryItems = queryItems
    }

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
            throw MihomoClientError.invalidURL(pathComponents.joined(separator: "/"))
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let resolved = components.url else {
            throw MihomoClientError.invalidURL(pathComponents.joined(separator: "/"))
        }

        return resolved
    }

    public static let root = MihomoEndpoint(pathComponents: [])
    public static let version = MihomoEndpoint(path: "version")
    public static let configs = MihomoEndpoint(path: "configs")
    public static let proxies = MihomoEndpoint(path: "proxies")
    public static let connections = MihomoEndpoint(path: "connections")
    public static let traffic = MihomoEndpoint(path: "traffic")
    public static let logs = MihomoEndpoint(path: "logs")
    public static let memory = MihomoEndpoint(path: "memory")
    public static let rules = MihomoEndpoint(path: "rules")
    public static let proxyProviders = MihomoEndpoint(pathComponents: ["providers", "proxies"])
    public static let ruleProviders = MihomoEndpoint(pathComponents: ["providers", "rules"])
    public static let restart = MihomoEndpoint(method: .post, path: "restart")

    public static func logsEndpoint(
        level: String? = nil,
        structured: Bool = true
    ) -> MihomoEndpoint {
        var queryItems: [URLQueryItem] = []
        if let level, !level.isEmpty {
            queryItems.append(URLQueryItem(name: "level", value: level))
        }
        if structured {
            queryItems.append(URLQueryItem(name: "format", value: "structured"))
        }
        return MihomoEndpoint(path: "logs", queryItems: queryItems)
    }

    public static func updateConfigs() -> MihomoEndpoint {
        MihomoEndpoint(method: .patch, path: "configs")
    }

    public static func reloadConfigs(force: Bool = false) -> MihomoEndpoint {
        MihomoEndpoint(
            method: .put,
            path: "configs",
            queryItems: force ? [URLQueryItem(name: "force", value: "true")] : []
        )
    }

    public static let updateGeoData = MihomoEndpoint(method: .post, pathComponents: ["configs", "geo"])

    public static func selectProxy(group: String) -> MihomoEndpoint {
        MihomoEndpoint(method: .put, pathComponents: ["proxies", group])
    }

    public static func clearFixedProxy(group: String) -> MihomoEndpoint {
        MihomoEndpoint(method: .delete, pathComponents: ["proxies", group])
    }

    public static func closeConnection(id: String) -> MihomoEndpoint {
        MihomoEndpoint(method: .delete, pathComponents: ["connections", id])
    }

    public static func closeAllConnections() -> MihomoEndpoint {
        MihomoEndpoint(method: .delete, path: "connections")
    }

    public static func groupDelay(group: String, url: String, timeout: Int) -> MihomoEndpoint {
        MihomoEndpoint(
            pathComponents: ["group", group, "delay"],
            queryItems: [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "timeout", value: "\(timeout)"),
            ]
        )
    }

    public static func proxyDelay(name: String, url: String, timeout: Int) -> MihomoEndpoint {
        MihomoEndpoint(
            pathComponents: ["proxies", name, "delay"],
            queryItems: [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "timeout", value: "\(timeout)"),
            ]
        )
    }

    public static func providerProxyDelay(
        provider: String,
        name: String,
        url: String,
        timeout: Int
    ) -> MihomoEndpoint {
        MihomoEndpoint(
            pathComponents: ["providers", "proxies", provider, name, "healthcheck"],
            queryItems: [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "timeout", value: "\(timeout)"),
            ]
        )
    }

    public static func updateProxyProvider(name: String) -> MihomoEndpoint {
        MihomoEndpoint(method: .put, pathComponents: ["providers", "proxies", name])
    }

    public static func healthCheckProxyProvider(name: String) -> MihomoEndpoint {
        MihomoEndpoint(pathComponents: ["providers", "proxies", name, "healthcheck"])
    }

    public static func updateRuleProvider(name: String) -> MihomoEndpoint {
        MihomoEndpoint(method: .put, pathComponents: ["providers", "rules", name])
    }

    public static func setRuleDisabled() -> MihomoEndpoint {
        MihomoEndpoint(method: .patch, pathComponents: ["rules", "disable"])
    }

    public static func flushDNSCache() -> MihomoEndpoint {
        MihomoEndpoint(method: .post, pathComponents: ["cache", "dns", "flush"])
    }

    public static func flushFakeIPCache() -> MihomoEndpoint {
        MihomoEndpoint(method: .post, pathComponents: ["cache", "fakeip", "flush"])
    }

    public static func upgradeCore(channel: String? = nil, force: Bool = false) -> MihomoEndpoint {
        var queryItems: [URLQueryItem] = []
        if let channel, !channel.isEmpty {
            queryItems.append(URLQueryItem(name: "channel", value: channel))
        }
        if force {
            queryItems.append(URLQueryItem(name: "force", value: "true"))
        }
        return MihomoEndpoint(method: .post, path: "upgrade", queryItems: queryItems)
    }
}
