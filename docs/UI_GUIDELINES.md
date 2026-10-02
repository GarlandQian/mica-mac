# UI Guidelines

## Design Review

Review the actual SwiftUI surfaces in light and dark appearances at narrow and
wide window sizes. Keep native keyboard navigation, meaningful empty states,
readable controls, and complete reported data. Behavioral tests and rendered
screenshots validate different parts of the experience.

## Workbench Structure

Page models own transient projection, selection, and scroll state. SwiftUI views
own native controls, persistence, and command dispatch. Editor navigation passes
through one transaction model, including canceling a previously requested exit.

- Build the usable controller workbench as the first screen; do not add a marketing or command-home layer.
- Use native sidebar navigation, toolbar search/actions, keyboard commands, SF Symbols, and same-window inspectors.
- Ordinary policy browsing, node selection, latency testing, source inspection, and connection inspection stay inline and never depend on a menu. The topology canvas may mirror its direct canvas and keyboard selection commands in one native context menu; no business data or command exists only there. Sheets, popovers, other context menus, and confirmation dialogs remain reserved for platform-required or destructive flows.
- The sidebar uses native List selection and a controller menu above navigation.
  Groups are Workspace (Overview, Proxies, Connections, Rules, Sources), Monitor
  (Logs, Diagnostics), and Controller (Controllers, Configuration, Actions).
  The controller menu preserves saved order and exposes Add, Manage, and Test.
  Opening it does not push navigation out of view. Controller identity reads
  are isolated from traffic updates. Row selection on Controllers manages a
  profile; explicit Use changes the live controller.
- Show Refresh and Pause on controller work pages. Show the inspector command
  only where actual detail content exists. Keep application preferences in
  native Settings and keep editor-discard checks in the window's navigation
  binding.
- Policy groups use a controller-ordered directory beside one active-group workspace. Directory rows show health, name, member count, current selection, and group type, with an inset rounded active and hover state. The active group header owns the single Locate Current command and a bordered Test Latency command; the member count sits beside the member search. The directory has a bounded 200-point width. Its search matches group name/type; the separate active-node search matches node fields. The toolbar does not repeat either search. Activating a group replaces the displayed member list; it never switches the controller's selected node. Mihomo ordinary groups follow matching names in `GLOBAL.all`, then unlisted groups in `/proxies` order; Surge and sing-box preserve their reported sequence. Filtering and interaction never reorder the result, and visible `GLOBAL` stays last. Group members preserve each group's reported order by default. A Sort Nodes menu beside the health filter can arrange the displayed members by lowest latency (measured delays ascending, then failed or timed-out nodes, then untested nodes, ties in reported order); it sorts only the filtered presentation copy and never changes the catalog, selection, or test targets.
- The active workspace has a compact identity/current-selection header, reported member counts, a health filter, and one virtualized member list. Directory scrolling and member scrolling have separate bounded regions; never recreate a page of expanded groups or nest full member grids in a same-axis lazy stack. Build and cache member indexes only for the active group.
- Node rows align name, reported protocol, latency, and independent commands. Quiet current-selection, hover, inspected, and reveal treatments distinguish state without permanent card outlines. Additional reported transport, source, SMART usage, and availability remain accessible. Unavailable nodes have a text state as well as color. Row-body and default VoiceOver activation only inspect. Switching uses a separate capability-gated button or named accessibility action and does not change the inspected node. Testing is independent and visually secondary, with one progress indicator per testing node.
- Hover provides a lightweight node preview; activation opens complete details inline below that node. Preview height stays within the member viewport, reduces optional fields when space is tight, and pauses during scrolling before restoring under a stationary pointer. Closing the detail does not mutate controller selection. Proxies has no competing workspace inspector. An opened node reads as one framed card: its row is the tinted header and the detail is the body. The detail leads with labeled summary tags (availability, latency, type, provider, SMART rank) and check/cross capability tags, then titled cards for reported configuration, runtime, test results, and other fields in balanced columns. Keys share a bounded leading column so values align beside them. Test times display in the reader's locale with the reported text as help, and two or more reported delay samples draw as a small history strip. The active group header owns group name and type, so the detail omits only those two fields. Known fields are human-labeled and never repeated as additional fields; uncategorized controller fields render in stable key order as monospaced key-value rows.
- Hover candidates and delayed preview state belong to the preview leaf, not
  the whole policy page. Individual node rows own their hover treatment and
  anchors; moving the pointer must not rebuild the directory or member index.
