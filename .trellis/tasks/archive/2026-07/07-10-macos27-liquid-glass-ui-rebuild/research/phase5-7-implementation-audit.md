# Research: Phase 5-7 implementation audit

- Query: 为 Phase 5-7 审计 Activity（Connections/Logs）、Rules & Sources、System/Settings/Controller Editor 的真实字段、动作、状态语义、原生 macOS 27 布局与实现文件边界；对照 Mica controller contract 和 `tmp/codex/sparxie-ui-reference`，但不把 SparkXie 的排序或本地后端行为带入 Mica。
- Scope: mixed（Mica 内部代码/spec + SparkXie UI/API 语义参考）
- Date: 2026-07-10

## Findings

### 0. Cross-cutting contract and implementation boundary

Mica 的远程控制器契约已经足够承载三阶段 UI，不需要引入本地核心、mock 数据或 SparkXie 的 session/backend。`MihomoCompatibleControllerAdapter.snapshot()` 并发读取 version/config/proxies/connections，并把 rules、proxy providers、rule providers 作为可部分失败的增强快照（`Sources/MicaCore/API/UnifiedControllerAdapters.swift:34-62`）；`AppModel.refreshSelectedRouter()` 将 base endpoint 失败与 rules/providers 部分不可用区分开（`Sources/Mica/App/AppModel.swift:620-717`）。

必须坚持：

- 所有远程业务字段原样可见、可换行、可选中；凭据、X-Key、secret、authorization、subscription URL、raw response/stream body 仍只留在安全边界之外。不要把 UI 上的业务字段改成“redacted/masked/safe summary”。
- `ControllerCapabilities` 是每个动作的唯一门控来源；`reloadRules`、`reloadProviders`、`updateProvider`、close connection、diagnostics copy 等都复用 `AppModel` 现有 operation，而不是在 View 里调用另一套 API（`Sources/MicaCore/Models/UnifiedControllerModels.swift:172-331`）。
- Activity/Rules/Sources 的筛选只改变可见集合；不要本地排序。尤其不要沿用 SparkXie 的 `providerList` 名称排序（`Sources/MicaCore/Models/MihomoModels.swift:444-473,526-555`）作为 Mica 的控制器顺序契约；如果底层只有字典且没有远程顺序，就明确标记“控制器未提供顺序”，不要伪造稳定业务顺序。
- 普通选择、刷新、更新、测试、关闭连接确认都留在主窗口。不要新增 sheet/popover/modal；只有高风险 destructive confirmation 可用平台标准确认。
- 所有中文/英文标题、状态、错误、辅助标签均走 `MicaStrings`/`Localizable.xcstrings`；字体大小必须乘 `micaFontMultiplier`，长中文和英文都不能依赖固定英文宽度。

Relevant durable contracts: `.trellis/spec/frontend/workbench-ui-contract.md:1-36`, `.trellis/spec/backend/controller-data-contract.md`, `.trellis/tasks/07-10-macos27-liquid-glass-ui-rebuild/design.md:168-197`, `.trellis/tasks/07-10-macos27-liquid-glass-ui-rebuild/implement.md:54-80`.

### 1. Phase 5 — Activity / Connections

#### Real fields and actions to retain

The canonical connection record is `ConnectionSnapshot`: `id`, `upload`, `download`, `start`, `chains`, `rule`, `rulePayload`, and optional `metadata` (`Sources/MicaCore/Models/MihomoModels.swift:633-672`). Metadata includes host, network, type, source/destination IP and port, process/processPath, inbound IP/port/name, DNS mode, sniff host, and UID (`:675-740`). Keep every one of these in the same-window inspector; the table may use a concise subset, but must not discard values.

Required actions are active/closed tab selection, search/filter, select row, close one connection, close all, clear closed history, refresh snapshot, and pause/resume dashboard updates where the Activity surface exposes live state. Existing methods are `AppModel.closeConnection(_:)` and `closeAllConnections()` (`Sources/Mica/App/AppModel.swift:267-358`), with local closed history in `DashboardSessionControls`; do not implement direct HTTP calls in the View.

The existing table has an explicit contract violation: `valueCell` uses `.lineLimit(1)` and `.truncationMode(.middle)` (`Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift:308-327`). Replace with native `Table` columns plus a full-value inspector and wrapping/selectable cells. The inspector already enumerates most required fields (`:167-217`), but currently duplicates source/UID labels and omits inbound IP/port; add explicit labels rather than overloading “source”.

#### Recommended macOS 27 components and same-window layout

