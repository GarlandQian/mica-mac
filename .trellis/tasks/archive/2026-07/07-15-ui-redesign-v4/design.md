# Design — UI 重做 v4

设计判断:这是面向高频管理和诊断工作的原生 macOS Pro Tool,视觉密度高、动效克制、系统控件优先。本文聚焦统一 surface roles、控制器上下文与导航、D13 实时会话模型、策略页固定错落双列和验收门;网页 landing-page 规则不适用。

## 1. 统一表面词汇(D2/D4)

### 新增共享原语(替代 glow/frost)

在 `MicaSurfaces.swift`(或新 `MicaCardStyle.swift`)定义一个带显式 role 的 content-layer 容器,由需要结构分组或重复内容边界的表面共用:

```
// 内容层统一容器:role 决定 material 或语义实底,共享圆角和描边 tokens
struct MicaContentCard<Content: View>: View {
    var tint: Color? = nil          // nil = 中性;有值 = 极淡语义描边
    var role: MicaContentSurfaceRole // structuralMaterial / repeatedContent
    var padding: CGFloat = 16
    var spacing: CGFloat = 10
    // structural: .regularMaterial; repeated: semantic opaque fill
    // both: RoundedRectangle(cornerRadius: token) + semantic stroke
    // 无 .environment(colorScheme,.dark)、无 GlassEffect、无 blur-heavy 叠层
}
```

- `structuralMaterial`:仅用于低数量页面结构卡,正常外观 `.regularMaterial`,Reduce Transparency 回退系统语义实底。
- `repeatedContent`:用于策略组卡等高数量重复容器,始终使用系统语义实底 + separator/tint 描边,不采样背景。
- Table/List rows、日志、规则、节点和长文本不包 `MicaContentCard`,直接使用原生内容背景、selection 和 divider。

- **退役**:`MicaGlowCard`、`MicaFrostCard`、`MicaFrostBackdrop`、`micaDashboardSurface()`、`MicaDashboard.neutralFill/tintedFill/edgeGlow/pageBackdrop`。
- **保留**:`MicaGlassSelectionSurface`(唯一自定义玻璃原语,悬浮/交互选择块用;verifier :308 断言不破)。
- **tokens**:圆角、padding、描边 opacity、卡间距做成 `MicaStyle`/`MicaLayouts` 常量,避免逐处魔法数字。

### 色板收敛(D3)

- `MicaDashboard.signalX/accent` → 逐点替换为 `MicaStyle.signalX/accent`(已 WCAG ≥4.5 双档达标),迁移完成后删除旧类型。
- `MicaDashboard.textSecondary` → `.secondary`;`hairline` → `MicaStyle.separator` / `.separator`。
- 图表(`WorkbenchOverviewView` Charts)线色/色点改 `MicaStyle`,浅底不失真。
- 迁移量:概览 ~30 处、策略 ~15 处,机械替换 + build 验证。

## 2. Controller context 与 destination navigation 分层(D42)

