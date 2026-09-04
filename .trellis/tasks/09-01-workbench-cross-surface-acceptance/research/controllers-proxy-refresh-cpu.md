# Research: Controllers Proxy Refresh CPU

- Query: Why does the authorized real Nikki session sustain roughly 100-143% CPU while Controllers is visible, and what is the smallest contract-compatible fix for the newly dominant `/proxies` decode branch?
- Scope: internal
- Date: 2026-09-02

## Findings

### Root Cause Summary

The old high-cardinality AppKit accessibility chain is absent from the new
sample. The new sample contains two concurrent costs during its 596-sample
window:

- The main thread is active for 596/596 samples in SwiftUI graph update and
  layout, principally the Controllers page/inspector. This remains a separate
  runtime/AX invalidation question.
- One background cooperative task spends 258/596 samples (about 43% of one
  core) in one `SessionRefreshCoordinator` medium-lane request. All 258 samples
  are inside `MihomoClient.proxies()` decoding; 218 reach
  `RawProxySnapshot.init(from:)`, and its recursive generic metadata decode is
  the dominant application branch.

The source-backed background diagnosis is therefore **the unconditional
five-second medium REST cadence amplified by expensive complete generic JSON
preservation**. It is not a duplicate proxy stream, overlapping lane request,
generation loop, or retry loop in this sample.

### Demand Ownership And Cadence

- Every Workbench window owns one stable demand token. The root registers,
  updates, and unregisters it on appear, destination change, and disappear
  (`Sources/Mica/Features/Workbench/WorkbenchChrome.swift:245-266`).
- Controllers maps to `LiveSessionVisibleDestination.other`
  (`WorkbenchChrome.swift:142-152`). `.other` observes no high-frequency
  publication domains (`Sources/Mica/App/LiveSessionRefreshModels.swift:4-25`),
  and the fixture contract asserts this explicitly
  (`Tests/MicaTests/LiveSessionPublicationTests.swift:44-52`).
- That demand only controls actor-backed presentation publication and immediate
  visibility flush. It does not own REST endpoint polling
  (`Sources/Mica/App/AppModelLiveSession.swift:90-129`,
  `Sources/Mica/App/AppModelLiveSessionRuntime.swift:78-144`).
- After the baseline, `startSessionRefreshCoordinator` always creates the
  medium and slow loops for a resolved non-sing-box session, regardless of
  visible destination (`AppModelLiveSession.swift:432-475`).
- The medium lane starts after two seconds and then runs every five seconds
  (`LiveSessionRefreshModels.swift:324-343`). Each loop waits for the current
  request to finish and only then sleeps for the interval
  (`AppModelLiveSession.swift:707-729`), so a slow decode cannot overlap with
  the next periodic iteration from that same loop.
- Mihomo medium refresh always calls `client.proxies()` and republishes policy
  groups/insight (`AppModelLiveSession.swift:838-886`). Controllers does not
  consume that catalog as a page requirement. The selected live session, not
  Controllers, is the current owner of the request.

Thus Controllers itself should not be described as demanding the proxy
catalog. The current architecture deliberately keeps the selected session's
REST lanes active independently of presentation visibility. Treating this as
REST visible-demand leakage would require a new product contract, not merely a
bug fix to the existing publication-demand model.

### Retry, Coalescing, Generation, And Streams

- `SessionRefreshCoordinator` permits one active flight per lane and at most
  one latest follow-up while the initial request is active
  (`Sources/Mica/App/SessionRefreshCoordinator.swift:109-163`, `:218-262`).
- Retries are iterative and back off only after an error
  (`SessionRefreshCoordinator.swift:265-333`). The sample contains the single
  `runAttempts -> refreshMihomoLane -> proxies` chain and no retry decision,
  backoff sleep, generation replacement, or second proxy flight.
- The periodic loop awaits the coordinator request. Manual refresh can join and
  reserve one follow-up, but the sample contains no evidence of that path.
- Mihomo live streams are logs, traffic, memory, and connections
  (`AppModelLiveSession.swift:1975-1992`, `:2143-2225`). There is no proxy-catalog
  WebSocket producer. Small WebSocket receive branches are present in the
  sample, but they do not call `MihomoClient.proxies()`.

Classification:

| Candidate | Result |
|---|---|
| Periodic refresh cadence | Confirmed trigger: medium lane requests `/proxies` every five seconds. |
| Expensive generic JSON preservation | Confirmed amplifier and dominant background application branch. |
| Overlapping proxy stream + poll | Rejected: no proxy stream exists. |
| Overlapping periodic requests | Rejected by await + lane single-flight; one request appears in the sample. |
| Generation/retry loop | Rejected for this sample; no replacement, error, or backoff frames. |
| Controllers presentation demand | Rejected: Controllers maps to `.other`, whose observed domain set is empty. |
| REST visible-demand leakage | Possible future redesign, but not the current contract: REST lane ownership is session-wide. |

### Why Decoding Is Expensive

- `MihomoClient.proxies()` must use the order-preserving decoder
  (`Sources/MicaCore/API/MihomoClient.swift:146-159`), as required by
  `.trellis/spec/backend/controller-data-contract.md:10-31`.
- `ProxiesResponse` decodes every proxy object into `RawProxySnapshot`
  (`Sources/MicaCore/Models/MihomoModels.swift:147-161`).
- `RawProxySnapshot` currently loops over every key and decodes every value into
  the indirect `MihomoJSONValue` tree before extracting known fields
  (`MihomoModels.swift:494-525`).
- `MihomoJSONValue.init(from:)` probes nil, Bool, Double, String, array, then
  object recursively (`MihomoModels.swift:590-612`). Large nested history and
  controller-specific metadata therefore pay repeated dynamic decode attempts,
  coding-path construction, allocations, and recursive containers.
- This work is not removable wholesale. Complete controller business fields are
  an accepted product requirement: the node HUD/inspector exposes typed known
  fields plus stable additional controller fields
  (`.trellis/spec/frontend/workbench-ui-contract.md:364-383`). Existing tests
  require unknown nested proxy metadata to survive
  (`Tests/MicaCoreTests/MihomoModelsTests.swift:244-300`) and also assert that
  known raw metadata remains available in the projected node detail
  (`Tests/MicaTests/WorkbenchTimelineAndProxyTests.swift:612-617`).

### Smallest Contract-Compatible Fix

Optimize only the `/proxies` DTO decode boundary first. Keep the five-second
medium cadence, source order, complete metadata, generation checks, endpoint
cache, publication semantics, and coordinator unchanged.

Recommended implementation boundary:

1. Replace `RawProxySnapshot`'s all-keys/all-generic decode with a specialized
   proxy-object decoder. Decode known hot fields (`type`, `now`, `all`, `alive`,
   `history`, icon/test/source/fixed/interface flags and transport booleans)
   directly into their typed representation.
2. Run recursive `MihomoJSONValue` decoding only for unknown controller fields.
   Reconstruct or retain the complete `ProxySnapshot.metadata` view so existing
   raw metadata tests, search, and HUD composition remain unchanged. Do not cap,
   stringify early, or drop nested unknown values.
3. Keep `ProxiesResponse.decodePreservingProxyOrder` and
   `JSONKeyOrderScanner`; no generic request helper or dictionary iteration may
   become the ordering authority.
4. Retain the change only with two comparable Release benchmark runs showing at
   least 10% improvement for a new large proxy-decode case and no repeated
   unrelated regression over 10%, per the Workbench performance contract.

An alternative single-pass structured implementation using
`JSONSerialization` plus a lossless `MihomoJSONValue` conversion could also
remove the repeated `Decodable` probing, but it has a larger semantic review
surface around `NSNumber`/Bool distinction, error paths, and the existing
decoder parameter. The typed-known/unknown-generic split is the narrower first
implementation.

Do not first gate the medium lane on Controllers visibility. A correct
demand-aware REST redesign would need a separate multi-window endpoint-demand
union, immediate refresh when a policy-consuming destination becomes visible,
manual-refresh bypass, retained stale values, generation-safe cancellation, and
a deliberate update to the current 2/5/30-second session contract. Reusing the
existing publication-domain set would conflate network ownership with UI
materialization and risks stale policy data when navigating.

### Main-Thread Layout Caveat

The decoder optimization targets only the measured 258-sample background
branch. The same capture has the main thread continuously inside SwiftUI layout
and Controllers composition, with repeated locale resolution also visible.
Because the background flight is still decoding and has not published its
result, that simultaneous main-thread work cannot be attributed solely to the
completion of this proxy refresh. Re-run a longer idle sample without an AX
request after the decoder change. If the main thread still remains busy, treat
Controllers observation/layout as a separate defect rather than expanding the
DTO change.

## Focused Tests And Benchmarks

