# Mica Post-Refactor Integration Audit Report

Audit date: 2026-08-16

## 1. Scope And Safety

This report audits the final combined working tree after the baseline global
functional fixes and the complete Overview replacement. Evidence is local-only:
source inspection, deterministic fixtures, in-process transports, Swift build
and tests, source contracts, localization/Info.plist parsing, and the Apple HIG
contrast checker.

No configured controller was contacted, no remote operation was invoked, no
network or router setting was changed, and no credential, authorization value,
raw response, or stream body was recorded. Runtime visual smoke was not run
because it requires explicit user authorization.

## 2. Entry Conditions

| Gate | Evidence | Result |
|---|---|---|
| Baseline global audit complete | `08-16-global-functional-audit/task.json` is `completed`; its report has no unresolved Critical/High/Medium finding | Pass |
| Overview replacement code-complete | Fixed composition, preferences, runtime, HUD, finite motion, localization, tests, verifier, and durable contracts are present | Pass |
| Legacy deletion complete | Four legacy Overview production files and the legacy personalization test are deleted; repository searches find no active reference | Pass |
| Final working-tree inventory captured | `git diff --name-status`, source list assertion, and untracked-file review completed without touching unrelated skill links | Pass |

## 3. Final Automated Gate

| Check | Result | Evidence |
|---|---|---|
| Source script syntax | Pass | `node --check` passed for source verifier and optional runtime-smoke script |
| Source contract | Pass | `Mica native workbench source contract passed` |
| Localization JSON | Pass | `python3 -m json.tool` parsed `Localizable.xcstrings` |
| Info.plist | Pass | `plutil -lint` reported OK |
| HIG contrast | Pass | `hig_checker.py` score 100, zero violations |
| Isolated Swift build | Pass | `swift build --scratch-path tmp/codex/swift-build` completed |
| Full Swift tests | Pass | 305 tests in 27 suites, 0 failures |
| Focused Overview/performance tests | Pass | 24 Overview tests plus the Surge near-live publication regression passed |
| Diff whitespace | Pass | `git diff --check` exited 0 |
| Runtime visual smoke | User-run / not executed | Explicit permission was not provided; no automated dependency was hidden behind it |

## 4. Final Application Coverage Matrix

Every row has a terminal result against the final code, not the pre-refactor
snapshot.

