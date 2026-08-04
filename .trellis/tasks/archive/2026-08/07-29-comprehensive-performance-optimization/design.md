# Technical Design: Comprehensive Performance Optimization

## Problem Restatement

Mica must continue showing complete, current controller data while preventing
high-frequency transport events and large collections from monopolizing the main
actor, invalidating unrelated SwiftUI subtrees, or rebuilding unchanged
presentation data.

## Fundamental Invariants

- Exactly one selected controller owns one live generation.
- Controller ID and generation guard every asynchronous apply and mutation.
- Controller-reported ordering and full visible business data are preserved.
- Visible `GLOBAL` remains presentation-only and last; node order is unchanged.
- Session end clears all generation-owned operational state and caches.
- Reconnect may retain the last committed snapshot only in the explicit
  `staleReconnecting` state and replaces it atomically.
- Existing 5/4/2/1 Hz visible publication budgets are ceilings, not permission
  to process every raw event on the main actor.
- UI interaction, connection errors, and confirmed mutations remain truthful;
  performance work cannot fabricate freshness by silently dropping state.
- Automated work does not contact a real controller or start a core. Real-session
  Instruments capture is deferred until the user explicitly authorizes it.

## Measurement Architecture

### Long-Lived Instrumentation

Add a small system-framework-only performance layer using `OSLog` and
`OSSignposter`. Signpost categories should cover:

- raw frame ingestion by domain;
- session snapshot/delta publication;
- connection, rule, source, log, and proxy projection;
- topology normalization, layout, hit-index build, and Canvas presentation;
- refresh lane flight, retry backoff, and transport client creation;
- workspace persistence and localization/formatter cache misses.

Signposts must contain only category names, counts, revisions, durations, and
controller kind. They must never include endpoints, credentials, URLs, node names,
rule payloads, connection IDs, logs, or raw response bodies.

Pure projection and storage types expose package-internal counters for tests:
materializations, full rebuilds, delta updates, JSON encodes, formatter creation,
topology starts/completions/cancellations, and request/client counts. Counters are
not observable UI state.

### Benchmark Harness

Keep deterministic synthetic fixtures in tests and run heavy Release benchmarks
through one explicit repository script. Ordinary `swift test` runs correctness and
small counter contracts only; heavy cases require an opt-in environment variable
or dedicated filtered command.

The harness writes disposable reports under `tmp/codex/performance/`:

- `before/` and `after/` summaries;
- median and p95 duration;
- operation/allocation proxy counters;
- scaling ratio for 1k/5k/10k connections and rules;
- full 2,000-entry log-ring append/drop behavior;
- shared-route and unique-route topology workloads;
- request and task-lifecycle traces from fake transports.

Absolute machine timings are supporting evidence. Acceptance is primarily based on
bounded operation counts and near-linear scaling so results remain useful across
developer machines.

## Runtime And State Boundaries

### Generation-Owned Runtime Actor

Introduce one generation-owned runtime/ingestion actor. It is the sole mutable
owner of high-frequency raw state:

- bounded raw logs and append/drop sequence;
- traffic and memory histories;
- ordered active-connection storage and retained closed history;
- live stream health and retry observations;
- pending per-domain revisions/deltas;
- generation-owned transport client bundle.

`AppModel` remains the `@MainActor` lifecycle and UI command owner. The runtime
actor does not become a second session authority: it is created and destroyed by
the selected generation, and every value returned to `AppModel` carries controller
ID plus generation.

The runtime actor emits immutable, `Sendable` domain publications. `AppModel`
applies those values to field-granular presentation catalogs only after validating
the current generation.

### Connection Storage And Revisions

Replace array scans in the high-frequency connection path with an ordered ID-indexed
store:

- dictionary maps stable occurrence ID to array slot;
- array preserves controller order;
- reset builds dictionary and array in one pass;
- updates use O(1) lookup;
- closes remove without repeatedly scanning the growing collection, while final
  visible order remains deterministic.

Connection publications expose separate revisions:

- `structureRevision`: membership, identity, metadata, rule, chain, source, final
  node, or ordering changed;
