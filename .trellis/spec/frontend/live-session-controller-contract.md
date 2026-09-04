# Live Session And Controller Transaction Contract

## 1. Scope / Trigger

Apply this contract whenever code starts, replaces, pauses, refreshes, or ends the selected controller session; mutates controller profiles/order; exposes controller commands; or changes controller-editor navigation.

## 2. Signatures

```swift
func enterLiveSession(for router: RouterProfile)
func leaveLiveSession(reason: LiveSessionEndReason = .sessionEnd)
func requestImmediateSessionRefresh(isUserInitiated: Bool = false)
func restartRequestedMihomoLiveStreamsForManualRefresh(
    router: RouterProfile,
    generation: UUID
)
func handleLiveStreamFailure(
    _ channel: LiveStreamChannel,
    error: Error,
    routerID: RouterProfile.ID,
    generation: UUID,
    runtime sourceRuntime: LiveSessionRuntime? = nil
)
func setPresentationPaused(_ paused: Bool)
func registerLiveSessionWindowDemand(
    _ id: LiveSessionWindowDemandID,
    destination: LiveSessionVisibleDestination
)
func updateLiveSessionWindowDemand(
    _ id: LiveSessionWindowDemandID,
    destination: LiveSessionVisibleDestination
)
func unregisterLiveSessionWindowDemand(_ id: LiveSessionWindowDemandID)

func upsertRouter(from draft: RouterDraft) async throws -> RouterProfile
func deleteRouterTransaction(_ router: RouterProfile) async throws
func moveRouter(_ routerID: RouterProfile.ID, to targetIndex: Int) async throws

actor RouterProfileMutationCoordinator {
    func run<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value
}
```

Command surfaces consume these shared capabilities:

```swift
var canTestSelectedRouter: Bool
var canRefreshSelectedRouter: Bool
var canTogglePresentationPause: Bool
```

## 3. Contracts

- Exactly one selected controller owns a live `ControllerSession` generation. Every async apply validates controller ID and generation.
- A session starts in `connecting`. Live mutation commands remain disabled until
  a complete capability-aware baseline commits atomically and state becomes
  `live` or `partial`.
- Reconnect keeps the last committed catalogs visible as
  `staleReconnecting`, clears generation-owned raw staging buffers/timelines,
  disables live mutations, and atomically replaces visible catalogs only after
  the complete reconnect baseline validates.
- Auto Detect resolves the Clash-compatible HTTP family before the sing-box StartedService fallback. A successful HTTP probe returns immediately; a conclusive refused, missing, or unavailable port does not wait for sing-box `waitForReady`. Only an unrecognized or ambiguous HTTP result falls through to sing-box.
- Controller editor and Controllers-page connection tests use the resolved runtime kind: Mihomo-family profiles call the HTTP version endpoint, Surge profiles call the Surge snapshot API, and sing-box profiles call StartedService `GetVersion` over gRPC. An Auto Detect result must never fall back to the wrong transport, and sing-box failures must not be presented as JSON-decoding failures.
- Because controller profiles accept direct LAN IPv4/IPv6 targets, the embedded
  `Info.plist` declares `NSAppTransportSecurity.NSAllowsLocalNetworking = true`
  and a non-empty English/Simplified-Chinese
  `NSLocalNetworkUsageDescription`. Keep the narrow local-network declaration;
  do not replace it with the global `NSAllowsArbitraryLoads` exception.
- Fast, medium, and slow REST lanes run at 2, 5, and 30 seconds. Mihomo WebSocket streams, Surge near-live polling, and sing-box StartedService streams remain part of the same selected generation.
- Every accepted Surge near-live tick stages the current traffic and active
  requests, appends the received traffic-rate and active-connection-count
  samples, and publishes the `.connections` presentation domain when not
  paused. The visible `trafficTimeline`, `connectionCountTimeline`,
  `liveTrafficRate`, `liveStreamUpdatedAt`, and connections catalog advance
  together; `domains: []` must not strand a current Surge frame only in the
  generation-owned raw snapshot.
