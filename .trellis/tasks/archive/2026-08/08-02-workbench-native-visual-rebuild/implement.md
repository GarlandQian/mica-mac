# Workbench 全页面原生视觉重构实施计划

## 执行原则

- 本任务保持一个集成任务，不拆子任务：共享 chrome、视觉原语、状态系统和页面迁移存在强依赖，拆分会增加重复兼容层和视觉漂移。
- 先集中完成相关修改，再执行一次完整验证；只在编译阻断或高风险数据边界时运行最小定向检查。
- 不启动 Mica、不采集截图、不联系真实控制器、不执行任何远程操作。
- 不覆盖当前未提交修改，不处理 `.pi/`，临时文件只放 `tmp/codex/` 并在结束时清理。

## Phase 0：基线与影响图

- [x] 读取活动 PRD、设计、Workbench UI 契约及当前 dirty diff，建立用户改动基线。
- [x] 用 `rg` 记录 10 个目的地、原生 Settings scene、共享 visual primitives、presentation caches、测试和 verifier 的完整引用路径。
- [x] 确认 `Package.swift` 依赖不变；本任务不添加 Swift package。
- [x] 确认设置、诊断和本地化现有未提交修改已纳入后续改动，而非被覆盖。

## Phase 1：共享 chrome 与视觉原语

- [x] 整理 `MicaStyle` / `WorkbenchVisualSystem` 的 Midnight Instrument 语义角色，消除页面自定义白块、割裂 toolbar fill 和重复容器样式。
- [x] 重做侧栏三组信息层级、完整行点击、键盘选择、低饱和选中态和控制器切换器密度；不设置全局 44pt 行高。
- [x] 精简 toolbar / command bar / bottom status bar，确保状态、时间和操作结果只出现一次。
- [x] 审计标准菜单与 Mica 自定义菜单的语言解析和快捷键，修复菜单栏语言混用且不覆盖系统标准命令。
- [x] 统一 loading、empty、filtered-empty、unsupported、failed、paused、stale 状态，并为表格 viewport 与全页内容提供正确定位。
- [x] 审计所有可见文字使用 `micaFont`；删除导致字号无效或字号改变布局结构的直接 font/geometry 耦合。

风险与回退点：`WorkbenchChrome.swift`、`WorkbenchVisualSystem.swift`、`MicaStyle.swift`。共享原语完成前不批量迁移页面。

## Phase 2：Overview 监控台

- [x] 重排首屏为上传、下载、活动连接三张主图表；内存并入连接图上下文，仪表条与运营摘要默认隐藏但保留个性化入口。
- [x] 统一 Swift Charts hover、pin、keyboard step、pause、return-live、空样本和 accessibility 行为。
- [x] 保留真实 bounded samples；确认隐藏模块和屏幕外模块不构建昂贵子树。
- [x] 重做完整连接拓扑的宽度拟合、动态高度、全链路 hover/pin 和 Connections 跳转，移除嵌套横向滚动。
- [x] 重组网络信息字段墙并保持完整真实字段。
- [x] 保留个性化布局事务、Undo/Cancel/Done、global/per-controller override 和冲突处理。

风险与回退点：`WorkbenchDashboard.swift`、`WorkbenchOverviewProjection.swift`、`WorkbenchOverviewRuntimes.swift`、`WorkbenchOverviewTopology.swift`、`WorkbenchOverviewEditor.swift`。

## Phase 3：Proxies 策略工作区

- [x] 以单一纵向策略组流替换目录 + 检查器布局；组标题直接显示类型、可用节点数、当前选择和真实延迟分布，窄窗与宽窗均无横向滚动。
- [x] 保持普通策略组报告顺序并将可见 GLOBAL 置于最后；过滤不改变源集合。
- [x] 支持多组独立展开和独立筛选；仅为展开组建立节点投影与索引，关闭组立即释放对应缓存。
- [x] 展开内容使用自适应节点网格；整张节点卡片可切换，直接显示名称、协议、传输能力、来源、控制器报告的 SMART 使用等级和延迟。
- [x] 节点详情在当前组内行内展开；已知字段按概览、传输与测试分组，控制器额外字段默认折叠并保持稳定顺序、完整值和结构化 JSON。
- [x] 对 `selectable == false`、测试能力和会话 generation 进行完整门控。

风险与回退点：`WorkbenchProxies.swift` 及其现有 projection/cache 测试；不得修改 AppModel 的策略顺序语义。

## Phase 4：四个数据浏览器

- [x] 将 Connections、Logs、Rules、Sources 统一到一个 data-browser scaffold，但保留各自列、命令和检查器。
- [x] 确保每页只有一个原生 `Table`，稳定命令区不因 loading/empty 状态跳动。
- [x] 移出行 body 内的过滤、排序、聚合、字符串拼接和格式化，保持 unary row 与稳定 ID。
- [x] Connections：检查 ID 门控、完整字段、分组关闭、inline confirmation 和 inspector。
- [x] Logs：检查 trace 能力、arrival order、暂停、Follow Newest 合并策略和清空命令。
- [x] Rules：实现可读决策路径和精确策略组跳转，移除所有用户可见 API 路径说明。
- [x] Sources：实现可读来源焦点、真实 metadata、单项更新、顺序 Update All 和最终一次刷新。

