# Diagnostics 问题投影映射

## 目的

这份映射定义默认 UI 如何把现有真实状态收敛成少量可操作问题。它不替代底层 capability、endpoint、session 或 report 模型，也不创建新的健康分数。

## 权威输入

| 输入 | 职责 | 不能表达的内容 |
| --- | --- | --- |
| `ControllerSessionPresentationState.state` | 当前会话生命周期：connecting/live/stale/partial/failed/stopped | 具体数据域失败 |
| `ControllerSessionPresentationState.lastSuccessAt` | 最近一次成功 baseline，用于 retained/stale 说明 | 不等于每个 endpoint 的检查时间 |
| `DashboardSessionControls.dashboardUpdatesPaused` / `presentationPausedAt` | 用户主动暂停本地 presentation | 不代表远端会话停止 |
| `ControllerHealthSnapshot` | 基础/增强 endpoint 的当前健康和检查时间 | 固有 capability 支持范围 |
| `rulesSnapshotState` / `providersSnapshotState` | 两个可选数据域的当前可见性 | 不能在 capability 为 false 时当作故障 |
| `LiveStreamState` | 当前实时/近实时流状态 | 必须结合 controller capabilities 判断是否预期 |
| `selectedUnifiedCapabilities` | 当前有效 controller 类型真实支持的产品域与操作 | false 表示不支持，不表示故障 |
| `selectedControllerAdapter` | 请求/探测类型与适配置信心 | 不是网络健康摘要 |
| `controllerMetadata` / `UnifiedControllerSnapshot` | 版本、模式和计数等技术事实 | 只作为摘要或证据，不自行产生问题 |

不以 `TrialSessionSnapshot.lastCommandStatus` 作为当前健康来源。历史命令可能已经失效，也可能记录复制报告、关闭连接等与健康无关的操作。

## 总体状态优先级

1. 无控制器：沿用 Workbench 根级 no-controller state，不构建诊断快照。
2. 首次 baseline 前正在连接/检查：`checking`，显示进度，不制造问题。
3. 首次 baseline 前失败或没有任何可保留数据的 controller-wide failure：`blocked`。
4. 已有 baseline，但处于 stale reconnecting、failed、partial、paused 或存在数据域问题：`needsAttention`。
5. 会话 live 且没有投影问题：`ready`。
6. idle/stopped 且窗口仍要求当前 controller 会话：`needsAttention`；正常窗口消失造成的 stopped 不会在可见 Diagnostics 中出现。

总体状态表达当前可用性，不等于最严重问题的颜色。已有 retained data 时，即使连接问题严重，页面仍明确说明“显示最近成功数据”，不把旧数据冒充实时。

## 问题类别与动作

| 稳定 ID | 触发条件 | 严重度 | 影响 | 主动作 |
| --- | --- | --- | --- | --- |
| `controller-access` | 首次连接失败、health 为 auth/wrongTarget/offline、或 session failed 且没有更具体可用状态 | critical | 所有 controller 数据页 | auth/wrong target -> Edit Controller；其他 -> Recheck Now |
| `adapter` | 有效 adapter 为 unsupported/unknown，且探测已结束 | critical | 所有 capability-driven 页面 | Edit Controller |
| `session-stale` | `staleReconnecting`，或失败时仍保留 `lastSuccessAt` | warning | 所有实时数据；旧快照仍可查看 | Recheck Now |
| `presentation-paused` | `dashboardUpdatesPaused == true` | warning | UI 停留在暂停时刻；远端可能仍在更新 | Resume Presentation |
| `session-partial` | `.partial(message)` 且没有更具体 endpoint/stream issue | warning | message 指示的当前会话范围 | Recheck Now |
| `endpoint-version` | version endpoint 在有 controller 时失败 | critical/ warning，取决于是否已有 baseline | 控制器身份与全部 snapshot | Edit Controller 或 Recheck Now |
| `endpoint-configs` | configs endpoint 预期存在且失败 | warning | Configuration、Overview metadata | Open Configuration |
| `endpoint-proxies` | policy groups 受支持且 proxies endpoint 失败 | warning | Overview、Proxies | Open Proxies |
| `endpoint-connections` | connections/active requests 受支持且 endpoint 失败 | warning | Overview、Connections | Open Connections |
| `endpoint-rules` | rules capability 为 true 且 endpoint/rules snapshot 失败 | warning | Rules、Overview routing | Open Rules |
| `endpoint-providers` | providers capability 为 true 且 endpoint/provider snapshot 失败 | warning | Sources、Overview routing | Open Sources |
| `live-telemetry` | traffic/logs capability 预期存在，live stream 为 partial/failed | warning | Overview、Connections、Logs 中适用范围 | Open Overview 或 Logs；详情说明受影响域 |

