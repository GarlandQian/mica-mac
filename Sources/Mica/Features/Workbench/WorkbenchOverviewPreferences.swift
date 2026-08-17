import Foundation
import Observation

enum OverviewMetricID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case upload
    case download
    case activeConnections

    var id: String { rawValue }
}

enum OverviewOptionalModuleID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case instrumentRail
    case operationalSummaries
    case networkInformation

    var id: String { rawValue }
}

enum OverviewSummaryCategoryID: String, CaseIterable, Hashable, Identifiable, Sendable {
    case latency
    case ruleHits
    case activeConnections

    var id: String { rawValue }
}

enum OverviewNetworkGroupID: String, CaseIterable, Hashable, Identifiable, Sendable {
    case controllerIdentity
    case runtimeAndFeatures
    case listenerPorts

    var id: String { rawValue }
}

struct OverviewPreferences: Codable, Equatable, Sendable {
    var visibleMetrics: Set<OverviewMetricID>
    var timelineWindow: OverviewTimelineWindow
    var visibleOptionalModules: Set<OverviewOptionalModuleID>

    init(
        visibleMetrics: Set<OverviewMetricID> = Set(OverviewMetricID.allCases),
        timelineWindow: OverviewTimelineWindow = .fiveMinutes,
        visibleOptionalModules: Set<OverviewOptionalModuleID> = []
    ) {
        self.visibleMetrics = visibleMetrics
        self.timelineWindow = timelineWindow
        self.visibleOptionalModules = visibleOptionalModules
    }

    static let `default` = OverviewPreferences()

    func normalized() -> OverviewPreferences {
        let supportedMetrics = Set(OverviewMetricID.allCases)
        var metrics = visibleMetrics.intersection(supportedMetrics)
        if metrics.isEmpty {
            metrics = [.upload]
        }
        return OverviewPreferences(
            visibleMetrics: metrics,
            timelineWindow: timelineWindow,
            visibleOptionalModules: visibleOptionalModules.intersection(
                Set(OverviewOptionalModuleID.allCases)
            )
        )
    }
}

struct OverviewPreferencesPersistenceClient: Sendable {
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
    ) -> OverviewPreferencesPersistenceClient {
        let box = OverviewPreferencesUserDefaultsBox(defaults)
        return OverviewPreferencesPersistenceClient(
            loadData: { box.defaults.data(forKey: key) },
            saveData: { box.defaults.set($0, forKey: key) }
        )
    }
}

private final class OverviewPreferencesUserDefaultsBox: @unchecked Sendable {
    let defaults: UserDefaults

    init(_ defaults: UserDefaults) {
        self.defaults = defaults
    }
}

struct OverviewPreferencesPersistenceEnvelope: Codable, Equatable, Sendable {
    static let schema = "mica.overview.fixed-core.v1"

    let schema: String
    let preferences: OverviewPreferences

    init(preferences: OverviewPreferences) {
        schema = Self.schema
        self.preferences = preferences.normalized()
    }
}

@MainActor
@Observable
final class OverviewPreferencesStore {
    /// The redesigned Overview intentionally replaces the development-only
    /// layout payload at the existing v1 key. The schema discriminator prevents
    /// the superseded layout object from being interpreted as preferences.
    static let defaultPersistenceKey = "overview.dashboard.layout.v1"

    private(set) var preferences: OverviewPreferences

    @ObservationIgnored private let persistence: OverviewPreferencesPersistenceClient
    @ObservationIgnored private let encoder = JSONEncoder()

    convenience init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = OverviewPreferencesStore.defaultPersistenceKey
    ) {
        self.init(
            persistence: .userDefaults(defaults, key: persistenceKey)
        )
    }

    init(persistence: OverviewPreferencesPersistenceClient) {
        self.persistence = persistence
        preferences = Self.restore(from: persistence.loadData())
    }

    func isMetricVisible(_ metric: OverviewMetricID) -> Bool {
        preferences.visibleMetrics.contains(metric)
    }

    func isOptionalModuleVisible(_ module: OverviewOptionalModuleID) -> Bool {
        preferences.visibleOptionalModules.contains(module)
    }

    func setMetric(_ metric: OverviewMetricID, isVisible: Bool) {
        update { preferences in
            if isVisible {
                preferences.visibleMetrics.insert(metric)
            } else {
                preferences.visibleMetrics.remove(metric)
            }
        }
    }

    func setTimelineWindow(_ window: OverviewTimelineWindow) {
        update { $0.timelineWindow = window }
    }

    func setOptionalModule(
        _ module: OverviewOptionalModuleID,
        isVisible: Bool
    ) {
        update { preferences in
            if isVisible {
                preferences.visibleOptionalModules.insert(module)
            } else {
                preferences.visibleOptionalModules.remove(module)
            }
        }
    }

    func reset() {
        assign(.default)
    }

    private func update(_ mutation: (inout OverviewPreferences) -> Void) {
        var next = preferences
        mutation(&next)
        assign(next)
    }

    private func assign(_ next: OverviewPreferences) {
        let normalized = next.normalized()
        guard normalized != preferences else { return }
        preferences = normalized
        guard let data = try? encoder.encode(
            OverviewPreferencesPersistenceEnvelope(preferences: normalized)
        ) else {
            return
        }
        try? persistence.saveData(data)
    }

    private static func restore(from data: Data?) -> OverviewPreferences {
        guard let data,
              let envelope = try? JSONDecoder().decode(
                OverviewPreferencesPersistenceEnvelope.self,
                from: data
              ),
              envelope.schema == OverviewPreferencesPersistenceEnvelope.schema else {
            return .default
        }
        return envelope.preferences.normalized()
    }
}