风险与回退点：`WorkbenchDataShared.swift` 以及四个页面文件。投影与 operation task slot 不随视觉改写。

## Phase 5：管理页面与 Settings

- [x] 重整 `WorkbenchManagementCanvas` / `WorkbenchManagementFormCanvas` 的最大阅读宽度、margin 和 width-only breakpoint。
- [x] Controllers 使用紧凑列表 + 详情，编辑/删除 trailing 对齐，管理选择与活动会话保持分离。
- [x] Configuration 使用 grouped Form 和能力过滤；字段错误、当前值、说明与控制靠近。
- [x] Actions 按风险与能力分组，使用原生按钮层级，删除无效方块式按钮和不支持项。
- [x] Settings 只保留原生 `Settings` scene 的单页 `WorkbenchPreferenceForm`，移除工作台侧栏入口和重复路由；使用 grouped Form、透明滚动背景和按需系统滚动指示器。
- [x] Settings 常规宽度使用说明在左、控制 trailing；紧凑宽度才堆叠。字号变化不得触发布局切换。
- [x] 保持 SwiftUI `Settings` scene 和现有 AppKit 边界，不新增设置窗口控制器。

风险与回退点：`WorkbenchManagement.swift`、`MicaApp.swift`。不更改 preference storage key 或默认值。

## Phase 6：Diagnostics

- [x] 将诊断结论改为紧凑无外框状态 band，将 metadata 改为自适应 fact grid。
- [x] 将详细检查改为一棵连续 outline，删除卡片套卡片、技术键值串和 API 路径。
- [x] 统一一级/二级 disclosure 的完整行命中、动画 transaction、chevron 和 Reduce Motion。
- [x] 在 projection 阶段过滤 `.unavailable` 行和空 section；一级与二级均只显示当前控制器支持项。
- [x] 预计算可见状态、原因和建议文案；展开 subtree 不创建嵌套 lazy container 或重复格式化。
- [x] 保持 Copy Report 的 credential-safe 技术内容，不把 raw response/stream body 放入页面或报告。

风险与回退点：`WorkbenchManagement.swift` 的 Diagnostics 区域、诊断 projection/tests、source verifier。

## Phase 7：本地化、可访问性和契约同步

- [x] 补齐所有新增/修改文案的 English 与 Simplified Chinese，保留控制器报告名称原文。
- [x] 审计全部格式化本地化调用并增加占位符泄漏回归检查，确保 `%@`、`%d` 和位置参数不进入可见界面。
- [x] 审计菜单、help、tooltip、accessibility label/value 和动态语言重定位。
- [x] 审计浅色/深色语义对比、键盘导航、VoiceOver 组合、Reduce Motion/Transparency。
- [x] 更新相关 projection/layout/performance 测试和 `verify-real-controller-source.mjs` durable assertions。
- [x] 只在行为合同真正变化时更新 `.trellis/spec/frontend/workbench-ui-contract.md` 与 `docs/`；避免把临时实现细节写入长期文档。

## Phase 8：集中验证

依次执行，失败后只重跑受影响项：

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
git diff --check
```

- [x] 使用 Apple HIG Skill 的 contrast 检查验证 Midnight Instrument 关键文字/底色组合；不使用面向 iOS 的 44pt 命令替代 macOS 指针界面判断。
- [x] 检查未新增 Swift package、未联系控制器、未启动 runtime smoke、未生成仓库外临时文件。
- [x] 清理 `tmp/codex/` 中不再需要的构建或研究产物。
- [x] 汇总功能、性能和自动验证结果，并给出用户视觉验收清单：10 个目的地、原生 Settings scene、浅/深色、四档字号、英文/中文、窄/宽窗口、loading/empty/disconnected/stale 状态。

自动验证（2026-08-02）：源码契约、本地化 JSON、Swift 6.2 build、294 项 Swift tests 和 `git diff --check` 均通过。按任务边界未启动 Mica、未运行 runtime smoke、未访问真实控制器；运行时视觉由用户验收。

增量验证（2026-08-02）：移除重复 Workbench Settings 目的地并统一诊断能力一级行后，源码契约、本地化 JSON、Swift 编译、12 项 `WorkbenchNavigationTests`、Trellis task 校验和 `git diff --check` 均通过。

增量验证（2026-08-03）：首页默认精简为上传、下载和活动连接三张真实交互图表，内存降为连接图上下文，并保留完整链路拓扑与网络信息；源码契约、本地化 JSON、Swift 6.2 build、294 项 Swift tests 和 `git diff --check` 均通过。未启动 Mica、未运行 runtime smoke、未访问真实控制器。

增量验证（2026-08-03）：策略组页面完整替换为纵向可展开工作区，加入真实延迟分布、自适应节点网格、整卡切换、独立筛选与可读行内详情；源码契约、Swift 6.2 build、16 项策略组定向测试、294 项完整 Swift tests 和 `git diff --check` 均通过。未启动 Mica、未运行 runtime smoke、未访问真实控制器。

## 启动前检查

- [x] 用户已审阅 `prd.md`、`design.md`、`implement.md` 并明确批准实施。
- [x] 使用 `trellis-before-dev` 载入 Phase 2 上下文。
- [x] 运行 `task.py start` 将任务从 planning 切换为 active。
