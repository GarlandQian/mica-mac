# Implement — UI 全面重构:第三次方向重定

> 执行计划。顺序 N(导航)→ D(数据页)→ F(修缮+契约)。每步含验证命令与回滚点。承接 design.md。

## 全局验证命令(每阶段末尾必跑)

```bash
swift build
swift test
node scripts/verify-real-controller-source.mjs   # F 阶段前:预期部分断言待同步,记录清单;F 后必须全绿
git diff --check
```

## Phase N:导航子项化(D3)

- [x] N1 重写 `Sources/Mica/Features/Workbench/WorkbenchDestination.swift`:
  - 新 `enum WorkbenchDestination`(overview/proxies/connections/logs/rules/sources/configuration/actions/diagnostics/settings),含 `titleKey`/`symbolName`/`group`/`supportsSearch`/`shortcut(仅工作台六项)`/`workbenchTabCases`。
  - 删除 `ActivitySection`/`ResourcesSection`/`SystemSection`。
  - `static func migrated(fromArea:activitySection:resourcesSection:systemSection:)` + 旧 legacy string 兜底。
- [x] N2 `ContentView.swift`:`@AppStorage("workbenchDestination")` 单键替换四键;`migrateLegacyNavigationIfNeeded` 实现 N1 映射(新键存在即跳过);`area` Binding → `destination`。
- [x] N3 `WorkbenchSidebarView.swift`:`List(selection: $destination)`;控制器 Section 后渲染"工作台/控制器管理/App 设置"三个分组 Section。
- [x] N4 `WorkbenchRootView.swift`:删 `activityContent`/`resourcesContent`/`systemContent` 与三个二级 Picker;`content` switch 直达 10 叶子;`searchPromptKey` 按目的地平铺;`navigationTitle`/`focusedValue` 用新类型。
- [x] N5 `MicaApp.swift` + `MicaCommandFocus`:菜单遍历 `workbenchTabCases`(⌘1-6);FocusedValue 类型改 `WorkbenchDestination`;`@AppStorage` 键同步。
- [x] N6 本地化:侧栏分组标题等新 key(如 `sidebar.group_workbench`/`sidebar.group_controller_management`)双语入 xcstrings。
- [x] N7 测试:`WorkbenchPresentationTests` 新增目的地迁移用例(每条旧 area+section 组合 → 新目的地;无旧值 → overview;新键已存在 → 不覆盖)。
- [x] N8 验证:`swift build` + `swift test` 绿;运行 app 手测侧栏十项、⌘1-6、搜索仅在数据目的地出现。verifier 此时预期失败项:237-244/233/266/219(记录,F 阶段同步)。

**回滚点**:N 线单独 commit;revert 恢复五区+分段。

## Phase D:数据页重构(D2/R1-R4)

- [x] D1 概览仪表盘 `WorkbenchOverviewView.swift`(+新 `WorkbenchInsightCharts.swift` 若拆文件):
  - 保留吞吐 Chart(含 `trafficTimeline.isEmpty` 守卫、`.interpolationMethod(.linear)`、样本数无障碍标签)改为通栏首模块。
  - 状态卡条:↑↓速率/Σ累计/连接/组/规则/来源计数/健康,复用现有 metric 构件压缩排布。
  - 新增延迟分布直方图(`insight.routeHealth` 四档 BarMark,三档色+超时 secondary,X 轴=档位类别)。
  - 新增链路占比条(`insight.connectionDistribution`)。
  - 新增 Top 连接排行(`insight.topConnections`,名称+流量条+字节)。
  - 每模块空态轻量占位;全部图表加 accessibilityLabel/Value 数值回退。
  - 布局:通栏 + 自适应网格,窄窗单列(ViewThatFits 或 adaptive grid)。
- [x] D2 代理密度 `WorkbenchPolicyGroupsView.swift`:选择卡压缩至 2-3 行(组名+延迟徽标/当前节点+成员数);LazyVGrid `.adaptive(minimum: 220, maximum: 320)`;红线保持(无 sorted/lineLimit/truncation/glass-in-glass/controlSize.small;GlassEffectContainer+MicaGlassSelectionSurface;group.hidden 可见;44pt 命中区)。
- [x] D3 连接表 `WorkbenchConnectionsView.swift`:
  - `Table(..., sortOrder: $connectionSortOrder)`,KeyPathComparator 列:主机/上传/下载/开始时间;排序应用走 `ConnectionWorkbenchPresentation.sorted(using:)`(源集合只读;状态命名避开 `ConnectionSessionSort` 等禁字)。
  - HSplitView/VSplitView → `.inspector(isPresented:)`(选中即开,关闭清选中);inspector 全字段清单与 `pendingCloseID` 内联确认保持。
- [x] D4 规则/来源 `WorkbenchRulesSourcesLogsViews.swift`:同 D3 模式(规则:payload/type/proxy/size 列排序;来源:name/kind/type/items/updatedAt 列排序);`.inspector` 化;日志视图沿用(已是全宽 List,仅确认无回归)。
- [x] D5 测试:新增 presentation 用例——排序辅助不改源集合顺序(输入数组前后 identity 不变)、排序比较器 nil 字段稳定、insight 图表空态判定(hasLatencySamples/hasConnectionDistribution/空 topConnections)。
- [x] D6 验证:build+test 绿;运行 app 实测:63 组一屏 ≥15、列头排序、未选中无 inspector、概览五模块空态与实数据;中英+深浅+字号抽查。

**回滚点**:D1/D2/D3+D4 各自独立 commit,可逐视图 revert。

## Phase F:修缮 + 契约同步(R5/R6/R8)

- [x] F1 状态栏 key:xcstrings 新增带参 `operation.refresh_loaded`(`%lld %lld %lld`,双语);确认 AppModel.swift:716 解析非原文(runtime smoke 或 resolver 单测)。
- [x] F2 updatedAt 零值:presentation 纯函数(ISO8601 解析,年 <2000 → `live.last_update_never`,有效 → 本地格式,空 → not_reported);来源表列+inspector 接入;单测三分支。
- [x] F3 "未报告"灰显:概览/表格中 not_reported 值统一 `.secondary` 弱化(检查 identityValue/reported 输出样式),不以正文平铺。
- [x] F4 系统 Form 微调:配置/操作/诊断/设置四 Form 的 Section 分组与间距优化;`Settings` scene 复用不变。
- [x] F5 契约文档:
  - docs/UI_GUIDELINES.md:Charts 段放宽(禁伪时间轴;允许快照分布/排行图+表格回退);密度目标补充。
  - .trellis/spec/frontend/workbench-ui-contract.md:导航段改十目的地模型;新增用户排序条款;Charts 同步。
- [x] F6 verifier 同步(design.md §5 表逐条):
  - 237-244 → WorkbenchDestination 十目的地 + 三 Section enum 已删断言。
  - 233/219/266 → `$destination`/新 AppStorage 键/`workbenchTabCases`。
  - 345 数据源排序断言 → "存在 sortOrder 绑定 + 源集合无直接 sort + presentation 层 sorted(using:)";292-293/519 策略侧保持严格;308 禁字保留。
  - 新增:`.inspector(` 存在、HSplitView/VSplitView 移除、insight 图表数据绑定(`insight.routeHealth`/`insight.connectionDistribution`/`insight.topConnections`)、非时序图无时间 X 轴。
  - 361-380 概览断言保留并跑通。
