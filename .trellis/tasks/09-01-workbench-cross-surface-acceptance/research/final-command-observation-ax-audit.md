# Research: Final command, observation, and accessibility boundary audit

- Query: Audit the current shared worktree after the latest Workbench/AppModel changes for residual remote-command admission and owner-marker bugs, stale target resolution, Refresh/Test flow defects, Overview topology/active-connection performance regressions, accessibility payload boundaries, and obsolete compatibility paths.
- Scope: internal
- Date: 2026-09-04
- Snapshot: source read on 2026-09-04 while another agent was still finishing AppModel tests; no controller/runtime operation was invoked.

## Files Found

- `Sources/Mica/App/AppModel.swift` - public Mihomo/shared command entry points, command admission, target resolution, and Test ownership.
- `Sources/Mica/App/AppModelSelectionState.swift` - shared live-action predicate, busy families, cancellation, and Surge log-level command.
- `Sources/Mica/App/AppModelLiveSession.swift` - public user Refresh and internal refresh coordination.
- `Sources/Mica/App/AppModelLiveSessionRuntime.swift` - domain publication into observable catalog snapshots.
- `Sources/Mica/App/AppModelSurgeOperations.swift` - Surge command executors and defensive reload admission.
- `Sources/Mica/App/AppModelSingBoxOperations.swift` - sing-box command executors.
- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift` - Overview active-connection loader, session scope, navigation, and request token.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift` - narrow topology request, deferred structure capture, bounded topology accessibility representation, and navigation.
- `Sources/Mica/Features/Workbench/WorkbenchDataPresentation.swift` - detached, bounded, equatable accessibility payload model.
- `Sources/Mica/Features/Workbench/WorkbenchDataShared.swift` - table accessibility host and the retained text-style compatibility bridge.
- `Tests/MicaTests/AppModelCommandBoundaryTests.swift` - command owner, Refresh/Test, current-target, and ordinary Mihomo Test regressions.
- `Tests/MicaTests/WorkbenchOverviewPerformanceTests.swift` - Overview request equality, structure Observation, cancellation, and source-boundary checks.

## Findings

### P1 - Same-controller old-generation command intent cannot be rejected at the AppModel boundary

Evidence:

- `Sources/Mica/App/AppModel.swift:697-704` documents stale-generation rejection, but `admitLiveActionIntent` accepts no caller scope and validates `router.id` against `controllerSession.generation`, which is the generation being validated. For the same selected controller ID, the generation half of this guard is necessarily current and cannot distinguish an intent captured before a reconnect/session replacement.
- `Sources/Mica/App/AppModelSelectionState.swift:272-286` has the same shape for the pure `canBeginLiveAction`: selected/current controller ID, readiness, pause, and capability are checked, but no captured generation enters the function.
- Public command APIs such as `setMode` and `selectNode` (`Sources/Mica/App/AppModel.swift:725-739` and `:808-835`) accept only command/entity values. Their sing-box executors (`Sources/Mica/App/AppModelSingBoxOperations.swift:12-29` and `:85-113`) capture the generation only after admission. Consequently an old closure that survives a same-controller generation replacement can submit a command to the replacement session when the target value/entity is still valid.
- This contradicts `.trellis/spec/frontend/live-session-controller-contract.md:176-179`, which requires stale clicks, reconnects, and direct dispatcher calls to be rejected inside AppModel immediately before task/client creation. It also falls short of `.trellis/spec/frontend/workbench-ui-contract.md:182-185` for delayed editable/destructive intents.

Reproduction:

1. Capture controller ID, generation, and a still-valid node/mode command from generation A.
2. Begin generation B for the same controller ID and restore live state with identical policy/config data.
3. Invoke the old command closure. Because the public API has no generation argument, admission evaluates generation B against itself and creates the generation-B task/client.

Suggested correction:

- Introduce a small immutable command scope containing controller ID and generation, pass it from delayed/dispatcher call sites into public AppModel command entry points, and validate that scope before marker mutation, task creation, or client creation.
- Keep current entity resolvers as an additional current-target check; they cannot replace generation identity when data is unchanged across generations.
- Make family-specific executors private or require an already-validated typed admission token so direct internal/test calls cannot bypass the public boundary.

