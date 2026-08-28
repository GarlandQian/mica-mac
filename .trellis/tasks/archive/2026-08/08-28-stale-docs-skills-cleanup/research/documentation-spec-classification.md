# Research: Documentation And Specification Cleanup Classification

- Query: Classify current README, maintained docs, Trellis specs, and directly related project guidance as delete, rewrite, or keep using current Mica source as authority.
- Scope: internal
- Date: 2026-08-28

## Findings

### Authority And Current Facts

The classification uses the repository authority order from `AGENTS.md:5-8`:
source, tests, and `Package.swift` first; active Trellis contracts next; maintained
docs last.

Current facts that disprove stale text:

- `Package.swift:1-19` declares Swift 6.2, macOS 27, and only the four direct
  gRPC/protobuf packages.
- `Sources/Mica/Features/Workbench/WorkbenchChrome.swift:6-16` defines ten
  Workbench destinations: Overview, Proxies, Connections, Logs, Rules, Sources,
  Controllers, Configuration, Actions, and Diagnostics. The sidebar grouping is
  fixed at `WorkbenchChrome.swift:42-57`; Settings is not a destination.
  `Tests/MicaTests/WorkbenchNavigationTests.swift:9-41` locks this behavior.
- `Sources/MicaCore/Models/RouterProfile.swift:58-67` exposes Mihomo, Nikki,
  OpenClash, Surge, sing-box, CMFA, Stash, and the legacy Stash/CMFA hint.
  `Sources/MicaCore/API/UnifiedControllerAdapters.swift:243-260` installs real
  Mihomo-family, Surge, and sing-box adapters while leaving only Smart Probe and
  the unresolved legacy Stash/CMFA hint unavailable.
- `Sources/MicaCore/API/SingBoxGRPCClient.swift:64-83` implements StartedService
  status, policy, connection, log, and Tailscale operations.
  `Sources/Mica/Features/Workbench/WorkbenchConfiguration.swift:96-112` places
  Tailscale in Configuration when real readiness/data exists; it is not a
  top-level navigation destination.
