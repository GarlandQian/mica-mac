import Foundation
import Testing
@testable import Mica

@MainActor
struct WorkbenchNavigationModelTests {
    private func presentation(_ name: String = "Controller") -> RouterEditorPresentation {
        RouterEditorPresentation(titleKey: "editor.edit_router", draft: RouterDraft(displayName: name))
    }

    @Test func acceptedDestinationsRemainOwnedBySceneStorage() {
        let navigation = WorkbenchNavigationModel()

        #expect(navigation.requestDestination(.connections, current: .overview) == .connections)
        #expect(navigation.requestDestination(.connections, current: .connections) == nil)
        #expect(navigation.requestDestination(.overview, current: nil) == .overview)
        #expect(navigation.editor == nil)
        #expect(navigation.discardRequestID == 0)
    }

    @Test func dirtyEditorDefersDestinationUntilItsOwnDiscardConfirmation() {
        let navigation = WorkbenchNavigationModel()
        let editor = presentation()
        navigation.requestEditor(editor)
        navigation.updateEditorState(editorID: editor.id, isDirty: true, isSaving: false)

        #expect(navigation.requestDestination(.rules, current: .overview) == nil)
        #expect(navigation.editor?.id == editor.id)
        #expect(navigation.editorIsDirty)
        #expect(navigation.discardRequestID == 1)

        #expect(navigation.confirmDiscard(editorID: editor.id) == .rules)
        #expect(navigation.editor == nil)
        #expect(!navigation.editorIsDirty)
        #expect(navigation.confirmDiscard(editorID: editor.id) == nil)
    }

    @Test func cleanEditorStillAcknowledgesNavigationUsingItsCurrentDraft() {
        let navigation = WorkbenchNavigationModel()
        let editor = presentation()
        navigation.requestEditor(editor)

        #expect(navigation.requestDestination(.logs, current: .overview) == nil)
        #expect(navigation.editor?.id == editor.id)
        #expect(navigation.discardRequestID == 1)
        #expect(navigation.confirmDiscard(editorID: editor.id) == .logs)
    }

    @Test func latestPendingIntentReplacesEarlierIntentWithoutReplacingDirtyEditor() {
        let navigation = WorkbenchNavigationModel()
        let current = presentation("Current")
        let replacement = presentation("Replacement")
        navigation.requestEditor(current)
        navigation.updateEditorState(editorID: current.id, isDirty: true, isSaving: false)
        _ = navigation.requestDestination(.connections, current: .overview)
        navigation.requestEditor(replacement)

        #expect(navigation.editor?.id == current.id)
        #expect(navigation.discardRequestID == 2)
        #expect(navigation.confirmDiscard(editorID: current.id) == nil)
        #expect(navigation.editor?.id == replacement.id)
        #expect(navigation.editor?.draft.displayName == "Replacement")
        #expect(!navigation.editorIsDirty)
        #expect(!navigation.editorIsSaving)
    }

    @Test func savingRejectsNavigationAndDiscardWithoutLosingPendingIntent() {
        let navigation = WorkbenchNavigationModel()
        let current = presentation()
        navigation.requestEditor(current)
        navigation.updateEditorState(editorID: current.id, isDirty: true, isSaving: false)
        _ = navigation.requestDestination(.connections, current: .overview)
        navigation.updateEditorState(editorID: current.id, isDirty: true, isSaving: true)

        #expect(navigation.requestDestination(.logs, current: .overview) == nil)
        navigation.requestEditor(presentation("Blocked"))
        navigation.cancelPendingIntent(editorID: current.id)
        #expect(navigation.confirmDiscard(editorID: current.id) == nil)
        #expect(navigation.editor?.id == current.id)
        #expect(navigation.discardRequestID == 1)
        #expect(!navigation.acceptsEditorCommands)
        #expect(!navigation.canSelectController)

        navigation.updateEditorState(editorID: current.id, isDirty: true, isSaving: false)
        #expect(navigation.acceptsEditorCommands)
        #expect(navigation.confirmDiscard(editorID: current.id) == .connections)
    }

    @Test func successfulSaveClosesSavingEditorAndClearsDeferredNavigation() {
        let navigation = WorkbenchNavigationModel()
        let editor = presentation()
        navigation.requestEditor(editor)
        _ = navigation.requestDestination(.rules, current: .overview)
        navigation.updateEditorState(editorID: editor.id, isDirty: true, isSaving: true)

        navigation.finishEditor(editorID: editor.id)

        #expect(navigation.editor == nil)
        #expect(!navigation.editorIsSaving)
        #expect(!navigation.editorIsDirty)
        #expect(navigation.canSelectController)
        #expect(navigation.confirmDiscard(editorID: editor.id) == nil)

        let next = presentation("Next")
        navigation.requestEditor(next)
        #expect(navigation.confirmDiscard(editorID: next.id) == nil)
        #expect(navigation.editor == nil)
    }

