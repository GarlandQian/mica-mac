# Workbench UI Contract

## Scope

Apply this contract to the owned files in `Sources/Mica/Features/Workbench/`
and to the app-wide design system in `Sources/Mica/Design/`. The
design system is two files: `MicaTheme.swift` owns the Mica Ops color,
typography, spacing, shape, metrics, and motion tokens, and
`MicaThemeComponents.swift` owns the shared SwiftUI primitives built on them.
The controller/data layer is stable; no previous Workbench View, presenter,
projector, interaction store, layout helper, file split, or UI-test type is a
compatibility requirement.

## File Architecture

The directory contains exactly:

- `WorkbenchChrome.swift`
- `WorkbenchWindow.swift`
- `WorkbenchSidebar.swift`
- `WorkbenchStatusBar.swift`
- `WorkbenchControllerSelector.swift`
- `WorkbenchWorkspaceView.swift`
- `WorkbenchWorkspaceStore.swift`
- `WorkbenchDashboard.swift`
- `WorkbenchOverviewEditor.swift`
- `WorkbenchOverviewPolicyInspection.swift`
- `WorkbenchOverviewPreferences.swift`
- `WorkbenchOverviewProjection.swift`
- `WorkbenchOverviewTelemetry.swift`
- `WorkbenchOverviewTopology.swift`
- `WorkbenchOverviewTopologyView.swift`
- `WorkbenchOverviewWindowRuntime.swift`
- `WorkbenchProxyGroupPanels.swift`
- `WorkbenchProxyInteraction.swift`
- `WorkbenchProxyPresentation.swift`
- `WorkbenchProxies.swift`
- `WorkbenchDataInteraction.swift`
- `WorkbenchDataPresentation.swift`
- `WorkbenchDataShared.swift`
- `WorkbenchConnections.swift`
- `WorkbenchConnectionCache.swift`
- `WorkbenchConnectionsView.swift`
- `WorkbenchConnectionPulseView.swift`
- `WorkbenchConnectionDetails.swift`
- `WorkbenchRulePresentation.swift`
- `WorkbenchRules.swift`
- `WorkbenchRuleDetails.swift`
- `WorkbenchSettings.swift`
- `WorkbenchSourcePresentation.swift`
- `WorkbenchSources.swift`
- `WorkbenchSourceDetails.swift`
- `WorkbenchLogPresentation.swift`
- `WorkbenchLogs.swift`
- `WorkbenchManagement.swift`
- `WorkbenchControllerPresentation.swift`
- `WorkbenchControllers.swift`
- `WorkbenchConfiguration.swift`
- `WorkbenchActionsPresentation.swift`
- `WorkbenchActions.swift`
- `WorkbenchTailscale.swift`
- `WorkbenchDiagnosticsPresentation.swift`
- `WorkbenchDiagnostics.swift`
- `WorkbenchDiagnosticsComponents.swift`

Files follow ownership and update frequency. The shell keeps destination/root
lifecycle in `WorkbenchChrome.swift`, window/editor coordination in
`WorkbenchWindow.swift`, navigation in `WorkbenchSidebar.swift`, and session or
operation status in `WorkbenchStatusBar.swift`. The design system is shared
app-wide from `Sources/Mica/Design/`: `MicaTheme.swift` owns tokens, typography,
spacing, shape, metrics, and motion; `MicaThemeComponents.swift` owns the shared
SwiftUI primitives (the `Mica*` panel, hairline separator, mono metric, status
dot/badge, section header, and empty-state family, plus the `Workbench*`
symbol, page-scaffold, command-bar, section, state-view, status-badge,
stale-notice, and icon-command primitives). Data interaction/scroll coordination,
controller-neutral presentation helpers, and shared data-browser SwiftUI
composition remain separate in `WorkbenchDataInteraction.swift`,
`WorkbenchDataPresentation.swift`, and `WorkbenchDataShared.swift`.

Overview keeps root/module composition in
`WorkbenchDashboard.swift`, instrument/telemetry and chart composition in
`WorkbenchOverviewTelemetry.swift`, topology geometry/cache in
`WorkbenchOverviewTopology.swift`, and topology SwiftUI/Canvas rendering in
`WorkbenchOverviewTopologyView.swift`. Global compact preferences and immediate
controls live in `WorkbenchOverviewPreferences.swift` and
`WorkbenchOverviewEditor.swift`; the policy inspection index, projection, cache,
and policy inspector content live in
`WorkbenchOverviewPolicyInspection.swift`; each window's demand ID and
session-scoped telemetry/topology runtimes live in
`WorkbenchOverviewWindowRuntime.swift`.

Connections keeps row/intent/navigation projection in
`WorkbenchConnections.swift`, high-frequency pulse/cache/cadence logic in
`WorkbenchConnectionCache.swift`, the live Table workspace in
`WorkbenchConnectionsView.swift`, pulse rendering in
`WorkbenchConnectionPulseView.swift`, and the connection inspector content in
`WorkbenchConnectionDetails.swift`. Logs, Rules, and Sources each split pure
presentation/cache logic from their root Table view; the log inspector content
lives in `WorkbenchLogs.swift`, and Rules and Sources also keep their inspector
content in `WorkbenchRuleDetails.swift` and `WorkbenchSourceDetails.swift`.

`WorkbenchManagement.swift` owns only primitives shared by management
destinations. Controller list/test projections live in
`WorkbenchControllerPresentation.swift`; `WorkbenchControllers.swift` owns the
full-width native list workspace and the controller inspector content. Actions separates its pure availability,
dispatcher, target-scope, and command projection from root composition across
`WorkbenchActionsPresentation.swift` and `WorkbenchActions.swift`; sing-box
Tailscale rendering remains in `WorkbenchTailscale.swift`. Diagnostics separates
pure issue projection, root composition, and reusable workspace components across `WorkbenchDiagnosticsPresentation.swift`,
`WorkbenchDiagnostics.swift`, and `WorkbenchDiagnosticsComponents.swift`.
Proxies keeps root composition, page state, and AppModel intents in
`WorkbenchProxies.swift`; active group/node UI in
`WorkbenchProxyGroupPanels.swift`; catalog and scroll scheduling in
`WorkbenchProxyInteraction.swift`; and pure presentation, indexing, cache, and
workspace reconciliation in `WorkbenchProxyPresentation.swift`. Do not add
compatibility files or recreate one-file-per-small-component sprawl. Cross-file
family entry points plus genuinely shared presentation primitives may be
module-internal; leaf views remain `private`. A source move must update
this exact list, the corresponding per-file aggregates and ownership assertions
in the source verifier, and any test that reads a file by name in the same
change. This keeps ownership checks meaningful instead of weakening them after
a split.

## Navigation And Chrome

- Use one `NavigationSplitView` and ten fixed destinations: Overview,
  Proxies, Connections, Logs, Rules, Sources, Controllers, Configuration,
  Actions, and Diagnostics. The sidebar presents them in three fixed groups —
  Operate (Overview, Proxies, Connections, Rules), Observe (Logs, Sources,
  Diagnostics), and Manage (Controllers, Configuration, Actions) — and the six
  controller-data destinations (Overview through Sources) keep their
  `Command-1`…`Command-6` View-menu shortcuts. Application preferences live
  only in the native Settings scene opened from the app menu (`Command-,`).
- The sidebar starts with a collapsed inline controller switcher above the
  ten destinations. Expanding it reveals persisted-order controller rows
  plus Add and Manage actions in the same window; the full management surface
  remains on Controllers. Controller identity is not repeated in the toolbar;
  the native navigation title owns that space without a custom capsule.
- Normal work happens in the main window. Controller editing, proxy expansion,
  member selection, filters, tests, inspectors, and operation results do not
  depend on popovers, context menus, sheets, or modal dialogs. The topology
  canvas may mirror its direct canvas and keyboard selection commands in one native context menu;
  no business data or command may exist only there. A native confirmation is
  reserved for destructive/high-risk actions or a dirty-window close.
