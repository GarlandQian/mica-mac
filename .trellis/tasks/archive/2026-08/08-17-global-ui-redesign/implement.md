# Implement — 全局 UI 设计系统与界面重构

Validation commands (from docs/DEVELOPMENT.md):

```bash
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
```

Global rules: build green at the end of every step; no controller contact in
any check; visible copy lands in `Localizable.xcstrings` (EN + zh-Hans) in
the same step that introduces it; scratch output stays under `tmp/codex/`.

Rollback points: full rollback = `git revert` to checkpoint `ebae3be`.
Per-step rollback = discard the step's diff (each step ends compile-green).

## Phase 0 — Baseline verification

- [x] 0.1 `git status --short` clean at checkpoint `ebae3be`. (planning artifacts
      committed as `f9480d6`; tree clean)
- [x] 0.2 Run build + full test suite; record results as the green baseline.
      If anything fails here, fix or explicitly accept before touching UI.
      Baseline: build 213.66s green; 305 tests / 27 suites all passed.

## Phase 1 — New design system (additive, old system untouched)

- [x] 1.1 Create `Sources/Mica/Design/MicaTheme.swift`: color tokens
      (dynamic light/dark helper), typography scale, spacing/shape/motion
      tokens per design.md §2. (257 lines; sub-agent d7b6af9d)
- [x] 1.2 Create `Sources/Mica/Design/MicaThemeComponents.swift`: shared
      primitives (panel, hairline separator, mono metric, status dot/badge,
      section header, empty state) used by all later steps. (214 lines)
- [x] 1.3 Build green. (Old system still referenced everywhere at this point.)
      Note: `Font.monospacedSystem` does not exist on this SDK; SF Mono is
      delivered via `Font.system(design: .monospaced)` (same face).

## Phase 2 — Chrome + inspector

- [x] 2.1 Rebuild sidebar with three groups (Operate / Observe / Manage) in
      `WorkbenchChrome.swift` / sidebar files; preserve ⌘1…⌘0 shortcuts and
      destination routing. (sub-agent aa7b99e2; operateCases/observeCases/
      manageCases; sidebar order = group order; ⌘1-⌘6 mapping unchanged)
- [x] 2.2 Restyle toolbar + status bar to Mica Ops tokens.
- [x] 2.3 Introduce the right-side inspector container in the workbench
      workspace; wire selection state from the workspace store.
      (`WorkbenchInspectorSelection` typed model; toolbar toggle; MicaEmptyState)
- [x] 2.4 Build green; EN+zh-Hans strings for new group titles and inspector
      chrome. (build 12.8s green; source verifier green; 49 affected tests
      green: Navigation/OperationOutcome/Preferences/ManagementProjection)

## Phase 3 — Overview

- [x] 3.1 Rewrite `WorkbenchOverviewTopologyView.swift` rendering (flat
      strokes, accent active path, status-colored nodes) on the retained
      geometry engine. (sub-agent 69323441; bands/hit-test/pause/a11y preserved;
      energy/glow removed)
- [x] 3.2 Rebuild the instrument/telemetry strip as mono-metric tiles.
      (fallback sub-agent af4e52f9: flat MicaPanel instruments, SF Mono
      readouts, charts + interactions preserved; gates green incl. verifier)
      Residual carried to 3B: dashboard optional-module interiors still on
      MicaStyle (OverviewSymbolMark/OverviewFlatSection/OverviewFormat.latencyTint).
- [x] 3.3 Remove `WorkbenchOverviewPolicyHUD.swift`; policy-group selection
      opens the inspector with the complete field composition (same data the
      HUD showed; hover reverts to tooltip). (sub-agent: projection moved to
      `WorkbenchOverviewPolicyInspection.swift` as `OverviewPolicyInspectionProjection`
      + `WorkbenchPolicyInspectorView`; placement/anchoring chrome deleted;
      `.proxyGroup`/`.proxyNode` selection reused; gates green)
- [x] 3.4 Restyle `WorkbenchOverviewPreferences.swift` UI to the new panels;
      keep the v1 storage schema unchanged. (Preferences UI lives in
      `WorkbenchOverviewEditor.swift`: bar now on MicaTheme.canvas +
      MicaHairlineSeparator + micaThemeFont roles; store/schema/keys
      byte-identical, zero new copy. 3.2 residual also closed: dashboard
      optional-module interiors off MicaStyle — OverviewSymbolMark/
      OverviewFlatSection flattened (surface plate + hairline, monochrome
      symbol, default tint textSecondary), cyan data tints -> textSecondary,
      latencyTint -> statusOK/Warning/Error/textTertiary, same thresholds.)
- [x] 3.5 Delete `WorkbenchOverviewVisualSystem.swift`. (File removed;
      verifier expected-files/read/assertions cleaned; removed-type tests
      dropped per AC6; zero-hit rg gate passes. Verifier chrome-separator
      count moved to MicaHairlineSeparator; flat-section assertions updated
      to micaThemeFont(.title3) + textSecondary default tint.)
