# UI Guidelines

## Design Review

The native macOS/SwiftUI/HIG skills (`macos-app-design`, `apple-hig-expert`, `swiftui-liquid-glass`) are the final authority for UI work. Follow the existing Workbench contract and verify measurable contrast and hit-target claims with `apple-hig-expert`'s `hig_checker.py`.

## Workbench Structure

- Build the usable controller workbench as the first screen; do not add a marketing or command-home layer.
- Use native sidebar navigation, toolbar search/actions, keyboard commands, SF Symbols, and same-window inspectors.
- Ordinary policy browsing, node selection, latency testing, source inspection, and connection inspection stay inline. Sheets, popovers, context menus, and confirmation dialogs are reserved for platform-required or destructive flows.
- The sidebar starts with a collapsed inline controller switcher above the ten destinations. It expands in place to show controllers in persisted order plus Add and Manage actions; the complete management view stays in Controllers. Application preferences appear only in the native Settings scene opened from the app menu, never as a duplicate sidebar destination. Do not repeat controller identity in the toolbar or cover the native navigation title with a custom capsule. Keep the inline switcher in an observation boundary that reads only profiles, selected ID, and displayed controller fields so traffic, log, memory, and connection frames cannot churn it. Row selection on Controllers manages a profile, while explicit Use or a quick-switch row changes the active live session. Recent history updates for every explicit controller change and never reorders the saved list.
- Policy groups use one bounded, controller-ordered vertical workspace with a single scroll owner. Each group has a compact identity/current-selection header, a real latency distribution, and an inline disclosure. Mihomo ordinary groups follow matching names in `GLOBAL.all`, then unlisted groups in `/proxies` order; Surge and sing-box preserve their reported sequence. Filtering and interaction never reorder the result, and visible `GLOBAL` stays last. Group members preserve each group's reported order.
- Multiple groups may stay expanded. Build and cache member indexes only for expanded groups, with independent filters and inspected-member state; prune indexes when groups close. Closing the active group prefers the next open source-order group, then the previous group.
- Expanded members use one source-ordered adaptive grid with at most three readable columns at regular width, then two or one as space contracts. Default cells have no permanent outline; a leading state rail and restrained hover, inspected, and current-node treatments provide hierarchy. Tiles show only reported name, type, transport, source, SMART usage, availability, latency, and current-selection state. The tile body inspects and invokes the existing capability-gated switch action; testing is separate and visually secondary.
- Node details stay below their owning group as one flat adaptive information shelf and close without mutating controller selection. Overview, transport, and testing use labeled key-value columns rather than nested cards or a field wall. Known fields are human-labeled and never repeated as additional fields; uncategorized controller fields remain folded by default and selectable one by one.
- The policy page reads `PolicyGroupCatalogSnapshot`, which changes only with mode or group data. High-frequency traffic, connection, provider, rule, and log updates must not force policy headers or expanded-group projections to recompute during scrolling.
- The selected-node detail groups overview, reported transport states, testing/latency, and additional controller fields. Arrays and objects use deterministic compact JSON. Generate complete additional-field rows only for the selected node, not for the whole catalog.
- Data tables and inspectors put the primary business field first: name, host, ID, payload, or message before type/status/auxiliary metadata.
- Empty data surfaces use native `ContentUnavailableView` with two distinct levels of copy: a short state title plus a cause or next-step description. Never repeat the same localized sentence as both title and description; distinguish no controller data from no filter matches. Keep headers and command rows at the top, then center the empty state in the remaining content region.
- Connections, logs, rules, and sources each construct one native `Table` plus an on-demand same-window inspector (`.inspector`, no resident placeholder pane). A root-level width mode conditionally supplies typed, composite, or stacked columns without constructing parallel Table trees; no mode drops a business field. Connections adds one compact current-result pulse above its Table and a complete selected route path; closed rows show historical totals rather than live rates, and additional objects/arrays disclose as structured fields rather than machine JSON paragraphs. Scan rows keep fixed single-line geometry, while complete wrapped/selectable values remain in the inspector. Search and category filters never reorder the source collection. User-initiated column sorting applies only to a presentation copy and never mutates source order. Logs remain source ordered: selecting a row or manually scrolling disables Follow Newest, rapid automatic scroll requests are coalesced, and Jump to Newest restores following.
- Rule scan rows treat payload plus type/index as one definition, then show
  route, activity, and state. State uses a quiet dot-and-text label; mutable
  enable/disable is part of the state cell rather than an isolated action
  button column. Compact mode combines route, activity, state, and action;
  stacked mode keeps one complete composite column.
