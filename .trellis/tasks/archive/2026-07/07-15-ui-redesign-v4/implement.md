# Implement — UI 重做 v4 执行顺序

原则:每个 Phase 结束都要 `swift build` + `swift test` + verifier 绿再进下一步。基础层先行(原语/色板),再数据模型,再逐 tab,最后契约收尾。改动面极大,严禁一次性大爆炸提交。

## Phase 0 — 基线与护栏
- 记录当前 `swift build` / `swift test` / source verifier 基线;按用户要求不运行 runtime smoke。
- 跑一次 `apple-hig-expert` hig_checker 记录当前分数(回归对比用)。
- 确认分支(非 main;按 git_safety 先开 feature 分支)。
- 建立 D49 源码护栏:新增工作台代码不得引入 `NSTableView`/`NSOutlineView`/`NSViewRepresentable`/`NSViewControllerRepresentable`;允许名单仅含 application/window/workspace 系统桥接。

## Phase 1 — 统一表面原语 + 色板(基础层,视觉零改动地铺路)
1. 新增带显式 surface role 的 `MicaContentCard`:structural 可用 material,repeated 使用系统语义实底;Table/List/log/member row 不包卡。
2. `MicaStyle`/`MicaLayouts` 补齐 tokens(圆角/padding/描边 opacity/卡间距)。
3. 色板收敛:`MicaDashboard.signalX/accent/textSecondary/hairline` → `MicaStyle` / 系统 `.secondary`/`.separator`;逐调用点替换后删除旧 dashboard/frost/glow 原语,不建立 typealias/compatibility wrapper。
- 验证:build 绿(此时视觉可能仍是旧卡,不强求)。

## Phase 1B — Controller context 与导航分层(D42)
1. `WorkbenchDestination` 新增 Controllers 并迁移 verifier/导航测试;工作台六项快捷键不变。
2. 侧栏删除完整 controller list,只保留 destinations。
3. toolbar leading 新增固定尺寸 ControllerSwitcher Menu(Add/Manage footer)。
4. 新建 `WorkbenchControllersView`:原生高密度 Table、搜索、active/name/full endpoint/type/status/lastSuccess 列与最右 Use/Test/Edit/Delete actions;endpoint 可选择复制,禁列排序和逐行 material/card。
5. selector/page 共用 session switch API;验证 1/10/100 controllers 不改变侧栏位置。
6. Controllers page 分离 managementSelection/active selection;row click 不切换,Use 显式切换,补刷新/删除 reconcile 与零双击行为测试。
7. controller switch 保持 destination,只重置 controller-scoped search/selection/Inspector/pending;unsupported 留页内空态,旧业务数据不跨 generation。
8. ControllerSwitcher 实现 ≤10 全量、>10 current+recent8+manage/add;recent 独立持久化/prune,补 1/10/11/100 项测试。
9. Controllers page 支持 search-empty 手动 reorder,持久化顺序,提供 drag+keyboard+VoiceOver Move actions,保证 selected/session 不变且无自动排序。
10. 为 Controllers Table 补 10/100 rows、列标题不排序、endpoint 全可见/可复制、actions 固定最右和 managementSelection 不切 session 的契约测试。
11. 使用纯 SwiftUI 实现七列/三列自适应 column model;以 detail width + font scale 判定,紧凑单元格完整呈现 endpoint/type/status/lastSuccess,无横向滚动或隐藏字段;补 820pt、宽窗和四档字号切换测试。

## Phase 2 — 拆强制深色(D1)
1. 删除四处 `.environment(\.colorScheme, .dark)`(MicaDashboardStyle:178,198、MicaFrostSurface:181、WorkbenchOverviewView:42)。
2. 内容区外观回归 `.preferredColorScheme` 单一源。
- 验证:build 绿;浅色模式下右侧不再强制黑(可能暂时难看,Phase 3 修卡片)。

