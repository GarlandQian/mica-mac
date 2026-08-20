import SwiftUI

extension EnvironmentValues {
    @Entry var micaAppLanguage: AppLanguage = .system
    @Entry var micaAppAppearance: AppAppearance = .system
    @Entry var micaAppFontScale: AppFontScale = .comfortable
}

extension View {
    func micaAppPreferences(
        language: AppLanguage,
        appearance: AppAppearance,
        fontScale: AppFontScale
    ) -> some View {
        environment(\.micaAppLanguage, language)
            .environment(\.micaAppAppearance, appearance)
            .environment(\.micaAppFontScale, fontScale)
            .environment(\.locale, language.resolvedLocale)
            .dynamicTypeSize(fontScale.dynamicTypeSize)
            .preferredColorScheme(appearance.colorScheme)
            .tint(MicaTheme.accent)
    }
}
