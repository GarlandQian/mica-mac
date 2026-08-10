# 诊断与操作工作台联动重构

## Goal

把 Mica Diagnostics 从内部检查清单重构为行动优先的诊断工作台，同时把 Actions 从静态操作表单重构为覆盖全部 controller family 的能力安全命令工作台。用户无需理解 controller API 或 Mica 内部模型，就能判断当前控制器是否可用、为什么命令不可用、下一步应重检、编辑还是进入对应职责页；连接成功后只看到当前 controller 真实可执行的命令，高级用户仍能查看真实技术证据并复制凭据安全的支持报告。

## Background

当前页面虽已有健康结论和 Copy Report，但默认信息架构仍以实现数据源为中心：Controller metadata、Endpoint results、Troubleshooting steps、Check history、Capabilities、Data availability、Monitoring status 和 Copy/export policy 被放成八个同级折叠区。`endpointCheckSteps` 与 `checkResultRows` 重复投影 profile、连接测试、快照和操作历史；Capability Matrix、Data Coverage 与 Observability Readiness 也重复表达支持度。用户必须自行把这些事实拼成问题与动作。

当前视觉失衡同样来自结构：`WorkbenchManagementCanvas` 最大宽度为 1180pt，事实网格与长 outline 在宽窗口留下大片空白，在窄窗口形成过长扫描路径。旧“status band + outline + fact grid”方案已被用户否定，不能只做配色、字号或图标润色。

Actions 也存在同类但不同根因的失衡。用户截图中的自动探测目标为 `http://127.0.0.1:9090`；`.probeReadiness` 让 Test 与 Refresh 都进入 `supportedOperationCount`，但连接失败时 Refresh 又被 live-session 门控禁用。页面因此宣称“2 项操作”，实际只有一项可执行，并把 recovery state 渲染成一张稀疏 grouped form。`127.0.0.1` 还只指向当前 Mac，无法到达路由器上的 Nikki；当前 UI 没有解释 loopback 目标身份，也没有在失败态直接提供 Edit Controller 与 Diagnostics 去向。

详细源码审查、历史结论和 Apple 官方模式研究见：

- `research/current-state-audit.md`
- `research/issue-projection-map.md`
- `research/actions-all-controller-audit.md`

## Confirmed Product Decisions

- 使用“行动优先的双层工作台”：默认层负责判断、影响和处置；完整技术事实进入次级详情与安全报告。
- 默认直接显示 live session 自动维护的诊断结果，不创建独立诊断会话；唯一主检查入口是只读“立即重新检查”。
- Diagnostics 只发现、解释和引导。它不直接执行 reload、provider/rule update、flush、关闭连接、core restart/upgrade 等远端操作。
- 问题动作仅限只读重检、恢复本地展示、编辑控制器、复制安全报告和跳转到现有职责页面。
- 存在问题时采用自适应 master-detail：宽窗口为问题列表 + 选中问题详情，窄窗口在选中行下顺序展开；完全健康时退化为单栏摘要。
- 不保留旧八组技术 disclosure 作为默认结构，也不把固有不支持、历史命令失败或诊断复制状态当成当前故障。
- Actions 面向全部已支持 controller family 统一重构，不做 Nikki 专用页面或特判视觉；Nikki 只作为 loopback/未连接样本。
- Actions 区分 checking、recovery/blocked、ready/partial 与 unsupported；恢复态和命令态使用不同构图。
- Actions 只把当前真实可执行且有正确 dispatcher 的命令计为可用；观察能力、静态 capability、disabled 命令和未完成探测不伪装成“可用操作”。
- 远端 controller 使用 loopback 时给出目标身份说明和修正路径；显式 mac-local controller 仍允许 loopback，不把提示升级为无条件校验错误。

## In Scope