- The right-side `.inspector` column is the single detail-reveal mechanism for
  the whole workbench. `WorkbenchChrome.swift` attaches it once on the
  workspace, and `WorkbenchInspectorContainer` (in `WorkbenchWorkspaceView.swift`)
  renders the typed `WorkbenchInspectorSelection` owned by
  `WorkbenchWorkspaceStore`: `.proxyGroup`/`.proxyNode`, `.connection(id:)`,
  `.rule(type:payload:)`, `.log(id:)`, `.source(id:)`, and `.controller(id:)`.
  Connections, Rules, Logs, and Sources register live row resolvers on the
  store so the inspector always shows current-generation data; controller
  detail resolves its profile directly from the app model. Each selection has
  a default `owningDestination`, while the store records the actual origin so
  Overview policy-node inspection can own the same `.proxyGroup`/`.proxyNode`
  payloads that Proxies uses. `WorkbenchInspectorContainer` resolves business
  detail only when that recorded owner matches the active destination.
  Selecting an inspectable item reveals the inspector and stays in two-way sync
  with the owning page's selection; inspector selection is window-level,
  session-bound, and never persisted. `dismissInspector()` clears the selection
  and recorded owner and hides the column. A destination transition hides a
  mismatched owner without clearing it, so returning to that destination can
  restore valid detail without erasing its workspace selection. No destination
  attaches a page-level `.inspector`, and hover presents a standard tooltip only.
- Inspector coordination stays in `WorkbenchWorkspaceStore` through
  `selectInspector(_:from:)`, `clearInspectorSelection(ownedBy:)`,
  `dismissInspector()`,
  `prepareInspectorForDestinationChange(to:)`, and
  `inspectorSelection(for:)`. A non-none repeat selection must reveal a column
  that was hidden earlier; `.none` does not fabricate an owner. Page selection
  reconciliation uses the owner-gated clear operation, which leaves column
  visibility unchanged. It must never use a global `selectInspector(.none)`:
  a late outgoing-page callback could otherwise erase a newer selection from
  another destination. Only the explicit close command calls
  `dismissInspector()` and hides the column.
- The inline switcher observes only profiles, selected ID, and the controller
  fields it renders. Traffic/log frames must not rebuild the expanded list.
  It starts collapsed and closes while the controller editor is active.
- Each controller editor presentation owns a fresh presentation identity even
  when it edits the same `RouterDraft.ID`; otherwise SwiftUI can retain stale
  field state across consecutive Add/Edit intents.
- Inline destructive confirmations and editable runtime fields capture the
  selected controller ID plus session generation. They clear or reject their
  action when either value changes, so a delayed command cannot target a new
  controller session.
- The bottom status bar keeps native fixed geometry and shows selected
  controller, live/paused/partial/failed state, and a stable relevant timestamp.
  Completed operation outcomes replace the activity segment inside this same
  bar instead of stacking a second result bar. Its final narrow fallback
  remains compressible; row-wide fixed sizing must not force status content
  outside the window.

## Visual System

### Page Archetypes

- Choose the page archetype before changing its styling. Do not make a data
  browser, monitoring canvas, selector, form, and diagnostic outline share one
  generic card composition.
- Overview is a monitoring canvas: its fixed core is three primary real-time
  charts for upload, download, and active connections followed by complete
  topology. Optional instrument, operational-summary, and grouped-network
  modules follow the fixed core only when globally enabled. Charts expose
  selection, cursor, pause, and same-window drill-in
  instead of acting as decoration. The monitoring canvas fills the remaining
  content width after page padding; it does not inherit the bounded reading
  width used by management forms.
- Connections, Logs, Rules, and Sources are data browsers: one native `Table`,
  toolbar search/filter/sort controls, stable rows, and row detail in the
  workspace inspector. Loading and empty states occupy the table region without
  changing the command-bar geometry.
- Proxies is an ordered selection workspace: controller-reported groups remain
  in order, expand inline, and expose node selection and filtering without a
  modal. Selection hierarchy matters more than dashboard metrics.
- Controllers detail and Configuration use the same bounded native grouped-form
  canvas. Actions is a state-aware command workspace: checking/recovery uses a
  compact unframed target/status composition, while ready/partial uses bounded
  flat command groups in two measured-width columns or one compact column.
  The Controllers destination is one full-width native `List` whose selection
  opens the workspace inspector for detail, and the native Settings scene keeps
  its own bounded grouped form outside Workbench navigation.
- `WorkbenchFormRow` owns the only visible label for every management field.
  Embedded text fields, secure fields, pickers, toggles, and nested configuration
  controls inherit hidden native labels from that shared row instead of adding
  page-local fixes.
- Controller add/edit uses one native grouped form and one scroll owner. Do not
  restore a fixed preview column or repeat draft values before testing; append
  connection diagnosis as another form section only after Test starts. A
  `WorkbenchFormRow` owns the only visible field label, so embedded native
  controls hide their own Form labels. Cancel, Test, and Save retain visible
  titles under horizontal compression instead of collapsing to isolated icons.
- Diagnostics is an action-first triage workspace. It uses an unframed verdict,
  adaptive issue master-detail, Available Now domains, and one secondary
  technical disclosure; the copied report remains the complete support payload.
- Before redesigning an archetype, review the corresponding current Apple HIG
  component and one current native macOS reference. Record any deliberate
  exception here before introducing a second layout model.

- Use the exact Mica Ops tokens from `MicaTheme` (light / dark):
  - canvas `#FFFFFF` / `#0D0E10` (window background)
  - surface `#F5F6F7` / `#15171A` (panels, sidebar selections)
  - surfaceRaised `#FFFFFF` / `#1C1F23` (inspector, popovers)
  - separator `#D9DBDF` / `#2A2D32` (opaque hairlines only)
  - textPrimary/textSecondary/textTertiary: system label-color ramps in both
    appearances
  - accent (signal teal) `#0B8F66` / `#34D1A3`
  - statusOK/statusWarning/statusError: system green/orange/red
- The accent never decorates: it marks selection, the active topology path,
  primary actions, and live indicators only. Status colors carry
  controller-reported state only and never brand chrome. Navigation and
  table-row selection use a 14% accent fill over the surface. Numeric values
  use the monospaced `data*` text roles with tabular numerals so live refreshes
  never shift layout. Motion in `MicaTheme.Motion` (120–200ms ease-out)
  animates only value or structural state changes and degrades to static under
  Reduce Motion; there are no idle loops.
- Text uses the semantic textPrimary/textSecondary/textTertiary ramps. Primary
  text contrast stays at least 4.5:1 and secondary/large data at least 3:1.
- Sidebar navigation remains a native virtualized list, but destination rows
  own their button selection semantics. Selection uses a 14% accent fill,
  a three-point leading indicator, monochrome symbols, and primary text rather
  than the saturated system-wide selection block. Rows use the label text role
  plus compact vertical padding, and the native button label fills the complete list
  row with a rectangular interaction shape. Do not impose one global touch
  height on this pointer-driven macOS navigation.
- Native window/sidebar/toolbar material is allowed. Workbench content contains
  no custom `.glassEffect`, `GlassEffectContainer`, nested cards, or repeated
  floating panels. Content surfaces are flat color fills separated by hairlines —
  no glow, decorative gradients, elevation shadows, or ambient animation loops
  anywhere.
- The window container, native toolbar, command bars, and management canvas use
  the same `MicaTheme.canvas` page fill across every destination. Loading,
  unavailable, filtered-empty, and empty states paint that fill explicitly;
  `MicaTheme.surface` and `MicaTheme.surfaceRaised` are reserved for panels,
  sidebar selections, and the raised inspector/popover surfaces. Management
  pages use a leading-anchored bounded canvas with an 1180-point limit;
  form-heavy pages use a 1040-point limit. The native Settings window uses one
  centered grouped form limited to 820 points, with no duplicate Workbench route
  or repeated in-page title. Data browsers remain width-filling.