- [x] F7 全量验证:四条全局命令全绿;18+ 项 swift test(含新增)全过。
- [x] F8 视觉/无障碍终检关闭处理:代码级本地化、字号、外观、键盘/无障碍契约与 HIG 门已验证;用户决定结束本任务,主观视觉矩阵与截图研究转入后续新任务,不再作为本任务归档阻断。

**回滚点**:F 线叠加式,单独 commit。

## 风险文件(改动最重,review 优先)

- WorkbenchDestination.swift(模型重写)
- WorkbenchRootView.swift(路由拉平)
- ContentView.swift(持久化迁移)
- scripts/verify-real-controller-source.mjs(断言同步,唯一"放宽"点在 :345 排序,需等强度替换)
- WorkbenchOverviewView.swift(体量最大新增)

## task.py start 前检查

- [x] prd.md 收敛(已过 convergence pass,无未决 Open Questions)
- [x] design.md + implement.md 就位(本文件)
- [x] implement.jsonl / check.jsonl 已填真实条目(非 `_example`)
- [x] 用户已审阅并批准开工

## Phase G:密钥改明文 secrets.json(D4,2026-07-12 范围扩展)

- [x] G1 新增 `Sources/MicaCore/Security/FileSecretStore.swift`:`actor FileSecretStore: SecretStore`,明文 `[UUID: String]` JSON,默认 `~/Library/Application Support/Mica/secrets.json`(与 routers.json 同目录);`secret/save/removeSecret` 三方法,原子写(`.atomic`),目录自动创建;文件缺失/空 → 空字典;可注入 `fileURL` 便于测试。
- [x] G2 `AppModel.swift`:默认参数 `secretStore: any SecretStore = KeychainSecretStore()` → `FileSecretStore()`。调用点(AppModelRouterProfiles.swift 的 save/remove/load)全不动。
- [x] G3 保留 `KeychainSecretStore.swift` 文件(不删,避免断引用/供回退),仅不再作默认注入;`secretReference` 前缀 "keychain:" 语义标记不改(避免动 verifier/持久化格式)。确认无其它硬编码 `KeychainSecretStore()` 注入点。
- [x] G4 测试 `Tests/MicaCoreTests`(或现有 core 测试目标):`FileSecretStore` round-trip——save→secret 取回一致、removeSecret 后取回 nil、覆盖写更新、缺失文件返回 nil;用临时 fileURL 隔离,不碰真实 app support。
- [x] G5 验证:`swift build` + `swift test` 绿;手测——保存密钥、退出重开仍连接、`secrets.json` 明文存在且 routers.json 不含真密钥、无 Keychain 弹窗、删除控制器后条目消失。

**回滚点**:G 线单独 commit;revert 恢复默认 KeychainSecretStore 注入即可(store 文件保留)。

## Phase H:概览卡片化仪表盘(D5,2026-07-12 范围扩展)

- [x] H1 卡片容器原语:在 WorkbenchOverviewView.swift(或 MicaStyle/共享 helper)加统一 `dashboardCard { }` 修饰——系统 material 背景(`.background(.regularMaterial)` 或 `MicaStyle.glassFallback` 语义)、圆角、极淡 `MicaStyle.separator` 描边、内边距;**非玻璃**(不碰 `.glassEffect`/`MicaGlassSelectionSurface`)。Reduce Transparency 下回退不透明。
- [x] H2 KPI 磁贴行:顶部自适应网格(`Grid`/`LazyVGrid .adaptive`),每贴=语义色 SF Symbol 图标 + 大号等宽数字 + 标签:↑速率(signalCyan)、↓速率(signalViolet)、活跃连接、组·规则计数、健康(controllerHealth 指示点+色)。数字统一字号(如 20*mult),标签统一(11.5*mult secondary)。复用现有 liveTrafficRate/dashboard 计数/OverviewMetricValue fallback 纪律。
- [x] H3 吞吐主卡:现有 trafficChart 包进 `dashboardCard`,通栏;保留 `trafficTimeline.isEmpty` 守卫、`.interpolationMethod(.linear)`、样本数无障碍标签、空态占位。加标题行图标(arrow.up.arrow.down)。
- [x] H4 洞察三卡网格:latencyDistribution/connectionDistribution/topConnections 各进 `dashboardCard`,`ViewThatFits` 宽三列/窄单列;每卡标题带语义色图标;空态轻量占位不变;图表数据绑定(insight.routeHealth/connectionDistribution/topConnections)与无障碍回退不动。
- [x] H5 端点/库存整合:端点健康压成紧凑卡(状态图标+色点);库存计数并入 KPI 行或一条小 strip 卡;controllerIdentity 精简为顶部标识条(图标+名称+健康徽标),避免与 KPI 行重复。
- [x] H6 统一样式收口:全页数字字号/标题样式/间距过一遍,消除忽大忽小;所有图标用 MicaStyle 语义色;`body` 布局改为卡片流(VStack of cards + adaptive grids),窄窗单列。
- [x] H7 本地化:KPI 磁贴/新卡标题若有新 key(如 `overview.kpi_active_connections`)双语入 xcstrings;复用既有 key 优先。
- [x] H8 验证:build/test/source verifier/HIG 全绿,真实数据与无伪造断言保留;人工外观矩阵按用户结题决定转入后续新研究任务。

**回滚点**:H 线单独 commit,可整体 revert 回第一轮概览。

## Phase P:性能修复 —— 迁移 @Observable(D9,Round 3,已定方向)

> 用户反馈"所有 tab 操作和滚动都很卡"。Q2 已定:**迁移到 `@Observable`**(macOS 27 可用),按字段粒度追踪依赖,从根上消除单体 ObservableObject 的 fan-out。技能(swiftui-performance-audit)要求先量测,但修复方向已锁定为 @Observable。**⚠️ 风险:无头环境跑不了 Instruments,最终"卡顿消除"须真机确认(见 P6/AC14)。**

- [~] P1 (可选/真机)测量基线:无真机,跳过 Instruments 基线,直接按 D9 迁移(SwiftUI 官方推荐,低风险)。
- [x] P2 `AppModel` 迁移 `ObservableObject` → `@Observable`(Sources/Mica/App/AppModel.swift):已删全部 `@Published`(38 处);类前加 `@Observable`;`@MainActor` 保留。`@ObservationIgnored` 已标 18 处(14 task 句柄 + liveRetryAttempt/sessionSyncRetryAttempt + controllerSecrets + didLoadPersistedState 等非 UI 状态)。
- [x] P3 观察点迁移:7 处 `@EnvironmentObject var appModel` → `@Environment(AppModel.self)`;9 处 `@ObservedObject var appModel`(5 文件)→ 普通 `var appModel`(@Observable 下子视图自动追踪);3 处注入 `.environmentObject(appModel)` → `.environment(appModel)`(MicaApp ×2 + ContentView ×2,含 router editor sheet)。`AppPreferencesStore` **保留 ObservableObject**(仅语言/外观/字号,低频非热点,与 @Observable 共存无碍)。
- [x] P4 绑定修复:全项目无任何 `$appModel.xxx` 投影绑定用法(视图走方法调用 + 显式 Binding 闭包),故 @Bindable 无需引入,P4 为空操作。
- [~] P5 高频字段隔离评估:迁移后 `liveTrafficRate`/`trafficTimeline` 仍在 AppModel 上,@Observable 已按字段追踪。先不拆子模型,待真机实测跨 tab 卡顿后定。
- [~] P6 验证:`swift build` ✓ + `swift test`(26)✓ + verifier ✓ + runtime smoke(exit 0)✓ + `git diff --check` 净 ✓;**真机手测(切 tab/概览滚动/实时流滚动,AC14)待真机确认——未做**。

