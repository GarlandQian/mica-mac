import Foundation
import MicaCore

enum ControllerConfigPort: String, CaseIterable, Identifiable {
    case http
    case socks
    case redir
    case mixed

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .http: "overview.config_http_port"
        case .socks: "overview.config_socks_port"
        case .redir: "overview.config_redir_port"
        case .mixed: "overview.config_mixed_port"
        }
    }
}

enum ControllerConfigMutation: Equatable {
    case logLevel(String)
    case allowLAN(Bool)
    case ipv6(Bool)
    case tcpConcurrent(Bool)
    case tun(Bool)
    case port(ControllerConfigPort, Int)

    var id: String {
        switch self {
        case .logLevel: "log-level"
        case .allowLAN: "allow-lan"
        case .ipv6: "ipv6"
        case .tcpConcurrent: "tcp-concurrent"
        case .tun: "tun"
        case .port(let port, _): "port:\(port.rawValue)"
        }
    }

    var action: UnifiedControllerAction {
        switch self {
        case .logLevel: .setLogLevel
        case .allowLAN: .setAllowLAN
        case .ipv6: .setIPv6
        case .tcpConcurrent: .setTCPConcurrent
        case .tun: .setTUN
        case .port: .setPort
        }
    }

    var patch: MihomoConfigPatch {
        switch self {
        case .logLevel(let value):
            MihomoConfigPatch(logLevel: value)
        case .allowLAN(let value):
            MihomoConfigPatch(allowLan: value)
        case .ipv6(let value):
            MihomoConfigPatch(ipv6: value)
        case .tcpConcurrent(let value):
            MihomoConfigPatch(tcpConcurrent: value)
        case .tun(let value):
            MihomoConfigPatch(tunEnabled: value)
        case .port(.http, let value):
            MihomoConfigPatch(port: value)
        case .port(.socks, let value):
            MihomoConfigPatch(socksPort: value)
        case .port(.redir, let value):
            MihomoConfigPatch(redirPort: value)
        case .port(.mixed, let value):
            MihomoConfigPatch(mixedPort: value)
        }
    }

    func apply(to snapshot: inout DashboardConfigSnapshot) {
        switch self {
        case .logLevel(let value): snapshot.logLevel = value
        case .allowLAN(let value): snapshot.allowLan = value
        case .ipv6(let value): snapshot.ipv6 = value
        case .tcpConcurrent(let value): snapshot.tcpConcurrent = value
        case .tun(let value): snapshot.tunEnabled = value
        case .port(.http, let value): snapshot.port = value
        case .port(.socks, let value): snapshot.socksPort = value
        case .port(.redir, let value): snapshot.redirPort = value
        case .port(.mixed, let value): snapshot.mixedPort = value
        }
    }
}

struct DashboardConfigSnapshot: Equatable {
    var modeOptions: [String] = []
    var logLevel: String?
    var allowLan: Bool?
    var ipv6: Bool?
    var tcpConcurrent: Bool?
    var tunEnabled: Bool?
    var port: Int?
    var socksPort: Int?
    var redirPort: Int?
    var mixedPort: Int?

    static let empty = DashboardConfigSnapshot()

    init() {}

    init(response: ConfigResponse) {
        modeOptions = response.modeOptions ?? []
        logLevel = response.logLevel
        allowLan = response.allowLan
        ipv6 = response.ipv6
        tcpConcurrent = response.tcpConcurrent
        tunEnabled = response.tun?.enable
        port = response.port
        socksPort = response.socksPort
        redirPort = response.redirPort
        mixedPort = response.mixedPort
    }

    var reportedFieldCount: Int {
        let scalarCount = [
            logLevel.map { _ in 1 },
            allowLan.map { _ in 1 },
            ipv6.map { _ in 1 },
            tcpConcurrent.map { _ in 1 },
            tunEnabled.map { _ in 1 },
            port.map { _ in 1 },
            socksPort.map { _ in 1 },
            redirPort.map { _ in 1 },
            mixedPort.map { _ in 1 },
        ].compactMap { $0 }.reduce(0, +)

        return scalarCount + (modeOptions.isEmpty ? 0 : 1)
    }

    var diagnosticsSummary: String {
        [
            "fields=\(reportedFieldCount)",
            "mode-options=\(modeOptions.count)",
            "ports=\([port, socksPort, redirPort, mixedPort].compactMap { $0 }.count)",
            "boolean-flags=\([allowLan, ipv6, tcpConcurrent, tunEnabled].compactMap { $0 }.count)",
        ].joined(separator: "; ")
    }
}

/// Low-frequency controller identity and configuration published separately
/// from traffic, logs, and connection frames.
struct ControllerMetadataSnapshot: Equatable {
    var versionLabel: String
    var mode: String
    var config: DashboardConfigSnapshot

    static let empty = ControllerMetadataSnapshot(
        versionLabel: "-",
        mode: "unknown",
        config: .empty
    )

    init(
        versionLabel: String,
        mode: String,
        config: DashboardConfigSnapshot
    ) {
        self.versionLabel = versionLabel
        self.mode = mode
        self.config = config
    }

    init(dashboard: DashboardSnapshot) {
        self.init(
            versionLabel: dashboard.versionLabel,
            mode: dashboard.mode,
            config: dashboard.config
        )
    }
}

struct DashboardPublicationDomains: OptionSet, Sendable {
    let rawValue: Int

    static let metadata = DashboardPublicationDomains(rawValue: 1 << 0)
    static let policyGroups = DashboardPublicationDomains(rawValue: 1 << 1)
    static let connections = DashboardPublicationDomains(rawValue: 1 << 2)
    static let rules = DashboardPublicationDomains(rawValue: 1 << 3)
    static let providers = DashboardPublicationDomains(rawValue: 1 << 4)
    static let insight = DashboardPublicationDomains(rawValue: 1 << 5)