- Overview uses a fixed core on flat `MicaPanel` surfaces. Its default contains
  telemetry followed by complete route topology. Instrument rail, operational
  summaries, and grouped network information are optional and hidden by default.
  Their order is fixed after topology; none can be resized or reordered.
- Telemetry is one module containing equal-weight upload, download, and active-
  connection panels. Wide layouts use three columns, medium layouts use two
  traffic columns plus a full connection row, and narrow layouts stack them.
  Each panel keeps a substantial plot, one current or selected value, and the
  shared cursor, pin, stepping, pause, and return-live state. Memory appears as
  context on the connection panel instead of a fourth chart. Plot height follows
  effective panel width within a stable 240-to-300-point range, so the three
  charts remain the first visual layer across narrow, medium, and wide windows.
  Overview section titles use 34-point framed marks and metric titles use
  28-point framed marks: a hierarchical monochrome SF Symbol tinted
  `textSecondary` on a flat surface plate with a hairline border. The status
  colors remain reserved for actual healthy, warning, or failure meaning.
  Dense rows keep unbacked monochrome
  symbols so the marks do not become decorative cards.
  The telemetry
  header has exactly two width-driven compositions: regular keeps title, state,
  commands, and the segmented timeline mode on one row; compact keeps every
  command while placing title/state and timeline controls on stable wrapped rows.
  Font preference never chooses the composition directly. Transient hover
  updates chart readouts and indicators but does not change the header from
  Live to Selected; only a pinned sample owns that chrome state.
- Corners come from `MicaTheme.Shape` and `MicaTheme.Metrics`: 6-point panels,
  10-point window-level surfaces, 8-point group modules, and 5-point badges.
  Native system controls keep their own geometry.
- Command summaries, section headings, and metric labels render SF Symbols
  through the shared `WorkbenchSymbol` primitive with monochrome rendering, a
  stable frame, and an explicit semantic tint. Do not rely on an inherited
  `LabelStyle` or secondary foreground alone for these navigation cues.
- Mica interface text uses `micaThemeFont` semantic roles (`MicaTheme.TextRole`:
  caption/label/body/title3/title/hero/heroLarge, plus the SF Mono `data*`
  variants reserved for live data) and the selected
  `AppFontScale` multiplier (`0.92`, `1.0`, `1.16`, `1.32`). Dynamic Type remains
  a native-control fallback. Window, sidebar, table, hit-target, toolbar, and
  status-bar geometry do not multiply by the font preference. Do not add direct
  view-level `.font(...)` calls for interface text.

## Data And Ordering

- Render real `AppModel`/`MicaCore` values only. Never fabricate chart
  samples, latency, counters, topology, network identity, rows, or success state.
- Active controller data is fully visible and selectable: endpoints, URLs, IDs,
  names, rules, chains, payloads, paths, metadata, and logs.
- Credentials, authorization values, subscription URLs, Keychain contents, and
  raw response/stream bodies stay out of diagnostics exports.
- Presentation filtering/sorting never mutates controller collections.
- Connections, Rules, and Sources may sort presentation copies. Logs retain
  incoming order and explicit Follow Newest behavior.
- Sources exposes one typed Update All operation. It filters the reported
  catalog to updatable entries without reordering them, updates sequentially
  through the shared provider task slot, publishes current/completed/success/
  failure progress, and refreshes provider snapshots exactly once at the end.
  Single-provider update, health-check, and reload commands cannot cancel or
  race an active batch.
- Provider presentation keeps reported test URLs and subscription metadata;
  missing values remain unavailable rather than synthesized.
- Rule-to-connection aggregates pre-index connection payload/type counts once
  per projection. Log rows cache search text by stable entry ID, and an empty
  log filter returns the incoming row array directly. Do not put O(rows x
  connections) scans or repeated full-string assembly in a table body.
- Follow Newest coalesces rapid programmatic requests against the last actual
  scroll time. A debounce restarted by every log entry can starve scrolling
  under a steady stream and is not acceptable.
- sing-box `trace` logs remain `trace` through projection and filtering. The
  Trace filter appears only for a resolved sing-box session; Mihomo and Surge
  must not expose a level their stream/filter contract does not provide.
- Proxies use one source-ordered vertical workspace capped at a readable width.
  Each policy group is an inline disclosure with a compact identity/current
  selection header and a controller-derived latency distribution. The page has
  one vertical scroll owner and never adds a horizontal scroll axis, sheet, or
  popover for normal policy browsing.
- Group and member controller order stays stable. Mihomo catalogs arrive with
  ordinary groups in `GLOBAL.all` configuration order, followed by unlisted
  groups in `/proxies` order; Surge and sing-box keep their reported sequence.
  Generic presentation only appends visible `GLOBAL` last. Every accepted
  refresh uses the latest catalog and never merges an earlier interaction order,
  alphabetizes names, or ranks by latency.
- Cache the arranged/filtered group catalog for the current catalog revision,
  visibility preference, and query. Build/search member indexes only for groups
  the user has expanded, and prune a group's index when it closes. Each expanded
  group owns its filter. Proxy search text remains precomputed outside SwiftUI
  tile bodies.
- Expanded nodes use one adaptive, source-ordered grid that settles into three,
  two, or one readable columns as width contracts. Default cells have no
  permanent outline; a leading state rail plus restrained hover, inspection,
  and current-node treatments establish hierarchy. A cell shows the reported
  name, type, transport capabilities, source, SMART rank, availability, exact
  latency, and current-selection state when those values exist. Clicking its
  main body inspects it and invokes the existing capability-gated switch action;
  latency testing remains a visually secondary, separate command.
- The selection-driven node detail renders in the workspace inspector as one
  flat field composition, not a field-card wall. Overview, reported `true` and
  `false` transport states, and testing/latency use adaptive key-value columns.
  Known fields must not be repeated under additional controller fields.
  Additional controller fields render in stable key order as monospaced
  key-value rows; arrays and objects use deterministic compact JSON.
- Closing details clears only the local inspection selection and never changes
  the controller-selected node.
- Build the complete reported-field rows only for the selected node detail.
  Search metadata may remain precomputed for the catalog, but invisible nodes
  must not pay the full raw-field formatting cost. Exclude raw `now` and `all`
  from that metadata search blob because selected names and member names are
  already indexed separately.
- Multiple groups may stay expanded simultaneously in source order. Closing the
  active group selects the next open source-order group, or the previous group
  when no next group exists. Local disclosure/filter/detail state never reorders
  controller data.
- A collapsed group summarizes only real positive reported delays into fast,
  normal, slow, timeout, and unavailable segments. Missing or non-positive
  values count as unavailable and never affect ordering.
- A selected rule exposes one compact
  `type → payload → target policy` focus path above the native Table. Only an
  exact case-sensitive visible policy-group target is actionable; DIRECT,
  REJECT, node names, and unknown targets remain plain data. Activation opens
  the target through the existing proxy workspace projection before navigating.
- SMART usage labels come only from controller-reported values and never trigger
  local reordering.
- A group whose controller reports `selectable == false` remains openable,
  inspectable, filterable, and latency-testable when supported, but member
  switching is disabled in both presentation and AppModel.
- Connections without a non-blank controller ID remain readable but do not show
  single-close commands and are excluded from grouped close projections.
- Overview is a focused summary, not another data browser. Its fixed core is
  primary telemetry followed by complete route topology. Instrument rail,
  operational summaries, and grouped network information are optional modules
  in that declaration order. Full connection fields remain on the Connections
  inspector; Overview never restores a raw connection selector or retained-
  closed aggregation.
- `MicaApp` owns one `OverviewPreferencesStore` shared across every controller
  and window. The persisted value contains only visible primary metrics, one
  timeline window, and optional-module visibility. At least one primary metric
  remains visible. Changes apply and persist immediately; Reset restores all
  metrics, five minutes, and no optional modules.