- Root: native `Picker`/segmented control for `Connections | Logs`, with toolbar refresh/live controls supplied by the workbench shell.
- Main: `Table(selection:)` with resizable columns, keyboard row selection, and `ScrollView`/inspector split. Use `HSplitView` only as the container if the rebuilt shell does not provide a native inspector column; do not add glass to rows.
- Inspector: `ScrollView` + `LabeledContent`/plain detail rows, selectable full text, optional `DisclosureGroup` for metadata and route chain. A selected row remains selected when unrelated rows update; clear selection only if its ID disappears.
- Destructive close: inline adjacent confirmation state in inspector is preferred; a standard destructive confirmation is allowed for close-all. No custom modal confirmation.

#### Wide/narrow window behavior

- Wide (roughly >= 900 pt content): table left, inspector right; expose ID/host/process/network/chain/bytes/start columns, with addresses and payload in inspector.
- Narrow: keep the same window and same selected identity; collapse to a single `Table`/list with the inspector below or as an adjacent fixed detail region. Do not hide fields: move them into the selected detail region and allow wrapping/horizontal scrolling for IDs, endpoints, rule payloads and paths.
- At all widths, no middle truncation for controller data. If a compact table cell cannot fit, show a wrapped multi-line cell or require the inspector, not `…`.

#### State, error, empty, unavailable semantics

- No selected controller/base snapshot: unavailable (“controller data not loaded”), not “no connections”.
- Loaded controller with zero active/closed rows: empty state; filtered zero rows: “no matching connections”.
- Refresh/loading: preserve the last usable rows where possible, show loading on the action and disable conflicting destructive actions; do not clear real data merely to show a spinner.
- Capability false or controller family unsupported: unavailable action with capability reason, not a fake empty list. Surge may report no connections because its capability matrix says `connections=false` even if other activity endpoints exist.
- Close failure: keep row, show operation error with the real controller failure detail in the active UI, and append the existing log event; never imply success.

#### Files to change/reuse

- Replace presentation in `Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift`; reuse `ConnectionSnapshot`, `ConnectionMetadataSnapshot`, `DashboardSessionControls`, `AppModel.closeConnection`, `closeAllConnections`, and `refreshSelectedRouter`.
- Likely shared selection/table/detail primitives belong under `Sources/Mica/Features/Workbench/` only if they do not recreate legacy abstract card/deck layers.
- Update localized keys in `Sources/Mica/Resources/Localizable.xcstrings` only as part of implementation; preserve existing Chinese/English terminology and add missing field-specific labels.

#### Tests and verifier assertions

- Decode and render-contract test that every metadata field survives and appears in searchable/detail projection, including long CJK, IPv6, URL-like payload, process path, and a chain with multiple names.
- Selection identity test: refresh/re-filter preserves selected ID when present and clears it only when absent.
- Capability tests: close/close-all disabled for `.none`/unsupported and enabled for mihomo-compatible; no fake local fallback.
- State tests for unavailable vs empty vs filtered-empty and close failure.
- Source verifier must reject `.truncationMode(.middle)`/ellipsis on controller fields, reject `sheet`/`popover`/custom modal for Activity, and require `Table` plus same-window inspector and complete field labels.

### 2. Phase 5 — Activity / Logs

#### Real fields and actions to retain

Mica stores `LogMessage.type` and `payload` (`Sources/MicaCore/Models/MihomoModels.swift:372-380`) and wraps them in timestamped `DashboardLogEntry`; current UI shows timestamp, level/type, complete payload, level filter, pause/resume updates, follow-bottom, search, and clear (`Sources/Mica/Features/Workbench/WorkbenchRulesSourcesLogsViews.swift:573-740`). Preserve exact payload text and ordering as received by Mica. Do not import SparkXie’s backend stream or local daemon log source.

Required actions: level filter, text search, pause/resume dashboard updates, follow bottom, clear logs. `clearDashboardLogs()` is a local session-view operation; it must not call a remote destructive endpoint. The toolbar/menu action should call the same AppModel operation.

#### Components and layout

Use a high-density native `Table` or `List` with columns for timestamp, type, and payload; payload remains a readable content layer, not a glass row. Keep `ScrollViewReader`-style follow-bottom behavior, but expose a visible “jump to newest” inline control when follow is off. Full payload wraps and is selectable; use monospaced only for the log body if it remains legible in Chinese.

#### States and width