| ID | Area | Inspected files / flows | Evidence | Result |
|---|---|---|---|---|
| A01 | Package, dependencies, resources | `Package.swift`, resources, Info.plist | isolated build, plist/localization checks | Pass |
| A02 | Localization and language | XCStrings, resolver, direct-key verifier | JSON parse, resolver tests, source contract | Pass |
| A03 | Profiles and endpoint validation | `RouterProfile`, store, editor/AppModel save paths | profile/client/store tests | Pass |
| A04 | Secrets and privacy | secret stores, export/diagnostics boundaries | secret tests and source verifier | Pass |
| A05 | Probe routing and cancellation | HTTP resolver plus sing-box fallback | resolver cancellation/family tests | Pass |
| A06 | Mihomo transport | HTTP/WebSocket reads and mutations | Mihomo contract/model/fallback tests | Pass |
| A07 | Nikki | detected variant, shared Mihomo transport, capability matrix | variant/session/capability tests | Pass |
| A08 | OpenClash | detected variant, shared Mihomo transport, capability matrix | resolver/variant/runtime tests | Pass |
| A09 | CMFA/Stash | delay fallback, optional data, restricted writes | fallback and capability tests | Pass |
| A10 | sing-box | StartedService gRPC, streams, Tailscale independence | in-process gRPC/readiness/stream tests | Pass |
| A11 | Surge | HTTP API, polling, optional recent requests, visible near-live timelines | Surge client/session/operation/publication tests | Pass — F-003 fixed |
| A12 | Unified ordering and optionality | DTOs, adapters, policy/source projections | controller model and presentation tests | Pass |
| A13 | Selected controller and generation | AppModel selection, replacement, stale completion | transaction/publication/navigation tests | Pass |
| A14 | Refresh, retry, reconnect, teardown | refresh coordinator and runtime task tree | coordinator/runtime cancellation tests | Pass |
| A15 | Profile mutation serialization | load/save/delete/reorder/connection metadata | failing-store and interleaving tests | Pass |
| A16 | Window demand and shell | `MicaApp`, `ContentView`, Chrome lifecycle | multi-window demand/navigation tests | Pass |
| A17 | Router editor close safety | window close guard and pending editor intents | source contract and transaction tests | Pass |
| A18 | Overview | fixed composition, telemetry, topology, preferences, HUD | focused tests and seam matrix below | Pass — F-001–F-004 fixed |
| A19 | Proxies | ordered groups, node details, selection gates | proxy workspace/capability tests | Pass |
| A20 | Connections | active/closed rows, close safety, staged navigation | data/cache/mutation/navigation tests | Pass |
| A21 | Logs | bounded buffers, deltas, pause/follow | stream/runtime/data tests | Pass |
| A22 | Rules | ordering, hit projection, mutation/navigation | data/navigation/capability tests | Pass |
| A23 | Sources | provider order, Update All, health/update gates | provider batch/data tests | Pass |
| A24 | Controllers and Configuration | management selection and capability-gated writes | management/transaction/variant tests | Pass |
| A25 | Actions and Tailscale | effective availability and dispatcher boundaries | management/readiness/runtime tests | Pass |
| A26 | Diagnostics | causal issues, safe evidence, freshness | management/runtime/endpoint tests | Pass |
| A27 | Settings, accessibility, keyboard | native Settings, font/language/appearance, focus and VoiceOver | preference tests, source verifier, HIG checker | Pass |
| A28 | Performance and invalidation | timelines, projection caches, topology bands/hits/HUD | performance suites and operation-count assertions | Pass — F-001/F-003 fixed |

## 5. Controller-Family Matrix

| Family | Adapter / session | Capability, order, optionality | Final result |
|---|---|---|---|
| Mihomo | HTTP + WebSocket generation tree | Full verified Mihomo subset; reported policy/provider order retained | Pass |
| Nikki | Mihomo-compatible transport with Nikki identity | Nikki-specific detected variant; no unsupported command widening | Pass |
| OpenClash | Mihomo-compatible transport with OpenClash identity | OpenClash capability boundary and ordering retained | Pass |
| CMFA / Stash | Mihomo-compatible reads with variant restrictions | Delay fallback retained; unsupported runtime/configuration writes remain gated | Pass |
| sing-box | Native StartedService gRPC | Structured streams and Tailscale independence retained; no Mihomo command leakage | Pass |
| Surge | Surge HTTP API and near-live polling | Surge-only dispatcher, optional recent requests, reported request order retained | Pass |

## 6. Overview Integration-Seam Matrix

| Seam | Evidence | Result |
|---|---|---|
| One global preference authority | `MicaApp.swift:24`; shared-store round-trip/multi-consumer test | Pass |
| Window-local transient runtime | `WorkbenchWindow.swift:24,93-94`; distinct window-demand/runtime identity test | Pass |
| Session isolation | registry keys contain controller ID + generation; runtime clears on stopped state | Pass |
| Fixed hierarchy | `WorkbenchDashboard.swift:124,131,136` orders telemetry, topology, optional modules | Pass |
| Fresh default | all metrics, five minutes, no optional modules | Pass |
| Old data reset | `mica.overview.fixed-core.v1`; wrong/old schema test returns default without migration | Pass |
| Immediate preferences | checkbox/segmented controls write directly; no draft, Done, Cancel, Undo, reorder, or resize | Pass |
| Real telemetry only | current values read latest received samples; plot cache owns history; cumulative connection totals are rejected as rates | Pass |
| Complete topology | every active path/hop, width-fitted Canvas bands, indexed hit tests | Pass |
| Policy resolution | exact unique group/member lookup; duplicate/missing becomes truthful route detail | Pass |
| HUD geometry | O(1) `nodeGeometryByID`, precomputed HUD obstacles, four-side score and clamp tests | Pass |
| Interaction semantics | hover precedence, complete hover fields, pin persistence, blank tap, Escape, keyboard path stepping | Pass |
| Accessibility | policy-node and path controls expose values, pin state, and navigation | Pass |
| Cross-tab navigation | session-bound Connections staging and same-window Proxies navigation | Pass |
| No hover network work | Overview/HUD sources contain no controller client/transport request | Pass |
| Invalidation isolation | catalog revision rebuilds inspection index only; hover/pin does not rebuild topology/layout | Pass |
| Bounded motion | finite sample/structure/traffic/metrics/selection triggers; no `TimelineView`, timer, or repeating animation | Pass |
| Static states | Reduce Motion, inactive window, local/global pause resolve to static presentation | Pass |

