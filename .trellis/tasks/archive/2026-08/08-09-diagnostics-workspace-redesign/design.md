# 诊断与操作工作台联动重构技术方案

## 1. Design Direction

Diagnostics 从“status band + hierarchical outline”改为“action-first adaptive triage workspace”。默认 UI 不再镜像内部数据模型，而是消费一个纯问题投影：

```text
field-granular AppModel state
  -> WorkbenchDiagnosticsInput
  -> WorkbenchDiagnosticsProjection.snapshot(...)
  -> overall verdict + issues + available areas + technical groups
  -> adaptive SwiftUI composition
```

Actions 从“capability-filtered grouped form”改为“state-aware command workspace”。它消费独立的纯命令投影，不直接把 capability matrix row 等同为按钮：

```text
controller + session + capabilities + runtime operation rows + dispatcher support
  -> WorkbenchActionsInput
  -> WorkbenchActionsProjection.snapshot(...)
  -> availability + target context + executable groups + recovery intents
  -> recovery or adaptive command composition
```

用户已确认：

- 默认判断与技术证据分层；
- live session 自动结果 + 一次只读 Recheck；
- Diagnostics 不直接执行远端修复；
- 宽窗口 master-detail、窄窗口行内详情、健康态单栏。
- Actions 覆盖全部 controller family，按真实 capability/dispatcher 输出命令；Nikki 不拥有专用视觉分支。
- Actions 的连接恢复态与正常命令态使用不同构图，loopback 明确标识为当前 Mac。

Apple Wireless Diagnostics 和 Apple Diagnostics 的“结果/解决办法优先、按项详情、技术报告用于支持交接、主动检查按目标选择”作为交互依据。Mica 项目合同继续优先：内容层不使用自定义 glass、装饰渐变、嵌套卡片或虚构数据。

## 2. Existing Boundaries To Preserve

- `ControllerSessionPresentationState` 继续是 SwiftUI 观察 session lifecycle、last success 和 controls 的 field-granular 来源。
- `ControllerHealthSnapshot` 继续拥有当前基础/增强 endpoint 状态与 checkedAt；本任务不改变 controller probe API。
- `selectedUnifiedCapabilities` 继续定义当前有效 controller 的真实能力；`false` 不得被重解释为故障。
- Actions 现有 direct/runtime/lifecycle operation 实现继续是命令来源，但只有与当前 adapter 对应的真实 dispatcher 才能生成可执行 command；观察状态不能冒充命令。
- `rulesSnapshotState`、`providersSnapshotState` 和 `LiveStreamState` 继续表达各自运行时状态。
- `refreshSelectedRouter()` 继续承担 generation-safe immediate refresh；不增加 Diagnostics 自有 task、timer 或网络请求。
- `AppModelEndpointChecks`、Capability Matrix、Data Coverage、Observability 和 Diagnostics Runtime Operations 仍被 Actions、Configuration、tests 或报告消费。本任务只移除它们对默认 Diagnostics SwiftUI 的驱动，不做无关模型清理。
- `copyDiagnosticsReport()` 和现有 export redaction/security contract 保持不变；可见 UI 只减少入口，不削弱报告内容。
- Workbench 保持十个固定目的地和同窗口 RouterEditor；不增加窗口、sheet 或 modal workflow。
- 既有 destructive confirmation 继续捕获 controller ID 与 session generation；Actions 重构不得放宽确认或 confirmed-write 边界。
- Router target scope 只做纯解释/提示，不自动探测局域网设备，不修改 controller profile、OpenWrt、service 或 firewall。

## 3. Presentation Model

`WorkbenchDiagnosticsPresentation.swift` 继续保持 SwiftUI-independent，并改为拥有以下模型：

