# Research: Connections And Overview Accessibility Hotspot

- Query: Determine whether the reproduced 102-195% CPU spike after accessibility snapshots is intrinsic live-view invalidation, accessibility scrape amplification, or both, and identify the smallest contract-compatible fix.
- Scope: internal
- Date: 2026-09-02

## Findings

### Diagnosis

The accessibility snapshot is the primary trigger. Normal real-data operation was measured at about 4.5% CPU before an AX request. A timed-out real-data snapshot then left Mica at about 102% CPU; an earlier Connections request left it near 195%. The same behavior reproduced on a populated Overview after returning with Cmd-1. Initial no-data Overview and real-data Proxies snapshots succeeded, so the evidence does not support a root-shell or generic live-session failure.

The resulting cost is both accessibility amplification and live invalidation, but the relationship is asymmetric:

1. Accessibility traversal creates or exposes a high-cardinality SwiftUI/AppKit subtree that would otherwise stay mostly unrealized.
2. Queued AttributeGraph, layout, hosting-view, and table-row work continues after the snapshot client times out.
3. Existing 2 Hz connection metrics and other live publications can then invalidate the enlarged graph, sustaining CPU use. They are an amplifier after AX expansion, not the initiating hotspot.

The smallest compatible correction is a bounded, paged accessibility representation for high-cardinality surfaces. Keep the visual native `Table` and complete controller-reported data unchanged. Expose at most 32 ordered row/path summaries at once, with Previous/Next controls and automatic page reveal for the current selection. This preserves complete user reachability without forcing an AX client to instantiate all table cells or all topology paths in one request.

### Runtime and Sample Evidence

`tmp/codex/mica-visual-audit.jIY55U/connections-high-cpu.sample.txt` is a 1.459-second `/usr/bin/sample` capture of PID 8305. The main thread was active for essentially the complete interval. Its dominant work is SwiftUI transaction and AttributeGraph processing:

- 1,058 samples in the SwiftUI run-loop observer flush path.
- 867 samples in transaction processing and 865 in graph updates.
- 711 samples in `AG::Subgraph::update` and 688 in `AG::Graph::UpdateStack::update`.
- The aggregate stack includes 384 `LayoutEngineBox.sizeThatFits` samples, 353 graph-stack updates, 345 attribute updates, and substantial stack placement/layout work.

The capture also contains a direct causal AX branch:

`_AXXMIGCopyMultipleAttributeValues` -> `NSAccessibilityGetObjectForAttributeUsingLegacyAPI` -> `NSTableViewCellMockElement accessibilityDescriptionAttribute` -> `NSTableView viewAtColumn:row:makeIfNecessary:` -> `NSTableRowData rowViewAtRow:createIfNeeded` -> prepared row/addSubview/window attachment -> `NSHostingView` update and accessibility focus-graph work.

That chain shows the accessibility scrape requesting descriptions for native table cells and causing AppKit to make rows that were not already onscreen. The relatively small direct AX sample count understates the effect because the row creation schedules subsequent SwiftUI transaction, layout, and AttributeGraph work outside the initiating AX stack. Table row reuse/removal also appears later in the sample.

`WorkbenchConnectionsView.body`, `connectionTable`, and the connection projection do not dominate the sample. A 424-sample cooperative background branch is a concurrent `MihomoClient.proxies()` JSON decode, not Connections projection work. It is sample contamination and possible secondary load, but it cannot explain the controlled jump from low idle CPU only after an AX request.

### Connections Source Cause

- `Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift:299` creates one native `Table(rows, selection:sortOrder:)`.
- `Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift:300` through the table column definitions build up to six hosted SwiftUI cell trees per full-width row, including nested text and stacks.
- `Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift:463` applies `micaWorkbenchTable`, but that modifier only labels the raw table. It does not replace or bound its AX children.
- `Sources/Mica/Features/Workbench/WorkbenchDataShared.swift:7` defines `micaWorkbenchTable`; its accessibility behavior is limited to `.accessibilityLabel`.
- `Sources/Mica/Features/Workbench/WorkbenchDataShared.swift:122` combines children within a primary cell, reducing per-cell noise but not the number of native rows/cells AX can request.
- `Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift:125` rebuilds/reconciles rows on `metricsRevision`, potentially at the accepted 2 Hz cadence.
- `Sources/Mica/Features/Workbench/WorkbenchConnectionCache.swift:412` copies and replaces the cached row array for metric changes, while `WorkbenchConnectionCache.swift:565` restricts visible-row mutation where possible. This is acceptable at the measured low idle baseline, but it fans out after AX has forced many hosted cells into the graph.
- `Sources/Mica/Features/Workbench/WorkbenchConnections.swift:120` stores precomputed factual display/search/metric strings on each presentation row. A bounded AX summary can reuse these values without new controller access or fabricated data.

