# Technical Design: Vertical Scroll Jank

## Decision Summary

Use a native SwiftUI, measurement-led scroll architecture refactor:

- one vertical scroll owner per destination;
- one native `Table` per data page;
- fixed and cheap row geometry while preserving selectable text;
- page-local presentation stores with narrow invalidation;
- delta-based logs and keyed connection metric updates;
- viewport-aware, layered topology rendering;
- one coarse interaction signal that does not invalidate page roots.

No AppKit table bridge, third-party scrolling framework, visual redesign, data
reduction, or removal of text selection is required.

The user approved Approach B on 2026-07-30.

## Considered Approaches

### A. Patch Only The Visible Hotspots

Remove the nested topology scroll, delete `fixedSize` from table text, and reduce
some `ViewThatFits` use.

This is the smallest change, but it leaves broad catalog Observation, three eager
Table descriptions, full-ring log projection, and write-only scroll state. It may
improve the offline case without fixing live-session regressions.

### B. Unified Scroll And Presentation Boundaries

Fix static rendering and online publication as one bounded performance task. Keep
the product structure and controller contract unchanged while replacing the
scrolling implementation boundaries.

This is the recommended approach because the user observes both first-pass and
repeat scrolling jank while offline, and the source audit also proves separate
online amplification paths.

### C. Replace SwiftUI Tables With AppKit Or A Third-Party Grid

This could provide lower-level virtualization control, but it expands the
SwiftUI/AppKit boundary, complicates text selection and accessibility, and is not
justified before correcting known SwiftUI structural problems. Reject for this
task.

## Measurement Gate

Before changing behavior, add temporary DEBUG-only observation at the smallest
useful boundaries:

- page and table body evaluations;
- projection full rebuild versus delta/keyed update counts;
- topology base draw, highlight draw, and accessibility materialization;
- workspace encode/write timing;
- scroll-phase begin/end and pending-publication commits.

Use existing privacy-safe `MicaPerformanceObservation` metadata only. Do not emit
controller values, IDs, URLs, names, payloads, or logs.

The offline static case is the first gate. Live fixtures and publication stress
are evaluated only after the static path improves. A final host-Mac SwiftUI
Instruments trace is needed because pure projection benchmarks cannot prove frame
smoothness.

## Static Scroll Architecture

### Single Vertical Owner

Each destination owns exactly one vertical scroll container. Nested scrolling may
remain only when its axis is orthogonal to the page.

Overview keeps the complete topology in the page. The topology's vertical extent
participates in the outer page scroll rather than owning a second vertical
`ScrollView`. Its horizontally wider content can retain a horizontal viewport.
For large graphs, divide the immutable layout into stable vertical render bands so
the outer `LazyVStack` materializes only nearby bands while every connection path
and chain hop remains represented.

Policy group horizontal canvas plus vertical native Lists is axis-orthogonal and
can remain. Directory, node, and inspector phase tracking stays local to each
scroll subtree.

### One Table Per Data Page

Replace `WorkbenchDataResponsive<Full, Compact, Stacked>` with a width-mode reader
that computes one discrete mode and invokes one content builder. Each page owns
one `Table` root and conditionally supplies the columns for that mode.

Selection, sort state, accessibility identity, scroll position, and scroll phase
belong to that single Table. Resizing across a width threshold may change columns,
but ordinary state changes must not construct three Table/column trees.

### Row Geometry And Selectable Text

Create separate components for table rows and inspectors:

- table values are single-line, fixed-height, and omit vertical `fixedSize`;
- full wrapping remains in inspectors and detail canvases;
- text selection is applied at the highest verified Table/row scope that preserves
  the current drag-selection behavior, rather than repeated on every Text leaf;
- if container-scoped selection does not preserve the exact behavior, retain
  leaf selection and optimize the surrounding layout instead.

No visible business value is removed. Truncated table cells continue exposing the
complete selectable value in the same-window inspector.

### Management Width Mode

`WorkbenchManagementCanvas` resolves a small width enum once. Repeated form,
diagnostic, and operation rows receive that value and directly choose their
layout. Keep `ViewThatFits` only for a few low-count chrome elements where its
measurement cost is immaterial.