- UI 技术边界遵守 D49:本节全部由 SwiftUI 实现,不引入 `NSTableView`/`NSOutlineView` 或 representable wrapper。宽窄列切换使用 SwiftUI 可用宽度观测、`ViewThatFits` 或等价的纯 presentation model;不得用 AppKit 内容视图绕过状态契约。
- `WorkbenchDestination` 新增 `.controllers`,归入 controllerManagement 首位。工作台 `⌘1...⌘6` 集合不变;Controllers 不占数字快捷键。
- `WorkbenchSidebarView` 删除 controller Section/rows/add header,只渲染 destination sections。sidebar 宽度与 controller 数量解耦。
- toolbar leading 新建 `ControllerSwitcher`:固定宽度约束 + icon/status/name + native Menu。Menu rows 只执行 switch,底部 Add/Manage 走已有同窗口 presentation/navigation;不放 edit/delete 破坏性动作。
- 新 `WorkbenchControllersView` 在内容区呈现原生高密度 `Table`,支持搜索;业务数据全可见。列固定表达 active/name/full endpoint/type/status/lastSuccess/actions,不提供列排序。endpoint 使用可选择文本并允许复制,不做中段脱敏。最右 actions 列集中放置 Use/Test/Edit/Delete,保留固定 44pt hit target和帮助/无障碍文本。
- selector/menu/page 切换全部调用同一 `selectRouter`/session coordinator;不得各自复制 generation lifecycle。
- `WorkbenchControllersView` 持有独立 `managementSelectionID`;Table/List selection 只控制管理焦点。Use button 才调用 `selectRouter`;active row 由 `selectedRouterID` 另行绘制 check/badge。
- 管理 selection reconcile 使用完整 routers 顺序;刷新保持 ID,删除选择 next/previous 只影响管理焦点。active 删除仍委托 D35。
- switch coordinator 不接收 destination binding。ContentView 在 generation replacement 时调用各 surface 的 controller-scoped presentation reset,但不写 `destinationRawValue`;unsupported 由 destination view 自己呈现 capability empty state。
- `ControllerSwitcher` 由纯 presentation 函数生成 menu model:small list=routers;large list=current + deduped/pruned recent prefix(8)。recent persistence 与 routers store 分离,不得写回 profile order。
- Controllers reorder 通过显式 AppModel transaction 更新 routers + profile store。drag/drop 与 Move Up/Down 共用同一 `moveController(id:to:)`;search 非空 capability=false。操作不调用 session coordinator。
- Controllers Table 的 row background、selection 和 separator 使用原生系统语义;禁止把每行包装为卡片、material 或 Liquid Glass。Table column header 不绑定 sort comparator,展示顺序唯一来自持久化 routers。
- Controllers Table 读取 detail 可用宽度与 font scale 生成两种等价 column model:宽布局为七列;紧凑布局为 Controller/Status/Actions 三列。Controller cell 垂直排列 name、完整可选择 endpoint、type;Status cell 排列 session state 与 lastSuccess。切换只改变 presentation,rows identity、managementSelection、manual order 和 session coordinator 均不变。紧凑布局允许自然增加 row height,不启用横向滚动、不隐藏业务字段;actions column 固定 trailing。

## 3. D13 数据模型:去快照,单一实时会话(最高风险)

### 现状(三路径)

- `refreshSelectedRouter()` — 一次性全量 REST。
- `startSessionAutoSync` / `sessionSyncTask` / `runMihomo|SurgeSessionAutoSyncLoop` / `syncMihomoSessionSnapshot` — 每 `sessionAutoSyncIntervalSeconds` 秒 REST 全量轮询(**用户可见"快照/sync"**)。
- `startLiveStreams` / `liveTrafficTask` / `liveLogsTask` — WebSocket 只 traffic+logs;Surge 1s 近实时轮询。

### 关键约束(不可绕过)

mihomo **只有 traffic/logs 两条 WebSocket**;connections/rules/proxies/providers/config **只能 REST**。所以"实时"底下**必须保留一条后台 REST 刷新**——它就是现在的 session-sync loop,只是不再作为用户可见模式。

### 目标模型:单一 `LiveSession`

选中控制器 → `enterLiveSession(router)` 自动启动,包含两个并发子系统(对用户是一个"实时"状态):

1. **推流子系统**(mihomo WebSocket traffic+logs;Surge 近实时轮询)——现有 `liveTrafficTask`/`liveLogsTask` 逻辑基本不动。
2. **后台刷新子系统**(REST 拉 connections/rules/proxies/providers/config)——**复用**现有 `runMihomoSessionAutoSyncLoop` + `syncMihomoSessionSnapshot` 的抓取/apply 逻辑,但:
   - 去掉 `syncRequested` 这个独立用户开关,生命周期绑定 `LiveSession`。
   - 去掉 `controllerSession.syncState` 的用户可见 `.synced/.syncing/.stopped` 文案,合并进 `liveStreamState`(或统一 `sessionState`)。
   - 保留失败重连退避(`sessionAutoSyncRetryDelay` 的 2/4/8/15/30)。

### 状态合并

