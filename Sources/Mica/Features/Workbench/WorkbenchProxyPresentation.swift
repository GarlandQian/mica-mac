import Foundation
import MicaCore

struct ProxySessionPresentation: Equatable {
    let commandsEnabled: Bool
    let retainedDataMessage: String?

    init(
        hasRetainedCatalog: Bool,
        state: LiveSessionState,
        language: AppLanguage
    ) {
        commandsEnabled = state.allowsLiveCommands

        guard hasRetainedCatalog else {
            retainedDataMessage = nil
            return
        }

        let detail: String?
        switch state {
        case .live:
            detail = nil
        case .idle:
            detail = MicaStrings.localizedKey(
                "connection.disconnected",
                language: language
            )
        case .connecting:
            detail = state.label(language: language)
        case .staleReconnecting(let message), .partial(let message),
             .failedBeforeFirstSnapshot(let message), .failed(let message):
            detail = message.proxyNonBlank ?? state.label(language: language)
        case .stopped:
            detail = MicaStrings.localizedKey(
                "live.detail_stopped",
                language: language
            )
        }

        retainedDataMessage = detail.map {
            MicaStrings.localized(
                "data.stale_detail \($0)",
                language: language
            )
        }
    }
}

struct ProxyOperationActivity: Equatable {
    let switchingGroupID: String?
    let switchingSurgePolicyGroup: String?
    let measuringDelayGroupID: String?
    let testingSurgePolicyGroup: String?
    let clearingFixedGroupID: String?
    let measuringDelayNode: PolicyNodeLatencyTestTarget?

    var isActive: Bool {
        switchingGroupID != nil
            || switchingSurgePolicyGroup != nil
            || measuringDelayGroupID != nil
            || testingSurgePolicyGroup != nil
            || clearingFixedGroupID != nil
            || measuringDelayNode != nil
    }

    func isSwitching(groupID: String) -> Bool {
        switchingGroupID == groupID || switchingSurgePolicyGroup == groupID
    }

    func isTesting(groupID: String) -> Bool {
        measuringDelayGroupID == groupID || testingSurgePolicyGroup == groupID
    }

    func isMeasuring(groupID: String, nodeName: String) -> Bool {
        measuringDelayNode?.groupID == groupID
            && measuringDelayNode?.nodeName == nodeName
    }
}

struct ProxyLatencyScale: Equatable {
    let maximumDelay: Int?

    init(delays: [Int?]) {
        maximumDelay = delays.compactMap { delay in
            guard let delay, delay > 0 else { return nil }
            return delay
        }.max()
    }

    func fraction(for delay: Int?) -> Double? {
        guard let delay,
              delay > 0,
              let maximumDelay,
              maximumDelay > 0 else {
            return nil
        }
        return min(1, max(0, Double(delay) / Double(maximumDelay)))
    }
}

struct ProxyGroupKey: Hashable {
    let groupID: String
    let occurrence: Int

    var rawValue: String {
        "\(groupID.utf8.count):\(groupID):\(occurrence)"
    }
}

struct ProxyGroupOccurrence: Identifiable, Equatable {
    let key: ProxyGroupKey
    let group: ProxyGroupViewState

    var id: String { key.rawValue }
}

struct ProxyMemberOccurrence: Identifiable, Equatable {
    let name: String
    let occurrence: Int

    var id: String {
        "\(name.utf8.count):\(name):\(occurrence)"
    }
}

struct ProxyGroupDirectoryItem: Identifiable, Equatable {
    let key: ProxyGroupKey
    let groupID: String
    let type: String
    let selected: String
    let memberCount: Int
    let selectedDelay: Int?
    let availableMemberCount: Int
    let latencyDistribution: ProxyLatencyDistribution
    let health: ProxyGroupHealthSummary
    let hidden: Bool
    let selectable: Bool
    let hasFixedSelection: Bool
    let reportedUsageRanks: [PolicyGroupUsageRank]

    var id: String { key.rawValue }

    var healthSummary: ProxyGroupHealthSummary { health }
}

struct ProxyNodeRowProjection: Identifiable, Equatable {
    let id: String
    let name: String
    let occurrence: Int
    let type: String?
    let providerName: String?
    let transportNames: [String]
    let delay: Int?
    let latencyFraction: Double?
    let alive: Bool?
    let health: ProxyNodeHealthState
    let usageRank: PolicyGroupUsageRank?
    let isControllerSelected: Bool

    var subtitle: String? {
        let values = [type?.proxyNonBlank, providerName?.proxyNonBlank]
            .compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: " / ")
    }

    var isSlow: Bool {
        ProxyNodeHealthState.grade(for: delay) == .slow
    }
}

enum ProxyNodeHealthState: String, CaseIterable, Equatable, Hashable, Sendable {
    case healthy
    case degraded
    case unavailable
    case unknown

    static func grade(for delay: Int?) -> LatencyHealthGrade? {
        guard let delay, delay > 0 else { return nil }
        return LatencyHealthGrade.allCases.first { $0.includes(delay: delay) }
    }

    static func classify(alive: Bool?, delay: Int?) -> Self {
        if let delay, delay <= 0 {
            return .unavailable
        }
        return classify(alive: alive, grade: grade(for: delay))
    }

    static func classify(alive: Bool?, grade: LatencyHealthGrade?) -> Self {
        if alive == false {
            return .unavailable
        }
        if let grade {
            switch grade {
            case .fast, .normal:
                return .healthy
            case .slow:
                return .degraded
            case .timeout:
                return .unavailable
            }
        }
        return alive == true ? .healthy : .unknown
    }
}

enum ProxyHealthFilter: String, CaseIterable, Equatable, Hashable, Sendable {
    case all
    case degraded
    case unavailable
    case slow
    case current

    func includes(_ row: ProxyNodeRowProjection) -> Bool {
        switch self {
        case .all:
            true
        case .degraded:
            row.health != .healthy
        case .unavailable:
            row.health == .unavailable
        case .slow:
            row.isSlow
        case .current:
            row.isControllerSelected
        }
    }
}

