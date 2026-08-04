import Foundation
import MicaCore
import Observation

enum OverviewDashboardModuleID: String, CaseIterable, Codable, Identifiable, Sendable {
    case instrumentRail
    case telemetry
    case operationalSummaries
    case routeTopology
    case networkInformation

    var id: String { rawValue }

    var legalSizes: [OverviewDashboardModuleSize] {
        switch self {
        case .instrumentRail, .telemetry, .networkInformation:
            [.standard, .full]
        case .operationalSummaries:
            [.compact, .standard, .full]
        case .routeTopology:
            [.full]
        }
    }

    var defaultSize: OverviewDashboardModuleSize {
        .full
    }
}

enum OverviewDashboardModuleSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case compact
    case standard
    case full

    var id: String { rawValue }
}

struct OverviewDashboardModuleConfiguration: Codable, Equatable, Identifiable, Sendable {
    var id: OverviewDashboardModuleID
    var size: OverviewDashboardModuleSize
    var isVisible: Bool

    init(
        id: OverviewDashboardModuleID,
        size: OverviewDashboardModuleSize? = nil,
        isVisible: Bool = true
    ) {
        self.id = id
        self.size = size ?? id.defaultSize
        self.isVisible = isVisible
    }
}

enum OverviewDashboardInstrumentMetricID: String, CaseIterable, Codable, Identifiable, Sendable {
    case upload
    case download
    case activeConnections
    case memoryUsage

    var id: String { rawValue }
}

struct OverviewDashboardInstrumentMetricConfiguration:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    var id: OverviewDashboardInstrumentMetricID
    var isVisible: Bool

    init(id: OverviewDashboardInstrumentMetricID, isVisible: Bool = true) {
        self.id = id
        self.isVisible = isVisible
    }
}

enum OverviewDashboardTimelineWindow: String, CaseIterable, Codable, Identifiable, Sendable {
    case oneMinute
    case threeMinutes
    case fiveMinutes

    var id: String { rawValue }

    var projectionWindow: OverviewTimelineWindow {
        switch self {
        case .oneMinute:
            .oneMinute
        case .threeMinutes:
            .threeMinutes
        case .fiveMinutes:
            .fiveMinutes
        }
    }
}

enum OverviewDashboardSummaryCategoryID: String, CaseIterable, Codable, Identifiable, Sendable {
    case latency
    case ruleHits
    case activeConnections

    var id: String { rawValue }
}

enum OverviewDashboardSummaryItemCount: Int, CaseIterable, Codable, Identifiable, Sendable {
    case one = 1
    case three = 3
    case five = 5

    var id: Int { rawValue }
}

struct OverviewDashboardSummaryCategoryConfiguration:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    var id: OverviewDashboardSummaryCategoryID
    var isVisible: Bool
    var itemCount: OverviewDashboardSummaryItemCount

    init(
        id: OverviewDashboardSummaryCategoryID,
        isVisible: Bool = true,
        itemCount: OverviewDashboardSummaryItemCount = .three
    ) {
        self.id = id
        self.isVisible = isVisible
        self.itemCount = itemCount
    }
}

enum OverviewDashboardNetworkGroupID: String, CaseIterable, Codable, Identifiable, Sendable {
    case controllerIdentity
    case runtimeAndFeatures
    case listenerPorts

    var id: String { rawValue }
}

struct OverviewDashboardContentPreferences: Codable, Equatable, Sendable {
    var instrumentMetrics: [OverviewDashboardInstrumentMetricConfiguration]
    var timelineWindow: OverviewDashboardTimelineWindow
    var summaryCategories: [OverviewDashboardSummaryCategoryConfiguration]
    var networkGroups: [OverviewDashboardNetworkGroupID]

    init(
        instrumentMetrics: [OverviewDashboardInstrumentMetricConfiguration] =
            OverviewDashboardInstrumentMetricID.allCases.map {
                OverviewDashboardInstrumentMetricConfiguration(id: $0)
            },
        timelineWindow: OverviewDashboardTimelineWindow = .fiveMinutes,
        summaryCategories: [OverviewDashboardSummaryCategoryConfiguration] =
            OverviewDashboardSummaryCategoryID.allCases.map {
                OverviewDashboardSummaryCategoryConfiguration(id: $0)
            },
        networkGroups: [OverviewDashboardNetworkGroupID] =
            OverviewDashboardNetworkGroupID.allCases
    ) {
        self.instrumentMetrics = instrumentMetrics
        self.timelineWindow = timelineWindow
        self.summaryCategories = summaryCategories
        self.networkGroups = networkGroups
    }

    static let repositoryDefault = OverviewDashboardContentPreferences()
}

struct OverviewDashboardLayout: Codable, Equatable, Sendable {
    var modules: [OverviewDashboardModuleConfiguration]
    var contentPreferences: OverviewDashboardContentPreferences

    init(
        modules: [OverviewDashboardModuleConfiguration],
        contentPreferences: OverviewDashboardContentPreferences = .repositoryDefault
    ) {
        self.modules = modules
        self.contentPreferences = contentPreferences
    }

    static let repositoryDefault = OverviewDashboardLayout(
        modules: [
            .init(id: .instrumentRail, size: .full, isVisible: false),
            .init(id: .telemetry, size: .full),
            .init(id: .operationalSummaries, size: .full, isVisible: false),
            .init(id: .routeTopology, size: .full),
            .init(id: .networkInformation, size: .full),
        ]
    )

    var visibleModules: [OverviewDashboardModuleConfiguration] {
        modules.filter(\.isVisible)
    }

    func configuration(
        for id: OverviewDashboardModuleID
    ) -> OverviewDashboardModuleConfiguration {
        modules.first { $0.id == id }
            ?? OverviewDashboardModuleConfiguration(id: id, isVisible: false)
    }

    func normalized() -> OverviewDashboardLayout {
        OverviewDashboardLayoutNormalizer.normalize(self)
    }
}

