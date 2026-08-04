# Workbench Acceptance Recovery

## Goal

Re-establish acceptance for Mica's native macOS workbench by replacing the
current visually disordered page compositions, removing confirmed global
scroll/update bottlenecks, and making controller-session and individual
connection lifecycle states truthful and unambiguous.

The result must remain a native SwiftUI macOS 27 pro tool over the existing
SparkXie-aligned controller data contract. This task does not preserve a page
composition merely because it belongs to the preceding rebuild.

## Background

The user supplied 14 real-runtime screenshots under `tmp/codex/picture/` and
rejected the current result. The screenshots cover Overview, Proxies,
Connections, Logs, Rules, Controllers, Configuration, Actions, Diagnostics,
and Settings. Sources was not included in the screenshot set and still requires
the same audit during implementation.

Confirmed visual defects include:

- inconsistent density: oversized empty regions coexist with walls of tiny data;
- page commands, counters, badges, table headers, and details compete without a
  clear primary hierarchy;
- Proxies lays out 62 selectors as a card wall; long selected node names change
  selector height and break row rhythm, while an expanded group can show a very
  large node matrix;
- Overview's lower latency, rule, connection, and metadata sections dominate the
  page and make live information difficult to scan;
- Logs repeats timestamps and log classifications while displaying 2,000 rows;
- Controllers, Configuration, Actions, Diagnostics, and Settings use only a
  small portion of the available canvas and leave unrelated empty space;
- raw localization placeholders or semantic keys are visible (`%@`,
  `diagnostics.runtime_operations_count`), sentinel dates appear as 1970, and
  missing delay values appear as healthy `0 ms`;
- the interface can still say it is live while the visible dataset consists of
  retained closed connections or an old controller snapshot.

Confirmed performance and lifecycle evidence:

- `BoundedLogBuffer` retains 2,000 entries and removes from the front of an
  `Array` after reaching its budget, causing repeated element shifts
  (`Sources/Mica/App/SessionBuffers.swift:4-38`).
- Every incoming controller log publishes the complete retained log array
  (`Sources/Mica/App/AppModelLiveSession.swift:863-867`), after which the Logs
  page rebuilds and filters its full projection for every revision
  (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:3345-3359` and
  `3690-3702`). This processing occurs on the main actor and can degrade every
  destination even when Logs is not visible.
- General dashboard mutation still synchronizes every domain catalog. The
  synchronization avoids Observation writes but performs full-array equality
  work across groups, connections, logs, routing, and insight
  (`Sources/Mica/App/AppModel.swift:315-386`).
- Proxies recomputes its full group projection whenever the complete policy
  catalog changes and initially reveals 48 members per expanded group
  (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:41-47`, `766-816`,
  and `1432-1482`).
- `leaveLiveSession()` invalidates stream/session buffers but does not clear or
  reclassify the published dashboard snapshot
  (`Sources/Mica/App/AppModelLiveSession.swift:76-87`).
- Overview deliberately combines active and retained closed connections in
  session totals and its connection selector
  (`Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:3411-3471`).
- Closed connection retention is currently bounded at 1,000 entries / 16 MiB
  (`Sources/Mica/App/SessionBuffers.swift:51-53`). The approved replacement is
  current-session history capped at 200 rows and 30 minutes, whichever expires
  first, exposed only through Connections' explicit Closed surface.

## Requirements

### R1. Coherent Workbench Information Architecture

- Audit and redesign all eleven destinations as one native macOS pro-tool
  system rather than eleven unrelated compositions.
- Preserve all eleven direct sidebar destinations, grouped as Workbench
  (Overview, Proxies, Connections, Logs, Rules, Sources), Controller Management
  (Controllers, Configuration, Actions, Diagnostics), and Application
  (Settings). Do not add a second navigation level merely to shorten the list.
- Make sidebar rows and selection treatment compact and restrained; page
  disorder must be solved in the content architecture rather than by hiding
  destinations.
- Each page must have one obvious primary task, a restrained command region,
  compact secondary status, and progressive disclosure for detail.
- Avoid both decorative card walls and unbounded full-width text/form deserts.
- Use native sidebar, toolbar, tables, lists, inspectors, forms, SF Symbols, and
  system-provided Liquid Glass only in navigation/control chrome.
- Preserve complete controller-reported business values and source order.

### R2. Scalable Data Surfaces

- Proxies uses a constrained master-detail workspace instead of a card wall or
  full-width inline expansion. A 280-340 pt ordered group directory drives a
  720-900 pt node workspace.
- Several groups may remain open as workspace tabs with independent filter and
  selection state, but only the active tab's node collection is rendered.
- Proxies must preserve controller group/member order, GLOBAL-last presentation,
  inline node selection/testing/filtering, and controller-reported SMART usage
  labels.
- A full-width inline node expansion is rejected because it becomes excessively
  wide in a large desktop window and weakens scanability.
- Long policy or node names must not change the selector grid's structural row
  height or make adjacent groups misalign.