    static let baseline: DashboardPublicationDomains = [
        .metadata,
        .policyGroups,
        .connections,
        .rules,
        .providers,
        .insight,
    ]
}

struct PolicyGroupCatalogSnapshot: Equatable {
    var mode: String
    var groups: [ProxyGroupViewState]

    static let empty = PolicyGroupCatalogSnapshot(mode: "unknown", groups: [])

    init(mode: String, groups: [ProxyGroupViewState]) {
        self.mode = mode
        self.groups = groups
    }

    init(dashboard: DashboardSnapshot) {
        self.init(mode: dashboard.mode, groups: dashboard.groups)
    }
}

/// Per-domain published snapshot for the connections table + throughput totals.
/// Split out of `DashboardSnapshot` so the connections view is only invalidated
/// when connections/traffic actually change — not on every log or group write.
/// Same pattern as `PolicyGroupCatalogSnapshot`: an Equatable value re-derived
/// at the single `replaceDashboard` sync point with a `!=` de-dupe guard.
struct ConnectionsCatalogChange: Equatable {
    var structureChanged: Bool
    var metricsChanged: Bool
    /// `nil` means every metric row must be refreshed.
    var changedMetricIndices: [Int]?
    var trafficChanged: Bool

    static let none = ConnectionsCatalogChange(
        structureChanged: false,
        metricsChanged: false,
        changedMetricIndices: [],
        trafficChanged: false
    )

    static let replacement = ConnectionsCatalogChange(
        structureChanged: true,
        metricsChanged: true,
        changedMetricIndices: nil,
        trafficChanged: true
    )
}

struct ConnectionsCatalogSnapshot: Equatable {
    var connections: [ConnectionSnapshot]
    var traffic: TrafficSnapshot
    /// Changes only when membership, ordering, or route/static row fields change.
    var structureRevision: UInt64
    /// Changes when a visible connection row changes, including structure or counters.
    var metricsRevision: UInt64
    /// Changes only when controller aggregate traffic changes.
    var trafficRevision: UInt64
    /// Describes only the change that produced this snapshot. Consumers that
    /// miss a revision must fall back to the complete snapshot.
    var lastChange: ConnectionsCatalogChange

    static let empty = ConnectionsCatalogSnapshot(
        connections: [],
        traffic: TrafficSnapshot(upload: 0, download: 0),
        structureRevision: 0,
        metricsRevision: 0,
        trafficRevision: 0,
        lastChange: .none
    )

    init(
        connections: [ConnectionSnapshot],
        traffic: TrafficSnapshot,
        structureRevision: UInt64 = 0,
        metricsRevision: UInt64 = 0,
        trafficRevision: UInt64 = 0,
        lastChange: ConnectionsCatalogChange = .replacement
    ) {
        self.connections = connections
        self.traffic = traffic
        self.structureRevision = structureRevision
        self.metricsRevision = metricsRevision
        self.trafficRevision = trafficRevision
        self.lastChange = lastChange
    }

    init(
        dashboard: DashboardSnapshot,
        structureRevision: UInt64 = 0,
        metricsRevision: UInt64 = 0,
        trafficRevision: UInt64 = 0,
        lastChange: ConnectionsCatalogChange = .replacement
    ) {
        self.init(
            connections: dashboard.connections,
            traffic: dashboard.traffic,
            structureRevision: structureRevision,
            metricsRevision: metricsRevision,
            trafficRevision: trafficRevision,
            lastChange: lastChange
        )
    }

    static func structuresMatch(
        _ lhs: [ConnectionSnapshot],
        _ rhs: [ConnectionSnapshot]
    ) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { left, right in
            left.id == right.id
                && left.start == right.start
                && left.chains == right.chains
                && left.providerChains == right.providerChains
                && left.rule == right.rule
                && left.rulePayload == right.rulePayload
                && left.metadata == right.metadata
                && left.additionalFields == right.additionalFields
        }
    }

    static func metricsMatch(
        _ lhs: [ConnectionSnapshot],
        _ rhs: [ConnectionSnapshot]
    ) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { left, right in
            left.upload == right.upload
                && left.download == right.download
                && left.uploadSpeed == right.uploadSpeed
                && left.downloadSpeed == right.downloadSpeed
        }
    }

    static func changedMetricIndices(
        _ lhs: [ConnectionSnapshot],
        _ rhs: [ConnectionSnapshot]
    ) -> [Int]? {
        guard lhs.count == rhs.count else { return nil }
        var changed: [Int] = []
        changed.reserveCapacity(min(lhs.count, 32))
        for index in lhs.indices where !metricsMatch(lhs[index], rhs[index]) {
            changed.append(index)
        }
        return changed
    }

    private static func metricsMatch(
        _ lhs: ConnectionSnapshot,
        _ rhs: ConnectionSnapshot
    ) -> Bool {
        lhs.upload == rhs.upload
            && lhs.download == rhs.download
            && lhs.uploadSpeed == rhs.uploadSpeed
            && lhs.downloadSpeed == rhs.downloadSpeed
    }
}

/// Visible log publication is sourced only from `ControllerSession.logBuffer`.
/// `DashboardSnapshot` is deliberately not consulted by the coalesced publisher.
enum LogsCatalogChange: Equatable {
    case none
    case replace
    case delta(
        droppedEntryIDs: [String],
        appendedEntries: [ControllerLogEntry]
    )
}

