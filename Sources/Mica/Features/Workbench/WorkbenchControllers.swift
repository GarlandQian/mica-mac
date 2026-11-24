import AppKit
import Foundation
import MicaCore
import SwiftUI

// MARK: - Controllers

private struct WorkbenchControllerStatus {
    let label: String
    let symbol: String
    let tint: Color
}

private enum WorkbenchControllerMove {
    case up
    case down
}

/// Shared controller status label used by the Controllers list rows and the
/// workspace-inspector detail (Mica Ops redesign, design.md §3).
private struct WorkbenchControllerStatusView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let profile: RouterProfile

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .micaThemeFont(.caption)
            .labelStyle(MicaStatusLabelStyle(tint: status.tint))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var status: WorkbenchControllerStatus {
        if appModel.selectedRouterID == profile.id {
            switch appModel.connectionState {
            case .disconnected:
                return WorkbenchControllerStatus(
                    label: appModel.connectionState.label(language: language),
                    symbol: "circle",
                    tint: .secondary
                )
            case .connecting:
                return WorkbenchControllerStatus(
                    label: appModel.connectionState.label(language: language),
                    symbol: "arrow.triangle.2.circlepath",
                    tint: MicaTheme.textSecondary
                )
            case .connected:
                return WorkbenchControllerStatus(
                    label: appModel.connectionState.label(language: language),
                    symbol: "checkmark.circle.fill",
                    tint: MicaTheme.statusOK
                )
            case .failed:
                return WorkbenchControllerStatus(
                    label: appModel.connectionState.label(language: language),
                    symbol: "xmark.circle.fill",
                    tint: MicaTheme.statusError
                )
            }
        }

        let health = appModel.trialSession(for: profile).sessionHealth
        switch health {
        case .idle:
            return WorkbenchControllerStatus(
                label: health.label(language: language),
                symbol: "minus.circle",
                tint: .secondary
            )
        case .fresh:
            return WorkbenchControllerStatus(
                label: health.label(language: language),
                symbol: "checkmark.circle.fill",
                tint: MicaTheme.statusOK
            )
        case .stale, .partial:
            return WorkbenchControllerStatus(
                label: health.label(language: language),
                symbol: "exclamationmark.triangle.fill",
                tint: MicaTheme.statusWarning
            )
        case .failed:
            return WorkbenchControllerStatus(
                label: health.label(language: language),
                symbol: "xmark.circle.fill",
                tint: MicaTheme.statusError
            )
        }
    }
}

