import AppKit
import MicaCore
import SwiftUI

// MARK: - Window

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var preferences: AppPreferencesStore
    @SceneStorage("workbenchDestination") private var destinationRawValue = WorkbenchDestination.overview.rawValue

    private let overviewPreferencesStore: OverviewPreferencesStore

    @State private var editor: RouterEditorPresentation?
    @State private var pendingIntent: PendingEditorIntent?
    @State private var discardRequestID = 0
    @State private var addControllerRequestID = 0
    @State private var editControllerRequestID = 0
    @State private var editorIsDirty = false
    @State private var editorIsSaving = false
    @State private var didRegisterMainWindow = false
    @State private var closeGuard = MainWindowCloseGuard()
    @State private var workspaceStore = WorkbenchWorkspaceStore()
    @State private var overviewRuntime = OverviewWindowRuntime()

    init(overviewPreferencesStore: OverviewPreferencesStore) {
        self.overviewPreferencesStore = overviewPreferencesStore
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
            }
            .onAppear {
                registerMainWindowIfNeeded()
                applyPresentationLanguage()
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
    }

    private var configuredContent: some View {
        navigationContent
            .navigationSplitViewStyle(.balanced)
            .environment(overviewPreferencesStore)
            .environment(overviewRuntime)
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
                    && !editorIsSaving,
                onSelectController: requestControllerSelection,
                onAddController: presentAddController
            )
                .navigationSplitViewColumnWidth(
                    min: MicaTheme.Metrics.sidebarMin,
                    ideal: MicaTheme.Metrics.sidebarIdeal,
                    max: MicaTheme.Metrics.sidebarMax
                )
        } detail: {
            VStack(spacing: 0) {
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
        requestEditor(
            RouterEditorPresentation(
                titleKey: "editor.add_router",
                draft: appModel.draft()
            )
        )
    }

    private func presentEditController(_ router: RouterProfile) {
        requestEditor(
            RouterEditorPresentation(
                titleKey: "editor.edit_router",
                draft: appModel.draft(for: router)
            )
        )
    }

    private func requestDestination(_ next: WorkbenchDestination) {
        guard !editorIsSaving else { return }
        guard next.rawValue != destinationRawValue else { return }
        if editor != nil {
            pendingIntent = .destination(next)
            discardRequestID += 1
            return
        }
        destinationRawValue = next.rawValue
    }

    private func requestControllerSelection(_ router: RouterProfile) {
        guard editor == nil, !editorIsSaving else { return }
        Task { @MainActor in
            await Task.yield()
            appModel.selectRouter(router)
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
            isDirty: editorIsDirty,
            isSaving: editorIsSaving,
            language: preferences.language
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
