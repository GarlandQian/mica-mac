# Implementation Plan

## Task Order And Child Gates

This parent task is phase 2 of a mandatory three-phase sequence:

1. complete `08-16-global-functional-audit`, including all verified
   Critical/High/Medium fixes and its preserved-boundary handoff;
2. execute Steps 1-10 in this file;
3. complete `08-16-post-refactor-integration-audit` against the final combined
   code and fix every verified Critical/High/Medium regression.

Do not begin product edits for this parent while the baseline child has an
unresolved blocking finding. Do not mark this parent complete before the final
integration child passes. Parent/child metadata alone is not a dependency
mechanism; this section is the execution gate.

## Preconditions

- Do not run `task.py start` until the user explicitly approves the final
  planning summary produced after this file and `design.md` are reviewed.
- Before editing product code, load `trellis-before-dev` plus the active
  frontend/backend contracts required by the touched files.
- Preserve the unrelated untracked local AI-skill links currently under
  `.agents/skills/`; do not stage or remove them as part of this task.
- Automated validation must not contact a controller or modify networking.

## Step 1. Establish Replacement Preferences And Window Runtime

- Replace the generic layout value types with:
  - fixed telemetry metric IDs;
  - fixed optional module IDs;
  - one `OverviewPreferences` value;
  - one app-owned `OverviewPreferencesStore`.
- Define the redesigned v1 default: all core telemetry metrics, five-minute
  range, and no optional modules.
- Replace the old persisted layout envelope with the new schema discriminator
  and global preference value. Decode failure returns the new default; add no
  migration adapter.
- Extract `LiveSessionWindowDemandID` and the session runtime registry from
  `OverviewDashboardWindowCoordinator` into `OverviewWindowRuntime`.
- Update `MicaApp`, `ContentView`, `WorkbenchChrome`, and environment injection.
- Remove Overview layout dirty-close integration and pending replacement bars;
  retain router-editor close safety.

Validation gate:

- focused preference default/round-trip/reset/dedupe tests;
- old persisted-layout fixture falls back to new default;
- multiple windows observe one shared preference store;
- live-session window demand remains one stable ID per window.

Rollback point: replacement store/runtime compiles while legacy layout source
still exists but is no longer consumed.

## Step 2. Replace Generic Dashboard Composition And Customizer

- Rewrite `WorkbenchDashboard.swift` around the fixed lazy composition:
  telemetry -> topology -> optional region.
- Delete span layout, width-mode column packing, module size, row packer, and
  generic module configuration consumption.
- Rewrite `WorkbenchOverviewEditor.swift` as an immediate inline customizer:
  metric toggles, timeline picker, optional module toggles, Reset.
- Remove preset, reorder, drag/drop, size, global-default, controller-reset,
  Done/Cancel, conflict, and persistence-result UI.
- Keep optional instrument, summary, and network projections source-backed and
  instantiate them only when enabled.

Validation gate:

- fixed default ordering test;
- optional subtree construction test;
- at-least-one-visible-metric normalization test;
- source checks exclude preset/size/row-packer/editor transaction symbols.

Rollback point: fixed composition is functional using existing visual styling.

## Step 3. Introduce Overview Cyber-Neon Primitives

- Add Overview-specific palette/surface/glow/energy primitives derived from
  `MicaStyle` semantic signals.
- Add finite motion tokens for sample pulse, route pulse, HUD appear/expand, and
  pin transitions.
- Apply opaque adaptive surfaces, restrained gradient borders, and bounded
  bloom to Overview only; keep content free of Liquid Glass.
- Add explicit inactive-window, pause, Reduce Motion, and high-contrast inputs
  to motion/style projection where needed.
- Remove duplicate headings, idle chrome, and repeated summary decoration that
  no longer supports the fixed hierarchy.

Validation gate:

- HIG contrast audit for text/surface/signal pairings;
- static Reduce Motion projection tests;
- source check excludes perpetual `TimelineView`/particle/scan-line animation.

## Step 4. Refactor Telemetry As The Hero Stage

- Preserve `OverviewTimelineProjectionCache`, timeline selection, pause, and
  real-sample-only behavior.
- Recompose the three charts as one coherent cyber telemetry stage across wide,
  medium, and narrow widths.
- Add finite latest-edge pulse keyed by the newest real sample identity.
- Keep memory as contextual information on the connection chart.
- Narrow observation so sample pulses do not invalidate topology or optional
  sections.
- Update chart accessibility values, selected/pinned state, and bilingual copy.

Validation gate:

- existing timeline projection/pause/selection tests;
- no fabricated zero samples;
- latest-edge pulse triggers once per new real sample and is static under
  Reduce Motion/pause/inactive state;
- representative width composition source/logic tests.

## Step 5. Build Policy Inspection And HUD Placement Primitives

- Add `OverviewPolicyInspectionIndex` and cache.
- Project unique group, selected member, unique member, ambiguous, and missing
  resolutions without changing controller order.
- Reuse existing typed group/member projections and formatting helpers where
  they already satisfy the HUD contract.
- Add `nodeGeometryByID` to `OverviewTopologyLayout` during the existing layout
  build.
- Add pure transient/pinned HUD size and placement models with candidate scoring,
  obstacle overlap, edge flipping, and final clamping.
- Add `OverviewPolicyHUDSnapshot` projection for transient, pinned, and route
  fallback content.

Validation gate:

- unique group and selected-member resolution;
- unique member resolution;
- duplicate/ambiguous/missing resolution never chooses arbitrarily;
- optional fields remain absent/unavailable without fabrication;
- placement tests cover all sides, corners, narrow graph, expanded HUD, and
  dense obstacles;
