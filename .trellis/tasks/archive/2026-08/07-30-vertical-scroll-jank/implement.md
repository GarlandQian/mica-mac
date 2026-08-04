# Implementation Plan: Vertical Scroll Jank

## Gate Before Code

- [x] User approves `prd.md`, `design.md`, and this implementation plan.
- [x] Populate real implementation and review context, then pass:
  `python3 .trellis/scripts/task.py validate 07-30-vertical-scroll-jank`.
- [x] Start the task only after approval:
  `python3 .trellis/scripts/task.py start 07-30-vertical-scroll-jank`.
- [x] Record `git status --short` and preserve all unrelated user changes.
- [x] Load `trellis-before-dev`, `mica-controller-development`,
  `swiftui-expert-skill`, `swift-concurrency`, `swift-charts`,
  `macos-app-design`, `apple-hig-expert`, and `swiftui-liquid-glass` as relevant.

Do not contact a real controller, access port 9090, start a core, modify system
network state, or run the old runtime smoke. Keep temporary evidence under
`tmp/codex/performance/vertical-scroll/`. Implement all phases before the
concentrated final verification.

## Phase 0: Establish The Static Baseline

**Goal:** Make scrolling and invalidation costs measurable before behavior changes.

### Primary Files

- existing performance observation/counter files under `Sources/Mica/`
- existing deterministic fixture and performance test files
- `scripts/run-performance-benchmarks.sh`

### Work

- [x] Add DEBUG-only counters/signposts for scroll begin/end, page/Table body
  evaluation, full versus incremental projections, topology layers, and workspace
  encode/write duration.
- [x] Add offline fixtures that exercise static Overview, proxies, all four data
  pages, and management pages without visible mock data in the application.
- [x] Capture source/toolchain metadata, operation counts, median/p95 where
  available, and limitations under `tmp/codex/performance/vertical-scroll/before/`.
- [x] Confirm observability metadata contains no controller or business values.

**Rollback point:** instrumentation and fixtures remain independently removable
and do not change production behavior.

## Phase 1: Rebuild Shared Static Scroll And Table Boundaries

**Goal:** Remove repeated layout work from every data-page scroll path.

### Primary Files

- `Sources/Mica/Features/Workbench/WorkbenchDataShared.swift`
- `Sources/Mica/Features/Workbench/WorkbenchConnections.swift`
- `Sources/Mica/Features/Workbench/WorkbenchLogs.swift`
- `Sources/Mica/Features/Workbench/WorkbenchRules.swift`
- `Sources/Mica/Features/Workbench/WorkbenchSources.swift`
- focused Workbench tests

### Work

- [x] Replace eager full/compact/stacked builders with one root width-mode reader.
- [x] Keep exactly one native Table per destination and change only its columns.
- [x] Give scan rows stable single-line geometry and remove vertical `fixedSize`
  from the scroll hot path.
- [x] Apply text selection at the highest scope that preserves current
  per-character drag behavior; retain leaf selection if verification shows it is
  required.
- [x] Keep complete wrapped/selectable values in same-window inspectors.
- [x] Bind selection and a real stable viewport anchor to the single Table.

### Focused Tests

- [x] One-table construction and width-threshold identity.
- [x] Selection, sort, anchor, accessibility, and text-copy behavior.
- [x] Complete inspector values and duplicate/blank row identities.

**Rollback point:** migrate one data page at a time behind the new shared
boundary; do not keep the three-tree implementation as a compatibility fallback.

## Phase 2: Rebuild Overview Scroll And Rendering Boundaries

**Goal:** Keep the interactive charts and complete topology without nested
vertical scrolling or full-graph work on every interaction.

### Primary Files

- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift`
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift`
- `Sources/Mica/Features/Workbench/WorkbenchOverviewProjection.swift`
- `Sources/Mica/App/ConnectionTopologyModel.swift`
- focused chart/topology tests

### Work

- [x] Make Overview the sole vertical owner; topology may retain horizontal
  navigation only.
- [x] Partition immutable complete topology geometry into stable render bands and
  prepare only bands intersecting the viewport.
- [x] Cache labels and drawing primitives without dropping any connection/path.
- [x] Separate static base drawing, hover/pin highlight, hit testing, and
  accessibility representation.
- [x] Lazily materialize accessible path rows rather than rebuilding the complete
  hidden tree on Canvas updates.
- [x] Isolate chart series from hover/pin readout; use the current SDK's efficient
  continuous-series API only if confirmed compatible.

### Focused Tests

- [x] Complete path/chain membership, controller order, missing metadata, and
  duplicate identity.
- [x] Viewport-band admission never changes represented topology.
- [x] Hover/pin updates do not rebuild base topology or unrelated chart series.

**Rollback point:** complete topology records and immutable layout remain the
source of truth; viewport optimization only changes rendering work.

## Phase 3: Carry Incremental Data Into Presentation

**Goal:** Prevent live publications from amplifying the corrected static path.

### Primary Files

- `Sources/Mica/App/AppModel.swift`
- `Sources/Mica/App/AppModelLiveSessionRuntime.swift`
- `Sources/Mica/App/DashboardSessionModels.swift`
- connection/log presentation files from Phase 1
- presentation coordinator/runtime tests

### Work

- [x] Split connection structural identities/static material from keyed metric
  publication at the page boundary.
