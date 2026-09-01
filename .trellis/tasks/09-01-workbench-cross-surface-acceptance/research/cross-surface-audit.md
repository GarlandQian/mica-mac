# Cross-Surface UX Static Audit

## Scope

Static evidence gathered for the Phase 5 Workbench acceptance task. No product code was changed and no runtime/controller access was used.

The audit covers the ten `WorkbenchDestination` cases plus RouterEditor, Settings, menu/toolbar, and global shell. Source, tests, active Trellis contracts, and the parent/Overview tasks are authoritative.

## Existing Strengths To Preserve

- One ten-destination IA: `Sources/Mica/Features/Workbench/WorkbenchChrome.swift:6-57`.
- One dispatch point for destination content and one toolbar search attachment: `Sources/Mica/Features/Workbench/WorkbenchWorkspaceView.swift:18-95`.
- One root workspace inspector: `Sources/Mica/Features/Workbench/WorkbenchChrome.swift:176-185`; no destination-owned `.inspector` is expected.
- Shared flat data-browser scaffold and native Table styling: `Sources/Mica/Features/Workbench/WorkbenchDataShared.swift:7-76`.
- Existing high-cardinality projection caches and offline benchmark cases cover Connections, Logs, Rules, Sources, and Proxies.
- Actions already recognizes sparse command sets and exposes related destinations when command count is at most two: `Sources/Mica/Features/Workbench/WorkbenchActionsPresentation.swift:199-215`.
- The current design tokens already enforce flat opaque content and semantic light/dark colors; another visual system would create regressions rather than improve UX.

## Confirmed Findings

### F1. Inspector close is not a close operation

- The inspector header button is localized as `dashboard.close_inspector`: `Sources/Mica/Features/Workbench/WorkbenchDataShared.swift:304-315`.
- Every migrated inspector passes `workspaceStore.selectInspector(.none)` as the close closure: `Sources/Mica/Features/Workbench/WorkbenchWorkspaceView.swift:151-226`.
- `selectInspector(.none)` clears only `inspectorSelection`; it never sets `isInspectorPresented = false`: `Sources/Mica/Features/Workbench/WorkbenchWorkspaceStore.swift:549-554`.

Observable result: clicking the X replaces detail with the empty inspector state while the trailing column remains open and consumes workspace width.

### F2. Inspector selection has no destination ownership gate

- The root destination observer updates persistence and live demand only: `Sources/Mica/Features/Workbench/WorkbenchChrome.swift:260-265`.
- Row resolvers are removed when data destinations unmount, while global `inspectorSelection` remains: Connections `WorkbenchConnectionsView.swift:100-103`, Rules `WorkbenchRules.swift:75-78`, Logs `WorkbenchLogs.swift:60-64`, Sources `WorkbenchSources.swift:68-71`.
- `WorkbenchInspectorContainer` switches only on selection type and does not compare it with the active destination: `Sources/Mica/Features/Workbench/WorkbenchWorkspaceView.swift:113-140`.

Observable result: destination transitions can briefly or persistently expose an empty/stale inspector state. Clearing the selection directly is also unsafe because each page observes `.none` and clears its row selection. The implementation must hide cross-destination detail separately from clearing a page-owned selection.

### F3. Long-chain topology selection is disconnected from its viewport

- The long-chain graph uses a horizontal `ScrollView` without a reader/position binding: `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift:425-450`.
- Keyboard movement updates only `OverviewTopologyInteractionState`: `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift:577-585`.
- The scroll indicator is always hidden even when the graph width exceeds the viewport: `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift:429`.

Observable result: keyboard-cycle or programmatic selection can target an offscreen node/edge/path with no visual location feedback. This is a follow-up to the still-open `08-23-overview-flow-ribbons` task, not a reason to redesign its ribbons.

### F4. Sparse Actions still uses the wide command canvas

- Projection intentionally identifies sparse command states and supplies related workspaces: `Sources/Mica/Features/Workbench/WorkbenchActionsPresentation.swift:206-215`.
- Ready/partial content always uses a 1,080pt maximum canvas regardless of command count: `Sources/Mica/Features/Workbench/WorkbenchActions.swift:343-367`.

Observable result: one or two real actions can still stretch explanation-to-button distance across a wide window. The fix should derive a compact maximum width from command/group count, not add fake operations or decorative panels.

### F5. Overview durable contract has one stale scroll statement

- The active Workbench UI contract says Overview topology has no nested horizontal viewport under Performance Boundaries.
- `08-23-overview-flow-ribbons` R10 and current source intentionally use a conditional horizontal viewport for long chains while keeping short chains width-filling.

Required resolution: after visual acceptance, update the durable rule to “one vertical scroll owner; conditional bounded horizontal topology viewport only when minimum label width cannot fit.”

### F6. Overview connection drill-in loses occurrence identity

- Controller connection IDs can repeat or be blank, while projected rows and
  topology paths already retain controller-order `sourceIndex` occurrence
  identity.
