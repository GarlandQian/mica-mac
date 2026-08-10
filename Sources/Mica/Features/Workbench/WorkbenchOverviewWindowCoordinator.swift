import Foundation
import MicaCore
import Observation

// MARK: - Overview window coordination

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