- Node location preserves the independent directory search, including when it activates another group. Explicit filter recovery clears only the member query and health filter; directory matches never block a member visible in the active workspace.
- `ProxyWorkspaceModel` owns policy catalog acceptance, projection indexes,
  filtering, and cached group presentations. A nonvisual leaf receives scalar
  catalog revisions through the scroll scheduler. The visual tree consumes
  accepted model output, so traffic and unrelated workspace changes do not
  rescan the catalog or rebuild unchanged active-group members.
- Overview chart and topology reservations account for window height as well
  as width. The metric charts retain one view collection when their columns
  change. Avoid width-only heights that make a short, wide window excessively
  tall; dense graph content remains scrollable without dropping routes.
- Each node's detail distinguishes runtime state, reported protocol configuration, reported capabilities, test results, and other reported fields. Missing protocol types remain absent, never replaced with a parent group type or guessed `Proxy` label. A runtime-only response must not produce a protocol-configuration section. Nested parameters retain complete field paths and original array indices; literal punctuation in keys is escaped so object keys cannot alias nested properties or array indices. Missing values and empty groups stay hidden, while reported `false` and `0` remain visible. Authentication parameters, including unknown extension fields, are masked by default and may be revealed individually; switching the inspected node, controller, or session resets that state. Generate complete parameter rows only for the inspected node, not for the whole catalog.
- Data tables and inspectors put the primary business field first: name, host, ID, payload, or message before type/status/auxiliary metadata.
- Empty data surfaces use native `ContentUnavailableView` with two distinct levels of copy: a short state title plus a cause or next-step description. Never repeat the same localized sentence as both title and description; distinguish no controller data from no filter matches. Keep headers and command rows at the top, then center the empty state in the remaining content region.
- Connections, logs, rules, and sources each construct one native `Table` plus row detail in the single workspace-level `.inspector` column (attached once at the workspace root; no page-level inspectors or resident placeholder panes). A root-level width mode conditionally supplies typed, composite, or stacked columns without constructing parallel Table trees; no mode drops a business field. Connections adds one compact current-result pulse above its Table and a complete selected route path; its host cell lists only reported destination and network parts, and the process column carries process name and path without repeating the network; closed rows show historical totals rather than live rates, and additional objects/arrays disclose as structured fields rather than machine JSON paragraphs. Scan rows keep fixed single-line geometry, while complete wrapped/selectable values remain in the inspector. Search and category filters never reorder the source collection. User-initiated column sorting applies only to a presentation copy and never mutates source order. Logs remain source ordered: selecting a row or manually scrolling disables Follow Newest, rapid automatic scroll requests are coalesced, and Jump to Newest restores following. Beside its count, Logs shows error and warning totals for every retained entry regardless of level or search; each total selects the newest visible entry of that severity (and is disabled when none is visible). Rules offers Type and Policy facet menus listing each reported value with its rule count, most frequent first; facets narrow the controller order like search and never reorder it, persist per controller, and navigation to a rule they hide lifts search and facets.
- The selected connection path stays in one horizontal strip with native horizontal scrolling for every reported hop. It must not expand into a tall vertical path above the Table. Complete source, inbound, rule, policy, exit, and destination values remain reachable, with exact policy/rule navigation and existing close-command capability checks.
- Connections, logs, rules and sources retain the latest complete catalog while
  scrolling, then present it once scrolling ends. Ingestion continues. Native
  trackpad gestures use their begin/end lifecycle; unphased mouse-wheel ticks
  use the owning scroll view's live-scroll notifications and a bounded idle
  deadline, without a global event monitor.
  Explicit filters, sorting, navigation, clearing, and Jump to Newest take
  effect immediately. Pending data is scoped to the active controller and
  generation; skipped deltas reconcile against the complete snapshot. A
  retained connection-close target must still match the current unique ID
  and static connection identity before the command can run.