The direct source-level defect is therefore not the presence of a native `Table`; that is an explicit Workbench contract. It is exposing the native table's unbounded cell matrix to AX on a 2,000-row surface.

### Overview Source Cause

Overview already uses `.accessibilityRepresentation`, but its replacement remains high cardinality:

- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift:386` attaches a topology accessibility replacement.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift:1217` iterates every accessibility group, even though each individual group is bounded.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift:1255` iterates all policy nodes and derives complete inspection values for each.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift:1343` iterates every path in every group and creates two buttons per path.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift:355` sets group capacity to 32, but `WorkbenchOverviewTopology.swift:400` builds enough groups to cover all paths simultaneously.
- `Tests/MicaTests/WorkbenchOverviewPerformanceTests.swift:1043` currently verifies that flattening every group covers every path. It verifies completeness, not a bounded active AX window.

A `LazyVStack` does not solve this contract because an AX snapshot asks for the semantic descendants and therefore traverses the complete replacement. The real-data Overview timeout, contrasted with the successful no-data Overview snapshot, is consistent with this unbounded replacement rather than a missing representation.

### Smallest Contract-Compatible Fix

Implement one shared pure accessibility-window projection, preferably in an existing presentation/shared file to keep the change narrow:

- Capacity: reuse 32, already established by topology grouping.
- Inputs: ordered stable IDs, total count, active page or lower bound, and optional selected ID.
- Outputs: clamped visible range, page status, previous/next availability, and page containing the selected item.
- Complexity: O(1) page metadata and O(32) rendered descriptors.
- Behavior: clamp after filter, sort, data shrink, or session-generation changes; preserve controller order and stable identity; do not move the page merely because metrics changed.

Add a shared lightweight accessibility pager in `WorkbenchDataShared.swift` using a simple `VStack`, at most 32 row-level buttons/elements, localized Previous/Next controls, and an “items X-Y of N” status. Do not use a nested `List` or `Table` in the replacement.

For Connections:

- Keep the visual native `Table`, all 2,000 projected rows, selection, sort, search, and inspector behavior unchanged.
- Attach `.accessibilityRepresentation` directly to the table and expose only the active 32-row slice.
- Represent each row as one combined element or button rather than six cell elements. Build its label/value from the row's existing host, identity/detail, process/network, rule/route, timestamp, and metric strings.
- Activating a row sets the exact stable `selectedRowID`; the existing inspector remains the complete field view.
- Previous/Next provides complete ordered reachability. Sorting and filtering occur before paging, and an existing selection reveals its page.

For Overview:

- Treat `accessibilityGroups` as page data, not as a list to render all at once.
- Expose policy nodes plus one active path group of at most 32 paths, with Previous/Next and a range/count status.
- Keep pin, selection, and direct Connections navigation actions. When a selected or pinned path changes, reveal its group.
- If policy-node cardinality itself can exceed the same practical bound, page that section independently; do not hide controller-reported nodes from the normal visual topology.

### Follow-Up Scope: All Four Data Browsers

The durable fix should cover Connections, Logs, Rules, and Sources through one shared bounded-accessibility contract, not Connections alone. All four are explicitly the same data-browser archetype with one native `Table` (`.trellis/spec/frontend/workbench-ui-contract.md:208`, `workbench-ui-contract.md:1048`), and all four terminate at the same raw `micaWorkbenchTable` modifier. AC9 explicitly exercises 2,000 Connections and 2,000 Logs, while R6 also requires large Rules and Sources sets (`prd.md:62`, `prd.md:81`). Leaving three raw boundaries would retain the same latent AppKit AX cell-instantiation defect.

Share the window/range projection, range status, Previous/Next controls, selected-item reveal, and combined-row element. Keep page adapters separate because activation contracts differ:

- **Connections:** default row activation selects the exact presentation ID and opens the inspector. Existing close, group-close, and open-rule commands remain in the selected focus/inspector flow with their confirmation and capability gates; the pager must never invoke them while navigating.
- **Logs:** default row activation selects the log and disables `followNewest`, matching `WorkbenchLogs.swift:94`. While follow is enabled, the accessibility window tracks the final 32 incoming rows. Moving to an older page must disable follow; append/drop ring changes must anchor by stable row ID, clamp an evicted selection, and must not jump an AX user's page back to newest (`WorkbenchLogs.swift:299`). The existing precomputed `accessibilityText` is suitable for the row summary (`WorkbenchLogPresentation.swift:180`).
- **Rules:** default activation selects the exact stable row and opens its inspector/focus path. Pending cross-page rule navigation must reveal the resolved row's page in addition to issuing the visual scroll (`WorkbenchRules.swift:661`). The current table also exposes a capability-gated inline enable/disable command (`WorkbenchRules.swift:462`); replacing the native subtree must preserve it as a localized named accessibility action on that bounded row, gated by the same `canMutate` and busy state. It must not become the row's default action or bypass AppModel/session validation.
- **Sources:** default activation selects the exact presentation row. Update and health-check remain selected-source focus-rail actions with the existing capability and busy gates (`WorkbenchSources.swift:35`, `WorkbenchSources.swift:495`); paging or selection must never execute them. Update-all/reload remain outside the table in the command bar.

One additional shared risk is sorting. Connections, Rules, and Sources currently obtain accessible sorting from native sortable column headers. A full `.accessibilityRepresentation` hides that subtree, so the bounded representation must also expose the current sort field/direction and localized sort actions for every supported comparator. Logs retain source order and need no sort action. Shipping the pager without this mirror would fix CPU by regressing an existing VoiceOver operation.

The preferred implementation boundary is an extended shared `micaWorkbenchTable`/bounded-representation helper that accepts page-owned ordered rows, selection, summary content, sort actions, and optional named row actions. This makes an unbounded raw table difficult to reintroduce while preserving each page's controller-action ownership. Do not move controller operations into the generic helper.

Do not start with localization caching or row-array micro-optimization. Those costs appear in the sample, but bounding AX exposure addresses the causal trigger. Measure again before considering a separate metrics-projection optimization.

### Recommended Files

- `Sources/Mica/Features/Workbench/WorkbenchDataPresentation.swift` - add the pure, shared accessibility-window/page projection if an existing general presentation boundary is preferred.
- `Sources/Mica/Features/Workbench/WorkbenchDataShared.swift` - add the bounded accessible pager and apply a replacement at the native table boundary.
- `Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift` - maintain page/selection state and provide ordered, precomputed row summaries to the table replacement.
- `Sources/Mica/Features/Workbench/WorkbenchLogs.swift` - adapt the shared window to stable append/drop identity and follow-newest semantics.
- `Sources/Mica/Features/Workbench/WorkbenchRules.swift` - provide selection, sorting, pending-navigation reveal, and the capability-gated named mutation action.
- `Sources/Mica/Features/Workbench/WorkbenchSources.swift` - provide selection and sorting while retaining selected-source actions in the focus rail.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift` - derive the active topology accessibility page and selected-path location.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift` - render policy semantics plus only the active path group.
- `Tests/MicaTests/WorkbenchDataProjectionTests.swift` - cover the pure pager and 2,000-row Connections descriptors.
- `Tests/MicaTests/WorkbenchOverviewPerformanceTests.swift` - replace simultaneous flatten-all-groups expectations with complete reachability across bounded pages.
- `scripts/verify-real-controller-source.mjs` - enforce bounded accessibility replacements without weakening the one-native-Table, selection, or completeness contracts.

### Recommended Tests

Pure window projection:

- Counts 0, 1, 31, 32, 33, and 2,000 always expose at most 32 items.
- Traversing Previous/Next covers every ordered item exactly once, without gaps or duplicates.
- Data/filter shrink and generation changes clamp the page.
- A selected stable ID locates and reveals the correct page.
- Metric-only changes preserve page and identity.

Connections:

- A 2,000-row fixture produces no more than 32 current AX row descriptors.
- Search and sort run before paging and retain exact row order.
- Activation selects the exact presentation ID, including duplicate or blank controller connection IDs that rely on source-index identity.
- The summary is factual and the inspector continues to expose the complete row fields.

Other data browsers:

- A 2,000-row Logs fixture remains capped at 32 AX rows; follow-newest tracks the final page, paging backward disables follow, append/drop preserves a stable anchor, and eviction clamps selection.
- Large Rules and Sources fixtures remain capped at 32 while sort/filter order and exact stable selection are preserved.
- Rules expose a named mutation action only for currently mutable, capability-enabled rows; its default row action remains selection.
- Connections, Rules, and Sources expose every existing sortable field and current direction without materializing native table headers/cells.
- A shared parameterized test runs the 0, 1, 31, 32, 33, and 2,000 contract against adapters for all four browsers.

Overview:

- A 2,000-path fixture exposes one path group with at most 32 items.
- Traversing groups reaches every path in controller order.
- Selected/pinned paths reveal the correct group.
- Policy-node semantics, pinning, and direct Connections navigation remain available.

Verifier additions:

- Require a bounded `.accessibilityRepresentation` at the Connections table boundary.
- Iterate all four `dataBrowserTableFiles` and require the same shared bounded representation rather than a Connections-only assertion.
- Require a shared capacity/visible-range projection and selection reveal.
- Reject `Table(` or `List(` inside the replacement.
- Require Logs follow-newest/older-page handling, Rules' named gated mutation action, and sort-action adapters for Connections, Rules, and Sources.
- Require Overview to consume one active path range rather than `ForEach(groups)`.
- Retain the existing exact-one visual native `Table`, selection, complete visual data, and path-action checks.

### Validation Without Controller Actions

1. Run focused fixture-only Swift tests for 2,000 rows and paths, the source verifier, and the normal build/test gates. These must not launch Mica, contact a controller, or invoke Test, Refresh, Close, Update, profile, or network actions.
2. Add a DEBUG performance observation for the accessibility presentation count if needed. Assert the count never exceeds 32; a new category is optional because the pure projection tests provide the core deterministic guarantee.
3. Under separate explicit runtime permission, use an already connected live session only as read-only data. Record 15 seconds of idle CPU, navigate without invoking controller actions, request one AX snapshot, and require it to complete within the client timeout and return close to baseline after queued work drains. Repeat for Connections and populated Overview, with no-data Overview and Proxies as controls.
4. Capture a short follow-up `sample` during the snapshot. The acceptance signal is the absence of the high-cardinality `NSTableViewCellMockElement -> viewAtColumn:row:makeIfNecessary:` chain and a bounded active topology group. A test-only `NSHostingView` AX harness is optional but may be less stable than the pure projection tests plus explicit runtime acceptance.

### Related Specs

- `.trellis/spec/frontend/workbench-ui-contract.md` - requires one native high-cardinality table, complete selectable controller data, stable order, exact connection reveal, 2 Hz responsiveness, topology accessibility, and fixture-only automated validation.
- `.trellis/spec/frontend/live-session-controller-contract.md` - owns selected-controller/session-generation validation and prohibits stale or cross-session publication.
- `.trellis/spec/frontend/component-guidelines.md` - establishes shared Workbench composition and native control expectations.
- `.trellis/spec/frontend/state-management.md` - constrains ownership and derived presentation state.

The durable Workbench contract should later clarify that “exposes all nodes/paths” means complete ordered reachability through a bounded accessibility window, not simultaneous materialization of every semantic descendant. The selected item must be automatically revealed, and normal visual UI must continue to expose all controller data.

### Files Found

- `tmp/codex/mica-visual-audit.jIY55U/connections-high-cpu.sample.txt` - high-CPU sample containing the AX-to-offscreen-table-row creation chain and subsequent SwiftUI graph/layout work.
- `Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift` - native Connections table, metrics-driven row rebuild, selection, sorting, and inspector integration.
- `Sources/Mica/Features/Workbench/WorkbenchConnections.swift` - stable presentation rows and reusable precomputed factual strings.
- `Sources/Mica/Features/Workbench/WorkbenchConnectionCache.swift` - structural/metric projection cache and visible-row update logic.
- `Sources/Mica/Features/Workbench/WorkbenchDataShared.swift` - shared table modifier and cells; currently labels but does not bound native table accessibility.
- `Sources/Mica/Features/Workbench/WorkbenchDataInteraction.swift` - responsive table and viewport observers; no evidence that it initiates the spike.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift` - topology path grouping with capacity 32 but simultaneous complete group construction.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift` - unbounded Overview accessibility replacement.
- `Tests/MicaTests/WorkbenchDataProjectionTests.swift` - existing high-cardinality projection fixtures suitable for bounded-window tests.
- `Tests/MicaTests/WorkbenchOverviewPerformanceTests.swift` - current topology completeness/performance assertions.
- `Tests/MicaTests/PerformanceObservationTests.swift` - existing performance-operation category coverage.
- `Sources/Mica/App/PerformanceObservation.swift` - current topology accessibility and data-table performance observations.
- `scripts/verify-real-controller-source.mjs` - source contract verifier; currently checks representation/table presence but not bounded AX cardinality.

### External References

No external references were required. The diagnosis is based on the controlled runtime comparison, the local process sample, current source/tests, and the repository's SwiftUI accessibility/performance guidance.

## Caveats / Not Found

- The process sample covers 1.459 seconds rather than a full Instruments trace. It is sufficient to establish the AppKit AX row-instantiation chain, but not to assign precise end-to-end percentages to every secondary invalidation source.
- The 4.5%, 102%, and 195% CPU observations are controlled runtime evidence supplied by the active audit; only the high-CPU sample is persisted in the referenced scratch file.
- Concurrent proxy JSON decoding appears in the sample. It is not the trigger according to the before/after AX control, but a follow-up capture should verify the bounded fix under the same background load.
- The exact behavior of the new `.accessibilityRepresentation` must be confirmed in a runtime AX acceptance pass. The native-table stack and the populated Overview failure make bounded exposure the strongest source-backed correction, but framework behavior cannot be fully proven by source tests alone.
- No product code, specs, controller state, or remote actions were modified or invoked during this research.
