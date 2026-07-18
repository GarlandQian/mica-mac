import MicaCore
import SwiftUI

/// Pure presentation projections for the Activity and Rules & Sources data
/// surfaces. They intentionally filter in source order and keep selection
/// identity independent from a temporary search result.
enum WorkbenchDataSurfaceState: Equatable {
    case unavailable
    case empty
    case filteredEmpty
    case content

    static func resolve(isUnavailable: Bool, sourceCount: Int, visibleCount: Int) -> Self {
        if sourceCount > 0 {
            return visibleCount == 0 ? .filteredEmpty : .content
        }
        return isUnavailable ? .unavailable : .empty
    }
}

enum ConnectionWorkbenchPresentation {
    static func filtered(_ connections: [ConnectionSnapshot], matching query: String) -> [ConnectionSnapshot] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return connections }

        return connections.filter { connection in
            searchableValues(for: connection).contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Applies user-initiated column sorting to a projection copy. The caller's
    /// source collection (`appModel.dashboard.connections`) is never mutated:
    /// this returns a reordered copy and leaves the input array untouched.
    static func ordered(
        _ connections: [ConnectionSnapshot],
        using comparators: [KeyPathComparator<ConnectionSnapshot>]
    ) -> [ConnectionSnapshot] {
        guard !comparators.isEmpty else { return connections }
        return connections.sorted(using: comparators)
    }

    static func reconciledSelection(_ selectedID: String?, in connections: [ConnectionSnapshot]) -> String? {
        guard let selectedID else { return nil }
        return connections.contains { $0.id == selectedID } ? selectedID : nil
    }

    static func ownerGroups(_ connections: [ConnectionSnapshot]) -> [WorkbenchConnectionOwnerGroup] {
        var groups: [WorkbenchConnectionOwnerGroup] = []
        var indexByOwner: [ConnectionOwnerIdentity: Int] = [:]

        for connection in connections {
            let owner = ConnectionOwnerIdentity(connection: connection)
            if let index = indexByOwner[owner] {
                groups[index].append(connection)
            } else {
                indexByOwner[owner] = groups.count
                groups.append(WorkbenchConnectionOwnerGroup(owner: owner, connections: [connection]))
            }
        }

        return groups
    }

    /// Default sort order (largest total traffic first). This is a temporary
    /// view-state seed for user-adjustable column sorting; it never touches the
    /// controller source collection.
    static let defaultSortOrder: [KeyPathComparator<ConnectionSnapshot>] = [
        KeyPathComparator(\ConnectionSnapshot.sortableStart, order: .reverse)
    ]

    private static func searchableValues(for connection: ConnectionSnapshot) -> [String] {
        [
            connection.id,
            connection.metadata?.host,
            connection.metadata?.process,
            connection.metadata?.processPath,
            connection.metadata?.network,
            connection.metadata?.type,
            connection.metadata?.sourceIP,
            connection.metadata?.sourcePort,
            connection.metadata?.destinationIP,
            connection.metadata?.destinationPort,
            connection.metadata?.inboundIP,
            connection.metadata?.inboundPort,
            connection.metadata?.inboundName,
            connection.metadata?.dnsMode,
            connection.metadata?.sniffHost,
            connection.metadata?.specialProxy,
            connection.metadata?.specialRules,
            connection.metadata?.remoteDestination,
            connection.metadata?.connectionLogs?.joined(separator: " "),
            connection.metadata?.uid.map(String.init),
            connection.rule,
            connection.rulePayload,
            connection.start,
            connection.upload.map(String.init),
            connection.download.map(String.init),
            connection.uploadSpeed.map(String.init),
            connection.downloadSpeed.map(String.init),
            connection.additionalFieldsText,
            connection.metadata?.additionalFieldsText,
        ].compactMap { $0 }
            + (connection.chains ?? [])
            + (connection.providerChains ?? [])
    }
}

enum ConnectionOwnerIdentity: Hashable {
    case inner
    case process(String)
    case source(String)
    case unreported

    init(connection: ConnectionSnapshot) {
        if connection.metadata?.type?.caseInsensitiveCompare("inner") == .orderedSame {
            self = .inner
        } else if let process = connection.metadata?.process?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !process.isEmpty {
            self = .process(process)
        } else if let source = connection.metadata?.sourceIP?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !source.isEmpty {
            self = .source(source)
        } else {
            self = .unreported
        }
    }

    var stableID: String {
        switch self {
        case .inner: "inner"
        case .process(let value): "process:\(value)"
        case .source(let value): "source:\(value)"
        case .unreported: "unreported"
        }
    }
}

struct WorkbenchConnectionOwnerGroup: Identifiable, Equatable {
    var owner: ConnectionOwnerIdentity
    var connections: [ConnectionSnapshot]

