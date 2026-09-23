import Foundation
import MicaCore

extension WorkbenchDataInspectorProjection {
    static func connectionIdentity(
        _ row: WorkbenchConnectionRow
    ) -> [WorkbenchDataInspectorValue] {
        let metadata = row.connection.metadata
        return [
            value("connection.id", "dashboard.col_id", row.connection.id, monospaced: true),
            value("connection.host", "traffic.connection_host", metadata?.host, monospaced: true),
            value("connection.process", "traffic.connection_process", metadata?.process),
            value("connection.process-path", "traffic.connection_process_path", metadata?.processPath, monospaced: true),
            value("connection.network", "traffic.connection_network", metadata?.network, monospaced: true),
            value("connection.type", "traffic.connection_type", metadata?.type, monospaced: true),
            value(
                "connection.source-address",
                "traffic.connection_source",
                WorkbenchDataFormat.address(metadata?.sourceIP, port: metadata?.sourcePort),
                monospaced: true
            ),
            value(
                "connection.destination-address",
                "traffic.connection_destination",
                WorkbenchDataFormat.address(metadata?.destinationIP, port: metadata?.destinationPort),
                monospaced: true
            ),
            value("connection.inbound-name", "traffic.inbound_name", metadata?.inboundName),
            value(
                "connection.inbound-address",
                "traffic.inbound_address",
                WorkbenchDataFormat.address(metadata?.inboundIP, port: metadata?.inboundPort),
                monospaced: true
            ),
            value("connection.uid", "traffic.connection_uid", metadata?.uid.map(String.init), monospaced: true),
        ]
    }

    static func connectionRouting(
        _ row: WorkbenchConnectionRow
    ) -> [WorkbenchDataInspectorValue] {
        let connection = row.connection
        let metadata = connection.metadata
        return [
            value("connection.rule", "dashboard.col_rule", connection.rule),
            value("connection.rule-payload", "dashboard.col_payload", connection.rulePayload, monospaced: true),
            value("connection.chains", "dashboard.col_chain", WorkbenchDataFormat.chain(connection.chains)),
            value("connection.provider-chains", "traffic.provider_chain", WorkbenchDataFormat.chain(connection.providerChains)),
            value("connection.dns-mode", "traffic.dns_mode", metadata?.dnsMode),
            value("connection.sniff-host", "traffic.sniff_host", metadata?.sniffHost),
            value("connection.remote-destination", "traffic.remote_destination", metadata?.remoteDestination, monospaced: true),
            value("connection.special-proxy", "traffic.special_proxy", metadata?.specialProxy),
            value("connection.special-rules", "traffic.special_rules", metadata?.specialRules, monospaced: true),
        ]
    }

    static func connectionTransfer(
        _ row: WorkbenchConnectionRow,
        language: AppLanguage
    ) -> [WorkbenchDataInspectorValue] {
        let connection = row.connection
        var values = [
            value("connection.started-at", "traffic.start_time", WorkbenchDataFormat.reportedTimestamp(connection.start), monospaced: true),
        ]
        if let closedAt = row.closedAt {
            values.append(
                value(
                    "connection.closed-at",
                    "traffic.log_received_time",
                    WorkbenchDataFormat.receivedDateTime(closedAt, language: language),
                    monospaced: true
                )
            )
        }
        values.append(contentsOf: [
            value("connection.upload", "dashboard.col_upload", WorkbenchDataFormat.bytes(connection.upload), monospaced: true),
            value("connection.upload-speed", "traffic.upload_speed", WorkbenchDataFormat.rate(connection.uploadSpeed, language: language), monospaced: true),
            value("connection.download", "dashboard.col_download", WorkbenchDataFormat.bytes(connection.download), monospaced: true),
            value("connection.download-speed", "traffic.download_speed", WorkbenchDataFormat.rate(connection.downloadSpeed, language: language), monospaced: true),
        ])
        return values
    }

    static func connectionMetadata(
        _ row: WorkbenchConnectionRow
    ) -> [WorkbenchDataInspectorValue] {
        [
            value(
                "connection.logs",
                "traffic.connection_logs",
                row.connection.metadata?.connectionLogs?.joined(separator: "\n"),
                monospaced: true
            ),
        ]
    }

}
// MARK: - Connection projection

struct WorkbenchConnectionAdditionalField: Identifiable, Equatable {
    var id: String { key }

    let key: String
    let value: MihomoJSONValue

