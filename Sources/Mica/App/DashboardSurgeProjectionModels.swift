import Foundation
import MicaCore

extension DashboardSnapshot {
    init(
        surge snapshot: SurgeControlSnapshot,
        language: AppLanguage = MicaStrings.appLanguage
    ) {
        let groups = snapshot.policyGroups.map { group in
            ProxyGroupViewState(
                id: group.name,
                type: group.type ?? "Surge",
                selected: group.selected ?? "-",
                options: group.policies,
                hidden: false,
                delays: group.latency ?? [:]
            )
        }

        let requestIDs = Self.surgeRequestDisplayIDs(for: snapshot.activeRequests)
        let connections = Self.surgeRequestConnections(
            for: snapshot.activeRequests,
            displayIDs: requestIDs,
            ruleKey: "traffic.surge_active_request",
            metadataType: "surge-http-api",
            language: language
        )

        let ruleIDs = Self.surgeRuleDisplayIDs(for: snapshot.rules)
        let rules = zip(snapshot.rules, ruleIDs).map { rule, projectedID in
            RuleViewState(
                id: projectedID,
                type: rule.type ?? "RULE",
                payload: rule.payload ?? "",
                proxy: rule.policy ?? MicaStrings.localized("overview.config_not_reported", language: language),
                size: rule.size
            )
        }

        self.init(
            versionLabel: "Surge HTTP API",
            mode: Self.displayMode(snapshot.outboundMode),
            traffic: TrafficSnapshot(
                upload: snapshot.traffic.upload,
                download: snapshot.traffic.download
            ),
            groups: groups,
            connections: connections,
            rules: rules,
            providers: []
        )
    }

    static func surgeRequestDisplayIDs(for requests: [SurgeActiveRequest]) -> [String] {
        visibleRequestIDs(prefix: "surge-request", requests: requests)
    }

    static func surgeRequestDisplayID(for request: SurgeActiveRequest) -> String {
        visibleRequestIDs(prefix: "surge-request", requests: [request]).first ?? "surge-request-unavailable"
    }

    static func surgeRecentRequestConnections(
        for requests: [SurgeActiveRequest],
        language: AppLanguage = MicaStrings.appLanguage
    ) -> [ConnectionSnapshot] {
        let requestIDs = visibleRequestIDs(prefix: "surge-recent-request", requests: requests)

        return surgeRequestConnections(
            for: requests,
            displayIDs: requestIDs,
            ruleKey: "traffic.surge_recent_request",
            metadataType: "surge-http-api-recent",
            language: language
        )
    }

    static func surgeEventLogEntries(
        for events: [SurgeEvent]
    ) -> [ControllerLogEntry] {
        var occurrences: [String: Int] = [:]

        return events.enumerated().map { index, event in
            let rawID = event.id.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "unreported-\(index + 1)"
            let occurrence = occurrences[rawID, default: 0]
            occurrences[rawID] = occurrence + 1
            let suffix = occurrence == 0 ? "" : "#\(occurrence + 1)"
            return ControllerLogEntry(
                id: "surge-event:\(rawID)\(suffix)",
                receivedAt: surgeEventDate(event.date) ?? Date(),
                message: LogMessage(
                    type: event.type?.nilIfEmpty ?? "info",
                    payload: event.message ?? "",
                    time: event.date,
                    level: event.type,
                    message: event.message
                )
            )
        }
    }

    private static func surgeRequestConnections(
        for requests: [SurgeActiveRequest],
        displayIDs: [String],
        ruleKey: String,
        metadataType: String,
        language: AppLanguage
    ) -> [ConnectionSnapshot] {
        zip(requests, displayIDs).map { request, projectedID in
            let chains = [request.policy?.nilIfEmpty, request.originalPolicy?.nilIfEmpty]
                .compactMap { $0 }
                .reduce(into: [String]()) { values, value in
                    if !values.contains(value) {
                        values.append(value)
                    }
                }
            return ConnectionSnapshot(
                id: projectedID,
                upload: request.upload,
                download: request.download,
                uploadSpeed: request.uploadSpeed,
                downloadSpeed: request.downloadSpeed,
                start: request.start,
                chains: chains,
                rule: request.ruleType?.nilIfEmpty
                    ?? MicaStrings.localizedKey(ruleKey, language: language),
                rulePayload: request.rulePayload?.nilIfEmpty ?? request.rule,
                metadata: ConnectionMetadataSnapshot(
                    host: request.url,
                    network: request.method,
                    type: metadataType,
                    sourceIP: request.sourceAddress,
                    destinationIP: request.destinationAddress,
                    sourcePort: request.sourcePort,
                    destinationPort: request.destinationPort,
                    process: request.process,
                    processPath: request.processPath,
                    inboundIP: request.localAddress,
                    inboundName: request.interfaceName,
                    specialProxy: request.policy,
                    specialRules: request.status,
                    remoteDestination: request.url,
                    connectionLogs: request.notes,
                    uid: request.uid
                ),
                fields: request.additionalFields
            )
        }
    }

    private static func surgeRuleDisplayIDs(for rules: [SurgeRule]) -> [String] {
        stableDerivedIDs(
            prefix: "surge-rule",
            sources: rules.map { Self.surgeRuleStableSource(for: $0) }
        )
    }

    private static func surgeRuleStableSource(for rule: SurgeRule) -> String {
        let values: [String] = [
            rule.type,
            rule.payload,
            rule.policy,
            rule.size.map(String.init),
        ].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        return values.isEmpty ? "unidentified-surge-rule" : values.joined(separator: "|")
    }

    private static func visibleRequestIDs(prefix: String, requests: [SurgeActiveRequest]) -> [String] {
        var occurrences: [String: Int] = [:]

        return requests.enumerated().map { index, request in
            let rawID = request.id.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let base = rawID ?? "\(prefix)-unreported-\(index + 1)"
            let count = (occurrences[base] ?? 0) + 1
            occurrences[base] = count

            return count == 1 ? base : "\(base)#\(count)"
        }
    }

    private static func stableDerivedIDs(prefix: String, sources: [String]) -> [String] {
        var occurrences: [String: Int] = [:]

        return sources.map { source in
            let hash = stableIDHash(source)
            let count = (occurrences[hash] ?? 0) + 1
            occurrences[hash] = count

            return count == 1 ? "\(prefix)-\(hash)" : "\(prefix)-\(hash)-\(count)"
        }
    }

    private static func stableIDHash(_ value: String) -> String {
        let hash = value.utf8.reduce(UInt32(2_166_136_261)) { partial, byte in
            (partial ^ UInt32(byte)) &* 16_777_619
        }
        return String(hash, radix: 16)
    }

    private static func surgeEventDate(_ value: String?) -> Date? {
        guard let value = value?.nilIfEmpty else { return nil }
        if let numeric = Double(value) {
            let seconds = numeric > 10_000_000_000 ? numeric / 1_000 : numeric
            return Date(timeIntervalSince1970: seconds)
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
