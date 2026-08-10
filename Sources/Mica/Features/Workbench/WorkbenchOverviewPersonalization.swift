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

    func apply(_ next: OverviewDashboardEffectiveSnapshot) {
        guard snapshot != next else { return }
        snapshot = next
    }
}
