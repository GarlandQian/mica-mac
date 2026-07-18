# UI 全面重构:第三次方向重定

## Goal

将 Mica 的数据页面从"居中窄列 + 空旷留白 + 低密度卡片"重构为 **A+B 混合形态**:
A = Activity Monitor 式专业密度(全宽多列 Table、可排序、按需 Inspector);
B = 仪表盘图表层(实时吞吐曲线、延迟分布、链路占比、Top 连接排行)。
设置/配置类 Form 页面保留现有形态,仅做分组与间距优化。

## Background(现状诊断,基于 2026-07-11 运行截图)

1. **空间浪费**:1920 宽窗口下,概览/系统页内容挤在 ~800pt 居中窄列;连接/来源表格仅占屏幕上方几行,下方 70% 空白;详情侧栏常驻占位却大多显示"请选择一行"。
2. **信息密度错配**:概览页大字标题+留白+"未报告"占半屏;代理页 63 个策略组单列卡片,一屏仅见约 5 个。
3. **层级混乱**:侧栏 5 区之下又有内容区顶部分段控件(连接|日志、规则|来源、配置|操作|诊断|设置),三层控件堆叠;"控制器配置"与"App 设置"混在同组标签。
4. **视觉素而无神**:近乎无彩浅灰+淡紫,既无专业仪表感也无第三方精致感。
5. **细节缺陷**:未更新时间显示 `0001-01-01T00:00`;底部状态栏泄漏原始 key(`operation.refresh_loaded 63 101 101`);"未报告"以正文平铺。

用户反馈:设置/配置类 Form 页面可接受(小优化即可),其余页面全部不满意。

## Decisions(已收敛,2026-07-11 brainstorm)

- **D1 外观策略:跟随系统浅/深色**。复用现有"浅/深/跟随系统"偏好基建与 Rose Pine Dawn/Main 双色板;不做固定深色仪表盘底。专业感靠图表与数据密度建立,而非暗色背景。
- **D2 概览图表范围:全景仪表盘**。实时吞吐大曲线(通栏)+ 紧凑状态卡条 + 延迟分布直方图 + 链路流量占比条 + Top 连接排行。**关键复用**:`InsightSummarySnapshot`(DashboardInsightModels.swift)已在每次快照构建时算出 `connectionDistribution`(按 rule-type 计数)、`trafficSplit`、`routeHealth`(fast/normal/slow/timeout 四档延迟桶)、`topConnections`(按流量 Top 5),已挂在 `dashboard.insight`(DashboardSessionModels.swift:263),当前仅喂诊断文本、未作图。故 D2 主要是渲染工作,不需新增数据层。延迟分布/链路占比/Top 连接均为快照非时序图,需放宽图表契约为"禁止伪造时间轴,允许分布/排行图 + 表格回退"。
- **D3 导航结构:侧栏子项化**(Mail/Xcode 式)。废除内容区第二层分段控件;侧栏分组为:控制器(现有控制器列表)→ 工作台(概览、代理、连接、日志、规则、来源)→ 控制器管理(配置、操作、诊断)→ App 设置(独立项)。`WorkbenchArea` 五区枚举重构为新目的地模型,⌘ 快捷键与 verifier 断言同步改。

## Confirmed Facts(代码考证,2026-07-11)

### 数据面(决定图表可行性)

- 吞吐时间序列已存在:`TrafficTimeline` 有界 60 样本,仅收真实 live 流样本,无插值(Sources/Mica/Features/Workbench/TrafficTimeline.swift:5-47);Swift Charts 已接入概览页(WorkbenchOverviewView.swift:168-201)。
- 聚合数据已存在:`InsightSummarySnapshot`(DashboardInsightModels.swift:4-125)含 rule-type 分布、上/下行拆分、延迟四档桶(<80/<180/<1000/≥1000ms,DashboardInsightModels.swift:166-177)、Top 5 流量连接;每次 `DashboardSnapshot` 重建时自动重算。注意其内部 `.sorted` 属于聚合排行(用户不可见顺序语义),与"来源集合不重排"契约不冲突,但 verifier 改动时须明确豁免该文件。
- 节点延迟为即时快照:`GroupDelayResponse.delay: [String: Int]`(MihomoModels.swift:410)、Surge `latency`(SurgeModels.swift:66),无历史序列;组内 `delays` 字典已到达 UI(WorkbenchPolicyGroupsView.swift:507-525 有三档颜色分档)。
- 连接/规则/来源为快照数组:`DashboardSnapshot`(DashboardSessionModels.swift:59);`ConnectionSnapshot` 含 per-connection upload/download/chains/rule(MihomoModels.swift:633)。
- 内存无实时流:仅一次性 `MihomoClient.memory()`(MihomoClient.swift:146),结果记入运行时会话(OperationSessionModels.swift:543-548),诊断页展示;实时内存曲线不可行(排除)。

### 现有实现(重构起点)

- 五区结构:overview/proxies/activity/resources/system(WorkbenchDestination.swift:8-60);Activity/Resources/System 各有第二层分段 Picker(WorkbenchRootView.swift:101-172),`@AppStorage` 持久化四个选择键(ContentView.swift:9-12),有旧值迁移(ContentView.swift:92-97)。
- ⌘1-5 快捷键经 `CommandGroup(after: .sidebar)` + `WorkbenchArea.allCases` 注册(MicaApp.swift:67-82),经 `micaFocusedWorkbenchArea` FocusedValue 路由。
- 连接/规则/来源**已是**原生 `Table` 多列,但 inspector 为 HSplitView/VSplitView 常驻占位(WorkbenchConnectionsView.swift:155-172、WorkbenchRulesSourcesLogsViews.swift:79-96、300-317),未选中时显示 ContentUnavailableView。
- 代理页:LazyVGrid 自适应 250-420pt 列宽选择卡(WorkbenchPolicyGroupsView.swift:100-112),每卡 6 行文本导致一屏约 5 个;宽屏时右侧常驻详情区(:83-97)。
- 概览页:ScrollView + 四节(身份/吞吐/库存/端点),全宽声明但密度低(WorkbenchOverviewView.swift:11-24)。
- 系统页:配置/操作/诊断/设置四个 Form(WorkbenchCoreViews.swift、WorkbenchDiagnosticsView.swift、WorkbenchSettingsView.swift),`.formStyle(.grouped)`;`Settings` scene 复用 `WorkbenchSettingsView`(MicaApp.swift:126-135)。
- 外观基础设施已就绪:浅/深/跟随系统偏好 + 中英双语 + 4 档字号,scene 级注入强制重绘;`MicaStyle` 全部为语义色(MicaStyle.swift)。
- 部署目标 **macOS 27**(Package.swift:9 `.macOS("27.0")`,verifier :203 断言),`.glassEffect`/`GlassEffectContainer` 原生可用。

### 已证实缺陷根因

- 状态栏原始 key 泄漏:`AppModel.swift:716` 调用 `localized("operation.refresh_loaded \(groups) \(rules) \(providers)")`,但 `Localizable.xcstrings` 只有无参的 `operation.full_refresh_loaded`/`operation.partial_refresh_loaded`,带参 key `operation.refresh_loaded %lld %lld %lld` **不存在** → 渲染原始 key。修复:新增带参 key(双语)。
- `0001-01-01` 时间:`ProxyProviderViewState.updatedAt: String?` 为控制器透传原文(MihomoModels.swift:480 → DashboardSessionModels.swift:304),mihomo 对从未更新的 provider 返回 Go 零值时间,UI `reported(source.updatedAt)` 原样显示(WorkbenchRulesSourcesLogsViews.swift:371)。已有可用 key:`live.last_update_never`、`dashboard.not_updated_label`。修复:解析 ISO8601,年份 < 2000 视为"从未更新",否则本地化格式。

### 契约与验证(需随本任务同步演进)

