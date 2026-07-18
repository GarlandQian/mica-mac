import Foundation
import MicaCore
import Observation
import SwiftUI

struct PolicyGroupControllerInteractionState: Equatable {
    static let memberWindowSize = 48

    private(set) var expandedGroupIDs: Set<String> = []
    private(set) var memberFilterTextByGroup: [String: String] = [:]
    private(set) var memberLimitByGroup: [String: Int] = [:]

    init(expandedGroupIDs: Set<String> = []) {
        self.expandedGroupIDs = expandedGroupIDs
    }

    mutating func setExpanded(_ expanded: Bool, groupID: String) {
        if expanded {
            expandedGroupIDs.insert(groupID)
        } else {
            expandedGroupIDs.remove(groupID)
            memberFilterTextByGroup.removeValue(forKey: groupID)
        }
    }

    mutating func setFilterText(_ text: String, groupID: String) {
        if text.isEmpty {
            memberFilterTextByGroup.removeValue(forKey: groupID)
        } else {
            memberFilterTextByGroup[groupID] = text
        }
    }

    func filterText(for groupID: String) -> String {
        memberFilterTextByGroup[groupID] ?? ""
    }

    mutating func showMoreMembers(groupID: String, totalCount: Int) {
        guard totalCount > 0 else { return }

        let currentLimit = memberLimit(for: groupID, totalCount: totalCount)
        memberLimitByGroup[groupID] = min(
            totalCount,
            currentLimit + Self.memberWindowSize
        )
    }

    func visibleOptions(_ options: [String], groupID: String) -> [String] {
        Array(options.prefix(memberLimit(for: groupID, totalCount: options.count)))
    }

    func hasMoreOptions(_ options: [String], groupID: String) -> Bool {
        memberLimit(for: groupID, totalCount: options.count) < options.count
    }

    mutating func pruneGroups(keeping validGroupIDs: Set<String>) {
        expandedGroupIDs.formIntersection(validGroupIDs)
        memberFilterTextByGroup = memberFilterTextByGroup.reduce(into: [:]) { result, entry in
            guard validGroupIDs.contains(entry.key) else { return }
            result[entry.key] = entry.value
        }
        memberLimitByGroup = memberLimitByGroup.reduce(into: [:]) { result, entry in
            guard validGroupIDs.contains(entry.key) else { return }
            result[entry.key] = entry.value
        }
    }

    private func memberLimit(for groupID: String, totalCount: Int) -> Int {
        guard totalCount > Self.memberWindowSize else {
            return max(0, totalCount)
        }

        let storedLimit = memberLimitByGroup[groupID]
            ?? Self.memberWindowSize
        return min(
            max(storedLimit, Self.memberWindowSize),
            totalCount
        )
    }
}

struct PolicyGroupRuntimeState: Equatable {
    private var statesByControllerID: [String: PolicyGroupControllerInteractionState] = [:]

    mutating func ensureController(
        _ controllerID: String,
        restoredExpandedGroupIDs: Set<String> = []
    ) {
        guard statesByControllerID[controllerID] == nil else { return }
        statesByControllerID[controllerID] = PolicyGroupControllerInteractionState(
            expandedGroupIDs: restoredExpandedGroupIDs
        )
    }

    func hasController(_ controllerID: String) -> Bool {
        statesByControllerID[controllerID] != nil
    }

    func expandedGroupIDs(for controllerID: String) -> Set<String> {
        statesByControllerID[controllerID]?.expandedGroupIDs ?? []
    }

    func isExpanded(_ groupID: String, controllerID: String) -> Bool {
        expandedGroupIDs(for: controllerID).contains(groupID)
    }

    mutating func setExpanded(
        _ expanded: Bool,
        groupID: String,
        controllerID: String
    ) {
        ensureController(controllerID)
        statesByControllerID[controllerID]?.setExpanded(expanded, groupID: groupID)
    }

    func filterText(groupID: String, controllerID: String) -> String {
        statesByControllerID[controllerID]?.filterText(for: groupID) ?? ""
    }

    mutating func setFilterText(
        _ text: String,
        groupID: String,
        controllerID: String
    ) {
        ensureController(controllerID)
        statesByControllerID[controllerID]?.setFilterText(text, groupID: groupID)
    }

    mutating func showMoreMembers(
        groupID: String,
        totalCount: Int,
        controllerID: String
    ) {
        ensureController(controllerID)
        statesByControllerID[controllerID]?.showMoreMembers(
            groupID: groupID,
            totalCount: totalCount
        )
    }

    func visibleOptions(
        _ options: [String],
        groupID: String,
        controllerID: String
    ) -> [String] {
        statesByControllerID[controllerID]?.visibleOptions(options, groupID: groupID)
            ?? Array(options.prefix(PolicyGroupControllerInteractionState.memberWindowSize))
    }

    func hasMoreOptions(
        _ options: [String],
        groupID: String,
        controllerID: String
    ) -> Bool {
        statesByControllerID[controllerID]?.hasMoreOptions(options, groupID: groupID)
            ?? (options.count > PolicyGroupControllerInteractionState.memberWindowSize)
    }

    mutating func pruneGroups(
        controllerID: String,
        keeping validGroupIDs: Set<String>
    ) {
        statesByControllerID[controllerID]?.pruneGroups(keeping: validGroupIDs)
    }

    mutating func removeController(_ controllerID: String) {
        statesByControllerID.removeValue(forKey: controllerID)
    }

    mutating func removeControllers(notIn validControllerIDs: Set<String>) {
        statesByControllerID = statesByControllerID.reduce(into: [:]) { result, entry in
            guard validControllerIDs.contains(entry.key) else { return }
            result[entry.key] = entry.value
        }
    }
}

