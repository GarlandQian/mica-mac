import AppKit
import Combine
import Foundation

@MainActor
final class AppPreferencesStore: ObservableObject {
    nonisolated static let languageKey = "appLanguage"
    nonisolated static let appearanceKey = "appAppearance"
    nonisolated static let fontScaleKey = "appFontScale"
    nonisolated static let globalGroupVisibilityKey = "globalGroupVisibility"
    nonisolated static let showsMenuBarExtraKey = "showsMenuBarExtra"

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

    /// Shows live rates and policy switching in the menu bar; while shown it
    /// keeps the live session running after the last window closes.
    @Published var showsMenuBarExtra: Bool {
        didSet {
            pendingMenuBarInsertion?.cancel()
            pendingMenuBarInsertion = nil
            guard defaults.object(forKey: Self.showsMenuBarExtraKey) as? Bool != showsMenuBarExtra else {
                return
            }
            defaults.set(showsMenuBarExtra, forKey: Self.showsMenuBarExtraKey)
        }
    }

    private let defaults: UserDefaults
    private var pendingMenuBarInsertion: Task<Void, Never>?

    /// MenuBarExtra can write its binding while SwiftUI is updating the scene,
    /// including writing the current value. Never publish back into that update.
    func requestMenuBarExtraInsertion(_ isInserted: Bool) {
        pendingMenuBarInsertion?.cancel()
        pendingMenuBarInsertion = nil
        guard showsMenuBarExtra != isInserted else { return }

        pendingMenuBarInsertion = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self else { return }
            self.pendingMenuBarInsertion = nil
            guard self.showsMenuBarExtra != isInserted else { return }
            self.showsMenuBarExtra = isInserted
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.language = AppLanguage.stored(defaults.string(forKey: Self.languageKey))
        self.appearance = AppAppearance.stored(defaults.string(forKey: Self.appearanceKey))
        self.fontScale = AppFontScale.stored(defaults.string(forKey: Self.fontScaleKey))
        self.globalGroupVisibility = GlobalGroupVisibility.stored(defaults.string(forKey: Self.globalGroupVisibilityKey))
        self.showsMenuBarExtra = defaults.object(forKey: Self.showsMenuBarExtraKey) as? Bool ?? true

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