enum OverviewDashboardLayoutNormalizer {
    static func normalize(_ layout: OverviewDashboardLayout) -> OverviewDashboardLayout {
        var seenModules: Set<OverviewDashboardModuleID> = []
        var modules: [OverviewDashboardModuleConfiguration] = []
        modules.reserveCapacity(OverviewDashboardModuleID.allCases.count)

        for configuration in layout.modules where seenModules.insert(configuration.id).inserted {
            var repaired = configuration
            if !configuration.id.legalSizes.contains(configuration.size) {
                repaired.size = configuration.id.defaultSize
            }
            modules.append(repaired)
        }

        for id in OverviewDashboardModuleID.allCases where !seenModules.contains(id) {
            modules.append(OverviewDashboardModuleConfiguration(id: id, isVisible: false))
        }

        guard modules.contains(where: \.isVisible) else {
            return .repositoryDefault
        }

        let summariesAreVisible = modules.contains {
            $0.id == .operationalSummaries && $0.isVisible
        }
        let content = normalize(
            layout.contentPreferences,
            requireVisibleSummaryCategory: summariesAreVisible
        )
        return OverviewDashboardLayout(
            modules: modules,
            contentPreferences: content
        )
    }

    private static func normalize(
        _ content: OverviewDashboardContentPreferences,
        requireVisibleSummaryCategory: Bool
    ) -> OverviewDashboardContentPreferences {
        var seenMetrics: Set<OverviewDashboardInstrumentMetricID> = []
        var metrics = content.instrumentMetrics.filter {
            seenMetrics.insert($0.id).inserted
        }
        for id in OverviewDashboardInstrumentMetricID.allCases where !seenMetrics.contains(id) {
            metrics.append(
                OverviewDashboardInstrumentMetricConfiguration(
                    id: id,
                    isVisible: false
                )
            )
        }
        if !metrics.contains(where: \.isVisible), !metrics.isEmpty {
            metrics[0].isVisible = true
        }

        var seenCategories: Set<OverviewDashboardSummaryCategoryID> = []
        var categories = content.summaryCategories.filter {
            seenCategories.insert($0.id).inserted
        }
        for id in OverviewDashboardSummaryCategoryID.allCases where !seenCategories.contains(id) {
            categories.append(
                OverviewDashboardSummaryCategoryConfiguration(
                    id: id,
                    isVisible: false
                )
            )
        }
        if requireVisibleSummaryCategory,
           !categories.contains(where: \.isVisible),
           !categories.isEmpty {
            categories[0].isVisible = true
        }

        var seenGroups: Set<OverviewDashboardNetworkGroupID> = []
        var groups = content.networkGroups.filter {
            seenGroups.insert($0).inserted
        }
        for id in OverviewDashboardNetworkGroupID.allCases where !seenGroups.contains(id) {
            groups.append(id)
        }

        return OverviewDashboardContentPreferences(
            instrumentMetrics: metrics,
            timelineWindow: content.timelineWindow,
            summaryCategories: categories,
            networkGroups: groups
        )
    }
}

enum OverviewDashboardPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case realTimeSituation
    case routeAnalysis
    case lightweightMonitoring

    var id: String { rawValue }

    func applying(to layout: OverviewDashboardLayout) -> OverviewDashboardLayout {
        OverviewDashboardLayout(
            modules: moduleConfigurations,
            contentPreferences: layout.contentPreferences
        )
        .normalized()
    }

    private var moduleConfigurations: [OverviewDashboardModuleConfiguration] {
        switch self {
        case .realTimeSituation:
            [
                .init(id: .instrumentRail, size: .full),
                .init(id: .telemetry, size: .full),
                .init(id: .operationalSummaries, size: .full),
                .init(id: .routeTopology, size: .full),
                .init(id: .networkInformation, size: .full),
            ]
        case .routeAnalysis:
            [
                .init(id: .instrumentRail, size: .full),
                .init(id: .routeTopology, size: .full),
                .init(id: .operationalSummaries, size: .standard),
                .init(id: .telemetry, size: .standard),
                .init(id: .networkInformation, size: .full),
            ]
        case .lightweightMonitoring:
            [
                .init(id: .instrumentRail, size: .full),
                .init(id: .telemetry, size: .full),
                .init(id: .operationalSummaries, size: .full),
                .init(id: .routeTopology, size: .full, isVisible: false),
                .init(id: .networkInformation, size: .full, isVisible: false),
            ]
        }
    }
}

enum OverviewDashboardGridWidthMode: String, CaseIterable, Codable, Sendable {
    case wide
    case medium
    case narrow

    var columnCount: Int {
        switch self {
        case .wide:
            12
        case .medium:
            6
        case .narrow:
            1
        }
    }

    func columnSpan(for size: OverviewDashboardModuleSize) -> Int {
        switch (self, size) {
        case (.wide, .compact):
            4
        case (.wide, .standard):
            6
        case (.wide, .full):
            12
        case (.medium, .compact):
            3
        case (.medium, .standard), (.medium, .full):
            6
        case (.narrow, _):
            1
        }
    }
}

struct OverviewDashboardPackedModule: Equatable, Identifiable, Sendable {
    let configuration: OverviewDashboardModuleConfiguration
    let columnSpan: Int

    var id: OverviewDashboardModuleID { configuration.id }
}

struct OverviewDashboardPackedRow: Equatable, Identifiable, Sendable {
    let id: Int
    let modules: [OverviewDashboardPackedModule]
}

enum OverviewDashboardRowPacker {
    static func rows(
        for layout: OverviewDashboardLayout,
        widthMode: OverviewDashboardGridWidthMode
    ) -> [OverviewDashboardPackedRow] {
        var rows: [OverviewDashboardPackedRow] = []
        var current: [OverviewDashboardPackedModule] = []
        var occupiedColumns = 0

        for configuration in layout.normalized().visibleModules {
            let span = widthMode.columnSpan(for: configuration.size)
            if !current.isEmpty, occupiedColumns + span > widthMode.columnCount {
                rows.append(OverviewDashboardPackedRow(id: rows.count, modules: current))
                current.removeAll(keepingCapacity: true)
                occupiedColumns = 0
            }

            current.append(
                OverviewDashboardPackedModule(
                    configuration: configuration,
                    columnSpan: span
                )
            )
            occupiedColumns += span
        }

        if !current.isEmpty {
            rows.append(OverviewDashboardPackedRow(id: rows.count, modules: current))
        }
        return rows
    }
}

enum OverviewDashboardEffectiveLayoutSource: String, Codable, Sendable {
    case globalDefault
    case controllerOverride
}

struct OverviewDashboardEffectiveRevisionToken: Codable, Equatable, Sendable {
    let source: OverviewDashboardEffectiveLayoutSource
    let revision: UInt64
}

struct OverviewDashboardCommitToken: Codable, Equatable, Sendable {
    let effective: OverviewDashboardEffectiveRevisionToken
    let globalRevision: UInt64
}

