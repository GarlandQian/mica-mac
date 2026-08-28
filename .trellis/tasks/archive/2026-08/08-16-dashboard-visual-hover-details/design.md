# Technical Design

## 1. Scope And Replacement Strategy

This task replaces the Overview presentation, customization, and persistence
architecture in place while keeping controller/session ownership intact.

Replace or delete the responsibilities currently owned by:

- `WorkbenchDashboard.swift`: generic module grid/span composition.
- `WorkbenchOverviewPersonalization.swift`: module size, preset, normalizer,
  row-packer, and arbitrary layout model.
- `WorkbenchOverviewLayoutStore.swift`: v1 development envelope, lossy restore,
  global/per-controller revisions, overrides, and transactions.
- `WorkbenchOverviewWindowCoordinator.swift`: layout drafts, conflicts, undo,
  commit state, and controller reconciliation.
- `WorkbenchOverviewEditor.swift`: presets, module drag/reorder/size, global
  default, reset, Done/Cancel, and content-order editors.
- The reserved topology selection-detail inset in
  `WorkbenchOverviewTopologyView.swift`.

Preserve and refactor rather than replace:

- `AppModel`, selected-controller identity, session generation, and domain
  snapshots.
- `ConnectionTopology`, its builder, complete paths, and unavailable-path
  semantics.
- Topology structure/layout caches, render-band isolation, hit testing, path
  highlighting, and pause/resume behavior.
- Timeline projection caches and real-sample-only chart contracts.
- Controller adapters, capability gates, authentication, ordering, optionality,
  and unsupported/unresolved states.

## 2. Ownership And Data Flow

```text
MicaApp
├── AppModel                         authoritative live controller data
├── OverviewPreferencesStore        one global persisted preference value
└── WindowGroup
    └── ContentView
        ├── OverviewWindowRuntime    window demand ID + session-scoped runtimes
        └── WorkbenchOverviewView
            ├── OverviewTelemetryStage
            ├── OverviewTopologyStage
            │   ├── topology presentation/cache
            │   ├── policy inspection cache
            │   └── node-anchored HUD
            └── OverviewOptionalRegion
```

- `OverviewPreferencesStore` is app-owned and shared by every window.
- `OverviewWindowRuntime` is window-owned and contains only
  `LiveSessionWindowDemandID` plus telemetry/topology runtime registry state.
- Removing layout drafts means Overview changes no longer participate in the
  window dirty-close guard.
- `AppModel.policyGroupCatalog` is observed only by the topology inspection
  subtree. Traffic writes cannot invalidate policy inspection, and policy writes
  cannot rebuild connection topology geometry.

## 3. Replacement Global Preference Model

Use a compact value model such as:

```swift
struct OverviewPreferences: Codable, Equatable, Sendable {
    var visibleMetrics: Set<OverviewMetricID>
    var timelineWindow: OverviewTimelineWindow
    var visibleOptionalModules: Set<OverviewOptionalModuleID>
}
```

The stable display order comes from enum order, not persisted arrays. The
default contains every telemetry metric, the five-minute window, and no optional
modules.

Persist an envelope with a required replacement-schema discriminator and the
preferences value. Continue using the Overview v1 product identity; the
discriminator distinguishes the replacement development format from the
superseded layout object. A decode failure returns `.default` and does not call a
migration adapter.

`OverviewPreferencesStore` is `@MainActor @Observable`:

- load once from `UserDefaults` at app initialization;
- expose one `preferences` snapshot;
- normalize only current invariants (at least one visible metric);
- save immediately after a meaningful change;
- deduplicate equal assignments;
- publish changes to every window through the shared instance.

The customizer is an inline/native disclosure from the Overview command area.
It writes immediately and contains only:

- metric visibility toggles in fixed order;
- one timeline-range picker;
- optional module visibility toggles in fixed order;
- one Reset to Default command.

There is no draft, preset, size, order, controller override, inheritance,
revision token, conflict UI, Done, Cancel, or close guard.

## 4. Fixed Overview Composition

`WorkbenchOverviewView` retains the current availability/state boundary, then
renders one `ScrollView` with a `LazyVStack`:

1. `OverviewTelemetryStage`
2. `OverviewTopologyStage`
3. `OverviewOptionalRegion`

Telemetry and topology are constructed unconditionally for a live/partial/stale
session. Optional sections are filtered before their view subtree is created.
Instrument rail, operational summaries, and network information keep their
existing real-data projections but receive the new surface treatment and appear
only in the fixed auxiliary order.

Delete `OverviewDashboardSpanLayout`, width-mode column counts, module size,
row packing, and layout presets. Each stage remains internally responsive:

