# Implementation Plan: Workbench Acceptance Recovery

## Gate Before Code

- [x] User reviews and approves `prd.md`, `design.md`, and this plan.
- [x] `python3 .trellis/scripts/task.py validate 07-28-workbench-acceptance-recovery`
      passes with real implementation/check context.
- [x] Start the task with
      `python3 .trellis/scripts/task.py start 07-28-workbench-acceptance-recovery`.
- [x] Implementation agents load `macos-app-design`, `apple-hig-expert`,
      `swiftui-liquid-glass`, `swiftui-expert-skill`,
      `mica-controller-development`, and the task manifests before editing.
- [x] Record the initial `git status --short`; do not overwrite or revert
      unrelated user changes.

Do not run repeated runtime smoke launches after individual edits. Complete all
phases, then run the concentrated validation matrix in Phase 8.

## Phase 1: Correct Session Storage And Publication

**Goal:** Remove global invalidation hot paths and make lifecycle state truthful
before rebuilding views on top of it.

**Primary files:**

- `Sources/Mica/App/SessionBuffers.swift`
- `Sources/Mica/App/DashboardSessionModels.swift`
- `Sources/Mica/App/DashboardSessionControls.swift`
- `Sources/Mica/App/OperationSessionModels.swift`
- `Sources/Mica/App/LiveSessionRefreshModels.swift`
- `Sources/Mica/App/AppModel.swift`
- `Sources/Mica/App/AppModelLiveSession.swift`
- `Sources/Mica/App/AppModelSelectionState.swift`
- controller-operation extensions that still mutate broad dashboard/log state

### Checklist

- [x] Replace the log front-removing array with an O(1) byte-budgeted ring.
- [x] Add raw revision and snapshot/delta support without materializing on every
      append.
- [x] Replace closed rows with timestamped current-session history capped at 200
      rows and 30 minutes.
- [x] Remove log ownership from observable `DashboardSnapshot` and adapt Surge,
      sing-box, pause/resume, clear, and diagnostics paths.
- [x] Replace broad `synchronizeDomainCatalogs()` use with explicit guarded
      domain publication APIs.
- [x] Add destination visibility to the presentation coordinator.
- [x] Add non-restarting cadence scheduling: logs 5 Hz, traffic 4 Hz,
      connections 2 Hz, memory 1 Hz.
- [x] Make hidden destinations retain raw state without publishing expensive UI
      projections; force one immediate flush on entry.
- [x] Add explicit session-end reasons and clear all operational presentation on
      switch/delete/end/sleep.
- [x] Add stale-reconnecting state and disable live mutation capabilities.
- [x] Stage capability-aware reconnect data and atomically commit the first
      complete valid replacement snapshot.
- [x] Preserve existing controller ID plus generation checks on every async
      apply and mutation intent.

### Focused Test Work

- [x] Rewrite buffer tests for FIFO/byte/count/time eviction and revisions.
- [x] Add deterministic cadence tests with an injected scheduler/clock.
- [x] Add domain revision-isolation tests.
- [x] Add stop/stale/reconnect atomicity and old-generation rejection tests for
      Mihomo, Surge, and sing-box presentation boundaries.

**Rollback point:** session/buffer changes must remain reviewable without any
Workbench layout changes. If a controller family cannot produce the designed
atomic baseline, stop and revise `design.md` rather than publishing mixed state.

## Phase 2: Window Workspace And Chrome

**Goal:** Establish destination visibility, per-controller page state, and quiet
native window chrome used by all redesigned pages.

**Primary files:**

- `Sources/Mica/Features/Workbench/WorkbenchChrome.swift`
- `Sources/Mica/Features/Workbench/WorkbenchVisualSystem.swift`
- `Sources/Mica/App/MicaCommandFocus.swift` where cross-page selection requires it

### Checklist

- [x] Add the window-owned controller/destination workspace store.
- [x] Preserve and restore search, filters, sort, selection, scroll anchors, and
      proxy workspaces according to the PRD lifecycle.
- [x] Notify AppModel/presentation coordinator when destination changes.
- [x] Support same-window navigation intents carrying a selected connection.
- [x] Keep eleven direct sidebar destinations in the approved three groups.
- [x] Keep the controller switcher compact, collapsed by default, and isolated
      from live-domain observation.
- [x] Remove repeated controller identity and decorative toolbar treatments.
- [x] Keep only native search and shared session commands in the toolbar.
- [x] Make the bottom status bar consume the new truthful session phase and one
      stable timestamp.
- [x] Consolidate visual tokens and primitives without adding content glass,
      nested cards, or a competing palette.

### Focused Test Work

- [x] Workspace state isolation/restoration/clearing tests.
- [x] Navigation intent and stale-generation selection tests.
- [x] Sidebar destination grouping and command capability tests.

**Rollback point:** chrome/workspace changes compile against temporary existing
page entry points before the page implementations are replaced.