struct OverviewDashboardEffectiveSnapshot: Equatable, Sendable {
    let layout: OverviewDashboardLayout
    let revisionToken: OverviewDashboardEffectiveRevisionToken
}

struct OverviewDashboardEditSnapshot: Equatable, Sendable {
    let layout: OverviewDashboardLayout
    let token: OverviewDashboardCommitToken
}

@MainActor
@Observable
final class OverviewDashboardEffectiveLayoutState {
    private(set) var snapshot: OverviewDashboardEffectiveSnapshot

    init(snapshot: OverviewDashboardEffectiveSnapshot) {
        self.snapshot = snapshot
    }

    var layout: OverviewDashboardLayout { snapshot.layout }
    var revisionToken: OverviewDashboardEffectiveRevisionToken {
        snapshot.revisionToken
    }

    fileprivate func apply(_ next: OverviewDashboardEffectiveSnapshot) {
        guard snapshot != next else { return }
        snapshot = next
    }
}

struct OverviewDashboardPersistenceClient: Sendable {
    let loadData: @Sendable () -> Data?
    let saveData: @Sendable (Data) throws -> Void

    init(
        loadData: @escaping @Sendable () -> Data?,
        saveData: @escaping @Sendable (Data) throws -> Void
    ) {
        self.loadData = loadData
        self.saveData = saveData
    }

    static func userDefaults(
        _ defaults: UserDefaults,
        key: String
    ) -> OverviewDashboardPersistenceClient {
        let box = OverviewDashboardUserDefaultsBox(defaults)
        return OverviewDashboardPersistenceClient(
            loadData: {
                box.defaults.data(forKey: key)
            },
            saveData: { data in
                box.defaults.set(data, forKey: key)
            }
        )
    }
}

private final class OverviewDashboardUserDefaultsBox: @unchecked Sendable {
    let defaults: UserDefaults

    init(_ defaults: UserDefaults) {
        self.defaults = defaults
    }
}

struct OverviewDashboardPersistenceEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let persistenceRevision: UInt64
    let globalRevision: UInt64
    let globalDefault: OverviewDashboardPersistedLayout?
    let controllerOverrides: [OverviewDashboardPersistedControllerOverride]

    init(
        version: Int = currentVersion,
        persistenceRevision: UInt64,
        globalRevision: UInt64,
        globalDefault: OverviewDashboardPersistedLayout?,
        controllerOverrides: [OverviewDashboardPersistedControllerOverride]
    ) {
        self.version = version
        self.persistenceRevision = persistenceRevision
        self.globalRevision = globalRevision
        self.globalDefault = globalDefault
        self.controllerOverrides = controllerOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case persistenceRevision
        case globalRevision
        case globalDefault
        case controllerOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decode(Int.self, forKey: .version)) ?? -1
        persistenceRevision =
            (try? container.decode(UInt64.self, forKey: .persistenceRevision)) ?? 0
        globalRevision =
            (try? container.decode(UInt64.self, forKey: .globalRevision)) ?? 0
        globalDefault =
            try? container.decode(OverviewDashboardPersistedLayout.self, forKey: .globalDefault)
        controllerOverrides =
            (
                try? container.decode(
                    OverviewDashboardLossyArray<
                        OverviewDashboardPersistedControllerOverride
                    >.self,
                    forKey: .controllerOverrides
                )
            )?.elements ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(persistenceRevision, forKey: .persistenceRevision)
        try container.encode(globalRevision, forKey: .globalRevision)
        try container.encode(globalDefault, forKey: .globalDefault)
        try container.encode(controllerOverrides, forKey: .controllerOverrides)
    }
}

struct OverviewDashboardPersistedControllerOverride: Codable, Equatable, Sendable {
    let controllerID: String?
    let revision: UInt64
    let layout: OverviewDashboardPersistedLayout?

    init(
        controllerID: String?,
        revision: UInt64,
        layout: OverviewDashboardPersistedLayout?
    ) {
        self.controllerID = controllerID
        self.revision = revision
        self.layout = layout
    }

    private enum CodingKeys: String, CodingKey {
        case controllerID
        case revision
        case layout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        controllerID = try? container.decode(String.self, forKey: .controllerID)
        revision = (try? container.decode(UInt64.self, forKey: .revision)) ?? 0
        layout = try? container.decode(
            OverviewDashboardPersistedLayout.self,
            forKey: .layout
        )
    }
}

struct OverviewDashboardPersistedLayout: Codable, Equatable, Sendable {
    let modules: [OverviewDashboardPersistedModule]
    let instrumentMetrics: [OverviewDashboardPersistedInstrumentMetric]
    let timelineWindow: String?
    let summaryCategories: [OverviewDashboardPersistedSummaryCategory]
    let networkGroups: [String]

    init(_ layout: OverviewDashboardLayout) {
        modules = layout.modules.map(OverviewDashboardPersistedModule.init)
        instrumentMetrics = layout.contentPreferences.instrumentMetrics.map(
            OverviewDashboardPersistedInstrumentMetric.init
        )
        timelineWindow = layout.contentPreferences.timelineWindow.rawValue
        summaryCategories = layout.contentPreferences.summaryCategories.map(
            OverviewDashboardPersistedSummaryCategory.init
        )
        networkGroups = layout.contentPreferences.networkGroups.map(\.rawValue)
    }

    init(
        modules: [OverviewDashboardPersistedModule],
        instrumentMetrics: [OverviewDashboardPersistedInstrumentMetric],
        timelineWindow: String?,
        summaryCategories: [OverviewDashboardPersistedSummaryCategory],
        networkGroups: [String]
    ) {
        self.modules = modules
        self.instrumentMetrics = instrumentMetrics
        self.timelineWindow = timelineWindow
        self.summaryCategories = summaryCategories
        self.networkGroups = networkGroups
    }

