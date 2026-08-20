# Design — 全局 UI 设计系统与界面重构 ("Mica Ops")

## 1. Direction

**Mica Ops**: a precision network-operations console. The product is a
monitoring/operations tool, so the design language is instrument-grade:
quiet neutral canvas, data-dense monospaced metrics, one restrained accent,
flat bordered panels, and motion only when data moves.

Deliberate departures from both previous directions:

| Aspect | v1 native (08-04) | Cyber-neon (08-16) | Mica Ops (this task) |
|---|---|---|---|
| Canvas | system materials | blue-tinted dark + glow | neutral near-black / clean light |
| Accent | system blue | cyan + violet, bloom | single signal teal, no glow |
| Data type | proportional fonts | styled numerals | SF Mono for all live data |
| Surfaces | cards on material | layered glass + bloom | flat panels, 1px separators |
| Detail reveal | sheets / panels | floating hover HUD | right-side inspector |
| Idle motion | some | bounded loops | none (data-driven only) |

Anti-goals (explicitly rejected): neon glow/bloom, decorative gradients,
card-in-card nesting, floating HUD panels inside content, custom glass
materials in content areas, idle/ambient animation, fabricated or decorative
charts.

## 2. Design Tokens (`Sources/Mica/Design/MicaTheme.swift`)

One consolidated namespace `MicaTheme` replaces `MicaDesignTokens`,
`MicaStyle`, `WorkbenchDesignSystem.swift`, `WorkbenchVisualSystem.swift`,
and `WorkbenchOverviewVisualSystem.swift`. Shared SwiftUI primitives live in
`Sources/Mica/Design/MicaThemeComponents.swift`.

### Color (semantic, dark + light via dynamic provider)

| Token | Dark | Light | Usage |
|---|---|---|---|
| `canvas` | #0D0E10 | #FFFFFF | window background |
| `surface` | #15171A | #F5F6F7 | panels, sidebar selections |
| `surfaceRaised` | #1C1F23 | #FFFFFF | inspector, popovers |
| `separator` | #2A2D32 (opaque) | #D9DBDF | hairlines only |
| `textPrimary/Secondary/Tertiary` | system-compatible ramps | same | labels and values |
| `accent` (signal teal) | #34D1A3 | #0B8F66 | selection, active path, primary action, live indicator ONLY |
| `statusOK/Warning/Error` | system green/orange/red | same | controller-reported status ONLY |

Rules: accent never decorates; status colors never brand. Text contrast
≥ 4.5:1 (primary) and ≥ 3:1 (secondary/large data). Dynamic colors are
created in code through a `Color(micaLight:dark:)` helper — no asset catalog.

### Typography

- UI labels: SF Pro, scale 11/12/13/15/17 semibold titles, 22/28 hero values.
- All live data (latency, rates, IPs, ports, counts, timestamps): SF Mono
  via `Font.monospacedSystem`, tabular numerals everywhere.
- Density-first: default row heights 22–28pt in data lists; no hero empty
  space.

### Shape, spacing, materials, motion

- 4pt spacing grid (4/8/12/16/24). Panel padding 12–16.
- Corners: 6pt panels / 10pt window-level surfaces. No shadows in dark mode;
  hairline separators instead of elevation.
- Materials: system `.sidebar` material in the sidebar and system toolbar
  only (native Liquid Glass chrome). Content surfaces are flat color fills —
  no custom glass, no blur stacks.
- Motion: 120–200ms ease-out for state changes only. No idle loops. Reduce
  Motion, paused stream, and inactive window render fully static.

## 3. Window Chrome and Information Architecture

Single workbench window (unchanged scene model in `MicaApp`), rebuilt as:

- **Sidebar** (native `NavigationSplitView`, system material): three groups
  replacing the current two —
  - **Operate**: Overview, Proxies, Connections, Rules
  - **Observe**: Logs, Sources, Diagnostics
  - **Manage**: Controllers, Configuration, Actions
  - Existing keyboard shortcuts (⌘1…⌘0) are preserved per destination.
