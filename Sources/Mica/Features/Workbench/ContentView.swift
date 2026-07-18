import AppKit
import MicaCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var preferences: AppPreferencesStore
    @AppStorage("appLanguage") private var appLanguageRawValue = AppLanguage.system.rawValue
    @AppStorage("appAppearance") private var appAppearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("appFontScale") private var appFontScaleRawValue = AppFontScale.comfortable.rawValue
    @AppStorage("workbenchDestination") private var destinationRawValue = WorkbenchDestination.overview.rawValue
    @State private var routerEditor: RouterEditorPresentation?
    @State private var addControllerRequestID = 0
    @State private var editControllerRequestID = 0
    @State private var didRegisterMainWindow = false
    @State private var discardRequestID = 0
    @State private var pendingDestination: WorkbenchDestination?
    @State private var pendingEditorPresentation: RouterEditorPresentation?
    @State private var windowCloseGuard = MainWindowCloseGuard()
    @State private var editorIsSaving = false

    private var appLanguage: AppLanguage { AppLanguage.stored(appLanguageRawValue) }
    private var appAppearance: AppAppearance { AppAppearance.stored(appAppearanceRawValue) }
    private var appFontScale: AppFontScale { AppFontScale.stored(appFontScaleRawValue) }

    private var destination: Binding<WorkbenchDestination> {
        Binding {
            WorkbenchDestination(rawValue: destinationRawValue) ?? .overview
        } set: { destination in
            guard !editorIsSaving else { return }
            if routerEditor != nil {
                pendingDestination = destination
                pendingEditorPresentation = nil
                discardRequestID += 1
                return
            }
            destinationRawValue = destination.rawValue
        }
    }

    var body: some View {
        NavigationSplitView {
            WorkbenchSidebarView(destination: destination)
            .navigationSplitViewColumnWidth(
                min: 240 * appFontScale.multiplier,
                ideal: 290 * appFontScale.multiplier,
                max: 380 * appFontScale.multiplier
            )
        } detail: {
            if let editor = routerEditor {
                RouterEditorView(
                    draft: editor.draft,
                    title: editor.title,
                    discardRequestID: discardRequestID,
                    onClose: closeEditor,
                    onDiscardConfirmed: performPendingEditorIntent,
                    onEditingStateChange: updateWindowCloseGuard
                )
                .id(editor.id)
                .environment(appModel)
            } else {
                WorkbenchRootView(
                    destination: destination,
                    onAddController: presentAddController,
                    onEditController: presentEditController
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .focusedValue(\.micaFocusedWorkbenchDestination, destination)
        .focusedValue(
            \.micaAddControllerRequestID,
            editorIsSaving ? nil : $addControllerRequestID
        )
        .focusedValue(
            \.micaEditControllerRequestID,
            editorIsSaving ? nil : $editControllerRequestID
        )
        .onChange(of: addControllerRequestID) { presentAddController() }
        .onChange(of: editControllerRequestID) {
            guard let router = appModel.selectedRouter else { return }
            presentEditController(router)
        }
        .task { appModel.loadPersistedState() }
        .micaAppPreferences(language: appLanguage, appearance: appAppearance, fontScale: appFontScale)
        .onAppear {
            if !didRegisterMainWindow {
                didRegisterMainWindow = true
                appModel.mainWindowDidAppear()
            }
            Task { @MainActor in
                await Task.yield()
                windowCloseGuard.attachToCurrentMainWindow()
                windowCloseGuard.update(
                    isDirty: false,
                    isSaving: false,
                    language: appLanguage
                )
            }
            migrateLegacyNavigationIfNeeded()
            syncObservedPreferences()
        }
        .onDisappear {
            if didRegisterMainWindow {
                didRegisterMainWindow = false
                appModel.mainWindowDidDisappear()
            }
            windowCloseGuard.detach()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            appModel.systemWillSleep()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            appModel.systemDidWake()
        }
        .onChange(of: appLanguage.rawValue) { _, _ in syncObservedPreferences() }
        .onChange(of: appAppearance.rawValue) { _, _ in syncObservedPreferences() }
        .onChange(of: appFontScale.rawValue) { _, _ in syncObservedPreferences() }
    }

    private func migrateLegacyNavigationIfNeeded() {
        let defaults = UserDefaults.standard
        // Skip when the new destination key already holds a value.
        guard defaults.object(forKey: "workbenchDestination") == nil else { return }

        destinationRawValue = WorkbenchDestination.migrated(
            fromArea: defaults.string(forKey: "workbenchArea"),
            activitySection: defaults.string(forKey: "workbenchActivitySection"),
            resourcesSection: defaults.string(forKey: "workbenchResourcesSection"),
            systemSection: defaults.string(forKey: "workbenchSystemSection")
        ).rawValue
    }

    private func syncObservedPreferences() {
        Bundle.setMicaLocalizationLanguage(MicaStrings.resolvedLanguageCode(for: appLanguage))
        appModel.applyPresentationLanguage(appLanguage)
        appAppearance.applyToApplication()

        if preferences.language != appLanguage { preferences.language = appLanguage }
        if preferences.appearance != appAppearance { preferences.appearance = appAppearance }
        if preferences.fontScale != appFontScale { preferences.fontScale = appFontScale }
    }

    private func presentAddController() {
        requestEditorPresentation(
            RouterEditorPresentation(title: "editor.add_router", draft: appModel.draft())
        )
    }

    private func presentEditController(_ router: RouterProfile) {
        requestEditorPresentation(
            RouterEditorPresentation(title: "editor.edit_router", draft: appModel.draft(for: router))
        )
    }

    private func requestEditorPresentation(_ presentation: RouterEditorPresentation) {
        guard !editorIsSaving else { return }
        guard routerEditor != nil else {
            routerEditor = presentation
            return
        }

        pendingDestination = nil
        pendingEditorPresentation = presentation
        discardRequestID += 1
    }

    private func closeEditor() {
        pendingDestination = nil
        pendingEditorPresentation = nil
        routerEditor = nil
        editorIsSaving = false
        updateWindowCloseGuard(isDirty: false, isSaving: false)
    }

    private func performPendingEditorIntent() {
        if let pendingEditorPresentation {
            self.pendingEditorPresentation = nil
            pendingDestination = nil
            routerEditor = pendingEditorPresentation
            return
        }

        if let pendingDestination {
            destinationRawValue = pendingDestination.rawValue
            self.pendingDestination = nil
        }
        routerEditor = nil
        editorIsSaving = false
        updateWindowCloseGuard(isDirty: false, isSaving: false)
    }

    private func updateWindowCloseGuard(isDirty: Bool, isSaving: Bool) {
        editorIsSaving = isSaving
        windowCloseGuard.update(
            isDirty: isDirty,
            isSaving: isSaving,
            language: appLanguage
        )
    }
}

struct RouterEditorPresentation: Identifiable {
    let id: RouterDraft.ID
    let title: String
    let draft: RouterDraft

    init(title: String, draft: RouterDraft) {
        self.id = draft.id
        self.title = title
        self.draft = draft
    }
}