    private enum CodingKeys: String, CodingKey {
        case modules
        case instrumentMetrics
        case timelineWindow
        case summaryCategories
        case networkGroups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modules =
            (
                try? container.decode(
                    OverviewDashboardLossyArray<OverviewDashboardPersistedModule>.self,
                    forKey: .modules
                )
            )?.elements ?? []
        instrumentMetrics =
            (
                try? container.decode(
                    OverviewDashboardLossyArray<
                        OverviewDashboardPersistedInstrumentMetric
                    >.self,
                    forKey: .instrumentMetrics
                )
            )?.elements ?? []
        timelineWindow = try? container.decode(String.self, forKey: .timelineWindow)
        summaryCategories =
            (
                try? container.decode(
                    OverviewDashboardLossyArray<
                        OverviewDashboardPersistedSummaryCategory
                    >.self,
                    forKey: .summaryCategories
                )
            )?.elements ?? []
        networkGroups =
            (
                try? container.decode(
                    OverviewDashboardLossyArray<String>.self,
                    forKey: .networkGroups
                )
            )?.elements ?? []
    }

    func restoredLayout() -> OverviewDashboardLayout? {
        var seenModules: Set<OverviewDashboardModuleID> = []
        var restoredModules: [OverviewDashboardModuleConfiguration] = []
        for record in modules {
            guard let rawID = record.id,
                  let id = OverviewDashboardModuleID(rawValue: rawID),
                  seenModules.insert(id).inserted else {
                continue
            }
            let requestedSize = record.size.flatMap(OverviewDashboardModuleSize.init(rawValue:))
            let size = requestedSize.flatMap {
                id.legalSizes.contains($0) ? $0 : nil
            } ?? id.defaultSize
            restoredModules.append(
                OverviewDashboardModuleConfiguration(
                    id: id,
                    size: size,
                    isVisible: record.isVisible ?? false
                )
            )
        }

        guard restoredModules.contains(where: \.isVisible) else {
            return nil
        }

        var seenMetrics: Set<OverviewDashboardInstrumentMetricID> = []
        let restoredMetrics: [OverviewDashboardInstrumentMetricConfiguration] =
            instrumentMetrics.compactMap { record
                -> OverviewDashboardInstrumentMetricConfiguration? in
            guard let rawID = record.id,
                  let id = OverviewDashboardInstrumentMetricID(rawValue: rawID),
                  seenMetrics.insert(id).inserted else {
                return nil
            }
            return OverviewDashboardInstrumentMetricConfiguration(
                id: id,
                isVisible: record.isVisible ?? false
            )
        }

        var seenCategories: Set<OverviewDashboardSummaryCategoryID> = []
        let restoredCategories: [OverviewDashboardSummaryCategoryConfiguration] =
            summaryCategories.compactMap { record
                -> OverviewDashboardSummaryCategoryConfiguration? in
            guard let rawID = record.id,
                  let id = OverviewDashboardSummaryCategoryID(rawValue: rawID),
                  seenCategories.insert(id).inserted else {
                return nil
            }
            return OverviewDashboardSummaryCategoryConfiguration(
                id: id,
                isVisible: record.isVisible ?? false,
                itemCount:
                    record.itemCount.flatMap(OverviewDashboardSummaryItemCount.init(rawValue:))
                    ?? .three
            )
        }

        var seenGroups: Set<OverviewDashboardNetworkGroupID> = []
        let restoredGroups: [OverviewDashboardNetworkGroupID] =
            networkGroups.compactMap { rawID
                -> OverviewDashboardNetworkGroupID? in
            guard let id = OverviewDashboardNetworkGroupID(rawValue: rawID),
                  seenGroups.insert(id).inserted else {
                return nil
            }
            return id
        }

        return OverviewDashboardLayout(
            modules: restoredModules,
            contentPreferences: OverviewDashboardContentPreferences(
                instrumentMetrics: restoredMetrics,
                timelineWindow:
                    timelineWindow.flatMap(OverviewDashboardTimelineWindow.init(rawValue:))
                    ?? .fiveMinutes,
                summaryCategories: restoredCategories,
                networkGroups: restoredGroups
            )
        )
        .normalized()
    }
}

struct OverviewDashboardPersistedModule: Codable, Equatable, Sendable {
    let id: String?
    let size: String?
    let isVisible: Bool?

    init(_ configuration: OverviewDashboardModuleConfiguration) {
        id = configuration.id.rawValue
        size = configuration.size.rawValue
        isVisible = configuration.isVisible
    }

    init(id: String?, size: String?, isVisible: Bool?) {
        self.id = id
        self.size = size
        self.isVisible = isVisible
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case size
        case isVisible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decode(String.self, forKey: .id)
        size = try? container.decode(String.self, forKey: .size)
        isVisible = try? container.decode(Bool.self, forKey: .isVisible)
    }
}

struct OverviewDashboardPersistedInstrumentMetric: Codable, Equatable, Sendable {
    let id: String?
    let isVisible: Bool?

    init(_ configuration: OverviewDashboardInstrumentMetricConfiguration) {
        id = configuration.id.rawValue
        isVisible = configuration.isVisible
    }

    init(id: String?, isVisible: Bool?) {
        self.id = id
        self.isVisible = isVisible
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case isVisible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decode(String.self, forKey: .id)
        isVisible = try? container.decode(Bool.self, forKey: .isVisible)
    }
}

struct OverviewDashboardPersistedSummaryCategory: Codable, Equatable, Sendable {
    let id: String?
    let isVisible: Bool?
    let itemCount: Int?

    init(_ configuration: OverviewDashboardSummaryCategoryConfiguration) {
        id = configuration.id.rawValue
        isVisible = configuration.isVisible
        itemCount = configuration.itemCount.rawValue
    }

    init(id: String?, isVisible: Bool?, itemCount: Int?) {
        self.id = id
        self.isVisible = isVisible
        self.itemCount = itemCount
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case isVisible
        case itemCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decode(String.self, forKey: .id)
        isVisible = try? container.decode(Bool.self, forKey: .isVisible)
        itemCount = try? container.decode(Int.self, forKey: .itemCount)
    }
}

private struct OverviewDashboardLossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(OverviewDashboardDiscardedJSONValue.self)
            }
        }
        self.elements = elements
    }
}

private struct OverviewDashboardDiscardedJSONValue: Decodable {
    init(from decoder: Decoder) throws {
        if var container = try? decoder.unkeyedContainer() {
            while !container.isAtEnd {
                _ = try? container.decode(OverviewDashboardDiscardedJSONValue.self)
            }
            return
        }

        if let container = try? decoder.container(
            keyedBy: OverviewDashboardDynamicCodingKey.self
        ) {
            for key in container.allKeys {
                _ = try? container.decode(
                    OverviewDashboardDiscardedJSONValue.self,
                    forKey: key
                )
            }
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            return
        }
        if (try? container.decode(Bool.self)) != nil
            || (try? container.decode(Double.self)) != nil
            || (try? container.decode(String.self)) != nil {
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported persisted Overview value."
        )
    }
}

