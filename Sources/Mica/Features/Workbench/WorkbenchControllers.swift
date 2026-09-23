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
            reconcileManagementSelection()
        }
        .onChange(of: appModel.routers) { _, _ in
            reconcileManagementSelection()
        }
        .onChange(of: searchText) {
            reconcileManagementSelection()
        }
        .onChange(of: language) {
            reconcileManagementSelection()
        }
        .onChange(of: workspaceStore.inspectorSelection) { _, selection in
            guard selection == .none, managementSelection != nil else { return }
            workspaceStore.update(
                controllerID: appModel.selectedRouterID,
                destination: .controllers
            ) { workspace in
                workspace.selectedItemID = nil
            }
        }
    }

    private var commandBar: some View {
        WorkbenchCommandBar {
            WorkbenchManagementHeader(
                systemImage: "server.rack",
                titleKey: "sidebar.controllers",
                detail: MicaStrings.localizedKey("controllers.subtitle", language: language)
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
        List(filteredProfiles, selection: managementSelectionBinding) { profile in
            controllerRow(profile)
                .tag(profile.id)
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

    private func controllerRow(_ profile: RouterProfile) -> some View {
        HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
            WorkbenchSymbol(
                systemName: profile.controllerKind.editorSymbol,
                tint: appModel.selectedRouterID == profile.id
                    ? MicaTheme.accent : MicaTheme.textSecondary,
                size: .focus
            )
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space2) {
                    Text(verbatim: profile.displayName)
                        .micaThemeFont(.label, weight: .semibold)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: MicaTheme.Spacing.space2)

                    if appModel.selectedRouterID == profile.id {
                        activeIndicator(profile)
                    }
                }

                Text(verbatim: profile.endpointURL)
                    .micaThemeFont(.dataCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: MicaTheme.Spacing.space2) {
                        controllerKindLabel(profile)
                        Spacer(minLength: MicaTheme.Spacing.space2)
                        WorkbenchControllerStatusView(profile: profile)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        controllerKindLabel(profile)
                        WorkbenchControllerStatusView(profile: profile)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
            controllerID: appModel.selectedRouterID,
            destination: .controllers
        ).selectedItemID else {
            return nil
        }
        return RouterProfile.ID(uuidString: storedID)
    }

    private var managementSelectionBinding: Binding<RouterProfile.ID?> {
        Binding(
            get: { managementSelection },
            set: { setManagementSelection($0) }
        )
    }

    private func setManagementSelection(_ id: RouterProfile.ID?) {
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .controllers
        ) { workspace in
            workspace.selectedItemID = id?.uuidString
        }
        if let id {
            workspaceStore.selectInspector(.controller(id: id))
        } else {
            workspaceStore.clearInspectorSelection(ownedBy: .controllers)
        }
    }

    private func reconcileManagementSelection() {
        let next = WorkbenchControllerListProjection.reconciledSelection(
            storedID: managementSelection,
            activeID: appModel.selectedRouterID,
            profiles: appModel.routers,
            query: searchText
        ) { profile in
            profile.controllerKind.micaLabel(language: language)
        }
        setManagementSelection(next)
    }

    private func activeIndicator(_ profile: RouterProfile) -> some View {
        let active = appModel.selectedRouterID == profile.id
        return Image(systemName: active ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(active ? MicaTheme.accent : .secondary)
            .accessibilityLabel(
                MicaStrings.localizedKey(
                    active ? "controllers.active" : "controllers.inactive",
                    language: language
                )
            )
    }
}

/// Controller detail in the workspace inspector (Mica Ops redesign, design.md
/// §3): identity, capability-gated actions, connection fields, and the
/// connection-test report for the selected controller. The profile arrives
/// already resolved from `AppModel.routers`; a deleted controller renders the
/// container's shared empty state instead. Inline delete confirmation captures
/// controller ID plus session generation exactly as before.
struct WorkbenchControllerInspector: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language

    let profile: RouterProfile
    let onEditController: (RouterProfile) -> Void

    @State private var pendingDelete: WorkbenchControllerDeleteConfirmation?
    @State private var connectionTests = WorkbenchConnectionTestProjection()

    var body: some View {
        WorkbenchManagementFormCanvas {
            Section {
                controllerIdentity(profile)
                controllerDetailActions(profile)
                if let pendingDelete,
                   pendingDelete.profileID == profile.id,
                   isCurrent(pendingDelete) {
                    deleteConfirmation(profile, confirmation: pendingDelete)
                }
            }

            Section {
                WorkbenchFormRow("settings.controller_endpoint") {
                    WorkbenchFormValue(value: profile.endpointURL, monospaced: true)
                }
                WorkbenchFormRow("settings.controller_type") {
                    WorkbenchFormValue(
                        value: profile.controllerKind.micaLabel(language: language)
                    )
                }
                WorkbenchFormRow("diagnostics.last_connected") {
                    lastSuccess(profile)
                }
            } header: {
                Label(
                    MicaStrings.localizedKey("settings.connection", language: language),
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
            }

            if let report = connectionTests.report(for: profile) {
                WorkbenchConnectionTestReportView(
                    profile: profile,
                    report: report
                )
            } else {
                Section {
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
                } header: {
                    Label(
                        MicaStrings.localizedKey("editor.connection_diagnosis", language: language),
                        systemImage: "stethoscope"
                    )
                }
            }
        }
        .environment(\.workbenchManagementWidthMode, .compact)
        .accessibilityLabel(
            MicaStrings.localizedKey("controllers.controller", language: language)
        )
        .onAppear {
            connectionTests.replacePresentation()
            connectionTests.reconcile(profiles: appModel.routers)
        }
        .onDisappear {
            connectionTests.replacePresentation()
        }
        .onChange(of: appModel.routers) { _, profiles in
            connectionTests.reconcile(profiles: profiles)
            let ids = profiles.map(\.id)
            if let pendingDelete, !ids.contains(pendingDelete.profileID) {
                self.pendingDelete = nil
            }
        }
        .onChange(of: appModel.selectedRouterID) { pendingDelete = nil }
        .onChange(of: appModel.controllerSessionPresentation.generation) { pendingDelete = nil }
        .onChange(of: profile.id) { pendingDelete = nil }
    }

    private func controllerIdentity(_ profile: RouterProfile) -> some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            controllerIdentityLabel(profile)
            WorkbenchControllerStatusView(profile: profile)
        }
        .frame(maxWidth: .infinity, minHeight: MicaTheme.Metrics.controlMinHeight, alignment: .leading)
    }

    private func controllerIdentityLabel(_ profile: RouterProfile) -> some View {
        HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
            WorkbenchSymbol(
                systemName: profile.controllerKind.editorSymbol,
                tint: appModel.selectedRouterID == profile.id
                    ? MicaTheme.accent
                    : MicaTheme.textSecondary,
                size: .focus
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: profile.displayName)
                    .micaThemeFont(.title3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: profile.controllerKind.micaLabel(language: language))
                    .micaThemeFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func controllerDetailActions(_ profile: RouterProfile) -> some View {
        VStack(alignment: .trailing, spacing: MicaTheme.Spacing.space2) {
            controllerDetailActionButtons(profile)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func controllerDetailActionButtons(_ profile: RouterProfile) -> some View {
        if appModel.selectedRouterID == profile.id {
            WorkbenchStatusBadge(
                text: MicaStrings.localizedKey("controllers.active", language: language),
                tint: MicaTheme.statusOK
            )
        } else {
            Button {
                appModel.selectRouter(profile)
            } label: {
                Label(
                    MicaStrings.localizedKey("controllers.use", language: language),
                    systemImage: "play.fill"
                )
                .labelStyle(.titleAndIcon)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(MicaTheme.accent)
        }

        Button {
            testConnection(profile)
        } label: {
            HStack(spacing: MicaTheme.Spacing.space2) {
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
            .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
        }
        .buttonStyle(.bordered)
        .disabled(isTesting(profile))
        .accessibilityLabel(MicaStrings.localizedKey("action.test", language: language))

        Divider()
            .frame(height: 18)

        HStack(spacing: 0) {
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
    }

    private func lastSuccess(_ profile: RouterProfile) -> some View {
        let candidate = appModel.selectedRouterID == profile.id
            ? appModel.controllerSessionPresentation.lastSuccessAt ?? profile.lastConnectedAt
            : profile.lastConnectedAt
        let date = workbenchDisplayableDate(candidate)
        return WorkbenchDataText(
            value: date.map {
                $0.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .shortened)
                        .locale(language.resolvedLocale)
                )
            } ?? MicaStrings.localizedKey("settings.never", language: language),
            role: .dataCaption,
            tone: .secondary
        )
    }

    private func testConnection(_ profile: RouterProfile) {
        let draft = appModel.draft(for: profile)
        let intent = connectionTests.begin(profile: profile)

        Task {
            let report = await appModel.testConnection(draft: draft)
            guard !Task.isCancelled else { return }
            connectionTests.receive(
                report,
                for: intent,
                profiles: appModel.routers
            )
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
        connectionTests.isTesting(profile)
            || appModel.trialSession(for: profile).commandLog.contains {
                $0.action == .test && !$0.status.isTerminal
            }
    }

    private func canMove(_ direction: WorkbenchControllerMove) -> Bool {
        guard workspaceStore.workspace(
            controllerID: appModel.selectedRouterID,
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
        Section {
            HStack(alignment: .top, spacing: MicaTheme.Spacing.space3) {
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
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(verbatim: localized(report.headline))
                .micaThemeFont(.label, weight: .semibold)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            WorkbenchFormRow("editor.hs_url") {
                WorkbenchFormValue(
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
                .micaThemeFont(.label)
                .labelStyle(MicaStatusLabelStyle(tint: report.summary.workbenchTint))
                .frame(
                    maxWidth: .infinity,
                    minHeight: MicaTheme.Metrics.controlMinHeight,
                    alignment: .leading
                )
            }
        } header: {
            Label(
                MicaStrings.localizedKey("editor.connection_diagnosis", language: language),
                systemImage: report.summary.workbenchSymbol
            )
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
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    let title: String
    let value: String
    let state: ConnectionCheckState
    let monospaced: Bool

    private var usesStackedLayout: Bool {
        widthMode == .compact
    }

    var body: some View {
        Group {
            if usesStackedLayout {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                    stepLabel
                    stepValue
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space3) {
                    stepLabel
                        .frame(width: MicaTheme.Metrics.formLabelWidth, alignment: .leading)
                    stepValue
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: MicaTheme.Metrics.controlMinHeight, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var stepLabel: some View {
        Label(title, systemImage: state.workbenchSymbol)
            .micaThemeFont(.label)
            .labelStyle(MicaStatusLabelStyle(tint: state.workbenchTint))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var stepValue: some View {
        WorkbenchFormValue(value: value, monospaced: monospaced)
    }
}