- 新增纯 Diagnostics 问题投影，将现有 session、endpoint、capability、snapshot 和 stream 状态归一为稳定的总体状态、问题、影响、证据、动作与 Available Now 区域。
- 建立 controller-wide failure、stale/reconnect、presentation paused、partial session、基础 endpoint、Rules/Sources 数据域、live telemetry 和 adapter 状态的优先级与去重规则。
- 重建 Diagnostics 根页面和组件：状态摘要、问题 master-detail、健康态摘要、Available Now、单一技术详情和 Copy Report。
- 让“立即重新检查”复用现有 `refreshSelectedRouter()`；在 Diagnostics 目的地隐藏会造成第二套语义的全量 Test 入口。
- 为问题项接入现有同窗口 RouterEditor、Workbench 目的地导航和本地 Resume Presentation intent。
- 更新英文与简体中文、键盘/VoiceOver、四档字号、Reduce Motion、Increase Contrast 和宽度自适应行为。
- 更新旧 Diagnostics 投影测试、源码结构验证与 Workbench UI 合约，使它们约束新问题模型而非旧 outline。
- 保留并验证现有凭据安全导出、capability/generation 门控和 controller/session 合同。
- 新增纯 Actions availability/command 投影，以 controller kind、adapter、session、capability、runtime row 与真实 dispatcher 支持共同决定页面状态、分组、可执行数、风险和 disabled reason。
- 重建 Actions：恢复/探测状态、真实命令分组、宽屏双栏/窄屏单栏、高风险 lifecycle 区和指向 Diagnostics/RouterEditor/职责页的安全 intent。
- 覆盖 Auto Detect、mihomo、Nikki、OpenClash、CMFA、Stash、sing-box、Surge、unknown/unsupported；共享布局但不共享未经证实的命令集合。
- 为可见 controller target 增加本机 loopback 与远端目标语义；在 Actions、Diagnostics 和现有 RouterEditor diagnosis 中复用，不连接或修改 router。

## Requirements

### R1. Current Verdict

- 首屏必须显示当前 controller、总体状态、数据 freshness 和稳定时间戳。
- 状态至少区分 checking、ready、needs attention、blocked、paused/stale retained data 和无 controller。
- 不创建健康分数，不用绿色数量掩盖关键失败，也不把旧数据表现为 live。

### R2. Actionable Issues

- 每个问题必须有稳定 ID、严重度、用户可读标题、影响范围、证据时间/说明和最多一个主动作。
- 问题按严重度与用户影响排序；controller-wide 根因压制由同一失败产生的重复 endpoint 行。
- capability false 表示固有不支持，不生成故障；只有 contract 预期存在但当前失败的数据域才进入问题列表。
- 历史 command/operation 结果只有仍能证明当前状态时才可作为证据，不能参与总体健康聚合。

### R3. Safe Actions

- Recheck 复用现有只读 session refresh，并继续校验 selected controller ID 与 generation。
- Resume 只解除本地 presentation pause。
- Edit Controller 复用当前同窗口 editor；导航动作进入 Overview、Proxies、Connections、Logs、Rules、Sources、Configuration 或 Actions 的既有页面。
- Diagnostics 不直接执行任何会改变远端 controller 状态的修复命令。

### R4. Responsive Workspace

- 页面使用专用全宽 Diagnostics canvas，不继承管理表单的 1180pt 阅读宽度上限。
- 有问题且宽度足够时，列表与详情同屏；窄宽度只保留一个滚动所有者，详情在选中问题下展开。
- 选择默认落在最高优先级问题；投影更新时保留仍有效选择，问题解决或 controller/generation 切换时稳定迁移或清空。
- 健康态不显示空 master/detail 框架，也不渲染冗长的“全部通过”列表。

### R5. Technical Evidence

- 默认折叠的单一技术区域按 Controller、Session、Evidence 分组，不恢复八个顶层 disclosure 或 disclosure 嵌套。
- 可见 UI 不输出 credential、token、authorization、subscription URL、Keychain/secret-store 内容、raw response/stream body、机器 assignment 或 backend-boundary 文案。
- 单一 Copy Report 入口继续提供足够的凭据安全技术材料；Endpoint Results 和 Check Results 不再各占一个顶层复制按钮。

### R6. Native UI And Accessibility