## Phase 3: Rebuild Policy Groups

**Goal:** Replace the 62-card wall and inline full-width expansions with a
performant master-detail selector.

**Primary file:**

- `Sources/Mica/Features/Workbench/WorkbenchProxies.swift`

### Checklist

- [x] Build the 280-340 pt ordered group directory with fixed-height rows.
- [x] Build the 720-900 pt active node workspace.
- [x] Keep multiple groups open as horizontal tabs in controller order; render
      only the active tab's member collection.
- [x] Preserve ordinary group order and append visible GLOBAL last.
- [x] Preserve member order and controller-reported SMART usage labels without
      local re-ranking.
- [x] Cache group/member search projection by real revision and query.
- [x] Use a virtualized fixed-height node list/table for groups near 798 members.
- [x] Clicking an eligible node invokes the existing typed selection method.
- [x] Keep group/node latency tests, filtering, selected state, and fixed-state
      clear inline in the same window.
- [x] Keep full names visible/selectable in the detail workspace while scan rows
      retain stable geometry.

### Focused Test Work

- [x] Controller order, GLOBAL-last, duplicate occurrence, open-tab order, and
      active-tab-only projection tests.
- [x] Per-controller/per-group filter and selection state tests.
- [x] Non-selectable group and stale member mutation rejection tests.
- [x] SMART labels prove they come only from controller-reported values.

**Rollback point:** the new master-detail implementation replaces the old board
as one file-level change; do not retain the rejected board as a compatibility
fallback.

## Phase 4: Rebuild Data Browsers

**Goal:** Make Connections, Logs, Rules, and Sources fast, compact, and complete.

**Primary file:**

- `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift`

### Checklist

- [x] Implement one compact data-browser scaffold with fixed command region,
      virtualized scan rows, and selection-driven inspector.
- [x] Connections: separate Active and Closed; remove closed rows from all live
      totals; add clear history; keep close commands generation-safe.
- [x] Logs: consume coalesced snapshots/deltas, cache projection, retain incoming
      order, and cap Follow Newest at 5 Hz.
- [x] Rules: pre-index connection matches once per visible connection revision.
- [x] Sources: preserve controller order, complete metadata, and typed update /
      update-all / health operations.
- [x] Expose every reported row field in selectable inspectors without masking.
- [x] Remove repeated KPI strips and duplicated timestamps/classification copy.
- [x] Reconcile row selection when data changes without selecting a different
      row accidentally.

### Focused Test Work

- [x] Active/closed lifecycle and retention tests.
- [x] Incremental log projection/filter/order/follow tests at 2,000 entries.
- [x] Rules index and Sources ordering/operation tests.
- [x] Complete inspector field and stable identity tests, including blank or
      duplicate controller IDs.

**Rollback point:** all four destinations share the new scaffold in the same
file; incomplete migration must not leave two competing data-page systems.

## Phase 5: Rebuild Overview And Complete Topology

**Goal:** Produce a focused interactive dashboard with complete route topology
and no eager lower-page overload.

**Primary files:**