struct LogsCatalogSnapshot: Equatable {
    var entries: [ControllerLogEntry]
    /// Changes only when the visible log collection changes. Views observe this
    /// token instead of comparing the complete bounded log buffer per event.
    var entriesRevision: UInt64
    /// Describes only the mutation that produced this revision. Consumers that
    /// miss a revision use `entries` as an authoritative replacement.
    var lastChange: LogsCatalogChange

    static let empty = LogsCatalogSnapshot(
        entries: [],
        entriesRevision: 0,
        lastChange: .none
    )

    init(
        entries: [ControllerLogEntry],
        entriesRevision: UInt64 = 0,
        lastChange: LogsCatalogChange = .replace
    ) {
        self.entries = entries
        self.entriesRevision = entriesRevision
        self.lastChange = lastChange
    }

    func applying(_ publication: LiveSessionLogsPublication) -> LogsCatalogSnapshot {
        if let fullSnapshot = publication.fullSnapshot {
            return LogsCatalogSnapshot(
                entries: fullSnapshot,
                entriesRevision: entriesRevision &+ 1,
                lastChange: .replace
            )
        }

        var nextEntries = entries
        if !publication.droppedEntryIDs.isEmpty {
            let prefixIDs = nextEntries.prefix(publication.droppedEntryIDs.count).map(\.id)
            if prefixIDs == publication.droppedEntryIDs {
                nextEntries.removeFirst(min(publication.droppedEntryIDs.count, nextEntries.count))
            } else {
                let droppedIDs = Set(publication.droppedEntryIDs)
                nextEntries.removeAll { droppedIDs.contains($0.id) }
            }
        }
        nextEntries.append(contentsOf: publication.appendedEntries)
        if nextEntries.count > BoundedLogBuffer.maximumEntryCount {
            nextEntries.removeFirst(nextEntries.count - BoundedLogBuffer.maximumEntryCount)
        }
        return LogsCatalogSnapshot(
            entries: nextEntries,
            entriesRevision: entriesRevision &+ 1,
            lastChange: .delta(
                droppedEntryIDs: publication.droppedEntryIDs,
                appendedEntries: publication.appendedEntries
            )
        )
    }
}

/// Rules and providers publish independently so either endpoint can refresh
/// without invalidating the other data browser.
struct RulesCatalogSnapshot: Equatable {
    var rules: [RuleViewState]

    static let empty = RulesCatalogSnapshot(rules: [])

    init(rules: [RuleViewState]) {
        self.rules = rules
    }

    init(dashboard: DashboardSnapshot) {
        self.init(rules: dashboard.rules)
    }
}

struct RuleMutationTargetResolver {
    static func resolve(
        requested: RuleViewState,
        currentRules: [RuleViewState]
    ) -> RuleViewState? {
        guard requested.index != nil, requested.hasMutableExtra else { return nil }

        let matches = currentRules.filter { current in
            current.id == requested.id
                && current.index == requested.index
                && current.type == requested.type
                && current.payload == requested.payload
                && current.proxy == requested.proxy
                && current.hasMutableExtra
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }
}

struct ConnectionMutationTargetResolver {
    static func resolve(
        requested: ConnectionSnapshot,
        currentConnections: [ConnectionSnapshot]
    ) -> ConnectionSnapshot? {
        guard requested.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        let matches = currentConnections.filter { $0.id == requested.id }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    static func resolve(
        requested: [ConnectionSnapshot],
        currentConnections: [ConnectionSnapshot]
    ) -> [ConnectionSnapshot]? {
        guard requested.isEmpty == false else { return [] }

        var resolved: [ConnectionSnapshot] = []
        resolved.reserveCapacity(requested.count)
        var resolvedIDs = Set<String>()
        for connection in requested {
            guard let current = resolve(
                requested: connection,
                currentConnections: currentConnections
            ), resolvedIDs.insert(current.id).inserted else {
                return nil
            }
            resolved.append(current)
        }
        return resolved
    }
}

struct ProvidersCatalogSnapshot: Equatable {
    var providers: [ProxyProviderViewState]

    static let empty = ProvidersCatalogSnapshot(providers: [])

    init(providers: [ProxyProviderViewState]) {
        self.providers = providers
    }

    init(dashboard: DashboardSnapshot) {
        self.init(providers: dashboard.providers)
    }
}

struct DashboardSnapshot: Equatable {
    var versionLabel: String
    var mode: String
    var config: DashboardConfigSnapshot
    var traffic: TrafficSnapshot
    var groups: [ProxyGroupViewState]
    var connections: [ConnectionSnapshot]
    var rules: [RuleViewState]
    var providers: [ProxyProviderViewState]
    var insight: InsightSummarySnapshot

    var hasBaseSnapshot: Bool {
        versionLabel != "-"
            || !groups.isEmpty
            || !connections.isEmpty
            || traffic.upload > 0
            || traffic.download > 0
    }

    static let empty = DashboardSnapshot(
        versionLabel: "-",
        mode: "unknown",
        config: .empty,
        traffic: TrafficSnapshot(upload: 0, download: 0),
        groups: [],
        connections: [],
        rules: [],
        providers: []
    )

    init(
        versionLabel: String,
        mode: String,
        config: DashboardConfigSnapshot = .empty,
        traffic: TrafficSnapshot,
        groups: [ProxyGroupViewState],
        connections: [ConnectionSnapshot],
        rules: [RuleViewState] = [],
        providers: [ProxyProviderViewState] = []
    ) {
        self.versionLabel = versionLabel
        self.mode = mode
        self.config = config
        self.traffic = traffic
        self.groups = groups
        self.connections = connections
        self.rules = rules
        self.providers = providers
        insight = .empty
        refreshInsight()
    }

