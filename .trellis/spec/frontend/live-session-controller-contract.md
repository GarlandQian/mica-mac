# Live Session And Controller Transaction Contract

## 1. Scope / Trigger

Apply this contract whenever code starts, replaces, pauses, refreshes, or ends the selected controller session; mutates controller profiles/order; exposes controller commands; or changes controller-editor navigation.

## 2. Signatures

```swift
func enterLiveSession(for router: RouterProfile)
func leaveLiveSession(reason: LiveSessionEndReason = .sessionEnd)
func requestImmediateSessionRefresh(isUserInitiated: Bool = false)
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
- Mihomo WebSocket receive failures are normalized to `MihomoClientError.connectionFailure` before retry classification. Traffic, logs, memory, and connections share one live retry reservation; concurrent channel failures cannot cancel and replace the pending retry or advance the backoff multiple times.
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
- Test stays available while paused. Refresh/reload/provider-update commands are disabled while paused. Menu, toolbar, Actions, Rules, and Sources consume the same capability rules.
- Closing the final main window or sleeping invalidates the generation. App deactivation and minimization do not. Settings-only state cannot issue selected-session commands.
- Profile save/delete persist before observable mutation. Storage failure keeps profiles, credentials, selection, and the active generation unchanged.
- Editing or adding a non-active controller never steals the active session. Active deletion chooses the next item at the old index, otherwise the previous item.
- Manual controller order is the only controller order. Recent controller history is stored separately and updates for every explicit selected-ID change.
- Dirty editor navigation is inline. Saving disables destination/Add/Edit
  replacement. Dirty window close uses `MainWindowCloseGuard`, an AppKit
  lifecycle delegate attached through an `NSView` to that exact owning window;
  it must not select the process-global main window or host content UI.

## 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Async result has old controller ID or generation | Drop it without mutating visible or pending state. |
| HTTP probe succeeds | Start the resolved HTTP session without waiting for an unrelated sing-box or Surge probe. |
| HTTP probe reports a conclusive unavailable port | Surface the transient failure and let the bounded probe retry run; do not wait for the sing-box readiness timeout. |
| A profile targets a LAN IP over HTTP | The app bundle permits local networking and provides the system privacy explanation before URLSession contacts the configured controller. |
| Several Mihomo live channels fail together | Keep one retry task and one backoff increment for the failure wave. |
| Lane request already in flight | Set one follow-up flag; do not start another request. |
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
| Presentation is paused | Continue networking; reject user refresh/reload; allow Test; keep visible timestamp fixed. |
| Profile persistence fails after secret write | Restore the prior secret and leave observable/session state unchanged. |
| Active controller is deleted | Select next at old index, else previous; create one new generation. |
| Non-active controller is edited/deleted/reordered | Current selected ID and generation remain unchanged. |
| Dirty editor window close | Show native destructive confirmation; cancel keeps window/draft. |
| Editor save is in progress | Block window close and all editor-replacement intents. |
| Remote write succeeds but authoritative refresh fails | Keep the confirmed local result and report partial success; do not roll back the write. |
| Connection close succeeds but `/connections` refresh fails | Move the confirmed row(s) to retained closed state, remove them locally, and report partial success. |
| A connection has no non-blank controller ID | Do not start a task or send a request; report the operation as unavailable/partial. |
| A policy member disappeared before selection | Reject the stale intent without cancelling or starting a selection task. |
| sing-box Tailscale fails after prior status | Retain prior Tailscale status and mark it partial without failing the rest of the controller session. |

## 5. Good / Base / Bad Cases

- Good: medium refresh fails after policy data loaded; the existing cards remain visible with a stale warning, while fast traffic continues.
- Good: `http://192.168.x.x:<port>` uses the user-configured endpoint with the
  narrow local-network ATS declaration and system privacy explanation.
- Base: no controller exists; no generation or network task starts and command capabilities are false.
- Bad: a refresh failure clears `dashboard`, starts another polling loop, changes selected controller, or exposes a user-facing Sync/Start Live mode. Removing the local-network declarations makes loopback appear healthy while a valid LAN IP can be blocked by macOS before reaching the controller.

## 6. Tests Required

- Refresh lane interval, coalescing, retry reset, terminal classification, and generation rejection.
- Auto Detect short-circuiting for HTTP success and conclusive transport failure, plus sing-box fallback for an unrecognized HTTP target.
- Connection-test transport routing for Mihomo, Surge, and sing-box, including Auto Detect resolving to sing-box and backend-specific failure reports.
- Live stream retry reservation deduplication and WebSocket transport-error normalization.
- Pause capabilities: Test true, Refresh false, fixed pause timestamp, reset on new generation.
- Log 2,000/8 MiB FIFO ring behavior, closed connection 200/30-minute current-session retention, and traffic/memory/active-connection five-minute/300-sample budgets.
- Deterministic 5/4/2/1 Hz visible publication cadence, non-restarting schedule
  tokens, hidden-domain raw retention, and immediate entry flush.
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
// Wrong: each command surface invents a pause condition.
.disabled(appModel.isBusy)

// Correct: every surface consumes the shared capability.
.disabled(!appModel.canRefreshSelectedRouter)
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
