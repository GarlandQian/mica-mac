# Design: Workbench Cross-Surface UX Acceptance

## 1. Architecture Boundary

This task changes presentation and per-window interaction state only. It does not change MicaCore, controller transports, capabilities, AppModel network operations, live publication cadence, profile persistence, or controller ordering.

Primary ownership remains:

- `WorkbenchWorkspaceStore`: ephemeral per-window destination/selection/inspector coordination.
- `WorkbenchChrome` / `WorkbenchWorkspaceView`: root lifecycle, destination dispatch, and the single inspector attachment.
- Existing page projections: pure layout/interaction decisions derived from real data.
- Existing SwiftUI pages: declarative rendering of those projections.

No compatibility wrapper, parallel state store, new dependency, page timer, or second inspector is introduced.

## 2. Inspector State Semantics

### 2.1 Selection ownership

Add a pure default `owningDestination` mapping to
`WorkbenchInspectorSelection`:

- proxy group/node -> `.proxies`
- connection -> `.connections`
- rule -> `.rules`
- log -> `.logs`
- source -> `.sources`
- controller -> `.controllers`
- none -> nil

The store also records the actual owner when a selection is made. Page-owned
selections use the default mapping, while the already-approved Overview policy
node inspector supplies the explicit `.overview` origin for the same
`.proxyGroup` / `.proxyNode` selection payloads. This typed origin preserves
Overview inspection without making proxy selection ownership ambiguous.

`WorkbenchInspectorContainer` receives the active destination and renders
business detail only when the recorded owner matches that destination. A
mismatch renders no business detail and never resolves an old page's row through
a missing resolver.

### 2.2 Separate hide from dismiss

`WorkbenchWorkspaceStore` exposes two distinct operations:

- `dismissInspector()`: set selection to `.none`, clear the recorded owner, and
  set `isInspectorPresented` to false. Inspector X buttons use this operation,
  so their localized “close inspector” label becomes truthful. Existing page
  observers then reconcile their selected row to nil.
- `prepareInspectorForDestinationChange(to:)`: hide the inspector when the
  destination does not match the recorded owner, and restore it when returning
  to that owner. Do not clear the selection here; clearing would trigger the
  outgoing page's observer and erase its per-destination workspace selection
  during SwiftUI lifecycle reordering.

`selectInspector(_:)` must always ensure `isInspectorPresented = true` for a non-none selection even when the same selection value is restored after a prior hide. This makes destination restoration deterministic.

### 2.3 Lifecycle

`WorkbenchRootLifecycleObserver.onChange(of: destination)` calls `prepareInspectorForDestinationChange(to:)` before updating visible-domain demand. Controller/generation termination continues to call `clearSessionBoundState`, which clears session-bound selection; it also hides the inspector when its detail is no longer valid.

Focused tests cover:

- close clears and hides;
- destination transition hides without deleting the old destination workspace selection;
- same selection can reopen after a transition;
- current-destination selection is not hidden;
- Overview and Proxies origins remain distinct for identical policy payloads;
- controller/generation clearing cannot retain visible detail.

## 3. Long-Chain Topology Viewport

Keep the `08-23` geometry, ribbons, hit index, and horizontal-overflow rule. Add a pure `OverviewTopologyViewportTarget` resolver that accepts current `OverviewTopologySelection`, layout/index, and viewport width, then returns a stable target identity/x anchor:

- node selection -> selected node center;
- edge selection -> edge midpoint;
- path selection -> first policy-hop node when available, otherwise the path's central visible segment;
- missing/stale selection -> nil.

The horizontal ScrollView uses native position/reader support with stable invisible anchors derived from existing geometry. Selection changes scroll only when the target is outside the visible viewport plus a small acquisition margin. User-driven horizontal scrolling is never continuously overridden.

- Overflow shows the native horizontal indicator; short-chain width keeps it absent.
- Explicit click, keyboard movement, pinned HUD selection, and cross-page programmatic selection share the same target resolver.
- Scroll animation uses `MicaTheme.Motion` only when Reduce Motion is false; otherwise location changes immediately.
- Target resolution must not rebuild topology layout, scan SwiftUI views, or introduce a timer.

