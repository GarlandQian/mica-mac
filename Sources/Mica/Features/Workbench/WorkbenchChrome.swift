import AppKit
import MicaCore
import SwiftUI

// MARK: - Navigation

enum WorkbenchDestination: String, CaseIterable, Identifiable {
    case overview
    case proxies
    case connections
    case logs
    case rules
    case sources
    case controllers
    case configuration
    case actions
    case diagnostics

    enum Group: CaseIterable, Identifiable {
        case workbench
        case controllerManagement

        var id: Self { self }

        var titleKey: String {
            switch self {
            case .workbench: "sidebar.group_workbench"
            case .controllerManagement: "sidebar.group_controller_management"
            }
        }
    }

    var id: String { rawValue }

    static let workbenchTabCases: [Self] = [
        .overview, .proxies, .connections, .logs, .rules, .sources,
    ]

    static let controllerManagementCases: [Self] = [
        .controllers, .configuration, .actions, .diagnostics,
    ]

    var group: Group {
        switch self {
        case .overview, .proxies, .connections, .logs, .rules, .sources:
            .workbench
        case .controllers, .configuration, .actions, .diagnostics:
            .controllerManagement
        }
    }

    var titleKey: String {
        switch self {
        case .overview: "navigation.overview"
        case .proxies: "navigation.proxies"
        case .connections: "dashboard.tab_connections"
        case .logs: "dashboard.tab_logs"
        case .rules: "dashboard.tab_rules"
        case .sources: "dashboard.tab_providers"
        case .controllers: "sidebar.controllers"
        case .configuration: "workbench.configuration"
        case .actions: "workbench.actions"
        case .diagnostics: "workspace.diagnostics"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .proxies: "point.3.connected.trianglepath.dotted"
        case .connections: "bolt.horizontal.circle"
        case .logs: "list.bullet.rectangle.portrait"
        case .rules: "arrow.triangle.branch"
        case .sources: "shippingbox"
        case .controllers: "server.rack"
        case .configuration: "slider.horizontal.3"
        case .actions: "bolt.badge.checkmark"
        case .diagnostics: "stethoscope"
        }
    }

    var shortcut: KeyEquivalent? {
        switch self {
        case .overview: "1"
        case .proxies: "2"
        case .connections: "3"
        case .logs: "4"
        case .rules: "5"
        case .sources: "6"
        case .controllers, .configuration, .actions, .diagnostics: nil
        }
    }

    var supportsSearch: Bool {
        switch self {
        case .proxies, .connections, .logs, .rules, .sources, .controllers:
            true
        case .overview, .configuration, .actions, .diagnostics:
            false
        }
    }

    var searchPromptKey: String {
        switch self {
        case .proxies: "routing.search_placeholder"
        case .rules: "dashboard.search_rules"
        case .controllers: "controllers.search_prompt"
        case .connections, .logs, .sources:
            "traffic.search_placeholder"
        case .overview, .configuration, .actions, .diagnostics:
            "traffic.search_placeholder"
        }
    }

    var requiresController: Bool {
        switch self {
        case .controllers:
            false
        default:
            true
        }
    }

    var liveSessionVisibleDestination: LiveSessionVisibleDestination {
        switch self {
        case .overview:
            .overview
        case .connections:
            .connections
        case .logs:
            .logs
        case .proxies, .rules, .sources, .controllers, .configuration,
             .actions, .diagnostics:
            .other
        }
    }
}

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
        .background(MicaDesignTokens.elevatedFill)
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Workbench Shell

struct WorkbenchRootView: View {
    @Environment(\.micaAppLanguage) private var language

    @Binding var destination: WorkbenchDestination

    let onAddController: () -> Void
    let onEditController: (RouterProfile) -> Void

