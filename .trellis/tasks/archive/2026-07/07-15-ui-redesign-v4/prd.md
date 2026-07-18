# UI 重做 v4:统一设计语言 + 实时会话模型

## Goal

把 Mica 从"多套视觉语言拼接 + 手动数据模式"重做为**一个统一、精致、不割裂的整体**:

1. **统一设计语言**——整个窗口(侧栏、工具栏、状态栏、全部工作台目的地与控制器编辑器)共用一套原生 macOS 27 Liquid Glass 语言,整窗跟随系统浅/深,消除"左边 mac、右边 win"的割裂。
2. **只保留"实时"数据概念**——去掉用户可见的"快照/会话同步"模式,选中控制器即进入实时会话,数据自动更新;底层 REST/WebSocket 是实现细节,不暴露给用户。

用户方向(2026-07-15 多轮收敛):
- "全局颜色统一,不要割裂" → "整个的布局 UI 等都重构" → "所有 tab 全部重构" → "去掉快照,只保留实时"。
- 这是一次**彻底重做**,不是在 v3 现有形态上打补丁。

## Why v4(v3 失败的根因)

v3 做了 9 轮"用户不满意 → 反应式再改"(概览 5 版、策略 4 版、色彩修一遍、空态、侧栏两遍),始终没让用户满意。**根因不是某页没调好,而是从头到尾没有一个统一的北极星设计语言**——每轮单独打补丁,所以每页各长各的样,永远差口气、显廉价。v4 的前提是**先把设计语言定死,再让所有表面照它做**。

## 设计语言(北极星,先定死)

**Liquid Glass 现代风(macOS 27),严格分层:**

| 层 | 用什么 | 哪些东西 |
|---|---|---|
| **悬浮功能层** | ✨ Liquid Glass(`.glassEffect` / `.buttonStyle(.glass)`) | 顶部工具栏、侧栏 chrome、悬浮操作条、`MicaGlassSelectionSurface` 选择块 |
| **低数量结构内容** | `.regularMaterial` 或 Reduce Transparency 下的语义实底 | 概览主容器、表单分组、Inspector、状态栏 |
| **高数量重复数据** | 系统语义实底 + 原生选中态/分隔线 | Table/List 行、策略卡/节点、日志、规则、长文本 |

**为什么严格分层**:v3 第 4 轮栽在玻璃上——63 个策略组每个套 `.glassEffect`,一屏几十块玻璃并排显得斑驳廉价。Apple HIG 明确:①别在内容层用 Liquid Glass;②克制使用,只留给最重要的功能元素。iOS/macOS 玻璃精致是因为**稀少且悬浮**(Dock/控制中心/工具栏)。所以玻璃收缩到"框",内容一律标准材质。

**统一 tokens(全部表面共用):**
- **底色**:整窗跟随系统浅/深(废除强制深色);由 scene 级 `.preferredColorScheme(appearance.colorScheme)` 单一驱动。
- **容器**:结构容器可用 `.regularMaterial`;重复数据使用系统语义实底。二者共用统一圆角、间距与极淡语义描边;不嵌套、不逐行加玻璃、模糊或阴影。
- **强调色**:`MicaStyle` 自适应语义色(紫=选中/焦点、绿=健康、青=信息/live、黄=警告、红=危险),Round 4 D10 已过 WCAG ≥4.5。
- **文字**:系统 `.primary`/`.secondary`,统一字号阶梯。
- **间距/圆角/描边**:一套固定节奏,全 tab 一致。
- **动效**:克制,尊重 Reduce Motion。

## Background(现状诊断,代码考证 2026-07-15)

### 割裂的确切机制

上一轮 v3(commit d85cc180,TD5)**故意**定下:"sidebar stays native, 右侧 forced-dark"。v4 推翻它。

- **左侧"mac"感**:`WorkbenchSidebarView` 用原生 `List(selection:)` + `.listStyle(.sidebar)`,跟随系统浅/深。
- **右侧"win"感**:tech-dashboard 强制深色自发光表面,由**四处** `.environment(\.colorScheme, .dark)` 实现:`MicaDashboardStyle.swift:178`(`MicaGlowCard`)、`:198`(`micaDashboardSurface()`)、`MicaFrostSurface.swift:181`(`MicaFrostCard`)、`WorkbenchOverviewView.swift:42`(概览根)。
- 浅色模式下"左白右黑"最扎眼。

### 四套并存的视觉语言(全 tab 重做依据)

| 分组 | Tab | 卡片/表面语言 | 外观 |
|---|---|---|---|
| ① | 概览 | `MicaFrostCard` frost 卡 + `MicaFrostBackdrop` | **强制深色** |
| ② | 策略 | `MicaGlowCard` 自发光渐变卡 | **强制深色** |
| ③ | 连接/规则/来源/日志 | 系统语义底(`pageFill`=windowBackgroundColor / `contentFill`=textBackgroundColor,均系统语义色)+ **无卡片包装** | 跟随系统 |
| ④ | 配置/操作/诊断/设置 | 原生 `.formStyle(.grouped)` | 跟随系统 |

四套收敛成一套统一表面词汇,才能真正不割裂。

### 数据模型现状(去快照依据)

当前有**三条数据加载路径**,拼在一起既乱又暴露给用户:

1. **一次性刷新** `refreshSelectedRouter()`(手动按钮)。
2. **会话自动同步** `toggleSessionAutoSync()` / `sessionSyncTask`——每 N 秒 REST 轮询**全量快照**(proxies/connections/rules/providers/config),带 `snapshot`/`sync` 状态标签。**这就是用户说的"快照"概念。**
3. **实时流** `toggleLiveStreams()`——mihomo WebSocket 只推 **traffic + logs** 两条流(`MihomoClient.trafficStream()` / `logsStream()`);Surge 无 WS,用 1s 近实时轮询。

**关键技术事实**:mihomo 的 connections/rules/proxies/providers/config **只有 REST 端点,没有 WebSocket**。所以"实时"底下**必然仍需轻量 REST 拉取**这些数据——这是实现细节,不是用户可见的"快照模式"。Round 3 曾特意"选中不自动加载"以避免非预期请求;v4 推翻它(连上即实时)。

### 额外 UI 表面(11 目的地之外)

- 顶部工具栏 `WorkbenchRootView` — test/refresh/live 的 `ControlGroup`,已 `.buttonStyle(.glass)`。
- 底部状态栏 `WorkbenchRootView:17` `.safeAreaInset(edge: .bottom)` — `WorkbenchOperationStatusBar`。
- 控制器编辑器 `RouterEditorView` — 主窗 detail 区 `.formStyle(.grouped)` 表单(加/改控制器)。
- 现有侧栏控制器行状态呈现由 `ControllerBayPresentation` 提供;D42 会删除该侧栏呈现,状态改由 toolbar `ControllerSwitcher`、Controllers page 与常驻状态栏承接。

### 关键基础设施(可复用)

- 外观偏好:浅/深/跟随系统三档(`AppPreferencesStore.appearanceKey`),scene 级 `.preferredColorScheme` 注入,`AppAppearance.applyToApplication()`。
- `MicaStyle`(浅色语义色 Round 4 D10 已修到 WCAG ≥4.5)。`MicaDashboard`(固定亮色变体,专为深色底)将退役/收敛。
- macOS 27,`.glassEffect`/`GlassEffectContainer`/`.regularMaterial` 原生可用。
- `swift-charts` 技能已装(概览图表参考)。

### verifier 约束(决定可动范围)

- **可自由拆**:verifier 对 dark/dashboard/colorScheme/frost/glow **零断言**。
- **写死不可动**:侧栏 `List(selection: $destination)`(:241)+ `NavigationSplitView`(:222);概览 `import Charts` + 真实值清单 + `trafficTimeline.isEmpty` 空态守卫 + 无 Timer/合成样本(:361-380);策略页 `ForEach(filteredGroups)` + 保序 + inline 四方法 + 无 `.sorted`(Round 7);表格页 `Table(...selection:)` + `sortOrder` 绑定;GLOBAL 末尾 partition;禁中间截断/掩码;secrets 走 `FileSecretStore` 不入 `RouterProfile`。
- 契约文档 `workbench-ui-contract.md` 需随 v4 同步演进。