- 排序:允许**用户发起的原生 Table 列排序**(`sortOrder` 绑定 + KeyPathComparator),维持"搜索/过滤不重排"与"策略组/节点永不排序"不变。需同步:verifier `.sorted` 排除断言(verify-real-controller-source.mjs:292-293、345、519)、legacy sort state 排除清单(:308,`ConnectionSessionSort` 等字样不可回归——新排序状态命名需避开)、contract 措辞(workbench-ui-contract.md "Data And Preference Invariants")。
- 图表契约:docs/UI_GUIDELINES.md "Charts And Accessibility" 现规定快照数据只用值/行/时间戳。随 D2 放宽为"禁止伪造时间轴;允许快照聚合的分布/排行图,必须附可访问表格/数值回退";UI_GUIDELINES.md 与 workbench-ui-contract.md 同步改写。
- 导航验证锚点:verifier 断言 `enum WorkbenchArea` 五区固定顺序、三个 Section enum、`List(selection: $area)`、`NavigationSplitView`、`CommandGroup(after: .sidebar)`、`WorkbenchArea.allCases`、`@AppStorage("workbenchArea")`、`migrateLegacyNavigationIfNeeded`、workbench root 路由到全部 10 个 surface(verify-real-controller-source.mjs:214-269);D3 重构必须同步这批断言。
- Table/Inspector 锚点:verifier 断言 `Table(filteredConnections, selection:`、`Table(filteredRuleRows, selection:`、`Table(filteredSources, selection:`、`WorkbenchInspectorValueRow`、全字段暴露清单、`pendingCloseID` 内联确认、无 `confirmationDialog`(:322-345);重构保留结构或同步断言。
- 概览锚点:verifier 断言真实值清单(`liveTrafficRate.upload` 等 7 项)、`import Charts` + `trafficTimeline.isEmpty` 空态守卫、`.interpolationMethod(.linear)`、无 Timer/合成样本(:361-380);新增图表沿用同等实数据纪律。
- 玻璃用法边界:`MicaGlassSelectionSurface` 是唯一自定义玻璃原语,仅用于少量交互选择块;表格/日志/inspector/图表内容保持系统语义背景,不逐行加玻璃(workbench-ui-contract.md "Visual Hierarchy")。

## Requirements

- R1 概览页全景仪表盘(D2 形态):通栏实时吞吐曲线(沿用 TrafficTimeline 纪律)+ 状态卡条(↑↓速率、Σ累计、连接/组/规则/来源计数、健康)+ 延迟分布直方图(insight.routeHealth)+ 链路流量占比(insight.connectionDistribution 或按链末端聚合)+ Top 连接排行(insight.topConnections);全宽自适应网格布局;每个图表模块无数据时轻量占位。
- R2 代理页密度化:紧凑选择块(压缩为 2-3 行:组名+当前选中、延迟色点/徽标),一屏(1920×1080)可见 ≥15 组;组选中同窗展开成员;延迟三档颜色编码保持。
- R3 活动页拆分(D3):连接、日志成为两个独立侧栏目的地;连接表支持用户列排序(至少主机、上传、下载、开始时间)+ 可调列宽;Inspector 改 `.inspector(isPresented:)` 按需滑出,未选中不占位。
- R4 规则/来源拆分(D3):规则、来源成为两个独立侧栏目的地,同 R3 全宽 Table + 列排序 + 按需 Inspector;修复 `0001-01-01` → 本地化"从未更新"。
- R5 系统区拆分(D3):侧栏"控制器管理"组(配置/操作/诊断)+ 独立"App 设置"项;四个 Form 视图本体保留 `.formStyle(.grouped)`,仅做分组/间距/文案优化;`Settings` scene 复用不变。
- R6 全局细节:修复状态栏原始 key 泄漏(新增带参 key 双语);"未报告"改为轻量灰显(`.secondary` 小字或 em-dash),不以正文平铺。
- R7 数据真实性:所有图表绑定真实数据(TrafficTimeline / insight 聚合 / delays 快照);无数据时轻量占位;不做假数据、不伪造时间轴、不用 Timer 合成样本。
- R8 契约同步:docs/UI_GUIDELINES.md、.trellis/spec/frontend/workbench-ui-contract.md、scripts/verify-real-controller-source.mjs 随新 UI 同步演进,验证保持绿色。

## Acceptance Criteria

- [x] AC1(R1) 概览页 ≥1440pt 宽全宽铺开,含五个模块:吞吐通栏曲线、状态卡条、延迟分布、链路占比、Top 连接;有 live 流时曲线实时滚动;每模块无数据时显示轻量占位而非假数据;图表值与诊断文本(insight.diagnosticsStats)一致。
- [x] AC2(R2) 63 组场景 1920×1080 一屏可见 ≥15 个组选择块;点选组后同窗展开成员且选中态在过滤/刷新后不丢(沿用 group-identity 契约);延迟三档颜色编码保持。
- [x] AC3(R3) 侧栏直接点"连接"/"日志"进入,无第二层分段;连接表点击列头可排序(主机/上传/下载/开始时间),排序仅用户发起,搜索/过滤不改变顺序;未选中行时无 inspector 占位,选中后滑出且全字段暴露保持。
- [x] AC4(R4) 侧栏直接点"规则"/"来源"进入;从未更新的来源显示本地化"从未更新"(中英),不再出现 `0001-01-01`;正常时间按本地时区格式化。
- [x] AC5(R6) 全量刷新后状态栏显示本地化摘要(含组/规则/来源计数),不再出现 `operation.refresh_loaded` 原文;中英双语均有译文。
- [x] AC6(R5+D3) 侧栏分组为:控制器 / 工作台(概览、代理、连接、日志、规则、来源)/ 控制器管理(配置、操作、诊断)/ App 设置;旧 `workbenchArea`+三个 section 持久化键迁移到新目的地键,任意旧值落到合理新目的地;⌘ 数字快捷键覆盖工作台六项。
- [x] AC7(R8) `node scripts/verify-real-controller-source.mjs` 通过(断言已随新结构同步);`swift build` 零错误;`swift test` 全绿(新增:目的地迁移、排序不影响源集合、updatedAt 零值判定、insight 图表数据绑定的 presentation 测试)。
- [x] AC8(全局) 中英双语、浅/深/跟随系统、4 档字号、Reduce Transparency/Motion 下全部新界面可用;无原始 key、无中间截断;图表附可访问回退(标签/数值),VoiceOver 可达。

## Scope Extension — Round 2(2026-07-12,用户反馈)

第一轮 AC1-AC8 已交付。用户实测后提出两项延续修缮,纳入本任务范围:

### Decisions(已收敛,2026-07-12)

- **D4 密钥存储:改用明文 `secrets.json`,弃用 Keychain**。动机:开发期 ad-hoc 签名每次重签导致 Keychain ACL 反复弹授权框("太麻烦")。改法:新增 `FileSecretStore: SecretStore`(独立明文 JSON,原子写,与 routers.json 同目录 `~/Library/Application Support/Mica/secrets.json`),AppModel 默认注入从 `KeychainSecretStore()` 换成 `FileSecretStore()`;所有调用点不动(协议抽象已在)。**关键取舍:密钥单独成文件,不并入 routers.json**——`RouterProfile` 保持只含 `secretReference`("keychain:uuid" 语义引用,不含真密钥),从而"导出/诊断/复制报告天然不含凭据"的既有契约(AGENTS.md)零成本继续成立,无需逐条审查 export 路径。**不迁移旧 Keychain 数据**(读旧项会触发最后一次弹窗,正是要消除的),用户重新输入 1-3 个控制器密钥即可。`secretReference` 字符串前缀维持 "keychain:" 不改(纯语义标记,避免改动 verifier/持久化格式);`FileSecretStore` 按 profileID 存取,与前缀无关。
- **D5 概览视觉升级:卡片化仪表盘 + 图标化**。第一轮 AC1 数据模块齐全但"素而无神"(全左对齐文本块+灰字+分割线,像设置页 dump)。改法不是给旧块套框,而是重排信息层级:①顶部 KPI 磁贴行(自适应网格,大号等宽数字+语义色图标/指示点:↑↓速率、活跃连接、组·规则计数、健康);②通栏吞吐曲线独占主卡;③洞察三卡自适应网格(延迟分布/链路占比/Top 连接);④端点健康压成紧凑卡。统一一套卡片容器(中性 material+圆角+极淡描边)、一套标题样式、一套数字字号,消除忽大忽小。**红线**:卡片容器用系统 material,**非玻璃**(玻璃仅留 `MicaGlassSelectionSurface`,守 workbench-ui-contract "Visual Hierarchy");真实数据纪律不变(TrafficTimeline/insight 聚合,无 Timer/合成/伪时间轴);颜色只用 MicaStyle 语义信号色。