- No logs: empty (“no logs yet”); filtered zero: “no matching logs”.
- Paused: retain existing rows and state that live updates are paused; new remote/controller data must follow AppModel’s pause semantics.
- Long payload: wrap vertically; do not horizontally clip or middle-truncate.
- Wide: timestamp/type fixed resizable columns, payload fills. Narrow: type and timestamp remain visible but may wrap; payload remains full below/within the row.

#### Files/tests/verifier

Primary file is `WorkbenchRulesSourcesLogsViews.swift` (the `WorkbenchLogsView` portion); reuse `DashboardLogEntry`, `LogSessionLevel`, `DashboardSessionControls`, `AppModel.toggleDashboardUpdatesPaused`, and `clearDashboardLogs`. Add tests for exact payload preservation, type filtering, follow-bottom state, clear-local-only semantics, paused state, and CJK wrapping. Verifier should assert no redaction copy, no glass on log rows, and no modal interaction for normal log work.

### 3. Phase 6 — Rules

#### Real fields and actions to retain

`RuleSnapshot` contains `type`, `payload`, `proxy`, and optional `size`; its identity is the concatenation of these values (`Sources/MicaCore/Models/MihomoModels.swift:418-442`). The payload is the primary business field. Preserve controller array order; search across type/payload/proxy; select a row for same-window detail; reload via `AppModel.reloadRules()`.

The current UI already has a payload-first visual order but is a hand-built fixed grid and truncates values (`Sources/Mica/Features/Workbench/WorkbenchRulesSourcesLogsViews.swift:65-133` and `:491-505`). Replace with `Table(selection:)`, resizable columns, and a detail inspector. Do not add local sort or pagination assumptions unless the remote API later provides a real pagination contract; the current `RulesResponse` is a complete array (`MihomoModels.swift:418-424`).

#### Components/layout and state semantics

- Native segmented `Rules | Sources` at the resource-area level; no sheet for detail.
- Wide: payload/type/proxy/size table with inspector. Narrow: payload-first single column/list, selected detail below/adjacent, wrapping payload.
- Loading: preserve existing usable rules where possible and show loading/action state. Unavailable: rules endpoint failed or capability false; keep base controller state usable. Empty: endpoint succeeded with zero rules. Filtered-empty: data exists but query matches nothing.
- Reload success updates exact count and operation state. Reload partial/failure uses existing `rulesSnapshotState` and operation error; never fabricate rules or silently convert unavailable to empty.

#### Files/tests/verifier

Change the Rules portion of `WorkbenchRulesSourcesLogsViews.swift`; reuse `RulesResponse`, `RuleSnapshot`, `rulesSnapshotState`, `AppModel.reloadRules`, and `supportsUnifiedAction(.reloadRules)`. Add order, duplicate-identity edge, long payload/CJK, unavailable/empty/filtered-empty/loading/error tests. Verifier should require `RuleSnapshot.payload/type/proxy/size` in source projection, forbid `sorted`, middle truncation, mock rule arrays, and normal-work modal presentation.

### 4. Phase 6 — Sources (proxy and rule providers)

#### Real fields and actions to retain

Proxy source fields are `name`, `type`, optional `vehicleType`, `updatedAt`, and `proxyCount` (`MihomoModels.swift:475-505`). Rule source fields are `name`, `type`, optional `behavior`, `vehicleType`, `updatedAt`, and `ruleCount` (`:557-592`). `ProviderKind` distinguishes proxy vs rule (`:521-524`). The existing view merges them into `ProxyProviderViewState`, shows kind/type/vehicle/behavior/count/updatedAt, and supports same-window update with capability gating (`WorkbenchRulesSourcesLogsViews.swift:252-468`). Keep both categories and all fields.

SparkXie reference screens show useful semantic vocabulary—provider kind, behavior, vehicle, item count, updated time, update action—but their Rust API owns local backend/provider behavior. Mica must only call its remote `MihomoClient`/adapter operations. In particular, do not copy SparkXie’s source ordering, local provider cache, local update queue, or backend switcher.

#### Components/layout and state semantics

- Use a native `Picker`/segmented control for `All | Proxy sources | Rule sources`, then one `Table(selection:)` grouped by real provider kind. Grouping is presentation only; it must not reorder controller data. If the response has no order guarantee, use an explicit stable presentation order only as a non-business UI choice and document it; do not imply remote ordering.
- Inspector uses `LabeledContent`/detail rows and an inline update control. Update confirmation may remain adjacent inline because provider update can be disruptive; no ordinary sheet/popover.
- Wide: name/kind/type/vehicle/behavior/count/updated columns; inspector for capability and action detail. Narrow: name/kind/count list, all remaining fields wrapped in detail.
- Loading/reloading: retain last source values, mark the selected source updating, disable duplicate update. Success: update timestamp/count/status from returned snapshot. Failure: keep source row and show exact failure state in UI; retain per-source failure map.
- Endpoint unavailable or capability false: unavailable panel/action reason. Empty successful provider response: empty sources, not unavailable. Partial base snapshot: sources can independently be unavailable while Overview/Activity remain usable.

