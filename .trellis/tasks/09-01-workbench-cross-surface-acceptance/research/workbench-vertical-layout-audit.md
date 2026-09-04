# Research: Workbench Vertical Layout Audit

- Query: Audit every Workbench surface for content-light chrome, supplementary rails, or empty states that can absorb remaining window height; identify the Connections pulse-strip root cause and determine whether the shared scaffold fix is sufficient.
- Scope: internal
- Date: 2026-09-02

## Findings

### Root cause and retained fix

The user screenshot is a real layout defect, not intentional whitespace. The
Connections page places `WorkbenchConnectionPulseStrip` in the data-browser
`supplementary` region (`Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift:33`,
`:36`, `:38`). Its regular horizontal composition contains an unconstrained
vertical `Divider` (`Sources/Mica/Features/Workbench/WorkbenchConnectionPulseView.swift:23`,
`:28`) and the strip itself constrains only width (`:10`, `:17`). In the HEAD
baseline, `WorkbenchPageScaffold` put the commands subtree and an infinitely
flexible content subtree in the same `VStack` without declaring which child
owned remaining height. The divider therefore made the supplementary subtree
vertically flexible, allowing it to share the page remainder and producing the
large blank strip shown in the 3433x874 screenshot.

The pending shared worktree fix is correctly placed at the ownership boundary:

- `WorkbenchPageScaffold` now keeps the complete commands/status/supplementary
  subtree at intrinsic height with
  `.fixedSize(horizontal: false, vertical: true)`
  (`Sources/Mica/Design/MicaThemeComponents.swift:438-443`).
- The main page content is the sole flexible-height child via
  `.layoutPriority(1)` (`Sources/Mica/Design/MicaThemeComponents.swift:444-447`).
- The source verifier locks both invariants
  (`scripts/verify-real-controller-source.mjs:899-913`).

This shared fix is sufficient for the reported defect and is preferable to a
hard pulse height. It preserves width-driven `ViewThatFits` fallback and lets
English, Simplified Chinese, narrow windows, and Extra Large text grow only by
their real intrinsic content height. A fixed numerical height would risk
clipping those valid compact compositions.

### Complete `WorkbenchPageScaffold` caller audit

| Surface | Caller and height ownership | Result |
| --- | --- | --- |
| Overview | `WorkbenchDashboard.swift:9-16`; optional preferences chrome is intrinsic, while the canvas owns a `GeometryReader` plus the sole vertical `ScrollView` at `:109-154`. | Covered by shared fix; no analogous defect. |
| Proxies | `WorkbenchProxies.swift:76-86`; command bar/stale notice are chrome, while the proxy workspace or full-page state owns the remainder at `:165-279`. | Covered; no flexible supplementary child. |
| Connections | Via `WorkbenchDataBrowserScaffold`; pulse, selected path rail, and inline confirmation are supplementary (`WorkbenchConnectionsView.swift:33-83`). | Reported defect; fixed by shared scaffold. |
| Logs | Via `WorkbenchDataBrowserScaffold` with `EmptyView` supplementary (`WorkbenchLogs.swift:41-48`). | Covered; no supplementary expansion path. |
| Rules | Via `WorkbenchDataBrowserScaffold`; the three-step selected-rule rail is conditional (`WorkbenchRules.swift:30-49`). | Covered; rail is intrinsic and bounded by its content. |
| Sources | Via `WorkbenchDataBrowserScaffold`; update-all progress and selected-source rail are conditional (`WorkbenchSources.swift:27-56`). Failure details have a deliberate 112-point cap (`WorkbenchSourceDetails.swift:211-229`). | Covered; no unbounded blank-height child. |
| Controllers | `WorkbenchControllers.swift:103-125`; command bar is intrinsic and `List`/full-page state owns the remainder. | Covered; no analogous defect. |
| Configuration | `WorkbenchConfiguration.swift:11-16`; command bar is intrinsic and the grouped form or full-page state owns the remainder (`:48-114`). | Covered; no analogous defect. |
| Actions | `WorkbenchActions.swift:33-40`; both recovery and command canvases use top-leading content in the main-region `GeometryReader`/`ScrollView` (`:131-151`, `:343-376`). | Covered; unused space is outside the bounded canvas, not inside stretched chrome. |
| Diagnostics | `WorkbenchDiagnostics.swift:18-25`; the main diagnostics canvas owns its `GeometryReader`/`ScrollView` (`WorkbenchDiagnosticsComponents.swift:30-54`). | Covered; no analogous defect. |

`WorkbenchDataBrowserScaffold` is the only shared supplementary composition
(`Sources/Mica/Features/Workbench/WorkbenchDataShared.swift:181-215`). It keeps
command bar, stale notice, and supplementary views in the scaffold's commands
subtree, so the one boundary fix covers Connections, Logs, Rules, and Sources
without four page-local patches.

### Other flexible-layout patterns checked

- Every Workbench `ViewThatFits(in: .horizontal)` was inspected. The command
  bar, command summary, selected-rule/source/connection rails, confirmations,
  Overview controls, Actions rows, Diagnostics rows, Tailscale rows, and status
  bar contain only intrinsic views or explicitly bounded children. The pulse
  strip's regular vertical divider is the only such candidate on a scaffold
  chrome path that can advertise flexible height.
