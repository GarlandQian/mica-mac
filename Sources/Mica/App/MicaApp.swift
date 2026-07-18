import AppKit
import SwiftUI

@main
@MainActor
struct MicaApp: App {
    @NSApplicationDelegateAdaptor(MicaAppDelegate.self) private var appDelegate
    private let launchPreferencesApplied: Void = AppLaunchPreferences.applyFromProcessArguments()
    @State private var appModel: AppModel
    @StateObject private var preferences: AppPreferencesStore
    @AppStorage("appLanguage") private var appLanguageRawValue = AppLanguage.system.rawValue
    @AppStorage("appAppearance") private var appAppearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("appFontScale") private var appFontScaleRawValue = AppFontScale.comfortable.rawValue
    @AppStorage("workbenchDestination") private var destinationRawValue = WorkbenchDestination.overview.rawValue
    @FocusedValue(\.micaFocusedWorkbenchDestination) private var focusedArea
    @FocusedValue(\.micaAddControllerRequestID) private var addControllerRequestID
    @FocusedValue(\.micaEditControllerRequestID) private var editControllerRequestID

    init() {
        _ = launchPreferencesApplied
        let storedLanguage = AppLanguage.stored(UserDefaults.standard.string(forKey: AppPreferencesStore.languageKey))
        Bundle.setMicaLocalizationLanguage(MicaStrings.resolvedLanguageCode(for: storedLanguage))
        Bundle.enableModuleLocalization()
        AppRuntimeSmokeProbe.runIfRequested()
        _appModel = State(wrappedValue: AppModel())
        _preferences = StateObject(wrappedValue: AppPreferencesStore())
    }

    private var appLanguage: AppLanguage {
        AppLanguage.stored(appLanguageRawValue)
    }

    private var appAppearance: AppAppearance {
        AppAppearance.stored(appAppearanceRawValue)
    }

    private var appFontScale: AppFontScale {
        AppFontScale.stored(appFontScaleRawValue)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environmentObject(preferences)
                .micaScenePreferences(
                    language: appLanguage,
                    appearance: appAppearance,
                    fontScale: appFontScale
                )
                .frame(minWidth: 820, minHeight: 580)
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button {
                    addControllerRequestID?.wrappedValue += 1
                } label: {
                    Label(localized("command.menu_new_controller"), systemImage: MicaSymbols.Command.add)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(addControllerRequestID == nil)
            }

            CommandGroup(after: .sidebar) {
                Divider()

                ForEach(WorkbenchDestination.workbenchTabCases) { destination in
                    Button {
                        if let focusedArea {
                            focusedArea.wrappedValue = destination
                        } else {
                            destinationRawValue = destination.rawValue
                        }
                    } label: {
                        Label(localized(destination.titleKey), systemImage: destination.symbolName)
                    }
                    .modifier(OptionalNumberShortcut(shortcut: destination.shortcut))
                }
            }

            CommandMenu(localized("controller.command_menu")) {
                Button {
                    appModel.testSelectedRouter()
                } label: {
                    Label(localized("command.menu_test_connection"), systemImage: MicaSymbols.Command.test)
                }
                .disabled(!appModel.canTestSelectedRouter)

                Button {
                    appModel.refreshSelectedRouter()
                } label: {
                    Label(localized("command.menu_refresh_data"), systemImage: MicaSymbols.Command.refresh)
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!appModel.canRefreshSelectedRouter)

                Divider()

                Button {
                    appModel.toggleDashboardUpdatesPaused()
                } label: {
                    Label(
                        localized(pauseCommandTitleKey),
                        systemImage: appModel.dashboardSessionControls.dashboardUpdatesPaused
                            ? MicaSymbols.Operation.resume
                            : MicaSymbols.Operation.pause
                    )
                }
                .disabled(!appModel.canTogglePresentationPause)

                Divider()

                Button {
                    editControllerRequestID?.wrappedValue += 1
                } label: {
                    Label(localized("sidebar.edit"), systemImage: "pencil")
                }
                .disabled(appModel.selectedRouter == nil || editControllerRequestID == nil)

                Divider()

                Button {
                    appModel.copyDiagnosticsReport()
                } label: {
                    Label(localized("command.menu_copy_diagnostics_report"), systemImage: MicaSymbols.Command.copy)
                }
            }
        }

        Settings {
            WorkbenchSettingsView()
                .environment(appModel)
                .environmentObject(preferences)
                .micaScenePreferences(
                    language: appLanguage,
                    appearance: appAppearance,
                    fontScale: appFontScale
                )
                .frame(minWidth: 560, idealWidth: 720, maxWidth: 900, minHeight: 460)
        }
    }

    private var pauseCommandTitleKey: String {
        appModel.dashboardSessionControls.dashboardUpdatesPaused ? "live.resume" : "live.pause"
    }

    private func localized(_ key: String) -> String {
        MicaStrings.localizedKey(key, language: appLanguage)
    }
}

private struct OptionalNumberShortcut: ViewModifier {
    let shortcut: KeyEquivalent?

    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut, modifiers: [.command])
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    func micaScenePreferences(
        language: AppLanguage,
        appearance: AppAppearance,
        fontScale: AppFontScale
    ) -> some View {
        self
            .micaAppPreferences(language: language, appearance: appearance, fontScale: fontScale)
            .onAppear {
                appearance.applyToApplication()
            }
            .onChange(of: appearance.rawValue) { _, _ in
                appearance.applyToApplication()
            }
            .onChange(of: language.rawValue) { _, _ in
                Bundle.setMicaLocalizationLanguage(MicaStrings.resolvedLanguageCode(for: language))
            }
            .onAppear {
                Bundle.setMicaLocalizationLanguage(MicaStrings.resolvedLanguageCode(for: language))
            }
    }
}

private final class MicaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)

        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}
