# Research: Workbench live-session functional audit

- Query: Audit the controller-to-Workbench live-data pipeline for confirmed bugs, especially data that appears frozen, controller/generation replacement, reconnect, pause, cancellation, stale presentation, and capability gating.
- Scope: internal
- Date: 2026-08-27

## Findings

### Confirmed P1: a terminal Mihomo channel failure disables every actor-backed live domain and Refresh does not recover it

- The traffic, log, memory, and connection WebSocket producers capture the same `LiveSessionRuntime`: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/AppModelLiveSession.swift:1913` through `:2017`.
- Every channel error reaches `handleLiveStreamFailure`; it invalidates the shared runtime before deciding whether retry is possible: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/AppModelLiveSession.swift:2491` through `:2506`.
- `cancelLiveSessionRuntime` immediately removes the runtime identity and asynchronously invalidates the actor: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/AppModelLiveSessionRuntime.swift:57` through `:75`.
- Actor ingestion then rejects all surviving producer input when `isActive` is false: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/LiveSessionRuntime.swift:166` through `:187`, `:228` through `:255`.
- The terminal branch records failure but neither cancels sibling producers nor reinstalls the actor: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/AppModelLiveSession.swift:2521` through `:2532`.
- Mihomo manual Refresh only requests REST lanes and never calls `startLiveStreams`: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/AppModelLiveSession.swift:297` through `:388`. Only the sing-box branch restarts streams at `:327` through `:344`.
- Terminal errors are reachable for auth, wrong-target, malformed JSON, TLS, and non-transient HTTP status: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/RouterTrialFailureModels.swift:21` through `:44`, `:318` through `:327`.

Minimal sequence: commit a Mihomo baseline; let one WebSocket fail terminally (or exhaust a retry-once failure); the common actor is invalidated; surviving sockets continue to call an inactive actor and publish nothing; click Refresh; REST data refreshes once but traffic, logs, memory, and live connections remain frozen until session replacement.

Test evidence: existing retry coverage only checks `LiveStreamRetryState` scheduling/de-duplication at `/Volumes/T7 Shield/project/mica-mac/Tests/MicaTests/LiveSessionTransactionTests.swift:182` through `:197`. No test covers terminal channel failure across sibling producers or manual recovery.

### Confirmed P1/P2: one terminal endpoint failure permanently suppresses unrelated endpoints in the same refresh lane

- Mihomo slow refresh concurrently captures version, config, rules, and two provider endpoints, publishes successes, then throws any `firstFailure`: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/AppModelLiveSession.swift:831` through `:904`.
- Surge medium and slow lanes use the same aggregate-failure pattern: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/AppModelLiveSession.swift:922` through `:982`.
- The aggregate error marks the entire lane terminal: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/AppModelLiveSession.swift:769` through `:778`; `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/LiveSessionRefreshModels.swift:372` through `:380`.
- Periodic refresh then skips the whole lane indefinitely: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/AppModelLiveSession.swift:681` through `:685`.
- Manual refresh clears the terminal flag for that attempt only: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/AppModelLiveSession.swift:746` through `:750`. A persistently unsupported endpoint immediately terminalizes the lane again.

Minimal sequence: rules/version/config succeed while one provider returns an error categorized terminal (for example 404); the successful values publish; the slow lane becomes terminal; all otherwise healthy slow endpoints stop their 30-second updates. The analogous Surge sequence can freeze unrelated policy or rules data.

This conflicts with endpoint isolation and last-good/stale behavior in `.trellis/spec/frontend/live-session-controller-contract.md:126`, `:155`, and `:183`.

Test evidence: `/Volumes/T7 Shield/project/mica-mac/Tests/MicaTests/SessionRefreshCoordinatorTests.swift:292` through `:315` confirms a generic terminal operation stops retry, but no integration test covers mixed endpoint success/failure within one lane.

### Confirmed P2: cross-domain publication order can move `lastSuccessAt` backward

