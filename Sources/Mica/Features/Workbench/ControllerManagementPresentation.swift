import Foundation
import MicaCore
import SwiftUI

enum ControllerManagementStatusKind: Equatable {
    case idle
    case checking
    case live
    case stale
    case partial
    case failed
}

struct ControllerManagementStatus: Equatable {
    var kind: ControllerManagementStatusKind
    var label: String

    var symbolName: String {
        switch kind {
        case .idle:
            "minus.circle"
        case .checking:
            MicaSymbols.Command.working
        case .live:
            "checkmark.seal.fill"
        case .stale, .partial:
            "exclamationmark.triangle.fill"
        case .failed:
            "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch kind {
        case .idle:
            .secondary
        case .checking:
            MicaStyle.signalCyan
        case .live:
            MicaStyle.signalMint
        case .stale, .partial:
            MicaStyle.signalAmber
        case .failed:
            MicaStyle.signalRed
        }
    }

    static func resolve(
        isActive: Bool,
        connectionState: ConnectionState,
        controllerHealth: ControllerHealthSummary,
        trialHealth: TrialSessionHealth,
        language: AppLanguage
    ) -> ControllerManagementStatus {
        if isActive, controllerHealth != .unknown {
            return ControllerManagementStatus(
                kind: kind(for: controllerHealth),
                label: controllerHealth.sidebarLabel(language: language)
            )
        }

        if isActive {
            return ControllerManagementStatus(
                kind: kind(for: connectionState),
                label: connectionState.sidebarLabel(language: language)
            )
        }

        return ControllerManagementStatus(
            kind: kind(for: trialHealth),
            label: trialHealth.sidebarLabel(language: language)
        )
    }

    private static func kind(for state: ConnectionState) -> ControllerManagementStatusKind {
        switch state {
        case .connected:
            .live
        case .connecting:
            .checking
        case .failed:
            .failed
        case .disconnected:
            .idle
        }
    }

    private static func kind(for health: ControllerHealthSummary) -> ControllerManagementStatusKind {
        switch health {
        case .ready:
            .live
        case .partial:
            .partial
        case .checking:
            .checking
        case .authFailed, .wrongTarget, .offline:
            .failed
        case .unknown:
            .idle
        }
    }

    private static func kind(for health: TrialSessionHealth) -> ControllerManagementStatusKind {
        switch health {
        case .idle:
            .idle
        case .fresh:
            .live
        case .stale:
            .stale
        case .partial:
            .partial
        case .failed:
            .failed
        }
    }
}

enum ControllerTableMode: Equatable {
    case wide
    case compact
}

enum ControllerManagementField: Hashable {
    case active
    case name
    case endpoint
    case type
    case status
    case lastSuccess
    case actions
}

struct ControllerTableColumnModel: Equatable {
    enum ID: Equatable {
        case active
        case name
        case endpoint
        case type
        case status
        case lastSuccess
        case controller
        case statusSummary
        case actions
    }

    var id: ID
    var fields: Set<ControllerManagementField>

    static func columns(for mode: ControllerTableMode) -> [ControllerTableColumnModel] {
        switch mode {
        case .wide:
            [
                ControllerTableColumnModel(id: .active, fields: [.active]),
                ControllerTableColumnModel(id: .name, fields: [.name]),
                ControllerTableColumnModel(id: .endpoint, fields: [.endpoint]),
                ControllerTableColumnModel(id: .type, fields: [.type]),
                ControllerTableColumnModel(id: .status, fields: [.status]),
                ControllerTableColumnModel(id: .lastSuccess, fields: [.lastSuccess]),
                ControllerTableColumnModel(id: .actions, fields: [.actions]),
            ]
        case .compact:
            [
                ControllerTableColumnModel(id: .controller, fields: [.active, .name, .endpoint, .type]),
                ControllerTableColumnModel(id: .statusSummary, fields: [.status, .lastSuccess]),
                ControllerTableColumnModel(id: .actions, fields: [.actions]),
            ]
        }
    }
}

enum ControllerMoveDirection: Equatable {
    case up
    case down
}

enum ControllerReorderIntent: Equatable {
    case move(RouterProfile.ID, ControllerMoveDirection)
    case moveBefore(RouterProfile.ID, RouterProfile.ID)
}

enum ControllerManagementPresentation {
    static let minimumWideWidth: CGFloat = 1_140

    static func tableMode(availableWidth: CGFloat, fontMultiplier: CGFloat) -> ControllerTableMode {
        let readabilityScale = max(1, fontMultiplier)
        return availableWidth >= minimumWideWidth * readabilityScale ? .wide : .compact
    }

