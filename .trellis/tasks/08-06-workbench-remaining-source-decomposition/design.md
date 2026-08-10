# Workbench 剩余源码职责拆分设计

## 1. Design Principle

本任务按“谁拥有状态、谁决定数据、谁负责呈现、谁独立变化”拆分，而不是按文件长度拆分。现有运行路径保持不变：

`generation-owned AppModel state -> pure projection/cache -> Workbench root View -> leaf View -> capability-gated AppModel intent`

不新增 view model、environment dependency 或 package，不改变 projection 输入输出，也不重新定义页面导航和状态所有权。

## 2. Target Ownership

### 2.1 Shell and shared layers

| File | Ownership |
|---|---|
| `WorkbenchChrome.swift` | `WorkbenchDestination`、Workbench 根组合、app lifecycle observer。 |
| `WorkbenchWindow.swift` | `ContentView`、editor presentation/intents、replacement decision bar。 |
| `WorkbenchSidebar.swift` | sidebar View 与 rows。 |
| `WorkbenchStatusBar.swift` | session control、operation outcome presentation、bottom/status chrome。 |
| `WorkbenchDesignSystem.swift` | `MicaStyle`、颜色/spacing/bounds/typography token、font/motion/modifier。 |
| `WorkbenchVisualSystem.swift` | 通用 SwiftUI primitives、page scaffold、empty/loading/error 状态。 |
| `WorkbenchDataInteraction.swift` | width/responsive、scroll coordinator、viewport 与 performance modifier。 |
| `WorkbenchDataShared.swift` | 通用 browser/inspector SwiftUI primitives。 |
| `WorkbenchDataPresentation.swift` | data state/resolver、inspector values/projection、formatting、stable identity、selection。 |

### 2.2 Data pages

| Family | Root / page | Presentation and cache | Detail / specialized View |
|---|---|---|---|
| Connections | `WorkbenchConnections.swift`, `WorkbenchConnectionsView.swift`, `WorkbenchConnectionDetails.swift` | `WorkbenchConnectionCache.swift` owns reported metrics, pulse projection/cache and sort cadence | `WorkbenchConnectionPulseView.swift` owns pulse strip, metric and owner distribution Views |
| Logs | `WorkbenchLogs.swift` owns table and inspector composition | `WorkbenchLogPresentation.swift` owns severity/row/projection/cache/follow cadence | Appearance-only severity tint remains beside the SwiftUI View |
| Rules | `WorkbenchRules.swift` owns the root table | `WorkbenchRulePresentation.swift` owns row/index/cache/projection/navigation/decision models | `WorkbenchRuleDetails.swift` owns decision rail and inspector |
| Sources | `WorkbenchSources.swift` owns the root table | `WorkbenchSourcePresentation.swift` owns row/projection/focus/cache | `WorkbenchSourceDetails.swift` owns focus rail, update-all progress and inspector |

Connections keeps the existing split between projection/intents, table workspace and connection details. Only pulse cache and pulse View islands move; this avoids rewriting current cross-file contracts.

### 2.3 Management pages

| File | Ownership |
|---|---|
| `WorkbenchActions.swift` | confirmation/projection and general actions root. |
| `WorkbenchTailscale.swift` | sing-box Tailscale section, endpoint and peer Views. |
| `WorkbenchControllerPresentation.swift` | delete/list/connection-test pure projections. |
| `WorkbenchControllers.swift` | view-specific controller status, root and test report Views. |
| `WorkbenchDiagnosticsPresentation.swift` | diagnostic fields/projection/support/visibility rules. |
| `WorkbenchDiagnostics.swift` | diagnostics root composition. |
| `WorkbenchDiagnosticsComponents.swift` | shared/detail diagnostics SwiftUI components. |

`WorkbenchManagement.swift` continues to own only shared management destination/projection definitions. Configuration and Settings remain untouched.

### 2.4 Overview personalization

| File | Ownership |
|---|---|
| `WorkbenchOverviewPersonalization.swift` | layout/configuration/normalizer/preset/row packer/effective model. |
| `WorkbenchOverviewLayoutStore.swift` | persistence client/envelope, typed mutations and store. |
| `WorkbenchOverviewWindowCoordinator.swift` | conflict models, window coordinator and draft state. |

Dashboard, Editor, Projection, Runtimes, Telemetry, Topology and TopologyView remain unchanged because their current filenames already describe coherent ownership.

