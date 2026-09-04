# Research: Dashboard Equality Publication Hotspot

- Query: Does the `AppModel.performSessionRefresh` -> `publishMihomoPresentation` -> Observation equality chain explain slow Proxies accessibility reads and stale-looking live data, and what is the smallest contract-safe fix?
- Scope: internal
- Date: 2026-09-03

## Findings

### Runtime evidence

The new sample is causal evidence for a major main-actor publication cost, not merely a coincidental leaf symbol:

- `tmp/codex/proxies-bounded-ax.sample.txt:24-38` contains 2,521 main-thread samples. The medium refresh flight owns 1,331 samples (52.8%).
- The first publication branch spends 461 samples in `AppModel.dashboard.setter -> shouldNotifyObservers -> DashboardSnapshot.==` (`tmp/codex/proxies-bounded-ax.sample.txt:34-46`). This is 18.3% of all captured main-thread samples.
- The immediately following domain synchronization spends another 450 samples in `synchronizePolicyGroupCatalog -> PolicyGroupCatalogSnapshot.==` (`tmp/codex/proxies-bounded-ax.sample.txt:737-749`). This is 17.9% of all captured main-thread samples.
- Together, those two equality walks account for 911 samples: 36.1% of the complete main-thread capture and 68.4% of the sampled medium-refresh branch.
- Both walks descend through `ProxyGroupViewState.optionDetails`, `ProxyNodeViewState.metadata` / `reportedMetadata`, and recursive `MihomoJSONValue` dictionaries and arrays. The sample repeatedly terminates in `MihomoJSONValue.__derived_enum_equals`, `Dictionary.==`, and `Array.==`, rather than network I/O or proxy decoding.

The worst case is an unchanged controller response. The Observation setter must traverse the complete old/new dashboard before suppressing the assignment, then `synchronizePolicyGroupCatalog` traverses the same policy graph again before its guard returns. The Mihomo medium lane fetches `/proxies` every five seconds (`Sources/Mica/App/LiveSessionRefreshModels.swift:329-333`, `Sources/Mica/App/AppModelLiveSession.swift:850-861`), so this is a periodic main-actor stall.

This materially explains Proxies AX/read latency: an AX request and SwiftUI updates must share the blocked main actor, so the bounded AX subtree can still wait behind this refresh work. It also plausibly explains temporary "not moving" presentation across surfaces because accepted runtime publications and SwiftUI invalidation queue behind the equality walk. It does **not** prove that networking or actor ingestion is stale, and it is not the only AX cost; if timestamps still fail to advance after this stall is removed, publication counters and controller payloads need a separate check.

### Why `dashboard` can leave Observation

`AppModel.dashboard` is now an internal aggregate/source snapshot, while the active UI contract is per-domain publication:

- The state contract requires views to observe presentation mirrors and domain catalogs rather than broad session state (`.trellis/spec/frontend/state-management.md`, Server State).
- Workbench production views have no direct `appModel.dashboard` read. Proxies observes `policyGroupCatalog` (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:89-103`); other surfaces use `controllerMetadata`, `connectionsCatalog`, `routingCatalog`, and `insightCatalog`.
- Whole-dashboard assignment is immediately followed by domain publication in `publishMihomoPresentation` (`Sources/Mica/App/AppModelLiveSession.swift:1251-1258`), baseline commit (`Sources/Mica/App/AppModelLiveSession.swift:1761-1767`), sing-box publication (`Sources/Mica/App/AppModelLiveSession.swift:2582-2587`), and `replaceDashboard` (`Sources/Mica/App/AppModel.swift:532-535`). In-place session mutations publish named domains through `mutateSessionDashboard` (`Sources/Mica/App/AppModelSingBoxOperations.swift:632-643`).

Therefore `@ObservationIgnored var dashboard` is contract-safe **after** all presentation-time indirect reads are moved to their owning observable domains. It is not safe as an isolated one-line edit. The remaining indirect dependencies are:

- `coreCompatibilitySummary` falls back to `dashboard.versionLabel` (`Sources/Mica/App/AppModelReadiness.swift:86-94`); use `controllerMetadata.versionLabel`.
- endpoint/check result projections use `dashboard.hasBaseSnapshot` (`Sources/Mica/App/AppModelEndpointChecks.swift:4-17,87-99`); derive one `hasPublishedBaseSnapshot` from `controllerMetadata`, `policyGroupCatalog`, and `connectionsCatalog`.
- diagnostics presentation/export reads dashboard counts/config/insight (`Sources/Mica/App/AppModelDiagnostics.swift:75-118,121-166,224-292`) through `snapshotStatsDiagnostics` (`Sources/Mica/App/AppModelSelectionState.swift:190-197`); read the corresponding domain catalogs. Export functions may read internal state on demand, but anything evaluated from `WorkbenchDiagnosticsView.body` must have domain-owned observation dependencies.

Ignoring `dashboard` removes the 461-sample full-dashboard Observation comparison and makes storage replacement unconditional, so the latest controller payload is retained. It does not remove the independent 450-sample policy-catalog equality guard.

### Minimal complete fix

1. Mark `AppModel.dashboard` `@ObservationIgnored`, document it as the non-observable aggregate feeding named domain catalogs, and migrate the indirect readiness/diagnostics dependencies listed above.
2. Keep `PolicyGroupCatalogSnapshot` change suppression. Do not publish/rebuild Proxies unconditionally every five seconds; that would trade equality stalls for guaranteed high-cardinality projection churn.
3. Replace recursive raw-metadata equality inside `ProxyNodeViewState` with an exact precomputed comparison representation created once during projection. A canonical sorted-key `Data` or string for the **complete** `metadata` payload can be compared with the typed scalar/history fields. Retain the raw `metadata` and derived `reportedMetadata` unchanged for inspection. If canonical encoding is unavailable, fall back to the existing deep equality so observation correctness is never weakened.
4. Do not use only `additionalMetadataText`: it deliberately excludes known controller keys (`Sources/Mica/App/DashboardSessionModels.swift:1004-1041`) and could treat different optional/raw controller payloads as equal. Do not use a hash alone because collisions could suppress a real update. Do not make `DashboardSnapshot.==` shallow: the Observation setter would then suppress the storage assignment itself and retain old controller data.

The exact comparison key belongs in `ProxyNodeViewState` (`Sources/Mica/App/DashboardSessionModels.swift:871-1035`), where both raw metadata and the existing sorted additional-metadata text are already derived. This preserves controller order, optionality, all inspector fields, the policy catalog revision contract, and the existing Proxies interaction scheduler.

### Affected files and tests

Likely production files:

- `Sources/Mica/App/AppModel.swift`: ignore the aggregate dashboard; retain named-domain synchronization.
- `Sources/Mica/App/DashboardSessionModels.swift`: exact, precomputed proxy-node metadata equality representation and custom `ProxyNodeViewState.==`.
- `Sources/Mica/App/AppModelReadiness.swift`: read version from `controllerMetadata`.
- `Sources/Mica/App/AppModelEndpointChecks.swift`: derive base-snapshot readiness from published domains.
- `Sources/Mica/App/AppModelSelectionState.swift` and `Sources/Mica/App/AppModelDiagnostics.swift`: diagnostics counts/config/insight from the domain catalogs.
- `scripts/verify-real-controller-source.mjs`: reject direct Workbench observation of `dashboard` and require the aggregate to remain ignored/domain-published.

Required focused coverage:

- `LiveSessionPublicationTests`: identical policy payload does not advance `policyGroupCatalogRevision`; a nested metadata-only change does advance it exactly once and updates both raw `dashboard` storage and `policyGroupCatalog`; pause/resume and generation rejection remain unchanged.
- `WorkbenchTimelineAndProxyTests` or a focused model suite: equal large nested metadata compares equal; a nested leaf, known-field optionality, history, fixed selection, or transport change compares unequal; unencodable/non-finite test metadata takes the correctness fallback.
- readiness/diagnostics tests: version compatibility, base-snapshot state, counts, config, and insight still update from their owning catalogs without observing `dashboard`.
- Add a 2,000-node policy-catalog equality benchmark to `MicaPerformanceBenchmarkTests`; retain the change only with matching work/checksum and two comparable Release runs under the Workbench 10% rule.
- Repeat the authorized read-only Proxies AX state read and process sample. The equality chain should disappear from the dashboard setter and recursive JSON equality should no longer dominate policy synchronization.

## Files Found

- `tmp/codex/proxies-bounded-ax.sample.txt` - runtime sample proving two consecutive deep equality walks on the main actor.
- `Sources/Mica/App/AppModelLiveSession.swift` - medium `/proxies` refresh and dashboard/domain publication sequence.
- `Sources/Mica/App/AppModel.swift` - observable aggregate plus per-domain catalog synchronization and policy revision.
- `Sources/Mica/App/DashboardSessionModels.swift` - synthesized dashboard/group/node equality and raw/derived proxy metadata ownership.
- `Sources/MicaCore/Models/MihomoModels.swift` - recursive `MihomoJSONValue` and complete `ProxySnapshot.metadata` payload.
- `Sources/Mica/Features/Workbench/WorkbenchProxies.swift` - Proxies consumes `policyGroupCatalog`, not `dashboard`.
- `Sources/Mica/App/AppModelReadiness.swift` - indirect presentation dependency on dashboard version.
- `Sources/Mica/App/AppModelEndpointChecks.swift` - indirect presentation dependency on dashboard baseline state.
- `Sources/Mica/App/AppModelDiagnostics.swift` - diagnostics presentation/export dependencies on broad dashboard data.
- `Sources/Mica/App/AppModelSelectionState.swift` - dashboard-backed diagnostics aggregate.

## External References

None. The generated Observation stack in the macOS 27 / Swift 6.2 runtime sample and current project source are the authoritative evidence for this issue.

## Related Specs

- `.trellis/spec/frontend/state-management.md` - views observe immutable per-domain presentation mirrors.
- `.trellis/spec/frontend/live-session-controller-contract.md` - five-second medium lane, generation validation, last-good retention, and named publication semantics.
- `.trellis/spec/frontend/workbench-ui-contract.md` - inactive-surface projection isolation, Proxies deferral, bounded accessibility, and two-run performance retention rules.

## Caveats / Not Found

- The sample proves main-actor publication delay but does not prove that controller values themselves changed during the capture.
- `@ObservationIgnored` is safe only while every new dashboard mutation publishes its owning domain and future views are prohibited from reading the aggregate directly.
- A canonical full-metadata key adds allocation/encoding work and memory. Measure end-to-end projection plus equality; do not retain it based only on micro-level intuition.
- No production source was modified by this research pass.
