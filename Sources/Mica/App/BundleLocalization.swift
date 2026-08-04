import Foundation
import ObjectiveC

extension Bundle {
    /// The resource bundle compiled from `Localizable.xcstrings` by SPM.
    /// Stored once via `static let` (dispatch_once semantics).
    private static let micaResourceBundle: Bundle = .module
    private static let micaLocalizationLock = NSLock()
    nonisolated(unsafe) private static var micaLocalizationLanguageCode = MicaStrings.resolvedLanguageCode
    nonisolated(unsafe) private static var micaLocalizationEnabled = false

    static func setMicaLocalizationLanguage(_ languageCode: String) {
        micaLocalizationLock.lock()
        micaLocalizationLanguageCode = languageCode
        micaLocalizationLock.unlock()
    }

    private static var activeMicaLocalizationLanguageCode: String {
        micaLocalizationLock.lock()
        let languageCode = micaLocalizationLanguageCode
        micaLocalizationLock.unlock()
        return languageCode
    }

    /// Call once at app launch — before any SwiftUI view is rendered —
    /// to make `Bundle.main` forward unresolved localization lookups to
    /// `Bundle.module`, and to route lookups on `Bundle.module` through the
    /// runtime `.xcstrings` resolver so the user's language preference takes
    /// effect under Swift Package Manager builds.
    ///
    /// Under SPM, `Localizable.xcstrings` is shipped as a single JSON document
    /// and `Bundle` reports only the source language (`en`); the standard
    /// `.lproj` mechanism cannot reach `zh-Hans`. The runtime resolver reads
    /// the JSON directly and returns the template for the active language, so
    /// `String(localized:bundle:)` (which performs argument substitution after
    /// the bundle lookup) produces correctly localized, interpolated strings.
    @MainActor
    static func enableModuleLocalization() {
        micaLocalizationLock.lock()
        if micaLocalizationEnabled {
            micaLocalizationLock.unlock()
            return
        }
        micaLocalizationEnabled = true
        micaLocalizationLock.unlock()

        let original = class_getInstanceMethod(
            Bundle.self,
            #selector(localizedString(forKey:value:table:))
        )!
        let replacement = class_getInstanceMethod(
            Bundle.self,
            #selector(_mica_localizedString(forKey:value:table:))
        )!
        method_exchangeImplementations(original, replacement)
    }

    /// After swizzle, calling `_mica_localizedString` invokes the **original**
    /// `localizedString(forKey:value:table:)` implementation.
    @objc private func _mica_localizedString(
        forKey key: String,
        value: String?,
        table tableName: String?
    ) -> String {
        // This calls the original (pre-swizzle) implementation.
        let originalResult = _mica_localizedString(forKey: key, value: value, table: tableName)

        // Route the module resource bundle through the runtime resolver so the
        // user's language preference is honored even when the catalog is a
        // single `.xcstrings` JSON document (SPM builds).
        if self == Bundle.micaResourceBundle {
            let resolved = XCStringsResolver.template(
                forKey: key,
                languageCode: Bundle.activeMicaLocalizationLanguageCode
            )
            if !resolved.isEmpty && resolved != key {
                return resolved
            }
            return originalResult
        }

        // If main bundle couldn't resolve (returns the key itself or the
        // fallback value), try the module resource bundle — which, via the
        // branch above, returns the runtime-resolved localization.
        if self == Bundle.main && (originalResult == key || originalResult == value) {
            return Bundle.micaResourceBundle.localizedString(
                forKey: key, value: value, table: tableName
            )
        }
        return originalResult
    }
}