```swift
enum WorkbenchDiagnosticsOverallState {
    case checking
    case ready
    case needsAttention
    case blocked
}

enum WorkbenchDiagnosticsIssueSeverity {
    case critical
    case warning
}

enum WorkbenchDiagnosticsAction: Equatable {
    case refresh
    case resumePresentation
    case editController
    case navigate(WorkbenchDestination)
}

struct WorkbenchDiagnosticsIssue: Identifiable, Equatable {
    let id: String
    let severity: WorkbenchDiagnosticsIssueSeverity
    let title: String
    let detail: String
    let affectedDestinations: [WorkbenchDestination]
    let evidence: [WorkbenchDiagnosticsEvidence]
    let primaryAction: WorkbenchDiagnosticsAction?
}

struct WorkbenchDiagnosticsSnapshot: Equatable {
    let controllerID: RouterProfile.ID
    let generation: UUID
    let overallState: WorkbenchDiagnosticsOverallState
    let freshness: WorkbenchDiagnosticsFreshness
    let issues: [WorkbenchDiagnosticsIssue]
    let availableAreas: [WorkbenchDiagnosticsArea]
    let technicalGroups: [WorkbenchDiagnosticsTechnicalGroup]
    let checkedAt: Date?
}
```

Exact names may adjust to local naming, but the typed boundaries remain. Titles/details can be localized inside the projector using the explicitly passed `AppLanguage`; issue identity must never depend on localized text, timestamps or array offsets.

`WorkbenchDiagnosticsInput` contains only the low-frequency values needed by Diagnostics:

- selected router identity and visible endpoint label;
- requested/detected controller kind and adapter confidence;
- `ControllerSessionPresentationState` lifecycle values copied into value types;
- pause state and pause timestamp;
- controller health and metadata;
- rules/providers snapshot states;
- live stream state;
- selected unified capabilities.

It does not include traffic timelines, connection rows, logs, command log arrays or raw controller payloads.

## 4. Derivation Contract

The complete mapping lives in `research/issue-projection-map.md`. The implementation must preserve these rules.

### 4.1 Overall Verdict

Precedence:

1. first baseline checking -> checking;
2. no retained baseline + controller-wide failure -> blocked;
3. retained data + stale/failed/partial/paused or any issue -> needsAttention;
4. live with no issue -> ready.

No-controller remains owned by `WorkbenchWorkspaceView`. A retained last-success timestamp is shown as stale evidence, never as current live time.

### 4.2 Issues And Deduplication

Issue families are controller access, adapter, session stale, presentation paused, fallback session partial, six endpoint/data domains and live telemetry.

- Controller-wide access failure suppresses derivative endpoint rows.
- Wrong target is more specific than adapter unknown and wins deduplication.
- Pause explains local presentation freshness; pending presentation state is not surfaced as new visible endpoint failure while paused.
- Endpoint failure wins over duplicate rules/providers snapshot-unavailable state.
- Capability false suppresses corresponding endpoint/snapshot/stream issue.
- Generic partial appears only when no specific data-domain issue explains it.
- Operation history and diagnostics copy state never affect overall health.

Issues are sorted by severity, then a fixed user-impact order. Controller-report ordering is kept inside technical evidence/report, not used to weaken issue priority.

### 4.3 Affected Destinations And Actions

| Domain | Destinations | Safe primary intent |
| --- | --- | --- |
| controller access / adapter | all controller surfaces | Edit Controller or Recheck |
| configs | Configuration, Overview | Navigate Configuration |
| proxies/policies | Proxies, Overview | Navigate Proxies |
| connections/requests | Connections, Overview | Navigate Connections |
| rules | Rules, Overview | Navigate Rules |
| providers | Sources, Overview | Navigate Sources |
| live traffic | Overview, Connections | Navigate Overview |
| logs | Logs | Navigate Logs |
| presentation pause | all visible data | Resume Presentation |

Root SwiftUI maps typed intents to existing closures/bindings. The projector never receives executable closures.

### 4.4 Available Now

Available areas are product domains, not API rows: Policies, Connections, Rules, Sources, Live Telemetry and Configuration. A domain appears only when capability says it exists and current domain evidence is not failed. Unsupported domains are omitted; failed supported domains move to Issues.

The UI renders a compact flat icon/value grid with no green badge wall and no fabricated count.