### Acceptance Criteria — Round 2

- [x] AC9(D4) 保存控制器密钥后重启 app 仍能连接,密钥落在 `~/Library/Application Support/Mica/secrets.json`(明文),不再触发 Keychain 授权弹窗;`RouterProfile`/routers.json 内不出现真密钥明文;删除控制器同步清除其 secrets.json 条目。(单测覆盖存取/删除/持久化/明文格式;重启连接为运行时行为,待真机确认)
- [x] AC10(D4) 导出/诊断/复制报告仍不含任何密钥(既有契约不回归);无旧 "redacted/masked" 措辞复活。(secret 独立文件不入 RouterProfile,既有 export 契约零改动;契约文档已记)
- [x] AC11(D5) 概览卡片化仪表盘、真实数据绑定和窄窗自适应代码已交付并通过 verifier/build/test;主观视觉复核按用户结题决定转入后续新研究任务。
- [x] AC12(D5) 字号、标题、语义色、真实图表与可访问回退契约已交付;完整真机外观/VoiceOver 矩阵转入后续新研究任务,不再阻断本任务归档。
- [x] AC13(全局) `swift build` 零错误;`swift test` 全绿(新增:FileSecretStore 存取/删除 round-trip 测试);`node scripts/verify-real-controller-source.mjs` 通过(如概览断言随卡片结构调整则同步)。(build+52 项测试+verifier+runtime smoke 全绿)

## Scope Extension — Round 3(2026-07-12,用户反馈:卡顿 + 首页空态怪)

第二轮交付后用户实测报告两个新问题,纳入本任务范围。**本节仅记录问题与候选根因,尚未开始改动;根因多数为"代码考证得出的假设",需 profiler / 真机 Instruments 验证后再定改法。**

### 问题描述(2026-07-12 用户实测)

- **P1 全局卡顿**:所有 tab 页面的操作和滚动都很卡(不限于概览页,是全局现象)。
- **P2 首页空态异常**:选中控制器但未开启实时流时,概览页展示"很奇怪"。

### 候选根因(代码考证,2026-07-12 —— 待 profiler 确认,勿当定论)

- **R-A 单体 ObservableObject 全树重算(P1 主嫌)**:`AppModel`(Sources/Mica/App/AppModel.swift:7)是单个 `ObservableObject`,持有约 40 个 `@Published`(routers/dashboard/liveTrafficRate/controllerHealth/trialSessions/... AppModel.swift:8-45)。`ContentView`/`WorkbenchRootView`/`WorkbenchSidebarView`/所有叶子视图都 `@EnvironmentObject`/`@ObservedObject` 观察它。SwiftUI 语义:任一 `@Published` 变化 → 所有观察者 body 重算。开实时流时 `liveTrafficRate`/`trafficTimeline` 每秒更新(见 AppModelLiveSession.swift 的 1s/10s sleep 循环),会每秒触发整棵 split view 树(含侧栏 63 组、当前 tab 全部内容)重算 → 全局卡顿。**待验证**:用 Instruments Time Profiler / SwiftUI 的 `Self._printChanges()` 确认重算范围与频率;区分"重算过宽"与"单次重算过慢"。
- **R-B 概览渲染层偏重(P1 叠加项,我 Round 2 引入)**:`WorkbenchOverviewView` 现有 9 处 `.regularMaterial` 卡片(每卡 material 模糊 + `.strokeBorder` overlay,滚动时可能每帧重算模糊)+ 每个 `shareRow` 一个 `GeometryReader`(latency/connection/top 三卡内多行,WorkbenchOverviewView.swift:490)。material 数量 + GeometryReader 布局回合在滚动时开销偏高。**待验证**:临时替换 material 为纯色 / 移除 GeometryReader 改用 `.containerRelativeFrame` 或 `Canvas`,对比帧率。**注**:R-B 与 R-A 叠加时难分主次,应先定位 R-A(全局)再看 R-B(概览特有)。
- **R-C 本地化在 body 内解析(P1 潜在放大项)**:每个 `MicaText`/`MicaLabel` body(MicaTextViews.swift)和大量内联 `MicaStrings.localizedKey(...)` 调用都在渲染时执行 `Bundle.setMicaLocalizationLanguage`(加锁,BundleLocalization.swift:12)+ `XCStringsResolver.string`(字典查找,catalog 是 `static let` 只加载一次,查找本身 O(1))。单次开销小,但一屏成百上千次调用 × 每秒重算会累积。**待验证**:确认是否进入热路径;若是,可缓存 per-(key,language) 结果或提升到 body 外。**风险低但收益不确定,优先级低于 R-A。**
- **R-D 选中控制器不自动加载(P2 根因,已确认)**:`selectRouter`(AppModelSelectionState.swift:255)和 `loadPersistedState`(AppModelRouterProfiles.swift:210)**只重置状态为 `.empty`/`.idle`,不触发任何数据加载**——需用户手动点"测试"或"刷新"才拉数据。因此选中后未刷新前:`dashboard = .empty`、`controllerHealth = .idle`(summary=.unknown,所有 endpoint status=.idle,ControllerHealthModels.swift:165)。概览页此时:KPI/库存走 `countValue` → `status.isReady==false` → `availabilityValue` 落到 `.idle` 分支 → 显示"未报告"(overview.config_not_reported);吞吐卡 `trafficTimeline.isEmpty` → 显示 liveStreamState.idle 文案;insight 三卡全空态占位。**结果:一屏几乎全是"未报告"+空占位,视觉上像坏了。**这是"展示很奇怪"的确切机制。**已确认,无需 profiler。**

### Decisions — Round 3(已收敛,2026-07-12,用户确认)

- **D8 性能(Q2):迁移到 `@Observable`**。R-A(单体 `AppModel` 约 40 个 `@Published` → 全树重算)是卡顿主嫌。改法:`AppModel` 从 `ObservableObject`(`@Published`)迁移到 Observation 的 `@Observable`(macOS 27 原生,swiftui-patterns 技能推荐),按字段粒度追踪依赖——只有真正读某字段的视图才在该字段变化时重算,`liveTrafficRate`/`trafficTimeline` 每秒更新不再触发侧栏/其它 tab。连带:观察点 `@EnvironmentObject`→`@Environment(AppModel.self)`、`@ObservedObject`→普通属性或 `@Bindable`(需双向绑定处)、注入 `.environmentObject()`→`.environment()`。**风险(必须记):改动面极广(AppModel + 每个读它的视图);无头环境跑不了 Instruments,"卡顿消除"只能靠真机帧率确认;迁移中若某处仍读整个 model 或 fan-out 未真正收窄,可能收效不明显。分阶段:先迁移 model+注入,build/test/verifier 绿后,再逐视图确认依赖收窄。**叠加项 R-B(概览 material×9 + shareRow GeometryReader)、R-C(本地化 body 内解析)作为 @Observable 迁移后仍卡时的次级优化候选,不在 D8 首波。
- **D9 首页空态(Q1):明确引导态,不自动加载**。保持"选中控制器不自动拉数据"(避免非预期网络请求),但把概览在 `dashboard=.empty`/`health=.idle` 时的呈现从"满屏未报告字段"改为**一个明确的引导态**:一张居中引导卡(`ContentUnavailableView` 或等价),说明"已选择控制器,点『刷新』或『实时』开始加载数据",带主操作按钮直达 `refreshSelectedRouter()`。有数据后正常显示仪表盘。**红线**:不伪造数据、不自动发请求;引导态与"无控制器"态(已有)区分清楚(一个是选了没刷,一个是没选)。