问题动作只允许以下 intent：

- `refresh`：调用现有 `refreshSelectedRouter()`，只读且 generation-safe。
- `resumePresentation`：调用 `setPresentationPaused(false)`，只改变本地展示。
- `editController`：复用当前同窗口 RouterEditor。
- `navigate(WorkbenchDestination)`：进入现有职责页面，由该页面决定后续远端动作与确认。
- `copyReport`：只用于技术/支持区域，不作为健康修复。

Diagnostics 不直接调用 reload rules/providers、provider update、flush、close、restart 或 upgrade。

## 去重规则

按以下顺序生成并去重：

1. Controller-wide access failure 会压制由同一次无响应产生的全部 endpoint failure 行。
2. Adapter unsupported/unknown 与 wrong-target 同时出现时只保留可解释根因更强的一条；wrong-target 优先。
3. `presentation-paused` 优先解释本地 UI freshness；暂停期间 pending presentation 不再产生新的可见 endpoint 问题。
4. endpoint failure 优先于相同域的 `EnhancedSnapshotState.unavailable`。
5. rules/providers capability 为 false 时，相应 unavailable 状态是固有限制，不生成问题。
6. stream capability 为 false 时，`.unavailable`/`.stopped` 不生成问题。
7. `.partial(message)` 只在没有更具体 endpoint 或 stream 问题时生成 fallback issue。
8. 最近 operation/command failure、诊断复制状态和 command counts 不参与问题投影。

问题先按 severity 排序，再按固定用户影响顺序排序；稳定 ID 不包含时间戳或数组索引。Controller 报告顺序仍保留在技术详情和报告中。

## Available Now 投影

正常能力不逐 API 显示，只投影产品区域：

| 产品区域 | 支持条件 | 当前可用条件 |
| --- | --- | --- |
| Policies | `policyGroups` | proxies/policy snapshot 未失败 |
| Connections | `connections || activeRequests` | connection domain 未失败 |
| Rules | `rules` | rules endpoint/snapshot 未失败 |
| Sources | `providers` | provider endpoint/snapshot 未失败 |
| Live telemetry | `traffic || logs` | stream 为 live/nearLive，或 controller 使用真实 polling 且 session live |
| Configuration | `snapshot` 或任一 config mutation capability | configs/metadata 已取得且未失败 |

固有不支持的区域直接省略；暂时失败的支持区域从 Available Now 移到问题列表。UI 使用平面 icon + label/value 布局，不渲染大量绿色 badge。

## 技术详情

默认折叠的单一技术区域包含三组：

1. Controller：名称、请求/检测类型、可见 endpoint、版本、模式。
2. Session：生命周期、paused/live/stale、最近成功时间、最近 endpoint 检查时间。
3. Evidence：controller 报告顺序的 endpoint 状态，以及支持能力的紧凑摘要。

UI 不显示 credential、authorization、subscription URL、secret-store、raw body、raw stream、机器 assignment 或内部 backend-boundary 文案。完整凭据安全机器报告继续通过单一 Copy Report 命令提供。

## 选择状态

- 宽窗口默认选择排序后的第一条问题。
- 投影更新后保留仍存在的 `selectedIssueID`；被解决后选择下一条排序问题。
- controller ID 或 session generation 改变时清空旧选择，再选择新快照第一条问题。
- 窄窗口使用同一个选择 ID，将选中详情展开在对应问题下，不维护第二份展开集合。
- 完全健康时清空选择并使用单栏摘要。
