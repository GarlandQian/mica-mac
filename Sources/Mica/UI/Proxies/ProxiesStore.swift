import Foundation
import MicaCore

enum ProxyFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case available
    case slow
    case unavailable

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: "routing.health_filter_all"
        case .available: "diagnostics.available_now"
        case .slow: "routing.health_filter_slow"
        case .unavailable: "routing.health_filter_unavailable"
        }
    }
}

enum ProxySortOrder: String, CaseIterable, Identifiable, Sendable {
    case defaultOrder
    case latencyAscending
    case nameAscending

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .defaultOrder: "routing.source_order"
        case .latencyAscending: "routing.order_latency"
        case .nameAscending: "action.copy_name"
        }
    }
}

enum ProxyLayoutMode: String, CaseIterable, Identifiable, Sendable {
    case grid
    case list

    var id: String { rawValue }
}

struct ProxyGroupSummary: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let type: String
    let selected: String
    let nodeCount: Int
    let availableCount: Int
    let selectedDelay: Int?
    let selectable: Bool
    let hasFixedSelection: Bool
}

struct ProxyNodeCardModel: Identifiable, Equatable, Sendable {
    let id: String
    let groupID: String
    let name: String
    let type: String?
    let providerName: String?
    let delay: Int?
    let alive: Bool?
    let isSelected: Bool
    let searchableLowercased: String

    var isUnavailable: Bool {
        if alive == false { return true }
        if let delay, delay <= 0 { return true }
        return false
    }

    var isSlow: Bool {
        !isUnavailable && (delay ?? 0) >= 180
    }

    var isAvailable: Bool {
        !isUnavailable && (delay.map { $0 > 0 } ?? (alive == true))
    }
}

/// Lean UI store for Proxies: projects groups and active group's nodes only when
/// `policyGroupCatalogRevision` or filter/sort inputs change.
@MainActor
@Observable
final class ProxiesStore {
    private static let layoutDefaultsKey = "mica.proxies.layoutMode"
    private static let sortDefaultsKey = "mica.proxies.sortOrder"

    private(set) var groups: [ProxyGroupSummary] = []
    private(set) var rawGroups: [ProxyGroupViewState] = []
    private(set) var visibleNodes: [ProxyNodeCardModel] = []

    var selectedGroupID: String? {
        didSet {
            guard oldValue != selectedGroupID else { return }
            rebuildVisibleNodes()
        }
    }

    var filter: ProxyFilter = .all {
        didSet {
            guard oldValue != filter else { return }
            rebuildVisibleNodes()
        }
    }

    var sortOrder: ProxySortOrder {
        didSet {
            guard oldValue != sortOrder else { return }
            userDefaults.set(sortOrder.rawValue, forKey: Self.sortDefaultsKey)
            rebuildVisibleNodes()
        }
    }

    var layoutMode: ProxyLayoutMode {
        didSet {
            guard oldValue != layoutMode else { return }
            userDefaults.set(layoutMode.rawValue, forKey: Self.layoutDefaultsKey)
        }
    }