- **删**:用户可见的"快照/会话同步"模式开关、`toggleSessionAutoSync` 的 UI 入口、"待刷新 idle"引导态(Round 3 D9 的 `OverviewIdleGuide` 逻辑需改——不再"选中不加载",而是"选中即连接中")。
- **统一 sessionState**:`connecting → live(数据流动) → partial(部分端点失败) → failed(可重试)`。概览/状态栏/工具栏都读这一个状态。
- **工具栏收敛(D10)**:`test / refresh / pause-resume` 三项已定。实时会话默认常开;删除 live/sync 独立开关。refresh 受 D25 pause capability 约束,test 保留为显式诊断尝试。

### 暂停呈现(D14,已定)

- 暂停不取消 WebSocket、Surge 近实时轮询或后台 REST;session 仍处于 connected/live,另有 presentation-paused 正交状态。
- 可见模型在暂停瞬间冻结。所有异步 apply 先写入同一个有界 pending presentation:REST/端点状态只覆盖为最新值;traffic 使用 D38 五分钟时间线预算;日志使用 D37 的 count+bytes 双上限。
- 恢复时在 MainActor 上原子替换可见模型,清空 pending,再通过刷新协调器请求一次 immediate refresh。若周期刷新已在飞,只标记一次 follow-up,不得并发重复请求。
- 状态栏显示“已暂停呈现”,诊断仍能说明网络会话在线。任何 Tab 不得绕过统一 presentation gate 直接修改可见业务数据。

### 冷启动恢复(D15,已定)

- 新增 selected-controller ID 持久化键;`selectRouter` 成功切换时更新,删除当前控制器后的回退选择也同步更新。
- `loadPersistedState()` 的顺序固定为:load profiles → 解析持久化 ID/稳定回退 → load secrets → 建立唯一 session generation → `enterLiveSession(router)`。secrets 未完成前不得启动请求。
- 无控制器时保持配置空态且不创建 generation。失效持久化 ID 回退 `loadedProfiles.first` 并立即修正存储,避免每次启动重复走失效分支。
- 自动进入实时会话由 AppModel 的幂等加载流程触发,不绑在可重复执行的 view `onAppear` 上;测试覆盖重复 load/appear 只能产生一个 session。

### 窗口与系统生命周期(D16,已定)

- App active/inactive 不控制 session;只要至少一个主工作台窗口仍存在,最小化或切换 App 都保持连接。
- 通过现有 AppKit window lifecycle bridge 识别最后一个主窗口关闭,调用幂等 `leaveLiveSession(reason: .noMainWindow)`;Settings scene 不计入主窗口。该桥接不承载工作台内容 UI。重新创建主窗口时调用幂等 resume,为持久化选择建立新 generation。
- 订阅 `NSWorkspace.willSleepNotification` / `didWakeNotification`:睡眠前停止所有网络、retry 与 pending presentation;唤醒后检查主窗口可见性,满足才重连。
- close/sleep/select/delete/edit-save/网络恢复都走同一 session coordinator,禁止各自直接启动 task。每次停止先使 generation 失效再 cancel,保证取消不及时的异步结果也无法 apply。

### 分级 REST 调度(D17,已定)

- 用一个 session-scoped refresh coordinator 管理三条 lane,而不是三个视图自行建 Task:
  - fast 2s:connections/active requests;
  - medium 5s:proxies/policy groups/current selection;
  - slow 30s:rules/providers/config/version。
- session 首次连接执行一次全量请求;随后 lane 使用不同起始 offset 错峰,避免同一时刻形成请求尖峰。Surge 现有 1s near-live traffic/events/requests 保持独立,但仍受同一 generation/cancellation 约束。
- coordinator 按 endpoint/lane 维护 in-flight、pendingFollowUp、lastSuccess、lastFailure 和 retryAttempt。周期 tick 或手动 refresh 遇到 in-flight 只设置一次 pendingFollowUp;完成后最多补跑一次。
- lane 失败只更新对应端点健康并独立退避,不阻断其他 lane。聚合 session 状态从各 lane + stream 状态计算,不把一个 provider 错误升级为全 session failed。
- 测试注入 clock/sleeper 和 client spy,不依赖真实等待或网络;断言频率、错峰、single-flight、coalescing、取消和 generation guard。

