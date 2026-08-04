# Technical Design: Overview Visual And Interaction Polish

## Decision Summary

Recompose Overview as a native, constrained dashboard:

- one application-wide committed layout store;
- one window-local transactional editor and stable module runtime;
- five unique modules in a deterministic responsive grid;
- one unified instrument rail and one dominant telemetry workspace;
- flat operational summaries, complete neutral topology, and grouped network facts;
- existing Swift Charts, topology caches, real projections, and publication cadence;
- no third-party UI dependency, compatibility wrapper, modal layout editor, or
  custom content glass.

The layout system changes presentation only. Controller APIs, DTOs, domain
catalogs, ordering, live-session cadence, stale data, and safety boundaries remain
unchanged.

## Architecture Boundaries

### Shared Committed Layout

Add one `@MainActor @Observable` `OverviewDashboardLayoutStore`, owned by
`MicaApp` and injected into every window. It owns:

- the global default layout;
- one optional override per controller ID;
- stable per-controller committed state objects and effective version tokens;
- one store-wide persistence revision and serialized mutation queue;
- validation, persistence transactions, and controller-retention cleanup.

This store is separate from both existing authorities:

- `AppPreferencesStore` remains language, appearance, font scale, and GLOBAL
  visibility only.
- `WorkbenchWorkspaceStore` remains window-local, per-controller destination
  interaction state.

Sharing one committed store gives all windows the same final layout without
turning window-local search, selection, or editing state into global state.
Per-controller observable state objects keep a commit for controller A from
invalidating windows displaying controller B.

### Window-Local Coordinator

Each `ContentView` owns an `OverviewDashboardWindowCoordinator` and injects it
into its Workbench subtree. It survives destination view replacement and owns:

- base controller ID and effective version token;
- original layout and mutable normalized draft;
- whether the draft should become the new global default;
- undo/redo history;
- external-update conflict state;
- current drag target and preset preview state;
- stable telemetry and topology runtime objects for the current controller
  generation.

Entering edit mode copies one immutable committed snapshot. Ordinary edits never
touch persistence. `Done` performs one compare-and-swap commit against the base
effective version token; `Cancel` discards the draft.

Clean edit sessions cancel automatically before a destination or controller
change. A dirty session intercepts those intents and keeps Overview visible with
an inline Discard And Continue / Keep Editing choice. The existing
`MainWindowCloseGuard` also receives the layout dirty state so a close cannot
destroy the draft; native confirmation remains limited to dirty window close.

Replace the current shared destination `@AppStorage` with window-scoped scene
state. Menu navigation targets only the focused window. The selected controller
remains application-wide because Mica owns exactly one live generation.

If another window changes that selected controller, a dirty draft stays bound to
its original controller and enters a suspended conflict state. It may commit only
after validating that controller still exists, be marked as the new global
default, or be explicitly discarded. If the target controller was deleted,
controller-override commit is disabled; the draft remains available for
set-default or discard. Add/Edit Controller and every same-window Workbench
replacement intent use the same coordinator gate.

### Multi-Window Live Demand

Window-scoped destination state requires window-scoped presentation demand.
Give every window coordinator a stable `LiveSessionWindowDemandID`.

Replace the single `visibleDestination` in
`LiveSessionPublicationCoordinator` with a map from window demand ID to
destination and expose the union of observed domains. Add an equatable,
sendable `LiveSessionPresentationDemand` snapshot containing that union plus
global presentation pause, logs presentation pause, and baseline-publication
state. Pair it with a monotonically increasing revision scoped to the selected
generation. Window lifecycle calls:

- register/update destination for its own token;
- unregister only its own token on disappearance/close;
- calculate domains newly entering the union;
- update the window-domain portion of the actor demand only when the union
  changes.

Global presentation pause, logs presentation pause, baseline-publication state,
runtime installation, and generation replacement each rebuild and send the
complete demand snapshot even when the window-domain union is unchanged.
`LiveSessionRuntime` tests snapshot membership and the existing pause/baseline
gates when scheduling or publishing. A domain newly entering the union flushes
immediately only when those gates permit; visibility never force-bypasses a
pause.

Generation begin/invalidate clears revisions and schedules but preserves active
window demands, matching the current behavior that destination survives a
controller generation replacement. Construct each new `LiveSessionRuntime` with
the current complete demand and its initial revision, before assigning it or
starting stream ingestion. Subsequent asynchronous updates carry generation and
revision; the actor ignores a snapshot whose identity is stale or whose revision
is not newer than its last applied revision. This initialization boundary and
monotonic check prevent an older unstructured task from overwriting a newer
pause or window-domain state.