- `MihomoModelsTests`: preserve wire key order, Unicode/escaped names, all known
  optional fields, nested unknown object/array/scalar/null metadata, numeric and
  Boolean distinction, missing fields, malformed payloads, and exact existing
  `ProxySnapshot.metadata` behavior after specialized decoding.
- Add a deterministic large `/proxies` fixture (for example 2,000 nodes plus
  groups, histories, and nested unknown metadata) to the Release benchmark.
  Measure `ProxiesResponse.decodePreservingProxyOrder`, report fixture checksum
  and work units, and compare two before/two after runs.
- Retain `SessionRefreshCoordinatorTests.duplicateManualAndPeriodicRequestsUseOneBoundedFollowUp`
  and retry/cancellation/generation tests; no coordinator behavior should change.
- Retain `LiveSessionPublicationTests.destinationsObserveOnlyTheirExpensiveLiveDomains`
  to prove Controllers/`.other` still creates no high-frequency presentation
  publication demand.
- Runtime acceptance, separately authorized: allow baseline to settle, leave
  Controllers idle for at least 15 seconds without issuing AX queries, capture
  CPU/sample, then issue one AX snapshot and measure drain. The decode branch
  should shrink materially, and the old `NSTableViewCellMockElement ->
  viewAtColumn` chain must remain absent. Do not invoke Test, Refresh, Update,
  Close, or any remote controller command.

## Files Found

- `tmp/codex/runtime-ax-acceptance-20260902/controllers-high-cpu.sample.txt` - 596-sample runtime capture with concurrent Controllers layout and one medium-lane proxy decode.
- `Sources/Mica/App/LiveSessionRefreshModels.swift` - visible publication domains plus 2/5/30-second REST lane cadence.
- `Sources/Mica/App/AppModelLiveSession.swift` - session-wide lane startup, periodic loop, medium `/proxies` request, and live stream ownership.
- `Sources/Mica/App/SessionRefreshCoordinator.swift` - per-lane single-flight, one-follow-up coalescing, retry, and generation cancellation.
- `Sources/Mica/App/AppModelLiveSessionRuntime.swift` - visibility-controlled high-frequency publication, separate from REST polling.
- `Sources/Mica/Features/Workbench/WorkbenchChrome.swift` - window demand lifecycle and Controllers-to-`.other` mapping.
- `Sources/MicaCore/API/MihomoClient.swift` - `/proxies` transport and order-preserving decoder boundary.
- `Sources/MicaCore/Models/MihomoModels.swift` - `ProxiesResponse`, `RawProxySnapshot`, and recursive `MihomoJSONValue` decode.
- `Sources/Mica/App/DashboardSessionModels.swift` - complete proxy metadata projection into policy/node UI state.
- `Tests/MicaTests/LiveSessionPublicationTests.swift` - current visible-domain demand contract.
- `Tests/MicaTests/SessionRefreshCoordinatorTests.swift` - coalescing, retry, cancellation, and generation coverage.
- `Tests/MicaCoreTests/MihomoModelsTests.swift` - order and complete proxy metadata coverage.
- `Tests/MicaTests/MicaPerformanceBenchmarkTests.swift` - existing proxy projection benchmarks; no proxy response decode benchmark was found.

## External References

No external references were required. The diagnosis uses the persisted local
sample, current source/tests, and active Trellis contracts.

## Related Specs

- `.trellis/spec/backend/controller-data-contract.md` - order-preserving proxy decode and complete controller business data.
- `.trellis/spec/frontend/live-session-controller-contract.md` - 2/5/30-second lanes, single-flight/coalescing, generation validation, and window publication demand.
- `.trellis/spec/frontend/workbench-ui-contract.md` - complete proxy field composition, inactive-view projection discipline, and two-run Release benchmark gate.

## Caveats / Not Found

- The sample is a short 596-sample capture. It proves one expensive proxy decode
  and one simultaneous main-thread layout interval, but cannot by itself prove
  the long-run duty cycle or distinguish idle layout from AX-request layout.
- No second `/proxies` request, retry/backoff, generation replacement, or proxy
  stream was found in the sample.
- The real response size and field distribution are not persisted, so the
  expected decoder speedup must be established with a representative generated
  fixture and the authorized runtime comparison.
- No source test currently benchmarks `ProxiesResponse` decoding directly.
- No controller was contacted, Mica was not run, and no product source or spec
  file was modified during this research.
