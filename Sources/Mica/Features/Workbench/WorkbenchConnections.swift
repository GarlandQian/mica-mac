import Foundation
import MicaCore
import SwiftUI

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

struct WorkbenchConnectionPulseOwner: Identifiable, Equatable {
    let identity: WorkbenchConnectionOwnerIdentity
    let count: Int

    var id: String { identity.id }
}

private struct WorkbenchConnectionReportedMetric: Equatable {
    private(set) var sum: Int64 = 0
    private(set) var reportedCount = 0

    var value: Int64? {
        reportedCount > 0 ? sum : nil
    }

    mutating func add(_ value: Int?) {
        guard let value, value >= 0 else { return }
        sum = Self.addingClamped(sum, Int64(value))
        reportedCount += 1
    }

    mutating func remove(_ value: Int?) {
        guard let value, value >= 0 else { return }
        sum = Self.addingClamped(sum, -Int64(value))
        reportedCount = max(0, reportedCount - 1)
        if reportedCount == 0 {
            sum = 0
        }
    }

    mutating func replace(_ previous: Int?, with current: Int?) {
        remove(previous)
        add(current)
    }

    private static func addingClamped(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard overflow else { return sum }
        return rhs >= 0 ? .max : .min
    }
}

private struct WorkbenchConnectionMetricValues: Equatable {
    let upload: Int?
    let download: Int?
    let uploadSpeed: Int?
    let downloadSpeed: Int?

    init(connection: ConnectionSnapshot) {
        upload = connection.upload
        download = connection.download
        uploadSpeed = connection.uploadSpeed
        downloadSpeed = connection.downloadSpeed
    }
}

private struct WorkbenchConnectionMetricDelta: Equatable {
    let sourceIndex: Int
    let previous: WorkbenchConnectionMetricValues
    let current: WorkbenchConnectionMetricValues
}

private struct WorkbenchConnectionMetricsReplacement {
    var changedIndices: [Int] = []
    var metricDeltas: [WorkbenchConnectionMetricDelta] = []
}

struct WorkbenchConnectionPulseProjection: Equatable {
    let scope: ConnectionSessionTab
    let visibleCount: Int
    let totalCount: Int
    let isFiltered: Bool
    let owners: [WorkbenchConnectionPulseOwner]
    let remainingOwnerCount: Int

    private var uploadMetric: WorkbenchConnectionReportedMetric
    private var downloadMetric: WorkbenchConnectionReportedMetric
    private var uploadRateMetric: WorkbenchConnectionReportedMetric
    private var downloadRateMetric: WorkbenchConnectionReportedMetric

    var uploadBytes: Int64? { uploadMetric.value }
    var downloadBytes: Int64? { downloadMetric.value }
    var uploadRate: Int64? { scope == .active ? uploadRateMetric.value : nil }
    var downloadRate: Int64? { scope == .active ? downloadRateMetric.value : nil }

    var totalBytes: Int64? {
        guard uploadBytes != nil || downloadBytes != nil else { return nil }
        let upload = uploadBytes ?? 0
        let download = downloadBytes ?? 0
        let (sum, overflow) = upload.addingReportingOverflow(download)
        return overflow ? .max : sum
    }

    static func empty(scope: ConnectionSessionTab = .active) -> Self {
        WorkbenchConnectionPulseProjection(
            scope: scope,
            visibleCount: 0,
            totalCount: 0,
            isFiltered: false,
            owners: [],
            remainingOwnerCount: 0,
            uploadMetric: WorkbenchConnectionReportedMetric(),
            downloadMetric: WorkbenchConnectionReportedMetric(),
            uploadRateMetric: WorkbenchConnectionReportedMetric(),
            downloadRateMetric: WorkbenchConnectionReportedMetric()
        )
    }

