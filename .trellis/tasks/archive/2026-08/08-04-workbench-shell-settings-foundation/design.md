# Workbench 壳层、设置与视觉基础设计

## 1. Existing Architecture

- `MicaApp` owns the main `WindowGroup`, native `Settings` scene, Commands, window appearance propagation, and shared window chrome.
- `ContentView` owns the single `NavigationSplitView`, editor replacement flow, close guards, and AppModel/session lifecycle.
- `WorkbenchRootView` owns the native navigation title, toolbar session commands, Workbench content, and bottom status bar.
- `WorkbenchSidebarView` owns the inline controller switcher and ten fixed destination buttons.
- `WorkbenchVisualSystem` owns all shared color, spacing, geometry, typography, motion, command-bar, state, and status primitives.
- `MicaSettingsSceneView` currently lives inside `WorkbenchManagement.swift`; this task mechanically extracts it without changing its public type or store bindings.

## 2. Visual and Interaction Changes

### Shared chrome

- Add one shared chrome separator token and use it for command/status/editor replacement boundaries.
- Keep every chrome band on `pageFill`; reserve `contentFill` and raised fills for actual data surfaces.
- Keep native titlebar/sidebar material system-owned. No content material is introduced.

### Sidebar

- Preserve Button-based custom selection so system selection blue does not override the Midnight Instrument contract.
- Give every destination row a full-width button label and rectangular interaction shape.
- Add row-local move-command handling. Up/down resolves against `WorkbenchDestination.allCases`, preserving the visible Workbench then Controller Management order.
- Keep geometry compact and content-driven; do not introduce a global minimum navigation height.

### Settings

- Extract the settings type and private helpers into `WorkbenchSettings.swift`; update the exact Workbench file contract and source verifier.
- Use a single centered grouped `Form` with an 820pt reading limit and one scroll owner.
- A preference row uses a stable explanatory column and a trailing control column at regular widths; below the existing width threshold it stacks vertically.
- Use native menu controls while preserving localized labels, help, accessibility value, and immediate store mutation.
- Window size remains stable across font choices; text may wrap and increase row height naturally.

## 3. State and Data Boundaries

- No new state authority. Settings binds directly to `AppPreferencesStore`.
- `MicaApp.micaScenePreferences` remains the only cross-window language/appearance application path.
- Sidebar destination changes continue through the existing `Binding<WorkbenchDestination>` so dirty Overview/editor guards remain authoritative.
- No controller session, API, capability, catalog, or persistence code changes.

## 4. Compatibility and Rollback

- Type names and scene entry points remain unchanged, so SwiftPM source discovery requires no package-manifest change.
- The mechanical Settings extraction can be rolled back independently by moving the unchanged types back into `WorkbenchManagement.swift`.
- Sidebar keyboard behavior is additive and can be removed without affecting pointer navigation or routing.

## 5. Verification

- Source verifier checks the exact owned-file list, Settings ownership, one native Settings scene, complete sidebar row semantics, shared page fill/separator, and absence of forbidden command/glass paths.
- Swift tests cover preference options/multipliers and destination order.
- Build/test run against `tmp/codex/swift-build`; runtime smoke and controller access remain prohibited.
