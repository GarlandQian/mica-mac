import Foundation

public actor MihomoCompatibleControllerAdapter: ControllerAdapterProtocol {
    public nonisolated let profile: RouterProfile
    private let client: MihomoClient

    public nonisolated var controllerType: UnifiedControllerType {
        profile.unifiedControllerType
    }

    public nonisolated var capabilities: ControllerCapabilities {
        UnifiedControllerAdapterRegistry.capabilities(for: profile)
    }

    public init(profile: RouterProfile, secret: String? = nil) {
        self.profile = profile
        self.client = MihomoClient(profile: profile, secret: secret)
    }

    init(profile: RouterProfile, client: MihomoClient) {
        self.profile = profile
        self.client = client
    }

    public func testConnection() async throws -> UnifiedControllerHealth {
        let version = try await client.version()

        return UnifiedControllerHealth(
            state: .ready,
            checkedAt: Date(),
            endpointStatuses: [
                UnifiedControllerEndpointStatus(endpoint: .version, state: .ready, safeDetail: version.version),
            ],
            safeSummary: "mihomo-compatible-version-ready"
        )
    }

    public func snapshot() async throws -> UnifiedControllerSnapshot {
        async let version = client.version()
        async let configs = client.configs()
        async let proxies = client.proxies()
        async let connections = client.connections()

        let base = try await (
            version: version,
            configs: configs,
            proxies: proxies,
            connections: connections
        )

        let rules = try await optionalValue { try await client.rules() }
        let providers = try await optionalValue { try await client.proxyProviders() }
        let ruleProviders = try await optionalValue { try await client.ruleProviders() }

        return UnifiedControllerSnapshot.mihomoCompatible(
            profile: profile,
            version: base.version,
            config: base.configs,
            proxies: base.proxies,
            connections: base.connections,
            rules: rules,
            providers: providers,
            ruleProviders: ruleProviders
        )
    }

    private func optionalValue<Value: Sendable>(
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
}

public actor SurgeHTTPAPIControllerAdapter: ControllerAdapterProtocol {
    public nonisolated let profile: RouterProfile
    private let apiKey: String?

    public nonisolated var controllerType: UnifiedControllerType {
        .surgeHTTPAPI
    }

    public nonisolated var capabilities: ControllerCapabilities {
        .surgeHTTPAPI
    }

    public init(profile: RouterProfile, apiKey: String? = nil) {
        self.profile = profile
        self.apiKey = apiKey
    }

    public func testConnection() async throws -> UnifiedControllerHealth {
        let client = SurgeHttpAPIClient(profile: profile, apiKey: apiKey)
        let events = try await client.events()

        return UnifiedControllerHealth(
            state: .ready,
            checkedAt: Date(),
            endpointStatuses: [
                UnifiedControllerEndpointStatus(endpoint: .surgeEvents, state: .ready, safeDetail: "\(events.events.count) events"),
            ],
            safeSummary: "surge-http-api-events-ready"
        )
    }

    public func snapshot() async throws -> UnifiedControllerSnapshot {
        let client = SurgeHttpAPIClient(profile: profile, apiKey: apiKey)
        let snapshot = try await client.snapshot()

        return UnifiedControllerSnapshot.surgeHTTPAPI(
            profile: profile,
            snapshot: snapshot
        )
    }
}

public actor SingBoxControllerAdapter: ControllerAdapterProtocol {
    public nonisolated let profile: RouterProfile
    private let credential: String?

    public nonisolated var controllerType: UnifiedControllerType {
        .singBoxCompatible
    }

    public nonisolated var capabilities: ControllerCapabilities {
        .singBoxCompatible
    }

    public init(profile: RouterProfile, credential: String? = nil) {
        self.profile = profile
        self.credential = credential
    }

    public func testConnection() async throws -> UnifiedControllerHealth {
        try await withClient { client in
            let version = try await client.version()
            return UnifiedControllerHealth(
                state: .ready,
                checkedAt: Date(),
                endpointStatuses: [
                    UnifiedControllerEndpointStatus(
                        endpoint: .singBoxVersion,
                        state: .ready,
                        safeDetail: "\(version.version); api=\(version.apiVersion)"
                    ),
                ],
                safeSummary: "sing-box-started-service-ready"
            )
        }
    }

    public func snapshot() async throws -> UnifiedControllerSnapshot {
        let profile = profile
        return try await withClient { client in
            let statusStream = try client.statusStream(intervalMilliseconds: 1_000)
            let groupStream = client.groupStream()

            async let version = client.version()
            async let status = Self.firstValue(from: statusStream, endpoint: "status")
            async let groups = Self.firstValue(from: groupStream, endpoint: "groups")
            async let mode = client.clashModeStatus()
            let values = try await (
                version: version,
                status: status,
                groups: groups,
                mode: mode
            )

            return UnifiedControllerSnapshot.singBox(
                profile: profile,
                version: values.version,
                status: values.status,
                groups: values.groups,
                mode: values.mode
            )
        }
    }

    private func withClient<Result: Sendable>(
        operation: @Sendable (SingBoxGRPCClient) async throws -> Result
    ) async throws -> Result {
        try await SingBoxGRPCClient.withConnectedClient(
            profile: profile,
            credential: credential,
            operation: operation
        )
    }

    private static func firstValue<Value: Sendable>(
        from stream: SingBoxGRPCStream<Value>,
        endpoint: String
    ) async throws -> Value {
        defer { stream.cancel() }
        return try await withThrowingTaskGroup(of: Value.self, returning: Value.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                guard let value = try await iterator.next() else {
                    throw SingBoxGRPCError.transport("sing-box \(endpoint) stream ended before its first frame")
                }
                return value
            }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw SingBoxGRPCError.transport("sing-box \(endpoint) stream timed out")
            }

            guard let value = try await group.next() else {
                throw SingBoxGRPCError.transport("sing-box \(endpoint) stream produced no result")
            }
            group.cancelAll()
            return value
        }
    }
}