- 使用现有 `MicaStyle`/Workbench primitives、SF Symbols、系统语义色和原生控件；内容层保持不透明、扁平，无自定义玻璃、装饰渐变、嵌套卡片或 badge 墙。
- 状态同时使用符号、文字和语义色；选中问题使用稳定 selection fill/leading rail，不只靠颜色。
- 页面必须支持英文与简体中文、四档字号、浅色/深色、键盘、VoiceOver、Reduce Motion 和 Increase Contrast。
- 动态状态更新不能触发全页隐式动画、嵌套滚动、时间戳驱动 identity 或高频业务数据导致的无关重建。

### R7. Truthful Actions Availability

- Actions 总体状态至少区分 no controller、checking/probing、recovery/blocked、ready、partial 和 unsupported；失败态不得继续使用普通操作表单冒充可用命令页。
- 可执行命令必须同时满足当前 controller/session/generation、capability、operation-specific readiness 和 adapter-appropriate dispatcher；静态 capability 或 status observation 本身不足以生成按钮。
- 如果显示数量，只统计当前可执行命令；disabled、unknown、固有不支持和等待探测的命令不进入“可用”计数。
- Test 在 recovery/checking 语境中是连接动作；Refresh 只有 live session 允许时才出现为可执行命令，不以被禁用的第二行制造虚假密度。

### R8. All-Controller Command Workspace

- Auto Detect 未解析时只呈现探测/修正路径；mihomo/Nikki/OpenClash、CMFA、Stash、sing-box 和 Surge 各自使用现有 capability 与 dispatcher 的真实子集。
- sing-box 的 memory/runtime subscription 只作为状态证据，不生成当前 Mihomo memory command；controller-specific 命令不能落入错误 client。
- Ready/partial 使用扁平操作分组；宽布局可双栏，窄布局单栏，危险 lifecycle 独立显示并保留 controller ID + generation 确认。
- 对仅有少量独立命令的 controller，不填充虚构操作；显示简洁状态、真实命令和可导航的职责区域，避免大面积空 form 与 disabled command wall。

### R9. Recovery And Target Semantics

- Recovery 首屏显示 controller、可见 target、当前失败原因/状态和最多一个主动作，并提供 Edit Controller 与 Open Diagnostics 的清晰次级 intent。
- loopback target 必须被标识为当前 Mac；对于路由器/远端 controller，说明应改用设备 LAN IP 或 hostname 及匹配 port/credential，但不得替用户修改 Nikki、OpenWrt、firewall 或服务。
- 显式本机 controller 允许 loopback；自动探测和未知目标使用说明性提示，不凭 host 猜测 controller family。
- 错误详情继续使用现有 typed failure reason，禁止通过本地化字符串解析来决定动作或严重度。

## Acceptance Criteria

- [x] AC1：进入 Diagnostics 后，无需展开技术详情即可看懂当前可用性、freshness、最重要问题、影响范围和首选下一步。
- [x] AC2：live session 自动结果直接可见；页面只有一个只读 Recheck 语义，不存在独立“运行全部诊断”结果源。
- [x] AC3：auth/wrong target/offline、首次连接失败、stale reconnect、partial、paused、endpoint/data-domain/stream failure 能生成稳定且不重复的问题。
- [x] AC4：固有不支持、未请求的可选流、历史命令失败和复制报告记录不会被表现为当前故障。
- [x] AC5：问题动作只执行 Recheck、Resume、Edit、Navigate 或 Copy Report；任何远端 mutation 仍在其职责页面及既有确认流程中。
- [x] AC6：宽窗口问题列表与详情同屏，窄窗口在选中行下展开；controller/generation/问题集合变化后选择无跳错、残留或崩溃。
- [x] AC7：完全健康时显示简洁单栏结论和真实 Available Now 区域，不显示空详情栏或冗长成功清单。
- [x] AC8：技术详情保留 controller 报告顺序和真实值；Copy Report 继续通过既有凭据安全与脱敏合同。
- [x] AC9：页面在窄/中/宽窗口、四档字号、英文/简体中文、浅色/深色下无重叠、截断、大面积失衡空白或不必要横向滚动。
- [x] AC10：主要流程可由键盘和 VoiceOver 完成；状态不只依赖颜色，Reduce Motion 下没有不必要结构动画。
- [x] AC11：实时刷新、pause/resume、stale reconnect 和问题解决不会引入嵌套 scroll、全树动画或由 traffic/log frames 驱动的 Diagnostics 重建。
- [x] AC12：更新后的测试、source verifier、Swift build、完整测试、localization JSON、`git diff --check` 和 Trellis validation 全部通过；不运行真实 controller smoke。
- [x] AC13：Actions 在 no controller、probing、首次连接失败、retained partial/live、ready 和 unsupported 状态下分别呈现正确构图，不再把所有状态塞进同一个 grouped form。
- [x] AC14：截图所示 unresolved/failed 场景不再显示误导性的“2 项操作”与 disabled Refresh；用户能直接 Test、Edit Controller 或进入 Diagnostics，并看懂 `127.0.0.1` 指向当前 Mac。
- [x] AC15：mihomo、Nikki、OpenClash、CMFA、Stash、sing-box、Surge、Auto Detect 和 unknown/unsupported 的 Actions snapshot 都只包含其真实命令子集；没有跨 adapter 错误 dispatcher。
- [x] AC16：connected Actions 在宽布局合理使用双栏、窄布局顺序单栏；少命令 controller 使用紧凑恢复/导航信息，不生成装饰内容、虚构命令或大面积失衡 form。
- [x] AC17：高风险 lifecycle 继续要求确认并校验 controller ID/generation；controller/session 切换后 pending confirmation 清空且无法误发到新目标。
- [x] AC18：loopback 目标提示对远端 controller 可见、对显式 mac-local controller 不误报；英文/简体中文、VoiceOver、键盘和四档字号均能完整表达目标、失败原因与动作。