Extract large state-dependent sections into actual `View` types with narrow value
inputs. Computed `some View` properties do not create invalidation boundaries and
are not sufficient.

## Dynamic Presentation Architecture

### Data Page Stores

Connections, Logs, Rules, Sources, and Proxies use page-owned `@Observable`
presentation stores. The SwiftUI Table receives only:

- stable ordered row IDs;
- immutable static row material;
- narrow dynamic row state;
- selection and sort snapshots;
- action availability needed by visible rows.

Command bars and operation controls are separate subviews so unrelated busy or
health changes cannot invalidate the Table.

### Connections

Keep structure and metric publications distinct all the way into presentation:

- structural revision creates/removes/reorders row identities and static search
  material;
- metric revision updates only changed row metric state by stable ID;
- sorting on static fields updates immediately;
- sorting on live metric fields freezes while the user is scrolling, retains only
  the newest pending ordering, and commits once on idle or at a fixed maximum
  latency boundary.

Controller source order remains untouched.

### Logs

Pass append/drop delta through to the log presentation store:

- format only appended rows;
- remove dropped IDs through an index;
- preserve controller order;
- when Follow Newest is off, retain viewport position while deltas arrive;
- while scrolling, merge non-critical Table commits with a fixed deadline and
  publish only the newest state.

The ScrollPhase handler changes Follow Newest once at interaction start and does
not write workspace persistence from the scrolling subtree.

### Rules, Sources, And Proxies

Keep stable static projections and rebuild only for their declared inputs.
Scrolling phase lives below the page root. A scheduler reference may track pending
work without being an observed page property; it publishes a minimal token only
when a deferred result actually commits.

## Overview Rendering

### Charts

Keep Swift Charts. Prefer the current SDK's vectorized continuous-series plot API
when availability is confirmed; otherwise retain bounded marks behind a stable
chart subview.

Static series and interaction overlays have separate state boundaries. Hover and
pin changes update readout/selection overlays without rebuilding both base chart
series.

### Complete Topology

Preserve every active connection and every reported chain hop.

- immutable structure/layout remains off the main actor;
- cache resolved labels and static drawing primitives;
- render stable vertical bands near the viewport;
- separate static base drawing from hover/pin highlight drawing;
- build accessible path rows lazily instead of materializing a complete hidden
  button tree on every Canvas update;
- cull drawing by band/visible bounds without dropping topology records.

The topology remains interactive and in Overview. Optimization changes
presentation work, not represented data.

## Workspace And Scroll State

Selection and viewport anchor are separate values. Bind a real scroll position or
stable visible-row anchor to the single Table/List and clear generation-owned
anchors on controller switch.

Workspace JSON encoding moves off the main actor from an immutable snapshot.
UserDefaults commit is coalesced until scroll idle, destination change, window
close, or a fixed maximum deadline. No scroll phase event performs synchronous
encoding or disk persistence.

## Correctness And Cancellation

- Controller ID and generation guard every delayed presentation commit.
- Interaction coalescing stores one latest state, never a historical queue.
- Errors, disconnects, destructive confirmations, mutation results, and
  cancellation bypass ordinary deferral.
- Destination changes cancel page projection/render work and clear local
  interaction state.
- Data, ordering, selection, text selection, accessibility, complete topology,
  and stale/disconnected semantics remain unchanged.

## Verification

1. Focused tests for width-mode single construction, stable row identity,
   delta logs, keyed connection updates, sorting freeze/flush, scroll anchor
   lifecycle, and generation cancellation.
2. Existing projection and runtime benchmarks with counters proving no full
   rebuild on scroll-only or metrics-only input.
3. Offline host-Mac SwiftUI Instruments capture across Overview, Proxies, all
   four data Tables, Controllers, Diagnostics, and Settings.
4. Live publication stress through existing fake transports; no real controller,
   port 9090, core process, or system-network change.
5. Final build/test/source-contract/localization/diff checks after implementation,
   not after every small edit.

Completion requires frame and invalidation evidence. A successful build alone is
not proof that scrolling is fixed.