## 7. Legacy-Removal Proof

| Removed concept | Proof | Result |
|---|---|---|
| Generic layout/preset/size/row packing | production and tests contain no active symbol; verifier rejects reintroduction | Removed |
| Per-controller override/inheritance/cleanup | store/coordinator files deleted; global preference model has no controller ID | Removed |
| Draft/conflict/commit/Undo workflow | window/editor coordination deleted; old localization keys removed | Removed |
| Lossy migration/compatibility shim | new schema accepts only compact preferences; invalid data returns default | Removed |
| Fixed 80-point topology detail inset | type and layout constant deleted; HUD is an overlay over stable graph geometry | Removed |
| Old localization and tests | all `overview.layout_*` entries and personalization tests removed | Removed |
| Stale documentation/contracts | Workbench spec, architecture, UI guidelines, and verifier describe only final v1 | Removed |

Negative references to removed symbol names remain only in source/test assertions
whose purpose is to prevent their return.

## 8. Findings And Remediation

All verified Critical/High/Medium findings are resolved.

### F-001 — Medium — HUD cache hits scaled with the complete policy catalog

- Observable impact: pointer hover/pin updates on a large policy catalog could
  repeatedly deep-compare every group/member metadata value and allocate every
  node/label obstacle rectangle, creating avoidable dense-topology hitches.
- Pre-fix path: `OverviewPolicyInspectionCache.resolve` compared a retained
  `PolicyGroupCatalogSnapshot` with full `Equatable`; the HUD overlay rebuilt
  obstacle arrays from `layout.nodes` on each evaluation.
- Root fix: AppModel now publishes a scalar catalog revision
  (`AppModel.swift:78,413-417`); cache hits compare only that revision
  (`WorkbenchOverviewPolicyHUD.swift:109-127`). Topology layout precomputes HUD
  obstacles once (`WorkbenchOverviewTopology.swift:650`) and the overlay reuses
  them (`WorkbenchOverviewTopologyView.swift:503`).
- Focused validation: catalog-revision publication test, cache build/hit test,
  dense layout/hit tests, source ownership test, 24-test focused run, and final
  full suite all pass.

### F-002 — Medium — Current Swift toolchain crashed on a method-reference Binding setter

- Observable impact: the initial full build aborted in Swift IRGen with
  `SmallVector unable to grow`, so the redesigned application could not be
  produced by the repository's current Xcode toolchain.
- Reproduction: `swift build` while compiling
  `WorkbenchOverviewEditor.swift`; the generated thunk converted the direct
  `set: store.setTimelineWindow` method reference.
- Root fix: use an explicit setter closure at
  `WorkbenchOverviewEditor.swift:134`, preserving identical immediate behavior
  while avoiding the compiler defect.
- Focused validation: subsequent ordinary and isolated scratch builds pass;
  full tests pass.

### F-003 — Medium — Live semantics stopped at projection boundaries

- Observable impact: Overview rate-labelled readouts could display cumulative
  connection aggregates, route energy reacted only to connection-structure
  changes, and Surge one-second near-live frames could remain in the raw session
  snapshot without advancing visible timelines/catalogs.