    var searchQuery: String = "" {
        didSet {
            guard oldValue != searchQuery else { return }
            rebuildVisibleNodes()
        }
    }

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var lastRevision: UInt64?
    @ObservationIgnored private var lastVisibility: GlobalGroupVisibility?
    @ObservationIgnored private var lastMode: String?
    @ObservationIgnored private var lastControllerID: RouterProfile.ID?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.layoutMode = ProxyLayoutMode(rawValue: userDefaults.string(forKey: Self.layoutDefaultsKey) ?? "") ?? .grid
        self.sortOrder = ProxySortOrder(rawValue: userDefaults.string(forKey: Self.sortDefaultsKey) ?? "") ?? .defaultOrder
    }

    var activeGroupSummary: ProxyGroupSummary? {
        guard let selectedGroupID else { return groups.first }
        return groups.first { $0.id == selectedGroupID } ?? groups.first
    }

    var activeRawGroup: ProxyGroupViewState? {
        guard let activeID = activeGroupSummary?.id else { return nil }
        return rawGroups.first { $0.id == activeID }
    }

    func sync(
        catalog: PolicyGroupCatalogSnapshot,
        revision: UInt64,
        visibility: GlobalGroupVisibility,
        controllerID: RouterProfile.ID?,
        preferredGroupID: String? = nil
    ) {
        if lastControllerID != controllerID {
            lastControllerID = controllerID
            lastRevision = nil
            lastVisibility = nil
            lastMode = nil
            selectedGroupID = nil
        }

        if let preferredGroupID,
           groups.contains(where: { $0.id == preferredGroupID }) {
            selectedGroupID = preferredGroupID
        }

        guard lastRevision != revision || lastVisibility != visibility || lastMode != catalog.mode else {
            return
        }

        lastRevision = revision
        lastVisibility = visibility
        lastMode = catalog.mode

        let arranged = Self.arrangedGroups(from: catalog, visibility: visibility)
        rawGroups = arranged
        groups = arranged.map { group in
            let available = group.options.reduce(into: 0) { count, option in
                let delay = group.delays[option] ?? group.optionDetails[option]?.latestHistoryDelay
                let alive = group.optionDetails[option]?.alive
                if alive != false, let delay, delay > 0 {
                    count += 1
                }
            }
            let selectedDelay = group.delays[group.selected]
                ?? group.optionDetails[group.selected]?.latestHistoryDelay
            return ProxyGroupSummary(
                id: group.id,
                name: group.id,
                type: group.type,
                selected: group.selected,
                nodeCount: group.options.count,
                availableCount: available,
                selectedDelay: selectedDelay,
                selectable: group.selectable,
                hasFixedSelection: group.details?.fixed?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            )
        }

        if let preferredGroupID, groups.contains(where: { $0.id == preferredGroupID }) {
            selectedGroupID = preferredGroupID
        } else if let current = selectedGroupID, groups.contains(where: { $0.id == current }) {
            rebuildVisibleNodes()
        } else {
            selectedGroupID = groups.first?.id
        }
    }

    private func rebuildVisibleNodes() {
        guard let group = activeRawGroup else {
            if !visibleNodes.isEmpty { visibleNodes = [] }
            return
        }

        var mapped: [ProxyNodeCardModel] = []
        mapped.reserveCapacity(group.options.count)

        let normalizedQuery = searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        for option in group.options {
            let detail = group.optionDetails[option]
            let delay = group.delays[option] ?? detail?.latestHistoryDelay
            let searchable = [option, detail?.type, detail?.providerName]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()

            let card = ProxyNodeCardModel(
                id: "\(group.id)::\(option)",
                groupID: group.id,
                name: option,
                type: detail?.type,
                providerName: detail?.providerName,
                delay: delay,
                alive: detail?.alive,
                isSelected: option == group.selected,
                searchableLowercased: searchable
            )

            switch filter {
            case .all:
                break
            case .available:
                guard card.isAvailable else { continue }
            case .slow:
                guard card.isSlow else { continue }
            case .unavailable:
                guard card.isUnavailable else { continue }
            }

            if !normalizedQuery.isEmpty, !card.searchableLowercased.contains(normalizedQuery) {
                continue
            }

            mapped.append(card)
        }

        switch sortOrder {
        case .defaultOrder:
            break
        case .latencyAscending:
            mapped.sort { lhs, rhs in
                let lVal = Self.sortableLatency(for: lhs)
                let rVal = Self.sortableLatency(for: rhs)
                if lVal != rVal { return lVal < rVal }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        case .nameAscending:
            mapped.sort {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }

        if mapped != visibleNodes {
            visibleNodes = mapped
        }
    }

    private static func sortableLatency(for node: ProxyNodeCardModel) -> Int {
        guard !node.isUnavailable, let delay = node.delay, delay > 0 else {
            return Int.max
        }
        return delay
    }

    /// Arranges policy groups identically for Proxies, Overview, and Menu Bar.
    nonisolated static func arrangedGroups(
        from catalog: PolicyGroupCatalogSnapshot,
        visibility: GlobalGroupVisibility
    ) -> [ProxyGroupViewState] {
        let isGlobalMode = catalog.mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "global"
        var nonGlobal: [ProxyGroupViewState] = []
        var globalGroups: [ProxyGroupViewState] = []

        for group in catalog.groups where !group.hidden {
            if group.id.caseInsensitiveCompare("GLOBAL") == .orderedSame {
                if visibility == .alwaysShow || isGlobalMode {
                    globalGroups.append(group)
                }
            } else {
                nonGlobal.append(group)
            }
        }

        return nonGlobal + globalGroups
    }
}
