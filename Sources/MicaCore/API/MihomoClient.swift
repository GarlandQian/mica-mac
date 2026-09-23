import Foundation

public enum MihomoClientError: Error, LocalizedError, Sendable {
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
            "Invalid controller URL for path \(path)."
        case .unauthorized:
            "The controller rejected the configured secret. Check the external-controller secret and update the saved Keychain secret."
        case .unexpectedStatus(let status):
            switch status {
            case 404:
                "The target returned HTTP 404. Check that the host and port point to the mihomo external-controller, not LuCI or another router page."
            case 405:
                "The target rejected the request method. Check that this is a mihomo-compatible external-controller endpoint."
            default:
                "The controller returned HTTP \(status)."
            }
        case .emptyResponse:
            "The controller returned an empty response for a read endpoint."
        case .invalidResponse:
            "The target did not return an HTTP response. Check the router address and controller port."
        case .malformedResponse(let path):
            "The response from \(path) was not valid mihomo external-controller JSON. Check that the host and port do not point to LuCI or another service."
        case .connectionFailure(let reason):
            reason.errorDescription
        }
    }
}

public actor MihomoClient {
    private let session: URLSession
    private let http: ControllerHTTPRequestExecutor<MihomoEndpoint>
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(profile: RouterProfile, secret: String? = nil, session: URLSession? = nil) {
        let session = session ?? URLSessionControllerHTTPTransport.makeSession(for: profile)
        self.session = session
        self.http = ControllerHTTPRequestExecutor(
            profile: profile,
            authentication: .bearer(secret),
            transport: URLSessionControllerHTTPTransport(session: session)
        )
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    init(
        profile: RouterProfile,
        secret: String? = nil,
        dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.session = URLSession(configuration: .ephemeral)
        self.http = ControllerHTTPRequestExecutor(
            profile: profile,
            authentication: .bearer(secret),
            transport: ClosureControllerHTTPTransport(loader: dataLoader)
        )
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public func version() async throws -> VersionResponse {
        do {
            return try await request(.version)
        } catch MihomoClientError.unexpectedStatus(404) {
            let root: ClashCompatibleRootResponse = try await request(.root)
            if let appVersion = root.appVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
               !appVersion.isEmpty {
                return VersionResponse(version: "Stash \(appVersion)")
            }
            if root.hello?.lowercased() == "mihomo" {
                return VersionResponse(version: "mihomo")
            }
            throw MihomoClientError.malformedResponse(MihomoEndpoint.root.pathDescription)
        }
    }

    public func configs() async throws -> ConfigResponse {
        try await request(.configs)
    }

    public func proxies() async throws -> ProxiesResponse {
        let data = try await http.data(for: .proxies)
        do {
            return try ProxiesResponse.decodePreservingProxyOrder(from: data, decoder: decoder)
        } catch {
            throw MihomoClientError.malformedResponse(MihomoEndpoint.proxies.pathDescription)
        }
    }

    public func smartWeights() async throws -> SmartWeightsResponse {
        try await request(.smartWeights)
    }

    public func smartGroupWeights(group: String) async throws -> SmartGroupWeightsResponse {
        try await request(.smartGroupWeights(group: group))
    }

    public func smartWeights(forGroups groupNames: [String]) async throws -> SmartWeightsResponse {
        do {
            return try await smartWeights()
        } catch let aggregateError as MihomoClientError {
            guard case .unexpectedStatus = aggregateError else {
                throw aggregateError
            }

            guard let fallback = try await legacySmartWeights(forGroups: groupNames) else {
                throw aggregateError
            }
            return fallback
        }
    }

    public func connections() async throws -> ConnectionsResponse {
        try await request(.connections)
    }

    public func connectionsStream() async throws -> AsyncThrowingStream<ConnectionsResponse, Error> {
        let request = try makeStreamRequest(.connections)
        return webSocketStream(request: request, decode: ConnectionsResponse.self)
    }

    public func rules() async throws -> RulesResponse {
        try await request(.rules)
    }

    public func proxyProviders() async throws -> ProxyProvidersResponse {
        let data = try await http.data(for: .proxyProviders)
        do {
            return try ProxyProvidersResponse.decodePreservingProviderOrder(from: data, decoder: decoder)
        } catch {
            throw MihomoClientError.malformedResponse(MihomoEndpoint.proxyProviders.pathDescription)
        }
    }

    public func ruleProviders() async throws -> RuleProvidersResponse {
        let data = try await http.data(for: .ruleProviders)
        do {
            return try RuleProvidersResponse.decodePreservingProviderOrder(from: data, decoder: decoder)
        } catch {
            throw MihomoClientError.malformedResponse(MihomoEndpoint.ruleProviders.pathDescription)
        }
    }

    public func memory() async throws -> MemoryResponse {
        let stream = try await memoryStream()
        var iterator = stream.makeAsyncIterator()
        guard let first = try await iterator.next() else {
            throw MihomoClientError.emptyResponse
        }
        return first
    }

    /// Mihomo keeps this endpoint open and pushes a memory frame once per second.
    /// Callers that need ongoing observations should retain the stream in the
    /// generation-owned session task; one-shot diagnostics use `memory()` above.
    public func memoryStream() async throws -> AsyncThrowingStream<MemoryResponse, Error> {
        let request = try makeStreamRequest(.memory)
        return webSocketStream(request: request, decode: MemoryResponse.self)
    }

    public func trafficStream() async throws -> AsyncThrowingStream<LiveTrafficEvent, Error> {
        let request = try makeStreamRequest(.traffic)
        return webSocketStream(request: request, decode: LiveTrafficEvent.self)
    }

    public func logsStream(level: String? = "info") async throws -> AsyncThrowingStream<LogMessage, Error> {
        let request = try makeStreamRequest(MihomoEndpoint.logsEndpoint(level: level, structured: true))
        return webSocketStream(request: request, decode: LogMessage.self)
    }

    public func updateMode(_ mode: String) async throws {
        try await updateConfigs(MihomoConfigPatch(mode: mode))
    }

    public func updateConfigs(_ patch: MihomoConfigPatch) async throws {
        let body = try encoder.encode(patch)
        try await requestNoContent(.updateConfigs(), body: body)
    }

    public func reloadConfigs(force: Bool = false) async throws {
        let body = try encoder.encode([String: String]())
        try await requestNoContent(.reloadConfigs(force: force), body: body)
    }

    public func updateGeoData() async throws {
        try await requestNoContent(.updateGeoData)
    }

    public func selectProxy(group: String, name: String) async throws {
        let body = try encoder.encode(SelectProxyRequest(name: name))
        try await requestNoContent(.selectProxy(group: group), body: body)
    }

    public func clearFixedProxy(group: String) async throws {
        try await requestNoContent(.clearFixedProxy(group: group))
    }

    public func closeConnection(id: String) async throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MihomoClientError.invalidURL(MihomoEndpoint.closeAllConnections().pathDescription)
        }
        try await requestNoContent(.closeConnection(id: id))
    }

    public func closeAllConnections() async throws {
        try await requestNoContent(.closeAllConnections())
    }

    public func updateProxyProvider(name: String) async throws {
        try await requestNoContent(.updateProxyProvider(name: name))
    }

    public func healthCheckProxyProvider(name: String) async throws {
        try await requestNoContent(.healthCheckProxyProvider(name: name))
    }

    public func updateRuleProvider(name: String) async throws {
        try await requestNoContent(.updateRuleProvider(name: name))
    }

    public func setRuleDisabled(index: Int, disabled: Bool) async throws {
        let body = try encoder.encode([String(index): disabled])
        try await requestNoContent(.setRuleDisabled(), body: body)
    }

    public func flushDNSCache() async throws {
        try await requestNoContent(.flushDNSCache())
    }

    public func flushFakeIPCache() async throws {
        try await requestNoContent(.flushFakeIPCache())
    }

    public func restartCore() async throws {
        try await requestNoContent(.restart)
    }

    public func upgradeCore(channel: String? = nil, force: Bool = false) async throws {
        try await requestNoContent(.upgradeCore(channel: channel, force: force))
    }

    public func groupDelay(
        group: String,
        url: String = "https://www.gstatic.com/generate_204",
        timeout: Int = 5000,
        forceMemberFallback: Bool = false
    ) async throws -> GroupDelayResponse {
        if forceMemberFallback {
            return try await fallbackGroupDelay(group: group, url: url, timeout: timeout)
        }

        do {
            return try await request(.groupDelay(group: group, url: url, timeout: timeout))
        } catch MihomoClientError.unexpectedStatus(404) {
            return try await fallbackGroupDelay(group: group, url: url, timeout: timeout)
        }
    }

    public func proxyDelay(
        name: String,
        url: String = "https://www.gstatic.com/generate_204",
        timeout: Int = 5000
    ) async throws -> ProxyDelayResponse {
        try await request(.proxyDelay(name: name, url: url, timeout: timeout))
    }

    public func providerProxyDelay(
        provider: String,
        name: String,
        url: String = "https://www.gstatic.com/generate_204",
        timeout: Int = 5000
    ) async throws -> ProxyDelayResponse {
        try await request(
            .providerProxyDelay(provider: provider, name: name, url: url, timeout: timeout)
        )
    }

    private func fallbackGroupDelay(
        group: String,
        url: String,
        timeout: Int
    ) async throws -> GroupDelayResponse {
        let catalog = try await proxies()
        guard let groupSnapshot = catalog.proxies[group] else {
            return GroupDelayResponse(delay: [:])
        }

        let probes = groupSnapshot.all.map { name in
            ProxyDelayProbe(name: name, provider: catalog.proxies[name]?.providerName)
        }
        guard !probes.isEmpty else {
            return GroupDelayResponse(delay: [:])
        }

        let delays = try await withThrowingTaskGroup(
            of: (String, Int).self,
            returning: [String: Int].self
        ) { taskGroup in
            var iterator = probes.makeIterator()
            let concurrency = min(32, probes.count)

            for _ in 0..<concurrency {
                guard let probe = iterator.next() else { break }
                addDelayTask(probe, url: url, timeout: timeout, to: &taskGroup)
            }

            var results: [String: Int] = [:]
            while let (name, delay) = try await taskGroup.next() {
                results[name] = delay
                if let probe = iterator.next() {
                    addDelayTask(probe, url: url, timeout: timeout, to: &taskGroup)
                }
            }
            return results
        }

        return GroupDelayResponse(delay: delays)
    }

    private func addDelayTask(
        _ probe: ProxyDelayProbe,
        url: String,
        timeout: Int,
        to taskGroup: inout ThrowingTaskGroup<(String, Int), any Error>
    ) {
        taskGroup.addTask { [self] in
            do {
                let response: ProxyDelayResponse
                if let provider = probe.provider {
                    response = try await providerProxyDelay(
                        provider: provider,
                        name: probe.name,
                        url: url,
                        timeout: timeout
                    )
                } else {
                    response = try await proxyDelay(name: probe.name, url: url, timeout: timeout)
                }
                return (probe.name, response.delay)
            } catch is CancellationError {
                throw CancellationError()
            } catch MihomoClientError.connectionFailure(.cancelled) {
                throw CancellationError()
            } catch {
                return (probe.name, 0)
            }
        }
    }

    private func request<Response: Decodable & Sendable>(_ endpoint: MihomoEndpoint) async throws -> Response {
        try await http.decode(endpoint, using: decoder)
    }

    private func requestNoContent(_ endpoint: MihomoEndpoint, body: Data? = nil) async throws {
        _ = try await http.data(for: endpoint, body: body, allowsEmptyResponse: true)
    }

    private func makeStreamRequest(_ endpoint: MihomoEndpoint) throws -> URLRequest {
        var request = try http.makeRequest(for: endpoint)
        guard let httpURL = request.url,
              var components = URLComponents(url: httpURL, resolvingAgainstBaseURL: false) else {
            throw MihomoClientError.invalidURL(endpoint.pathDescription)
        }

        components.scheme = components.scheme == "https" ? "wss" : "ws"
        guard let streamURL = components.url else {
            throw MihomoClientError.invalidURL(endpoint.pathDescription)
        }

        request.url = streamURL
        request.httpMethod = HTTPMethod.get.rawValue
        request.setValue(nil, forHTTPHeaderField: "Accept")
        return request
    }

    private func webSocketStream<Response: Decodable & Sendable>(
        request: URLRequest,
        decode responseType: Response.Type
    ) -> AsyncThrowingStream<Response, Error> {
        let session = session

        return AsyncThrowingStream<Response, Error>(bufferingPolicy: .bufferingNewest(64)) { continuation in
            let task = session.webSocketTask(with: request)
            let receiveTask = Task {
                let decoder = JSONDecoder()
                do {
                    while !Task.isCancelled {
                        let message: URLSessionWebSocketTask.Message
                        do {
                            message = try await task.receive()
                        } catch {
                            // URLSessionWebSocketTask can surface transport
                            // failures as NSError/POSIX errors rather than a
                            // URLError. Normalize those failures so the
                            // session retry policy treats a dropped stream as
                            // transient instead of a one-time local error.
                            throw Self.clientError(for: error)
                        }
                        let data: Data
                        switch message {
                        case .data(let messageData):
                            data = messageData
                        case .string(let text):
                            data = Data(text.utf8)
                        @unknown default:
                            continue
                        }

                        let decoded = try decoder.decode(responseType, from: data)
                        continuation.yield(decoded)
                    }
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { _ in
                receiveTask.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }

            task.resume()
        }
    }

    private func legacySmartWeights(forGroups groupNames: [String]) async throws -> SmartWeightsResponse? {
        try await withThrowingTaskGroup(
            of: SmartWeightFallbackResult.self,
            returning: SmartWeightsResponse?.self
        ) { taskGroup in
            for groupName in groupNames {
                taskGroup.addTask {
                    do {
                        let response = try await self.smartGroupWeights(group: groupName)
                        return SmartWeightFallbackResult(
                            groupName: groupName,
                            weights: response.weights
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch MihomoClientError.connectionFailure(.cancelled) {
                        throw CancellationError()
                    } catch {
                        return SmartWeightFallbackResult(groupName: groupName, weights: nil)
                    }
                }
            }

            var didLoadAnyGroup = false
            var weightsByGroup: [String: [SmartNodeRankSnapshot]] = [:]
            for try await result in taskGroup {
                guard let weights = result.weights else { continue }
                didLoadAnyGroup = true
                weightsByGroup[result.groupName] = weights
            }

            guard didLoadAnyGroup else { return nil }
            return SmartWeightsResponse(weights: weightsByGroup)
        }
    }

    static func clientError(for error: Error) -> MihomoClientError {
        ControllerHTTPRequestExecutor<MihomoEndpoint>.failure(for: error)
    }
}

private struct ProxyDelayProbe: Sendable {
    var name: String
    var provider: String?
}

private struct SmartWeightFallbackResult: Sendable {
    var groupName: String
    var weights: [SmartNodeRankSnapshot]?
}

private struct SelectProxyRequest: Encodable {
    var name: String
}

extension MihomoClientError: ControllerHTTPRequestFailure {
    var connectionFailureReason: ControllerConnectionFailureReason? {
        guard case .connectionFailure(let reason) = self else { return nil }
        return reason
    }
}

extension MihomoEndpoint: ControllerHTTPEndpoint {
    typealias Failure = MihomoClientError
}
