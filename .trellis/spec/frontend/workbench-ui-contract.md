# Workbench UI Contract

## Scope

Apply this contract to the owned files in `Sources/Mica/Features/Workbench/`.
The controller/data layer is stable; no previous Workbench View, presenter,
projector, interaction store, layout helper, file split, or UI-test type is a
compatibility requirement.

## File Architecture

The directory contains exactly:

- `WorkbenchChrome.swift`
- `WorkbenchControllerSelector.swift`
- `WorkbenchWorkspaceView.swift`
- `WorkbenchWorkspaceStore.swift`
- `WorkbenchVisualSystem.swift`
- `WorkbenchDashboard.swift`
- `WorkbenchOverviewEditor.swift`
- `WorkbenchOverviewPersonalization.swift`
- `WorkbenchOverviewProjection.swift`
- `WorkbenchOverviewRuntimes.swift`
- `WorkbenchOverviewTopology.swift`
- `WorkbenchProxyGroupPanels.swift`
- `WorkbenchProxies.swift`
- `WorkbenchDataShared.swift`
- `WorkbenchConnections.swift`
- `WorkbenchConnectionsView.swift`
- `WorkbenchConnectionDetails.swift`
- `WorkbenchRules.swift`
- `WorkbenchSources.swift`
- `WorkbenchLogs.swift`
- `WorkbenchManagement.swift`

Files follow ownership and update frequency: chrome/workspace, Overview,
Proxies, each high-density data destination, and management remain separate.
Connections is the one split data destination: projection/cache, live Table,
and selection-driven details have different update rates. Do not add
compatibility files or recreate one-file-per-small-component sprawl.

## Navigation And Chrome

- Use one `NavigationSplitView` and ten fixed destinations: Overview,
  Proxies, Connections, Logs, Rules, Sources, Controllers, Configuration,
  Actions, and Diagnostics. Application preferences live only in the native
  Settings scene opened from the app menu (`Command-,`).
- The sidebar starts with a collapsed inline controller switcher above the
  ten destinations. Expanding it reveals persisted-order controller rows
  plus Add and Manage actions in the same window; the full management surface
  remains on Controllers. Controller identity is not repeated in the toolbar;
  the native navigation title owns that space without a custom capsule.
- Normal work happens in the main window. Controller editing, proxy expansion,
  member selection, filters, tests, inspectors, and operation results do not use
  popovers, context menus, sheets, or modal dialogs. A native confirmation is
  reserved for destructive/high-risk actions or a dirty-window close.
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
- Overview is a monitoring canvas: three primary real-time charts for upload,
  download, and active connections, followed by complete topology and network
  facts. Charts expose selection, cursor, pause, and same-window drill-in
  instead of acting as decoration.
- Connections, Logs, Rules, and Sources are data browsers: one native `Table`,
  toolbar search/filter/sort controls, stable rows, and an optional same-window
  inspector. Loading and empty states occupy the table region without changing
  the command-bar geometry.
- Proxies is an ordered selection workspace: controller-reported groups remain
  in order, expand inline, and expose node selection and filtering without a
  modal. Selection hierarchy matters more than dashboard metrics.
- Controllers detail, Configuration, and Actions use the same bounded native
  grouped-form canvas. Controls follow their explanation, while command buttons
  align to the trailing edge and keep visible titles. These pages do not become
  full-width dashboards. The Controllers list remains a native split-view list,
  and the native Settings scene keeps its own bounded grouped form outside
  Workbench navigation.
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
- Diagnostics is a status band plus hierarchical outline. Use progressive
  disclosure for advanced checks and reserve technical payloads for the copied
  report.
- Before redesigning an archetype, review the corresponding current Apple HIG
  component and one current native macOS reference. Record any deliberate
  exception here before introducing a second layout model.

- Use the exact accessible Midnight Instrument adaptive palette (dark-first "墨蓝黑",
  light "实验室白"):
  - page `#E7E9F2` / `#0E0F1A`
  - content `#FBFBFE` / `#161827`
  - elevated `#DEE1EE` / `#1E2133`
  - tertiary `#D9DCE9` / `#2A2E45`
  - accent (electric indigo) `#4F5BD5` / `#8B93FF`
  - cyan (info) `#1E7A93` / `#6FD3E7`
  - mint (ok) `#2E7D54` / `#7FD4A8`
  - amber (warning) `#9A6410` / `#F2BE6E`
  - red (error) `#B23A52` / `#F28B9E`
  - violet (debug/trace) `#6C4FD1` / `#B79CFF`