- Overview summaries and topology/policy drill-in staged only a nonblank raw ID,
  and Connections selected the first matching ID.

Observable result: duplicate IDs navigate to the wrong row and blank IDs cannot
navigate at all. The retained fix stages and resolves `sourceIndex` plus the
exact reported ID while preserving controller order and generation validation.

### F7. Inline destructive confirmations do not support Escape

- Actions runtime confirmations and Controllers delete confirmations expose
  visible Cancel buttons but lacked `onExitCommand`.
- A root-level handler would consume Escape even when no confirmation is
  visible, so cancellation must live on the conditional confirmation subtree.

Observable result: keyboard users cannot cancel these two inline confirmation
states consistently with the shared connection confirmation pattern.

### F8. Refresh/Test affordances bypass shared availability gates

- Toolbar Test/Refresh/Pause reconstructed partial state locally instead of
  consuming `canTestSelectedRouter`, `canRefreshSelectedRouter`, and
  `canTogglePresentationPause`.
- Configuration failed/empty state actions stayed enabled without the shared
  refresh gate.
- Diagnostics issue action buttons had no availability input and could present
  an enabled command while the underlying shared command was busy or not live.

Observable result: command bars, state actions, and issue actions can disagree
about whether the same operation is available. The retained UI fix consumes the
shared AppModel gates and rechecks availability at the UI dispatch boundary.

### High-Priority Residual: AppModel command entry points

The AppModel network/remote-command methods are outside this task's approved
presentation boundary and were intentionally not changed. Some entry points do
not independently enforce the same capability/busy/live-session predicates, so
a future non-UI or stale programmatic caller could bypass the corrected UI
affordances. A follow-up should harden those method boundaries with controller
ID and session-generation validation plus the shared command gates, with direct
AppModel tests. This is defense in depth, not permission to broaden this task.

## Audit Matrix For Implementation

| Surface | Primary UX checks | Stress/state checks |
| --- | --- | --- |
| Global shell/sidebar/status | destination focus, title/toolbar duplication, inspector transition, status compression | controller switch, generation end, pause, stale reconnect, narrow width |
| Overview | command wrap, fixed-core hierarchy, topology locate/scroll discoverability | live revisions, long chain, Reduce Motion, inactive window |
| Proxies | group expansion, filter, selected-node reveal, inspector ownership | many groups/nodes, scroll deferral, catalog revision |
| Connections | selection/rail/inspector sync, search/sort, close confirmation | 2,000 rows, metrics-only revisions, active/closed |
| Logs | follow newest, search/filter, selection/inspector | 2,000 rows/8 MiB, steady stream, paused presentation |
| Rules | table columns, target jump, selection reconciliation | large rules, connection count index, mutation state |
| Sources | table/selection, update-all progress, inspector | large catalog, serial update projection, partial failure |
| Controllers/RouterEditor | management selection vs Use, form compression, dirty close | profile order, per-row test progress, generation safety |
| Configuration | grouped form labels, focus/commit, unsupported states | partial/live gates, language/font changes |
| Actions | sparse/dense command balance, inline confirmation, related navigation | 0/1/2/many commands, partial/live/busy |
| Diagnostics | action-first hierarchy, outline keyboard navigation, copy report | expanded disclosure, partial evidence, redaction |
| Settings/menu | native layout, immediate preference repaint, command discovery | en/zh, light/dark/system, four font scales |

## Constraints Derived From Evidence

- Do not launch Mica or contact a controller during automated work.
- Do not add production mock data for visual balance.
- Do not change controller order, optionality, capabilities, or generation semantics.
- Do not introduce content glass, card walls, modal detail, a second inspector, or page-owned networking.
- Treat Mica's 28pt standalone icon control as the project-specific macOS pointer contract; use the HIG audit for contrast/semantics rather than imposing a mobile 44pt row height.

## Recommended Implementation Boundaries

1. Shared inspector semantics and destination gating in `WorkbenchWorkspaceStore`, `WorkbenchChrome`, and `WorkbenchWorkspaceView`, with focused store/navigation tests.
2. Pure topology scroll-target projection plus lightweight viewport binding in `WorkbenchOverviewTopologyView`, reusing existing layout/index geometry.
3. Pure sparse Actions layout decision in `WorkbenchActionsPresentation`, consumed by `WorkbenchActions`.
4. Evidence-led fixes from the matrix only; broad visual edits require a reproducible failure and matching acceptance case.

## Completed Audit Outcome

The static 14-surface pass retained F1-F4 and F6-F8 as reproducible defects.
F5 remains a durable-spec update for the main session after visual acceptance.
No additional deterministic overlap, truncation, scroll-ownership, focus,
state, localization, accessibility, or performance defect met the task's edit
threshold. Runtime light/dark and real-controller traversal remain user
acceptance work; automated work did not launch Mica or contact a controller.