- Overview has no per-controller overrides, drafts, Done/Cancel transaction,
  UndoManager history, conflict resolution, migration, module order, module
  size, row packing, or preset compatibility. The existing v1 persistence key
  now carries the `mica.overview.fixed-core.v1` schema. A missing, corrupt,
  wrong-schema, or superseded layout payload returns the new default without
  migration.
- Each window owns one `OverviewWindowRuntime`: a stable live-session demand ID,
  a window-local preferences disclosure, and session-keyed telemetry/topology
  runtimes. Controller ID or generation changes discard obsolete runtimes so
  hover, pin, pause, and cached presentation cannot leak into another session.
- The topology admits every active connection and every reported chain hop.
  Missing source or chain metadata creates an explicit unavailable path record,
  not a fabricated edge. Each layer owns a distinct node identity, the first
  column sorts by reported name, and every later column sorts by the
  flow-weighted barycenter of its upstream neighbors with name-order tiebreaks
  (task 08-23) so parallel flows become near-parallel edges instead of maximal
  crossings. Aggregated edges retain their real count
  while layout band width uses `log10(count + 1) * 10`. The Sankey fits the
  panel width until the column count would compress columns below a 168-point
  minimum step; longer chains widen the graph past the panel and the viewport
  scrolls horizontally instead of truncating labels (task 08-23 R10). The
  native horizontal indicator is visible only while that overflow exists.
  Pinned node, edge, and path selections resolve an x target from the existing
  topology index/layout and move the native scroll position only when the
  target lies outside the visible acquisition margin. Hover never moves the
  viewport, user scrolling is not continuously overridden, and Reduce Motion
  makes the same reveal immediate instead of disabling it. The
  graph uses 20-point node bars, 8-point gaps, true flow-width ribbons, and
  full-trajectory
  hover/pin highlighting. Edge strokes are tiered (tasks 08-20, 08-23): the
  single active, hovered, or pinned trajectory redraws as a solid accent
  ribbon at 85% opacity; while a selection exists every other edge fades to
  an explicit
  alpha-baked neutral mist (`MicaTheme.edgeDimmed`); an edge touching a policy
  hop with a controller-reported status carries that status color; every
  remaining edge renders as a true sankey ribbon (task 08-23 R9): a closed
  band tracing its flow-proportional geometry width (flow * valueScale, the
  same width the layout packs into node rects) filled with a
  source-to-target column-tint gradient at 45% opacity, so route families
  stay traceable by hue and converging flows brighten naturally through
  translucency. Column identity tints (`MicaTheme.ColumnTint`: muted slate
  blue sources, warm sand rules, violet chain hops, dusty rose exits, both
  appearances) encode column identity only - status colors and the accent
  always win. Node bars fill with the controller-reported status color when
  one exists, a solid column-tint anchor bar (dimmed to 35%) otherwise, and
  the accent when the path is active. A 22x2.5-point column-tinted tick sits under
  each column title, and title slices are capped by band edges and neighbor
  distances so titles never overlap or clip. Each band renders through
  exactly one opaque, linear-composited Canvas (base and highlight passes
  merged) plus a dedicated system-text label layer; band equality gates on the
  structure/policy revisions so telemetry ticks never redraw the graph. Hover and explicit pause freeze only the presented
  snapshot; ingestion continues and resume catches up to the latest real frame.
  Inline expansion, complete accessible path rows, and navigation to Connections
  stay in the same window. The graph grows vertically with its densest
  column (no nested vertical scroll axis); horizontal scrolling appears only
  when long chains exceed the panel width (task 08-23 R10). Visible node bars win hit testing first,
  ribbons win over overlapping invisible node padding, and bounded label-adjacent
  node targets use a local 28-point acquisition size while ribbons use a
  10-point baseline tolerance. The layout builds `nodeGeometryByID` once so hit
  testing and policy inspection stay constant-time and never change node/ribbon
  or scroll geometry.
  Policy-node hover presents a standard tooltip with the truthful route label;
  clicking a policy node pins the canvas selection and opens the workspace
  inspector with the complete field composition, and Escape or blank-canvas
  activation clears selection. Policy inspection resolves names through
  `OverviewPolicyInspectionIndex` using only the already-published policy
  catalog and exact case-sensitive names. A duplicate
  or missing match falls back to truthful route detail; inspection never starts
  network work or rebuilds topology structure/layout. The inspector composition
  includes current choice/member group, ordered members, availability, latency,
  type, provider, interface, hidden/fixed/icon values, every reported transport
  state including `false`, SMART rank, latest test detail and URL, plus every
  additional controller field in stable key order; selection is not a gate
  hiding fields, and additional metadata has no arbitrary item cap.
  Eligible Proxies and Connections
  navigation remains same-window. The graph is one native focusable surface:
  direction keys step through complete paths, Escape clears local selection,
  and one native context menu mirrors path stepping, pin/unpin, clear, and
  eligible navigation. VoiceOver exposes policy nodes and paths with pinned
  state, factual inspection values, and direct navigation. Ordered path IDs and their
  index map keep path stepping constant-time. Node labels and column titles
  render in the label layer through the system text pipeline at the active
  Mica font scale, positioned exactly on the geometry engine's label
  rectangles, truncating to the fitted slice; column title centers clamp so
  even the trailing column title stays fully inside the band. Never rewrite
  reported names with fixed character-count
  truncation or extend a label target to the next column. Sparse topology keeps
  a width-responsive 680-to-920-point minimum flow area; dense columns may grow
  beyond it.
- Actions availability is the intersection of current controller identity and
  generation, session readiness, controller capability, operation readiness,
  and an adapter-appropriate dispatcher. Static support, observed runtime state,
  disabled commands, and unresolved probes do not enter the executable count.
  Auto Detect exposes only recovery while unresolved; sing-box memory remains an
  observation and never becomes a Mihomo memory command. mihomo, Nikki,
  OpenClash, CMFA, Stash, sing-box, Surge, unknown, and unsupported profiles each
  receive only their verified subset. Reusing a Mihomo HTTP client is not proof
  that every Mihomo maintenance command is valid: Stash keeps its verified read
  and reload subset but must not inherit Mihomo DNS flush. Destructive lifecycle commands remain in
  one full-width final group and capture controller ID plus generation for inline
  confirmation.
- Actions recovery shows controller, visible target, factual target scope,
  current reason, at most one primary Test command, Edit Controller, and Open
  Diagnostics. It never shows a disabled Refresh or a capability count. Ready
  and partial states use one outer scroll owner; wide content uses two flat
  columns and compact content uses the same ordered groups in one column. A
  controller with few standalone commands links to its real owning workspaces
  instead of fabricating operations. Projection computes command groups from
  raw availability and then derives one effective availability; recovery copy,
  target correction, executable count, related destinations, and canvas choice
  all consume that effective state. Related workspaces appear only for
  unsupported or at-most-two-command compositions, never as filler beneath a
  complete command workspace.
- Diagnostics leads with an unframed verdict containing controller, target,
  current availability, freshness, stable last-check time, and retained/paused
  meaning. Controller-wide root causes suppress duplicate endpoint failures;
  capability false means inherently unsupported and never becomes an issue.
  Historical command outcomes and diagnostics-copy state do not drive current
  health. Stable issues contain severity, impact, safe evidence, and at most one
  typed action: Recheck, Resume Presentation, Edit Controller, or same-window
  navigation. Diagnostics never performs remote reload, update, flush, close,
  restart, or upgrade commands.
- Diagnostics has one full-width outer scroll owner. At 900 points of content
  width or more, bounded issue rows and selected detail share one master-detail
  row; below it the same selected issue expands inline. A resolved issue keeps
  selection by stable ID or moves deterministically to the first remaining
  issue. Healthy state omits the issue workspace and shows only the concise
  verdict plus real Available Now product domains. One native technical
  disclosure groups Controller, Session, and safe Evidence; API paths, machine
  assignments, credentials, authorization, subscription URLs, Keychain values,
  and raw response/stream bodies stay out of visible UI. Copy Report is the only
  complete report command. Checking is a projection gate: before the first
  committed baseline it produces no adapter/endpoint/domain issue and no
  Available Now claim. A controller-wide access issue suppresses its derived
  endpoint/domain failures even when retained data exists. Every free-form
  evidence value rejected by `displayableText` becomes the localized
  `diagnostics.evidence_unavailable` string, never the rejected raw value.