### 重试分类(D29,已定)

- 在 `RouterTrialFailureCategory` 上定义非本地化 `retryDisposition`:transient / terminal / cancelled / retryOnce,并为 `unexpectedHTTP(Int)` 按 408/429/5xx 与其他 4xx 分类。
- retry coordinator 接收可注入 jitter source。生产环境在 capped 30s 周围加小幅随机抖动;测试使用固定值。每 lane 独立 retryAttempt,任一 lane 成功只重置自身。
- terminal 失败停止对应 session 或 lane 的自动调度,但保留 D18 stale data 与诊断。用户手动 test/refresh 是显式新尝试,仍走 single-flight/generation guard。

### Terminal error 导航(D30,已定)

- session coordinator 只发布结构化 terminal error/capabilities,不直接修改 `WorkbenchDestination` 或 `RouterEditorPresentation`。
- Workbench shell 在状态栏与当前 surface 提供 edit/test commands;toolbar selector 与 Controllers page 同步错误状态。edit 通过现有 `routerEditor` detail presentation 打开,无 sheet/popover。
- 当前 controller 保存成功后由统一 coordinator replace session;非当前 controller 保存只更新 profile/secret/persistence。任何保存失败都不得销毁活跃 session。

### 控制器保存事务(D31,已定)

- `AppModel.upsertRouter` 提供 async/throwing 或 typed result API,不再内部启动不可等待 Task。UI 持有 `isSaving` 和 typed inline error。
- transaction 在变更 live session 前先完成可回滚持久化边界;失败保持原 profile/secret/session。成功后再原子更新 routers/selected ID,随后按 affectsSelectedSession 决定 replace session。
- RouterEditor 保存期间 Save/Cancel/测试与会引发第二次提交的导航入口禁用。成功回调携带原 destination,由 ContentView 关闭 editor 后恢复。
- 测试注入失败的 SecretStore/ProfileStore,验证输入、存储和 session 的失败原子性。
- 新 controller 的 post-commit selection 由 D34 决定:已有 valid selected ID 时不调用 replace session;无有效选择时才 select + enter。Controllers page 可提供瞬态新增反馈,但不得改变 management selection 或 active session。

### 控制器删除回落(D35,已定)

- delete transaction 在修改数组前捕获 active index 和预期 replacement ID,用于确认文案与成功后的稳定回落。不得删除后再用 `routers.first` 猜目标。
- profile store 与 secret store 删除失败保持原模型/session;全部成功后先 invalidate old generation,再移除 profile/展开偏好,更新 selected persistence,最后按 replacement enter 新 session。
- 非 active 删除不 invalidate generation。测试覆盖 first/middle/last/only、非 active 和存储失败。

### 无自动故障转移(D36,已定)

- session coordinator 只维护 selected controller 的 generation,不存在“尝试下一个 profile”循环或 fallback candidate。
- retry/terminal state 必须携带 controller ID;apply、状态栏、stale surface 和 diagnostics 均校验并显示该 ID/名称。其他 profiles 的 trial health 不能升级为 active selection。
- D35 删除回落是由明确 destructive action 触发的独立路径,不复用 connection-failure 逻辑。

### 日志环形缓冲(D37,已定)

- 抽 `BoundedLogBuffer` 维护 ordered entries、UTF8 byte total、maxCount=2000、maxBytes=8MiB。append 后从 oldest 端循环淘汰,不能每次重算全数组字节数。
- visible/pending 可使用同一个 session-owned buffer + presentation cursor/snapshot,避免暂停时双份各占 8MiB。恢复只推进可见 cursor/投影,保持到达顺序。
- filter/search 返回 projection,clear 原子清 entries/bytes/pending cursor。测试覆盖多字节文本、单条日志大于预算和批量 append。

### 五分钟 TrafficTimeline(D38,已定)