### 4.5 Technical Details

One secondary technical disclosure contains:

- Controller: identity, requested/detected type, visible target, version and mode.
- Session: lifecycle, freshness, pause state, last success and last endpoint check.
- Evidence: human endpoint names/status in their existing order plus a compact supported-area summary.

It does not render raw API paths, machine assignments, backend-boundary terminology or raw report sections. Copy Report remains the only full machine-evidence command.

## 5. Actions Presentation And State Contract

新增 `WorkbenchActionsPresentation.swift`，保持 SwiftUI-independent，拥有以下等价 typed boundary：

```swift
enum WorkbenchActionsAvailability {
    case checking
    case recovery
    case ready
    case partial
    case unsupported
}

enum WorkbenchActionsIntent: Equatable {
    case testConnection
    case refresh
    case direct(UnifiedControllerAction)
    case runtimeOperation(String)
    case editController
    case openDiagnostics
    case navigate(WorkbenchDestination)
}

struct WorkbenchActionCommand: Identifiable, Equatable {
    let id: String
    let group: WorkbenchActionGroup
    let risk: WorkbenchActionRisk
    let intent: WorkbenchActionsIntent
    let requiresConfirmation: Bool
}

struct WorkbenchActionsSnapshot: Equatable {
    let controllerID: RouterProfile.ID
    let generation: UUID
    let availability: WorkbenchActionsAvailability
    let targetScope: WorkbenchControllerTargetScope
    let executableCount: Int
    let groups: [WorkbenchActionCommandGroup]
    let recovery: WorkbenchActionsRecovery?
}
```

Exact names may follow local conventions. IDs are stable operation IDs; localized text and timestamps remain values, never identity or dispatch keys. The projection receives an explicit executable-operation inventory so a capability/status row cannot invent a dispatcher.

### 5.1 Availability Precedence

1. connecting/probing with no baseline -> checking;
2. failed/unresolved with no live commands -> recovery;
3. live with retained failures or a subset temporarily unavailable -> partial;
4. live with executable commands and no blocking issue -> ready;
5. resolved controller with no standalone Actions contract -> unsupported/related-workspaces composition, not an empty form.

No-controller remains the shared Workbench state. `executableCount` is derived only from commands whose readiness and dispatcher both pass now. Refresh is absent as an executable command until `canRefreshSelectedRouter` is true.

### 5.2 Controller Coverage

- Auto Detect/unknown before successful probe exposes Test plus Edit/Diagnostics recovery intents; it does not project guessed family commands.
- mihomo, Nikki and OpenClash share verified mihomo-compatible API commands while preserving separate controller labels and Mica boundaries.
- CMFA and Stash expose only their capability subsets; core lifecycle remains unavailable.
- sing-box runtime memory/traffic are observations. Standalone Actions remains limited to real commands; policy, connections, configuration and Tailscale commands stay on their owning pages.
- Surge uses Surge HTTP API commands and API Key semantics; no Mihomo maintenance/lifecycle command enters its groups.
- Unsupported families render an explanation and safe navigation/edit intents without disabled command catalogs.

The detailed source audit and candidate command matrix live in `research/actions-all-controller-audit.md`.

### 5.3 Target Scope

`WorkbenchControllerTargetScope` is a pure classification shared by RouterEditor diagnosis, Actions recovery and Diagnostics evidence:

- `thisMac` for `localhost`, IPv4 loopback and IPv6 loopback;
- `networkHost` for other valid host/IP values;
- `unconfigured` for empty/invalid draft targets.

The label is factual. Explicit mac-local controllers accept `thisMac`; router-bound families such as Nikki/OpenClash use it as a high-confidence recovery explanation. Auto Detect does not infer a family from the address. Parsing uses structured host/address handling, not localized-string matching.

### 5.4 Actions Composition

Recovery/checking uses a compact, top-aligned, unframed status composition: controller, target scope, current reason, one primary Test/Recheck intent, then Edit Controller and Open Diagnostics. It does not render disabled Refresh, empty sections or an operation-count badge.

