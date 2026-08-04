# Research: Session Concurrency Performance Audit

- Query: Audit AppModel, ControllerSession, live refresh/stream tasks, HTTP/WebSocket/gRPC concurrency, cancellation, retries, publication cadence, actor hops, reconnect, timers, and lifecycle cleanup for CPU, memory, and network performance.
- Scope: internal
- Date: 2026-07-29

## Findings

### Executive priority

1. **P0 - Move high-frequency raw ingestion out of `@MainActor AppModel`.** Logs, traffic, memory, and connection frames currently re-enter the main actor for every received value, before the 5/4/2/1 Hz visible publication gates apply.
2. **P0 - Make refresh/retry ownership iterative and generation-scoped.** Manual refresh can lose its task handle, HTTP lane retries recurse without a bound, and startup work overlaps live polling.
3. **P0 - Remove main-actor collection rebuilds.** sing-box connection batches are quadratic; Surge near-live updates rebuild and sort the complete log buffer.
4. **P1 - Reuse generation-owned transport clients.** Periodic HTTP lanes construct fresh clients and `URLSession` instances, while sing-box commands open additional gRPC channels instead of using the live generation's channel.
5. **P1 - Treat required gRPC stream completion as reconnect-worthy.** Most required stream children can end normally without failing the task group.

### 1. High - Raw stream ingestion runs one event at a time on the main actor

**Evidence**

- `AppModel` is `@MainActor @Observable`: `Sources/Mica/App/AppModel.swift:69`.
- Mihomo log, traffic, memory, and connection tasks are created inside that isolation and call AppModel mutation for every stream element: `Sources/Mica/App/AppModelLiveSession.swift:1656`, `Sources/Mica/App/AppModelLiveSession.swift:1783`, `Sources/Mica/App/AppModelLiveSession.swift:1801`, `Sources/Mica/App/AppModelLiveSession.swift:1818`.
- Per-element handlers append timelines/buffers, derive rates, compute closed rows, update live diagnostics, and mutate session state before visible throttling: `Sources/Mica/App/AppModelLiveSession.swift:2293`, `Sources/Mica/App/AppModelLiveSession.swift:2317`, `Sources/Mica/App/AppModelLiveSession.swift:2335`, `Sources/Mica/App/AppModelLiveSession.swift:2361`.
- `ControllerSession` is a large value containing endpoint snapshots, timelines, a 2,000-slot log ring, connection arrays, and presentation buffers: `Sources/Mica/App/OperationSessionModels.swift:616`.
- Every nested session mutation also passes through `controllerSession.didSet`, which synchronizes presentation lifecycle and compares runtime state: `Sources/Mica/App/AppModel.swift:129`.

**Impact**

The visible publication coordinator limits SwiftUI updates, but it does not limit raw main-actor work or actor hops. High log or connection volume can therefore starve UI work even while visible catalogs publish at their intended cadence. The large value-type property observer is also an allocation/COW risk, but its exact cost is not measured yet.

**Tests needed**

- Offline stress fixture producing at least 10,000 logs and 5,000 connection events while measuring main-actor time, task count, and allocations.
- Observation test proving raw ingestion does not invalidate unrelated presentation state.
- Instruments Swift Concurrency, Time Profiler, and Allocations comparison before/after.

**Rewrite boundary**

Introduce one generation-owned runtime/ingestion actor that owns raw buffers, timelines, connection indexes, and stream health. Publish immutable per-domain deltas/snapshots to `AppModel` only at the existing visible cadence. Keep `ControllerSessionPresentationState` and UI-owned state on `@MainActor`.

### 2. High - sing-box connection batch application is O(events x active connections)

**Evidence**

- Every close event performs both `first` and `removeAll` over the active array; every update performs `firstIndex`: `Sources/Mica/App/AppModelLiveSession.swift:2103`.
- A reset clears the array and then repeatedly scans the growing array while rebuilding it: `Sources/Mica/App/AppModelLiveSession.swift:2096`.
- The stream can deliver connection batches every second: `Sources/Mica/App/AppModelLiveSession.swift:1914`.

**Impact**

Large reset or churn batches become quadratic on the main actor. This is a direct hitch/CPU risk independent of SwiftUI rendering.

**Tests needed**

- Deterministic 1k/5k/10k reset-batch performance tests with controller-order assertions.
- Mixed open/update/close batch tests proving stable order and retained-closed behavior.

**Rewrite boundary**

