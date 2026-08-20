# 全局 UI 设计系统与界面重构 (Mica Ops)

## Goal

Replace the entire application UI — design system, window chrome, information
architecture, and every surface — with the new **Mica Ops** direction: a
precision operations console — neutral near-black/light canvas, single
signal-teal accent, monospaced live data, flat hairline-separated panels,
inspector-based detail reveal, no glow/HUD/idle motion — and rewrite the
frontend UI contract so the new system becomes the authoritative spec.

User value: the application's look, layout, and interaction model are the
result of one deliberate design decision instead of the accumulated output of
the previous two UI rebuilds.

## Background And Confirmed Facts

- Mica is a Swift 6.2 SwiftPM macOS 27 app controlling already-running remote
  controllers (Mihomo, Nikki, OpenClash, CMFA/Stash, sing-box, Surge). Swift
  6.2 / macOS 27 targets are not lowered.
- UI code: `Sources/Mica/Features/{Workbench,Routers,Settings,Dashboard}`
  (~52k Swift lines in the app target). The Workbench has 10 destinations
  (`WorkbenchChrome.swift:6` — overview, proxies, connections, logs, rules,
  sources, controllers, configuration, actions, diagnostics) in 2 groups.
- The UI was rebuilt twice already: `08-04-workbench-native-ui-system`
  (in_progress, 9/9 done) and `08-16-dashboard-visual-hover-details`
  (completed: cyber-neon Overview, policy HUD). That work is now committed as
  the pre-redesign baseline checkpoint `ebae3be` (122 files), giving this
  task a clean, reviewable starting point and full rollback capability.
- Current design system to be replaced: `MicaDesignTokens` / `MicaStyle` /
  `WorkbenchDesignSystem.swift` / `WorkbenchVisualSystem.swift` /
  `WorkbenchOverviewVisualSystem.swift` (dark cyber-neon, cyan/violet).
- The current UI contract (`.trellis/spec/frontend/workbench-ui-contract.md`)
  explicitly states the controller/data layer is stable and no previous
  Workbench View/presenter/store/file split is a compatibility requirement —
  so a full UI rewrite is contract-legal.
- Retained engineering assets: topology geometry/cache/hit-testing engine
  (`WorkbenchOverviewTopology.swift`), telemetry projections, Overview
  preferences model (`WorkbenchOverviewPreferences.swift`, v1 storage schema
  unchanged), all of `Sources/MicaCore`, AppModel/live-session logic, and the
  localization infrastructure (`MicaStrings` + `Localizable.xcstrings`).
- Verification commands (docs/DEVELOPMENT.md):
  `swift build --scratch-path tmp/codex/swift-build` and
  `swift test --scratch-path tmp/codex/swift-build`.

## Key Decisions

- D1 (user): Full reset — the new UI is not bound by the current visual
  system, information architecture, page organization, window model, or
  interaction patterns.
- D2 (user): Design direction explicitly delegated to the agent ("自由发挥"),
  fixed in `design.md` as **Mica Ops**; this summary is the approval gate.
- D3 (user): Scope is the whole application UI — Workbench destinations,
  Routers, Settings, window chrome, and the design system itself.
- D4 (user): The ~100 uncommitted files from the previous rebuilds were
  committed first as checkpoint `ebae3be` before any redesign work.
- D5 (agent design): IA regrouped into Operate (Overview, Proxies,
  Connections, Rules) / Observe (Logs, Sources, Diagnostics) / Manage
  (Controllers, Configuration, Actions); ⌘1…⌘0 shortcuts preserved.
- D6 (agent design): A right-side inspector is the single detail-reveal
  mechanism; the floating policy HUD
  (`WorkbenchOverviewPolicyHUD.swift`) is removed, showing the same complete
  controller-reported field set in the inspector.
- D7 (agent design): The topology geometry engine and overview preferences
  model are retained; only rendering/presentation layers are rewritten.

## Non-Negotiable Constraints

- Mica never downloads/launches/manages a local core and never touches system
  networking, OpenWrt/LuCI, SSH, or `ubus`. Automated checks must not contact
  a controller or invoke remote actions.
- Controller-reported business data stays visible and selectable; exports
  stay free of credentials/tokens/subscription URLs/Keychain contents/raw
  response or stream bodies. No fabricated charts; no mock controller
  business data in production UI.
- Preserve controller order and optionality; actions gated by capabilities;
  validate controller ID + session generation after async work; one selected
  live controller; no automatic failover.
- Visible copy in English + Simplified Chinese.
- The frontend design contract is rewritten as a task deliverable (R3), not
  silently ignored.

## Requirements And Acceptance Criteria

- **R1 — New design system**: one consolidated `MicaTheme`
  (`Sources/Mica/Design/`) implementing the tokens in design.md §2.
  - AC1: zero remaining references to `MicaStyle`, `MicaDesignTokens`,
    `WorkbenchDesignSystem`, `WorkbenchVisualSystem`,
    `WorkbenchOverviewVisualSystem` in `Sources/` (rg gate in implement.md
    7.3).
- **R2 — Whole-app application**: chrome (3-group sidebar, toolbar, status
  bar, inspector), all 10 Workbench destinations, Routers, and Settings
  rebuilt on the new system with the rethought IA and interaction model.
  - AC2: all 10 destinations reachable from the new three-group sidebar with
    previous keyboard shortcuts working.
  - AC3: proxy-group/connection/rule/source/controller details render in the
    inspector; `WorkbenchOverviewPolicyHUD.swift` no longer exists and no
    floating HUD remains.
  - AC4: text contrast ≥ 4.5:1 (primary) per token rules; Reduce Motion
    renders all surfaces static; VoiceOver labels preserved.
- **R3 — Spec rewrite**: `workbench-ui-contract.md` rewritten and
  `component-guidelines.md` / `directory-structure.md` /
  `state-management.md` / `docs/UI_GUIDELINES.md` updated to match the
  shipped code.
  - AC5: spec descriptions match the final file layout and design system;
    no stale references to the neon system or HUD.
- **R4 — Behavior preservation**: controller-driven behavior, capability
  gating, session validation, ordering/optionality, and localization coverage
  unchanged.
  - AC6: `swift build` and the full `swift test` suite pass; existing tests
    unchanged except where they assert removed UI types.
  - AC7: every new/changed visible string has EN + zh-Hans values in
    `Localizable.xcstrings`.

## Out Of Scope

- `Sources/MicaCore` API/persistence changes (except where a UI binding
  strictly requires it, flagged for review).
- New product features not required by the redesign.
- Overview preferences storage-schema migration (v1 schema kept).
- Lowering Swift 6.2 / macOS 27 targets; adding Swift packages.

## Risks And Deferred Items

- Highest-risk changes: topology rendering rewrite on the retained engine,
  and HUD removal (inspector must carry the identical complete field set).
- Full-rewrite breadth (~40 Workbench files + Routers + Settings) is
  mitigated by per-phase compile-green steps and checkpoint rollback to
  `ebae3be`.
- Deferred: any runtime visual smoke requires explicit user/task permission
  per project rules; otherwise verification is build + tests + code review.
