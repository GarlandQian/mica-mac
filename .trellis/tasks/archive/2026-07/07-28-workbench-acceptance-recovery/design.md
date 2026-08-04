# Technical Design: Workbench Acceptance Recovery

## Design Decision

Rebuild the Workbench presentation and publication path around three rules:

1. Transport ingestion is independent from visible SwiftUI publication.
2. Each destination observes only its own domain and computes expensive
   projections only while visible.
3. Active UI shows controller truth completely, while layout and rendering use
   bounded viewports, stable identities, caching, and native virtualization.

The controller protocol, DTOs, capability matrices, authentication, and remote
operations remain unchanged. This task replaces presentation/state plumbing and
the six existing Workbench files; it does not add a local core or new controller
capabilities.

## Architectural Boundaries

### Ingestion Layer

`ControllerSession` remains the generation-owned operational store. REST,
WebSocket, Surge polling, and sing-box gRPC producers write real received values
into session-owned buffers and endpoint caches after validating controller ID
and generation.

High-frequency producers must not assign observable Workbench collections
directly. They mark the affected domain dirty and notify a presentation
coordinator.

### Presentation Coordinator

Add one `@MainActor` session presentation coordinator owned by `AppModel`. It
has these responsibilities:

- know the currently visible `WorkbenchDestination`;
- coalesce traffic, memory, connection, topology, and log publication to their
  approved cadences;
- publish only the domain whose raw revision changed;
- flush the latest retained domain immediately when its destination becomes
  visible;
- cancel all scheduled work when controller ID or generation changes;
- stage reconnect data and atomically commit a complete replacement snapshot.

The coordinator uses one scheduled task per cadence class, not one task per
event. An incoming event never cancels and restarts a pending timer. This avoids
the steady-stream starvation pattern already prohibited for Follow Newest.

### Published Domains

Keep field-granular observable state, but make it authoritative instead of
re-deriving every catalog after a broad dashboard mutation:

- controller metadata/configuration;
- policy groups;
- active connections and traffic totals;
- logs;
- rules and sources;
- insight summaries;
- traffic timeline;
- memory timeline;
- session phase/freshness and operation capabilities;
- current-session closed history.

`replaceDashboard(_:)` and `synchronizeDomainCatalogs()` are removed from the
high-frequency path. Mutations publish through explicit domain methods. A log
append cannot compare connections, groups, rules, or insight; a connection frame
cannot compare logs or policy groups.

`DashboardSnapshot` may remain as a non-observed staging/adapter value where a
backend currently projects several endpoint responses together, but it is not
the observable source of all Workbench domains and no longer owns the log
buffer.

## Session Lifecycle

### Presentation Phases

Represent the visible session lifecycle explicitly:

- `stopped`: no active generation; operational domains are cleared;
- `connecting`: no complete snapshot has been published yet;
- `live`: the last complete snapshot belongs to the active generation;
- `staleReconnecting`: the last complete snapshot is retained read-only while
  transport retry is active, with its last-received timestamp;
- `partial`: a complete baseline is present but one supported endpoint is stale
  or unavailable;
- `failedBeforeFirstSnapshot`: connection failed before any complete snapshot.

All commands derive from this shared phase and the existing capability matrix.
Commands requiring a live controller are false during `stopped`, `connecting`,
`staleReconnecting`, and `failedBeforeFirstSnapshot`. Test remains available
only where the existing controller/profile contract permits it.

### Explicit End Versus Temporary Failure

`leaveLiveSession` gains an explicit reason. Window/session end, controller
switch, controller deletion, and sleep invalidate the generation and clear:

- all published operational domains;
- visible timelines and live timestamps;
- current-session closed history;
- visible log snapshot and retained session log buffer;
- pending presentation transactions and cadence tasks;
- data-bound selection/scroll/open-workspace state when the product contract
  says the session is ended or the controller is deleted.

A retryable transport failure does not call the destructive end path. It keeps
the last committed snapshot, marks it `staleReconnecting`, freezes live
commands, and records a stable last-received timestamp.

### Atomic Reconnect Commit

Create a generation-scoped reconnect transaction. Producers write replacement
endpoint results into staging state while the old snapshot remains visible and
read-only. The baseline readiness predicate is capability-aware:

- Mihomo-family sessions require the supported identity/configuration, policy,
  and active-connection domains used to establish the Workbench baseline;
