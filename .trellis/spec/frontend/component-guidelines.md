# Component Guidelines

> How components are built in this project.

---

## Overview

The Mica UI is SwiftUI. All visual primitives come from the Mica Ops design
system in `Sources/Mica/Design/`: `MicaTheme.swift` (color, typography,
spacing, shape, metrics, and motion tokens) and `MicaThemeComponents.swift`
(the shared components built on those tokens). Feature code never defines its
own colors, fonts, or spacing literals — it composes tokens and shared
primitives.

- Colors: `MicaTheme.canvas` / `surface` / `surfaceRaised` / `separator`, the
  `textPrimary` / `textSecondary` / `textTertiary` ramps, the single `accent`
  (signal teal), and `statusOK` / `statusWarning` / `statusError`. The accent
  marks selection, the active topology path, primary actions, and live
  indicators only; status colors carry controller-reported state only.
- Text: `micaThemeFont(_:weight:)` with a `MicaTheme.TextRole`. Live data
  (latency, rates, IPs, ports, counts, timestamps) uses the SF Mono `data*`
  roles with tabular numerals. No direct view-level `.font(...)` for interface
  text.
- Shape and spacing: `MicaTheme.Spacing` (4-point grid), `MicaTheme.Shape`
  (6-point panels, 10-point window surfaces, 1-point hairline), and
  `MicaTheme.Metrics` (control, command-bar, status-bar, sidebar, inspector,
  form, and page-padding values).
- Motion: `micaStateChangeAnimation(_:value:)` with a `MicaTheme.Motion` token
  (120–200ms ease-out) for state changes only; the modifier already gates on
  Reduce Motion. No idle animation loops.

---

## Component Structure

- Feature views are small `struct ...: View` value types. Leaf views stay
  `private` to their file; cross-file entry points are module-internal.
- Reusable chrome comes from `MicaThemeComponents.swift`: `MicaPanel`,
  `MicaHairlineSeparator`, `MicaMonoMetric`, `MicaStatusDot`,
  `MicaStatusBadge`, `MicaSectionHeader`, `MicaEmptyState`, and the `Workbench*`
  primitives (`WorkbenchPageScaffold`, `WorkbenchCommandBar`,
  `WorkbenchSection`, `WorkbenchStateView`, `WorkbenchStatusBadge`,
  `WorkbenchStaleNotice`, `WorkbenchIconCommand`, `WorkbenchSymbol`, and the
  decision-path/metric-tile family). Management forms use `WorkbenchFormRow`
  (in `WorkbenchManagement.swift`) as the only visible field label.
- Detail reveal goes through the single workspace inspector:
  `WorkbenchInspectorContainer` (in `WorkbenchWorkspaceView.swift`) renders the
  typed `WorkbenchInspectorSelection`; pages register live row resolvers on
  `WorkbenchWorkspaceStore` and call `selectInspector(_:)`. Pages never attach
  their own `.inspector`.
- Pure projection types (no SwiftUI imports) prepare row/section models; views
  consume them verbatim and do not reshape controller data in a body.

---

## Props Conventions

- Props are immutable `let` value types; projections are `Equatable` so SwiftUI
  invalidation stays cheap.
- Actions arrive as closures or capability-gated AppModel calls, never as
  direct mutation of controller collections.
- Optional controller-reported values stay optional end-to-end; views render
  localized unavailable copy instead of fabricating placeholders.

---

## Styling Patterns

- Flat surfaces only: `MicaTheme.canvas` page fill, `surface` panels,
  `surfaceRaised` inspector/popovers, `separator` hairlines. No custom glass,
  glow, decorative gradients, or elevation shadows in content.
- Selection uses a 14% accent fill plus the leading indicator bar in sidebar
  rows, never the saturated system selection block.
- Empty, loading, and unavailable states use `MicaEmptyState` /
  `WorkbenchStateView` with distinct title and description copy.

---

## Accessibility

- Interactive geometry follows the macOS pointer context: row buttons fill
  their row, standalone icon controls use the 28-point `iconControlSize`.
- Icon-only commands carry localized labels and help.
- Color supplements text/symbol meaning; it never carries status alone.
- Reduce Motion renders every surface static; VoiceOver labels are preserved on
  rebuilt controls; contrast follows the token rules (at least 4.5:1 for
  primary text, 3:1 for secondary/large data).

---

## Common Mistakes

- Reintroducing a page-level `.inspector` or a floating detail panel instead of
  routing selection through `WorkbenchWorkspaceStore.selectInspector`.
- Using a raw color literal or the system accent instead of a `MicaTheme`
  token.
- Formatting dates/bytes or assembling search text inside a view body.
- Adding ambient or idle animation instead of a state-change
  `micaStateChangeAnimation`.