    static func fields(
        in values: [String: MihomoJSONValue]
    ) -> [WorkbenchConnectionAdditionalField] {
        values
            .sorted { $0.key < $1.key }
            .map {
                WorkbenchConnectionAdditionalField(
                    key: $0.key,
                    value: $0.value
                )
            }
    }
}

struct WorkbenchConnectionRow: Identifiable, Equatable {
    let id: String
    let identityFamily: String
    let sourceIndex: Int
    let connection: ConnectionSnapshot
    let closedAt: Date?
    let host: String
    let destination: String
    let process: String
    let network: String
    let route: String
    let rule: String
    let payload: String
    let startedAt: String?
    let identityDetailText: String
    let processNetworkText: String
    let rulePayloadText: String
    let ruleRouteText: String
    let stackedDetailText: String
    let timestampText: String
    let searchText: String
    let metadataAdditionalFields: [WorkbenchConnectionAdditionalField]
    let connectionAdditionalFields: [WorkbenchConnectionAdditionalField]
    let uploadText: String?
    let uploadRateText: String?
    let downloadText: String?
    let downloadRateText: String?
    let uploadDisplayText: String
    let uploadRateDisplayText: String
    let downloadDisplayText: String
    let downloadRateDisplayText: String
    let uploadSummaryText: String
    let downloadSummaryText: String

    var upload: Int { connection.upload ?? -1 }
    var download: Int { connection.download ?? -1 }
}

enum WorkbenchConnectionProjection {
    static func rows(
        from connections: [ConnectionSnapshot],
        language: AppLanguage = .english
    ) -> [WorkbenchConnectionRow] {
        rows(
            from: connections.map { ProjectionItem(connection: $0, closedAt: nil) },
            language: language
        )
    }

    static func rows(
        from records: [ClosedConnectionRecord],
        language: AppLanguage = .english
    ) -> [WorkbenchConnectionRow] {
        rows(
            from: records.map {
                ProjectionItem(connection: $0.snapshot, closedAt: $0.closedAt)
            },
            language: language
        )
    }

    static func rows(
        activeConnections: [ConnectionSnapshot],
        closedConnections: [ClosedConnectionRecord],
        scope: ConnectionSessionTab,
        language: AppLanguage = .english
    ) -> [WorkbenchConnectionRow] {
        switch scope {
        case .active:
            rows(from: activeConnections, language: language)
        case .closed:
            rows(from: closedConnections, language: language)
        }
    }

    private struct ProjectionItem {
        let connection: ConnectionSnapshot
        let closedAt: Date?
    }