#### Files/tests/verifier

Change Sources portion of `WorkbenchRulesSourcesLogsViews.swift`; reuse `ProxyProviderSnapshot`, `RuleProviderSnapshot`, `ProviderKind`, `providersSnapshotState`, `providerUpdateFailures`, `AppModel.reloadProviders`, `updateProxyProvider`, and capability checks. Add tests for proxy/rule field projection, category filtering without sorting, provider update loading/success/failure, partial/unavailable/empty states, and long names/updatedAt. Verifier should reject `sorted` in the new source view projection, require both provider kinds and their distinct fields, and reject SparkXie/local backend identifiers.

### 5. Phase 7 — System / Configuration, Actions, Diagnostics, Settings

#### Real fields and actions to retain

`ConfigResponse` currently reports mode/modeOptions, allowLan, logLevel, port, socksPort, redirPort, mixedPort, IPv6, TCP concurrent, and TUN enable (`Sources/MicaCore/Models/MihomoModels.swift:8-42`). System Configuration may display these as read-only remote controller state unless a corresponding remote mutation action already exists. Do not create system/core mutation controls merely because SparkXie has a config screen.

Remote actions already represented by Mica include test connection, refresh snapshot, rules/providers reload, policy switch, latency test, mode change, close actions, provider update, DNS flush, Surge outbound/policy operations, and diagnostics copy (`UnifiedControllerModels.swift:116-170`). System Actions should call these existing AppModel methods and show capability/risk states. No local core start, system proxy change, firewall change, process kill, or environment mutation.

Diagnostics should retain endpoint status, health state, checked time, adapter source, controller type, capabilities, and operation history as allowed business/diagnostic data. Copy reports must exclude credentials and raw response/stream bodies; the active UI may show controller endpoint/host, IDs, provider/policy names, routes and messages in full.

Settings currently owns language, appearance, and four font-scale choices through `AppStorage`, `AppPreferencesStore`, and root synchronization (`Sources/Mica/Features/Workbench/WorkbenchSettingsView.swift:4-83,86-165,258-273`). Preserve immediate repaint across every area. The selected controller summary may show display name, type, full endpoint URL, TLS policy, and last connected time (`:167-199`); secrets remain credential fields, never diagnostics/export.

#### Recommended components and same-window layout

- Use one reusable `MicaSettingsForm` built from native `Form`, `Section`, `LabeledContent`, `Picker`, `Toggle`, `TextField` and `SecureField`, shared by System/Settings scene. Do not preserve manual section card borders as the primary hierarchy.
- Configuration: read-only `Form` sections for remote reported config and endpoint health. Show “not reported” for missing optional values, not guessed defaults.
- Actions: task-group sections with native buttons, capability-derived disabled state, inline progress/result, and destructive confirmation only where risk warrants it.
- Diagnostics: native `Table`/`DisclosureGroup` for endpoint statuses and capability matrix; full selectable endpoint/host and safe error details. Copy diagnostics from toolbar/menu invokes existing operation.
- Settings: language, appearance, font scale first; controller summary second; controller editing is a separate in-window state but shares form primitives.

#### Wide/narrow and states

- Wide: two-column form where native layout supports it, otherwise one readable max-width column with a right-side diagnostics inspector. Keep endpoint and operation detail selectable.
- Narrow: single `Form` column; sections remain in fixed order and controls wrap. Do not hide advanced configuration or replace it with a summary card.
- No selected controller: settings still work; controller section shows explicit no-controller state. Base unavailable: configuration fields report unavailable/not reported; actions disable by capability and explain why.
- Partial: show independently available sections and an inline partial status; never clear healthy sections because rules/providers failed.
- Busy/error/success: use existing `operationState`, `controllerHealth`, endpoint statuses, and per-action flags; avoid a generic toast-only result.

#### Files/tests/verifier

