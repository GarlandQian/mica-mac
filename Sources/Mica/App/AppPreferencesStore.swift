import AppKit
import Combine
import Foundation

@MainActor
final class AppPreferencesStore: ObservableObject {
    static let languageKey = "appLanguage"
    static let appearanceKey = "appAppearance"
    static let fontScaleKey = "appFontScale"
    static let globalGroupVisibilityKey = "globalGroupVisibility"

    @Published var language: AppLanguage {
        didSet {
            persist(language.rawValue, forKey: Self.languageKey)
            Bundle.setMicaLocalizationLanguage(MicaStrings.resolvedLanguageCode(for: language))
        }
    }

    @Published var appearance: AppAppearance {
        didSet {
            persist(appearance.rawValue, forKey: Self.appearanceKey)
            appearance.applyToApplication()
        }
    }

    @Published var fontScale: AppFontScale {
        didSet {
            persist(fontScale.rawValue, forKey: Self.fontScaleKey)
        }
    }

    @Published var globalGroupVisibility: GlobalGroupVisibility {
        didSet {
            persist(globalGroupVisibility.rawValue, forKey: Self.globalGroupVisibilityKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.language = AppLanguage.stored(defaults.string(forKey: Self.languageKey))
        self.appearance = AppAppearance.stored(defaults.string(forKey: Self.appearanceKey))
        self.fontScale = AppFontScale.stored(defaults.string(forKey: Self.fontScaleKey))
        self.globalGroupVisibility = GlobalGroupVisibility.stored(defaults.string(forKey: Self.globalGroupVisibilityKey))

        Bundle.setMicaLocalizationLanguage(MicaStrings.resolvedLanguageCode(for: language))
        appearance.applyToApplication()
    }

    private func persist(_ value: String, forKey key: String) {
        guard defaults.string(forKey: key) != value else {
            return
        }

        defaults.set(value, forKey: key)
    }

}
