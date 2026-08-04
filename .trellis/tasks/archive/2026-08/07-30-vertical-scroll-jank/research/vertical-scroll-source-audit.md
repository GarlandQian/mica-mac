# Vertical Scroll Source Audit

## Scope And Method

This is a source-only audit of the current native SwiftUI Workbench. It covers
offline/static scrolling first and live publication as a separate amplification
path. No real controller, port 9090, core process, system network state, or
runtime smoke was used.

The user confirmed:

- disconnected and completely static pages still lag vertically;
- both first exposure and repeated scrolling lag;
- per-character text selection must remain;
- full controller data, controller order, and complete topology must remain.

Host-side Instruments measurements are still required during implementation.

## Static Scroll Costs

### Responsive Tables

- `Sources/Mica/Features/Workbench/WorkbenchDataShared.swift:38` eagerly accepts
  full, compact, and stacked view trees. Each page invalidation therefore pays to
  describe multiple large Table candidates even though only one is mounted.
- `Sources/Mica/Features/Workbench/WorkbenchDataShared.swift:163` combines
  selectable text, vertical `fixedSize`, and partially flexible row geometry.
  Repeated scrolling continues ideal-size and selection hit-region work.
- Corrective boundary: resolve one width mode at the page root, build one native
  Table, keep rows single-line and fixed-height, and preserve complete selectable
  values in the same-window inspector.

### Overview And Topology

- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:112` owns the page's
  vertical ScrollView, while `WorkbenchDashboard.swift:1155` gives topology a
  nested two-axis ScrollView. Both compete for vertical gestures.
- `WorkbenchDashboard.swift:1258` synchronously walks all edges, nodes, and
  labels in one full-size Canvas. Clipping happens after the traversal.
- `WorkbenchDashboard.swift:1336` adds a full-size hit layer and
  `WorkbenchDashboard.swift:1368` materializes the complete accessibility path
  tree.
- `WorkbenchDashboard.swift:505` and `:648` create per-sample chart marks;
  shared hover state at `:710` can invalidate both charts.
- Corrective boundary: let the page own vertical scrolling, keep topology
  horizontal-only where needed, render stable viewport bands, and split base
  drawing, highlights, hit testing, and accessibility.

### Management

- `Sources/Mica/Features/Workbench/WorkbenchManagement.swift:22` already knows
  the root width.
- Repeated rows still use `ViewThatFits`, including
  `WorkbenchManagement.swift:169` and `:3562`, repeatedly measuring horizontal
  and vertical candidates during scrolling.
- Corrective boundary: resolve one small width-mode enum at the root and pass it
  into repeated rows.

### Proxy Scrolling

- `Sources/Mica/Features/Workbench/WorkbenchProxies.swift:478` stores the
  interaction scheduler in root state.
- Scroll events at `WorkbenchProxies.swift:689` and `:1349` can invalidate large
  root subtrees on first phase transitions.
- Corrective boundary: keep phase tracking local to each scrolling subtree and
  hold scheduling mechanics in a non-observed reference.

## Live Amplification

### Connections

- `Sources/Mica/App/AppModel.swift:82` exposes `connectionsCatalog` as one
  observable value.
- `Sources/Mica/App/AppModelLiveSessionRuntime.swift:383` assigns the whole
  catalog. `Sources/Mica/Features/Workbench/WorkbenchConnections.swift:699` then
  rebuilds the page projection, producing a second invalidation.
- `WorkbenchConnections.swift:491` still loops/copies the current rows when
  rebuilding cache state, and `:543` repeatedly sorts on live metric changes.
- Corrective boundary: separate structural IDs/static material from keyed metric
  state and freeze live-metric ordering during interaction.

### Logs

- `Sources/Mica/App/DashboardSessionModels.swift:307` publishes append/drop
  delta information.
- `Sources/Mica/Features/Workbench/WorkbenchLogs.swift:310` and `:355` expand
  that information back into full ring and row projection work.
- Corrective boundary: apply append/drop delta directly to a page-owned indexed
  presentation store and format only appended rows.

### Workspace Persistence

- `Sources/Mica/Features/Workbench/WorkbenchLogs.swift:948` changes Follow
  Newest on the first scroll transition.
- `Sources/Mica/Features/Workbench/WorkbenchWorkspaceStore.swift:351` performs workspace
  encoding/write work from main-actor-owned state.
- `Sources/Mica/Features/Workbench/WorkbenchWorkspaceStore.swift:437` persists
  `scrollAnchorID`, but the current
  presentation does not consume it as a real scroll position.
- Corrective boundary: separate selection from viewport, bind a real anchor, and
  encode immutable snapshots off the main actor with bounded idle coalescing.

## Excluded Explanations

- The defect is not solely caused by controller traffic because it reproduces
  while disconnected and static.
- It is not solely first-time lazy construction because repeated scrolling also
  lags.
- Workbench does not contain enough explicit scroll animation to make disabling
  animation a complete fix.
- Removing text selection, truncating business data, reducing topology paths, or
  changing controller order is not an acceptable optimization.

## Recommended Architecture

Use the approved unified native SwiftUI approach:

1. Establish static scroll and invalidation measurements.
2. Give each destination one vertical owner and each data page one Table.
3. Stabilize row geometry while preserving text selection.
4. Narrow page observation and carry keyed/delta updates to presentation.
5. Layer and viewport-bound complete topology rendering.
6. Move workspace encoding away from active scrolling.
7. Verify static behavior before live publication stress, then collect one
   concentrated final Instruments comparison.