Replace only the generation-owned sing-box active-connection store with an ordered ID-indexed structure. Build reset batches in one pass; apply incremental updates with O(1) lookup while preserving controller order.

### 3. High - Surge near-live ingestion rebuilds and sorts the complete log buffer

**Evidence**

- Every staged Surge snapshot materializes all log entries, builds an ID dictionary, filters the full buffer, concatenates event logs, sorts by timestamp, and replaces the ring: `Sources/Mica/App/AppModelLiveSession.swift:1208`.
- Surge near-live stages a snapshot each polling cycle: `Sources/Mica/App/AppModelLiveSession.swift:2235`, `Sources/Mica/App/AppModelLiveSession.swift:2434`.
- `BoundedLogBuffer.replace` constructs a new 2,000-slot ring and performs equality work before replacement: `Sources/Mica/App/SessionBuffers.swift:51`.

**Impact**

This is O(logCount log logCount) work plus repeated full materialization on the main actor, nominally once per second. Existing tests verify deduplication, not cost: `Tests/MicaTests/SessionStreamStateTests.swift:594`.

**Tests needed**

- 2,000-entry Surge event refresh benchmark with unchanged, appended, removed, and reordered event sets.
- Allocation-count assertion or signposted performance budget for one near-live application.

**Rewrite boundary**

Maintain Surge event entries as a dedicated ordered/indexed source and merge only changed IDs into the bounded log owner. Do not rebuild or sort unrelated Mihomo/sing-box log entries.

### 4. High - Manual refresh does not own or join coalesced work reliably

**Evidence**

- `requestImmediateSessionRefresh` overwrites `manualSessionRefreshTask` without cancelling, joining, or rejecting an existing task: `Sources/Mica/App/AppModelLiveSession.swift:319`.
- An in-flight lane merely sets `pendingFollowUp` and returns immediately: `Sources/Mica/App/AppModelLiveSession.swift:652`.
- The manual task then clears the shared handle and reports success/partial after those early returns, not after the in-flight request and promised follow-up complete: `Sources/Mica/App/AppModelLiveSession.swift:340`.
- `canRefreshSelectedRouter` checks `isBusy`, but `isBusy` does not include `manualSessionRefreshTask` or refresh-lane in-flight state: `Sources/Mica/App/AppModelLiveSession.swift:13`, `Sources/Mica/App/AppModelSelectionState.swift:203`.
- Tests cover the lane state struct and manually inserted task cancellation, not concurrent AppModel refresh requests: `Tests/MicaTests/LiveSessionTransactionTests.swift:87`, `Tests/MicaTests/LiveSessionTransactionTests.swift:407`.

**Impact**

Repeated refresh actions can lose the only cancellation handle, report completion early, and leave older work running until its own network suspension completes. Generation guards prevent stale publication but do not prevent wasted network/CPU work.

**Tests needed**

- Two and three overlapping manual refresh requests with blocking fake endpoints.
- Assert one network flight per lane, one retained owner task, completion only after the coalesced follow-up, and cancellation on session end.

**Rewrite boundary**

Make the refresh coordinator own one awaitable task/result per lane. Callers join the same flight and receive the final coalesced result. `AppModel` should retain one generation-scoped coordinator task, not overwrite per-call handles.

### 5. High - Refresh retries recurse indefinitely during a long transient outage

**Evidence**

- A transient lane failure sleeps and recursively awaits `performSessionRefresh` again: `Sources/Mica/App/AppModelLiveSession.swift:694`.
- Transient retries have no attempt ceiling; only delay is capped at 30 seconds: `Sources/Mica/App/LiveSessionRefreshModels.swift:253`, `Sources/Mica/App/LiveSessionRefreshModels.swift:271`.

**Impact**

Each failed retry retains another suspended async frame. A controller left offline for hours or days can grow the task's retained continuation chain until success, cancellation, or process exit.

**Tests needed**

- Injected clock/transport test running thousands of transient failures with bounded task/allocation assertions.
- Cancellation during backoff must terminate immediately with no further request.

**Rewrite boundary**

Replace recursive retry and recursive follow-up calls with one iterative lane state machine owned by the refresh coordinator.

### 6. High - Startup and steady-state HTTP work overlap and create fresh sessions

**Evidence**