Ready/partial uses one outer scroll owner and a bounded command canvas:

- wide content uses two balanced flat section columns separated by spacing, not nested cards;
- compact content uses the same groups in one column;
- lifecycle/destructive commands occupy their own full-width final section and retain inline confirmation;
- controllers with few standalone commands show a compact related-workspaces row instead of fabricated operations or oversized grouped-form rows.

The command bar leads with connection/controller status. An optional count is secondary and equals `executableCount` exactly.

## 6. Diagnostics SwiftUI Composition

### 6.1 Root And Canvas

`WorkbenchDiagnosticsView` receives:

- `@Binding var destination: WorkbenchDestination`;
- `let onEditController: (RouterProfile) -> Void`.

`WorkbenchWorkspaceView` already owns both and passes them through. No-controller handling remains outside the page.

Replace `WorkbenchManagementCanvas` with a Diagnostics-specific `GeometryReader + ScrollView` canvas that uses `MicaBounds.pagePadding(for:)` and full remaining width. It remains the single scroll owner and paints `MicaDesignTokens.pageFill`.

### 6.2 Stable Page Order

1. shared command bar with controller verdict/freshness summary and one secondary Copy Report command;
2. retained/stale notice when applicable;
3. unframed verdict header with symbol, exact status, controller and timestamps;
4. Needs Attention master-detail when issues exist;
5. Available Now flat area summary;
6. one native technical disclosure and export-boundary note.

There is no page-level feature explanation or instructional copy.

### 6.3 Adaptive Master-Detail

Use measured content width, not font scale or device assumptions:

- width >= a dedicated Diagnostics split threshold around 900pt: `HStack` with a 320-380pt issue list, one hairline separator and a flexible selected-detail column;
- below the threshold: one issue list where selected detail expands directly below its row;
- zero issues: omit the master-detail region entirely and use the ready single-column verdict.

Both modes are inside the same outer ScrollView. Do not put `List`, `Table`, a second `ScrollView` or a lazy scrolling container inside it. Issue counts are bounded by the fixed domain taxonomy, so eager `VStack` is appropriate.

Issue rows are native Buttons with full-row hit targets, content-driven height, stable leading severity rail/symbol and restrained selection fill. Detail contains title, impact destinations, evidence and at most one icon+text action button. No card is nested inside another card.

### 6.4 Selection State

The root owns one `selectedIssueID`:

- on first issue snapshot, choose the first sorted issue;
- preserve the ID if it remains;
- if resolved, move to the next first issue;
- clear and reseed when controller ID or generation changes;
- clear when healthy.

The same ID drives wide detail and compact inline expansion. `onMoveCommand` advances through stable issue IDs for keyboard users. Selection changes use only a short local opacity/selection transition and become static under Reduce Motion; no animation modifier attaches to the full subtree.

## 7. Command Semantics

The main Workbench toolbar currently exposes Test, Refresh and Pause on every destination. Diagnostics must have one check meaning:

- hide the global Test button only while destination is Diagnostics;
- retain the existing Refresh button as Recheck Now, with its native icon and tooltip;
- retain Pause/Resume because it is a shared local presentation control;
- remove Copy Endpoint Results and Copy Check Results from the Diagnostics command bar;
- retain one Copy Report secondary command.

Other destinations keep existing toolbar behavior.

Actions root receives the same destination binding and editor intent as Diagnostics. It maps typed Actions intents to existing AppModel operations; the pure projection never owns closures or starts tasks. Open Diagnostics changes the same-window destination. Pending lifecycle confirmation clears on controller, generation, availability or visible-operation changes.

## 8. Observation And Performance

