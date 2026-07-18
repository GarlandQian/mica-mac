# Design — UI 全面重构:第三次方向重定

> 技术设计。信息架构、数据流、契约演进、兼容迁移、回滚形态。承接 prd.md 的 D1/D2/D3 与 R1-R8。

## 1. 架构总览

三条相对独立的改造线,可分别验证、分别回滚:

| 线 | 交付物 | 主要文件 | 依赖 |
|---|---|---|---|
| **N(导航)** | D3 侧栏子项化 + 系统区拆分 | WorkbenchDestination.swift、WorkbenchSidebarView.swift、WorkbenchRootView.swift、ContentView.swift、MicaApp.swift | 无(其余线的地基) |
| **D(数据页密度)** | R1 概览仪表盘、R2 代理密度、R3/R4 表格排序+按需 Inspector | WorkbenchOverviewView.swift、WorkbenchPolicyGroupsView.swift、WorkbenchConnectionsView.swift、WorkbenchRulesSourcesLogsViews.swift、新增 InsightCharts | N(目的地就位后接管) |
| **F(修缮+契约)** | R5 系统 Form 优化、R6 缺陷修复、R8 契约/verifier 同步 | AppModel.swift、Localizable.xcstrings、ActivityResourcesPresentation.swift、docs + spec + verifier | 贯穿 |

实施顺序:**N → D → F**。N 先把目的地模型立起来,D 在稳定路由上重构各页,F 收尾修缮并把契约/verifier 对齐到最终结构(放到最后避免中途反复改断言)。

## 2. N 线:导航信息架构

### 2.1 目的地模型重构

现状 `WorkbenchArea`(5 值)+ 三个二级 Section enum。目标是把二级 section 拉平为一级目的地。

新模型 `WorkbenchDestination`(替换 `WorkbenchArea`):

```
enum WorkbenchDestination: String, CaseIterable, Identifiable {
    // 工作台组
    case overview, proxies, connections, logs, rules, sources
    // 控制器管理组
    case configuration, actions, diagnostics
    // 独立
    case settings
}
```

每个 case 携带 `titleKey` / `symbolName` / `group`(用于侧栏分区)/ `supportsSearch`(connections/logs/rules/sources/proxies = true;overview/configuration/actions/diagnostics/settings = false)。

保留命名为 `WorkbenchArea` 还是改名 `WorkbenchDestination`?**改名**,因为语义从"5 大区"变为"10 目的地",且 verifier 断言 `enum WorkbenchArea` + 五区固定顺序(:237-241)本就要重写,改名让新旧断言不混淆。`ActivitySection`/`ResourcesSection`/`SystemSection` 三个 enum **删除**。

### 2.2 侧栏分区渲染

`WorkbenchSidebarView` 的 `List(selection:)` 在控制器 Section 之后,按 `group` 渲染三个 `Section`(工作台 / 控制器管理 / App 设置)。`List(selection: $destination)` 保留(verifier :233 断言 `List(selection: $area)` → 改为 `$destination`)。

侧栏宽度:现 240/290/380(ContentView.swift:56-59,verifier :217 断言 `240 * appFontScale.multiplier`)。目的地变多需要更高侧栏,但 240 min 够用,保留断言值不变。

### 2.3 快捷键与菜单

`CommandGroup(after: .sidebar)`(MicaApp.swift:67)现遍历 `WorkbenchArea.allCases` 给 ⌘1-5。改为遍历工作台组六项给 ⌘1-6(overview…sources);控制器管理与设置不绑数字键(或绑 ⌘, 给 Settings,macOS 惯例)。`WorkbenchDestination.workbenchTabCases` 静态子集供菜单遍历。verifier :266 `WorkbenchArea.allCases` → 同步。

`shortcut` 属性从"5 值全绑"改为"仅工作台六项返回 KeyEquivalent,其余 nil",菜单构建时 `if let`。

### 2.4 持久化与迁移

现 `@AppStorage` 四键:`workbenchArea` + 三个 section(ContentView.swift:9-12)。新方案单键 `workbenchDestination`(避免与旧 `workbenchArea` 撞键,便于迁移检测)。