- A resolved session starts baseline refresh coordination and live streams back-to-back: `Sources/Mica/App/AppModelLiveSession.swift:529`.
- Surge baseline `snapshot()` performs nine endpoint reads sequentially: `Sources/MicaCore/API/SurgeHttpAPIClient.swift:152`.
- Surge near-live immediately requests traffic, events, active requests, and recent requests in parallel: `Sources/Mica/App/AppModelLiveSession.swift:2235`.
- The 2-second fast lane also requests active requests, while the 1-second near-live loop already does so: `Sources/Mica/App/AppModelLiveSession.swift:837`, `Sources/Mica/App/AppModelLiveSession.swift:2240`.
- Each periodic lane constructs a new Mihomo or Surge client: `Sources/Mica/App/AppModelLiveSession.swift:715`, `Sources/Mica/App/AppModelLiveSession.swift:833`.
- Each client initializer creates a new `URLSession` when none is injected: `Sources/MicaCore/API/MihomoClient.swift:77`, `Sources/MicaCore/API/SurgeHttpAPIClient.swift:42`.

**Impact**

Startup can issue overlapping reads for the same Surge endpoints before the atomic baseline commits. Steady-state lanes repeatedly allocate transport/client state and cannot share one URLSession connection pool across the selected generation. The active contract currently names both a 2-second Surge active-request lane and a 1-second near-live active-request poll, so removing that duplication requires a contract decision.

**Tests needed**

- Request recorder asserting endpoint counts/order from session start through first baseline commit.
- Client/session factory counter proving one HTTP transport bundle per generation.
- Slow-baseline test proving periodic lanes do not duplicate startup endpoints.

**Rewrite boundary**

Create a generation-owned typed HTTP client bundle and startup barrier. Baseline, periodic lanes, live polling, and mutations reuse those clients. Start periodic work only after baseline completion, and assign each endpoint to exactly one cadence owner.

### 7. Medium - Optional Surge recent requests can stall the entire near-live cycle

**Evidence**

- `recentRequests` starts as an `async let`, but the loop explicitly awaits it before applying the otherwise-complete traffic/events/active update: `Sources/Mica/App/AppModelLiveSession.swift:2241`, `Sources/Mica/App/AppModelLiveSession.swift:2247`.
- Surge requests use an 8-second request timeout: `Sources/MicaCore/API/SurgeHttpAPIClient.swift:50`.

**Impact**

A slow optional endpoint can delay all near-live publication by up to its request duration. The loop also sleeps one second after work, so cadence is request-duration plus one second rather than a fixed start-to-start interval.

**Tests needed**

- Hold recent requests open while traffic/events/active complete; assert core near-live state publishes without waiting.

**Rewrite boundary**

Move recent requests to an independent lower-frequency lane or apply a short explicit timeout and publish the required trio first.

### 8. High - Required sing-box streams can end normally without triggering reconnect

**Evidence**

- Status, groups, mode, connections, and logs children return normally when their `for try await` loops end: `Sources/Mica/App/AppModelLiveSession.swift:1873`, `Sources/Mica/App/AppModelLiveSession.swift:1883`, `Sources/Mica/App/AppModelLiveSession.swift:1893`, `Sources/Mica/App/AppModelLiveSession.swift:1914`, `Sources/Mica/App/AppModelLiveSession.swift:1924`.
- The parent waits for every child, so one required stream can disappear while the others keep the group alive: `Sources/Mica/App/AppModelLiveSession.swift:1982`.
- Tailscale explicitly converts unexpected normal completion into a transport error, showing the missing behavior on the required streams: `Sources/Mica/App/AppModelLiveSession.swift:1947`.
- Current gRPC tests cover consumer cancellation, not premature normal stream completion: `Tests/MicaCoreTests/SingBoxGRPCClientTests.swift:180`.

**Impact**

One domain can silently stop updating without reconnect or user-visible failure while the overall session remains live.

**Tests needed**

- In-process fixture that normally finishes each required stream independently; assert whole-session failure, child cancellation, channel shutdown, one retry reservation, and generation-safe restart.

**Rewrite boundary**

Normalize unexpected completion of every required long-lived stream and `runConnections()` into a transport failure at the gRPC session-owner boundary. Keep Tailscale's independent partial/retry semantics.

### 9. Medium - Live reconnect backoff resets on any successful frame

**Evidence**

- Every successful live ingestion calls `liveRetryState.recordSuccess()`: `Sources/Mica/App/AppModelLiveSession.swift:1612`.
- A reconnect baseline commit also resets retry state: `Sources/Mica/App/AppModelLiveSession.swift:1512`.
- Retry delay is reserved from the shared attempt counter: `Sources/Mica/App/LiveSessionRefreshModels.swift:284`.