## Out of Scope

- 不新增、下载、启动或管理本地代理核心，不修改系统网络、OpenWrt、LuCI、SSH 或 `ubus`。
- 不把 Diagnostics 变成日志浏览器、连接表、策略管理页、配置编辑器或 Actions 的副本；两页共享 typed 状态与 intents，但职责保持“解释”与“执行”分离。
- 不增加后台全 controller 轮询、自动故障转移、未经现有 API/capability 证实的修复动作或新 package。
- 不修改 controller API、DTO、持久化 schema、credential storage 或导出安全边界。
- 不制造示例 controller 数据、健康分数、图表或成功项，也不照搬其他项目源码与品牌视觉。
- 不通过 Mica 配置 Nikki/OpenClash/OpenWrt 的 API listen、service 或 firewall，不新增 SSH/LuCI/ubus 路径，也不承诺修复设备侧网络配置。
- 不为了填满 Actions 把 Proxies、Connections、Rules、Sources、Configuration 或 Tailscale 已拥有的上下文操作重复成第二套命令入口。

## Post-Implementation Audit Extension (2026-08-10)

### New Goal

在已完成的 Diagnostics + Actions 重构上增加一次功能正确性、隐私边界、无障碍和性能审计。先修复可证明的状态语义问题，再用离线 Release 基准做 before/after 对比；不以“持续优化”为理由做无指标、无边界的全局重写。

### Confirmed Source-Level Findings

- Diagnostics 的通用 evidence helper 先调用 `displayableText`，但过滤失败后又回退到原始 `value`。这会绕过机器 assignment 和 API path 的可见 UI 过滤合同；现有测试只直接测试过滤函数，没有覆盖最终 issue evidence。
- Auto Detect 在 `.connecting` / checking 时仍会把 `.smartProbe` 投影为 critical adapter issue，导致“正在检查”与“适配器故障”同时出现。
- 首次连接尚未成功时，显式 controller 可从 detected kind 获得静态 capabilities；`availableAreas` 没有以 checking/首个 baseline 为门槛，因此可能提前宣称 Available Now。
- Controller-wide failure 只在 `lastSuccessAt == nil` 时压制 endpoint/domain issues。曾成功后发生控制器级故障时，当前逻辑可能同时显示根因和一组派生 endpoint 故障；需要用 retained-session fixture 固化正确去重语义。
- Actions 先用原始 availability 构造 recovery，再把无命令的 command state 改写为 `.unsupported`，最终 availability 与 recovery copy 可能不一致。
- Diagnostics issue row 已组合 VoiceOver children，但没有显式的本地化 severity value；需要验证系统是否会稳定朗读严重度，而不是只朗读 SF Symbol 名称。