- Build the input from `controllerSessionPresentation` lifecycle fields plus the small AppModel health/capability values. Do not read timeline arrays or row catalogs in Diagnostics.
- Projection is pure, deterministic and bounded by fixed endpoint/domain counts.
- Stable issue IDs prevent selection churn; timestamps are values only and never identity.
- Do not call `Date()` from `body` to age data or add a timer. Session state determines live/stale; absolute timestamps explain evidence.
- Recheck delegates to the existing refresh coordinator and retains controller/generation validation.
- Technical groups are value projections; collapsed UI must not build raw report text or large operation/check arrays.
- Actions observes only selected controller identity/target, session lifecycle, capability/runtime readiness and operation-running state. Traffic samples, connection rows and log frames do not rebuild it.
- Controller target classification is deterministic and side-effect free; no reachability timer, LAN discovery or controller request is added.

## 9. Accessibility And Localization

- Every severity uses symbol + text + color; VoiceOver combines issue title, severity, impact and selection state.
- Issue list exposes native button semantics and selected trait; compact inline detail does not duplicate the selected issue to VoiceOver.
- Impact destinations use localized visible names. All new status, area, evidence and action copy is English + Simplified Chinese.
- Long controller names, endpoint labels and error messages wrap without negative tracking or viewport-scaled fonts.
- Four font scales may increase row height; split/compact switching remains width-driven.
- Increase Contrast strengthens separators/selection through existing semantic tokens. Reduce Motion disables selection/detail transitions.
- Actions recovery reason, target scope, group labels, command risk and availability use text + symbol + semantic color. Buttons keep visible English/Chinese titles and wrap rather than collapsing to unexplained glyphs.

## 10. Files And Ownership

Primary changes:

- `Sources/Mica/Features/Workbench/WorkbenchActionsPresentation.swift`: pure all-controller availability, target-scope, command-group and executable-inventory projection; no SwiftUI import.
- `Sources/Mica/Features/Workbench/WorkbenchActions.swift`: Actions root, typed intent routing, recovery/ready compositions and existing generation-safe confirmation UI.
- `Sources/Mica/Features/Workbench/WorkbenchDiagnosticsPresentation.swift`: input, snapshot, issue/area/evidence/action types, projector and selection reconciliation helpers; no SwiftUI import.
- `Sources/Mica/Features/Workbench/WorkbenchDiagnostics.swift`: root observation, projection input, selected issue state, intent routing and page composition.
- `Sources/Mica/Features/Workbench/WorkbenchDiagnosticsComponents.swift`: full-width canvas, verdict, issue list/detail, available areas and technical disclosure components.
- `Sources/Mica/Features/Workbench/WorkbenchWorkspaceView.swift`: pass destination and editor intent to Diagnostics and Actions.
- `Sources/Mica/Features/Workbench/WorkbenchChrome.swift`: omit Test only for Diagnostics while retaining Refresh/Pause.
- `Sources/Mica/App/ControllerPresentation.swift` and RouterEditor diagnosis composition: shared factual target-scope presentation without profile mutation.
- `Sources/Mica/Resources/Localizable.xcstrings`: English and Simplified Chinese copy.
- `Tests/MicaTests/WorkbenchManagementProjectionTests.swift` or cohesive Actions/Diagnostics projection test files: replace old outline visibility assertions and cover every controller command snapshot.
- `scripts/verify-real-controller-source.mjs`: replace old disclosure/fact-grid source contracts with new projection/layout/safety contracts.
- `.trellis/spec/frontend/workbench-ui-contract.md`: replace the rejected Diagnostics archetype with the approved action-first adaptive contract.

Files expected to remain behaviorally unchanged:

- `AppModelEndpointChecks.swift`
- `AppModelReadiness.swift`
- `AppModelDiagnosticsRuntimeOperations.swift` and `AppModelRuntimeOperations.swift`; projection must stop exposing mismatched commands instead of adding unsupported controller dispatchers.
- controller API/client/DTO files
- credential storage and export redaction implementation

If implementation proves a shared model change is unavoidable, stop and update this design before broadening scope.

## 11. Tests And Verification

Pure projection tests cover:

- first-load checking and blocked/no-baseline failure;
- retained stale/failed data;
- pause precedence and Resume action;
- controller-wide failure suppressing endpoint duplicates;
- capability false suppressing unsupported Rules/Sources/stream issues;
- endpoint domain -> impact/action mapping;
- specific issue suppressing generic partial;
- stable severity ordering and issue selection reconciliation;
- healthy Available Now projection;
- technical evidence excludes machine-facing/raw values.
- Actions unresolved probe counts only executable Test and omits disabled Refresh;
- ready/partial/recovery/unsupported Actions state precedence;
- mihomo, Nikki, OpenClash, CMFA, Stash, sing-box and Surge command inventories and stable order;
- dispatcher inventory suppresses sing-box memory and every other capability-without-command mismatch;
- loopback/network/mac-local target classification and recovery copy intent;
- pending confirmation invalidation across controller ID/generation/operation changes.

Source verifier covers:

- Diagnostics presentation remains SwiftUI-independent;
- one issue snapshot projection and stable IDs;
- adaptive wide/compact composition with one scroll owner;
- no old eight-section outline or three copy commands;
- no direct remote mutation calls from Diagnostics;
- Workspace passes navigation/editor intents;
- Diagnostics hides only the shared Test toolbar command.
- Actions presentation remains SwiftUI-independent and all buttons originate from the executable inventory;
- recovery composition contains Edit/Diagnostics intents and no disabled command wall;
- adaptive Actions command groups have one scroll owner and lifecycle remains isolated.

Full build/tests are justified because the change touches shared Workbench navigation/chrome, localization and cross-layer presentation contracts.

## 12. Compatibility And Rollback

- Swift 6.2, macOS 27 and SwiftPM targets remain unchanged.
- No package, persistence migration, controller protocol or report-format migration is added.
- The projection layer can be implemented and tested before replacing the UI.
- Root/components replacement is isolated to the existing three Diagnostics files; toolbar/workspace wiring is a small separate slice.
- Actions projection can replace the misleading count before the full ready-state composition; if the dual-column layout regresses, retain the new truthful projection and fall back to its single-column composition.
- If adaptive master-detail causes layout regression, keep the new problem projection and temporarily fall back to the compact single-column issue composition; do not restore the old implementation inventory.
- If an issue cannot be derived without string parsing or fabricated inference, omit/defer that issue instead of weakening the typed evidence rule.

## 13. Durable Contract Update

Implementation must update `workbench-ui-contract.md` because the current spec explicitly mandates the rejected Diagnostics status-band/outline/fact-grid archetype and treats Actions as an ordinary grouped form. The new durable contract will state action-first issue projection, safe action boundary, adaptive Diagnostics master-detail, healthy single-column mode, one technical disclosure/report export, plus all-controller Actions availability, executable-inventory gating, recovery composition and adaptive command grouping.

## 14. Post-Implementation Correctness Audit

### 14.1 One Diagnostics State Gate

`WorkbenchDiagnosticsProjection.snapshot` derives one `isChecking` value before projecting issues. A first-baseline checking/probing snapshot:

- does not project controller-access, adapter, endpoint, Rules/Sources, live-stream or generic partial failures;
- does not publish Available Now domains from detected-kind static capabilities;
- keeps overall state and freshness as checking;
- may expose technical controller identity/target, but no rejected machine-facing failure value.

After checking completes, controller-access is the causal root. When it exists, it suppresses endpoint and data-domain failures regardless of whether `lastSuccessAt` exists. `lastSuccessAt` still controls freshness (`unavailable` versus `retained`) and does not weaken causal deduplication.

Every free-form issue evidence value goes through one helper that either returns `displayableText(value)` or the localized `diagnostics.evidence_unavailable` fallback. The helper receives language explicitly and never falls back to the rejected raw string. Endpoint evidence with a typed status label may retain that safe label as its explicit fallback.

### 14.2 One Effective Actions State

Actions computes `rawAvailability`, command groups, and then one `effectiveAvailability`. If a ready/partial controller has no verified command groups, `effectiveAvailability` becomes unsupported. Recovery composition, target-correction context, executable count and the rendered canvas all consume that same effective value. There must not be an unsupported snapshot carrying recovery copy derived from ready/partial.

