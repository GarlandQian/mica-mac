# Research: SwiftUI Workbench Bug Audit

- Query: Audit the Workbench, with emphasis on Proxies locate/health/reveal behavior, for interaction, accessibility, and performance bugs.
- Scope: internal source audit plus Apple SwiftUI API contract review; no runtime UI smoke and no controller contact
- Date: 2026-08-27

## Findings

### Confirmed source bugs

1. **High - A reported latency of zero can be presented as a healthy `0 ms` node.**
   `ProxyNodeHealthState.grade(for:)` rejects non-positive delays, but `classify` then falls back to `.healthy` whenever `alive == true` (`Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift:166`, `Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift:176`). The row retains the raw zero (`Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift:1051`), and the tile, tooltip, and selected-node header render every non-nil delay (`Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift:108`, `Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift:473`, `Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift:691`). `OverviewFormat.latencyTint` independently grades zero as fast (`Sources/Mica/Features/Workbench/WorkbenchDashboard.swift:791`). This conflicts with the UI contract and existing scale test, which treat non-positive values as unavailable (`Tests/MicaTests/WorkbenchProxyWorkspaceTests.swift:258`). Normalize non-positive values before deriving both health and display.

2. **High - The node locate target is structurally outside the primary scroll-target layout.**
   The root `LazyVStack` is the outermost `.scrollTargetLayout()` and exposes group IDs (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:178`), while node IDs live in a nested `LazyVGrid` that declares another `.scrollTargetLayout()` (`Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift:305`). The binding is nevertheless assigned a node target ID (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:229`). Apple's `scrollTargetLayout` contract says nested target layouts do not become additional targets once an outer target layout is established. Consequently locate can expand/highlight a node but fail to bring its tile into view. Use one target layout that owns both group and node targets, or perform a two-stage group-then-node scroll with a single valid target scope.

3. **Medium - The `Attention` health filter is effectively a narrower duplicate of `Slow`, not an attention aggregate.**
   `.degraded` matches only `.degraded` rows, while classification maps only slow latency to that state; timeout maps to unavailable and missing evidence maps to unknown (`Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift:176`, `Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift:198`). `.slow` already includes slow and timeout (`Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift:171`). Tests codify `Attention == [Slow]` and `Slow == [Slow]` for ordinary data (`Tests/MicaTests/WorkbenchProxyWorkspaceTests.swift:90`). The localized label promises “Attention / 需关注”, so unavailable and unknown rows are unexpectedly omitted. Either make Attention the union of degraded/unavailable/unknown or rename it to Degraded and document the overlap.

4. **Medium - Reveal failures display a false, one-size-fits-all explanation.**
   Resolution distinguishes missing group, ambiguous group, and missing node (`Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift:309`), but `WorkbenchProxies` collapses them into one unresolved state and always claims the controller no longer reports the node (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:835`, `Sources/Mica/Features/Workbench/WorkbenchProxies.swift:1020`). A group excluded by the global-visibility preference is also absent from `arrangedGroups` (`Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift:994`), producing the same false message. This violates the task's truthful-unresolved-state requirement. Preserve the resolver status and model global-visibility obstruction separately without mutating the preference.

5. **Medium - Overview-to-Proxies navigation cannot identify duplicate group occurrences reliably.**
   `WorkbenchInspectorSelection` carries only raw `groupName` (`Sources/Mica/Features/Workbench/WorkbenchWorkspaceStore.swift:36`). Overview falls back to that raw name when exact resolution is ambiguous (`Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift:302`), and group navigation chooses the first matching catalog group (`Sources/Mica/Features/Workbench/WorkbenchOverviewPolicyInspection.swift:743`). The Proxies resolver correctly treats duplicate raw names as ambiguous (`Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift:1132`). Cross-page navigation can therefore select the wrong occurrence or fail. Carry the stable occurrence ID end to end.

6. **Medium - Image-only node test buttons lack a localized accessibility name.**
   The per-node test button contains only an SF Symbol and `.help`, without an explicit accessibility label/value (`Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift:522`). VoiceOver may announce the symbol name rather than “Test <node>”. The surrounding selection button also depends on inferred reading order and does not expose health as a factual accessibility value (`Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift:457`). Add localized command labels and a concise state value; keep visible color supplemental to text.

### Runtime-only validation risks

1. **Session switch while scrolling may preserve stale interaction state.** Session-boundary reset asks the presentation coordinator to preserve scroll state (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:394`). If the old scroll phase never emits `.idle`, deferrable updates for the new session could remain queued until the deadline or another phase transition. Unit tests cover normal idle/deadline behavior (`Tests/MicaTests/WorkbenchProxyWorkspaceTests.swift:853`) but not a controller-generation switch mid-scroll.

2. **Large-catalog health aggregation remains a measurement watchpoint, not a proven regression.** `ProxyGroupCatalogIndex` eagerly computes every group's `ProxyGroupHealthSummary`, which scans all members (`Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift:237`, `Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift:438`, `Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift:1309`). Existing offline benchmarks are approximately 59 ms for 100 groups x 1,000 members, so static inspection alone does not establish a visible hitch. Validate with Instruments under catalog churn and scrolling.

3. **Stale navigation rejection has no user-visible reason.** Controller/generation mismatch returns early (`Sources/Mica/Features/Workbench/WorkbenchProxies.swift:825`) and store consumption similarly leaves a mismatched target pending (`Sources/Mica/Features/Workbench/WorkbenchWorkspaceStore.swift:472`). Common session-boundary cleanup likely masks this, so reproduce ordering before treating it as a release blocker.

## Files Found

- `Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift` - health classification, stable IDs, filtering, resolver, and catalog projections.
- `Sources/Mica/Features/Workbench/WorkbenchProxies.swift` - root scrolling, reveal orchestration, session boundaries, and unresolved UI.
- `Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift` - group/node controls, nested grid targets, latency presentation, and accessibility surface.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift` - Overview topology selection resolution.
- `Sources/Mica/Features/Workbench/WorkbenchOverviewPolicyInspection.swift` - cross-page navigation target staging.
- `Sources/Mica/Features/Workbench/WorkbenchWorkspaceStore.swift` - session-scoped navigation state.
- `Tests/MicaTests/WorkbenchProxyWorkspaceTests.swift` - projection, filter, scroll scheduler, and performance coverage.

## External References

- Apple SwiftUI `scrollTargetLayout(isEnabled:)`: https://developer.apple.com/documentation/swiftui/view/scrolltargetlayout%28isenabled%3A%29
- Apple SwiftUI `scrollPosition(id:anchor:)`: https://developer.apple.com/documentation/swiftui/view/scrollposition%28id%3Aanchor%3A%29

## Related Specs

- `.trellis/spec/frontend/workbench-ui-contract.md` - one outer scroll owner, stable IDs, non-positive latency handling, accessibility, and large-catalog performance requirements.
- `.trellis/spec/frontend/live-session-controller-contract.md` - controller ID/session generation validation and truthful live-session state.
- `.trellis/tasks/08-25-policy-group-health-navigation/prd.md` - health filtering, exact reveal, passive-update, and unresolved-state acceptance criteria.

## Caveats / Not Found

- No runtime UI smoke, controller request, remote action, or Instruments capture was performed by instruction.
- Static inspection found no Workbench content-glass misuse, nested `ScrollView` in the Proxies flow, unstable `ForEach` identity in the reviewed policy-group path, view-owned controller networking, or obvious Reduce Motion violation.
- The nested scroll-target issue follows Apple's documented layout ownership semantics; a local runtime smoke should still capture the visual failure and guard the eventual fix.