- One `LiveSessionRuntime` actor owns high-frequency raw traffic, memory,
  active-connection count, connection rows, closed-history, and log mutations
  for the selected generation.
  Its immutable publications carry controller ID, generation, domain revision,
  receipt time, typed observation counts, and bounded snapshot or log delta.
  AppModel must reject an old identity or a revision older than the last applied
  revision for that domain.
- One `SessionRefreshCoordinator` actor owns the fast, medium, and slow REST
  flights. Manual and periodic requests join the same flight, reserve at most
  one latest follow-up, retry iteratively, and cancel on generation invalidation.
  Do not restore recursive retry or a second view-owned refresh loop.
- Public user Refresh owns `selectedRouterRefreshOperationID` plus its task and
  visible busy state. A repeated user Refresh rejects without cancelling or
  replacing that owner. Internal immediate refresh requests may join the same
  lane coordinator, but they never claim, clear, or impersonate the public
  owner; completion clears markers only when its owner token still matches.
- Mihomo WebSocket receive failures are normalized to `MihomoClientError.connectionFailure` before retry classification. Traffic, logs, memory, and connections share one live retry reservation; concurrent channel failures cannot cancel and replace the pending retry or advance the backoff multiple times.
- A Mihomo producer captures the installed `LiveSessionRuntime` and includes
  that reference in failure handling. A callback from a replaced runtime is
  rejected even when controller ID and generation still match. Cancellation is
  a no-op. Once one retry is scheduled, every later callback from that failure
  wave joins the existing reservation regardless of its error category.
- A terminal Mihomo channel failure does not invalidate the generation-owned
  runtime. It marks the aggregate stream/session partial (or failed before the
  first baseline) while healthy sibling channels keep ingesting and publishing.
  Retryable failures may perform one controlled all-stream rebuild through the
  shared reservation.
- User-initiated Refresh restarts requested streams for every resolved Mihomo
  family (`mihomo`, Nikki, OpenClash, CMFA, and Stash), replaces the runtime,
  and cancels all old producers before running the existing REST lanes. It does
  not create a second refresh or retry subsystem.
- A multi-endpoint refresh attempt returns success, partial success, or total
  failure. Partial success publishes every successful endpoint, retains
  last-good values for failures, records endpoint health, and keeps the lane
  eligible for its next periodic cycle; it never terminalizes the whole lane.
- sing-box status, groups, mode, connections, logs, and Tailscale producers are structured children of one task tree. Generation invalidation cancels every child and gracefully shuts down the gRPC channel; no second lossy mixed-domain queue may sit between the RPC streams and AppModel.
- Manual refresh uses the lane single-flight/coalescing path. It never creates a second refresh subsystem.
- Provider Update All reuses the existing provider operation task slot. It
  processes the updatable provider projection in controller order, validates
  controller ID plus generation after every suspension, retains per-provider
  failures, and performs one authoritative provider refresh after the batch.
- Connection termination requires a non-blank controller-reported connection
  ID at both AppModel and transport boundaries. Rows without IDs remain visible
  but never enter single or grouped close intents.
- Pause keeps networking active but freezes visible business data. Pending REST keeps only the latest projection; traffic, logs, and closed connections use their bounded session buffers. The status bar shows the fixed `presentationPausedAt`, not a moving network timestamp.
- Explicit session end, controller switch/deletion, final-window close, or sleep
  cancels the whole task tree, invalidates the generation, clears raw buffers,
  timelines, retained closed history, per-domain catalogs, log presentation,
  operation markers, and session-bound workspace selection.
- `BoundedLogBuffer` is an O(1) fixed-slot ring capped at 2,000 entries and
  8 MiB UTF-8. `ClosedConnectionBuffer` is current-session history capped at
  200 records and 30 minutes. Neither uses array front removal.
- `DashboardSnapshot` does not own logs. The generation-owned raw log buffer
  publishes through `LogsCatalogSnapshot`, preserving the transport receipt
  timestamp and incoming order.
- Connection structure, metrics, and aggregate traffic use independent
  revisions. Rate/counter-only frames must not rebuild static connection rows,
  close groups, rules, providers, or topology structure.