    fileprivate static func project(
        rows: [WorkbenchConnectionRow],
        sourceIndices: [Int],
        totalCount: Int,
        scope: ConnectionSessionTab,
        isFiltered: Bool
    ) -> Self {
        var uploadMetric = WorkbenchConnectionReportedMetric()
        var downloadMetric = WorkbenchConnectionReportedMetric()
        var uploadRateMetric = WorkbenchConnectionReportedMetric()
        var downloadRateMetric = WorkbenchConnectionReportedMetric()
        var ownerCounts: [WorkbenchConnectionOwnerIdentity: Int] = [:]
        var ownerFirstSeen: [WorkbenchConnectionOwnerIdentity: Int] = [:]

        for sourceIndex in sourceIndices where rows.indices.contains(sourceIndex) {
            let row = rows[sourceIndex]
            uploadMetric.add(row.connection.upload)
            downloadMetric.add(row.connection.download)
            if scope == .active {
                uploadRateMetric.add(row.connection.uploadSpeed)
                downloadRateMetric.add(row.connection.downloadSpeed)
            }

            let owner = WorkbenchConnectionOwnerIdentity(connection: row.connection)
            if ownerFirstSeen[owner] == nil {
                ownerFirstSeen[owner] = ownerFirstSeen.count
            }
            ownerCounts[owner, default: 0] += 1
        }

        let rankedOwners = ownerCounts.map { identity, count in
            (
                owner: WorkbenchConnectionPulseOwner(identity: identity, count: count),
                firstSeen: ownerFirstSeen[identity] ?? .max
            )
        }
        .sorted { lhs, rhs in
            if lhs.owner.count != rhs.owner.count {
                return lhs.owner.count > rhs.owner.count
            }
            return lhs.firstSeen < rhs.firstSeen
        }

        let owners = rankedOwners.prefix(3).map(\.owner)
        let remainingOwnerCount = rankedOwners.dropFirst(3).reduce(0) {
            $0 + $1.owner.count
        }

        return WorkbenchConnectionPulseProjection(
            scope: scope,
            visibleCount: sourceIndices.count,
            totalCount: totalCount,
            isFiltered: isFiltered,
            owners: owners,
            remainingOwnerCount: remainingOwnerCount,
            uploadMetric: uploadMetric,
            downloadMetric: downloadMetric,
            uploadRateMetric: uploadRateMetric,
            downloadRateMetric: downloadRateMetric
        )
    }

