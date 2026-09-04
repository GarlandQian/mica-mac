# Research: Connections AX Localization Cost

- Query: Find the smallest safe fix for repeated system-language resolution in the bounded Connections accessibility representation.
- Scope: internal, with local macOS SDK API verification
- Date: 2026-09-02

## Findings

### Runtime evidence

- `tmp/codex/runtime-ax-acceptance-20260902/connections-post-timeout.sample.txt:57-67` shows the bounded replacement is active: `WorkbenchBoundedAccessibilityTable.accessibleRow` calls `WorkbenchConnectionProjection.accessibilitySummary`, which repeatedly enters `MicaStrings.localizedKey`, `resolvedLanguageCode(for:)`, `AppLanguage.systemLocale`, and `systemLocaleCandidates`.
- The sample's collapsed-symbol section reports 32 samples in `AppLanguage.systemLocale`, 25 in the candidate reduction, and repeated `Locale.preferredLanguages` work (`connections-post-timeout.sample.txt:17716-18032`). The old `NSTableViewCellMockElement -> viewAtColumn:row:makeIfNecessary:` offscreen-cell chain is absent.
- This sample is a one-second observation of a request that timed out at 120 seconds, so it identifies a main-thread cost center but does not prove localization is the only remaining timeout cause. Sustained controller publication work was present concurrently.

### Current language semantics and invalidation

- `AppLanguage.system` is not cached. Every `resolvedLanguageCode(for: .system)` call traverses `Locale.preferredLanguages`, `AppleLanguages`, autoupdating/current locale identifiers, and `AppleLocale`, then allocates a deduplicated candidate array before choosing English or Simplified Chinese (`Sources/Mica/App/AppLanguage.swift:42-103`, `172-180`). Explicit `.english` and `.simplifiedChinese` are constant-time switch cases.
- `MicaStrings.localizedKey(_:language:)` resolves the effective language on every call and only then performs the catalog lookup (`Sources/Mica/App/AppLanguage.swift:257-264`). Connections performs ten such lookups per row (`Sources/Mica/Features/Workbench/WorkbenchConnections.swift:394-436`), so one 32-row AX window can resolve the system language at least 320 times per summary evaluation. SwiftUI/AX may evaluate a row summary more than once.
- The string catalog itself is already cached once as an immutable `static let`; exact-key lookup is a dictionary read with requested-language, English, then key fallback (`Sources/Mica/App/XCStringsResolver.swift:23-31`, `71`, `377-396`). A second broad string cache would duplicate existing storage and would not remove the language-selection call unless it bypassed `MicaStrings.localizedKey`.
- A Settings language change is live and explicit: `AppPreferencesStore.language` is `@Published`, persists its value, and updates Bundle localization (`Sources/Mica/App/AppPreferencesStore.swift:5-17`). `MicaApp` injects that value through `micaAppLanguage`; a raw-value change updates the Bundle and asks `AppModel` to relocalize stored presentation strings (`Sources/Mica/App/MicaApp.swift:29-51`, `187-208`; `Sources/Mica/App/AppModelPresentationLanguage.swift:5-29`). A new AX representation therefore receives the new enum value.
- An operating-system language/locale change while the stored preference remains `.system` has no explicit observer in current source. The next unrelated body evaluation can recalculate `AppLanguage.systemLocale`, but Bundle language and `AppModel.applyPresentationLanguage` are not guaranteed to update because the enum remains `.system` and `applyPresentationLanguage` exits when the enum is unchanged (`Sources/Mica/App/AppModelPresentationLanguage.swift:8-13`). A permanent global `.system` cache would make this existing gap worse.
- `Bundle` protects its active language code with `NSLock` (`Sources/Mica/App/BundleLocalization.swift:8-22`). `XCStringsResolver.catalog` is immutable after thread-safe static initialization. The proposed value snapshot adds no shared mutable state.
- Menu-bar localization is intentionally separate and follows executable-bundle preferred localizations (`Sources/Mica/App/AppLanguage.swift:56-73`; `Sources/Mica/App/MicaApp.swift:161-163`). The AX optimization must not reuse or modify that authority.

### Preferred minimal implementation boundary

Introduce an immutable, `Sendable` resolved localization value under `MicaStrings`, for example `MicaStrings.LocalizationContext`:

```swift
extension MicaStrings {
    struct LocalizationContext: Equatable, Sendable {
        fileprivate let languageCode: String

        func localizedKey(_ key: String) -> String {
            XCStringsResolver.string(forKey: key, languageCode: languageCode)
        }
    }

    static func localizationContext(for language: AppLanguage) -> LocalizationContext {
        LocalizationContext(languageCode: resolvedLanguageCode(for: language))
    }
}
```

Create this context once in `WorkbenchBoundedAccessibilityTable.body`, before `ForEach(rows)`, and change its summary closure from `(Row) -> String` to `(Row, MicaStrings.LocalizationContext) -> String`. Pass the same context through `accessibleRow` to the summary. Change `WorkbenchAccessibilitySummary.field` and the Connections, Logs, Rules, and Sources `accessibilitySummary` functions to accept that context instead of `AppLanguage`.

This is the smallest shared fix because:

