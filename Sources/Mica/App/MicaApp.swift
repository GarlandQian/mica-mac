import AppKit
import SwiftUI

@main
@MainActor
struct MicaApp: App {
    @NSApplicationDelegateAdaptor(MicaAppDelegate.self) private var appDelegate
    private let launchPreferencesApplied: Void = AppLaunchPreferences.applyFromProcessArguments()
    @State private var appModel: AppModel
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
        WindowGroup(id: MicaSceneID.workbench) {
            ContentView()
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
        .windowToolbarStyle(.unified)
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

                ForEach(WorkbenchDestination.sidebarCases) { destination in
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
                .disabled(focusedArea == nil || !appModel.canTestSelectedRouter)

                Button {
                    appModel.refreshSelectedRouter()
                } label: {
                    Label(menuLocalized("command.menu_refresh_data"), systemImage: MicaSymbols.Command.refresh)
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(focusedArea == nil || !appModel.canRefreshSelectedRouter)

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
                .disabled(focusedArea == nil || !appModel.canTogglePresentationPause)

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
                .disabled(appModel.selectedRouter == nil)
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
                    minWidth: 540,
                    idealWidth: 660,
                    maxWidth: .infinity,
                    minHeight: 440,
                    idealHeight: 500,
                    maxHeight: .infinity
                )
        }
        .defaultSize(width: 660, height: 500)
        .windowResizability(.contentMinSize)

        MenuBarExtra(isInserted: Binding(
            get: { preferences.showsMenuBarExtra },
            set: { preferences.requestMenuBarExtraInsertion($0) }
        )) {
            MicaMenuBarContent()
                .environment(appModel)
                .environmentObject(preferences)
                .micaAppPreferences(language: appLanguage, appearance: appAppearance, fontScale: appFontScale)
        } label: {
            MicaMenuBarLabel()
                .environment(appModel)
                .environment(\.micaAppLanguage, appLanguage)
                .environment(\.micaAppFontScale, appFontScale)
        }
        .menuBarExtraStyle(.menu)
    }

    private var pauseCommandTitleKey: String {
        appModel.dashboardSessionControls.dashboardUpdatesPaused ? "live.resume" : "live.pause"
    }

    private func menuLocalized(_ key: String) -> String {
        MicaStrings.localizedKey(key, language: preferences.language)
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

extension View {
    /// macOS 27 window chrome. The system draws the Liquid Glass toolbar,
    /// floating sidebar, and inspector over the window background; Mica only
    /// names that background and never paints the toolbar, so content can
    /// scroll beneath the glass with the native scroll-edge effect.
    func micaWindowChrome() -> some View {
        containerBackground(MicaTheme.canvas, for: .window)
    }
}

private extension View {
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
                appModel.applyPresentationLanguage(language)
            }
            .onChange(of: language) { _, newLanguage in
                appModel.applyPresentationLanguage(newLanguage)
            }
    }
}

private final class MicaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        if !Bundle.main.bundlePath.hasSuffix(".app"),
           let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }

        DispatchQueue.main.async {
            NSApplication.shared.activate()
            let workbenchWindow = NSApplication.shared.windows.first {
                $0.styleMask.contains(.titled)
            }
            workbenchWindow?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainWindowCloseGuard.confirmApplicationTermination(for: sender)
    }
}