Missing tests:

- For Mihomo, Surge, and sing-box, capture generation A, replace it with generation B for the same controller, invoke A's intent with unchanged data, and assert zero transport calls, no task/marker creation, and no operation outcome mutation.
- Exercise direct family executor entry where its access level permits it, not only disabled-button UI paths.

### P2 - Overview active-connections loader still observes the entire catalog on every catalog assignment

Evidence:

- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:677-687` creates the loader request inside `body`.
- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:754-768` reads `appModel.connectionsCatalog.metricsRevision`. Because `connectionsCatalog` is one stored property of the `@Observable` AppModel (`Sources/Mica/App/AppModel.swift:105-120`), this registers Observation on that whole property, not on an independently observable nested revision.
- Traffic-only frames still replace the whole snapshot at `Sources/Mica/App/AppModelLiveSessionRuntime.swift:463-491`; synchronous publications do the same at `Sources/Mica/App/AppModel.swift:584-602`. The metric revision remains equal, so `.task(id:)` ordinarily does not restart, but the hidden loader body is nevertheless invalidated at traffic cadence.
- The topology path already demonstrates the correct boundary: `OverviewTopologyCatalogRequest.observing` reads the independent scalar `connectionsStructureRevision` at `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift:66-77`, and `Tests/MicaTests/WorkbenchOverviewPerformanceTests.swift:198-226` proves metric/traffic publications do not invalidate that observation.
- `Tests/MicaTests/WorkbenchOverviewPerformanceTests.swift:45-82` checks only value equality for the highlight request. It does not use `withObservationTracking`, so it cannot detect the extra SwiftUI invalidation.

Reproduction:

1. Wrap `OverviewConnectionHighlightsRequest.observing(model, maximumCount: 3)` in `withObservationTracking`.
2. Publish a traffic-only connections-domain update that leaves connection metrics unchanged.
3. The on-change callback fires even though a newly constructed request compares equal to the old value.

Suggested correction:

- Add an AppModel-level `connectionsMetricsRevision` scalar updated only when connection metrics/structure change, mirroring `connectionsStructureRevision`, and have the Overview request observe that scalar.
- Keep the full `connectionsCatalog.connections` read inside the cancellable task after request revalidation, as it is now.

Missing tests:

- Observation tracking around the complete highlight request: traffic-only publication must cause zero invalidations; metric-only and structure changes must each invalidate once.
- Retain the existing request equality and cancellable projection tests; equality alone is not an Observation regression test.

### P3 - Obsolete text-style compatibility shim remains in active Workbench code

Evidence:

- `Sources/Mica/Features/Workbench/WorkbenchDataShared.swift:297-357` defines `MicaTextStyle` and a runtime `themeRole(for:design:)` mapper explicitly to keep old call sites stable. Its comments call it a transitional bridge even though the referenced earlier phases are complete.
- The active UI contract says no previous View/helper/file split is a compatibility requirement at `.trellis/spec/frontend/workbench-ui-contract.md:10-12`; the active task also prohibits compatibility layers.

Suggested correction:

- Make `WorkbenchDataText` accept `MicaTheme.TextRole` directly, migrate the remaining call sites, and delete `MicaTextStyle` plus `themeRole(for:design:)`.

Missing test:

- Add a source-verifier assertion that the transitional type and mapper are absent after migration.

## Confirmed Repairs / No New Source Finding

