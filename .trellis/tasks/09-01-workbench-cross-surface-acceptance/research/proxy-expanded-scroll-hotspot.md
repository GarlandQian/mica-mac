# Research: Expanded policy-group scroll hotspot

- Query: Why does Proxies scrolling become visibly janky after policy groups are expanded, and what is the smallest defensible fix?
- Scope: Internal, static/offline source, contract, and test inspection only
- Date: 2026-09-04

## Findings

### Conclusion

There are two compounding hot paths. The layout problem explains why the defect appears only after expansion; the observation problem explains repeatable refresh-time hitches while that large layout is on screen.

1. **The outer lazy layout virtualizes groups, not node tiles.** `WorkbenchPolicyGroupsView` places one `ProxyPolicyGroupPanel` per item in an outer `LazyVStack` (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:198-252`). Each expanded panel then inserts its own adaptive `LazyVGrid` and every member identity beneath that single variable-height outer item (`Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift:534-626`). With multiple large groups open, the outer scroll layout has a few very tall, changing children rather than one flat stream of independently virtualizable rows/tiles. The nested grid must keep resolving its many row placements as the enclosing group enters and leaves the viewport. This is the strongest structural explanation for expansion-dependent continuous scroll cost.
2. **The existing scroll deferral does not isolate the visual tree from the raw catalog observation.** The expensive root directly evaluates `.onChange(of: appModel.policyGroupCatalog)` (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:88-105`). Therefore every changed catalog first invalidates/re-evaluates `WorkbenchPolicyGroupsView`; only inside the callback does `receiveCatalog` decide to stage the update (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:498-524`). During that root pass, `groupPresentations` rebuilds a directory dictionary, an open-ID set, and all visible group presentation values (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:465-495`), then SwiftUI diffs the expanded panel/grid tree. The coordinator successfully postpones committing `acceptedCatalog`, but it cannot undo the root invalidation which already occurred.
3. Catalog changes are not per-frame, but they are periodic and expensive enough to be visible with expanded content. The medium refresh lane is five seconds (`Sources/Mica/App/LiveSessionRefreshModels.swift:324-334`), and AppModel publishes the catalog only when it differs (`Sources/Mica/App/AppModel.swift:545-550`). Thus the report should be verified as both (a) steady drag/deceleration cost from nested layout and (b) periodic spikes aligned to real catalog revisions.

The existing interaction code is not a per-frame state-update loop. `ProxyScrollInteractionTracker` changes state only when `ScrollPhase` crosses scrolling/idle (`Sources/Mica/Features/Workbench/WorkbenchProxyInteraction.swift:249-295`), and its modifier uses `onScrollPhaseChange`, not offset observation (`Sources/Mica/Features/Workbench/WorkbenchProxyInteraction.swift:298-319`). The node hover callback suppresses pointer-entry changes while scrolling and only permits cleanup on pointer exit (`Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift:861-870`). Hover can add hit-testing cost across many tiles, but the source does not support blaming it as the primary invalidation loop.

### Smallest defensible fix

Treat the fix as two narrow changes; either one alone leaves a demonstrated hotspot.

1. **Flatten the visual collection to one root lazy layout.** Make the `ScrollView` own one adaptive `LazyVGrid` (or one root lazy row stream) and render policy groups as source-ordered sections: a full-width group header/filter section followed by that group's member tiles. Do not retain `LazyVStack -> panel -> LazyVGrid`. Keep the existing stable group/member IDs on the root layout so the current two-stage `ScrollViewReader` reveal remains valid. This changes only presentation structure: all expanded members remain reachable, source order remains group-then-member, multiple groups remain open, and selection/Inspector commands remain unchanged.
2. **Put catalog intake behind a real observation boundary.** A tiny nonvisual leaf should observe the scalar `policyGroupCatalogRevision`, read the matching catalog when that revision changes, and call the existing `receiveCatalog`. The large page/root visual subtree must no longer directly observe or compare the complete catalog. Keep initial/session-boundary force-accept behavior and the existing coordinator. While scrolling, a deferrable update should mutate only ignored scheduler storage; the visual tree should update once, with the latest catalog, when idle. Do not change the five-second controller refresh cadence or the critical-operation bypass.

Do not solve this by limiting nodes, pagination, sorting, dropping controller fields, collapsing other groups, or disabling exact reveal/accessibility. Those would violate the product contract instead of removing layout/invalidation work.

An optional second-line optimization is an explicit equatable boundary around stable group/tile visual data. `ProxyExpandedGroupPresentation` is already `Equatable` (`Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift:5-20`), but `ProxyPolicyGroupPanel` has no equatable boundary and carries regenerated closures (`Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift:297-331`). Do not add equality that ignores callbacks: it could retain a stale controller/generation command scope. First flatten and isolate observation; add a safe action-router/equatable split only if an Instruments trace still shows row-body diff cost.

### Existing cache and scheduling behavior to preserve

- Expanded indexes are genuinely cached per catalog revision and only built for requested open groups; closed groups are pruned (`Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift:797-840`, `:878-927`). Replacing this cache is not justified.
- Member projection preserves occurrence identity, controller order, reported delay/health, transport/source data, and current selection (`Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift:1252-1326`). The layout fix should consume these rows unchanged.
- The scheduler keeps only the latest deferrable catalog and does not publish it while any scroll region remains active (`Sources/Mica/Features/Workbench/WorkbenchProxyInteraction.swift:338-417`). Coordinator publication is a scalar `commitRevision` (`Sources/Mica/Features/Workbench/WorkbenchProxyInteraction.swift:136-241`). Existing tests prove latest-wins-until-idle and one commit per actual deferred publication (`Tests/MicaTests/WorkbenchProxyWorkspaceTests.swift:1250-1313`, `:1366-1457`).
- Accessibility is already a separate bounded 32-item projection; it should remain detached from the visual grid. The source verifier explicitly prevents the accessibility replacement from constructing the visual `LazyVGrid` (`scripts/verify-real-controller-source.mjs:1950-1970`).