- Actor publications apply independently by domain: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/AppModelLiveSessionRuntime.swift:266` through `:325`.
- `completeLiveTransportIngestion` first records a monotonic receipt but then directly assigns `lastSuccessAt = receivedAt`: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/AppModelLiveSession.swift:1708` through `:1725`.
- The underlying receipt helper correctly uses `max`, establishing the intended monotonic behavior: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/OperationSessionModels.swift:745` through `:749`.

Minimal sequence: a traffic publication received at t=200 applies first; a slower memory publication received at t=199 applies afterward; `lastSuccessAt` regresses from 200 to 199. Diagnostics and session freshness can therefore jump backward even though every domain revision is monotonic.

Test evidence: `/Volumes/T7 Shield/project/mica-mac/Tests/MicaTests/LiveSessionPublicationTests.swift:540` through `:566` rejects an older revision in one domain, but there is no cross-domain out-of-order timestamp test.

### Confirmed P2: derived connection rates are incorrect for duplicate reported IDs

- `ConnectionTransferRateTracker` retains exactly one previous counter per raw connection ID, so the final duplicate overwrites earlier occurrences: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/OperationSessionModels.swift:506` through `:535`.
- The active Workbench projection explicitly supports duplicate reported IDs with occurrence identities: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/Features/Workbench/WorkbenchConnections.swift:209` through `:271`.

Minimal sequence: frame one contains two `duplicate` rows with upload totals 100 and 1000; frame two contains 200 and 1100 one second later. Both rows compare against the stored 1000 counter, so the first rate is clamped to zero instead of 100 B/s.

Test evidence: `/Volumes/T7 Shield/project/mica-mac/Tests/MicaTests/SessionStreamStateTests.swift:463` through `:522` covers unique IDs, counter reset, and controller-reported rates, but not duplicate IDs.

### Expected cadence, not defects

- REST lanes are intentionally 2/5/30 seconds: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/LiveSessionRefreshModels.swift:324` through `:343`.
- Visible actor publication cadence is intentionally logs 200 ms, traffic 250 ms, connections 500 ms, memory 1 second: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/LiveSessionRefreshModels.swift:42` through `:47`.
- Proxies, Rules, Sources, Controllers, Configuration, Actions, and Diagnostics intentionally map to `.other` and do not request high-frequency domains: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/Features/Workbench/WorkbenchChrome.swift:142` through `:153`.
- Overview topology redraw intentionally keys on connection structure revision, so unchanged routes remain visually static even while metrics advance: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift:13` through `:31` and `.trellis/spec/frontend/workbench-ui-contract.md:441`.
- Local-network entitlement/usage declarations are present: `/Volumes/T7 Shield/project/mica-mac/Sources/Mica/App/Info.plist:21` through `:29`.

## Files Found

- `Sources/Mica/App/AppModelLiveSession.swift` - selected-generation lifecycle, REST refresh lanes, live producers, retry and failure handling.
- `Sources/Mica/App/AppModelLiveSessionRuntime.swift` - actor installation/invalidation and publication application.
- `Sources/Mica/App/LiveSessionRuntime.swift` - generation-owned raw ingestion and demand-gated publication.
- `Sources/Mica/App/LiveSessionRefreshModels.swift` - domain cadence and lane terminal state.
- `Sources/Mica/App/OperationSessionModels.swift` - session receipt timestamps and connection rate tracker.
- `Sources/Mica/Features/Workbench/WorkbenchChrome.swift` - destination-to-demand mapping.
- `Sources/Mica/Features/Workbench/WorkbenchConnections.swift` - duplicate-safe connection row identity.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift` - topology invalidation input.
- `Tests/MicaTests/LiveSessionPublicationTests.swift` - revision, pause, hidden-domain and flush coverage.
- `Tests/MicaTests/LiveSessionTransactionTests.swift` - retry-state coverage.
- `Tests/MicaTests/SessionRefreshCoordinatorTests.swift` - single-flight and terminal retry coverage.
- `Tests/MicaTests/SessionStreamStateTests.swift` - timeline and rate-derivation coverage.

## Related Specs

- `.trellis/spec/backend/controller-data-contract.md`
- `.trellis/spec/frontend/live-session-controller-contract.md`
- `.trellis/spec/frontend/workbench-ui-contract.md`

## External References

None. This was a source-and-contract audit; no external documentation or controller was used.

## Caveats / Not Found

- No automated check contacted a controller or invoked a remote action.
- This research subtask did not run the test suite; test evidence above is based on source inspection of existing tests.
- Pause/raw-retention, hidden-domain flush, same-domain stale revision rejection, and generic refresh coordinator retry behavior have direct test coverage and did not yield a confirmed defect in this audit.
- Controller switching and explicit generation end validate identity/generation and clear task/runtime state in the inspected paths; no confirmed switching or generation-leak bug was found.
- Capability gating is centralized and the inspected destinations consume the intended demand mapping; no confirmed capability bypass was found in this audit.
