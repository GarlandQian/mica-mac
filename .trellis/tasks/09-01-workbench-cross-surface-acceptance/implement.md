# Implement: Workbench Cross-Surface UX Acceptance

## Execution Rules

- Active task: `.trellis/tasks/09-01-workbench-cross-surface-acceptance`.
- Main session dispatches `trellis-implement`, then `trellis-check`; sub-agents read curated JSONL context before task artifacts.
- Preserve unrelated work and current source order/optionality. Use `tmp/codex/` for all scratch/build/benchmark output.
- Do not launch Mica, connect to a controller, run runtime smoke, or invoke remote actions without new explicit permission.
- Do not add dependencies, compatibility layers, content glass, fabricated data, or a new visual system.

## Phase 0. Dependency And Baseline

- [x] Explicitly take over `08-23-overview-flow-ribbons` after its true-Sankey
  visual failed real-data acceptance; inherit only its complete topology,
  ordering, interaction, index, and long-chain viewport foundations.
- [x] Confirm clean/understood git status and record the implementation rollback point.
- [x] Run focused baseline tests for Workbench navigation/preferences/proxy workspace/overview performance/data projections.
- [x] Capture an offline Release benchmark baseline only if the implementation will touch topology or high-cardinality projection hot paths.
- [x] Re-read the 14-module audit matrix and map every planned code edit to a PRD acceptance criterion.

## Phase 1. Inspector Continuity

- [x] Add `WorkbenchInspectorSelection.owningDestination` and focused mapping tests.
- [x] Add separate store operations for true dismiss and destination-transition hide; make non-none `selectInspector` reopen even when selection identity is unchanged.
- [x] Gate `WorkbenchInspectorContainer` detail by active destination.
- [x] Wire root destination lifecycle to hide cross-destination detail without erasing the outgoing destination workspace selection.
- [x] Route all inspector X buttons through true dismiss and verify row-selection reconciliation.
- [x] Test controller switch/generation end/session stop clearing, destination return restoration, and no stale resolver access.

Likely files: `WorkbenchWorkspaceStore.swift`, `WorkbenchChrome.swift`, `WorkbenchWorkspaceView.swift`, shared inspector consumers, `WorkbenchNavigationTests.swift`, `WorkbenchPreferencesTests.swift`, and verifier assertions.

## Phase 2. Topology Selection Location

- [x] Add a pure viewport-target resolver using existing topology layout/index geometry.
- [x] Bind the overflow ScrollView to stable anchors/position and reveal only offscreen selected targets.
- [x] Show native horizontal scroll affordance only when long-chain content exceeds the viewport.
- [x] Cover node/edge/path, keyboard/click/programmatic selection, stale target, short-chain, overflow, and Reduce Motion behavior.
- [x] Verify no topology rebuild, timer, implicit full-tree animation, or measurable performance regression.

Likely files: `WorkbenchOverviewTopology.swift`, `WorkbenchOverviewTopologyView.swift`, `WorkbenchOverviewPerformanceTests.swift`, verifier assertions.

## Phase 3. Sparse Actions Balance

- [x] Add a pure sparse/dense Actions layout decision based on real command/group count and measured width.
- [x] Use 780pt one-column content for 1-2 commands and preserve current 1,080pt adaptive layout for denser command sets.
- [x] Preserve related destinations, exact capability gates, inline confirmation, command order, and full button labels.
- [x] Test 0/1/2/many command states in live/partial/recovery/unsupported/busy scenarios and English/Chinese copy pressure.

Likely files: `WorkbenchActionsPresentation.swift`, `WorkbenchActions.swift`, `WorkbenchManagementProjectionTests.swift`, verifier assertions.

## Phase 4. Fourteen-Module Evidence Pass

- [x] Audit global shell/sidebar/status, Overview, Proxies, Connections, Logs, Rules, Sources, Controllers/RouterEditor, Configuration, Actions, Diagnostics, Settings, menu, and toolbar against the task matrix.
- [x] Check narrow/medium/wide composition and all four font scales; fix only deterministic overlap, truncation, scroll ownership, focus, state, or space-balance failures.
- [x] Check no-controller/loading/unsupported/empty/filter-empty/failed-first/stale/paused/partial consistency and capability/pause/busy gates.
- [x] Check English/`zh-Hans`, menus, help, tooltips, accessibility labels/order, Reduce Motion, and increased-contrast semantics.
- [x] Add focused tests or verifier assertions for every retained fix; do not perform unrelated restyling.