- Rules and providers publish through separate `RulesCatalogSnapshot` and
  `ProvidersCatalogSnapshot` properties/domains. A successful endpoint refresh
  invalidates only the catalog it owns; neither endpoint may recreate a combined
  routing catalog or overwrite another pending domain.
- `connectionsStructureRevision` and `connectionsMetricsRevision` are
  independently observable AppModel scalar tokens. Publish the complete
  `ConnectionsCatalogSnapshot` first, then advance only the token whose
  semantic domain changed. Equality/change-plan evaluation happens before
  publication and before any high-cardinality projection; an unchanged frame
  advances freshness/baseline state without replacing observable catalogs.
- `ConnectionsCatalogSnapshot.traffic` preserves the controller connection
  aggregate (for Mihomo/sing-box this can be cumulative totals). It is not the
  authoritative live rate. Rate-labelled UI consumes the latest received
  `TrafficTimeline.Sample` or `liveTrafficRate`; cumulative totals remain byte
  totals and must not be formatted with `/s`.
- Every main window owns one stable `LiveSessionWindowDemandID`. Window roots
  register/update/unregister only their own destination. The effective domains
  are the union across windows; this never creates per-window networking or a
  second runtime.
- `LiveSessionPresentationDemand` is one complete snapshot containing identity,
  generation-scoped monotonic revision, domain union, global pause, logs pause,
  and baseline-publication state. Runtime installation receives the current
  snapshot before stream ingestion. The actor rejects stale identity/revision
  updates.
- Logs publish at 200 ms, traffic at 250 ms, connections at 500 ms, and memory
  at one second. Hidden domains retain raw changes without materializing UI
  projections. A newly visible domain flushes immediately only when global,
  logs, and baseline gates permit it.
- A superseded immediate flush releases its actor reservation. If the current
  demand still observes that domain, the actor may complete the flush against
  the current demand; otherwise the next visibility transition reserves it
  again. A publication staged while hidden is flushed from generation-owned
  staged state on re-entry, even when the actor revision was already consumed.
- Last successful rows remain visible after an endpoint failure. The owning surface shows stale state; only never-loaded data uses an error empty state.
- `ControllerSession.lastSuccessAt`, lane success times, and publication times
  are monotonic maxima. An older domain publication must never move freshness
  backward.
- Locally derived connection rates key previous counters by reported ID plus
  source-order occurrence. Duplicate-count changes or counter resets preserve
  a controller-reported speed, otherwise they return unavailable rather than
  borrowing another occurrence's counter.
- Test is a controller reachability operation rather than a live mutation. It
  stays available after first/later connection failure and while presentation is
  paused; a duplicate Test preserves the active owner task/token. Refresh,
  reload, and provider-update commands are disabled while paused. Menu, toolbar,
  Actions, Rules, and Sources consume the same capability rules.
- Closing the final main window or sleeping invalidates the generation. App deactivation and minimization do not. Settings-only state cannot issue selected-session commands.
- Profile save/delete persist before observable mutation. Storage failure keeps profiles, credentials, selection, and the active generation unchanged.
- Profile load, save, delete, reorder, and `lastConnectedAt` persistence share
  one serialized mutation queue. Each transaction reads observable profile state
  only after it reaches the head of that queue; an older whole-array snapshot
  must never overwrite a newer edit or metadata update across an `await`.
- Editing or adding a non-active controller never steals the active session. Active deletion chooses the next item at the old index, otherwise the previous item.
- Manual controller order is the only controller order. Recent controller history is stored separately and updates for every explicit selected-ID change.
- Dirty editor navigation is inline. Saving disables destination/Add/Edit
  replacement. Dirty window close uses `MainWindowCloseGuard`, an AppKit
  lifecycle delegate attached through an `NSView` to that exact owning window;
  it must not select the process-global main window or host content UI.
- Every remote command revalidates live-session state and the concrete runtime
  capability inside AppModel immediately before creating its task/client.
  Disabled or hidden UI is presentation defense only; stale clicks, controller
  switches, reconnects, and direct dispatcher calls must not start transport.
  Persistent or delayed handlers additionally follow the
  [Live Command Scope Contract](./live-command-scope-contract.md).