    private static func rows(
        from items: [ProjectionItem],
        language: AppLanguage
    ) -> [WorkbenchConnectionRow] {
        let metricsFormatter = WorkbenchDataFormat.MetricsFormatter(language: language)
        let unavailableText = MicaStrings.localizedKey(
            "overview.config_not_reported",
            language: language
        )
        var identities = WorkbenchStableRowIdentityBuilder(
            reportedIDs: items.map { $0.connection.id }
        )
        return items.enumerated().map { index, item in
            let connection = item.connection
            let metadata = connection.metadata
            let host = metadata?.host?.dataNonEmpty
                ?? metadata?.sniffHost?.dataNonEmpty
                ?? metadata?.destinationIP?.dataNonEmpty
                ?? connection.id.dataNonEmpty
                ?? "-"
            let destination = WorkbenchDataFormat.address(
                metadata?.destinationIP,
                port: metadata?.destinationPort
            ) ?? metadata?.remoteDestination?.dataNonEmpty ?? "-"
            let process = metadata?.process?.dataNonEmpty
                ?? metadata?.processPath?.dataNonEmpty
                ?? "-"
            let network = [metadata?.network?.dataNonEmpty, metadata?.type?.dataNonEmpty]
                .compactMap { $0 }
                .joined(separator: " / ")
                .dataNonEmpty ?? "-"

            let route = WorkbenchDataFormat.chain(connection.chains) ?? "-"
            let rule = connection.rule?.dataNonEmpty ?? "-"
            let payload = connection.rulePayload?.dataNonEmpty ?? "-"
            let startedAt = WorkbenchDataFormat.reportedTimestamp(connection.start)
            let uploadText = metricsFormatter.bytes(connection.upload)
            let uploadRateText = metricsFormatter.rate(connection.uploadSpeed)
            let downloadText = metricsFormatter.bytes(connection.download)
            let downloadRateText = metricsFormatter.rate(connection.downloadSpeed)
            let reportedUpload = uploadText ?? unavailableText
            let reportedUploadRate = uploadRateText ?? unavailableText
            let reportedDownload = downloadText ?? unavailableText
            let reportedDownloadRate = downloadRateText ?? unavailableText
            let metadataFields = WorkbenchDataFormat.json(metadata?.additionalFields ?? [:]) ?? ""
            let connectionFields = WorkbenchDataFormat.json(connection.additionalFields) ?? ""
            let metadataAdditionalFields = WorkbenchConnectionAdditionalField.fields(
                in: metadata?.additionalFields ?? [:]
            )
            let connectionAdditionalFields = WorkbenchConnectionAdditionalField.fields(
                in: connection.additionalFields
            )
            let searchText = [
                connection.id, host, destination, process, network, route, rule,
                payload, startedAt ?? "", item.closedAt?.ISO8601Format() ?? "",
                metadata?.processPath ?? "",
                metadata?.sourceIP ?? "", metadata?.sourcePort ?? "",
                metadata?.inboundName ?? "", metadata?.inboundIP ?? "",
                metadata?.inboundPort ?? "", metadata?.remoteDestination ?? "",
                metadata?.specialProxy ?? "", metadata?.specialRules ?? "",
                WorkbenchDataFormat.chain(connection.providerChains) ?? "",
                metadataFields, connectionFields,
            ].joined(separator: "\n")
            let identity = identities.make(
                reportedID: connection.id,
                fallbackComponents: [
                    host, destination, process, network, startedAt ?? "", rule,
                    payload, route, metadata?.sourceIP ?? "", metadata?.sourcePort ?? "",
                    metadata?.inboundName ?? "", metadata?.remoteDestination ?? "",
                    metadataFields, connectionFields,
                ]
            )
            let timestampText = item.closedAt.map {
                WorkbenchDataFormat.receivedDateTime($0, language: language)
            } ?? startedAt ?? unavailableText

            return WorkbenchConnectionRow(
                id: identity.id,
                identityFamily: identity.family,
                sourceIndex: index,
                connection: connection,
                closedAt: item.closedAt,
                host: host,
                destination: destination,
                process: process,
                network: network,
                route: route,
                rule: rule,
                payload: payload,
                startedAt: startedAt,
                identityDetailText: "\(destination) · \(network)",
                processNetworkText: "\(process) · \(network)",
                rulePayloadText: "\(rule) · \(payload)",
                ruleRouteText: "\(rule) · \(route)",
                stackedDetailText: "\(destination) · \(rule) · \(route)",
                timestampText: timestampText,
                searchText: searchText,
                metadataAdditionalFields: metadataAdditionalFields,
                connectionAdditionalFields: connectionAdditionalFields,
                uploadText: uploadText,
                uploadRateText: uploadRateText,
                downloadText: downloadText,
                downloadRateText: downloadRateText,
                uploadDisplayText: reportedUpload,
                uploadRateDisplayText: reportedUploadRate,
                downloadDisplayText: reportedDownload,
                downloadRateDisplayText: reportedDownloadRate,
                uploadSummaryText: "↑ \(reportedUpload)",
                downloadSummaryText: "↓ \(reportedDownload)"
            )
        }
    }

    static func updatingMetrics(
        in row: WorkbenchConnectionRow,
        from connection: ConnectionSnapshot,
        language: AppLanguage,
        forceFormatting: Bool = false
    ) -> WorkbenchConnectionRow {
        updatingMetrics(
            in: row,
            from: connection,
            formatter: WorkbenchDataFormat.MetricsFormatter(language: language),
            forceFormatting: forceFormatting
        )
    }