    init(
        version: VersionResponse,
        config: ConfigResponse,
        proxies: ProxiesResponse,
        connections: ConnectionsResponse,
        language: AppLanguage = MicaStrings.appLanguage
    ) {
        let groups = Self.proxyGroupViewStates(from: proxies)

        self.init(
            versionLabel: version.version,
            mode: Self.displayMode(config.mode),
            config: DashboardConfigSnapshot(response: config),
            traffic: TrafficSnapshot(
                upload: connections.uploadTotal ?? 0,
                download: connections.downloadTotal ?? 0
            ),
            groups: groups,
            connections: connections.connections
        )
    }

    mutating func replaceGroups(
        with proxies: ProxiesResponse,
        smartWeights: SmartWeightsResponse? = nil
    ) {
        let existingDelays = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.delays) })
        let existingUsageRanks = Dictionary(
            uniqueKeysWithValues: groups.map { ($0.id, $0.optionUsageRanks) }
        )

        groups = Self.proxyGroupViewStates(
            from: proxies,
            existingDelays: existingDelays,
            existingUsageRanks: existingUsageRanks,
            smartWeights: smartWeights
        )
        insight.updateRouteHealth(groups)
    }

    mutating func replaceConfig(with config: ConfigResponse) {
        mode = Self.displayMode(config.mode)
        self.config = DashboardConfigSnapshot(response: config)
    }

    mutating func replaceDelays(_ delays: [String: Int], in groupID: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else {
            return
        }

        groups[index].delays = delays
        insight.updateRouteHealth(groups)
    }

    mutating func replaceDelay(_ delay: Int, for node: String, in groupID: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else {
            return
        }

        groups[index].delays[node] = delay
        insight.updateRouteHealth(groups)
    }

    mutating func replaceConnections(
        with response: ConnectionsResponse,
        structureChanged: Bool = true,
        metricsChanged: Bool = true,
        trafficChanged: Bool = true
    ) {
        if trafficChanged {
            traffic = TrafficSnapshot(
                upload: response.uploadTotal ?? 0,
                download: response.downloadTotal ?? 0
            )
            insight.updateTraffic(traffic)
        }
        if structureChanged || metricsChanged {
            connections = response.connections
            insight.updateConnections(
                connections,
                structureChanged: structureChanged,
                metricsChanged: metricsChanged
            )
        }
    }

    mutating func replaceSingBoxStatus(with status: SingBoxStatusSnapshot) {
        traffic = TrafficSnapshot(
            upload: Int(clamping: status.uplinkTotalBytes),
            download: Int(clamping: status.downlinkTotalBytes)
        )
        insight.updateTraffic(traffic)
    }

    mutating func replaceSingBoxGroups(with catalog: SingBoxPolicyCatalog) {
        groups = catalog.groups.map { group in
            var optionDetails: [String: ProxyNodeViewState] = [:]
            var delays: [String: Int] = [:]
            for item in group.items where optionDetails[item.tag] == nil {
                optionDetails[item.tag] = ProxyNodeViewState(singBoxNode: item)
            }
            for item in group.items
            where delays[item.tag] == nil
                && (item.urlTestTimestamp != 0 || item.urlTestDelayMilliseconds != 0) {
                delays[item.tag] = Int(item.urlTestDelayMilliseconds)
            }
            return ProxyGroupViewState(
                id: group.tag,
                type: group.type,
                selected: group.selected,
                options: group.items.map(\.tag),
                details: ProxyNodeViewState(singBoxGroup: group),
                optionDetails: optionDetails,
                hidden: false,
                selectable: group.selectable,
                delays: delays
            )
        }
        insight.updateRouteHealth(groups)
    }

    mutating func replaceSingBoxMode(with status: SingBoxClashModeStatus) {
        mode = Self.displayMode(status.currentMode)
        config.modeOptions = status.availableModes
    }

    mutating func replaceRules(with response: RulesResponse) {
        rules = response.rules.map { rule in
            RuleViewState(
                id: rule.id,
                index: rule.index,
                type: rule.type,
                payload: rule.payload,
                proxy: rule.proxy,
                size: rule.size,
                disabled: rule.disabled,
                hitCount: rule.hitCount,
                hitAt: rule.hitAt,
                missCount: rule.missCount,
                missAt: rule.missAt,
                hasMutableExtra: rule.hasMutableExtra,
                extraMetadata: rule.extra?.metadata ?? [:],
                metadata: rule.additionalMetadata
            )
        }
        insight.updateRuleCount(rules.count)
    }

    mutating func replaceProviders(with response: ProxyProvidersResponse) {
        replaceProviders(proxyProviders: response, ruleProviders: nil)
    }

    mutating func replaceProviders(
        proxyProviders: ProxyProvidersResponse?,
        ruleProviders: RuleProvidersResponse?
    ) {
        let proxyRows = proxyProviders?.providerList.map { provider in
            ProxyProviderViewState(
                kind: .proxy,
                name: provider.name,
                type: provider.type,
                behavior: nil,
                format: provider.format,
                vehicleType: provider.vehicleType,
                updatedAt: provider.updatedAt,
                updatable: provider.updatable,
                testURL: provider.testURL,
                healthCheck: provider.healthCheck,
                subscriptionInfo: provider.subscriptionInfo,
                itemCount: provider.proxyCount
            )
        } ?? []

        let ruleRows = ruleProviders?.providerList.map { provider in
            ProxyProviderViewState(
                kind: .rule,
                name: provider.name,
                type: provider.type,
                behavior: provider.behavior,
                format: provider.format,
                vehicleType: provider.vehicleType,
                updatedAt: provider.updatedAt,
                updatable: provider.updatable,
                healthCheck: provider.healthCheck,
                itemCount: provider.ruleCount
            )
        } ?? []

        providers = proxyRows + ruleRows
        insight.updateProviderCount(providers.count)
    }

    static func displayMode(_ mode: String?) -> String {
        guard let mode, !mode.isEmpty else {
            return "unknown"
        }

        return mode.prefix(1).uppercased() + mode.dropFirst()
    }

    private static func proxyGroupViewStates(
        from response: ProxiesResponse,
        existingDelays: [String: [String: Int]] = [:],
        existingUsageRanks: [String: [String: PolicyGroupUsageRank]] = [:],
        smartWeights: SmartWeightsResponse? = nil
    ) -> [ProxyGroupViewState] {
        // A node may appear in many groups. Its reported metadata and search
        // text only need projecting once for this response. Keep the cache
        // local so a later history/configuration update cannot retain old data.
        var sharedOptionDetails: [String: ProxyNodeViewState] = [:]
        return mihomoPolicyGroupsInConfigurationOrder(response.policyGroups).map { proxy in
            var optionDetails: [String: ProxyNodeViewState] = [:]
            optionDetails.reserveCapacity(proxy.all.count)
            for option in proxy.all where optionDetails[option] == nil {
                if let existing = sharedOptionDetails[option] {
                    optionDetails[option] = existing
                    continue
                }
                guard let snapshot = response.proxies[option] else { continue }
                let detail = ProxyNodeViewState(snapshot: snapshot)
                sharedOptionDetails[option] = detail
                optionDetails[option] = detail
            }

            let optionUsageRanks: [String: PolicyGroupUsageRank]
            if proxy.type.caseInsensitiveCompare("Smart") != .orderedSame {
                optionUsageRanks = [:]
            } else if let smartWeights {
                optionUsageRanks = (smartWeights.weights[proxy.name] ?? []).reduce(into: [:]) {
                    ranks, item in
                    ranks[item.name] = PolicyGroupUsageRank(reportedValue: item.rank)
                }
            } else {
                optionUsageRanks = existingUsageRanks[proxy.name] ?? [:]
            }

            return ProxyGroupViewState(
                id: proxy.name,
                type: proxy.type,
                selected: proxy.now ?? "-",
                options: proxy.all,
                details: ProxyNodeViewState(snapshot: proxy),
                optionDetails: optionDetails,
                optionUsageRanks: optionUsageRanks,
                hidden: proxy.hidden ?? false,
                delays: existingDelays[proxy.name] ?? [:]
            )
        }
    }

    private static func mihomoPolicyGroupsInConfigurationOrder(
        _ groups: [ProxySnapshot]
    ) -> [ProxySnapshot] {
        let globalGroups = groups.filter { $0.name == "GLOBAL" }
        guard let global = globalGroups.first else { return groups }

        let peers = groups.filter { $0.name != "GLOBAL" }
        var peersByName: [String: [ProxySnapshot]] = [:]
        for peer in peers {
            peersByName[peer.name, default: []].append(peer)
        }

        var consumedNames: Set<String> = []
        var orderedPeers: [ProxySnapshot] = []
        for name in global.all where consumedNames.insert(name).inserted {
            orderedPeers.append(contentsOf: peersByName[name] ?? [])
        }
        orderedPeers.append(
            contentsOf: peers.filter { !consumedNames.contains($0.name) }
        )
        return orderedPeers + globalGroups
    }

    private mutating func refreshInsight() {
        insight = InsightSummarySnapshot(snapshot: self)
    }
}