- [x] 3.6 Build + tests green (update `WorkbenchOverview*Tests` only where
      they assert removed UI types). (build 21.63s green; WorkbenchOverview
      23/23; WorkbenchNavigation 12/12; verify-real-controller-source green)

## Phase 4 — Operate data surfaces

- [x] 4.1 Proxies: dense node grid/list, mono latency badges, inspector
      detail; capability gates untouched. (4A sub-agent 03d5b107: ProxyGroupPanels
      fully converted, inline shelf removed → selectInspector(.proxyNode); 4B
      sub-agent 20e58ab4: all 19 WorkbenchVisualSystem primitives relocated
      restyled into MicaThemeComponents.swift with byte-compatible APIs, old file
      deleted, Proxies page converted; build/verifier/17-proxy+12-nav tests green)
- [x] 4.2 Connections: table-style rows + filter bar restyle. (MAIN SESSION
      inline — subagent provider down (kimi-k3 model_not_found x2). 4 files fully
      converted (ConnectionsView/ConnectionDetails/ConnectionPulseView/DataShared);
      page-level `.inspector` removed; `.connection` case live in the workspace
      container via store-registered live row resolver; two-way selection sync;
      verifier page-fill assertion re-pointed to MicaTheme.canvas; build/verifier/
      60 tests green: DataProjection/ConnectionMutationSafety/Navigation/Preferences)