迁移 `migrateLegacyNavigationIfNeeded`(ContentView.swift:92-97,verifier :220 断言存在):
- 若新键 `workbenchDestination` 已存在 → 跳过。
- 否则读旧 `workbenchArea` + 对应 section 映射到新目的地:`activity`+section=connections/logs、`resources`+section=rules/sources、`system`+section=configuration/actions/diagnostics/settings、`overview`→overview、`proxies`→proxies。再读更旧的 `workbenchDestination`(legacy string)兜底 `WorkbenchArea.migrated`。
- 旧三个 section 键读取后可留存(无害)或清理。

`WorkbenchDestination.migrated(fromArea:section:)` 静态函数承载映射,配套单测。

### 2.5 内容路由

`WorkbenchRootView` 现有 `activityContent`/`resourcesContent`/`systemContent` 三个含二级 Picker 的包装(:101-172)**全部删除**,`content` 的 switch 直接 10 路由到叶子视图。`.searchable` 挂载条件从 `area.supportsSearch` 变 `destination.supportsSearch`。搜索 promptKey 按目的地直接映射(消除现有 activity/resources 的 section 判断,:204-211)。

verifier :245-258 的 10 个 surface 路由断言(`WorkbenchOverviewView(` 等)全部保留——叶子视图不改名,只是路由层级从"区+section"变"目的地直达"。

## 3. D 线:数据页

### 3.1 R1 概览仪表盘

新增 `WorkbenchInsightCharts.swift`(或在 Overview 内建 `@ViewBuilder`),渲染五模块。数据全部来自现有 `appModel.dashboard.insight`(InsightSummarySnapshot)+ `appModel.trafficTimeline` + `appModel.controllerHealth`,**零数据层改动**。

布局:`ScrollView` + 自适应网格。用 `Grid` 或 `LazyVGrid(.adaptive(minimum: ~420))`,窄窗回落单列(沿用现有 `ViewThatFits` 模式)。

模块与数据源:

| 模块 | 视图 | 数据源 | 空态 |
|---|---|---|---|
| 实时吞吐(通栏) | 现有 `trafficChart`(保留) | trafficTimeline.samples | timeline.isEmpty → 现有 availability 文案 |
| 状态卡条 | 紧凑 metric grid(改造现有 inventory/traffic metric) | liveTrafficRate、dashboard.traffic、各 count、health | 复用现有 not_reported |
| 延迟分布直方图 | `Chart { BarMark }`,四档 | insight.routeHealth(LatencyHealthBucket) | hasLatencySamples=false → 占位 |
| 链路流量占比 | 水平占比条(BarMark stacked 或自绘 Capsule) | insight.connectionDistribution(rule-type 计数)| hasConnectionDistribution=false → 占位 |
| Top 连接排行 | 横条列表(名称 + 流量条 + 字节) | insight.topConnections(已 Top 5)| 空数组 → 占位 |

图表可访问性(契约要求):每图附 `.accessibilityLabel` + 数值型 `.accessibilityValue`;直方图/占比条提供隐藏的表格回退或 `accessibilityElement` 组合读值。延迟分布用 Rose Pine 三档+超时色(mint/amber/red/secondary),与代理页色档一致。

**图表非时序纪律**:延迟分布/链路占比/Top 连接的 X 轴是类别(档位/rule-type/连接名),非时间。X 轴不得出现伪造时间戳。仅吞吐曲线用时间轴且必须 `trafficTimeline.isEmpty` 守卫(verifier :373 保留)。

### 3.2 R2 代理密度

`policyGroupSelector`(WorkbenchPolicyGroupsView.swift:114-190)现每卡 6 行(组名/类型/选中/计数+隐藏/操作标签)。压缩为:
- 主行:组名(semibold)+ 右侧延迟色点或"当前节点延迟"徽标。
- 次行:当前选中节点(单行,可截断到 nil 保护)+ 成员数(小字 monospaced)。
- 测延迟按钮保留(44pt 命中区),但视觉压缩。

`LazyVGrid` 列宽下调:`.adaptive(minimum: 220, maximum: 320)`(现 250-420),配合精简卡内容,1920 宽下每行可容 5-6 列 × 3 行 ≥ 15。`GlassEffectContainer` + `MicaGlassSelectionSurface` 保持(verifier :281-296 断言)。选中详情区不变。

契约红线保持:无 `.sorted`(:292)、无 `.lineLimit`/`.truncationMode`(:313-314)在策略文本上、无 `.buttonStyle(.glass)`(:315)、无 `.controlSize(.small)`(:316)、`ForEach(filteredGroups)`(:294)、`group.hidden` 可见(:312)。→ 压缩布局不得触碰这些。

