# UI Guidelines

## Design Review

The native macOS/SwiftUI/HIG skills (`macos-app-design`, `apple-hig-expert`, `swiftui-liquid-glass`) are the final authority for all UI work. The `design-taste-frontend` (installed as `taste-skill`) skill contributes only its general anti-slop principles — color, density, layout rhythm, contrast, shape consistency, pre-flight review — because it explicitly scopes itself to landing pages/portfolios, not dashboards, data tables, or multi-step product UI (which is exactly what Mica is). Where its web/landing-page guidance conflicts with native Apple conventions or SparkXie-aligned data clarity, the native rules win. Measurable design claims (contrast, tap-target) are verified with `apple-hig-expert`'s `hig_checker.py`.

## Workbench Structure

- Build the usable controller workbench as the first screen; do not add a marketing or command-home layer.
- Use native sidebar navigation, toolbar search/actions, keyboard commands, SF Symbols, and same-window inspectors.
- Ordinary policy browsing, node selection, latency testing, source inspection, and connection inspection stay inline. Sheets, popovers, context menus, and confirmation dialogs are reserved for platform-required or destructive flows.
- The sidebar contains the eleven functional destinations only. Controller identity and switching live in the toolbar; the complete list lives in Controllers. Row selection manages a controller, while explicit Use changes the active live session. Recent history updates for every explicit controller change and never reorders the saved list.
- Policy groups use fixed staggered columns at wide widths: filter first, then visible indices `0,2,4...` on the left and `1,3,5...` on the right. Never rebalance by height. Narrow widths return to the same flat controller order. `GLOBAL`, when visible, is stable-partitioned last and remains an ordinary card.
- Multiple policy groups may stay expanded. Every group owns its filter, 48-item reveal window, and bounded inner scroll independently. Filtering runs against the complete ordered `group.options` before pagination; group and member content uses semantic solid fills, not per-row Liquid Glass.
- Data tables and inspectors put the primary business field first: name, host, ID, payload, or message before type/status/auxiliary metadata.
- Empty data surfaces use native `ContentUnavailableView` with two distinct levels of copy: a short state title plus a cause or next-step description. Never repeat the same localized sentence as both title and description; distinguish no controller data from no filter matches. Keep headers and command rows at the top, then center the empty state in the remaining content region.
- Connections, logs, rules, and sources use native tables/lists plus on-demand same-window inspectors (`.inspector`, no resident placeholder pane). Search and category filters never reorder the source collection. User-initiated column sorting is allowed through the native table `sortOrder` binding: sorting applies to a presentation-layer projection (`ordered(using:)`) and never mutates the source collection. Old local sort/group/page controls are not part of the rebuilt UI.
- Configuration, Actions, Diagnostics, and Settings use native `Form`, `Section`, and `LabeledContent`. Controller add/edit uses the same-window detail region with toolbar Save, Cancel, and Test actions. Dirty ordinary navigation uses the inline discard bar; dirty main-window close is the destructive exception and uses the native AppKit confirmation. Saving disables every editor-replacement path.
- The Controllers page uses a native SwiftUI `Table` with complete selectable endpoints and a compact trailing action cluster. It switches between seven wide columns and three equivalent composite columns based on real detail width and font scale; compact mode wraps rather than hides fields or adds horizontal scrolling.
- The bottom session bar is always present and fixed-height. It shows controller, unified live state, and last success; while presentation is paused it shows the fixed pause instant instead of a moving network timestamp. Temporary operations replace only the status summary so page height never jumps.
- Test remains available while presentation is paused. Refresh, rule/source reload, and provider update are disabled everywhere through the same AppModel capability. Endpoint failures retain the last successful rows and add a stale marker; never-loaded endpoints alone use an error empty state.

## Visual System

The exact Rose Pine Dawn/Main tokens are:

| Role | Light | Dark |
|---|---|---|
| Background | `#FAF4ED` | `#191724` |
| Grouped background | `#FFFAF3` | `#1F1D2E` |
| Secondary grouped | `#F2E9E1` | `#26233A` |
| Tertiary grouped | `#DFDAD9` | `#403D52` |
| Accent / indigo / purple | `#907AA9` | `#C4A7E7` |
| Blue / green | `#286983` | `#31748F` |
| Cyan / teal | `#56949F` | `#9CCFD8` |
| Orange / yellow | `#EA9D34` | `#F6C177` |
| Red | `#B4637A` | `#EB6F92` |

These are the base tint/fallback tokens. When a semantic color is used as normal-size foreground text or an icon that carries text meaning, `MicaStyle` uses the nearest darker light-mode derivative needed to pass 4.5:1 against the light content background. Do not lighten those derivatives without rerunning `hig_checker.py`; chart marks and decorative graphics still use the same semantic family and must pass 3:1.

Native Liquid Glass/material belongs to windows, sidebars, toolbars, the controller selector, compact actions, and a small number of interactive selectors. Business-data tables, controller rows, policy members, logs, long text, and inspectors use semantic system backgrounds/separators; do not nest cards, use decorative gradients/orbs, or apply glass per row. Follow System, Light, and Dark apply to the entire window without a forced-dark content island.

The overview dashboard is the one place that groups content into cards: KPI tiles, the throughput chart, insight modules, inventory, and endpoint health each sit in a flat `dashboardCard` (system `.regularMaterial` fill + soft separator border). These cards are **material, not glass** — they never use `.glassEffect`/`MicaGlassSelectionSurface`, and they do not nest (a card holds a chart or text rows, never another card). Reduce Transparency falls the material back to an opaque control background. Card titles pair a semantic-color SF Symbol with the localized label; metric values use one shared numeric scale (no per-block font drift).

## Text And Density

- All visible copy comes from `Localizable.xcstrings` in English and Simplified Chinese.
- Font scale affects dynamic type, controls, explicit fonts, sidebar width, and table layout. Do not use unscaled fixed system fonts.
- Controller names and endpoints must wrap or receive enough width; do not middle-truncate or mask them.
- Monospaced styling is reserved for endpoints, IDs, payloads, paths, counters, and protocol values.
- Unknown values use localized not-reported/unavailable wording rather than fabricated zeros, rendered de-emphasized (`.secondary`, smaller than real values) instead of body-weight prose.
- An unconfigured controller target says `Not configured` / `尚未配置`; it never renders a placeholder endpoint such as `http://-:9090`. IPv6 endpoints use bracketed host notation.
- Density target: collapsed policy rows stay compact enough for a 63-group controller to show at least 15 groups on a 1920×1080 window; expanded members keep a 44-point minimum interaction target.

## Charts And Accessibility

- Time-series charts require a real bounded time series (the received-sample `TrafficTimeline`); never fabricate, extend, or synthesize a time axis, and never interpolate snapshot-only data into a series.
- Current-state aggregates may render as category charts (distribution histograms, share bars, rankings) whose X axis is a category — latency grade, rule type, connection name — never a fabricated timestamp.
- Every chart carries an accessibility label plus a numeric/tabular fallback (`accessibilityValue` or equivalent) so values stay reachable without the visual.
- Aggregate modules show a lightweight localized empty state instead of placeholder data when the controller has not reported values.
- Every icon-only control needs a localized help string, accessibility label, and at least a 44-point hit region even when the visible glyph remains compact; selection and disclosure state must remain keyboard and VoiceOver reachable.
- Controller table actions stay in the far-right Actions column. Visible glyphs remain compact while help, accessibility labels, and adequate hit regions make Use/Test/Edit/Delete and Move Up/Down reachable.
