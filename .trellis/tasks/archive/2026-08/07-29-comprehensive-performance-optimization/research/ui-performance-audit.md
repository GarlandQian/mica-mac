# Research: SwiftUI / Workbench performance audit

- Query: Read-only audit of the six Workbench SwiftUI files and directly related presentation models, focused on Observation invalidation, virtualization, identity, projection work, charts/Canvas, topology, gestures, layout, and page-transition ownership.
- Scope: internal
- Date: 2026-07-29

## Findings

### Priority summary

| Priority | Severity | Finding |
| --- | --- | --- |
| P0 | High | One broad connection revision drives full connection-row projection, Rules connection indexing, and topology rebuilds. |
| P0 | High | The 5 Hz logs path still performs full-buffer comparison and delta-discovery scans before a virtualized table can help. |
| P1 | Medium | `WorkbenchWorkspaceStore` exposes all page state through one observed dictionary, widening invalidation for search, selection, and persisted view state. |
| P1 | Medium | Overview chart and highlight projections synchronously filter, merge, and sort on repeated presentation updates. |
| P1 | Medium | Topology hover/selection performs graph-wide lookup work and redraws the complete Canvas. |

### P0: Broad connection revision fans out into three expensive consumers

**Severity: High**

Evidence:

- `Sources/Mica/App/DashboardSessionModels.swift:216-251` stores connections, traffic, and `connectionsRevision` in one `ConnectionsCatalogSnapshot`; its custom equality compares the full connections and traffic values rather than using the revision token.
- `Sources/Mica/App/AppModel.swift:396-405` determines whether the connection revision changes by comparing the full connection collection, then compares the newly built snapshot again before assignment.
- `Sources/Mica/App/AppModelLiveSession.swift:171-229` publishes presentation domains on the main actor; connection publication is budgeted separately but still assigns the whole catalog snapshot.
- `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1725-1728` rebuilds active connection rows whenever `connectionsRevision` changes.
- `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:919-1030` eagerly maps every connection into a presentation row, builds fallback identity material, formats metadata, serializes additional fields for search text, filters, and optionally sorts.
- `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:2146-2182` then reconciles selection, rebuilds close groups, and creates ID sets across the full projected collection.
- `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1149-1176`, `:2633-2638`, and `:2941-2969` key the Rules connection index to the same revision, rebuilding an O(connections + rules) projection even when only transfer counters changed.
- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:969-991`, `:1014-1028`, and `:1080-1099` key topology normalization and layout work to the same connection revision.

Why it matters:

Native `Table` virtualization limits row-view creation, but it does not avoid the eager O(n) presentation work performed before the table receives `rows`. Mutable upload/download counters can therefore cause repeated string/JSON projection, filtering, sorting, Rules indexing, and topology tasks even when connection membership and route structure are unchanged.

Likely measurement method:

- Add signposts around connection catalog publication, `WorkbenchConnectionProjection.rows`, Rules index resolution, and topology request completion.
- Use Time Profiler and Allocations with synthetic 1,000 / 5,000 / 10,000-connection snapshots at the intended 2 Hz publication rate.
- Use SwiftUI Instruments and temporary `Self._logChanges()` probes to count Connections, Rules, and Overview subtree updates while only byte counters change.
- Record topology task starts, cancellations, and accepted completions per minute.

Concrete options:

- Split structural/membership revision from mutable transfer-metric revision. Key topology and Rules membership counts only to the structural revision.
- Give the Connections page an ID-keyed incremental row cache: retain static identity/search fields and update only transfer/time fields that changed.
- Move expensive additional-field serialization out of the 2 Hz projection path, or compute it lazily for search/inspection.
- Derive revisions from the upstream domain event/sequence rather than discovering change with repeated full-array equality scans.

### P0: Log publication and “incremental” projection still scan the full buffer

**Severity: High under sustained near-capacity streams**

Evidence:

- `Sources/Mica/App/DashboardSessionModels.swift:255-270` stores the full log array and a revision, but snapshot equality compares the entries array.
- `Sources/Mica/App/AppModel.swift:408-417` compares the full dashboard log buffer to derive the revision and then compares the next snapshot before publishing it.
- `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1383-1434` attempts append-delta reuse by scanning IDs, building a `Set`, validating old rows, finding overlap, checking the overlap, and reindexing retained rows.
- `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1519-1562` reruns source projection on each source revision and then reruns the level/search filter.
- `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:4144-4152` triggers that path for every log revision; `:4478-4496` also performs selection reconciliation against the old and new arrays.
- The rendered stream uses native tables (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:4357-4457`) and coalesces follow-newest scrolling (`:4303-4331`), so the primary risk is projection/publication work, not row-view virtualization or scroll scheduling.