    static func updatingMetrics(
        in row: WorkbenchConnectionRow,
        from connection: ConnectionSnapshot,
        formatter: WorkbenchDataFormat.MetricsFormatter,
        forceFormatting: Bool = false
    ) -> WorkbenchConnectionRow {
        if !forceFormatting,
           row.connection.upload == connection.upload,
           row.connection.download == connection.download,
           row.connection.uploadSpeed == connection.uploadSpeed,
           row.connection.downloadSpeed == connection.downloadSpeed {
            return row
        }

        let uploadText = formatter.bytes(connection.upload)
        let uploadRateText = formatter.rate(connection.uploadSpeed)
        let downloadText = formatter.bytes(connection.download)
        let downloadRateText = formatter.rate(connection.downloadSpeed)
        let unavailableText = MicaStrings.localizedKey(
            "overview.config_not_reported",
            language: formatter.language
        )
        let reportedUpload = uploadText ?? unavailableText
        let reportedDownload = downloadText ?? unavailableText
        let timestampText = row.closedAt.map {
            WorkbenchDataFormat.receivedDateTime(
                $0,
                language: formatter.language
            )
        } ?? row.startedAt ?? unavailableText

        return WorkbenchConnectionRow(
            id: row.id,
            identityFamily: row.identityFamily,
            sourceIndex: row.sourceIndex,
            connection: connection,
            closedAt: row.closedAt,
            host: row.host,
            destination: row.destination,
            process: row.process,
            network: row.network,
            route: row.route,
            rule: row.rule,
            payload: row.payload,
            startedAt: row.startedAt,
            identityDetailText: row.identityDetailText,
            processNetworkText: row.processNetworkText,
            rulePayloadText: row.rulePayloadText,
            ruleRouteText: row.ruleRouteText,
            stackedDetailText: row.stackedDetailText,
            timestampText: timestampText,
            searchText: row.searchText,
            metadataAdditionalFields: row.metadataAdditionalFields,
            connectionAdditionalFields: row.connectionAdditionalFields,
            uploadText: uploadText,
            uploadRateText: uploadRateText,
            downloadText: downloadText,
            downloadRateText: downloadRateText,
            uploadDisplayText: reportedUpload,
            uploadRateDisplayText: uploadRateText ?? unavailableText,
            downloadDisplayText: reportedDownload,
            downloadRateDisplayText: downloadRateText ?? unavailableText,
            uploadSummaryText: "↑ \(reportedUpload)",
            downloadSummaryText: "↓ \(reportedDownload)"
        )
    }

    static func accessibilitySummary(
        for row: WorkbenchConnectionRow,
        localization: MicaStrings.LocalizationContext
    ) -> String {
        let timestampTitleKey = row.closedAt == nil
            ? "traffic.start_time"
            : "traffic.log_received_time"
        let uploadTitle = localization.localizedKey("dashboard.col_upload")
        let downloadTitle = localization.localizedKey("dashboard.col_download")
        return [
            WorkbenchAccessibilitySummary.field(
                "traffic.connection_host", value: row.host, localization: localization
            ),
            WorkbenchAccessibilitySummary.field(
                "traffic.connection_destination", value: row.destination, localization: localization
            ),
            WorkbenchAccessibilitySummary.field(
                "traffic.connection_process", value: row.process, localization: localization
            ),
            WorkbenchAccessibilitySummary.field(
                "traffic.connection_network", value: row.network, localization: localization
            ),
            WorkbenchAccessibilitySummary.field(
                "dashboard.col_rule", value: row.rule, localization: localization
            ),
            WorkbenchAccessibilitySummary.field(
                "dashboard.col_payload", value: row.payload, localization: localization
            ),
            WorkbenchAccessibilitySummary.field(
                "dashboard.col_chain", value: row.route, localization: localization
            ),
            WorkbenchAccessibilitySummary.field(
                timestampTitleKey, value: row.timestampText, localization: localization
            ),
            "\(uploadTitle): \(row.uploadDisplayText), \(row.uploadRateDisplayText)",
            "\(downloadTitle): \(row.downloadDisplayText), \(row.downloadRateDisplayText)",
        ].joined(separator: ", ")
    }

    static func visibleRows(
        from rows: [WorkbenchConnectionRow],
        query: String,
        sortOrder: [KeyPathComparator<WorkbenchConnectionRow>]
    ) -> [WorkbenchConnectionRow] {
        let query = query.dataNonEmpty
        let filtered = rows.filter { row in
            guard let query else { return true }
            return WorkbenchDataSearch.contains(query, in: row.searchText)
        }
        return sortOrder.isEmpty ? filtered : filtered.sorted(using: sortOrder)
    }

    static func closeGroups(
        from rows: [WorkbenchConnectionRow]
    ) -> [WorkbenchConnectionCloseGroup] {
        var groups: [WorkbenchConnectionCloseGroup] = []
        var indexByIdentity: [WorkbenchConnectionOwnerIdentity: Int] = [:]

        for row in rows where row.connection.id.dataNonEmpty != nil {
            let identity = WorkbenchConnectionOwnerIdentity(connection: row.connection)
            if let index = indexByIdentity[identity] {
                groups[index].connections.append(row.connection)
            } else {
                indexByIdentity[identity] = groups.count
                groups.append(
                    WorkbenchConnectionCloseGroup(
                        identity: identity,
                        connections: [row.connection]
                    )
                )
            }
        }

        return groups
    }
}