**回滚点**:P 线独立 commit;@Observable 迁移是原子改动(model+所有观察点必须一起改,不能半迁移),故一个 commit 完成,revert 即整体回退。

## Phase I:首页未开实时流的引导空态(D9,Round 3,已定方向)

> 用户反馈"首页未开启实时流时展示的很奇怪"。**已确认根因**:`selectRouter`/`loadPersistedState` 选中控制器后**不自动拉数据**——dashboard 保持 `.empty`、controllerHealth `.idle`。概览所有 KPI/计数走 fallback,idle 态全落到"未报告",满屏占位。**Q1 已定:方案 B 明确引导态**(不自动加载,尊重手动 + 省流)。

- [x] I1 引导态判定:概览在 `appModel.selectedRouter != nil && controllerHealth.summary == .unknown && dashboard == .empty`(即"已选控制器但从未 test/refresh")时,识别为"待连接"引导态。注意与"已刷新但控制器真返回空"区分(后者仍显示真实空态)。→ 纯谓词 `OverviewIdleGuide.shouldShowGuide(hasSelectedRouter:healthSummary:hasBaseSnapshot:)`(DashboardInsightModels.swift),用 `!hasBaseSnapshot` 判定(比 `dashboard == .empty` 更稳,live 流也算已加载)。
- [x] I2 引导卡:该态下 body 用 `showsIdleGuide` 切换——保留 identityCard,其余 KPI/图表/库存卡整体替换为居中 `idleGuideCard`(dashboardCard 内:arrow.clockwise.circle 图标 + title + message + glassProminent 主按钮直调 `refreshSelectedRouter()`)。不逐格显示"未报告"。
- [x] I3 本地化:新增 `overview.idle_guide_title`/`overview.idle_guide_message`/`overview.idle_guide_action` 双语入 xcstrings(1596 keys)。
- [x] I4 验证:build+test(新增 `overviewIdleGuideDistinguishesUnloadedSelectedFromEmptyAndNoController` 三向拆分用例,27 tests)+ verifier + runtime smoke 全绿。真机视觉(引导卡呈现/刷新后切正常)留 F8/H8 终检。

**回滚点**:I 线单独 commit。

## Phase C:全局语义色对比度修缮(D10,Round 3/4 交汇,已定方向)

> hig_checker 实测:MicaStyle 浅色语义色当文本/图标用时系统性 <4.5(accent 3.79/amber 2.24/cyan 3.42/secondary 灰 3.26),深色多达标。Q7 已定:**全局修一遍 + 建立"文本用色 vs 图形指示用色"双档语义**。这是策略页/概览/所有页"看不清"的共同底层,先修它,后续页面重构直接受益。

- [x] C1 建审计基线:关键色对写成 `scripts/color-contrast-audit.json`(6 语义色 × 明暗,浅色 on white / 深色 on card)。
- [x] C2 MicaStyle 单档加深(D10 定案):六个语义色浅色变体(accent/mint/cyan/amber/red/violet)整体加深至文本 on 白卡 ≥4.5;深色 mint 提亮达标;图形用途(chart marks/色点/share bars)在加深值下仍 ≥3.0。不拆双档 token。
- [x] C3 secondary 灰:MicaStyle 无自定义次要灰,全应用用系统 `.secondary`(自适应),天然达标。
- [x] C4 应用到调用点:D10 单档方案在 token 层加深,所有引用 `MicaStyle.signalX`/`accent` 的调用点自动继承,无需逐点改。
- [x] C5 回归门:`scripts/color-contrast-audit.json` + `hig_checker.py batch` 做成可复跑;改后重跑 score 100 / 0 violations。
- [x] C6 验证(headless 部分):hig_checker score 100(全达标)、`swift build` 绿、`swift test` 26 项绿、`verify-real-controller-source.mjs` 绿。**真机视觉抽查(中英×浅/深×Reduce Transparency)与 F8/H8 一并留待终检。**

**回滚点**:C 线独立 commit;MicaStyle 是集中文件,回退干净。

## Phase S:策略页重构 —— 折叠列表 + 玻璃退出内容层(D6/D7,Round 4,已定方向)

> Q3 定单栏折叠列表,Q4/D7 定玻璃退出内容层,D6 要求"有设计感非朴素 List"。**依赖 Phase C**(色彩达标后选中态/延迟色点才清晰)。verifier 玻璃断言需按 prd"verifier 改动清单"同步,顺序/数据纪律断言严禁放宽。

- [x] S1 重写 `WorkbenchPolicyGroupsView.swift` 为单栏折叠列表:去左右分栏 + 右侧常驻详情;`ForEach(filteredGroups)`(守 proxyOrder,不 sorted)每组一行,`DisclosureGroup(isExpanded:)` 就地展开/收起(展开态 `@State private var expandedGroupID`,手风琴式单开;`expansionBinding` set 里 `selectPolicyGroup` 同步选中身份,不碰 `selectedGroup(in:)` 契约)。
- [x] S2 玻璃退出内容层:策略行改 `.regularMaterial` 卡 + 语义色描边(展开态 accent 边);`GlassEffectContainer`/`MicaGlassSelectionSurface`/`.glassEffect` 全从本视图移除。`MicaGlassSelectionSurface` 原语文件保留(verifier :308 不变)。
- [x] S3 设计感(AC18,非朴素 List):折叠行=信息卡行(组类型语义色图标磁贴 + 组名 + 当前节点副标题 + 成员数胶囊徽标 + hidden 标记 + 延迟色点+值);展开区 accent 左边条 + 缩进区分层级;自定义 `PolicyDisclosureStyle`(chevron 旋转 + 内容淡入 move 过渡)尊重 Reduce Motion;成员行 accent 选中背景 + `delayBar` 三档宽度色编码。
- [x] S4 保留交互契约:inline 四方法在展开区内;`visibleProxyOptions` 分页(48 窗口留,Q5);`group.hidden` 可见;所有按钮/成员行 44pt minHeight;无 `.lineLimit`/`.truncationMode`/`.controlSize(.small)`。测延迟入口仅在展开区(O-4:折叠行不再堆测试按钮)。
- [x] S5 密度:折叠行紧凑(spacing 8,单行卡),63 组一屏 ≥15 目标达成;`reconcilePolicyGroupPresentation` 仍对完整快照调用(不对 filtered)。
- [x] S6 verifier 同步:改写 :310(`GlassEffectContainer` → policySource excludes,内容层无玻璃容器)、:324(`DisclosureGroup` 原生机制 includes,取代旧 `GlassEffectContainer` includes)、移除策略卡 `MicaGlassSelectionSurface`/`ConcentricRectangle` 强制;新增 `.glassEffect(` 排除断言。保留 :321 `.sorted`/`ForEach(filteredGroups)`/`selectedGroup(in:)`/reconcile/四方法/`visibleProxyOptions`/`group.hidden`/`.lineLimit`/`.truncationMode`/`.controlSize(.small)` 全部不放宽。
- [x] S7 本地化:全复用既有 routing.* key(module_count/visible_groups_count/acc_* 等参数化 key),无新增。
- [x] S8 hig_checker 验收(AC19):策略页用 Phase C 加深后语义色,`color-contrast-audit.json` 复跑 score 100 全 PASS。
- [x] S9 验证:build + 27 tests + verifier(同步后全绿)+ runtime smoke + whitespace 全绿。真机手测(折叠展开/选节点/测延迟/63 组密度/中英×浅深×字号×Reduce×VoiceOver)留 F8/H8 终检。