- `localhost`, IPv4 loopback, and IPv6 loopback are presented factually as This
  Mac in Actions, Diagnostics evidence, and RouterEditor diagnosis. A failed
  remote/router target explains that a device LAN IP or hostname, matching API
  port, and matching credential are required. Explicit Surge mac-local profiles
  permit loopback. Target presentation never discovers devices or modifies a
  profile, router, service, firewall, OpenWrt, or controller.
- Provider diagnostics choose the newest real command across individual Update
  and Update All records rather than assuming only one action exists.

## Scenario: Exact Proxy Reveal And Health Triage

### 1. Scope / Trigger

Apply this scenario when changing policy-group health projection, Overview or
inspector Open Proxies actions, workspace navigation state, proxy catalog
deferral, group disclosure, programmatic node reveal, or proxy content states.

### 2. Signatures

```swift
struct WorkbenchProxyNavigationSelection: Equatable, Sendable {
    let controllerID: RouterProfile.ID
    let generation: UUID
    let groupOccurrenceID: String
    let nodeName: String
}

func stageProxyNavigation(_ selection: WorkbenchProxyNavigationSelection)
func consumeProxyNavigation(
    controllerID: RouterProfile.ID,
    generation: UUID
) -> WorkbenchProxyNavigationSelection?

enum ProxyNavigationTargetResolutionStatus: String, Equatable, Sendable {
    case resolved, emptyCatalog, hiddenGlobal
    case missingGroup, ambiguousGroup, missingNode
}
```

### 3. Contracts

- Every Overview topology, VoiceOver, and policy-inspector Open Proxies action
  stages controller ID, generation, stable group occurrence ID, and node name
  before changing destination. A raw duplicate group name is never first-match
  navigation.
- The Proxies page observes pending workspace navigation even when it is already
  visible. A newly staged selection cancels any in-flight reveal task before it
  replaces an unresolved target. Accepted immediate or deferred catalogs first
  consume the newest selection and then resolve it.
- Empty catalog, hidden GLOBAL, missing group, duplicate raw group, and missing
  node remain distinct outcomes. An unresolved current-generation target stays
  available for a later catalog commit; controller or generation replacement
  clears it.
- Global search, the exact group's local query, and health filter form one
  obstruction set. Clear Filters and Locate clears all three local filters in
  one transaction. GLOBAL visibility is separate and changes only after the
  explicit Show GLOBAL and Locate action.
- Root content distinguishes no controller, loading, unsupported, unloaded,
  hidden-by-preference, global-search no match, first failure, and retained
  stale data. A non-empty search must not override hidden-by-preference when the
  arranged catalog itself is empty.
- Locate Current reads only controller-reported selected members. Inspector-only
  selection is never treated as controller current.
- Proxy health uses controller `alive`, positive reported/history delay, and
  `LatencyHealthGrade`. Attention includes every nonhealthy row; Unavailable is
  unavailable only; Slow is `.slow` only and excludes timeout. A missing delay
  preserves optionality and falls back to reported `alive`; an explicitly
  non-positive delay is unavailable in summaries, filters, color, and compact
  display while the full inspector may preserve the raw controller value.
- One outer `ScrollViewReader` owns proxy reveal. The request validates token,
  controller, and generation; jumps without animation to the lazy group ID,
  waits one frame for member materialization, validates again, scrolls to the
  exact member ID, and records the token only after that node scroll. Nested
  scroll owners, `scrollPosition`, and member-grid `scrollTargetLayout` are
  forbidden.
- A reveal briefly highlights the exact node and synchronizes the workspace
  inspector. Catalog refresh alone never creates a new reveal token or steals
  scroll position. Reduce Motion keeps a static equivalent.
- Icon-only node test commands retain localized help, accessibility label, and
  accessibility hint containing the controller-reported node name.

### 4. Validation & Error Matrix

| Input or change | Required result |
| --- | --- |
| Staged controller/generation is stale | Reject and clear at the session boundary; no remote action |
| Exact occurrence and member exist | Expand group, materialize group, scroll once to member, highlight, inspect |
| Raw group name matches multiple occurrences | Truthful ambiguous state; never first match |
| Catalog is currently empty | Consume and explain the target; retry resolution on a later accepted catalog |
| GLOBAL target is hidden by preference | Dedicated obstruction; only explicit Show GLOBAL and Locate changes preference |
| Search, group query, and health filter all hide target | One Clear Filters and Locate action clears all three and resumes reveal |
| New target arrives while an old reveal is running | Cancel old task/token and resolve only the new selection |
| Deferred catalog commits after scrolling | Consume the newest staged target and re-resolve pending navigation |
| Search has no visible match but arranged groups exist | Show no-match state |
| Only hidden groups remain before search projection | Show hidden-by-preference state |
| Delay is zero or negative | Compact value unavailable; health unavailable; raw inspector value retained |
| Grade is timeout | Included in Attention and Unavailable, excluded from Slow |

### 5. Good/Base/Bad Cases

- Good: a duplicate-named group's occurrence is staged from the inspector,
  filters are cleared once, the distant lazy group materializes, and the exact
  member is centered and highlighted.
- Base: the controller reports an empty policy catalog; the page explains the
  empty target and resolves it automatically if the same generation later
  publishes the group.
- Bad: destination changes without staging, raw group name chooses the first
  match, hidden GLOBAL silently changes a preference, a deferred catalog leaves
  a target permanently unresolved, or a nested scroll target cannot materialize
  the node.

### 6. Tests Required

- `WorkbenchProxyWorkspaceTests`: health classification and filter subsets,
  non-positive compact delay plus raw inspector value, stable group/member
  occurrence resolution, hidden GLOBAL, empty catalog, obstruction sets,
  workspace consume/generation rejection, and reveal identity rejection.
- Source contract: every Overview entry stages before navigation; the page
  observes pending workspace selection, accepts a new selection by cancelling
  the old reveal, accepted catalogs consume then resolve, and Current excludes
  inspector state.
- Source contract: exactly one outer scroll reader, lazy group then exact member
  targeting, token recorded after member scroll, no `scrollPosition`, no nested
  `scrollTargetLayout`, and localized node-test label/hint/help.
- Localization resolver: every new state, reason, action, accessibility label,
  and hint has English and Simplified-Chinese values with matching placeholders.
- Runtime UI/VoiceOver smoke remains user-authorized only; automated coverage
  must not load a profile or contact a controller.

### 7. Wrong vs Correct

```swift
// Wrong: navigation loses occurrence identity and relies on a later first match.
destination = .proxies

// Correct: stage the exact session-bound target before changing destination.
workspaceStore.stageProxyNavigation(selection)
destination = .proxies
```

```swift
// Wrong: a nested lazy member is targeted before its group exists in the view.
proxy.scrollTo(reveal.targetID)

// Correct: materialize the group in the same scroll owner, revalidate, then
// target the exact member and record completion.
proxy.scrollTo(WorkbenchProxyScrollTarget.group(reveal.groupID))
try await Task.sleep(for: .milliseconds(16))
guard reveal.isCurrent(controllerID: controllerID, generation: generation) else { return }
proxy.scrollTo(reveal.targetID, anchor: .center)
lastScrolledRevealToken = reveal.token
```

## Scenario: Exact Connection Reveal

### 1. Scope / Trigger

Apply this scenario when Overview summaries, topology paths, policy inspection,
or another Workbench surface navigates to one controller-reported active
connection. Raw connection IDs may be duplicate or blank and are not navigation
identity by themselves.

### 2. Signatures

