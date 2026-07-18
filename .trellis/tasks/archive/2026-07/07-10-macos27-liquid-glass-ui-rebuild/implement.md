# Implementation Plan

## Phase 0: Baseline And Contract Repair

- [x] Re-read PRD/design plus Apple macOS 27 Liquid Glass sources and project UI/data specs.
- [x] Record the current source verifier failure caused by the archived task path.
- [x] Update `AGENTS.md` wording so it describes the current Liquid Glass rebuild rather than the archived rebuild as active.
- [x] Refactor `verify-real-controller-source.mjs` to read durable spec/docs and current source instead of a Trellis task path/status.
- [x] Preserve current behavior assertions before visual migration: controller order, full data, no mock, inline operations, localization/preferences.
- [x] Run the repaired source verifier before UI edits.

## Phase 1: Navigation And Window Shell

- [x] Introduce `WorkbenchArea` and child section enums for Overview, Proxies, Activity, Rules & Sources, and System.
- [x] Replace the 10-item flat destination state and migrate stored navigation safely to a default area.
- [x] Build the new `MicaWorkbenchWindow`/content host around native `NavigationSplitView` and `List(selection:)`.
- [x] Rebuild controller selection and full endpoint presentation at the top of the sidebar.
- [x] Replace the old Command menu with standard View navigation and Controller operation menus.
- [x] Consolidate global toolbar actions into native grouped controls; remove the competing top operation strip.
- [x] Add a compact bottom operation/status bar with localized working/success/partial/error states.
- [x] Verify keyboard shortcuts, focused-window routing, window resize, fullscreen, and minimum-size behavior.

## Phase 2: Liquid Glass Foundation

- [x] Remove custom navigation/page backgrounds that block system Liquid Glass.
- [x] Replace `MicaStyle` surface fills with semantic system colors plus restrained Rose Pine accent/status tokens.
- [x] Add one constrained `MicaGlassSelectionSurface` using `glassEffect`, `GlassEffectContainer`, `ConcentricRectangle`, and interactive glass.
- [x] Add Reduce Transparency and Reduce Motion behavior to the glass selection primitive.
- [x] Use native `.glass`/`.glassProminent` button styles instead of custom control chrome where supported.
- [x] Remove unused `MicaPanel`, `MicaPanelTint`, `MicaShellButtonStyle`, and other dead visual helpers as call sites migrate.
- [x] Add source checks preventing arbitrary nested glass/card systems from returning.

## Phase 3: Overview

- [x] Recompose controller identity and health as an unframed header with complete endpoint text.
- [x] Add a bounded real `TrafficTimeline` fed only by received live traffic events.
- [x] Clear timeline state on controller/session changes and never synthesize missing samples.
- [x] Build accessible upload/download Swift Charts only when real samples exist.
- [x] Rebuild cumulative metrics and inventory as typographic groups with separators, not equal card tiles.
- [x] Rebuild endpoint/runtime status as a native table/list with explicit availability.
- [x] Add timeline/availability unit tests and overview runtime-smoke samples.

## Phase 4: Proxies

- [x] Build the fixed-order Liquid Glass strategy-group selection area inside `GlassEffectContainer`.
- [x] Preserve source order through search, selection, refresh, latency tests, pagination, and area changes; never call `sorted`.
- [x] Implement wide selection+detail layout and narrow same-window inline detail layout.
- [x] Show complete group name, type, current selection, count, hidden status, and operation state.
- [x] Build the member list with complete names, type, delay, selection, unavailable, loading, and switching states.
- [x] Keep Mihomo/Surge selection and latency actions capability-gated and inline.
- [x] Add explicit unavailable vs empty policy-group presentation.
- [x] Add order, filtering, selected identity, long-text, and availability tests.

## Phase 5: Activity

- [x] Build Connections/Logs native segmented navigation.
- [x] Replace the hand-built connection grid with SwiftUI `Table` and a same-window inspector.
- [x] Preserve complete ID, host, process, addresses, payload, chains, upload/download, timestamps, and close behavior.
- [x] Rebuild logs as a high-density table/list with complete message text, pause/resume, follow-bottom, level filtering, and clear.
- [x] Keep destructive connection close confirmation within the same window or use only platform-standard destructive confirmation.
- [x] Validate keyboard selection, column resizing, inspector focus, and long-content visibility.

## Phase 6: Rules And Sources

- [x] Build Rules/Sources native segmented navigation.
- [x] Replace manual rule rows with payload-first `Table` plus same-window detail.
- [x] Replace source cards/rows with source tables grouped by real category and capability.
- [x] Preserve full rule payload/type/proxy and source name/vehicle/behavior/count/update fields.
- [x] Keep source updates capability-gated with true loading/success/error states.
- [x] Verify empty, unavailable, partial, search, pagination, and long-text states.

## Phase 7: System, Settings, And Controller Editing