- Surge requires one internally consistent Surge control snapshot;
- sing-box requires the supported version/status/group/mode/connection baseline
  delivered by the active StartedService generation.

Only a complete valid baseline commits. The commit updates all staged domains,
freshness states, timelines required by the baseline, session phase, and
timestamp in one main-actor transaction. Optional endpoint failures are included
as explicit per-domain stale/unavailable states; they cannot silently mix old
and new values under a `live` label.

## Buffer And Cadence Design

### Log Buffer

Replace `BoundedLogBuffer`'s front-removing `Array` with a fixed-capacity ring:

- capacity: 2,000 entries;
- byte budget: 8 MiB;
- append and oldest eviction: O(1);
- monotonic raw revision;
- FIFO materialization only when a visible snapshot is published;
- clear/replace preserve deterministic order and byte accounting.

No new Swift package is required. The byte-budgeted fixed-capacity ring is small
and project-specific; adding Swift Collections only for this storage primitive
would add build/dependency cost without a material correctness advantage.

When Logs is visible, materialize at most once every 200 ms. When hidden, append
to the ring without publishing `logsCatalog` or rebuilding log rows. Opening
Logs forces one immediate snapshot. Clearing logs publishes immediately.

### Log Projection

Keep incoming order. Precompute stable row identity, normalized level, display
timestamp, and search text outside row bodies. The visible projection cache uses
`(sourceRevision, level, query, language)` as its key and applies append/eviction
deltas when possible. A full 2,000-row rebuild occurs only after replacement,
language/filter change, or cache invalidation, and runs outside SwiftUI `body`.

Follow Newest scrolls only after the coalesced visible snapshot and at the same
5 Hz maximum. It does not scroll while disabled or while the user is reading an
older position.

### Closed Connections

Replace raw retained rows with records containing the real
`ConnectionSnapshot` and a local `closedAt` receipt timestamp. Retention is:

- current controller session only;
- at most 200 records;
- at most 30 minutes;
- oldest record evicted when either limit is exceeded;
- explicit clear action available on the Closed surface.

Active rows disappear from Active and Overview immediately after confirmed
close. Closed records never contribute to Overview counts, charts, rankings, or
topology.

### Other Cadences

| Domain | Maximum visible publication | Hidden behavior |
|---|---:|---|
| Traffic values/timeline | 4 Hz | retain raw samples, no chart projection |
| Active connections/topology input | 2 Hz | retain latest frame, no table/topology projection |
| Memory/timeline | 1 Hz | retain raw samples, no chart projection |
| Logs | 5 Hz | append only, no visible snapshot/projection |
| Groups/rules/sources/config | on real revision or operation | no projection |

User-initiated mutations publish their confirmed outcome immediately. Timeline
downsampling selects real received samples only.

## Window Workspace State

Add a window-owned `WorkbenchWorkspaceStore`, separate from controller business
state. It is keyed by controller ID and destination and stores:

- search/filter values;
- sort descriptors;
- active/closed and source-kind tabs;
- selected inspector row;
- stable scroll anchor;
- Proxies opened groups, active group tab, per-group node filter, and selected
  member;
- pending cross-page navigation selection, such as Overview to Connections.

Changing destinations or switching controllers restores that key's state. An
explicit session end clears data-bound selections and scroll anchors for the
ended session; controller deletion removes the controller's state. Application
preferences remain owned only by `AppPreferencesStore`.

`WorkbenchRootView` informs the presentation coordinator of destination changes
and flushes the destination's latest domain before rendering its expensive
projection.

## Workbench Composition

The frontend remains exactly the six files required by the Workbench contract.
Old page composition and helper names are not compatibility requirements.

### `WorkbenchVisualSystem.swift`

- Keep the fixed adaptive graphite/cyan palette.
- Use semantic system foreground styles for text.
- Use 8/12/16/24-point layout rhythm, radii at 8 points or less, and stable
  44-point hit regions without multiplying geometry by font scale.
- Native Liquid Glass is limited to window/sidebar/toolbar/control chrome.
- Content sections are flat and separated; no custom content glass, gradients,
  nested cards, decorative card walls, or repeated KPI panels.
- Add shared compact command row, data-browser row, facts grid, inspector field,
  and centered content-state primitives only where they remove real duplication.

### `WorkbenchChrome.swift`