    fileprivate mutating func applyMetricDeltas(
        _ deltas: [WorkbenchConnectionMetricDelta]
    ) {
        guard scope == .active else { return }
        for delta in deltas {
            uploadMetric.replace(delta.previous.upload, with: delta.current.upload)
            downloadMetric.replace(delta.previous.download, with: delta.current.download)
            uploadRateMetric.replace(
                delta.previous.uploadSpeed,
                with: delta.current.uploadSpeed
            )
            downloadRateMetric.replace(
                delta.previous.downloadSpeed,
                with: delta.current.downloadSpeed
            )
        }
    }
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
            let reportedUpload = WorkbenchDataFormat.reported(
                uploadText,
                language: language
            )
            let reportedDownload = WorkbenchDataFormat.reported(
                downloadText,
                language: language
            )
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
                identityDetailText: WorkbenchDataFormat.joined([
                    destination, network,
                ]) ?? destination,
                processNetworkText: WorkbenchDataFormat.joined([
                    process, network,
                ]) ?? process,
                rulePayloadText: WorkbenchDataFormat.joined([
                    rule, payload,
                ]) ?? rule,
                ruleRouteText: WorkbenchDataFormat.joined([
                    rule, route,
                ]) ?? rule,
                stackedDetailText: WorkbenchDataFormat.joined([
                    destination, rule, route,
                ]) ?? destination,
                timestampText: item.closedAt.map {
                    WorkbenchDataFormat.receivedDateTime($0, language: language)
                } ?? WorkbenchDataFormat.reported(startedAt, language: language),
                searchText: searchText,
                metadataAdditionalFields: metadataAdditionalFields,
                connectionAdditionalFields: connectionAdditionalFields,
                uploadText: uploadText,
                uploadRateText: uploadRateText,
                downloadText: downloadText,
                downloadRateText: downloadRateText,
                uploadDisplayText: reportedUpload,
                uploadRateDisplayText: WorkbenchDataFormat.reported(
                    uploadRateText,
                    language: language
                ),
                downloadDisplayText: reportedDownload,
                downloadRateDisplayText: WorkbenchDataFormat.reported(
                    downloadRateText,
                    language: language
                ),
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
            timestampText: row.closedAt.map {
                WorkbenchDataFormat.receivedDateTime(
                    $0,
                    language: formatter.language
                )
            } ?? WorkbenchDataFormat.reported(
                row.startedAt,
                language: formatter.language
            ),
            searchText: row.searchText,
            metadataAdditionalFields: row.metadataAdditionalFields,
            connectionAdditionalFields: row.connectionAdditionalFields,
            uploadText: uploadText,
            uploadRateText: uploadRateText,
            downloadText: downloadText,
            downloadRateText: downloadRateText,
            uploadDisplayText: WorkbenchDataFormat.reported(
                uploadText,
                language: formatter.language
            ),
            uploadRateDisplayText: WorkbenchDataFormat.reported(
                uploadRateText,
                language: formatter.language
            ),
            downloadDisplayText: WorkbenchDataFormat.reported(
                downloadText,
                language: formatter.language
            ),
            downloadRateDisplayText: WorkbenchDataFormat.reported(
                downloadRateText,
                language: formatter.language
            ),
            uploadSummaryText: "↑ \(WorkbenchDataFormat.reported(uploadText, language: formatter.language))",
            downloadSummaryText: "↓ \(WorkbenchDataFormat.reported(downloadText, language: formatter.language))"
        )
    }

    static func visibleRows(
        from rows: [WorkbenchConnectionRow],
        query: String,
        sortOrder: [KeyPathComparator<WorkbenchConnectionRow>]
    ) -> [WorkbenchConnectionRow] {
        let query = query.dataNonEmpty
        let filtered = rows.filter { row in
            guard let query else { return true }
            return row.searchText.localizedCaseInsensitiveContains(query)
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

struct WorkbenchConnectionNavigationDirectory: Equatable {
    private struct RuleKey: Hashable {
        let type: String
        let payload: String
    }

    private var uniqueRules: [RuleKey: RuleViewState] = [:]
    private var visiblePolicyTargets: [String: ProxyGroupOccurrence] = [:]
    private(set) var visiblePolicyGroups: [ProxyGroupOccurrence] = []

    init(
        rules: [RuleViewState] = [],
        groups: [ProxyGroupOccurrence] = []
    ) {
        visiblePolicyGroups = groups
        var ambiguousRuleKeys: Set<RuleKey> = []
        for rule in rules {
            guard rule.type.dataNonEmpty != nil,
                  rule.payload.dataNonEmpty != nil else {
                continue
            }
            let key = RuleKey(type: rule.type, payload: rule.payload)
            if uniqueRules[key] != nil {
                uniqueRules.removeValue(forKey: key)
                ambiguousRuleKeys.insert(key)
            } else if !ambiguousRuleKeys.contains(key) {
                uniqueRules[key] = rule
            }
        }

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
    }

    func ruleTarget(type: String, payload: String) -> RuleViewState? {
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

struct WorkbenchConnectionProjectionCache {
    private(set) var allRows: [WorkbenchConnectionRow] = []
    private(set) var visibleRows: [WorkbenchConnectionRow] = []
    private(set) var pulseProjection = WorkbenchConnectionPulseProjection.empty()
    private(set) var closeGroups: [WorkbenchConnectionCloseGroup] = []
    private(set) var connectionIDs: Set<String> = []
    private(set) var groupIDs: Set<String> = []
    private(set) var staticProjectionCount = 0
    private(set) var metricsProjectionCount = 0
    private(set) var staticRowProjectionCount = 0
    private(set) var metricsRowProjectionCount = 0
    private(set) var metricsCandidateProjectionCount = 0
    private(set) var filterProjectionCount = 0
    private(set) var sortProjectionCount = 0
    private(set) var pulseProjectionCount = 0
    private(set) var pulseMetricUpdateCount = 0
    private(set) var pulseMetricCandidateCount = 0

    private var scope: ConnectionSessionTab?
    private var structureRevision: UInt64?
    private var metricsRevision: UInt64?
    private var closedRevision: UInt64?
    private var language: AppLanguage?
    private var query: String?
    private var sortOrder: [KeyPathComparator<WorkbenchConnectionRow>] = []
    private var filteredSourceIndices: [Int] = []
    private var rowIndexByID: [String: Int] = [:]
    private var visibleIndexBySourceIndex: [Int: Int] = [:]
    private(set) var hasDeferredMetricSort = false

    @discardableResult
    mutating func project(
        activeConnections: [ConnectionSnapshot],
        closedConnections: [ClosedConnectionRecord],
        scope: ConnectionSessionTab,
        structureRevision: UInt64,
        metricsRevision: UInt64,
        closedRevision: UInt64,
        query: String,
        sortOrder: [KeyPathComparator<WorkbenchConnectionRow>],
        language: AppLanguage,
        change: ConnectionsCatalogChange? = nil,
        deferMetricSorting: Bool = false,
        isActive: Bool = true
    ) -> Bool {
        guard isActive else { return false }

        let scopeChanged = self.scope != scope
        let languageChanged = self.language != language
        let normalizedQuery = query.dataNonEmpty
        let filterChanged = self.query != normalizedQuery
        var sourceChanged = false
        var changedMetricIndices: [Int] = []
        var metricDeltas: [WorkbenchConnectionMetricDelta] = []

        switch scope {
        case .active:
            if scopeChanged || self.structureRevision != structureRevision {
                replaceSource(
                    WorkbenchConnectionProjection.rows(
                        from: activeConnections,
                        language: language
                    )
                )
                staticProjectionCount += 1
                staticRowProjectionCount += allRows.count
                sourceChanged = true
            } else if self.metricsRevision != metricsRevision || languageChanged {
                if activeConnections.count == allRows.count {
                    let keyedIndices = languageChanged
                        ? nil
                        : keyedMetricIndices(
                            in: activeConnections,
                            nextRevision: metricsRevision,
                            change: change
                        )
                    if keyedIndices != nil || sourceIDsMatch(activeConnections) {
                        let replacement = replaceMetrics(
                            with: activeConnections,
                            at: keyedIndices,
                            language: language,
                            forceFormatting: languageChanged
                        )
                        changedMetricIndices = replacement.changedIndices
                        metricDeltas = replacement.metricDeltas
                    } else {
                        replaceSource(
                            WorkbenchConnectionProjection.rows(
                                from: activeConnections,
                                language: language
                            )
                        )
                        staticProjectionCount += 1
                        staticRowProjectionCount += allRows.count
                        sourceChanged = true
                    }
                } else {
                    replaceSource(
                        WorkbenchConnectionProjection.rows(
                            from: activeConnections,
                            language: language
                        )
                    )
                    staticProjectionCount += 1
                    staticRowProjectionCount += allRows.count
                    sourceChanged = true
                }
            }
            self.structureRevision = structureRevision
            self.metricsRevision = metricsRevision
            self.closedRevision = nil

        case .closed:
            if scopeChanged || self.closedRevision != closedRevision {
                replaceSource(
                    WorkbenchConnectionProjection.rows(
                        from: closedConnections,
                        language: language
                    )
                )
                staticProjectionCount += 1
                staticRowProjectionCount += allRows.count
                sourceChanged = true
            } else if languageChanged {
                let snapshots = closedConnections.map(\.snapshot)
                if snapshots.count == allRows.count, sourceIDsMatch(snapshots) {
                    let replacement = replaceMetrics(
                        with: snapshots,
                        at: nil,
                        language: language,
                        forceFormatting: true
                    )
                    changedMetricIndices = replacement.changedIndices
                    metricDeltas = replacement.metricDeltas
                } else {
                    replaceSource(
                        WorkbenchConnectionProjection.rows(
                            from: closedConnections,
                            language: language
                        )
                    )
                    staticProjectionCount += 1
                    staticRowProjectionCount += allRows.count
                    sourceChanged = true
                }
            }
            self.structureRevision = nil
            self.metricsRevision = nil
            self.closedRevision = closedRevision
        }

        self.scope = scope
        self.language = language
        let visibleChanged = updateVisibleRows(
            query: query,
            sortOrder: sortOrder,
            sourceChanged: sourceChanged,
            changedMetricIndices: changedMetricIndices,
            deferMetricSorting: deferMetricSorting
        )

        if sourceChanged || filterChanged {
            pulseProjection = WorkbenchConnectionPulseProjection.project(
                rows: allRows,
                sourceIndices: filteredSourceIndices,
                totalCount: allRows.count,
                scope: scope,
                isFiltered: normalizedQuery != nil
            )
            pulseProjectionCount += 1
        } else if !metricDeltas.isEmpty {
            let visibleDeltas = metricDeltas.filter {
                visibleIndexBySourceIndex[$0.sourceIndex] != nil
            }
            if !visibleDeltas.isEmpty {
                pulseProjection.applyMetricDeltas(visibleDeltas)
                pulseMetricUpdateCount += 1
                pulseMetricCandidateCount += visibleDeltas.count
            }
        }
        return visibleChanged
    }

    @discardableResult
    mutating func commitDeferredMetricSort() -> Bool {
        guard hasDeferredMetricSort else { return false }
        hasDeferredMetricSort = false
        guard isMetricSort(sortOrder) else { return false }

        visibleRows = filteredSourceIndices.map { allRows[$0] }
        visibleRows.sort(using: sortOrder)
        rebuildVisibleIndex()
        sortProjectionCount += 1
        return true
    }

    func row(id: String?) -> WorkbenchConnectionRow? {
        guard let id, let index = rowIndexByID[id], allRows.indices.contains(index) else {
            return nil
        }
        return allRows[index]
    }

    mutating func reset() {
        self = WorkbenchConnectionProjectionCache()
    }

    private mutating func replaceSource(_ rows: [WorkbenchConnectionRow]) {
        allRows = rows
        rowIndexByID = Dictionary(
            uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) }
        )
        connectionIDs = Set(rows.map(\.id))
        closeGroups = WorkbenchConnectionProjection.closeGroups(from: rows)
        groupIDs = Set(closeGroups.map(\.id))
    }

    private mutating func replaceMetrics(
        with connections: [ConnectionSnapshot],
        at sourceIndices: [Int]?,
        language: AppLanguage,
        forceFormatting: Bool
    ) -> WorkbenchConnectionMetricsReplacement {
        let formatter = WorkbenchDataFormat.MetricsFormatter(language: language)
        var nextRows = allRows
        var replacement = WorkbenchConnectionMetricsReplacement()

        func updatedRow(at index: Int) -> WorkbenchConnectionRow {
            WorkbenchConnectionProjection.updatingMetrics(
                in: allRows[index],
                from: connections[index],
                formatter: formatter,
                forceFormatting: forceFormatting
            )
        }

        if let sourceIndices {
            replacement.changedIndices.reserveCapacity(sourceIndices.count)
            replacement.metricDeltas.reserveCapacity(sourceIndices.count)
            for index in sourceIndices {
                let next = updatedRow(at: index)
                if next != allRows[index] {
                    let previousMetrics = WorkbenchConnectionMetricValues(
                        connection: allRows[index].connection
                    )
                    let currentMetrics = WorkbenchConnectionMetricValues(
                        connection: next.connection
                    )
                    nextRows[index] = next
                    replacement.changedIndices.append(index)
                    if previousMetrics != currentMetrics {
                        replacement.metricDeltas.append(
                            WorkbenchConnectionMetricDelta(
                                sourceIndex: index,
                                previous: previousMetrics,
                                current: currentMetrics
                            )
                        )
                    }
                }
            }
        } else {
            replacement.changedIndices.reserveCapacity(connections.count)
            replacement.metricDeltas.reserveCapacity(connections.count)
            for index in connections.indices {
                let next = updatedRow(at: index)
                if next != allRows[index] {
                    let previousMetrics = WorkbenchConnectionMetricValues(
                        connection: allRows[index].connection
                    )
                    let currentMetrics = WorkbenchConnectionMetricValues(
                        connection: next.connection
                    )
                    nextRows[index] = next
                    replacement.changedIndices.append(index)
                    if previousMetrics != currentMetrics {
                        replacement.metricDeltas.append(
                            WorkbenchConnectionMetricDelta(
                                sourceIndex: index,
                                previous: previousMetrics,
                                current: currentMetrics
                            )
                        )
                    }
                }
            }
        }

        allRows = nextRows
        metricsProjectionCount += 1
        metricsCandidateProjectionCount += sourceIndices?.count ?? connections.count
        metricsRowProjectionCount += replacement.changedIndices.count
        return replacement
    }

    private func keyedMetricIndices(
        in connections: [ConnectionSnapshot],
        nextRevision: UInt64,
        change: ConnectionsCatalogChange?
    ) -> [Int]? {
        guard let previousRevision = metricsRevision,
              previousRevision &+ 1 == nextRevision,
              let change,
              !change.structureChanged,
              let indices = change.changedMetricIndices else {
            return nil
        }

        var uniqueIndices: [Int] = []
        var seen: Set<Int> = []
        uniqueIndices.reserveCapacity(indices.count)
        for index in indices {
            guard connections.indices.contains(index),
                  allRows.indices.contains(index),
                  allRows[index].connection.id == connections[index].id else {
                return nil
            }
            if seen.insert(index).inserted {
                uniqueIndices.append(index)
            }
        }
        return uniqueIndices
    }

    private func sourceIDsMatch(_ connections: [ConnectionSnapshot]) -> Bool {
        connections.count == allRows.count
            && zip(allRows, connections).allSatisfy {
                $0.connection.id == $1.id
            }
    }

    private func isMetricSort(
        _ sortOrder: [KeyPathComparator<WorkbenchConnectionRow>]
    ) -> Bool {
        sortOrder.contains {
            $0.keyPath == \WorkbenchConnectionRow.upload
                || $0.keyPath == \WorkbenchConnectionRow.download
        }
    }

    private mutating func updateVisibleMetrics(at sourceIndices: [Int]) {
        for sourceIndex in sourceIndices {
            guard let visibleIndex = visibleIndexBySourceIndex[sourceIndex],
                  visibleRows.indices.contains(visibleIndex),
                  allRows.indices.contains(sourceIndex) else {
                continue
            }
            visibleRows[visibleIndex] = allRows[sourceIndex]
        }
    }

    private mutating func rebuildVisibleIndex() {
        visibleIndexBySourceIndex = Dictionary(
            uniqueKeysWithValues: visibleRows.enumerated().map {
                ($0.element.sourceIndex, $0.offset)
            }
        )
    }

    private mutating func rebuildVisibleRows(
        sortOrder: [KeyPathComparator<WorkbenchConnectionRow>]
    ) {
        visibleRows = filteredSourceIndices.map { allRows[$0] }
        if !sortOrder.isEmpty {
            visibleRows.sort(using: sortOrder)
            sortProjectionCount += 1
        }
        rebuildVisibleIndex()
    }

    private mutating func updateVisibleRows(
        query: String,
        sortOrder: [KeyPathComparator<WorkbenchConnectionRow>],
        sourceChanged: Bool,
        changedMetricIndices: [Int],
        deferMetricSorting: Bool
    ) -> Bool {
        let normalizedQuery = query.dataNonEmpty
        let filterChanged = self.query != normalizedQuery
        let sortChanged = self.sortOrder != sortOrder

        if sourceChanged || filterChanged {
            filteredSourceIndices = allRows.indices.filter { index in
                guard let normalizedQuery else { return true }
                return allRows[index].searchText.localizedCaseInsensitiveContains(normalizedQuery)
            }
            filterProjectionCount += 1
        }

        if sourceChanged || filterChanged || sortChanged {
            rebuildVisibleRows(sortOrder: sortOrder)
            hasDeferredMetricSort = false
        } else if !changedMetricIndices.isEmpty {
            updateVisibleMetrics(at: changedMetricIndices)
            if isMetricSort(sortOrder) {
                if deferMetricSorting {
                    hasDeferredMetricSort = true
                } else {
                    rebuildVisibleRows(sortOrder: sortOrder)
                    hasDeferredMetricSort = false
                }
            }
        }

        self.query = normalizedQuery
        self.sortOrder = sortOrder
        return sourceChanged || filterChanged || sortChanged || !changedMetricIndices.isEmpty
    }
}

struct WorkbenchConnectionMetricSortCadence: Equatable {
    static let maximumDeferral: TimeInterval = 0.2

    private(set) var pendingDeadline: Date?

    mutating func schedule(now: Date = Date()) {
        guard pendingDeadline == nil else { return }
        pendingDeadline = now.addingTimeInterval(Self.maximumDeferral)
    }

    mutating func consume(now: Date = Date()) -> Bool {
        guard let pendingDeadline, pendingDeadline <= now else { return false }
        self.pendingDeadline = nil
        return true
    }

    mutating func cancel() {
        pendingDeadline = nil
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
