# Research: Current Workbench Diff Functional Audit

- Query: Audit the current policy-group health/navigation diff for confirmed behavioral defects.
- Scope: source, tests, task contracts, source verifier and offline quality gates; no runtime UI smoke or controller contact
- Date: 2026-08-27

## Confirmed Findings

1. **P1 - Topology Open Proxies drops the selected target.** `WorkbenchOverviewTopologyView.swift:275-277` only changes destination. The same closure serves the topology context menu and accessibility representation, so neither path stages `WorkbenchProxyNavigationSelection`.
2. **P1 - A global search with zero matching groups renders a blank body.** `WorkbenchProxies.swift:155-220` branches on unfiltered `arrangedGroups` but renders filtered `groupPresentations`; a non-empty catalog plus empty `visibleGroups` enters an empty ScrollView instead of filtered-empty state.
3. **P1 - Duplicate group occurrences lose exact identity across Overview navigation.** `WorkbenchOverviewPolicyInspection.swift:735-768` stages the raw group ID while `WorkbenchProxyPresentation.swift:1132-1180` correctly rejects duplicate raw IDs as ambiguous. The existing test proves the resolver behavior but not the broken end-to-end entry path.
4. **P1 - Node reveal IDs are outside the active scroll target layout.** The outer `LazyVStack.scrollTargetLayout()` in `WorkbenchProxies.swift:178-220` owns group targets; the nested `LazyVGrid.scrollTargetLayout()` in `WorkbenchProxyGroupPanels.swift:305-350` cannot add nested targets. The binding is nevertheless assigned a node ID at `WorkbenchProxies.swift:229-234`.
5. **P2 - Hidden GLOBAL and empty-catalog targets are not truthfully resolved.** `WorkbenchProxyPresentation.swift:994-1010` removes GLOBAL before indexing; `WorkbenchProxies.swift:807-847` either refuses to consume an empty index or reports the target missing. Data hidden by a preference is therefore described as no longer reported.
6. **P2 - Clear Filters and Locate is not one-shot.** `WorkbenchProxies.swift:850-930` records only the first obstruction and clears one of search, group query or health filter per click. A target hidden by multiple filters requires repeated clicks despite AC4.
7. **P2 - Locate Current Node prioritizes inspector-only selection.** `WorkbenchProxies.swift:719-761` returns any inspected `.proxyNode` before reading each group's controller-reported selected member. A node inspected in a read-only group can therefore be labeled current without being controller-current.
8. **P2 - Health filter labels and membership disagree.** `WorkbenchProxyPresentation.swift:166-218` makes Attention effectively slow-only while Slow includes timeout/unavailable; the localized labels promise distinct diagnostic concepts.
9. **P2 - Non-positive delay remains visibly formatted as valid latency.** `WorkbenchProxyPresentation.swift:1051-1085` retains zero/negative values and `WorkbenchProxyGroupPanels.swift:473-479,691-703` formats every non-nil delay, although the latency scale already treats non-positive values as unavailable.
10. **P2 - Node test icon has no localized accessibility label.** `WorkbenchProxyGroupPanels.swift:522-553` provides help text but no explicit command label, contrary to the Workbench accessibility contract.

## Validation Evidence

- Focused proxy tests: 22 passed.
- Full Swift suite: 314 tests in 27 suites passed.
- Source verifier and syntax check: passed.
- Localization catalog JSON parse: passed.
- `git diff --check`: passed.
- Current 100,000-node proxy catalog benchmark was approximately 2.62% faster than the matching baseline; this is noise/neutral under the project's 10% retention rule, not a claimed optimization.

## Gaps

- No current test covers topology action -> stage -> Proxies reveal, filtered-empty root state, hidden GLOBAL, multiple simultaneous obstructions, toolbar-current semantics, non-positive tile display, or the icon command accessibility label.
- No runtime UI smoke was authorized. The invalid nested target layout is confirmed by Apple's API contract, but the eventual replacement still requires visual verification.
- No controller was contacted and no remote action was invoked.