This is still one selected controller generation, one runtime, and one refresh
coordinator. It does not create per-window networking. With Overview in window A
and Logs in window B, the effective demand is traffic + connections + memory +
logs; closing B removes logs only.

If another window commits first, the current editor keeps its draft and shows an
inline conflict bar. `Reload` replaces the draft with the latest committed
layout. `Keep Mine` explicitly rebases and commits the current draft. No
last-writer-wins overwrite occurs without a user action.

### Effective Versions

The committed token records global revision, optional override revision, and
whether the effective layout is inherited or overridden.

- An inherited-layout commit validates the global revision.
- An override-layout commit validates its override revision and source.
- A `Set as Default` commit also validates the global revision.
- Changing the global default republishes only states currently inheriting it;
  overridden controllers keep their effective layout.

This makes global-default edits visible to every affected window and gives an
in-progress inherited draft the same explicit conflict behavior as a direct
controller override.

### Undo Integration

The coordinator registers every discrete draft mutation with the current
window's `UndoManager`. A drag reorder registers once on drop; a preset registers
one grouped action. Cmd-Z and Shift-Cmd-Z therefore use the standard responder
chain and never affect another window.

Done, Cancel, Reload, explicit discard, and controller-target replacement remove
the coordinator's registered actions. An external controller change suspends the
history with the draft; it does not replay mutations against the new controller.

## Layout Model

### Stable Types

Use small `Codable`, `Equatable`, `Sendable` value types:

- `OverviewDashboardModuleID`
- `OverviewDashboardModuleSize`
- `OverviewDashboardModuleConfiguration`
- `OverviewDashboardContentPreferences`
- `OverviewDashboardLayout`
- `OverviewDashboardPreset`

The fixed top-level module IDs are:

1. instrument rail
2. telemetry
3. operational summaries
4. route topology
5. network information

Every normalized layout contains each known ID exactly once. Visibility is a
field on the configuration, so restoring a hidden module never invents a second
instance. Operational summaries contain three uniquely identified category
configurations: latency, rule hits, and active connections.

### Legal Sizes

| Module | Legal sizes |
|---|---|
| Instrument rail | standard, full |
| Telemetry | standard, full |
| Operational summaries | compact, standard, full |
| Route topology | standard, full |
| Network information | standard, full |

Illegal persisted sizes fall back to that module's default. At least one module
must remain visible; hide commands are disabled for the final visible module and
normalization independently enforces the invariant.

### Deterministic Responsive Grid

Keep Overview's existing outer `ScrollView` and `LazyVStack`. A pure row packer
converts visible modules, in user order, into lazy rows:

- wide: 12 logical units; compact = 4, standard = 6, full = 12;
- medium: 6 units; compact = 3, standard/full = 6;
- narrow: one column; every module occupies the row.

Packing is sequential and never moves a later item ahead to fill a gap. This
preserves the user's horizontal reading order. Each lazy row creates at most
three modules, so below-viewport topology and charts are not eagerly
materialized.

Drag hover updates only an insertion indicator. The module order changes once on
drop, avoiding repeated topology/chart relocation for every pointer event.
Keyboard and VoiceOver alternatives move a module earlier or later.

### Built-In Presets

Presets replace only order, visibility, and legal size in the draft. They retain
the user's instrument metric order/visibility, timeline window, summary category
order/visibility/counts, and network group order.

| Preset | Default emphasis |
|---|---|
| Real-time Situation | instrument, full telemetry, full summaries, topology, network |
| Route Analysis | instrument, full topology, summaries, telemetry, network |
| Lightweight Monitoring | instrument, full telemetry, summaries; topology/network hidden |

The repository default is Real-time Situation. Applying a preset is already a
same-window preview because it changes only the transaction draft.

## Persistence

Use a dedicated UserDefaults data key and a versioned envelope:

- schema version;
- global default layout;
- controller override entries sorted by controller UUID;
- no business data, endpoint, identifier, credential, or live value.

Persist raw string IDs in the storage DTO and convert them through a validator so
future unknown module IDs do not invalidate the complete envelope. Validation:

1. discard unknown module records;
2. keep the first occurrence of each known module;
3. repair illegal sizes and bounded content settings;
4. append missing known modules as hidden using module defaults;
5. restore one instrument metric and one summary category when their owning
   visible module would otherwise be empty;
