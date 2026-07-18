# Live Session And Controller Transaction Contract

## 1. Scope / Trigger

Apply this contract whenever code starts, replaces, pauses, refreshes, or ends the selected controller session; mutates controller profiles/order; exposes controller commands; or changes controller-editor navigation.

## 2. Signatures

```swift
func enterLiveSession(for router: RouterProfile)
func leaveLiveSession()
func requestImmediateSessionRefresh(isUserInitiated: Bool = false)
func setPresentationPaused(_ paused: Bool)

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
- Fast, medium, and slow REST lanes run at 2, 5, and 30 seconds. Mihomo WebSocket streams, Surge near-live polling, and sing-box StartedService streams remain part of the same selected generation.
- sing-box status, groups, mode, connections, logs, and Tailscale producers are structured children of one task tree. Generation invalidation cancels every child and gracefully shuts down the gRPC channel; no second lossy mixed-domain queue may sit between the RPC streams and AppModel.
- Manual refresh uses the lane single-flight/coalescing path. It never creates a second refresh subsystem.
- Pause keeps networking active but freezes visible business data. Pending REST keeps only the latest projection; traffic, logs, and closed connections use their bounded session buffers. The status bar shows the fixed `presentationPausedAt`, not a moving network timestamp.
- Last successful rows remain visible after an endpoint failure. The owning surface shows stale state; only never-loaded data uses an error empty state.
- Test stays available while paused. Refresh/reload/provider-update commands are disabled while paused. Menu, toolbar, Actions, Rules, and Sources consume the same capability rules.
- Closing the final main window or sleeping invalidates the generation. App deactivation and minimization do not. Settings-only state cannot issue selected-session commands.
- Profile save/delete persist before observable mutation. Storage failure keeps profiles, credentials, selection, and the active generation unchanged.
- Editing or adding a non-active controller never steals the active session. Active deletion chooses the next item at the old index, otherwise the previous item.
- Manual controller order is the only controller order. Recent controller history is stored separately and updates for every explicit selected-ID change.
- Dirty editor navigation is inline. Saving disables destination/Add/Edit replacement. Dirty window close uses `MainWindowCloseGuard`, an AppKit lifecycle delegate only; it must not host content UI.

## 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Async result has old controller ID or generation | Drop it without mutating visible or pending state. |
| Lane request already in flight | Set one follow-up flag; do not start another request. |
| Endpoint fails after success | Keep last value, mark endpoint/surface stale, preserve `lastSuccessAt`. |
| Endpoint has never succeeded | Show the localized error empty state and retry path. |
| Presentation is paused | Continue networking; reject user refresh/reload; allow Test; keep visible timestamp fixed. |
| Profile persistence fails after secret write | Restore the prior secret and leave observable/session state unchanged. |
| Active controller is deleted | Select next at old index, else previous; create one new generation. |
| Non-active controller is edited/deleted/reordered | Current selected ID and generation remain unchanged. |
| Dirty editor window close | Show native destructive confirmation; cancel keeps window/draft. |
| Editor save is in progress | Block window close and all editor-replacement intents. |
| Remote write succeeds but authoritative refresh fails | Keep the confirmed local result and report partial success; do not roll back the write. |
| sing-box Tailscale fails after prior status | Retain prior Tailscale status and mark it partial without failing the rest of the controller session. |

## 5. Good / Base / Bad Cases

- Good: medium refresh fails after policy data loaded; the existing cards remain visible with a stale warning, while fast traffic continues.
- Base: no controller exists; no generation or network task starts and command capabilities are false.
- Bad: a refresh failure clears `dashboard`, starts another polling loop, changes selected controller, or exposes a user-facing Sync/Start Live mode.

## 6. Tests Required

- Refresh lane interval, coalescing, retry reset, terminal classification, and generation rejection.
- Pause capabilities: Test true, Refresh false, fixed pause timestamp, reset on new generation.
- Log 2000/8 MiB, closed connection 1000/16 MiB with duplicate-ID latest retention, and traffic five-minute/300-sample budgets.
- Transaction failure rollback for profile and secret storage.
- Active/non-active insert, edit, delete, and reorder session side effects.
- Last-data presentation: unavailable plus existing rows resolves to content/stale; zero rows resolves to unavailable.
- sing-box multi-stream fixture, cancellation/channel shutdown, structured gRPC status mapping, and Tailscale empty/error/partial readiness.
- Confirmed-write/refresh-failure transactions for mode, policy selection, fixed-selection clear, and connection termination.
- Source verification for shared command capabilities, window close guard, removed live/sync paths, and no AppKit content views.

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
