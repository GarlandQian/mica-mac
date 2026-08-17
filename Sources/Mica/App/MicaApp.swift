import AppKit
import SwiftUI

@main
@MainActor
struct MicaApp: App {
    @NSApplicationDelegateAdaptor(MicaAppDelegate.self) private var appDelegate
    private let launchPreferencesApplied: Void = AppLaunchPreferences.applyFromProcessArguments()
    @State private var appModel: AppModel
    @State private var overviewPreferencesStore: OverviewPreferencesStore
    @StateObject private var preferences: AppPreferencesStore
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
        _overviewPreferencesStore = State(
            wrappedValue: OverviewPreferencesStore()
        )
        _preferences = StateObject(wrappedValue: AppPreferencesStore())
    }

    private var appLanguage: AppLanguage {
        preferences.language
    }

    private var appAppearance: AppAppearance {
        preferences.appearance
    }

    private var appFontScale: AppFontScale {
        preferences.fontScale
    }

    var body: some Scene {
        WindowGroup {
            ContentView(overviewPreferencesStore: overviewPreferencesStore)
                .environment(appModel)
                .environmentObject(preferences)
                .micaScenePreferences(
                    language: appLanguage,
                    appearance: appAppearance,
                    fontScale: appFontScale,
                    appModel: appModel
                )
                .micaWindowChrome()
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
                    Label(menuLocalized("command.menu_new_controller"), systemImage: MicaSymbols.Command.add)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(addControllerRequestID == nil)
            }

            CommandGroup(after: .sidebar) {
                Divider()

                ForEach(WorkbenchDestination.workbenchTabCases) { destination in
                    Button {
                        focusedArea?.wrappedValue = destination
                    } label: {
                        Label(menuLocalized(destination.titleKey), systemImage: destination.symbolName)
                    }
                    .modifier(OptionalNumberShortcut(shortcut: destination.shortcut))
                    .disabled(focusedArea == nil)
                }
            }

            CommandMenu(menuLocalized("controller.command_menu")) {
                Button {
                    appModel.testSelectedRouter()
                } label: {
                    Label(menuLocalized("command.menu_test_connection"), systemImage: MicaSymbols.Command.test)
                }
                .disabled(!appModel.canTestSelectedRouter)

                Button {
                    appModel.refreshSelectedRouter()
                } label: {
                    Label(menuLocalized("command.menu_refresh_data"), systemImage: MicaSymbols.Command.refresh)
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!appModel.canRefreshSelectedRouter)

                Divider()

                Button {
                    appModel.toggleDashboardUpdatesPaused()
                } label: {
                    Label(
                        menuLocalized(pauseCommandTitleKey),
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
                    Label(menuLocalized("sidebar.edit"), systemImage: "pencil")
                }
                .disabled(appModel.selectedRouter == nil || editControllerRequestID == nil)

                Divider()

                Button {
                    appModel.copyDiagnosticsReport()
                } label: {
                    Label(menuLocalized("command.menu_copy_diagnostics_report"), systemImage: MicaSymbols.Command.copy)
                }
            }
        }

        Settings {
            MicaSettingsSceneView()
                .environment(appModel)
                .environmentObject(preferences)
                .micaScenePreferences(
                    language: appLanguage,
                    appearance: appAppearance,
                    fontScale: appFontScale,
                    appModel: appModel
                )
                .micaWindowChrome()
                .frame(
                    minWidth: 680,
                    idealWidth: 860,
                    maxWidth: .infinity,
                    minHeight: 560,
                    idealHeight: 680,
                    maxHeight: .infinity
                )
        }
        .defaultSize(width: 880, height: 700)
        .windowResizability(.contentMinSize)
    }

    private var pauseCommandTitleKey: String {
        appModel.dashboardSessionControls.dashboardUpdatesPaused ? "live.resume" : "live.pause"
    }

    private func menuLocalized(_ key: String) -> String {
        MicaStrings.localizedKey(key, language: AppLanguage.menuBarLanguage)
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
    func micaWindowChrome() -> some View {
        background(MicaDesignTokens.pageFill)
            .containerBackground(MicaDesignTokens.pageFill, for: .window)
            .toolbarBackground(MicaDesignTokens.pageFill, for: .windowToolbar)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
    }

    @ViewBuilder
    func micaScenePreferences(
        language: AppLanguage,
        appearance: AppAppearance,
        fontScale: AppFontScale,
        appModel: AppModel
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
                appModel.applyPresentationLanguage(language)
            }
            .onAppear {
                Bundle.setMicaLocalizationLanguage(MicaStrings.resolvedLanguageCode(for: language))
                appModel.applyPresentationLanguage(language)
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
