# Implementation Plan: Comprehensive Performance Optimization

## Gate Before Code

- [x] User reviews and approves `prd.md`, `design.md`, and this plan.
- [x] Curate real implementation and review context in `implement.jsonl` and
      `check.jsonl`.
- [x] Run
      `python3 .trellis/scripts/task.py validate 07-29-comprehensive-performance-optimization`.
- [x] Start with
      `python3 .trellis/scripts/task.py start 07-29-comprehensive-performance-optimization`
      only after user approval.
- [x] Record `git status --short`; preserve every unrelated user change.
- [x] Load `mica-controller-development`, `trellis-before-dev`,
      `swiftui-expert-skill`, `swift-concurrency`, `swift-charts`, and the native
      macOS design skills relevant to any touched UI.

Do not contact a real controller, start a core, access port 9090, or modify system
network settings. Complete the implementation phases before the concentrated final
validation gate.

## Phase 0: Establish The Offline Baseline

**Goal:** Make every later performance claim comparable and reproducible.

### Work

- [x] Add privacy-safe `OSSignposter` categories and package-internal operation
      counters for the audited hot paths.
- [x] Add deterministic fixture builders for connections, rules, logs, proxies,
      timelines, topology routes, fake HTTP/WebSocket/gRPC events, and persistence.
- [x] Add an opt-in Release benchmark entry under `scripts/`; ordinary tests must
      skip heavy workloads.
- [x] Add a repeatable package bake-off path so any proposed third-party structure
      or scheduler is compared against the exact Mica workload before manifest
      adoption.
- [x] Capture source-state baseline results under `tmp/codex/performance/before/`.
- [x] Record compiler/toolchain, build configuration, fixture sizes, median/p95,
      operation counts, and known limitations.

### Focused Verification

- Counter tests must be deterministic.
- Signpost payload audit must prove no business data or credential leakage.
- Benchmark command must make no network request.

**Rollback point:** instrumentation and fixtures are independently removable and
must not change application behavior.

## Phase 1: Move Raw Ingestion Off The Main Actor

**Goal:** Stop raw high-frequency events from competing directly with SwiftUI.

### Primary Files

- `Sources/Mica/App/AppModel.swift`
- `Sources/Mica/App/AppModelLiveSession.swift`
- `Sources/Mica/App/OperationSessionModels.swift`
- `Sources/Mica/App/SessionBuffers.swift`
- `Sources/Mica/App/SessionTimelineModels.swift`
- new generation-runtime/publication model files under `Sources/Mica/App/`

### Work

- [x] Add one generation-owned runtime/ingestion actor.
- [x] Move log, traffic, memory, connection, closed-history, and live-health raw
      mutations into it.
- [x] Define immutable per-domain publication envelopes carrying controller ID,
      generation, revision, and latest snapshot/delta.
- [x] Keep UI/session controls on `@MainActor AppModel`; eliminate broad per-frame
      `ControllerSession.didSet` work from the ingestion path.
- [x] Ensure session end cancels the runtime and drops all raw/cached state.

### Focused Tests

- Generation replacement and stale-result rejection.
- 10k log/5k connection event stress without per-event main-actor publication.
- Session end clears actor state and pending publications.
- Existing pause/stale/reconnect behavior remains correct.

**Rollback point:** runtime actor plus publication envelopes must pass independently
before UI projections consume the new revisions.

## Phase 2: Rebuild Connections And Log Publication

**Goal:** Make frequent collection work proportional to actual change.

### Primary Files

- `Sources/Mica/App/DashboardSessionModels.swift`
- `Sources/Mica/App/DashboardInsightModels.swift`
- `Sources/Mica/App/SessionBuffers.swift`
- `Sources/Mica/App/AppModel.swift`
- runtime/publication files from Phase 1

### Work

- [x] Implement ordered ID-indexed active connections with one-pass reset and
      O(1) update lookup while preserving controller order.
- [x] Split connection structure, metrics, and aggregate traffic revisions.
- [x] Remove full-array equality scans used only to discover revision changes.
- [x] Publish explicit log append/drop deltas and monotonic sequence.
- [x] Refactor dashboard insights so connection-only changes do not rebuild policy,
      rule, provider, or latency aggregates; use bounded top-K selection.
- [x] Keep retained closed rows bounded and optimize only where benchmark evidence
      shows material cost.

### Focused Tests

- 1k/5k/10k reset/update/close order and scaling contracts.
- Structure-only versus metrics-only revision matrix.
- Full-ring one-entry append/evict formats only delta rows after warmup.
- No controller ordering or full-data regression.

**Rollback point:** source catalogs can temporarily adapt the new revisions to the
existing UI until Phase 4 replaces page projections.

## Phase 3: Rebuild Refresh, Retry, And Transport Ownership

