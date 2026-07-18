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

struct DashboardSnapshot: Equatable {
    var versionLabel: String
    var mode: String
    var config: DashboardConfigSnapshot
    var traffic: TrafficSnapshot
    var groups: [ProxyGroupViewState]
    private var controllerLogBuffer: BoundedLogBuffer
    var controllerLogs: [ControllerLogEntry] {
        get { controllerLogBuffer.entries }
        set { controllerLogBuffer.replace(with: newValue) }
    }
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
        controllerLogs: [],
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
        controllerLogs: [ControllerLogEntry],
        connections: [ConnectionSnapshot],
        rules: [RuleViewState] = [],
        providers: [ProxyProviderViewState] = []
    ) {
        self.versionLabel = versionLabel
        self.mode = mode
        self.config = config
        self.traffic = traffic
        self.groups = groups
        controllerLogBuffer = BoundedLogBuffer(entries: controllerLogs)
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
            controllerLogs: [],
            connections: connections.connections
        )
    }

    mutating func replaceGroups(with proxies: ProxiesResponse) {
        let existingDelays = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.delays) })

        groups = Self.proxyGroupViewStates(from: proxies, existingDelays: existingDelays)
        refreshInsight()
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
        refreshInsight()
    }

    mutating func replaceDelay(_ delay: Int, for node: String, in groupID: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else {
            return
        }

        groups[index].delays[node] = delay
        refreshInsight()
    }

    mutating func replaceConnections(with response: ConnectionsResponse) {
        traffic = TrafficSnapshot(
            upload: response.uploadTotal ?? 0,
            download: response.downloadTotal ?? 0
        )
        connections = response.connections
        refreshInsight()
    }

    mutating func replaceSingBoxStatus(with status: SingBoxStatusSnapshot) {
        traffic = TrafficSnapshot(
            upload: Int(clamping: status.uplinkTotalBytes),
            download: Int(clamping: status.downlinkTotalBytes)
        )
        refreshInsight()
    }

    mutating func replaceSingBoxGroups(with catalog: SingBoxPolicyCatalog) {
        let orderedGroups = catalog.groups.filter { $0.tag.caseInsensitiveCompare("GLOBAL") != .orderedSame }
            + catalog.groups.filter { $0.tag.caseInsensitiveCompare("GLOBAL") == .orderedSame }

        groups = orderedGroups.map { group in
            var optionDetails: [String: ProxyNodeViewState] = [:]
            var delays: [String: Int] = [:]
            for item in group.items where optionDetails[item.tag] == nil {
                optionDetails[item.tag] = ProxyNodeViewState(singBoxNode: item)
            }
            for item in group.items where delays[item.tag] == nil {
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
        refreshInsight()
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
        refreshInsight()
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
                healthCheck: provider.healthCheck,
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
        refreshInsight()
    }

    static func displayMode(_ mode: String?) -> String {
        guard let mode, !mode.isEmpty else {
            return "unknown"
        }

        return mode.prefix(1).uppercased() + mode.dropFirst()
    }

    private static func proxyGroupViewStates(
        from response: ProxiesResponse,
        existingDelays: [String: [String: Int]] = [:]
    ) -> [ProxyGroupViewState] {
        response.policyGroups.map { proxy in
            var optionDetails: [String: ProxyNodeViewState] = [:]
            for option in proxy.all where optionDetails[option] == nil {
                guard let snapshot = response.proxies[option] else { continue }
                optionDetails[option] = ProxyNodeViewState(snapshot: snapshot)
            }

            return ProxyGroupViewState(
                id: proxy.name,
                type: proxy.type,
                selected: proxy.now ?? "-",
                options: proxy.all,
                details: ProxyNodeViewState(snapshot: proxy),
                optionDetails: optionDetails,
                hidden: proxy.hidden ?? false,
                delays: existingDelays[proxy.name] ?? [:]
            )
        }
    }

    private mutating func refreshInsight() {
        insight = InsightSummarySnapshot(snapshot: self)
    }
}

struct ControllerLogEntry: Identifiable, Equatable {
    var id: String
    var receivedAt: Date
    var message: LogMessage

    init(id: String = UUID().uuidString, receivedAt: Date = Date(), message: LogMessage) {
        self.id = id
        self.receivedAt = receivedAt
        self.message = message
    }

    var structuredFieldsText: String? {
        guard let fields = message.fields,
              let data = try? JSONEncoder().encode(fields),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        return text
    }
}

struct ProxyGroupViewState: Identifiable, Equatable {
    var id: String
    var type: String
    var selected: String
    var options: [String]
    var details: ProxyNodeViewState?
    var optionDetails: [String: ProxyNodeViewState] = [:]
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
        self.hidden = hidden
        self.selectable = selectable
        self.delays = delays
    }

    func detail(for option: String) -> ProxyNodeViewState? {
        optionDetails[option]
    }
}