## Confirmed Evidence And Resolved Risks(2026-07-16)

以下问题已经由当前任务文件、工作区状态和源码确认,不是需要用户猜测的事项。

### F1 当前原型与 v4 北极星直接冲突

- 未提交的 `MicaFrostSurface.swift` 新增了内容层 `.regularMaterial` 模糊、径向渐变背景、`.shadow` 和 `.environment(\.colorScheme, .dark)`。
- `WorkbenchOverviewView` 的未提交改动正在接入该 Frost 表面并再次强制深色。
- 这与 D1“整窗跟随系统”、D2“内容层禁强制深色/重模糊/阴影堆叠”、以及既有滚动性能约束相反。该原型不得直接并入 v4;除非后续明确推翻 D1/D2,否则应从 v4 实现路径隔离。

### F2 任务尚在 planning,但实现与无关暂存已混入 main

- `task.json` 仍为 `planning`,Phase 0 的基线、feature branch 和验证尚未完成,但 `MicaStyle`/`MicaSurfaces` 已出现 Phase 1 实现。
- 暂存区还混有大批技能安装/删除(`swift-charts`、`swift-concurrency`、`swiftdata-pro`)改动,不属于 v4 UI 功能提交。
- 开发前必须先隔离任务改动与技能管理改动,再建立 v4 分支和可复现基线;否则后续提交、回滚和归因都不可靠。

### F3 “所有内容层都用 regularMaterial”范围过宽

- `.regularMaterial` 仍是带透明采样的材质,不是免费的纯色背景。若用于表格行、日志行、长文本或大量策略成员,会降低可读性并重新引入滚动合成成本。
- D2/R2 应收敛为:material 只用于有限数量的页面容器、工具区和分组卡;`Table`、日志、长文本、策略成员数据层继续使用系统语义背景/分隔线,禁止逐行 material、blur 或 shadow。
- Reduce Transparency 必须有不依赖模糊的系统语义色回退。该问题已由 D26 的 surface-role 预算收敛。

### F4 单一 sessionState 只能是聚合展示,不能抹掉端点状态

- 当前连接、规则、代理、来源、配置和 traffic/log 流拥有不同的数据源、刷新频率与失败方式。
- v4 可以只向用户展示一个聚合的 `connecting/live/partial/failed/paused` 状态,但内部必须继续保留每个端点/通道的健康、更新时间和错误信息,供页面空态、诊断与 partial 状态计算使用。

### F5 实时会话需要明确的并发与陈旧写入边界

- 自动连接、后台 REST、WebSocket、手动 refresh、重试和控制器切换会并发发生。
- 设计必须增加 session generation/identity:切换控制器先取消旧任务;所有异步 apply 同时校验 router ID 与 session generation;手动 refresh 与周期刷新合并为 single-flight/coalesced 请求,避免重复拉取和旧控制器结果覆盖新界面。

### F6 当前“暂停”只暂停部分数据应用

- `toggleDashboardUpdatesPaused()` 只切换布尔值。
- `applyLiveTraffic`、`applyLiveLog` 和 Surge near-live 在暂停时丢弃事件,但网络连接仍运行;后台 REST 同步没有相同暂停门,因此连接/规则/策略等仍可能变化。
- v4 工具栏的“暂停”不能直接复用现状而不定义产品语义,否则用户看到的是部分页面冻结、部分页面继续更新。该产品语义已由 D14 收敛。

### F7 自动实时还缺两个生命周期决定

- 启动 App 时自动连接上次选中的控制器已由 D15 收敛。源码同时确认当前 `loadPersistedState()` 只选择 `loadedProfiles.first`,并未持久化上次选择;v4 必须补选中控制器 ID 的持久化与无效 ID 回退。
- App 退到后台、关闭主窗口和休眠/唤醒的会话策略已由 D16 收敛。控制器编辑保存与网络恢复仍需按同一 generation/cancellation 纪律实现。

### F8 策略多列方案存在顺序跳动与 verifier 风险

- 动态分行方案会在展开/收起时重新分块,虽然数据顺序不变,视觉位置仍会大幅跳动。
- 现有 verifier 依赖 `ForEach(filteredGroups)` 和完整快照选择契约;实现多列时必须用纯 presentation 分组并新增“扁平化后仍等于 arrangedGroups”的测试,不能为了布局放宽顺序断言。

### F8.1 Zashboard 参考实现的错位是结构性行为

- 已检查 Zashboard `0d2a7b5c`。`ProxiesPage.vue` 在双列模式下创建两个独立纵向 `flex-col` 容器,再用 `index % 2` 把策略组交错分到左右列;`ProxyGroup.vue` 内部的 `CollapseCard` 直接在所属列原地增高。
- 因此任一组展开只推移同列后续卡片,另一列不动,左右“行”必然失去对齐。这是 masonry/双独立列方案的预期结果,不是可通过修动画消除的小 bug。
- 用户已接受该错落特征,并要求顺序横向排列。最终规则由 D20 固化:固定行优先分配,展开后不重平衡列。

### F9 缺少早期视觉验收门

- v3 的失败根因被任务本身归纳为“各页完成后才发现整体语言不成立”;v4 的早期草案同样曾计划一次推进全部 Tab,直到终检才让用户主观确认。
- 这会重复 v3 的高成本路径。该问题已由 D19 收敛:统一原语完成后必须先做覆盖导航、数据卡、策略交互、表格和表单的代表性 vertical slice,在浅/深两档真机截图与用户确认后才能扩散到剩余 Tab。

### F10 Command 菜单仍暴露旧数据模式

- `MicaApp.swift` 的 Controller `CommandMenu` 仍包含 `toggleLiveStreams` 和 `toggleSessionAutoSync`,以及对应 live/sync 文案与图标。
- v4 删除用户可见的 live/sync 模式后,菜单必须同步重构;否则即使工具栏简化,macOS 菜单栏仍保留两套概念。该问题已由 D39 收敛。

### F11 控制器列表与功能导航堆叠在同一侧栏

- `WorkbenchSidebarView` 先完整渲染所有 controller rows,再渲染工作台/控制器管理/App 设置目的地。controller 数量增加或大字号启用时,工作台导航会被持续向下推,可见项和空间位置不稳定。
- controller selection 是“当前数据源/工作区上下文”,destination selection 是“当前功能页面”,两者语义层级不同;把两种可变长度列表首尾堆在同一 `List` 中会让侧栏既像账户列表又像 Tab 栏,扫描和键盘导航都不清晰。
- 该问题不能只靠压缩行高解决,需要重新决定 controller switcher 与 destination navigation 的信息架构,同时遵守同窗口、尽量无弹窗和原生 macOS 导航纪律。该问题已由 D42 收敛。

## Decisions(已收敛,2026-07-15 brainstorm)

### 全局

- **D1 全程跟随系统,整窗一致**。删除全部四处 `.environment(\.colorScheme, .dark)`;内容区外观由 scene 级 `.preferredColorScheme` 单一驱动,与侧栏一致。
- **D2 玻璃严格分层并受 material 预算约束**。Liquid Glass 只用于导航与悬浮功能层(工具栏/侧栏 chrome/悬浮操作/`MicaGlassSelectionSurface`),内容层禁止 `.glassEffect`。低数量结构内容可使用 `.regularMaterial`;高数量重复数据必须使用系统语义实底、原生选中态和分隔线,禁止逐项 material/blur/shadow。`MicaGlowCard`/`MicaFrostCard`/`MicaFrostBackdrop` 退役。
- **D3 色板统一到 `MicaStyle`**。`MicaDashboard.*` 前景色调用点(概览 30+、策略 15+)迁移到 `MicaStyle` 自适应语义色;`textSecondary`/`hairline` 改系统 `.secondary`/`.separator`。语义(紫/绿/青/黄/红)不变。
- **D4 统一表面词汇**。定义共享的 structural/repeated surface roles、页面底、标题、间距、圆角和描边节奏,全部工作台表面与控制器编辑器统一使用。

### 每个表面的形态(逐个确认)