    var id: String { owner.stableID }
    var connectionCount: Int { connections.count }
    var upload: Int { Self.total(connections.compactMap(\.upload)) }
    var download: Int { Self.total(connections.compactMap(\.download)) }
    var uploadSpeed: Int { Self.total(connections.compactMap(\.uploadSpeed)) }
    var downloadSpeed: Int { Self.total(connections.compactMap(\.downloadSpeed)) }

    var processPath: String? {
        connections.lazy.compactMap { $0.metadata?.processPath?.nilIfEmpty }.first
    }

    mutating func append(_ connection: ConnectionSnapshot) {
        connections.append(connection)
    }

    private static func total(_ values: [Int]) -> Int {
        values.reduce(0) { partial, value in
            let value = max(value, 0)
            return partial > Int.max - value ? Int.max : partial + value
        }
    }
}

struct WorkbenchRuleRow: Identifiable, Equatable {
    let id: String
    let rule: RuleViewState
}

enum RulesWorkbenchPresentation {
    static func rows(from rules: [RuleViewState]) -> [WorkbenchRuleRow] {
        var occurrenceByRuleID: [String: Int] = [:]

        return rules.map { rule in
            let occurrence = occurrenceByRuleID[rule.id, default: 0]
            occurrenceByRuleID[rule.id] = occurrence + 1
            return WorkbenchRuleRow(id: "\(rule.id)#\(occurrence)", rule: rule)
        }
    }

    static func filtered(_ rows: [WorkbenchRuleRow], matching query: String) -> [WorkbenchRuleRow] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }

        return rows.filter { row in
            searchableValues(for: row.rule).contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }

    /// Applies user-initiated column sorting to a projection copy. The caller's
    /// source collection is never mutated.
    static func ordered(
        _ rows: [WorkbenchRuleRow],
        using comparators: [KeyPathComparator<WorkbenchRuleRow>]
    ) -> [WorkbenchRuleRow] {
        guard !comparators.isEmpty else { return rows }
        return rows.sorted(using: comparators)
    }

    static func reconciledSelection(_ selectedID: String?, in rows: [WorkbenchRuleRow]) -> String? {
        guard let selectedID else { return nil }
        return rows.contains { $0.id == selectedID } ? selectedID : nil
    }

    private static func searchableValues(for rule: RuleViewState) -> [String] {
        let status: String
        switch rule.disabled {
        case true:
            status = "disabled"
        case false:
            status = "enabled"
        case nil:
            status = ""
        }

        return [
            rule.payload,
            rule.type,
            rule.proxy,
            rule.id,
            rule.index.map(String.init) ?? "",
            status,
            rule.hitCount.map(String.init) ?? "",
            rule.hitAt ?? "",
            rule.missCount.map(String.init) ?? "",
            rule.missAt ?? "",
            rule.additionalExtraText ?? "",
            rule.additionalMetadataText ?? "",
        ]
    }
}