## 3. Intentionally Unsplit Files

- `WorkbenchWorkspaceStore.swift` remains one per-window workspace/persistence owner. Extracting its private envelopes would widen access without creating a separately reusable contract.
- `WorkbenchConfiguration.swift`, `WorkbenchSettings.swift` and `WorkbenchControllerSelector.swift` are already bounded page components.
- `WorkbenchOverviewTelemetry.swift`, `WorkbenchOverviewTopology.swift` and `WorkbenchOverviewTopologyView.swift` are large but cohesive chart/topology implementations.
- Proxies keeps the just-completed four-file boundary. Proxy panels and presentation are not recursively split.

This explicit exclusion is part of the design: a line-count-only decomposition would trade one maintenance problem for cross-file coupling and file sprawl.

## 4. Mechanical Migration And Access

1. Move complete top-level declaration blocks using stable type markers; do not reformat or reorder implementation bodies unless the compiler requires an import/access fix.
2. Start every new file with only the imports required by its declarations. Pure presentation/cache owners should use `Foundation` and `MicaCore` when possible.
3. Move SwiftUI-only computed appearance, such as severity tint, into a private extension beside its consuming View so pure presentation files do not import SwiftUI.
4. Promote only declarations referenced across the new file boundary from `private`/`fileprivate` to module-internal. Keep leaf components, cache keys and local helpers private.
5. If a file-private helper has multiple consumers, give the existing implementation one feature-specific module-internal owner. Do not duplicate it.
6. Preserve declaration names and signatures so tests and downstream pages continue to compile without compatibility aliases.

## 5. Executable Contract Migration

The verifier should read every target file independently, then create family aggregates only for behavior that legitimately spans them:

- `chromeSource = chrome + window + sidebar + statusBar`
- `visualSource = designSystem + visualSystem`
- `dataSharedSource = dataInteraction + dataShared + dataPresentation`
- `connectionsPage = connections + connectionsView + connectionDetails + connectionCache + connectionPulseView`
- `logsPage = logPresentation + logs`
- `rulesPage = rulePresentation + rules + ruleDetails`
- `sourcesPage = sourcePresentation + sources + sourceDetails`
- `actionsPage = actions + tailscale`
- `controllersPage = controllerPresentation + controllers`
- `diagnosticsPage = diagnosticsPresentation + diagnostics + diagnosticsComponents`
- `overviewPersonalizationSource = personalization + layoutStore + windowCoordinator`

Existing cross-family assertions may use these aggregates. Ownership assertions must continue to target individual files, for example destination/root only in Chrome, sidebar types only in Sidebar, log cache only in LogPresentation, and diagnostics root only in Diagnostics. This prevents aggregation from silently accepting future responsibility drift.

The exact Workbench file list in `.trellis/spec/frontend/workbench-ui-contract.md` and `expectedWorkbenchFiles` must include every new file. `docs/ARCHITECTURE.md` is updated only where it currently describes affected Workbench ownership.

## 6. Behavior Preservation

- Root View identity, `@State`/`@Environment` ownership, task IDs and AppModel intent calls remain at their current semantic owner.
- Controller order, optionality, selection reconciliation, stale/paused/unsupported/empty states and raw reported values remain unchanged.
- Controller ID plus session generation validation, capability gates and confirmed-write semantics remain unchanged.
- Scroll/pulse/follow cadence constants, cache keys, invalidation inputs and persistence encoding remain byte-for-byte where feasible.
- No production mock data, no controller access and no runtime smoke are introduced.

## 7. Risk Control And Rollback

- Work in ownership families, but defer build/test until all related source and contract moves are complete, following repository verification policy.
- Use `rg` after each family to check duplicate/missing top-level declarations and stale ownership assertions; these are static checks, not repeated builds.
- Compiler failures are treated as boundary evidence: repair the smallest import/access issue without changing algorithms or copying code.
- The current dirty worktree is authoritative. Never use destructive Git commands, file checkout or broad generated rewrites; inspect overlapping edits before moving a declaration.
- Each move is a complete declaration block, so a failed slice can be restored manually with `apply_patch` without touching unrelated changes.

## 8. Documentation Boundary

This decomposition changes durable source ownership, so it updates the Workbench UI contract and the directly affected architecture summary. It does not change user-facing UI, controller/session contracts, localization, dependencies or release documentation.