- **D5 侧栏**:保留原生 `List(selection:)` 结构,只呈现 D42 的固定功能 destinations,融入系统侧栏材质与统一节奏;不再承载控制器列表或控制器编辑/删除操作。
- **D6 概览**:收敛为**少数容器卡 + 密集布局**(告别 v3 的 ~10 张独立浮卡):① KPI 磁贴行(一张卡内分隔:↑↓速率/连接数/组·规则计数/健康);② 通栏吞吐曲线主卡;③ 洞察卡(延迟分布/链路占比/Top 连接,一张卡三栏或紧凑网格);④ 端点健康紧凑卡。真实数据纪律不变。
- **D7 策略**:按 D20–D24 使用 Zashboard 式固定错落双列,窄窗单列;源顺序横向 index-modulo-2 分配,允许多组在原卡内展开且不重平衡。组头显示类型、组名、当前节点和延迟状态;成员区提供选中态、延迟、过滤、分页和有界滚动。保序、GLOBAL 逻辑末位、inline 四方法和过滤先于分页的契约不变。
- **D8 表格页(连接/规则/来源/日志)**:保留**可排序 `Table` + 按需 `.inspector`** 形态,融入统一语言;空态两级文案 + 居中(Round 8)不变。
- **D9 表单页(配置/操作/诊断/设置)**:从纯 `.formStyle(.grouped)` 重做为使用统一 structural surface role 的原生表单分组,与其他 tab 同语言;不嵌套卡片,原生控件语义不丢。
- **D10 工具栏**:保持 `.buttonStyle(.glass)`(悬浮玻璃合规);动作随 D13 数据模型简化(见下)。
- **D11 状态栏**:底部 `safeAreaInset` 材质条,统一材质语言。
- **D12 控制器编辑器**:`RouterEditorView` 从 grouped 表单重做为 D9 同款 structural surface 原生表单,并遵守 D31/D32 的同窗口事务与草稿保护。

### 数据模型

- **D13 去掉"快照"概念,只保留"实时"**。删除用户可见的"会话自动同步/快照"模式与其状态文案、"待刷新/idle"中间态。合并为**单一"已连接实时会话"**:选中控制器 → 自动连接 → WebSocket 推流量/日志 + 轻量 REST 补 connections/rules/proxies/providers(实现细节,用户只看到"已连接、数据实时更新")。顶部工具栏 test/refresh/live/sync 收敛(不再有独立"快照同步"挡)。**红线**:不伪造数据;REST 补拉是后台细节不暴露"快照"字样;失败重连/错误态保留但用统一"实时会话"语义呈现。
  - **注**:`toggleSessionAutoSync` / `startSessionAutoSync` / `runMihomo|SurgeSessionAutoSyncLoop` / `syncMihomoSessionSnapshot` 等会话同步机制需要**并入**实时会话的后台刷新,而不是简单删除(否则 connections/rules 无数据源)。设计阶段细化。