    var body: some View {
        WorkbenchWorkspaceView(
            destination: $destination,
            onAddController: onAddController,
            onEditController: onEditController
        )
            .navigationTitle(
                MicaStrings.localizedKey(destination.titleKey, language: language)
            )
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if destination == .overview {
                    ToolbarItem(placement: .primaryAction) {
                        OverviewDashboardToolbarControl()
                    }
                    .sharedBackgroundVisibility(.hidden)
                }

                ToolbarItem(placement: .primaryAction) {
                    WorkbenchSessionControlButton(kind: .test)
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .primaryAction) {
                    WorkbenchSessionControlButton(kind: .refresh)
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .primaryAction) {
                    WorkbenchSessionControlButton(kind: .pause)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                WorkbenchBottomChrome()
            }
            .focusedValue(\.micaFocusedWorkbenchDestination, $destination)
            .background {
                WorkbenchRootLifecycleObserver(destination: destination)
            }
    }
}

private struct WorkbenchRootLifecycleObserver: View {
    @Environment(AppModel.self) private var appModel
    @Environment(OverviewDashboardWindowCoordinator.self) private var overviewCoordinator
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore

    let destination: WorkbenchDestination

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                if !appModel.routers.isEmpty {
                    retainControllers(appModel.routers)
                }
                appModel.registerLiveSessionWindowDemand(
                    overviewCoordinator.liveSessionWindowDemandID,
                    destination: destination.liveSessionVisibleDestination
                )
            }
            .onDisappear {
                workspaceStore.flushPendingPersistence()
                appModel.unregisterLiveSessionWindowDemand(
                    overviewCoordinator.liveSessionWindowDemandID
                )
            }
            .onChange(of: destination) { _, destination in
                workspaceStore.flushPendingPersistence()
                appModel.updateLiveSessionWindowDemand(
                    overviewCoordinator.liveSessionWindowDemandID,
                    destination: destination.liveSessionVisibleDestination
                )
            }
            .onChange(of: appModel.routers) { _, routers in
                retainControllers(routers)
            }
            .onChange(of: appModel.selectedRouterID) { previous, current in
                workspaceStore.flushPendingPersistence()
                if let previous, previous != current {
                    workspaceStore.clearSessionBoundState(controllerID: previous)
                }
                appModel.updateLiveSessionWindowDemand(
                    overviewCoordinator.liveSessionWindowDemandID,
                    destination: destination.liveSessionVisibleDestination
                )
            }
            .onChange(of: appModel.controllerSessionPresentation.state) { _, state in
                guard state == .stopped else { return }
                overviewCoordinator.runtimeRegistry.clear()
                if let controllerID = appModel.selectedRouterID {
                    workspaceStore.clearSessionBoundState(controllerID: controllerID)
                }
            }
    }

    private func retainControllers(_ routers: [RouterProfile]) {
        workspaceStore.retainControllers(Set(routers.map(\.id)))
    }
}

struct WorkbenchSidebarView: View {
    @Environment(\.micaAppLanguage) private var language

    @Binding var destination: WorkbenchDestination

    let isControllerSwitchingEnabled: Bool
    let onSelectController: (RouterProfile) -> Void
    let onAddController: () -> Void