## Phase 3 — 数据模型重构(D13,最高风险,独立阶段)
1. 设计 `LiveSession` 生命周期:`enterLiveSession(router)` / `leaveLiveSession()`。
2. 后台 REST 刷新子系统:把 `runMihomoSessionAutoSyncLoop`+`syncMihomoSessionSnapshot` 拆成 session-scoped refresh coordinator 的 2s/5s/30s lanes;初始/手动全量请求共用 single-flight/coalescing,剥离 `syncRequested` 用户开关。
3. 推流子系统:现有 `liveTrafficTask`/`liveLogsTask` 接入 LiveSession。
4. 状态合并为单一 `sessionState`(connecting/live/partial/failed);删 `controllerSession.syncState` 用户可见文案。
5. 新增 selected-controller ID 持久化;`loadPersistedState()` 在 profiles/secrets 完成后幂等恢复选择并自动 `enterLiveSession`,失效 ID 回退第一项,无控制器零请求。
6. `selectRouter` → 自动 `enterLiveSession`(反转 Round 3 D9);切换控制器正确 cancel 旧 session,更新持久化 ID。
7. 新增统一 presentation pause gate + session-owned 有界 pending 数据:REST/端点仅保留最新值、traffic 使用五分钟/~300 真实样本窗口、日志使用 2000 条+8MiB 双上限;恢复时原子应用并 coalesce 一次立即刷新。
8. pause 时统一禁用 toolbar/menu/shortcut refresh,test 保留;resume 原子 apply pending 后只请求一次 coalesced full refresh。
9. 接入主窗口关闭与 `NSWorkspace` sleep/wake 生命周期:失焦/最小化继续;最后主窗关闭或睡眠 leave;可见主窗重开/唤醒只建立一个新 generation。
10. 删除用户可见"快照/sync"概念:`toggleSessionAutoSync` UI 入口、snapshot 状态文案、Round 3 idle 引导态改"连接中"。
11. 本地化:移除孤儿 sync/snapshot key,新增连接中/实时会话/已暂停呈现文案(中英)。
12. 为每个 endpoint/channel 建 last-success/stale 状态;成功后失败在同一 generation 内无超时保留最后值,从未成功走错误空态;切换/leave 清除,恢复原地替换。
13. 在 `RouterTrialFailureCategory` 增加 retry disposition;协调器实现分类退避、capped jitter、成功重置、terminal stop 和显式 manual attempt。
14. terminal error 只发布状态和 edit/test commands,不自动改 destination;当前控制器保存成功后 replace session,非当前保存无会话副作用。
15. 重构 controller upsert 为 awaitable transaction;RouterEditor 保存成功才关闭,失败保留草稿内联报错,覆盖重复提交与存储失败原子性测试。
16. 建统一 dirty-editor navigation gate;普通离开使用 inline confirm,window close 使用唯一原生 destructive confirm,保存中禁止离开。
17. 将 pause 收入 session generation state;Tab 保留,所有 session/lifecycle replacement 重置,删除任何持久化或页面级 pause 副本。
18. 调整新 controller 保存:已有 active 时不抢占,无 active/首个 controller 才自动 select+connect;补草稿 test 与保存失败零副作用测试。
19. 重构 controller delete 为原子事务;active 按原 index next/previous 回落并连接,非 active 零会话副作用,失败保留全部状态。
20. 删除任何连接失败自动选择候选逻辑;retry/terminal/stale 状态绑定 selected controller ID,仅显式选择或 D35 可切换。
21. 用 `BoundedLogBuffer` 替换 16 条数组截断:2000 条 + 8MiB UTF8 双上限,pause 共预算,过滤纯 projection,clear/leave 全清。
22. 扩展 `TrafficTimeline` 为五分钟/~300 真实样本窗口,按 timestamp+count 裁剪,pause 使用 session timeline,保持无 Timer/插值/持久化。
23. 重构 Controller CommandMenu/toolbar 为共享 descriptors:test/refresh/pause-resume/edit/copy;删 live/sync,Add 仅 File,Delete 仅 Controllers 管理页,统一 capabilities。
24. 将按需 operation bar 重构为常驻固定高度 status bar,绑定 controller/session/lastSuccess,临时 operation 覆盖摘要且无布局跳动。
25. 将 closed connections 改为 1000 条 + 16MiB 双上限 buffer,ID 去重保最新,pause 共预算,clear/switch/leave 全清。
- 验证补充:注入测试 clock/client spy,覆盖三档频率、错峰、单端点 single-flight、手动 follow-up 合并、独立退避、暂停仍调度、generation 取消及 live/partial/stale/paused 正交组合。
- 验证:build + test(新增注入 client/clock 的 LiveSession 状态机与零真实网络请求测试)绿;不运行 runtime smoke。真机确认选中即有数据留终检。

## Phase 4A — 代表性视觉 slice(D19,强制停点)
1. **shell** — 纯 destination 原生侧栏 + ControllerSwitcher/glass 工具栏 + material 状态栏 + Controllers 管理页。
2. **概览** — 少量 `MicaContentCard`、KPI/Charts/真实空态。
3. **策略样本** — Zashboard 式固定错落双列;按可见结果 index 奇偶横向紧凑分配,GLOBAL 作为普通末位卡,支持多组同时展开和按组过滤/分页/卡内节点滚动;展开 ID 按控制器持久化,瞬态状态仅进程内;补搜索换列、恢复、键盘/VoiceOver 横向顺序测试。
4. **连接样本** — Table + sortOrder + Inspector。
5. **设置样本** — 一个原生表单分组,套统一节奏。
6. light/dark × standard/large + Reduce Transparency 截图,HIG 检查,记录用户明确批准。
- **硬门**:用户批准前不得进入 Phase 4B;反馈只回改 tokens/共享原语/slice,不扩散。