```swift
struct WorkbenchConnectionNavigationSelection: Equatable, Sendable {
    let controllerID: RouterProfile.ID
    let generation: UUID
    let sourceIndex: Int
    let reportedConnectionID: String

    func matches(sourceIndex: Int, reportedConnectionID: String) -> Bool
}

func stageConnectionNavigation(_ selection: WorkbenchConnectionNavigationSelection)
func consumeConnectionNavigation(
    controllerID: RouterProfile.ID,
    generation: UUID
) -> WorkbenchConnectionNavigationSelection?
```

### 3. Contracts

- Every Overview summary, topology path, and policy-inspector Connections action
  stages controller ID, generation, source occurrence index, and the exact raw
  ID before changing destination. Blank IDs remain valid values.
- `sourceIndex` is the occurrence in the controller-reported active connection
  array used to build both the Overview row/path and the Connections row. The
  raw ID is checked with it so reordered or replaced data cannot select another
  occurrence accidentally.
- Staging clears the old persisted row ID and retains one pending target. The
  Connections page consumes it only in Active scope, for the selected controller
  and current generation, after an exact row match exists; it then selects and
  scrolls to that row's stable presentation ID.
- A missing, changed, stale, or not-yet-published target is not first-matched and
  is not consumed as success. Controller or generation invalidation clears the
  session-bound target through the workspace store.

### 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| Same generation, exact index and raw ID | Consume once; select and reveal the exact active row |
| Duplicate raw ID at another index | Keep occurrences distinct; never select the first raw-ID match |
| Blank raw ID at the exact index | Consume and reveal normally |
| Index matches but raw ID changed | Do not consume or select a replacement row |
| Wrong controller or generation | Reject without selecting a row |
| Connections is showing Closed scope | Keep Active navigation out of the closed-history table |

### 5. Good/Base/Bad Cases

- Good: the user clicks the second of two equal raw IDs and Connections reveals
  that second controller-reported occurrence.
- Base: an active connection has a blank raw ID; its occurrence still stages,
  resolves, and scrolls normally.
- Bad: only the raw ID is staged, an empty ID skips staging but still changes
  destination, or `.first` silently selects another equal ID.

### 6. Tests Required

- `WorkbenchNavigationTests`: stale-generation rejection, duplicate raw IDs,
  blank IDs, exact pair matching, one-shot consumption, and session clearing.
- `WorkbenchOverviewPerformanceTests` / topology tests: every path retains its
  controller-order `sourceIndex` and exact `reportedConnectionID`.
- `verify-real-controller-source.mjs`: Overview summary, topology, and policy
  inspector stage occurrence identity; Connections checks both fields before
  consumption and selection.
- Automated coverage remains fixture-only and never contacts a controller.

### 7. Wrong vs Correct

```swift
// Wrong: duplicate and blank IDs cannot identify a reported occurrence.
WorkbenchConnectionNavigationSelection(connectionID: connection.id)

// Correct: stage the exact session-bound occurrence before navigation.
WorkbenchConnectionNavigationSelection(
    controllerID: controllerID,
    generation: generation,
    sourceIndex: connection.sourceIndex,
    reportedConnectionID: connection.connectionID
)
```

## Scenario: Audited Diagnostics And Actions Projection

### 1. Scope / Trigger

Apply this scenario when changing Diagnostics issue projection, Actions command
inventory, controller runtime-row observation, or their SwiftUI composition. It
prevents provisional health claims, unsafe evidence fallback, contradictory
Actions states, and high-frequency session data from entering management views.

### 2. Signatures

- `WorkbenchDiagnosticsProjection.snapshot(_ input: WorkbenchDiagnosticsInput) -> WorkbenchDiagnosticsSnapshot`
- `WorkbenchActionsProjection.snapshot(_ input: WorkbenchActionsInput) -> WorkbenchActionsSnapshot`
- `WorkbenchActionsLayoutDecision.resolve(commandCount:availableWidth:) -> WorkbenchActionsLayoutDecision`
- `WorkbenchDiagnosticsActionAvailability.isEnabled(_:) -> Bool`
- `AppModel.actionsRuntimeOperationRows: [DiagnosticsRuntimeOperationRow]`
- `UnifiedControllerType.hasWorkbenchRuntimeOperations: Bool`

### 3. Contracts

- Neither typed input contains connection rows, log entries, traffic timelines,
  catalog snapshots, credentials, or raw response/stream bodies.
- Diagnostics derives one `isChecking` gate before issues. Until
  `lastSuccessAt != nil`, Available Now is empty. Rejected free-form evidence is
  replaced with localized safe fallback copy.
- A controller-access issue is the causal root and suppresses endpoint/domain
  derivatives; `lastSuccessAt` changes freshness only.
- Actions derives `rawAvailability`, groups, then `effectiveAvailability`.
  Recovery, target correction, count, related destinations, and rendering use
  only the effective value.
- Actions counts every real projected command, including a currently disabled
  command. Zero through two commands use a 780-point maximum, one-column canvas;
  three or more use the 1,080-point canvas and become two columns only at 900
  points of measured content width or more. The layout decision never adds,
  removes, or reorders a command.
- Runtime command rows are evidence-free and dispatcher-family-gated before
  entering Actions. Diagnostics enriches its separate rows with evidence.
- Toolbar Test/Refresh/Pause, Configuration state actions, and Diagnostics issue
  actions consume the shared `AppModel` availability properties. Their handlers
  recheck the same gate before dispatch so a stale enabled frame cannot launch
  an unavailable UI intent. This UI contract does not replace command-boundary
  validation inside `AppModel`.
- Actions and Controllers destructive confirmation rows handle Escape only on
  the visible inline confirmation subtree. A page- or inspector-root exit
  handler must not consume unrelated native Escape behavior.
- Issue buttons expose localized severity plus title as their accessibility
  label, affected count as value, and native selected trait as selection state.

### 4. Validation & Error Matrix

| Input condition | Required projection |
| --- | --- |
| Connecting or first-baseline health checking | `.checking`, no issues, no Available Now |
| Controller access failed, no baseline | Controller-access only, blocked, unavailable freshness |
| Controller access failed after success | Controller-access only, needs attention, retained freshness |
| Free-form evidence contains assignment/API path | Localized evidence-unavailable value |
| Ready/partial but no verified command group | Effective `.unsupported` plus unsupported recovery |
| Zero, one, or two projected commands | 780-point maximum; one column |
| Three or more commands below 900 points | 1,080-point maximum; one column |
| Three or more commands at least 900 points | 1,080-point maximum; adaptive two columns |
| More than two verified commands | No related-workspace filler |
| Controller family has no runtime dispatcher | Empty `actionsRuntimeOperationRows` |
| Shared Refresh/Test/Pause gate is false | Affordance disabled; stale handler call is a no-op |
| Inline destructive confirmation is visible and Escape arrives | Clear only that pending confirmation |

### 5. Good/Base/Bad Cases

- Good: retained controller failure keeps retained freshness and one causal issue.
- Base: a live sing-box controller shows its real Refresh command plus compact
  owning-workspace navigation, without Mihomo runtime commands.
- Bad: checking displays an adapter failure, an API path reappears as evidence,
  an unsupported snapshot carries ready/partial recovery copy, a sparse Actions
  canvas stretches to 1,080 points, or a page-root Escape handler consumes focus
  changes while no confirmation is visible.

### 6. Tests Required

- `WorkbenchManagementProjectionTests`: checking gate, first-baseline areas,
  retained causal dedup, safe evidence, effective Actions state, compact related
  destinations, 0/1/2/dense layout decisions, Diagnostics action availability,
  and dispatcher-family runtime observation.
- `RuntimeMemoryTests`: full Diagnostics rows still expose current authoritative
  runtime evidence after Actions rows become evidence-free.
- `verify-real-controller-source.mjs`: typed inputs exclude stream payloads;
  Actions uses the evidence-free property; issue rows expose severity semantics;
  shared UI gates are consumed and rechecked; Escape stays on visible
  confirmation subtrees.

### 7. Wrong vs Correct