struct ControllerLogEntry: Identifiable, Equatable, Sendable {
    var id: String
    var receivedAt: Date
    var message: LogMessage
    let structuredFieldsText: String?

    init(id: String = UUID().uuidString, receivedAt: Date = Date(), message: LogMessage) {
        self.id = id
        self.receivedAt = receivedAt
        self.message = message
        self.structuredFieldsText = Self.encodeStructuredFields(message.fields)
    }

    private static func encodeStructuredFields(
        _ fields: MihomoJSONValue?
    ) -> String? {
        guard let fields else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(fields),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        return text
    }
}

enum PolicyGroupUsageRank: Equatable {
    case rarelyUsed
    case occasionallyUsed
    case mostUsed
    case reported(String)

    init(reportedValue: String) {
        switch reportedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "rarelyused": self = .rarelyUsed
        case "occasionalused": self = .occasionallyUsed
        case "mostused": self = .mostUsed
        default: self = .reported(reportedValue)
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .rarelyUsed:
            MicaStrings.localizedKey("routing.smart_rank_rarely_used", language: language)
        case .occasionallyUsed:
            MicaStrings.localizedKey("routing.smart_rank_occasionally_used", language: language)
        case .mostUsed:
            MicaStrings.localizedKey("routing.smart_rank_most_used", language: language)
        case .reported(let value):
            value
        }
    }
}

struct ProxyGroupViewState: Identifiable, Equatable {
    var id: String
    var type: String
    var selected: String
    var options: [String]
    var details: ProxyNodeViewState?
    var optionDetails: [String: ProxyNodeViewState] = [:]
    var optionUsageRanks: [String: PolicyGroupUsageRank] = [:]
    var hidden: Bool = false
    var selectable: Bool = true
    var delays: [String: Int] = [:]

    init(
        id: String,
        type: String,
        selected: String,
        options: [String],
        details: ProxyNodeViewState? = nil,
        optionDetails: [String: ProxyNodeViewState] = [:],
        optionUsageRanks: [String: PolicyGroupUsageRank] = [:],
        hidden: Bool = false,
        selectable: Bool = true,
        delays: [String: Int] = [:]
    ) {
        self.id = id
        self.type = type
        self.selected = selected
        self.options = options
        self.details = details
        self.optionDetails = optionDetails
        self.optionUsageRanks = optionUsageRanks
        self.hidden = hidden
        self.selectable = selectable
        self.delays = delays
    }

