import AppKit
import MicaCore
import SwiftUI

// MARK: - Window

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var preferences: AppPreferencesStore
    @Environment(\.undoManager) private var undoManager
    @SceneStorage("workbenchDestination") private var destinationRawValue = WorkbenchDestination.overview.rawValue

    private let overviewLayoutStore: OverviewDashboardLayoutStore

    @State private var editor: RouterEditorPresentation?
    @State private var pendingIntent: PendingEditorIntent?
    @State private var pendingOverviewIntent: PendingOverviewIntent?
    @State private var discardRequestID = 0
    @State private var addControllerRequestID = 0
    @State private var editControllerRequestID = 0
    @State private var editorIsDirty = false
    @State private var editorIsSaving = false
    @State private var didRegisterMainWindow = false
    @State private var closeGuard = MainWindowCloseGuard()
    @State private var workspaceStore = WorkbenchWorkspaceStore()
    @State private var overviewCoordinator: OverviewDashboardWindowCoordinator
    @State private var knownOverviewControllerIDs: Set<RouterProfile.ID>?

    init(overviewLayoutStore: OverviewDashboardLayoutStore) {
        self.overviewLayoutStore = overviewLayoutStore
        _overviewCoordinator = State(
            wrappedValue: OverviewDashboardWindowCoordinator(
                layoutStore: overviewLayoutStore
            )
        )
    }

    private var destination: Binding<WorkbenchDestination> {
        Binding {
            WorkbenchDestination(rawValue: destinationRawValue) ?? .overview
        } set: { next in
            requestDestination(next)
        }
    }

    var body: some View {
        lifecycleContent
    }

    private var lifecycleContent: some View {
        observedContent
            .background {
                MainWindowCloseGuardAttachment(closeGuard: closeGuard)
                    .frame(width: 0, height: 0)
            }
            .task {
                appModel.loadPersistedState()
                synchronizeOverviewControllerOwnership()
                reconcileOverviewCoordinator()
            }
            .onAppear {
                registerMainWindowIfNeeded()
                applyPresentationLanguage()
                overviewCoordinator.attachUndoManager(undoManager)
                synchronizeOverviewControllerOwnership()
                reconcileOverviewCoordinator()
            }
            .onDisappear {
                if didRegisterMainWindow {
                    didRegisterMainWindow = false
                    appModel.mainWindowDidDisappear()
                }
                closeGuard.detach()
            }
            .onReceive(
                NSWorkspace.shared.notificationCenter.publisher(
                    for: NSWorkspace.willSleepNotification
                )
            ) { _ in
                appModel.systemWillSleep()
            }
            .onReceive(
                NSWorkspace.shared.notificationCenter.publisher(
                    for: NSWorkspace.didWakeNotification
                )
            ) { _ in
                appModel.systemDidWake()
            }
    }

    private var observedContent: some View {
        configuredContent
            .onChange(of: addControllerRequestID) { presentAddController() }
            .onChange(of: editControllerRequestID) {
                guard let router = appModel.selectedRouter else { return }
                presentEditController(router)
            }
            .onChange(of: preferences.language) { _, _ in
                applyPresentationLanguage()
            }
            .onChange(of: undoManager) { _, undoManager in
                overviewCoordinator.attachUndoManager(undoManager)
            }
            .onChange(of: appModel.routers) { _, _ in
                synchronizeOverviewControllerOwnership()
                reconcileOverviewCoordinator()
            }
            .onChange(of: appModel.didFinishLoadingPersistedState) { _, finished in
                guard finished else { return }
                synchronizeOverviewControllerOwnership()
            }
            .onChange(of: appModel.selectedRouterID) {
                reconcileOverviewCoordinator()
            }
            .onChange(of: overviewCoordinator.hasDirtyDraft) {
                updateCombinedCloseGuard()
            }
            .onChange(of: overviewCoordinator.isCommitting) {
                updateCombinedCloseGuard()
            }
            .onChange(of: overviewCoordinator.isEditing) { _, isEditing in
                if !isEditing {
                    pendingOverviewIntent = nil
                }
            }
    }

    private var configuredContent: some View {
        navigationContent
            .navigationSplitViewStyle(.balanced)
            .environment(overviewLayoutStore)
            .environment(overviewCoordinator)
            .focusedValue(\.micaFocusedWorkbenchDestination, destination)
            .focusedValue(
                \.micaAddControllerRequestID,
                editorIsSaving ? nil : $addControllerRequestID
            )
            .focusedValue(
                \.micaEditControllerRequestID,
                editorIsSaving ? nil : $editControllerRequestID
            )
    }

    private var navigationContent: some View {
        NavigationSplitView {
            WorkbenchSidebarView(
                destination: destination,
                isControllerSwitchingEnabled:
                    editor == nil
                    && !editorIsSaving
                    && !overviewCoordinator.isCommitting,
                onSelectController: requestControllerSelection,
                onAddController: presentAddController
            )
                .navigationSplitViewColumnWidth(
                    min: MicaBounds.sidebarMin,
                    ideal: MicaBounds.sidebarIdeal,
                    max: MicaBounds.sidebarMax
                )
        } detail: {
            VStack(spacing: 0) {
                if pendingOverviewIntent != nil {
                    OverviewReplacementDecisionBar(
                        onKeepEditing: {
                            pendingOverviewIntent = nil
                        },
                        onDiscardAndContinue: performPendingOverviewIntent
                    )
                }

                if let editor {
                    RouterEditorView(
                        draft: editor.draft,
                        title: editor.titleKey,
                        discardRequestID: discardRequestID,
                        onClose: closeEditor,
                        onDiscardConfirmed: performPendingIntent,
                        onEditingStateChange: updateCloseGuard
                    )
                    .id(editor.id)
                    .environment(appModel)
                } else {
                    WorkbenchRootView(
                        destination: destination,
                        onAddController: presentAddController,
                        onEditController: presentEditController
                    )
                    .environment(workspaceStore)
                }
            }
        }
    }

    private func registerMainWindowIfNeeded() {
        if !didRegisterMainWindow {
            didRegisterMainWindow = true
            appModel.mainWindowDidAppear()
        }

        updateCombinedCloseGuard()
    }

    private func applyPresentationLanguage() {
        Bundle.setMicaLocalizationLanguage(
            MicaStrings.resolvedLanguageCode(for: preferences.language)
        )
        appModel.applyPresentationLanguage(preferences.language)
    }

    private func presentAddController() {
        requestOverviewReplacement(
            .editor(
                RouterEditorPresentation(
                    titleKey: "editor.add_router",
                    draft: appModel.draft()
                )
            )
        )
    }

    private func presentEditController(_ router: RouterProfile) {
        requestOverviewReplacement(
            .editor(
                RouterEditorPresentation(
                    titleKey: "editor.edit_router",
                    draft: appModel.draft(for: router)
                )
            )
        )
    }

    private func requestDestination(_ next: WorkbenchDestination) {
        guard !editorIsSaving, !overviewCoordinator.isCommitting else { return }
        guard next.rawValue != destinationRawValue else { return }
        if editor != nil {
            pendingIntent = .destination(next)
            discardRequestID += 1
            return
        }
        requestOverviewReplacement(.destination(next))
    }

    private func requestControllerSelection(_ router: RouterProfile) {
        requestOverviewReplacement(.controller(router))
    }

    private func requestOverviewReplacement(_ intent: PendingOverviewIntent) {
        guard !overviewCoordinator.isCommitting else { return }
        guard overviewCoordinator.isEditing else {
            performOverviewIntent(intent)
            return
        }
        guard overviewCoordinator.hasDirtyDraft else {
            overviewCoordinator.cancel()
            performOverviewIntent(intent)
            return
        }
        pendingOverviewIntent = intent
    }

    private func performPendingOverviewIntent() {
        guard let intent = pendingOverviewIntent else { return }
        pendingOverviewIntent = nil
        overviewCoordinator.cancel()
        performOverviewIntent(intent)
    }

    private func performOverviewIntent(_ intent: PendingOverviewIntent) {
        switch intent {
        case .destination(let destination):
            destinationRawValue = destination.rawValue
        case .editor(let presentation):
            requestEditor(presentation)
        case .controller(let router):
            Task { @MainActor in
                await Task.yield()
                appModel.selectRouter(router)
            }
        }
    }

    private func requestEditor(_ presentation: RouterEditorPresentation) {
        guard !editorIsSaving else { return }
        guard editor != nil else {
            editor = presentation
            return
        }

        pendingIntent = .editor(presentation)
        discardRequestID += 1
    }

    private func closeEditor() {
        editor = nil
        pendingIntent = nil
        editorIsSaving = false
        updateCloseGuard(isDirty: false, isSaving: false)
    }

    private func performPendingIntent() {
        switch pendingIntent {
        case .destination(let destination):
            destinationRawValue = destination.rawValue
            editor = nil
        case .editor(let presentation):
            editor = presentation
        case nil:
            editor = nil
        }

        pendingIntent = nil
        editorIsSaving = false
        updateCloseGuard(isDirty: false, isSaving: false)
    }

    private func updateCloseGuard(isDirty: Bool, isSaving: Bool) {
        editorIsSaving = isSaving
        editorIsDirty = isDirty
        updateCombinedCloseGuard()
    }

    private func updateCombinedCloseGuard() {
        closeGuard.update(
            isDirty: editorIsDirty || overviewCoordinator.hasDirtyDraft,
            isSaving: editorIsSaving || overviewCoordinator.isCommitting,
            language: preferences.language
        )
    }

    private func synchronizeOverviewControllerOwnership() {
        guard appModel.didFinishLoadingPersistedState else { return }
        let current = Set(appModel.routers.map(\.id))
        guard let previous = knownOverviewControllerIDs else {
            knownOverviewControllerIDs = current
            return
        }
        knownOverviewControllerIDs = current
        for removedControllerID in previous.subtracting(current) {
            Task {
                try? await overviewLayoutStore.removeController(
                    removedControllerID
                )
            }
        }
    }

    private func reconcileOverviewCoordinator() {
        let targetExists = overviewCoordinator.targetControllerID.map { targetID in
            appModel.routers.contains { $0.id == targetID }
        } ?? true
        overviewCoordinator.reconcile(
            selectedControllerID: appModel.selectedRouterID,
            targetControllerExists: targetExists
        )
    }
}

