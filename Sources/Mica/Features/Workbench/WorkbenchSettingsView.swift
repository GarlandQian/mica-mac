import MicaCore
import SwiftUI

struct WorkbenchSettingsView: View {
    var body: some View {
        MicaSettingsForm()
    }
}

struct MicaSettingsForm: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var preferences: AppPreferencesStore
    @Environment(\.micaAppLanguage) private var environmentLanguage
    @AppStorage(AppPreferencesStore.languageKey) private var appLanguageRawValue = AppLanguage.system.rawValue
    @AppStorage(AppPreferencesStore.appearanceKey) private var appAppearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(AppPreferencesStore.fontScaleKey) private var appFontScaleRawValue = AppFontScale.comfortable.rawValue
    @AppStorage(AppPreferencesStore.globalGroupVisibilityKey) private var globalGroupVisibilityRawValue = GlobalGroupVisibility.followMode.rawValue

    private var appLanguage: AppLanguage { AppLanguage.stored(appLanguageRawValue) }
    private var appAppearance: AppAppearance { AppAppearance.stored(appAppearanceRawValue) }
    private var appFontScale: AppFontScale { AppFontScale.stored(appFontScaleRawValue) }
    private var globalGroupVisibility: GlobalGroupVisibility { GlobalGroupVisibility.stored(globalGroupVisibilityRawValue) }

    var body: some View {
        Form {
            Section {
                Picker(MicaStrings.localizedKey("settings.language", language: environmentLanguage), selection: appLanguageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(MicaStrings.localizedKey(language.titleKey, language: appLanguage)).tag(language)
                    }
                }
                .help(MicaStrings.localizedKey("settings.help_language", language: appLanguage))
                .accessibilityLabel(MicaStrings.localizedKey("settings.acc_language", language: appLanguage))

                Picker(MicaStrings.localizedKey("settings.appearance", language: environmentLanguage), selection: appAppearanceBinding) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(MicaStrings.localizedKey(appearance.titleKey, language: appLanguage)).tag(appearance)
                    }
                }
                .help(MicaStrings.localizedKey("settings.help_appearance", language: appLanguage))
                .accessibilityLabel(MicaStrings.localizedKey("settings.acc_appearance", language: appLanguage))

                Picker(MicaStrings.localizedKey("settings.font_scale", language: environmentLanguage), selection: appFontScaleBinding) {
                    ForEach(AppFontScale.allCases) { scale in
                        Text(MicaStrings.localizedKey(scale.titleKey, language: appLanguage)).tag(scale)
                    }
                }
                .help(MicaStrings.localizedKey("settings.help_font_scale", language: appLanguage))
                .accessibilityLabel(MicaStrings.localizedKey("settings.acc_font_scale", language: appLanguage))
            } header: {
                MicaText("settings.appearance_section")
            }

            Section {
                Picker(MicaStrings.localizedKey("settings.global_group_visibility", language: environmentLanguage), selection: globalGroupVisibilityBinding) {
                    ForEach(GlobalGroupVisibility.allCases) { visibility in
                        Text(MicaStrings.localizedKey(visibility.titleKey, language: appLanguage)).tag(visibility)
                    }
                }
                .help(MicaStrings.localizedKey("settings.help_global_group_visibility", language: appLanguage))
                .accessibilityLabel(MicaStrings.localizedKey("settings.acc_global_group_visibility", language: appLanguage))
            } header: {
                MicaText("settings.routing_section")
            }

            Section {
                controllerSummary
            } header: {
                MicaText("settings.controller_section")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(MicaStrings.localizedKey("workbench.settings", language: appLanguage))
        .micaAppPreferences(language: appLanguage, appearance: appAppearance, fontScale: appFontScale)
        .onAppear(perform: synchronizePreferences)
        .onChange(of: appLanguage.rawValue) { _, _ in synchronizePreferences() }
        .onChange(of: appAppearance.rawValue) { _, _ in synchronizePreferences() }
        .onChange(of: appFontScale.rawValue) { _, _ in synchronizePreferences() }
    }

    @ViewBuilder
    private var controllerSummary: some View {
        if let router = appModel.selectedRouter {
            detailRow("settings.active_controller", value: router.displayName)
            detailRow("settings.controller_type", value: router.controllerKind.micaLabel(language: appLanguage))
            detailRow("settings.controller_endpoint", value: router.endpointURL)
            detailRow("settings.controller_tls", value: tlsPolicyLabel(router.tlsPolicy))
            detailRow("settings.controller_last_connected", value: lastConnectedLabel(router.lastConnectedAt))
        } else {
            detailRow("settings.active_controller", value: localized("settings.none"))
            detailRow("settings.controller_type", value: localized("settings.none"))
            detailRow("settings.controller_endpoint", value: localized("settings.none"))
            detailRow("settings.controller_tls", value: localized("settings.none"))
            detailRow("settings.controller_last_connected", value: localized("settings.none"))
        }
    }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(get: { appLanguage }) { language in
            appLanguageRawValue = language.rawValue
            preferences.language = language
        }
    }

    private var appAppearanceBinding: Binding<AppAppearance> {
        Binding(get: { appAppearance }) { appearance in
            appAppearanceRawValue = appearance.rawValue
            preferences.appearance = appearance
        }
    }

    private var appFontScaleBinding: Binding<AppFontScale> {
        Binding(get: { appFontScale }) { scale in
            appFontScaleRawValue = scale.rawValue
            preferences.fontScale = scale
        }
    }

    private var globalGroupVisibilityBinding: Binding<GlobalGroupVisibility> {
        Binding(get: { globalGroupVisibility }) { visibility in
            globalGroupVisibilityRawValue = visibility.rawValue
            preferences.globalGroupVisibility = visibility
        }
    }

    private func detailRow(_ titleKey: String, value: String) -> some View {
        LabeledContent(MicaStrings.localizedKey(titleKey, language: appLanguage)) {
            Text(verbatim: value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func synchronizePreferences() {
        Bundle.setMicaLocalizationLanguage(MicaStrings.resolvedLanguageCode(for: appLanguage))
        appModel.applyPresentationLanguage(appLanguage)
        appAppearance.applyToApplication()
        if preferences.language != appLanguage { preferences.language = appLanguage }
        if preferences.appearance != appAppearance { preferences.appearance = appAppearance }
        if preferences.fontScale != appFontScale { preferences.fontScale = appFontScale }
    }

    private func tlsPolicyLabel(_ policy: TLSValidationPolicy) -> String {
        localized(policy == .allowSelfSigned ? "editor.tls_self_signed_short" : "editor.tls_system_short")
    }

    private func lastConnectedLabel(_ date: Date?) -> String {
        guard let date else { return localized("settings.never") }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(appLanguage.resolvedLocale))
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        MicaStrings.localized(key, language: appLanguage)
    }
}