- Connections, Logs, Rules, and Sources must remain useful at their real data
  sizes through stable identities, bounded/virtualized presentation, cached
  projections, and detail shown on demand.
- Connections, Logs, Rules, and Sources share a compact data-browser contract:
  a restrained count/filter/action bar, fixed-height scan-oriented rows, and a
  native inspector presented only for the selected row.
- Data-browser rows show only the fields needed for rapid comparison. The
  inspector exposes all reported fields as complete, selectable values; moving
  detail out of the row is not permission to truncate or hide business data.
- Repeated KPI/readout strips are removed from these pages unless a page-specific
  metric is required to perform its primary task.
- Page-local workspace state is keyed by controller and destination. During the
  same controller session, destination changes preserve search, filter, sort,
  scroll position, inspector selection, and Proxies workspace tabs/filters.
- Controller switching restores that controller's independent workspace state
  or defaults on first use. Explicit session end or controller deletion clears
  data-bound selections, scroll anchors, and opened node workspaces without
  affecting application preferences.
- Overview must summarize live state. Historical/diagnostic detail must not
  overwhelm its first or second viewport.
- Overview is a focused live dashboard containing controller state/last update,
  upload, download, active connection count, memory, one primary traffic chart,
  one compact memory chart, a short latency-anomaly list, a short top-active-
  connection list, a compact rule-hit summary, and a scroll-bounded active-
  connection topology viewport, followed by a compact network-information facts
  section.
- Overview topology uses only current active connections and real reported route
  chains, and all current active connections are admitted without Top-N or
  pagination truncation. Every admitted connection must render its complete
  controller-reported path from source through every reported rule/policy hop to
  the final node; this includes every non-blank element of the reported `chains`
  collection rather than only its first and last elements. Identical semantic
  stages may reuse shared source, rule,
  policy, or final-node vertices to reduce drawing work, but no route stage or
  connection path may be omitted or replaced by ellipses. Historical
  connections and non-route connection fields remain on Connections.
- Overview network information remains visible but is reorganized as an aligned,
  bounded facts grid with complete reported values rather than an uncontrolled
  field wall.
- Overview does not contain closed connections, the complete latency catalog,
  the complete rule-hit catalog, or a raw connection selector/inspector.
  Complete detail remains fully available in Proxies, Connections, Rules, and
  Diagnostics through direct navigation.
- Management/settings pages must use deliberate readable widths and adaptive
  grouping instead of leaving most of a large window functionally empty.
- Controllers uses a compact master-detail management layout: an ordered
  controller list plus selected-controller status, test result, and edit actions.
- Configuration and Settings use native grouped forms inside a 960-1100 pt
  management canvas, with at most two columns at wide widths and one column when
  compact.
- Actions uses one capability-grouped vertical command list. Diagnostics uses a
  concise summary followed by on-demand disclosure groups rather than rendering
  the entire report hierarchy eagerly.
- Intentional outer whitespace is acceptable on an ultra-wide window; controls,
  forms, and command descriptions must not stretch merely to fill the canvas.

### R3. Global Performance Correction

- Replace per-log full-array copy/equality/filter publication with a bounded,
  append-oriented mechanism and coalesced UI delivery.
- Remove front-removal hot paths from bounded buffers.
- Log transport ingestion remains lossless within the existing 2,000-entry /
  8 MiB retention budget, implemented as a true ring/deque-style buffer.
- While Logs is visible, publish one coalesced UI snapshot at most every 200 ms;
  Follow Newest scrolls at the same maximum cadence. While Logs is hidden, log
  ingestion continues but no log-table projection or SwiftUI row publication is
  performed. Opening Logs reads the latest retained snapshot immediately.
- Outside Logs, transport ingestion remains independent from presentation:
  traffic values/charts publish at most 4 Hz, active connections and topology at
  most 2 Hz, and memory at most 1 Hz. Policy groups, rules, sources, and
  configuration publish only on real domain changes, completed operations, or
  explicit refresh.
- Hidden destinations do not compute their expensive projection; entering a
  destination immediately consumes the latest retained domain snapshot. User-
  initiated mutations publish their outcome immediately rather than waiting for
  a cadence timer.
- Chart downsampling selects only real received samples and never synthesizes
  intermediate points.
- The retained Overview connection topology is interactive rather than a static
  decoration. Hovering highlights a complete route path and exposes compact
  details; selecting a source, rule, policy, or node filters/highlights matching
  paths; selecting an active connection highlights its complete chain. An
  explicit `Open in Connections` action navigates to and selects the
  corresponding connection. Performance controls may virtualize drawing,
  suspend animation, cache layout, or reduce update cadence, but may never
  truncate an admitted connection's route or remove intermediate hops.
- Topology implementation must choose the lowest-overhead native rendering path
  proven by profiling. Graph normalization and layout are revision-keyed and
  computed away from SwiftUI `body`; stable nodes and paths are reused between
  updates, only changed graph data is rebuilt, rendering is coalesced to the
  approved connection cadence, and continuous decorative animation is absent.
  A single-pass canvas-style renderer is preferred over a large hierarchy of
  individually observed SwiftUI node and edge views when profiling confirms the
  latter would cost more.