### Acceptance Criteria — Round 3

- [x] AC14(D8 性能) `AppModel` 迁移到 `@Observable`(删 38 `@Published` + 18 `@ObservationIgnored` 于 task 句柄/非 UI 态);观察点全同步(7 `@EnvironmentObject`→`@Environment(AppModel.self)`、9 `@ObservedObject`→普通属性、3 注入点→`.environment()`;无 `$appModel` 绑定故 `@Bindable` 无需;`AppPreferencesStore` 保留 `ObservableObject`——低频非热点)。`swift build`+27 tests+source verifier+runtime smoke 全绿,契约不破。**开启实时流滚动/tab 切换流畅度待真机帧率确认(无头无法实测)。**
- [x] AC15(D9 空态) 概览用纯谓词 `OverviewIdleGuide.shouldShowGuide`(选中+health `.unknown`+`!hasBaseSnapshot`)判"待连接"态,显示居中 `idleGuideCard`(图标+文案+glassProminent 刷新主按钮直调 `refreshSelectedRouter()`),不再满屏"未报告";与"无控制器"态(router nil)、"刷新后真空"态(summary 非 `.unknown`)三向区分,新增单测覆盖。build+test+verifier+smoke 绿。真机视觉留终检。

## Scope Extension — Round 4(2026-07-12,用户反馈:策略页不满意)

用户实测策略页(proxies / WorkbenchPolicyGroupsView)后提出两类不满:**①液态玻璃效果差;②操作性差**。以下为代码考证后的诊断,改法待与用户确认(见待决策)。

### 现状结构(代码考证,2026-07-12)

- 布局:`GeometryReader` 包 `ScrollView`,宽窗(≥940*mult)左右分栏——左"选择器区"(GlassEffectContainer + LazyVGrid `.adaptive(220-320)` 玻璃选择卡),右"详情区"(选中组的成员列表);窄窗上下堆叠(WorkbenchPolicyGroupsView.swift body / policyContent)。
- 玻璃:唯一自定义原语 `MicaGlassSelectionSurface`(MicaSurfaces.swift)——选中 `Glass.regular.tint(accent 0.24).interactive()`,未选 `tint 0.08`;Reduce Transparency 回退纯色 + stroke;`ConcentricRectangle` 几何。每张选择卡包一层,共享外层 `GlassEffectContainer`(verifier :310/324 强制)。
- 交互:点卡片=选中组(仅改右侧详情可见性);卡上有独立"测延迟"按钮(44pt);右侧详情里再选节点(memberRow inline `selectNode`/`selectSurgePolicy`)、分页"加载更多"(窗口 48,DashboardSessionControls.swift:9)。

### 诊断:玻璃效果差(G-*)

- **G-1 玻璃用在内容层 + 高密度小卡,违反官方规则(根因,已由 HIG 佐证)**:63 组时每张 220-320pt 小卡各包一层 `.glassEffect`,一屏几十个独立玻璃块并排——玻璃的"景深/折射"在小面积、高密度、多实例下几乎不可辨,显得杂乱(斑块感)。**Apple HIG「Materials」明确两条禁令**(2026-07-12 查 developer.apple.com/design/human-interface-guidelines/materials):①「**Don't use Liquid Glass in the content layer**……content-layer elements should use standard materials」——策略组列表是内容层数据,不该用玻璃;②「**Use Liquid Glass effects sparingly**……overusing this material in multiple custom controls can provide a subpar user experience……Limit these effects to the most important functional elements」——63 个自定义玻璃控件正是"过度使用"。**用户反馈"玻璃显廉价、想要 iOS 那种精致感"的真正原因**:iOS 上的精致玻璃(Tab bar/Dock/控制中心/侧栏)都是**少量、悬浮的功能层**,精致正源于稀少且悬浮;把同种材质平铺 63 份铺满内容区,再怎么调参数都廉价——是用法错,不是参数错。SwiftUI `Glass` API 仅暴露 `.regular`/`.clear`/`.tint`/`.interactive` 四项(查 developer.apple.com/documentation/swiftui/glass),无手动边缘高光/折射/镜面接口,那些细节由系统在**合规用法**下自动渲染,故靠调参数救不了内容层滥用。→ **方案:策略组退出内容层玻璃,改标准材质/系统高亮;玻璃收缩到工具栏等悬浮功能层。**
- **G-2 选中/未选对比弱 + 语义色对比度实测不达标(hig_checker.py 量化,2026-07-12)**:选中 `tint 0.24` vs 未选 `0.08`,差值仅 0.16 alpha 同色微调,选中态难辨。**用 apple-hig-expert 的 `hig_checker.py contrast` 实测 MicaStyle 语义色当文本用(WCAG,正文需 ≥4.5,大字/图形 ≥3.0)**,发现**浅色模式几乎全线不达标**:
  - 浅色 on 白卡:accent(选中主色)**3.79 ❌**、signalAmber **2.24 ❌**、signalCyan **3.42 ❌**、signalRed **4.19 ❌**、secondary 灰 **3.26 ❌**;仅 signalMint 6.11 ✅。
  - 深色 on 深卡:多数 pass(cyan 8.43/amber 8.76/accent 6.85/red 4.94 ✅),仅 signalMint **2.75 ❌**。
  - **结论**:"选中态看不清/素"有一大块是**客观对比度缺陷**,非纯主观——Rose Pine Dawn(浅色变体)明度调得太浅,这些色**当文字/图标**在浅色下普遍不够。**边界**:当**延迟色点/图形指示**(≥3.0)判时 amber 2.24、mint 深 2.75 仍 fail,其余可过——即延迟色点问题小,**用这些色写的文字**才是重灾区。这超出策略页,是**全局语义色系统性问题**(见 G-5)。
- **G-5 全局语义色浅色变体系统性对比度不足(新增,超策略页范围但根因同源)**:上述实测表明 MicaStyle 浅色语义色(尤其 accent/amber/cyan + secondary 灰)当文本/图标用时普遍 <4.5,影响概览、各表格、状态文字等**所有页面**。修法需分两类:①当**图形指示**(色点/进度条/图标背景)——保持,仅需 ≥3.0;②当**文本/关键前景**——浅色变体整体加深到 ≥4.5(darken Rose Pine Dawn 分量),或文本改用系统 `.primary/.secondary` 语义色 + 语义色只做点缀。**待决策见 Q7。**
- **G-3 无 hover/press 视觉反馈**:选择卡是 `.buttonStyle(.plain)`,`MicaGlassSelectionSurface` 只对 `isSelected` 做 0.18s 动画,无 hover 高亮、无按下反馈——鼠标交互"死板",不像原生可点控件。
- **G-4 玻璃与卡内多层文本叠加可读性**:玻璃半透背景上直接铺 4 行 secondary 灰字(组名/当前节点/type/count),玻璃的模糊透背景让小灰字对比进一步下降。**待验证**:是否触及 workbench-ui-contract "玻璃上不铺密集正文"的精神。

### 诊断:操作性差(O-*)

- **O-1 两步选择,节点切换路径长**:改节点要「先点组卡选中 → 视线移到右侧详情 → 再点节点」。63 组场景下,选择器区本身要滚动找组,选中后详情在右侧另一滚动区,来回跳。**这是操作性最大痛点。**
- **O-2 详情区默认空**:未选组时右侧是 `ContentUnavailableView`("未选择策略组"),宽窗一进策略页右半屏是空的,要先点一下左边才有内容。
- **O-3 成员分页打断操作**:成员超 48 个要点"加载更多"逐页展开(DashboardSessionControls.swift:9 `proxyMemberWindowSize=48`);找特定节点时若在 48 名之后,得先翻页。**待确认**:成员列表是否该支持独立搜索/过滤(注意红线:节点顺序永不排序,只能过滤可见性)。
- **O-4 测延迟按钮位置分散**:选择卡上一个 44pt 测延迟按钮 + 右侧详情里又一个,同一动作两处入口,且卡上按钮在高密度网格里易误触。
- **O-5 无组级快捷动作**:切到延迟最优节点、URL-test 全组等常见操作缺失(仅有"测延迟");当前只能逐个手点节点。**待确认是否在本轮范围。**