struct RouterEditorPresentation: Identifiable {
    let id = UUID()
    let titleKey: String
    let draft: RouterDraft

    init(titleKey: String, draft: RouterDraft) {
        self.titleKey = titleKey
        self.draft = draft
    }
}

private enum PendingEditorIntent {
    case destination(WorkbenchDestination)
    case editor(RouterEditorPresentation)
}

private enum PendingOverviewIntent {
    case destination(WorkbenchDestination)
    case editor(RouterEditorPresentation)
    case controller(RouterProfile)
}

private struct OverviewReplacementDecisionBar: View {
    @Environment(\.micaAppLanguage) private var language

    let onKeepEditing: () -> Void
    let onDiscardAndContinue: () -> Void

    var body: some View {
        HStack(spacing: MicaSpacing.module) {
            Label(
                MicaStrings.localizedKey(
                    "overview.layout_pending_navigation",
                    language: language
                ),
                systemImage: "exclamationmark.triangle"
            )
            .micaFont(.callout, weight: .semibold)
            .foregroundStyle(MicaStyle.signalAmber)

            Spacer(minLength: MicaSpacing.module)

            Button(action: onKeepEditing) {
                Text(
                    MicaStrings.localizedKey(
                        "overview.layout_keep_editing",
                        language: language
                    )
                )
            }

            Button(role: .destructive, action: onDiscardAndContinue) {
                Text(
                    MicaStrings.localizedKey(
                        "overview.layout_discard_continue",
                        language: language
                    )
                )
            }
        }
        .padding(.horizontal, MicaBounds.chromeHorizontalPadding)
        .padding(.vertical, MicaSpacing.tight)
        .background(MicaDesignTokens.pageFill)
        .overlay(alignment: .bottom) { WorkbenchChromeSeparator() }
    }
}