```swift
// Wrong: final availability and recovery are derived from different states.
let availability = availability(for: input)
let recovery = recovery(for: input, availability: availability)
let final = groups.isEmpty ? .unsupported : availability

// Correct: derive one effective state, then use it everywhere downstream.
let rawAvailability = availability(for: input)
let groups = commandGroups(for: input, availability: rawAvailability)
let effectiveAvailability = groups.isEmpty && rawAvailability.isCommandState
    ? .unsupported
    : rawAvailability
let recovery = recovery(for: input, availability: effectiveAvailability)
```

```swift
// Wrong: a copied UI condition can drift from the command availability source.
let isEnabled = hasSelectedSession && !appModel.isBusy

// Correct: rendering and stale-intent rejection share the same authority.
let isEnabled = appModel.canRefreshSelectedRouter
guard appModel.canRefreshSelectedRouter else { return }
appModel.refreshSelectedRouter()
```

## Scenario: High-Cardinality Data Projection

### 1. Scope / Trigger

Apply this scenario when changing Connections, Logs, Rules, or Sources row
projection/search, or the corresponding offline benchmark cases. These paths
may process thousands of complete controller-reported rows; fixed-size
Diagnostics, Actions, Controllers, and Configuration projections do not use
this scenario without separate evidence.

### 2. Signatures

- `WorkbenchDataSearch.contains(_ query: String, in searchText: String) -> Bool`
- `WorkbenchConnectionProjection.rows(activeConnections:closedConnections:scope:language:) -> [WorkbenchConnectionRow]`
- `WorkbenchConnectionProjection.updatingMetrics(in:from:formatter:forceFormatting:) -> WorkbenchConnectionRow`
- Release cases: `connection-initial-cache-projection`,
  `connection-search-projection`, `log-search-projection`,
  `rule-connection-index-and-counts`, `rule-row-projection`,
  `rule-search-projection`, `source-row-projection`,
  `source-search-projection`, `proxy-catalog-index-projection`, and
  `proxy-expanded-groups-projection`.

### 3. Contracts

- Each caller converts a blank query to nil before filtering. A nil query keeps
  the page's existing unfiltered fast path and ordering semantics.
- Data-browser search calls the shared Foundation `NSString` case-insensitive
  range matcher against the row's cached raw search blob. Do not retain a
  second folded/lowercased full blob or use localized matching independently in
  each high-cardinality projection.
- Search remains case-insensitive and Unicode-aware for the same characters,
  but does not remove diacritics. `mÜnchen` matches `München`; `munchen` does
  not. Search does not mutate controller order, stable identity, selection, or
  inspector values.
- Connection structural projection resolves the localized unavailable value
  once per language/projection. Direct summary interpolation is allowed only
  after every component has been normalized with `dataNonEmpty` and assigned a
  non-empty fallback. Metrics-only updates preserve structural search text and
  identity.
- Comparable performance reports keep case name, fixture count, checksum, and
  reported work units equal. Retain an optimization only after two Release runs
  improve the target median by at least 10% without an unrelated case
  consistently regressing by more than 10%.

### 4. Validation & Error Matrix

| Input or change | Required result |
| --- | --- |
| Blank or whitespace query | Existing unfiltered rows/order; no matcher work |
| Same text with different case | Match |
| Same accented text with different case | Match |
| Query removes an accent | No implicit diacritic-insensitive match |
| Missing connection metric/timestamp | One localized unavailable fallback |
| Metrics-only connection frame | Stable ID/search text; only changed metrics update |
| Report checksum or work units differ | Reject comparison and optimization claim |

### 5. Good/Base/Bad Cases

- Good: a 10,000-row prepared search uses `WorkbenchDataSearch`, returns the
  same rows, and crosses the repeated retention threshold.
- Base: a refresh-driven provider catalog projects complete reported fields;
  its synthetic stress cost alone does not justify another cache state model.
- Bad: every row folds and stores a second full search blob, a SwiftUI body
  formats search text, or a faster report silently evaluates fewer rows.

### 6. Tests Required

- `WorkbenchDataProjectionTests`: shared ASCII/Unicode case behavior, retained
  diacritics, row output, identity, sorting, and metrics-only updates.
- `MicaPerformanceBenchmarkTests`: prepared search setup, stress fixture sizes,
  checksum, and reported work units.
- Run two comparable Release reports when product hot-path code changes; unit
  tests alone do not establish a performance improvement.

### 7. Wrong vs Correct

```swift
// Wrong: every high-cardinality page chooses and pays for its own matcher.
row.searchText.localizedCaseInsensitiveContains(query)

// Correct: query normalization stays at the page boundary; matching is shared.
WorkbenchDataSearch.contains(query, in: row.searchText)
```

## Performance Boundaries

- Workbench views do not observe `AppModel.controllerSession` directly. They
  read the field-granular `controllerSessionPresentation` state so timeline and
  stream-buffer mutations cannot invalidate views that only need state,
  generation, controls, identity, or runtime.
- Actions consumes evidence-free `AppModel.actionsRuntimeOperationRows` only
  for Mihomo, Nikki, OpenClash, and CMFA, the controller families with verified
  runtime dispatchers. Surge, sing-box, Stash, probing, unknown, and unsupported
  states do not construct diagnostic runtime rows. Full diagnostic evidence may
  read authoritative session runtime, but that evidence is enriched only after
  the shared command rows are built and is never passed into Actions.
- Overview telemetry, topology, policy inspection, operational
  summaries, and grouped network facts are separate invalidation subtrees. A
  traffic sample rebuilds telemetry only; a policy catalog change may rebuild
  its inspection index but cannot rebuild topology structure or layout.
- The Overview vertical scroll uses lazy construction. Optional modules are
  filtered before subtree construction and hidden modules perform no work.
  Telemetry and topology are always constructed in fixed order; there is no row
  packer, size negotiation, reorder runtime, or alternate layout tree.
- Overview finite motion is triggered only by a newly received real sample,
  topology structure/traffic/metrics revision, or explicit selection. Reduce Motion,
  inactive windows, local pause, and global dashboard pause resolve to a static
  equivalent. Do not introduce `TimelineView`, repeating timers, particles,
  scan lines, or perpetual phase animation.
- Live chart collections use stable identities and bounded real samples. Do not
  format, sort, group, or rebuild search text inside a mark or row body.
- Traffic, memory, and active-connection timelines append only controller-received
  samples. They never pad a window with zeroes or derive history from a current
  snapshot. Upload, download, and active-connection charts anchor the latest
  sample to the right edge, use area plus linear line rendering, share hover/
  click/keyboard selection, and pause only presentation while retained session
  data continues to advance. The nearest real memory sample annotates the
  connection chart instead of creating a fourth plot.
- Current Overview values read the latest raw AppModel-published timeline sample
  directly; downsampling caches prepare plot history only and never become the
  authority for the current rate/count/timestamp. Instrument rate labels never
  format `ConnectionsCatalogSnapshot.traffic` cumulative totals as `/s`.
- Timeline projection cache signatures include receipt-time boundaries in
  addition to count and IDs. A reconnect/replacement that reuses sample IDs but
  carries new receipt times must invalidate the cached plot.
- Every window root owns one stable `LiveSessionWindowDemandID` and updates only
  its own `LiveSessionVisibleDestination`. Effective live domains are the union
  across windows; child pages never create their own demand or refresh loop.
- Each dirty-close delegate is attached through that window's own AppKit host
  view. It never discovers a process-global main or key window.
- Visible publication budgets are logs 5 Hz, traffic 4 Hz, connections 2 Hz,
  and memory 1 Hz. Hidden domains keep raw state and flush once immediately on
  entry; scheduled publication uses one non-restarting token per domain.
- Connections, Rules, Sources, Logs, and Proxies keep page-owned projection
  caches. Structure/query/sort/language inputs and high-frequency metrics have
  separate invalidation paths; an inactive destination performs no expensive
  row, chart, topology, or search-index projection.
