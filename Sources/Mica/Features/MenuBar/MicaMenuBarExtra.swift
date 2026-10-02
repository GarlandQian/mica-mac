import AppKit
import MicaCore
import SwiftUI

/// Compact transfer-rate text for the menu bar, where width is scarce:
/// decimal units like the Overview, one decimal below ten, no "/s".
enum MicaMenuBarRateFormat {
    private static let units = ["K", "M", "G", "T"]

    static func compact(_ bytesPerSecond: Int) -> String {
        let value = max(bytesPerSecond, 0)
        guard value >= 1_000 else { return "\(value) B" }
        var scaled = Double(value) / 1_000
        var unitIndex = 0
        while scaled >= 999.95, unitIndex < units.count - 1 {
            scaled /= 1_000
            unitIndex += 1
        }
        let number = scaled < 9.95
            ? String(format: "%.1f", scaled)
            : String(Int(scaled.rounded()))
        return "\(number) \(units[unitIndex])"
    }
}

/// Selectable policy groups as the menu bar presents them: the workbench's
/// arranged order and GLOBAL visibility, limited to groups a user can switch.
enum MicaMenuBarPolicyProjection {
    static func groups(
        _ catalog: PolicyGroupCatalogSnapshot,
        visibility: GlobalGroupVisibility
    ) -> [ProxyGroupOccurrence] {
        ProxyProjection.arrangedGroups(
            catalog.groups,
            mode: catalog.mode,
            visibility: visibility
        )
        .filter { $0.group.selectable && !$0.group.options.isEmpty }
    }
}

/// The status item label: live rates while a session streams, otherwise
/// only the symbol. It also holds the live session and its traffic demand
/// for as long as the item is shown.
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
                    "menu_bar.rates_accessibility \(OverviewFormat.rate(rate.upload)) \(OverviewFormat.rate(rate.download))",
                    language: language
                )
            )
        } else {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .accessibilityLabel(Text(verbatim: "Mica"))
        }
    }

    private var isStreaming: Bool {
        appModel.selectedRouterID != nil
            && appModel.controllerSessionPresentation.controllerID == appModel.selectedRouterID
            && appModel.controllerSessionPresentation.state.allowsLiveCommands
    }
}

/// Menu-style content: controller and rates, one submenu per selectable
/// policy group with its members in reported order, and app commands.
struct MicaMenuBarContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var preferences: AppPreferencesStore

    var body: some View {
        if let router = appModel.selectedRouter {
            Text(verbatim: router.displayName)
            let rate = appModel.liveTrafficRate
            Text(
                MicaStrings.localized(
                    "menu_bar.rates \(OverviewFormat.rate(rate.upload)) \(OverviewFormat.rate(rate.download))",
                    language: language
                )
            )
        } else {
            Text(localized("menu_bar.no_controller"))
        }

        Divider()

        policySection

        Divider()

        Button(localized("menu_bar.open_workbench")) {
            openWorkbench()
        }
        .keyboardShortcut("o")

        SettingsLink {
            Text(localized("menu_bar.settings"))
        }
        .keyboardShortcut(",")

        Divider()

        Button(localized("menu_bar.quit")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var policySection: some View {
        let groups = MicaMenuBarPolicyProjection.groups(
            appModel.policyGroupCatalog,
            visibility: preferences.globalGroupVisibility
        )
        if groups.isEmpty {
            Text(localized("menu_bar.no_policy_groups"))
        } else {
            Text(localized("menu_bar.policy_groups"))
            ForEach(groups) { occurrence in
                Menu {
                    Picker(
                        occurrence.group.id,
                        selection: selection(for: occurrence.group)
                    ) {
                        ForEach(occurrence.group.options, id: \.self) { option in
                            Text(verbatim: optionTitle(option, in: occurrence.group))
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(!canSwitch(occurrence.group))
                } label: {
                    Text(verbatim: "\(occurrence.group.id) — \(occurrence.group.selected)")
                }
            }
        }
    }

    private func selection(for group: ProxyGroupViewState) -> Binding<String> {
        Binding(
            get: { group.selected },
            set: { option in
                guard option != group.selected,
                      canSwitch(group),
                      let scope = LiveCommandScope(
                        controllerID: appModel.selectedRouterID,
                        generation: appModel.controllerSessionPresentation.generation
                      ) else { return }
                if isSurge {
                    appModel.selectSurgePolicy(option, in: group.id, scope: scope)
                } else {
                    appModel.selectNode(option, in: group.id, scope: scope)
                }
            }
        )
    }

    private func optionTitle(_ option: String, in group: ProxyGroupViewState) -> String {
        guard let delay = group.delays[option] else { return option }
        let latency = delay > 0
            ? OverviewFormat.latency(delay)
            : localized("latency.timeout")
        return "\(option)  ·  \(latency)"
    }

    private func canSwitch(_ group: ProxyGroupViewState) -> Bool {
        appModel.controllerSessionPresentation.state.allowsLiveCommands
            && appModel.switchingGroupID == nil
            && (isSurge
                ? appModel.supportsUnifiedAction(.selectSurgePolicy)
                : appModel.supportsUnifiedAction(.switchPolicy))
    }

    private var isSurge: Bool {
        guard let router = appModel.selectedRouter else { return false }
        return appModel.runtimeControllerKind(for: router) == .surgeCompatible
    }

    /// Brings an existing workbench window forward, or opens one when the
    /// menu bar item is the only thing running.
    private func openWorkbench() {
        NSApplication.shared.activate()
        if appModel.mainWindowCount > 0,
           let window = NSApplication.shared.windows.first(where: {
               $0.identifier?.rawValue.hasPrefix(MicaSceneID.workbench) == true
           }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: MicaSceneID.workbench)
        }
    }

    private func localized(_ key: String) -> String {
        MicaStrings.localizedKey(key, language: language)
    }
}

enum MicaSceneID {
    static let workbench = "workbench"
}