- **D14 暂停只冻结呈现,不停止会话**。用户选择暂停后,WebSocket、Surge 近实时轮询和后台 REST 刷新继续运行;所有页面保持同一份冻结的可见状态,不得出现日志/流量停住但连接/规则继续变化的半暂停。暂停期间只保留有界待呈现数据:REST/聚合状态保留最新值,traffic 使用 D38 的五分钟时间线预算,日志使用 D37 的双上限环形缓冲,不得无限积压。恢复时原子应用最新待呈现状态并立即触发一次 coalesced refresh,随后继续实时更新;状态栏明确显示“已暂停呈现”,不伪装为断开连接。
- **D15 冷启动自动恢复实时会话**。App 加载控制器与凭据后,自动恢复上次选中的有效控制器并立即进入 `connecting`;不要求再次点击、测试或刷新。新增持久化的 selected-controller ID;若该 ID 不存在/已删除则稳定回退到控制器列表第一项并更新持久化值;无控制器时不发网络请求并显示配置空态。自动连接只能在 profiles 与 secrets 都加载完成后启动一次,不得因 SwiftUI `onAppear` 重复建 session。
- **D16 可见性与系统生命周期**。仅切换到其他 App 或最小化主窗口时保持实时会话;关闭最后一个 Mica 主窗口时停止 WebSocket、REST、重试和 pending presentation,即使设置窗口仍开着也不保持控制器会话。系统睡眠前停止会话;唤醒后只有主窗口可见才自动重连。重新打开主窗口时恢复持久化选中的控制器并创建全新的 session generation。生命周期事件必须幂等,不得重复启动或让旧 generation 在重开后写入。
- **D17 非流式数据分级刷新**。mihomo traffic/log 继续使用 WebSocket;Surge 既有 1 秒 near-live 轮询保持。REST 由统一刷新协调器拆为三档:2 秒刷新 connections/active requests 等快速变化数据;5 秒刷新 proxies/policy groups/current selection;30 秒刷新 rules/providers/config/version 等慢变化数据。进入 session 先做一次 coalesced 全量加载,之后各档错峰运行。手动 refresh 请求全部档立即刷新,但与在飞请求 single-flight 合并,最多登记一次 follow-up,不得并发重复端点请求。每档独立记录成功时间、错误与退避,聚合为 session partial/failed;暂停呈现不停止这些调度。
- **D18 失败时保留并标记最后成功数据**。端点或流在至少成功一次后失败,继续显示该端点最后成功的数据,但对应页面/模块必须显示“数据已过期”及最后成功时间,并从实时聚合状态降为 partial/stale;其他健康端点继续实时。某端点从未成功则显示错误空态和重试入口。重连成功原地更新,不得先清空造成闪屏。暂停呈现是用户主动冻结,与 stale 正交:暂停显示暂停时间,网络失败仍更新诊断状态,但冻结内容不变化。切换控制器或结束 session 时旧控制器数据必须清除,不得跨 controller 复用。
- **D19 全量重构前必须通过代表性视觉验收**。统一 tokens/`MicaContentCard` 完成后先实现且仅实现一个 vertical slice:侧栏 + 工具栏 + 状态栏、概览、一个策略组的折叠/展开、连接表格 + Inspector、一个设置表单分组。只能使用真实控制器数据与真实空态,不得造 mock。产出浅/深 × 标准/大字号截图并让用户明确确认材质、颜色、密度、层级;未确认前不得把视觉语言扩展到其余 Tab。反馈先回写 tokens/原语和代表页面,通过后再机械推广。
- **D20 策略采用 Zashboard 式固定错落双列,顺序横向排列**。宽度达到双列阈值时使用两个独立纵列;控制器有序集合按原始索引固定分配:`0 左、1 右、2 左、3 右...`,即折叠态按行从左到右阅读。窄窗退化为单列。展开只增加所属列高度,允许左右错落;收起恢复。禁止按“较短列”动态重平衡;展开、延迟变化和普通刷新不得改变同一可见集合的列分配。页面搜索改变可见集合时按 D28 重新紧凑分配。业务选择、键盘导航与 VoiceOver 遍历仍按完整横向源顺序,不能按“左列全部 → 右列全部”读取。展开内容留在原卡内,继续提供过滤、节点选择、延迟测试和分页。
- **D21 GLOBAL 不做视觉末位特例**。GLOBAL 继续先由 Round 7 的稳定 partition 追加为逻辑序列最后一项,随后像普通策略卡一样按 D20 的 index modulo 2 分配到左/右列;不渲染底部全宽卡、不因列高度重新定位。展开造成错落后,GLOBAL 允许在屏幕 y 坐标上高于另一列的较早组。所谓“GLOBAL 最后”只保证数据/逻辑、键盘和 VoiceOver 顺序最后,不保证视觉最低。
- **D22 允许多个策略组同时展开**。展示状态改为 `expandedGroupIDs: Set<GroupID>`;展开/收起任一组不影响其他组。`PolicyGroupInteractionStore` 为每组保存独立过滤、成员窗口和滚动位置;关闭某组只清理该组过滤词,重新打开保留该组已加载分页窗口。页面搜索暂时隐藏组时保留其展开/过滤状态,清空搜索后恢复;控制器切换、session leave 或组从完整数据中消失时才 prune/reset。`selectedPolicyGroupID` 继续表示唯一当前操作/键盘焦点组,与多展开集合分离;点击或操作某展开组时更新 active selection,但不收起其他组。
- **D23 展开卡采用 Zashboard 式卡内节点滚动**。卡标题、指标、测试动作和组内过滤栏保持在卡内滚动区之外;节点列表放入独立垂直 `ScrollView`,标准/舒适字号最大高度约 432pt,大/特大字号按档位提高但封顶约 560pt,短列表按内容自然收缩。显示原生滚动指示器和清晰边界,不得隐藏滚动归属。继续使用每组 48 项窗口和“加载更多”,按钮位于节点滚动内容末尾;多组各自保留滚动位置、过滤和分页。外层页面负责卡片之间滚动,内层到达边界后不得通过自定义手势劫持外层滚动。Reduce Motion 不影响滚动,Reduce Transparency 使用不依赖 blur 的背景。
- **D24 按控制器持久化展开组,不持久化瞬态成员状态**。为每个 controller ID 保存 `expandedGroupIDs`;App 重启后恢复仍存在的组并 prune 失效 ID。切换 Tab/目的地时当前运行内的展开、过滤、分页和节点滚动位置全部保持;切换控制器时切换到该控制器自己的展开集合。`PolicyGroupInteractionStore` 的过滤、成员窗口和滚动位置不写入磁盘,App 重启后重置,避免遗留筛选让节点看似消失。删除控制器同步清除其持久化展开记录。
- **D25 暂停呈现时禁用手动刷新**。presentation paused 时工具栏、菜单和快捷键中的 refresh 均 disabled,帮助文本说明需恢复后刷新;后台 D17 调度继续,所以不损失数据。test/诊断仍可执行,结果只更新操作/诊断状态,不解冻业务数据。点击 resume 后先原子应用 pending,再由协调器 coalesce 一次立即全量 refresh;不得出现暂停期间 refresh 成功但界面无反馈的假失效。
- **D26 统一 surface role,限制 material 数量**。共享视觉词汇分为两种实现但共用 tokens:低数量结构容器(概览主卡、表单分组、Inspector、状态栏)可用 `.regularMaterial`;高数量重复内容(策略组卡、节点、Table/List 行、日志、规则、长文本)使用系统语义实底/选中态/分隔线,禁止逐行 material、glass、blur、shadow。`MicaContentCard` 必须显式接收 `surfaceRole` 或拆为清楚的 structural/repeated 变体,不得默认把所有调用者变成 material。Reduce Transparency 下 structural 也回退为不采样背景的系统语义实底。
- **D27 stale 数据保留到当前 session 结束**。端点成功后无论离线多久都保留 lastValue,不设置 5 分钟/30 分钟等任意清空时限;始终显示准确 lastSuccessAt,并可随持续失败提高警告视觉权重,但不得标记为 live。只有 controller switch/delete、最后主窗关闭、sleep leave 或显式 session replacement 才清除该 generation 的旧数据;同 session 重连成功直接替换。
- **D28 页面搜索后按过滤结果紧凑横向重排**。先对完整 ordered groups 做保序过滤,再对过滤结果从 index 0 重新按 `0 左、1 右...` 分配,不保留被隐藏项造成的列空洞。搜索词变化可导致可见卡换列,这是明确的用户发起布局变化;清空搜索恢复原始分配。展开集合、组内过滤、分页和滚动仍按 group ID 保留。普通刷新、延迟更新和展开/收起在可见集合不变时不得换列。
- **D29 按错误类别持续或停止重连**。复用 `RouterTrialFailureCategory`,不得解析本地化字符串。瞬态类(`dns`,`connectionRefused`,`timeout`,`networkUnavailable`,`networkFailed`,`partialEnhancedSnapshot`,`providerUpdateFailed`,HTTP 408/429/5xx)在主窗口存在期间无限重试,退避 `2→4→8→15→30s`,到顶后约 30s 并加入可测试的小幅 jitter;对应端点任一成功即重置。终止类(`authFailed`,`wrongTarget`,`invalidURL`,`tls`,`malformedJSON`,非 408/429 的 4xx,明确 unsupported)停止该 session/lane 自动重试并显示可操作错误。`cancelled` 不重试;未知 local failure 采用有限一次快速重试后转终止,避免死循环。手动 test/refresh 可立即发起一次显式尝试;关闭主窗/sleep 停止全部 retry。
- **D30 终止型错误不自动导航**。鉴权/地址/目标/TLS/unsupported 等 terminal 错误保留当前工作台目的地和 D18 stale 数据;状态栏、toolbar controller selector、Controllers page 和所属页面一致显示错误,提供同窗口“编辑控制器”和“重新测试”操作。只有用户点击编辑才进入现有主窗口 detail 编辑器,不使用弹窗。保存当前控制器成功后使旧 generation 失效并自动创建新实时 session;保存非当前控制器不得打断活跃 session。
- **D31 控制器持久化成功后才关闭编辑器**。将 `upsertRouter` 从 fire-and-forget 改为可 await 的结构化保存结果。点击保存后保留编辑器和草稿,显示进度并禁止重复保存/取消;依次完成 profile validation、secret 写入和 profiles 持久化。任一步失败都留在编辑器、保留输入并内联显示错误,不得关闭或破坏当前 live session。全部成功后才关闭并返回进入编辑器前的目的地;当前控制器随后按 D30 replace session,非当前控制器无会话副作用。
- **D32 保护未保存控制器草稿**。编辑器保存 initial draft 并计算 dirty。干净草稿的取消/导航立即执行;脏草稿的取消、侧栏切换、新建或编辑其他控制器先留在当前编辑器显示同窗口确认栏“继续编辑/放弃修改”,不使用 sheet/popover。确认放弃后执行原始 pending navigation,不固定跳概览。保存进行中禁止离开。关闭整个主窗口且草稿脏时允许使用一次原生破坏性确认作为唯一弹窗例外;取消关闭返回编辑器,确认后丢弃并关闭。
- **D33 pause 是 session-scoped 瞬态状态**。pause 在当前 controller generation 内跨 Tab 保持,但不写入偏好。controller switch、当前 controller 保存后的 session replacement、最后主窗关闭、sleep leave、App restart 都清除 pause/pending 并使新 session 默认实时。仅非 session 的 Tab 导航不改变 pause。状态栏和所有 surface 从同一 session pause 状态读取,不得存在页面级独立 pause。
- **D34 新增控制器不抢占已有活跃会话**。保存新 controller 时,若已有 selected/live controller,只追加 profile/secret;若当前位于 Controllers page 可对新行给出短暂非侵入式反馈,但保持 management selection、selected ID、session generation、当前目的地和业务数据完全不变;用户主动执行 Use/selector switch 后才切换。若保存的是第一个控制器或当前无有效 selected controller,保存成功后自动选中并进入实时会话。编辑器内 test 可在保存前验证新控制器,不影响当前 session。
- **D35 删除 active controller 时优先回落下一项,否则上一项**。删除前记录 active 在 ordered routers 中的 index;删除成功后若同 index 仍有元素(原下一项)则选它,否则选新的最后一项(原上一项),并自动建立新实时 session。无剩余项则 selected=nil、清 session 并显示无控制器空态。删除非 active controller 不改变 selection/session。删除确认文案明确即将切换的目标;持久化 selected ID 与展开状态记录同步更新。只有 profile/secret/persistence 删除全部成功后才执行回落,失败保持原 controller/session。
- **D36 不自动故障转移控制器**。selected controller 网络或 terminal 失败时保持 selected ID、当前目的地和 controller 上下文;瞬态错误按 D29 重试,terminal 错误显示 edit/test,但绝不自动选择其他保存项。其他 controller 可能代表不同设备/环境,静默切换会造成数据归属误判。唯一自动切换例外是用户明确删除 active controller 后的 D35 回落。状态栏和所有错误面必须持续显示当前 controller 名称。
- **D37 实时日志使用 2000 条 + 8 MiB 双上限环形缓冲**。日志按 controller 到达顺序完整保存 UTF-8 内容,不截断、不脱敏;达到任一上限即从最旧条目淘汰直到同时满足。正常可见与 pause pending 使用同一 session 总预算,恢复时按原始顺序合并后再淘汰。page search/level filter 只投影视图,不重排/删除源缓冲。切换 controller 或 session leave 清空;不跨重启持久化。“清除日志”同时清除 visible 与 pending。字节预算必须按真实 UTF-8 长度统计,避免超长 payload 绕过限制。
- **D38 吞吐图保留最近五分钟真实样本**。`TrafficTimeline` 从 60 扩为约 300 个控制器实际到达样本,并按 receivedAt 裁剪五分钟窗口;不使用 Timer 补点、不插值伪造、不跨 controller/session/restart 持久化。pause 时网络继续写 session timeline,visible chart 冻结;resume 后切到最新五分钟。Charts 可对绘制做确定性视觉降采样,但诊断、可访问数值和峰值统计基于原始保留样本。无样本保持真实空态。
- **D39 Controller 菜单收敛为单一实时会话命令**。Controller `CommandMenu` 固定为:测试连接、立即刷新(`⌘R`)、暂停/恢复呈现、分隔、编辑当前控制器、分隔、复制诊断报告。删除启动/停止 live 与启动/停止 session sync。新增控制器只保留在 File 菜单(`⌥⌘N`),删除只在 Controllers 管理页,均不重复进入 Controller 菜单。除 `⌘R` 外不新增全局快捷键。所有 enabled 状态复用统一 capabilities:无 controller 时 test/refresh/pause/edit disabled;pause 时 refresh disabled;菜单、toolbar 和 keyboard 行为一致。
- **D40 底部状态栏固定高度常驻**。主工作台始终保留稳定 status bar,按字号档位约 32–44pt,状态变化不改变页面高度。左侧显示当前 controller 图标/名称,中间显示统一 session 状态(connecting/live/paused/partial-stale/failed),右侧显示最后成功更新时间;窄窗优先隐藏右侧时间但保留 controller+状态。无 controller 显示未选择。临时 test/refresh/save 操作摘要短暂替换中间状态,结束后恢复;完整错误和 edit/test 操作留在 surface,状态栏不扩成多行。使用 structural material,Reduce Transparency 回退语义实底。
- **D41 已关闭连接使用 1000 条 + 16 MiB 双上限**。closed connection 按 controller 报告的关闭顺序保存完整业务字段,相同 connection ID 只保留最新关闭记录;达到 count 或估算 UTF8/字段内容 16MiB 任一预算即从最旧淘汰。pause 与 visible 共用 session buffer;清除动作全清;controller switch/session leave 清空且不持久化。active connections 继续直接来自 fast lane,不受历史预算影响。
- **D42 控制器列表移出导航侧栏**。`WorkbenchDestination` 从 10 项扩为 11 项,在“控制器管理”组首位新增 Controllers destination,后接配置/操作/诊断;工作台六项与 App 设置顺序不变。侧栏不再渲染完整 controller rows,只承载功能 destinations,位置不受 controller 数量/字号影响。工具栏 leading 放固定尺寸 current-controller selector(类型图标+状态点+名称),点击原生 macOS Menu 按保存顺序快速切换,当前项带 checkmark;菜单底部 Add Controller 与 Manage Controllers。完整 controller 列表在主内容区 Controllers page,展示名称、完整 endpoint、类型、连接/最后成功状态,行尾提供 test/edit/delete。状态栏继续显示 active identity。无 sheet;selector 的标准 Menu 是普通 option set 唯一例外。
- **D43 Controllers page 行选择不切换 session**。管理页使用单选 row selection 表示当前管理对象,与 active controller ID 分离。单击行只选中并展示状态;行尾提供明确 Use Controller、test、edit、delete。只有 Use 命令调用 session switch;active 行显示“正在使用”/check 且 Use disabled。不得用双击、整行点击或 selection binding 隐式切换。工具栏 selector 仍可一键切换。管理 selection 在刷新后按 ID 保持,被删除时清除/选择相邻管理行,但不影响 active session(除非删除 active 走 D35)。
- **D44 controller switch 保留当前 destination**。工具栏 selector、Controllers page Use 和其他显式选择均不修改 `WorkbenchDestination`;新 generation 在原 surface 显示 connecting/live/stale/error。若新 controller 不支持当前 destination,留在页内显示 capability unavailable 与可选“前往概览”,不自动导航。controller-scoped 临时状态(表格/Inspector selection、页面与组内搜索、旧 pending operation)按 surface 契约清理,但窗口布局/destination 保持。旧 controller 业务数据在 generation replacement 时清除,不得在新 controller 页面短暂显示。
- **D45 ControllerSwitcher 按规模限制菜单项**。controllers≤10 时按持久化保存顺序显示全部;>10 时当前 controller 固定顶部,随后显示最多 8 个唯一最近使用项,底部显示“管理全部控制器…(N)”与“新增控制器”。recent IDs 是独立 UI 元数据,可持久化但不得改变 routers 顺序;选择成功后更新 recent,删除/失效/重复 ID 清理。完整名称/endpoint/type 搜索只在 Controllers page;不新增收藏或自动分组。当前项不在 recent 中重复。
- **D46 Controllers page 允许显式手动重排**。未搜索时用户可拖动 controller rows 调整持久化 routers 顺序;搜索非空时禁用重排。重排不得改变 selected controller、session generation 或 current destination。≤10 selector 和 D35 删除 next/previous 使用该手动顺序;>10 recent menu 独立。提供键盘/VoiceOver Move Up/Down actions,不把拖动作为唯一入口。禁止按名称/状态/延迟自动排序;若未来提供临时 view sort 必须另立决策,当前不做。
- **D47 Controllers page 使用原生高密度 Table**。面向 10–100 个 controllers,主内容区采用原生 macOS `Table`,按 D46 的持久化手动顺序显示 active、name、完整 endpoint、type、status、last success 与 actions。列标题仅用于标识,禁止点击列标题排序或任何隐式自动排序。endpoint 必须完整可见或可直接选择/复制,不得中段脱敏;管理 row selection 继续遵守 D43,不会切换 session。Use/Test/Edit/Delete 组成固定最右 actions 列,命令使用紧凑图标/文本和帮助、无障碍标签,不得散落在中间数据列。表格使用系统行选中态、分隔与语义实底,不得逐行 Liquid Glass/material/card。
- **D48 Controllers Table 使用宽窄自适应列结构且不隐藏数据**。宽窗口显示 D47 的七个信息/操作列;当 detail 可用宽度不足或大/特大字号无法保持列可读性时,切换为三列:`Controller`(名称、完整 endpoint、type 的多行单元格)、`Status`(连接状态、最后成功时间)、`Actions`。端点允许自然换行并保持逐字选择/复制,不得省略中段、tooltip-only 或要求打开弹窗查看。窄布局允许行高随内容稳定增加,但 actions 列始终固定在最右侧并垂直居中。禁止横向滚动作为主要适配方案,禁止通过隐藏 type/lastSuccess 等业务字段制造假整洁。布局切换不得改变管理选择、手动顺序或 active session。
- **D49 v4 UI 保持 SwiftUI,暂不引入 AppKit 数据组件**。Controllers、连接、规则、来源和日志继续使用 SwiftUI `Table`/`List`/`ScrollView` 与 SwiftUI presentation/state。当前任务不得新增 `NSTableView`、`NSOutlineView`、`NSViewRepresentable`、`NSViewControllerRepresentable` 或以 AppKit delegate/dataSource 重建工作台 UI。允许保留和补充不承担内容渲染的系统桥接:现有 `NSApplication` 外观应用、主窗口生命周期/关闭确认、`NSWorkspace` sleep/wake 通知等。若 SwiftUI 在真实实现中无法满足 D47–D48 或性能验收,必须记录可复现阻塞并重新获得用户批准,不得自行切换 AppKit。

