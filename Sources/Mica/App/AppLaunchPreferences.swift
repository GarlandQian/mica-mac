import Foundation

@MainActor
enum AppLaunchPreferences {
    struct Snapshot {
        var language: AppLanguage
        var appearance: AppAppearance
        var fontScale: AppFontScale
    }

    static func applyFromProcessArguments(
        _ arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard
    ) {
        guard !isRuntimeSmokeProbeRequested(in: arguments) else {
            return
        }

        for (key, value) in parsedOverrides(from: arguments) {
            switch key {
            case AppPreferencesStore.languageKey:
                let language = AppLanguage.stored(value)
                guard language.rawValue == value || value == "english" || value == "simplifiedChinese" else {
                    continue
                }
                defaults.set(language.rawValue, forKey: AppPreferencesStore.languageKey)
            case AppPreferencesStore.appearanceKey:
                guard let appearance = AppAppearance(rawValue: value) else {
                    continue
                }
                defaults.set(appearance.rawValue, forKey: AppPreferencesStore.appearanceKey)
            case AppPreferencesStore.fontScaleKey:
                guard let fontScale = AppFontScale(rawValue: value) else {
                    continue
                }
                defaults.set(fontScale.rawValue, forKey: AppPreferencesStore.fontScaleKey)
            default:
                continue
            }
        }
    }

    static func resolvedSnapshot(
        from arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard
    ) -> Snapshot {
        var snapshot = Snapshot(
            language: AppLanguage.stored(defaults.string(forKey: AppPreferencesStore.languageKey)),
            appearance: AppAppearance.stored(defaults.string(forKey: AppPreferencesStore.appearanceKey)),
            fontScale: AppFontScale.stored(defaults.string(forKey: AppPreferencesStore.fontScaleKey))
        )

        for (key, value) in parsedOverrides(from: arguments) {
            switch key {
            case AppPreferencesStore.languageKey:
                let language = AppLanguage.stored(value)
                guard language.rawValue == value || value == "english" || value == "simplifiedChinese" else {
                    continue
                }
                snapshot.language = language
            case AppPreferencesStore.appearanceKey:
                guard let appearance = AppAppearance(rawValue: value) else {
                    continue
                }
                snapshot.appearance = appearance
            case AppPreferencesStore.fontScaleKey:
                guard let fontScale = AppFontScale(rawValue: value) else {
                    continue
                }
                snapshot.fontScale = fontScale
            default:
                continue
            }
        }

        return snapshot
    }

    static func isRuntimeSmokeProbeRequested(
        in arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains { argument in
            let key = argument
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                .split(separator: "=", maxSplits: 1)
                .first
                .map(String.init)

            return key == "micaRuntimeSmokeProbe" || key == "micaRuntimeSmokeStdout"
        }
    }

    private static func parsedOverrides(from arguments: [String]) -> [(key: String, value: String)] {
        var overrides: [(key: String, value: String)] = []
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            guard argument.hasPrefix("-") else {
                index = arguments.index(after: index)
                continue
            }

            let trimmed = argument.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let key: String
            let value: String?

            if let separator = trimmed.firstIndex(of: "=") {
                key = String(trimmed[..<separator])
                value = String(trimmed[trimmed.index(after: separator)...])
                index = arguments.index(after: index)
            } else {
                key = trimmed
                let nextIndex = arguments.index(after: index)
                if nextIndex < arguments.endIndex, !arguments[nextIndex].hasPrefix("-") {
                    value = arguments[nextIndex]
                    index = arguments.index(after: nextIndex)
                } else {
                    value = nil
                    index = nextIndex
                }
            }

            if let preferenceKey = preferenceKey(for: key),
               let value,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                overrides.append((preferenceKey, value))
            }
        }

        return overrides
    }

    private static func preferenceKey(for launchKey: String) -> String? {
        switch launchKey {
        case AppPreferencesStore.languageKey:
            AppPreferencesStore.languageKey
        case AppPreferencesStore.appearanceKey:
            AppPreferencesStore.appearanceKey
        case AppPreferencesStore.fontScaleKey:
            AppPreferencesStore.fontScaleKey
        default:
            nil
        }
    }
}