- telemetry: three columns at wide width, two traffic columns plus one full row
  at medium width, and a vertical stack at narrow width;
- topology: one full-width graph with no nested horizontal viewport;
- optional region: simple full-width sections, not a second dashboard grid.

## 5. Cyber-Neon Visual Layer

Add Overview-focused semantic primitives without changing controller semantics:

- `OverviewCyberPalette`: derived from existing Mica semantic signal colors;
- `OverviewCyberSurface`: opaque/adaptive content fill, restrained gradient edge,
  one-pixel semantic border, and bounded shadow/bloom;
- `OverviewEnergyStroke`: static base stroke plus finite trigger-driven energy
  overlay;
- `OverviewGlowMark`: finite latest-value/selection emphasis;
- motion tokens for sample pulse, route pulse, HUD appear/expand, and pin state.

Do not use Liquid Glass for content. Native toolbar/sidebar controls may continue
to receive system materials. Cyber surfaces must remain legible in light mode,
high contrast, increased font scale, and Reduce Transparency.

Neon roles encode information:

- cyan: download/informational/live route;
- violet: upload/secondary energy series;
- mint: reported healthy/available;
- amber: stale/warning/unknown measurement;
- red: reported failure/unavailable.

No background particles, scan-line loop, or continuous `TimelineView` is used.

## 6. Telemetry Refactor

Keep Swift Charts and `OverviewTimelineProjectionCache`. Refactor only the view
composition and interaction effects:

- retain real received samples and existing timeline selection/pause semantics;
- keep plot height responsive within the current bounded range;
- use area + line marks with a restrained under-glow;
- add a finite latest-edge pulse keyed by the latest real sample identity;
- keep hover and pinned sample state inside the telemetry runtime;
- render static latest markers when paused or Reduce Motion is enabled.

The pulse trigger is a discrete sample/revision token, not a timer. A new sample
runs one finite animation; no sample means no animation work.

## 7. Policy Inspection Projection

Introduce a pure, cached policy projection independent of topology geometry:

```text
PolicyGroupCatalogSnapshot
    -> OverviewPolicyInspectionIndex
       ├── unique groups by reported name
       ├── member records by reported name
       └── ambiguous-name markers
```

`OverviewPolicyInspectionIndex` preserves controller order and builds typed
records once per distinct catalog snapshot. Resolution order for a `.policyHop`
node is:

1. one unique exact group-name match -> group summary + selected member;
2. no group match and one unique exact member-name match -> member summary;
3. duplicate/ambiguous/missing match -> no policy record, keep route detail.

Never select the first duplicate silently. Standard HUD fields are derived from
`ProxyGroupViewState`, `ProxyNodeViewState`, `ProxyMemberDetailProjection`, and
existing formatting/localization helpers. Every additional controller field is
projected individually in stable key order; Proxies remains the browsing,
switching, testing, and recursive-disclosure workspace.

The topology runtime owns an `OverviewPolicyInspectionCache`. Changing the
catalog updates only this cache and the active HUD projection. The topology
structure request remains generation + connection revision; the layout request
remains structure + width/minimum height.

## 8. Node Geometry And HUD Placement

Extend `OverviewTopologyLayout` with an immutable `nodeGeometryByID` lookup built
alongside the existing node array. This makes selection-to-anchor lookup O(1)
without changing graph construction order.

Use a pure `OverviewPolicyHUDPlacement` function with inputs:

- anchor node `rect` and `labelRect`;
- transient or pinned HUD width;
- graph bounds;
- nearby node/label rectangles;
- preferred side derived from label side and available space.

Generate trailing, leading, above, and below candidates. Score candidates by:

1. out-of-bounds area (largest penalty);
2. overlap with the anchor (disallowed);
3. overlap area with nearby node/label obstacles;
4. distance from the anchor;
5. stable preferred-side tie break.

Choose the lowest score and clamp the result to graph bounds. Placement is
recomputed only when active selection, pin mode, layout identity, or measured HUD
size changes. Raw pointer movement within the same hit target does no work.

## 9. HUD Interaction And Content

Retain `OverviewTopologyInteractionState` as the hover/pin authority, then derive
an `OverviewPolicyHUDSnapshot` from:

- active selection;
- pinned/transient state;
- topology index;
- policy inspection index;
- anchor geometry;
- language.

Transient and pinned HUDs share the same complete field composition:

- group/member name and role;
- group type, selected member, member count, and ordered member names;
- member type, provider, interface, hidden/fixed/icon fields;
- current/latest reported latency and availability;
- every reported transport capability state, including `false`;
- SMART usage rank;
- latest test delay/time, history count, and test URL;
- every additional controller field in stable key order;
- same-window Open Proxies action;
- existing single-path Open Connections action when eligible.