struct WorkbenchConnectionDecisionPathSegment: Identifiable, Equatable {
    enum Kind: Equatable {
        case provider
        case policy

        var titleKey: String {
            switch self {
            case .provider: "traffic.provider_chain"
            case .policy: "dashboard.col_chain"
            }
        }

        var systemImage: String {
            switch self {
            case .provider: "shippingbox"
            case .policy: "point.3.connected.trianglepath.dotted"
            }
        }
    }

    let id: String
    let kind: Kind
    let value: String
}

struct WorkbenchConnectionDecisionPathProjection: Equatable {
    let origin: String
    let inbound: String
    let rule: String
    let payload: String
    let destination: String
    let segments: [WorkbenchConnectionDecisionPathSegment]

    init(row: WorkbenchConnectionRow) {
        let metadata = row.connection.metadata
        let sourceAddress = WorkbenchDataFormat.address(
            metadata?.sourceIP,
            port: metadata?.sourcePort
        )
        let inboundAddress = WorkbenchDataFormat.address(
            metadata?.inboundIP,
            port: metadata?.inboundPort
        )
        origin = WorkbenchDataFormat.joined([
            metadata?.process?.dataNonEmpty,
            sourceAddress,
        ]) ?? metadata?.type?.dataNonEmpty ?? ""
        inbound = WorkbenchDataFormat.joined([
            metadata?.inboundName?.dataNonEmpty,
            inboundAddress,
        ]) ?? ""
        rule = row.connection.rule?.dataNonEmpty ?? row.rule
        payload = row.connection.rulePayload?.dataNonEmpty ?? row.payload
        let destinationAddress = WorkbenchDataFormat.address(
            metadata?.destinationIP,
            port: metadata?.destinationPort
        ) ?? metadata?.remoteDestination?.dataNonEmpty
        destination = WorkbenchDataFormat.joined([
            metadata?.host?.dataNonEmpty ?? metadata?.sniffHost?.dataNonEmpty,
            destinationAddress,
        ]) ?? row.destination

        var nextSegments: [WorkbenchConnectionDecisionPathSegment] = []
        for (index, value) in (row.connection.providerChains ?? []).enumerated() {
            guard value.dataNonEmpty != nil else { continue }
            nextSegments.append(
                WorkbenchConnectionDecisionPathSegment(
                    id: "provider-\(index)-\(value)",
                    kind: .provider,
                    value: value
                )
            )
        }
        for (index, value) in (row.connection.chains ?? []).enumerated() {
            guard value.dataNonEmpty != nil else { continue }
            nextSegments.append(
                WorkbenchConnectionDecisionPathSegment(
                    id: "policy-\(index)-\(value)",
                    kind: .policy,
                    value: value
                )
            )
        }
        segments = nextSegments
    }
}

struct WorkbenchConnectionRuleNavigationTarget: Equatable {
    let sourceIndex: Int
    let reportedRuleID: String
    let type: String
    let payload: String
}

struct WorkbenchConnectionNavigationDirectory: Equatable {
    private struct RuleKey: Hashable {
        let type: String
        let payload: String
    }

    private var uniqueRules: [RuleKey: WorkbenchConnectionRuleNavigationTarget] = [:]
    private var ruleIdentities: [WorkbenchConnectionRuleNavigationTarget] = []
    private var visiblePolicyTargets: [String: ProxyGroupOccurrence] = [:]
    private(set) var visiblePolicyGroups: [ProxyGroupOccurrence] = []

    init(
        rules: [RuleViewState] = [],
        groups: [ProxyGroupOccurrence] = []
    ) {
        replaceRules(rules)
        replaceGroups(groups)
    }