- node geometry lookup is O(1) after layout build.

Rollback point: all policy/HUD logic is pure and tested before SwiftUI overlay
integration.

## Step 6. Replace Topology Detail With The Holographic HUD

- Remove the reserved 80-point selection detail inset and related idle/detail
  views from topology geometry.
- Overlay the HUD as its own subtree anchored from cached node geometry.
- Render compact hover and expanded pinned variants.
- Preserve current transient-hover precedence over a pinned selection; leaving
  the transient node restores the pinned HUD.
- Add node click pin toggle, blank-canvas clear, Escape clear, context actions,
  Open Proxies, and eligible Open Connections behavior.
- Keep non-policy node/edge/path selection truthful through a compact route HUD.
- Add accessible labels, values, actions, focus behavior, and help text.
- Keep base/highlight/hit render-band invalidation boundaries.

Validation gate:

- hover/pin/catalog-only changes leave topology structure/layout/cache counts
  unchanged;
- hit testing and path highlighting remain correct;
- keyboard stepping, Escape, context menu, pause, expand, accessibility, and
  navigation tests pass;
- HUD stays inside graph bounds and graph/scroll geometry does not move.

## Step 7. Add Bounded Route Energy And Final Visual Integration

- Add finite connection-revision and interaction-triggered energy overlays to
  topology ribbons and selected trajectories.
- Ensure idle effects settle and no recurring timer remains.
- Make paused/inactive/Reduce Motion rendering static.
- Tune glow radius, opacity, gradients, and typography against dense and sparse
  fixtures in dark/light/high-contrast appearances.
- Apply the new surface language to enabled optional sections without turning
  them into competing hero modules.

Validation gate:

- route pulse trigger/state tests;
- render-band equality/invalidation tests;
- existing dense topology operation-count thresholds do not regress materially;
- HIG contrast and hit-target audit passes.

## Step 8. Delete Legacy Overview Architecture

- Delete or fully replace superseded types and code paths:
  - `OverviewDashboardModuleSize`;
  - `OverviewDashboardPreset`;
  - `OverviewDashboardLayoutNormalizer`;
  - `OverviewDashboardRowPacker` and span layout;
  - old persisted module/metric/summary records and lossy decoder;
  - per-controller override/revision/commit models;
  - layout draft/conflict/commit coordinator behavior;
  - old selection-detail inset implementation.
- Remove obsolete localization keys and update both English/Simplified Chinese
  values for the customizer and HUD.
- Replace old personalization tests rather than keeping compatibility fixtures.
- Update `verify-real-controller-source.mjs` required files and assertions to
  enforce the new v1 architecture and reject removed legacy symbols.

Validation gate:

- repository-wide `rg` confirms removed symbols have no production/test/spec
  references except explicit negative verifier assertions;
- localization format/signature checks pass;
- source contract passes.

## Step 9. Update Durable Contracts And Documentation

- Rewrite the Overview sections in
  `.trellis/spec/frontend/workbench-ui-contract.md`:
  - fixed telemetry/topology composition;
  - simplified global preferences;
  - no compatibility migration;
  - node-anchored HUD and inspection index;
  - bounded data-driven motion and invalidation boundaries.
- Update `docs/UI_GUIDELINES.md` to describe verified final behavior.
- Update `docs/ARCHITECTURE.md` if preference/window runtime ownership changes
  are architectural rather than task-local.
- Remove stale descriptions of the detail inset, controller overrides, presets,
  module sizes, transaction editor, and default network-information visibility.

## Step 10. Consolidated Verification

Run related checks once after all implementation edits, then rerun only failed
checks after fixes:

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 .agents/skills/apple-hig-expert/scripts/hig_checker.py batch scripts/color-contrast-audit.json
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
git diff --check
```

Also perform source/fixture review for:

- default, optional-enabled, empty, stale, narrow, wide, dense topology, light,
  dark, high-contrast, larger font, and Reduce Motion states;
- hover, transient-to-pinned restoration, expanded HUD, Escape, blank clear,
  keyboard path stepping, pause/resume, and controller switch;
- no real-controller access during automated checks.

Runtime visual smoke is user-run only when explicitly permitted.

## Risky Files And Review Gates

- `WorkbenchWindow.swift` / `WorkbenchChrome.swift`: verify live-domain demand
  and router-editor close guard after coordinator removal.
- `WorkbenchOverviewTopology.swift`: preserve topology operation counts and
  structure/layout cache keys.
- `WorkbenchOverviewTopologyView.swift`: preserve hit-test priority, Canvas band
  isolation, keyboard/context/accessibility behavior, and scroll stability.
- `WorkbenchOverviewTelemetry.swift`: preserve real-sample-only charts and
  selection/pause semantics.
- `WorkbenchOverviewLayoutStore.swift` and personalization tests: replacement is
  intentionally incompatible; verify clean default rather than migration.
- `scripts/verify-real-controller-source.mjs`: replace assertions atomically so
  the verifier does not enforce deleted architecture.

## Completion Gate

Implementation is complete only when:

- every PRD acceptance criterion is mapped to code and verification evidence;
- no blocking planning question has reappeared;
- the old Overview compatibility architecture is absent rather than dormant;
- controller-family/session contracts remain unchanged;
- required tests and checks pass;
- task specs/docs reflect the implemented v1 behavior.
- `08-16-global-functional-audit` and
  `08-16-post-refactor-integration-audit` are both complete, their reports cover
  every required matrix row, and neither contains an unresolved
  Critical/High/Medium finding.
