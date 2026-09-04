# Research: Overview Topology Visual Density Redesign

- Query: Audit the user-reported "too ugly" Overview topology screenshot and propose the smallest coherent redesign grounded in the current implementation.
- Scope: internal, with existing Apple-platform guidance
- Date: 2026-09-04

## Findings

### Bottom Line

The screenshot is not primarily a palette failure. Three independent layout
rules amplify one another:

1. the graph always expands to the complete available width;
2. a sparse graph always reserves a 680-920 point flow area and then scales its
   ribbons upward to fill that area;
3. every node label remains primary text above those ribbons, including while a
   path is selected.

That combination produces very long routes, oversized gray/accent slabs, and a
wall of equally prominent labels. The correct repair is a visual-scale and
focus-hierarchy revision. It must not remove controller data, cap admitted
paths, reorder controller records, or replace the topology with summary data.

### Screenshot Evidence

- The selected teal trajectory and several neutral routes read as broad blocks
  rather than directional links. Their area dominates the labels and node bars.
- The final-outbound column is pushed to the far edge of a very wide canvas,
  leaving long, low-information ribbon spans through the center.
- Labels sit directly over crossing ribbons. The text is readable in isolation,
  but all labels use the same bright weight, so selection does not establish a
  useful foreground/background hierarchy.
- Several reported names are tail-truncated (`DomainSuffix`, `GeoSite`, and
  outbound names). This is intentional fitted-label behavior, not evidence that
  the underlying controller value was lost.
- The lower IPv6 source is cut by the screenshot boundary. Current code grows
  the graph with the densest column and delegates vertical movement to the one
  Overview scroll owner, so the screenshot alone does not prove product-level
  vertical clipping. Runtime visual inspection is still required.

### Code-Grounded Causes

#### 1. Unbounded horizontal stretching

`OverviewTopologyLayoutBuilder` sets `graphWidth` to the maximum of the measured
panel width and the long-chain minimum-width floor. There is no preferred or
maximum column step, so a wide window always pushes the first and last columns
to opposite sides (`Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift:1062`).
The 168-point minimum correctly protects long chains and horizontal scrolling
(`WorkbenchOverviewTopology.swift:878`); it should remain. What is missing is a
wide-window preferred step.

#### 2. Sparse flow is forced to become visually massive

The view requests `availableWidth * 0.56`, clamped to 680-920 points
(`Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift:240`).
The layout then derives `valueScale` from all of that available height
(`Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift:1052`). Because
there is no upper scale bound, sparse graphs are inflated until they fill the
reserved area. `edge.width = flow * valueScale` then turns an already logarithmic
count into the very thick bands visible in the screenshot
(`WorkbenchOverviewTopology.swift:1206`).

This is the main defect. The logarithmic count projection itself remains sound:
`log10(count + 1) * 10` preserves a monotonic, compressed traffic hierarchy
(`WorkbenchOverviewTopology.swift:866`).

#### 3. Labels compete with the data layer

Each nonterminal label rectangle occupies the space immediately after its node
bar, which is also the outgoing ribbon corridor
(`Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift:1107`). The
dedicated system-text layer is correct for performance and font rendering, but
every label is always `textPrimary` and one line
(`Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift:1196`). It
does not distinguish default, related, selected, or dimmed nodes.

The current minimum 20-point node height and 8-point gap prevent most geometric
label-label overlap (`WorkbenchOverviewTopology.swift:885`), but that minimum is
implemented by increasing the global flow scale. Thus collision avoidance is
being paid for with oversized ribbons.

#### 4. Opacity compounds at intersections

Default ribbons use two 45% column tints, status ribbons use 70%, and the active
trajectory uses 85% accent
(`Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift:1535`).
These values are individually defensible for thin bands, but intersecting thick
bands accumulate into the gray and teal slabs shown in the screenshot. The
selected-node highlight can also contain many related paths, so a high-cardinality
node legitimately produces a broad accent subgraph rather than one narrow path.

#### 5. Interaction and performance foundations are already good

- Hover and pin are separate states, and repeated pointer movement over the same
  target does not republish (`WorkbenchOverviewTopology.swift:218`, `:272`).
- Highlight membership is cached by structure and selection
  (`WorkbenchOverviewTopology.swift:188`).
- Hit testing uses a spatial index and gives visible node bars priority
  (`WorkbenchOverviewTopology.swift:688`, `:1266`).
- Long-chain selection reveal uses indexed geometry and respects Reduce Motion
  (`WorkbenchOverviewTopologyView.swift:692`).
- The graph retains one asynchronous opaque Canvas per render band, while text
  stays in the system pipeline (`WorkbenchOverviewTopologyView.swift:992`).
- Policy-node pinning already opens the complete real-field workspace inspector;
  hover never initiates network work (`WorkbenchOverviewTopologyView.swift:387`).

These mechanisms should be preserved rather than replaced.

## Recommended Rendering And Layout Contract

### A. Compact the graph without making it small