- Preserve eleven direct sidebar destinations in the approved three groups.
- Keep the controller switcher collapsed by default and observe only persisted
  profile/selection fields.
- Use the native navigation title; do not repeat controller identity in toolbar
  capsules or page headers.
- Toolbar contains only destination search where applicable and shared
  test/refresh/pause commands.
- Keep one fixed bottom status bar with truthful phase, last-received timestamp,
  and operation outcome.

### `WorkbenchDashboard.swift`

Use a centered operational canvas with a wide maximum appropriate to charts,
not an unbounded edge-to-edge layout:

1. compact session header and four live readouts;
2. one primary traffic chart plus one compact memory chart;
3. short latency anomalies, top active connections, and rule-hit summary;
4. complete active-connection topology viewport;
5. compact aligned network-information facts grid.

Overview excludes closed connections and full catalogs. Charts retain hover,
pinned selection, keyboard accessibility, and exact real sample readouts without
duplicating the same values in several modules.

### `WorkbenchProxies.swift`

Replace the selector card wall and row-attached expansion with constrained
master-detail:

- ordered group directory: 280-340 pt;
- node workspace: 720-900 pt within the centered content canvas;
- fixed-height directory rows showing group, selected node, count, status, and
  reported SMART usage summary;
- long names truncate only in the scan row and remain fully selectable in the
  active workspace;
- multiple groups can remain open as horizontal workspace tabs in controller
  order, but only the active group's nodes are rendered;
- each group keeps independent filter and selected-node state;
- the active node collection uses a virtualized fixed-height list/table rather
  than hundreds of card views;
- clicking an eligible node invokes the existing typed selection operation;
- test, fixed-selection clear, and filter controls remain inline;
- ordinary groups preserve controller order and visible GLOBAL remains last.

Filtering and node search text are cached per group revision. A change to one
group's operation state must not rebuild all 62 groups or all 798 members.

### `WorkbenchDataPages.swift`

Connections, Logs, Rules, and Sources share a compact data-browser shape:

- restrained filter/count/action row;
- native virtualized table/list with stable fixed-height scan rows;
- inspector appears only for a selected row;
- inspector exposes every reported value in full and selectable form;
- no repeated KPI strip unless required for the page's primary operation.

Connections keeps explicit Active and Closed views. Rules builds its active
connection index once per visible connection revision. Sources preserves
controller order and existing typed operations. Logs uses the ring/coalesced
projection contract above.

### `WorkbenchManagement.swift`

- Use a centered 960-1100 pt management canvas.
- Controllers is master-detail with ordered list on the left and selected
  profile/status/test/editor actions on the right; edit/delete commands align at
  the trailing edge.
- Configuration and Settings use native grouped forms, two columns only when
  there is enough readable width, one column otherwise.
- Actions is one capability-grouped vertical command list with trailing actions.
- Diagnostics starts with concise health/identity facts and creates expensive
  report sections only when their disclosure is expanded.
- Deliberate outer whitespace is retained on ultra-wide windows instead of
  stretching forms and text.

## Complete Connection Topology

### Graph Model

Replace the fixed four-layer, capped graph with a dynamic path model:

- each active connection has a stable occurrence identity and a `PathRecord`;
- a path contains source, optional rule, every reported policy-chain hop, and
  final node;
- the existing tested Mihomo chain semantics are preserved: `chains.first` is
  the final outbound and the remaining reported elements are traversed in
  reverse order from source toward that final outbound;
- blank elements are ignored, but first/last-only reduction is forbidden;
- duplicate semantic stages may share a vertex at the same role/depth;
- aggregated edges retain membership of every contributing connection path, so
  selecting one connection can highlight its full chain;
- missing source or route metadata produces an explicit non-drawable
  `routeUnavailable` path record, never a fabricated edge.

No node, edge, or connection count cap may discard a reported path. Source order
is retained for deterministic first appearance.

### Projection And Layout

Graph normalization runs off the main actor and is keyed by controller ID,
generation, and connections revision. Dynamic columns are source, rule, zero or
more policy-hop depths, and final node. The layout result contains only immutable
numeric geometry, labels, path membership, and a coarse spatial hit index.

Layout is recomputed only when graph revision or viewport size changes. Hover,
selection, and color changes reuse the cached geometry. Hit testing queries the
spatial index instead of scanning and rebuilding a path for every edge.