Unit tests cover node/edge/path target choice, stale selection, short-chain no-scroll, overflow scroll, and deterministic output.

## 4. Sparse Actions Layout

Extend `WorkbenchActionsSnapshot` (or a pure adjacent layout projection) with a semantic density result:

- no commands/recovery -> existing recovery canvas;
- 1-2 commands -> compact maximum canvas width (780pt), one column;
- 3+ commands with enough available width -> current 1,080pt adaptive layout;
- width below the existing threshold -> one column regardless of command count.

The projection continues to expose every capability-backed command and the existing related destinations. It does not invent descriptions, metrics, cards, or actions. The view consumes the projection rather than recomputing command counts in multiple branches.

Tests cover 0/1/2/many command snapshots, group ordering, width mode, related destinations, and existing capability gates.

## 5. Cross-Surface Audit Pass

After the three confirmed fixes, audit the 14-module matrix in `research/cross-surface-audit.md`. A change is allowed only when one of these evidence forms exists:

1. deterministic unit/layout/source assertion failure;
2. localization or accessibility contract failure;
3. reproducible narrow/medium/wide composition failure from source-driven fixture state;
4. user screenshot showing a repeatable defect;
5. measured performance regression/hotspot.

Prefer shared primitive fixes when at least three surfaces exhibit the same defect. Otherwise keep the change in the owning page. Do not refactor accepted pages merely to make their source look uniform.

The evidence pass additionally permits three confirmed shared-state repairs:

- connection navigation uses controller order occurrence identity plus the
  exact reported ID, including duplicates and blanks;
- Escape is attached only to visible Actions/Controllers inline confirmation
  subtrees;
- toolbar, Configuration state actions, and Diagnostics issue actions consume
  the existing AppModel capability/busy/live-session gates and reject stale UI
  intents before dispatch.

AppModel remote-command method hardening remains outside this presentation task.

## 6. State, Localization, And Accessibility

- Reuse `WorkbenchStateView`, `WorkbenchStaleNotice`, shared command capabilities, and status bar outcomes. No page-local vocabulary for the same state.
- Add visible copy only when an existing localized key cannot express the behavior; update English and `zh-Hans` together.
- Inspector and topology controls receive localized labels/help and selected-state semantics.
- Mica's macOS pointer metrics remain authoritative. Contrast is checked against both MicaTheme appearances; icon-only controls use the existing 28pt frame and complete `contentShape`/accessibility label.
- No meaning relies on color alone. Reduce Motion removes scroll animation but not auto-location.

## 7. Performance Plan

- Capture the existing offline Release report before touching a relevant projection hot path.
- Inspector destination checks and Actions density are O(1).
- Topology scroll target uses existing dictionaries/geometry; path target resolution is bounded by one selected path and must not rebuild layout.
- Run focused unit tests while iterating. If high-cardinality or topology projection code changes, run two comparable `before` and `after` benchmark reports and apply the contract's 10% retention/regression rule.
- Full tests/build/verifier run once after focused changes stabilize.

## 8. Compatibility, Migration, And Rollback

- No persisted schema or compatibility migration is needed. Inspector visibility/selection remains ephemeral and session-bound.
- Existing per-destination persisted search/filter/sort/selection formats remain unchanged.
- Each implementation phase should be independently revertible: shared inspector semantics, topology viewport, sparse Actions, then evidence-led page fixes.
- `08-23-overview-flow-ribbons` visual acceptance is a prerequisite for topology edits. Its durable contract drift is corrected during the final `trellis-update-spec` pass.

## 9. Validation Boundary

Automated validation uses fixtures and offline tests only. It must not launch Mica, contact a controller, click Test/Refresh/Update/Close/Action controls, or access user profile/secret stores. Final light/dark runtime screenshots and real-controller page traversal remain a user acceptance step unless separately authorized.
