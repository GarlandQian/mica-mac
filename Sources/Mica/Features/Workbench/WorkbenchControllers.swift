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

struct WorkbenchControllersView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language

    @Binding var searchText: String
    @State private var pendingDelete: WorkbenchControllerDeleteConfirmation?
    @State private var connectionTests = WorkbenchConnectionTestProjection()

    let onAddController: () -> Void
    let onEditController: (RouterProfile) -> Void

    var body: some View {
        GeometryReader { proxy in
            let widthMode = WorkbenchManagementWidthMode(
                availableWidth: proxy.size.width
            )

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
                    controllerContent(availableWidth: proxy.size.width)
                }
            }
            .environment(\.workbenchManagementWidthMode, widthMode)
        }
        .onAppear {
            connectionTests.replacePresentation()
            connectionTests.reconcile(profiles: appModel.routers)
            reconcileManagementSelection()
        }
        .onDisappear {
            connectionTests.replacePresentation()
        }
        .onChange(of: appModel.routers) { _, profiles in
            connectionTests.reconcile(profiles: profiles)
            let ids = profiles.map(\.id)
            reconcileManagementSelection()
            if let pendingDelete, !ids.contains(pendingDelete.profileID) {
                self.pendingDelete = nil
            }
        }
        .onChange(of: appModel.selectedRouterID) { pendingDelete = nil }
        .onChange(of: appModel.controllerSessionPresentation.generation) { pendingDelete = nil }
        .onChange(of: searchText) {
            reconcileManagementSelection(visibleOnly: true)
        }
    }

    @ViewBuilder
    private func controllerContent(availableWidth: CGFloat) -> some View {
        if let profile = selectedReportProfile {
            if availableWidth >= 840 {
                HSplitView {
                    controllerList
                        .frame(
                            minWidth: 280,
                            idealWidth: WorkbenchManagementMetrics.controllerListWidth,
                            maxWidth: 360
                        )

                    controllerDetail(profile)
                        .frame(minWidth: 480)
                }
            } else {
                VSplitView {
                    controllerList
                        .frame(minHeight: 220)

                    controllerDetail(profile)
                        .frame(minHeight: 280)
                }
            }
        } else {
            controllerList
        }
    }

    private func controllerDetail(_ profile: RouterProfile) -> some View {
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
                        tint: MicaDesignTokens.signalCyan,
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
        .accessibilityLabel(
            MicaStrings.localizedKey("controllers.controller", language: language)
        )
    }

    private func controllerIdentity(_ profile: RouterProfile) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: MicaSpacing.module) {
                controllerIdentityLabel(profile)
                Spacer(minLength: MicaSpacing.row)
                statusLabel(profile)
            }

            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                controllerIdentityLabel(profile)
                statusLabel(profile)
            }
        }
        .frame(maxWidth: .infinity, minHeight: MicaBounds.controlMinHeight, alignment: .leading)
    }

    private func controllerIdentityLabel(_ profile: RouterProfile) -> some View {
        HStack(alignment: .top, spacing: MicaSpacing.row) {
            WorkbenchSymbol(
                systemName: profile.controllerKind.editorSymbol,
                tint: appModel.selectedRouterID == profile.id
                    ? MicaDesignTokens.accent
                    : MicaDesignTokens.signalCyan,
                size: .focus
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: profile.displayName)
                    .micaFont(.title3, weight: .semibold)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: profile.controllerKind.micaLabel(language: language))
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func controllerDetailActions(_ profile: RouterProfile) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.row) {
                controllerDetailActionButtons(profile)
            }

            VStack(alignment: .trailing, spacing: MicaSpacing.row) {
                controllerDetailActionButtons(profile)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func controllerDetailActionButtons(_ profile: RouterProfile) -> some View {
        if appModel.selectedRouterID == profile.id {
            WorkbenchStatusBadge(
                text: MicaStrings.localizedKey("controllers.active", language: language),
                tint: MicaDesignTokens.signalMint
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
                .frame(minHeight: MicaBounds.controlMinHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(MicaStyle.accent)
        }

        Button {
            testConnection(profile)
        } label: {
            HStack(spacing: MicaSpacing.row) {
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
            .frame(minHeight: MicaBounds.controlMinHeight)
        }
        .buttonStyle(.bordered)
        .disabled(isTesting(profile))
        .accessibilityLabel(MicaStrings.localizedKey("action.test", language: language))

        Divider()
            .frame(height: 18)

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
            tint: MicaDesignTokens.signalRed
        ) {
            requestDelete(profile)
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
                text: MicaStrings.localized(
                    "controllers.count \(filteredProfiles.count)",
                    language: language
                ),
                tint: MicaDesignTokens.signalCyan
            )
        } commands: {
            WorkbenchIconCommand(
                titleKey: "sidebar.add_controller",
                systemImage: "plus",
                action: onAddController
            )
        }
    }

    private var controllerList: some View {
        List(filteredProfiles, selection: managementSelectionBinding) { profile in
            controllerRow(profile)
                .tag(profile.id)
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .micaObserveScrollPerformance()
        .scrollContentBackground(.hidden)
        .background(MicaStyle.groupedPageFill)
        .accessibilityLabel(
            MicaStrings.localizedKey("sidebar.controllers", language: language)
        )
    }

    private func controllerRow(_ profile: RouterProfile) -> some View {
        HStack(alignment: .top, spacing: MicaSpacing.row) {
            activeIndicator(profile)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.row) {
                    Text(verbatim: profile.displayName)
                        .micaFont(.callout, weight: .semibold)
                        .lineLimit(1)

                    Spacer(minLength: MicaSpacing.row)

                    statusLabel(profile)
                        .lineLimit(1)
                }

                Text(verbatim: profile.endpointURL)
                    .micaFont(.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, MicaSpacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var filteredProfiles: [RouterProfile] {
        WorkbenchControllerListProjection.filtered(
            appModel.routers,
            query: searchText
        ) { profile in
            profile.controllerKind.micaLabel(language: language)
        }
    }

    private var selectedReportProfile: RouterProfile? {
        let selectedID = managementSelection
            ?? appModel.selectedRouterID
            ?? filteredProfiles.first?.id
        guard let selectedID else { return nil }
        return appModel.routers.first { $0.id == selectedID }
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
        if let pendingDelete, pendingDelete.profileID != id {
            self.pendingDelete = nil
        }
        workspaceStore.update(
            controllerID: appModel.selectedRouterID,
            destination: .controllers
        ) { workspace in
            workspace.selectedItemID = id?.uuidString
        }
    }

    private func reconcileManagementSelection(visibleOnly: Bool = false) {
        let candidates = visibleOnly ? filteredProfiles : appModel.routers
        let next = WorkbenchControllerListProjection.reconciledSelection(
            storedID: managementSelection,
            activeID: appModel.selectedRouterID,
            candidates: candidates
        )
        setManagementSelection(next)
    }

    private func activeIndicator(_ profile: RouterProfile) -> some View {
        let active = appModel.selectedRouterID == profile.id
        return Image(systemName: active ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(active ? MicaDesignTokens.signalMint : .secondary)
            .accessibilityLabel(
                MicaStrings.localizedKey(
                    active ? "controllers.active" : "controllers.inactive",
                    language: language
                )
            )
    }

    private func statusLabel(_ profile: RouterProfile) -> some View {
        let status = controllerStatus(profile)
        return Label(status.label, systemImage: status.symbol)
            .micaFont(.caption)
            .labelStyle(MicaStatusLabelStyle(tint: status.tint))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func controllerStatus(_ profile: RouterProfile) -> WorkbenchControllerStatus {
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
                    tint: MicaDesignTokens.signalCyan
                )
            case .connected:
                return WorkbenchControllerStatus(
                    label: appModel.connectionState.label(language: language),
                    symbol: "checkmark.circle.fill",
                    tint: MicaDesignTokens.signalMint
                )
            case .failed:
                return WorkbenchControllerStatus(
                    label: appModel.connectionState.label(language: language),
                    symbol: "xmark.circle.fill",
                    tint: MicaDesignTokens.signalRed
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
                tint: MicaDesignTokens.signalMint
            )
        case .stale, .partial:
            return WorkbenchControllerStatus(
                label: health.label(language: language),
                symbol: "exclamationmark.triangle.fill",
                tint: MicaDesignTokens.signalAmber
            )
        case .failed:
            return WorkbenchControllerStatus(
                label: health.label(language: language),
                symbol: "xmark.circle.fill",
                tint: MicaDesignTokens.signalRed
            )
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
            style: .caption, design: .monospaced,
            tone: .secondary
        )
    }

    private func testConnection(_ profile: RouterProfile) {
        setManagementSelection(profile.id)
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
                .frame(width: MicaBounds.iconControlSize, height: MicaBounds.iconControlSize)
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
        guard searchText.managementNonEmpty == nil,
              let managementSelection,
              let index = appModel.routers.firstIndex(where: { $0.id == managementSelection }) else {
            return false
        }
        switch direction {
        case .up: return index > 0
        case .down: return index < appModel.routers.count - 1
        }
    }

    private func moveSelection(_ direction: WorkbenchControllerMove) {
        guard let managementSelection,
              let index = appModel.routers.firstIndex(where: { $0.id == managementSelection }) else {
            return
        }
        let target = direction == .up ? index - 1 : index + 1
        guard appModel.routers.indices.contains(target) else { return }
        let profile = appModel.routers[index]
        let action = MicaStrings.localizedKey(
            direction == .up ? "controllers.move_up" : "controllers.move_down",
            language: language
        )
        Task {
            do {
                try await appModel.moveRouter(managementSelection, to: target)
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.module) {
                deleteConfirmationContent(profile, confirmation: confirmation)
            }
            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                deleteConfirmationContent(profile, confirmation: confirmation)
            }
        }
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .foregroundStyle(MicaDesignTokens.signalRed)
        }

        Spacer(minLength: MicaSpacing.row)

        Button(MicaStrings.localizedKey("editor.cancel", language: language)) {
            pendingDelete = nil
        }
        .frame(minHeight: MicaBounds.controlMinHeight)

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
        .tint(MicaDesignTokens.signalRed)
        .frame(minHeight: MicaBounds.controlMinHeight)
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
            HStack(alignment: .top, spacing: MicaSpacing.module) {
                Label(
                    report.summary.label(language: language),
                    systemImage: report.summary.workbenchSymbol
                )
                .micaFont(.callout, weight: .semibold)
                .labelStyle(MicaStatusLabelStyle(tint: report.summary.workbenchTint))

                Spacer(minLength: MicaSpacing.row)

                Text(verbatim: profile.displayName)
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(verbatim: localized(report.headline))
                .micaFont(.callout, weight: .semibold)
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
                .micaFont(.callout)
                .labelStyle(MicaStatusLabelStyle(tint: report.summary.workbenchTint))
                .frame(
                    maxWidth: .infinity,
                    minHeight: MicaBounds.controlMinHeight,
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
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    stepLabel
                    stepValue
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.module) {
                    stepLabel
                        .frame(width: MicaBounds.formLabelWidth, alignment: .leading)
                    stepValue
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: MicaBounds.controlMinHeight, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var stepLabel: some View {
        Label(title, systemImage: state.workbenchSymbol)
            .micaFont(.callout)
            .labelStyle(MicaStatusLabelStyle(tint: state.workbenchTint))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var stepValue: some View {
        WorkbenchFormValue(value: value, monospaced: monospaced)
    }
}