@MainActor
@Observable
final class PolicyGroupInteractionStore {
    static let shared = PolicyGroupInteractionStore()

    private var runtimeState = PolicyGroupRuntimeState()
    private var scrollPositionsByControllerID: [String: [String: ScrollPosition]] = [:]

    func ensureController(
        _ controllerID: String,
        restoredExpandedGroupIDs: Set<String> = []
    ) {
        runtimeState.ensureController(
            controllerID,
            restoredExpandedGroupIDs: restoredExpandedGroupIDs
        )
    }

    func isExpanded(_ groupID: String, controllerID: String) -> Bool {
        runtimeState.isExpanded(groupID, controllerID: controllerID)
    }

    func expandedGroupIDs(for controllerID: String) -> Set<String> {
        runtimeState.expandedGroupIDs(for: controllerID)
    }

    func setExpanded(_ expanded: Bool, groupID: String, controllerID: String) {
        runtimeState.setExpanded(expanded, groupID: groupID, controllerID: controllerID)
    }

    func filterText(groupID: String, controllerID: String) -> String {
        runtimeState.filterText(groupID: groupID, controllerID: controllerID)
    }

    func setFilterText(_ text: String, groupID: String, controllerID: String) {
        runtimeState.setFilterText(text, groupID: groupID, controllerID: controllerID)
    }

    func showMoreMembers(groupID: String, totalCount: Int, controllerID: String) {
        runtimeState.showMoreMembers(
            groupID: groupID,
            totalCount: totalCount,
            controllerID: controllerID
        )
    }

    func visibleOptions(
        _ options: [String],
        groupID: String,
        controllerID: String
    ) -> [String] {
        runtimeState.visibleOptions(options, groupID: groupID, controllerID: controllerID)
    }

    func hasMoreOptions(
        _ options: [String],
        groupID: String,
        controllerID: String
    ) -> Bool {
        runtimeState.hasMoreOptions(options, groupID: groupID, controllerID: controllerID)
    }

    func scrollPosition(groupID: String, controllerID: String) -> ScrollPosition {
        scrollPositionsByControllerID[controllerID]?[groupID]
            ?? ScrollPosition(idType: String.self)
    }

    func setScrollPosition(
        _ position: ScrollPosition,
        groupID: String,
        controllerID: String
    ) {
        scrollPositionsByControllerID[controllerID, default: [:]][groupID] = position
    }

    func pruneGroups(controllerID: String, keeping validGroupIDs: Set<String>) {
        runtimeState.pruneGroups(
            controllerID: controllerID,
            keeping: validGroupIDs
        )
        scrollPositionsByControllerID[controllerID] = scrollPositionsByControllerID[controllerID]?
            .reduce(into: [:]) { result, entry in
                guard validGroupIDs.contains(entry.key) else { return }
                result[entry.key] = entry.value
            }
    }

    func removeController(_ controllerID: String) {
        runtimeState.removeController(controllerID)
        scrollPositionsByControllerID.removeValue(forKey: controllerID)
    }

    func removeControllers(notIn validControllerIDs: Set<String>) {
        runtimeState.removeControllers(notIn: validControllerIDs)
        scrollPositionsByControllerID = scrollPositionsByControllerID.reduce(into: [:]) { result, entry in
            guard validControllerIDs.contains(entry.key) else { return }
            result[entry.key] = entry.value
        }
    }
}

struct PolicyGroupExpansionArchive: Equatable {
    static let storageKey = "policyGroupExpandedIDsByController"

    private struct Payload: Codable {
        var groupsByControllerID: [String: [String]]
    }

    private var groupsByControllerID: [String: Set<String>] = [:]

    init(rawValue: String = "") {
        guard
            let data = rawValue.data(using: .utf8),
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return
        }

        groupsByControllerID = payload.groupsByControllerID.mapValues(Set.init)
    }

    func expandedGroupIDs(for controllerID: String) -> Set<String> {
        groupsByControllerID[controllerID] ?? []
    }

    mutating func setExpandedGroupIDs(_ groupIDs: Set<String>, for controllerID: String) {
        if groupIDs.isEmpty {
            groupsByControllerID.removeValue(forKey: controllerID)
        } else {
            groupsByControllerID[controllerID] = groupIDs
        }
    }

    mutating func pruneGroups(controllerID: String, keeping validGroupIDs: Set<String>) {
        setExpandedGroupIDs(
            expandedGroupIDs(for: controllerID).intersection(validGroupIDs),
            for: controllerID
        )
    }

    mutating func removeController(_ controllerID: String) {
        groupsByControllerID.removeValue(forKey: controllerID)
    }

    mutating func removeControllers(notIn validControllerIDs: Set<String>) {
        groupsByControllerID = groupsByControllerID.reduce(into: [:]) { result, entry in
            guard validControllerIDs.contains(entry.key) else { return }
            result[entry.key] = entry.value
        }
    }

    var rawValue: String {
        guard !groupsByControllerID.isEmpty else { return "" }

        let payload = Payload(
            groupsByControllerID: groupsByControllerID.mapValues { Array($0).sorted() }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension AppModel {
    func removePolicyGroupPresentationState(for controllerID: RouterProfile.ID) {
        let stateID = controllerID.uuidString
        PolicyGroupInteractionStore.shared.removeController(stateID)

        var archive = PolicyGroupExpansionArchive(
            rawValue: userDefaults.string(forKey: PolicyGroupExpansionArchive.storageKey) ?? ""
        )
        archive.removeController(stateID)
        if archive.rawValue.isEmpty {
            userDefaults.removeObject(forKey: PolicyGroupExpansionArchive.storageKey)
        } else {
            userDefaults.set(archive.rawValue, forKey: PolicyGroupExpansionArchive.storageKey)
        }
    }
}