enum SourcesWorkbenchPresentation {
    static func filtered(
        _ sources: [ProxyProviderViewState],
        kind: ProviderSessionKind,
        matching query: String
    ) -> [ProxyProviderViewState] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return sources.filter { source in
            kind.matches(source.kind)
                && (query.isEmpty || [
                    source.name,
                    source.type,
                    source.vehicleType ?? "",
                    source.behavior ?? "",
                    source.format ?? "",
                    source.healthCheckText ?? "",
                    source.updatable ? "updatable" : "read-only",
                    source.updatedAt ?? "",
                    String(source.itemCount),
                ].contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    static func reconciledSelection(_ selectedID: String?, in sources: [ProxyProviderViewState]) -> String? {
        guard let selectedID else { return nil }
        return sources.contains { $0.id == selectedID } ? selectedID : nil
    }

    /// Applies user-initiated column sorting to a projection copy. The caller's
    /// source collection is never mutated.
    static func ordered(
        _ sources: [ProxyProviderViewState],
        using comparators: [KeyPathComparator<ProxyProviderViewState>]
    ) -> [ProxyProviderViewState] {
        guard !comparators.isEmpty else { return sources }
        return sources.sorted(using: comparators)
    }

    static func updateState(
        sourceID: String,
        updatingSourceID: String?,
        failures: [String: String]
    ) -> ProviderUpdatePresentationState {
        if updatingSourceID == sourceID { return .updating }
        if let failure = failures[sourceID] { return .failed(failure) }
        return .ready
    }

    /// Cached ISO8601 parsers for the controller's `updatedAt` transparency
    /// field. `ISO8601DateFormatter` is documented thread-safe once configured,
    /// and these are never mutated after creation.
    nonisolated(unsafe) private static let fractionalSecondsParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let internetDateTimeParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Classifies a controller-reported `updatedAt` value. mihomo reports the
    /// Go zero time (`0001-01-01T00:00:00Z`) for providers that have never
    /// been updated; any parsed timestamp before year 2000 is treated as
    /// "never updated". Unparseable non-empty text is surfaced verbatim so
    /// real controller data is never replaced or hidden.
    static func classifyUpdatedAt(_ raw: String?) -> SourceUpdatedAtPresentation {
        guard let raw else { return .notReported }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notReported }

        guard let date = fractionalSecondsParser.date(from: trimmed)
            ?? internetDateTimeParser.date(from: trimmed) else {
            return .reported(trimmed)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        if calendar.component(.year, from: date) < 2000 {
            return .neverUpdated
        }
        return .updated(date)
    }
}

/// Presentation classification for a source's controller-reported update time.
enum SourceUpdatedAtPresentation: Equatable {
    case notReported
    case neverUpdated
    case updated(Date)
    case reported(String)
}

enum ProviderUpdatePresentationState: Equatable {
    case ready
    case updating
    case failed(String)
}

enum LogsWorkbenchPresentation {
    static func emptyState(isFiltering: Bool) -> WorkbenchEmptyStateCopy {
        if isFiltering {
            return WorkbenchEmptyStateCopy(
                titleKey: "dashboard.no_matching_logs",
                messageKey: "traffic.empty_filtered"
            )
        }

        return WorkbenchEmptyStateCopy(
            titleKey: "dashboard.no_logs_yet",
            messageKey: "dashboard.no_logs_yet_message"
        )
    }

    static func visible(
        _ entries: [ControllerLogEntry],
        level: LogSessionLevel,
        matching query: String
    ) -> [ControllerLogEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            level.matches(entry.message.type)
                && (query.isEmpty
                    || entry.message.type.localizedCaseInsensitiveContains(query)
                    || entry.message.payload.localizedCaseInsensitiveContains(query)
                    || entry.message.time?.localizedCaseInsensitiveContains(query) == true
                    || entry.structuredFieldsText?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    static func clearedEntries() -> [ControllerLogEntry] { [] }
}

struct WorkbenchEmptyStateCopy: Equatable {
    let titleKey: String
    let messageKey: String
}

struct WorkbenchInspectorValueRow: View {
    let titleKey: String
    let value: String?
    var monospaced = false

    @Environment(\.micaFontMultiplier) private var fontMultiplier

    init(titleKey: String, value: String?, monospaced: Bool = false) {
        self.titleKey = titleKey
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            MicaText(titleKey)
                .font(.system(size: 10.5 * fontMultiplier, weight: .semibold))
                .foregroundStyle(.secondary)
            if let value {
                Text(value)
                    .font(.system(size: 12 * fontMultiplier, design: monospaced ? .monospaced : .default))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                // Unknown controller value: de-emphasized localized
                // not-reported wording instead of full-weight body text.
                MicaText("overview.config_not_reported")
                    .font(.system(size: 11 * fontMultiplier))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Sortable derived accessors

/// Derived, comparable projections used only for user-initiated column sorting.
/// They read optional controller fields into stable, comparable values so that
/// `KeyPathComparator` can order a projection copy without ever mutating the
/// controller source collection.
extension ConnectionSnapshot {
    var sortableHost: String {
        metadata?.host?.nilIfEmpty
            ?? metadata?.sniffHost?.nilIfEmpty
            ?? metadata?.destinationIP?.nilIfEmpty
            ?? ""
    }

    var sortableUpload: Int { max(upload ?? 0, 0) }
    var sortableDownload: Int { max(download ?? 0, 0) }
    var sortableStart: String { start ?? "" }

    var additionalFieldsText: String? {
        Self.jsonText(additionalFields)
    }

    fileprivate static func jsonText(_ values: [String: MihomoJSONValue]) -> String? {
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

extension ConnectionMetadataSnapshot {
    var additionalFieldsText: String? {
        ConnectionSnapshot.jsonText(additionalFields)
    }
}

extension WorkbenchRuleRow {
    var sortablePayload: String { rule.payload }
    var sortableType: String { rule.type }
    var sortableProxy: String { rule.proxy }
    var sortableSize: Int { rule.size ?? -1 }
    var sortableIndex: Int { rule.index ?? -1 }
    var sortableStatus: Int { rule.disabled == true ? 1 : 0 }
    var sortableHitCount: Int { rule.hitCount ?? -1 }
    var sortableMissCount: Int { rule.missCount ?? -1 }
}

extension ProxyProviderViewState {
    var sortableName: String { name }
    var sortableKind: String { kind.rawValue }
    var sortableType: String { type }
    var sortableItemCount: Int { itemCount }
    var sortableUpdatedAt: String { updatedAt ?? "" }
}