Related workspace navigation stays truthful but appears only in the unsupported/few-command composition; controllers with normal command groups do not render it as body filler.

### 14.3 Explicit Accessibility Semantics

Critical and warning severity receive English and Simplified Chinese labels. The issue-row SF Symbol remains decorative for assistive technology; the Button exposes an explicit label/value containing localized severity, issue title, affected-area count and selected state. Existing native button semantics, selected trait, arrow-key movement, Reduce Motion behavior and one scroll owner remain unchanged.

## 15. Observation And Invalidation Audit

- Diagnostics continues to read field-granular session lifecycle, health, fixed endpoint/domain state and metadata only. It must not read connection rows, traffic timelines, log rings or report bodies.
- Actions currently builds 17 fixed runtime rows and reads broad `isBusy`. Those values are bounded and operation-driven rather than stream-driven. Do not introduce a new AppModel state model merely to reduce 17-row work; first prove an invalidation problem with observation counters or a focused test.
- Add source/test contracts that traffic, connection metrics and log catalog revisions are absent from Diagnostics/Actions inputs. Preserve operation-running updates so command disabled state remains accurate.
- Existing Proxies scroll deferral/coalescing and hover suppression are treated as a protected performance contract. No change is planned without a failing regression test or separately authorized trace.

## 16. Shared Stable-Identity Performance Design

The first measured optimization targets `WorkbenchStableRowIdentityBuilder`, which is shared by Connections, Logs, Rules and Sources:

1. Make `fallbackComponents` lazy (`@autoclosure` or an equivalent nonescaping closure), because unique controller-reported IDs currently allocate the complete fallback array even though it is never hashed.
2. Add a unique reported-ID fast path: if the ID is not duplicated and does not collide with reserved/used IDs, insert it once and return without touching the occurrence dictionary or evaluating fallback components.
3. Reserve count/set capacity from the reported-ID count to avoid repeated rehashing on large catalogs.
4. Preserve the existing duplicate, missing-ID, reserved-ID collision, occurrence and controller-order behavior exactly. Existing call sites retain their source shape and do not gain page-specific identity logic.

This change is kept only if repeated Release reports show a meaningful improvement in 10,000-row connection projection while stable-identity tests and checksums remain unchanged. If the gain stays within baseline noise, revert the optimization slice rather than adding more identity complexity.

## 17. Benchmark Fidelity And Performance Stop Rules

- Keep all existing benchmark cases and schemas for historical comparison.
- Add a prepared-state measurement helper whose setup runs outside the timed interval, then add `log-steady-state-delta-projection`: initialize the 2,000-row buffer/cache before timing and measure only 32 valid sequential delta applies.
- Run two before reports and two after reports under the same Release build configuration. Compare checksum, reported work units, median and p95. The observed ordinary baseline spread is roughly 0-8%; the targeted 10,000-row connection median should improve by at least 10% in both after runs to justify shared identity complexity, while unrelated cases must not regress by more than 10% consistently.
- The existing log end-to-end case includes initial full projection plus 32 deltas and remains an integration measure. Change the Logs cache only if the new steady-state case exposes material cost or a correctness/performance defect; do not replace the bounded ring or add a dependency to chase a synthetic number.
- Runtime SwiftUI Instruments and real-controller smoke remain outside this automated task. They may be performed only after separate authorization and must not become automated controller contact.

## 18. Post-Audit Files And Verification

Expected product/test files:

- `WorkbenchDiagnosticsPresentation.swift`: checking gate, safe evidence fallback and causal dedup.
- `WorkbenchActionsPresentation.swift`: effective availability/recovery consistency and compact related-destination rule.
- `WorkbenchDiagnosticsComponents.swift` plus `Localizable.xcstrings`: explicit severity accessibility semantics.
- `WorkbenchDataPresentation.swift`: lazy fallback and unique-ID fast path.
- `MicaPerformanceBenchmarkTests.swift`: prepared steady-state delta benchmark while retaining old cases.
- Focused management/identity/performance tests and `verify-real-controller-source.mjs` only where they express durable behavior.
- `workbench-ui-contract.md`: record first-baseline truthfulness, safe evidence fallback, causal dedup and measured optimization stop rules.

