# Actions 全控制器审查

## 用户样本与当前行为

用户截图显示 Actions 顶部目标为 `http://127.0.0.1:9090`，状态徽章写“2 项操作”，正文只有 Test 与被禁用的 Refresh，下面留下大面积空白。这个样本同时暴露了连接配置、可执行性语义和页面构图三个问题，不能用增加装饰或 Nikki 专用文案解决。

- `WorkbenchActionsProjection.connectionActions` 固定包含 Test 与 Refresh；`supportedOperationCount` 统计的是 capability 匹配项，而不是当前真正可执行的命令（`Sources/Mica/Features/Workbench/WorkbenchActions.swift:24`、`:67`）。
- 未完成自动探测时使用 `.probeReadiness`，它只有 `snapshot == true`，因此 Test 与 Refresh 都被算入“2 项操作”（`Sources/MicaCore/Models/UnifiedControllerModels.swift:496`）。
- Refresh 还要求 live session 允许命令，所以连接失败时会被禁用（`Sources/Mica/App/AppModelLiveSession.swift:13`）。结果是徽章宣称两项可用，实际上只有 Test 可以执行。
- `127.0.0.1` 从 Mica 进程看始终是当前 Mac，不是 OpenWrt 路由器。当前 RouterDraft 只校验 host 非空、格式和 port 范围，不解释 loopback 的目标含义（`Sources/Mica/App/RouterDraft.swift:110`）。

## 跨控制器命令边界

Actions 当前只应展示 Mica 已实现且由当前 adapter/capability/runtime state 共同证明可执行的命令。下表是现有合同能够产生的 Actions 候选，不是未连接时应承诺的固定数量。

| Controller family | 已有 Actions 候选 | 关键边界 |
| --- | --- | --- |
| Auto Detect / unresolved | Test；live 后才有 Refresh | 未探测成功前不能推断 controller-specific 命令 |
| mihomo / Nikki / OpenClash | Test、Refresh、Reload Rules/Providers、configuration/GeoData、memory read、DNS/FakeIP flush、core restart/upgrade | Nikki/OpenClash 仍只通过已启用的 external-controller；lifecycle 保持确认与 generation 门控 |
| CMFA | mihomo-compatible 子集，包括 rules/providers、memory、DNS/FakeIP | 不显示 configuration/GeoData/core lifecycle |
| Stash | Test、Refresh、Reload Rules/Providers | 不显示未证实的 backend maintenance |
| sing-box | Test、Refresh；其余真实命令留在 Proxies、Connections、Configuration、Tailscale 等职责页 | runtime memory 是订阅状态，不是 Actions 中可分发的 Mihomo memory command |
| Surge | Test、Refresh、Reload Rules/Profile、DNS flush | 使用 API Key 与 Surge HTTP API 路由，不复用 Mihomo lifecycle/maintenance |
| unknown / unsupported | recovery 或 unsupported state | 不显示空分组、禁用命令墙或推测能力 |

当前还有一个跨控制器语义缺陷：sing-box capability matrix 可把 `memory` 标为 supported（`Sources/Mica/App/AppModelReadiness.swift:269`、`:449`），Actions 会据此生成按钮；但 `performDiagnosticsRuntimeOperation("memory")` 调用 `checkMihomoMemory()`，而 runtime router guard 不接受 sing-box（`Sources/Mica/App/AppModelRuntimeOperations.swift:5`、`:307`）。新投影必须区分“可观察状态”与“此页面可执行命令”，并以真实 dispatcher 支持为最终门控。

## 连接目标与 Nikki 官方证据

Nikki 当前官方 LuCI 源码在 `External Control Config` 下定义 `API Listen`、`API TLS Listen` 和 `API Secret`。这与 Mica 的 host、port、scheme、secret 字段一一对应：

- [Nikki official mixin UI source](https://github.com/nikkinikki-org/OpenWrt-nikki/blob/main/luci-app-nikki/htdocs/luci-static/resources/view/nikki/mixin.js#L342-L365)
- [Nikki official repository](https://github.com/nikkinikki-org/OpenWrt-nikki)

Mica 不应修改 Nikki/OpenWrt 配置或防火墙。产品侧只提供真实目标解释和下一步：loopback 标记为“This Mac”；远端 router/controller 失败时引导用户填设备 LAN IP/hostname、匹配 API port/secret，并进入 Edit Controller 或 Diagnostics。显式 mac-local controller 不把 loopback 当成错误。

## 设计结论

1. Actions 必须有 recovery、checking、ready/partial 和 unsupported 构图，不能让所有状态都落入同一 grouped form。
2. 标题区域显示 controller/session 状态；若保留数量，只统计当前可执行命令，不能把 disabled/unknown 项算作“可用”。
3. Recovery 状态优先显示目标、失败原因和 Test / Edit Controller / Open Diagnostics，不渲染空分组或一个被禁用的 Refresh。
4. Ready/partial 状态按真实命令类别自适应为宽屏双栏、窄屏单栏；高风险 lifecycle 独立且保持现有确认。
5. 不用 Nikki 的能力替代其他 controller；共享视觉模型，保持每个 adapter 的真实 action/dispatcher boundary。