## Phase 5. Performance And Quality Gate

- [x] Run focused test suites after their owning phase.
- [x] If a measured hot path changed, capture two comparable after reports and enforce checksum/work-unit equality plus the 10% retention/regression rule.
- [x] Run source verifier and localization JSON validation.
- [x] Run Swift build and complete Swift tests once the focused work is stable.
- [x] Run contrast audit for both appearances and project-specific macOS control-geometry assertions.
- [x] Run `git diff --check` and Trellis validation for this child and the `08-04` parent.

Validation commands:

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
git diff --check
python3 .trellis/scripts/task.py validate 09-01-workbench-cross-surface-acceptance
python3 .trellis/scripts/task.py validate 08-04-workbench-native-ui-system
```

Optional offline benchmark when relevant:

```bash
scripts/run-performance-benchmarks.sh before
scripts/run-performance-benchmarks.sh after-1
scripts/run-performance-benchmarks.sh after-2
```

### Implementation Evidence (2026-09-01)

- Rollback point: `a251d31278886de2337e0be78b456d5fe4899eeb`.
  Baseline worktree contained only the understood `08-04` task-state edit and
  the new `09-01` task artifacts.
- The inherited `08-23` work was limited to the already-approved interaction
  follow-up. Light/dark visual acceptance remains a user step; this run did not
  launch Mica.
- Baseline focused suites passed: 61 tests across Navigation, Preferences,
  Overview Performance, and Management Projection. No Release benchmark was
  captured because the implementation adds an O(1) viewport lookup plus one
  bounded selected-path scan; it does not change topology layout/admission or a
  high-cardinality projection hot path.
- Phase-focused results: Inspector Navigation 16/16, topology performance and
  reveal 18/18, sparse Actions 28/28. After the evidence-pass repairs,
  integrated Navigation + Management passed 47/47.
- Complete offline validation passed after the independent-check repair:
  `swift build --scratch-path tmp/codex/swift-build`, full
  `swift test --scratch-path tmp/codex/swift-build` (344 Swift Testing tests in
  27 suites, plus the XCTest suites from the same successful run),
  `node --check scripts/verify-real-controller-source.mjs`,
  `node scripts/verify-real-controller-source.mjs`, localization JSON parsing,
  `git diff --check`, and both child/parent Trellis validations.
- The project HIG batch audit passed with score 100 and no contrast violations;
  the source verifier retained the Mica-specific 28-point macOS pointer-control
  metrics and prohibited a universal mobile touch-target rule.
- The 14-surface evidence pass retained three additional defects: exact
  occurrence navigation for duplicate/blank connection IDs; subtree-scoped
  Escape cancellation for Actions and Controllers confirmations; and shared
  AppModel availability gates for toolbar, Configuration, and Diagnostics UI.
  No unrelated visual restyling was performed.
- High-priority residual: AppModel remote-command entry points were not changed
  because they are outside this task's presentation boundary. A follow-up must
  add defense-in-depth capability/busy/live-session and generation validation
  for non-UI or stale programmatic callers; see
  `research/cross-surface-audit.md` F8/residual.
- Independent Trellis check found and fixed one late-lifecycle race: an
  outgoing page could clear a newer inspector selection owned by another
  destination. Page reconciliation now uses owner-gated clearing, while the
  explicit inspector close remains the only clear-and-hide operation. The
  focused Navigation suite passed 18/18 after the repair, and the source
  verifier plus `git diff --check` passed.

### Reopened Runtime Accessibility Pass (2026-09-02)

- [x] Launch the already-built Mica executable under explicit user permission
  and browse the configured Nikki controller without invoking Test, Refresh,
  Update, Close, or another remote action.
- [x] Reproduce the high-cardinality accessibility failure and capture a
  process sample. Normal real-data idle measured about 4.5% CPU; timed-out AX
  snapshots left Mica at about 102% and 195% CPU.
- [x] Trace the trigger to native Table offscreen cell creation and the
  unbounded Overview topology accessibility replacement; record the evidence
  in `research/connections-accessibility-hotspot.md`.
- [x] Add one shared, bounded accessibility-window contract with a maximum of
  32 ordered items, complete Previous/Next reachability, clamping, and selected
  item reveal. Keep visual Tables/topology and complete controller data intact.
- [x] Apply the bounded representation to every source-backed high-cardinality
  surface supported by the evidence, with exact selection/Inspector/navigation
  behavior and localized range/page controls.
- [x] Run focused 2,000-item tests, source verifier, full offline quality gates,
  and independent `trellis-check` review.
- [ ] Repeat the authorized read-only AX snapshot on populated Connections and
  Overview; require bounded output, completion within the client timeout, and
  CPU return toward the pre-snapshot baseline.

Implementation and independent review now cover Connections, Logs, Rules,
Sources, Overview policy nodes, and Overview paths. The checker additionally
removed eager full-collection AX summaries, replaced high-frequency complete-ID
scans with indexed or prefix-delta reconciliation, stopped hover-driven Overview
page movement, and made Rules/Sources reorder reveal the retained selection.
The complete offline suite passed 354 tests across 27 suites, including 46 data
projection tests and the 96-unique-policy-node Overview traversal case.

Two comparable Release reports were captured at
`tmp/codex/performance/ax-final-1/mica-performance.json` and
`tmp/codex/performance/ax-final-2/mica-performance.json` against the two
`health-nav-final` baselines. All 25 case signatures, fixture counts, and
checksums match. No case regressed by more than 10% in both after runs;
connection keyed metric update measured -4.48%/+3.84%, log full-ring
incremental projection -2.17%/-3.76%, and log steady-state delta projection
+1.65%/-2.41%. The authorized runtime repeat remains open because the Mac was
locked; no controller command was invoked while retrying access.

A later authorized read-only repeat reached the configured Nikki session. The
bounded Connections replacement was active and the old
`NSTableViewCellMockElement -> viewAtColumn:row:makeIfNecessary:` chain was
absent, but the AX request still timed out while CPU remained around 100-150%.
The follow-up samples isolated two remaining costs without finding a duplicate
refresh loop or cadence change:

- bounded row summaries repeatedly resolved `AppLanguage.systemLocale` for
  every localized field;
- the existing five-second medium REST lane recursively decoded every known
  `/proxies` field through `MihomoJSONValue`.

The retained fixes resolve one immutable `MicaStrings.LocalizationContext` per
bounded Table body and directly decode known proxy/history fields while using
the generic recursive decoder for unknown fields and unexpected known-field
shapes. Controller order, optionality, complete metadata, `testUrl` precedence,
malformed-response behavior, AppModel capabilities, and the five-second refresh
lane remain unchanged. See `research/connections-ax-localization-cost.md` and
`research/controllers-proxy-refresh-cpu.md`.

The proxy decoder's two comparable Release reports are under
`tmp/codex/performance/proxy-decode-{before,after}-{1,2}/mica-performance.json`.
All 26 case names, fixture counts, checksums, and reported work units match.
`proxy-response-decode#2000` improved by 23.93% and 20.91%; no unrelated case
regressed by more than 10% in both after runs. The latest full offline suite
passed 357 Swift Testing tests across 27 suites plus all XCTest suites; the
post-fix authorized runtime AX repeat remains the open acceptance item.