private struct OverviewDashboardDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct OverviewDashboardVersionedLayout: Equatable, Sendable {
    var revision: UInt64
    var layout: OverviewDashboardLayout
}

private struct OverviewDashboardCommittedState: Equatable, Sendable {
    var persistenceRevision: UInt64
    var globalDefault: OverviewDashboardVersionedLayout
    var controllerOverrides: [RouterProfile.ID: OverviewDashboardVersionedLayout]

    static let initial = OverviewDashboardCommittedState(
        persistenceRevision: 0,
        globalDefault: OverviewDashboardVersionedLayout(
            revision: 0,
            layout: .repositoryDefault
        ),
        controllerOverrides: [:]
    )

    func effectiveSnapshot(
        for controllerID: RouterProfile.ID
    ) -> OverviewDashboardEffectiveSnapshot {
        if let controllerOverride = controllerOverrides[controllerID] {
            return OverviewDashboardEffectiveSnapshot(
                layout: controllerOverride.layout,
                revisionToken: OverviewDashboardEffectiveRevisionToken(
                    source: .controllerOverride,
                    revision: controllerOverride.revision
                )
            )
        }

        return globalSnapshot
    }

    var globalSnapshot: OverviewDashboardEffectiveSnapshot {
        OverviewDashboardEffectiveSnapshot(
            layout: globalDefault.layout,
            revisionToken: OverviewDashboardEffectiveRevisionToken(
                source: .globalDefault,
                revision: globalDefault.revision
            )
        )
    }

    func editSnapshot(for controllerID: RouterProfile.ID) -> OverviewDashboardEditSnapshot {
        let effective = effectiveSnapshot(for: controllerID)
        return OverviewDashboardEditSnapshot(
            layout: effective.layout,
            token: OverviewDashboardCommitToken(
                effective: effective.revisionToken,
                globalRevision: globalDefault.revision
            )
        )
    }

    static func restored(from data: Data?) -> OverviewDashboardCommittedState {
        guard let data,
              let envelope = try? JSONDecoder().decode(
                  OverviewDashboardPersistenceEnvelope.self,
                  from: data
              ),
              envelope.version == OverviewDashboardPersistenceEnvelope.currentVersion,
              envelope.persistenceRevision < UInt64.max,
              envelope.globalRevision < UInt64.max else {
            return .initial
        }

        let globalLayout = envelope.globalDefault?.restoredLayout() ?? .repositoryDefault
        var overrides: [RouterProfile.ID: OverviewDashboardVersionedLayout] = [:]
        var highestRevision = max(
            envelope.persistenceRevision,
            envelope.globalRevision
        )

        for record in envelope.controllerOverrides {
            guard let rawControllerID = record.controllerID,
                  let controllerID = RouterProfile.ID(uuidString: rawControllerID),
                  overrides[controllerID] == nil,
                  record.revision < UInt64.max,
                  let layout = record.layout?.restoredLayout() else {
                continue
            }
            overrides[controllerID] = OverviewDashboardVersionedLayout(
                revision: record.revision,
                layout: layout
            )
            highestRevision = max(highestRevision, record.revision)
        }

        guard highestRevision < UInt64.max else {
            return .initial
        }
        return OverviewDashboardCommittedState(
            persistenceRevision: highestRevision,
            globalDefault: OverviewDashboardVersionedLayout(
                revision: envelope.globalRevision,
                layout: globalLayout
            ),
            controllerOverrides: overrides
        )
    }

    var persistenceEnvelope: OverviewDashboardPersistenceEnvelope {
        OverviewDashboardPersistenceEnvelope(
            persistenceRevision: persistenceRevision,
            globalRevision: globalDefault.revision,
            globalDefault: OverviewDashboardPersistedLayout(globalDefault.layout),
            controllerOverrides: controllerOverrides.map { controllerID, value in
                OverviewDashboardPersistedControllerOverride(
                    controllerID: controllerID.uuidString,
                    revision: value.revision,
                    layout: OverviewDashboardPersistedLayout(value.layout)
                )
            }
            .sorted {
                ($0.controllerID ?? "") < ($1.controllerID ?? "")
            }
        )
    }
}

enum OverviewDashboardCommitMode: Sendable {
    case controller
    case globalDefault
    case resetController
}

enum OverviewDashboardLayoutStoreError: Error, Equatable, Sendable {
    case conflict(current: OverviewDashboardEditSnapshot)
    case persistenceFailed
}

private enum OverviewDashboardTypedPersistenceMutation: Sendable {
    case commit(
        controllerID: RouterProfile.ID,
        layout: OverviewDashboardLayout,
        expected: OverviewDashboardCommitToken,
        mode: OverviewDashboardCommitMode
    )
    case removeController(RouterProfile.ID)
    case retainControllers(Set<RouterProfile.ID>)
}

private struct OverviewDashboardPersistenceResult: Sendable {
    let committedState: OverviewDashboardCommittedState
    let publicationSequence: UInt64
}