struct ProxyGroupHealthSummary: Equatable {
    enum Status: String, CaseIterable, Equatable, Hashable, Sendable {
        case healthy
        case degraded
        case failed
        case unknown
    }

    let status: Status
    let memberCount: Int
    let availableCount: Int
    let unavailableCount: Int
    let unknownCount: Int
    let slowCount: Int
    let latencyDistribution: ProxyLatencyDistribution

    init(group: ProxyGroupViewState) {
        var availableCount = 0
        var unavailableCount = 0
        var unknownCount = 0
        var slowCount = 0
        var hasIssue = false
        var latencyCounts: [ProxyLatencyDistributionBucket.Kind: Int] = [:]

        for member in group.options {
            let detail = group.detail(for: member)
            let delay = group.delays[member] ?? detail?.latestHistoryDelay
            let grade = ProxyNodeHealthState.grade(for: delay)
            let state = ProxyNodeHealthState.classify(
                alive: detail?.alive,
                delay: delay
            )
            switch state {
            case .healthy:
                availableCount += 1
            case .degraded:
                availableCount += 1
                hasIssue = true
            case .unavailable:
                unavailableCount += 1
                hasIssue = true
            case .unknown:
                unknownCount += 1
                hasIssue = true
            }
            if grade == .slow {
                slowCount += 1
            }

            let bucket: ProxyLatencyDistributionBucket.Kind
            guard let delay, delay > 0 else {
                bucket = .unavailable
                latencyCounts[bucket, default: 0] += 1
                continue
            }
            switch grade {
            case .fast: bucket = .fast
            case .normal: bucket = .normal
            case .slow: bucket = .slow
            case .timeout, .none: bucket = .timeout
            }
            latencyCounts[bucket, default: 0] += 1
        }

        memberCount = group.options.count
        self.availableCount = availableCount
        self.unavailableCount = unavailableCount
        self.unknownCount = unknownCount
        self.slowCount = slowCount
        latencyDistribution = ProxyLatencyDistribution(
            counts: latencyCounts,
            total: group.options.count
        )

        let hasUsableMember = availableCount > 0
        let hasExplicitFailure = unavailableCount > 0
        if hasUsableMember {
            status = hasIssue ? .degraded : .healthy
        } else if hasExplicitFailure {
            status = .failed
        } else {
            status = .unknown
        }
    }
}

enum ProxyNavigationTargetResolutionStatus: String, Equatable, Sendable {
    case resolved
    case emptyCatalog
    case hiddenGlobal
    case missingGroup
    case ambiguousGroup
    case missingNode
}

struct ProxyNavigationTargetResolution: Equatable {
    let status: ProxyNavigationTargetResolutionStatus
    let occurrence: ProxyGroupOccurrence?
    let member: ProxyMemberOccurrence?
    let row: ProxyNodeRowProjection?

    var isResolved: Bool {
        status == .resolved && occurrence != nil && member != nil && row != nil
    }

    var revealTargetID: String? {
        guard let occurrence, let member else { return nil }
        return ProxyProjection.revealTargetID(
            groupID: occurrence.id,
            memberID: member.id
        )
    }
}

struct ProxyLatencyDistribution: Equatable {
    let buckets: [ProxyLatencyDistributionBucket]

    init(
        counts: [ProxyLatencyDistributionBucket.Kind: Int],
        total: Int
    ) {
        let denominator = max(1, total)
        buckets = ProxyLatencyDistributionBucket.Kind.allCases.compactMap {
            kind in
            let count = counts[kind, default: 0]
            guard count > 0 else { return nil }
            return ProxyLatencyDistributionBucket(
                kind: kind,
                count: count,
                fraction: Double(count) / Double(denominator)
            )
        }
    }

    init(group: ProxyGroupViewState) {
        var counts: [ProxyLatencyDistributionBucket.Kind: Int] = [:]
        for member in group.options {
            let delay = group.delays[member]
                ?? group.detail(for: member)?.latestHistoryDelay
            let kind: ProxyLatencyDistributionBucket.Kind
            guard let delay, delay > 0 else {
                counts[.unavailable, default: 0] += 1
                continue
            }
            switch LatencyHealthGrade.allCases.first(where: {
                $0.includes(delay: delay)
            }) {
            case .fast: kind = .fast
            case .normal: kind = .normal
            case .slow: kind = .slow
            case .timeout, .none: kind = .timeout
            }
            counts[kind, default: 0] += 1
        }

        self.init(counts: counts, total: group.options.count)
    }
}

struct ProxyLatencyDistributionBucket: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case fast
        case normal
        case slow
        case timeout
        case unavailable
    }

    let kind: Kind
    let count: Int
    let fraction: Double

    var id: String { kind.rawValue }
}

struct ProxyMemberInteractionAvailability: Equatable {
    let canSelect: Bool
    let canTest: Bool
}

struct ProxyMemberMutationTarget: Equatable {
    let groupID: String
    let memberName: String
}

struct ProxyGroupCatalogRecord: Identifiable, Equatable {
    let occurrence: ProxyGroupOccurrence
    let directoryItem: ProxyGroupDirectoryItem
    let searchableText: String

    var id: String { occurrence.id }
}

struct ProxyNodeCatalogRecord: Identifiable, Equatable {
    let row: ProxyNodeRowProjection
    let searchableText: String

    var id: String { row.id }
}

struct ProxyGroupCatalogIndex: Equatable {
    let revision: ProxyCatalogRevision
    let visibilityRawValue: String
    let mode: String
    let arrangedGroups: [ProxyGroupOccurrence]
    let directoryItems: [ProxyGroupDirectoryItem]
    let records: [ProxyGroupCatalogRecord]

    static let empty = ProxyGroupCatalogIndex(
        revision: .zero,
        visibilityRawValue: "",
        mode: "unknown",
        arrangedGroups: [],
        directoryItems: [],
        records: []
    )

