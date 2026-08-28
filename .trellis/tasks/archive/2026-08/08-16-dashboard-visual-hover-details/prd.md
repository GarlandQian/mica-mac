# 首页赛博霓虹重构与策略节点全息 HUD

## Goal

Rebuild the Workbench Overview as the definitive v1 cyber-neon dashboard. The
page must make live telemetry and complete route topology the visual focus,
remove the current generic dashboard/customization architecture, and expose
useful controller-reported policy-group parameters through a node-anchored
holographic HUD. The broader delivery also includes a separate full-application
functional audit so defects outside the redesigned Overview are not missed.

## Confirmed Facts And Constraints

- Planning uses the current repository state only; earlier homepage proposals
  and conversation decisions are intentionally not inputs.
- Mica is a Swift 6.2 SwiftPM application targeting macOS 27. No older-OS
  back-deployment layer is required.
- The selected live controller, session generation, capability gates,
  controller-reported ordering, and optional fields remain authoritative.
- Mihomo, Nikki, OpenClash, CMFA/Stash, sing-box, and Surge support is active
  product behavior, not legacy homepage compatibility.
- The existing topology already provides cached geometry, render bands,
  indexed hit testing, path membership, transient hover, pinned selection,
  keyboard path stepping, pause behavior, and accessible path controls.
- Rich policy data already exists in `PolicyGroupCatalogSnapshot` and related
  group/member projections; hovering must not start a controller request.
- The current `overview.dashboard.layout.v1` representation is a development
  implementation, not a public migration contract.
- The repository currently contains approximately 128 production Swift files
  (65,000 lines) and 38 Swift test files (17,000 lines). The audit therefore
  requires a separate, evidence-led review pass rather than being folded into
  incidental homepage review.

## Key Decisions

- The application remains v1. This work replaces the current Overview in
  place; it is not called v2.
- The visual direction is selective cyber-neon: dark layered depth,
  cyan/violet energy accents, luminous data flow, and strong hover/selection
  contrast without decorative clutter.
- The Overview uses a fixed hierarchy: telemetry first, complete route
  topology second, then user-enabled optional information.
- Telemetry and topology are always visible and cannot be reordered or resized.
- Instrument rail, operational summaries, and network information are hidden
  by default but remain recoverable through the rewritten customizer.
- Remove module sizes, presets, free drag/reorder, generic row packing, and
  arbitrary module placement.
- Keep one global preference set. Remove per-controller overrides, inheritance,
  controller cleanup, revision conflicts, and transactional layout drafts.
- Replace the current persisted layout format in place. Do not migrate old
  stored layouts; incompatible data resets to the new v1 default.
- Hovering a policy-group node shows a node-anchored holographic HUD with the
  complete available field composition. Clicking pins the same complete HUD;
  Escape or a blank-canvas action clears it.
- Motion is bounded and data-driven. Idle, paused, inactive-window, and Reduce
  Motion states are static.
- Audit remediation policy: automatically fix every verified Critical, High,
  and Medium functional/security/data-integrity/concurrency/performance defect.
  Record Low-severity style or maintainability findings without expanding the
  delivery automatically.

## Delivery Task Tree And Order

The approved delivery is one parent feature task with two independently
verifiable audit children:

```text
08-16-dashboard-visual-hover-details
├── 08-16-global-functional-audit
└── 08-16-post-refactor-integration-audit
```

Execution is strictly ordered:

1. complete the baseline global audit and all verified Critical/High/Medium
   remediations outside the obsolete Overview presentation;
2. implement this parent Overview replacement on the corrected baseline;
3. run the post-refactor full-application integration audit and fix every
   verified Critical/High/Medium regression.

Trellis parent/child metadata does not enforce dependencies, so these gates are
part of the product acceptance contract. The parent cannot be completed until
both child reports are complete and blocking findings are resolved.

## Requirements

### R1. Fixed Overview Composition

- Replace the generic dashboard grid with a purpose-built vertical composition:
  telemetry, topology, and a stable optional-details region.
- Keep one Overview-owned vertical scroll axis and lazy construction for content
  below the viewport.
- A fresh/default preference state shows only telemetry and topology.
- Optional modules render after topology in a fixed order when enabled.

### R2. Cyber-Neon Visual System

- Refactor the complete Overview presentation rather than applying a local
  styling patch to existing module shells.
- Use existing semantic signal roles as the basis for neon effects: cyan for
  informational/live flow, violet for the paired series/energy role, mint for
  healthy state, amber for warning, and red for failure.
- Preserve readable content fills and native macOS controls. Do not apply
  Liquid Glass to chart, topology, table, or parameter content surfaces.