### User-Reported Ultrawide Chrome Sizing (2026-09-02)

- A real-controller Connections screenshot showed the one-row pulse strip
  absorbing roughly half of an ultrawide, short window. The flexible vertical
  `Divider` in that supplementary row exposed that `WorkbenchPageScaffold`
  did not distinguish content-height chrome from its remaining-height content.
- The audit covered every direct scaffold caller: Overview, Proxies, Actions,
  Controllers, Configuration, Diagnostics, RouterEditor, and the shared data
  browser wrapper used by Connections, Logs, Rules, and Sources. Every
  `commands` closure contains only command/status/stale/supplementary chrome;
  none owns a page-height canvas or requires remaining-height expansion.
- `WorkbenchPageScaffold` now fixes only the commands region to its intrinsic
  vertical size while leaving horizontal proposals intact for `ViewThatFits`.
  The main content remains the sole flexible-height child with explicit layout
  priority. Narrow and large-text command/supplementary fallbacks can therefore
  grow to their natural multiline height without consuming arbitrary space.
- The source verifier now requires both scaffold invariants. Focused offline
  validation passed: source verifier, Node syntax check, scoped diff check,
  Debug `swift build`, and `WorkbenchNavigationTests` 18/18. No Mica process
  was launched and no controller was contacted by this implementation pass;
  the main session retains the authorized ultrawide visual confirmation.