    /// Hit counters and rule state do not change an exact navigation target.
    /// Compare its complete identity before allocating another lookup table.
    @discardableResult
    mutating func replaceRules(_ rules: [RuleViewState]) -> Bool {
        guard rules.count != ruleIdentities.count || !zip(ruleIdentities, rules).allSatisfy({ target, rule in
            target.reportedRuleID == rule.id && target.type == rule.type && target.payload == rule.payload
        }) else { return false }

        uniqueRules.removeAll(keepingCapacity: true)
        ruleIdentities.removeAll(keepingCapacity: true)
        ruleIdentities.reserveCapacity(rules.count)
        var ambiguousRuleKeys: Set<RuleKey> = []
        for (sourceIndex, rule) in rules.enumerated() {
            let target = WorkbenchConnectionRuleNavigationTarget(
                sourceIndex: sourceIndex,
                reportedRuleID: rule.id,
                type: rule.type,
                payload: rule.payload
            )
            ruleIdentities.append(target)
            guard rule.type.dataNonEmpty != nil,
                  rule.payload.dataNonEmpty != nil else {
                continue
            }
            let key = RuleKey(type: rule.type, payload: rule.payload)
            if uniqueRules[key] != nil {
                uniqueRules.removeValue(forKey: key)
                ambiguousRuleKeys.insert(key)
            } else if !ambiguousRuleKeys.contains(key) {
                uniqueRules[key] = target
            }
        }
        return true
    }

    @discardableResult
    mutating func replaceGroups(_ groups: [ProxyGroupOccurrence]) -> Bool {
        guard visiblePolicyGroups != groups else { return false }
        visiblePolicyGroups = groups
        visiblePolicyTargets.removeAll(keepingCapacity: true)
        var ambiguousPolicyTargets: Set<String> = []
        for occurrence in groups {
            let target = occurrence.group.id
            guard target.dataNonEmpty != nil,
                  !Self.isTerminalTarget(target) else {
                continue
            }
            if visiblePolicyTargets[target] != nil {
                visiblePolicyTargets.removeValue(forKey: target)
                ambiguousPolicyTargets.insert(target)
            } else if !ambiguousPolicyTargets.contains(target) {
                visiblePolicyTargets[target] = occurrence
            }
        }
        return true
    }

    func ruleTarget(
        type: String,
        payload: String
    ) -> WorkbenchConnectionRuleNavigationTarget? {
        guard type.dataNonEmpty != nil, payload.dataNonEmpty != nil else {
            return nil
        }
        return uniqueRules[RuleKey(type: type, payload: payload)]
    }

    func policyTarget(named target: String) -> ProxyGroupOccurrence? {
        guard target.dataNonEmpty != nil, !Self.isTerminalTarget(target) else {
            return nil
        }
        return visiblePolicyTargets[target]
    }

    private static func isTerminalTarget(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.caseInsensitiveCompare("DIRECT") == .orderedSame
            || normalized.caseInsensitiveCompare("REJECT") == .orderedSame
    }
}

enum WorkbenchConnectionOwnerIdentity: Hashable {
    case inner
    case process(String)
    case source(String)
    case unreported

    init(connection: ConnectionSnapshot) {
        if connection.metadata?.type?.caseInsensitiveCompare("inner") == .orderedSame {
            self = .inner
        } else if let process = connection.metadata?.process?.dataNonEmpty {
            self = .process(process)
        } else if let source = connection.metadata?.sourceIP?.dataNonEmpty {
            self = .source(source)
        } else {
            self = .unreported
        }
    }

    var id: String {
        switch self {
        case .inner: "inner"
        case .process(let value): "process:\(value)"
        case .source(let value): "source:\(value)"
        case .unreported: "unreported"
        }
    }
}

struct WorkbenchConnectionCloseGroup: Identifiable, Equatable {
    let identity: WorkbenchConnectionOwnerIdentity
    var connections: [ConnectionSnapshot]

    var id: String { identity.id }
}

// MARK: - Connections

struct WorkbenchConnectionCloseIntent: Equatable {
    enum Target: Equatable {
        case connection(String)
        case group(String)
        case all
    }

    let routerID: RouterProfile.ID
    let generation: UUID
    let target: Target

    func isCurrent(
        routerID: RouterProfile.ID?,
        generation: UUID
    ) -> Bool {
        self.routerID == routerID && self.generation == generation
    }

    func reconciled(
        routerID: RouterProfile.ID?,
        generation: UUID,
        connectionIDs: Set<String>,
        groupIDs: Set<String>
    ) -> Self? {
        guard isCurrent(routerID: routerID, generation: generation) else {
            return nil
        }

        switch target {
        case .connection(let id):
            return connectionIDs.contains(id) ? self : nil
        case .group(let id):
            return groupIDs.contains(id) ? self : nil
        case .all:
            return connectionIDs.isEmpty ? nil : self
        }
    }
}