Use these starting constants and validate them in light/dark screenshots before
final tuning:

- retain `minimumColumnStep = 168` for long-chain readability;
- add `preferredMaximumColumnStep = 320`;
- reduce the sparse requested flow height to `availableWidth * 0.36`, clamped to
  `480...680` points;
- reduce the visible node bar width from 20 to 12 points while retaining the
  existing 28-point invisible pointer acquisition size;
- retain the 8-point node gap and existing 40-point column header.

Width should resolve as:

```text
minimumWidth = insets + nodeWidth + 168 * (columnCount - 1)
preferredWidth = insets + nodeWidth + 320 * (columnCount - 1)
graphWidth = min(max(availableWidth, minimumWidth), preferredWidth)
```

The existing outer frame already centers a graph narrower than the panel. A
long chain still overflows horizontally at the 168-point floor, while an
ultrawide window no longer stretches ordinary routes indefinitely.

### B. Cap visual flow expansion while preserving ratios

Keep the logarithmic `OverviewTopologyFlowScale` and a single graph-wide scale,
but cap that scale at `4.0` pixels per flow unit. At that cap:

- one connection is about 12 points;
- nine connections are 40 points;
- 99 connections are 80 points.

All edge ratios remain exact within the graph. Dense columns can still grow the
canvas, but sparse data no longer expands merely to consume reserved height.
Keep the existing 1.5-point drawing floor and 10-point edge hit tolerance.

Do not independently clamp each edge to a common maximum. Per-edge clamping
would destroy aggregation ratios and break packed node/edge geometry. The cap
must apply once to the global `valueScale`.

### C. Lower background ink, strengthen focus

Recommended initial alpha hierarchy:

| State | Ribbon treatment |
|---|---|
| Default | source-to-target tint gradient at 0.24 |
| Reported status | semantic status color at 0.52 |
| Active trajectory | accent at 0.82 |
| Non-active while selected | existing explicit neutral mist, approximately 0.10-0.14 |

Keep full-width closed ribbons and the current status/accent priority. Width
continues to encode the real aggregated count; opacity establishes focus. Under
Increased Contrast, raise default/status/dimmed alpha rather than substituting
new hues. In grayscale, the active path must remain distinguishable through the
large opacity difference, not color alone.

### D. Give labels a hierarchy without hiding data

- Default node labels use `textSecondary`, not `textPrimary`.
- Nodes on the active highlight get a primary, medium-weight duplicate in a
  small focus-only text layer; unrelated labels remain static and do not need to
  re-style on every hover.
- Keep system tail truncation inside the existing geometry rectangle. Do not
  rewrite reported names, abbreviate controller values, or use a character cap.
- The complete exact value remains in hover help, expanded path rows,
  accessibility, and the pinned inspector.
- Do not add a rounded label chip, glow, shadow, or glass backing. Lower ribbon
  opacity supplies the necessary contrast without turning every node into a
  card.

The focus-only overlay should iterate only highlighted node IDs and use the
existing O(1) `nodeGeometryByID` lookup. It must not make the static label layer
observe high-frequency metrics or rebuild all topology labels on pointer motion.

### E. Hover and pinned detail behavior

Do not restore the deleted node-adjacent floating/holographic HUD. It would
cover neighboring paths, require collision-placement logic, and create another
content card over the densest part of the graph.

Instead:

- hover keeps native `.help`, but its value should combine the existing exact
  `selectionLabel` and factual `selectionDescription` (role/count or route);
- click keeps the current pin behavior and visual emphasis;
- a pinned policy node keeps opening the workspace inspector, which already owns
  the complete controller-field composition;
- Escape/blank activation keeps clearing selection; keyboard path stepping and
  native context-menu mirrors remain unchanged.

This gives hover a useful two-line summary and pin a durable full-detail surface
without adding layout movement or overlapping UI.

### F. Accessibility and appearance

- Keep the opaque content surface; Reduce Transparency requires no alternate
  composition.
- Keep existing Reduce Motion behavior for selection reveal and finite state
  animation.
- Pass Increased Contrast into the band's equatable render input so only an
  actual appearance change redraws it.
- Preserve the bounded 32-item accessibility windows, complete traversal,
  selected traits, and direct Connections/Proxies navigation.
- Validate all four Mica font scales. A smaller node bar may not reduce the
  label row pitch below the resolved label height plus the 8-point gap.

## Minimal Implementation Boundary

- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift`
  - add the preferred maximum column step;
  - cap global flow scale;
  - reduce visible bar width while preserving hit acquisition;
  - expose an O(1) focused-node geometry projection if the existing lookup is
    insufficient for the focus label layer.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift`
  - change sparse-height request;
  - apply the revised alpha hierarchy;
  - make static labels secondary and render focus-only primary labels;
  - enrich native hover help with existing factual projection text;
  - consume Increased Contrast without changing topology data.