- Each command family has one owner task/marker. A duplicate or competing
  intent rejects without cancelling that owner, and an older cancelled task
  cannot clear a newer token. Entity commands resolve one exact current rule,
  connection occurrence, group, member, or provider immediately before any
  optimistic mutation or transport; raw IDs, stale indexes, and historical
  objects are not sufficient mutation targets.

## 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Async result has old controller ID or generation | Drop it without mutating visible or pending state. |
| HTTP probe succeeds | Start the resolved HTTP session without waiting for an unrelated sing-box or Surge probe. |
| HTTP probe reports a conclusive unavailable port | Surface the transient failure and let the bounded probe retry run; do not wait for the sing-box readiness timeout. |
| A profile targets a LAN IP over HTTP | The app bundle permits local networking and provides the system privacy explanation before URLSession contacts the configured controller. |
| Several Mihomo live channels fail together | Keep one retry task and one backoff increment for the failure wave. |
| Old same-generation producer reports after runtime replacement | Reject it by runtime identity; do not alter the replacement runtime or retry state. |
| One Mihomo channel fails terminally after baseline | Keep the runtime and sibling producers active; retain data and expose partial state until explicit Refresh. |
| User Refresh follows a terminal Mihomo channel failure | Cancel old producers, replace the same-generation runtime, restart requested streams, and run the shared REST lanes. |
| Lane request already in flight | Set one follow-up flag; do not start another request. |
| Some endpoints in one lane succeed and others fail | Publish successes, retain failed endpoints' last-good values, report partial, and leave the lane nonterminal. |
| Endpoint fails after success | Keep last value, mark endpoint/surface stale, preserve `lastSuccessAt`. |
| Endpoint has never succeeded | Show the localized error empty state and retry path. |
| Transport reconnects after a committed baseline | Keep the prior snapshot read-only as `staleReconnecting`; replace it only after an atomic valid baseline. |
| Session ends or selected controller changes | Clear every operational catalog, timeline, raw buffer, retained closed row, task marker, and session-bound workspace selection. |
| Two windows show Overview and Logs | Use one generation/runtime and publish the union of traffic, connections, memory, and logs. |
| One of several windows closes | Unregister only that window token; keep domains still required by another window. |
| Pause/baseline state changes while the domain union is unchanged | Send a newer complete demand snapshot; do not deduplicate it as a no-op. |
| An older async demand reaches the actor late | Reject its stale identity or revision without changing scheduling or pause state. |
| An immediate flush revision is superseded while its domain remains visible | Release the old reservation and publish against the current demand; do not orphan the dirty domain. |
| A publication is staged while its domain becomes hidden | Keep staging authoritative; the next permitted visibility entry flushes the staged full state even if no actor revision remains dirty. |
| Surge near-live traffic/active requests arrive after baseline | Append both bounded timelines and publish `.connections`; visible rate, count, timestamp, and catalog advance in the same accepted session. |
| A consumer needs a live upload/download rate | Read the received traffic timeline/latest rate, not `ConnectionsCatalogSnapshot.traffic` cumulative totals. |
| Presentation is paused | Continue networking; reject user refresh/reload; allow Test; keep visible timestamp fixed. |
| Profile persistence fails after secret write | Restore the prior secret and leave observable/session state unchanged. |
| Profile edit and successful-connection metadata write overlap | Serialize both whole-array writes and retain both the edit and `lastConnectedAt` in memory and storage. |
| Active controller is deleted | Select next at old index, else previous; create one new generation. |
| Non-active controller is edited/deleted/reordered | Current selected ID and generation remain unchanged. |
| Dirty editor window close | Show native destructive confirmation; cancel keeps window/draft. |
| Editor save is in progress | Block window close and all editor-replacement intents. |
| Remote write succeeds but authoritative refresh fails | Keep the confirmed local result and report partial success; do not roll back the write. |
| Connection close succeeds but `/connections` refresh fails | Move the confirmed row(s) to retained closed state, remove them locally, and report partial success. |
| A connection has no non-blank controller ID | Do not start a task or send a request; report the operation as unavailable/partial. |
| A policy member disappeared before selection | Reject the stale intent without cancelling or starting a selection task. |
| sing-box Tailscale fails after prior status | Retain prior Tailscale status and mark it partial without failing the rest of the controller session. |
| A runtime command is invoked while connecting/reconnecting or after a controller variant change | Reject it before task/client creation and keep every in-flight marker nil. |
| Older domain receipt applies after a newer one | Keep `lastSuccessAt` at the newer timestamp. |
| Duplicate reported connection IDs are stable across frames | Derive rates independently by source-order occurrence. |
| Duplicate count changes or a counter decreases | Keep reported speed if present; otherwise leave derived speed unavailable. |