Why it matters:

At the configured 5 Hz presentation rate and a full retained log buffer, append/drop updates can remain O(n) and can reconstruct many row values solely because `sourceIndex` shifted. The table may display only visible rows, but publication, delta discovery, filtering, and selection reconciliation still touch most or all retained entries.

Likely measurement method:

- Benchmark 2,000 retained entries with 1, 10, and 100 appended entries per publication at 5 Hz.
- Profile `synchronizeLogsCatalog`, `rowsByApplyingAppendDelta`, `visibleRows`, and `WorkbenchDataSelection.reconciled` with Time Profiler and Allocations.
- Track full versus incremental projection counters already exposed by `WorkbenchLogProjectionCache` (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1506-1513`).

Concrete options:

- Publish an explicit append/drop delta and monotonic sequence from the log owner instead of rediscovering overlap in the view layer.
- Remove positional `sourceIndex` from retained row state where possible; stable IDs already provide row identity.
- Maintain filtered ID/index views incrementally when level/query are unchanged.
- Replace front-removal storage with a bounded deque/ring representation if profiling shows buffer maintenance is material.

### P1: Workspace persistence has dictionary-wide Observation scope

**Severity: Medium**

Evidence:

- `Sources/Mica/Features/Workbench/WorkbenchChrome.swift:188-211` defines `WorkbenchWorkspaceStore` as `@Observable` with one stored `storage` dictionary; reads and updates go through that single property.
- `Sources/Mica/Features/Workbench/WorkbenchChrome.swift:213-233` creates search bindings that read and write entries in the same dictionary.
- Data pages persist selection/sort/filter state through this store, for example Connections at `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1740-1749` and Rules at `:3043-3059`.

Why it matters:

Observation tracks the stored dictionary property, not an individual key or field inside a value. A search keystroke or row-selection persistence write can therefore invalidate every mounted consumer that read `storage`, widening work beyond the local control whose state changed.

Likely measurement method:

- Add temporary `Self._logChanges()` probes to `WorkbenchRootView`, the active page, command bar, and table wrapper while typing and changing selection.
- Compare body-update counts with workspace persistence disabled in an instrumented branch.

Concrete options:

- Store per-controller/per-destination `@Observable` workspace objects with field-level properties.
- Keep interaction-hot state in page-local `@State` and persist only on a coalesced boundary or when leaving the page.
- Avoid writing unchanged values; preserve the current equality guard at the narrower field/object level.

### P1: Overview projections repeat bounded but non-trivial chart and ranking work

**Severity: Medium**

Evidence:

- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:230-245` derives visible traffic, visible memory, and merged dates during telemetry-section evaluation.
- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:435-453` filters and downsamples both timelines; `:1542-1572` maps dates, builds a `Set`, sorts, filters, and downsamples.
- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:507-716` constructs the traffic and memory Charts from those derived arrays.
- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:785-805` rebuilds latency, rule-hit, and active-connection highlights; `:1647-1740` uses full sorts even though the UI consumes only a small top subset.
- `Sources/Mica/App/SessionTimelineModels.swift:12-20` and `:78-86` cap both timelines at 300 stable-ID samples, limiting the current chart cost.

Why it matters:

The 300-sample bound prevents unbounded chart growth, but repeated Set/sort/filter/downsample work and two chart mark sets still run on the main actor. Highlight ranking performs O(n log n) full sorts for top-N output and is more sensitive to large connection/rule collections.

Likely measurement method:

- Use SwiftUI Instruments while traffic publishes at 4 Hz and while moving/pinning the chart selection.
- Use Time Profiler around the timeline projection helpers and highlight ranking with large synthetic connection/rule sets.
- Compare frame time and body counts with cached projections keyed by generation, window, and source revision.

Concrete options:

- Cache timeline projections by source revision plus selected window; isolate hover/pin readout state from sample projection state.
- Precompute merged dates once per projected sample set.
- Use bounded top-K selection instead of full sorting for five-item highlight lists.
- Keep the existing sample bounds and stable IDs.

### P1: Topology interaction does graph-wide lookup and full-Canvas redraw work

**Severity: Medium, potentially High for large graphs**

Evidence:

- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:1147-1159` redraws all topology edges and nodes whenever Canvas input state changes.
- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:1325-1355` updates hover/selection from pointer movement and tap gestures.
- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:2071-2085` resolves selected path IDs by scanning nodes and edges; `:2087-2093` filters all paths for the resulting set.
- Topology construction/layout is correctly moved off the caller actor in `Sources/Mica/App/ConnectionTopologyModel.swift:214-246` and `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:1913-1923`; the remaining concern is frequency and main-thread presentation work.

Why it matters:

Pointer movement can combine O(nodes + edges + paths) lookup work with a redraw of every Canvas primitive. The spatial hit index reduces hit testing, but the subsequent selection projection is not similarly indexed.

Likely measurement method:

- Capture SwiftUI and Time Profiler traces while scrubbing across 100 / 1,000 / 5,000-node synthetic topologies.
- Count Canvas redraws and sample `pathIDs`, `paths`, and drawing helpers.
- Test trackpad hover and click behavior together with the enclosing vertical scroll view.

Concrete options:

- Include node-to-path, edge-to-path, and path-by-ID dictionaries in the off-main topology presentation.
- Precompute selected/highlighted path sets and update them only when the selected target changes.
- Coalesce hover updates to display cadence if pointer events outpace useful visual updates.
- Preserve the single-Canvas architecture and indexed hit testing.

### Confirmed strengths / no high-confidence defect

- Native `Table` is used for large Connections, Rules, Sources, and Logs data (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1895-2093`, `:2762-2896`, `:3402-3525`, `:4357-4457`).
- Proxy directories and active-node rows use native `List`, stable IDs, and fixed row geometry (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:539-560`, `:1118-1214`, `:1309-1358`). Only the active proxy-group member list is rendered.
- Data-page IDs preserve reported IDs and explicitly handle duplicates/fallback identity (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:799-861`). Timeline samples also have stable IDs and fixed capacity.
- The log empty-filter path returns the existing rows array (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:1436-1450`), and follow-newest scheduling is coalesced rather than restart-debounced.
- `WorkbenchRootView` owns visible-destination publication on appear, disappear, destination change, and controller change (`Sources/Mica/Features/Workbench/WorkbenchChrome.swift:537-560`). No competing child-page visible-destination writes were found in the six Workbench files.
- `WorkbenchVisualSystem.swift` and the management pages contain no high-confidence high-frequency hotspot from source inspection. Management scrolling uses lazy/native containers where the potentially larger collections appear (`Sources/Mica/Features/Workbench/WorkbenchManagement.swift:20-33`, `:985-995`).

## Files Found

- `Sources/Mica/Features/Workbench/WorkbenchChrome.swift` - root routing, workspace persistence, sidebar/chrome, and visible-destination ownership.
- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift` - Overview telemetry Charts, highlights, topology layout, Canvas, and gestures.
- `Sources/Mica/Features/Workbench/WorkbenchDataPages.swift` - Connections, Rules, Sources, Logs projections, filtering/sorting, tables, selection, and follow scrolling.
- `Sources/Mica/Features/Workbench/WorkbenchProxies.swift` - proxy group/member projections, native lists, stable IDs, and nested scrolling.
- `Sources/Mica/Features/Workbench/WorkbenchManagement.swift` - controllers, configuration, actions, diagnostics, responsive forms, and management lists.
- `Sources/Mica/Features/Workbench/WorkbenchVisualSystem.swift` - shared page, command, state, and visual primitives.
- `Sources/Mica/App/AppModel.swift` - observable presentation catalogs and synchronization.
- `Sources/Mica/App/AppModelLiveSession.swift` - publication coordinator and live-domain flushing.
- `Sources/Mica/App/DashboardSessionModels.swift` - catalog snapshot/equality definitions.
- `Sources/Mica/App/OperationSessionModels.swift` - field-granular observable session presentation.
- `Sources/Mica/App/SessionTimelineModels.swift` - bounded stable-ID traffic and memory timelines.
- `Sources/Mica/App/ConnectionTopologyModel.swift` - cancellable off-main topology normalization.

## Code Patterns

- Good: real View subtrees split Overview telemetry, highlights, network facts, and topology; the Overview scroll stack is lazy.
- Good: high-frequency views generally consume presentation catalogs/revision tokens rather than the mutable `controllerSession` object.
- Risk: revision tokens are often calculated after full collection comparison and then used to trigger eager whole-collection projection.
- Risk: multiple unrelated consumers use the same connection revision despite requiring different notions of change.
- Risk: computed projection helpers execute synchronously on the main actor unless explicitly marked `@concurrent`.

## External References

- Apple WWDC25 session 306, “Optimize SwiftUI performance with Instruments” - intended measurement path for body updates, long view updates, and dependency causes.
- Apple WWDC25 session 266, “Explore concurrency in SwiftUI” - actor/invalidation guidance for moving projection work off the main actor.
- Apple SwiftUI `Table`, Observation, Charts, and Canvas documentation, using the project target assumptions of Swift 6.2 and macOS 27.
- No live web lookup was used; these are measurement references, not runtime evidence.

## Related Specs

- `.trellis/spec/frontend/workbench-ui-contract.md` - lazy Overview structure, bounded chart work, topology off-main work, native proxy virtualization, stable IDs, and sole visible-destination ownership.
- `.trellis/spec/frontend/live-session-controller-contract.md` - per-domain publication cadence, field-granular presentation, generation fencing, and cancellation requirements.
- `.trellis/spec/guides/cross-layer-thinking-guide.md` - end-to-end state flow and ownership checks.
- `.trellis/tasks/07-29-comprehensive-performance-optimization/prd.md` - required publication budgets, invalidation tests, large-dataset tests, and real profiling evidence.

## Caveats / Not Found

- This is a source audit only. No Instruments trace, runtime benchmark, controller session, build, or test command was run; severity ranks likely cost and blast radius, not measured regression.
- Real controller event distributions, connection/log cardinalities, adapter ordering, and machine-specific frame budgets remain unknown.
- `WorkbenchDataResponsive` eagerly constructs full/compact/stacked view values before selecting one by width (`Sources/Mica/Features/Workbench/WorkbenchDataPages.swift:32-63`). The source establishes extra view construction, but not whether it is material; measure before refactoring.
- `ViewThatFits` in management/form rows can measure multiple candidates, but those surfaces are comparatively low-frequency and no source evidence establishes it as a priority bottleneck.
- Gesture competition remains an interaction-test item: chart overlays use simultaneous tap/hover handling, and Proxies nests horizontal scrolling around vertical Lists. No source-only correctness or performance defect was established.
- Bounded timeline front removal uses `removeFirst` (`Sources/Mica/App/SessionTimelineModels.swift:67-70`, `:126-129`), but capacity is 300; profile before replacing it.
- No application code, specs, PRD, or other task files were modified.