**Goal:** Remove duplicate requests, recursive retry state, and avoidable clients.

### Primary Files

- `Sources/Mica/App/LiveSessionRefreshModels.swift`
- `Sources/Mica/App/AppModelLiveSession.swift`
- `Sources/Mica/App/AppModelSelectionState.swift`
- `Sources/Mica/App/AppModelSingBoxOperations.swift`
- `Sources/Mica/App/AppModelSurgeOperations.swift`
- `Sources/MicaCore/API/MihomoClient.swift`
- `Sources/MicaCore/API/SurgeHttpAPIClient.swift`
- `Sources/MicaCore/API/SingBoxGRPCClient.swift`

### Work

- [x] Implement an iterative generation-scoped lane coordinator.
- [x] Make manual refresh callers join one flight and await the coalesced follow-up.
- [x] Add a startup barrier before steady-state polling.
- [x] Reuse one typed transport bundle per generation.
- [x] Assign every endpoint one cadence owner; keep Surge active requests in the
      near-live owner and move recent requests to an independent optional lane.
- [x] Convert unexpected normal completion of required long-lived streams into a
      reconnect-worthy failure.
- [x] Reset shared backoff only after a complete reconnect baseline/stability gate.
- [x] Reuse one decoder per Mihomo receive task; simplify gRPC stream bridging only
      if task/actor benchmarks prove a material gain.

### Focused Tests

- Overlapping manual refresh joins/coalesces and keeps one task handle.
- Thousands of transient retries retain bounded task state and cancel immediately.
- Fake request recorder proves one request owner and one transport bundle.
- Slow optional Surge recent requests do not delay required near-live publication.
- Premature required stream completion cancels siblings and reconnects once.

**Rollback point:** cadence/request-count tests must pass before removing any old
lane or client construction path.

## Phase 4: Narrow Observation And Split Data Pages

**Goal:** Prevent unrelated SwiftUI invalidation and eliminate repeated row work.

### Primary Files

- `Sources/Mica/Features/Workbench/WorkbenchChrome.swift`
- `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift`
- `Sources/Mica/Features/Workbench/WorkbenchProxies.swift`
- `Sources/Mica/App/DashboardSessionModels.swift`
- new page/projection files under `Sources/Mica/Features/Workbench/`

### Work

- [x] Replace the observed workspace dictionary with narrow per-destination objects
      and coalesced persistence.
- [x] Separate Rules and Sources observable catalogs.
- [x] Build static/dynamic projection caches for Connections, Rules, Sources, Logs,
      and Proxies using the new structural/delta revisions.
- [x] Cache metadata JSON, normalized search text, date parsing, and formatter
      results at bounded ownership scopes.
- [x] Avoid whole-catalog proxy index rebuild and all-group workspace
      materialization when only the active group/query changes.
- [x] Split `WorkbenchDataPages.swift` by Connections, Rules, Sources, Logs, and a
      small genuinely shared table/projection boundary.
- [x] Preserve native `Table`/`List`, stable identity, complete visible values,
      controller order, selection, and Follow Newest semantics.

### Focused Tests

- Query-only updates perform no JSON encoding/date parsing.
- Metrics-only connection updates do not rebuild Rules static rows.
- Search/selection writes do not invalidate another destination workspace.
- Proxy catalog and active-group benchmarks preserve order and bounded indexing.
- Log selection/follow behavior survives append/drop delta updates.

**Rollback point:** split one product page at a time while shared source catalogs
remain compilable; do not combine all file moves into one unreviewable change.

## Phase 5: Visibility And Interaction Demand

**Goal:** Spend presentation work only where the user can consume it.

### Primary Files

- `Sources/Mica/Features/Workbench/WorkbenchChrome.swift`
- page entry files created in Phase 4
- `Sources/Mica/App/AppModel.swift`
- session publication coordinator files

### Work

- [x] Extend root-owned presentation demand with window visibility and active
      interaction state.
- [x] Stop inactive-page projection, Chart preparation, topology work, and Canvas
      preparation while raw session state continues.
- [x] Flush one latest consistent snapshot on destination/window activation.
- [x] Add bounded interaction-priority scheduling for scrolling, chart dragging,
      and filter typing.
- [x] Define critical states that always bypass coalescing.
- [x] Ensure no historical presentation frames replay after interaction.

### Focused Tests

- Hidden destinations execute zero expensive projections after the current flight
  is cancelled.
- Activation publishes only the latest current-generation state.
- Sustained interaction remains bounded while errors and mutation outcomes publish
  immediately.
- Scroll position, table selection, and chart pin state remain stable.

**Rollback point:** visibility and interaction scheduling are separate switches;
either can be disabled without reverting the runtime/projection improvements.

## Phase 6: Rewrite Overview And Complete Topology Hot Paths

**Goal:** Keep the interactive Overview and complete route graph without quadratic
work.