## Requirements

- R1(D1)删除四处 `.environment(\.colorScheme, .dark)`;整窗单一外观源。
- R2(D2/D4/D26)建立统一 surface roles + tokens;结构容器可用 material,策略/节点/Table/List/log/长文本使用语义实底;退役 glow/frost 原语;内容层无 `.glassEffect`;玻璃仅导航/悬浮功能层。
- R3(D3)`MicaDashboard.*` 全调用点直接迁移到 `MicaStyle`;`textSecondary`/`hairline` → 系统 `.secondary`/`.separator`;图表线/色点浅底不失真;迁移完成删除旧 dashboard/frost/glow 原语,不保留兼容别名。
- R4(D5–D12/D20–D24/D42/D47–D48)全部表面按最终形态重做并共用统一语言:纯功能侧栏、Controllers 自适应 Table、概览少量结构容器、策略固定错落双列+多展开、连接/规则/来源/日志 Table+Inspector、配置/操作/诊断/设置原生 structural 表单、玻璃工具栏、常驻状态栏和同窗口控制器编辑器。
- R5(D13)数据模型:去快照、选中即实时会话;会话同步逻辑并入实时会话后台刷新;工具栏动作收敛;不伪造数据。
- R6 契约与验证同步:`workbench-ui-contract.md`(Visual Hierarchy 去 forced-dark、写明整窗跟随外观 + 玻璃分层;Data Invariants 去"快照/sync 模式"、写明单一实时会话)、`docs/UI_GUIDELINES.md`、`scripts/verify-real-controller-source.mjs`(同步断言,新增"内容层无 `.glassEffect`/无强制深色"、更新数据模型断言)全部随 v4 演进并保持绿色。
- R7 数据/结构纪律不动:图表真实数据、排序契约、策略组保序 + GLOBAL 末尾 + 展开内过滤(Round 7)、空态两级文案 + 居中(Round 8)、Controllers actions 固定最右且命中区 44pt、secrets 走 `FileSecretStore` 不入 `RouterProfile`、导出不含凭据——全部保持,不因重做而回归。
- R8(D14)暂停必须冻结全部可见业务数据而保持网络会话在线;使用 D38/D37 的有界待呈现缓冲,恢复时应用最新状态并合并一次立即刷新;不得只暂停部分 Tab,不得无界缓存。
- R9(D15)持久化上次选中的控制器 ID;冷启动在 profiles/secrets 完成后自动进入该控制器的实时会话;失效 ID 回退第一项,无控制器不请求;整个启动流程只能创建一个 session generation。
- R10(D16)最小化/失焦继续会话;关闭最后主窗口或系统睡眠停止全部会话任务;唤醒仅在主窗口可见时重连;设置窗口不单独维持会话;所有 lifecycle 回调幂等并生成新 generation。
- R11(D17)以 2s/5s/30s 三档调度非流式端点,Surge near-live 保持 1s;初始与手动全量刷新经过同一 single-flight/coalescing 协调器;各档错峰、独立退避和记录更新时间,不得恢复每 10 秒全量抓取。
- R12(D18)每个端点/流保留 lastSuccessAt、lastValue 和 currentError;成功后失败展示最后值 + stale 标识,从未成功展示错误空态;恢复原地替换;切换/结束 session 清除旧控制器数据;pause 与 stale 分开建模。
- R13(D19)Phase 1 后建立 representative vertical slice;提供浅/深 × 标准/大字号真机截图和 HIG 检查;必须获得用户明确批准后才可进入剩余 Tab 的视觉铺开。
- R14(D20)策略宽窗固定双列、窄窗单列;双列按 source index modulo 2 分配,展开不重平衡;扁平化逻辑顺序、键盘顺序和 VoiceOver 顺序均等于 arrangedGroups。
- R15(D21)GLOBAL 作为普通双列卡参与固定 index 分配,不做全宽/视觉最低特殊处理;稳定 partition 后的逻辑、键盘和可访问顺序仍最后。
- R16(D22)使用展开 ID 集合和按组过滤/分页状态支持任意多组同时展开;active selection 仍单一;搜索隐藏不销毁状态,控制器/session/组删除时清理失效状态。
- R17(D23)每个展开组提供 bounded inner node scroll:过滤/动作固定在外,节点区约 432pt 且字号放大封顶 560pt,短内容收缩;保留 48 项分页、原生指示器、每组独立滚动位置和键盘/VoiceOver 可达性。
- R18(D24)持久化 `[ControllerID: Set<GroupID>]` 展开状态并在加载真实组后 prune;tab 切换保留全部运行时成员状态;App 重启仅恢复展开 ID,重置过滤/分页/滚动;删除控制器清记录。
- R19(D25)pause 时统一禁用所有 refresh 入口,test 保留;resume 原子应用 pending 后只触发一次合并全量刷新;命令菜单、工具栏、快捷键状态一致。
- R20(D26)实现 structural material 与 repeated semantic-fill 两种 surface role,共享圆角/间距/描边 tokens;策略/节点/表格/日志/长文本无逐项材质;Reduce Transparency 有实底回退。
- R21(D27)lastValue 在同一 generation 内无超时保留,持续显示 lastSuccessAt/stale;不得基于墙钟自动清空;session leave/replacement 才清除。
- R22(D28)策略 page search 保序过滤后对可见结果重新 modulo-2 紧凑分配;无空洞;清空恢复;状态按 ID 保留;非搜索更新不改变列归属。
- R23(D29)为 `RouterTrialFailureCategory` 增加结构化 retry disposition;瞬态错误无限 capped+jitter 退避,终止错误停止,HTTP 按状态分类,成功重置,手动动作可立即尝试,lifecycle leave 取消。
- R24(D30)terminal error 不自动切目的地;三处一致显示错误与 edit/test 命令;编辑保持同窗口;当前控制器保存成功自动换 generation 重连,非当前控制器保存无会话副作用。
- R25(D31)把控制器保存建模为 awaitable transaction/result;编辑器保存期间保留草稿与进度,失败内联且不关闭,成功才返回原目的地;禁止重复提交和保存中取消;当前/非当前会话副作用严格分支。
- R26(D32)dirty draft 拦截 cancel/sidebar/new/edit/window-close;普通导航用同窗口确认栏并保存 pending intent,主窗关闭使用原生 destructive confirmation;保存中所有离开路径禁用;clean draft 无额外步骤。
- R27(D33)pause 仅存于当前 session generation;Tab 切换保留,controller/session/lifecycle replacement 清除;不持久化,无页面级 pause 副本。
- R28(D34)新 controller 保存成功时仅在无有效 active controller 的情况下自动 select/connect;已有 active 时保持 session/management selection/destination,Controllers page 可提供非侵入式新行反馈;测试新草稿无会话副作用。
- R29(D35)active 删除成功后按删除前 index 选择 next/previous 并连接;非 active 删除零会话副作用;无剩余清选择;删除失败原子保留;确认文案包含回落目标。
- R30(D36)连接/鉴权失败不得修改 selected controller;无自动遍历其他 profiles;仅用户选择或 D35 删除回落可切换;错误与 stale data 始终归属并标注当前 controller。
- R31(D37)日志缓冲同时满足 count≤2000、UTF8 bytes≤8MiB,按最旧淘汰且保持到达顺序;pause/visible 共预算;过滤不改源;clear/session leave 全清。
- R32(D38)TrafficTimeline 保留 receivedAt 最近五分钟且约 300 个真实样本;无合成/插值/持久化;pause 共用 session timeline,图表与 accessibility 数据来源一致。
- R33(D39)重构 Controller CommandMenu 为 test/refresh/pause-edit/copy 集合,删除 live/sync;Add 仅 File;Delete 仅 Controllers 管理页;统一 capability 与快捷键状态。
- R34(D40)主工作台常驻稳定高度 status bar,展示 controller/session/lastSuccess;临时 operation 只替换中间摘要;窄窗渐进隐藏时间;无布局跳动,Reduce Transparency 有实底回退。
- R35(D41)closed connection buffer 同时满足 count≤1000、estimated bytes≤16MiB,按最旧淘汰、ID 去重保最新、保持关闭顺序;pause 共预算;clear/switch/leave 全清。
- R36(D42)侧栏只渲染 11 destinations;工具栏 selector 快速切换并提供 add/manage;Controllers destination 承载完整列表与 test/edit/delete;controller 数量不改变 destination 位置;菜单/页面选择共用 session switch API。
- R37(D43)Controllers page managementSelection 与 selectedRouterID 分离;row click 只管理选择;Use 明确切换,active Use disabled;刷新/删除稳定 reconcile;无双击隐藏行为。
- R38(D44)所有显式 controller switch 保持 destination;unsupported 显示页内空态不跳转;清 controller-scoped presentation selection/search/pending,清旧业务数据;布局与 nav 不变。
- R39(D45)ControllerSwitcher ≤10 全量有序,>10 为 current+recent8+manage/add;recent 独立持久化、去重/prune,不重排 routers;完整搜索只在管理页。
- R40(D46)Controllers page 在 search empty 时支持持久化 manual reorder,search active 禁用;mouse/keyboard/VoiceOver 均可移动;无 automatic sort;active session 不受影响。
- R41(D47)Controllers page 使用原生高密度 Table,按手动顺序展示 active/name/full endpoint/type/status/lastSuccess/actions;禁列排序;endpoint 可选择复制;actions 固定最右;row selection 不切 session且无逐行 glass/material/card。
- R42(D48)Controllers Table 依据实际 detail width/font scale 在七列与三列复合单元格间切换;两种布局业务字段等价且 endpoint 完整可选择;窄布局无横向滚动/隐藏列,actions 固定最右,切换不改变 selection/order/session。
- R43(D49)全部工作台内容 UI 使用 SwiftUI;源码不新增 AppKit table/outline/view representable 或 delegate/dataSource UI。AppKit 仅限 application/window/workspace 系统桥接;任何扩大范围必须先形成阻塞证据并由用户重新批准。