public struct UnavailableControllerAdapter: ControllerAdapterProtocol {
    public let profile: RouterProfile
    public let controllerType: UnifiedControllerType
    public let capabilities: ControllerCapabilities
    private let reason: String

    public init(profile: RouterProfile, reason: String) {
        self.profile = profile
        self.controllerType = profile.unifiedControllerType
        self.capabilities = UnifiedControllerAdapterRegistry.capabilities(for: profile)
        self.reason = reason
    }

    public func testConnection() async throws -> UnifiedControllerHealth {
        UnifiedControllerHealth.unavailable(reason: reason)
    }

    public func snapshot() async throws -> UnifiedControllerSnapshot {
        UnifiedControllerAdapterRegistry.unavailableSnapshot(profile: profile, reason: reason)
    }
}

public extension UnifiedControllerAdapterRegistry {
    static func makeAdapter(profile: RouterProfile, credential: String?) -> any ControllerAdapterProtocol {
        switch profile.unifiedControllerType {
        case .mihomoCompatible, .openClashMihomoCompatible, .nikkiMihomoCompatible, .cmfaCompatible, .stashCompatible:
            return MihomoCompatibleControllerAdapter(profile: profile, secret: credential)
        case .surgeHTTPAPI:
            return SurgeHTTPAPIControllerAdapter(profile: profile, apiKey: credential)
        case .singBoxCompatible:
            return SingBoxControllerAdapter(profile: profile, credential: credential)
        case .smartProbe:
            return UnavailableControllerAdapter(
                profile: profile,
                reason: "smart-probe-capability-only; no-local-core-runtime"
            )
        case .stashCmfaCompatible:
            return UnavailableControllerAdapter(
                profile: profile,
                reason: "stash-cmfa-adapter-unavailable; capability-matrix-only"
            )
        case .unknown, .unsupported:
            return UnavailableControllerAdapter(
                profile: profile,
                reason: "controller-adapter-unavailable"
            )
        }
    }
}