- Every Workbench `GeometryReader` was inspected. They either own the main
  content region (Overview, Tables, management forms, Actions, Diagnostics,
  Settings) or are explicitly height-bounded visual internals: the connection
  owner bar is 5 points (`WorkbenchConnectionPulseView.swift:295-328`) and the
  proxy latency bar is 4 points (`WorkbenchProxyGroupPanels.swift:405-427`).
- The remaining `maxHeight: .infinity` uses are intentional main-region owners:
  page content, native Tables, grouped Forms, inspector content, and chart plot
  placeholders. `WorkbenchStateView` deliberately replaces and centers within
  the remaining content region (`MicaThemeComponents.swift:757-823`); it is not
  supplementary chrome. The inspector's `MicaEmptyState` is similarly a
  dedicated empty inspector composition (`WorkbenchWorkspaceView.swift:113-145`,
  `:226-231`). Applying the scaffold's fixed-size rule to either would break
  the explicit centered-state contract.
- Vertical dividers in Overview summary columns, Actions command columns, and
  Diagnostics master-detail sit inside scroll content and correctly match the
  intrinsic height of neighboring content. Overview telemetry separators are
  paired with stable chart geometry, and compact instrument/status separators
  already have explicit heights (`WorkbenchOverviewTelemetry.swift:17-29`,
  `:211-284`; `WorkbenchStatusBar.swift:347-350`). They do not participate in
  top-chrome height allocation.

No second accidental blank-height expansion was found.

### Recommended verification

1. Keep the shared scaffold fix and verifier assertions; do not add a fixed
   pulse-strip height or duplicate page-local constraints.
2. Runtime visual acceptance should exercise Connections at an ultrawide/short
   window matching the screenshot, then at compact width, with no selection and
   with the decision rail visible. The Table must receive all height remaining
   after intrinsic command/supplementary content.
3. Spot-check Rules and Sources with a selected row, Sources update progress,
   stale notice, and an inline Connections confirmation. These are every
   conditional supplementary composition that passes through the same boundary.
4. Repeat standard and Extra Large text in English and Simplified Chinese. The
   acceptance invariant is content-driven height, not one numeric maximum.

## Files Found

- `Sources/Mica/Design/MicaThemeComponents.swift` - owns the shared page scaffold and full-page state behavior.
- `Sources/Mica/Features/Workbench/WorkbenchDataShared.swift` - owns the four data-browser command/supplementary composition.
- `Sources/Mica/Features/Workbench/WorkbenchConnectionPulseView.swift` - contains the pulse regular/compact layouts and triggering vertical divider.
- `Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift` - mounts every Connections supplementary strip/rail/confirmation.
- `Sources/Mica/Features/Workbench/WorkbenchLogs.swift` - data-browser caller with no supplementary content.
- `Sources/Mica/Features/Workbench/WorkbenchRules.swift` and `WorkbenchRuleDetails.swift` - conditional selected-rule rail.
- `Sources/Mica/Features/Workbench/WorkbenchSources.swift` and `WorkbenchSourceDetails.swift` - bounded progress and selected-source rail.
- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift`, `WorkbenchProxies.swift`, `WorkbenchControllers.swift`, `WorkbenchConfiguration.swift`, `WorkbenchActions.swift`, and `WorkbenchDiagnostics.swift` - all remaining direct scaffold callers.
- `scripts/verify-real-controller-source.mjs` - static regression contract for intrinsic chrome and flexible main content.

## Related Specs

- `.trellis/spec/frontend/workbench-ui-contract.md:1228` - Connections owns one compact pulse strip above the native Table.
- `.trellis/spec/frontend/workbench-ui-contract.md:1272` - top command areas stay stable; only full-page unavailable states center in the remaining region.
- `.trellis/spec/frontend/workbench-ui-contract.md:1302` - management content stays in a leading-anchored bounded column.
- `.trellis/spec/frontend/component-guidelines.md:35-49` - shared Workbench primitives and archetype-specific composition are authoritative.
- `.trellis/tasks/09-01-workbench-cross-surface-acceptance/prd.md` R2 / AC1 - wide, narrow, and short windows must not produce significantly imbalanced blank space.

## External References

No external browsing was required. The local `macos-app-design` guidance was
used for fluid window resizing and content-height chrome; the local
`apple-hig-expert` and `swiftui-liquid-glass` guidance confirms that hierarchy
must come from layout and native content structure rather than decorative or
stretched content surfaces.

## Caveats / Not Found

- Per dispatch constraints, this research did not launch Mica, contact a
  controller, or run runtime visual smoke. Final pixel/frame confirmation must
  use the already-authorized read-only acceptance path in the main session.
- A very long selected connection path can legitimately become tall in the
  narrow vertical fallback (`WorkbenchConnectionDetails.swift:22-80`). That is
  real content rather than blank expansion and is not the screenshot's defect;
  change it only if a separate runtime screenshot shows the Table workflow is
  being crowded out.
- The worktree changed concurrently while this audit ran. The root-cause
  comparison uses the committed HEAD baseline; the shared scaffold fix and
  verifier assertions cited above are the current pending implementation.