- A selected rule adds one compact `type → payload → target policy` focus path
  above the Table. Only an exact case-sensitive visible policy-group target is
  a navigation action; DIRECT, REJECT, node names, and unknown targets remain
  plain reported values.
- Management pages use one bounded content column. Controllers detail,
  Configuration, Actions, controller add/edit, and the native Settings scene use
  grouped `Form` sections; Diagnostics uses adaptive elevated rows on the shared
  page fill, never the system white disclosure background.
  Diagnostic disclosure headers are full-width buttons with animated chevrons
  and lightweight opacity transitions. Expanded content uses ordinary stacks
  so scrolling remains smooth. Unsupported controller capabilities are removed
  at both the section and nested-row levels.
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
- The Controllers page uses a native persisted-order `List` plus a same-window
  grouped-form detail. Wide layouts use `HSplitView`; compact layouts use
  `VSplitView`. Each row shows the complete selectable endpoint and keeps compact
  Edit/Delete commands at the far trailing edge; explicit Use in the detail
  region changes the active controller. Actions uses the same grouped-form
  section rhythm and trailing titled commands, but capability gating still hides
  unsupported operations rather than showing disabled placeholders.
- The bottom session bar is always present with a stable, unscaled native minimum height. It shows controller, unified live state, and last success; while presentation is paused it shows the fixed pause instant instead of a moving network timestamp. Temporary operations replace only the status summary, and larger Dynamic Type reflows through the provided variants instead of multiplying bar geometry.
- Test remains available while presentation is paused. Refresh, rule/source reload, and provider update are disabled everywhere through the same AppModel capability. Endpoint failures retain the last successful rows and add a stale marker; never-loaded endpoints alone use an error empty state.

## Visual System

The exact adaptive Midnight Instrument tokens are (dark-first "墨蓝黑" with a
light "实验室白" counterpart):

| Role | Light | Dark |
|---|---|---|
| Background | `#E7E9F2` | `#0E0F1A` |
| Content | `#FBFBFE` | `#161827` |
| Elevated content | `#DEE1EE` | `#1E2133` |
| Tertiary content | `#D9DCE9` | `#2A2E45` |
| Accent (电感靛蓝) | `#4F5BD5` | `#8B93FF` |
| Cyan (信息) | `#1E7A93` | `#6FD3E7` |
| Green / mint (成功) | `#2E7D54` | `#7FD4A8` |
| Orange / amber (警告) | `#9A6410` | `#F2BE6E` |
| Red (错误) | `#B23A52` | `#F28B9E` |
| Violet (debug/trace) | `#6C4FD1` | `#B79CFF` |

These values are fixed, not starting points for derived palettes. The workbench canvas and opaque content layers use the exact surface pairs. Electric indigo owns navigation selection/focus and the 2-point selection glow rail, cyan owns informational/live data, mint healthy state, amber warnings, red failures/destructive state, and violet debug/trace separation; the four signal hues stay at least 30 degrees away from the accent so color never carries meaning alone. A soft accent fill (`accentSoft`, accent at 12%/16% over the surface) backs navigation and table-row selection. Normal text, status text, and text-bearing icons use system `primary`/`secondary` foreground styles. Any new color role still requires `hig_checker.py` verification.

Numeric values (KPIs, rates, timestamps, byte counts, endpoints) use monospaced-digit or SF Mono styling so live refreshes never shift layout horizontally. Motion primitives in `WorkbenchMotion` animate only value or structural changes - never scroll position or high-frequency row layout - and degrade to static equivalents under Reduce Motion.

Sidebar destinations remain in a native virtualized `List`, but each row is a
native `Button` with its own restrained selection treatment: a 14% accent fill,
three-point leading indicator, monochrome symbol, and primary text. Row height
is content-driven from the callout label and compact vertical padding. The
button label occupies the complete list-row width and declares a rectangular
interaction shape, so trailing whitespace remains clickable without imposing a
mobile touch-target height. Do not restore a saturated full-row system
selection block.

Native system materials belong to windows, sidebars, toolbars, the controller selector, and standard controls. The window container, native toolbar, command bars, management canvas, and loading/empty states share one adaptive page fill so every destination keeps a continuous title-bar color. Do not add custom `.glassEffect` content surfaces. Business-data tables, controller rows, policy selectors/members, logs, long text, and inspectors use opaque semantic backgrounds/separators; do not nest cards or use decorative gradients/orbs. Follow System, Light, and Dark apply to the entire window without a forced-dark content island. The custom top-level Controller menu follows the macOS menu language; its commands follow Mica's selected interface language.

