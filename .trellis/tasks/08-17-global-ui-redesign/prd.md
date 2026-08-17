# 全局 UI 设计系统与界面重构

## Goal

Replace the current Workbench visual/interaction system with a new design
direction chosen deliberately by the user, and formally rewrite the frontend
UI contract (`.trellis/spec/frontend/`) so the new system becomes the
authoritative contract instead of an unrecorded exception.

User value: the application's look, layout, and interaction model match the
user's actual intent rather than the accumulated result of the previous two
UI rebuilds.

## Confirmed Facts

- Mica is a Swift 6.2 SwiftPM macOS 27 app controlling already-running remote
  controllers (Mihomo, Nikki, OpenClash, CMFA/Stash, sing-box, Surge).
- UI code lives in `Sources/Mica/Features/{Workbench,Routers,Settings,Dashboard}`
  (~52k lines of Swift in the app target). The Workbench directory is the main
  surface (~40 files listed in the current UI contract).
- The current design system is `MicaDesignTokens` / `MicaStyle` /
  `WorkbenchDesignSystem` + `WorkbenchVisualSystem` +
  `WorkbenchOverviewVisualSystem` (dark cyber-neon: signalCyan/signalViolet
  accents, layered depth, HUD panels).
- The UI was already rebuilt twice in active/recent tasks:
  - `08-04-workbench-native-ui-system` (in_progress, 9/9 subtasks done)
  - `08-16-dashboard-visual-hover-details` (completed: cyber-neon Overview,
    fixed telemetry/topology composition, node-anchored policy HUD)
- The 08-16 delivery and related work are **uncommitted**: ~84 modified files,
  5 deletions, 12 untracked paths (including `WorkbenchOverviewPolicyHUD.swift`,
  `WorkbenchOverviewPreferences.swift`, `WorkbenchOverviewVisualSystem.swift`,
  `WorkbenchOverviewWindowRuntime.swift` and their tests).
- The frontend spec set (`.trellis/spec/frontend/`, 9 docs, ~1.5k lines) makes
  `workbench-ui-contract.md` the authoritative UI contract; it explicitly
  states the controller/data layer is stable and no previous Workbench View /
  presenter / projector / store / file split is a compatibility requirement.
- Localization contract: visible copy in English + Simplified Chinese via
  `MicaStrings` / `Localizable.xcstrings`.

## Non-Negotiable Constraints (carried over, not re-negotiable)

- Mica never downloads/launches/manages a local core and never touches system
  networking, OpenWrt/LuCI, SSH, or `ubus`. Automated checks must not contact
  a controller.
- Controller-reported business data stays visible and selectable; exports stay
  free of credentials/tokens/subscription URLs/Keychain contents/raw bodies.
- Preserve controller order and optionality; actions gated by capabilities;
  validate controller ID + session generation after async work; one selected
  live controller, no automatic failover.
- No fabricated charts and no mock controller business data in production UI.
- Visible copy remains English + Simplified Chinese.
- The frontend design contract may be **rewritten as a task deliverable**
  (spec update is part of this task), not silently ignored.

## Key Decisions

- D1 (user, 2026-08-17): Full reset. The new UI is not bound by the current
  visual system, information architecture, page organization, window model,
  or interaction patterns. Existing UI code structure is not a compatibility
  anchor (the current UI contract already states this explicitly).
- D2 (user, 2026-08-17): Design direction is explicitly delegated to the
  agent ("自由发挥"). The chosen direction will be fixed in `design.md` and
  presented in the final planning summary; user approval of that summary is
  still required before implementation.
- D3: Scope is the whole application UI: Workbench destinations, Routers,
  Settings, window chrome, and the design system itself. Controller/data
  layer behavior is preserved (see Non-Negotiable Constraints).

## Requirements

- R1: Define and implement the new global design system (tokens, typography,
  color, surfaces, motion) replacing `MicaStyle`/`WorkbenchDesignSystem` and
  the cyber-neon Overview visual system.
- R2: Apply the new system across all app surfaces (Workbench destinations,
  Routers, Settings, window chrome) with a deliberately rethought information
  architecture and interaction model.
- R3: Rewrite `.trellis/spec/frontend/workbench-ui-contract.md` (and related
  component/state guidelines where affected) to describe the new system.
- R4: Preserve all existing controller-driven behavior, capability gating,
  and localization coverage; no functional regressions.

## Out Of Scope (draft)

- Controller/API layer changes (`Sources/MicaCore`) except where a UI change
  strictly requires it.
- New product features not required by the redesign.
- Lowering the Swift 6.2 / macOS 27 targets.

## Risks

- ~100 uncommitted files from the 08-16/08-04 work sit in the working tree.
  Recommendation: commit or otherwise checkpoint that work before the refactor
  starts, so the redesign diff is reviewable and rollback is clean.
- A second full rewrite immediately after two UI rebuilds risks churn without
  a clear direction; the direction decision below gates all planning.

## Open Questions (blocking)

- Q2: What should happen to the ~100 uncommitted files from the previous two
  UI rebuilds before this refactor starts? Options: commit as checkpoint
  (recommended), selectively discard UI-only files, or rewrite on top without
  committing.
