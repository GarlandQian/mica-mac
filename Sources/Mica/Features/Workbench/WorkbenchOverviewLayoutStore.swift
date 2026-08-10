import Foundation
import MicaCore
import Observation

// MARK: - Overview layout persistence

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