Primary files: `WorkbenchSettingsView.swift`, existing System/diagnostics/action views under `Sources/Mica/Features/Workbench/`, `AppModelDiagnostics*.swift`, `ControllerHealthModels.swift`, `AppPreferencesStore.swift`, `AppFontScale.swift`, and `MicaApp.swift` scene/root injection. Reuse `RouterProfile`, `RouterDraft`, `ControllerKind`, `TLSValidationPolicy`, `ControllerCapabilities`, `UnifiedControllerHealth`.

Add tests for config optional-field semantics, capability/risk gating, partial health, endpoint status rendering data, copy-report credential/raw-body exclusion, immediate language/appearance/font-scale propagation, and no-controller settings. Verifier should require native `Form`/`Section`/`LabeledContent`, forbid system/core/local-proxy mutation strings, ensure secrets are `SecureField`/Keychain-only, and ensure no ordinary sheet/popover/modal.

### 6. Phase 7 — Controller Editor

#### Real fields and actions to retain

`RouterEditorView` currently holds a `RouterDraft`, `TestState`, same-window editor content, diagnosis, and footer (`Sources/Mica/Features/Routers/Views/RouterEditorView.swift:4-49`). Existing editor sections and diagnosis expose controller kind, platform/scheme, endpoint target, TLS policy, and connection test audit (`RouterEditorSections.swift:1-168`, `RouterEditorDiagnosisSections.swift:1-150`). Preserve complete controller name and endpoint/host. Secret/X-Key is credential-only and must remain secure; never echo it in diagnosis, logs, diagnostics or copy reports.

Actions are Save, Cancel, Test, and close editor. They belong in native toolbar or same-window footer with clear disabled/loading/success/error state. Test must use existing AppModel/endpoint-check path, not SparkXie/local probing. Save must update `RouterProfile`/secret store through existing persistence path; do not add compatibility wrappers for old editor concepts.

#### Layout and states

- Wide: native `Form` on the left/primary region and diagnosis/status on the right/adjacent region; no stacked card wall. Keep endpoint full-width/selectable and use wrapping labels.
- Narrow: one `Form` column with diagnosis below; toolbar actions remain reachable and do not move into a modal.
- Empty/new draft: required fields visibly invalid only after interaction or Test/Save; no mock endpoint or placeholder controller data.
- Testing: disable conflicting Save/Test, show per-check state. Ready/warning/failed use existing `ConnectionCheckState` tint semantics (`RouterEditorView.swift:86-107`).
- Save failure: keep draft and field-level/inline error. Cancel: return to previous workbench state without destructive confirmation unless unsaved changes policy explicitly requires it. Unsupported/future controller family: show capability-only message; do not enable invented operations.

#### Files/tests/verifier

Change `RouterEditorView.swift`, `RouterEditorSections.swift`, `RouterEditorDiagnosisSections.swift`, and `RouterDraft.swift` as needed; reuse existing `ControllerBayPresentation`, `ControllerKind`, `ControllerScheme`, `SurgeControllerPlatform`, `ConnectionTestReport`, secret store and AppModel persistence/test methods. Add tests for full endpoint/name rendering, secure secret handling, validation, test state transitions, unsupported-family capability-only behavior, Save/Cancel identity, Chinese/English and four font scales. Verifier should reject mock endpoint literals, raw secret interpolation, modal editor presentation, old visible terminology, and endpoint truncation.

### 7. SparkXie reference: what is semantic only, and what must not be copied

Useful semantic references found in `tmp/codex/sparxie-ui-reference`:

- `lib/screens/connections_screen.dart` and `lib/widgets/connection_detail_sheet.dart` enumerate host, connection ID, network/type, source/destination, inbound, DNS/sniff, process/path/UID, rule/payload, chains, bytes, start time and connection logs. Mica should use the field vocabulary but keep details in the same main window, not a Flutter sheet.
- `lib/screens/rules_screen.dart` uses payload/type/outbound and filtering vocabulary; Mica maps that to `RuleSnapshot` and its remote response order.
- `lib/screens/resources_screen.dart` and `lib/src/rust/backend/api/providers.dart` show provider kind, type, vehicle, behavior, count, updated time and update intent; Mica maps only to `ProxyProviderSnapshot`/`RuleProviderSnapshot` and `AppModel.updateProxyProvider`.
- `lib/screens/settings_screen.dart`/`core_config_screen.dart` show settings/config concepts; Mica may use the conceptual grouping but only exposes fields and remote actions present in Mica’s contract.

Explicitly not portable: local Rust daemon APIs under `lib/src/rust/backend/api/`, local session notifiers under `lib/session/`, process icon/cache behavior, local provider/rule update implementation, backend switcher, local ordering, or any local core/system operation. Mica remains remote-controller-only.