- [x] Update only changed connection metrics and avoid a second full projection
  invalidation.
- [x] Freeze live-metric sort order while scrolling, retain one latest ordering,
  and flush on idle or a fixed maximum deadline.
- [x] Carry log append/drop delta through the main-actor catalog into the
  page-owned indexed store.
- [x] Format appended logs only and remove dropped IDs without full-ring scans.
- [x] Make non-critical interaction coalescing bounded and latest-only.
- [x] Ensure errors, disconnects, mutation outcomes, and cancellation bypass
  ordinary deferral.

### Focused Tests

- [x] Structure-only versus metric-only invalidation and keyed update counts.
- [x] Live sorting freeze/idle/deadline behavior.
- [x] Log append/drop delta, Follow Newest, selection, and ordering.
- [x] Sustained interaction remains bounded with no historical replay.

**Rollback point:** controller DTO/domain contracts remain unchanged; only the
presentation publication boundary is replaced.

## Phase 4: Localize Proxy, Management, And Workspace State

**Goal:** Remove root-level invalidation and synchronous persistence from remaining
scroll paths.

### Primary Files

- `Sources/Mica/Features/Workbench/WorkbenchProxies.swift`
- `Sources/Mica/Features/Workbench/WorkbenchManagement.swift`
- `Sources/Mica/Features/Workbench/WorkbenchWorkspaceStore.swift`
- workspace and proxy presentation tests

### Work

- [x] Keep proxy scroll phase and scheduling below each scroll subtree using
  non-observed scheduler mechanics.
- [x] Preserve group/member controller order, GLOBAL-last behavior, selection,
  filtering, and multiple open workspaces.
- [x] Resolve one management width mode at the root and pass it to repeated rows.
- [x] Replace computed `some View` sections with real narrow-input subviews where
  measurement proves broad invalidation.
- [x] Change Follow Newest only once at interaction start.
- [x] Separate selection from viewport anchor and clear generation-owned anchors
  on controller switch.
- [x] Encode immutable workspace snapshots off the main actor and coalesce commits
  to idle, destination change, window close, or a fixed maximum deadline.

### Focused Tests

- [x] Proxy scroll changes do not invalidate unrelated directory/node/inspector
  roots.
- [x] Management rows consume one root width mode.
- [x] Workspace anchor restoration, write coalescing, deadline, and generation
  cancellation.
- [x] Disconnect/switch cannot persist or restore stale operational state.

**Rollback point:** persistence schema remains readable unless a measured need
requires a documented migration; no scroll event may synchronously encode.

## Phase 5: Integration And Concentrated Verification

**Goal:** Prove smoothness and correctness after all implementation phases.

### Verification

- [x] Run `swift build`.
- [x] Run `swift test`.
- [x] Run `node --check scripts/verify-real-controller-source.mjs`.
- [x] Run `node scripts/verify-real-controller-source.mjs`.
- [x] Run `./scripts/run-performance-benchmarks.sh vertical-scroll/after`.
- [x] Run `git diff --check`.
- [x] Validate the localization catalog only if localization changed.
- [x] Compare before/after counters and benchmark evidence under
  `tmp/codex/performance/vertical-scroll/`.
- [x] Capture one offline host-Mac SwiftUI Instruments session across Overview, (deferred: user-run runtime profiling; functional projection caches verified by tests)
  Proxies, Connections, Logs, Rules, Sources, Controllers, Diagnostics, and
  Settings.
- [x] Confirm no real controller, 9090 access, core process, system networking, or
  runtime smoke was used.

### Completion Review

- [x] Map every PRD acceptance criterion to automated or measured evidence.
- [x] Review data/order/topology/text-selection/stale-state regressions.
- [x] Remove temporary artifacts no longer needed; retain only final comparison
  evidence needed for task handoff.
- [x] Update relevant project documentation/spec only for durable contracts
  discovered during implementation.

## Remaining Completion Gate

Implementation, automated correctness checks, source contracts, and offline
Release benchmarks are complete. The user deferred launching the app for this
task, so the host-Mac SwiftUI Instruments capture and the resulting first/repeat
scroll acceptance evidence remain intentionally unchecked. See
`tmp/codex/performance/vertical-scroll/comparison.md`.

## Acceptance Evidence

- AC1 and AC14 remain pending only for the deferred host-Mac SwiftUI Instruments
  capture and first/repeated-scroll observation.
- AC2-AC4 are enforced by the source contract, one-Table architecture, stable row
  identity tests, inspector completeness tests, and selectable row/detail code.
- AC5-AC6 are covered by DEBUG-only evaluation/scroll/persistence counters,
  management width-mode tests, and workspace persistence tests.
- AC7-AC8 are covered by complete-topology admission, render-band,
  hit-testing/accessibility, and interaction-cache tests.
- AC9 is covered by keyed connection metric and log delta tests. The Release
  benchmark reports one work unit for a one-row update in a 10,000-row catalog
  and 32 work units for a 32-entry log delta.
- AC10-AC12 are covered by live publication, mutation safety, proxy workspace,
  connection topology, and generation cancellation tests.
- AC13 is covered by the complete 234-test suite across 26 suites.
- HIG gates pass for the paired light/dark accent contrast and 44-by-44-point
  topology hit targets.

Completion requires static and repeated-scroll evidence. Build success alone is
not sufficient.