- `Sources/Mica/App/ConnectionTopologyModel.swift`
- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift`

### Checklist

- [x] Reduce first viewport to session state, four live readouts, one primary
      traffic chart, and one compact memory chart.
- [x] Keep only short latency anomalies, top active connections, and rule-hit
      summary before the topology.
- [x] Remove closed connection/session aggregation and the raw connection
      selector/inspector from Overview.
- [x] Rebuild network information as a compact aligned facts grid.
- [x] Replace fixed four-layer/capped topology with dynamic complete path records
      containing every reported chain hop.
- [x] Include every active connection path record; never Top-N or paginate the
      graph. Represent missing route metadata explicitly without fake edges.
- [x] Preserve shared vertices/aggregated edges plus per-connection path
      membership for full-chain highlighting.
- [x] Run graph normalization and size-dependent layout off the main actor,
      keyed by generation/revision/viewport.
- [x] Cache immutable layout geometry and a spatial hit index.
- [x] Draw in one Canvas pass with no continuous animation and no per-edge
      observed view hierarchy.
- [x] Use a constrained scrollable topology viewport to reveal the complete
      intrinsic graph.
- [x] Implement hover/pin/path highlighting and `Open in Connections` selection.
- [x] Preserve an accessible complete path representation outside Canvas.

### Focused Test Work

- [x] Every chain hop, variable path depth, shared vertices, all-active admission,
      deterministic order, and path-membership tests.
- [x] Missing route/source and duplicate/blank connection identity tests.
- [x] Cancellation, stale revision, layout caching, and hit-index tests.
- [x] Overview excludes closed data and downsampling uses only real samples.

**Rollback point:** graph model/layout and Overview composition are separate
commits-in-waiting/review units even though the supervising session owns the
eventual single commit.

## Phase 6: Rebuild Management And Settings Pages

**Goal:** Apply one readable native management system to the remaining five
destinations.

**Primary file:**

- `Sources/Mica/Features/Workbench/WorkbenchManagement.swift`

### Checklist

- [x] Controllers master-detail with ordered list and trailing edit/delete.
- [x] Configuration grouped form in a 960-1100 pt adaptive canvas.
- [x] Actions capability-grouped vertical list with trailing commands.
- [x] Diagnostics concise summary plus lazily created disclosures.
- [x] Settings native grouped form bound only to `AppPreferencesStore`.
- [x] Keep one/two-column readable layouts and intentional ultra-wide whitespace.
- [x] Apply shared empty/loading/unsupported/failed/stale states centered in the
      remaining content region.
- [x] Verify language, appearance, and font changes invalidate every visible
      destination/chrome surface without changing fixed control geometry.

### Focused Test Work

- [x] Existing typed action/capability and preference tests updated to the new
      presentation.
- [x] Controller edit/delete alignment and generation-safe action tests.
- [x] Diagnostics disclosure laziness and complete selectable value tests.

## Phase 7: Data Correctness, Localization, And Contract Updates

**Goal:** Remove visible placeholder/sentinel defects and align automated source
contracts with the final architecture.

**Primary files:**

- `Sources/Mica/Resources/Localizable.xcstrings`
- affected formatting/localization helpers
- `scripts/verify-real-controller-source.mjs`
- relevant project specs only when the implementation establishes a durable new
  contract

### Checklist

- [x] Audit all eleven destinations, sidebar, toolbar, status bar, menus, help,
      inspector, and accessibility labels in English and Simplified Chinese.
- [x] Eliminate visible `%@`, `%lld`, raw keys, duplicated labels, and awkward
      implementation terminology.
- [x] Treat sentinel/missing timestamps as unavailable, not 1970.
- [x] Preserve missing latency as unavailable and reported zero as `0 ms`.
- [x] Preserve deterministic `0 B` and `0 B/s`.
- [x] Keep active UI full-visible and existing credential/raw-body export limits.
- [x] Update source verifier assertions for six Workbench files, destination
      visibility, domain publication, complete topology, and removed legacy
      concepts.

## Phase 8: Concentrated Verification And Acceptance

Run only after Phases 1-7 are integrated.

### Static And Unit Verification

```bash
git diff --check
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
```

### HIG Audit

- [x] Create `tmp/codex/hig-audit.json` covering every custom foreground/background
      pairing and custom hit region.
- [x] Run:

```bash
python3 .agents/skills/apple-hig-expert/scripts/hig_checker.py batch tmp/codex/hig-audit.json
```

- [x] Score 90 or above with no unresolved contrast or sub-44-point target
      failures. The batch audit scored 100 with no violations. Runtime-only
      VoiceOver, keyboard-focus, Reduce Transparency, font-scale, and layout
      inspection is deferred with the visual acceptance pass below.

### Runtime Visual And Performance Acceptance (Deferred By User)

- [x] Intentionally skipped for this task at the user's request. No runtime smoke,
      app launch, real-controller connection, screenshot capture, or profiling
      was performed. These checks remain the entry criteria for a future visual
      acceptance/research task and are not represented as completed here.

Deferred scope:

- Use the user's real controller dataset, not generated production mock data.
- Capture all eleven destinations in light/dark, wide/compact, and all font
  scales under `tmp/codex/acceptance/`.
- Exercise the large policy, node, log, connection, inspector, and topology data
  sets while collecting SwiftUI and Time Profiler evidence.
- Verify disconnect, stale read-only, reconnect, explicit end/switch clearing,
  complete topology paths, accessibility, and responsive layout behavior.

### Final Repository Check

```bash
git status --short
git diff --stat
```

Delete disposable artifacts in `tmp/codex/` that are not needed for final
acceptance/handoff. Do not commit or push until the user requests the final
commit step.

## Review Gates

- Session/data reviewer checks Phase 1 before UI integration continues.
- Performance reviewer checks log, connection, projection, and topology paths
  after all pages are integrated.
- Native design reviewer checks all eleven destinations as one system, not page
  by page in isolation.
- Automated implementation recovery completes when the static, unit, source,
  localization, and HIG gates pass. The user explicitly deferred runtime visual
  acceptance to a future task, so it does not block this task's completion.

## Completion Record

Completed on 2026-07-29 without runtime smoke or a real controller session:

- `swift build` passed using repository-local scratch directories.
- `swift test` passed: 173 tests in 19 suites, zero failures.
- `node --check scripts/verify-real-controller-source.mjs` passed.
- `node scripts/verify-real-controller-source.mjs` passed.
- `python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings` passed.
- `git diff --check` passed.
- Apple HIG batch audit scored 100 with zero violations.
- Trellis implementation and check context validation passed.
- No application launch, controller/core/service operation, commit, or push was
  performed.
