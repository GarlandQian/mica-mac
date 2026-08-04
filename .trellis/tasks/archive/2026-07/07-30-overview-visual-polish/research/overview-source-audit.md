# Overview Source Audit

## Scope

This audit records the current implementation facts needed for the Overview
visual and personalization task. It is source-only. No controller, port 9090,
core process, system networking, runtime smoke, or old screenshot was used.

## Current Composition

- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift` owns the complete
  Overview route.
- `OverviewLiveCanvas` has one vertical `ScrollView`, one `LazyVStack`, and an
  existing 1,180-point maximum content width.
- The current order is session header, telemetry/KPI section, three summary
  sections, complete topology, and network facts.
- Four filled metric tiles compete with the traffic chart. Wide telemetry places
  memory in a separate right column; narrow telemetry stacks it below.
- Each latency/rule/connection summary asks the pure projection for up to five
  rows.
- Network facts render in an adaptive label/value grid without semantic groups.

## Existing Real Data And Interaction

- `WorkbenchOverviewProjection.swift` owns received-sample timeline projection,
  bounded Top-K summaries, deterministic formatting inputs, and complete network
  fact values.
- Traffic and memory timelines contain only generation-scoped received samples.
  The chart supports hover, click-to-pin, sample stepping, timeline windows, and
  return to live.
- Summary rows retain real policy names, node names, rule payloads/proxies,
  connection IDs, and traffic values; destination actions open the corresponding
  complete page.
- `WorkbenchOverviewTopology.swift` builds every active connection path and every
  reported chain hop. Missing metadata becomes an explicit unavailable record
  rather than a fabricated edge.
- Topology selection supports hover, pin, accessible complete path rows, and
  same-window Connections navigation.

## Performance Boundaries To Preserve

The implementation from `07-30-vertical-scroll-jank` already provides:

- one Overview vertical owner and horizontal-only topology overflow;
- cached/downsampled timeline projection keyed by generation, source identity,
  and window;
- static chart series isolated from interaction overlays;
- topology normalization and layout away from the main actor;
- indexed topology nodes, edges, path membership, and segment-cell hit regions;
- separate base, highlight, hit, and accessibility layers;
- stable vertical render bands;
- bounded Top-K summary projections.

`Tests/MicaTests/WorkbenchOverviewPerformanceTests.swift` and
`Tests/MicaTests/WorkbenchTimelineAndProxyTests.swift` cover these boundaries.
`scripts/verify-real-controller-source.mjs` currently asserts two Swift Charts,
three vectorized line plots, lazy construction, complete topology bands, one
vertical owner, real data, and the old fixed KPI/fact-grid composition.

## State And Window Ownership

- `MicaApp` owns one shared `AppModel` and `AppPreferencesStore` for its
  `WindowGroup`.
- The selected controller/session is intentionally application-wide, but the
  current destination is also stored through `@AppStorage`; a destination change
  can therefore navigate every window.
- Every `ContentView` owns a separate `WorkbenchWorkspaceStore`, so destination
  search, selection, filters, and session-bound workspace state remain local to
  that window.
- `WorkbenchWorkspaceStore` persists versioned per-controller/per-destination
  values through coalesced off-main JSON encoding. It excludes session-only
  selection and scroll state from persistence.
- No current store owns Overview layout preferences or cross-window committed
  layout revisions.
- A separate app-owned layout store is therefore required for shared commits;
  putting edit drafts into `AppPreferencesStore` or the window workspace store
  would violate one of their existing ownership boundaries.
- Personalization needs window-scoped destination state while preserving the
  single app-wide controller generation. External controller switches/deletions
  must be treated as draft conflicts rather than silently retargeting the draft.
- The live publication coordinator and actor runtime currently each hold one
  `visibleDestination`. Making destination window-scoped therefore also requires
  stable per-window demand tokens and a union of observed domains; otherwise one
  window can stop another window's traffic, memory, connection, or log
  publication.
- Actor presentation demand also carries global pause, logs pause, and baseline
  publication state. Those values can change while the window-domain union stays
  equal, so union deduplication must apply only to window demand mutations.
- `AppModelLiveSessionRuntime` currently sends presentation demand through
  unstructured concurrent tasks. Without a generation-scoped revision, an older
  task can arrive after a newer snapshot; runtime installation also needs the
  initial snapshot before stream ingestion starts.
- The authoritative live-session contract and tests, including
  `SessionStreamStateTests.swift`, still call the scalar
  `setVisibleSessionDestination(_:)` API and must migrate with the implementation.

## Chrome And Duplication

- The sidebar already displays the selected controller.
- `WorkbenchRootView` already supplies the native Overview navigation title.
- `WorkbenchBottomChrome` already supplies selected controller state and a stable
  timestamp.
- The complete `OverviewSessionHeader` therefore repeats controller identity,
  status, time, and version inside content.
- The toolbar currently contains shared session controls. A child Overview
  toolbar item can add the personalization command without replacing those
  controls or adding a custom capsule.

## Visual And Product Constraints

- The fixed graphite/cyan palette and semantic status colors live in
  `WorkbenchVisualSystem.swift` and the active Workbench UI contract.
- Native material is reserved for window/sidebar/toolbar/control chrome.
  Overview business content is opaque and flat; custom content glass, gradients,
  glow, nested cards, and fabricated charts are prohibited.
- Active controller business values remain fully visible. Credentials and raw
  response/stream bodies remain outside diagnostics exports.
- SwiftUI, Swift Charts, Canvas, and SF Symbols already satisfy this task. No
  third-party package has a demonstrated need.

## Required Contract Updates

Implementation must replace, not preserve, source assertions and documentation
for:

- the complete Overview session header;
- four separate KPI tiles;
- side-by-side wide memory chart;
- five-row fixed summary columns;
- adaptive ungrouped network fact wall;
- the exact Workbench file list if the cohesive personalization file is added.

The controller data, live-session, topology completeness, localization,
accessibility, and performance assertions remain authoritative.