## 5. Good / Base / Bad Cases

- Good: medium refresh fails after policy data loaded; the existing cards remain visible with a stale warning, while fast traffic continues.
- Good: one terminal traffic socket fails while the log runtime continues to
  publish; Refresh later replaces the runtime and cancels the old producers.
- Good: rules and version refresh while one optional provider endpoint fails;
  the lane reports partial and tries every endpoint again on its next cycle.
- Good: `http://192.168.x.x:<port>` uses the user-configured endpoint with the
  narrow local-network ATS declaration and system privacy explanation.
- Base: no controller exists; no generation or network task starts and command capabilities are false.
- Bad: a refresh failure clears `dashboard`, starts another polling loop, changes selected controller, or exposes a user-facing Sync/Start Live mode. Removing the local-network declarations makes loopback appear healthy while a valid LAN IP can be blocked by macOS before reaching the controller.
- Bad: one channel invalidates the shared runtime without cancelling/replacing
  every producer, or a second callback reclassifies an already-scheduled retry
  wave as terminal.

## 6. Tests Required

- Refresh lane interval, coalescing, retry reset, terminal classification, and generation rejection.
- Auto Detect short-circuiting for HTTP success and conclusive transport failure, plus sing-box fallback for an unrecognized HTTP target.
- Connection-test transport routing for Mihomo, Surge, and sing-box, including Auto Detect resolving to sing-box and backend-specific failure reports.
- Live stream retry reservation deduplication and WebSocket transport-error normalization.
- Terminal Mihomo channel isolation with a real actor publication from a
  healthy sibling, cancellation no-op, mixed-category shared retry waves, and
  rejection of an old same-generation runtime callback.
- Offline manual Refresh lifecycle coverage: replacement runtime identity is
  unchanged at controller/generation level, runtime object changes, and every
  old Mihomo producer is cancelled without opening a network transport.
- Mixed Mihomo and Surge endpoint fixtures: assert successful values publish,
  failed endpoint health and last-good values remain, lane state is partial and
  nonterminal, and a later cycle still runs.
- Cross-domain out-of-order receipt tests for monotonic `lastSuccessAt`, plus
  duplicate reported-ID rate tests for stable occurrences, count changes,
  controller-reported rates, and counter resets.
- Pause capabilities: Test true, Refresh false, fixed pause timestamp, reset on new generation.
- Log 2,000/8 MiB FIFO ring behavior, closed connection 200/30-minute current-session retention, and traffic/memory/active-connection five-minute/300-sample budgets.
- Deterministic 5/4/2/1 Hz visible publication cadence, non-restarting schedule
  tokens, hidden-domain raw retention, and immediate entry flush.
- Surge near-live publication test asserting traffic/count timelines,
  `liveTrafficRate`, `liveStreamUpdatedAt`, and connections catalog all advance
  from one accepted tick.
- Source or projection test rejecting cumulative connection totals as the input
  to rate-labelled Overview readouts.
- Multi-window union, duplicate-domain registration, token update/unregister,
  generation replacement, and one-runtime ownership.
- Complete demand propagation for unchanged unions when global pause, logs
  pause, baseline state, or runtime installation changes.
- Initial runtime demand before ingestion and out-of-order demand revision
  rejection, including paused and Logs-only installation.
- Superseded immediate-flush liveness while a domain remains visible, plus
  staged-data recovery after hide and re-entry.
