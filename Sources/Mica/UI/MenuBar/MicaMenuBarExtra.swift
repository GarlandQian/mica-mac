import AppKit
import MicaCore
import SwiftUI

enum MicaMenuBarRateFormat {
    static func compact(_ bytesPerSecond: Int) -> String {
        MicaFormatters.compactRate(bytesPerSecond)
    }
}

enum MicaMenuBarPolicyProjection {
    static func groups(
        _ catalog: PolicyGroupCatalogSnapshot,
        visibility: GlobalGroupVisibility
    ) -> [ProxyGroupViewState] {
        ProxiesStore.arrangedGroups(from: catalog, visibility: visibility)
            .filter { $0.selectable && !$0.options.isEmpty }
    }
}

/// Menu bar status item label isolated to live traffic updates.
struct MicaMenuBarLabel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    @State private var demandID = LiveSessionWindowDemandID()

    var body: some View {
        label
            .onAppear {
                appModel.menuBarExtraDidAppear()
                appModel.registerLiveSessionWindowDemand(demandID, destination: .menuBar)
            }
            .onDisappear {
                appModel.unregisterLiveSessionWindowDemand(demandID)
                appModel.menuBarExtraDidDisappear()
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

    @ViewBuilder
    private var label: some View {
        if isStreaming {
            let rate = appModel.liveTrafficRate
            Text(
                "\(Image(systemName: "arrow.up")) \(MicaMenuBarRateFormat.compact(rate.upload))  \(Image(systemName: "arrow.down")) \(MicaMenuBarRateFormat.compact(rate.download))"
            )
            .monospacedDigit()
            .accessibilityLabel(
                MicaStrings.localized(
                    "menu_bar.rates_accessibility \(MicaFormatters.formatRate(rate.upload)) \(MicaFormatters.formatRate(rate.download))",
                    language: language
                )
            )
        } else {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .accessibilityLabel(Text(verbatim: "Mica"))
        }
    }

    private var isStreaming: Bool {
        let session = appModel.controllerSessionPresentation
        return appModel.selectedRouterID != nil
            && session.controllerID == appModel.selectedRouterID
            && session.state.allowsLiveCommands
            && !session.controls.dashboardUpdatesPaused
            && appModel.selectedUnifiedCapabilities.traffic
    }
}

private struct MicaMenuBarRatesItem: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    var body: some View {
        let rate = appModel.liveTrafficRate
        Text(
            MicaStrings.localized(
                "menu_bar.rates \(MicaFormatters.formatRate(rate.upload)) \(MicaFormatters.formatRate(rate.download))",
                language: language
            )
        )
    }
}

struct MicaMenuBarContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var preferences: AppPreferencesStore

    var body: some View {
        if let router = appModel.selectedRouter {
            Text(verbatim: "\(router.displayName) · \(sessionStatusLabel)")
            MicaMenuBarRatesItem()
        } else {
            Text(localized("menu_bar.no_controller"))
        }

        if appModel.selectedRouter != nil {
            Divider()

            Button(localized("command.menu_refresh_data")) {
                appModel.refreshSelectedRouter()
            }
            .disabled(!appModel.canRefreshSelectedRouter)

            Button(localized(pauseTitleKey)) {
                appModel.toggleDashboardUpdatesPaused()
            }
            .disabled(!appModel.canTogglePresentationPause)
        }

        Divider()

        policySection

        Divider()

        Button(localized("menu_bar.open_workbench")) {
            NSApplication.shared.activate()
            openWindow(id: MicaSceneID.workbench)
        }

        Button(localized("menu_bar.settings")) {
            NSApplication.shared.activate()
            openSettings()
        }

        Divider()

        Button(localized("menu_bar.quit")) {
            NSApplication.shared.terminate(nil)
        }
    }

    @ViewBuilder
    private var policySection: some View {
        let groups = MicaMenuBarPolicyProjection.groups(
            appModel.policyGroupCatalog,
            visibility: preferences.globalGroupVisibility
        )

        if appModel.selectedRouter == nil {
            EmptyView()
        } else if groups.isEmpty {
            Text(localized("menu_bar.no_policy_groups"))
        } else {
            let scope = LiveCommandScope(
                controllerID: appModel.selectedRouterID,
                generation: appModel.controllerSessionPresentation.generation
            )
            let isSurge = appModel.selectedRouter.map {
                appModel.runtimeControllerKind(for: $0) == .surgeCompatible
            } ?? false
            let canSwitch = appModel.controllerSessionPresentation.state.allowsLiveCommands

            ForEach(groups) { group in
                Menu("\(group.id) — \(group.selected)") {
                    ForEach(group.options, id: \.self) { option in
                        Button {
                            guard let scope else { return }
                            if isSurge {
                                appModel.selectSurgePolicy(option, in: group.id, scope: scope)
                            } else {
                                appModel.selectNode(option, in: group.id, scope: scope)
                            }
                        } label: {
                            HStack {
                                Text(verbatim: option)
                                if option == group.selected {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(!canSwitch)
                    }
                }
            }
        }
    }

    private var sessionStatusLabel: String {
        appModel.controllerSessionPresentation.state.label(language: language)
    }

    private var pauseTitleKey: String {
        appModel.controllerSessionPresentation.controls.dashboardUpdatesPaused
            ? "live.resume"
            : "live.pause"
    }

    private func localized(_ key: String) -> String {
        MicaStrings.localizedKey(key, language: language)
    }
}