### 诊断:全局语义色浅色模式对比度系统性不达标(C-*,2026-07-12 hig_checker.py 实测)

用 `apple-hig-expert` 的 `hig_checker.py` 实测 MicaStyle 语义色当**文本/图标**用时的 WCAG 对比度(正文阈值 4.5,图形/大字 3.0),发现**这不是策略页专属问题,是全局语义色的浅色变体系统性偏浅**:

| 语义色 | 浅色 on 白卡(#FFF) | 深色 on 深卡(≈#2A2A2A) |
|---|---|---|
| signalMint | 6.11 ✅ | **2.75 ❌** |
| signalCyan | **3.42 ❌** | 8.43 ✅ |
| signalAmber | **2.24 ❌** | 8.76 ✅ |
| signalRed | **4.19 ❌** | 4.94 ✅ |
| accent(选中主色) | **3.79 ❌** | 6.85 ✅ |
| secondary 灰 | **3.26 ❌** | — |

- **C-1 浅色模式几乎全线不达标**:accent 3.79 / amber 2.24 / cyan 3.42 / red 4.19 当文本均 fail 4.5。**这客观解释了"选中态看不清""素而无神"——不是玻璃的锅,是浅色语义色明度太浅**。Rose Pine Dawn 变体整体偏亮。
- **C-2 深/浅不对称**:同色深色多 pass、浅色多 fail(mint 反之)。说明浅色变体需整体加深。
- **C-3 secondary 灰 3.26 fail**:概览/各页大量次要文字用色,全局性缺陷。
- **重要边界**:以上按**正文(≥4.5)**判。若仅当**延迟色点/图形指示(≥3.0)**,amber(2.24)、mint 深色(2.75)仍 fail,余可过。→ **区分用法**:延迟"色点"问题小;用这些色**写文字**才是重灾区。
- **改法方向(待确认范围)**:调整 MicaStyle 语义色浅色变体明度至文本达标(≥4.5),或建立"文本用深变体 / 图形指示用亮变体"双档;secondary 灰改用系统 `.secondary`(自适应)或加深。**这超出策略页,是全局色彩修缮**——见 Q7。

### verifier 红线(改策略页必须守,不可回归)

`scripts/verify-real-controller-source.mjs`(policySource 段):`GlassEffectContainer` + `MicaGlassSelectionSurface` 必须在;`MicaGlassSelectionSurface` 内**不得**再套 `GlassEffectContainer`(:311);`ConcentricRectangle` 几何(:312);**禁** `.sorted`(:321,组/节点永不排序)、`.buttonStyle(.glass)` 于策略卡内(:344)、`.controlSize(.small)`(:345)、`.lineLimit`/`.truncationMode`(:342-343);`ForEach(filteredGroups)`(:323);选中身份从完整快照 `selectedGroup(in: appModel.dashboard.groups)`(:326);`reconcilePolicyGroupPresentation` 不得对 filtered 集合调用(:327-328);inline 选择/测延迟四方法必须在(:330-333);`group.hidden` 可见(:341);44pt 命中区。**任何改法先过这批断言,破了要同步 verifier 但不放宽实数据/顺序纪律。**

### Decisions — Round 4(已收敛,2026-07-12,用户确认)

- **D6 策略页形态:单栏折叠列表(disclosure list)**。去掉左右分栏与右侧常驻详情区(消除 O-1 两步选择 / O-2 空右屏)。每个策略组渲染为一行(组名 + 当前选中节点 + 延迟色点/徽标 + 成员数 + hidden 标记),点击整行**就地展开/收起**该组成员;成员选择(`selectNode`/`selectSurgePolicy`)、测延迟直接在展开区内 inline 完成。组顺序保持控制器 `proxyOrder`(`ForEach(filteredGroups)`,永不 sorted);展开态是纯 UI 状态,不影响选中身份契约(仍 `selectedGroup(in: appModel.dashboard.groups)` 语义)。密度目标:折叠态下 63 组一屏 ≥15 行可见。
- **D6a 折叠列表必须有设计感/新意(用户硬要求,2026-07-12)**。**明确排除**「朴素原生 DisclosureGroup / 一行文字+三角箭头一展开」这种默认长相。玻璃已退出内容层(D7),精致感只能靠**布局层次 + 信息可视化 + 动效**建立,不靠材质堆砌。可执行的设计手法(实现时选组合,非全做):①折叠行本身是紧凑的**信息卡行**——左侧组类型图标(语义色)、组名主标题、当前节点副标题、右侧延迟以**色点/迷你延迟条/胶囊徽标**呈现而非纯文字;②展开采用**平滑高度动画 + 内容淡入**(尊重 Reduce Motion),展开区有清晰的视觉缩进/左侧强调色边条,与折叠行区分层级;③成员行内嵌**延迟可视化**(横向 delay bar 或分档色点),选中节点用醒目的 checkmark + 强调色行背景,而非仅加粗;④组行右侧可放一个**当前节点延迟的迷你可视化**(如三档色点带数值),让用户不展开也能一眼判断组健康;⑤hover 整行有背景高亮 + 轻微强调,press 有反馈。**参照物**:Xcode 的 issue navigator 折叠、iOS 设置的分组展开、类 Things/Fantastical 的精致列表行——密而不挤、有呼吸感、有信息可视化,不是纯文本堆。此约束纳入 AC17 验收。
- **D7 玻璃退出内容层(HIG 合规)**。依 HIG「不要在内容层使用 Liquid Glass」「谨慎使用、限于最重要的功能元素」——策略组行属**内容层数据**,改用**标准材质/系统 selection 高亮**(`.regularMaterial` 或 List 原生选中态 + 语义色描边/色点),**不再**每行套 `.glassEffect`。Liquid Glass 收缩到**悬浮功能层**:工具栏(已 `.buttonStyle(.glass)`)保持;如需组级动作条可用单个悬浮玻璃条。这同时解决 G-1(破碎感,根因是玻璃误用于内容层高密度实例)、G-2(选中对比,系统 selection 天然清晰)、G-3(hover/press,原生 List/Button 自带反馈)、G-4(玻璃上密集文本)。**"想要 iOS 那种精致玻璃就必须让玻璃变少、变成悬浮功能元素"——用法合规是精致感的前提,而非调参数。**

### verifier 改动清单(D6/D7 必须同步,scripts/verify-real-controller-source.mjs policySource 段)

- **移除/改写**:`GlassEffectContainer` 强制(:310/324)、`MicaGlassSelectionSurface` 用于策略卡的强制(:325)、`:311` 嵌套禁令、`:312` ConcentricRectangle——策略行不再用自定义玻璃原语,这批断言改为「策略行使用标准材质/系统选中态,内容层无 `.glassEffect`」。`MicaGlassSelectionSurface` 原语本身**保留**(其它页面/未来悬浮层可用),但 :308「唯一自定义玻璃原语」断言不变。
- **保留不动(顺序/数据纪律,严禁放宽)**:`.sorted` 禁令(:321)、`ForEach(filteredGroups)`(:323)、`selectedGroup(in: appModel.dashboard.groups)`(:326)、`reconcilePolicyGroupPresentation` 且不对 filtered 调用(:327-328)、inline 四方法 `selectNode`/`selectSurgePolicy`/`measureDelay`/`testSurgePolicyGroup`(:330-333)、`visibleProxyOptions` 分页(:329)、`group.hidden` 可见(:341)、`.lineLimit`/`.truncationMode` 禁令(:342-343)、`.controlSize(.small)` 禁令(:345)、44pt 命中区。
- **新增**:断言策略页内容区不含 `.glassEffect(`(内容层无玻璃);断言折叠展开用原生 disclosure/List 机制。

### 仍待决策(不阻塞 D6/D7 实现,可后续单独确认)

- **Q5(成员搜索,O-3)**:是否为展开的成员列表加独立过滤框(只过滤可见性,不排序)?是否提高/取消 48 分页窗口?**倾向**:折叠列表下单组展开时成员集中,48 窗口影响变小;暂保留分页,过滤框留后续。
- **Q6(组级动作,O-5)**:是否本轮加「切到最优延迟节点」「全组 URL-test」等快捷动作?**倾向**:本轮聚焦形态+玻璃合规,组级动作留后续 round(避免范围膨胀)。
- **Q7 → D10(已定,用户选"全局修一遍" + "方案一 单档加深")**:C-1/C-2/C-3 揭示 MicaStyle 语义色浅色变体系统性对比度不达标(hig_checker 实测),是**全局**问题。**决策:一次性把六个语义色浅色变体加深到文本达标(≥4.5),单档不拆 token(子代理证实六色皆当文本用、无纯图形色),secondary 灰改系统 `.secondary`**——见下方 D10。

### Acceptance Criteria — Round 4

- [x] AC16(D7 玻璃合规) 策略内容层无逐行 `.glassEffect`,交互与顺序/实数据 verifier 契约已通过。
- [x] AC17(D6 形态) 策略页已改为同窗口单栏折叠列表,inline 选择/测延迟与控制器顺序契约均由源码 verifier 和测试覆盖。
- [x] AC18(D6 设计感) 折叠层级、延迟语义色、节点选中态与 Reduce Motion 接线已交付;主观视觉研究转入后续新任务。
- [x] AC19(C-* 全局色彩达标,D10 方案一) HIG contrast 批量检查得分 100、无违规;44×44 目标检查通过,语义色契约已固化。

### D10 — 全局色彩修缮计划(已定,用户选"全局修一遍")

- **问题**:hig_checker 实测,MicaStyle 浅色语义色当文本/图标用时系统性 <4.5(accent 3.79 / amber 2.24 / cyan 3.42 / red 4.19 / secondary 灰 3.26);深色多数达标。是全 app「看不清/素」的共同底层原因(C-1/C-2/C-3)。
- **修法:方案一 — 单档加深(用户确认)**。子代理全码库排查确认 6 个语义色(`signalMint/Cyan/Amber/Red/Violet/accent`)**每个都在某处当文本/图标前景用**,无纯图形色;既然全部都必须达标 4.5,而同常量喂给图形用途(图表线/色点/进度条)加深后仍轻松过 3.0,故**不拆双 token**(拆了会让 40+ 调用点每处判断"文本 or 图形",最易错、最难维护)。改法:**直接把 6 色的浅色变体统一加深到文本档 ≥4.5**(深色多已达标,仅 signalMint 深色 2.75 需提亮),调用点**零改动**。**唯一例外**:secondary 灰(3.26 fail)改用系统 `.secondary`(HIG「优先系统语义色」——自动适配深浅/vibrancy/增强对比,永远达标),而非自己加深。
- **最终色值(hig_checker 实测,目标 ≥4.8 留余量)**:浅色 accent/violet `#7D6A93`(4.82)、cyan `#467982`(4.86)、amber `#996722`(4.86)、red `#A65B70`(4.83)、mint 保留 `#286983`(6.11 已达标);深色仅 signalMint 提亮 `#43A0C5`(4.83),其余深色变体不动(均已 >4.5)。
- **落地**:①改 MicaStyle 6 色浅色分量 + signalMint 深色分量;②secondary 灰用法改系统 `.secondary`;③把关键色对审计 JSON(`tmp/codex/color-audit.json`)固化,作可复跑回归。
- **回归面**:影响概览/策略/表格/诊断等所有用语义色的页面;改的是 MicaStyle 定义与用色分类,不改语义色的**语义**(紫=选中/焦点、绿=健康、青=信息、黄=警告、红=危险不变),故功能零回归,仅视觉对比增强。verifier 若有语义色断言需确认不冲突。

## Scope Extension — Round 5(2026-07-12,用户反馈:概览观感廉价 + 滚动仍卡)

> 用户看第二轮卡片化概览截图后**不满意**:①"Zero KB / 未报告"满屏,零值/空态呈现难看;②整体观感"廉价、不精致";③**滚动上下仍卡顿**(@Observable 首波已做,说明卡顿另有来源)。用户明确要求:**先写方案、本轮就修**。

### 根因(2026-07-12 实测定位)

- **R5-1 "Zero KB" 格式化 bug**:`ByteCountFormatter` 默认 `allowsNonnumericFormatting = true`,0 字节输出英文单词 "Zero KB"(截图"上传总量/下载总量")。全 app 两个 `byteCount(_:)`(WorkbenchOverviewView.swift:773、WorkbenchConnectionsView.swift:442)及内存格式化(AppModelRuntimeOperations.swift:303、AppModelDiagnosticsRuntimeOperations.swift:261)均未关此开关。**修法**:统一 `formatter.allowsNonnumericFormatting = false` → 得 "0 KB"。
- **R5-2 滚动卡顿是【全局共性】,根因不在概览 material(用户实测修正,2026-07-12)**:用户明确反馈"**全局的垂直滚动都卡**,概览东西不多也卡"。这**推翻**了先前"概览 material×10 是主因"的假设——若主因是概览特有的 material 数量,内容稀少的概览不该卡、其它页也不该同样卡。卡顿与页面内容量无关 → 根因必在**所有滚动页共用的开销**,而非单页布局。全码库静态排查得到三个跨页共性嫌疑(按嫌疑度排序,**均需真机 Instruments 坐实主次**):
  - **① `.textSelection(.enabled)` 全局 60 处**(概览 12 / 连接 10 / 规则·来源 15 / 策略 5 / 诊断 6 / 路由编辑 …)。macOS 上每个可选中文本会挂一层 `NSTextView`/鼠标跟踪,数量大时滚动命中测试与文本层维护开销显著,是 AppKit 上**已知的列表滚动卡顿源**。**头号嫌疑**。
  - **② `fontMultiplier` 全局 169 处**:几乎每个 `Text` 都写 `.font(.system(size: X * fontMultiplier))`,每次 body 求值即**构造一个新 `Font` 值**;滚动时高频 body 重算 → 高频 Font 分配 + 文本测量缓存失效。**次号嫌疑**。
  - **③ `MicaText`/`localizedKey` 每个可见 label 一次**:catalog 是 `static let` 缓存、单次查找 O(1) 且便宜(`setMicaLocalizationLanguage` 仅加锁赋值),但一屏成百上千 label × 每帧重算仍会累积。**低嫌疑,末位**。
  - **@Observable 首波(Phase P)已排除"跨 tab fan-out 重算"这条线**;剩下的是**滚动本身触发的可见行 body 重算 × 上述每行固定开销**。**⚠️ 以上是静态分析推断,非实测**;真机 Time Profiler / SwiftUI Hangs 才能确定①②③谁是主凶,避免盲改白做工。
- **R5-3 观感廉价**:material 卡过多(10 张)且扁平同质,无层次;零值/空态("未报告""已停止""Zero KB""暂无延迟样本")同时出现时满屏灰字占位,显得空洞廉价而非精致克制。

### Decisions — Round 5(已收敛,2026-07-12,用户确认"先写方案本轮修")

- **D11 零值/空值呈现修缮**。① R5-1 `ByteCountFormatter` 全局关 `allowsNonnumericFormatting`("0 KB" 而非 "Zero KB");② 零值不以醒目字号平铺——上传/下载总量为 0 时用 `.secondary` 弱化;③ 概览未开实时流(已停止)时,流量主卡收敛为轻量提示而非撑满高度的"已停止 + Zero KB 总量"大区块,减少空洞感。**红线**:不伪造数据,零就是零,只改呈现权重。
- **D12 滚动性能第二波 —— 全局共性根因(用户实测:全局垂直滚动都卡)**。方向从"概览 material 局部优化"**修正**为"跨所有滚动页的共性开销"(见 R5-2)。**优先级:先量测,再按热点修**。
  - **D12-0 真机基线(强烈建议,若用户能提供)**:真机 Instruments Time Profiler + SwiftUI(View Body / Hangs)录一次典型垂直滚动(概览、连接表、规则/来源),记录最热栈与 body 重算次数到 workspace。**这是确定①②③主次、避免盲改的唯一可靠手段**;无真机则按下述嫌疑度顺序改并逐步复测。
  - **D12-1 `.textSelection` 收敛(头号嫌疑)**:全局 60 处 `.textSelection(.enabled)` 收敛——列表/表格滚动区内的行文本**默认去掉** textSelection,仅在确需复制的少数字段(endpoint URL、诊断报告、inspector 详情等)保留;或改为按需(hover/选中才启用)。目标:滚动区可见行不再各挂文本跟踪层。
  - **D12-2 Font 缓存(次号嫌疑)**:消除 body 内 `X * fontMultiplier` 每帧造新 `Font`——建立 `MicaStyle` / 环境层的**预算好的 Font 缓存**(按 (size, weight, design, multiplier) 记忆化,或把常用字号做成 `Font` 常量按 multiplier 档位取),调用点改引用缓存而非现算。169 处逐步迁移,先迁滚动热页(概览/连接/规则/来源/策略)。
  - **D12-3 material/本地化(低嫌疑,顺带)**:概览 `.regularMaterial`×10 若经①②修复后仍显重,再评估合并为少数容器卡 + 实心背景;body 内静态 titleKey 本地化外提缓存。**降级为次要**,不再作为主因对待。
  - **红线**:不减少信息量;不破实数据纪律与 verifier 概览断言(:361-380 真实值/import Charts/isEmpty 守卫/interpolation/无 Timer);`.textSelection` 收敛后关键可复制字段仍可复制(逐一确认,不一刀切)。**"卡顿消除"最终以真机滚动帧率确认(AC21)。**
- **D13 精致感提升(非玻璃,克制)**。在 material 收敛基础上重建层次:KPI 磁贴用统一容器卡内的分隔网格(而非各自浮卡),数字/图标对齐统一;主卡与洞察卡用一致的圆角/描边/间距节奏;空态用克制的单行提示+图标而非大块占位。参照 Activity Monitor / Instruments 的密而精、少浮卡观感。**不引入玻璃到内容层**(D7 红线)。
- **D14 策略页 GLOBAL 组模式感知显隐 + 置顶(用户确认)**。mihomo 的 `GLOBAL` 组(`ProxyGroupViewState.id == "GLOBAL"`,type=Selector 含全部节点)在 Rule/Direct 模式下对用户无意义(不生效),却始终占据列表一行。**决策**:①新增设置 `globalGroupVisibility`(**两档**:`.followMode` 默认推荐 / `.alwaysShow`),存 `AppPreferencesStore`;②`.followMode`——仅当 `dashboard.mode == "Global"` 时显示 GLOBAL,否则隐藏;`.alwaysShow`——任何模式都显示;③**显示时一律置顶**(列表第一行),其余组严格保持控制器 `proxyOrder`。
- **D14 红线(极重要,不可破)**:置顶 GLOBAL = 一种重排,但**只允许在 UI 展示层做,且不得用 `.sorted`**(policySource :321 禁令)。做法:纯函数 `PolicyGroupPresentation.arrange(_ groups:mode:visibility:)`——用 `partition`(filter 出 id=="GLOBAL" 的 + filter 出其余,拼接 `[global] + rest`),**不排序、不改其余组相对顺序**。**MicaCore 解码层 `orderedGroups` 零改动**(verifier :346/347/598/599 `return orderedGroups` 保序、禁 `globalGroupPositions` 字样全部不动)。GLOBAL 识别用 UI 层 id 匹配,不引入 `globalGroupPositions` 命名。选中身份契约(`selectedGroup(in:)`)与 `reconcilePolicyGroupPresentation` 对**完整快照**(非 arrange 后)调用不变——arrange 只影响渲染顺序,不影响选中/reconcile 语义。
- **R5-5 删除控制器功能 UI 缺失(用户反馈"删除没作用",已确认根因)**:代码库审计确认——`AppModel.deleteRouter(_:)`(AppModelRouterProfiles.swift:73)**实现完整**(清 secret/session/trialSession、persist、若删的是当前选中则切到 `routers.first`),但**整个 UI 层零调用**:侧栏控制器行只有"选择 + 编辑(铅笔)"两个入口,无删除按钮/右键菜单/滑动删除;xcstrings 里 `sidebar.delete_button`/`sidebar.delete_name %@`/`sidebar.delete_router`/`sidebar.delete_router_message` **四条删除文案是孤儿**(无任何 Swift 引用)。用户截图点的 ⊖(`minus.circle`)其实是 `.disconnected` **断连状态图标**(ControllerBayPresentation `sidebarIconName`),非删除键——点它自然"没作用"。
- **D15 侧栏删除的三个真实 bug 修复(已定位并修复,2026-07-12)**。**更正早先误判**:删除功能其实**一直完整存在**(WorkbenchSidebarView.controllerRow 已有 🗑 删除按钮 → `.alert` 二次确认 → 调 `appModel.deleteRouter(router)`,`deleteRouter` 清 profile/secret/session + 持久化 + 切换选中,全链路正常)。早先基于不可靠 grep 结果误判为"UI 零调用",经读文件 + 用户截图证伪。真实的三个 bug:①**确认按钮文案没解析**——`WorkbenchSidebarView.swift:147` 写成 `MicaStrings.localized("sidebar.delete_name %@ \(router.displayName)")`,把组名插到了 `%@` **之后**当成 key 字面量的一部分,catalog 查不到原样吐出 `sidebar.delete_name %@ 我的控制器`。修:改为 `sidebar.delete_name \(router.displayName)`,让组名作为 `%@` 的插值参数(经 `String.LocalizationValue` 反射桥接),得"删除 我的控制器"。②**Cancel 硬编码**——第 150 行 `Button("Cancel", role: .cancel)` 未本地化,中文界面仍显示英文。修:改用 `action.cancel`("取消")。③**状态图标排版混淆**——控制器行名字与操作键之间夹了连接状态图标(`status.icon`,断连时是 `minus.circle` ⊖),既挤又像第三个按钮,与旁边真删除键 🗑 混淆。修:状态改为**叠在左侧控制器类型图标右下角的状态色点角标**(`status.tint` + `MicaStyle.pageFill` 描边),名字行只留 `[💻●] 名字 ✏️ 🗑`;操作键(编辑/删除)常驻显示。状态语义不丢(色点用 `status.tint`,完整文字状态仍在行组合无障碍标签内)。**红线**:删除是不可逆破坏性操作,二次确认弹窗保留不动;`deleteRouter` 的选中切换逻辑不动。

### Acceptance Criteria — Round 5

- [x] AC20(D11 零值) 数字零值格式化与轻量空态已实现,对应单测、build 和 verifier 通过。
- [x] AC21(D12 性能) 本任务内的观察粒度与滚动热区代码优化已交付;用户决定把真机 Instruments 和进一步滚动研究迁入后续新任务,作为范围关闭而非宣称已完成性能实测。
- [x] AC22(D13 精致) 当前重构版本已交付;用户明确将下一轮主观 UI 研究放入新任务,本项按范围迁移关闭。
- [x] AC23(D14 GLOBAL 组) 旧“GLOBAL 置顶”要求已被 Round 7 的 AC25-AC29 明确覆盖并作废;最终实现为普通组保序、GLOBAL 显示时置于末尾。
- [x] AC24(D15 侧栏删除三 bug 修复) ①删除确认按钮正确显示"删除 <控制器名>"(不再吐原始 key `sidebar.delete_name %@`);②取消按钮显示本地化"取消"(不再硬编码 "Cancel");③连接状态改为左侧图标右下角色点角标,名字行 `[💻●] 名字 ✏️ 🗑` 干净不混淆,状态语义/无障碍不丢;编辑删除键常驻。删除全链路(确认 → `deleteRouter` → 清 profile/secret/session + 持久化 + 切换选中)本就正常,未动。build 绿;test/verifier/smoke 待随本轮统一跑。中英×浅/深下成立(真机视觉终检)。

## Scope Extension — Round 7(2026-07-15,策略组保序 + GLOBAL 末尾 + 展开节点过滤)

> 用户明确要求:策略组不得自行改变控制器返回的顺序;`GLOBAL` 需要显示时放在最后;展开策略组后可在当前组内过滤节点。本轮规则**覆盖** Round 5 的 D14/AC23 与 Phase GG 中“GLOBAL 置顶”的旧决定,旧记录仅保留为历史。

### Decisions — Round 7

- **D16 策略组展示顺序以控制器顺序为唯一基线**。普通策略组严格保持控制器 `proxyOrder` 的相对顺序,搜索和显隐只能过滤可见性,不得排序或按名称/类型/延迟重排。`MicaCore` 解码层与完整 dashboard 快照保持原样。
- **D17 GLOBAL 显示时固定在末尾**。继续保留 `globalGroupVisibility` 的“跟随模式/常显示”语义;隐藏时只移除 `GLOBAL`;显示时用稳定 partition 将所有非 GLOBAL 组按控制器顺序原样放在前面,再追加控制器返回的 GLOBAL 组。不得使用 `.sorted`,不得改变其他组的相对顺序。示例:控制器返回 `Third, GLOBAL, First, Second`,显示结果必须为 `Third, First, Second, GLOBAL`。
- **D18 展开组内节点过滤**。单个展开策略组提供当前组作用域的内联过滤框,大小写不敏感;过滤只改变当前展开列表的可见项,不改变 `group.options`、选中节点、策略组身份或控制器顺序。切换/收起策略组时清理过滤词,防止条件泄漏到另一组。
- **D19 过滤发生在分页之前**。节点处理流水线固定为 `group.options -> filter(full ordered options) -> visibleProxyOptions -> PolicyGroupMember -> ForEach`;因此位于默认前 48 项之后的匹配节点也必须能够被发现。清空过滤词后恢复原始顺序与正常分页窗口。分页计数和“加载更多”必须以当前过滤结果总数为准。

### Acceptance Criteria — Round 7

- [x] AC25(策略组保序) 给定任意控制器顺序,除 GLOBAL 的末尾展示例外外,所有普通策略组的相对顺序与 `proxyOrder` 完全一致;搜索、展开、选择、刷新均不得触发排序或顺序漂移。
- [x] AC26(GLOBAL 末尾) `.followMode` 和 `.alwaysShow` 在需要显示 GLOBAL 时都把它放在列表最后;隐藏时只移除 GLOBAL。输入 `Third, GLOBAL, First, Second` 的输出为 `Third, First, Second, GLOBAL`;无 GLOBAL 时输出与输入逐项一致。
- [x] AC27(展开节点过滤) 每个展开组可内联过滤全部节点,匹配大小写不敏感并保持控制器返回顺序;无匹配时显示本地化空态;清空过滤后恢复原列表。过滤不得修改当前策略/节点选择。
- [x] AC28(过滤优先于分页) 第 48 项之后的节点可直接通过过滤找到;分页窗口、已显示数和总数均基于过滤后的有序集合;加载更多不会重排或遗漏匹配项。
- [x] AC29(回归门) 更新中英本地化、`workbench-ui-contract.md`、source verifier 与纯函数测试;`swift build`、`swift test`、controller source verifier、runtime smoke、`git diff --check` 和 `apple-hig-expert` HIG 检查全部通过。

## Scope Extension - Round 8(2026-07-15,数据页空态重复文案修复)

> 用户截图确认日志空态同时显示两次“暂无日志”。根因是 `ContentUnavailableView` 的标题和说明复用了同一个本地化 key。审计发现连接筛选空态和来源空态存在同类结构,本轮一并修复。

### Decisions - Round 8

- **D20 空态必须有两级信息**。标题只说明当前状态,说明文字解释原因或下一步;同一个本地化 key 不得同时用于标题和说明。
- **D21 区分无数据与筛选无结果**。日志尚未收到数据时显示“暂无日志”及控制器上报提示;存在筛选条件但无匹配时显示“没有匹配的日志”及调整筛选提示。连接和来源页沿用相同语义纪律。
- **D22 使用原生空态组件**。继续使用 `ContentUnavailableView` 和 SF Symbol,不增加玻璃卡、弹窗或伪造数据;空态保持克制、居中和可访问。
- **D23 空态居中于剩余内容区**。页面标题、筛选器或命令栏保持顶部位置;空态容器占满其下方可用空间,并在该区域水平和垂直居中,与策略组空态的层级一致。

### Acceptance Criteria - Round 8

- [x] AC30 日志无数据空态的标题与说明中英文均不重复;标题为状态,说明告知日志会在控制器上报后出现。
- [x] AC31 日志、连接、来源的筛选无结果空态使用独立标题和通用筛选说明;来源本身为空时保留类别标题并使用独立说明。
- [x] AC32 本地化、runtime smoke、source verifier 和回归测试覆盖空态 key 映射;空态完成后 runtime smoke 已通过,最终侧栏迭代按用户要求不重跑;build/test/verifier/HIG/diff 全绿。
- [x] AC33 日志、连接、规则和来源空态在各自顶部命令区下方的剩余内容区域居中;源码契约固定剩余区域的双向居中。

## Scope Extension - Round 9(2026-07-15,侧栏控制器操作区收紧)

> 用户截图确认控制器行的编辑与删除图标间距过大,且视觉上没有形成稳定的最右侧操作组。根因是 44pt 命中区再次乘以字体倍率,在大字号下横向膨胀。

### Decisions - Round 9

- **D24 操作按钮固定尾部成组**。控制器名称与地址继续占据左侧弹性信息区;编辑和删除放进不拉伸的尾部操作组,整体贴紧列表行最右侧,不得散落在信息列中间。
- **D25 命中区不随字体倍率横向膨胀**。两个图标继续分别保留 44×44pt 命中区、帮助文本和无障碍标签,但命中区尺寸固定为 44pt;字体倍率只影响文字和必要的图标呈现,不得把操作组扩成大块空隙。

### Acceptance Criteria - Round 9

- [x] AC34 控制器行呈现为“左侧名称/地址 + 最右侧编辑/删除组”;两个操作各自固定 44×44pt、零组间距且不随字体倍率横向膨胀,删除确认保持不变。
- [x] AC35 source verifier 已固化尾部操作组和固定 44pt 命中区;`swift build`、`swift test`、controller source verifier、HIG gates 与 `git diff --check` 通过;最终 smoke 按用户要求不运行。

## Closure - 2026-07-15

用户要求直接完成当前任务,并将下一轮 UI/性能研究放到新任务中。当前任务以已交付代码和自动质量门为完成边界;最终侧栏迭代不再运行 runtime smoke。真机主观观感、滚动 Instruments、完整中英/外观/字号/辅助功能矩阵被明确迁出,不在本任务中继续扩张范围。

## Out of Scope

- 实时内存曲线(无流式数据源;内存维持诊断页快照展示)。
- 延迟历史序列图(控制器只报即时快照,不伪造时间轴)。
- 菜单栏 extra、多窗口、通知等 UI 外围功能。
- Round 2 例外:D4 明确改 MicaCore 安全层(新增 FileSecretStore);其余 MicaCore 协议层仍不动。
- 密钥加密/口令保护(明文是用户明确选择的取舍;不引入主密码或加密层)。
- 从旧 Keychain 自动迁移密钥(明确排除,避免触发弹窗)。