### 3.3 R3/R4 表格排序 + 按需 Inspector

**列排序**:SwiftUI `Table` 原生 `sortOrder` 绑定。

```
@State private var connectionSort = [KeyPathComparator(\ConnectionRow.totalBytes, order: .reverse)]
Table(sortedRows, selection: $sel, sortOrder: $connectionSort)
```

关键约束:排序作用于**行投影副本**,`appModel.dashboard.connections`(源集合)永不排序——满足"源集合顺序不变,仅用户发起排序改变显示"。因 `ConnectionSnapshot` 字段多为 optional String,引入轻量 `ConnectionRow`(id + 可比较派生字段:host、upload、download、startDate)或直接对 `[ConnectionSnapshot]` 用 KeyPathComparator。排序状态是视图 `@State`,不进 `DashboardSessionControls`(避免撞 verifier :308 的 legacy sort state 禁令——**新命名必须避开 `ConnectionSessionSort`/`RuleSessionSort`/`ProviderSessionSort`/`sortedRules`/`sortedProviders` 字样**)。

verifier :345/519 现断言数据源文件无 `.sorted`。Table 的 `sortOrder` 用 `.sorted(using:)` 应用比较器 → 会踩断言。**解法**:排序应用抽到 presentation 层辅助(如 `ConnectionWorkbenchPresentation.sorted(_:using:)`),让视图文件不直接出现 `.sorted`;或把 verifier 断言从"文件无 `.sorted`"改为"不出现 legacy 全量排序状态名 + 源集合不被排序"。**选后者**:更诚实,但要精确措辞——断言 `appModel.dashboard.connections` 不作为 Table 数据直接排序,改断言存在 `sortOrder:` 绑定 + 排序作用于本地投影。design 决定:presentation 层新增 `sorted(using:)`,视图传 `sortOrder`,verifier 改断言"存在 sortOrder 绑定 + 源 read 不带 sort"。

**按需 Inspector**:现 HSplitView/VSplitView 常驻(:155-172 等)。改用 `.inspector(isPresented:)`(macOS 27 原生):

```
tableView
  .inspector(isPresented: Binding(get: { sel != nil }, set: { if !$0 { sel = nil } })) {
      inspectorContent
  }
```

未选中 → inspector 收起,表格占满宽。verifier :335 断言 `Table(filteredConnections, selection:` + `WorkbenchInspectorValueRow` 保留;新增可断言 `.inspector(` 存在、`HSplitView`/`VSplitView` 移除。全字段暴露清单(:322-345)、`pendingCloseID` 内联确认、无 `confirmationDialog`(:341)保持。

### 3.4 D 线数据流不变量

- 概览:只读 `dashboard.insight`/`trafficTimeline`/`controllerHealth`,不新增 @Published,不改 AppModel 计算。
- 排序:纯视图态,源集合只读。
- Inspector:选中 ID 仍是视图 `@State`(现状即如此),`.inspector` 只改呈现容器。

## 4. F 线:修缮与契约

### 4.1 R6 状态栏 key 泄漏

`Localizable.xcstrings` 新增带参 key `operation.refresh_loaded`(参数 `%lld %lld %lld` = groups/rules/providers),中英双语。英文示例 `"Loaded %lld groups, %lld rules, %lld sources."`,中文 `"已加载 %lld 个组、%lld 条规则、%lld 个来源。"`。AppModel.swift:716 调用点不变(key 补齐即可解析)。补 presentation 测试或 runtime smoke 验证解析非原文。

### 4.2 R4 updatedAt 零值

新增纯函数(建议置于 `ActivitySourceFormatting` 或 SourcesWorkbenchPresentation):输入 `updatedAt: String?`,解析 ISO8601;年份 < 2000(Go 零值 `0001-01-01`)→ 返回 `live.last_update_never` 本地化;有效 → 本地时区 `.formatted`;nil/空 → not_reported。WorkbenchRulesSourcesLogsViews.swift:371 与 inspector :405 改用该函数。配套单测覆盖零值/有效/空三分支。

### 4.3 R5 系统 Form

四个 Form 视图本体保留 `.formStyle(.grouped)`;仅调 Section header 文案、间距、把"控制器配置/操作/诊断"与"App 设置"在**导航层**分离(N 线已做)。视图内部改动最小。

### 4.4 R8 契约 + verifier 同步(最后一步)

