import SwiftUI

struct MicaSettingsSceneView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    @Environment(\.micaAppLanguage) private var language

    var body: some View {
        Form {
            Section(L("settings.language", language: language)) {
                Picker(L("settings.language", language: language), selection: $preferences.language) {
                    ForEach(AppLanguage.allCases) { item in
                        Text(L(item.titleKey, language: language)).tag(item)
                    }
                }
                .pickerStyle(.menu)

                Picker(L("settings.appearance", language: language), selection: $preferences.appearance) {
                    ForEach(AppAppearance.allCases) { item in
                        Text(L(item.titleKey, language: language)).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Picker(L("settings.font_scale", language: language), selection: $preferences.fontScale) {
                    ForEach(AppFontScale.allCases) { item in
                        Text(L(item.titleKey, language: language)).tag(item)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(L("navigation.proxies", language: language)) {
                Picker(L("settings.global_group_visibility", language: language), selection: $preferences.globalGroupVisibility) {
                    ForEach(GlobalGroupVisibility.allCases) { item in
                        Text(L(item.titleKey, language: language)).tag(item)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                Toggle(L("settings.menu_bar_extra", language: language), isOn: $preferences.showsMenuBarExtra)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