public extension UnifiedControllerSnapshot {
    static func mihomoCompatible(
        profile: RouterProfile,
        controllerType: UnifiedControllerType? = nil,
        version: VersionResponse,
        config: ConfigResponse,
        proxies: ProxiesResponse,
        connections: ConnectionsResponse,
        rules: RulesResponse?,
        providers: ProxyProvidersResponse?,
        ruleProviders: RuleProvidersResponse? = nil
    ) -> UnifiedControllerSnapshot {
        let policyGroups = proxies.policyGroups.map { group in
            UnifiedPolicyGroupSnapshot(
                id: "mihomo-group-\(group.name)",
                displayLabel: displayLabel(group.name),
                selectedDisplayLabel: group.now.map { displayLabel($0) },
                optionCount: group.all.count
            )
        }

        let rulesLoaded = rules != nil
        let providersLoaded = providers != nil
        let ruleProvidersLoaded = ruleProviders != nil
        let providerCount = (providers?.providerList.count ?? 0) + (ruleProviders?.providerList.count ?? 0)
        let isPartial = !rulesLoaded || !providersLoaded || !ruleProvidersLoaded

        let resolvedControllerType = controllerType ?? profile.unifiedControllerType

        return UnifiedControllerSnapshot(
            controllerType: resolvedControllerType,
            adapterSource: UnifiedControllerAdapterRegistry.adapterSource(for: resolvedControllerType),
            capabilities: UnifiedControllerAdapterRegistry.capabilities(for: resolvedControllerType),
            health: UnifiedControllerHealth(
                state: isPartial ? .partial : .ready,
                checkedAt: Date(),
                endpointStatuses: [
                    UnifiedControllerEndpointStatus(endpoint: .version, state: .ready, safeDetail: version.version),
                    UnifiedControllerEndpointStatus(endpoint: .configs, state: .ready, safeDetail: config.mode ?? "mode-unknown"),
                    UnifiedControllerEndpointStatus(endpoint: .proxies, state: .ready, safeDetail: "\(proxies.policyGroups.count) groups"),
                    UnifiedControllerEndpointStatus(endpoint: .connections, state: .ready, safeDetail: "\(connections.connections.count) active"),
                    UnifiedControllerEndpointStatus(endpoint: .rules, state: rulesLoaded ? .ready : .unavailable, safeDetail: rulesLoaded ? "\(rules?.rules.count ?? 0) rules" : "not-loaded"),
                    UnifiedControllerEndpointStatus(endpoint: .providers, state: providerCount > 0 ? .ready : .unavailable, safeDetail: providerCount > 0 ? "\(providerCount) providers" : "not-loaded"),
                ],
                safeSummary: isPartial ? "mihomo-compatible-partial-snapshot" : "mihomo-compatible-ready"
            ),
            checkedAt: Date(),
            versionLabel: version.version,
            modeLabel: config.mode ?? "",
            traffic: UnifiedTrafficSnapshot(
                upload: connections.uploadTotal ?? 0,
                download: connections.downloadTotal ?? 0
            ),
            policyGroups: policyGroups,
            rulesCount: rules?.rules.count ?? 0,
            providersCount: providerCount,
            connectionsCount: connections.connections.count,
            isPartial: isPartial,
            unavailableReason: isPartial ? "enhanced-snapshot-partial" : nil
        )
    }

    static func surgeHTTPAPI(
        profile: RouterProfile,
        snapshot: SurgeControlSnapshot
    ) -> UnifiedControllerSnapshot {
        let groups = snapshot.policyGroups.map { group in
            UnifiedPolicyGroupSnapshot(
                id: "surge-policy-group-\(group.name)",
                displayLabel: displayLabel(group.name),
                selectedDisplayLabel: group.selected.map { displayLabel($0) },
                optionCount: group.policies.count,
                latencyBuckets: latencyBuckets(from: group.latency)
            )
        }

        return UnifiedControllerSnapshot(
            controllerType: .surgeHTTPAPI,
            adapterSource: "surge-http-api-x-key",
            capabilities: .surgeHTTPAPI,
            health: UnifiedControllerHealth(
                state: .ready,
                checkedAt: snapshot.checkedAt ?? Date(),
                endpointStatuses: [
                    UnifiedControllerEndpointStatus(endpoint: .surgeEvents, state: .ready, safeDetail: "\(snapshot.events.count) events"),
                    UnifiedControllerEndpointStatus(endpoint: .surgeOutbound, state: .ready, safeDetail: snapshot.outboundMode),
                    UnifiedControllerEndpointStatus(endpoint: .surgePolicyGroups, state: .ready, safeDetail: "\(snapshot.policyGroups.count) groups"),
                    UnifiedControllerEndpointStatus(endpoint: .surgeActiveRequests, state: .ready, safeDetail: "\(snapshot.activeRequests.count) active"),
                    UnifiedControllerEndpointStatus(endpoint: .rules, state: .ready, safeDetail: "\(snapshot.rules.count) rules"),
                    UnifiedControllerEndpointStatus(endpoint: .surgeTraffic, state: .ready, safeDetail: "aggregate"),
                    UnifiedControllerEndpointStatus(endpoint: .surgeDNSCache, state: snapshot.dnsCacheEntryCount == nil ? .unavailable : .ready, safeDetail: snapshot.dnsCacheEntryCount.map { "\($0) entries" } ?? "not-loaded"),
                ],
                safeSummary: "surge-http-api-ready"
            ),
            checkedAt: snapshot.checkedAt ?? Date(),
            versionLabel: "Surge HTTP API",
            modeLabel: snapshot.outboundMode,
            traffic: UnifiedTrafficSnapshot(upload: snapshot.traffic.upload, download: snapshot.traffic.download),
            policyGroups: groups,
            rulesCount: snapshot.rules.count,
            providersCount: 0,
            connectionsCount: snapshot.activeRequests.count,
            isPartial: false
        )
    }