**Impact**

A healthy high-rate channel can reset backoff just before another channel repeatedly fails, causing recurring two-second reconnect waves instead of bounded escalation.

**Tests needed**

- Simulate traffic success followed by repeated log/connection failure waves; verify delays progress 2/4/8/15/30 until a complete reconnect baseline or stability threshold succeeds.

**Rewrite boundary**

Reset shared retry state only after a complete reconnect baseline or an explicit all-required-channels stability condition, not on every frame.

### 10. Medium - gRPC stream bridging adds two unstructured tasks and extra buffering per stream

**Evidence**

- `makeStream` creates an unstructured task around each RPC stream: `Sources/MicaCore/API/SingBoxGRPCClient.swift:492`.
- `consume` creates another task plus a completion `AsyncThrowingStream` before yielding into the public stream: `Sources/MicaCore/API/SingBoxGRPCClient.swift:536`.
- AppModel then owns another structured consumer child for each domain: `Sources/Mica/App/AppModelLiveSession.swift:1861`.

**Impact**

Each message crosses multiple task and stream boundaries before reaching session state. Cancellation is explicitly bridged and tested, so this is a measured-profile optimization candidate rather than a correctness failure.

**Tests needed**

- Swift Tasks/Actors trace comparing task count, hops, and latency for the current bridge versus direct structured consumption.
- Preserve the existing cancellation test and bounded-buffer behavior.

**Rewrite boundary**

Limit changes to `SingBoxStartedServiceAdapter.makeStream/consume`; preserve its typed public API unless profiling proves a direct structured callback/sequence path is materially better.

### 11. Medium - Mihomo WebSocket decoding allocates a decoder for every message

**Evidence**

- The receive loop constructs `JSONDecoder()` inside the per-message path: `Sources/MicaCore/API/MihomoClient.swift:513`, `Sources/MicaCore/API/MihomoClient.swift:537`.
- Four WebSocket domains share this path, including high-volume logs and connections: `Sources/MicaCore/API/MihomoClient.swift:189`, `Sources/MicaCore/API/MihomoClient.swift:242`, `Sources/MicaCore/API/MihomoClient.swift:247`, `Sources/MicaCore/API/MihomoClient.swift:252`.

**Impact**

This adds avoidable allocation/configuration work per frame. Exact significance depends on stream rate and payload size.

**Tests needed**

- Decode throughput/allocation benchmark using fixture traffic, log, memory, and connection frames.

**Rewrite boundary**

Create one decoder per receive task or use a stateless decode helper outside the actor-isolated client state. Do not share a non-thread-safe decoder across concurrent receive tasks.

### Existing foundations worth retaining

- Publication scheduling is non-restarting and limited to one task per visible domain: `Sources/Mica/App/AppModelLiveSession.swift:113`.
- Hidden domains retain raw state and flush on entry: `Sources/Mica/App/LiveSessionRefreshModels.swift:88`, `Sources/Mica/App/AppModelLiveSession.swift:89`.
- Session end cancels operation, refresh, publication, WebSocket, retry, probe, and sing-box owner tasks and invalidates generation: `Sources/Mica/App/AppModelLiveSession.swift:77`, `Sources/Mica/App/AppModelLiveSession.swift:1690`.
- Mihomo WebSocket termination cancels both receive and socket tasks: `Sources/MicaCore/API/MihomoClient.swift:550`.
- gRPC stream consumer cancellation is propagated and covered by an in-process test: `Sources/MicaCore/API/SingBoxGRPCClient.swift:21`, `Tests/MicaCoreTests/SingBoxGRPCClientTests.swift:180`.
- Log, timeline, and closed-connection retention are bounded: `Sources/Mica/App/SessionBuffers.swift:4`, `Sources/Mica/App/SessionTimelineModels.swift:19`, `Sources/Mica/App/SessionBuffers.swift:151`.

## Files Found

