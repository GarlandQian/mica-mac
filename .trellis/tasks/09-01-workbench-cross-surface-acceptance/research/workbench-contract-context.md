# Curated Workbench Contract Context

This is a task-local routing digest for sub-agent context injection. The full authoritative source remains `.trellis/spec/frontend/workbench-ui-contract.md`; use this file to identify the exact constraints relevant to the cross-surface UX task without truncating the full contract.

## Navigation And Inspector

- Keep one `NavigationSplitView`, ten fixed destinations, the current Operate/Observe/Manage groups, native Settings, and the collapsed inline controller switcher.
- Normal work remains in the main window. Do not add page-level popovers, sheets, modal details, or a second navigation model.
- The root `.inspector` is the only detail mechanism. `WorkbenchWorkspaceStore` owns typed, per-window, session-bound inspector selection; pages register live row resolvers and never persist inspector state.
- Inspector, delayed confirmation, and cross-destination intents must remain scoped to controller ID plus generation.
- Bottom status chrome keeps fixed native geometry and truthfully reports live/paused/partial/failed state and operation outcomes.

## Page Archetypes And Visual Rules

- Overview is a full-width monitoring canvas; data browsers use one native Table; Proxies is an ordered inline selection workspace; Controllers/Configuration use native management layouts; Actions is a flat command workspace; Diagnostics is action-first triage; Settings remains a native grouped form.
- Use `MicaTheme` and existing Workbench primitives. Content is opaque and flat: no custom `.glassEffect`, decorative gradient, glow, shadow, nested cards, or ambient animation.
- Management canvases are leading-anchored and bounded. Data browsers fill width. Font preference changes text only; measured width alone chooses compact/regular layout.
- Accent marks selection/active path/primary action/live state only. Status colors carry actual controller state. Interface text uses semantic Mica roles; live values use monospaced data roles.

## Data, State, And Ordering

- Render complete real controller data only. Never fabricate rows, chart samples, latency, capability, or success state.
- Preserve controller and policy group/member order. Filtering changes visibility only; user sorting operates on presentation copies.
- Each destination distinguishes no-controller, loading, unsupported, empty/unloaded, filter-empty, failed-before-first-value, and stale retained content.
- Endpoint failure retains last good values with stale state. Session end/controller change clears operational catalogs and session-bound selection.
- Commands consume the same capability, pause, busy, controller ID, and generation gates at presentation and execution boundaries.

## Performance

- Views observe narrow presentation/catalog state, never broad `controllerSession` or raw runtime.
- Connections, Logs, Rules, Sources, and Proxies keep page-owned projection caches, stable IDs, separate structural/metrics invalidation, and one expensive projection only while visible.
- SwiftUI row/mark bodies do not filter, sort, aggregate, format full strings, decode, or scan related collections.
- Publication budgets remain logs 5 Hz, traffic 4 Hz, connections 2 Hz, memory 1 Hz. Do not add page timers or a second polling/debounce system.
- Expensive work may defer during interaction only if the latest result survives and publishes when interaction becomes idle.
- Comparable Release reports require equal case/fixture/checksum/work units. Retain hot-path optimization only after two target medians improve at least 10% without unrelated repeated >10% regression.

## Preferences, Accessibility, And Validation

- `AppPreferencesStore` is the only language, appearance, font-scale, and GLOBAL-visibility authority. English and `zh-Hans` parameter signatures must match.
- Keyboard focus, native selection, text selection, VoiceOver order, full business values, Reduce Motion, and increased contrast remain usable at wide/narrow widths.
- Mica's macOS pointer contract uses complete row hit areas and 28pt standalone icon controls; do not impose a mobile universal row height.
- Automated checks use fixtures only and never launch Mica, read profiles, contact a controller, invoke remote actions, or modify networking.
- Required gates are Swift build/test, source verifier, localization JSON, contrast/control-geometry audit, diff check, and Trellis validation.

## Known Contract Drift To Resolve

The full contract still contains an older statement that complete topology always fits available width with no nested horizontal viewport. The user-approved `08-23-overview-flow-ribbons` R10 and current source use a conditional horizontal viewport only when long-chain minimum label width exceeds the panel. After visual acceptance, replace the stale sentence with this bounded rule; do not leave both statements.