    init(
        catalog: PolicyGroupCatalogSnapshot,
        visibility: GlobalGroupVisibility,
        revision: ProxyCatalogRevision = .zero
    ) {
        let arranged = ProxyProjection.arrangedGroups(
            catalog.groups,
            mode: catalog.mode,
            visibility: visibility
        )
        let records = arranged.map { occurrence in
            ProxyGroupCatalogRecord(
                occurrence: occurrence,
                directoryItem: ProxyProjection.directoryItem(
                    for: occurrence
                ),
                searchableText: ProxyProjection.groupSearchText(
                    for: occurrence.group
                )
            )
        }
        self.init(
            revision: revision,
            visibilityRawValue: visibility.rawValue,
            mode: catalog.mode,
            arrangedGroups: arranged,
            directoryItems: records.map(\.directoryItem),
            records: records
        )
    }

    private init(
        revision: ProxyCatalogRevision,
        visibilityRawValue: String,
        mode: String,
        arrangedGroups: [ProxyGroupOccurrence],
        directoryItems: [ProxyGroupDirectoryItem],
        records: [ProxyGroupCatalogRecord]
    ) {
        self.revision = revision
        self.visibilityRawValue = visibilityRawValue
        self.mode = mode
        self.arrangedGroups = arrangedGroups
        self.directoryItems = directoryItems
        self.records = records
    }
}

struct ProxyGroupCatalogProjection: Equatable {
    let mode: String
    let arrangedGroups: [ProxyGroupOccurrence]
    let visibleGroups: [ProxyGroupOccurrence]
    let directoryItems: [ProxyGroupDirectoryItem]
    let visibleDirectoryItems: [ProxyGroupDirectoryItem]

    static let empty = ProxyGroupCatalogProjection(
        index: .empty,
        query: ""
    )

    init(
        catalog: PolicyGroupCatalogSnapshot,
        visibility: GlobalGroupVisibility,
        query: String
    ) {
        self.init(
            index: ProxyGroupCatalogIndex(
                catalog: catalog,
                visibility: visibility
            ),
            query: query
        )
    }

    init(index: ProxyGroupCatalogIndex, query: String) {
        let needle = ProxySearchText.normalize(query)
        mode = index.mode
        arrangedGroups = index.arrangedGroups
        directoryItems = index.directoryItems

        if needle.isEmpty {
            visibleGroups = index.arrangedGroups
            visibleDirectoryItems = index.directoryItems
        } else {
            let visibleRecords = index.records.filter {
                $0.searchableText.contains(needle)
            }
            visibleGroups = visibleRecords.map(\.occurrence)
            visibleDirectoryItems = visibleRecords.map(\.directoryItem)
        }
    }
}

struct ProxyActiveGroupProjection: Equatable {
    let occurrence: ProxyGroupOccurrence?
    let members: [ProxyNodeRowProjection]

    static let empty = ProxyActiveGroupProjection(
        occurrence: nil,
        members: []
    )

    init(
        index: ProxyActiveGroupIndex,
        query: String,
        healthFilter: ProxyHealthFilter = .all
    ) {
        let needle = ProxySearchText.normalize(query)
        occurrence = index.occurrence
        if needle.isEmpty, healthFilter == .all {
            members = index.rows
        } else {
            members = index.records
                .filter { record in
                    (needle.isEmpty || record.searchableText.contains(needle))
                        && healthFilter.includes(record.row)
                }
                .map(\.row)
        }
    }

    private init(
        occurrence: ProxyGroupOccurrence?,
        members: [ProxyNodeRowProjection]
    ) {
        self.occurrence = occurrence
        self.members = members
    }
}

struct ProxyAccessibilityIndex: Equatable {
    struct GroupElement: Identifiable, Equatable {
        let occurrence: ProxyGroupOccurrence
        let item: ProxyGroupDirectoryItem
        let isExpanded: Bool

        var id: String {
            ProxyAccessibilityIndex.groupElementID(occurrence.id)
        }
    }

    struct MemberElement: Identifiable, Equatable {
        let groupOccurrenceID: String
        let groupName: String
        let groupSelectable: Bool
        let member: ProxyNodeRowProjection

        var id: String {
            ProxyProjection.revealTargetID(
                groupID: groupOccurrenceID,
                memberID: member.id
            )
        }
    }

    enum Element: Identifiable, Equatable {
        case group(GroupElement)
        case member(MemberElement)

        var id: String {
            switch self {
            case .group(let group): group.id
            case .member(let member): member.id
            }
        }
    }

    private struct GroupRecord: Equatable {
        let occurrence: ProxyGroupOccurrence
        let item: ProxyGroupDirectoryItem
        let isExpanded: Bool
        let members: [ProxyNodeRowProjection]
        let lowerBound: Int

        var upperBound: Int {
            lowerBound + 1 + members.count
        }
    }

    static let empty = ProxyAccessibilityIndex(
        groups: [],
        directoryItems: [],
        openGroupIDs: [],
        expandedGroups: [:]
    )

    private let groups: [GroupRecord]
    let orderedIDs: [String]
    private let positionsByID: [String: Int]

    var totalCount: Int { orderedIDs.count }

    init(
        groups: [ProxyGroupOccurrence],
        directoryItems: [ProxyGroupDirectoryItem],
        openGroupIDs: [String],
        expandedGroups: [String: ProxyActiveGroupProjection]
    ) {
        let itemsByID = Dictionary(
            uniqueKeysWithValues: directoryItems.map { ($0.id, $0) }
        )
        let openIDs = Set(openGroupIDs)
        var records: [GroupRecord] = []
        records.reserveCapacity(groups.count)
        var orderedIDs: [String] = []
        var positionsByID: [String: Int] = [:]

        for occurrence in groups {
            guard let item = itemsByID[occurrence.id] else { continue }
            let isExpanded = openIDs.contains(occurrence.id)
            let members = isExpanded
                ? expandedGroups[occurrence.id]?.members ?? []
                : []
            let lowerBound = orderedIDs.count
            let groupID = Self.groupElementID(occurrence.id)
            orderedIDs.append(groupID)
            positionsByID[groupID] = lowerBound

            for member in members {
                let memberID = ProxyProjection.revealTargetID(
                    groupID: occurrence.id,
                    memberID: member.id
                )
                positionsByID[memberID] = orderedIDs.count
                orderedIDs.append(memberID)
            }

            records.append(
                GroupRecord(
                    occurrence: occurrence,
                    item: item,
                    isExpanded: isExpanded,
                    members: members,
                    lowerBound: lowerBound
                )
            )
        }

        self.groups = records
        self.orderedIDs = orderedIDs
        self.positionsByID = positionsByID
    }