## Acceptance Criteria

- [ ] AC1(D1)系统浅色整窗协调浅、深色整窗协调深,无"左白右黑";浅/深/跟随三档即时对整窗生效;源码无 `.environment(\.colorScheme, .dark)`。
- [ ] AC2(D2/D4/D26)全部表面套用统一 tokens 与 surface roles;结构层可用 material,重复内容使用语义实底;内容层无 `.glassEffect`、无 glow/frost 卡;玻璃仅存于导航/悬浮功能层;`apple-hig-expert` HIG 检查通过(玻璃合规 + 对比度 ≥4.5 文本 / ≥3.0 图形)。
- [ ] AC3(D3)前景色全走 `MicaStyle`;旧 `MicaDashboard`/frost/glow 原语删除且无兼容别名;浅/深两模式对比度达标。
- [ ] AC4(D5–D12/D20–D24/D42/D47–D48)每个表面达成最终形态:侧栏仅功能导航;Controllers 自适应 Table;概览少量结构容器;策略固定错落双列、多展开和延迟可视化;数据页 Table+Inspector;表单页 structural 原生表单;工具栏玻璃;状态栏材质条;编辑器同窗口表单。真机主观复核整窗一致、不割裂、不廉价。
- [ ] AC5(D13)选中控制器即自动进入实时会话、数据自动更新,无"快照/sync"模式与"待刷新 idle"中间态;connections/rules/proxies/providers 有数据(后台 REST 补拉);工具栏动作收敛;失败重连正常;不伪造数据。
- [ ] AC6(R6)`workbench-ui-contract.md` + `docs/UI_GUIDELINES.md` 已去 forced-dark/快照表述并写明整窗跟随外观 + 玻璃分层 + 单一实时会话;`node scripts/verify-real-controller-source.mjs` 通过。
- [ ] AC7(R7)`swift build` 零错误;`swift test` 全绿;source verifier + `git diff --check` + HIG 全通过;按用户要求不运行 runtime smoke;数据/排序/保序 + GLOBAL/空态/侧栏/secrets 契约无回归。
- [ ] AC8(全局)中英双语、浅/深/跟随、4 档字号、Reduce Transparency/Motion 下全部界面可用;VoiceOver 可达;图表附可访问数值回退。
- [ ] AC9(D14)暂停后所有 Tab 的可见时间点一致且不再变化,后台连接与拉取保持;待呈现 traffic/log 分别满足 D38/D37 预算、REST 状态只保留最新值;恢复后原子切到最新状态并只触发一次合并刷新,无突发重复请求、无旧 session 写入。
- [ ] AC10(D15)选择控制器后重启 App 会自动恢复同一控制器并立即显示“连接中”;不存在的持久化 ID 稳定回退第一项并修正存储;无控制器时零网络请求;重复 view appear 不会创建第二套 WebSocket/REST/retry 任务。
- [ ] AC11(D16)最小化或切换 App 后 session ID 不变且数据继续;关闭最后主窗口后全部网络/retry task 取消;仅设置窗口存在时零会话;睡眠停止、唤醒且主窗可见时只建立一个新 generation;旧 generation 的延迟结果全部被拒绝。
- [ ] AC12(D17)自动化时钟测试证明 fast/medium/slow 分别按 2s/5s/30s 触发且首轮错峰;同一端点任意时刻最多一个请求;手动 refresh 与周期请求重叠时只产生一次 follow-up;某一档失败不会停止其他档,重试按退避执行;暂停呈现期间调度继续且不改变可见数据。
- [ ] AC13(D18)端点首次成功后断线仍显示完全相同的最后数据,并显示 stale + 准确最后成功时间;未成功端点显示错误空态;健康端点仍更新;重连无清空闪屏;切换控制器后旧数据归零;测试覆盖 live/partial/stale/paused 的正交组合。
- [ ] AC14(D19)代表性 slice 同时覆盖导航 chrome、卡片/Charts、策略折叠与成员选择、Table/Inspector、Form;浅/深 × 标准/大字号截图无割裂、无逐行 material/glass、无文字裁切;用户明确批准记录在任务后,剩余 Tab 才开始改造。
- [ ] AC15(D20)输入 `[A,B,C,D,E]` 时双列固定为左 `[A,C,E]`、右 `[B,D]`;展开 A/C/B、过滤、刷新或延迟变化均不改变任何组的列归属;窄窗输出单列 `[A,B,C,D,E]`;键盘与 VoiceOver 始终按 `A→B→C→D→E`,而非逐列读取;源码和纯 presentation 测试禁止 shortest-column/rebalance/sorted。
- [ ] AC16(D21)输入 `[A,GLOBAL,B]` 经稳定 partition 得 `[A,B,GLOBAL]`,双列为左 `[A,GLOBAL]`、右 `[B]`;即使 A 展开导致 GLOBAL 的 y 坐标变化,GLOBAL 仍不被抽成全宽或重分配;扁平化/键盘/VoiceOver 顺序始终 `[A,B,GLOBAL]`。
- [ ] AC17(D22)可同时展开 A/B/C;收起 B 不改变 A/C;A/B 的过滤词与分页窗口互不影响;页面搜索隐藏 A 后清空可恢复其展开和过滤状态;完整快照删除 B 时只 prune B;切换控制器清空全部;点击 C 后 active selection=C,但 A/B 仍展开。
- [ ] AC18(D23)含 3/48/96 节点的组分别表现为自然短高/封顶滚动/分页加载更多;多组内层滚动互不影响并保留位置;过滤栏和组动作始终可见;标准至特大字号不裁切且最大高度不超过约 560pt;键盘可进入/离开内层列表,VoiceOver 能报告组名、节点数和滚动区域。
- [ ] AC19(D24)控制器 A 展开 G1/G2、控制器 B 展开 G3 后切换和重启,分别恢复 A=`{G1,G2}`、B=`{G3}`;过滤/分页/滚动重启后均为默认;服务端删除 G2 后只 prune G2;删除控制器 A 后磁盘不再包含 A 的展开记录。
- [ ] AC20(D25)暂停后 toolbar/menu/⌘R refresh 全部不可用且帮助文本正确,test 仍可用;后台 client spy 继续收到周期请求;resume 只产生一次 coalesced full refresh,业务数据在 resume 前逐值不变。
- [ ] AC21(D26)源码检查证明 Table/List/log/member row 和 63 个策略卡无 `.regularMaterial`/`.glassEffect`/`.blur`/`.shadow`;结构卡可用 material 且 Reduce Transparency 变为语义实底;代表性 slice 的两种 role 在浅/深模式仍属于同一 tokens 与层级语言。
- [ ] AC22(D27)模拟端点成功后连续失败 1 分钟/1 小时/24 小时,lastValue 始终完全保留、lastSuccessAt 不变且状态为 stale;同 session 恢复直接替换;generation leave 后数据清空;源码无基于 stale age 清空业务数据的 timer/threshold。
- [ ] AC23(D28)原序列 `[A,B,C,D,E,F]` 搜索得 `[B,D,E]` 时左 `[B,E]`、右 `[D]`,扁平顺序 `[B,D,E]`;清空搜索恢复左 `[A,C,E]`/右 `[B,D,F]`;B/D/E 的展开、过滤、分页和滚动状态不丢;仅延迟或刷新数据变化不触发换列。
- [ ] AC24(D29)表驱动测试覆盖每个 failure category 和 HTTP 408/429/4xx/5xx;瞬态序列达到 30s 后继续但不超过上限,终止类不调度下一次,success 重置为 2s,manual attempt 不与 in-flight 重复,lifecycle leave 后测试时钟推进不再产生请求;jitter 可注入并确定性验证。
- [ ] AC25(D30)terminal failure 前位于策略页时仍留在策略页并保留 stale 数据;状态栏/toolbar selector/Controllers page/当前页面错误一致且 edit/test 可达;点击 edit 才进入主窗编辑器;保存当前控制器成功后旧 generation 无法写入且只创建一个新 session;编辑其他控制器不改变当前 session ID。
- [ ] AC26(D31)注入 secret/profile 写入失败时编辑器保持、字段逐值不变、错误内联、live session ID 不变;成功时仅写入一次、编辑器关闭并回到原目的地;当前控制器只创建一个新 generation,非当前控制器 session ID 不变;快速双击保存只执行一个 transaction。
- [ ] AC27(D32)clean cancel 立即关闭;dirty cancel/侧栏切换/新建/编辑其他控制器均不丢草稿并显示 inline confirm;继续编辑不导航,放弃后执行原 pending intent;保存中这些入口不可用;dirty window close 的取消保持窗口与草稿,确认才关闭;全流程除 window close 外无 sheet/popover/alert。
- [ ] AC28(D33)当前 controller 暂停后切换任意 Tab 仍暂停;切换 controller、保存当前 controller、close/reopen、sleep/wake 或重启 App 后新 generation 均未暂停;UserDefaults/配置文件无 pause 键;任一页面 pause 命令更新全局同一状态。
- [ ] AC29(D34)A 活跃时新增 B,A 的 session ID/streams/data/destination/management selection 逐值不变,B 出现在 Controllers page 与 selector 数据源且只可由显式 Use/switch 激活;空列表新增 A 自动 selected 并只建立一个 session;编辑器 test B 不修改 selected ID;新增保存失败既不追加 B 也不影响 A。
- [ ] AC30(D35)列表 `[A,B,C]` 删除 active B 后选择 C;删除 C 后选择 B;删除唯一 A 后 selected=nil;删除非 active 不改变 session ID;注入 secret/profile 删除失败时列表、selected、session 和持久化逐值不变;确认文案准确预告目标。
- [ ] AC31(D36)A 失败且 B/C 可用时推进重试时钟不会改变 selected=A 或启动 B/C 请求;terminal A 仍停留 A 并显示 edit/test;只有用户点击 B 或删除 A 才切换;所有页面/导出诊断明确标注数据属于 A。
- [ ] AC32(D37)追加 2001 条短日志后只保留最新 2000 条;追加不足 2000 条但 UTF8 总量超过 8MiB 时按最旧淘汰到预算内;多字节中文按真实字节计;pause 后恢复保持原到达顺序;过滤前后源缓冲相同;clear/切换 controller/session leave 后 visible+pending 均为空。
- [ ] AC33(D38)以测试时钟追加 301 个 1s 样本只保留最近约 300/五分钟;跳时后旧样本按 receivedAt 淘汰;空档不补点;controller/session reset 清空;pause 期间 visible 数组不变但 session timeline 前进,resume 后显示最新窗口;源码保持无 Timer/合成样本断言。
- [ ] AC34(D39)Controller 菜单仅出现七个规定条目/分隔结构,源码无 `toggleLiveStreams`/`toggleSessionAutoSync` 菜单入口;Add 只在 File,Delete 只在 Controllers 管理页;⌘R 与 toolbar 同 capability,pause 时两处 refresh 同时禁用;中英帮助/无障碍文本一致。
- [ ] AC35(D40)无 controller/connecting/live/paused/partial/stale/terminal error/working/success 各状态切换时 detail 可用高度不变化;标准至特大字号高度稳定且文本不裁切;窄窗只隐藏 lastSuccess;临时 operation 结束恢复 session 摘要;VoiceOver 合并读出 controller+状态+时间。
- [ ] AC36(D41)追加 1001 条短 closed rows 只保留最新 1000;不足 1000 但估算内容超过 16MiB 时淘汰最旧;重复 ID 更新为最新且无重复;source order 不排序;pause/resume 顺序不变;clear/controller switch/session leave 后缓冲为空。
- [ ] AC37(D42)添加 1/10/100 个 controllers 时侧栏 11 个 destination 的位置和高度不变;toolbar selector 按保存顺序列出并正确 check active,Add/Manage 可达;Controllers page 完整显示 endpoint/type/status 且 test/edit/delete 在行尾;选择器与页面切换只建立一个 generation;中英×4 字号无裁切。
- [ ] AC38(D43)A active 时单击 B 行只改变 managementSelection=B,session ID/selectedRouterID 不变;test/edit B 不抢占 A;点击 Use B 才建立一个 B generation;active B 的 Use disabled;删除非 active selected row reconcile 管理选择但 A session 不变;无 row double-click switch。
- [ ] AC39(D44)在 logs/proxies/diagnostics/controllers 各页从 A 切 B 后 destination 逐值不变,旧 A rows/selection/search/Inspector 不出现在 B;B unsupported 时只显示页内 unavailable + 可选 overview action;点击 action 才导航;切换期间页面尺寸和 sidebar selection 不跳。
- [ ] AC40(D45)1/10 controllers 菜单全显且顺序等于 routers;11/100 controllers 菜单为 current + 最多 8 unique recents + manage/add,current 不重复;选择更新 recent 但 routers 顺序不变;删除/失效 ID prune;Manage 导航 Controllers 且 Add 打开同窗口编辑器。
- [ ] AC41(D46)将 `[A,B,C]` 拖为 `[C,A,B]` 后重启仍保持;selected/session ID 不变;搜索非空时 drag/Move commands disabled;键盘与 VoiceOver 可上移/下移并报新位置;≤10 menu 和删除回落读取新顺序;源码无自动 `.sorted` controller list。
- [ ] AC42(D47)10/100 个 controllers 均以原生 Table 对齐显示 active/name/full endpoint/type/status/lastSuccess/actions,顺序等于持久化 routers;点击任意列标题不改变顺序;完整 endpoint 可选择复制且 UI 不脱敏;单击行只改变 managementSelection;Use/Test/Edit/Delete 固定在最右 actions 列;源码和真机检查无 controller row card、逐行 material/glass/shadow。
- [ ] AC43(D48)在宽窗口标准字号时显示七列;缩到 820pt 主窗或切换大/特大字号后稳定切为 Controller/Status/Actions 三列,名称、完整 endpoint、type、状态和 lastSuccess 均仍可见且 endpoint 可逐字复制;无横向滚动、无中段省略、无隐藏字段;actions 保持最右且不覆盖文字;来回缩放不改变 managementSelection、routers 顺序或 session generation。
- [ ] AC44(D49)新增/重构的工作台视图全部由 SwiftUI 实现;源码检查无 `NSTableView`、`NSOutlineView`、`NSViewRepresentable`、`NSViewControllerRepresentable` 或 AppKit delegate/dataSource 内容 UI;现有/新增 AppKit 引用仅服务外观、窗口生命周期、关闭确认和 sleep/wake;若 D47–D48 无法通过,任务停在记录阻塞而不是静默改架构。

## Out of Scope

- 除 D42 明确的 controller switcher/Controllers destination 外,其余 destination 分组与工作台六项快捷键不再扩张。
- 图表数据层、排序契约、策略组保序等数据纪律语义(不动,仅视觉)。
- 密钥加密/口令保护;从旧 Keychain 迁移(维持 Round 2 决定)。
- 实时内存曲线、延迟历史序列(无流式数据源,不伪造时间轴)。
- 菜单栏 extra、多窗口、通知等 UI 外围。
- AppKit 数据表格、outline view 或工作台内容层重写;本任务先以 SwiftUI 完成。
- 滚动性能真机 Instruments 实测(v3 已迁出为独立后续任务;v4 遵守既有实数据/观察粒度纪律但不承诺帧率实测)。