- `metricsRevision`: upload/download/time/rate changed;
- `trafficRevision`: aggregate traffic sample changed.

Rules connection indexing and topology depend on `structureRevision`; transfer
columns depend on `metricsRevision`. Full collection equality is not used to
discover these revisions at the publication boundary.

### Log Delta Contract

The raw log owner publishes a monotonic sequence with explicit append/drop deltas.
The presentation cache applies the delta using stable IDs and formats only new or
changed rows. It does not rematerialize the complete ring or rediscover overlap at
5 Hz.

Filtering by level/query uses a cached visible-ID projection keyed by source
sequence and filter state. `Follow Newest` remains coalesced and is disabled by
selection or user-driven scrolling exactly as the current contract requires.

### Refresh And Retry Coordinator

Replace recursive lane retry/follow-up calls with one iterative,
generation-scoped coordinator:

- one awaitable flight per lane;
- repeated manual refresh callers join or request one coalesced follow-up;
- one retained task handle per owned flight;
- bounded iterative backoff with immediate cancellation;
- startup baseline completes before steady-state polling begins;
- each endpoint has one cadence owner.

For Surge, the 1-second near-live owner is authoritative for traffic, events, and
active requests. Recent requests move to an independent lower-frequency optional
lane so they cannot block the required near-live trio. The duplicate 2-second
active-request fetch is removed and the live-session spec is updated accordingly.

Unexpected normal completion of any required Mihomo/sing-box long-lived stream is
normalized into a reconnect-worthy transport failure. Optional Tailscale behavior
remains independently capability-gated.

### Transport Reuse

Create one typed transport bundle per generation:

- one Mihomo HTTP/WebSocket client where applicable;
- one Surge HTTP client where applicable;
- one sing-box gRPC channel/adapter where applicable.

Baseline, periodic lanes, live streams, and typed mutations reuse the generation's
transport resources. Command code must not open an additional channel/session when
the active generation already owns a compatible one. Transport replacement occurs
only with generation replacement.

## Presentation Demand And Interaction Scheduling

### Visibility Demand

The window root remains the sole owner of destination visibility. Extend that
ownership with window presentation demand:

- current destination;
- window visible/occluded state;
- active interaction kind;
- latest accepted generation.

When a destination is inactive or the window is not visible, networking and raw
state continue, but expensive page projection, Chart preparation, topology layout,
and Canvas preparation stop. Returning to the page performs one latest-snapshot
flush rather than replaying intermediate states.

App deactivation or minimization does not invalidate the generation. Closing the
final main window and sleep retain their existing session-end behavior.

### Interaction Priority

Scrolling, chart dragging, and filter typing create a bounded interaction window.
During that window:

- critical state bypasses coalescing: disconnect, reconnect phase, errors,
  confirmed mutation outcomes, node selection, and cancellation;
- non-critical telemetry, rankings, topology, and table counters retain only the
  latest pending update;
- interaction end or the maximum latency boundary publishes one latest snapshot;
- no queued historical frames are replayed.

The mechanism uses explicit state and a non-restarting deadline. It is not an
unbounded debounce.

## Projection And Observation Architecture

### Narrow Catalogs

Separate unrelated observable roots:

- connection structure and metrics;
- rules and rule-hit/count projection;
- sources/providers;
- logs plus log delta sequence;
- policy groups;
- traffic/memory timelines;
- topology presentation;
- controller/session phase and command capability state.

Views observe only the smallest catalog needed for their body. Pure projection,
index, and layout types receive values explicitly and never read the SwiftUI
Environment or the full `AppModel`.

### Workspace State

Replace the single observed workspace dictionary with per-controller,
per-destination observable workspace objects. Hot interaction state remains local
to the page and persists through an equality-guarded, coalesced boundary. A search
keystroke in one page must not invalidate all mounted workspace consumers.

Session-bound selections include controller ID and generation and clear on session
end. User preferences and non-session filter choices keep their existing persistence
semantics.

### Static And Dynamic Row Data