按第 5 节清单逐条改。原则:每放宽一条旧断言,补一条等强度新断言,不净删保护。

## 5. 契约演进清单(精确到断言)

verify-real-controller-source.mjs 改动:

| 行 | 现断言 | 改法 |
|---|---|---|
| 237-241 | `enum WorkbenchArea` + 五区固定序 | → `enum WorkbenchDestination` + 十目的地固定序 + 分组 |
| 242-244 | 三个 Section enum 存在 | → 删除(section 已拉平);可断言三 enum **不再存在** |
| 233 | `List(selection: $area)` | → `List(selection: $destination)` |
| 245-258 | 10 surface 路由 | 保留(叶子不改名) |
| 265-266 | `CommandGroup(after: .sidebar)` + `WorkbenchArea.allCases` | → 保留 CommandGroup;`allCases` → `workbenchTabCases` |
| 219-220 | `@AppStorage("workbenchArea")` + migrate | → `@AppStorage("workbenchDestination")` + migrate 保留 |
| 292/345/519 | 数据/策略源无 `.sorted` | 策略源(:292-293)保留严格;数据源(:345)改为"源集合不排序 + 存在 sortOrder 绑定 + 排序在 presentation 层" |
| 308 | legacy sort state 禁字清单 | 保留(新排序状态命名避开这些字) |
| 361-380 | 概览真实值 + 吞吐图纪律 | 保留;新增延迟分布/占比/Top 连接的 insight 数据绑定断言 + 非时序 X 轴无时间戳 |
| — | (新) inspector | 新增 `.inspector(` 存在 + `HSplitView`/`VSplitView` 移除断言 |

docs/UI_GUIDELINES.md:"Charts And Accessibility" 段放宽为允许快照聚合分布/排行图 + 表格回退;"Text And Density" 补代理密度目标。
.trellis/spec/frontend/workbench-ui-contract.md:"Navigation And Window" 改为十目的地侧栏子项模型;"Data And Preference Invariants" 增列排序条款(用户发起、源不变);"Charts" 同步。

## 6. 兼容与迁移

- **偏好迁移**:见 2.4。旧用户升级后落到对应新目的地,不重置到 overview(除非无旧值)。单测覆盖每条映射。
- **本地化**:所有新文案(图表标题、分组标题、排序无障碍标签、refresh_loaded、never-updated)必须中英双语进 xcstrings;XCStringsResolver 运行时 JSON 解析路径(见 memory)对新 key 自动生效,无需额外接线。
- **无 core/协议改动**:insight 聚合已在 Mica 层;不动 MicaCore、不动 AppModel 数据获取。

## 7. 回滚形态

三线独立提交,任一线可单独 revert:
- N 线回滚:恢复 `WorkbenchArea` + 三 section + 二级 Picker;偏好键 `workbenchDestination` 保留无害。
- D 线回滚:概览/代理/表格视图各自独立,可逐视图 revert 到当前实现。
- F 线回滚:xcstrings 加 key、纯函数、契约文档均为叠加式,revert 不影响 N/D。

风险点:N 线改目的地模型牵动 verifier 最广,先本地跑 `node scripts/verify-real-controller-source.mjs` 确认断言与代码同步再提交。排序断言改法(:345)是唯一"放宽"动作,需 reviewer 确认新断言等强度。

## 8. 验证策略

- `node scripts/verify-real-controller-source.mjs`(断言随结构同步)。
- `swift build`(macOS 27 SDK 零错误)。
- `swift test`:现有 swift-testing 套件(WorkbenchPresentationTests 11 项 + MicaCore 18 项)全绿;新增测试见 implement.md。
- 运行时/视觉:中英 × 浅/深/跟随 × 4 字号 × Reduce Transparency/Motion × VoiceOver/键盘;63 组密度实测;网络无关 smoke 不加载 profile、不起 core。

## 9. Round 7:策略组稳定顺序与展开节点过滤

### 9.1 策略组展示流水线

展示顺序只允许一个显式例外:`GLOBAL` 在需要显示时追加到末尾。流水线固定为:

```
controller proxyOrder
  -> filteredGroups(query)              // 只过滤,保持顺序
  -> visibility partition               // otherGroups + globalGroups
  -> ForEach(arrangedGroups)
```

