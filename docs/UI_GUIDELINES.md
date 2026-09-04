# UI Guidelines

## Design Review

The native macOS/SwiftUI/HIG skills (`macos-app-design`, `apple-hig-expert`, `swiftui-liquid-glass`) are the final authority for UI work. Follow the existing Workbench contract and verify measurable contrast and hit-target claims with `apple-hig-expert`'s `hig_checker.py`.

## Workbench Structure

- Build the usable controller workbench as the first screen; do not add a marketing or command-home layer.
- Use native sidebar navigation, toolbar search/actions, keyboard commands, SF Symbols, and same-window inspectors.
- Ordinary policy browsing, node selection, latency testing, source inspection, and connection inspection stay inline and never depend on a menu. The topology canvas may mirror its direct canvas and keyboard selection commands in one native context menu; no business data or command exists only there. Sheets, popovers, other context menus, and confirmation dialogs remain reserved for platform-required or destructive flows.
- The sidebar starts with a collapsed inline controller switcher above the ten
  destinations, which are grouped Operate (Overview, Proxies, Connections,
  Rules), Observe (Logs, Sources, Diagnostics), and Manage (Controllers,
  Configuration, Actions). It expands in place to show controllers in persisted order plus Add and Manage actions; the complete management view stays in Controllers. Application preferences appear only in the native Settings scene opened from the app menu, never as a duplicate sidebar destination. Do not repeat controller identity in the toolbar or cover the native navigation title with a custom capsule. Keep the inline switcher in an observation boundary that reads only profiles, selected ID, and displayed controller fields so traffic, log, memory, and connection frames cannot churn it. Row selection on Controllers manages a profile, while explicit Use or a quick-switch row changes the active live session. Recent history updates for every explicit controller change and never reorders the saved list.
- Policy groups use one bounded, controller-ordered vertical workspace with a single scroll owner. Each group has a compact identity/current-selection header, a real latency distribution, and an inline disclosure. Mihomo ordinary groups follow matching names in `GLOBAL.all`, then unlisted groups in `/proxies` order; Surge and sing-box preserve their reported sequence. Filtering and interaction never reorder the result, and visible `GLOBAL` stays last. Group members preserve each group's reported order.
- Multiple groups may stay expanded. Build and cache member indexes only for expanded groups, with independent filters and inspected-member state; prune indexes when groups close. Closing the active group prefers the next open source-order group, then the previous group.
- Expanded members use one source-ordered adaptive grid with at most three readable columns at regular width, then two or one as space contracts. Default cells have no permanent outline; a leading state rail and restrained hover, inspected, and current-node treatments provide hierarchy. Tiles show only reported name, type, transport, source, SMART usage, availability, latency, and current-selection state. The tile body inspects and invokes the existing capability-gated switch action; testing is separate and visually secondary.
- Node details render in the workspace inspector as one flat field composition
  and close without mutating controller selection. Overview, transport, and testing use labeled key-value columns rather than nested cards or a field wall. Known fields are human-labeled and never repeated as additional fields; uncategorized controller fields render in stable key order as monospaced key-value rows.
- The policy page reads `PolicyGroupCatalogSnapshot`, which changes only with mode or group data. High-frequency traffic, connection, provider, rule, and log updates must not force policy headers or expanded-group projections to recompute during scrolling.
- The selected-node detail groups overview, reported transport states, testing/latency, and additional controller fields. Arrays and objects use deterministic compact JSON. Generate complete additional-field rows only for the selected node, not for the whole catalog.
- Data tables and inspectors put the primary business field first: name, host, ID, payload, or message before type/status/auxiliary metadata.
- Empty data surfaces use native `ContentUnavailableView` with two distinct levels of copy: a short state title plus a cause or next-step description. Never repeat the same localized sentence as both title and description; distinguish no controller data from no filter matches. Keep headers and command rows at the top, then center the empty state in the remaining content region.
- Connections, logs, rules, and sources each construct one native `Table` plus row detail in the single workspace-level `.inspector` column (attached once at the workspace root; no page-level inspectors or resident placeholder panes). A root-level width mode conditionally supplies typed, composite, or stacked columns without constructing parallel Table trees; no mode drops a business field. Connections adds one compact current-result pulse above its Table and a complete selected route path; closed rows show historical totals rather than live rates, and additional objects/arrays disclose as structured fields rather than machine JSON paragraphs. Scan rows keep fixed single-line geometry, while complete wrapped/selectable values remain in the inspector. Search and category filters never reorder the source collection. User-initiated column sorting applies only to a presentation copy and never mutates source order. Logs remain source ordered: selecting a row or manually scrolling disables Follow Newest, rapid automatic scroll requests are coalesced, and Jump to Newest restores following.
- Rule scan rows treat payload plus type/index as one definition, then show
  route, activity, and state. State uses a quiet dot-and-text label; mutable
  enable/disable is part of the state cell rather than an isolated action
  button column. Compact mode combines route, activity, state, and action;
  stacked mode keeps one complete composite column.