- Actor publication ordering: a delayed older revision cannot overwrite a newer
  visible state, and session invalidation rejects every pending actor result.
- Refresh coordinator single-flight, one bounded follow-up, iterative retry,
  cancellation during backoff, and generation replacement.
- Explicit end clears every published operational domain; reconnect retains one
  read-only stale snapshot and commits one atomic replacement baseline.
- Transaction failure rollback for profile and secret storage.
- Deterministic interleaving test for profile edit versus connection metadata
  persistence; assert no overlapping store write and no lost field.
- Active/non-active insert, edit, delete, and reorder session side effects.
- Last-data presentation: unavailable plus existing rows resolves to content/stale; zero rows resolves to unavailable.
- sing-box multi-stream fixture, cancellation/channel shutdown, structured gRPC status mapping, and Tailscale empty/error/partial readiness.
- Provider batch ordering, read-only skipping, one terminal refresh, partial and
  total failure outcomes, competing command rejection, and generation-cancelled
  stale publication.
- Confirmed-write/refresh-failure transactions for mode, policy selection, fixed-selection clear, and connection termination.
- Blank-ID rejection at the Workbench projection, AppModel operation, and Mihomo client boundary.
- Source verification for shared command capabilities, window close guard, removed live/sync paths, and no AppKit content views.
- Source verification that the embedded `Info.plist` retains
  `NSAllowsLocalNetworking` plus a bilingual
  `NSLocalNetworkUsageDescription`; `plutil -lint` and `swift build` verify the
  source plist and linker embedding path.
- Execution-boundary tests that configuration and maintenance dispatch reject
  non-live sessions and unsupported CMFA/Stash variants without transport.

## 7. Wrong vs Correct

```swift
// Wrong: a page creates its own refresh task and clears old rows on failure.
Task {
    dashboard = .empty
    dashboard.replaceRules(with: try await client.rules())
}

// Correct: use the selected generation's coordinator and retain last values.
requestImmediateSessionRefresh(isUserInitiated: true)
```

```swift
// Wrong: every channel callback invalidates the actor, including a late
// callback from the producer that belonged to the previous runtime.
cancelLiveSessionRuntime()
scheduleLiveStreamRetry(routerID: routerID, generation: generation)

// Correct: reject stale runtime identity, join an existing retry wave, and
// isolate a terminal Mihomo channel from healthy siblings.
handleLiveStreamFailure(
    channel,
    error: error,
    routerID: routerID,
    generation: generation,
    runtime: capturedRuntime
)
```

```swift
// Wrong: any optional endpoint failure terminalizes the whole lane.
failed.finishFailure(message, disposition: category.retryDisposition)

// Correct: mixed endpoint results remain retryable on the normal cadence.
completed.finishPartial(message, at: receivedAt)
```

```swift
// Wrong: rely on a disabled button and start transport from a stale intent.
guard controllerSupports(action, router: router, action: title) else { return }
runtimeOperationTask = Task { try await client.flushDNSCache() }

// Correct: AppModel revalidates live state and capability at execution time.
guard controllerSupportsLiveAction(action, router: router, action: title) else { return }
runtimeOperationTask = Task { try await client.flushDNSCache() }
```

```swift
// Wrong: each command surface invents a pause condition.
.disabled(appModel.isBusy)

// Correct: every surface consumes the shared capability.
.disabled(!appModel.canRefreshSelectedRouter)
```

```swift
// Wrong: the field is an Int, but its semantic unit is cumulative bytes.
OverviewFormat.rate(appModel.connectionsCatalog.traffic.upload)

// Correct: a rate-labelled readout consumes a received rate sample.
appModel.trafficTimeline.samples.last.map { OverviewFormat.rate($0.upload) }
```

```xml
<!-- Wrong: direct LAN HTTP profiles are supported, but the app declares no local access. -->
<dict>
    <key>CFBundleName</key>
    <string>Mica</string>
</dict>

<!-- Correct: keep the exception local and explain the system permission prompt. -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
<key>NSLocalNetworkUsageDescription</key>
<string>Mica uses the local network … Mica 使用本地网络…</string>
```
