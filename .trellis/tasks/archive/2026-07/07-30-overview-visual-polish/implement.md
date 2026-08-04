# Implementation Plan: Overview Visual And Interaction Polish

## Gate Before Code

- [x] User approves `prd.md`, `design.md`, and this implementation plan.
- [x] Populate real implementation/review context and pass
  `python3 .trellis/scripts/task.py validate 07-30-overview-visual-polish`.
- [x] Start the task only after approval with
  `python3 .trellis/scripts/task.py start 07-30-overview-visual-polish`.
- [x] Record `git status --short` and preserve all unrelated user changes.
- [x] Load `trellis-before-dev`, `mica-controller-development`,
  `swiftui-expert-skill`, `swift-concurrency`, `swift-charts`,
  `macos-app-design`, `apple-hig-expert`, and `swiftui-liquid-glass`.

Do not contact a real controller, access port 9090, launch a core, modify system
networking, or run the old runtime smoke. Keep disposable evidence under
`tmp/codex/overview-visual-polish/`. Perform one concentrated verification pass
after all implementation phases rather than repeatedly rebuilding after small
edits.

## Phase 1: Build The Layout Domain And Persistence Boundary

**Goal:** Create a valid, testable personalization model before changing visible
composition.

### Primary Files

- new `Sources/Mica/Features/Workbench/WorkbenchOverviewPersonalization.swift`
- `Sources/Mica/App/MicaApp.swift`
- `Sources/Mica/App/MainWindowCloseGuard.swift`
- `Sources/Mica/App/LiveSessionRefreshModels.swift`
- `Sources/Mica/App/AppModelLiveSession.swift`
- `Sources/Mica/App/AppModelLiveSessionRuntime.swift`
- `Sources/Mica/App/LiveSessionRuntime.swift`
- `Sources/Mica/Features/Workbench/WorkbenchChrome.swift`
- `Sources/Mica/Features/Workbench/WorkbenchControllerSelector.swift`
- focused preference/layout tests

### Work

- [x] Define stable module IDs, legal sizes, content preferences, presets, and
  deterministic defaults.
- [x] Implement normalization for unknown, duplicate, missing, illegal, empty,
  and corrupted layouts.
- [x] Implement the shared committed store with per-controller narrow observable
  state, effective global/override versions, a store-wide persistence revision,
  retention, and reset/default commands.
- [x] Add versioned persistence-first commits with off-main encoding and inline
  failure retention; serialize and merge typed mutations against the latest
  envelope so concurrent controllers cannot lose updates.
- [x] Inject one store from `MicaApp`; add one window coordinator per
  `ContentView`; keep `WorkbenchWorkspaceStore` window-local.
- [x] Implement window-local draft, a controller/generation/module runtime
  registry, compare-and-swap commit, inherited/default conflict actions, cancel,
  and current-window `UndoManager` integration.
- [x] Implement the pure width-mode row packer and legal-size mapping.
- [x] Write tests alongside the implementation but defer command execution until
  the final verification phase.

## Phase 2: Replace The Overview Shell

**Goal:** Make the personalized layout the sole Overview composition path.

### Primary Files

- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift`
- `Sources/Mica/Features/Workbench/WorkbenchVisualSystem.swift`
- `Sources/Mica/Features/Workbench/WorkbenchWorkspaceView.swift`

### Work

- [x] Remove the duplicated complete session header and four separate KPI cards.
- [x] Add the low unified instrument rail with metric order/visibility.
- [x] Render normalized visible modules through lazy deterministic rows at the
  existing 1,180-point content bound.
- [x] Filter hidden modules before constructing module subtrees.
- [x] Add the Overview toolbar edit command and inline editor bar.
- [x] Add drag/drop insertion, size/hide controls, keyboard move commands, hidden
  module restoration, preset preview, reset, set-default, cancel, and done.
- [x] Add inline content controls for metric order/visibility, timeline window,
  summary category order/visibility/row count, and network group order.
- [x] Enforce one visible dashboard module, one visible instrument metric, and
  one visible category when the summary module is visible.
- [x] Disable business interactions while editing without pausing live state.
- [x] Add inline external-update conflict handling with Reload and Keep Mine.
- [x] Intercept dirty destination/controller changes and extend the existing
  dirty-window close guard; clean edit sessions cancel automatically.
- [x] Replace shared destination `@AppStorage` with window-scoped scene state and
  route menu commands only to the focused window.
- [x] Give each window a stable demand token; replace the single visible
  destination with a token-to-destination registry and domain union.
- [x] Define one complete live-presentation demand snapshot containing the union,
  global pause, logs pause, and baseline state. Window mutations may deduplicate
  unchanged unions, but pause/baseline changes, runtime installation, and
  generation replacement must always synchronize the current snapshot.
- [x] Give complete demand snapshots a generation-scoped monotonic revision.
  Initialize a new actor runtime with the current snapshot before assigning it
  or starting ingestion, and reject stale identity/revision updates inside the
  actor.
- [x] Pass that snapshot to the existing actor runtime, flush newly visible
  domains only through the existing pause/baseline gates, and unregister only
  the disappearing window without creating any second live session or refresh
  loop.
- [x] Preserve a draft bound to an externally switched controller in a suspended
  state; validate target existence before override commit and allow set-default
  or explicit discard after target deletion.
- [x] Route Add/Edit Controller and every Workbench replacement intent through
  the same dirty-draft gate.
- [x] Replace the broad availability catalog scan and stale Equatable gate with
  a narrow Overview availability/layout boundary.
- [x] Remove replaced Overview view types rather than adding compatibility
  wrappers.

## Phase 3: Recompose Telemetry And Summaries

**Goal:** Create one clear first-viewport visual hierarchy without weakening real
data or interaction.

### Primary Files

- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift`
- `Sources/Mica/Features/Workbench/WorkbenchOverviewProjection.swift`
- existing Overview timeline/performance tests

### Work

- [x] Make upload/download the full primary timeline with one shared readout.
- [x] Move memory into a 64-80 point track below the traffic chart.
- [x] Keep the shared cursor, fixed selection, stepping, return-live, and timeline
  window behavior.
- [x] Preserve cached/downsampled received samples and static-series isolation.
- [x] Rebuild latency, rule, and connection summaries inside one composite module
  with configurable category order, visibility, and 1/3/5 rows.
- [x] Use three internal columns when wide and a native segmented category when
  narrow without combining data rankings.
- [x] Preserve complete destination navigation and missing-value semantics.

## Phase 4: Refine Topology And Network Facts

**Goal:** Make the lower Overview legible while preserving complete information.

### Primary Files

- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift`
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift`
- `Sources/Mica/Features/Workbench/WorkbenchOverviewProjection.swift`
- existing topology and projection tests

### Work

- [x] Restyle the complete topology as a neutral base graph with semantic column
  headings and cyan complete-path focus only.
- [x] Preserve all graph records, horizontal overflow, render bands, hit index,
  accessibility rows, pinning, and Connections navigation.
- [x] Ensure layout/edit changes do not rebuild immutable topology structure.
- [x] Group all existing network facts into controller, runtime/features, and
  listener-port definition lists.
- [x] Support network-group order customization without hiding fields.
- [x] Add distinct unavailable/empty states without fabricated values.

## Phase 5: Localize And Update Durable Contracts

**Goal:** Keep source checks and maintained documentation aligned with the new
single Overview architecture.

### Primary Files

- `Sources/Mica/Resources/Localizable.xcstrings`
- `scripts/verify-real-controller-source.mjs`
- `.trellis/spec/frontend/workbench-ui-contract.md`
- `.trellis/spec/frontend/live-session-controller-contract.md`
- `docs/UI_GUIDELINES.md`
- runtime probe only if its static strings/types require replacement

### Work

- [x] Add complete English and Simplified Chinese editor, preset, module, conflict,
  help, and accessibility strings.
- [x] Replace source assertions for the old session header, KPI cards, side memory
  chart, five-row summaries, and adaptive fact wall.
- [x] Migrate `WorkbenchOverviewPerformanceTests.swift` source-boundary checks
  away from removed type names while retaining behavior and operation-count
  assertions.
- [x] Replace the scalar `setVisibleSessionDestination(_:)` contract and migrate
  `LiveSessionPublicationTests.swift`, `LiveSessionRuntimeTests.swift`,
  `SessionStreamStateTests.swift`, and every remaining caller to stable
  per-window demand tokens and complete demand snapshots.