- Remove low-value duplicate headings, empty chrome, repeated summaries, and
  decorative elements that do not communicate data or interaction state.
- Shared Workbench primitives may be refactored where required, but other tabs
  must not receive unrelated feature or information-architecture changes.

### R3. Bounded Data-Driven Motion

- Route energy, latest-chart-edge glow, and hover/pin emphasis react only to new
  real data or direct interaction. Live readouts consume received rate/count
  samples rather than cumulative connection totals or structure-only revisions.
- Effects settle after a bounded animation; do not add background particles,
  looping scan lines, or page-wide perpetual animation.
- Pause, inactive-window state, and Reduce Motion disable motion while retaining
  static emphasis and complete information.
- Motion state must remain local to its chart/topology subtree and must not
  propagate raw per-frame values through the environment.

### R4. Policy-Group Holographic HUD

- Resolve `.policyHop` topology nodes against a prebuilt read-only policy
  inspection index.
- Anchor the HUD to cached node geometry, not to the raw pointer position.
- Clamp and flip HUD placement inside graph bounds to reduce occlusion and avoid
  edge overflow.
- Transient hover shows the complete available group/current-member field
  composition: current selection, member count and ordered members, reported
  availability/latency, node type, provider, interface, hidden/fixed/icon
  values, every reported transport capability including `false`, SMART usage
  rank, latest test delay/time/history count/URL, and every additional
  controller field in stable key order.
- Clicking pins the same complete field composition so it remains available
  after pointer exit; pinning is persistence, not a gate hiding detail.
- The existing same-window Proxies inspector remains available for browsing,
  switching, testing, and larger recursive values, but the HUD does not replace
  real fields with a compact summary or cap additional metadata.
- Non-policy nodes and unresolved/ambiguous policy names retain truthful
  route-oriented details rather than fabricated policy values.
- Keyboard focus and VoiceOver expose the same semantic inspection and pinning
  actions without requiring pointer hover.

### R5. Topology And Data Integrity

- Keep every active connection and every reported chain hop visible.
- Preserve controller order and optionality; never create fallback nodes,
  latency, availability, metadata, chart samples, or flow activity.
- Hover/pin must not rebuild topology structure or layout, change the current
  scroll position, or initiate network work.
- Policy-catalog changes may rebuild only the inspection index/HUD projection;
  connection/width changes remain the topology geometry invalidation boundary.
- Keep direct canvas, keyboard, context-menu, accessible-path, pause, expand,
  and Connections-navigation behavior unless explicitly replaced by the HUD.

### R6. Simplified Global Preferences

- Persist one global value containing only visible telemetry metrics, timeline
  range, and optional-module visibility.
- Apply the same preferences across windows and controller switches.
- Save preference changes immediately; there is no Done/Cancel transaction,
  dirty-close guard, global-vs-controller mode, or per-controller conflict.
- Invalid or superseded stored data falls back to the new default without a
  compatibility adapter.
- The customizer remains an inline/native Workbench interaction rather than an
  ordinary modal workflow.

### R7. Legacy Removal

- Remove old Overview module-size, preset, normalizer, row-packer, persisted
  layout, lossy migration, controller-override, draft, conflict, and commit
  types instead of retaining aliases or shims.
- Remove superseded localization keys, tests, source-verifier assertions, and
  UI contract text in the same change.
- Separate the window-owned live-session demand/runtime registry from the
  deleted layout coordinator so session behavior is preserved without keeping
  legacy personalization code.
- Do not remove controller adapters, capability gates, generation validation,
  optional-field handling, or unsupported/unresolved states under the label of
  compatibility cleanup.

### R8. Quality, Accessibility, And Localization

- Keep visible copy in English and Simplified Chinese.
- Retain selectable business values, keyboard navigation, VoiceOver order,
  high-contrast legibility, and font-scale support.
- Use stable view identity and narrow observation dependencies. Hover and motion
  must not invalidate unrelated Overview modules.
- Keep system Swift Charts and Canvas/Path; add no decorative dependency.

### R9. Full-Application Functional Audit

- Execute `08-16-global-functional-audit` before this refactor and
  `08-16-post-refactor-integration-audit` after it. Together they cover
  `MicaCore`, AppModel/live-session state, controller probing/adapters, profile
  and secret persistence, every Workbench destination, navigation/commands,
  localization/accessibility, concurrency/cancellation, performance caches,
  build configuration, and source-verifier contracts.
- Use build, test, source-contract, static-risk, data-flow, security, and
  focused manual source review evidence. Do not infer correctness from test
  count alone.