- A selected rule adds one compact `type → payload → target policy` focus path
  above the Table. Only an exact case-sensitive visible policy-group target is
  a navigation action; DIRECT, REJECT, node names, and unknown targets remain
  plain reported values.
- Management pages use one bounded, leading-anchored content column. Controllers
  detail, Configuration, controller add/edit, and the native Settings scene use
  grouped `Form` sections. Actions uses a state-aware flat command workspace;
  Diagnostics uses one continuous action-first triage canvas with an adaptive
  issue workspace and one secondary technical disclosure. Both keep one outer
  scroll owner on the shared page fill rather than raised or nested cards.
- Every controller-management field uses `WorkbenchFormRow`: a 176-point leading label
  column at regular width and a leading stacked layout at compact width.
  It owns the only visible field label; embedded text fields, secure fields,
  pickers, toggles, port controls, and Tailscale controls inherit hidden native
  labels from the row. Preference rows show concise help below the label.
  Field controls begin immediately after the label column, while command buttons
  align to the trailing edge. Do not restore `LabeledContent` auto-centering or
  wrap a form between spacer columns.
- Preference choice rows use one compact borderless menu with a current-value
  icon, label, and disclosure chevron. Do not render appearance or font scale
  as a strip of boxed segmented buttons.
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
- The Controllers page is one full-width native persisted-order `List`;
  selecting a row opens the workspace inspector with the complete detail
  (identity, capability-gated actions, connection fields, test report, inline
  delete confirmation). Each row shows the complete selectable endpoint and remains
  scan-only; Use, Test, Edit, Delete, and manual reordering live in the
  inspector detail, and only explicit Use changes the active controller. Actions uses the
  effective controller/session state: checking and recovery show target context
  plus Test, Edit, and Diagnostics; ready/partial shows only verified commands.
  Full command inventories do not add related-workspace filler, while a real
  at-most-two-command controller may link to its owning workspaces. Capability
  gating hides unsupported operations rather than showing disabled placeholders.
- Diagnostics treats checking as a gate: before the first successful baseline
  it shows neither provisional failures nor Available Now. Controller-wide
  failures suppress derived endpoint errors even when prior data is retained,
  and rejected machine-facing evidence becomes localized unavailable copy.
  Issue rows announce localized severity, title, affected count, and native
  selected state; color and SF Symbols remain supplemental.
- The bottom session bar is always present with a stable, unscaled native minimum height. It shows controller, unified live state, and last success; while presentation is paused it shows the fixed pause instant instead of a moving network timestamp. Temporary operations replace only the status summary, and larger Dynamic Type reflows through the provided variants instead of multiplying bar geometry.
- Test remains available while presentation is paused. Refresh, rule/source reload, and provider update are disabled everywhere through the same AppModel capability. Endpoint failures retain the last successful rows and add a stale marker; never-loaded endpoints alone use an error empty state.

## Visual System

The exact Mica Ops tokens from `MicaTheme` (in `Sources/Mica/Design/MicaTheme.swift`)
are (light / dark):

| Role | Light | Dark |
|---|---|---|
| Canvas (window background) | `#FFFFFF` | `#0D0E10` |
| Surface (panels, sidebar selections) | `#F5F6F7` | `#15171A` |
| Raised surface (inspector, popovers) | `#FFFFFF` | `#1C1F23` |
| Separator (opaque hairlines only) | `#D9DBDF` | `#2A2D32` |
| Accent (signal teal) | `#0B8F66` | `#34D1A3` |
| Status OK / Warning / Error | system green / orange / red | system green / orange / red |

Text uses the system label-color ramps (`textPrimary` / `textSecondary` /
`textTertiary`) in both appearances. These values are fixed, not starting points
for derived palettes. The accent never decorates: it owns selection, the active
topology path, primary actions, and live indicators only. Status colors carry
controller-reported state only and never brand chrome. Navigation and table-row
selection use a 14% accent fill over the surface. Any new color role still
requires `hig_checker.py` verification.