6. restore the repository default if no module remains visible.

An invalid override falls back to the current global default. An invalid global
layout falls back to the repository default.

Encoding reuses the safe part of the existing workspace pattern: snapshot on the
main actor and encode in a dedicated actor. Layout edits do not write while the
draft changes, so each successful Done needs exactly one final UserDefaults
commit rather than a delayed/coalesced queue. Controller deletion removes its
override. No import/export or external-process synchronization is added.

Layout commits are persistence-first transactions. `Done` disables replacement
intents, snapshots the complete envelope, awaits encoding in a dedicated actor,
writes the encoded data, then publishes the new committed state and exits edit
mode. Encoding failure leaves the draft open with an inline error. This creates
no pending layout write for destination changes, window close, or application
termination to lose.

All persisted mutations enter one serialized queue. Each queued request carries
its typed target mutation and expected effective token, not a stale complete
envelope. When it reaches the head, the store revalidates against the latest
store-wide revision, merges into the latest envelope, increments that revision,
encodes, writes, and only then publishes. A second-controller commit cannot
overwrite a first-controller commit while encoding is suspended.

`Set as Default` only marks the transaction draft. On `Done`, the store commits
that draft as the global default and removes an identical current-controller
override. `Reset Current Controller` previews the current global default; `Done`
removes the override when the final draft still equals that default. Cancel
clears either intent without writing.

## Overview Composition

### Instrument Rail

Replace four filled cards with one opaque, radius-8 rail. Its metrics share:

- one baseline;
- quiet vertical separators;
- semantic labels and monospaced numeric values;
- one text-supported live/stale status indicator.

Metric order and visibility come from layout content preferences. Values continue
to read the current real catalogs.

### Telemetry

Use one flat telemetry workspace:

- full-width upload/download chart as the visual focus;
- 64-80 point memory track immediately below;
- one shared readout and time-selection interaction state;
- controls aligned in the module header;
- cyan/violet traffic series and amber memory series, without decorative fills
  or gradients.

Preserve the current timeline cache and separate static series from hover/pin
overlays. Changing only a layout or editor affordance must not recompute samples.

### Operational Summaries

Use one operational-summary module with three internal categories. A full module
with sufficient width shows the visible categories as aligned columns. Narrow or
compact modules show one category at a time with a native segmented control.
Category order, visibility, and independent 1/3/5 row counts come from content
preferences; a visible summary module always keeps at least one category.

Rows use a primary business label, one secondary value, and a trailing real
metric. Empty states remain lightweight and distinct from unavailable states.

### Complete Topology

Retain every topology record and the existing asynchronous layout/index. Change
only visual encoding:

- neutral base edges and nodes;
- column headings with existing semantic titles and SF Symbols;
- cyan only for the complete hovered/pinned path;
- real final-node health color where available;
- no continuous animation.

Keep horizontal overflow, render bands, isolated base/highlight/hit layers,
44-point hit regions, accessible path rows, and same-window connection
navigation.

### Network Information

Project existing network facts into three stable presentation groups without
changing values:

- controller identity;
- runtime and feature state;
- listener ports.

Render each group as an unfilled aligned definition list. The module can be
standard or full width, but all reported fields remain visible in either size.

## Editing Surface

The Overview toolbar receives one localized SF Symbol command for edit mode.
During editing:

- an opaque inline editor bar appears at the top of Overview;
- module headers expose drag, size, hide, move-earlier, and move-later actions;
- a bottom available-module region restores hidden modules;
- an inline configuration disclosure inside the instrument module reorders and
  toggles metrics while enforcing one visible metric;
- telemetry exposes its default timeline window inline;
- operational summaries expose category order, visibility, and 1/3/5 row
  controls inline;
- network information exposes field-group order inline;
- module business buttons, chart selection, and topology selection are disabled;
- incoming live values may repaint inside their existing narrow subtrees.

Discrete layout changes may use a short system reflow animation. Respect Reduce
Motion by removing that animation. Data series, status, and topology never gain
continuous decorative animation.

## Observation And Performance

- Replace the current broad `hasOverviewData` catalog scan with a narrow
  `OverviewAvailabilitySnapshot` derived only from selected-controller identity,
  effective runtime kind, and low-frequency session state. Module-specific
  catalogs and timelines never participate in this root gate.
- Remove the old generation/language-only `OverviewLiveCanvas` Equatable gate or
  replace it with explicit availability, effective-layout, language, and
  edit-state inputs.
- The dashboard root observes availability, effective layout, edit-session
  state, and width mode only.