    func elements(in range: Range<Int>) -> [Element] {
        range.compactMap(element(at:))
    }

    func element(at index: Int) -> Element? {
        guard orderedIDs.indices.contains(index) else { return nil }
        var lower = 0
        var upper = groups.count

        while lower < upper {
            let middle = lower + ((upper - lower) / 2)
            let group = groups[middle]
            if index < group.lowerBound {
                upper = middle
            } else if index >= group.upperBound {
                lower = middle + 1
            } else if index == group.lowerBound {
                return .group(
                    GroupElement(
                        occurrence: group.occurrence,
                        item: group.item,
                        isExpanded: group.isExpanded
                    )
                )
            } else {
                let memberIndex = index - group.lowerBound - 1
                guard group.members.indices.contains(memberIndex) else {
                    return nil
                }
                return .member(
                    MemberElement(
                        groupOccurrenceID: group.occurrence.id,
                        groupName: group.item.groupID,
                        groupSelectable: group.item.selectable,
                        member: group.members[memberIndex]
                    )
                )
            }
        }

        return nil
    }

    func index(of elementID: String) -> Int? {
        positionsByID[elementID]
    }

    func id(at index: Int) -> String? {
        orderedIDs.indices.contains(index) ? orderedIDs[index] : nil
    }

    func selectedElementID(
        activeGroupID: String?,
        selectedMemberID: String?
    ) -> String? {
        guard let activeGroupID else { return nil }
        if let selectedMemberID {
            let memberID = ProxyProjection.revealTargetID(
                groupID: activeGroupID,
                memberID: selectedMemberID
            )
            if positionsByID[memberID] != nil {
                return memberID
            }
        }

        let groupID = Self.groupElementID(activeGroupID)
        return positionsByID[groupID] == nil ? nil : groupID
    }

    static func groupElementID(_ groupID: String) -> String {
        "proxy-group:\(groupID.utf8.count):\(groupID)"
    }
}

struct ProxyActiveGroupIndex: Equatable {
    let revision: ProxyCatalogRevision
    let occurrence: ProxyGroupOccurrence?
    let records: [ProxyNodeCatalogRecord]
    let rows: [ProxyNodeRowProjection]
    let recordsByID: [String: ProxyNodeCatalogRecord]

    static let empty = ProxyActiveGroupIndex(
        revision: .zero,
        occurrence: nil,
        records: [],
        rows: [],
        recordsByID: [:]
    )

    func reconciledSelectionID(_ selectedID: String?) -> String? {
        if let selectedID, recordsByID[selectedID] != nil {
            return selectedID
        }
        return rows.first(where: \.isControllerSelected)?.id ?? rows.first?.id
    }
}

struct ProxyCatalogProjectionWorkCounts: Equatable {
    var catalogIndexBuilds = 0
    var groupRecordsBuilt = 0
    var activeGroupIndexBuilds = 0
    var memberRowsBuilt = 0
}

struct ProxyCatalogProjectionCache {
    private struct CatalogKey: Equatable {
        let revision: ProxyCatalogRevision
        let visibilityRawValue: String
    }

    private struct ActiveGroupKey: Equatable {
        let catalog: CatalogKey
        let groupID: String?
    }

    private var catalogKey: CatalogKey?
    private var activeGroupKey: ActiveGroupKey?
    private var expandedGroupKeys: [String: ActiveGroupKey] = [:]
    private(set) var groupIndex = ProxyGroupCatalogIndex.empty
    private(set) var activeGroupIndex = ProxyActiveGroupIndex.empty
    private var expandedGroupIndexes: [String: ProxyActiveGroupIndex] = [:]
    private(set) var workCounts = ProxyCatalogProjectionWorkCounts()

    @discardableResult
    mutating func updateCatalog(
        _ catalog: PolicyGroupCatalogSnapshot,
        revision: ProxyCatalogRevision,
        visibility: GlobalGroupVisibility
    ) -> Bool {
        let nextKey = CatalogKey(
            revision: revision,
            visibilityRawValue: visibility.rawValue
        )
        guard nextKey != catalogKey else { return false }

        groupIndex = ProxyGroupCatalogIndex(
            catalog: catalog,
            visibility: visibility,
            revision: revision
        )
        catalogKey = nextKey
        activeGroupKey = nil
        activeGroupIndex = .empty
        expandedGroupKeys.removeAll(keepingCapacity: true)
        expandedGroupIndexes.removeAll(keepingCapacity: true)
        workCounts.catalogIndexBuilds += 1
        workCounts.groupRecordsBuilt += groupIndex.records.count
        return true
    }

    func groupProjection(query: String) -> ProxyGroupCatalogProjection {
        ProxyGroupCatalogProjection(index: groupIndex, query: query)
    }

    @discardableResult
    mutating func updateActiveGroup(groupID: String?) -> Bool {
        guard let catalogKey else {
            activeGroupIndex = .empty
            activeGroupKey = nil
            return false
        }
        let nextKey = ActiveGroupKey(
            catalog: catalogKey,
            groupID: groupID
        )
        guard nextKey != activeGroupKey else { return false }

        activeGroupIndex = ProxyProjection.activeGroupIndex(
            in: groupIndex.arrangedGroups,
            groupID: groupID,
            revision: groupIndex.revision
        )
        activeGroupKey = nextKey
        if activeGroupIndex.occurrence != nil {
            workCounts.activeGroupIndexBuilds += 1
            workCounts.memberRowsBuilt += activeGroupIndex.rows.count
        }
        return true
    }