struct WorkbenchControllersView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language

    @Binding var searchText: String

    let onAddController: () -> Void
    let onEditController: (RouterProfile) -> Void

    var body: some View {
        WorkbenchPageScaffold {
            commandBar
        } content: {
            if appModel.routers.isEmpty {
                WorkbenchStateView(
                    kind: .empty,
                    titleKey: "sidebar.no_controllers",
                    detailKey: "sidebar.no_controllers_message",
                    actionTitleKey: "sidebar.add_controller",
                    actionSystemImage: "plus",
                    action: onAddController
                )
            } else if filteredProfiles.isEmpty {
                WorkbenchStateView(
                    kind: .filterEmpty,
                    titleKey: "controllers.no_match_title",
                    detailKey: "controllers.no_match_description"
                )
            } else {
                controllerList
            }
        }
        .onAppear {
            reconcileManagementSelection(initialAppear: true)
        }
        .onChange(of: appModel.routers) { _, _ in
            reconcileManagementSelection(initialAppear: false)
        }
        .onChange(of: searchText) {
            reconcileManagementSelection(initialAppear: false)
        }
        .onChange(of: language) {
            reconcileManagementSelection(initialAppear: false)
        }
        .onChange(of: workspaceStore.isInspectorPresented) { _, presented in
            if !presented {
                workspaceStore.didDismissControllersInspector = true
            }
        }
        .onChange(of: workspaceStore.inspectorSelection) { _, selection in
            guard selection == .none else { return }
            workspaceStore.didDismissControllersInspector = true
            if managementSelection != nil {
                workspaceStore.update(
                    controllerID: nil,
                    destination: .controllers
                ) { workspace in
                    workspace.selectedItemID = nil
                }
            }
        }
    }

    private var commandBar: some View {
        WorkbenchCommandBar {
            WorkbenchManagementHeader(
                systemImage: "server.rack",
                titleKey: "sidebar.controllers"
            )
        } controls: {
            WorkbenchStatusBadge(
                text: Self.countLabel(
                    filteredProfiles.count,
                    language: language
                ),
                tint: MicaTheme.textSecondary
            )
        } commands: {
            Button(action: onAddController) {
                Label(
                    MicaStrings.localizedKey("sidebar.add_controller", language: language),
                    systemImage: "plus"
                )
                .micaThemeFont(.caption, weight: .medium)
                .fixedSize()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    static func countLabel(_ count: Int, language: AppLanguage) -> String {
        if count == 1 {
            return MicaStrings.localizedKey("controllers.count_one", language: language)
        }
        return MicaStrings.localized("controllers.count \(count)", language: language)
    }

    private var controllerList: some View {
        List(selection: managementSelectionBinding) {
            ForEach(filteredProfiles) { profile in
                controllerRow(profile)
                    .tag(profile.id)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            onEditController(profile)
                        }
                    )
            }
            // Drag to reorder follows the persisted order, so it is offered
            // only while the complete, unfiltered list is visible.
            .onMove(perform: reorderAction)
        }
        .contextMenu(forSelectionType: RouterProfile.ID.self) { ids in
            if let id = ids.first,
               let profile = filteredProfiles.first(where: { $0.id == id }) {
                controllerContextMenu(for: profile)
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .micaObserveScrollPerformance()
        .scrollContentBackground(.hidden)
        .background(MicaTheme.canvas)
        .accessibilityLabel(
            MicaStrings.localizedKey("sidebar.controllers", language: language)
        )
    }

    @ViewBuilder
    private func controllerContextMenu(for profile: RouterProfile) -> some View {
        Button {
            setManagementSelection(profile.id, revealInspector: true)
        } label: {
            Label(MicaStrings.localizedKey("routing.inspect_details", language: language), systemImage: "sidebar.trailing")
        }
        if appModel.selectedRouterID != profile.id {
            Button {
                appModel.selectRouter(profile)
            } label: {
                Label(MicaStrings.localizedKey("controllers.use", language: language), systemImage: "play.fill")
            }
        }
        Button {
            onEditController(profile)
        } label: {
            Label(MicaStrings.localizedKey("sidebar.edit", language: language), systemImage: "pencil")
        }
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(profile.endpointURL, forType: .string)
        } label: {
            Label(MicaStrings.localizedKey("action.copy", language: language), systemImage: "doc.on.doc")
        }
        if searchText.managementNonEmpty == nil,
           let index = appModel.routers.firstIndex(where: { $0.id == profile.id }) {
            Divider()
            if index > 0 {
                Button {
                    moveProfiles(from: IndexSet(integer: index), to: index - 1)
                } label: {
                    Label(MicaStrings.localizedKey("controllers.move_up", language: language), systemImage: "arrow.up")
                }
            }
            if index < appModel.routers.count - 1 {
                Button {
                    moveProfiles(from: IndexSet(integer: index), to: index + 2)
                } label: {
                    Label(MicaStrings.localizedKey("controllers.move_down", language: language), systemImage: "arrow.down")
                }
            }
        }
    }

    /// Identity leads; type and live state align in a trailing column, and
    /// every inactive controller offers the one explicit Use command.
    private func controllerRow(_ profile: RouterProfile) -> some View {
        let isActive = appModel.selectedRouterID == profile.id

        return HStack(alignment: .center, spacing: MicaTheme.Spacing.space3) {
            Image(systemName: profile.controllerKind.editorSymbol)
                .symbolRenderingMode(.monochrome)
                .micaThemeFont(.title3, weight: .medium)
                .foregroundStyle(isActive ? MicaTheme.accent : MicaTheme.textSecondary)
                .frame(width: 36, height: 36)
                .background(
                    isActive ? MicaTheme.accent.opacity(0.14) : MicaTheme.surface,
                    in: RoundedRectangle(cornerRadius: MicaTheme.Metrics.moduleRadius, style: .continuous)
                )
                .accessibilityHidden(true)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: MicaTheme.Spacing.space3) {
                    controllerIdentity(profile, isActive: isActive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    controllerFacts(profile)
                        .frame(width: 200, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                    controllerIdentity(profile, isActive: isActive)
                    HStack(spacing: MicaTheme.Spacing.space2) {
                        controllerFacts(profile)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isActive {
                WorkbenchStatusBadge(
                    text: MicaStrings.localizedKey("controllers.active", language: language),
                    tint: MicaTheme.accent
                )
                .fixedSize()
            } else {
                WorkbenchControllerUseButton(profile: profile, compact: true)
            }
        }
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private func controllerIdentity(_ profile: RouterProfile, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: profile.displayName)
                .micaThemeFont(.body, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: profile.endpointURL)
                .micaThemeFont(.dataCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            isActive ? MicaStrings.localizedKey("controllers.active", language: language) : ""
        )
    }

    private func controllerFacts(_ profile: RouterProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            controllerKindLabel(profile)
            WorkbenchControllerStatusView(profile: profile)
        }
    }

    private var reorderAction: ((IndexSet, Int) -> Void)? {
        guard searchText.managementNonEmpty == nil else { return nil }
        return { source, destination in
            moveProfiles(from: source, to: destination)
        }
    }

    private func moveProfiles(from source: IndexSet, to destination: Int) {
        guard let from = source.first,
              filteredProfiles.indices.contains(from) else { return }
        let profile = filteredProfiles[from]
        let target = destination > from ? destination - 1 : destination
        guard target != from else { return }
        Task {
            do {
                try await appModel.moveRouter(profile.id, to: target)
            } catch {
                appModel.operationState = .error(
                    AppModel.routerTrialFailureMessage(for: error, language: language),
                    action: MicaStrings.localizedKey("controllers.reorder", language: language),
                    target: profile.displayName,
                    nextStep: MicaStrings.localizedKey("action.retry", language: language)
                )
            }
        }
    }

    private func controllerKindLabel(_ profile: RouterProfile) -> some View {
        Text(verbatim: profile.controllerKind.micaLabel(language: language))
            .micaThemeFont(.caption)
            .foregroundStyle(MicaTheme.textSecondary)
    }

    private var filteredProfiles: [RouterProfile] {
        WorkbenchControllerListProjection.filtered(
            appModel.routers,
            query: searchText
        ) { profile in
            profile.controllerKind.micaLabel(language: language)
        }
    }

    private var managementSelection: RouterProfile.ID? {
        guard let storedID = workspaceStore.workspace(
            controllerID: nil,
            destination: .controllers
        ).selectedItemID else {
            return nil
        }
        return RouterProfile.ID(uuidString: storedID)
    }

    private var managementSelectionBinding: Binding<RouterProfile.ID?> {
        Binding(
            get: { managementSelection },
            set: { next in
                setManagementSelection(next, revealInspector: next != nil)
            }
        )
    }

    private func setManagementSelection(
        _ id: RouterProfile.ID?,
        revealInspector: Bool
    ) {
        workspaceStore.update(
            controllerID: nil,
            destination: .controllers
        ) { workspace in
            workspace.selectedItemID = id?.uuidString
        }
        if let id {
            if revealInspector || workspaceStore.isInspectorPresented {
                workspaceStore.selectInspector(
                    .controller(id: id),
                    revealInspector: revealInspector
                )
            }
        } else {
            workspaceStore.clearInspectorSelection(ownedBy: .controllers)
        }
    }

    private func reconcileManagementSelection(initialAppear: Bool) {
        if workspaceStore.didDismissControllersInspector, managementSelection == nil {
            workspaceStore.clearInspectorSelection(ownedBy: .controllers)
            return
        }
        let next = WorkbenchControllerListProjection.reconciledSelection(
            storedID: managementSelection,
            activeID: appModel.selectedRouterID,
            profiles: appModel.routers,
            query: searchText
        ) { profile in
            profile.controllerKind.micaLabel(language: language)
        }
        let shouldReveal = initialAppear && !workspaceStore.didDismissControllersInspector
        setManagementSelection(next, revealInspector: shouldReveal)
    }
}

/// Controller detail in the workspace inspector (Mica Ops redesign, design.md
/// §3): identity, capability-gated actions, connection fields, and the
/// connection-test report for the selected controller.
struct WorkbenchControllerInspector: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language

    let profile: RouterProfile
    let onEditController: (RouterProfile) -> Void

    @State private var pendingDelete: WorkbenchControllerDeleteConfirmation?
    @State private var testTask: Task<Void, Never>?

    var body: some View {
        let controllerStatus = inspectorStatus(for: profile)
        WorkbenchDataInspectorShell(
            title: profile.displayName,
            subtitle: profile.controllerKind.micaLabel(language: language),
            statusText: controllerStatus.label,
            statusTint: controllerStatus.tint,
            close: { workspaceStore.dismissInspector() }
        ) {
            WorkbenchDataInspectorSection("sidebar.controllers") {
                controllerDetailActions(profile)
                if let pendingDelete,
                   pendingDelete.profileID == profile.id,
                   isCurrent(pendingDelete) {
                    deleteConfirmation(profile, confirmation: pendingDelete)
                }
            }

            WorkbenchDataInspectorSection("settings.connection") {
                WorkbenchDataInspectorField(
                    titleKey: "settings.controller_endpoint",
                    value: profile.endpointURL,
                    monospaced: true
                )
                WorkbenchDataInspectorField(
                    titleKey: "settings.controller_type",
                    value: profile.controllerKind.micaLabel(language: language)
                )
                WorkbenchDataInspectorField(
                    titleKey: "diagnostics.last_connected",
                    value: lastSuccessText(profile),
                    monospaced: hasDisplayableLastSuccess(profile)
                )
            }

            if let report = workspaceStore.controllerConnectionTests.report(for: profile) {
                WorkbenchConnectionTestReportView(
                    profile: profile,
                    report: report
                )
            } else {
                WorkbenchDataInspectorSection("editor.connection_diagnosis") {
                    WorkbenchManagementInlineState(
                        systemImage: MicaSymbols.Command.test,
                        title: MicaStrings.localizedKey("editor.test", language: language),
                        detail: MicaStrings.localizedKey(
                            "command.action_test_detail",
                            language: language
                        ),
                        tint: MicaTheme.textSecondary,
                        isLoading: isTesting(profile)
                    )
                }
            }
        }
        .id(profile.id)
        .accessibilityLabel(
            MicaStrings.localizedKey("controllers.controller", language: language)
        )
        .onAppear {
            workspaceStore.controllerConnectionTests.reconcile(profiles: appModel.routers)
        }
        .onDisappear {
            testTask?.cancel()
            testTask = nil
        }
        .onChange(of: appModel.routers) { _, profiles in
            workspaceStore.controllerConnectionTests.reconcile(profiles: profiles)
            let ids = profiles.map(\.id)
            if let pendingDelete, !ids.contains(pendingDelete.profileID) {
                self.pendingDelete = nil
            }
        }
        .onChange(of: appModel.selectedRouterID) { pendingDelete = nil }
        .onChange(of: appModel.controllerSessionPresentation.generation) { pendingDelete = nil }
        .onChange(of: profile.id) {
            pendingDelete = nil
            testTask?.cancel()
            testTask = nil
        }
    }

    private func inspectorStatus(for profile: RouterProfile) -> WorkbenchControllerStatus {
        if appModel.selectedRouterID == profile.id {
            switch appModel.connectionState {
            case .disconnected:
                return WorkbenchControllerStatus(
                    label: appModel.connectionState.label(language: language),
                    symbol: "circle",
                    tint: .secondary
                )
            case .connecting:
                return WorkbenchControllerStatus(
                    label: appModel.connectionState.label(language: language),
                    symbol: "arrow.triangle.2.circlepath",
                    tint: MicaTheme.textSecondary
                )
            case .connected:
                return WorkbenchControllerStatus(
                    label: appModel.connectionState.label(language: language),
                    symbol: "checkmark.circle.fill",
                    tint: MicaTheme.statusOK
                )
            case .failed:
                return WorkbenchControllerStatus(
                    label: appModel.connectionState.label(language: language),
                    symbol: "xmark.circle.fill",
                    tint: MicaTheme.statusError
                )
            }
        }

        let health = appModel.trialSession(for: profile).sessionHealth
        switch health {
        case .idle:
            return WorkbenchControllerStatus(
                label: health.label(language: language),
                symbol: "minus.circle",
                tint: .secondary
            )
        case .fresh:
            return WorkbenchControllerStatus(
                label: health.label(language: language),
                symbol: "checkmark.circle.fill",
                tint: MicaTheme.statusOK
            )
        case .stale, .partial:
            return WorkbenchControllerStatus(
                label: health.label(language: language),
                symbol: "exclamationmark.triangle.fill",
                tint: MicaTheme.statusWarning
            )
        case .failed:
            return WorkbenchControllerStatus(
                label: health.label(language: language),
                symbol: "xmark.circle.fill",
                tint: MicaTheme.statusError
            )
        }
    }

    private func controllerDetailActions(_ profile: RouterProfile) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaTheme.Spacing.space2) {
                primaryActionButtons(profile)
                Divider()
                    .frame(height: 18)
                secondaryIconButtons(profile)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                HStack(spacing: MicaTheme.Spacing.space2) {
                    primaryActionButtons(profile)
                    Spacer(minLength: 0)
                }
                HStack(spacing: MicaTheme.Spacing.space1) {
                    secondaryIconButtons(profile)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func primaryActionButtons(_ profile: RouterProfile) -> some View {
        if appModel.selectedRouterID == profile.id {
            WorkbenchStatusBadge(
                text: MicaStrings.localizedKey("controllers.active", language: language),
                tint: MicaTheme.accent
            )
        } else {
            WorkbenchControllerUseButton(profile: profile, compact: true)
        }

        Button {
            testConnection(profile)
        } label: {
            HStack(spacing: MicaTheme.Spacing.space1) {
                if isTesting(profile) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: MicaSymbols.Command.test)
                }
                Text(
                    MicaStrings.localizedKey(
                        isTesting(profile) ? "editor.testing" : "action.test",
                        language: language
                    )
                )
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isTesting(profile))
        .accessibilityLabel(MicaStrings.localizedKey("action.test", language: language))
    }

    @ViewBuilder
    private func secondaryIconButtons(_ profile: RouterProfile) -> some View {
        controllerIcon(titleKey: "sidebar.edit", symbol: "pencil") {
            onEditController(profile)
        }
        controllerIcon(
            titleKey: "controllers.move_up",
            symbol: "arrow.up",
            isEnabled: canMove(.up)
        ) {
            moveSelection(.up)
        }
        controllerIcon(
            titleKey: "controllers.move_down",
            symbol: "arrow.down",
            isEnabled: canMove(.down)
        ) {
            moveSelection(.down)
        }
        controllerIcon(
            titleKey: "sidebar.delete_button",
            symbol: "trash",
            tint: MicaTheme.statusError
        ) {
            requestDelete(profile)
        }
    }

    private func hasDisplayableLastSuccess(_ profile: RouterProfile) -> Bool {
        let candidate = appModel.selectedRouterID == profile.id
            ? appModel.controllerSessionPresentation.lastSuccessAt ?? profile.lastConnectedAt
            : profile.lastConnectedAt
        return workbenchDisplayableDate(candidate) != nil
    }

    private func lastSuccessText(_ profile: RouterProfile) -> String {
        let candidate = appModel.selectedRouterID == profile.id
            ? appModel.controllerSessionPresentation.lastSuccessAt ?? profile.lastConnectedAt
            : profile.lastConnectedAt
        guard let date = workbenchDisplayableDate(candidate) else {
            return MicaStrings.localizedKey("settings.never", language: language)
        }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(language.resolvedLocale)
        )
    }

    private func testConnection(_ profile: RouterProfile) {
        testTask?.cancel()
        let draft = appModel.draft(for: profile)
        let intent = workspaceStore.controllerConnectionTests.begin(profile: profile)

        testTask = Task {
            let report = await appModel.testConnection(draft: draft)
            guard !Task.isCancelled else { return }
            workspaceStore.controllerConnectionTests.receive(
                report,
                for: intent,
                profiles: appModel.routers
            )
            testTask = nil
        }
    }

    private func controllerIcon(
        titleKey: String,
        symbol: String,
        tint: Color = .primary,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: MicaTheme.Metrics.iconControlSize, height: MicaTheme.Metrics.iconControlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(tint)
        .disabled(!isEnabled)
        .help(MicaStrings.localizedKey(titleKey, language: language))
        .accessibilityLabel(MicaStrings.localizedKey(titleKey, language: language))
    }

    private func isTesting(_ profile: RouterProfile) -> Bool {
        workspaceStore.controllerConnectionTests.isTesting(profile)
            || appModel.trialSession(for: profile).commandLog.contains {
                $0.action == .test && !$0.status.isTerminal
            }
    }

    private func canMove(_ direction: WorkbenchControllerMove) -> Bool {
        guard workspaceStore.workspace(
            controllerID: nil,
            destination: .controllers
        ).searchText.managementNonEmpty == nil,
              let index = appModel.routers.firstIndex(where: { $0.id == profile.id }) else {
            return false
        }
        switch direction {
        case .up: return index > 0
        case .down: return index < appModel.routers.count - 1
        }
    }

    private func moveSelection(_ direction: WorkbenchControllerMove) {
        guard let index = appModel.routers.firstIndex(where: { $0.id == profile.id }) else {
            return
        }
        let target = direction == .up ? index - 1 : index + 1
        guard appModel.routers.indices.contains(target) else { return }
        let action = MicaStrings.localizedKey(
            direction == .up ? "controllers.move_up" : "controllers.move_down",
            language: language
        )
        Task {
            do {
                try await appModel.moveRouter(profile.id, to: target)
            } catch {
                appModel.operationState = .error(
                    AppModel.routerTrialFailureMessage(for: error, language: language),
                    action: action,
                    target: profile.displayName,
                    nextStep: MicaStrings.localizedKey("action.retry", language: language)
                )
            }
        }
    }

    private func deleteConfirmation(
        _ profile: RouterProfile,
        confirmation: WorkbenchControllerDeleteConfirmation
    ) -> some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            deleteConfirmationContent(profile, confirmation: confirmation)
        }
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onExitCommand {
            pendingDelete = nil
        }
    }

    @ViewBuilder
    private func deleteConfirmationContent(
        _ profile: RouterProfile,
        confirmation: WorkbenchControllerDeleteConfirmation
    ) -> some View {
        Label {
            Text(verbatim: deleteMessage(profile))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "trash")
                .foregroundStyle(MicaTheme.statusError)
        }

        HStack(spacing: MicaTheme.Spacing.space2) {
            Spacer(minLength: MicaTheme.Spacing.space2)

            Button(MicaStrings.localizedKey("editor.cancel", language: language)) {
                pendingDelete = nil
            }
            .frame(minHeight: MicaTheme.Metrics.controlMinHeight)

            Button(
                MicaStrings.localizedKey("sidebar.delete_button", language: language),
                role: .destructive
            ) {
                guard pendingDelete == confirmation,
                      isCurrent(confirmation),
                      let currentProfile = appModel.routers.first(where: {
                          $0.id == confirmation.profileID
                      }) else {
                    pendingDelete = nil
                    return
                }
                pendingDelete = nil
                appModel.deleteRouter(currentProfile)
            }
            .buttonStyle(.borderedProminent)
            .tint(MicaTheme.statusError)
            .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
        }
    }

    private func requestDelete(_ profile: RouterProfile) {
        pendingDelete = WorkbenchControllerDeleteConfirmation(
            profileID: profile.id,
            selectedRouterID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
    }

    private func isCurrent(
        _ confirmation: WorkbenchControllerDeleteConfirmation
    ) -> Bool {
        confirmation.isCurrent(
            selectedRouterID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
    }

    private func deleteMessage(_ profile: RouterProfile) -> String {
        guard appModel.selectedRouterID == profile.id,
              let index = appModel.routers.firstIndex(where: { $0.id == profile.id }) else {
            return MicaStrings.localized(
                "controllers.delete_confirm \(profile.displayName)",
                language: language
            )
        }

        var remaining = appModel.routers
        remaining.remove(at: index)
        let replacement = remaining.indices.contains(index) ? remaining[index] : remaining.last
        if let replacement {
            return MicaStrings.localized(
                "controllers.delete_active_confirm \(profile.displayName) \(replacement.displayName)",
                language: language
            )
        }
        return MicaStrings.localized(
            "controllers.delete_only_confirm \(profile.displayName)",
            language: language
        )
    }
}

private struct WorkbenchConnectionTestReportView: View {
    @Environment(\.micaAppLanguage) private var language

    let profile: RouterProfile
    let report: ConnectionTestReport

    var body: some View {
        WorkbenchDataInspectorSection("editor.connection_diagnosis") {
            HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
                Label(
                    report.summary.label(language: language),
                    systemImage: report.summary.workbenchSymbol
                )
                .micaThemeFont(.label, weight: .semibold)
                .labelStyle(MicaStatusLabelStyle(tint: report.summary.workbenchTint))

                Spacer(minLength: MicaTheme.Spacing.space2)

                Text(verbatim: profile.displayName)
                    .micaThemeFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(verbatim: localized(report.headline))
                .micaThemeFont(.label, weight: .semibold)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !report.steps.contains(where: { $0.id == "url" }) {
                WorkbenchDataInspectorField(
                    titleKey: "editor.hs_url",
                    value: localized(report.targetURL),
                    monospaced: true
                )
            }

            ForEach(report.steps) { step in
                WorkbenchConnectionTestStepRow(
                    title: localized(step.title),
                    value: localized(step.value),
                    state: step.state,
                    monospaced: step.id == "url"
                )
            }

            if let nextStep = report.nextStep.managementNonEmpty {
                Label {
                    Text(verbatim: localized(nextStep))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.turn.down.right")
                }
                .micaThemeFont(.caption)
                .labelStyle(MicaStatusLabelStyle(tint: report.summary.workbenchTint))
                .frame(
                    maxWidth: .infinity,
                    minHeight: MicaTheme.Metrics.controlMinHeight,
                    alignment: .leading
                )
            }
        }
        .accessibilityLabel(
            MicaStrings.localizedKey("editor.connection_diagnosis", language: language)
        )
    }

    private func localized(_ text: String) -> String {
        MicaStrings.relocalizedText(text, language: language)
    }
}

private struct WorkbenchConnectionTestStepRow: View {
    let title: String
    let value: String
    let state: ConnectionCheckState
    let monospaced: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: state.workbenchSymbol)
                .micaThemeFont(.caption, weight: .medium)
                .labelStyle(MicaStatusLabelStyle(tint: state.workbenchTint))
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: value)
                .micaThemeFont(monospaced ? .dataCaption : .caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

/// The only command that switches the live controller, shared by list rows
/// and the inspector so both honor the same explicit-intent path.
struct WorkbenchControllerUseButton: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let profile: RouterProfile
    var compact = false

    var body: some View {
        let title = MicaStrings.localizedKey("controllers.use", language: language)

        Button {
            appModel.selectRouter(profile)
        } label: {
            Label(title, systemImage: "play.fill")
                .labelStyle(.titleAndIcon)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: compact ? nil : MicaTheme.Metrics.controlMinHeight)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(compact ? .small : .regular)
        .tint(MicaTheme.accent)
        .help(MicaStrings.localized("controllers.use_named \(profile.displayName)", language: language))
        .accessibilityLabel(
            MicaStrings.localized("controllers.use_named \(profile.displayName)", language: language)
        )
    }
}