- [x] 4.3 Rules: table-style rows + detail via inspector. (sub-agent 4856c912
      landed Rules.swift wiring + selectInspector sync before the 30-min cap
      killed it; MAIN SESSION completed: RuleDetails.swift + Rules.swift zero-ref
      conversion, store ruleRowResolver, container .rule case with full mutation
      inputs (canMutate/updatingRuleID/ruleUpdateFailures/setRuleDisabled binding),
- [x] 4.4 Build green. (build 6.63s; verifier green; 49 tests DataProjection+
      Navigation + perf benchmark green)

## Phase 5 — Observe surfaces

- [x] 5.1 Logs restyle (severity = status colors only). (sub-agent f38ca7a8:
      WorkbenchLogs.swift zero old refs; WorkbenchInspectorSelection gained
      .log(id:); store logEntryResolver; page-level .inspector removed; container
      .log case live; build 7.63s/verifier/49 tests green)
- [x] 5.2 Sources restyle. (sub-agent e2cf447e: Sources + SourceDetails zero old
      refs; enum case relabeled `source(name:)` → `source(id:)`; store
      `sourceRowResolver`; page-level `.inspector` removed; container `.source`
      case live with two-way selection sync; build 8.43s/verifier/49 tests green)
- [x] 5.3 Diagnostics restyle. (sub-agent 6d586061: DiagnosticsComponents 97 refs
      converted; MicaTheme.Metrics gained compactPagePadding/regularPagePadding/
      wideThreshold/pagePadding(for:) additively; Diagnostics.swift + Presentation
      verified already clean; build 5.62s/verifier/49 tests green)
- [x] 5.4 Build green. (5A/5B/5C each ended compile-green; Phase 5 gates all pass)

## Phase 6 — Manage surfaces

- [x] 6.1 Controllers list + inspector detail restyle. (MAIN SESSION inline —
      6A sub-agent 325bb64b died on kimi-k3 model_not_found before any edit.
      Management 36 + Controllers 55 refs zero; controller detail (identity,
      capability-gated actions, connection fields, test report, inline delete
      confirmation) moved into new WorkbenchControllerInspector hosted by the
      workspace container .controller case (resolves profile live from
      appModel.routers, empty state when deleted); split-view detail removed,
      list is now full-width with two-way selection sync; page pendingDelete/
      connectionTests state moved into the inspector; WorkbenchControllerStatusView
      shared by row + inspector; MicaTheme.Metrics gained statusBarHeight/
      inspectorMin/Ideal/Max/formLabelWidth/formControlMax; WorkspaceView iconControlSize
      + Chrome inspector-width residuals cleared; verifier re-pointed (controllerDetail
      section → inspector struct, HSplitView/VSplitView → inspector routing asserts,
      actions-section end marker → lastSuccess); build 19.07s+9.52s green, verifier
      green, 44 tests in 4 suites green)
- [x] 6.2 Configuration form restyle. (MAIN SESSION inline with 6B: 8 refs zero;
      formControlMax/iconControlSize → MicaTheme.Metrics, fonts → micaThemeFont,
      signalRed → statusError)
- [x] 6.3 Actions grouped list restyle; confirmations and capability gates
      unchanged. (MAIN SESSION inline: Actions 60 + Tailscale 32 refs zero;
      status tints checking→textSecondary/recovery+partial→statusWarning/
      ready→statusOK preserved as projection semantics; build 5.08s green,
      verifier green, 43 tests in 6 suites green)
- [x] 6.4 Build green. (6A/6B each ended compile-green; verifier + tests pass)

## Phase 7 — Routers, Settings, old-system deletion

- [x] 7.1 Theme `Sources/Mica/Features/Routers/**` (tokens, typography,
      panels); no functional change. (MAIN SESSION inline: 5 files / 42 refs zero;
      signal* → status/textSecondary semantics)
- [x] 7.2 Theme Settings scene (native grouped Form). (WorkbenchSettings.swift
      16 refs zero; MicaSettingsSceneView native Form on MicaTheme.canvas)
- [x] 7.3 Delete `WorkbenchDesignSystem.swift`, `WorkbenchVisualSystem.swift`,
      and remove every remaining `MicaStyle` / `MicaDesignTokens` reference.
      Gate: `rg -n "MicaStyle|MicaDesignTokens|WorkbenchVisualSystem" Sources/`
      returns zero hits. (MAIN SESSION inline: all residuals cleared — Dashboard 41,
      TopologyView 24, PolicyInspection 13, ControllerSelector 23, StatusBar 4,
      Window 3, MicaApp 3, AppPreferenceEnvironment 1; MicaTheme.Metrics gained
      sidebar*/inspector*/formLabelWidth/formControlMax/statusBarHeight;
      MicaTextStyle relocated as WorkbenchDataText input type into DataShared;
      WorkbenchMotion.expand → MicaTheme.Motion.reveal; DesignSystem file deleted;
      doc-comment provenance scrubbed; verifier designSystem block rewritten to
      Mica Ops tokens/TextRole/Motion + re-pointed 4 stale assertions; 4 test refs
      updated to MicaTheme.Metrics per AC6; AC1 gate + broader sweep both zero)
- [x] 7.4 Build + full test suite green. (build 17.38s; 304 tests / 27 suites
      pass — baseline 305 minus the 3.5 removed-type test per AC6)

## Phase 8 — Polish, spec rewrite, final gate

- [x] 8.1 Accessibility pass: Reduce Motion static, VoiceOver labels,
      keyboard navigation, contrast spot-check per design.md §2. (MAIN SESSION:
      all `.animation(`/`withAnimation` sites gated on reduceMotion — one ungated
      numeric transition in MicaThemeComponents fixed; a11y label count 82 ≥
      baseline 77; ⌘1-⌘0 order asserted by tests; text uses system label ramps
      (≥4.5:1), accent reserved for selection/live per token rules)
- [x] 8.2 Localization audit: every new/changed key has EN + zh-Hans values.
      (MAIN SESSION: Localizable.xcstrings 2093 keys, zero missing en/zh-Hans —
      programmatic audit)
- [x] 8.3 Rewrite `.trellis/spec/frontend/workbench-ui-contract.md` and
      update `component-guidelines.md` / `directory-structure.md` /
      `state-management.md` where the new system changes them; update
      `docs/UI_GUIDELINES.md` to match. (sub-agent 3716308b: 6 docs rewritten —
      contract File Architecture verified against `ls` (zero stale/missing),
      Navigation And Chrome = 3-group sidebar + single inspector mechanism,
      Visual System = Mica Ops tokens, Scenario/Data-And-Ordering sections
      preserved verbatim; docs/ARCHITECTURE also synced; AC5 stale-concept gate
      zero hits; build + verifier green)
- [x] 8.4 Full verification: build + full test suite. (MAIN SESSION: AC1 rg gate
      zero hits; AC3 PolicyHUD deleted + 7 inspector cases routed; build 6.59s;
      304 tests / 27 suites all pass; verifier green; AC2 via WorkbenchNavigation
      tests; AC4/AC7 audited in 8.1/8.2; AC5 spec-vs-tree verified)
- [x] 8.5 Final review against prd.md acceptance criteria (trellis-check),
      then Phase 3.3/3.4 (spec update + commit). (trellis-check a1b578cb:
      AC1–AC7 all PASS with independently re-run gates — build 11.95s, 304/27
      tests, verifier, AC1/AC5 rg zero-hit, xcstrings 2093-key audit; product
      red lines verified: MicaCore/AppModel zero diff, Routers zero logic diff,
      capability/session-generation/credential-export assertions retained;
      commit readiness APPROVED, no blockers/should-fix; nits resolved where
      actionable: onCloseInspector dead plumbing removed (property + call site +
      closeMemberInspector), closingInspector projection retained (pure, tested);
      stale sidebar.group_* keys kept — referenced by AppRuntimeSmokeProbe)

## Risky files / notes

- `WorkbenchOverviewTopologyView.swift` (rendering rewrite on retained
  engine) and `WorkbenchOverviewPolicyHUD.swift` (removal; inspector must
  show the same complete field set) are the highest-risk changes.
- `Sources/Mica/App/AppModel*.swift` should not change except where a
  selection/inspector binding strictly requires it; treat any such change as
  a review flag.
- No persistence-format change is planned; if one becomes necessary, stop
  and record it here before landing it.