    var body: some View {
        List {
            Section {
                WorkbenchSidebarControllerSwitcher(
                    isEnabled: isControllerSwitchingEnabled,
                    onSelectController: onSelectController,
                    onAddController: onAddController,
                    onManageControllers: {
                        destination = .controllers
                    }
                )
            }
            .listRowInsets(
                EdgeInsets(
                    top: MicaSpacing.tight,
                    leading: MicaSpacing.row,
                    bottom: MicaSpacing.tight,
                    trailing: MicaSpacing.row
                )
            )
            .listRowBackground(Color.clear)

            destinationSection(.workbench, destinations: WorkbenchDestination.workbenchTabCases)
            destinationSection(
                .controllerManagement,
                destinations: WorkbenchDestination.controllerManagementCases
            )
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .tint(MicaStyle.accent)
        .navigationTitle("Mica")
    }

    private func destinationSection(
        _ group: WorkbenchDestination.Group,
        destinations: [WorkbenchDestination]
    ) -> some View {
        Section {
            ForEach(destinations) { item in
                WorkbenchSidebarRow(
                    destination: item,
                    isSelected: item == destination,
                    action: {
                        destination = item
                    }
                )
                .listRowInsets(
                    EdgeInsets()
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } header: {
            Text(
                MicaStrings.localizedKey(
                    group.titleKey,
                    language: language
                )
            )
            .micaFont(.caption2, weight: .medium)
            .foregroundStyle(.secondary)
            .padding(.leading, MicaSpacing.row)
        }
    }
}

private struct WorkbenchSidebarRow: View {
    @Environment(\.micaAppLanguage) private var language

    let destination: WorkbenchDestination
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MicaSpacing.row) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(isSelected ? MicaStyle.accent : .clear)
                    .frame(width: 3, height: 18)
                    .accessibilityHidden(true)

                Image(systemName: destination.symbolName)
                    .foregroundStyle(isSelected ? MicaStyle.accent : .secondary)
                    .symbolRenderingMode(.monochrome)
                    .symbolVariant(isSelected ? .fill : .none)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                Text(
                    MicaStrings.localizedKey(
                        destination.titleKey,
                        language: language
                    )
                )
                .micaFont(.callout)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(.primary)
                .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, MicaSpacing.tight)
            .padding(.trailing, MicaSpacing.space2)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(
                        cornerRadius: 6,
                        style: .continuous
                    )
                    .fill(MicaStyle.navigationSelectionFill)
                }
            }
            .contentShape(.interaction, Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.interaction, Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Toolbar

private enum WorkbenchSessionControlKind: Equatable {
    case test
    case refresh
    case pause
}

private struct WorkbenchSessionControlButton: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let kind: WorkbenchSessionControlKind

    var body: some View {
        let title = MicaStrings.localizedKey(titleKey, language: language)
        let help = MicaStrings.localizedKey(helpKey, language: language)

        Button(action: perform) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(
                    width: MicaBounds.iconControlSize,
                    height: MicaBounds.iconControlSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(Text(title))
    }

    private var session: ControllerSessionPresentationState {
        appModel.controllerSessionPresentation
    }

    private var hasSelectedLiveSession: Bool {
        guard let selectedRouterID = appModel.selectedRouterID else {
            return false
        }
        return session.controllerID == selectedRouterID
    }

    private var titleKey: String {
        switch kind {
        case .test:
            "action.test"
        case .refresh:
            "action.refresh"
        case .pause:
            session.controls.dashboardUpdatesPaused ? "live.resume" : "live.pause"
        }
    }

    private var helpKey: String {
        switch kind {
        case .test:
            "dashboard.help_test_controller"
        case .refresh:
            "dashboard.help_refresh_controller"
        case .pause:
            titleKey
        }
    }

    private var systemImage: String {
        switch kind {
        case .test:
            MicaSymbols.Command.test
        case .refresh:
            MicaSymbols.Command.refresh
        case .pause:
            session.controls.dashboardUpdatesPaused
                ? MicaSymbols.Operation.resume
                : MicaSymbols.Operation.pause
        }
    }

    private var tint: Color {
        kind == .pause && session.controls.dashboardUpdatesPaused
            ? MicaStyle.signalAmber
            : .primary
    }

    private var isEnabled: Bool {
        switch kind {
        case .test:
            hasSelectedLiveSession && !appModel.isBusy
        case .refresh:
            hasSelectedLiveSession
                && !appModel.isBusy
                && !session.controls.dashboardUpdatesPaused
        case .pause:
            hasSelectedLiveSession
        }
    }

    private func perform() {
        switch kind {
        case .test:
            appModel.testSelectedRouter()
        case .refresh:
            appModel.refreshSelectedRouter()
        case .pause:
            appModel.toggleDashboardUpdatesPaused()
        }
    }
}

// MARK: - Status

struct WorkbenchOperationOutcomePresentation: Equatable {
    enum Tone: Equatable {
        case success
        case partial
        case failure
    }

    let tone: Tone
    let titleKey: String
    let symbolName: String
    let message: String
    let action: String?
    let target: String?
    let nextStep: String?

    init?(operationState: OperationState?) {
        guard let operationState else { return nil }

        switch operationState.kind {
        case .working:
            return nil
        case .success:
            tone = .success
            titleKey = "lifecycle.success"
            symbolName = "checkmark.circle.fill"
        case .partial:
            tone = .partial
            titleKey = "lifecycle.partial"
            symbolName = "exclamationmark.triangle.fill"
        case .error:
            tone = .failure
            titleKey = "lifecycle.failed"
            symbolName = "xmark.octagon.fill"
        }

        message = operationState.message
        action = Self.normalized(operationState.action)
        target = Self.normalized(operationState.target)
        nextStep = Self.normalized(operationState.nextStep)
    }

    var context: String? {
        [action, target]
            .compactMap { $0 }
            .joined(separator: " - ")
            .nilIfEmpty
    }

    private static func normalized(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private struct WorkbenchBottomChrome: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        WorkbenchStatusBar(operationState: appModel.operationState)
    }
}

private struct WorkbenchStatusBar: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let operationState: OperationState?

    var body: some View {
        let status = sessionStatus

        ViewThatFits(in: .horizontal) {
            statusRow(status: status, showsTimestamp: true)
                .fixedSize(horizontal: true, vertical: false)
            statusRow(status: status, showsTimestamp: false)
                .fixedSize(horizontal: true, vertical: false)
            compactStatusRow(status: status)
        }
        .micaFont(.caption)
        .frame(
            maxWidth: .infinity,
            minHeight: MicaBounds.statusBarHeight,
            alignment: .leading
        )
        .padding(.horizontal, MicaBounds.chromeHorizontalPadding)
        .background(MicaDesignTokens.pageFill)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }

    private func statusRow(
        status: WorkbenchSessionStatus,
        showsTimestamp: Bool
    ) -> some View {
        HStack(spacing: MicaSpacing.module) {
            activityIdentity(status: status, compact: false)

            if showsTimestamp, let timestamp = status.timestamp {
                statusDivider
                timestampLabel(timestamp)
            }
        }
    }

    private func compactStatusRow(status: WorkbenchSessionStatus) -> some View {
        HStack(spacing: MicaSpacing.module) {
            activityIdentity(status: status, compact: true)
                .layoutPriority(2)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func activityIdentity(
        status: WorkbenchSessionStatus,
        compact: Bool
    ) -> some View {
        if let operationOutcome {
            operationIdentity(operationOutcome, compact: compact)
        } else {
            sessionIdentity(status)
        }
    }

    private func sessionIdentity(_ status: WorkbenchSessionStatus) -> some View {
        Label {
            Text(verbatim: status.summary)
                .foregroundStyle(.primary)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tint)
                .accessibilityHidden(true)
        }
        .help(status.summary)
    }

    private func operationIdentity(
        _ presentation: WorkbenchOperationOutcomePresentation,
        compact: Bool
    ) -> some View {
        HStack(spacing: MicaSpacing.row) {
            Image(systemName: presentation.symbolName)
                .foregroundStyle(operationTint(presentation.tone))
                .accessibilityHidden(true)

            Text(
                MicaStrings.localizedKey(
                    presentation.titleKey,
                    language: language
                )
            )
            .fontWeight(.semibold)

            Text(verbatim: presentation.message)
                .foregroundStyle(.primary)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)

            if !compact, let context = presentation.context {
                statusDivider

                Text(verbatim: context)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            if !compact, let nextStep = presentation.nextStep {
                statusDivider

                Label {
                    Text(verbatim: nextStep)
                        .lineLimit(1)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: MicaSymbols.Data.nextStep)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.secondary)
            }
        }
        .help(operationHelp(presentation))
    }

    private func operationTint(
        _ tone: WorkbenchOperationOutcomePresentation.Tone
    ) -> Color {
        switch tone {
        case .success:
            MicaStyle.signalMint
        case .partial:
            MicaStyle.signalAmber
        case .failure:
            MicaStyle.signalRed
        }
    }

    private func operationHelp(
        _ presentation: WorkbenchOperationOutcomePresentation
    ) -> String {
        var lines = [
            MicaStrings.localizedKey(
                presentation.titleKey,
                language: language
            ),
            presentation.message,
        ]

        if let context = presentation.context {
            lines.append(context)
        }

        if let nextStep = presentation.nextStep {
            lines.append(
                [
                    MicaStrings.localizedKey(
                        "diagnostics.check_next",
                        language: language
                    ),
                    nextStep,
                ]
                .joined(separator: ": ")
            )
        }

        return lines.joined(separator: "\n")
    }

    private var statusDivider: some View {
        Divider()
            .frame(height: 14)
    }

    private func timestampLabel(_ timestamp: Date) -> some View {
        Label {
            Text(timestamp, format: .dateTime.hour().minute().second())
                .micaFont(.callout, design: .monospaced)
        } icon: {
            Image(systemName: "clock")
                .accessibilityHidden(true)
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var operationOutcome: WorkbenchOperationOutcomePresentation? {
        WorkbenchOperationOutcomePresentation(operationState: operationState)
    }

    private var sessionStatus: WorkbenchSessionStatus {
        let session = appModel.controllerSessionPresentation
        let state = session.state
        let lastSuccessAt = session.lastSuccessAt

        if let operation = operationState, operation.kind == .working {
            return WorkbenchSessionStatus(
                summary: operation.message,
                symbol: "arrow.clockwise",
                tint: MicaStyle.signalCyan,
                timestamp: lastSuccessAt
            )
        }

        let controls = session.controls
        if controls.dashboardUpdatesPaused {
            return WorkbenchSessionStatus(
                summary: MicaStrings.localizedKey(
                    "operation.dashboard_updates_paused",
                    language: language
                ),
                symbol: "pause.circle.fill",
                tint: MicaStyle.signalAmber,
                timestamp: controls.presentationPausedAt
            )
        }

        switch state {
        case .idle:
            return makeSessionStatus(
                state: state,
                lastSuccessAt: lastSuccessAt,
                symbol: "circle",
                tint: .secondary
            )
        case .connecting:
            return makeSessionStatus(
                state: state,
                lastSuccessAt: lastSuccessAt,
                symbol: "arrow.triangle.2.circlepath",
                tint: MicaStyle.signalCyan
            )
        case .staleReconnecting(let message):
            return WorkbenchSessionStatus(
                summary: message,
                symbol: "arrow.triangle.2.circlepath",
                tint: MicaStyle.signalAmber,
                timestamp: lastSuccessAt
            )
        case .live:
            return makeSessionStatus(
                state: state,
                lastSuccessAt: lastSuccessAt,
                symbol: "checkmark.circle.fill",
                tint: MicaStyle.signalMint
            )
        case .partial(let message):
            return WorkbenchSessionStatus(
                summary: message,
                symbol: "exclamationmark.triangle.fill",
                tint: MicaStyle.signalAmber,
                timestamp: lastSuccessAt
            )
        case .failedBeforeFirstSnapshot(let message):
            return WorkbenchSessionStatus(
                summary: message,
                symbol: "xmark.octagon.fill",
                tint: MicaStyle.signalRed,
                timestamp: nil
            )
        case .failed(let message):
            return WorkbenchSessionStatus(
                summary: message,
                symbol: "xmark.octagon.fill",
                tint: MicaStyle.signalRed,
                timestamp: lastSuccessAt
            )
        case .stopped:
            return makeSessionStatus(
                state: state,
                lastSuccessAt: lastSuccessAt,
                symbol: "stop.circle",
                tint: .secondary
            )
        }
    }

    private func makeSessionStatus(
        state: LiveSessionState,
        lastSuccessAt: Date?,
        symbol: String,
        tint: Color
    ) -> WorkbenchSessionStatus {
        WorkbenchSessionStatus(
            summary: state.label(language: language),
            symbol: symbol,
            tint: tint,
            timestamp: lastSuccessAt
        )
    }
}

private struct WorkbenchSessionStatus {
    let summary: String
    let symbol: String
    let tint: Color
    let timestamp: Date?
}