private actor OverviewDashboardPersistenceCoordinator {
    private var committedState: OverviewDashboardCommittedState
    private var publicationSequence: UInt64 = 0
    private let persistence: OverviewDashboardPersistenceClient

    init(
        committedState: OverviewDashboardCommittedState,
        persistence: OverviewDashboardPersistenceClient
    ) {
        self.committedState = committedState
        self.persistence = persistence
    }

    func apply(
        _ mutation: OverviewDashboardTypedPersistenceMutation
    ) throws -> OverviewDashboardPersistenceResult {
        var next = committedState
        let changed: Bool

        switch mutation {
        case .commit(let controllerID, let layout, let expected, let mode):
            let current = next.editSnapshot(for: controllerID)
            switch mode {
            case .controller:
                guard current.token.effective == expected.effective else {
                    throw OverviewDashboardLayoutStoreError.conflict(current: current)
                }
                changed = applyControllerCommit(
                    layout.normalized(),
                    controllerID: controllerID,
                    to: &next
                )
            case .globalDefault:
                guard current.token == expected else {
                    throw OverviewDashboardLayoutStoreError.conflict(current: current)
                }
                changed = applyGlobalCommit(
                    layout.normalized(),
                    controllerID: controllerID,
                    to: &next
                )
            case .resetController:
                guard current.token.effective == expected.effective else {
                    throw OverviewDashboardLayoutStoreError.conflict(current: current)
                }
                changed = applyControllerReset(
                    controllerID: controllerID,
                    to: &next
                )
            }
        case .removeController(let controllerID):
            changed = next.controllerOverrides.removeValue(forKey: controllerID) != nil
            if changed {
                next.persistenceRevision &+= 1
            }
        case .retainControllers(let controllerIDs):
            let previousCount = next.controllerOverrides.count
            next.controllerOverrides = next.controllerOverrides.filter {
                controllerIDs.contains($0.key)
            }
            changed = previousCount != next.controllerOverrides.count
            if changed {
                next.persistenceRevision &+= 1
            }
        }

        guard changed else {
            return OverviewDashboardPersistenceResult(
                committedState: committedState,
                publicationSequence: publicationSequence
            )
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(next.persistenceEnvelope)
            try persistence.saveData(data)
        } catch {
            throw OverviewDashboardLayoutStoreError.persistenceFailed
        }

        committedState = next
        publicationSequence &+= 1
        return OverviewDashboardPersistenceResult(
            committedState: next,
            publicationSequence: publicationSequence
        )
    }

    private func applyControllerCommit(
        _ layout: OverviewDashboardLayout,
        controllerID: RouterProfile.ID,
        to state: inout OverviewDashboardCommittedState
    ) -> Bool {
        if layout == state.globalDefault.layout {
            guard state.controllerOverrides.removeValue(forKey: controllerID) != nil else {
                return false
            }
            state.persistenceRevision &+= 1
            return true
        }

        if state.controllerOverrides[controllerID]?.layout == layout {
            return false
        }

        state.persistenceRevision &+= 1
        state.controllerOverrides[controllerID] = OverviewDashboardVersionedLayout(
            revision: state.persistenceRevision,
            layout: layout
        )
        return true
    }

    private func applyGlobalCommit(
        _ layout: OverviewDashboardLayout,
        controllerID: RouterProfile.ID,
        to state: inout OverviewDashboardCommittedState
    ) -> Bool {
        let changesGlobal = state.globalDefault.layout != layout
        let removesControllerOverride = state.controllerOverrides[controllerID] != nil

        guard changesGlobal || removesControllerOverride else {
            return false
        }

        state.persistenceRevision &+= 1
        if changesGlobal {
            state.globalDefault = OverviewDashboardVersionedLayout(
                revision: state.persistenceRevision,
                layout: layout
            )
        }
        if removesControllerOverride {
            state.controllerOverrides.removeValue(forKey: controllerID)
        }
        return true
    }

    private func applyControllerReset(
        controllerID: RouterProfile.ID,
        to state: inout OverviewDashboardCommittedState
    ) -> Bool {
        guard state.controllerOverrides.removeValue(forKey: controllerID) != nil else {
            return false
        }
        state.persistenceRevision &+= 1
        return true
    }
}

@MainActor
@Observable
final class OverviewDashboardLayoutStore {
    static let defaultPersistenceKey = "overview.dashboard.layout.v1"

    @ObservationIgnored private let persistenceCoordinator:
        OverviewDashboardPersistenceCoordinator
    @ObservationIgnored private var committedState: OverviewDashboardCommittedState
    @ObservationIgnored private var controllerStates: [
        RouterProfile.ID: OverviewDashboardEffectiveLayoutState
    ] = [:]
    @ObservationIgnored private let globalState: OverviewDashboardEffectiveLayoutState
    @ObservationIgnored private var latestPublicationSequence: UInt64 = 0

    convenience init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = OverviewDashboardLayoutStore.defaultPersistenceKey
    ) {
        self.init(
            persistence: .userDefaults(defaults, key: persistenceKey)
        )
    }

    init(persistence: OverviewDashboardPersistenceClient) {
        let restored = OverviewDashboardCommittedState.restored(
            from: persistence.loadData()
        )
        committedState = restored
        globalState = OverviewDashboardEffectiveLayoutState(
            snapshot: restored.globalSnapshot
        )
        persistenceCoordinator = OverviewDashboardPersistenceCoordinator(
            committedState: restored,
            persistence: persistence
        )
    }

    var globalDefaultState: OverviewDashboardEffectiveLayoutState {
        globalState
    }

    var globalDefaultLayout: OverviewDashboardLayout {
        committedState.globalDefault.layout
    }

    func effectiveState(
        for controllerID: RouterProfile.ID
    ) -> OverviewDashboardEffectiveLayoutState {
        if let state = controllerStates[controllerID] {
            return state
        }

        let state = OverviewDashboardEffectiveLayoutState(
            snapshot: committedState.effectiveSnapshot(for: controllerID)
        )
        controllerStates[controllerID] = state
        return state
    }

    func effectiveSnapshot(
        for controllerID: RouterProfile.ID
    ) -> OverviewDashboardEffectiveSnapshot {
        committedState.effectiveSnapshot(for: controllerID)
    }

    func editSnapshot(
        for controllerID: RouterProfile.ID
    ) -> OverviewDashboardEditSnapshot {
        committedState.editSnapshot(for: controllerID)
    }

    @discardableResult
    func commit(
        _ layout: OverviewDashboardLayout,
        for controllerID: RouterProfile.ID,
        expected token: OverviewDashboardCommitToken,
        mode: OverviewDashboardCommitMode = .controller
    ) async throws -> OverviewDashboardEditSnapshot {
        let result = try await persistenceCoordinator.apply(
            .commit(
                controllerID: controllerID,
                layout: layout,
                expected: token,
                mode: mode
            )
        )
        publish(result)
        return committedState.editSnapshot(for: controllerID)
    }

    func removeController(_ controllerID: RouterProfile.ID) async throws {
        let result = try await persistenceCoordinator.apply(
            .removeController(controllerID)
        )
        publish(result)
        controllerStates.removeValue(forKey: controllerID)
    }

    func retainControllers(_ controllerIDs: Set<RouterProfile.ID>) async throws {
        let result = try await persistenceCoordinator.apply(
            .retainControllers(controllerIDs)
        )
        publish(result)
        controllerStates = controllerStates.filter {
            controllerIDs.contains($0.key)
        }
    }

    private func publish(_ result: OverviewDashboardPersistenceResult) {
        guard result.publicationSequence >= latestPublicationSequence else {
            return
        }
        latestPublicationSequence = result.publicationSequence
        let next = result.committedState
        committedState = next
        globalState.apply(next.globalSnapshot)
        for (controllerID, state) in controllerStates {
            state.apply(next.effectiveSnapshot(for: controllerID))
        }
    }
}