    static func singBox(
        profile: RouterProfile,
        version: SingBoxVersion,
        status: SingBoxStatusSnapshot,
        groups: SingBoxPolicyCatalog,
        mode: SingBoxClashModeStatus
    ) -> UnifiedControllerSnapshot {
        let policyGroups = groups.groups.map { group in
            let delays = group.items.reduce(into: [String: Int]()) { values, item in
                if values[item.tag] == nil {
                    values[item.tag] = Int(item.urlTestDelayMilliseconds)
                }
            }
            return UnifiedPolicyGroupSnapshot(
                id: "sing-box-group-\(group.tag)",
                displayLabel: displayLabel(group.tag),
                selectedDisplayLabel: group.selected.isEmpty ? nil : displayLabel(group.selected),
                optionCount: group.items.count,
                latencyBuckets: latencyBuckets(from: delays)
            )
        }

        return UnifiedControllerSnapshot(
            controllerType: .singBoxCompatible,
            adapterSource: UnifiedControllerAdapterRegistry.adapterSource(for: .singBoxCompatible),
            capabilities: .singBoxCompatible,
            health: UnifiedControllerHealth(
                state: .ready,
                checkedAt: Date(),
                endpointStatuses: [
                    UnifiedControllerEndpointStatus(
                        endpoint: .singBoxVersion,
                        state: .ready,
                        safeDetail: "\(version.version); api=\(version.apiVersion)"
                    ),
                    UnifiedControllerEndpointStatus(
                        endpoint: .singBoxStatus,
                        state: .ready,
                        safeDetail: "traffic=\(status.trafficAvailable); memory=\(status.memoryBytes)"
                    ),
                    UnifiedControllerEndpointStatus(
                        endpoint: .singBoxGroups,
                        state: .ready,
                        safeDetail: "\(groups.groups.count) groups"
                    ),
                    UnifiedControllerEndpointStatus(
                        endpoint: .singBoxMode,
                        state: .ready,
                        safeDetail: mode.currentMode
                    ),
                ],
                safeSummary: "sing-box-started-service-ready"
            ),
            checkedAt: Date(),
            versionLabel: version.version,
            modeLabel: mode.currentMode,
            traffic: UnifiedTrafficSnapshot(
                upload: Int(clamping: status.uplinkBytesPerSecond),
                download: Int(clamping: status.downlinkBytesPerSecond)
            ),
            policyGroups: policyGroups,
            rulesCount: 0,
            providersCount: 0,
            connectionsCount: 0,
            isPartial: false
        )
    }

    static func unavailable(
        profile: RouterProfile,
        reason: String
    ) -> UnifiedControllerSnapshot {
        let type = profile.unifiedControllerType
        return UnifiedControllerSnapshot(
            controllerType: type,
            adapterSource: UnifiedControllerAdapterRegistry.adapterSource(for: type),
            capabilities: UnifiedControllerAdapterRegistry.capabilities(for: profile),
            health: .unavailable(reason: reason),
            checkedAt: Date(),
            versionLabel: type.label,
            modeLabel: "Unavailable",
            isPartial: true,
            unavailableReason: reason
        )
    }

    private static func displayLabel(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func latencyBuckets(from latency: [String: Int]?) -> [String: Int] {
        guard let latency else {
            return [:]
        }

        var buckets = [
            "fast": 0,
            "normal": 0,
            "slow": 0,
            "timeout": 0,
        ]

        for delay in latency.values {
            switch delay {
            case ..<80:
                buckets["fast", default: 0] += 1
            case 80..<180:
                buckets["normal", default: 0] += 1
            case 180..<1000:
                buckets["slow", default: 0] += 1
            default:
                buckets["timeout", default: 0] += 1
            }
        }

        return buckets
    }
}