## Phase 4B — 剩余 tab 视觉铺开(仅 Phase 4A 批准后)
按依赖顺序,每个 tab 独立小步提交:
1. **侧栏/概览/策略/连接** — 将 slice 的最终原语覆盖完整状态与数据规模;策略补 `[A,B,C,D,E]→左[A,C,E]/右[B,D]`、单列回退、无 rebalance 和可访问顺序测试。
2. **规则/来源/日志** — 表格/List + 按需 Inspector 保留;守排序/空态契约。
3. **配置/操作/诊断/设置** — 原生表单套已批准的共享节奏。
4. **控制器编辑器** — 与表单页同语言。
5. **工具栏/状态栏** — 完整动作和 sessionState 状态覆盖。
- 每 tab:build 绿 + 该页 verifier 断言绿;禁止创建 slice 未批准的新视觉原语。

## Phase 5 — 契约 + 验证收尾(R5/R6)
1. 更新 `workbench-ui-contract.md`「Visual Hierarchy」/「Data And Preference Invariants」:去 forced-dark,写整窗跟随外观 + 单一实时会话模型。
2. `docs/UI_GUIDELINES.md` 同步。
3. `scripts/verify-real-controller-source.mjs`:新增内容层无 dark/glow/frost 断言;更新数据模型锚点;保留所有实数据/顺序/凭据纪律。
4. 全量门禁:`swift build` + `swift test` + verifier + `git diff --check` + `apple-hig-expert` HIG contrast/target 检查(浅/深双档文本 ≥4.5、图形 ≥3.0、命中区 ≥44pt);不运行 runtime smoke。

## Phase 6 — 终检(真机,用户）
- 整窗一致无割裂(浅/深/跟随)、中英、4 档字号、Reduce Transparency/Motion、VoiceOver。
- 选中控制器即进入实时、有数据、无"快照"字样。
- 主观精致度复核(Liquid Glass 分层是否到位、有无廉价感)。

## 关键红线(全程)
- 玻璃只在导航/悬浮功能层;低数量结构内容可用 material,高数量重复数据使用系统语义实底;内容层无 `.glassEffect`。
- 实数据纪律:无 Timer 合成、无伪造时间轴、`trafficTimeline` 空态守卫。
- 顺序纪律:策略组保序 + GLOBAL 末尾 + 过滤先于分页;表格 presentation 层排序、view 无 `.sorted`。
- 凭据纪律:FileSecretStore、导出无凭据、RouterProfile 只 secretReference。
- 无中间截断/掩码;44pt 命中区;空态两级文案。
- 工作台内容纯 SwiftUI;不新增 AppKit table/outline/representable UI,系统级 AppKit bridge 除外。

## Completion Record — 2026-07-17

- 完成 11 个固定 destinations、纯 destination 侧栏、ControllerSwitcher、Controllers 自适应 Table、手动顺序和独立 recent history。
- 完成单一 generation 实时会话、2s/5s/30s lanes、single-flight/follow-up、分类重试、窗口/睡眠生命周期和首个控制器自动恢复。
- 完成暂停呈现的 pending/有界缓冲、固定暂停时间、共享命令能力；Test 保留，所有 refresh/reload/provider-update 入口统一禁用。
- 完成 last-success 数据保留与 stale 标记；删除旧 Surge 快照刷新路径、用户可见 live/sync 模式文案及兼容残留。
- 完成策略组固定横向顺序错落双列、GLOBAL 稳定末位、多展开、按组过滤/分页/滚动及按控制器展开持久化。
- 完成控制器保存/删除事务、非活动控制器零会话副作用、编辑器 inline discard gate 和脏草稿窗口关闭原生破坏性确认。
- 完成 Rose Pine 语义色对比度调整、Liquid Glass 分层、空态居中、全量可见业务数据及中英本地化清理。

验证结果：

- `swift test --scratch-path tmp/codex/swift-build`: 26 XCTest + 64 Swift Testing，0 failures，构建无警告。
- `node scripts/verify-real-controller-source.mjs`: passed。
- `node --check scripts/verify-runtime-smoke.mjs`: passed（仅语法；按用户要求不运行 runtime smoke）。
- `python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings`: passed。
- `git diff --check`: passed。
- `apple-hig-expert hig_checker.py batch`: 100/100，0 violations。