enum OverviewDashboardWindowConflictKind: String, Codable, Sendable {
    case committedLayoutChanged
    case selectedControllerChanged
    case targetControllerUnavailable
}

struct OverviewDashboardWindowConflict: Equatable, Sendable {
    let kind: OverviewDashboardWindowConflictKind
    let latestToken: OverviewDashboardCommitToken?
}

enum OverviewDashboardWindowCommitFailure: String, Codable, Sendable {
    case conflict
    case targetControllerUnavailable
    case persistence
}

@MainActor
@Observable
final class OverviewDashboardWindowCoordinator {
    let liveSessionWindowDemandID: LiveSessionWindowDemandID
    let runtimeRegistry = OverviewDashboardModuleRuntimeRegistry()

    private(set) var targetControllerID: RouterProfile.ID?
    private(set) var draft: OverviewDashboardLayout?
    private(set) var original: OverviewDashboardLayout?
    private(set) var baseToken: OverviewDashboardCommitToken?
    private(set) var setsGlobalDefault = false
    private(set) var resetsControllerOverride = false
    private(set) var conflict: OverviewDashboardWindowConflict?
    private(set) var lastCommitFailure: OverviewDashboardWindowCommitFailure?
    private(set) var isCommitting = false

    @ObservationIgnored private let layoutStore: OverviewDashboardLayoutStore
    @ObservationIgnored private weak var undoManager: UndoManager?
    @ObservationIgnored private var targetControllerIsAvailable = true

    init(
        layoutStore: OverviewDashboardLayoutStore,
        liveSessionWindowDemandID: LiveSessionWindowDemandID =
            LiveSessionWindowDemandID()
    ) {
        self.layoutStore = layoutStore
        self.liveSessionWindowDemandID = liveSessionWindowDemandID
    }

    var isEditing: Bool {
        draft != nil
    }

    var hasDirtyDraft: Bool {
        guard let draft, let original else { return false }
        return draft != original
            || setsGlobalDefault
            || resetsControllerOverride
    }

    func presentedLayout(
        for controllerID: RouterProfile.ID
    ) -> OverviewDashboardLayout {
        if targetControllerID == controllerID, let draft {
            return draft
        }
        return layoutStore.effectiveSnapshot(for: controllerID).layout
    }

    func beginEditing(
        controllerID: RouterProfile.ID,
        undoManager: UndoManager? = nil
    ) {
        guard !isCommitting, !isEditing else { return }
        if let undoManager {
            attachUndoManager(undoManager)
        }
        clearUndoHistory()

        let snapshot = layoutStore.editSnapshot(for: controllerID)
        targetControllerID = controllerID
        draft = snapshot.layout
        original = snapshot.layout
        baseToken = snapshot.token
        setsGlobalDefault = false
        resetsControllerOverride = false
        conflict = nil
        lastCommitFailure = nil
        targetControllerIsAvailable = true
    }

    func attachUndoManager(_ undoManager: UndoManager?) {
        guard self.undoManager !== undoManager else { return }
        clearUndoHistory()
        self.undoManager = undoManager
    }

    func mutateDraft(
        actionName: String? = nil,
        _ mutation: (inout OverviewDashboardLayout) -> Void
    ) {
        guard var next = draft, !isCommitting else { return }
        mutation(&next)
        next = next.normalized()
        replaceDraftState(
            OverviewDashboardWindowDraftState(
                layout: next,
                setsGlobalDefault: setsGlobalDefault,
                resetsControllerOverride: false
            ),
            actionName: actionName,
            registersUndo: true
        )
    }

    func updateContentPreferences(
        actionName: String? = nil,
        _ mutation: (inout OverviewDashboardContentPreferences) -> Void
    ) {
        mutateDraft(actionName: actionName) {
            mutation(&$0.contentPreferences)
        }
    }

    func applyPreset(
        _ preset: OverviewDashboardPreset,
        actionName: String? = nil
    ) {
        mutateDraft(actionName: actionName) {
            $0 = preset.applying(to: $0)
        }
    }

    func moveModule(
        _ id: OverviewDashboardModuleID,
        to targetIndex: Int,
        actionName: String? = nil
    ) {
        mutateDraft(actionName: actionName) { layout in
            guard let sourceIndex = layout.modules.firstIndex(where: { $0.id == id }) else {
                return
            }
            let configuration = layout.modules.remove(at: sourceIndex)
            let insertionIndex = min(max(targetIndex, 0), layout.modules.endIndex)
            layout.modules.insert(configuration, at: insertionIndex)
        }
    }

    func setModuleVisibility(
        _ id: OverviewDashboardModuleID,
        isVisible: Bool,
        actionName: String? = nil
    ) {
        mutateDraft(actionName: actionName) { layout in
            guard let index = layout.modules.firstIndex(where: { $0.id == id }) else {
                return
            }
            layout.modules[index].isVisible = isVisible
        }
    }

    func setModuleSize(
        _ id: OverviewDashboardModuleID,
        size: OverviewDashboardModuleSize,
        actionName: String? = nil
    ) {
        guard id.legalSizes.contains(size) else { return }
        mutateDraft(actionName: actionName) { layout in
            guard let index = layout.modules.firstIndex(where: { $0.id == id }) else {
                return
            }
            layout.modules[index].size = size
        }
    }

    func resetCurrentController(actionName: String? = nil) {
        guard draft != nil, let baseToken, !isCommitting else { return }
        replaceDraftState(
            OverviewDashboardWindowDraftState(
                layout: layoutStore.globalDefaultLayout,
                setsGlobalDefault: false,
                resetsControllerOverride:
                    baseToken.effective.source == .controllerOverride
            ),
            actionName: actionName,
            registersUndo: true
        )
    }

    func setAsGlobalDefault(
        _ enabled: Bool,
        actionName: String? = nil
    ) {
        guard let draft, setsGlobalDefault != enabled, !isCommitting else {
            return
        }
        replaceDraftState(
            OverviewDashboardWindowDraftState(
                layout: draft,
                setsGlobalDefault: enabled,
                resetsControllerOverride: false
            ),
            actionName: actionName,
            registersUndo: true
        )
        reconcileConflictAgainstCommittedState()
    }