- The four signal hues stay at least 30 degrees away from the accent so color
  never carries meaning alone. A soft accent fill (`accentSoft`) backs navigation
  and table-row selection. Numeric values use monospaced-digit/SF Mono styling so
  live refreshes never shift layout. Motion in `WorkbenchMotion` animates only
  value or structural changes and degrades to static under Reduce Motion.
- Text uses semantic primary/secondary foreground styles.
- Sidebar navigation remains a native virtualized list, but destination rows
  own their button selection semantics. Selection uses a 14% accent fill,
  a three-point leading indicator, monochrome symbols, and primary text rather
  than the saturated system-wide selection block. Rows use callout content plus
  compact vertical padding, and the native button label fills the complete list
  row with a rectangular interaction shape. Do not impose one global touch
  height on this pointer-driven macOS navigation.
- Native window/sidebar/toolbar material is allowed. Workbench content contains
  no custom `.glassEffect`, `GlassEffectContainer`, gradients used as
  decoration, nested cards, or repeated floating panels.
- The window container, native toolbar, command bars, and management canvas use
  the same adaptive page fill across every destination. Loading, unavailable,
  filtered-empty, and empty states paint that fill explicitly; `contentFill` is
  reserved for real tables and intentionally raised data surfaces. Management
  pages center a responsive canvas with an 1180-point reading limit; form-heavy
  pages use a 1040-point limit. The native Settings window uses one centered
  grouped form limited to 820 points, with no duplicate Workbench route or
  repeated in-page title. Data browsers remain width-filling.
- Overview uses flat modules and separators. Its default layout contains only
  telemetry, complete route topology, and network information. The instrument
  rail and operational summaries remain optional personalization modules.
- Telemetry is one module containing equal-weight upload, download, and active-
  connection panels. Wide layouts use three columns, medium layouts use two
  traffic columns plus a full connection row, and narrow layouts stack them.
  Each panel keeps a substantial plot, one current or selected value, and the
  shared cursor, pin, stepping, pause, and return-live state. Memory appears as
  context on the connection panel instead of a fourth chart.
- Radius is 8 points or less except native system controls. Badges may be pills.
- Command summaries, section headings, and metric labels render SF Symbols
  through the shared `WorkbenchSymbol` primitive with monochrome rendering, a
  stable frame, and an explicit semantic tint. Do not rely on an inherited
  `LabelStyle` or secondary foreground alone for these navigation cues.
- Mica interface text uses `micaFont` semantic roles and the selected
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
- The selection-driven node detail is inserted below its own group as one flat
  information shelf, not a field-card wall. Overview, reported `true` and
  `false` transport states, and testing/latency use adaptive key-value columns.
  Known fields must not be repeated under additional controller fields. Extra
  fields remain folded by default, individually selectable in stable key order;
  arrays and objects use deterministic compact JSON.
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
- Overview is a personalized summary, not another data browser. Its five unique
  modules are instrument rail, telemetry, operational summaries, complete route
  topology, and grouped network information. Full connection fields remain on
  the Connections inspector; Overview never restores a raw connection selector
  or retained-closed aggregation.
- One app-owned layout store persists a global default and optional
  per-controller overrides. Each window owns a transactional draft, UndoManager
  history, conflict state, and stable module runtimes. Normal edits remain
  inline; Done persists once, Cancel discards, and external commits require
  explicit Reload or Keep Mine.
- Reset records an explicit remove-override transaction, so it continues to
  inherit a global default changed by another window before Done. A global
  default commit compares both the target controller's effective revision and
  the global revision before it may remove that target override.
- Controller-layout cleanup starts only after profile loading completes and
  removes IDs observed as actually deleted. A transient empty cold-launch
  snapshot never prunes persisted overrides.