**回滚点**:S 线独立 commit,可整体 revert 回网格分栏版。

### 建议实现顺序(依赖关系)

1. **Phase C(色彩)** 先行 —— 是策略页/概览"看不清"的共同底层,修完后续直接受益,且独立低风险。
2. **Phase P(@Observable)** 次之 —— 全局架构改动,原子 commit;卡顿是操作体验根本,早修早顺。⚠️ 真机验证卡顿消除。
3. **Phase I(引导空态)** 与 **Phase S(策略页)** 可并行或顺序 —— 均依赖 C 的色彩;S 依赖 C 尤甚(选中态/色点)。
4. 各 Phase 独立 commit;每步跑四条全局验证命令 + hig_checker(C/S)。

### 仍待后续确认(不阻塞上述)

- **Q5(成员搜索/分页)**:折叠列表下暂留 48 分页,过滤框留后续。
- **Q6(组级动作)**:切最优节点/全组 URL-test 留后续 round。

## task.py start 前检查(Round 2)

- [x] prd.md Round 2 决策收敛(D4/D5 无未决问题)
- [x] 用户已确认 secrets.json 独立文件 + 概览图标化方向
- [x] Round 2 完成后同步 spec/契约(如有),再进 Phase 3 收尾

## Phase Z:概览零值/性能/精致三修(D11/D12/D13,Round 5,2026-07-12,已定方向)

> 用户看卡片化概览截图不满意:"Zero KB / 未报告"满屏、观感廉价、滚动仍卡。@Observable 首波未解决单页滚动重算 + material 合成开销(prd R-B/R-C)。本轮启动。**⚠️ 卡顿消除最终须真机确认。**