Connections, Rules, Sources, Logs, and Proxies separate stable row material from
dynamic fields:

- stable IDs, names, metadata search text, parsed dates, and serialized additional
  fields are cached by structural/catalog revision;
- transfer counters, active counts, latency, selection, and stale state update via
  narrow dynamic revisions;
- query changes scan cached normalized text and do not re-encode JSON or parse
  dates;
- sorting applies to copied presentation indices and never mutates source order.

Overview timelines cache downsampled samples by source revision plus selected
window. Top-five lists use bounded top-K selection rather than sorting an entire
large collection when order beyond the visible subset is not needed.

## Topology Rewrite

Complete route-chain visibility remains mandatory. Optimization changes storage and
indexes, not the represented data.

### Linear Accumulation

Normalize paths once per `structureRevision`. Use array-backed node and edge tables
plus key-to-index dictionaries. Path membership is appended through the array slot
so dictionary value copying cannot repeatedly clone growing membership arrays.

The immutable result contains:

- every path and every reported stage;
- node/edge geometry inputs;
- path-by-ID;
- path IDs by node and edge;
- stable first-appearance order;
- explicit unavailable-route records.

### Layout And Hit Testing

Normalization and layout run away from the main actor and are cooperatively
cancellable inside their loops. Only one topology build is active; newer structural
revisions coalesce and the latest eventually publishes.

The hit index indexes actual node rectangles and sampled edge segments rather than
placing every edge into every grid cell of its full bounding rectangle. Selection
and hover use precomputed node/edge-to-path indexes. Hover updates are coalesced to
display cadence and reuse cached geometry.

Rendering stays one native SwiftUI `Canvas` pass. Color, hover, and selection do not
trigger graph normalization or layout.

## File And Module Split

The split follows ownership and refresh frequency. Proposed names may be adjusted
to match existing symbol ownership, but the boundaries are fixed:

### Session Layer

- keep `AppModelLiveSession.swift` as thin lifecycle/wiring extensions;
- add a generation runtime/ingestion actor file;
- add a refresh/retry coordinator file;
- add a domain publication/delta model file;
- keep controller transport implementations in `MicaCore`.

### Data Pages

Replace the monolithic `WorkbenchDataPages.swift` with:

- Connections page and connection projection/cache;
- Rules page and static/dynamic rule projection;
- Sources page and formatter/metadata projection;
- Logs page and delta/filter/follow projection;
- one small shared data-table primitive file only where behavior is genuinely
  shared.

### Overview And Topology

Replace the monolithic `WorkbenchDashboard.swift` with:

- Overview telemetry and highlights;
- topology page section/Canvas interaction;
- pure topology layout and hit-index presentation helpers where they belong in
  the UI target;
- shared dashboard formatting only when used by more than one boundary.

`WorkbenchChrome.swift`, `WorkbenchProxies.swift`, and management files are split
only if measurement or ownership analysis shows a comparable boundary. Line count
alone is not a reason.

## Persistence And Localization Follow-Up

After hot session/UI paths are stable:

- let `FileSecretStore` load/decode its map once per actor lifetime and provide a
  bulk read for startup;
- keep atomic whole-file writes and current credential semantics;
- cache canonical JSON encoders, ISO8601 parsing, byte formatting, reverse
  localization matches, and compiled templates at bounded ownership scopes;
- avoid global language-lock writes when the requested language is unchanged.

These changes remain behind correctness tests and are lower priority than the
main-actor, connection, log, topology, and refresh work.

## Dependency Decision

No new runtime package currently clears the adoption gate, but package adoption
remains open to later measured evidence.

Keep the four direct gRPC/Protobuf dependencies. Do not fork the upstream graph.
The focused Release evaluation in
`research/third-party-performance-candidates.md` found the Mica-specific indexed
array faster than `OrderedDictionary` for reset, update, and ordered batch removal,
and the fixed ring faster than `Deque` for bounded appends. Therefore do not add
`OrderedCollections`, `HeapModule`, or direct `DequeModule` use now.