- `Sources/Mica/Design/MicaTheme.swift`
  - only if the alpha hierarchy is promoted to adaptive topology tokens;
    do not add a new decorative palette.
- `Tests/MicaTests/WorkbenchOverviewPerformanceTests.swift`
  - pin minimum/maximum column-step behavior at narrow, normal, and ultrawide
    widths;
  - verify sparse scale cap and exact within-graph ratios;
  - verify all node labels retain complete source strings and stable geometry;
  - verify hover help uses label plus description and the floating HUD remains
    absent;
  - retain 2,000-path band, hit-index, AX-window, and metrics-only invalidation
    coverage.
- `scripts/verify-real-controller-source.mjs`
  - replace the obsolete 680-920 and always-full-width assertions;
  - require the scale cap, preferred maximum step, native help, single Canvas,
    bounded AX, and no custom content glass/HUD.
- `.trellis/spec/frontend/workbench-ui-contract.md`
  - update the implemented geometry/alpha contract after visual acceptance.

`ConnectionTopologyModel.swift`, controller adapters, DTOs, live cadence, path
admission, workspace ordering, localization catalog, and dependencies do not
need to change.

## Verification Matrix

1. Pure geometry fixtures: 3, 5, and 7 columns at 640, 1000, 1600, and 2400
   points; assert the 168-point floor, 320-point preferred ceiling, centering,
   overflow, and no label-rectangle overlap.
2. Flow fixtures: counts 1/9/99 plus fan-in/fan-out; assert global scale <= 4,
   exact ratios, packed edge centers, drawing bounds, and hit-index locality.
3. Visual states: idle, hover node, hover edge, pinned path, pinned shared node,
   and reported warning/error in light/dark and Increased Contrast.
4. Accessibility: standard/extra-large text, Reduced Motion, grayscale, bounded
   VoiceOver pages, and exact full-name exposure despite visual truncation.
5. Performance: retain one opaque asynchronous Canvas per band; compare two
   Release benchmark runs for topology layout/presentation and verify telemetry
   revisions still cause zero topology reconstruction or label redraw.
6. Runtime acceptance, only after explicit permission: capture the same real
   controller topology at the same window size before/after and inspect the
   bottom edge to distinguish actual clipping from the screenshot crop.

## Files Found

- `Sources/Mica/App/ConnectionTopologyModel.swift` - complete, ordered topology
  admission and path/node/edge identities.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift` - graph
  normalization cache, interaction/index, geometry, banding, and hit index.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift` -
  topology composition, Canvas/text/hit layers, hover/pin, inspector sync, AX.
- `Sources/Mica/Design/MicaTheme.swift` - semantic surfaces, text, accent,
  status, column tints, and dimmed-edge token.
- `Tests/MicaTests/WorkbenchOverviewPerformanceTests.swift` - layout, scaling,
  complete topology, viewport, AX, rendering, and source-contract tests.
- `Tests/MicaTests/ConnectionTopologyTests.swift` - complete connection/path
  normalization and ordering tests.
- `scripts/verify-real-controller-source.mjs` - durable source assertions for
  the topology and Workbench contract.
- `.trellis/tasks/08-23-overview-flow-ribbons/{prd,design}.md` - provenance for
  the current true-ribbon, tint, barycenter, and 168-point floor decisions.

## Related Specs

- `.trellis/spec/frontend/workbench-ui-contract.md:200` - Overview is a
  full-width monitoring canvas whose fixed core includes complete topology.
- `.trellis/spec/frontend/workbench-ui-contract.md:239` - Mica Ops colors,
  semantic contrast, and accent/status restrictions.
- `.trellis/spec/frontend/workbench-ui-contract.md:425` - complete topology,
  ordering, width, ribbons, labels, hover/pin, AX, and performance contract.
- `.trellis/spec/frontend/live-session-controller-contract.md` - selected
  generation, narrow publication, and stale-data ownership.

## External References

- Apple Human Interface Guidelines, Layout:
  https://developer.apple.com/design/human-interface-guidelines/layout
- Apple Human Interface Guidelines, Color:
  https://developer.apple.com/design/human-interface-guidelines/color
- Apple Human Interface Guidelines, Accessibility:
  https://developer.apple.com/design/human-interface-guidelines/accessibility
- SwiftUI `Canvas`:
  https://developer.apple.com/documentation/swiftui/canvas

No new third-party dependency or external graph engine is warranted. The
current geometry/index/render-band architecture already supports the proposed
repair.

## Caveats / Not Found

- The screenshot does not contain a measurable light-mode or Increased Contrast
  sample, so the proposed alpha values are starting points, not visually accepted
  tokens.
- Static inspection cannot prove that the lower row is clipped by Mica rather
  than by the screenshot or Overview scroll position.
- The active task's older PRD says not to redesign the topology, but the user's
  newer explicit rejection supersedes that visual assumption. Product code and
  the durable UI contract should change together only after the main session
  accepts this revised scope.
- This research changed no product code, tests, task plan, or specification.