- **Toolbar**: controller picker + session state + primary contextual
  actions; native toolbar, no custom chrome.
- **Status bar**: retained concept (session, stream, controller health),
  restyled as a 1px-separated hairline bar with mono metrics.
- **Inspector** (right side, collapsible): the single detail-reveal
  mechanism for the whole app. Selecting a proxy group/node, connection,
  rule, source, or controller shows its complete controller-reported fields
  here. Hover shows a standard tooltip only.
  **The floating policy HUD (`WorkbenchOverviewPolicyHUD.swift`) is removed.**
- **Settings**: native grouped `Form` scene, themed; no custom window.

## 4. Surface Direction (behavior preserved, presentation rebuilt)

- **Overview**: two fixed regions — the telemetry instrument stage above the
  route topology. The three real-data charts (upload/download/connections)
  and their interactions (selection, cursor, pin, pause, timeline window)
  are **preserved product behavior**; they are restyled as flat instrument
  panels — mono current-value readouts, hairline separators, no glow. The
  existing topology geometry/cache/hit-testing engine
  (`WorkbenchOverviewTopology.swift`, ~1.5k lines) is **retained**; only its
  rendering layer (`WorkbenchOverviewTopologyView.swift`) is rewritten:
  flat strokes, accent on the active/selected path, status colors on nodes.
  Selection opens the inspector; the customizable-optional-modules model in
  `WorkbenchOverviewPreferences.swift` is kept (it is product behavior).
- **Proxies**: group sections with dense node grid/list; mono latency badges
  colored by status thresholds; capability-gated actions unchanged.
- **Connections / Rules / Logs**: table-style dense rows, monospaced data
  columns, hairline separators, filter bars; existing caches and interaction
  stores retained.
- **Sources / Diagnostics**: status-list presentations with semantic colors.
- **Controllers / Configuration / Actions**: list + detail via inspector;
  form-style configuration; grouped action lists with existing confirmation
  and capability gates.
- **Routers feature**: themed to match (tokens, typography, panel language);
  no functional change.

## 5. Engineering Plan and Boundaries

Kept (not redesign targets): all of `Sources/MicaCore`; AppModel and
live-session logic; topology geometry engine; telemetry projections;
workspace/navigation stores; localization infrastructure; capability gating.

Replaced: the three old design-system files + `MicaStyle`/`MicaDesignTokens`
references across all surfaces; the policy HUD; neon-specific rendering.

Migration strategy: introduce `MicaTheme` alongside the old system, migrate
surface-by-surface with a compiling-green build at each step, delete the old
system last, then rewrite the frontend spec docs. Heavy neon-coupled views
(Overview visuals, HUD) are rewritten rather than patched.

Localization: every new/changed visible string lands in
`Localizable.xcstrings` in English + Simplified Chinese.

Accessibility: Reduce Motion honored everywhere; VoiceOver labels preserved
on rebuilt controls; keyboard navigation preserved; contrast per token rules.

## 6. Compatibility and Rollback

- Baseline checkpoint: commit `ebae3be` (pre-redesign baseline). Full
  rollback = revert to this commit.
- No persistence-format changes are planned; Overview preferences storage
  keeps its current v1 schema (restyle only). If any key must change, it is
  called out in implement.md before the change lands.
- Swift 6.2 / macOS 27 targets unchanged. No new packages.
- Out of scope per prd.md: MicaCore API changes, new product features.

## 7. Trade-offs

- Keeping the topology engine sacrifices "everything is new" purity for a
  verified, expensive component; its look still changes completely.
- The inspector replaces the HUD: loses the "holographic" flourish, gains a
  standard, keyboard/VoiceOver-friendly, consistent detail mechanism.
- Single accent + flat surfaces is less immediately flashy than neon, but
  reads faster for operations data and ages better; it also sharply reduces
  the custom-rendering surface area (maintenance + performance).