### Rendering

Render nodes, labels, and bands in one native SwiftUI `Canvas` pass. Do not
create an observed SwiftUI view per node or edge and do not run continuous
decorative animation. The graph has a constrained viewport with native
horizontal/vertical scrolling when its intrinsic layout is larger; scrolling
reveals all data rather than truncating it.

Hover and selection highlight every edge belonging to a path. Node/edge
selection exposes compact details. `Open in Connections` changes the existing
same-window destination and selects the matching active row through the
workspace store. Accessibility exposes path records and complete labels outside
the bitmap-like canvas.

## Localization And Data Truth

- Audit every visible string path in all eleven destinations, toolbar, status
  bar, inspector, help, menu, and accessibility labels.
- Replace interpolation patterns that can leak `%@`, `%lld`, or semantic keys.
- Parse missing/sentinel dates as unavailable before formatting; never show Unix
  epoch as a real update time.
- Preserve `nil` latency through DTO/domain/projection boundaries; only a
  controller-reported zero may render `0 ms`.
- Keep deterministic `0 B` and `0 B/s` formatting.
- Active business data remains fully visible. Export credential/raw-body
  exclusions remain unchanged.

## Dependency Decision

No new package is planned. SwiftUI `Table`/`List`, Swift Charts, Canvas,
Observation, and structured concurrency cover the required UI and rendering.
The existing gRPC/protobuf packages remain for sing-box StartedService. A new
dependency is reconsidered only if Instruments demonstrates a native boundary
that cannot be corrected locally and the repository dependency gate is met.

## Migration And Compatibility

- Preserve `MicaCore` DTO/domain contracts and typed AppModel operations.
- Replace old Workbench page composition, projections, and interaction stores
  directly; do not add compatibility wrappers for rejected concepts.
- Update the existing source verifier and tests to the new lifecycle,
  publication, topology, and layout contracts.
- Keep the six-file Workbench directory contract.
- Do not modify system networking, start a core, or contact a real controller in
  automated verification.

## Test Design

### Pure/Unit Tests

- ring buffer count/byte eviction, FIFO order, clear/replace, and revisions;
- closed-history 200-row/30-minute eviction with an injected clock;
- domain publication proves a log append changes only log revisions and a
  connection frame changes only connection/traffic revisions;
- cadence coalescing and immediate destination-entry flush with an injected
  scheduler/clock;
- hidden destinations perform no expensive projection;
- explicit session end clears operational state; temporary failure retains a
  read-only stale snapshot;
- reconnect baseline commits atomically and rejects stale generations;
- workspace state isolation/restoration/clearing;
- proxy source order, GLOBAL-last, active-tab-only member projection, filtering,
  and direct selection capability gates;
- complete topology includes every chain hop, all active path records, shared
  vertices, stable order, path membership, cancellation, and unavailable-route
  handling;
- localization placeholders, sentinel dates, missing latency, and zero-byte
  formatting.

### Integrated Verification

After the complete implementation is integrated, run one concentrated build,
test, source-contract, localization, HIG, screenshot, and Instruments cycle.
Use the real dataset represented by `tmp/codex/picture/` for manual runtime and
performance acceptance. Do not perform repeated smoke launches after every small
edit.

## Risks And Rollback

- **Publication rewrite risk:** domain state can diverge if one mutation path is
  missed. Mitigate with source-verifier coverage and revision-isolation tests.
- **Reconnect risk:** a baseline predicate that is too strict can remain stale
  forever. Keep predicates capability-aware and test success, partial failure,
  cancellation, and generation replacement for every controller family.
- **Topology risk:** complete graphs can be large. Mitigate through shared
  vertices/edges, background normalization/layout, cached geometry, spatial hit
  indexing, a single Canvas pass, and 2 Hz maximum graph refresh, never by data
  truncation.
- **Workspace risk:** stale selections can target another generation. Store
  controller ID plus generation in all mutation intents and reconcile against
  the latest domain before dispatch.
- **Visual risk:** another broad rewrite can drift between pages. Build every
  destination from the shared visual/data-browser contracts and review all pages
  together before final verification.

Rollback is file-group based: session publication/buffers, workspace/chrome,
Proxies, data pages, Overview, and management pages remain separable review
boundaries. No migration of persisted controller profiles or credentials is
required.