- `Sources/Mica/App/AppModel.swift` - Main-actor observable owner and operation/task slots.
- `Sources/Mica/App/AppModelLiveSession.swift` - Session lifecycle, refresh lanes, publication cadence, streams, reconnect, and retry.
- `Sources/Mica/App/OperationSessionModels.swift` - `ControllerSession`, runtime state, and rate tracking.
- `Sources/Mica/App/LiveSessionRefreshModels.swift` - Lane, retry, baseline, and publication coordinator state machines.
- `Sources/Mica/App/SessionBuffers.swift` - Bounded log and closed-connection storage.
- `Sources/Mica/App/SessionTimelineModels.swift` - Bounded traffic and memory histories.
- `Sources/Mica/App/AppModelSelectionState.swift` - Busy gates, task cancellation, and session clearing.
- `Sources/Mica/App/AppModelSingBoxOperations.swift` - Unary sing-box operations and per-command channels.
- `Sources/MicaCore/API/MihomoClient.swift` - HTTP/WebSocket client, decoding, buffering, and socket cleanup.
- `Sources/MicaCore/API/SurgeHttpAPIClient.swift` - Surge HTTP endpoints, sequential baseline snapshot, and URLSession ownership.
- `Sources/MicaCore/API/SingBoxGRPCClient.swift` - gRPC channel, stream bridges, cancellation, and adapters.
- `Tests/MicaTests/LiveSessionPublicationTests.swift` - Functional publication cadence/visibility coverage.
- `Tests/MicaTests/LiveSessionTransactionTests.swift` - Lane-state, retry-state, and task-handle cancellation coverage.
- `Tests/MicaTests/SessionStreamStateTests.swift` - Buffer and projection correctness coverage.
- `Tests/MicaCoreTests/SingBoxGRPCClientTests.swift` - In-process gRPC field and cancellation coverage.

## Code Patterns

- One selected controller and generation gate every asynchronous apply: `Sources/Mica/App/AppModelLiveSession.swift:1681`.
- Visible publication budgets are 200/250/500/1000 ms: `Sources/Mica/App/LiveSessionRefreshModels.swift:34`.
- REST lanes are 2/5/30 seconds with 1/2/4-second startup offsets: `Sources/Mica/App/LiveSessionRefreshModels.swift:205`.
- Live retry delays are 2/4/8/15/30 seconds with bounded jitter: `Sources/Mica/App/LiveSessionRefreshModels.swift:271`.
- HTTP clients are actors, but their default initializers own newly created URL sessions: `Sources/MicaCore/API/MihomoClient.swift:68`, `Sources/MicaCore/API/SurgeHttpAPIClient.swift:34`.
- sing-box uses one outer structured task group, with per-stream bridge tasks underneath it: `Sources/Mica/App/AppModelLiveSession.swift:1861`, `Sources/MicaCore/API/SingBoxGRPCClient.swift:492`.

## External References

- `Package.swift:1` selects Swift tools 6.2 and `Package.swift:9` selects macOS 27.
- `Package.swift:14` pins grpc-swift-2 2.4.2, grpc-swift-nio-transport 2.9.0, grpc-swift-protobuf 2.4.1, and swift-protobuf 1.38.0.
- No online documentation was relied on. The available web lookup failed before retrieval, so all conclusions above come from current repository source, tests, active Trellis contracts, and the locally installed Swift concurrency guidance.

## Related Specs

- `.trellis/spec/frontend/live-session-controller-contract.md` - generation ownership, single-flight lanes, reconnect, publication cadence, and cleanup.
- `.trellis/spec/backend/controller-data-contract.md` - transport/DTO ordering and capability boundaries.
- `.trellis/spec/frontend/workbench-ui-contract.md` - high-frequency observation and visible-domain budgets.
- `AGENTS.md` - Swift 6.2/macOS 27 constraints, full-visible business data, and dependency/rewrite policy.
- `.agents/skills/mica-controller-development/references/architecture.md` - AppModel/session ownership and concurrency boundaries.
- `.agents/skills/mica-controller-development/references/controllers.md` - transport, retry, and session publication contracts.

## Caveats / Not Found

- No Instruments trace, signpost baseline, allocation benchmark, or network request-count benchmark exists in the inspected tests. Severity reflects source-level asymptotic cost, ownership correctness, and likely hot-path frequency, not measured production percentages.
- The exact COW/allocation cost of mutating the large value-type `ControllerSession` behind `didSet` remains an explicit unknown until measured.
- Real-controller behavior was not exercised, consistent with the task PRD. WebSocket/gRPC normal-completion behavior must be confirmed with offline fixtures and then, only with user authorization, a real endpoint trace.
- `Package.swift` does not explicitly declare Swift language mode, strict-concurrency level, default actor isolation, or upcoming concurrency features beyond the Swift 6.2 tools version.
- The active live-session spec currently assigns Surge active requests to both the 2-second fast lane and the 1-second near-live poll. Deduplicating that request requires a documented contract decision before implementation.