    func detail(for option: String) -> ProxyNodeViewState? {
        optionDetails[option]
    }

    func usageRank(for option: String) -> PolicyGroupUsageRank? {
        optionUsageRanks[option]
    }
}

enum ProxySearchText {
    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: nil
            )
    }
}

struct ProxyTransportCapabilityState: Identifiable, Equatable {
    let id: String
    let name: String
    let isEnabled: Bool
}

struct ProxyNodeViewState: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let type: String
    let alive: Bool?
    let history: [ProxyDelayHistorySnapshot]
    let icon: String?
    let testURL: String?
    let providerName: String?
    var fixed: String? {
        didSet {
            searchableText = Self.searchableText(
                name: name,
                type: type,
                providerName: providerName,
                interfaceName: interfaceName,
                fixed: fixed,
                testURL: testURL,
                icon: icon,
                transportNames: transportNames,
                additionalMetadataText: additionalMetadataText
            )
        }
    }
    let interfaceName: String?
    let hidden: Bool?
    let transportCapabilities: [ProxyTransportCapabilityState]
    let transportNames: [String]
    let metadata: [String: MihomoJSONValue]
    let reportedMetadata: [String: MihomoJSONValue]
    private(set) var searchableText: String
    let additionalMetadataText: String?

    init(snapshot: ProxySnapshot) {
        self.init(
            name: snapshot.name,
            type: snapshot.type,
            alive: snapshot.alive,
            history: snapshot.history,
            icon: snapshot.icon,
            testURL: snapshot.testURL,
            providerName: snapshot.providerName,
            fixed: snapshot.fixed,
            interfaceName: snapshot.interfaceName,
            hidden: snapshot.hidden,
            transportCapabilities: Self.transportCapabilities(
                udp: snapshot.udp,
                uot: snapshot.uot,
                xudp: snapshot.xudp,
                tfo: snapshot.tfo,
                mptcp: snapshot.mptcp,
                smux: snapshot.smux
            ),
            metadata: snapshot.metadata
        )
    }

    init(singBoxNode node: SingBoxPolicyNode) {
        let hasURLTestMeasurement = node.urlTestTimestamp != 0 || node.urlTestDelayMilliseconds != 0
        let history = hasURLTestMeasurement
            ? [
                ProxyDelayHistorySnapshot(
                    time: node.urlTestTimestamp == 0 ? nil : String(node.urlTestTimestamp),
                    delay: Int(node.urlTestDelayMilliseconds)
                ),
            ]
            : []
        let metadata: [String: MihomoJSONValue] = hasURLTestMeasurement
            ? [
                "urlTestTime": .string(String(node.urlTestTimestamp)),
                "urlTestDelay": .number(Double(node.urlTestDelayMilliseconds)),
            ]
            : [:]

        self.init(
            name: node.tag,
            type: node.type,
            alive: nil,
            history: history,
            icon: nil,
            testURL: nil,
            providerName: nil,
            fixed: nil,
            interfaceName: nil,
            hidden: nil,
            transportCapabilities: [],
            metadata: metadata
        )
    }

    init(singBoxGroup group: SingBoxPolicyGroup) {
        self.init(
            name: group.tag,
            type: group.type,
            alive: nil,
            history: [],
            icon: nil,
            testURL: nil,
            providerName: nil,
            fixed: nil,
            interfaceName: nil,
            hidden: nil,
            transportCapabilities: [],
            metadata: [
                "selected": .string(group.selected),
                "selectable": .bool(group.selectable),
                "isExpand": .bool(group.isExpandedByController),
            ]
        )
    }

    private init(
        name: String,
        type: String,
        alive: Bool?,
        history: [ProxyDelayHistorySnapshot],
        icon: String?,
        testURL: String?,
        providerName: String?,
        fixed: String?,
        interfaceName: String?,
        hidden: Bool?,
        transportCapabilities: [ProxyTransportCapabilityState],
        metadata: [String: MihomoJSONValue]
    ) {
        let icon = icon?.nilIfEmpty
        let testURL = testURL?.nilIfEmpty
        let providerName = providerName?.nilIfEmpty
        let fixed = fixed?.nilIfEmpty
        let interfaceName = interfaceName?.nilIfEmpty
        let transportNames = transportCapabilities
            .filter(\.isEnabled)
            .map(\.name)
        let additionalMetadata = metadata.filter {
            !Self.knownMetadataKeys.contains($0.key)
        }
        let additionalMetadataText = Self.metadataText(for: additionalMetadata)

        self.name = name
        self.type = type
        self.alive = alive
        self.history = history
        self.icon = icon
        self.testURL = testURL
        self.providerName = providerName
        self.fixed = fixed
        self.interfaceName = interfaceName
        self.hidden = hidden
        self.transportCapabilities = transportCapabilities
        self.transportNames = transportNames
        self.metadata = metadata
        self.reportedMetadata = additionalMetadata
        self.additionalMetadataText = additionalMetadataText
        searchableText = Self.searchableText(
            name: name,
            type: type,
            providerName: providerName,
            interfaceName: interfaceName,
            fixed: fixed,
            testURL: testURL,
            icon: icon,
            transportNames: transportNames,
            additionalMetadataText: additionalMetadataText
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
            && lhs.type == rhs.type
            && lhs.alive == rhs.alive
            && lhs.history == rhs.history
            && lhs.icon == rhs.icon
            && lhs.testURL == rhs.testURL
            && lhs.providerName == rhs.providerName
            && lhs.fixed == rhs.fixed
            && lhs.interfaceName == rhs.interfaceName
            && lhs.hidden == rhs.hidden
            && lhs.transportCapabilities == rhs.transportCapabilities
            && reportedMetadataMatches(lhs, rhs)
    }

    private static func reportedMetadataMatches(_ lhs: Self, _ rhs: Self) -> Bool {
        // Known fields are compared above; this text already represents every
        // additional controller field shown by the Workbench.
        if let left = lhs.additionalMetadataText,
           let right = rhs.additionalMetadataText,
           left == right {
            return true
        }
        return lhs.reportedMetadata == rhs.reportedMetadata
    }

    private static let knownMetadataKeys: Set<String> = [
        "name", "type", "now", "all", "alive", "history", "icon",
        "testUrl", "tester", "provider-name", "fixed", "interface",
        "udp", "uot", "xudp", "tfo", "mptcp", "smux", "hidden",
    ]

    private static func transportCapabilities(
        udp: Bool?,
        uot: Bool?,
        xudp: Bool?,
        tfo: Bool?,
        mptcp: Bool?,
        smux: Bool?
    ) -> [ProxyTransportCapabilityState] {
        [
            ("udp", "UDP", udp),
            ("uot", "UOT", uot),
            ("xudp", "XUDP", xudp),
            ("tfo", "TFO", tfo),
            ("mptcp", "MPTCP", mptcp),
            ("smux", "SMUX", smux),
        ].compactMap { id, name, enabled in
            enabled.map {
                ProxyTransportCapabilityState(
                    id: id,
                    name: name,
                    isEnabled: $0
                )
            }
        }
    }

    private static func searchableText(
        name: String,
        type: String,
        providerName: String?,
        interfaceName: String?,
        fixed: String?,
        testURL: String?,
        icon: String?,
        transportNames: [String],
        additionalMetadataText: String?
    ) -> String {
        ProxySearchText.normalize(
            [
                name,
                type,
                providerName,
                interfaceName,
                fixed,
                testURL,
                icon,
                transportNames.joined(separator: " "),
                additionalMetadataText,
            ]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " ")
        )
    }

    var latestHistoryDelay: Int? {
        history.last(where: { $0.delay != nil })?.delay
    }

    var latestHistoryTime: String? {
        history.last(where: { $0.time?.nilIfEmpty != nil })?.time?.nilIfEmpty
    }

    private static func metadataText(
        for metadata: [String: MihomoJSONValue]
    ) -> String? {
        guard !metadata.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(metadata),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        return text
    }
}