Numeric values (KPIs, rates, timestamps, byte counts, endpoints) use the SF Mono
`data*` text roles with tabular numerals so live refreshes never shift layout
horizontally. Motion primitives in `MicaTheme.Motion` (press 120ms, state change
150ms, reveal 200ms ease-out) animate only value or structural state changes -
never scroll position or high-frequency row layout - and are gated through
`micaStateChangeAnimation`, which renders static equivalents under Reduce
Motion. There are no idle loops, repeating timers, or ambient animation.

Sidebar destinations remain in a native virtualized `List`, but each row is a
native `Button` with its own restrained selection treatment: a 14% accent fill,
three-point leading indicator, monochrome symbol, and primary text. Row height
is content-driven from the callout label and compact vertical padding. The
button label occupies the complete list-row width and declares a rectangular
interaction shape, so trailing whitespace remains clickable without imposing a
mobile touch-target height. Do not restore a saturated full-row system
selection block.

Native system materials belong to windows, sidebars, toolbars, the controller selector, and standard controls. The window container, native toolbar, command bars, management canvas, and loading/empty states share one `MicaTheme.canvas` page fill so every destination keeps a continuous title-bar color. Do not add custom `.glassEffect` content surfaces. Business-data tables, controller rows, policy selectors/members, logs, long text, and inspectors use flat semantic backgrounds with hairline separators; do not nest cards or use decorative gradients, glow, or orbs. Follow System, Light, and Dark apply to the entire window. The custom top-level Controller menu follows the macOS menu language; its commands follow Mica's selected interface language.

Management pages use a leading-anchored bounded canvas rather than a fixed-width centered block. The canvas grows to an 1180-point limit and form-heavy pages grow to 1040 points. The standalone native Settings window uses one centered grouped `Form` up to 820 points; it has no duplicate Workbench route, repeated title, or unbalanced category column. Data tables, timelines, topology surfaces, policy workspaces, and logs remain width-filling because their scan and interaction density benefits from the available canvas; the route graph inside an ultrawide topology surface caps ordinary column spacing and stays centered.

Overview does not repeat the selected-controller/session header. Its fixed, width-filling core contains three equal-weight real-time charts for upload, download, and active connections followed by the complete active route topology. Instrument rail, operational summaries, and grouped network information follow in that fixed order only when globally enabled; all are hidden by default. The one app-owned preference value controls visible primary metrics, timeline window, and optional visibility, applies immediately across windows/controllers, and resets to all metrics, five minutes, and no optional modules. There is no module reorder, resize, preset, per-controller override, layout draft, Done/Cancel transaction, or legacy-layout migration.

Wide telemetry uses three chart columns, medium telemetry uses two traffic columns plus a full connection row, and narrow telemetry stacks visible metrics. Plot height follows effective panel width within a stable 240-to-300-point range, while sparse topology requests `availableWidth * 0.36` clamped to 480-to-680 points and dense bounded-node columns may grow further. Overview section titles use 34-point framed marks and metric titles use 28-point framed marks: a hierarchical monochrome SF Symbol tinted `textSecondary` on a flat surface plate with a hairline border; the status colors stay reserved for real healthy, warning, or failure meaning, and dense rows retain unbacked monochrome symbols. Every chart shares real timestamps, hover/single-click pin selection, keyboard stepping, pause, and return-to-live; hover updates only readouts and indicators, while only a pinned sample changes the header to Selected. Memory is contextual metadata on the connection chart rather than a fourth plot. Zero-value and one-sample timelines remain visible through a presentation-only padded scale and a latest-real-sample point; this never fabricates samples. Overview does not contain retained closed data, a raw connection selector, or the full connection inspector.

The topology uses 12-point node rails, bounded 20-to-30-point node heights, 1.5-to-7-point cubic routes, 8-point vertical gaps, and caption labels with a secondary/tertiary/accent focus hierarchy. Hover shows the exact selection label plus factual role/count or route detail; clicking a policy node pins the canvas selection and opens the workspace inspector with the complete field composition, and Escape or blank-canvas activation clears selection. Policy inspection reads only the current published policy catalog through a cached bounded index, uses exact case-sensitive unique matching, exposes ordered members, typed node/test/transport fields, and every additional controller field in stable key order, and performs no network request. Duplicate or missing names fall back to truthful route detail. Eligible Proxies and Connections navigation remains in the same window, and VoiceOver exposes policy-node values and pinned state.

Workbench views observe `controllerSessionPresentation`, `controllerMetadata`, and domain catalogs instead of the broad `controllerSession` or `dashboard` aggregates. Each window root registers one stable destination-demand token; the selected generation publishes the union required by all windows through one runtime. Logs/traffic/connections/memory publish at 5/4/2/1 Hz and hidden domains flush once on entry when pause/baseline gates permit. Timeline updates stay inside the telemetry subtree; they do not rebuild sidebar switching, configuration, policy/rule projections, network facts, or topology. Render zero byte values deterministically as `0 B` / `0 B/s`, not locale text such as `Zero KB`.