- **Test owner lifecycle:** the ordinary Mihomo branch now has the same token-gated `defer finishSelectedRouterTest` cleanup as override, auto-detect, and Surge (`Sources/Mica/App/AppModel.swift:2339-2413`). `Tests/MicaTests/AppModelCommandBoundaryTests.swift:408-461` now covers ordinary failure cleanup and prevents an old cancelled task from clearing a newer owner. The previously observed permanent busy marker is repaired in the current tree.
- **Public versus internal Refresh:** user Refresh remains capability/readiness/busy-gated and owner-scoped while internal immediate refresh can coalesce without impersonating user intent. `Tests/MicaTests/AppModelCommandBoundaryTests.swift:291-368` covers connecting/stale/busy rejection, duplicate user Refresh, internal refresh, and owner cleanup. No additional source-proven defect was found.
- **Surge reload helper:** `reloadSurgeRules` now has selected-router/runtime/task/family/live/capability/pause guards before command/task creation (`Sources/Mica/App/AppModelSurgeOperations.swift:331-349`).
- **Current-target resolution:** rule mutation requires a unique exact current rule; connection mutations resolve current occurrences and preserve current controller order. No stale-index/metric-drift defect was found in the reviewed paths.
- **Overview topology:** the topology observes only controller/generation/structure scalar in its body, captures the full catalog after a yield and revalidation, hides cross-session input, and uses bounded/cancellable projection. No new source-proven rebuild, cancellation, or navigation defect was found.
- **Detached/equatable AX payloads:** `WorkbenchTableAccessibilityPayload.materialize` resolves and materializes only the bounded window (`Sources/Mica/Features/Workbench/WorkbenchDataPresentation.swift:584-689`); `WorkbenchTableAccessibilityHost` equality depends only on that payload and its representation is non-hit-testing (`Sources/Mica/Features/Workbench/WorkbenchDataShared.swift:18-37`). Table dispatchers reviewed revalidate controller/generation and visible current targets. No new source-proven unbounded payload or stale-dispatch defect was found.

## Related Specs

- `.trellis/spec/frontend/live-session-controller-contract.md:163-179` - paused Test/Refresh behavior and AppModel command-boundary validation.
- `.trellis/spec/frontend/workbench-ui-contract.md:10-12` - obsolete UI helper compatibility is not required.
- `.trellis/spec/frontend/workbench-ui-contract.md:175-185` - narrow observation and captured controller/generation for delayed actions.
- `.trellis/spec/frontend/state-management.md:63-64` - async commands revalidate controller ID and generation before observable mutation.
- `.trellis/spec/backend/controller-data-contract.md:41-53` - capability-gated, typed, cancellable, generation-safe controller operations.

## Caveats / Not Found

- No P0 issue was found in the reviewed source.
- This was a static, read-only audit of a shared tree changing concurrently. Line numbers and the command findings should be rechecked after the in-progress AppModel test patch settles.
- No app/controller/runtime was started. The open authorized acceptance item at `.trellis/tasks/09-01-workbench-cross-surface-acceptance/implement.md:149-151` remains: repeat populated Connections and Overview AX snapshots and confirm bounded completion plus CPU recovery. Static payload boundaries cannot prove AppKit/SwiftUI runtime AX behavior.
- No network operation, controller command, Git operation, or product/spec/task-file edit was performed by this research pass.

## Post-Audit Resolution

- The same-controller stale-intent finding was reclassified from P1 to P2 after
  a complete call-graph pass: reproduction required retention of an old closure,
  while existing Connections, Actions, and Tailscale typed intents already
  synchronously revalidated their captured identity. The contract gap was still
  real and is now closed with required `LiveCommandScope` inputs for persisted
  Configuration, Rules, Proxy, and Logs handlers.
- A fresh checker found two omissions after the first scope pass: the Surge Logs
  level Picker and Proxy AX group-toggle/Locate Current workspace effects. Both
  now carry the originating controller/generation and reject before any local or
  remote side effect.
- The Overview finding is resolved by the standalone
  `connectionsMetricsRevision` token and Observation regressions; traffic-only
  catalog publication no longer invalidates the highlights request.
- The text-style compatibility finding is resolved: Workbench data text accepts
  `MicaTheme.TextRole` directly, and the old style enum/mapper cannot pass the
  source verifier.
- The remaining runtime item is unchanged: static and offline checks cannot
  prove AppKit AX completion/CPU recovery. A populated read-only repeat still
  requires explicit permission and must invoke no controller command.