### Final Integrated Gate Repair (2026-09-04)

- The pre-commit full gate exposed three drifts left by the reopened pass: the
  verifier still asserted the pre-cancellable Overview projection entry point
  and the pre-refactor AppModel refresh-gate location; and
  `runImmediateSessionRefreshLane` called the `private` `performSessionRefresh`
  across files. All were aligned to the intended architecture (cancellable
  projection entry point, refresh-gate assertion at its definition site,
  internal refresh lane), plus one missing `projection` source load in
  `WorkbenchOverviewPerformanceTests`.
- The full suite also caught six regressions where the `canBeginLiveAction`
  refactor had silently dropped rejection outcomes: provider update/health
  check/rule mutation for incapable entities and provider update-all while
  paused or busy. AppModel now keeps `canBeginLiveAction` as the pure UI
  predicate and adds `admitLiveActionIntent` as the command boundary:
  current-session rejections publish truthful `.partial` outcomes (session
  unavailable, paused, busy, capability, entity), while stale controller or
  generation intents stay silent so they cannot mutate the replacement
  session. Entity rejections publish before catalog-membership staleness
  checks; provider batch races reject without cancelling the active batch.
- Final offline gate passed: source verifier, Node syntax check, localization
  JSON, `git diff --check`, Debug `swift build`, and the complete `swift test`
  (396 Swift Testing tests in 27 suites plus 109 XCTest tests). Both child and
  parent Trellis validations pass.

### Final Workbench Hotspot And Command Audit (2026-09-04)

- The final cross-surface pass split Rules and Providers publication, added
  exact Mihomo endpoint change plans, isolated connection structure and metrics
  observation tokens, and moved Overview topology/highlight catalog reads behind
  cancellable request revalidation. Traffic-only frames no longer invalidate
  structure or connection-highlight observers.
- Connections, Logs, Rules, and Sources now hide the native Table AX subtree and
  expose a detached, equatable, maximum-32-row pure payload host. Proxies uses
  one bounded global group/member AX window. Complete visual rows, controller
  order, selection, Inspector data, sort controls, and named actions remain.
- Remote command ownership now distinguishes user Refresh from internal lane
  work, keeps Test available after failure and while paused, preserves active
  owners on duplicate intents, and resolves exact current Rules/Connections
  targets before mutation.
- `LiveCommandScope` closes same-controller generation replacement for retained
  Configuration, Rules visual/AX, Proxy visual/AX, and Logs level handlers. A
  fresh checker found and fixed the last two omissions: Surge log-level Picker
  dispatch and Proxy AX group-toggle/Locate Current workspace effects. Test and
  Refresh intentionally retain activation-time current-session semantics.
- Main validation passed Node syntax/source contract, localization JSON,
  `git diff --check`, Debug build, focused 157 tests in seven suites, and the
  complete pre-check Swift Testing run of 412 tests in 28 suites; all XCTest
  suites in the same run also passed. After the fresh Trellis checker repaired
  the two final scope omissions, the final gate passed 167 focused tests in five
  suites and 413 Swift Testing tests in 28 suites, plus all XCTest suites.
- Comparable Release reports are
  `tmp/codex/performance/workbench-final-{1,2}/mica-performance.json`. Both have
  the same 30 case names, fixture counts, and checksums; no case regressed by
  more than 10% in both runs versus `mihomo-medium-gating`. Against the 28
  matching `dashboard-equality-before-full-{1,2}` cases, deterministic fields
  match and policy-catalog equality improved 77.70% and 78.59%.
- Durable prevention is recorded in
  `research/workbench-boundary-root-cause.md`, the Workbench/live-session and
  live-command-scope specs, and the cross-layer checklist. No spec template
  tree exists in this repository, so there was no template synchronization
  target.
- No App or controller was started during this final pass. The populated
  Connections/Overview read-only AX completion and CPU-recovery acceptance item
  remains open and still requires explicit runtime permission.

## Phase 6. Spec, Commit, And User Acceptance