`PolicyGroupPresentation.arrangedGroups` 不使用 `.sorted`;普通组保持输入相对顺序。`globalGroupVisibility` 仍决定是否显示 GLOBAL,但 Round 7 覆盖旧的“置顶”设计:显示时始终位于列表最后。该变换只存在于 UI presentation 层,不回写 dashboard,不修改 MicaCore `orderedGroups`,不参与选中身份或 reconcile。

### 9.2 展开组内节点过滤流水线

每次只有一个策略组展开,因此视图维护一个当前展开组作用域的 `memberFilterText`;切换或收起组时重置。过滤字段置于展开内容顶部,使用原生 macOS `TextField` 和 SF Symbol,不引入弹窗、popover 或内容层 Liquid Glass。

节点流水线固定为:

```
group.options
  -> PolicyGroupPresentation.filteredOptions(query)  // 对完整集合 filter,保序
  -> DashboardSessionControls.visibleProxyOptions    // 过滤后再分页
  -> PolicyGroupMember
  -> ForEach
```

空查询直接返回原集合;匹配采用 trim 后的大小写不敏感包含判断;重复值与相对顺序均保留。原组无节点时沿用 `routing.members_empty`;有节点但过滤结果为空时显示独立的本地化过滤空态。分页的 `hasMore`、当前显示数和总数以过滤结果为准,确保默认 48 项之后的匹配节点可被直接发现。

### 9.3 状态与交互不变量

- 过滤只改变可见项,不触发 `selectPolicyGroup`、`selectNode`、`selectSurgePolicy` 或 reconcile。
- 当前选择不匹配过滤词时可以暂时不可见,但选择身份保持不变;清空过滤后原选中行恢复。
- 展开/收起动画继续尊重 Reduce Motion;成员行维持至少 44pt 命中区。
- 策略列表和成员数据仍属于内容层,不添加 `.glassEffect`;Liquid Glass 只用于已有的功能层控件。

### 9.4 验证与契约更新

- 纯函数测试覆盖 GLOBAL 末尾、隐藏、无 GLOBAL、普通组保序、节点过滤大小写与重复项保序。
- source verifier 断言 `otherGroups + globalGroups`、过滤先于 `visibleProxyOptions`、策略源无 `.sorted`。
- `Localizable.xcstrings` 增加节点过滤标签/占位/无结果文案,并把 GLOBAL 设置帮助从“置顶”更新为“置于末尾”。
- `.trellis/spec/frontend/workbench-ui-contract.md` 同步为长期契约,避免后续重构恢复旧顺序。

## 10. Round 8:数据页空态文案层级

空态继续使用原生 `ContentUnavailableView`,但标题 key 与说明 key 必须分离。映射固定为:

| 场景 | 标题 | 说明 |
|---|---|---|
| 日志尚无数据 | `dashboard.no_logs_yet` | `dashboard.no_logs_yet_message` |
| 日志筛选无结果 | `dashboard.no_matching_logs` | `traffic.empty_filtered` |
| 连接筛选无结果 | `dashboard.no_matching_connections` | `traffic.empty_filtered` |
| 来源筛选无结果 | `dashboard.no_matching_sources` | `traffic.empty_filtered` |
| 当前来源类别为空 | 既有类别标题 key | `traffic.sources_empty_message` |

`traffic.empty_filtered` 调整为适用于搜索、级别和类别过滤的通用说明,不再作为任何空态标题。presentation 层提供可测试的日志空态 key 映射,视图只负责渲染。source verifier 禁止数据页把 `traffic.empty_filtered` 重新放回 `titleKey`。

规则、连接、来源和日志页面把数据内容分支统一包在 `frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)` 中。顶部命令区不参与居中;表格/List 在有数据时仍填满剩余区域,`ContentUnavailableView` 在空态时获得同一完整区域并居中。

## 11. Round 9:侧栏控制器操作区

控制器行维持单个横向布局:左侧选择按钮承载控制器类型、状态角标、名称和完整地址,并使用 `maxWidth: .infinity` 吸收剩余空间;右侧 `HStack(spacing: 0)` 只承载编辑和删除。外层行填满可用宽度,操作组使用 `fixedSize(horizontal: true, vertical: false)` 锁定在尾部。

编辑和删除各自使用固定 44×44pt 命中区,不再乘 `fontMultiplier`。这既保留无障碍目标尺寸,也避免 Large/Extra Large 字号把两个图标横向拉散。删除确认、帮助文本、可访问标签和业务行为均保持不变。