- Pre-fix path: the instrument rail formatted
  `connectionsCatalog.traffic` with `/s`; topology energy used only
  `request.revision`; Surge called the visible publisher with `domains: []`.
- Root fix: current Overview values read latest received timeline samples;
  topology receives a separate traffic/metrics live signal without rebuilding
  structure; accepted Surge ticks publish `.connections` and advance visible
  traffic/count/rate/timestamp state together.
- Focused validation: same-ID/new-receipt cache regression, topology live-signal
  regression, Surge source-to-visible publication regression, source contract,
  24 Overview tests, and the 305-test full suite pass.

### F-004 — Medium — Hover HUD hid and capped requested node fields

- Observable impact: pointer hover showed only a summary; full typed fields were
  gated behind pinning and additional controller metadata was capped at three
  entries, contradicting the requested hover inspection behavior.
- Pre-fix path: `compactFields` rendered on hover, `expandedFields` rendered only
  when pinned, and metadata used `.prefix(3)` plus one joined string.
- Root fix: hover and pinned states share organized Overview, Transport, Testing,
  and Controller Fields sections. Ordered members, reported false transport
  states, typed node/test fields, and every additional field are visible; click
  now preserves the HUD instead of unlocking detail.
- Focused validation: HUD projection requires identical hover/pinned sections,
  false transport state, and four uncapped additional fields; placement,
  accessibility projection, source contract, and full suite pass.

### Verification-only correction

One architecture test incorrectly required `OverviewMotionState.resolve` to be
called from the same source file that defines it. The production split was
correct; the test now verifies the definition in the visual system and calls in
the combined Overview source. The focused test and full suite pass. This was not
a product defect.

## 9. Parent Acceptance Mapping

| Parent AC | Evidence | Result |
|---|---|---|
| AC-01–04 | fixed hierarchy/default, compact global store, schema fallback tests | Pass |
| AC-05 | semantic cyan/violet opaque surfaces, HIG 100, no content glass | Pass by source/contrast evidence; runtime visual smoke remains user-run |
| AC-06 | finite sample/route triggers and static-state tests | Pass |
| AC-07–10 | unique policy projection, complete hover/pinned HUD, placement/ambiguity tests | Pass |
| AC-11 | no client calls; revision/index/layout operation-count evidence | Pass |
| AC-12 | keyboard, accessibility, pause/expand, hit/cache/navigation tests | Pass |
| AC-13 | deletion/search/verifier/localization proof | Pass |
| AC-14 | build, 305 tests, focused tests, localization/HIG/source/diff gates | Pass |
| AC-15–17 | complete final matrices, findings, post-refactor audit | Pass |
| AC-18 | baseline child complete; final child has no unresolved blocker | Pass after task status closure |

## 10. Child Acceptance Mapping

| Child AC | Evidence | Result |
|---|---|---|
| AC-01 | both entry gates recorded in section 2 | Pass |
| AC-02–03 | sections 4 and 5 cover every surface and controller family | Pass |
| AC-04–08 | section 6 ownership, session, request, geometry, and motion evidence | Pass |
| AC-09 | section 7 source/test/localization/docs removal proof | Pass |
| AC-10 | non-Overview rows A16–A27 plus full suite | Pass |
| AC-11 | F-001–F-004 fixed; no unresolved Critical/High/Medium; no Low finding | Pass |
| AC-12 | section 3 final automated gate | Pass |
| AC-13 | local-only safety statement and no runtime smoke | Pass |
| AC-14 | parent/child mapping and terminal conclusion | Pass |

## 11. Conclusion

The final combined code satisfies the approved three-phase delivery. The fixed
v1 Overview, global preferences, session/window isolation, complete topology,
policy HUD, finite motion, all controller-family boundaries, every Workbench
destination, Settings, accessibility, localization, privacy, and performance
contracts pass the available automated and source-review evidence. No unresolved
Critical, High, Medium, or completion-blocking finding remains.

Runtime visual smoke is clearly deferred to a user-authorized pass and is not an
automated correctness dependency.