### Performance Baseline

2026-08-10 已运行项目自带的离线 Release benchmark，未连接真实 controller，报告为 `tmp/codex/performance/diagnostics-audit-before/mica-performance.json`。首次 Release 构建约 218 秒，benchmark 本身约 3.28 秒；构建时间不作为产品性能指标。

当前主要子指标：

- connection row full projection，10,000 rows：median 125.41 ms，p95 158.61 ms；5,000 rows p95 61.15 ms。
- connection keyed metric update，10,000 rows：p95 3.33 ms。
- log full-ring incremental projection，2,000 rows / 32 work units：p95 40.31 ms。
- runtime hidden-log ingestion，10,000 rows：p95 12.88 ms。
- runtime connection frame，10,000 rows：p95 7.12 ms。
- topology unique-route，2,000 rows：p95 13.57 ms。

同一 Release 构建缓存下的重复基线显示：10,000-row connection projection median 为 123.98 ms，首轮为 125.41 ms；重复 p95 为 125.65 ms，说明首轮 158.61 ms 属于离群值。5,000-row case p95 波动约 4.2%，其他多数 case 在约 0-8% 内。后续判断收益必须比较重复 median 与 p95，不能用单次最大值。

现有 `log-full-ring-incremental-projection` case 的计时区间同时包含 2,000 行首次 full projection 和后续 32 次 delta，因此 39-40 ms 不能直接除以 32 当作稳态单次 delta 成本。实施前应新增 setup 不计时的 steady-state delta case，再决定是否修改 Logs cache；旧 case 保留以维持历史可比性。

Diagnostics projection 只处理固定 endpoint/domain 集合，本身不是当前基准中的高成本路径。Actions 每次 snapshot 会读取宽泛的 `isBusy`，并从完整 capability matrix 重建 operation rows 后只消费少量命令；这是可收窄的 invalidation/read fan-out，但只有在专门的投影计数或观察证据支持时才改。Connections 全量行投影和 Logs 满环增量投影是现有离线基准中更明确的候选热点。

此前 Proxies 滚动卡顿已经通过“滚动中只保留最新 catalog 更新、空闲后一次提交、滚动时抑制 hover 动画”处理，并有专门测试；本轮不在没有新 trace 或回归证据时重复改写该机制。

### Proposed Audit Order

1. 修复 Diagnostics evidence 过滤、checking/adapter 冲突、首个 baseline 前 Available Now、controller-wide causal dedup，以及 Actions effective availability/recovery 一致性。
2. 增加只覆盖上述稳定回归的纯 projection tests，并核对 VoiceOver severity、键盘、Reduce Motion 和单一 scroll owner 合同。
3. 审计 Diagnostics/Actions 的 observation 边界，避免 traffic、connection rows、logs 或无关 operation 状态触发页面重建；只在可观察证据支持时收窄依赖。
4. 若范围扩展到整个 Workbench，再按基线优先检查 Connections full projection 与 Logs full-ring incremental projection；每次改动都保留 controller 顺序、generation 检查和 missed-revision fallback，并生成 after 报告比较 checksum、work units、median 与 p95。
5. 完成 focused tests、build、完整测试、source verifier、localization JSON、`git diff --check` 与 Trellis validation；继续不运行真实 controller smoke 或任何远端操作。SwiftUI Instruments 需要另行授权，因为它会启动应用并进入运行态。

### Provisional Acceptance Criteria

- [x] 被 `displayableText` 拒绝的字符串不会通过任何 issue evidence helper 回到可见 UI，最终 snapshot 有直接回归测试。
- [x] checking/probing 期间不显示 adapter failure、endpoint/domain failure 或 Available Now；首个真实 baseline 提交后才公布可用区域。
- [x] Controller-wide failure 在首次失败和 retained-session failure 中都压制同一根因产生的 endpoint/domain 重复项，同时保留最后成功数据的 retained 语义。
- [x] Actions 最终 availability、recovery copy、command groups 和 executable count 来自同一 effective state。
- [x] VoiceOver 通过明确 label/value 与 selected trait 朗读问题严重度、标题、影响和选择状态；键盘与 Reduce Motion 行为保持现有合同。
- [x] Diagnostics/Actions typed inputs 不含 traffic/log/connection payload；Actions 仅对有 dispatcher 的 family 构造 evidence-free runtime rows，命令 busy/disabled 状态保持准确。
- [x] 两份 before/after 报告 checksum/work units 不变；identity slice 仅改善 6.38%/4.71%，按停止规则撤回，未把噪声内变化宣称为优化。