- Module order, legal size, visibility, presets, instrument order/visibility,
  timeline window, summary order/visibility/count, and network-group order are
  customizable. At least one module, instrument, and visible summary category
  remain. Network fields themselves are never hidden. Complete route topology
  is always a full-row module so its complete chain cannot be squeezed beside
  another module.
- The topology admits every active connection and every reported chain hop.
  Missing source or chain metadata creates an explicit unavailable path record,
  not a fabricated edge. Each layer owns a distinct node identity, nodes sort by
  reported name within that layer, and aggregated edges retain their real count
  while display width uses `log10(count + 1) * 10`. The width-fitted Sankey uses
  15-point node bars, 4-point gaps, curved gradient ribbons, and full-trajectory
  hover/pin highlighting. Hover and explicit pause freeze only the presented
  snapshot; ingestion continues and resume catches up to the latest real frame.
  Inline expansion, complete accessible path rows, and navigation to Connections
  stay in the same window. The graph has no nested scroll axis and grows
  vertically with its densest column. Visible node bars win hit testing first,
  ribbons win over overlapping invisible node padding, and bounded label-adjacent
  node targets use a local 28-point acquisition size while ribbons use a
  10-point baseline tolerance. Never index a
  node label target across the complete distance to the next column.
- Diagnostics leads with an unframed compact status band containing the
  localized conclusion, selected controller, connection state, compatibility,
  last check, and recommended action. It then uses one flat same-window outline
  for controller metadata and all detailed checks; never wrap either region in
  an opaque card or nest cards inside disclosures. Controller metadata uses a
  compact adaptive fact grid instead of a long form table. Diagnostic row states
  and counts use restrained text signals rather than repeated filled badges.
  Visible rows use user-facing
  feature names and outcomes; API paths, adapter evidence, machine key/value
  summaries, credentials, and raw response or stream bodies stay out of the
  page. The Copy Report command retains the credential-safe technical report.
  Every disclosure header owns its complete row hit region and uses the same
  animated chevron and lightweight opacity transition at both levels. Keep
  animation in the toggle transaction rather than attaching it to the expanded
  subtree, and avoid nested lazy containers for these bounded row sets. Filter
  `.unavailable` controller capabilities before rendering nested rows; omit a
  top-level section when no supported rows remain.
- Provider diagnostics choose the newest real command across individual Update
  and Update All records rather than assuming only one action exists.

## Performance Boundaries

- Workbench views do not observe `AppModel.controllerSession` directly. They
  read the field-granular `controllerSessionPresentation` state so timeline and
  stream-buffer mutations cannot invalidate views that only need state,
  generation, controls, identity, or runtime.
- Overview telemetry, summaries, grouped network facts, and topology are
  separate invalidation subtrees. A traffic sample rebuilds the telemetry
  subtree only.
- The Overview vertical scroll uses lazy construction. Below-viewport charts,
  topology, and network facts are not created eagerly.
- Hidden modules are filtered before constructing their subtree. Sequential
  12/6/1-column row packing preserves user order and never moves a later module
  ahead to fill a gap. Window runtime objects preserve timeline and topology
  caches across reorder/resize while hidden modules perform no work.
- Live chart collections use stable identities and bounded real samples. Do not
  format, sort, group, or rebuild search text inside a mark or row body.
- Traffic, memory, and active-connection timelines append only controller-received
  samples. They never pad a window with zeroes or derive history from a current
  snapshot. Upload, download, and active-connection charts anchor the latest
  sample to the right edge, use area plus linear line rendering, share hover/
  click/keyboard selection, and pause only presentation while retained session
  data continues to advance. The nearest real memory sample annotates the
  connection chart instead of creating a fourth plot.
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
  timelines. Topology stores indexed nodes, edges, path memberships, and
  segment-cell hit regions; hover/selection cannot rebuild graph structure.
  Overview is the sole scroll owner. The complete topology fits the available
  width without a nested horizontal viewport and expands its cached render
  bands vertically.
- Expensive presentation work may be deferred during scrolling, chart dragging,
  or filter typing, but one latest result must survive the interaction window.
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
- Configuration and native Settings use grouped `Form`; Actions uses shared
  management surfaces. Diagnostics uses an unframed status
  band followed by a continuous outline with hairline separators and indented
  detail guides. These are operational rows, not Liquid Glass or decorative
  cards.
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