### Validation

Add focused, offline protection before relying on real-controller acceptance:

1. Extend `WorkbenchProxyWorkspaceTests` source-contract coverage to require one root lazy visual layout, stable group and member reveal IDs, and the absence of a per-group nested `LazyVGrid`. Retain the existing one-scroll-owner assertions at `Tests/MicaTests/WorkbenchProxyWorkspaceTests.swift:416-449`.
2. Add a source-contract assertion that the root visual view does not contain `.onChange(of: appModel.policyGroupCatalog)` and that catalog intake is driven through the scalar revision observation leaf. Keep the scheduler tests at `Tests/MicaTests/WorkbenchProxyWorkspaceTests.swift:1250-1457` unchanged.
3. Add a pure projection-order test for several simultaneously open groups: flattening must yield group headers and every member in exact group/member source order, with unchanged stable IDs. Also cover close/reopen, independent filters, selected inspector member, and exact group-then-member reveal.
4. Retain the Release `proxy-expanded-groups-projection` benchmark and run two comparable reports to catch cache/projection regression. Its current case prepares 100 groups x 1,000 members but measures only expansion of two cached 1,000-member indexes (`Tests/MicaTests/MicaPerformanceBenchmarkTests.swift:724-727`, `:832-852`). It does **not** instantiate SwiftUI, lay out the nested grid, scroll, hover, diff rows, or render accessibility, so its current passing result cannot validate scroll smoothness.
5. After offline checks, user-authorized real-data validation should compare collapsed, one-expanded, and several-expanded groups during drag and deceleration, and correlate frame hitches with the five-second catalog revision. A SwiftUI Instruments trace or temporary debug-only `Self._logChanges()` at the root/section/tile boundaries can distinguish remaining layout work from refresh invalidation. Runtime/controller access was not authorized for this research and was not performed.

### Files found

- `Sources/Mica/Features/Workbench/WorkbenchProxies.swift` - root observation, presentation assembly, outer scrolling layout, reveal, and catalog acceptance.
- `Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift` - nested expanded grid, node tile body, hover behavior, and commands.
- `Sources/Mica/Features/Workbench/WorkbenchProxyInteraction.swift` - phase-only scroll tracker and latest-update presentation scheduler.
- `Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift` - source-ordered group/member projection and per-expanded-group caches.
- `Sources/Mica/App/AppModel.swift` - changed-only catalog publication and scalar revision.
- `Sources/Mica/App/LiveSessionRefreshModels.swift` - five-second medium refresh cadence.
- `Tests/MicaTests/WorkbenchProxyWorkspaceTests.swift` - scroll-owner, reveal, cache scheduling, and idle-commit regression coverage.
- `Tests/MicaTests/MicaPerformanceBenchmarkTests.swift` - large proxy projection benchmark with no SwiftUI scroll/layout coverage.
- `scripts/verify-real-controller-source.mjs` - static proxy layout/accessibility/reveal contract; currently requires the nested panel grid but has no observation-boundary assertion.

### Related specs and task requirements

- `.trellis/spec/frontend/workbench-ui-contract.md:348-388` requires one vertical scroll owner, complete source order, cached indexes only for expanded groups, adaptive readable cells, and multiple simultaneous expansions.
- `.trellis/spec/frontend/workbench-ui-contract.md:630-638` requires the current group-then-member reveal under the one outer `ScrollViewReader` and forbids nested scroll target ownership.
- `.trellis/spec/frontend/workbench-ui-contract.md:1246-1249` requires page-owned projection caches and separate invalidation paths.
- `.trellis/spec/frontend/workbench-ui-contract.md:1306-1311` requires the latest deferrable proxy update to remain pending throughout scrolling and publish at idle.
- `.trellis/tasks/09-01-workbench-cross-surface-acceptance/prd.md:62-67` requires smooth multi-expanded policy-group scrolling without broad AppModel observation or body-time full-set work.
- `.trellis/tasks/09-01-workbench-cross-surface-acceptance/prd.md:102-104` shows the offline benchmark gate as complete but real-controller visual acceptance still open; this user report is evidence that the existing benchmark did not cover the rendered hotspot.

### External references

- The project SwiftUI performance reference recommends lazy construction, narrow dependencies, explicit invalidation boundaries, and `_logChanges()` for unexpected body updates (`.agents/skills/swiftui-expert-skill/references/performance-patterns.md:29-65`, `:138-164`, `:186-217`).
- The local reference cites Apple's WWDC25 "What's new in SwiftUI" for improved nested-scroll lazy loading, but that statement concerns nested scroll views, not multiple same-axis lazy layout containers inside one scroll view (`.agents/skills/swiftui-expert-skill/references/performance-patterns.md:162-164`). It does not establish that this group-level nesting is free.

## Caveats / Not Found

- No Mica process, controller, profile, network endpoint, or remote action was used. Static inspection can identify the invalidation leak and risky layout shape, but it cannot assign frame-time percentages or prove which dominates on the user's Mac.
- The source contains no per-frame scroll-offset state mutation and no unbounded visual accessibility mirror; those suspected causes were not found.
- Existing performance tests measure projection/index work, not rendered SwiftUI scroll work. A user-authorized trace is the remaining proof for frame pacing after the targeted fix.
- The source verifier currently asserts that the adaptive grid exists inside `WorkbenchProxyGroupPanels.swift` (`scripts/verify-real-controller-source.mjs:1972-1975`). A flattening fix must update that assertion to enforce the new single-root layout rather than mechanically preserving the hotspot.