- [x] Assert single instances, lazy row admission, complete topology, real
  timelines, no nested vertical scroll, no custom content glass, and no synthetic
  values.
- [x] Update the Workbench file list for the one cohesive personalization file.
- [x] Update maintained UI documentation at finish; do not preserve obsolete
  fixed-layout wording.

## Phase 6: Concentrated Verification

**Goal:** Prove correctness, accessibility, and performance after the complete
implementation is in place.

### Automated Checks

- [x] Run `swift build`.
- [x] Run `swift test`.
- [x] Run `node --check scripts/verify-real-controller-source.mjs`.
- [x] Run `node scripts/verify-real-controller-source.mjs`.
- [x] Run `python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings`.
- [x] Create a HIG batch file under `tmp/codex/overview-visual-polish/` and run
  `.agents/skills/apple-hig-expert/scripts/hig_checker.py` for paired palette
  contrast and every new 44-point command target.
- [x] Run `./scripts/run-performance-benchmarks.sh overview-visual-polish`.
- [x] Run `git diff --check`.

### Focused Acceptance

- [x] Verify presets, global/default overrides, restart persistence, corruption
  fallback, reset, set-default cancellation, controller deletion, and concurrent
  different-controller commits without lost updates.
- [x] Verify cancel, single commit, undo/redo, cross-window synchronization, and
  explicit conflict resolution, including Cmd-Z/Shift-Cmd-Z window isolation and
  history cleanup.
- [x] Verify per-window destination independence and external selected-controller
  switch/deletion handling for dirty drafts.
- [x] Verify Overview + Logs/Connections window demand unions, token updates,
  unregister behavior, generation replacement, immediate newly-visible flush,
  and one-runtime ownership.
- [x] Verify an unchanged domain union still propagates global pause/resume,
  logs pause/resume, baseline state, runtime installation, and generation
  replacement; newly visible domains must not bypass pause gates.
- [x] Verify intentionally out-of-order demand revisions cannot overwrite the
  newest actor state, and a runtime initialized while paused or Logs-only applies
  that demand before immediate traffic/log ingestion.
- [x] Verify cold-hidden telemetry/topology modules create no expensive work and
  previously visible modules add no work after being hidden.
- [x] Verify pure reorder leaves timeline projection and topology structure/layout
  counts unchanged, hidden modules add zero work, and one topology size change
  causes at most one necessary layout.
- [x] Verify real timeline and complete topology operation counts do not regress
  `07-30-vertical-scroll-jank`.
- [ ] Inspect 360/720/1,180 point layouts, four font sizes, English/Chinese, and
  Follow System/Light/Dark.
- [ ] Verify keyboard, VoiceOver order, chart numeric fallback, Reduce Motion,
  text selection, and full business-value visibility.
- [ ] Use current running-app screenshots only with user authorization. Do not
  substitute old screenshots or run the old runtime smoke.

### Verification Evidence

- AC1-AC12: covered by the replacement source contract plus focused Overview,
  personalization, topology, projection, publication-demand, generation, and
  runtime regression tests.
- AC13: shared responsive, localization, font-scale, and appearance contracts
  pass automated source and unit checks; the requested viewport matrix remains
  an explicit manual visual acceptance item.
- AC14: paired palette contrast and new Overview editor 44-point targets pass
  `hig_checker.py` with score 100. VoiceOver and Reduce Motion remain manual.
- AC15: `swift build`, all 270 tests in 27 suites, source verification,
  localization JSON validation, HIG checks, the offline release benchmark, and
  `git diff --check` pass.
- AC16: intentionally deferred. No current app launch, screenshot substitution,
  runtime smoke, or Instruments capture was performed without separate user
  authorization.
- The release benchmark used offline synthetic fixtures only. Large connection
  and topology cases were stable or faster than the vertical-scroll baseline;
  operation-count contracts remained unchanged.
- No real controller, port 9090, core process, or system networking was used.

### Completion

- [x] Map each PRD acceptance criterion to evidence.
- [x] Confirm no real controller, 9090, core process, system networking, or mock
  production data was used.
- [x] Remove disposable files under `tmp/codex/overview-visual-polish/`.
- [x] Update durable docs/specs only for final implemented behavior.
