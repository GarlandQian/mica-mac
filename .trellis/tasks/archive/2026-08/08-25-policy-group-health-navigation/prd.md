# PRD: 策略组健康排障与 Workbench 实时链路收口

## Goal

完成策略组健康排障、真实字段检查和跨页节点定位，并修复本轮全局审计确认的 Workbench 实时数据冻结、状态失真和交互失效问题。修复只使用现有 controller API、已有快照和当前能力矩阵；不新增端点、后台轮询、远程写操作或控制器管理行为。

## User Value

- Mihomo/Nikki/OpenClash/CMFA/Stash 的某个实时频道失败时，其余频道继续更新；用户主动刷新能够恢复请求中的实时流。
- 一个可选端点失败时，同刷新 lane 的其他端点不会被永久连坐冻结。
- 策略组页面始终给出真实的加载、空数据、无匹配、筛选遮挡和目标失效状态，不再出现空白主体或错误归因。
- 从首页拓扑、策略检查器或策略组工具栏定位时，能够精确展开、滚动、高亮并检查真实节点；重名组也不会定位到错误 occurrence。
- 健康分类、延迟、连接速率、freshness 和辅助功能名称与真实数据语义一致。

## Confirmed Defects

| ID | Severity | Evidence | Required outcome |
| --- | --- | --- | --- |
| D1 | P1 | `AppModelLiveSession.swift:1913-2017,2491-2532`; `AppModelLiveSessionRuntime.swift:57-75`; `LiveSessionRuntime.swift:166-255` | 一个 Mihomo channel 终止不得使共享 runtime 失活并冻结其余 domain；手动 Refresh 必须能重建请求中的实时流。 |
| D2 | P1 | `AppModelLiveSession.swift:681-685,769-778,831-904,922-982`; `LiveSessionRefreshModels.swift:372-380` | 多端点 lane 的部分失败不得把成功端点永久标成 terminal；端点健康与重试状态必须隔离。 |
| D3 | P1 | `WorkbenchOverviewTopologyView.swift:275-277` | 拓扑菜单和 VoiceOver 的 Open Proxies 必须先暂存当前策略节点目标，再切页。 |
| D4 | P1 | `WorkbenchProxies.swift:155-220` | `arrangedGroups` 非空但 `visibleGroups` 为空时显示 no-match，不得渲染空白 ScrollView。 |
| D5 | P1 | `WorkbenchOverviewPolicyInspection.swift:735-768`; `WorkbenchProxyPresentation.swift:1132-1180` | 跨页目标携带稳定 occurrence ID；重名原始 group ID 不得退化为 ambiguous 或选择 first match。 |
| D6 | P1 | `WorkbenchProxies.swift:178-220,229-234`; `WorkbenchProxyGroupPanels.swift:305-350` | 节点 ID 必须属于实际的程序化滚动目标范围；定位必须把节点带入可视区域。 |
| D7 | P2 | `WorkbenchProxyPresentation.swift:994-1010`; `WorkbenchProxies.swift:807-847,913-930` | 隐藏 GLOBAL、空目录、缺组、重名组和缺节点保留各自真实原因；空目录也必须消费并解释导航请求。 |
| D8 | P2 | `WorkbenchProxies.swift:850-930` | 一次 Clear Filters and Locate 清除全部阻挡目标的本地搜索、组内查询和健康筛选，然后完成定位。 |
| D9 | P2 | `WorkbenchProxies.swift:719-761` | Locate Current Node 只解析控制器当前选择，不得优先定位仅在 inspector 中查看的非当前节点。 |
| D10 | P2 | `AppModelLiveSession.swift:1708-1725`; `OperationSessionModels.swift:745-749` | 跨 domain 乱序发布不得让 `lastSuccessAt` 倒退。 |
| D11 | P2 | `OperationSessionModels.swift:506-535`; `WorkbenchConnections.swift:209-271` | 重复 reported connection ID 不得共用一份 previous counter 并产生错误速率。 |
| D12 | P2 | `WorkbenchProxyPresentation.swift:166-218`; localization keys `routing.health_filter_attention/slow` | Attention 覆盖所有非健康节点；Slow 只覆盖 slow，不与 timeout/unavailable 混淆。 |
| D13 | P2 | `WorkbenchProxyPresentation.swift:1051-1085`; `WorkbenchProxyGroupPanels.swift:473-479,691-703` | 非正延迟显示 unavailable，不得呈现为绿色 `0 ms` 或负值。 |
| D14 | P2 | `WorkbenchProxyGroupPanels.swift:522-553` | 图标节点测试按钮提供本地化的 accessibility label，并保留 tooltip/help。 |

完整证据与触发序列记录在 `research/live-session-functional-audit.md`、`research/swiftui-workbench-bug-audit.md` 和 `research/current-diff-functional-audit.md`。

## In Scope

1. 修复 D1-D14，并为每个状态序列添加离线回归测试。
2. 保留原策略组能力：健康摘要、本地健康筛选、真实字段 tooltip/inspector、定位当前节点、首页跨页定位和短暂高亮。
3. 保留控制器顺序和 optionality；所有远程选择/测试动作继续走现有 capability、controller ID 和 generation 防线。
4. 中英双语、VoiceOver、键盘、Reduce Motion、单一外层滚动和现有滚动期间快照延迟策略。
5. 使用现有离线 benchmark 检查当前代理目录投影和共享实时链路没有超过项目 10% 回归阈值。