## Text And Density

- All visible copy comes from `Localizable.xcstrings` in English and Simplified Chinese.
- Font scale changes visible Mica text through one semantic `micaThemeFont` ladder using multipliers `0.92`, `1.0`, `1.16`, and `1.32`; `dynamicTypeSize` remains a native-control fallback. Management rows change between horizontal and stacked layouts only from actual available width, never from the selected font step. Sidebar width, status height, interaction targets, margins, and table breakpoints stay bounded and are never multiplied by text scale. Do not add direct view-level `.font(...)` calls for interface text; use `micaThemeFont` so every destination responds immediately.
- Controller names and endpoints must wrap or receive enough width; do not middle-truncate or mask them.
- Monospaced styling is reserved for endpoints, IDs, payloads, paths, counters, and protocol values.
- Unknown values use localized not-reported/unavailable wording rather than fabricated zeros, rendered de-emphasized (`.secondary`, smaller than real values) instead of body-weight prose.
- An unconfigured controller target says `Not configured` / `尚未配置`; it never renders a placeholder endpoint such as `http://-:9090`. IPv6 endpoints use bracketed host notation.
- Density target: policy headers and node tiles derive height from semantic text and compact padding; shared two-line data tables keep stable scan geometry. Ordinary macOS controls use native compact geometry instead of a universal row-height floor.

## Charts And Accessibility

- Time-series charts use only bounded, generation-scoped samples received from
  the controller: traffic, memory, and active-connection count. Never pad a
  timeline with fake zeroes or derive history from a current snapshot.
- Anchor the latest real point to the right edge of the selected time window.
  Use area plus linear line rendering, hover/click/keyboard sample selection,
  and explicit presentation pause. Pausing never stops ingestion; resuming
  catches up to the latest retained sample.
- System Swift Charts implements the received timelines. Overview owns the only vertical scroll axis. The native `Canvas`/`Path` topology is a bounded weighted route map: every active connection and reported chain hop remains present, same names remain distinct across layers, the first column sorts by reported name, and later columns sort by upstream flow-weighted barycenter with name-order tiebreaks. Real edge counts remain in details and place edge anchors through normalized cumulative weights; visible node and route sizes are logarithmic and bounded so aggregates never become screen-sized filled areas. Each edge is one round-capped cubic centerline; default/status/active opacity is 28%/52%/88%, and a selected route gains 1.5 points. Closed or filled Sankey ribbons are prohibited. Column steps use a 168-point minimum and 320-point preferred maximum, so ordinary graphs stay centered while genuinely long chains widen past the panel and scroll horizontally. Hover or pin highlights the complete trajectory in the signal accent; hover and manual pause freeze only presentation. The graph has no nested vertical scroll and remains one focusable surface: direction keys step through complete paths and Escape clears selection. Policy inspection reads the published catalog through a cached bounded index over the O(1) node geometry, so hover, pin, and inspection never rebuild graph structure or shift layout. Path stepping, pin/unpin, clear, and eligible same-window navigation remain available through direct canvas interaction, keyboard, accessible node/path controls, and the single native context menu without becoming permanent toolbar chrome. A mature Swift-native chart package may replace or supplement these tools only when it provides a required capability or measurable performance/maintenance benefit that the system frameworks cannot deliver cleanly, after the repository dependency review in `docs/DEVELOPMENT.md`.
- Topology hit testing prioritizes visible node rails, then visible centerline routes, then bounded label-adjacent pointer padding. Nodes use a local 28-point acquisition size and routes use a 10-point baseline tolerance; targets stay near rendered content and never span the entire gap to the next topology column.
- Current-state aggregates may render as category charts (distribution histograms, share bars, rankings) whose X axis is a category — latency grade, rule type, connection name — never a fabricated timestamp.
- Every chart carries an accessibility label plus a numeric/tabular fallback (`accessibilityValue` or equivalent) so values stay reachable without the visual.
- Aggregate modules show a lightweight localized empty state instead of placeholder data when the controller has not reported values.
- Every icon-only control needs a localized help string and accessibility label. Standalone icon controls use compact 28-point geometry; controls inside rows inherit the row's complete rectangular interaction shape. Selection and disclosure state remain keyboard and VoiceOver reachable.
- Controller row Edit/Delete actions stay at the far trailing edge. Visible glyphs remain compact while help, accessibility labels, and adequate hit regions make Use/Test/Edit/Delete and Move Up/Down reachable.
