# Implementation Plan: Localization Placeholders And Management Form Alignment

## Gate Before Code

- [x] 用户审阅并批准 `prd.md`、`design.md` 和本计划。
- [x] 运行
  `python3 .trellis/scripts/task.py validate 07-30-localization-placeholder-settings-alignment`。
- [x] 批准后运行
  `python3 .trellis/scripts/task.py start 07-30-localization-placeholder-settings-alignment`。
- [x] 加载 `trellis-before-dev`、`mica-controller-development`、
  `swiftui-expert-skill`、`macos-app-design` 和 `apple-hig-expert`。
- [x] 记录 `git status --short`，保留全部无关未提交修改。

不访问真实控制器、9090、核心进程或系统网络；不运行旧 runtime smoke。
临时验证输出只放在 `tmp/codex/localization-settings/`，结束时清理无用文件。

## Phase 1: Repair The Catalog Contract

**Primary files**

- `Sources/Mica/Resources/Localizable.xcstrings`
- `Sources/Mica/App/AppModelDiagnostics.swift`
- 参数化 dashboard/diagnostics 调用所在的现有 Swift 文件

**Work**

- [x] 生成实施前的 31 项结构化审计清单。
- [x] 按“静态标签”和“参数化整句”拆分诊断目录键。
- [x] 将参数化键签名改为 Swift 实际生成的 `%@` / `%lld` 形式。
- [x] 修复 `dashboard.switch_node` 等静态控件文案。
- [x] 审计其余异常 dashboard 条目并迁移有效模板。
- [x] 更新目录语义键以匹配所有受影响调用点，不保留错误旧键的兼容副本。
- [x] 检查英文与简体中文文案在语义和参数顺序上对应。

**Rollback point**

按目录键组提交逻辑上的独立修改；不改 resolver 来兼容错误 catalog。

## Phase 2: Add Localization Regression Gates

**Primary files**

- `scripts/verify-real-controller-source.mjs`
- `Tests/MicaTests/XCStringsResolverTests.swift`
- 必要时新增聚焦的本地化测试文件

**Work**

- [x] 在源码验证器中实现 catalog 全量格式签名检查。
- [x] 覆盖普通百分号、`%%`、显式位置、字符串和整数格式符。
- [x] 增加静态诊断标签测试，确认输出不含格式符。
- [x] 增加字符串/整数参数化诊断测试。
- [x] 增加英文与简体中文反向重定位测试。
- [x] 增加截图中代表键的防回归断言。

**Rollback point**

验证器与测试只编码通用目录契约，不硬编码全部 31 项旧清单。

## Phase 3: Establish The Canonical Management Field Row

**Primary files**

- `Sources/Mica/Features/Workbench/WorkbenchManagement.swift`
- `Sources/Mica/Features/Workbench/WorkbenchVisualSystem.swift`
- `Sources/Mica/Features/Routers/Views/RouterEditorSections.swift`
- 现有 Workbench/设置布局测试

**Work**

- [x] 完善 `WorkbenchFormRow`，明确常规/紧凑布局、标签宽度、控件起点和尾部
  弹性空间。
- [x] 设置页两个 host 在根部解析并注入宽度模式，不在每行重复测量。
- [x] 将语言、外观、界面文字和 GLOBAL 策略组迁移到 canonical row。
- [x] 将配置页 `configurationRow` 迁移到 canonical row，移除 Picker 和
  只读文本的 trailing 对齐。
- [x] 审计控制器编辑、控制器详情、操作和诊断的全部字段行，消除局部默认
  值列或对齐例外。
- [x] 将 Tailscale 等管理内嵌详情的默认 `LabeledContent` 改为明确 leading
  布局。
- [x] 保留 Picker、Toggle、TextField、文本选择、help、键盘和辅助功能语义。
- [x] 增加结构测试，禁止管理字段恢复默认自动值列或 trailing 对齐。

**Rollback point**

按设置、配置和内嵌详情分组迁移；不改变工具栏、头部计数、状态摘要、表格列
或非表单页面。

## Phase 4: Concentrated Verification

