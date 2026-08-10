# Overview 原生监控工作台设计

## 1. Existing Architecture

- `WorkbenchOverviewView` owns availability routing and the one Overview instantiation used by `WorkbenchWorkspaceView`.
- `OverviewDashboardCanvas` owns the single vertical scroll view, deterministic row packing, responsive width mode, and per-window runtime lookup.
- `OverviewTelemetryModuleRuntime` owns timeline projection caching, pause state, selected window, and shared chart interaction.
- `OverviewTopologyModuleRuntime` owns complete topology presentation caching, hover/pin state, pause, and same-window expansion.
- `WorkbenchOverviewPersonalization` owns five stable module IDs, persisted order/visibility/size, presets, global defaults, controller overrides, CAS conflict handling, and per-window drafts.

## 2. Visual Changes

### Telemetry

- Replace three separately boxed `OverviewTelemetryPanel` surfaces with one bounded telemetry surface.
- Keep each metric as an equal-weight instrument column with its own label, selected/current value, substantial 144pt plot, timestamp, and contextual footer.
- In wide and medium horizontal arrangements, use subtle vertical separators between instruments; in stacked arrangements, use horizontal separators.
- Keep chart plot backgrounds restrained and radius at 4pt. Do not add gradients, shadows, or nested cards.

### Topology

- Preserve the current complete, width-bounded Sankey implementation and isolated base/highlight/hit/accessibility render bands.
- Reduce dead selection space when nothing is selected, while retaining a stable detail region when a path is active.
- Keep the graph centered and vertically unconstrained by a decorative frame; only the graph itself owns the bounded content fill and 8pt outline.

### Network facts

- Keep source-defined group order and facts.
- Present each group as a flat definition block with a group header, internal dividers, and adaptive columns. Values wrap naturally under large font scale.

## 3. Performance Changes

- Remove per-row `onAppear` opacity/offset animation, which overlaps with live chart and topology invalidations while scrolling.
- Remove sample-array implicit animations from traffic and connection base charts. Point, line, and area marks update directly from real samples.
- Retain `Equatable` base chart boundaries, projection caches, topology caches, lazy module rows, banded Canvas rendering, and scroll performance instrumentation.
- Do not introduce `TimelineView`, polling, per-view timers, geometry feedback loops, or nested vertical/horizontal scroll owners.

## 4. State and Data Boundaries

- No view performs network requests or controller mutations.
- Chart and topology states remain scoped to the selected controller ID plus generation through the existing runtime registry.
- Disconnected/loading/partial/error behavior remains owned by `OverviewAvailabilityRegion`; no stale data authority is added.
- Personalization persistence and conflict handling remain unchanged.

## 5. Verification

- Extend source tests/verifier to prohibit Overview viewport-entry animations and sample-driven base-chart animation.
- Preserve current source contracts for chart count/marks, complete topology, one scroll owner, width fitting, and default module visibility.
- Run focused Overview tests first, then one full Swift build/test pass and non-runtime repository checks.