- Each business module remains a separate view that observes only its existing
  catalog/projection inputs.
- Hidden module IDs are filtered before the `@ViewBuilder` switch. Never-visible
  modules do not create runtime work; previously visible modules may retain a
  lightweight cached runtime but cannot resolve projections or schedule topology
  tasks while hidden.
- Layout packing is pure O(five modules) work and is cached by layout plus width
  mode.
- Drag movement does not rewrite persisted state or reorder business data.
- A runtime registry in the window coordinator is keyed by controller ID,
  generation, and module ID. It owns timeline projection/interaction state plus
  topology presentation, cache, and interaction state. Reordering a module
  across lazy rows therefore does not destroy its cache; replacing the
  generation prunes the old runtime.
- Controller generation changes reset chart/topology interaction but do not
  erase committed layout.
- Unsupported modules retain their layout identity and render an accessible
  unavailable state rather than disappearing.

Add DEBUG counters or focused operation counts proving: cold-hidden
telemetry/topology create no work and subsequently hidden modules add no work;
pure reordering does not increment timeline projection or topology
structure/layout build counts; a discrete topology width change performs at most
one required layout; a live frame invalidates only its own module. Metadata
contains counts and categories only.

## File Plan

- Add `WorkbenchOverviewPersonalization.swift` for layout values, validator,
  presets, shared store, persistence sink, window coordinator, stable module
  runtime, draft transaction, and row packing.
- Update `MicaApp.swift` to own and inject the shared committed layout store.
- Update `WorkbenchChrome.swift` to own/inject the window coordinator, intercept
  dirty navigation/controller changes, extend close guarding, and coordinate
  persistence-first commits; keep controller/session toolbar controls unchanged.
- Replace shared destination persistence with window-scoped scene state and make
  app commands act only on the focused window.
- Update `WorkbenchControllerSelector.swift` and `MainWindowCloseGuard.swift`
  only to route controller replacement and dirty-close intent through that
  coordinator.
- Update `LiveSessionRefreshModels.swift`, `AppModelLiveSession.swift`,
  `AppModelLiveSessionRuntime.swift`, and `LiveSessionRuntime.swift` to register
  window-token demands and publish their domain union through the existing single
  session/runtime. Keep pause, logs-pause, and baseline state in the complete
  demand snapshot even when the union does not change. Add generation-scoped
  monotonic revisions and initialize the actor with the first snapshot before
  any ingestion source can use it.
- Recompose `WorkbenchDashboard.swift` around the module grid and editor.
- Update `WorkbenchOverviewProjection.swift` only for pure network grouping or
  bounded summary inputs.
- Update `WorkbenchOverviewTopology.swift` only if neutral semantic styling
  needs cached metadata; do not move rendering back to the main actor.
- Reuse or minimally extend `WorkbenchVisualSystem.swift` primitives.
- Add focused layout/persistence tests and migrate Overview source-boundary tests
  under `Tests/MicaTests/`.
- Add dual-window demand-union tests to `LiveSessionPublicationTests.swift` and
  `LiveSessionRuntimeTests.swift`, including unchanged-union pause/resume,
  logs-pause, baseline, runtime-install, generation-replacement, and gated
  newly-visible flush cases. Deliver revisions out of order and verify the actor
  rejects the stale snapshot; initialize a paused or logs-only runtime and ingest
  immediately to verify there is no default-Overview publication gap.
- Migrate scalar destination callers in `SessionStreamStateTests.swift` and any
  other live-session tests to stable window demand tokens.
- Update localization, source verifier, `workbench-ui-contract.md`, and
  `live-session-controller-contract.md`, plus `docs/UI_GUIDELINES.md`, to replace
  the old fixed KPI/header and scalar destination contracts.

Adding one cohesive personalization file intentionally updates the current
Workbench file-architecture contract. Do not split each module into a separate
file or keep compatibility aliases for removed Overview views.

## Verification And Rollback

Implement all phases before the concentrated verification pass requested by the
user. Verify:

- layout normalization, presets, persistence, reset/default, transaction,
  conflicts, and row packing;
- unchanged real timeline/topology/summary/network projections;
- hidden-module admission and existing performance counters;
- localization, contrast, hit targets, Dynamic Type, keyboard, VoiceOver, and
  Reduce Motion;
- complete build/test/source-contract and offline performance gates.

The rollback boundary is presentation and layout persistence. Removing the new
layout key restores the repository default; controller data and API state are
never migrated.
