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

- [ ] 0.1 `git status --short` clean at checkpoint `ebae3be`.
- [ ] 0.2 Run build + full test suite; record results as the green baseline.
      If anything fails here, fix or explicitly accept before touching UI.

## Phase 1 — New design system (additive, old system untouched)

- [ ] 1.1 Create `Sources/Mica/Design/MicaTheme.swift`: color tokens
      (dynamic light/dark helper), typography scale, spacing/shape/motion
      tokens per design.md §2.
- [ ] 1.2 Create `Sources/Mica/Design/MicaThemeComponents.swift`: shared
      primitives (panel, hairline separator, mono metric, status dot/badge,
      section header, empty state) used by all later steps.
- [ ] 1.3 Build green. (Old system still referenced everywhere at this point.)

## Phase 2 — Chrome + inspector

- [ ] 2.1 Rebuild sidebar with three groups (Operate / Observe / Manage) in
      `WorkbenchChrome.swift` / sidebar files; preserve ⌘1…⌘0 shortcuts and
      destination routing.
- [ ] 2.2 Restyle toolbar + status bar to Mica Ops tokens.
- [ ] 2.3 Introduce the right-side inspector container in the workbench
      workspace; wire selection state from the workspace store.
- [ ] 2.4 Build green; EN+zh-Hans strings for new group titles and inspector
      chrome.

## Phase 3 — Overview

- [ ] 3.1 Rewrite `WorkbenchOverviewTopologyView.swift` rendering (flat
      strokes, accent active path, status-colored nodes) on the retained
      geometry engine.
- [ ] 3.2 Rebuild the instrument/telemetry strip as mono-metric tiles.
- [ ] 3.3 Remove `WorkbenchOverviewPolicyHUD.swift`; policy-group selection
      opens the inspector with the complete field composition (same data the
      HUD showed; hover reverts to tooltip).
- [ ] 3.4 Restyle `WorkbenchOverviewPreferences.swift` UI to the new panels;
      keep the v1 storage schema unchanged.
- [ ] 3.5 Delete `WorkbenchOverviewVisualSystem.swift`.
- [ ] 3.6 Build + tests green (update `WorkbenchOverview*Tests` only where
      they assert removed UI types).

## Phase 4 — Operate data surfaces

- [ ] 4.1 Proxies: dense node grid/list, mono latency badges, inspector
      detail; capability gates untouched.
- [ ] 4.2 Connections: table-style rows + filter bar restyle.
- [ ] 4.3 Rules: table-style rows + detail via inspector.
- [ ] 4.4 Build green.

## Phase 5 — Observe surfaces

- [ ] 5.1 Logs restyle (severity = status colors only).
- [ ] 5.2 Sources restyle.
- [ ] 5.3 Diagnostics restyle.
- [ ] 5.4 Build green.

## Phase 6 — Manage surfaces

- [ ] 6.1 Controllers list + inspector detail restyle.
- [ ] 6.2 Configuration form restyle.
- [ ] 6.3 Actions grouped list restyle; confirmations and capability gates
      unchanged.
- [ ] 6.4 Build green.

## Phase 7 — Routers, Settings, old-system deletion

- [ ] 7.1 Theme `Sources/Mica/Features/Routers/**` (tokens, typography,
      panels); no functional change.
- [ ] 7.2 Theme Settings scene (native grouped Form).
- [ ] 7.3 Delete `WorkbenchDesignSystem.swift`, `WorkbenchVisualSystem.swift`,
      and remove every remaining `MicaStyle` / `MicaDesignTokens` reference.
      Gate: `rg -n "MicaStyle|MicaDesignTokens|WorkbenchVisualSystem" Sources/`
      returns zero hits.
- [ ] 7.4 Build + full test suite green.

## Phase 8 — Polish, spec rewrite, final gate

- [ ] 8.1 Accessibility pass: Reduce Motion static, VoiceOver labels,
      keyboard navigation, contrast spot-check per design.md §2.
- [ ] 8.2 Localization audit: every new/changed key has EN + zh-Hans values.
- [ ] 8.3 Rewrite `.trellis/spec/frontend/workbench-ui-contract.md` and
      update `component-guidelines.md` / `directory-structure.md` /
      `state-management.md` where the new system changes them; update
      `docs/UI_GUIDELINES.md` to match.
- [ ] 8.4 Full verification: build + full test suite.
- [ ] 8.5 Final review against prd.md acceptance criteria (trellis-check),
      then Phase 3.3/3.4 (spec update + commit).

## Risky files / notes

- `WorkbenchOverviewTopologyView.swift` (rendering rewrite on retained
  engine) and `WorkbenchOverviewPolicyHUD.swift` (removal; inspector must
  show the same complete field set) are the highest-risk changes.
- `Sources/Mica/App/AppModel*.swift` should not change except where a
  selection/inspector binding strictly requires it; treat any such change as
  a review flag.
- No persistence-format change is planned; if one becomes necessary, stop
  and record it here before landing it.