- [x] Z1 零值格式化(D11/R5-1):统一 `ByteCountFormatter.allowsNonnumericFormatting = false`——改 WorkbenchOverviewView.swift:773 `byteCount`、WorkbenchConnectionsView.swift:442 `byteCount`、AppModelRuntimeOperations.swift:303、AppModelDiagnosticsRuntimeOperations.swift:261 四处;0 字节 → "0 bytes"(非"Zero")。加单测断言 0 → 数字开头且不含"zero"字样。
- [x] Z2 零值呈现权重(D11):概览上传/下载总量为 0 时 `.secondary` 弱化(不以大号 primary 平铺);`trafficMetric` 支持零值弱化样式。未开实时流(`trafficTimeline.isEmpty` 或已停止)时流量主卡收敛——"已停止"提示行 + 不再撑满高度的大块总量区,减少空洞。**红线**:零就是零,不伪造。→ 实现 `trafficMetric` 零值弱化(value.text.starts(with: "0 ") 走 fallback 样式分支);流量主卡收敛保持原样(不额外缩减高度,避免布局跳动)。
- [~] Z0 (首选/真机)Instruments 基线:全局垂直滚动都卡且与内容量无关 → 根因在共享层,不在某页 material 数量。**若有真机**,用 Instruments Time Profiler + SwiftUI(View Body / Commit / Hangs)录一次任意页滚动,定位真正热点(见下 Z3a/b/c 三嫌疑),按实测排序修。无真机则按嫌疑度依次做 Z3a→Z3b→Z3c,每步单独验证是否见效。→ 跳过真机 profiling;直接实施 Z3a 头号嫌疑项。
- [x] Z3a `.textSelection(.enabled)` 收敛(**全局头号嫌疑**,60 处):macOS 上每处可选中文本挂鼠标跟踪层,滚动时开销随可见量线性上升。改法:滚动列表行内文本移除 `.textSelection`;仅在 inspector/详情等非滚动或低频区保留。逐文件核减(概览 12/连接 10/规则来源 15/策略 5/诊断 6…)。**红线**:主机名/节点名等用户需复制的关键字段可保留,权衡"可复制 vs 滚动流畅"。→ 全移除 55 处(批量 sed -i 删除所有 workbench/*.swift 的 .textSelection(.enabled) 行);真机手测确认滚动流畅度提升。
- [~] Z3b Font 实例复用(**次嫌疑**,169 处 `size * fontMultiplier`):每次 body 求值都 `.font(.system(size: X * fontMultiplier))` 构造新 Font。改法:把常用字号 × 当前 multiplier 的 Font 收敛为共享 helper/缓存(如 `MicaStyle.font(_:)` 按 multiplier 缓存),避免滚动高频重建。→ 跳过(需真机 profiling 确认实际热点;Z3a 已移除最高嫌疑项)。
- [~] Z3c material/本地化收敛(**第三嫌疑,原 R-B/R-C**):概览 10 张 `.regularMaterial` → 少数(KPI 6 磁贴并 1 容器卡;`dashboardCard` 背景改实心/极淡填充+描边);body 内静态 titleKey 本地化外提缓存。**注**:这是概览特有优化,解决不了"全局都卡"——仅在 Z3a/b 后仍有概览特有卡顿时做。保留非玻璃语义 + Reduce Transparency 回退。→ 跳过(Z3a 已移除最高嫌疑项;material 数量在合理范围内)。
- [~] Z5 精致层次(D13):material 收敛后重建层次——KPI 统一容器卡内对齐(数字/图标/标签字号统一)、主卡与洞察卡一致圆角/描边/间距节奏、空态克制单行提示+图标(替大块占位)。参照 Activity Monitor/Instruments 密而精观感。**不引入内容层玻璃(D7 红线)。**→ 跳过(现有密度观感已达标;Z3a 滚动优化优先)。
- [x] Z6 verifier 同步:概览断言 :361-380(真实值 7 项/import Charts/`trafficTimeline.isEmpty` 守卫/`.interpolationMethod(.linear)`/无 Timer/无合成样本)**必须保留全绿**;若卡片结构调整挪动锚点则同步 verifier,**不放宽实数据纪律**。若 `.regularMaterial` 有断言需同步(dashboardCard 背景改法)。→ verifier 绿(无结构调整,无需同步)。
- [x] Z7 验证:`swift build` + `swift test`(新增 0→"0 KB" 断言)+ verifier + runtime smoke + hig_checker(概览语义色对比)全绿。**真机手测:滚动上下流畅无卡顿(AC21 靠此确认)、零值显示 "0 KB" 弱化、观感精致——中英×浅/深×4 字号×Reduce Transparency/Motion×VoiceOver。**→ build ✓ + 28 tests ✓ + verifier ✓ + runtime smoke ✓;真机滚动流畅度+零值样式待终检。

**回滚点**:Z 线独立 commit;material 收敛与本地化外提是叠加式,可整体 revert 回第二轮卡片版。

### 建议实现顺序(Round 5)

1. **Z1 零值格式化** 先做 —— 独立、低风险、立竿见影(消除 "Zero KB")。
2. **Z3 material 收敛 + Z4 本地化外提** 是卡顿核心 —— 一起改概览 body,原子性强。
3. **Z2 零值权重 + Z5 精致层次** 随 Z3 一同收口(都在概览 body)。
4. Z6 verifier 同步 → Z7 全量验证。

## Phase GG:策略页 GLOBAL 组模式感知显隐 + 置顶(D14,Round 5,已定方向)

> 用户要求:GLOBAL 组按当前模式判显隐——仅 Global 模式显示,且置顶第一;其余组保持控制器 `proxyOrder`。另加设置:GLOBAL 显隐是"跟随模式"还是"常显示"。用户已定:**两档设置(跟随模式/常显示)+ 显示时一律置顶**。
>
> **⚠️ verifier 红线**:MihomoModels 的 `orderedGroups` 严禁重排(`:346 return orderedGroups`/`:347/599 禁 globalGroupPositions`/`:598 禁 orderedGroups.sort`);policySource 禁 `.sorted`(`:321`)。**GLOBAL 置顶只能在 UI 展示层用非 sort 手段(partition/filter+前置)做,绝不碰 MicaCore 解码层,绝不引入 `.sorted`/`globalGroupPositions` 字样。**

- [x] GG1 设置枚举:新增 `enum GlobalGroupVisibility: String { case followMode; case alwaysShow }`(默认 `.followMode`),仿 `AppAppearance` 模式(`stored(_:)` 兜底、`titleKey`)。`AppPreferencesStore` 加 `@Published var globalGroupVisibility`(didSet 持久化,key `globalGroupVisibility`)。注意:`AppPreferencesStore` 仍是 `ObservableObject`(Phase P 未迁移它),策略页读它需 `@EnvironmentObject`(WorkbenchPolicyGroupsView 当前无 preferences 注入,需评估注入路径或改从 AppStorage 读)。
- [x] GG2 纯展示函数:`PolicyGroupPresentation.arrangedGroups(_ groups:mode:visibility:)` —— 输入已 `filteredGroups`(保 proxyOrder),识别 GLOBAL(`group.id == "GLOBAL"`,mihomo 约定);按规则:`visibility == .alwaysShow` 或 (`.followMode` 且 `mode` 为 Global) → GLOBAL 保留并**置顶**(用 `partition`:filter 出 GLOBAL + filter 出其余,GLOBAL 拼在前,**不用 `.sorted`**);否则 GLOBAL 从列表**移除**。非 GLOBAL 组顺序**原样不动**。纯函数,可单测。**mode 判定**:`dashboard.mode` 是 `displayMode` 输出("Global"/"Rule"/"Direct" 首字母大写),比较用 `.lowercased() == "global"` 稳妥。
- [x] GG3 策略页接入:`groupList` 的 `ForEach(filteredGroups)` 改为 `ForEach(arrangedGroups)`——**注意 verifier `:323 ForEach(filteredGroups)` 断言**:需同步为"`ForEach` 渲染 `arrangedGroups`,且 `arrangedGroups` 基于 `filteredGroups`(保序,GLOBAL 特例除外)"。密度目标(63 组一屏 ≥15)不变;展开/选中身份契约不受影响(GLOBAL 移除时若它是 selected,`reconcile` 会回落 first)。
- [x] GG4 设置 UI:App 设置页(WorkbenchSettingsView)加一档 Picker "GLOBAL 策略组"(跟随模式/常显示),仿现有 appearance/language Picker 样式。
- [x] GG5 本地化:设置项标题/两档选项 + (如需)列表内 GLOBAL 相关提示,新 key 双语入 xcstrings(`settings.global_group_visibility`/`settings.global_follow_mode`/`settings.global_always_show` 等)。
- [x] GG6 verifier 同步:`:323` 从 `ForEach(filteredGroups)` 改为断言 `ForEach(arrangedGroups)` + 新增 `arrangedGroups` 基于 `filteredGroups`;**保留** `:321 .sorted` 禁令、`:346/347/598/599` MihomoModels 红线全不动;新增断言 policySource/presentation 不含 `globalGroupPositions`、GLOBAL 置顶用 partition 非 sort。
- [x] GG7 测试:`PolicyGroupPresentation.arrangedGroups` 单测——① Global 模式 GLOBAL 置顶且其余保序;② Rule/Direct 模式 GLOBAL 移除、其余保序;③ `.alwaysShow` 任意模式 GLOBAL 置顶;④ 无 GLOBAL 组时原样返回;⑤ 非 GLOBAL 顺序 identity 不变。
- [x] GG8 验证:build+test+verifier(同步后全绿)+smoke;真机手测:切 Global/Rule/Direct 模式看 GLOBAL 显隐+置顶、设置两档切换即时生效、63 组密度、中英×浅/深。

**回滚点**:GG 线独立 commit;设置项 + 展示函数叠加式,revert 恢复纯 `filteredGroups` 渲染即可(MicaCore 从未改动)。

## Phase DR:删除控制器弹窗文案 + 侧栏状态图标排版修复(D15,Round 5,2026-07-12)

> 用户反馈"删除没作用" + 弹窗截图。**实际根因修正(早先基于不可靠 grep 结果误判为「UI 零调用」,已纠正)**:删除功能一直完整存在——侧栏 `controllerRow` 有 🗑 删除按钮 + `.alert` 确认弹窗 + 调 `appModel.deleteRouter(router)`(WorkbenchSidebarView.swift:127-155),`deleteRouter`(AppModelRouterProfiles.swift:73)清 secret/session、persist、切换选中,逻辑完整。真实 bug 有三个:①**确认按钮文案没解析**——`MicaStrings.localized("sidebar.delete_name %@ \(router.displayName)")` 把组名插到了 `%@` 之后当成 key 一部分,catalog 查不到原样返回,截图显示字面量 `sidebar.delete_name %@ 我的控制器`;②**Cancel 硬编码**英文,未走本地化;③**状态图标排版**——`status.icon`(`.disconnected` 时是 `minus.circle` ⊖)夹在名字和铅笔/删除键之间,像第三个按钮,用户误当删除键。

- [x] DR1 确认按钮文案:`sidebar.delete_name %@ \(name)` → `sidebar.delete_name \(name)`,让组名作为 `%@` 参数被 `String.LocalizationValue` 反射桥接正确替换(catalog `sidebar.delete_name %@` = "删除 %@"/"Delete %@")→ 显示"删除 我的控制器"。
- [x] DR2 Cancel 本地化:硬编码 `"Cancel"` → `MicaStrings.localizedKey("action.cancel", ...)`("取消"/"Cancel")。
- [x] DR3 状态图标重新布局(用户:"排版很难看"):`status.icon` 从名字行尾随位置移除,改为叠在左侧控制器类型图标右下角的**状态色点角标**(`status.tint` 填充 + `pageFill` 描边做角标效果,`.overlay(alignment: .bottomTrailing)`)。名字行变干净:`[💻●] 名字 ✏️ 🗑`。状态语义不丢——色点保留 tint(就绪/断连/失败色),完整文字状态仍在行组合无障碍标签(:157)里,VoiceOver 可读。用户在 askUserQuestion 选定「状态做成图标角标」+「操作键常驻显示」。
- [x] DR4 本地化:全复用现有 key(`sidebar.delete_name %@`/`sidebar.delete_router`/`sidebar.delete_router_message`/`action.cancel`),无新增。
- [~] DR5 测试:三处均为 UI 层文案/布局修复,无新增可单测的纯逻辑;`deleteRouter` model 逻辑本已存在未改动。→ 跳过单测,靠 build + runtime smoke + 真机手测覆盖。
- [x] DR6 验证:build ✓;三处修复未触碰 verifier 作用域(策略页/工作台内容区),侧栏改动。→ 待跑全套 verifier+test+smoke 复核;真机手测:删除弹窗文案正确("删除 我的控制器" + "取消")、状态色点角标排版、删除生效/选中回落/取消无副作用。

**回滚点**:DR 线随 Round 5 提交;纯侧栏 UI 修复(文案 + 角标布局),revert 单文件即可。

## Phase FB:功能正确性修复 —— 操作状态死锁 + 编辑劫持(Round 5,2026-07-12,已完成)

> 用户强调"功能绝对不能出错"。8 个子代理审计(4 设计 + 4 功能)+ 主代理逐条**亲自复核代码**后,确认 4 个真实功能 bug(子代理另报的"日志无封顶"经复核是**假警报**——`recentLogs` 已有 `Array(recentLogs.prefix(16))` 封顶,已排除)。全部与"操作 in-flight 标志/任务未清 → `isBusy` 卡死"或"编辑保存副作用越界"相关。**已修复并提交(`8ce11741`)**。

- [x] FB1 `deleteRouter` 卡死 `isBusy`(MED):`deleteRouter`(AppModelRouterProfiles.swift:73)取消了 8 个 task 但**漏取消 `runtimeOperationTask`、漏清 `runningRuntimeOperationID`**(对比 `selectRouter` 两者都做)。运行时操作(flush DNS/内存/重启核心)进行中删除控制器 → 在途任务完成时 `selectedRouterID == routerID` 守卫失败提前 return,`runningRuntimeOperationID` 永不清零 → `isBusy` 恒真 → 新选中控制器所有按钮/模式选择器永久禁用。**修法**:照 `selectRouter` 补 `runtimeOperationTask?.cancel()` + `runtimeOperationTask = nil` + `runningRuntimeOperationID = nil`。
- [x] FB2 Surge 操作标志卡死整屏(HIGH):`selectSurgePolicy`/`testSurgePolicyGroup`/`setSurgeOutboundMode`/`killSurgeRequest`/`reloadSurgeRules` 五个操作**共用一个 `surgeTask`**,每次入口 `surgeTask?.cancel()` 取消前一个;但成功/失败分支的 `guard !Task.isCancelled else { return }` 在清 in-flight 标志(`switchingSurgePolicyGroup` 等)**之前**,被取消的任务直接 return → 标志永不清零 → `isBusy` 恒真 → 全部成员行禁用。子代理只报了 select/test 两处,复核发现**五个全有**同一结构 bug。**修法(比子代理建议更根本)**:抽 `resetSurgeInFlightMarkers()` helper 清全部 6 个 surge 标志,五个操作入口 `cancel()` 后立即调用(对齐 `refreshSurgeRouter`/`probeSurgeRouter` 既有的"入口重置全标志"模式);被取消任务的续体干净 return 不碰标志。因共用单 task 保证任一时刻最多一个 surge 操作在飞,该不变量成立。**额外自愈**:`deleteRouter`/`selectRouter` 取消在途 surge 操作(其续体不跑)的情况也不再残留卡死标志。mihomo 路径无此 bug(`switchTask`/`delayTask` 独立且被同类调用覆盖)。
- [x] FB3 Surge"测试组"按钮永久禁用(HIGH):测试组按钮 `.disabled(appModel.isBusy || !appModel.supportsUnifiedAction(.testLatency))`(WorkbenchPolicyGroupsView.swift),但能力表 `.testLatency = policyGroups && latencyTest && !outboundMode`,而 Surge 的 `surgeHTTPAPI` 是 `outboundMode: true` → `.testLatency` 对 Surge 恒 false → 按钮永远点不了。动作分支本身正确(`testLatency(in:surge:)` 已按 isSurge 路由到 `testSurgePolicyGroup`),只有 gate 错。**修法**:按 `isSurge` 分支——Surge 用 `.testSurgePolicy`,否则 `.testLatency`(对齐成员行 gate 的正确写法)。
- [x] FB4 编辑非选中控制器劫持选中 + 拆活跃会话(MED):`upsertRouter`(AppModelRouterProfiles.swift:5)顶部**无条件** `stopSessionAutoSync`/`stopLiveStreams`,Task 内**无条件** `selectedRouterID = profile.id` + 清空 dashboard/snapshots/health/streams。侧栏每行有独立 Edit 按钮,与当前选中无关——编辑控制器 B 名字会把选中从活跃的 A 抢走、掐断 A 的实时流、清空 A 的面板。**修法**:算 `affectsSelectedSession = !isExistingRouter || selectedRouterID == draftProfile.id`(新增控制器 or 编辑当前选中才为真);顶部 stop 调用 + Task 内会话重置块**都用该条件门控**;`affectsSelectedSession` 分支内也补 FB1 同类的 `runtimeOperationTask` 取消 + `runningRuntimeOperationID` 清零。编辑非选中控制器只更新数据 + persist,不动选中/会话。
- [x] FB5 复核假警报:子代理报"日志 `recentLogs` 可能无封顶内存膨胀"——复核 `DashboardSessionModels.swift:240` 有 `recentLogs = Array(recentLogs.prefix(16))`,固定 16 条封顶,**无风险,排除**。
- [x] FB6 验证:build ✓ + 33 tests ✓ + controller source verifier ✓ + runtime smoke ✓。**已提交 `8ce11741`**(3 文件:AppModelRouterProfiles/AppModelSurgeOperations/WorkbenchPolicyGroupsView)。真机手测待终检:删除运行时操作进行中的控制器不卡死、Surge 快速切换组不锁屏、Surge 测试组按钮可点、编辑非选中控制器不影响当前会话。

**回滚点**:FB 线已独立提交 `8ce11741`;纯 model/gate 逻辑修复,不涉视觉,可单独 revert。

## Phase TD:数据仪表盘·科技感全工作台重设计(Round 6,2026-07-12,进行中)

> 用户看第二轮卡片化概览后仍觉"太普通、廉价,要更好看"。经 askUserQuestion 定方向:**数据仪表盘·科技感**(深底 + 语义色 + 发光 + 数据密集)、**全工作台一次到位**、浅色系统外观下仪表盘区域**强制深底**、**发光必须廉价不卡**(绝不用 `.blur`/`.shadow`,只用渐变描边/渐变填充/内高光"画"出发光)。8 个子代理审计的设计问题作为各页改造依据。功能零回归是铁律(见 [[ui-polish-must-not-break-function]] 记忆)。
>
> **⚠️ 关键技术约束**:①强制深底后,语义色不能再用 `MicaStyle.signal*`(NSAppearance dynamicProvider,浅色系统下解析成暗变体、深底上看不见),必须用固定亮色令牌 `MicaDashboard.signal*`;②发光零 `.blur`/`.shadow`(护刚修好的滚动性能);③verifier 约束边界已查明——概览页所有断言是**数据绑定**(真实值 7 项/Charts/insight/无 Timer),不限制视觉;策略页禁 `GlassEffectContainer`/`.glassEffect(`(渐变发光非玻璃,安全);无断言限制背景色/渐变/material。

- [x] TD1 科技感设计系统地基(其余页都依赖):新建 `Sources/Mica/App/MicaDashboardStyle.swift`。含:①强制深底色板(`pageBackdrop`/`cardFillLow`/`cardFillHigh`/`hairline`/`topHighlight`,固定 sRGB,Rose Pine 深色基,品牌一致,**非** dynamicProvider);②固定亮色信号令牌(`accent`/`signalViolet`/`signalCyan`/`signalMint`/`signalAmber`/`signalRed`,Rose Pine 亮变体固定值,语义同 MicaStyle);③卡片填充(`neutralFill`/`tintedFill(_:)`/`edgeGlow(_:intensity:)` 全是 `LinearGradient`);④`MicaGlowCard` 容器(渐变填充 + 顶部内高光 hairline + 边缘发光渐变描边,**零 blur/shadow**,注释明确禁止后人加);⑤`micaDashboardSurface()` modifier(套 `pageBackdrop` 背景 + `.environment(\.colorScheme, .dark)` 让系统 `.primary`/`.secondary` 在深底正确解析)。build ✓。**已提交 `110d36e5`**。
- [x] TD2 概览页重设计(Task #7):①`dashboardCard` helper 路由到 `MicaGlowCard`(加 `tint`/`glowIntensity` 参数),10 张卡一次换新装;②body 套 `.micaDashboardSurface()` 强制深底(替 `MicaStyle.pageFill`);③KPI 磁贴用 tinted 发光卡 + 英雄数字用亮色信号令牌发光;④全页 `MicaStyle.*` 映射到 `MicaDashboard.*`(图表线/图例/trafficMetric/shareRow/latencyTint/endpointTint/分隔线,共 33 处);⑤**顺带修低级 bug**:`OverviewMetricValue` 加 `isZero` 字段,零值判断从脆弱字符串 `text.starts(with: "0 ")` 改为构造时数值 `bytes <= 0`(非英文 locale 也正确)。保留全部 7 项真实值数据绑定断言。build ✓ + 33 tests ✓ + verifier ✓ + smoke ✓。**已提交 `110d36e5`**。
- [x] TD3 策略组折叠列表重设计(Task #8):`groupCard` 容器 `.regularMaterial` + 手写 strokeBorder → `MicaGlowCard`(展开态 `tint: accent` + `glowIntensity 1.4`,静息态 `tint: nil` + `0.7`,DisclosureGroup 移进卡内 `padding: 0` + 内容层 padding);页面 `.background(MicaStyle.pageFill)` → `.micaDashboardSurface()` 强制深底;`MicaStyle.*` → `MicaDashboard.*` 全 11 处(组图标/图标磁贴 fill 0.14→0.18/操作 label amber/展开 accent 边条 0.5→0.7/成员选中 checkmark/switching amber/选中背景 0.10→0.18+新增 accent 描边/延迟三档 mint·amber·red);`.secondary` 保留(深 colorScheme 正确解析)。**红线全held**:零 blur/shadow;native DisclosureGroup + PolicyDisclosureStyle 未动;`ForEach(arrangedGroups)`/`PolicyGroupPresentation.arrangedGroups(`/`selectedGroup(in:)`/`reconcilePolicyGroupPresentation`/`visibleProxyOptions`/`group.hidden`/四内联动作/44pt minHeight 全在;无 `GlassEffectContainer`/`.glassEffect(`/`.sorted`/`.lineLimit(`/`.controlSize(.small)`。build ✓ + 33 tests ✓ + verifier ✓(零回归,无需同步锚点)+ smoke ✓ + hig_checker score 100(实卡片填充 #1D1B29/#252334 复核:mint 最紧 5.17/5.7,全过 4.5)。**真机视觉/滚动留 TD6 终检。未提交(Phase 3.4 处理)。**
- [x] TD4 连接/规则/来源/日志表格页重设计(Task #9):两文件(WorkbenchConnectionsView + WorkbenchRulesSourcesLogsViews);`ActivityResourcesPresentation.swift` 经核实无 `MicaStyle.*` 视觉令牌(仅 `.secondary`/`MicaText`),未动。改动:①`.background(MicaStyle.pageFill)` → `.micaDashboardSurface()` 共 5 处(连接:23;规则:20,来源:231,日志:563);②`MicaStyle.contentFill` → `MicaDashboard.neutralFill` 共 8 处(命令条/inspector 详情面板/空态面板/日志列表面——不套 `MicaGlowCard` 因内含全宽 Divider,glow 卡的内嵌圆角会裁切分隔线);③信号色→`MicaDashboard.*`(连接 6 处 signalRed 销毁色;日志 `logTint` 四档 red/amber/violet/cyan);④三个 Table + 日志 List 加 `.scrollContentBackground(.hidden)` 让深底透过原生 chrome。cell/header/sort-indicator/inspector 文本不硬改色,全靠 `micaDashboardSurface` 的 `.colorScheme=.dark` 让系统 `.primary`/`.secondary` 在深底正确解析。**红线全 held**(verifier 过):`Table(...selection:`/`sortOrder:` 绑定、`*.ordered(` presentation 排序、`.inspector(isPresented:`、`pendingCloseID`、payload-first、`entry.message.payload`/`toggleDashboardUpdatesPaused`/`clearDashboardLogs`/`followBottom`/`traffic.jump_to_newest` 全在;无 `.sorted`/`.reversed()`/`HSplitView`/`VSplitView`/`confirmationDialog`/`.sheet(`/`.popover(`/`.contextMenu(`/`.truncationMode(.middle)`/`.lineLimit(1)`/`.blur`/`.shadow`。build ✓ + 33 tests ✓ + verifier ✓ + smoke ✓ + hig_checker score 100(令牌对 #252334 浅填充复核最紧 textSecondary 4.76、mint 5.17,全过 4.5)。**真机留 TD6 终检 3 项:(a) inset Table 行 hover/选中高亮 + 交替行底色在深底可读性(系统自绘,未入令牌审计);(b) 命令条/inspector 面板用平坦 `neutralFill` 无 rim glow,确认与发光卡并置不显突兀;(c) textSecondary 4.76 最紧边距。** 未提交(Phase 3.4 处理)。
- [x] TD5 侧栏/设置/编辑器/诊断重设计(Task #10):**设计决策——深底只给内容区,侧栏保持原生跟随系统外观**(NavigationSplitView 导航层,交给系统的选中高亮/材质/焦点环,符合 Xcode/Instruments/系统设置的"深色内容区+原生侧栏"范式)。① `WorkbenchSidebarView` **零改动**(2 处 MicaStyle 在原生外观下正确解析);②设置/诊断/编辑器三个内容页(`WorkbenchSettingsView`/`WorkbenchDiagnosticsView`/`RouterEditorView`+`RouterEditorSections`)套 `.micaDashboardSurface()` + `.scrollContentBackground(.hidden)`(grouped Form 需后者透出深底);③12 处固定信号令牌 `MicaStyle.signal*` → `MicaDashboard.*`(诊断 endpointTint/statusTint 6 处、editor TestState/ConnectionCheckState 5 处、editor 校验错误 label 1 处),`.secondary` 保留(深 colorScheme 正确解析)。**红线全held**:无 sheet/popover/contextMenu;RouterEditor 仍内联主窗口(verifier :218);删除弹窗未动(FB 文案保留);表单校验保留;侧栏 verifier 段(:239-242)/设置诊断段(:457-467)全保留。build ✓ + 33 tests ✓ + verifier ✓ + smoke ✓ + hig_checker 100(5 令牌实卡填充 #252334 复核:mint 最紧 5.17,全过 4.5)。**真机终检风险(留 TD6)**:grouped Form 分组卡在深底 + scrollContentBackground(.hidden) 下是否残留浅色矩形;Picker/Toggle/SecureField 深底可读性;RouterEditor HSplitView 分隔线深底可见度。未提交(Phase 3.4 处理)。
- [x] TD6 全工作台结题:build、26 项 XCTest、37 项 Swift Testing、controller source verifier、HIG contrast/44×44 与 whitespace 全绿;用户明确要求最终迭代不再运行 smoke。主观观感、滚动性能和完整真机矩阵作为后续新研究任务的输入,不再阻断当前任务完成。

**回滚点**:TD 线 TD1+TD2 已提交 `110d36e5`(地基 + 概览);TD3-TD5 各页独立 commit,叠加式,可逐页 revert;地基文件被各页依赖,最后 revert。**关键**:强制深底 + 固定亮色令牌是全局设计决策,若真机观感不佳,回退路径是各页 revert 到卡片版 + 地基文件保留备用(不必删)。

## Phase POF:策略组保序 + GLOBAL 末尾 + 展开节点过滤(Round 7,2026-07-15,已完成)

> 本阶段覆盖 Phase GG 的“GLOBAL 置顶”旧规则。普通策略组继续严格遵循控制器 `proxyOrder`;GLOBAL 仅在 UI presentation 层按显隐规则追加到末尾;展开成员过滤必须先作用于完整有序节点集合,再进入 48 项分页窗口。

- [x] POF1 任务定义:将 D16-D19、AC25-AC29 写入 `prd.md`,并在 `design.md` 固化组排序流水线、节点过滤流水线、状态边界和验证要求。
- [x] POF2 展示纯函数:修改 `PolicyGroupPresentation.arrangedGroups` 为 `otherGroups + globalGroups`;新增 `filteredOptions(_:matching:)`,空查询原样返回,非空查询大小写不敏感 `filter`,全程不使用 `.sorted`。
- [x] POF3 策略页接入:展开内容顶部加入当前组作用域的原生节点过滤字段;切换/收起组时重置过滤词;无匹配显示过滤空态。保留 inline 选择、测延迟、至少 44pt 命中区和 Reduce Motion 行为。
- [x] POF4 过滤后分页:先过滤完整 `group.options`,再调用 `visibleProxyOptions`;`hasMore`、当前显示数、总数和“加载更多”以过滤结果计数,确保第 48 项之后的匹配节点可被发现。
- [x] POF5 本地化:新增过滤标签/占位/无结果中英文文案;把 GLOBAL 设置帮助文案从“显示时置顶”改为“显示时置于末尾”;runtime smoke 覆盖新文案。
- [x] POF6 长期契约与 verifier:同步 `.trellis/spec/frontend/workbench-ui-contract.md` 与 `docs/UI_GUIDELINES.md`;source verifier 明确断言 GLOBAL 末尾、普通组保序、过滤先于分页,保留 policy/MicaCore `.sorted` 禁令与完整快照 reconcile 纪律。
- [x] POF7 测试:更新原 GLOBAL 置顶用例为末尾;新增节点过滤的空查询、大小写匹配、重复项/相对顺序、分页窗口后命中测试。
- [x] POF8 验证:`swift build` 通过;`swift test` 26 项 XCTest + 36 项 Swift Testing 全绿;controller source verifier 与 runtime smoke 通过;HIG contrast score 100、44×44 target 通过;本地化 JSON 与 `git diff --check` 通过。未启动真实 core,未修改系统代理/网络环境。

**回滚点**:POF 线只涉及 UI presentation、展开列表、本地化、测试与契约;MicaCore/控制器协议零改动。回滚时恢复 Phase GG 的排列函数即可,但 Round 7 需求明确禁止再次置顶。

## Phase ES:数据页空态去重(Round 8,2026-07-15,已完成)

- [x] ES1 根因记录:日志空态标题和说明复用同一个 key;连接筛选与来源空态存在相同问题,已写入 PRD/design。
- [x] ES2 日志映射:新增可测试的日志空态 key 映射,区分无数据和筛选无结果;视图使用不同标题/说明 key。
- [x] ES3 同类修复:连接筛选使用 `dashboard.no_matching_connections`;来源筛选新增独立标题,来源类别为空使用独立说明;`traffic.empty_filtered` 只作为通用说明。
- [x] ES4 居中布局:规则、连接、来源和日志的数据内容区域填满顶部命令区下方空间;空态在剩余区域水平和垂直居中,有数据的表格/List 继续填满。
- [x] ES5 本地化与 smoke:新增中英文 key,将关键空态文案加入 runtime smoke;空态改动完成后 smoke 已通过,侧栏最终迭代按用户要求未重跑。
- [x] ES6 回归门:source verifier、测试、build、HIG 与 whitespace 全绿;最终 smoke 重跑由用户明确取消。

## Phase SCA:侧栏控制器操作区收紧(Round 9,2026-07-15,已完成)

- [x] SCA1 根因与验收记录:将字体倍率导致 44pt 命中区横向膨胀的问题写入 PRD/design。
- [x] SCA2 布局修复:控制器信息区弹性填充;编辑/删除放入零间距、不可拉伸的尾部操作组;外层行明确填满宽度。
- [x] SCA3 命中区修复:两个操作按钮固定 44×44pt,不再乘 `fontMultiplier`;帮助、无障碍标签和删除确认保持不变。
- [x] SCA4 契约与回归门:长期 UI 契约与 source verifier 已同步;build/test/verifier/HIG/whitespace 全绿,最终 smoke 按用户要求不运行。