    func activeProjection(query: String) -> ProxyActiveGroupProjection {
        ProxyActiveGroupProjection(index: activeGroupIndex, query: query)
    }

    @discardableResult
    mutating func updateExpandedGroups(groupIDs: [String]) -> Bool {
        guard let catalogKey else {
            let changed = !expandedGroupIndexes.isEmpty
            expandedGroupKeys.removeAll(keepingCapacity: true)
            expandedGroupIndexes.removeAll(keepingCapacity: true)
            return changed
        }

        let requestedIDs = Set(groupIDs)
        var changed = false
        let staleGroupIDs = expandedGroupIndexes.keys.filter {
            !requestedIDs.contains($0)
        }
        for groupID in staleGroupIDs {
            expandedGroupIndexes.removeValue(forKey: groupID)
            expandedGroupKeys.removeValue(forKey: groupID)
            changed = true
        }

        for groupID in groupIDs {
            let nextKey = ActiveGroupKey(
                catalog: catalogKey,
                groupID: groupID
            )
            guard expandedGroupKeys[groupID] != nextKey else { continue }

            let index = ProxyProjection.activeGroupIndex(
                in: groupIndex.arrangedGroups,
                groupID: groupID,
                revision: groupIndex.revision
            )
            guard index.occurrence != nil else {
                expandedGroupIndexes.removeValue(forKey: groupID)
                expandedGroupKeys.removeValue(forKey: groupID)
                changed = true
                continue
            }

            expandedGroupIndexes[groupID] = index
            expandedGroupKeys[groupID] = nextKey
            workCounts.activeGroupIndexBuilds += 1
            workCounts.memberRowsBuilt += index.rows.count
            changed = true
        }
        return changed
    }

    func expandedGroupIndex(for groupID: String) -> ProxyActiveGroupIndex {
        expandedGroupIndexes[groupID] ?? .empty
    }
}