Management pages use a centered responsive canvas rather than a fixed-width block anchored to the leading edge. The canvas grows to an 1180-point reading limit and form-heavy pages grow to 1040 points. The standalone native Settings window uses one centered grouped `Form` up to 820 points; it has no duplicate Workbench route, repeated title, or unbalanced category column. Data tables, timelines, topology, policy workspaces, and logs remain width-filling because their scan and interaction density benefits from the available canvas.

Overview does not repeat the selected-controller/session header. Its default layout contains three equal-weight real-time charts for upload, download, and active connections, followed by the complete active route topology and grouped network information. Wide layouts use three chart columns, medium layouts use two traffic columns plus a full connection row, and narrow layouts stack all three. Every chart shares real timestamps, hover/single-click pin selection, keyboard stepping, pause, and return-to-live; memory is contextual metadata on the connection chart rather than a fourth plot. Zero-value and one-sample timelines remain visible through a presentation-only padded scale and a latest-real-sample point; this never fabricates samples. The instrument rail and operational summaries remain optional personalization modules but are hidden by default. The complete topology is always a full-row module. Overview does not contain retained closed data, a raw connection selector, or the full connection inspector. Reset removes the controller override and keeps inheriting the latest global default; edits remain window-local until a persistence-first Done transaction succeeds.

Workbench views observe `controllerSessionPresentation`, `controllerMetadata`, and domain catalogs instead of the broad `controllerSession` or `dashboard` aggregates. Each window root registers one stable destination-demand token; the selected generation publishes the union required by all windows through one runtime. Logs/traffic/connections/memory publish at 5/4/2/1 Hz and hidden domains flush once on entry when pause/baseline gates permit. Timeline updates stay inside the telemetry subtree; they do not rebuild sidebar switching, configuration, policy/rule projections, network facts, or topology. Render zero byte values deterministically as `0 B` / `0 B/s`, not locale text such as `Zero KB`.

## Text And Density

- All visible copy comes from `Localizable.xcstrings` in English and Simplified Chinese.
- Font scale changes visible Mica text through one semantic `micaFont` ladder using multipliers `0.92`, `1.0`, `1.16`, and `1.32`; `dynamicTypeSize` remains a native-control fallback. Management rows change between horizontal and stacked layouts only from actual available width, never from the selected font step. Sidebar width, status height, interaction targets, margins, and table breakpoints stay bounded and are never multiplied by text scale. Do not add direct view-level `.font(...)` calls for interface text; use `micaFont` so every destination responds immediately.
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
- System Swift Charts implements the received timelines. Overview owns the only scroll axis. The native `Canvas`/`Path` topology is a width-fitted Sankey: every active connection and reported chain hop remains present, same names remain distinct across layers, nodes sort by reported name, real edge counts drive detail text, and `log10(count + 1) * 10` drives ribbon width. Hover or pin highlights the complete trajectory; hover and manual pause freeze only presentation. The graph has no internal scroll, supports same-window expansion and Connections navigation, and exposes every route through an accessible fallback. A mature Swift-native chart package may replace or supplement these tools only when it provides a required capability or measurable performance/maintenance benefit that the system frameworks cannot deliver cleanly, after the repository dependency review in `docs/DEVELOPMENT.md`.
- Topology hit testing prioritizes visible node bars, then visible ribbons, then bounded label-adjacent pointer padding. Nodes use a local 28-point acquisition size and ribbons use a 10-point baseline tolerance; targets stay near rendered content and never span the entire gap to the next Sankey column.
- Current-state aggregates may render as category charts (distribution histograms, share bars, rankings) whose X axis is a category — latency grade, rule type, connection name — never a fabricated timestamp.
- Every chart carries an accessibility label plus a numeric/tabular fallback (`accessibilityValue` or equivalent) so values stay reachable without the visual.
- Aggregate modules show a lightweight localized empty state instead of placeholder data when the controller has not reported values.
- Every icon-only control needs a localized help string and accessibility label. Standalone icon controls use compact 28-point geometry; controls inside rows inherit the row's complete rectangular interaction shape. Selection and disclosure state remain keyboard and VoiceOver reachable.
- Controller row Edit/Delete actions stay at the far trailing edge. Visible glyphs remain compact while help, accessibility labels, and adequate hit regions make Use/Test/Edit/Delete and Move Up/Down reachable.