struct ProxyNodeViewState: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var type: String
    var alive: Bool?
    var history: [ProxyDelayHistorySnapshot]
    var icon: String?
    var testURL: String?
    var providerName: String?
    var fixed: String?
    var interfaceName: String?
    var transportNames: [String]
    var metadata: [String: MihomoJSONValue]

    init(snapshot: ProxySnapshot) {
        name = snapshot.name
        type = snapshot.type
        alive = snapshot.alive
        history = snapshot.history
        icon = snapshot.icon?.nilIfEmpty
        testURL = snapshot.testURL?.nilIfEmpty
        providerName = snapshot.providerName?.nilIfEmpty
        fixed = snapshot.fixed?.nilIfEmpty
        interfaceName = snapshot.interfaceName?.nilIfEmpty
        transportNames = snapshot.enabledTransportNames
        metadata = snapshot.metadata
    }

    init(singBoxNode node: SingBoxPolicyNode) {
        name = node.tag
        type = node.type
        alive = nil
        if node.urlTestTimestamp != 0 || node.urlTestDelayMilliseconds != 0 {
            history = [
                ProxyDelayHistorySnapshot(
                    time: node.urlTestTimestamp == 0 ? nil : String(node.urlTestTimestamp),
                    delay: Int(node.urlTestDelayMilliseconds)
                ),
            ]
        } else {
            history = []
        }
        icon = nil
        testURL = nil
        providerName = nil
        fixed = nil
        interfaceName = nil
        transportNames = []
        metadata = [
            "urlTestTime": .string(String(node.urlTestTimestamp)),
            "urlTestDelay": .number(Double(node.urlTestDelayMilliseconds)),
        ]
    }

    init(singBoxGroup group: SingBoxPolicyGroup) {
        name = group.tag
        type = group.type
        alive = nil
        history = []
        icon = nil
        testURL = nil
        providerName = nil
        fixed = nil
        interfaceName = nil
        transportNames = []
        metadata = [
            "selected": .string(group.selected),
            "selectable": .bool(group.selectable),
            "isExpand": .bool(group.isExpandedByController),
        ]
    }

    var latestHistoryDelay: Int? {
        history.last(where: { $0.delay != nil })?.delay
    }

    var latestHistoryTime: String? {
        history.last(where: { $0.time?.nilIfEmpty != nil })?.time?.nilIfEmpty
    }

    var searchableText: String {
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
    }

    var additionalMetadataText: String? {
        let knownKeys: Set<String> = [
            "name", "type", "now", "all", "alive", "history", "icon",
            "testUrl", "tester", "provider-name", "fixed", "interface",
            "udp", "uot", "xudp", "tfo", "mptcp", "smux", "hidden",
        ]
        let additional = metadata.filter { !knownKeys.contains($0.key) }
        guard !additional.isEmpty else { return nil }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(additional),
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
        case SingBoxLogLevel.debug.rawValue,
             SingBoxLogLevel.trace.rawValue:
            "debug"
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
    }

    var hitRate: Double? {
        guard let hitCount, let missCount else { return nil }
        let total = hitCount + missCount
        guard total > 0 else { return nil }
        return Double(hitCount) / Double(total)
    }

    var additionalExtraText: String? {
        let knownKeys: Set<String> = ["disabled", "hitCount", "hitAt", "missCount", "missAt"]
        return Self.jsonText(extraMetadata.filter { !knownKeys.contains($0.key) })
    }

    var additionalMetadataText: String? {
        Self.jsonText(metadata)
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

struct ProxyProviderViewState: Identifiable, Equatable {
    var id: String { "\(kind.rawValue):\(name)" }
    var kind: ProviderKind = .proxy
    var name: String
    var type: String
    var behavior: String?
    var format: String?
    var vehicleType: String?
    var updatedAt: String?
    var updatable: Bool = false
    var healthCheck: MihomoJSONValue?
    var itemCount: Int

    var proxyCount: Int {
        itemCount
    }

    var supportsHealthCheck: Bool {
        kind == .proxy && healthCheck != nil
    }

    var healthCheckText: String? {
        guard let healthCheck,
              let data = try? JSONEncoder().encode(healthCheck),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        return text
    }
}
