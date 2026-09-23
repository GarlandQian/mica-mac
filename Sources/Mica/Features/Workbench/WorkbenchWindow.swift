import AppKit
import MicaCore
import SwiftUI

// MARK: - Window

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var preferences: AppPreferencesStore
    @SceneStorage("workbenchDestination") private var destinationRawValue = WorkbenchDestination.overview.rawValue

    private let overviewPreferencesStore: OverviewPreferencesStore

    @State private var navigation = WorkbenchNavigationModel()
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
            .onChange(of: navigation.addControllerRequestID) { presentAddController() }
            .onChange(of: navigation.editControllerRequestID) {
                guard let router = appModel.selectedRouter else { return }
                presentEditController(router)
            }
            .onChange(of: preferences.language) { _, _ in
                applyPresentationLanguage()
            }
    }

    private var configuredContent: some View {
        @Bindable var navigation = navigation
        return navigationContent
            .navigationSplitViewStyle(.balanced)
            .environment(overviewPreferencesStore)
            .environment(overviewRuntime)
            .focusedValue(\.micaFocusedWorkbenchDestination, destination)
            .focusedValue(
                \.micaAddControllerRequestID,
                navigation.acceptsEditorCommands ? $navigation.addControllerRequestID : nil
            )
            .focusedValue(
                \.micaEditControllerRequestID,
                navigation.acceptsEditorCommands ? $navigation.editControllerRequestID : nil
            )
    }

    private var navigationContent: some View {
        NavigationSplitView {
            WorkbenchSidebarView(
                destination: destination,
                isControllerSwitchingEnabled: navigation.canSelectController,
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
                if let editor = navigation.editor {
                    RouterEditorView(
                        draft: editor.draft,
                        title: editor.titleKey,
                        discardRequestID: navigation.discardRequestID,
                        onClose: { finishEditor(editorID: editor.id) },
                        onDiscardConfirmed: { confirmDiscard(editorID: editor.id) },
                        onDiscardCancelled: {
                            navigation.cancelPendingIntent(editorID: editor.id)
                        },
                        onEditingStateChange: { isDirty, isSaving in
                            navigation.updateEditorState(
                                editorID: editor.id,
                                isDirty: isDirty,
                                isSaving: isSaving
                            )
                            updateCombinedCloseGuard()
                        }
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
        navigation.requestEditor(
            RouterEditorPresentation(
                titleKey: "editor.add_router",
                draft: appModel.draft()
            )
        )
    }

    private func presentEditController(_ router: RouterProfile) {
        navigation.requestEditor(
            RouterEditorPresentation(
                titleKey: "editor.edit_router",
                draft: appModel.draft(for: router)
            )
        )
    }

    private func requestDestination(_ next: WorkbenchDestination) {
        if let accepted = navigation.requestDestination(
            next,
            current: WorkbenchDestination(rawValue: destinationRawValue)
        ) {
            destinationRawValue = accepted.rawValue
        }
    }

    private func requestControllerSelection(_ router: RouterProfile) {
        guard navigation.canSelectController else { return }
        Task { @MainActor in
            await Task.yield()
            guard navigation.canSelectController,
                  let current = appModel.routers.first(where: { $0.id == router.id }) else { return }
            appModel.selectRouter(current)
        }
    }

    private func finishEditor(editorID: UUID) {
        navigation.finishEditor(editorID: editorID)
        updateCombinedCloseGuard()
    }

    private func confirmDiscard(editorID: UUID) {
        if let destination = navigation.confirmDiscard(editorID: editorID) {
            destinationRawValue = destination.rawValue
        }
        updateCombinedCloseGuard()
    }

    private func updateCombinedCloseGuard() {
        closeGuard.update(
            isDirty: navigation.editorIsDirty,
            isSaving: navigation.editorIsSaving,
            language: preferences.language
        )
    }
}