struct ProxyReportedMetadataField: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let value: String

    static func fields(
        in metadata: [String: MihomoJSONValue]
    ) -> [ProxyReportedMetadataField] {
        metadata
            .sorted { $0.key < $1.key }
            .compactMap { key, value in
                guard let text = displayText(for: value) else { return nil }
                return ProxyReportedMetadataField(key: key, value: text)
            }
    }

    private static func displayText(for value: MihomoJSONValue) -> String? {
        switch value {
        case .string(let text):
            return text.isEmpty ? "\"\"" : text
        case .number(let number):
            guard number.isFinite else { return String(number) }
            if number.rounded() == number,
               number >= Double(Int64.min),
               number <= Double(Int64.max) {
                return String(Int64(number))
            }
            return String(number)
        case .bool(let enabled):
            return String(enabled)
        case .null:
            return "null"
        case .object, .array:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}

struct ProxyMemberDetailProjection: Equatable {
    let alive: Bool?
    let fixed: String?
    let history: [ProxyDelayHistorySnapshot]?
    let latestHistoryDelay: Int?
    let latestHistoryTime: String?
    let reportedFields: [ProxyReportedMetadataField]

    init(detail: ProxyNodeViewState?) {
        alive = detail?.alive
        fixed = detail?.fixed
        history = detail?.history
        latestHistoryDelay = detail?.latestHistoryDelay
        latestHistoryTime = detail?.latestHistoryTime
        reportedFields = ProxyReportedMetadataField.fields(
            in: detail?.reportedMetadata ?? [:]
        )
    }

    func availabilityText(language: AppLanguage) -> String {
        guard let alive else { return unavailableText(language: language) }
        return MicaStrings.localizedKey(
            alive ? "routing.node_alive" : "routing.node_unavailable",
            language: language
        )
    }

    func fixedSelectionText(language: AppLanguage) -> String {
        fixed?.proxyNonBlank ?? unavailableText(language: language)
    }

    func historySummaryText(language: AppLanguage) -> String {
        guard let history, !history.isEmpty else {
            return unavailableText(language: language)
        }

        let delay = latestHistoryDelay.map(OverviewFormat.latency)
            ?? unavailableText(language: language)
        let time = latestHistoryTime?.proxyNonBlank
            ?? unavailableText(language: language)
        return MicaStrings.localized(
            "routing.history_summary \(history.count) \(delay) \(time)",
            language: language
        )
    }

    private func unavailableText(language: AppLanguage) -> String {
        MicaStrings.localizedKey(
            "routing.node_unavailable",
            language: language
        )
    }
}

struct ProxyWorkspaceReconciliationResult: Equatable {
    let workspace: WorkbenchDestinationWorkspace
    let inspectedMemberCount: Int
}

enum ProxyWorkspaceProjection {
    static func reconciled(
        _ workspace: WorkbenchDestinationWorkspace,
        groups: [ProxyGroupOccurrence]
    ) -> WorkbenchDestinationWorkspace {
        reconciliation(workspace, groups: groups).workspace
    }

    static func reconciliation(
        _ workspace: WorkbenchDestinationWorkspace,
        groups: [ProxyGroupOccurrence]
    ) -> ProxyWorkspaceReconciliationResult {
        var next = workspace
        let orderedIDs = groups.map(\.id)
        let validIDs = Set(orderedIDs)
        let requestedOpenIDs = Set(workspace.openGroupIDs)

        next.openGroupIDs = orderedIDs.filter(requestedOpenIDs.contains)
        if let activeGroupID = workspace.activeGroupID,
           next.openGroupIDs.contains(activeGroupID) {
            next.activeGroupID = activeGroupID
        } else {
            next.activeGroupID = next.openGroupIDs.first
        }

        next.groupFilters = workspace.groupFilters.filter {
            validIDs.contains($0.key)
        }
        var selectedGroupMemberIDs = workspace.selectedGroupMemberIDs.filter {
            validIDs.contains($0.key)
        }
        var inspectedMemberCount = 0
        var staleSelectionGroupIDs: [String] = []
        for (groupID, selectedID) in selectedGroupMemberIDs {
            guard let occurrence = groups.first(where: { $0.id == groupID }) else {
                staleSelectionGroupIDs.append(groupID)
                continue
            }
            let resolution = ProxyProjection.memberResolution(
                memberID: selectedID,
                in: occurrence.group
            )
            inspectedMemberCount += resolution.inspectedCount
            if resolution.member == nil {
                staleSelectionGroupIDs.append(groupID)
            }
        }
        for groupID in staleSelectionGroupIDs {
            selectedGroupMemberIDs.removeValue(forKey: groupID)
        }
        next.selectedGroupMemberIDs = selectedGroupMemberIDs
        return ProxyWorkspaceReconciliationResult(
            workspace: next,
            inspectedMemberCount: inspectedMemberCount
        )
    }

    static func opening(
        _ groupID: String,
        in workspace: WorkbenchDestinationWorkspace,
        groups: [ProxyGroupOccurrence],
        preferredMemberID: String?
    ) -> WorkbenchDestinationWorkspace {
        guard let occurrence = groups.first(where: { $0.id == groupID }) else {
            return reconciled(workspace, groups: groups)
        }

        var next = reconciled(workspace, groups: groups)
        let requested = Set(next.openGroupIDs).union([groupID])
        next.openGroupIDs = groups.map(\.id).filter(requested.contains)
        next.activeGroupID = groupID
        if let selectedID = next.selectedGroupMemberIDs[groupID],
           ProxyProjection.memberResolution(
               memberID: selectedID,
               in: occurrence.group
           ).member == nil {
            next.selectedGroupMemberIDs.removeValue(forKey: groupID)
        }
        if next.selectedGroupMemberIDs[groupID] == nil,
           let preferredMemberID {
            next.selectedGroupMemberIDs[groupID] = preferredMemberID
        }
        return next
    }

    static func closingInspector(
        for groupID: String,
        in workspace: WorkbenchDestinationWorkspace
    ) -> WorkbenchDestinationWorkspace {
        var next = workspace
        next.selectedGroupMemberIDs.removeValue(forKey: groupID)
        return next
    }

    static func closing(
        _ groupID: String,
        in workspace: WorkbenchDestinationWorkspace,
        groups: [ProxyGroupOccurrence]
    ) -> WorkbenchDestinationWorkspace {
        var next = reconciled(workspace, groups: groups)
        guard let closingIndex = next.openGroupIDs.firstIndex(of: groupID) else {
            return next
        }

        let wasActive = next.activeGroupID == groupID
        next.openGroupIDs.remove(at: closingIndex)
        if wasActive {
            if closingIndex < next.openGroupIDs.count {
                next.activeGroupID = next.openGroupIDs[closingIndex]
            } else {
                next.activeGroupID = next.openGroupIDs.last
            }
        }
        _ = reconcileActiveSelection(in: &next, groups: groups)
        return next
    }

    static func openGroups(
        _ openGroupIDs: [String],
        in groups: [ProxyGroupDirectoryItem]
    ) -> [ProxyGroupDirectoryItem] {
        let openIDs = Set(openGroupIDs)
        return groups.filter { openIDs.contains($0.id) }
    }

    private static func reconcileActiveSelection(
        in workspace: inout WorkbenchDestinationWorkspace,
        groups: [ProxyGroupOccurrence]
    ) -> Int {
        guard let activeGroupID = workspace.activeGroupID,
              let selectedID = workspace.selectedGroupMemberIDs[activeGroupID],
              let occurrence = groups.first(where: { $0.id == activeGroupID }) else {
            return 0
        }

        let resolution = ProxyProjection.memberResolution(
            memberID: selectedID,
            in: occurrence.group
        )
        if resolution.member == nil {
            workspace.selectedGroupMemberIDs.removeValue(forKey: activeGroupID)
        }
        return resolution.inspectedCount
    }
}

struct ProxyMemberResolution: Equatable {
    let member: ProxyMemberOccurrence?
    let inspectedCount: Int
}

enum ProxyProjection {
    static func navigationSelection(
        controllerID: RouterProfile.ID,
        generation: UUID,
        groupOccurrenceID: String,
        nodeName: String
    ) -> WorkbenchProxyNavigationSelection? {
        guard !groupOccurrenceID.isEmpty,
              nodeName.proxyNonBlank != nil else {
            return nil
        }
        return WorkbenchProxyNavigationSelection(
            controllerID: controllerID,
            generation: generation,
            groupOccurrenceID: groupOccurrenceID,
            nodeName: nodeName
        )
    }

    static func memberInteractions(
        in group: ProxyGroupViewState,
        selectionActionAvailable: Bool,
        testActionAvailable: Bool
    ) -> ProxyMemberInteractionAvailability {
        ProxyMemberInteractionAvailability(
            canSelect: selectionActionAvailable && group.selectable,
            canTest: testActionAvailable
        )
    }

    static func arrangedGroups(
        _ groups: [ProxyGroupViewState],
        mode: String,
        visibility: GlobalGroupVisibility
    ) -> [ProxyGroupOccurrence] {
        let occurrences = occurrences(in: groups)
        let globalGroups = occurrences.filter {
            $0.group.id.caseInsensitiveCompare("GLOBAL") == .orderedSame
        }
        let peers = occurrences.filter {
            $0.group.id.caseInsensitiveCompare("GLOBAL") != .orderedSame
        }

        let showsGlobal = visibility == .alwaysShow
            || mode.caseInsensitiveCompare("Global") == .orderedSame
        return showsGlobal ? peers + globalGroups : peers
    }

    static func filteredGroups(
        _ groups: [ProxyGroupOccurrence],
        query: String
    ) -> [ProxyGroupOccurrence] {
        let needle = ProxySearchText.normalize(query)
        guard !needle.isEmpty else { return groups }
        return groups.filter { groupSearchText(for: $0.group).contains(needle) }
    }

    static func members(
        in group: ProxyGroupViewState,
        query: String
    ) -> [ProxyMemberOccurrence] {
        let needle = ProxySearchText.normalize(query)
        let members = memberOccurrences(in: group)
        guard !needle.isEmpty else { return members }

        return members.filter { member in
            ProxySearchText.normalize(member.name).contains(needle)
                || group.detail(for: member.name)?.searchableText.contains(needle) == true
        }
    }

    static func activeGroupIndex(
        in groups: [ProxyGroupOccurrence],
        groupID: String?,
        revision: ProxyCatalogRevision = .zero
    ) -> ProxyActiveGroupIndex {
        guard let groupID,
              let occurrence = groups.first(where: { $0.id == groupID }) else {
            return ProxyActiveGroupIndex(
                revision: revision,
                occurrence: nil,
                records: [],
                rows: [],
                recordsByID: [:]
            )
        }

        let baseRows = memberOccurrences(in: occurrence.group).map { member in
            let detail = occurrence.group.detail(for: member.name)
            let reportedDelay = occurrence.group.delays[member.name]
                ?? detail?.latestHistoryDelay
            let displayDelay = reportedDelay.flatMap { $0 > 0 ? $0 : nil }
            return ProxyNodeRowProjection(
                id: member.id,
                name: member.name,
                occurrence: member.occurrence,
                type: detail?.type,
                providerName: detail?.providerName,
                transportNames: detail?.transportNames ?? [],
                delay: displayDelay,
                latencyFraction: nil,
                alive: detail?.alive,
                health: ProxyNodeHealthState.classify(
                    alive: detail?.alive,
                    delay: reportedDelay
                ),
                usageRank: occurrence.group.usageRank(for: member.name),
                isControllerSelected: occurrence.group.selected == member.name
            )
        }
        let latencyScale = ProxyLatencyScale(
            delays: baseRows.map(\.delay)
        )
        let records = baseRows.map { base in
            let row = ProxyNodeRowProjection(
                id: base.id,
                name: base.name,
                occurrence: base.occurrence,
                type: base.type,
                providerName: base.providerName,
                transportNames: base.transportNames,
                delay: base.delay,
                latencyFraction: latencyScale.fraction(for: base.delay),
                alive: base.alive,
                health: base.health,
                usageRank: base.usageRank,
                isControllerSelected: base.isControllerSelected
            )
            return ProxyNodeCatalogRecord(
                row: row,
                searchableText: occurrence.group.detail(
                    for: base.name
                )?.searchableText
                    ?? ProxySearchText.normalize(base.name)
            )
        }

        return ProxyActiveGroupIndex(
            revision: revision,
            occurrence: occurrence,
            records: records,
            rows: records.map(\.row),
            recordsByID: Dictionary(
                uniqueKeysWithValues: records.map { ($0.id, $0) }
            )
        )
    }

    static func activeGroup(
        in groups: [ProxyGroupOccurrence],
        groupID: String?,
        query: String
    ) -> ProxyActiveGroupProjection {
        ProxyActiveGroupProjection(
            index: activeGroupIndex(
                in: groups,
                groupID: groupID
            ),
            query: query
        )
    }

    static func filteredRows(
        _ rows: [ProxyNodeRowProjection],
        healthFilter: ProxyHealthFilter
    ) -> [ProxyNodeRowProjection] {
        rows.filter(healthFilter.includes)
    }

    static func resolveNavigationTarget(
        groupOccurrenceID: String,
        nodeName: String,
        catalog: PolicyGroupCatalogSnapshot,
        visibility: GlobalGroupVisibility
    ) -> ProxyNavigationTargetResolution {
        guard !catalog.groups.isEmpty else {
            return ProxyNavigationTargetResolution(
                status: .emptyCatalog,
                occurrence: nil,
                member: nil,
                row: nil
            )
        }

        let completeGroups = arrangedGroups(
            catalog.groups,
            mode: catalog.mode,
            visibility: .alwaysShow
        )
        let complete = resolveNavigationTarget(
            groupID: groupOccurrenceID,
            nodeName: nodeName,
            in: completeGroups
        )
        guard complete.isResolved,
              complete.occurrence?.group.id
                  .caseInsensitiveCompare("GLOBAL") == .orderedSame else {
            return complete
        }

        let visibleGroups = arrangedGroups(
            catalog.groups,
            mode: catalog.mode,
            visibility: visibility
        )
        let visible = resolveNavigationTarget(
            groupID: groupOccurrenceID,
            nodeName: nodeName,
            in: visibleGroups
        )
        guard !visible.isResolved else { return visible }
        return ProxyNavigationTargetResolution(
            status: .hiddenGlobal,
            occurrence: complete.occurrence,
            member: complete.member,
            row: complete.row
        )
    }

    static func resolveNavigationTarget(
        groupID: String,
        nodeName: String,
        in groups: [ProxyGroupOccurrence]
    ) -> ProxyNavigationTargetResolution {
        let matchingOccurrences: [ProxyGroupOccurrence]
        if let exactOccurrence = groups.first(where: { $0.id == groupID }) {
            matchingOccurrences = [exactOccurrence]
        } else {
            matchingOccurrences = groups.filter { $0.group.id == groupID }
        }
        guard !matchingOccurrences.isEmpty else {
            return ProxyNavigationTargetResolution(
                status: .missingGroup,
                occurrence: nil,
                member: nil,
                row: nil
            )
        }
        guard matchingOccurrences.count == 1,
              let occurrence = matchingOccurrences.first else {
            return ProxyNavigationTargetResolution(
                status: .ambiguousGroup,
                occurrence: nil,
                member: nil,
                row: nil
            )
        }

        guard let member = memberOccurrences(in: occurrence.group)
            .first(where: { $0.name == nodeName }) else {
            return ProxyNavigationTargetResolution(
                status: .missingNode,
                occurrence: occurrence,
                member: nil,
                row: nil
            )
        }

        let index = activeGroupIndex(
            in: [occurrence],
            groupID: occurrence.id
        )
        return ProxyNavigationTargetResolution(
            status: .resolved,
            occurrence: occurrence,
            member: member,
            row: index.recordsByID[member.id]?.row
        )
    }

    static func revealTargetID(groupID: String, memberID: String) -> String {
        let group = "\(groupID.utf8.count):\(groupID)"
        let member = "\(memberID.utf8.count):\(memberID)"
        return "proxy-node:\(group):\(member)"
    }

    static func preferredMemberID(in group: ProxyGroupViewState) -> String? {
        var counts: [String: Int] = [:]
        var firstMemberID: String?

        for name in group.options {
            let occurrence = counts[name, default: 0]
            counts[name] = occurrence + 1
            let member = ProxyMemberOccurrence(
                name: name,
                occurrence: occurrence
            )
            if firstMemberID == nil {
                firstMemberID = member.id
            }
            if name == group.selected {
                return member.id
            }
        }
        return firstMemberID
    }

    static func memberMutationTarget(
        groupID: String,
        memberID: String,
        index: ProxyActiveGroupIndex,
        actionAvailable: Bool,
        requiresSelectableGroup: Bool
    ) -> ProxyMemberMutationTarget? {
        guard actionAvailable,
              let occurrence = index.occurrence,
              occurrence.id == groupID,
              !requiresSelectableGroup || occurrence.group.selectable,
              let record = index.recordsByID[memberID] else {
            return nil
        }

        return ProxyMemberMutationTarget(
            groupID: occurrence.group.id,
            memberName: record.row.name
        )
    }

    static func currentMemberMutationTarget(
        groupID: String,
        memberID: String,
        index: ProxyActiveGroupIndex,
        selectedControllerID: RouterProfile.ID?,
        sessionControllerID: RouterProfile.ID?,
        generation: UUID,
        actionAvailable: Bool,
        requiresSelectableGroup: Bool
    ) -> ProxyMemberMutationTarget? {
        guard index.revision.isCurrent(
            selectedControllerID: selectedControllerID,
            sessionControllerID: sessionControllerID,
            generation: generation
        ) else {
            return nil
        }
        return memberMutationTarget(
            groupID: groupID,
            memberID: memberID,
            index: index,
            actionAvailable: actionAvailable,
            requiresSelectableGroup: requiresSelectableGroup
        )
    }

    static func memberMutationTarget(
        groupID: String,
        memberID: String,
        groups: [ProxyGroupOccurrence],
        actionAvailable: Bool,
        requiresSelectableGroup: Bool
    ) -> ProxyMemberMutationTarget? {
        guard actionAvailable,
              let occurrence = groups.first(where: { $0.id == groupID }),
              !requiresSelectableGroup || occurrence.group.selectable,
              let member = memberResolution(
                memberID: memberID,
                in: occurrence.group
              ).member else {
            return nil
        }

        return ProxyMemberMutationTarget(
            groupID: occurrence.group.id,
            memberName: member.name
        )
    }

    static func memberResolution(
        memberID: String,
        in group: ProxyGroupViewState
    ) -> ProxyMemberResolution {
        var counts: [String: Int] = [:]
        var inspectedCount = 0

        for name in group.options {
            inspectedCount += 1
            let occurrence = counts[name, default: 0]
            counts[name] = occurrence + 1
            let member = ProxyMemberOccurrence(
                name: name,
                occurrence: occurrence
            )
            if member.id == memberID {
                return ProxyMemberResolution(
                    member: member,
                    inspectedCount: inspectedCount
                )
            }
        }

        return ProxyMemberResolution(
            member: nil,
            inspectedCount: inspectedCount
        )
    }

    static func directoryItem(
        for occurrence: ProxyGroupOccurrence
    ) -> ProxyGroupDirectoryItem {
        let health = ProxyGroupHealthSummary(group: occurrence.group)
        return ProxyGroupDirectoryItem(
            key: occurrence.key,
            groupID: occurrence.group.id,
            type: occurrence.group.type,
            selected: occurrence.group.selected,
            memberCount: occurrence.group.options.count,
            selectedDelay: (
                occurrence.group.delays[occurrence.group.selected]
                    ?? occurrence.group.detail(
                        for: occurrence.group.selected
                    )?.latestHistoryDelay
            ).flatMap { $0 > 0 ? $0 : nil },
            availableMemberCount: health.availableCount,
            latencyDistribution: health.latencyDistribution,
            health: health,
            hidden: occurrence.group.hidden,
            selectable: occurrence.group.selectable,
            hasFixedSelection: occurrence.group.details?.fixed?.proxyNonBlank != nil,
            reportedUsageRanks: reportedUsageRanks(in: occurrence.group)
        )
    }

    static func reportedUsageRanks(
        in group: ProxyGroupViewState
    ) -> [PolicyGroupUsageRank] {
        var result: [PolicyGroupUsageRank] = []
        for member in group.options {
            guard let rank = group.usageRank(for: member),
                  !result.contains(rank) else { continue }
            result.append(rank)
        }
        return result
    }

    static func groupSearchText(for group: ProxyGroupViewState) -> String {
        var values = [
            ProxySearchText.normalize(group.id),
            ProxySearchText.normalize(group.type),
            ProxySearchText.normalize(group.selected),
        ]
        values.reserveCapacity(values.count + (group.options.count * 2))

        for member in group.options {
            values.append(ProxySearchText.normalize(member))
            if let detail = group.detail(for: member) {
                values.append(detail.searchableText)
            }
        }
        return values.joined(separator: " ")
    }

    private static func occurrences(
        in groups: [ProxyGroupViewState]
    ) -> [ProxyGroupOccurrence] {
        var counts: [String: Int] = [:]

        return groups.map { group in
            let occurrence = counts[group.id, default: 0]
            counts[group.id] = occurrence + 1
            return ProxyGroupOccurrence(
                key: ProxyGroupKey(
                    groupID: group.id,
                    occurrence: occurrence
                ),
                group: group
            )
        }
    }

    private static func memberOccurrences(
        in group: ProxyGroupViewState
    ) -> [ProxyMemberOccurrence] {
        var counts: [String: Int] = [:]

        return group.options.map { name in
            let occurrence = counts[name, default: 0]
            counts[name] = occurrence + 1
            return ProxyMemberOccurrence(
                name: name,
                occurrence: occurrence
            )
        }
    }
}

extension String {
    var proxyNonBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