- `TrafficTimeline` 保持真实 received event 模型,容量约 300,append 时同时按 count 与 `receivedAt >= newest-5min` 裁剪。没有新事件时不靠 Timer 插入或移动样本。
- session timeline 与 visible projection 分离,pause 只冻结 projection。resume 读取最新完整 window。controller/session reset 清空两者。
- 如 Charts 需要减少 marks,使用纯函数按像素/固定 bucket 从原始样本选择代表点;不得生成不存在的值。accessibility/diagnostics 始终读原始样本。

### Dirty draft 导航门(D32,已定)

- `RouterEditorPresentation` 记录 initial draft、current draft、isSaving 和 optional pending navigation intent。dirty 比较使用结构化 Equatable 字段,不比较本地化预览文本。
- ContentView 所有会清空/替换 editor 的入口先经过统一 `requestEditorExit(intent)`;dirty 时只设置 pending intent 并展示 editor 内确认栏。确认 discard 才执行 intent,keep editing 清 pending。
- 保存中 `requestEditorExit` 拒绝 intent。window close 由 AppKit delegate 查询 editor dirty/save 状态;dirty 使用原生 destructive confirm,保存中阻止关闭。
- pending intent 覆盖 destination、add controller、edit controller、cancel editor;测试确保后来的 intent 不在未确认时静默覆盖前一个。

### 最后成功数据与 stale 状态(D18,已定)

- 每个 endpoint/channel 状态保存 `lastValue`、`lastSuccessAt`、`currentError` 和 availability(`neverLoaded/live/stale/failed`)。聚合 `sessionState` 只做展示,不覆盖这些细粒度事实。
- 有 `lastValue` 的失败转为 stale,projection 继续读取 lastValue,并在所属 surface 显示 lastSuccessAt;无 lastValue 的失败才进入错误空态。
- pause 是 presentation 维度,stale 是数据健康维度。暂停期间网络失败可更新 endpoint diagnostics/pending health,但 visible business value 保持冻结;恢复后原子呈现最新 live/stale 组合。
- controller switch、delete、close-window leave 和 sleep leave 都清除该 generation 的 lastValue/pending,防止跨控制器泄漏。短暂重连不得先置空,成功结果直接替换 stale 值。
- stale age 只影响标签/警告权重,不驱动数据删除。实现不得创建 stale-expiry Task/Timer;lastValue 的唯一清理边界是 session generation 结束。

### 风险与验证

- **改动面广**:`AppModelLiveSession.swift`(628 行)、`AppModelRuntimeOperations.swift`、`AppModelSelectionState.swift`(selectRouter 需触发 enterLiveSession)、`DashboardSessionModels.swift`(controllerSession 状态字段)、概览/状态栏/工具栏视图。
- **Round 3 反转**:selectRouter 现在只 reset 为 idle;v4 改为自动 enterLiveSession → **自动发网络请求**。这是用户明确要的("连上即实时"),但要确保切换控制器时正确 cancel 旧 session(现有 `selectedRouterID == routerID` 守卫复用)。
- **verifier**:概览 `trafficTimeline.isEmpty` 空态守卫、无 Timer/合成样本断言仍须过(后台 REST 刷新不是 Timer 合成 traffic,是真实拉取,合规)。
- **无头限制**:实时连接为运行时行为,自动化只验证注入 client/clock 的状态机、generation 与零真实网络请求;按用户要求不运行 runtime smoke,真机确认"选中即有数据"。

## 4. 代表性视觉验收门(D19)

统一表面原语完成后不直接铺满全部 Tab,先建立一条真实数据 vertical slice:

1. 工作台 shell:原生侧栏、glass 工具栏、material 状态栏。
2. 概览:共享卡片、KPI、Charts、真实空态。
3. 策略:一个真实组的折叠/展开、节点过滤、选择与延迟状态。
4. 连接:原生 Table、排序、选择和按需 Inspector。
5. 设置:一个使用共享节奏的原生表单分组。

slice 使用现有控制器响应或真实无数据状态,不引入 fixture/mock 业务数据。验证矩阵至少为 light/dark × standard/large,同时覆盖 Reduce Transparency。产出截图并记录用户明确批准;未批准时只允许修改 tokens、共享原语和 slice 页面,不得继续迁移剩余 Tab。批准后,共享原语成为其余页面的唯一视觉实现来源,禁止各 Tab 自创新卡片样式。