- Publish only the domain that changed; a connection frame must not compare the
  complete logs or policy catalog, and a log entry must not rebuild other pages.
- Expensive projections must be revision-keyed, cached, and computed outside
  SwiftUI `body`; row views receive only the values they render.
- Large expanded groups and 2,000 retained logs must scroll and switch tabs
  without sustained main-thread starvation.
- Final performance acceptance requires an Instruments SwiftUI/Time Profiler
  trace using the real dataset represented by the supplied screenshots.

### R4. Truthful Session And Connection State

- Distinguish controller session stopped/disconnected/failed/stale from an
  individual network connection becoming closed.
- A stopped controller session must never display `实时中`, live controls, or a
  current timestamp as though new data is arriving.
- Closing an individual connection must remove it immediately from Active and
  from Overview's live connection selector/statistics.
- A closed individual connection may remain only in an explicitly historical
  Closed surface for the current controller session. It must never be mixed
  into live totals and must have a user-visible clear action.
- A temporary controller transport failure keeps the last successful snapshot
  as read-only stale data with an explicit disconnected state and last-received
  timestamp. Commands that require a live controller are disabled.
- On reconnect, the stale snapshot remains explicitly read-only while the
  controller is reconnecting. The UI returns to live state only when the first
  complete, valid replacement snapshot is available, at which point the
  replacement is applied atomically so stale and fresh domains cannot mix.
- An explicit controller switch, controller deletion, or session end clears the
  previous session's operational snapshot and retained closed history.
- Current-session closed history keeps at most 200 rows and at most 30 minutes;
  whichever limit is reached first evicts the oldest rows.

### R5. Data And Localization Correctness

- No visible `%@`, `%lld`, semantic localization key, duplicated translated/raw
  label, or untranslated implementation term.
- Missing delay is unavailable, never healthy `0 ms`; a reported zero remains
  visible only when the controller actually reports zero.
- Missing timestamps do not render Unix epoch dates.
- Zero byte/rate formatting remains `0 B` / `0 B/s`.
- Active UI remains full-visible; only credentials and unsafe raw export payloads
  retain the existing export boundary.

### R6. Scope And Constraints

- Native SwiftUI/macOS 27 only; do not introduce an AppKit parallel UI.
- Do not add OpenSurge capabilities or change the controller protocol contract
  merely to solve presentation problems.
- A third-party package may be added only if repository review proves a mature
  library is necessary for correctness or performance and the dependency rules
  in `AGENTS.md` are satisfied.
- No production mock data, local-core management, system proxy changes, or real
  controller mutation during automated verification.

## Acceptance Criteria

- [ ] All eleven destinations pass one consistent visual audit at wide and
      compact window sizes, in light and dark appearance and all font scales.
- [ ] The supplied real dataset (62 policy groups, a group with about 798 nodes,
      2,000 retained logs, and dozens of connections) remains responsive during
      tab switching, scrolling, policy expansion, filtering, and selection.
- [ ] Instruments evidence shows no sustained main-actor starvation from log
      ingestion, domain publication, row projection, or programmatic scrolling.
- [ ] Proxies preserves controller order, GLOBAL-last presentation, multi-expand,
      inline filtering, and direct node switching without row-height collapse or
      full-catalog rebuilds for unrelated updates.
- [ ] Overview topology admits every current active connection and preserves its
      complete reported source-to-final-node chain. Shared semantic vertices are
      permitted, but no route stage or connection path is hidden or elided.
- [ ] Profiling confirms topology graph normalization, layout, and drawing do not
      cause sustained main-actor starvation at the real active-connection size.
- [ ] Closing an active connection removes it from Active and Overview live data
      immediately; any retained row appears only in an explicitly historical
      surface according to the approved retention decision.
- [ ] Controller session stop/disconnect removes live indicators and disables
      live commands immediately; old snapshots follow the approved stale-data
      decision and cannot be mistaken for current data.
- [ ] Reconnection preserves a clearly labeled read-only stale snapshot until a
      complete valid replacement snapshot atomically restores live data; no
      mixed stale/fresh dashboard is observable.
- [ ] No screenshot exposes localization placeholders/keys, 1970 sentinel dates,
      fabricated `0 ms`, repeated duplicate labels, or `Zero KB` formatting.
- [ ] Source verifier, localization JSON validation, HIG contrast/target audit,
      Swift build, and all tests pass after the complete implementation.
- [ ] Runtime screenshots and performance traces are captured only after all
      page/state/performance work is integrated, not after each small edit.

## Out Of Scope

- Adding controller capabilities that do not already exist in the Mica/SparkXie
  aligned data contract.
- Bundling, downloading, starting, or supervising a proxy core.
- App Store, DMG, Sparkle, signing, notarization, or release work.
- Preserving compatibility with the rejected Workbench page composition.