No controller API, live-session cadence, persistence, credential storage, report redaction, production mock data or package dependency changes are expected. Correctness fixes can be rolled back independently from the shared identity optimization; benchmark infrastructure remains useful even if the optimization slice is discarded.

## 19. Full Workbench Hotspot Coverage

The continued audit measures the actual high-cardinality projection boundaries rather than SwiftUI body construction or controller I/O:

- Connections: structural rows at 1,000/5,000/10,000, initial 10,000-row cache construction, prepared search, and one keyed metric update.
- Logs: ring materialization, full-ring-plus-delta integration, prepared steady-state delta, and prepared search at the bounded 2,000-row capacity.
- Rules: one 10,000-row connection index plus aggregate pass, structural rows, and search over projected rows.
- Sources: 1,000-row stress structural projection and search over projected rows.
- Proxies: a 100-group x 1,000-member catalog index and two expanded 1,000-member groups.
- Existing runtime connection and topology cases remain controls for shared regressions.

Prepared cases recreate the cache outside the timed interval and time only the user-triggered projection. Reports preserve fixture count, checksum and reported work units so an apparently faster case cannot silently do less work.

## 20. Retained Product Optimizations

### 20.1 Connection Structural Formatting

`WorkbenchConnectionProjection.rows` resolves the localized unavailable value once per language/projection. Metrics formatter results use direct nil fallback. Summary strings use direct interpolation only after every component has already passed `dataNonEmpty` and received a non-empty fallback. This removes repeated optional-array allocation, trimming and localization without changing row identity, controller order, search text, inspector values or metric-revision behavior.

`updatingMetrics` applies the same direct fallback contract. Its unchanged-metric early return and keyed changed-row path remain authoritative.

### 20.2 Shared Data Search

Connections, Logs, Rules and Sources normalize blank query handling at their existing projection boundary, then call:

```swift
WorkbenchDataSearch.contains(query, in: row.searchText)
```

The helper performs one Foundation `NSString.range(of:options: [.caseInsensitive])` query against the already cached search blob. It keeps case-insensitive Unicode matching without adding diacritic folding; for example, `mÜnchen` matches `München`, while `munchen` does not. It does not pre-normalize and retain a second full search blob, mutate row order, or perform work in a SwiftUI row body.

## 21. Rejected Alternatives

- Pre-folding and lowercasing every complete connection search blob increased the 10,000-row row projection from roughly 90 ms to roughly 142 ms, initial cache from roughly 119 ms to 172-182 ms, and search from roughly 29-37 ms to roughly 67 ms. The extra allocation dominates the lookup saving.
- Swift `String.range(of:options: .caseInsensitive)` measured roughly 343 ms for the 10,000-row connection search and is not a replacement for the shared Foundation matcher.
- `@inline(__always)` produced only noise-level connection change while worsening some log/rule tail samples. The helper remains ordinary module-internal code.
- The previously attempted stable-identity fast path remains rejected because its two-run gain did not cross the 10% stop rule.

## 22. Page-Level Stop Decisions

- Keep Connections formatting/search changes: two repeated runs improve structural row median by 22.40%/21.79%, initial cache by 19.81%/22.21%, and search by 22.96%/22.11%.
- Keep shared search for Logs: repeated median improves by 49.53%/51.08%. Rules and Sources show the same direction in same-process A/B and stable final repeated cases.
- Do not add another Rules or Sources cache layer. Their structural projections are refresh-driven, preserve complete controller data, and show no measured interaction defect that justifies new revision/state machinery.
- Do not modify Proxies scheduling. Catalog indexing and expanded-group projection remain bounded in the synthetic stress cases, while the existing scroll deferral contract already targets the reported hitch.
- Do not modify Overview topology/timeline or fixed-size management/diagnostic pages without a new repeatable trace or benchmark regression.