- [x] `python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings`
- [x] `node --check scripts/verify-real-controller-source.mjs`
- [x] `node scripts/verify-real-controller-source.mjs`
- [x] `swift test --scratch-path tmp/codex/swift-build --filter XCStringsResolverTests`
  （9/9）。
- [x] `swift build --scratch-path tmp/codex/swift-build`
- [x] `swift test --scratch-path tmp/codex/swift-build`
  （Swift Testing 276/276，XCTest 无失败）。
- [x] `git diff --check`
- [x] 全目录结构化格式签名审计异常数为 0。
- [x] 按用户要求不启动应用或运行 runtime smoke；运行时视觉验收留给用户。
  常规/紧凑布局由宽度模式测试、源码契约、完整构建和 HIG 44 点命中门槛
  覆盖。
- [x] 确认未运行 runtime smoke，未访问真实控制器、9090、核心或系统网络。
- [x] 清理本任务在 `tmp/codex/` 中生成的无用输出。

## Completion Review

- [x] 将每条 PRD 验收标准映射到 resolver 测试、偏好/布局测试、源码验证器、
  HIG 检查或用户运行时视觉验收边界。
- [x] 检查并保留全部无关工作区修改。
- [x] 将本地化格式签名和管理字段布局约束同步到
  `.trellis/spec/frontend/workbench-ui-contract.md`。
- [x] 完成 Trellis check 和 finish 前置审阅；遵循“未提交代码不归档”规则，
  本轮不创建 Git 提交，也不归档任务。

## Phase 5: Approved Proxy Node Field Follow-Up

**Primary files**

- `Sources/Mica/App/DashboardSessionModels.swift`
- `Sources/Mica/Features/Workbench/WorkbenchProxies.swift`
- `Sources/Mica/Resources/Localizable.xcstrings`
- `Tests/MicaTests/WorkbenchTimelineAndProxyTests.swift`
- `scripts/verify-real-controller-source.mjs`

**Work**

- [x] 保留控制器上报的启用与停用传输能力状态。
- [x] 将节点检查器拆分为概况、传输能力、测试与延迟、控制器字段。
- [x] 将原始顶层节点字段逐项显示，并提供确定性标量/JSON 格式。
- [x] 将原始字段投影限制到当前选中节点，避免全节点目录预计算。
- [x] 增加字段完整性、顺序、格式化和源码边界回归断言。
- [x] 集中运行目录验证、源码验证器、Swift 构建/测试和 diff 检查。
- [x] 将通过后的节点检查器契约同步到前端 spec，并完成 Trellis check。

## Phase 6: Approved Management Settings Visual Follow-Up

- [x] 将管理 ScrollView、Form 和偏好内容改为左侧有限宽度轴。
- [x] 新增共享无圆角 `WorkbenchContentBand`，统一设置、操作、控制器详情和
  诊断分区。
- [x] 收紧字段标签列并让设置帮助文案直接可见。
- [x] 保留配置和原生 Settings 的 grouped `Form`，移除 Spacer 居中框架。
- [x] 更新源码验证器与前端 UI contract。
- [x] 集中运行目录、源码、HIG、Swift 构建测试和 diff 验证。

## Phase 7: Approved Preference Control Chrome Follow-Up

- [x] 将四个偏好选项统一为共享原生 borderless menu。
- [x] 移除外观和字体大小的 segmented button strip。
- [x] 保留即时 Binding、help、键盘与辅助功能语义。
- [x] 更新源码验证器、UI 指南、前端 contract 和任务验收标准。
- [x] 集中运行源码、HIG、Swift 构建测试和 diff 验证。

## Phase 8: Approved Rules Scan Hierarchy Follow-Up

- [x] 合并规则类型与主要定义，移除重复类型列。
- [x] 将状态改为圆点与文字，并把 mutation 合并到状态/摘要。
- [x] 移除独立操作按钮列，保持单 Table 的三种宽度模式。
- [x] 保留原始顺序、搜索、排序、选择、检查器和 typed mutation。
- [x] 更新源码验证器、UI 指南、前端 contract 和任务验收标准。
- [x] 与 Phase 7 集中运行源码、HIG、Swift 构建测试和 diff 验证。
