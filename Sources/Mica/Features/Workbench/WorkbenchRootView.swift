import MicaCore
import SwiftUI

struct WorkbenchRootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var appLanguage
    @Environment(\.micaFontMultiplier) private var fontMultiplier

    @Binding var destination: WorkbenchDestination
    @State private var searchText = ""
    @AppStorage("recentControllerIDs") private var recentControllerIDsRawValue = ""

    var onAddController: () -> Void
    var onEditController: (RouterProfile) -> Void

    var body: some View {
        searchableContent
            .navigationTitle(MicaStrings.localizedKey(destination.titleKey, language: appLanguage))
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                WorkbenchSessionStatusBar(appModel: appModel)
            }
            .focusedValue(\.micaFocusedWorkbenchDestination, $destination)
            .onChange(of: destination) { _, _ in searchText = "" }
            .onChange(of: appModel.routers.map(\.id)) { _, _ in pruneRecentControllers() }
            .onChange(of: appModel.selectedRouterID) { previousID, selectedID in
                recordRecentController(previousID, excluding: selectedID)
            }
    }

    @ViewBuilder
    private var searchableContent: some View {
        if destination.supportsSearch {
            content
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: Text(MicaStrings.localizedKey(destination.searchPromptKey, language: appLanguage))
                )
        } else {
            content
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            controllerSwitcher
        }

        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button {
                    appModel.testSelectedRouter()
                } label: {
                    Label(MicaStrings.localizedKey("action.test", language: appLanguage), systemImage: "checkmark.circle")
                }
                .disabled(!appModel.canTestSelectedRouter)
                .help(MicaStrings.localizedKey("dashboard.help_test_controller", language: appLanguage))
                .accessibilityLabel(MicaStrings.localizedKey("action.test", language: appLanguage))

                Button {
                    appModel.refreshSelectedRouter()
                } label: {
                    Label(MicaStrings.localizedKey("action.refresh", language: appLanguage), systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!appModel.canRefreshSelectedRouter)
                .help(MicaStrings.localizedKey("dashboard.help_refresh_controller", language: appLanguage))
                .accessibilityLabel(MicaStrings.localizedKey("action.refresh", language: appLanguage))

                Button {
                    appModel.toggleDashboardUpdatesPaused()
                } label: {
                    Label(MicaStrings.localizedKey(pauseTitleKey, language: appLanguage), systemImage: appModel.dashboardSessionControls.dashboardUpdatesPaused ? "play.circle" : "pause.circle")
                }
                .disabled(!appModel.canTogglePresentationPause)
                .help(MicaStrings.localizedKey(pauseTitleKey, language: appLanguage))
                .accessibilityLabel(MicaStrings.localizedKey(pauseTitleKey, language: appLanguage))
            }
            .buttonStyle(.glass)
        }
    }

    @ViewBuilder
    private var content: some View {
        if appModel.selectedRouter == nil, destination.requiresController {
            noControllerState
        } else {
            switch destination {
            case .controllers:
                WorkbenchControllersView(
                    onAddController: onAddController,
                    onEditController: onEditController
                )
            case .overview:
                WorkbenchOverviewView(appModel: appModel)
            case .proxies:
                WorkbenchPolicyGroupsView(appModel: appModel, searchText: $searchText)
            case .connections:
                WorkbenchConnectionsView(appModel: appModel, searchText: $searchText)
            case .logs:
                WorkbenchLogsView(appModel: appModel, searchText: $searchText)
            case .rules:
                WorkbenchRulesView(appModel: appModel, searchText: $searchText)
            case .sources:
                WorkbenchSourcesView(appModel: appModel, searchText: $searchText)
            case .configuration:
                controllerRequired {
                    WorkbenchCoreConfigView(appModel: appModel)
                }
            case .actions:
                controllerRequired {
                    WorkbenchCoreActionsView(appModel: appModel)
                }
            case .diagnostics:
                controllerRequired {
                    WorkbenchDiagnosticsView(appModel: appModel)
                }
            case .settings:
                WorkbenchSettingsView()
            }
        }
    }

    private var noControllerState: some View {
        ContentUnavailableView {
            Label {
                MicaText("dashboard.connect_router")
            } icon: {
                Image(systemName: "network")
            }
        } description: {
            MicaText("dashboard.connect_router_message")
        } actions: {
            Button(action: onAddController) {
                MicaLabel("sidebar.add_controller", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
            .tint(MicaStyle.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func controllerRequired<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if appModel.selectedRouter == nil {
            noControllerState
        } else {
            content()
        }
    }

    private var pauseTitleKey: String {
        appModel.dashboardSessionControls.dashboardUpdatesPaused ? "live.resume" : "live.pause"
    }

    private var controllerSwitcher: some View {
        Menu {
            if switcherProfiles.isEmpty {
                Text(MicaStrings.localizedKey("settings.none", language: appLanguage))
            } else {
                ForEach(switcherProfiles) { router in
                    Button {
                        switchController(to: router)
                    } label: {
                        Label(
                            router.displayName,
                            systemImage: appModel.selectedRouterID == router.id ? "checkmark" : router.controllerKind.editorSymbol
                        )
                    }
                }
            }

            Divider()

            Button {
                destination = .controllers
            } label: {
                Label(MicaStrings.localizedKey("sidebar.controllers", language: appLanguage), systemImage: "server.rack")
            }

            Button(action: onAddController) {
                Label(MicaStrings.localizedKey("sidebar.add_controller", language: appLanguage), systemImage: "plus")
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(controllerStatusTint)
                    .frame(width: 7, height: 7)
                Image(systemName: appModel.selectedRouter?.controllerKind.editorSymbol ?? "server.rack")
                    .foregroundStyle(.secondary)
                Text(appModel.selectedRouter?.displayName ?? MicaStrings.localizedKey("settings.none", language: appLanguage))
                    .lineLimit(1)
                    .frame(maxWidth: 180, alignment: .leading)
            }
        }
        .menuStyle(.button)
        .help(MicaStrings.localizedKey("sidebar.controllers", language: appLanguage))
        .accessibilityLabel(MicaStrings.localizedKey("sidebar.controllers", language: appLanguage))
    }

    private var switcherProfiles: [RouterProfile] {
        guard appModel.routers.count > 10 else { return appModel.routers }

        var profiles: [RouterProfile] = []
        if let selected = appModel.selectedRouter {
            profiles.append(selected)
        }

        let recentIDs = recentControllerIDsRawValue
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
        for id in recentIDs where profiles.count < 9 {
            guard let profile = appModel.routers.first(where: { $0.id == id }),
                  !profiles.contains(where: { $0.id == id }) else { continue }
            profiles.append(profile)
        }
        return profiles
    }

    private var controllerStatusTint: Color {
        guard appModel.selectedRouter != nil else { return .secondary }
        if appModel.dashboardSessionControls.dashboardUpdatesPaused { return MicaStyle.signalAmber }
        switch appModel.controllerSession.state {
        case .live: return MicaStyle.signalMint
        case .connecting: return MicaStyle.signalCyan
        case .partial: return MicaStyle.signalAmber
        case .failed: return MicaStyle.signalRed
        case .idle, .stopped: return .secondary
        }
    }

    private func switchController(to router: RouterProfile) {
        appModel.selectRouter(router)
    }

    private func recordRecentController(
        _ previousID: RouterProfile.ID?,
        excluding selectedID: RouterProfile.ID?
    ) {
        guard let previousID, previousID != selectedID else { return }
        guard appModel.routers.contains(where: { $0.id == previousID }) else {
            pruneRecentControllers()
            return
        }

        var ids = recentControllerIDsRawValue
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
        ids.removeAll { $0 == previousID || $0 == selectedID }
        ids.insert(previousID, at: 0)
        recentControllerIDsRawValue = ids.prefix(8).map(\.uuidString).joined(separator: ",")
    }

    private func pruneRecentControllers() {
        let validIDs = Set(appModel.routers.map(\.id))
        var seen = Set<UUID>()
        let pruned = recentControllerIDsRawValue
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
            .filter { validIDs.contains($0) && seen.insert($0).inserted }
        recentControllerIDsRawValue = pruned.prefix(8).map(\.uuidString).joined(separator: ",")
    }
}

private struct WorkbenchSessionStatusBar: View {
    @Environment(\.micaFontMultiplier) private var fontMultiplier
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let appModel: AppModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            statusContent(showsTime: true)
            statusContent(showsTime: false)
        }
        .frame(height: min(max(32 * fontMultiplier, 32), 44))
        .padding(.horizontal, 12)
        .background(reduceTransparency ? AnyShapeStyle(MicaStyle.glassFallback) : AnyShapeStyle(.bar))
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }

    private func statusContent(showsTime: Bool) -> some View {
        HStack(spacing: 10) {
            Label {
                Text(appModel.selectedRouter?.displayName ?? MicaStrings.localizedKey("settings.none", language: appModel.presentationLanguage))
                    .lineLimit(1)
            } icon: {
                Image(systemName: appModel.selectedRouter?.controllerKind.editorSymbol ?? "server.rack")
                    .foregroundStyle(statusTint)
            }

            Divider()
                .frame(height: 16)

            Image(systemName: statusIcon)
                .foregroundStyle(statusTint)
                .accessibilityHidden(true)

            Text(statusMessage)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            if showsTime, let statusTime {
                Text(statusTime, format: .dateTime.hour().minute().second())
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusTime: Date? {
        if appModel.dashboardSessionControls.dashboardUpdatesPaused {
            return appModel.dashboardSessionControls.presentationPausedAt
        }
        return appModel.controllerSession.lastSuccessAt
    }

    private var statusMessage: String {
        if let operationState = appModel.operationState {
            return operationState.message
        }
        if appModel.dashboardSessionControls.dashboardUpdatesPaused {
            return MicaStrings.localized("operation.dashboard_updates_paused", language: appModel.presentationLanguage)
        }
        return appModel.controllerSession.state.label(language: appModel.presentationLanguage)
    }

    private var statusIcon: String {
        if let operationState = appModel.operationState {
            switch operationState.kind {
            case .working: return "arrow.clockwise"
            case .success: return "checkmark.circle.fill"
            case .partial: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }
        if appModel.dashboardSessionControls.dashboardUpdatesPaused { return "pause.circle.fill" }
        switch appModel.controllerSession.state {
        case .idle, .stopped: return "circle"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .live: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private var statusTint: Color {
        if let operationState = appModel.operationState {
            switch operationState.kind {
            case .working: return MicaStyle.signalCyan
            case .success: return MicaStyle.signalMint
            case .partial: return MicaStyle.signalAmber
            case .error: return MicaStyle.signalRed
            }
        }
        if appModel.dashboardSessionControls.dashboardUpdatesPaused { return MicaStyle.signalAmber }
        switch appModel.controllerSession.state {
        case .idle, .stopped: return .secondary
        case .connecting: return MicaStyle.signalCyan
        case .live: return MicaStyle.signalMint
        case .partial: return MicaStyle.signalAmber
        case .failed: return MicaStyle.signalRed
        }
    }
}