### Adopted Scope Decision

用户已于 2026-08-10 采用完整 Workbench 范围：先修复 Diagnostics/Actions 已确认的功能、隐私与状态语义问题，再继续审计和优化离线基准已经指出的 Workbench 共享热点。性能改动仍必须逐项提供证据，不把范围扩展解释为无边界重写，也不重复改写没有新回归证据的 Proxies 滚动机制。

### Full Workbench Measured Outcome

完整审计补齐了 Connections initial cache/search、Logs search、Rules index/rows/search、Sources rows/search，以及 Proxies catalog/expanded groups 的离线 Release case。两轮基线为 `workbench-hotspots-before` / `workbench-hotspots-before-repeat`，两轮最终结果为 `workbench-hotspots-after` / `workbench-hotspots-after-repeat`；相同 case 的 fixture count、checksum 和 reported work units 保持一致。

最终保留两项范围受控的产品优化：

- Connections 结构行投影每轮只解析一次本地化 unavailable 文案，并对已归一且保证非空的行摘要直接组合；10,000-row row median 两轮改善 22.40% / 21.79%，initial-cache median 改善 19.81% / 22.21%，对应 p95 也均改善超过 18%。
- Connections、Logs、Rules、Sources 统一通过 `WorkbenchDataSearch` 使用 Foundation `NSString` case-insensitive range；连接搜索 median 两轮改善 22.96% / 22.11%，日志搜索改善 49.53% / 51.08%。同一 Release 进程的 A/B 中，Rules 从 14.71 ms 降到 6.85 ms，Sources 从 2.35 ms 降到 1.57 ms；最终两轮实际 case 分别稳定在 7.03/6.94 ms 与 1.61/1.58 ms。

以下实验未保留：预折叠完整搜索 blob 会把连接 row/cache/search 全部显著拖慢；Swift `String.range(options: .caseInsensitive)` 的 10,000-row 搜索约 343 ms；`@inline(__always)` 对共享 matcher 没有可重复收益且增加实现噪声。此前稳定 identity 快速路径也继续保持撤回状态。

逐页停止结论：

- Connections 的结构投影和共享搜索已跨过两轮 10% 门槛；keyed metric update 仍约 2-3 ms，不改 revision/cadence/identity 合同。
- Logs 搜索受益，steady delta 仍约 25 ms/32 次有效更新；保留 bounded ring、delta 和 missed-revision fallback。
- Rules 的 10,000-row connection index 约 5-6 ms、row projection 约 40-42 ms；Sources 的 1,000-row stress projection 约 76-79 ms，但 provider catalog 通常低基数且不是高频流。没有证据支持增加缓存状态或改变数据合同。
- Proxies 的 100,000-member catalog index 约 55-57 ms，2,000 expanded rows 约 1.7-1.8 ms；现有滚动期 latest-only deferral、空闲提交和 hover suppression 继续作为保护合同，不重复改写。
- Overview runtime/topology case 没有两轮一致回退；既有 timeline/topology cache 保持不变。Diagnostics、Actions、Controllers 和 Configuration 是固定或低基数页面，不用合成高基数 benchmark 证明不存在的热点。

### Full Workbench Acceptance Criteria

- [x] 高基数数据页均有与真实 projection/cache 边界一致的离线 case，不把 fixture 构造计入 prepared search 测量。
- [x] 保留的产品优化在两次可比 Release 运行中均让目标 median 改善至少 10%，且无无关 case 连续回退超过 10%。
- [x] 共享搜索保持大小写不敏感、同重音 Unicode 匹配和不移除重音的既有语义；空 query、排序、controller 顺序、stable identity 和 selection 不变。
- [x] 未达到收益门槛或扩大状态复杂度的实验已撤回；没有新增 package、controller contact、runtime smoke 或远端动作。