- language selection happens once per bounded representation evaluation, not once per row field;
- the existing cached catalog and fallback semantics remain authoritative;
- explicit Settings changes rebuild the environment and create a new context, so English and Simplified Chinese switch immediately through the existing path;
- `.system` is still recalculated on the next representation rebuild, preserving current behavior without adding a stale global cache;
- the immutable value is safe to capture in the AX summary closure and requires no lock, actor, notification observer, or invalidation registry;
- applying it to all four bounded table surfaces prevents the same cost from moving from Connections to Logs, Rules, or Sources.

The page/range and sort controls perform only a bounded number of localization calls. They may also consume the context for consistency, but this is optional for the first fix; the critical invariant is that no row-summary field resolves `AppLanguage.systemLocale`.

Do not add a broad `MicaStrings` result cache or a `static let` system language as part of this fix. If app-wide live response to OS locale changes is later required, it needs a separate design: observe `NSLocale.currentLocaleDidChangeNotification`, invalidate/recompute the effective code, publish a preferences localization revision even when `language == .system`, update Bundle localization, and force `AppModel` relocalization despite the unchanged enum. The local macOS 26.5 SDK declares this notification in `Foundation.framework/Headers/NSLocale.h:133` and exposes the Swift name in `Foundation.apinotes:1454-1455`. That is materially broader than the AX hot path.

### Focused validation

1. `XCStringsResolverTests`: verify a context created for `.english` and `.simplifiedChinese` produces exactly the same known key, fallback, and format-token behavior as `MicaStrings.localizedKey`; verify separate contexts switch output without shared mutation.
2. `WorkbenchDataProjectionTests`: build representative Connections, Logs, Rules, and Sources rows and assert their context-based summaries preserve every value and use the expected English/Chinese labels.
3. Add an offline Release benchmark case that creates one `.system` context and renders 32 Connections summaries repeatedly. Record checksum and work units; run twice. The context-based case should be compared with a temporary legacy per-field case during diagnosis, but production must retain only the context path.
4. Extend `verify-real-controller-source.mjs` to require `(Row, MicaStrings.LocalizationContext) -> String`, context creation before the bounded `ForEach`, and `summary(row, localization)`. Assert the four summary implementations do not call `resolvedLanguageCode(for:)` or `localizedKey(... language:)` per field.
5. Repeat the explicitly authorized read-only runtime AX query. Acceptance evidence: the request completes within its timeout, each page still exposes at most 32 rows, English/Chinese Settings switches rebuild labels, and a fresh sample has no `AppLanguage.systemLocaleCandidates` below a row-summary stack. Do not invoke Test, Refresh, Update, Close, or any controller action.

## Files Found

- `Sources/Mica/App/AppLanguage.swift` - language choices, system candidate resolution, and `MicaStrings` entry points.
- `Sources/Mica/App/XCStringsResolver.swift` - immutable catalog cache and fallback lookup.
- `Sources/Mica/App/AppPreferencesStore.swift` - persisted, published Settings authority.
- `Sources/Mica/App/MicaApp.swift` - environment injection and explicit language-change propagation.
- `Sources/Mica/App/AppModelPresentationLanguage.swift` - stored presentation-string relocalization and unchanged-enum early return.
- `Sources/Mica/App/BundleLocalization.swift` - lock-protected Bundle localization code.
- `Sources/Mica/Features/Workbench/WorkbenchDataShared.swift` - bounded AX table and lazy row-summary loop.
- `Sources/Mica/Features/Workbench/WorkbenchDataPresentation.swift` - shared accessibility field formatter.
- `Sources/Mica/Features/Workbench/WorkbenchConnections.swift` - ten-field Connections summary.
- `Sources/Mica/Features/Workbench/WorkbenchLogPresentation.swift` - Logs summary with the same per-field pattern.
- `Sources/Mica/Features/Workbench/WorkbenchRulePresentation.swift` - Rules summary with the same per-field pattern.
- `Sources/Mica/Features/Workbench/WorkbenchSourcePresentation.swift` - Sources summary with the same per-field pattern.
- `Tests/MicaTests/XCStringsResolverTests.swift` - current English/Chinese resolver coverage.
- `Tests/MicaTests/WorkbenchDataProjectionTests.swift` - projection and summary test home.
- `Tests/MicaTests/MicaPerformanceBenchmarkTests.swift` - offline Release benchmark harness.
- `scripts/verify-real-controller-source.mjs` - bounded AX source-contract verifier.

## Related Specs

- `.trellis/spec/frontend/workbench-ui-contract.md:1003-1133` - bounded high-cardinality accessibility scenario, lazy summary contract, 32-row cap, verifier and runtime smoke requirements.
- `.trellis/spec/frontend/state-management.md:9-19` - `AppPreferencesStore` as app-owned language authority and smallest-owner state rule.
- `.trellis/spec/frontend/component-guidelines.md:58-64`, `81-87` - pure presentation boundaries and localized VoiceOver labels.

## External References

- Installed macOS 26.5 SDK, `Foundation.framework/Headers/NSLocale.h:109,133` - `preferredLanguages` semantics and `NSCurrentLocaleDidChangeNotification` availability.
- Installed macOS 26.5 SDK, `Foundation.framework/Headers/Foundation.apinotes:1454-1455` - Swift name `NSLocale.currentLocaleDidChangeNotification`.

## Caveats / Not Found

- No current source subscribes to the system-locale change notification, so immediate app-wide relocalization while Settings remains `.system` is not an existing guaranteed behavior.
- The runtime sample does not isolate localization from concurrent controller publication work; runtime re-measurement is still required after the focused fix.
- No controller was contacted and Mica was not launched during this research.