- Connections, Rules, Sources, and Logs each construct one native `Table`.
  Resolve one discrete width mode at the page root and conditionally provide
  columns within that Table; do not retain eager full/compact/stacked Table
  trees. Scan rows keep stable single-line geometry while complete wrapped,
  selectable values remain available in the same-window inspector.
- Rules wide mode separates reported index, type, payload, target, activity,
  and state into explicit scan columns. The state cell's trailing edge owns the
  optional mutation command. Compact mode combines route, metrics, state, and
  mutation; stacked mode has one complete composite column. Never restore boxed
  type/status badges or an isolated action-button column.
- Connection search text and complete inspector values are precomputed on
  structural revision. Metrics-only frames carry changed row positions and
  update only those metric rows; a missed revision falls back to the complete
  authoritative snapshot. Logs with unique controller IDs consume append/drop
  deltas instead of rescanning or reformatting the full ring, with the same
  missed-revision fallback.
- Connections resolves localized unavailable copy once per structural
  projection and directly composes only summaries whose components already have
  non-empty fallbacks. Connections, Logs, Rules, and Sources use
  `WorkbenchDataSearch` for high-cardinality cached search blobs. Pre-folding a
  second complete blob and Swift `String.range` are measured regressions; do not
  reintroduce either without new two-run evidence.
- Offline performance reports compare matching case name and fixture count,
  preserve checksum and reported work units, and require two comparable Release
  runs. A shared hot-path optimization is retained only when both runs improve
  the target median by at least 10% and unrelated cases do not consistently
  regress by more than 10%. The attempted lazy/fast-path
  `WorkbenchStableRowIdentityBuilder` slice improved the 10,000-row connection
  median by only 6.38% and 4.71%, so it is intentionally reverted. Do not
  reintroduce that complexity without new evidence. Keep the prepared-state
  `log-steady-state-delta-projection` case so initialization cost cannot hide
  steady delta behavior; retain the older end-to-end log case for comparison.
- Connections places one compact pulse strip above its native Table. It
  aggregates only the current activity/closed scope and current search result:
  visible/total count, reported upload/download/total bytes, the first three
  stable owner buckets, and a remainder bucket. Active scope may show reported
  rates; closed scope shows historical totals only. Structure or filter changes
  rebuild the pulse, keyed metric changes adjust only visible changed rows, and
  sorting never rebuilds owner buckets.
- A selected connection exposes the complete reported path in order: source or
  process, inbound, rule, provider/policy hops, and destination. Extra metadata
  remains in stable key order and renders as selectable scalar rows or
  recursively disclosed objects/arrays, never as one machine JSON paragraph.
- Overview keeps bounded Top-K summaries and cached/downsampled received
  timelines. Topology stores indexed nodes, node geometry, edges, path
  memberships, and segment-cell hit regions; hover/selection/inspection projection
  cannot rebuild graph structure or scan node geometry. Policy inspection builds
  a bounded index once per AppModel-published catalog revision; unchanged
  inspection selections check the scalar revision instead of comparing the complete
  catalog and performs no network access.
  Overview remains the sole vertical scroll owner. Topology expands cached
  render bands vertically without a nested vertical scroller; only a long chain
  whose 168-point minimum column step exceeds the panel width owns a bounded
  horizontal viewport. Short chains fit the available width and hide its native
  horizontal indicator.
- Expensive presentation work may be deferred during scrolling, chart dragging,
  or filter typing, but one latest result must survive the interaction window.
  For Proxies, a deferrable catalog update remains pending while any proxy
  scroll region is active, even after the ordinary deferral deadline, and the
  latest result is published when scrolling becomes idle.
  Errors, destructive confirmations, and mutation outcomes bypass deferral.
- Byte formatting renders zero as `0 B` and `0 B/s`; never expose locale output
  such as `Zero KB` inside another interface language.

## Content States

Every destination distinguishes:

- no controller
- loading
- unsupported
- empty/unloaded
- no filter matches
- failed before first value
- stale data retained after a later failure

Top command areas stay stable. Full-page unavailable states center in the
remaining region, use distinct title/description copy, and share the same
capability/pause/busy gates as their command-bar actions.

## Preferences

- `AppPreferencesStore` is the only language, appearance, font-scale, and
  GLOBAL-visibility preference authority.
- Static localization keys contain no format arguments. Parameterized keys,
  English values, and Simplified Chinese values declare the same positional
  argument types; split a field label from its parameterized sentence instead
  of reusing one catalog entry for both.
- Language repaints cached presentation strings and menus immediately.
- Views that resolve dynamic localization keys read
  `@Environment(\.micaAppLanguage)` and pass that value to `MicaStrings`.
  Relying on the process-global default does not create a SwiftUI invalidation
  dependency and can leave a sidebar or menu in the previous language.
- Follow System, Light, and Dark repaint every window immediately.
- Standard, Comfortable, Large, and Extra Large map to `small`, `large`,
  `xxLarge`, and `xxxLarge` Dynamic Type fallbacks plus visible Mica text
  multipliers `0.92`, `1.0`, `1.16`, and `1.32`. Font preference changes never
  select compact/stacked management layout; only measured width may do that.
- The native Settings scene is the only application-preference surface and uses
  the persisted `AppPreferencesStore` bindings directly.
- General management fields use `WorkbenchFormRow`: regular width has one stable
  label column followed by a leading-aligned value column; compact width stacks
  both columns on the leading edge. Preference rows use a dedicated flexible
  explanation column and align their compact native menu to the trailing edge at
  regular width so available line length is not wasted. Do not restore default
  `LabeledContent` value-column placement.
- Management pages use one bounded column anchored to the leading edge. Never
  center a `Form` between spacer columns or let settings stretch across the
  remaining workspace.
- Configuration and native Settings use grouped `Form`. Actions and Diagnostics
  use dedicated flat operational workspaces with hairline separators, one scroll
  owner each, and width-driven composition. They are not Liquid Glass,
  decorative cards, dashboards, or nested panel walls.
- Preference rows keep their existing help strings visible beneath the field
  label. At regular width the explanation consumes the available line and the
  control remains trailing-aligned; at compact width they stack without changing
  because of the font preference. General management rows retain their stable
  176-point label column, with values starting directly after
  it and trailing space remains unoccupied.
- Preference option sets use the shared borderless menu treatment: one current
  value, one semantic SF Symbol, and one restrained disclosure chevron. Do not
  restore segmented button strips for appearance or font scale.
- Custom top-level macOS menu titles follow the system menu language. Commands
  within those menus continue to follow Mica's selected interface language.

## Accessibility

- Interactive geometry follows macOS pointer context: row buttons occupy their
  complete row width, standalone icon controls use compact 28-point frames, and
  topology targets add bounded local acquisition padding. Do not impose a
  universal mobile touch-target height.
- Icon-only commands have localized labels and help.
- Color supplements text/symbol meaning; it never carries status alone.
- Keyboard focus, native table selection, text selection, VoiceOver order, and
  long English/Chinese business values remain usable at wide and narrow widths.

## Validation

- Automated checks do not load controller profiles, connect to a controller,
  launch a core, access port 9090, or modify system networking.
- Replace old UI tests and source assertions instead of keeping compatibility
  types alive.
- Required checks: Swift build/test, source contract, localization JSON, HIG
  contrast/hit targets, and diff checks.
- Runtime visual acceptance is user-run when requested; smoke testing is skipped
  when the user asks not to run it.

## Third-Party Packages

- System SwiftUI, Swift Charts, and `Canvas` remain the current Workbench implementation because they satisfy the present chart and interaction contracts.
- A mature Swift package may be introduced when it materially improves correctness, performance, accessibility, protocol integration, or maintenance and the system framework or a small local implementation is materially worse.
- Before adding it, verify macOS 27/Swift 6.2 support, maintenance, license/redistribution, transitive and binary cost, concurrency/cancellation integration, and record the rationale plus boundary tests in the active task.
- Do not add packages for decorative convenience or to avoid a small native implementation.