### Primary Files

- `Sources/Mica/App/ConnectionTopologyModel.swift`
- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift`
- `Sources/Mica/App/DashboardInsightModels.swift`
- new Overview/topology files under `Sources/Mica/Features/Workbench/`

### Work

- [x] Replace dictionary get-copy-append-set topology accumulation with indexed
      array tables.
- [x] Precompute path-by-ID and path memberships by node/edge.
- [x] Make layout cooperatively cancellable and latest-revision coalesced.
- [x] Replace bounding-rectangle edge indexing with sampled segment-cell indexing.
- [x] Reuse geometry for hover/selection/color changes and coalesce hover events.
- [x] Cache Overview timeline/downsampling work and bounded Top-K highlights.
- [x] Split `WorkbenchDashboard.swift` into Overview telemetry and topology
      presentation/interaction boundaries.
- [x] Preserve one native Canvas and every active route path/stage.

### Focused Tests

- Shared-route and unique-route 1k/2k scaling slopes.
- Complete path, chain order, duplicate identity, and unavailable-route fixtures.
- Hit-index growth and hit correctness for long crossing edges.
- Build cancellation/churn publishes latest result with one active build.
- Hover/selection performs no topology rebuild.

**Rollback point:** normalization, layout/index, and Canvas integration are separate
review slices; never trade completeness for a passing benchmark.

## Phase 7: Lower-Priority Storage, Localization, And Build Work

**Goal:** Remove measured startup and repeated formatting costs after hot UI/session
paths are stable.

### Work

- [x] Add bulk/cached `FileSecretStore` reads while preserving atomic writes and
      credential semantics.
- [x] Cache bounded localization reverse/template lookups and avoid redundant global
      language writes.
- [x] Consolidate canonical JSON encoders and reusable formatter ownership.
- [x] Measure `swift-protobuf` `traits: []` in clean Release builds; keep only with
      material build/binary improvement and full sing-box test success.
- [x] Do not add a third-party package unless a Phase 0-6 benchmark proves the
      native/local design materially insufficient and the dependency gate is met.
- [x] If a package candidate emerges, record its exact tag, official compatibility
      and license evidence, transitive graph, cold/incremental build cost, release
      binary impact, focused benchmark, and rollback before retaining it.

### Focused Tests

- Startup reads/decode counts for 10/100/1,000 profiles/secrets.
- Localization exact/interpolated correctness and bounded cache behavior.
- Before/after clean-build and release-size report for any manifest experiment.

**Rollback point:** each lower-priority optimization is isolated and may be dropped
without affecting the main performance architecture.

## Phase 8: Concentrated Validation And Documentation

### Commands

- [x] `swift build`
- [x] `swift test`
- [x] opt-in Release performance benchmark command added in Phase 0
- [x] `node --check scripts/verify-real-controller-source.mjs`
- [x] `node scripts/verify-real-controller-source.mjs`
- [x] `python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings`
- [x] native HIG contrast/tap-target checker required by repository rules
- [x] `git diff --check`
- [x] relevant Xcode workspace build/test if the local SDK/toolchain supports the
      declared macOS 27 target

### Final Review

- [x] Compare `tmp/codex/performance/before/` and `after/` operation/scaling results.
- [x] Inspect all eleven destinations for observation scope and interaction
      regressions without contacting a controller.
- [x] Audit package graph, licenses, direct dependency rationale, and any retained
      manifest change.
- [x] Update Trellis specs, project Skill references, source verifier,
      `docs/ARCHITECTURE.md`, and `docs/DEVELOPMENT.md` to the final architecture.
- [x] Remove disposable `tmp/codex/` artifacts not needed for the final handoff.
- [x] Clearly state that real-controller Instruments acceptance remains deferred
      until the user separately authorizes it.

## High-Risk Files

- `Sources/Mica/App/AppModelLiveSession.swift`
- `Sources/Mica/App/AppModel.swift`
- `Sources/Mica/App/OperationSessionModels.swift`
- `Sources/Mica/App/DashboardSessionModels.swift`
- `Sources/Mica/App/ConnectionTopologyModel.swift`
- `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift`
- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift`
- `Sources/Mica/Features/Workbench/WorkbenchChrome.swift`
- `Sources/MicaCore/API/MihomoClient.swift`
- `Sources/MicaCore/API/SurgeHttpAPIClient.swift`
- `Sources/MicaCore/API/SingBoxGRPCClient.swift`
- `Package.swift`

## Final Start Checklist

- [x] PRD convergence pass is complete and has no blocking open questions.
- [x] Design maps every P0/P1 finding to an implementation phase and test.
- [x] No phase relies on real controller access.
- [x] File splitting follows ownership and refresh frequency rather than line count.
- [x] User explicitly approves implementation.
