import Foundation
import MicaCore

extension WorkbenchDataInspectorProjection {
    static func sourceConfiguration(
        _ row: WorkbenchSourceRow
    ) -> [WorkbenchDataInspectorValue] {
        let source = row.source
        return [
            value("source.id", "dashboard.col_id", source.id, monospaced: true),
            value("source.kind", "traffic.provider_kind", row.kindText),
            value("source.type", "dashboard.col_provider_type", source.type, monospaced: true),
            value("source.vehicle", "dashboard.col_vehicle", source.vehicleType, monospaced: true),
            value("source.behavior", "traffic.provider_behavior", source.behavior, monospaced: true),
            value("source.format", "traffic.provider_format", source.format, monospaced: true),
            value("source.test-url", "routing.test_url", source.testURL, monospaced: true),
            value("source.item-count", "traffic.provider_items", String(source.itemCount), monospaced: true),
        ]
    }

    static func sourceStatus(
        _ row: WorkbenchSourceRow
    ) -> [WorkbenchDataInspectorValue] {
        let source = row.source
        return [
            value("source.updated-at", "traffic.updated_at", WorkbenchDataFormat.reportedTimestamp(source.updatedAt), monospaced: true),
            value("source.health-check", "traffic.provider_health_check", source.healthCheckText, monospaced: true),
            value("source.subscription-info", "traffic.provider_subscription_info", source.subscriptionInfoText, monospaced: true),
        ]
    }

}

// MARK: - Source projection

struct WorkbenchSourceRow: Identifiable, Equatable {
    let id: String
    let identityFamily: String
    let sourceIndex: Int
    let source: ProxyProviderViewState
    let kindText: String
    let updatedText: String
    let typeText: String
    let configurationDetailText: String?
    let compactConfigurationText: String
    let itemCountText: String
    let compactStatusText: String
    let stackedSummaryText: String
    let updatableText: String
    let healthCheckAvailabilityText: String
    let statusAccessibilityText: String
    let searchText: String

    var name: String { source.name }
    var type: String { source.type }
    var itemCount: Int { source.itemCount }
}

enum WorkbenchSourceProjection {
    static func rows(
        from sources: [ProxyProviderViewState],
        language: AppLanguage
    ) -> [WorkbenchSourceRow] {
        var identities = WorkbenchStableRowIdentityBuilder(
            reportedIDs: sources.map(\.id)
        )
        return sources.enumerated().map { index, source in
            let kindText = MicaStrings.localizedKey(
                source.kind == .proxy
                    ? "traffic.provider_kind_proxy"
                    : "traffic.provider_kind_rule",
                language: language
            )
            let updatedText = WorkbenchDataFormat.providerUpdatedAt(
                source.updatedAt,
                language: language
            ) ?? MicaStrings.localizedKey("overview.config_not_reported", language: language)
            let typeText = WorkbenchDataFormat.reported(
                source.type,
                language: language
            )
            let configurationDetailText = WorkbenchDataFormat.joined([
                source.vehicleType,
                source.format,
                source.behavior,
            ])
            let compactConfigurationText = WorkbenchDataFormat.joined([
                typeText,
                WorkbenchDataFormat.reported(
                    source.vehicleType,
                    language: language
                ),
                WorkbenchDataFormat.reported(
                    source.format,
                    language: language
                ),
            ]) ?? typeText
            let itemCountText = String(source.itemCount)
            let updatableText = MicaStrings.localizedKey(
                source.updatable
                    ? "traffic.provider_updatable_yes"
                    : "traffic.provider_updatable_no",
                language: language
            )
            let healthCheckAvailabilityText = MicaStrings.localizedKey(
                source.supportsHealthCheck
                    ? "traffic.provider_health_check_available"
                    : "traffic.provider_health_check_unavailable",
                language: language
            )
            let identity = identities.make(
                reportedID: source.id,
                fallbackComponents: [
                    source.kind.rawValue, source.name, source.type,
                    source.vehicleType ?? "", source.behavior ?? "",
                ]
            )
            return WorkbenchSourceRow(
                id: identity.id,
                identityFamily: identity.family,
                sourceIndex: index,
                source: source,
                kindText: kindText,
                updatedText: updatedText,
                typeText: typeText,
                configurationDetailText: configurationDetailText,
                compactConfigurationText: compactConfigurationText,
                itemCountText: itemCountText,
                compactStatusText: WorkbenchDataFormat.joined([
                    itemCountText,
                    updatedText,
                ]) ?? updatedText,
                stackedSummaryText: WorkbenchDataFormat.joined([
                    typeText,
                    itemCountText,
                    updatedText,
                ]) ?? updatedText,
                updatableText: updatableText,
                healthCheckAvailabilityText: healthCheckAvailabilityText,
                statusAccessibilityText: "\(updatableText), \(healthCheckAvailabilityText)",
                searchText: [
                    source.id, source.name, kindText, source.type, source.behavior ?? "",
                    source.format ?? "", source.vehicleType ?? "", source.updatedAt ?? "",
                    updatedText, source.testURL ?? "", source.healthCheckText ?? "",
                    source.subscriptionInfoText ?? "", String(source.itemCount),
                ].joined(separator: "\n")
            )
        }
    }