- `Sources/Mica/Design/MicaTheme.swift:6-38` defines the current Mica Ops system
  and signal-teal accent. The removed Rose Pine / `MicaStyle` system is not a
  current source boundary.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift:732-745`
  fixes a 168-point minimum column step, 20-point node width, and 8-point gap.
  The first column uses name order and later columns use upstream flow-weighted
  barycenters at `WorkbenchOverviewTopology.swift:849-887`.
  `WorkbenchOverviewTopologyView.swift:425-451` adds horizontal scrolling only
  when a long chain exceeds the panel. The active contract states the same at
  `.trellis/spec/frontend/workbench-ui-contract.md:407-451`.
- `AGENTS.md:17` permits runtime smoke only when the user or task explicitly
  authorizes it. Static source verification remains part of the ordinary gate.

### Delete

Delete exactly these eight files. Their complete substantive bodies are
placeholder prompts rather than Mica contracts:

| Path | Evidence |
|---|---|
| `.trellis/spec/backend/database-guidelines.md` | Every section says `To be filled` (`:19,27,35,43,51`) and assumes an ORM/database absent from `Package.swift` and the current JSON/file persistence architecture. |
| `.trellis/spec/backend/directory-structure.md` | Contains a generic `src/...` placeholder (`:19-30`) rather than the SwiftPM layout. |
| `.trellis/spec/backend/error-handling.md` | Every section is empty (`:19,27,35,43,51`); the real transport/error contract is already in `controller-data-contract.md`. |
| `.trellis/spec/backend/quality-guidelines.md` | Every section is empty (`:19,27,35,43,51`). |
| `.trellis/spec/backend/logging-guidelines.md` | Every section is empty (`:19,27,35,43,51`). |
| `.trellis/spec/frontend/hook-guidelines.md` | Empty template (`:19,27,35,43,51`) that asks about React Query/SWR at `:31-35`; Mica is SwiftUI. |
| `.trellis/spec/frontend/quality-guidelines.md` | Every section is empty (`:19,27,35,43,51`). |
| `.trellis/spec/frontend/type-safety.md` | Empty template (`:19,27,35,43,51`) that asks about Zod/Yup/io-ts at `:31-35`; Mica is Swift 6.2. |

### Rewrite In Place

These paths are still useful or required, but contain demonstrably stale
statements. Rewrite only the contradicted material.

| Path | Evidence and exact replacement intent |
|---|---|
| `README.md` | Replace the old destination list at `:7-18` with the ten current sidebar destinations and state that native Settings is separate. Remove the external/old IA wording at `:20`. Replace the incomplete controller claims at `:29-34` with the implemented Mihomo/Nikki/OpenClash, CMFA, Stash, Surge, and sing-box boundaries; describe Tailscale as a capability/readiness-gated Configuration section. Replace Rose Pine at `:43` with Mica Ops. Keep static default checks together, but move the executable runtime smoke command at `:65` into an explicitly authorized opt-in block consistent with `AGENTS.md:17`. |
| `docs/README.md` | Replace `Rose Pine-inspired tokens` at `:10` with the exact Mica Ops design system terminology used by `MicaTheme.swift`. |
| `docs/DEVELOPMENT.md` | Strengthen `:18` from merely optional/no-smoke wording to explicit user-or-task authorization. Replace `:50-56` with a three-platform summary: Codex uses `UserPromptSubmit` and `SubagentStart`; Claude Code registers `SessionStart`, prompt, and subagent hooks; Pi loads `.pi/extensions/trellis/index.ts`, whose lifecycle handlers include `session_start` and `before_agent_start`. Keep runtime execution outside the default command block. |
| `docs/UI_GUIDELINES.md` | Rewrite the topology sentence at `:153`: first column sorts by reported name; later columns use flow-weighted barycenters with name tiebreaks; true filled ribbons use real flow width; there is no nested vertical scroll, while chains below the 168-point column-step threshold widen into a horizontal viewport. Keep the existing interaction and accessibility requirements. |
| `.trellis/spec/backend/index.md` | Remove the five `To fill` links at `:17-21` and the fill-template instructions at `:26-35`. Make this a concise MicaCore/controller index pointing to the active controller data contract. |
| `.trellis/spec/frontend/index.md` | Remove the three deleted placeholder links and all `To fill` statuses at `:17-24`. List `directory-structure.md`, `component-guidelines.md`, `state-management.md`, `live-session-controller-contract.md`, and `workbench-ui-contract.md` as active Mica-specific contracts. |
| `.trellis/spec/guides/index.md` | Preserve the path because `.trellis/workflow.md:32` and `.agents/skills/trellis-start/SKILL.md:35` load it. Replace generic API/service/database/component triggers (`:31-39`), the unverified AI false-positive estimate (`:54-66`), and `grep` example (`:70-79`) with concise Mica triggers and `rg`. |
| `.trellis/spec/guides/code-reuse-thinking-guide.md` | Preserve the stable path but replace JavaScript payload/reducer examples (`:61-83,108-132`), Python platform dispatch (`:147-174`), and Trellis CLI template mechanics (`:178-223`). The replacement should tell agents to search current Mica owners first and reuse typed controller adapters, generation-owned AppModel operations, projections/caches, Workbench primitives, formatters, and localization without erasing backend semantics. |
| `.trellis/spec/guides/cross-layer-thinking-guide.md` | Preserve the stable path but replace generic database/TypeScript examples (`:11-16,35-43,74-101`) and all Trellis product-repository/versioned-doc/registry sections (`:148-310`), including duplicated `:148-181` / `:245-277` content. The replacement should trace wire DTO -> adapter -> generation-owned session/runtime -> presentation projection/cache -> SwiftUI, with capability, order, optionality, cancellation, revision, localization, and offline-test checkpoints. |
| `AGENTS.md` | Replace removed `MicaStyle` at `:15` with `MicaTheme` and existing Workbench primitives. `scripts/verify-real-controller-source.mjs:406-417` explicitly requires `Sources/Mica/App/MicaStyle.swift` to remain deleted. |
| `.agents/skills/mica-controller-development/references/project-constraints.md` | Replace `Rose Pine-inspired tokens` / `MicaStyle` at `:85-87` with the Mica Ops tokens defined by `MicaTheme` and the active Workbench UI contract. This is a project-skill wording correction, not deletion of a skill or platform copy. |

### Keep

Keep these maintained documents unchanged; this audit found no source-backed
conflict:

| Path | Reason |
|---|---|
| `docs/ARCHITECTURE.md` | Its ten-destination/native-Settings model (`:13-21`), data flow (`:23-45`), fixed Overview preferences (`:47-51`), and removed compatibility list (`:53-55`) match current source and the active UI/session contracts. |
| `docs/CONTROLLER_COMPATIBILITY.md` | The Mihomo/CMFA/Stash, Surge, sing-box/Tailscale, Auto Detect, and safety boundaries at `:3-23` match current adapters and protocol methods. |
| `docs/DATA_MODEL.md` | Ordering/optionality at `:3-19` and the current object/capability inventory at `:21-34` match `controller-data-contract.md:22-70` and current presentation models. |
| `.trellis/spec/backend/controller-data-contract.md` | Active, Mica-specific controller truth, capability, cancellation, and validation contract with current required tests (`:22-101`). |
| `.trellis/spec/frontend/component-guidelines.md` | Current Mica Ops/SwiftUI primitives and inspector ownership (`:7-53`) match `MicaTheme` and Workbench source. |
| `.trellis/spec/frontend/directory-structure.md` | Correctly identifies the SwiftPM targets and current Workbench/Design layout (`:7-44`); the mentioned Dashboard/Settings directories currently exist and are empty. |
| `.trellis/spec/frontend/state-management.md` | Current AppModel, runtime, per-window, preference, inspector, generation, and publication ownership (`:7-83`) matches the live-session contract. |
| `.trellis/spec/frontend/live-session-controller-contract.md` | Active generation/session transaction contract; current source and tests are organized around its controller-ID, generation, revision, pause, stale-data, and Tailscale rules (`:54-218`). |
| `.trellis/spec/frontend/workbench-ui-contract.md` | Active UI/performance contract. Its navigation at `:124-155`, topology at `:400-455`, and static/runtime validation boundary at `:1032-1041` match current source. |

The Trellis-managed `.codex`, `.claude`, and `.pi` integration trees and all
resolving skill links are keep items; their detailed inventory is owned by the
parallel AI-integration research artifact. The unregistered Codex
`.codex/hooks/session-start.py` is not evidence of obsolescence.

### External References

None. This classification is based entirely on current repository source,
tests, manifests, project rules, and active contracts; no external or
time-sensitive claim was needed.

### Related Specs

- `.trellis/spec/backend/controller-data-contract.md`
- `.trellis/spec/frontend/live-session-controller-contract.md`
- `.trellis/spec/frontend/workbench-ui-contract.md`
- `.trellis/spec/frontend/component-guidelines.md`
- `.trellis/spec/frontend/state-management.md`

## Caveats / Not Found

- This was a research-only pass. No product, documentation, specification,
  skill, platform configuration, or task lifecycle file was edited.
- The two additional rewrite items (`AGENTS.md` and the Mica project-skill
  reference) were found after the initial cleanup matrix was drafted. The task
  artifacts should explicitly permit those two wording-only edits before the
  implementation agent proceeds; otherwise active AI guidance will still name
  a deleted visual system.
- No Git commands were run in this research role. The audited scope is the
  repository files present under the paths named above; tracked-state and task
  archival verification remains an implementation/check responsibility.
