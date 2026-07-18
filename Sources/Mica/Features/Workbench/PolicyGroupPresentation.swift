import Foundation

/// Local workbench state for policy browsing. Controller snapshots remain the source
/// of order and policy truth; this state only remembers a selected identity.
struct PolicyGroupPresentation: Equatable {
    private(set) var selectedPolicyGroupID: ProxyGroupViewState.ID?

    mutating func select(_ groupID: ProxyGroupViewState.ID) {
        selectedPolicyGroupID = groupID
    }

    mutating func reset() {
        selectedPolicyGroupID = nil
    }

    mutating func reconcile(with groups: [ProxyGroupViewState]) {
        guard let selectedPolicyGroupID,
              groups.contains(where: { $0.id == selectedPolicyGroupID }) else {
            self.selectedPolicyGroupID = groups.first?.id
            return
        }
    }

    func selectedGroup(in groups: [ProxyGroupViewState]) -> ProxyGroupViewState? {
        guard let selectedPolicyGroupID else {
            return nil
        }
        return groups.first(where: { $0.id == selectedPolicyGroupID })
    }

    static func filteredGroups(
        _ groups: [ProxyGroupViewState],
        matching query: String
    ) -> [ProxyGroupViewState] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return groups
        }

        return groups.filter { group in
            group.id.localizedCaseInsensitiveContains(query)
                || group.type.localizedCaseInsensitiveContains(query)
                || group.selected.localizedCaseInsensitiveContains(query)
                || group.options.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    static func filteredOptions(
        _ options: [String],
        matching query: String
    ) -> [String] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return options
        }

        return options.filter { option in
            option.localizedCaseInsensitiveContains(query)
        }
    }

    static func filteredOptions(
        in group: ProxyGroupViewState,
        matching query: String
    ) -> [String] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return group.options
        }

        return group.options.filter { option in
            option.localizedCaseInsensitiveContains(query)
                || group.detail(for: option)?.searchableText.localizedCaseInsensitiveContains(query) == true
        }
    }

    /// The mihomo identity of the GLOBAL policy group.
    static let globalGroupID = "GLOBAL"

    /// Arranges already-filtered groups for display: applies GLOBAL visibility and,
    /// when GLOBAL is shown, places it after every peer group. Every other group keeps
    /// its exact controller order. This never sorts; it only partitions GLOBAL out and
    /// appends it, so `proxyOrder` remains untouched for all peer groups.
    ///
    /// - Parameters:
    ///   - groups: already `filteredGroups(_:matching:)` output (controller order).
    ///   - mode: the controller's reported display mode (e.g. "Global"/"Rule"/"Direct").
    ///   - visibility: user preference for GLOBAL visibility.
    static func arrangedGroups(
        _ groups: [ProxyGroupViewState],
        mode: String,
        visibility: GlobalGroupVisibility
    ) -> [ProxyGroupViewState] {
        let isGlobalMode = mode.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "global"
        let showGlobal = visibility == .alwaysShow || (visibility == .followMode && isGlobalMode)

        let globalGroups = groups.filter { $0.id == globalGroupID }
        let otherGroups = groups.filter { $0.id != globalGroupID }

        guard showGlobal, !globalGroups.isEmpty else {
            return otherGroups
        }

        return otherGroups + globalGroups
    }
}