    static func visibleRows(
        from rows: [WorkbenchSourceRow],
        kind: ProviderSessionKind,
        query: String,
        sortOrder: [KeyPathComparator<WorkbenchSourceRow>]
    ) -> [WorkbenchSourceRow] {
        let query = query.dataNonEmpty
        let filtered = rows.filter { row in
            guard kind.matches(row.source.kind) else { return false }
            guard let query else { return true }
            return WorkbenchDataSearch.contains(query, in: row.searchText)
        }
        return sortOrder.isEmpty ? filtered : filtered.sorted(using: sortOrder)
    }

    static func updateTargets(
        from sources: [ProxyProviderViewState]
    ) -> [ProxyProviderViewState] {
        sources.filter(\.updatable)
    }
}

struct WorkbenchSourceFocusProjection: Equatable {
    let name: String
    let configuration: String
    let itemCount: String
    let updatedAt: String
    let updatableStatus: String
    let healthAvailability: String
    let health: String?

    init(row: WorkbenchSourceRow) {
        name = row.source.name
        configuration = WorkbenchDataFormat.joined([
            row.kindText,
            row.typeText,
        ]) ?? row.typeText
        itemCount = row.itemCountText
        updatedAt = row.updatedText
        updatableStatus = row.updatableText
        healthAvailability = row.healthCheckAvailabilityText
        health = row.source.healthCheckText?.dataNonEmpty
    }
}

enum WorkbenchSourceProjectionUpdate {
    case source
    case visibleOnly
}

struct WorkbenchSourceProjectionCache {
    private(set) var allRows: [WorkbenchSourceRow] = []
    private(set) var visibleRows: [WorkbenchSourceRow] = []
    private(set) var updatableSourceCount = 0
    private(set) var sourceProjectionCount = 0
    private(set) var staticRowProjectionCount = 0
    private(set) var filterProjectionCount = 0
    private(set) var sortProjectionCount = 0

    private var kind: ProviderSessionKind?
    private var query: String?
    private var sortOrder: [KeyPathComparator<WorkbenchSourceRow>] = []
    private var filteredSourceIndices: [Int] = []
    private var rowIndexByID: [String: Int] = [:]

    @discardableResult
    mutating func project(
        update: WorkbenchSourceProjectionUpdate,
        sources: [ProxyProviderViewState],
        kind: ProviderSessionKind,
        query: String,
        sortOrder: [KeyPathComparator<WorkbenchSourceRow>],
        language: AppLanguage,
        isActive: Bool = true
    ) -> Bool {
        guard isActive else { return false }

        let sourceChanged: Bool
        switch update {
        case .source:
            allRows = WorkbenchSourceProjection.rows(from: sources, language: language)
            updatableSourceCount = sources.lazy.filter(\.updatable).count
            rowIndexByID = Dictionary(
                uniqueKeysWithValues: allRows.enumerated().map {
                    ($0.element.id, $0.offset)
                }
            )
            sourceProjectionCount += 1
            staticRowProjectionCount += allRows.count
            sourceChanged = true
        case .visibleOnly:
            sourceChanged = false
        }

        let normalizedQuery = query.dataNonEmpty
        let filterChanged = self.kind != kind || self.query != normalizedQuery
        let sortChanged = self.sortOrder != sortOrder

        if sourceChanged || filterChanged {
            filteredSourceIndices = allRows.indices.filter { index in
                let row = allRows[index]
                guard kind.matches(row.source.kind) else { return false }
                guard let normalizedQuery else { return true }
                return WorkbenchDataSearch.contains(
                    normalizedQuery,
                    in: row.searchText
                )
            }
            filterProjectionCount += 1
        }

        if sourceChanged || filterChanged || sortChanged {
            visibleRows = filteredSourceIndices.map { allRows[$0] }
            if !sortOrder.isEmpty {
                visibleRows.sort(using: sortOrder)
                sortProjectionCount += 1
            }
        }

        self.kind = kind
        self.query = normalizedQuery
        self.sortOrder = sortOrder
        return sourceChanged || filterChanged || sortChanged
    }

    func row(id: String?) -> WorkbenchSourceRow? {
        guard let id, let index = rowIndexByID[id], allRows.indices.contains(index) else {
            return nil
        }
        return allRows[index]
    }

    mutating func reset() {
        self = WorkbenchSourceProjectionCache()
    }
}