    func reconcile(
        selectedControllerID: RouterProfile.ID?,
        targetControllerExists: Bool
    ) {
        guard let targetControllerID, let baseToken else { return }
        targetControllerIsAvailable = targetControllerExists

        guard targetControllerExists else {
            conflict = OverviewDashboardWindowConflict(
                kind: .targetControllerUnavailable,
                latestToken: nil
            )
            return
        }

        let latest = layoutStore.editSnapshot(for: targetControllerID)
        if selectedControllerID != targetControllerID {
            conflict = OverviewDashboardWindowConflict(
                kind: .selectedControllerChanged,
                latestToken: latest.token
            )
            return
        }

        if resetsControllerOverride {
            guard latest.token.effective == baseToken.effective else {
                conflict = OverviewDashboardWindowConflict(
                    kind: .committedLayoutChanged,
                    latestToken: latest.token
                )
                return
            }
            if latest.token.globalRevision != baseToken.globalRevision {
                draft = layoutStore.globalDefaultLayout
                self.baseToken = latest.token
            }
            conflict = nil
            return
        }

        if latest.token.effective != baseToken.effective
            || (setsGlobalDefault && latest.token.globalRevision != baseToken.globalRevision) {
            conflict = OverviewDashboardWindowConflict(
                kind: .committedLayoutChanged,
                latestToken: latest.token
            )
            return
        }

        conflict = nil
    }

    func reloadFromCommitted() {
        guard let targetControllerID,
              targetControllerIsAvailable,
              conflict?.kind != .selectedControllerChanged,
              !isCommitting else {
            return
        }
        let latest = layoutStore.editSnapshot(for: targetControllerID)
        clearUndoHistory()
        draft = latest.layout
        original = latest.layout
        baseToken = latest.token
        setsGlobalDefault = false
        resetsControllerOverride = false
        conflict = nil
        lastCommitFailure = nil
    }

    func cancel() {
        guard !isCommitting else { return }
        finishEditing()
    }

    @discardableResult
    func done() async -> Bool {
        await commitDraft(allowExistingConflict: false)
    }

    @discardableResult
    func keepMineAndCommit() async -> Bool {
        guard let targetControllerID, draft != nil, !isCommitting else {
            return false
        }
        if !targetControllerIsAvailable, !setsGlobalDefault {
            lastCommitFailure = .targetControllerUnavailable
            return false
        }

        baseToken = layoutStore.editSnapshot(for: targetControllerID).token
        conflict = nil
        return await commitDraft(allowExistingConflict: true)
    }

    private func reconcileConflictAgainstCommittedState() {
        guard let targetControllerID, let baseToken else { return }
        if conflict?.kind == .selectedControllerChanged
            || conflict?.kind == .targetControllerUnavailable {
            return
        }
        let latest = layoutStore.editSnapshot(for: targetControllerID)
        if resetsControllerOverride {
            if latest.token.effective != baseToken.effective {
                conflict = OverviewDashboardWindowConflict(
                    kind: .committedLayoutChanged,
                    latestToken: latest.token
                )
            } else if conflict?.kind == .committedLayoutChanged {
                conflict = nil
            }
            return
        }
        if latest.token.effective != baseToken.effective
            || (setsGlobalDefault && latest.token.globalRevision != baseToken.globalRevision) {
            conflict = OverviewDashboardWindowConflict(
                kind: .committedLayoutChanged,
                latestToken: latest.token
            )
        } else if conflict?.kind == .committedLayoutChanged {
            conflict = nil
        }
    }

    private func commitDraft(allowExistingConflict: Bool) async -> Bool {
        guard let targetControllerID,
              let draft,
              let baseToken,
              !isCommitting else {
            return false
        }

        if !targetControllerIsAvailable, !setsGlobalDefault {
            lastCommitFailure = .targetControllerUnavailable
            return false
        }
        if conflict != nil, !allowExistingConflict,
           !(setsGlobalDefault && !targetControllerIsAvailable) {
            lastCommitFailure = .conflict
            return false
        }

        isCommitting = true
        lastCommitFailure = nil
        defer { isCommitting = false }

        do {
            let mode: OverviewDashboardCommitMode
            if setsGlobalDefault {
                mode = .globalDefault
            } else if resetsControllerOverride {
                mode = .resetController
            } else {
                mode = .controller
            }
            _ = try await layoutStore.commit(
                draft,
                for: targetControllerID,
                expected: baseToken,
                mode: mode
            )
            finishEditing()
            return true
        } catch OverviewDashboardLayoutStoreError.conflict(let current) {
            conflict = OverviewDashboardWindowConflict(
                kind: .committedLayoutChanged,
                latestToken: current.token
            )
            lastCommitFailure = .conflict
            return false
        } catch {
            lastCommitFailure = .persistence
            return false
        }
    }

    private func replaceDraftState(
        _ next: OverviewDashboardWindowDraftState,
        actionName: String?,
        registersUndo: Bool
    ) {
        guard let currentLayout = draft else { return }
        let current = OverviewDashboardWindowDraftState(
            layout: currentLayout,
            setsGlobalDefault: setsGlobalDefault,
            resetsControllerOverride: resetsControllerOverride
        )
        guard current != next else { return }

        if registersUndo, let undoManager {
            undoManager.registerUndo(withTarget: self) { target in
                // Window UndoManager callbacks execute on the main event loop.
                MainActor.assumeIsolated {
                    target.replaceDraftState(
                        current,
                        actionName: actionName,
                        registersUndo: true
                    )
                }
            }
            if let actionName {
                undoManager.setActionName(actionName)
            }
        }

        draft = next.layout
        setsGlobalDefault = next.setsGlobalDefault
        resetsControllerOverride = next.resetsControllerOverride
        lastCommitFailure = nil
        reconcileConflictAgainstCommittedState()
    }

    private func clearUndoHistory() {
        undoManager?.removeAllActions(withTarget: self)
    }

    private func finishEditing() {
        clearUndoHistory()
        targetControllerID = nil
        draft = nil
        original = nil
        baseToken = nil
        setsGlobalDefault = false
        resetsControllerOverride = false
        conflict = nil
        lastCommitFailure = nil
        targetControllerIsAvailable = true
    }
}

private struct OverviewDashboardWindowDraftState: Equatable, Sendable {
    let layout: OverviewDashboardLayout
    let setsGlobalDefault: Bool
    let resetsControllerOverride: Bool
}