Do not promote `AsyncAlgorithms` or `Atomics` into Mica application code without a
new focused benchmark: the required generation, critical-state bypass, latest-only,
and cancellation contracts are more specific than generic throttle/channel APIs,
and higher-level actor/lock ownership remains sufficient.

Do not add Alamofire, AsyncHTTPClient, or DGCharts. They replace native transport or
rendering boundaries without addressing the audited ownership/projection costs.

Do not add the Ordo One Benchmark package initially. It provides strong metrics but
adds plugins plus several transitive tool dependencies, while Mica's internal app
target types cannot be benchmarked cleanly through its executable-target model
without a wider target split. Start with the native opt-in harness; reopen this
decision only when a required metric or CI threshold cannot be implemented reliably.

Measure `swift-protobuf` with `traits: []` as an isolated build/binary experiment.
Retain that manifest change only if it produces material clean-build or release-size
improvement and all sing-box protocol/cancellation tests pass.

For any newly discovered candidate, repeat the exact-version official-source audit,
focused Release A/B benchmark, dependency/build/binary analysis, and full correctness
matrix before editing the manifest. Remove the candidate when the gain is
inconclusive.

## Migration And Compatibility

- Preserve MicaCore DTO/domain/API contracts unless a measured transport ownership
  fix requires an internal typed API extension.
- Preserve profile, preference, and credential file formats; no user-data migration
  is planned.
- Replace old hot-path state/projection implementations directly; do not add
  compatibility wrappers for removed internal concepts.
- Update Trellis specs, the project Skill references, source verifier, and
  `docs/ARCHITECTURE.md` / `docs/DEVELOPMENT.md` after final architecture settles.
- Active data remains fully visible; exports retain credential/raw-body exclusions.

## Validation Design

### Correctness

- generation rejection, explicit session clear, reconnect atomicity;
- controller/group/member order and GLOBAL-last;
- required stream completion and retry-wave ownership;
- refresh single-flight, coalesced follow-up, cancellation, and iterative backoff;
- log append/drop deltas, filters, Follow Newest, and stable selection;
- structure/metrics revision isolation;
- visibility and interaction demand latest-only publication;
- complete topology paths, shared membership, hit testing, and cancellation;
- transport-client reuse and endpoint request counts;
- bulk persistence and localization cache correctness.

### Performance Contracts

- 1k/5k/10k connection reset/update/close and row projection slopes;
- 2,000-entry log append/drop at 5 Hz with delta-proportional formatting;
- 1k/5k/10k rule static/dynamic projection separation;
- 100 groups x 1,000 proxy members with active-group-only indexing;
- shared-route and unique-route topology near-linear build behavior;
- hit-index entry growth bounded by sampled geometry rather than bounding-area
  multiplication;
- hidden and interaction-active pages perform zero or bounded expensive updates;
- startup reads each persistence file at most once;
- generation creates one transport bundle and one request owner per endpoint.

### Concentrated Final Gate

Run the complete build, ordinary tests, opt-in Release performance suite, source
verifier, localization validation, HIG checks, and `git diff --check` after all
implementation phases are integrated. Do not repeatedly launch runtime smoke after
small edits. Do not run a real controller trace until separately authorized.

## Risks And Rollback Boundaries

- **Runtime actor divergence:** prevent with one generation owner and publication
  envelopes carrying controller ID/generation. Roll back the runtime slice without
  UI file changes if atomicity tests fail.
- **Revision under-reporting:** static/dynamic split can leave stale fields. Every
  domain gets mutation-matrix tests mapping field changes to revisions.
- **Refresh rewrite:** endpoint cadence mistakes can over-fetch or stop updating.
  Fake transport request-count tests are the rollback gate.
- **Topology rewrite:** index optimization can omit paths or hits. Completeness and
  hit-test fixtures must pass before replacing the current model.
- **File split churn:** move symbols only after ownership boundaries are implemented;
  avoid simultaneous mechanical renames and behavioral rewrites when a smaller
  reviewable sequence is possible.
- **Dependency experiment:** `swift-protobuf` trait changes are isolated and dropped
  if measurement is inconclusive.