- Record each verified finding with severity, observable impact, reproduction
  or code path, file/line evidence, affected controllers/surfaces, and the
  appropriate focused validation.
- Critical/High/Medium findings are remediation requirements for this delivery;
  each fix must preserve controller/session contracts and pass a focused check.
  Low findings remain in the audit report unless promoted by new evidence.
- Automated audit checks must use fixtures/in-process transports and must not
  contact a real controller, reveal secrets, or modify networking.
- Avoid spending remediation effort on the superseded Overview implementation;
  audit its preserved controller/session boundaries, then review the redesigned
  Overview in the final integration pass.
- Run a final cross-feature audit after the Overview refactor to catch shared
  visual/runtime regressions introduced by the global cleanup.

## Acceptance Criteria

- [x] AC-01: The default Overview renders telemetry first and complete topology
      second; no optional module occupies space until enabled.
- [x] AC-02: The customizer exposes only metric visibility, timeline range, and
      optional-module visibility. No size, preset, reorder, controller override,
      inheritance, draft, conflict, Done, or Cancel controls remain.
- [x] AC-03: Preferences are shared immediately across windows/controllers and
      persist through one global store.
- [x] AC-04: Data stored by the superseded Overview layout implementation is not
      migrated and results in the redesigned v1 default.
- [x] AC-05: Telemetry and topology have a coherent cyber-neon hierarchy in
      dark and light appearances without content glass or low-contrast text.
- [x] AC-06: New real samples and route interaction produce bounded glow/energy
      effects; idle, paused, inactive, and Reduce Motion states are static.
- [x] AC-07: Hovering a resolvable policy-group node immediately displays an
      anchored HUD containing every available typed field and every additional
      controller field without an arbitrary count cap.
- [x] AC-08: Clicking that node pins the same complete HUD; Escape or clearing
      the canvas removes the pin without moving graph geometry.
- [x] AC-09: HUD placement remains inside graph bounds and selects a lower-
      occlusion side at narrow, wide, top-edge, bottom-edge, and dense-node
      positions.
- [x] AC-10: Missing, duplicate, or ambiguous policy matches never select an
      arbitrary group or invent values; route details remain usable.
- [x] AC-11: Hover/pin performs no controller request and does not rebuild the
      topology structure, geometry, render bands, or hit index.
- [x] AC-12: Dense topology interaction, chart selection, keyboard path stepping,
      pause/resume, expand/collapse, context commands, accessibility, and
      Connections/Proxies navigation remain responsive and correct.
- [x] AC-13: Source contains no superseded Overview preset, module-size,
      row-packer, layout migration, per-controller override, or layout-draft
      compatibility implementation.
- [x] AC-14: Focused preferences, policy inspection, HUD placement, topology
      invalidation, and motion-state tests pass alongside the project build,
      test, localization, HIG, source-contract, and diff checks.
- [x] AC-15: Every production subsystem and Workbench destination appears in a
      completed audit matrix with evidence and an explicit pass/finding result.
- [x] AC-16: Every reported defect has a severity, impact, reproducible path or
      source proof, file/line anchors, and focused validation status.
- [x] AC-17: A post-refactor integration audit verifies controller/session,
      navigation, persistence, accessibility, and performance behavior across
      the final combined codebase.
- [x] AC-18: Both audit child tasks are complete, every verified Critical/High/
      Medium finding is fixed and validated, and their reports map the final
      code to the parent acceptance criteria.

## Out Of Scope

- Changing controller protocols, supported controller families, authentication,
  live-session ownership, or controller capability semantics.
- Redesigning Workbench navigation or the feature architecture of non-Overview
  tabs beyond necessary shared primitive updates.
- Adding a new chart, graph, animation, or persistence package.
- Migrating the superseded Overview layout data or bumping the application to
  a v2 product version.
- Duplicating Proxies browsing, mutation commands, or recursive disclosure UI
  inside the HUD; the HUD still shows every available scalar/compact field.

## Risks And Deferred Items

- Duplicate policy/member names can make a topology-name join ambiguous. The
  HUD must fall back truthfully and may offer Proxies navigation rather than
  choosing an arbitrary record.
- A pinned HUD can obscure dense graph content. Placement is bounded and
  side-flipped; Proxies remains available for browsing and mutation workflows.
- Runtime visual acceptance requires representative live data and is user-run;
  automated checks must not contact a controller.
- A comprehensive audit can uncover remediation beyond the homepage scope.
  Scope stays finite through severity classification: verified Critical, High,
  and Medium defects are fixed; Low findings are recorded only.

## Open Questions

None. Visual direction, interaction model, preference ownership, compatibility
policy, audit coverage, remediation threshold, and three-phase order are
confirmed.