## 5. 策略页固定错落双列 + 多展开(D7/D20–D24)

### 布局

- 折叠态宽窗为固定双列,窄窗为单列;不使用自适应三列以上布局。
- **已选方案(D20)**:Zashboard 式两个独立 `LazyVStack`,按 source index 奇偶固定分配卡片,每卡在本列原地展开。展开后允许左右列高度错落。
- 分配只能由纯函数 `staggeredColumns(visibleOrderedGroups)` 完成:`left = indices 0,2,4...`,`right = 1,3,5...`;不读取卡片高度,不做 shortest-column/masonry rebalance,不排序。
- 窄窗使用当前 visible ordered collection 单列渲染;跨阈值时按同一 index 规则重建两列。页面搜索先过滤完整有序集合,再把紧凑过滤结果传入分配函数;清空后恢复原分配。
- 视觉容器是左右两列,但交互语义仍是单一横向序列:键盘上下/左右移动、VoiceOver sort priority、可访问序号都按 arrangedGroups index,不得按 SwiftUI 容器默认的“整列读取”顺序。
- 使用 `expandedGroupIDs: Set<GroupID>` 允许任意多组展开;每个展开内容仍在对应卡内部,因此只推移本列后续卡片。展开/收起不改变分配结果。
- `PolicyGroupInteractionStore` 按 controller/group ID 持有独立过滤、成员窗口和滚动状态。关闭组清过滤词但保留已加载 window;页面搜索隐藏保留状态;完整数据变化时与有效 ID 取交集并清理孤儿项;controller/session reset 全清。
- `PolicyGroupPresentation.selectedPolicyGroupID` 保持单值,代表 active/focused group。点击标题、过滤、节点或组动作会更新 active ID,但不会收起其他展开卡。
- GLOBAL 不脱离双列。`arrangedGroups` 已把它放在逻辑末尾后,按同一 index 规则进入普通列;不增加 full-width footer。验收只比较扁平化顺序与可访问顺序,不比较屏幕 y 坐标。
- **红线不变**:`ForEach(filteredGroups)` 保序、GLOBAL 末尾 partition、`selectedGroup(in: appModel.dashboard.groups)`、inline 四方法、展开内过滤先于分页(Round 7 全部)。多列只是排布,不碰顺序/选中/过滤语义。

### 展开成员滚动(D23,已定)

- expanded card 的 metadata/actions/filter 位于内层滚动区外;只有 member rows + divider + load-more footer 进入 `ScrollView`。
- max height token 按 font scale 档位提供,基准约 432pt、上限约 560pt;使用 `min(contentHeight, token)` 的稳定约束,短列表不留空白,动态内容不得改变列宽。
- 每组滚动位置使用稳定 group ID 关联的 presentation state;收起/页面搜索隐藏后再显示时恢复,controller/session reset 清除。不得把 `ScrollViewReader` ID 与成员索引绑定导致过滤后跳错行。
- 内外滚动都使用系统行为,不添加 drag gesture/scroll interception。节点区保留可见滚动条、焦点环和 accessibility container label。

### 展开状态持久化(D24,已定)

- 在偏好存储中以 controller UUID 为 key 保存有序无关的 group ID 集合;序列化前排序仅为稳定文件输出,不得用于 UI 排列。
- 恢复时先加载 dashboard 完整组集合,再取交集;不存在的 group ID 立即从存储清除。删除 controller 时同步删除对应 entry。
- 运行时另有 controller-scoped presentation cache,保存过滤、member window 和 scroll anchor;切换目的地/控制器时保留,但 AppModel 新实例或进程重启不恢复这些瞬态值。
- 持久化变化只由用户展开/收起触发;页面搜索隐藏、刷新暂缺组或网络 stale 不应立即删除 ID,只有完整成功快照确认组不存在时才 prune。

### 暂停时命令状态(D25,已定)

