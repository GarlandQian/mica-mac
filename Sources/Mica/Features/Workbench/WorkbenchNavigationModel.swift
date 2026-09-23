import Foundation
import Observation

struct RouterEditorPresentation: Identifiable {
    let id = UUID()
    let titleKey: String
    let draft: RouterDraft
    fileprivate var isDirty = false
    fileprivate var isSaving = false

    init(titleKey: String, draft: RouterDraft) {
        self.titleKey = titleKey
        self.draft = draft
    }
}

@MainActor
@Observable
final class WorkbenchNavigationModel {
    private enum PendingIntent {
        case destination(WorkbenchDestination)
        case editor(RouterEditorPresentation)
    }

    private(set) var editor: RouterEditorPresentation?
    private(set) var discardRequestID = 0
    var addControllerRequestID = 0
    var editControllerRequestID = 0

    private var pendingIntent: PendingIntent?

    var editorIsDirty: Bool { editor?.isDirty ?? false }
    var editorIsSaving: Bool { editor?.isSaving ?? false }
    var canSelectController: Bool { editor == nil }
    var acceptsEditorCommands: Bool { !editorIsSaving }

    // SceneStorage remains the destination owner. A returned destination is an
    // accepted transition for the window to persist, not a second stored copy.
    func requestDestination(
        _ next: WorkbenchDestination,
        current: WorkbenchDestination?
    ) -> WorkbenchDestination? {
        guard acceptsEditorCommands, next != current else { return nil }
        guard editor != nil else { return next }
        pendingIntent = .destination(next)
        discardRequestID &+= 1
        return nil
    }

    func requestEditor(_ presentation: RouterEditorPresentation) {
        guard acceptsEditorCommands else { return }
        if editor == nil {
            editor = presentation
        } else {
            pendingIntent = .editor(presentation)
            discardRequestID &+= 1
        }
    }

    func updateEditorState(editorID: UUID, isDirty: Bool, isSaving: Bool) {
        guard var editor, editor.id == editorID else { return }
        guard editor.isDirty != isDirty || editor.isSaving != isSaving else { return }
        editor.isDirty = isDirty
        editor.isSaving = isSaving
        self.editor = editor
    }

    func confirmDiscard(editorID: UUID) -> WorkbenchDestination? {
        guard editor?.id == editorID, !editorIsSaving else { return nil }
        let intent = pendingIntent
        pendingIntent = nil
        switch intent {
        case .destination(let destination):
            editor = nil
            return destination
        case .editor(let presentation):
            editor = presentation
            return nil
        case nil:
            editor = nil
            return nil
        }
    }

    func cancelPendingIntent(editorID: UUID) {
        guard editor?.id == editorID, !editorIsSaving else { return }
        pendingIntent = nil
    }

    // RouterEditorView calls this after a successful save or an accepted clean
    // close. A save completion is valid while its editor still reports saving.
    func finishEditor(editorID: UUID) {
        guard editor?.id == editorID else { return }
        editor = nil
        pendingIntent = nil
    }
}