## Files found

- `.trellis/spec/frontend/workbench-ui-contract.md` — fixed area/navigation, full-visible data, no ordinary modal, Liquid Glass placement and validation contract.
- `.trellis/spec/backend/controller-data-contract.md` — remote response/order/availability preservation requirements.
- `.trellis/tasks/07-10-macos27-liquid-glass-ui-rebuild/design.md` — Phase 5-7 target layout and native component decisions.
- `.trellis/tasks/07-10-macos27-liquid-glass-ui-rebuild/implement.md` — Phase 5-7 acceptance checklist.
- `Sources/Mica/Features/Workbench/WorkbenchConnectionsView.swift` — current connection table/inspector, close controls, filtering and truncation defect.
- `Sources/Mica/Features/Workbench/WorkbenchRulesSourcesLogsViews.swift` — current rules/sources/logs grids, inspectors, reload/update/log controls and truncation defect.
- `Sources/Mica/Features/Workbench/WorkbenchSettingsView.swift` — current appearance/controller summary and preference propagation.
- `Sources/Mica/Features/Routers/Views/RouterEditorView.swift`, `RouterEditorSections.swift`, `RouterEditorDiagnosisSections.swift` — current controller editor, test state and diagnosis.
- `Sources/Mica/App/AppModel.swift` and `Sources/Mica/App/AppModel*.swift` — remote operations, task state, partial snapshot semantics and session actions.
- `Sources/MicaCore/Models/MihomoModels.swift` — config, rules, providers, connections and logs field contracts.
- `Sources/MicaCore/Models/UnifiedControllerModels.swift` — controller families, capabilities, actions and health states.
- `Sources/MicaCore/API/UnifiedControllerAdapters.swift` — remote adapter snapshot boundary and partial enhanced endpoint behavior.
- `Tests/MicaCoreTests/MihomoModelsTests.swift`, `UnifiedControllerModelsTests.swift`, `SurgeHttpAPIClientTests.swift` — existing decode/order/endpoint/capability test patterns.
- `tmp/codex/sparxie-ui-reference/lib/screens/{connections_screen.dart,logs_screen.dart,rules_screen.dart,resources_screen.dart,settings_screen.dart,core_config_screen.dart}` — semantic UI reference only.
- `tmp/codex/sparxie-ui-reference/lib/src/rust/backend/api/{connections.dart,rules.dart,providers.dart,control.dart}` — reference backend semantics; not portable into Mica.

## External references

- Apple SwiftUI/macOS 26-27 native components as selected by the task design: `NavigationSplitView`, `Table`, `Form`, `Section`, `LabeledContent`, native `Picker`/`Toggle`/`TextField`, `DisclosureGroup`, toolbar commands, and standard destructive confirmation. The repository’s `research/apple-liquid-glass.md` and `.trellis/spec/frontend/workbench-ui-contract.md` are the local design authority for Liquid Glass placement.
- No external backend or SparkXie behavior is an implementation dependency. Mica’s authoritative runtime contract is the remote adapter/API and the Swift models listed above.

## Related specs

- `.trellis/spec/frontend/workbench-ui-contract.md`
- `.trellis/spec/backend/controller-data-contract.md`
- `.trellis/spec/frontend/quality-guidelines.md`
- `.trellis/spec/frontend/type-safety.md`
- `.trellis/spec/guides/cross-layer-thinking-guide.md`
- `.trellis/spec/guides/code-reuse-thinking-guide.md`

## Caveats / Not Found

- The current unified snapshot exposes aggregate `rulesCount/providersCount/connectionsCount` and policy/traffic projections, while detailed rules/providers/connections remain in Mica’s dashboard/Mihomo models; Phase 5-7 should not invent new fields in the unified model just for UI convenience.
- The current `ProxyProvidersResponse.providerList` and `RuleProvidersResponse.providerList` sort by name. This is an existing model convenience, not permission to impose SparkXie ordering on the new UI; the implementation should either preserve an available controller order or label the projection as unordered and avoid business-order assertions.
- No remote mutation contract for arbitrary `ConfigResponse` fields was found. Configuration should therefore be read-only until a concrete adapter action exists.
- The current Activity/Rules/Sources views already contain substantial same-window inspector behavior, but their hand-built grids, fixed widths and middle truncation are not acceptable for the rebuild.
- No task, spec, or reference file authorizes changing system proxy, firewall, local core, local Rust daemon, or other system behavior; such behavior must remain absent.