- `canRefresh = session exists && !presentationPaused && !blockingOperation`;toolbar、CommandMenu 和 keyboard command 共用该 capability,不各写一套条件。
- test capability 不受 presentationPaused 影响。test 结果进入 diagnostics/operation state,不通过 business presentation gate。
- resume 流程顺序固定:apply pending atomically → clear paused flag → request coalesced full refresh。多个 resume/快捷键事件幂等。
- pause 存在于 session generation state,不在 AppPreferencesStore。任何 `replace/leave/enter` 都从 unpaused 开始;普通 destination navigation 不触碰它。

### Controller CommandMenu(D39,已定)

- Menu 与 toolbar 只消费共享 command descriptors/capabilities,避免标题、图标、enabled 条件分叉。descriptor 集:test,refresh,pauseResume,editCurrent,copyDiagnostics。
- File menu 独立保留 add controller;Controllers 管理页独立保留 destructive delete。旧 live/sessionSync descriptor 和本地化入口删除。
- `⌘R` 只绑定 refresh descriptor。焦点位于 TextField 时仍遵循系统命令路由,不添加会冲突的 pause/test 全局快捷键。

### 常驻状态栏(D40,已定)

- status bar 读取统一 `SessionPresentationState`,不直接拼 `liveStreamState`/`syncState`/operationState。固定外层高度由 font-scale token 决定。
- 三段布局使用 `ViewThatFits`:controller identity 永久保留;session/operation summary 永久保留;lastSuccess 在窄宽度省略。完整错误不在此展开。
- operation overlay 有明确优先级 working/error > success > base session;结束/过期后恢复 base。状态栏不持有业务数据或触发网络操作。
- structural material 只一层,无嵌套卡/阴影;Reduce Transparency 使用 window/control background + separator top border。

### Closed connection buffer(D41,已定)

- 抽有界 buffer 维护 ordered rows、ID index 与 estimated byte total,maxCount=1000/maxBytes=16MiB。新关闭记录先移除同 ID 旧项再作为最新项加入,之后从 oldest 淘汰。
- byte estimate 覆盖完整可见字符串字段(URL/host/process/rule/chains/metadata),不用于隐藏或截断 UI,只用于内存预算。
- visible/pending 共 session-owned buffer;filter/sort 是 presentation projection。clear 和 generation leave 原子清 rows/index/bytes。

### 行视觉

- 折叠行:`[组类型图标(语义色)] 组名 · 当前节点 · [延迟色点/迷你延迟条]`。
- 展开区:成员行内嵌延迟可视化(横向 delay bar 或分档色点)、选中节点 checkmark + 强调行背景、组作用域过滤框。
- 用 `MicaContentCard` 容器,hover/press 用系统反馈,不用玻璃。

## 6. verifier 同步清单(R6)

- **改/删**:任何 glow/frost/dashboard-dark 相关(目前零断言,主要是新增)。
- **新增**:内容层视图文件断言不含 `.environment(\.colorScheme, .dark)`;不含 `MicaGlowCard`/`MicaFrostCard`(退役);概览/策略内容层不含 `.glassEffect(`。
- **数据模型**:更新/移除 `toggleSessionAutoSync` 相关断言(若有);新增"selectRouter 进入实时会话"锚点(谨慎——避免锁死实现细节)。
- **保留不动**:侧栏 List/NavigationSplitView、概览 Charts/真实值/isEmpty/无 Timer、策略保序/GLOBAL/inline/过滤、表格 Table/sortOrder/inspector、secrets FileSecretStore、导出无凭据。
- 原则:verifier 跟随内容契约演进,**绝不放宽**实数据/顺序/凭据纪律。

## 7. Final Design Invariants

- Toolbar command set 固定为 `test / refresh / pause-resume`,Controller 菜单另含 edit/copy;实时会话默认常开,无 live/sync 模式开关。
- 策略布局固定为 D20–D24 的错落双列、多组原卡内展开,不再保留跨整行或自适应三列方案。
- `MicaDashboard`/frost/glow 逐调用点替换后删除,不保留 typealias 或兼容 wrapper。
- Controllers 使用 D47–D48 原生自适应 Table,不改为卡片列表。
- v4 工作台内容保持 SwiftUI;AppKit 仅作 application/window/workspace 系统桥接,不引入数据组件或 representable wrapper。