extension ConnectionSnapshot {
    init(singBox connection: SingBoxConnection) {
        let processFields: [String: MihomoJSONValue] = connection.process.map { process in
            [
                "processId": .number(Double(process.processID)),
                "userId": .number(Double(process.userID)),
                "userName": .string(process.userName),
                "processPath": .string(process.processPath),
                "packageNames": .array(process.packageNames.map(MihomoJSONValue.string)),
            ]
        } ?? [:]
        let rawFields: [String: MihomoJSONValue] = [
            "id": .string(connection.id),
            "inbound": .string(connection.inbound),
            "inboundType": .string(connection.inboundType),
            "ipVersion": .number(Double(connection.ipVersion)),
            "network": .string(connection.network),
            "source": .string(connection.source),
            "destination": .string(connection.destination),
            "domain": .string(connection.domain),
            "protocol": .string(connection.protocolName),
            "user": .string(connection.user),
            "fromOutbound": .string(connection.fromOutbound),
            "createdAt": .string(String(connection.createdAt)),
            "closedAt": .string(String(connection.closedAt)),
            "uplink": .string(String(connection.uplinkBytesPerSecond)),
            "downlink": .string(String(connection.downlinkBytesPerSecond)),
            "uplinkTotal": .string(String(connection.uplinkTotalBytes)),
            "downlinkTotal": .string(String(connection.downlinkTotalBytes)),
            "rule": .string(connection.rule),
            "outbound": .string(connection.outbound),
            "outboundType": .string(connection.outboundType),
            "chainList": .array(connection.chain.map(MihomoJSONValue.string)),
            "processInfo": .object(processFields),
        ]
        let processName = connection.process?.processPath
            .split(separator: "/")
            .last
            .map(String.init)

        self.init(
            id: connection.id,
            upload: Int(clamping: connection.uplinkTotalBytes),
            download: Int(clamping: connection.downlinkTotalBytes),
            uploadSpeed: Int(clamping: connection.uplinkBytesPerSecond),
            downloadSpeed: Int(clamping: connection.downlinkBytesPerSecond),
            start: String(connection.createdAt),
            chains: connection.chain,
            rule: connection.rule,
            metadata: ConnectionMetadataSnapshot(
                host: connection.domain.nilIfEmpty ?? connection.destination.nilIfEmpty,
                network: connection.network.nilIfEmpty,
                type: connection.inboundType.nilIfEmpty,
                sourceIP: connection.source.nilIfEmpty,
                destinationIP: connection.destination.nilIfEmpty,
                process: processName,
                processPath: connection.process?.processPath.nilIfEmpty,
                inboundName: connection.inbound.nilIfEmpty,
                specialProxy: connection.outbound.nilIfEmpty,
                specialRules: connection.rule.nilIfEmpty,
                remoteDestination: connection.destination.nilIfEmpty,
                uid: connection.process.map { Int($0.userID) },
                fields: rawFields
            ),
            fields: rawFields
        )
    }
}