- Live catalog intake belongs to nonvisual leaf views. Deferring the page model
  alone is insufficient if the root still observes each incoming catalog.
  Capability checks must not subscribe the whole page to traffic or timestamps.
- Logs put the message first and reserve bounded secondary columns for level, type, and received time. The level control is a segmented choice that sets the lowest level Mica subscribes to and shows (on Surge it also changes the controller's own level); Follow Newest is a native toggle button. Compact rows keep the message on the primary line and factual metadata on the secondary line. Rules put payload first in the full table, followed by type, target, activity, state, and the original index; secondary columns stay bounded so extra width benefits the payload.
- Sources retain one table at every width. Compact rows pair name with reported configuration, while the trailing summary owns item count, update time, and update/health-check capabilities. Configuration summaries include reported vehicle, format, and behavior without repeated unavailable placeholders. Capabilities use neutral icons and text: being updatable or reporting a health-check configuration is not a successful health result. Full values and unsupported-capability explanations remain available through the inspector and accessibility summary.
- Rule scan rows treat payload plus type/index as one definition, then show
  route, activity, and state. State uses a quiet dot-and-text label; mutable
  enable/disable is part of the state cell rather than an isolated action
  button column. Compact mode combines route, activity, state, and action;
  stacked mode keeps one complete composite column.
- A selected rule adds one compact `type → payload → target policy` focus path
  above the Table. The complete path and statistics remain horizontal and
  scroll independently when narrow, leaving the Table a usable viewport.
  Only an exact case-sensitive visible policy-group target is
  a navigation action; DIRECT, REJECT, node names, and unknown targets remain
  plain reported values.
- A selected source keeps its identity and available commands together, with
  lifecycle facts on one horizontally scrollable line at narrow widths. Its
  single-source commands capture the session that supplied the displayed row;
  retained commands cannot operate on a replacement controller or generation.
  The source-kind filter uses a segmented picker only while its full localized
  labels fit, then switches to a native menu. Neither the filter nor selected
  summary may expand the data column beneath the inspector.
- Management pages use one bounded, leading-anchored content column. Controllers
  detail, Configuration, controller add/edit, and the native Settings scene use
  grouped `Form` sections. Actions uses a state-aware flat command workspace;
  Diagnostics uses one continuous action-first triage canvas: a status-tinted
  verdict card (state, meaning, fact tags, Recheck), an adaptive issue
  workspace, working areas as small navigation cards, and one secondary
  technical disclosure. Actions commands
  are cards whose column count fits readable card widths, never exceeding the
  command count. Each operation has a
  command button that stays visible while running, and destructive operations
  retain the existing inline confirmation. Both keep one outer
  scroll owner on the shared page fill rather than raised or nested cards.
- Every controller-management field uses `WorkbenchFormRow`: at regular width a
  leading label of at least 176 points with the control at the trailing edge,
  as in System Settings and Mica's own Settings window; read-only values also
  trail. At compact width the row stacks leading. It owns the only visible
  field label; embedded text fields, secure fields, pickers, toggles, port
  controls, and Tailscale controls inherit hidden native labels from the row.
  Preference rows show concise help below the label. Do not restore
  `LabeledContent` auto-centering or wrap a form between spacer columns.
- Language and GLOBAL visibility use one compact borderless menu with a
  current-value icon, label, and disclosure chevron. Appearance and interface
  text size preview their result as System Settings does: a row of labeled
  tiles (miniature light, dark, and split windows; "Aa" at each text size)
  with an accent ring and the native selected trait on the current choice.
  Do not render these as a strip of boxed segmented buttons.
- The native Settings scene is the only application-preference surface and uses
  the shared persisted preference bindings directly. Controller add/edit
  uses one bounded native grouped form in the same-window detail region, with a
  Workbench command bar for Save, Cancel, and Test. It has no fixed draft
  preview column; connection diagnosis appears as a form section only after
  Test starts. Each row shows one field label; embedded text fields, secure
  fields, and pickers hide their duplicate native Form labels. Save, Cancel,
  and Test remain titled commands at every supported width. Dirty ordinary
  navigation uses the inline discard bar;
  dirty main-window close is the destructive exception and uses the native
  AppKit confirmation. Saving disables every editor-replacement path.
- The menu bar item (Settings › General › Show in Menu Bar, on by default) shows
  compact upload and download rates while a session streams and only the app
  symbol otherwise. Its menu names the controller and full rates, lists each
  switchable policy group in the workbench order and GLOBAL visibility as a
  submenu of members in reported order with reported delays and a checkmark on
  the current member, and offers Open Mica, Settings, and Quit.
- The Controllers page is one full-width native persisted-order `List`;
  selecting a row opens the workspace inspector with the complete detail
  (identity, capability-gated actions, connection fields, test report, inline
  delete confirmation). Each row shows a controller-type tile, the complete
  name and selectable endpoint, and a trailing type and connection-state
  column. The active controller carries an Active badge; every other row
  offers the explicit Use command. Use in rows and in the inspector is one
  shared control, the only path that switches the live controller. Rows can
  be dragged to reorder while the complete, unfiltered list is visible, and
  Move Up/Down remain in the inspector. Edit, Test, and Delete live in the
  inspector detail. Actions uses the
  effective controller/session state: checking and recovery show target context
  plus Test, Edit, and Diagnostics; ready/partial shows only verified commands
  as cards in up to three columns, each with its icon, description, and one
  Run command; confirmation-gated commands say Run… and confirm inside their
  own card.
  Full command inventories do not add related-workspace filler, while a real
  at-most-two-command controller may link to its owning workspaces. Capability
  gating hides unsupported operations rather than showing disabled placeholders.
- Diagnostics treats checking as a gate: before the first successful baseline
  it shows neither provisional failures nor Available Now. Controller-wide
  failures suppress derived endpoint errors even when prior data is retained,
  and rejected machine-facing evidence becomes localized unavailable copy.
  Issue rows announce localized severity, title, affected count, and native
  selected state; color and SF Symbols remain supplemental. The verdict header
  exposes a named Recheck command through the existing availability gate. Issue
  detail places its primary corrective action before affected-workspace links,
  and the full canvas stays leading-anchored within the management width bound.
- The bottom session bar is always present with a stable, unscaled native minimum height. It reserves actual layout space beside the content in the root vertical stack; a safe-area overlay can cover the last native Table row. It shows controller, unified live state, and last success; while presentation is paused it shows the fixed pause instant instead of a moving network timestamp. Temporary operations replace only the status summary, and larger Dynamic Type reflows through the provided variants instead of multiplying bar geometry.
- Test remains available while presentation is paused. Refresh, rule/source reload, and provider update are disabled everywhere through the same AppModel capability. Endpoint failures retain the last successful rows and add a stale marker; never-loaded endpoints alone use an error empty state.

## Visual System

Mica follows the macOS 27 Liquid Glass design. The system owns the control
layer: the unified window toolbar, the floating sidebar, and the inspector are
native glass that Mica never paints. Content sits on the system window
background and groups itself with the system fill hierarchy, so every surface
tracks Increase Contrast, Reduce Transparency, and the user's glass tint
preference.

The shared tokens live in `MicaTheme` (`Sources/Mica/Design/MicaTheme.swift`):

| Role | Token | Source |
|---|---|---|
| Page fill | `canvas` | `windowBackgroundColor` |
| Grouped panels and cards | `surface` | quaternary system fill (light) / tertiary (dark), matching native grouped `Form` sections |
| Hover on a grouped row or tile | `surfaceHover` | secondary system fill |
| Hairlines | `separator` | `separatorColor` |
| Accent | `accent` | macOS accent preference |
| Status OK / Warning / Error | `status*` | system green / orange / red |

The topology route canvas is an opaque drawing layer, so it uses
`Topology.panelSurface`, the grouped fill resolved over the page fill, for both
its card and its base; its node cards use opaque `Topology.nodeSurface`.

Text uses the system label-color ramps (`textPrimary` / `textSecondary` /
`textTertiary`) in both appearances. The user's macOS accent owns selection,
active topology paths, and commands. Chart series use dedicated teal upload,
blue download, and orange connection colors. Native List and Table selection
supply their own focus, active/inactive appearance, and accessibility
treatment.

Geometry uses continuous corners sized for macOS 27 windows: 12-point cards
(`Shape.panelRadius`), 8-point standalone rows and tiles (`Shape.rowRadius`),
and 10-point modules. `micaCard` is the one grouped-card treatment: a
borderless system fill that also becomes the container shape, so nested fills
use `ConcentricRectangle` rather than a hand-picked smaller radius. Status
badges and tags are capsules. Panels do not add hairline borders or shadows;
hairlines separate adjacent regions only.

Numeric values (KPIs, rates, timestamps, byte counts, endpoints) use the SF Mono
`data*` text roles with tabular numerals so live refreshes never shift layout
horizontally. Motion primitives in `MicaTheme.Motion` (snappy press 120ms,
smooth state change 160ms, smooth reveal 200ms) use the system's critically
damped springs, animate only value or structural state changes - never scroll
position or high-frequency row layout - and are gated through
`micaStateChangeAnimation`, which renders static equivalents under Reduce
Motion. There are no idle loops, repeating timers, or ambient animation.

Sidebar destinations use tagged rows in a native selection-bound `List`.
macOS owns arrow-key navigation, row hit testing, focus, and selected-state
semantics. The controller switcher is pinned above navigation in a top
`safeAreaBar`, so destinations scroll beneath it with the native scroll-edge
effect. The selection binding delegates destination changes to the window,
which protects dirty or saving controller edits.

The toolbar is one shared `WorkbenchToolbar`: Refresh and Pause share a glass
group with high visibility priority, the inspector toggle is a native button
toggle separated by a fixed `ToolbarSpacer`, and the optional Overview
preferences control stands in its own group with low priority so it moves to
the overflow menu first.
Toolbar commands use native labels; the glass toolbar supplies capsules,
hover, pressed, and overflow presentations.

Command bars on Actions, Configuration, Diagnostics, and the controller editor
name the controller they act on rather than repeating the page title. Bulk and
destructive bar commands (Close All, Close Connection/Group, Clear Closed, Clear
Logs, Update All Sources) are titled `WorkbenchLabeledCommand` buttons; icon-only
commands remain for universal verbs such as refresh and pause. When a command
bar wraps, its controls stay on one row beneath the summary.

The window container names `MicaTheme.canvas`; the toolbar has no painted
background. Command bars, management canvases, and loading/empty states share
the same page fill. Liquid Glass is reserved for Mica's own floating layer and
is applied only through `micaFloatingGlass`; today that is the transient proxy
node hover preview. Business-data tables, controller rows, policy
selectors/members, logs, long text, topology, charts, and inspector content use
flat semantic fills; do not nest cards or use decorative gradients, glow, or
orbs. Data tables use the native inset style with continuous selection. Follow
System, Light, and Dark apply to the entire window. The custom top-level
Controller menu follows the macOS menu language; its commands follow Mica's
selected interface language.

Management pages use a leading-anchored bounded canvas rather than a fixed-width centered block. The canvas grows to an 1180-point limit and form-heavy pages grow to 1040 points. The standalone native Settings window uses one centered grouped `Form` up to 820 points; it has no duplicate Workbench route, repeated title, or unbalanced category column. Data tables, timelines, topology surfaces, policy workspaces, and logs remain width-filling because their scan and interaction density benefits from the available canvas; the route graph inside an ultrawide topology surface caps ordinary column spacing and stays centered.

Overview does not repeat the selected-controller/session header. The route topology leads its fixed, width-filling core; a compact real-time trend strip for upload, download, and active connections follows it. Instrument rail, operational summaries, and grouped network information follow in that fixed order only when globally enabled. Operational summaries and network information are visible by default because they add facts the charts do not show; the instrument rail repeats the chart readouts and is opt-in. The one app-owned preference value controls visible primary metrics, timeline window, and optional visibility, applies immediately across windows/controllers, and resets to all metrics, five minutes, operational summaries, and network information. There is no module reorder, resize, preset, per-controller override, layout draft, Done/Cancel transaction, or legacy-layout migration; saved preferences from the earlier preference schema are upgraded once to show the two new default modules.

Telemetry always occupies one row. When all enabled metrics fit, they share
equal columns; otherwise a segmented selector switches the single complete
chart, retaining timeline selection across metrics. Plot heights use a
56-to-92-point viewport budget. The summary topology uses a height-aware
208-to-440-point budget and shrinks further to fit sparse content; complete
mode retains a 280-to-500-point viewport. Dense graph content scrolls inside
that reservation. Upload and download each use their own
reported values to determine the vertical axis; small connection counts use
their actual range instead of a 100-connection floor. Charts share timestamps,
hover/pin selection, keyboard stepping, pause, and return-to-live. Memory is
contextual metadata on the connection chart. Zero and single-sample series
retain a visible padded scale and the latest real point without generating data.

The default topology summary aggregates dense columns into at most six displayed nodes per column. Aggregate counts and path membership remain exact; selecting a node or aggregate exposes its complete reported routes. Aggregation is presentation-only: the complete graph retains every active path and reported hop, including unavailable partial-route records. The complete graph can scroll in both directions within the topology viewport.

Complete topology nodes are opaque cards, 144–184 points wide and 36–44 points high, with 12-point vertical gaps and at least 48 points of routing space between columns. Names stay inside their cards; source addresses use monospaced labels and other nodes use regular labels. Type symbols and real node counts identify the columns. Cards paint after every edge so routes cannot cross text, including during selection. Status appears as a small node marker. Sparse graphs cap spare vertical space; dense graphs grow internally and retain their complete data.

Hover shows the exact selection label and factual route detail. Selecting a summary node or edge opens its related original paths in a bounded list with a complete stage-by-stage detail. This is an explicitly captured snapshot; connection navigation remains available only while its controller generation and structural revision still match. Return to Overview restores the summary, and View All opens the complete graph. In the complete graph, clicking a policy node pins the selection and opens its full field composition in the inspector. Escape or blank-canvas activation clears selection. Policy inspection reads only the published catalog through a cached index, uses exact case-sensitive unique matching, and preserves additional reported fields without network requests. Duplicate or missing names retain truthful route detail. Proxies/Connections navigation and VoiceOver remain available.

Workbench views observe `controllerSessionPresentation`, `controllerMetadata`, and domain catalogs instead of the broad `controllerSession` or `dashboard` aggregates. Each window root registers one stable destination-demand token; the selected generation publishes the union required by all windows through one runtime. Logs/traffic/connections/memory publish at 5/4/2/1 Hz and hidden domains flush once on entry when pause/baseline gates permit. Timeline updates stay inside the telemetry subtree; they do not rebuild sidebar switching, configuration, policy/rule projections, network facts, or topology. Render zero byte values deterministically as `0 B` / `0 B/s`, not locale text such as `Zero KB`.

## Text And Density

- All visible copy comes from `Localizable.xcstrings` in English and Simplified Chinese.
- Font scale changes visible Mica text through one semantic `micaThemeFont` ladder using multipliers `0.92`, `1.0`, `1.16`, and `1.32`; `dynamicTypeSize` remains a native-control fallback. Management rows change between horizontal and stacked layouts only from actual available width, never from the selected font step. Sidebar width, status height, interaction targets, margins, and table breakpoints stay bounded and are never multiplied by text scale. Do not add direct view-level `.font(...)` calls for interface text; use `micaThemeFont` so every destination responds immediately.
- Controller names and endpoints must wrap or receive enough width; do not middle-truncate or mask them.
- Monospaced styling is reserved for endpoints, IDs, payloads, paths, counters, and protocol values.
- Unknown values use localized not-reported/unavailable wording rather than fabricated zeros. Scan-table cells draw that state as a tertiary em dash with the complete wording as help and VoiceOver label. Inspector sections list reported values as rows and name every unreported field in one quiet summary line, so the state stays complete without burying real values; forms show the words. Joined cell text skips unreported parts rather than showing placeholder separators. Values are rendered de-emphasized (`.secondary`, smaller than real values) instead of body-weight prose.
- An unconfigured controller target says `Not configured` / `尚未配置`; it never renders a placeholder endpoint such as `http://-:9090`. IPv6 endpoints use bracketed host notation.
- Density target: policy headers and node rows derive height from semantic text and compact padding; shared two-line data tables keep stable scan geometry. Ordinary macOS controls use native compact geometry instead of a universal row-height floor.

## Charts And Accessibility

- Time-series charts use only bounded, generation-scoped samples received from
  the controller: traffic, memory, and active-connection count. Never pad a
  timeline with fake zeroes or derive history from a current snapshot.
- Anchor the latest real point to the right edge of the selected time window.
  Use area plus linear line rendering, hover/click/keyboard sample selection,
  and explicit presentation pause. Pausing never stops ingestion; resuming
  catches up to the latest retained sample.
- System Swift Charts implements received timelines. The topology retains every active path and reported chain hop. Source order stays stable; remaining columns use up to four cancellable bidirectional barycenter rounds, retaining the candidate with the fewest same-column-pair crossings. That order is cached with the structure and reused during resizing, hover, and metric updates.
- Each complete-graph edge is a round-capped cubic centerline with bounded density-aware width and opacity. Selected paths gain an accent stroke and a subtle outline; unrelated paths recede further. Real counts still determine attachment weights within each card's straight edges. No filled Sankey ribbons or continuous animation are used. The summary identifies aggregation explicitly rather than silently discarding paths.
- Overview owns page scrolling; the complete graph owns its bounded internal two-axis viewport. Current same-session geometry stays visible while a replacement is prepared, including when a scrollbar changes viewport width. Complete cards are hit targets; route gaps remain available for edge selection. Keyboard path stepping, pinning, clearing, inspection, and same-window navigation remain available alongside summary drill-down.
- The topology stores the exact visible rectangle for keyboard reveal without
  observing every offset in the graph body. Only viewport size changes may
  invalidate the geometry-dependent render; scrolling keeps the latest
  position available to explicit reveal actions.
- Current-state aggregates may render as category charts (distribution histograms, share bars, rankings) whose X axis is a category — latency grade, rule type, connection name — never a fabricated timestamp.
- Every chart carries an accessibility label plus a numeric/tabular fallback (`accessibilityValue` or equivalent) so values stay reachable without the visual.
- Aggregate modules show a lightweight localized empty state instead of placeholder data when the controller has not reported values.
- Every icon-only control needs a localized help string and accessibility label. Standalone icon controls use compact 28-point geometry; controls inside rows inherit the row's complete rectangular interaction shape. Selection and disclosure state remain keyboard and VoiceOver reachable.
- Controller inspector actions keep Use/Test/Edit/Delete and Move Up/Down reachable with named controls or localized help and accessibility labels. Controller list rows retain native selection and complete name/endpoint scan content.