    static func filteredProfiles(
        _ profiles: [RouterProfile],
        matching query: String,
        language: AppLanguage
    ) -> [RouterProfile] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return profiles
        }

        return profiles.filter { profile in
            let searchableValues = [
                profile.displayName,
                profile.endpointURL,
                profile.controllerKind.rawValue,
                profile.controllerKind.micaLabel(language: language),
            ]
            return searchableValues.contains {
                $0.localizedCaseInsensitiveContains(normalizedQuery)
            }
        }
    }

    static func isReorderingEnabled(searchText: String) -> Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func reconciledManagementSelection(
        _ selection: RouterProfile.ID?,
        previousOrder: [RouterProfile.ID],
        currentOrder: [RouterProfile.ID]
    ) -> RouterProfile.ID? {
        guard let selection else {
            return nil
        }

        if currentOrder.contains(selection) {
            return selection
        }

        guard let previousIndex = previousOrder.firstIndex(of: selection), !currentOrder.isEmpty else {
            return nil
        }

        if previousIndex < currentOrder.count {
            return currentOrder[previousIndex]
        }

        return currentOrder.last
    }

    static func applying(
        _ intent: ControllerReorderIntent,
        to profiles: [RouterProfile]
    ) -> [RouterProfile] {
        switch intent {
        case .move(let id, let direction):
            guard let sourceIndex = profiles.firstIndex(where: { $0.id == id }) else {
                return profiles
            }

            let targetIndex: Int
            switch direction {
            case .up:
                targetIndex = sourceIndex - 1
            case .down:
                targetIndex = sourceIndex + 1
            }

            guard profiles.indices.contains(targetIndex) else {
                return profiles
            }

            var reordered = profiles
            reordered.swapAt(sourceIndex, targetIndex)
            return reordered

        case .moveBefore(let sourceID, let targetID):
            guard sourceID != targetID,
                  let sourceIndex = profiles.firstIndex(where: { $0.id == sourceID }),
                  let targetIndex = profiles.firstIndex(where: { $0.id == targetID }) else {
                return profiles
            }

            var reordered = profiles
            let moved = reordered.remove(at: sourceIndex)
            let insertionIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
            reordered.insert(moved, at: insertionIndex)
            return reordered
        }
    }

    static func canMove(
        _ id: RouterProfile.ID,
        direction: ControllerMoveDirection,
        in profiles: [RouterProfile]
    ) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            return false
        }

        switch direction {
        case .up:
            return index > profiles.startIndex
        case .down:
            return index < profiles.index(before: profiles.endIndex)
        }
    }
}

enum ControllerManagementCopy {
    static func title(language: AppLanguage) -> String {
        MicaStrings.localizedKey("sidebar.controllers", language: language)
    }

    static func add(language: AppLanguage) -> String {
        MicaStrings.localizedKey("sidebar.add_controller", language: language)
    }

    static func name(language: AppLanguage) -> String {
        MicaStrings.localizedKey("editor.name", language: language)
    }

    static func endpoint(language: AppLanguage) -> String {
        MicaStrings.localizedKey("settings.controller_endpoint", language: language)
    }

    static func type(language: AppLanguage) -> String {
        MicaStrings.localizedKey("settings.controller_type", language: language)
    }

    static func status(language: AppLanguage) -> String {
        MicaStrings.localizedKey("dashboard.col_status", language: language)
    }

    static func lastSuccess(language: AppLanguage) -> String {
        MicaStrings.localizedKey("settings.controller_last_connected", language: language)
    }

    static func use(language: AppLanguage) -> String {
        MicaStrings.localizedKey("controllers.use", language: language)
    }

    static func test(language: AppLanguage) -> String {
        MicaStrings.localizedKey("action.test", language: language)
    }

    static func edit(language: AppLanguage) -> String {
        MicaStrings.localizedKey("sidebar.edit", language: language)
    }

    static func delete(language: AppLanguage) -> String {
        MicaStrings.localizedKey("sidebar.delete_button", language: language)
    }

    static func active(language: AppLanguage) -> String {
        MicaStrings.localizedKey("controllers.active", language: language)
    }

    static func actions(language: AppLanguage) -> String {
        MicaStrings.localizedKey("controllers.actions", language: language)
    }

    static func controller(language: AppLanguage) -> String {
        MicaStrings.localizedKey("controllers.controller", language: language)
    }

    static func searchPrompt(language: AppLanguage) -> String {
        MicaStrings.localizedKey("controllers.search_prompt", language: language)
    }

    static func subtitle(language: AppLanguage) -> String {
        MicaStrings.localizedKey("controllers.subtitle", language: language)
    }

    static func count(_ count: Int, language: AppLanguage) -> String {
        MicaStrings.localized("controllers.count \(count)", language: language)
    }

    static func noMatchTitle(language: AppLanguage) -> String {
        MicaStrings.localizedKey("controllers.no_match_title", language: language)
    }

    static func noMatchDescription(language: AppLanguage) -> String {
        MicaStrings.localizedKey("controllers.no_match_description", language: language)
    }

    static func noControllersDescription(language: AppLanguage) -> String {
        MicaStrings.localizedKey("sidebar.no_controllers_message", language: language)
    }

    static func moveUp(language: AppLanguage) -> String {
        MicaStrings.localizedKey("controllers.move_up", language: language)
    }

    static func moveDown(language: AppLanguage) -> String {
        MicaStrings.localizedKey("controllers.move_down", language: language)
    }

    static func never(language: AppLanguage) -> String {
        MicaStrings.localizedKey("live.last_update_never", language: language)
    }

}