Click toggles persistence; it does not unlock hidden fields. Escape and
blank-canvas click clear it. Hovering a new
node temporarily inspects it without destroying the pinned selection only if the
interaction model explicitly keeps the current precedence; implementation must
retain one clear authority and cover it with tests. The chosen v1 behavior is
the current precedence: transient hover wins visually, and leaving restores the
pinned HUD.

Non-policy node/edge/path selection uses a compact route HUD with the existing
truthful label/description rather than the old fixed header inset.

## 10. Topology Rendering And Motion Isolation

- Remove `selectionDetailHeight` and the fixed detail overlay from graph layout.
- Preserve base/highlight/hit render-band separation.
- Base bands remain equatable and do not observe hover/HUD content.
- Highlight bands observe only the compact interaction snapshot.
- HUD is a separate overlay subtree and does not redraw base Canvas bands.
- A finite route-energy animation is triggered by structure, received traffic,
  connection metrics/traffic revision, or direct selection, then settles to the
  static gradient ribbon.
- Window inactive, pause, or Reduce Motion disables route animation but not
  static highlight.

## 11. Accessibility And Localization

- Every policy node keeps an accessible label and gains a value summarizing the
  same reported HUD fields.
- Accessible actions expose inspect/pin/unpin, clear, Open Proxies, and eligible
  Open Connections behavior.
- Focus traversal does not require pointer hit testing.
- HUD text supports Mica font scale, text selection for business values, and
  meaningful wrapping in English and Simplified Chinese.
- Color never carries status alone; symbols/text accompany health and pin state.
- Reduce Motion and high-contrast appearance are explicit acceptance states.

## 12. Verification And Contract Updates

Replace focused tests instead of preserving old compatibility types:

- global preference default/round-trip/reset/deduplication;
- old-layout data falls back to the redesigned default;
- fixed composition and optional visibility;
- no per-controller persistence API remains;
- unique/ambiguous/missing policy inspection resolution;
- complete hover/pinned HUD field projection;
- HUD candidate scoring and boundary clamping;
- topology geometry/cache counts unchanged across hover and catalog-only updates;
- Reduce Motion/inactive/pause motion-state projection;
- existing timeline, topology, accessibility, and dense-data performance tests.

Update `workbench-ui-contract.md`, `docs/UI_GUIDELINES.md`, localization, and
`verify-real-controller-source.mjs` to assert the new v1 architecture and to
exclude removed legacy symbols.

## 13. Rollback Shape

Implementation is staged so each boundary can be reverted independently before
the final legacy deletion:

1. preference/window-runtime separation;
2. fixed composition;
3. visual and telemetry treatment;
4. policy inspection/HUD;
5. legacy deletion and contract cleanup.

Do not delete the old layout types until the replacement global store and window
runtime compile and their focused tests pass. Do not replace topology detail
until the HUD projection/placement tests pass.

## 14. Task Decomposition And Audit Integration

The parent feature and its audit children form one ordered delivery:

```text
Phase 1: 08-16-global-functional-audit
    -> evidence-led baseline audit
    -> fix verified Critical/High/Medium defects
    -> hand off preserved shared boundaries

Phase 2: 08-16-dashboard-visual-hover-details
    -> implement the Overview replacement described in this design
    -> delete the superseded Overview architecture
    -> satisfy AC-01 through AC-14 on the corrected baseline

Phase 3: 08-16-post-refactor-integration-audit
    -> audit the final combined application
    -> prove cross-window/session/destination integration and legacy removal
    -> fix verified Critical/High/Medium regressions
    -> close AC-15 through AC-18
```

The baseline audit covers all production areas, but intentionally limits review
of the soon-to-be-deleted Overview presentation to shared live-session,
controller-switching, publication, and navigation boundaries. Its report is a
required implementation input for Phase 2.

The post-refactor audit starts only after Phase 2 is code-complete. It reviews
the final code—not separate patches—and explicitly traces shared owners and
consumers introduced or changed by the refactor:

- app-owned global Overview preferences;
- window-owned live-session demand and runtime;
- ContentView/WorkbenchChrome injection and close behavior;
- telemetry/topology/policy-catalog projections and invalidation boundaries;
- HUD navigation into Proxies and Connections;
- shared Workbench visual primitives consumed by other destinations;
- source verifier, localization, docs, and active Trellis contracts.

Each audit uses its own evidence report. Findings may be fixed in focused
batches, but the parent cannot complete while either report contains an
unresolved Critical, High, or Medium issue. Low findings remain report-only and
do not silently broaden the feature scope.