## Out of Scope

- 新 controller endpoint、transport、capability、后台自动测速或更高轮询频率。
- 自动切换最快节点、改写控制器顺序、跨组批量操作或未经确认的远程写操作。
- 自定义悬浮 HUD、第二 inspector、嵌套 ScrollView、内容 Liquid Glass 或新 Swift package。
- 修改路由器、OpenWrt、Nikki/LuCI、系统网络、防火墙、SSH 或 `ubus`。
- 自动化检查连接真实控制器；运行时 UI/controller smoke 继续需要单独授权。

## Key Decisions

- `LiveSessionRuntime` 生命周期属于 controller ID + generation，而不是任一单独 channel。终态 channel 将聚合 live/session 状态标为 partial（首个 baseline 前为 failed），但不得使健康 sibling 的 actor ingestion 失效；retryable 波次仍复用既有共享 reservation 做一次受控全流重建。
- 手动 Refresh 除 REST lanes 外重启当前 controller 请求中的 live streams；所有重启继续验证 controller ID/generation 并取消旧 producer。
- 多端点 lane 发布成功端点并保留失败端点的 last-good/stale 状态；单个 optional endpoint 的 terminal 分类不升级为整个 lane terminal。
- Attention 是 `health != healthy` 的诊断聚合；Unavailable 和 Slow 是可继续下钻的子集，Slow 不包含 timeout。
- 非正 latency 保留原始数据于完整字段检查，但摘要、筛选、颜色和紧凑显示一律按 unavailable 处理。
- 跨页定位从可见投影携带稳定 occurrence ID。原始重名 group ID 只可得到 truthful ambiguous，不允许 first-match 猜测。
- Clear Filters and Locate 一次清除全部本地阻挡条件。GLOBAL 可见性是独立偏好，页面显示专用 obstruction；只有用户明确执行 Show GLOBAL and Locate 才修改全局偏好。
- 程序化节点定位改用包住现有唯一 ScrollView 的 `ScrollViewReader`（或等价的单目标范围机制），等待展开后的节点 ID materialize 后只滚动一次。

## Acceptance Criteria

- [x] AC1：Mihomo traffic/log/memory/connections 的 transient 或 retry-once 失败复用一个共享 reservation，并通过受控全流重建恢复；terminal 单 channel 失败保留健康 sibling 发布。Refresh 能恢复请求中的流，旧 producer 不能污染同 generation 的 replacement runtime 或新 generation。
- [x] AC2：Mihomo/Surge 多端点 lane 的混合成功/失败按 endpoint 隔离；成功端点保持周期刷新，失败端点保留 last-good/stale 和真实原因。
- [x] AC3：`lastSuccessAt` 单调不减；重复 connection ID 的本地派生速率按 occurrence 正确计算，无法稳定匹配时保持 unavailable 而不猜测。
- [x] AC4：每个可见策略组展示只来自 `alive`、正延迟/历史和 `LatencyHealthGrade` 的健康摘要；Attention、Unavailable、Slow、Current 语义与文案一致，控制器顺序不变。
- [x] AC5：加载、unsupported、真实空目录、GLOBAL 偏好隐藏、全局搜索无匹配、组内/健康筛选无匹配、首次失败和 retained stale 均有独立真实状态。
- [x] AC6：可见目标定位会展开组、一次滚动到节点、短暂高亮并同步 inspector；工具栏 Current 解析控制器当前节点，普通快照更新不抢滚动。
- [x] AC7：拓扑、VoiceOver、策略 inspector 的 Open Proxies 都携带 controller ID、generation、occurrence ID 和 node name；重名、缺失或过期目标不触发远程动作。
- [x] AC8：目标被多个本地筛选阻挡时，一次明确操作完成清除和定位；GLOBAL 偏好不被静默修改，专用恢复操作必须由用户触发。
- [x] AC9：所有显示字段保留 controller optionality；非正延迟不显示为有效 ms；不可选择组可查看/筛选/定位但不能启动选择写操作。
- [x] AC10：中英双语覆盖状态、原因和动作；图标命令有本地化名称；Reduce Motion 下使用静态高亮。
- [x] AC11：离线测试覆盖 D1-D14 的触发序列、controller/generation 拒绝、取消、重连、重复 ID、空状态和滚动请求幂等；自动化不联系控制器。
- [x] AC12：Swift build/test、source verifier、localization JSON、diff check 全部通过；两个可比 Release benchmark 不出现稳定超过 10% 的无关回归。

## Risks And Deferred Validation

- 当前 100,000 节点代理目录两轮离线投影为 57.49/55.46 ms；10,000 连接首帧为 4.956/4.950 ms，相对旧可比报告约改善 26.6%。25 个匹配 case 校验和一致且无稳定超过 10% 的回归；主线程目录 churn 仍需 Instruments 验证。
- Apple 的 `scrollTargetLayout` 语义确认嵌套 target layout 不会成为额外目标；修复后仍需一次用户授权的运行时 UI smoke 验证实际滚动、高亮和会话切换。
- 本次静态审计和自动化均未连接 Nikki 或任何真实 controller，因此不能把真实设备网络可达性纳入自动验收。
