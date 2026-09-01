# Implement: Workbench Cross-Surface UX Acceptance

## Execution Rules

- Active task: `.trellis/tasks/09-01-workbench-cross-surface-acceptance`.
- Main session dispatches `trellis-implement`, then `trellis-check`; sub-agents read curated JSONL context before task artifacts.
- Preserve unrelated work and current source order/optionality. Use `tmp/codex/` for all scratch/build/benchmark output.
- Do not launch Mica, connect to a controller, run runtime smoke, or invoke remote actions without new explicit permission.
- Do not add dependencies, compatibility layers, content glass, fabricated data, or a new visual system.

## Phase 0. Dependency And Baseline

- [x] Resolve `08-23-overview-flow-ribbons` user light/dark visual acceptance or explicitly record that only its already-approved interaction follow-up is being inherited.
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

## Phase 6. Spec, Commit, And User Acceptance

- [x] Run `trellis-check` against PRD/design, source, tests, localization, and performance evidence.
- [x] Use `trellis-update-spec` only for durable changes, including the conditional long-chain topology viewport rule; remove superseded wording rather than appending a contradiction.
- [ ] Commit product/spec work in scoped commits, then run `trellis-finish-work` for task archival and journal updates.
- [ ] Ask the user to run real-controller light/dark page-by-page acceptance; address only reproducible screenshot findings.
- [ ] Mark parent Phase 5 complete only after user visual acceptance and final integrated validation.

## Final Planning Gate

- [x] Goal, in-scope/out-of-scope behavior, observable acceptance, risks, and dependencies are explicit.
- [x] Static evidence and file:line anchors are recorded in `research/cross-surface-audit.md`.
- [x] `implement.jsonl` and `check.jsonl` contain real curated context.
- [x] User explicitly approved this final planning summary with “开始”.
- [x] Approval received: run `task.py start` and dispatch implementation.
