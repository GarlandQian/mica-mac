# Implementation Plan: Connection, Source And Log Workspaces

## Gate Before Code

- [x] 用户审核并批准 `prd.md`、`design.md` 和本计划。
- [x] 运行
  `python3 .trellis/scripts/task.py validate 08-01-connection-source-log-workspaces`。
- [x] 批准后运行
  `python3 .trellis/scripts/task.py start 08-01-connection-source-log-workspaces`。
- [x] 记录 `git status --short`，只处理本任务文件，不回退现有未提交修改。
- [x] Phase 2 前加载 `trellis-before-dev`、`mica-controller-development`、
  `macos-app-design`、`apple-hig-expert`、`swiftui-expert-skill` 和
  `swiftui-liquid-glass`。

本任务使用 inline 工作流，不派发 implement/check 子代理。不得连接真实控制器、
9090 或核心，不修改系统网络，不运行旧 runtime smoke。临时构建与检查输出放在
`tmp/codex/connection-source-log-workspaces/`，完成后删除不再需要的内容。
所有页面修改完成后再集中执行完整验证。

## Phase 1: Shared Navigation And Pure Projections

**Primary files**

- `Sources/Mica/Features/Workbench/WorkbenchWorkspaceStore.swift`
- `Sources/Mica/Features/Workbench/WorkbenchVisualSystem.swift`
- `Sources/Mica/Features/Workbench/WorkbenchConnections.swift`
- `Sources/Mica/Features/Workbench/WorkbenchSources.swift`
- `Sources/Mica/Features/Workbench/WorkbenchLogs.swift`
- focused Workbench tests

**Work**

- [ ] 增加 session-bound 的规则导航请求和 stage/consume 生命周期。
- [ ] 增加连接焦点、唯一规则解析、来源焦点和日志严重度纯投影。
- [ ] 只在真正跨页复用时扩展共享路径原语；页面专属视觉留在页面文件。
- [ ] 添加中英文文案、help 和辅助功能语义。

**Focused tests**

- [ ] 规则 `(type, payload)` 唯一精确命中、零命中和重复命中。
- [ ] 策略组大小写敏感精确命中，DIRECT/REJECT/节点不命中。
- [ ] generation/controller 变化使待处理导航失效。
- [ ] 日志类型别名到严重度、色彩角色和文字的稳定映射。

**Rollback point:** 纯投影和 session navigation 不改变 API、DTO 或持久化编码。

## Phase 2: Connections Diagnostic Workspace

**Primary files**

- `Sources/Mica/Features/Workbench/WorkbenchConnections.swift`
- `Sources/Mica/Features/Workbench/WorkbenchRules.swift`
- `Sources/Mica/Features/Workbench/WorkbenchWorkspaceView.swift`
- connection/rule/navigation tests

**Work**

- [ ] 将 destination binding 传入连接页。
- [ ] 选中连接时显示完整身份、规则、provider/策略链和目标焦点区；无选择时
  完全移除。
- [ ] 将可导航规则与策略步骤实现为严格解析后的无底色动作。
- [ ] Rules 消费唯一匹配导航，必要时揭示目标并选择/滚动到对应行。
- [ ] 删除连接 Table 独立操作列，将当前/分组关闭移入焦点区，关闭全部保留
  命令栏。
- [ ] 保留活动/已关闭、搜索、排序、keyed 指标、排序冻结、确认和 inspector。

**Focused tests**

- [ ] 唯一规则跳转选择正确行，重复规则不跳转。
- [ ] 策略跳转保留目标组过滤与检查选择。
- [ ] 关闭命令继续使用相同 intent、capability 和 generation 门控。
- [ ] 指标帧不重建规则/策略解析目录或连接静态索引。

**Rollback point:** 焦点区和 destination/navigation 接线可独立回退，mutation
层保持不变。

## Phase 3: Sources Lifecycle Workspace

**Primary files**

- `Sources/Mica/Features/Workbench/WorkbenchSources.swift`
- source projection/operation tests

**Work**

- [ ] 增加选择驱动的
  `来源 → 内容规模 → 最近更新/健康状态` 焦点区。
- [ ] 将单项更新和健康检查移入焦点区并保持固定命中几何与进度反馈。
- [ ] 删除 Table 独立操作列，重新平衡 full/compact/stacked 列宽。
- [ ] 保留 Update All、重新加载和批量进度的命令栏边界。
- [ ] inspector 只保留完整字段、错误和最近结果，不重复主要命令。

**Focused tests**

- [ ] 选中来源投影只读取一个来源，缺失字段不合成。
- [ ] 单项操作、批量操作和重载继续使用现有任务槽和能力门控。
- [ ] 过滤、排序、选择和滚动恢复不受 action column 删除影响。

**Rollback point:** 来源操作调用不变，只迁移其呈现位置。

## Phase 4: Logs Stream Workspace

**Primary files**

- `Sources/Mica/Features/Workbench/WorkbenchLogs.swift`
- log projection/follow tests

**Work**

- [ ] 在行投影阶段预计算严重度，增加 3 点语义色轨和明确级别文字。
- [ ] 重组三种宽度模式，让时间/级别稳定定位、消息/载荷成为主扫描内容。
- [ ] 保持固定单行几何、完整 inspector 和无彩色行背景。
- [ ] 收敛 Follow Newest、停止跟随和 Jump to Newest 的命令状态。
- [ ] 保留 append/drop delta、来源顺序、过滤、搜索、选择和锚点。

**Focused tests**

- [ ] 级别映射同时提供颜色以外的文字/辅助功能语义。
- [ ] append/drop 只格式化新增行，不因色轨回退为全量投影。
- [ ] 选择和用户滚动停止跟随一次，Jump 恢复并滚动到最新行。

**Rollback point:** 严重度投影是展示值，不修改日志 domain 或来源顺序。

## Phase 5: Documentation And Concentrated Verification

- [ ] 更新 `Localizable.xcstrings` 并验证英文/简体中文覆盖。
- [ ] 更新 `scripts/verify-real-controller-source.mjs` 的新结构和旧结构排除项。
- [ ] 运行聚焦连接、来源、日志、规则导航和 workspace 测试。
- [ ] 使用仓库内 scratch path 运行 `swift build`。
- [ ] 使用同一 scratch path 运行 `swift test`。
- [ ] 运行 `node --check scripts/verify-real-controller-source.mjs`。
- [ ] 运行 `node scripts/verify-real-controller-source.mjs`。
- [ ] 运行 `python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings`。
- [ ] 运行 Apple HIG 对比度与 44 点命中区域检查。
- [ ] 运行 `git diff --check` 和 Trellis task validation。
- [ ] 对照 AC1-AC10 汇总证据，确认未运行 runtime smoke 或访问真实控制器。
- [ ] 仅把新发现的长期约束同步到 `.trellis/spec/` / `docs/`。
- [ ] 删除 `tmp/codex/connection-source-log-workspaces/` 中无用临时文件。

## Risk Review Before Start

- 三个页面及共享 workspace/store 已包含大量未提交重构，编辑必须逐段保留现有
  性能和功能工作。
- 规则导航不得在连接页复制规则 Table 投影，也不得用首项解决重复匹配。
- 日志色轨不得增加可变行高、行背景动画或每帧字符串归一化。
- 来源与连接移除 action column 后，键盘、VoiceOver 和 destructive confirmation
  仍必须可达。
- 最终验证失败时按页面回退呈现，不回退现有增量数据和性能边界。