- [x] Run `trellis-check` against PRD/design, source, tests, localization, and performance evidence.
- [x] Use `trellis-update-spec` only for durable changes, including the conditional long-chain topology viewport rule; remove superseded wording rather than appending a contradiction.
- [x] Commit product/spec work in scoped local commits (`3662209`, `aa5bbe2`); do not push without a new user request.
- [x] Run the `trellis-finish-work` survey and defer archive/journal because AC1/AC11 still require user real-controller visual acceptance.
- [x] Prepare the real-controller light/dark page-by-page acceptance handoff; address only reproducible screenshot findings.
- [x] Commit the reopened accessibility fix, tests, verifier, task evidence, and durable spec correction (`ab240ae`).
- [ ] After user visual acceptance, run `trellis-finish-work` to archive the child and record its work commits in the journal.
- [ ] Mark parent Phase 5 complete only after user visual acceptance and final integrated validation.

### Reopened Dense Topology Visual Correction (2026-09-04)

- [x] Record the user-provided real-data screenshot and supersede the rejected
  true-Sankey area-fill decision in PRD/design.
- [x] Add bounded node/edge visual scales and dense-column layout that preserves
  every real node, edge, path, count, order rule, and interaction identity.
- [x] Replace closed filled bands with restrained weighted centerline strokes;
  add selection-aware label hierarchy without glass, glow, cards, or a parallel
  display mode.
- [x] Add scale/layout/rendering/source-verifier regressions and run focused
  topology/navigation/accessibility tests.
- [x] Capture and assess two comparable offline Release reports with matching
  fixtures/checksums/work units and record every repeated >10% movement.
- [x] Dispatch an independent `trellis-check`, synchronize the durable Workbench
  contract, and run the complete offline gate.
- [ ] Commit the accepted correction in a scoped local commit; do not push
  without a new user request.
- [ ] Obtain the user's light/dark real-controller visual acceptance before
  archiving this task or its `08-23` visual predecessor.

Implementation evidence:

- The layout now uses 20-to-30-point node rails, 1.5-to-7-point weighted
  centerlines, 12-point visible rails with the retained 28-point acquisition
  target, 8-point gaps, and 168-to-320-point column spacing. The requested flow
  height is `availableWidth * 0.36`, clamped to 480-to-680 points; dense columns
  may grow vertically to preserve every real node.
- Edge attachment centers use normalized cumulative real connection counts
  inside each bounded node. Existing barycenter ordering, complete topology
  admission, render bands, hit/index/keyboard/accessibility/hover/pin/Inspector
  behavior, and one opaque asynchronous Canvas remain intact. Closed ribbon
  fill is rejected by focused tests and the source verifier.
- Offline validation passed Debug Swift build, 31 focused Overview performance
  tests, 15 Connection topology tests, 28 timeline/proxy regression tests, the
  Workbench source verifier, localization JSON validation, `git diff --check`,
  and the complete suite: 109 XCTest tests plus 414 Swift Testing tests with
  zero failures. No Mica process was launched and no controller was contacted.
- Independent `trellis-check` removed one dead layout projection and strengthened
  the source verifier so its closed-ribbon rejection is scoped to `drawEdge`;
  focused and full tests passed after the correction.
- Comparable Release reports are
  `tmp/codex/performance/topology-route-final-{1,2}/mica-performance.json`.
  All 30 fixtures, checksums, and reported work units match the existing
  `workbench-final-{1,2}` baselines, and no topology case regressed by more than
  10% in both paired runs. The existing topology benchmark measures
  `ConnectionTopologyBuilder.build`, not layout or Canvas rendering; layout
  complexity remains guarded by focused 2,000-path operation-count,
  cancellation, and render-band tests. Three unrelated benchmark cases
  (rule search projection, Mihomo unchanged change-plan, and runtime connection
  frame) exceeded 10% in both noisy paired runs; no out-of-scope source was
  changed to tune those results.

## Final Planning Gate

- [x] Goal, in-scope/out-of-scope behavior, observable acceptance, risks, and dependencies are explicit.
- [x] Static evidence and file:line anchors are recorded in `research/cross-surface-audit.md`.
- [x] `implement.jsonl` and `check.jsonl` contain real curated context.
- [x] User explicitly approved this final planning summary with “开始”.
- [x] Approval received: run `task.py start` and dispatch implementation.