    @Test func continuingEditingAbandonsTheEarlierDestinationBeforeExplicitClose() {
        let navigation = WorkbenchNavigationModel()
        let editor = presentation()
        navigation.requestEditor(editor)
        navigation.updateEditorState(editorID: editor.id, isDirty: true, isSaving: false)
        _ = navigation.requestDestination(.connections, current: .overview)

        navigation.cancelPendingIntent(editorID: editor.id)

        #expect(navigation.editor?.id == editor.id)
        #expect(navigation.editorIsDirty)
        #expect(navigation.confirmDiscard(editorID: editor.id) == nil)
        #expect(navigation.editor == nil)
    }

    @Test func continuingEditingAlsoAbandonsAnEarlierReplacementEditor() {
        let navigation = WorkbenchNavigationModel()
        let editor = presentation("Current")
        navigation.requestEditor(editor)
        navigation.updateEditorState(editorID: editor.id, isDirty: true, isSaving: false)
        navigation.requestEditor(presentation("Abandoned"))

        navigation.cancelPendingIntent(editorID: editor.id)

        #expect(navigation.editor?.id == editor.id)
        #expect(navigation.confirmDiscard(editorID: editor.id) == nil)
        #expect(navigation.editor == nil)
    }

    @Test func staleContinueEditingCannotCancelTheSuccessorNavigation() {
        let navigation = WorkbenchNavigationModel()
        let previous = presentation("Previous")
        let current = presentation("Current")
        navigation.requestEditor(previous)
        navigation.requestEditor(current)
        _ = navigation.confirmDiscard(editorID: previous.id)
        _ = navigation.requestDestination(.logs, current: .overview)

        navigation.cancelPendingIntent(editorID: previous.id)

        #expect(navigation.confirmDiscard(editorID: current.id) == .logs)
    }

    @Test func lateCallbacksFromReplacedEditorCannotModifySuccessor() {
        let navigation = WorkbenchNavigationModel()
        let previous = presentation("Previous")
        let current = presentation("Current")
        navigation.requestEditor(previous)
        navigation.requestEditor(current)
        _ = navigation.confirmDiscard(editorID: previous.id)
        navigation.updateEditorState(editorID: current.id, isDirty: true, isSaving: false)

        navigation.updateEditorState(editorID: previous.id, isDirty: false, isSaving: true)
        navigation.finishEditor(editorID: previous.id)
        #expect(navigation.confirmDiscard(editorID: previous.id) == nil)
        #expect(navigation.editor?.id == current.id)
        #expect(navigation.editorIsDirty)
        #expect(!navigation.editorIsSaving)
    }

    @Test func reopeningTheSameDraftCreatesAnIndependentEditorIdentity() {
        let navigation = WorkbenchNavigationModel()
        let draft = RouterDraft(displayName: "Repeated")
        let first = RouterEditorPresentation(titleKey: "editor.edit_router", draft: draft)
        let second = RouterEditorPresentation(titleKey: "editor.edit_router", draft: draft)
        navigation.requestEditor(first)
        navigation.requestEditor(second)
        _ = navigation.confirmDiscard(editorID: first.id)

        #expect(first.draft.id == second.draft.id)
        #expect(first.id != second.id)
        #expect(navigation.editor?.id == second.id)
    }

    @Test func explicitDiscardWithoutDeferredNavigationClosesOnlyItsEditor() {
        let navigation = WorkbenchNavigationModel()
        let editor = presentation()
        navigation.requestEditor(editor)
        navigation.updateEditorState(editorID: editor.id, isDirty: true, isSaving: false)

        #expect(navigation.confirmDiscard(editorID: UUID()) == nil)
        #expect(navigation.editor?.id == editor.id)
        #expect(navigation.confirmDiscard(editorID: editor.id) == nil)
        #expect(navigation.editor == nil)
    }

    @Test func editorTransactionsAndMenuRequestsAreWindowOwned() {
        let first = WorkbenchNavigationModel()
        let second = WorkbenchNavigationModel()
        first.requestEditor(presentation())
        first.addControllerRequestID += 1
        first.editControllerRequestID += 1

        #expect(!first.canSelectController)
        #expect(second.canSelectController)
        #expect(second.editor == nil)
        #expect(second.addControllerRequestID == 0)
        #expect(second.editControllerRequestID == 0)
        #expect(second.discardRequestID == 0)
    }
}