- [x] Build Configuration/Actions/Diagnostics/Settings segmented navigation with conditional Tailscale.
- [x] Rebuild configuration and settings with semantic `Form`, `Section`, `LabeledContent`, Picker, Toggle, and TextField.
- [x] Share one settings form between the System area and the standard Settings scene.
- [x] Rebuild core actions as task groups with explicit capability and risk states, not operation cards.
- [x] Rebuild diagnostics using native tables/disclosures and preserve copy-report boundaries.
- [x] Rebuild controller add/edit as an in-window Form with native Save/Cancel/Test toolbar actions.
- [x] Verify language, appearance, font scale, full endpoint visibility, and credential field handling in both settings presentations.

## Phase 8: Removal And Localization

- [x] Delete old root/sidebar/destination structures and visual helpers after all call sites migrate.
- [x] Delete obsolete background/card/localization keys; do not keep aliases for removed UI concepts.
- [x] Rewrite all visible English and Simplified Chinese labels for the five-area architecture and standard menus.
- [x] Update `AppRuntimeSmokeProbe` and `verify-runtime-smoke.mjs` together for new areas, menus, help, and accessibility samples.
- [x] Scan for old “Command menu”, legacy destination titles, awkward Chinese, middle truncation, and hidden/masked active data.

## Phase 9: Durable Documentation

- [x] Update `.trellis/spec/frontend/workbench-ui-contract.md` with the five-area and Liquid Glass contract.
- [x] Update `docs/UI_GUIDELINES.md` with native glass hierarchy, policy selector exception, shapes, accessibility, and density.
- [x] Update `docs/ARCHITECTURE.md` for the new window/navigation/presentation-state structure.
- [x] Update `docs/DEVELOPMENT.md`, README, and CHANGELOG where commands or architecture changed.
- [x] Ensure source verifier checks durable contracts and never references active/archived task state.

## Phase 10: Verification And Preflight

- [x] `node --check scripts/verify-real-controller-source.mjs`
- [x] `node scripts/verify-real-controller-source.mjs`
- [x] `node --check scripts/verify-runtime-smoke.mjs`
- [x] Build Mica into a repository-local scratch path under `tmp/codex/`.
- [x] Run `swift test` with repository-local scratch output.
- [x] Run runtime smoke across English/Chinese, system/light/dark, and all four font scales.
- [x] Run UI smoke for wide and minimum window sizes without loading real controller profiles or starting a core.
- [x] Inspect screenshots in normal transparency and user-driven Reduce Transparency/Reduce Motion where environment permissions allow.
- [x] Run design-taste, macOS HIG, SwiftUI Liquid Glass, accessibility, contrast, density, icon, shape, and text-overflow preflight over every area.
- [x] Run `git diff --check` and remove disposable `tmp/codex/` outputs.

## Risk And Rollback Points

- Navigation migration: commit separately before destination removal; fallback is the previous root commit, not a compatibility wrapper.
- Real traffic timeline: isolate as presentation state and test controller/session reset before integrating the chart.
- Policy-group order: never change decode/projection order; reject any UI implementation that derives identity from array index after filtering.
- SwiftUI `Table`: verify field visibility and selection behavior at minimum width before deleting old rows.
- Liquid Glass performance: profile large policy sets; limit custom glass to visible group selectors and avoid glass on member/table rows.
- Localization/preferences: update runtime probe in the same commit as renamed destinations to avoid silent coverage loss.
- Verifier migration: first make the verifier independent of task paths, then update assertions incrementally with each vertical slice.

## Completion Evidence

- `node --check scripts/verify-real-controller-source.mjs` and the source contract verifier pass.
- `node --check scripts/verify-runtime-smoke.mjs` and runtime smoke pass against the final repository-local binary.
- `swift test --scratch-path tmp/codex/final-build` passes 18 XCTest cases plus 11 Swift Testing cases.
- Xcode workspace build and test pass with repository-local DerivedData. The installed SDK emits the known warning that it advertises deployment targets only through macOS 26.5.99 while this project intentionally targets macOS 27.
- English and Simplified Chinese, system/light/dark appearance, and all four font scales are covered by runtime preference transitions.
- Wide and 820 x 580 settings layouts were inspected with standard and extra-large text. Native sidebar/toolbar material cannot be captured faithfully by the application-local AppKit bitmap path, and broader screen/window capture is permission-limited; source-level Reduce Transparency/Reduce Motion behavior and Mica-only launch smoke were used for the remaining checks.
- SF Symbols introduced by the five-area shell and policy selectors resolve through AppKit.
- The final full-scope Trellis check agent found and fixed undersized icon-only sidebar hit regions, then passed source verification, build, 29 tests, runtime smoke, and `git diff --check`.
- Durable documentation changed in `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`, `docs/DEVELOPMENT.md`, `docs/UI_GUIDELINES.md`, and `.trellis/spec/frontend/workbench-ui-contract.md`.
- Verification did not load a real controller, access controller APIs, launch/download/bundle a core, or modify system networking.