extension LogMessage {
    init(singBox message: SingBoxLogMessage) {
        let level: String = switch message.level.rawValue {
        case SingBoxLogLevel.panic.rawValue,
             SingBoxLogLevel.fatal.rawValue,
             SingBoxLogLevel.error.rawValue:
            "error"
        case SingBoxLogLevel.warning.rawValue:
            "warning"
        case SingBoxLogLevel.info.rawValue:
            "info"
        case SingBoxLogLevel.debug.rawValue:
            "debug"
        case SingBoxLogLevel.trace.rawValue:
            "trace"
        default:
            "info"
        }
        self.init(
            type: level,
            payload: message.message,
            level: level,
            message: message.message,
            fields: .object(["singBoxLogLevel": .number(Double(message.level.rawValue))])
        )
    }
}

struct RuleViewState: Identifiable, Equatable {
    var id: String
    var index: Int?
    var type: String
    var payload: String
    var proxy: String
    var size: Int?
    var disabled: Bool?
    var hitCount: Int?
    var hitAt: String?
    var missCount: Int?
    var missAt: String?
    var hasMutableExtra: Bool
    var extraMetadata: [String: MihomoJSONValue]
    var metadata: [String: MihomoJSONValue]
    let additionalExtraText: String?
    let additionalMetadataText: String?

    init(
        id: String,
        index: Int? = nil,
        type: String,
        payload: String,
        proxy: String,
        size: Int? = nil,
        disabled: Bool? = nil,
        hitCount: Int? = nil,
        hitAt: String? = nil,
        missCount: Int? = nil,
        missAt: String? = nil,
        hasMutableExtra: Bool = false,
        extraMetadata: [String: MihomoJSONValue] = [:],
        metadata: [String: MihomoJSONValue] = [:]
    ) {
        self.id = id
        self.index = index
        self.type = type
        self.payload = payload
        self.proxy = proxy
        self.size = size
        self.disabled = disabled
        self.hitCount = hitCount
        self.hitAt = hitAt
        self.missCount = missCount
        self.missAt = missAt
        self.hasMutableExtra = hasMutableExtra
        self.extraMetadata = extraMetadata
        self.metadata = metadata
        let knownKeys: Set<String> = ["disabled", "hitCount", "hitAt", "missCount", "missAt"]
        self.additionalExtraText = Self.jsonText(
            extraMetadata.filter { !knownKeys.contains($0.key) }
        )
        self.additionalMetadataText = Self.jsonText(metadata)
    }

    var hitRate: Double? {
        guard let hitCount, let missCount else { return nil }
        let total = hitCount + missCount
        guard total > 0 else { return nil }
        return Double(hitCount) / Double(total)
    }

    private static func jsonText(_ values: [String: MihomoJSONValue]) -> String? {
        guard !values.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(values),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        return text
    }
}

struct ProxyProviderViewState: Identifiable, Equatable, Sendable {
    var id: String { "\(kind.rawValue):\(name)" }
    var kind: ProviderKind = .proxy
    var name: String
    var type: String
    var behavior: String?
    var format: String?
    var vehicleType: String?
    var updatedAt: String?
    var updatable: Bool = false
    var testURL: String? = nil
    var healthCheck: MihomoJSONValue?
    var subscriptionInfo: MihomoJSONValue? = nil
    var itemCount: Int
    let healthCheckText: String?
    let subscriptionInfoText: String?

    init(
        kind: ProviderKind = .proxy,
        name: String,
        type: String,
        behavior: String? = nil,
        format: String? = nil,
        vehicleType: String? = nil,
        updatedAt: String? = nil,
        updatable: Bool = false,
        testURL: String? = nil,
        healthCheck: MihomoJSONValue? = nil,
        subscriptionInfo: MihomoJSONValue? = nil,
        itemCount: Int
    ) {
        self.kind = kind
        self.name = name
        self.type = type
        self.behavior = behavior
        self.format = format
        self.vehicleType = vehicleType
        self.updatedAt = updatedAt
        self.updatable = updatable
        self.testURL = testURL
        self.healthCheck = healthCheck
        self.subscriptionInfo = subscriptionInfo
        self.itemCount = itemCount
        self.healthCheckText = Self.jsonText(healthCheck)
        self.subscriptionInfoText = Self.jsonText(subscriptionInfo)
    }

    var proxyCount: Int {
        itemCount
    }

    var supportsHealthCheck: Bool {
        kind == .proxy && healthCheck != nil
    }

    private static func jsonText(_ value: MihomoJSONValue?) -> String? {
        guard let value else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        return text
    }
}

struct ProviderUpdateAllProgress: Equatable, Sendable {
    struct Target: Identifiable, Equatable, Sendable {
        var id: String
        var name: String
        var kind: ProviderKind

        init(provider: ProxyProviderViewState) {
            id = provider.id
            name = provider.name
            kind = provider.kind
        }
    }

    struct Failure: Identifiable, Equatable, Sendable {
        var id: String { target.id }
        var target: Target
        var message: String
    }

    var current: Target?
    var completed: Int
    var total: Int
    var succeeded: Int
    var failed: Int
    var failures: [Failure]
    var isRunning: Bool

    init(providers: [ProxyProviderViewState]) {
        current = nil
        completed = 0
        total = providers.count
        succeeded = 0
        failed = 0
        failures = []
        isRunning = !providers.isEmpty
    }

    mutating func begin(_ provider: ProxyProviderViewState) {
        current = Target(provider: provider)
    }

    mutating func completeCurrentSuccessfully() {
        guard current != nil else { return }
        completed += 1
        succeeded += 1
        current = nil
    }

    mutating func failCurrent(with message: String) {
        guard let current else { return }
        completed += 1
        failed += 1
        failures.append(Failure(target: current, message: message))
        self.current = nil
    }

    mutating func finish() {
        current = nil
        isRunning = false
    }
}
