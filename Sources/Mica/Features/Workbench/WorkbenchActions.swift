import Foundation
import MicaCore
import SwiftUI

// MARK: - Actions

struct WorkbenchRuntimeConfirmation: Equatable {
    let routerID: RouterProfile.ID
    let generation: UUID
    let operationID: String

    func isCurrent(
        routerID: RouterProfile.ID?,
        generation: UUID,
        permitsLiveOperations: Bool
    ) -> Bool {
        self.routerID == routerID
            && self.generation == generation
            && permitsLiveOperations
    }
}

struct WorkbenchActionsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    @Binding var destination: WorkbenchDestination

    let onEditController: (RouterProfile) -> Void

    @State private var pendingConfirmation: WorkbenchRuntimeConfirmation?

    var body: some View {
        let snapshot = actionsSnapshot

        WorkbenchPageScaffold {
            commandBar(snapshot)
        } content: {
            actionsContent(snapshot)
        }
        .onChange(of: appModel.selectedRouterID) { _, _ in
            pendingConfirmation = nil
        }
        .onChange(of: appModel.controllerSessionPresentation.generation) { _, _ in
            pendingConfirmation = nil
        }
        .onChange(of: snapshot?.availability) { _, availability in
            if availability != .ready && availability != .partial {
                pendingConfirmation = nil
            }
        }
        .onChange(of: snapshot?.visibleOperationIDs) { _, operationIDs in
            guard let pendingConfirmation else { return }
            if operationIDs?.contains(pendingConfirmation.operationID) != true {
                self.pendingConfirmation = nil
            }
        }
    }

    private var actionsSnapshot: WorkbenchActionsSnapshot? {
        guard let router = appModel.selectedRouter else { return nil }
        let controllerType = appModel.selectedUnifiedControllerType
        return WorkbenchActionsProjection.snapshot(
            WorkbenchActionsInput(
                router: router,
                generation: appModel.controllerSessionPresentation.generation,
                controllerType: controllerType,
                sessionState: appModel.controllerSessionPresentation.state,
                capabilities: appModel.selectedUnifiedCapabilities,
                runtimeRows: appModel.actionsRuntimeOperationRows,
                canTest: appModel.canTestSelectedRouter,
                canRefresh: appModel.canRefreshSelectedRouter,
                isBusy: appModel.isBusy
            )
        )
    }

    @ViewBuilder
    private func actionsContent(_ snapshot: WorkbenchActionsSnapshot?) -> some View {
        if let snapshot, let router = appModel.selectedRouter {
            switch snapshot.availability {
            case .checking, .recovery, .unsupported:
                recoveryCanvas(snapshot: snapshot, router: router)
            case .ready, .partial:
                commandCanvas(snapshot: snapshot, router: router)
            }
        } else {
            WorkbenchStateView(
                kind: .noController,
                titleKey: "dashboard.connect_router",
                detailKey: "configuration.no_controller_detail"
            )
        }
    }

    private func commandBar(
        _ snapshot: WorkbenchActionsSnapshot?
    ) -> some View {
        WorkbenchCommandBar {
            WorkbenchManagementHeader(
                systemImage: "bolt.badge.checkmark",
                titleKey: "workbench.actions",
                detail: appModel.selectedRouter?.displayName,
                value: appModel.selectedRouter?.endpointURL
            )
        } controls: {
            if let snapshot {
                HStack(spacing: MicaTheme.Spacing.space2) {
                    WorkbenchStatusBadge(
                        text: MicaStrings.localizedKey(
                            snapshot.availability.labelKey,
                            language: language
                        ),
                        tint: snapshot.availability.tint
                    )
                    if snapshot.availability == .ready || snapshot.availability == .partial,
                       snapshot.executableCount > 0 {
                        WorkbenchStatusBadge(
                            text: MicaStrings.localized(
                                "actions.executable_count \(snapshot.executableCount)",
                                language: language
                            ),
                            tint: MicaTheme.statusOK
                        )
                    }
                }
            }
        }
    }

    private func recoveryCanvas(
        snapshot: WorkbenchActionsSnapshot,
        router: RouterProfile
    ) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space4) {
                    recoverySummary(snapshot: snapshot, router: router)
                    targetSection(snapshot: snapshot, router: router)
                    recoveryActions(snapshot: snapshot, router: router)
                    if !snapshot.relatedDestinations.isEmpty {
                        relatedWorkspaces(snapshot.relatedDestinations)
                    }
                }
                .padding(.horizontal, MicaTheme.Metrics.pagePadding(for: geometry.size.width))
                .padding(.vertical, MicaTheme.Spacing.space4)
                .frame(maxWidth: 780, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .micaObserveScrollPerformance()
        }
    }

    private func recoverySummary(
        snapshot: WorkbenchActionsSnapshot,
        router: RouterProfile
    ) -> some View {
        HStack(alignment: .top, spacing: MicaTheme.Spacing.space3) {
            Group {
                if snapshot.availability == .checking {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    WorkbenchSymbol(
                        systemName: snapshot.availability == .unsupported
                            ? "questionmark.circle"
                            : "network.slash",
                        tint: snapshot.availability.tint,
                        font: .title2.weight(.semibold),
                        frameSize: 30
                    )
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                Text(
                    MicaStrings.localizedKey(
                        snapshot.recovery?.titleKey ?? "actions.recovery_title",
                        language: language
                    )
                )
                .micaThemeFont(.title)

                Text(
                    MicaStrings.localizedKey(
                        snapshot.recovery?.detailKey ?? "actions.recovery_detail",
                        language: language
                    )
                )
                .micaThemeFont(.label)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if let message = snapshot.recovery?.message?.managementNonEmpty {
                    Text(verbatim: message)
                        .micaThemeFont(.caption)
                        .foregroundStyle(snapshot.availability.tint)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func targetSection(
        snapshot: WorkbenchActionsSnapshot,
        router: RouterProfile
    ) -> some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            WorkbenchSectionHeading(
                systemImage: "scope",
                titleKey: "actions.target_title"
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space3) {
                    targetIdentity(snapshot: snapshot, router: router)
                    Spacer(minLength: MicaTheme.Spacing.space3)
                    targetScopeLabel(snapshot.targetScope)
                }
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                    targetIdentity(snapshot: snapshot, router: router)
                    targetScopeLabel(snapshot.targetScope)
                }
            }

            if snapshot.showsTargetCorrection {
                Label {
                    Text(
                        MicaStrings.localizedKey(
                            "target.loopback_recovery_detail",
                            language: language
                        )
                    )
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(MicaTheme.statusWarning)
                }
                .micaThemeFont(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(
                    MicaStrings.localizedKey(
                        snapshot.targetScope.detailKey,
                        language: language
                    )
                )
                .micaThemeFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, MicaTheme.Spacing.space3)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func targetIdentity(
        snapshot: WorkbenchActionsSnapshot,
        router: RouterProfile
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: router.displayName)
                .micaThemeFont(.body, weight: .semibold)
            Text(verbatim: router.endpointURL)
                .micaThemeFont(.dataCaption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func targetScopeLabel(
        _ scope: WorkbenchControllerTargetScope
    ) -> some View {
        Label(
            MicaStrings.localizedKey(scope.titleKey, language: language),
            systemImage: scope == .thisMac ? "desktopcomputer" : "network"
        )
        .micaThemeFont(.caption, weight: .semibold)
        .foregroundStyle(scope == .unconfigured ? MicaTheme.statusWarning : .secondary)
    }

    private func recoveryActions(
        snapshot: WorkbenchActionsSnapshot,
        router: RouterProfile
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaTheme.Spacing.space2) {
                recoveryActionButtons(snapshot: snapshot, router: router)
            }
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                recoveryActionButtons(snapshot: snapshot, router: router)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func recoveryActionButtons(
        snapshot: WorkbenchActionsSnapshot,
        router: RouterProfile
    ) -> some View {
        if let primaryIntent = snapshot.recovery?.primaryIntent {
            Button {
                perform(primaryIntent)
            } label: {
                Label(
                    MicaStrings.localizedKey("action.test", language: language),
                    systemImage: MicaSymbols.Command.test
                )
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.borderedProminent)
        }

        Button {
            onEditController(router)
        } label: {
            Label(
                MicaStrings.localizedKey("action.edit_router", language: language),
                systemImage: "pencil"
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)

        Button {
            destination = .diagnostics
        } label: {
            Label(
                MicaStrings.localizedKey("workspace.diagnostics", language: language),
                systemImage: "stethoscope"
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
    }

    private func commandCanvas(
        snapshot: WorkbenchActionsSnapshot,
        router: RouterProfile
    ) -> some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
                - MicaTheme.Metrics.pagePadding(for: geometry.size.width) * 2
            let usesTwoColumns = availableWidth >= 900

            ScrollView {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space4) {
                    if let retainedFailureMessage {
                        WorkbenchStaleNotice(message: retainedFailureMessage)
                    }

                    commandWorkspace(snapshot: snapshot, usesTwoColumns: usesTwoColumns)

                    if !snapshot.relatedDestinations.isEmpty {
                        relatedWorkspaces(snapshot.relatedDestinations)
                    }
                }
                .padding(.horizontal, MicaTheme.Metrics.pagePadding(for: geometry.size.width))
                .padding(.vertical, MicaTheme.Spacing.space4)
                .frame(maxWidth: 1_080, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .micaObserveScrollPerformance()
        }
    }

    @ViewBuilder
    private func commandWorkspace(
        snapshot: WorkbenchActionsSnapshot,
        usesTwoColumns: Bool
    ) -> some View {
        let ordinaryGroups = snapshot.groups.filter { $0.group != .lifecycle }
        let lifecycleGroup = snapshot.groups.first { $0.group == .lifecycle }

        if usesTwoColumns, ordinaryGroups.count > 1 {
            HStack(alignment: .top, spacing: MicaTheme.Spacing.space4) {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space4) {
                    ForEach(Array(ordinaryGroups.enumerated()), id: \.element.id) { index, group in
                        if index.isMultiple(of: 2) {
                            commandGroup(group)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()

                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space4) {
                    ForEach(Array(ordinaryGroups.enumerated()), id: \.element.id) { index, group in
                        if !index.isMultiple(of: 2) {
                            commandGroup(group)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space4) {
                ForEach(ordinaryGroups) { group in
                    commandGroup(group)
                }
            }
        }

        if let lifecycleGroup {
            Divider()
            commandGroup(lifecycleGroup)
        }
    }

    private func commandGroup(
        _ group: WorkbenchActionCommandGroup
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkbenchSectionHeading(
                systemImage: group.group.systemImage,
                titleKey: group.group.titleKey,
                tint: group.group == .lifecycle
                    ? MicaTheme.statusWarning
                    : MicaTheme.textSecondary
            )
            .padding(.bottom, MicaTheme.Spacing.space2)

            ForEach(Array(group.commands.enumerated()), id: \.element.id) { index, command in
                if index > 0 { Divider() }
                commandRow(command)
                if hasPendingConfirmation(for: command) {
                    Divider()
                    inlineConfirmation(command)
                        .padding(.vertical, MicaTheme.Spacing.space2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func commandRow(_ command: WorkbenchActionCommand) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: MicaTheme.Spacing.space3) {
                commandExplanation(command)
                Spacer(minLength: MicaTheme.Spacing.space3)
                commandButton(command)
            }
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                commandExplanation(command)
                commandButton(command)
            }
        }
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commandExplanation(_ command: WorkbenchActionCommand) -> some View {
        HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
            WorkbenchSymbol(
                systemName: command.systemImage,
                tint: command.risk == .destructive
                    ? MicaTheme.statusWarning
                    : MicaTheme.textSecondary,
                frameSize: 20
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(MicaStrings.localizedKey(command.titleKey, language: language))
                    .micaThemeFont(.label, weight: .medium)
                Text(MicaStrings.localizedKey(command.detailKey, language: language))
                    .micaThemeFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commandButton(_ command: WorkbenchActionCommand) -> some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            if isRunning(command) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }

            Button(role: command.risk == .destructive ? .destructive : nil) {
                if command.requiresConfirmation {
                    guard let routerID = appModel.selectedRouterID else { return }
                    pendingConfirmation = WorkbenchRuntimeConfirmation(
                        routerID: routerID,
                        generation: appModel.controllerSessionPresentation.generation,
                        operationID: command.id
                    )
                } else {
                    perform(command.intent)
                }
            } label: {
                Label(
                    MicaStrings.localizedKey(command.titleKey, language: language),
                    systemImage: command.systemImage
                )
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.bordered)
            .disabled(!command.isEnabled || hasPendingConfirmation(for: command))
        }
        .frame(minHeight: MicaTheme.Metrics.controlMinHeight, alignment: .trailing)
    }

    private func relatedWorkspaces(
        _ destinations: [WorkbenchDestination]
    ) -> some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space3) {
            WorkbenchSectionHeading(
                systemImage: "arrow.triangle.branch",
                titleKey: "actions.related_workspaces"
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: MicaTheme.Spacing.space2)],
                alignment: .leading,
                spacing: MicaTheme.Spacing.space2
            ) {
                ForEach(destinations) { destination in
                    Button {
                        self.destination = destination
                    } label: {
                        Label(
                            MicaStrings.localizedKey(destination.titleKey, language: language),
                            systemImage: destination.symbolName
                        )
                        .frame(maxWidth: .infinity, minHeight: MicaTheme.Metrics.controlMinHeight, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.top, MicaTheme.Spacing.space3)
        .overlay(alignment: .top) { Divider() }
    }

    private func inlineConfirmation(
        _ command: WorkbenchActionCommand
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaTheme.Spacing.space3) {
                confirmationContent(command)
            }
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                confirmationContent(command)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func confirmationContent(
        _ command: WorkbenchActionCommand
    ) -> some View {
        Label {
            Text(
                MicaStrings.localizedKey(
                    command.confirmationMessageKey ?? "diagnostics.confirm_runtime_message",
                    language: language
                )
            )
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MicaTheme.statusWarning)
        }

        Spacer(minLength: MicaTheme.Spacing.space2)

        Button(MicaStrings.localizedKey("action.cancel", language: language)) {
            pendingConfirmation = nil
        }

        Button(
            MicaStrings.localizedKey(command.titleKey, language: language),
            role: .destructive
        ) {
            guard let pendingConfirmation,
                  pendingConfirmation.operationID == command.id,
                  isCurrent(pendingConfirmation) else {
                self.pendingConfirmation = nil
                return
            }
            self.pendingConfirmation = nil
            perform(command.intent)
        }
        .buttonStyle(.borderedProminent)
        .tint(MicaTheme.statusError)
    }

    private func perform(_ intent: WorkbenchActionsIntent) {
        switch intent {
        case .testConnection:
            appModel.testSelectedRouter()
        case .refresh:
            appModel.refreshSelectedRouter()
        case .direct(let action):
            switch action {
            case .reloadRules:
                appModel.reloadRules()
            case .reloadProviders:
                appModel.reloadProviders()
            case .reloadProfile:
                appModel.reloadSurgeProfile()
            default:
                break
            }
        case .runtimeOperation(let operationID):
            appModel.performDiagnosticsRuntimeOperation(operationID)
        case .editController:
            if let router = appModel.selectedRouter { onEditController(router) }
        case .openDiagnostics:
            destination = .diagnostics
        case .navigate(let destination):
            self.destination = destination
        }
    }

    private func isRunning(_ command: WorkbenchActionCommand) -> Bool {
        switch command.intent {
        case .testConnection:
            appModel.connectionState == .connecting
        case .refresh:
            appModel.isRefreshingDashboard
        case .direct(.reloadRules):
            appModel.reloadingRules
        case .direct(.reloadProviders):
            appModel.reloadingProviders
        case .direct(.reloadProfile):
            appModel.reloadingSurgeProfile
        case .runtimeOperation(let operationID):
            appModel.runningRuntimeOperationID == operationID
        case .direct, .editController, .openDiagnostics, .navigate:
            false
        }
    }

    private func isCurrent(
        _ confirmation: WorkbenchRuntimeConfirmation
    ) -> Bool {
        confirmation.isCurrent(
            routerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation,
            permitsLiveOperations: appModel.controllerSessionPresentation.state.allowsLiveCommands
        )
    }

    private func hasPendingConfirmation(
        for command: WorkbenchActionCommand
    ) -> Bool {
        guard let pendingConfirmation else { return false }
        return pendingConfirmation.operationID == command.id && isCurrent(pendingConfirmation)
    }

    private var retainedFailureMessage: String? {
        switch appModel.controllerSessionPresentation.state {
        case .partial(let message):
            message.managementNonEmpty
        default:
            nil
        }
    }
}

private extension WorkbenchActionsAvailability {
    var labelKey: String {
        switch self {
        case .checking: "actions.status_checking"
        case .recovery: "actions.status_recovery"
        case .ready: "actions.status_ready"
        case .partial: "actions.status_partial"
        case .unsupported: "actions.status_unsupported"
        }
    }

    var tint: Color {
        switch self {
        case .checking: MicaTheme.textSecondary
        case .recovery, .partial: MicaTheme.statusWarning
        case .ready: MicaTheme.statusOK
        case .unsupported: .secondary
        }
    }
}
