# Implementation Plan: Rules And Policy Decision Workspace

## Gate Before Code

- [x] 用户审核并批准 `prd.md`、`design.md` 和本计划。
- [x] 运行
  `python3 .trellis/scripts/task.py validate 07-31-rules-policy-workspace-innovation`。
- [x] 批准后运行
  `python3 .trellis/scripts/task.py start 07-31-rules-policy-workspace-innovation`。
- [x] 记录 `git status --short`，只处理本任务文件，不回退用户现有修改。
- [x] Phase 2 开始前加载 `trellis-before-dev`、`mica-controller-development`、
  `macos-app-design`、`apple-hig-expert`、`swiftui-expert-skill` 和
  `swiftui-liquid-glass`。

不连接真实控制器、端口 9090 或核心进程，不修改系统网络，不运行旧 runtime
smoke。临时构建和检查文件放在 `tmp/codex/rules-policy-workspace/`，任务结束
删除不再需要的内容。所有实现完成后再集中验证。

## Phase 1: Shared Path Language And Pure Models

**Primary files**

- `Sources/Mica/Features/Workbench/WorkbenchVisualSystem.swift`
- `Sources/Mica/Features/Workbench/WorkbenchRules.swift`
- `Sources/Mica/Features/Workbench/WorkbenchProxies.swift`
- `Sources/Mica/Resources/Localizable.xcstrings`

**Work**

- [x] 实现无卡片背景的路径步骤、连接符、状态 readout 和动作样式。
- [x] 增加规则路径投影与精确策略组目标解析。
- [x] 增加策略 split/stacked 布局模型、路径带前缀/溢出模型和组内延迟比例模型。
- [x] 添加中英文文案、help 和辅助功能标签。

**Focused tests**

- [x] 精确大小写匹配；DIRECT、REJECT、节点名和未知目标不可导航。
- [x] 可见前缀与溢出保持来源顺序并标记当前项。
- [x] 布局阈值、超大字体预算、无延迟和真实延迟比例。

**Rollback point:** 纯模型和共享视觉原语不修改控制器或持久化行为。

## Phase 2: Rules Decision Path And Cross-Navigation

**Primary files**

- `Sources/Mica/Features/Workbench/WorkbenchRules.swift`
- `Sources/Mica/Features/Workbench/WorkbenchWorkspaceView.swift`
- focused rules/navigation tests

**Work**

- [x] 把目的地 binding 传入规则页。
- [x] 选中规则时在 Table 上方显示
  `type → payload → target` 焦点条；无选择时完全移除。
- [x] 在焦点条显示真实状态、命中/未命中和活跃连接，不复制完整 inspector。
- [x] 精确目标点击时先用现有 workspace projection 打开/激活组，再导航到
  `.proxies`。
- [x] 保持规则 Table 单实例、排序、搜索、滚动恢复、mutation 和 inspector。

**Focused tests**

- [x] 跳转后目标组打开且活动，既有过滤和检查选择保留。
- [x] 无匹配目标不修改目的地或策略工作区。
- [x] 规则选择变化不触发静态规则索引重建。

**Rollback point:** 删除焦点条和 destination binding 即可恢复规则页，规则
数据与 mutation 层不变。

## Phase 3: Policy Shell, Directory And Open Path Ribbon

**Primary files**

- `Sources/Mica/Features/Workbench/WorkbenchProxies.swift`
- `Tests/MicaTests/WorkbenchProxyWorkspaceTests.swift`
- `Tests/MicaTests/WorkbenchTimelineAndProxyTests.swift`

**Work**

- [x] 用清晰 `MARK` 分区整理策略呈现，不增加 Workbench 文件，不移动投影缓存
  和 controller operation 边界。
- [x] 宽窗口保留受限双栏；窄窗口改为默认收起、可原地展开的顶部目录。
- [x] 将目录行拆成组名 open/activate 与尾部 disclosure open/close 两个命中区。
- [x] 用打开路径带替换横向标签 ScrollView，尾部项目进入来源顺序溢出菜单。
- [x] 用活动决策路径焦点条替换普通 header。
- [x] 选择紧凑目录项目后收起目录；过滤、检查选择和打开状态继续持久化。

**Focused tests**

- [x] 组名重复点击不关闭；disclosure 与路径关闭有效。
- [x] 关闭活动组时下一项优先、否则上一项。
- [x] 多组打开和 GLOBAL-last 顺序不变；溢出无横向滚动。
- [x] split/stacked 都只构建一个活动节点 List。

**Rollback point:** 新 shell 只消费现有投影值，可独立恢复呈现文件。

## Phase 4: Node Comparison And Selection-Driven Inspector

**Primary files**

- `Sources/Mica/Features/Workbench/WorkbenchProxies.swift`
- strategy projection/workspace tests

**Work**

- [x] 在固定高度节点行绘制无动画的真实延迟比较轨道和精确毫秒值。
- [x] 区分控制器当前节点、工作区检查节点、健康和 SMART 上报状态。
- [x] 节点点击先打开详情，再按现有能力立即切换；不可选择组仍可检查和测试。
- [x] 宽窗口仅在有检查节点时插入右侧 inspector；窄窗口在同页底部插入。
- [x] inspector 关闭只清除检查 ID，不发送 mutation，不预留空白。
- [x] 保持节点/组测试和解除固定选择在同一主窗口。

**Focused tests**

- [x] 缺失延迟无轨道；比例不重排且不覆盖精确值。
- [x] SMART 仅使用上报等级。
- [x] 关闭详情不改变 `group.selected`，重新选择可恢复详情。
- [x] 高频延迟更新不重建目录或非活动组成员。

**Rollback point:** 延迟轨道与条件 inspector 不改变成员投影、身份或 mutation。

## Phase 5: Concentrated Verification And Cleanup

- [x] 运行 focused rules/proxy/navigation tests。
- [x] 使用仓库内 scratch path 运行 `swift build`。
- [x] 使用仓库内 scratch path 运行 `swift test`。
- [x] 运行 `node --check scripts/verify-real-controller-source.mjs`。
- [x] 运行 `node scripts/verify-real-controller-source.mjs`。
- [x] 运行 `python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings`。
- [x] 运行 Apple HIG 对比度与命中区域检查。
- [x] 运行 `git diff --check`。
- [x] 通过离散布局模型和源码契约检查常规、紧凑、最窄及超大字体结构；未运行旧
  runtime smoke。
- [x] 对照 AC1-AC12 汇总验证证据。
- [x] 删除 `tmp/codex/rules-policy-workspace/` 中不再需要的临时文件。
- [x] 仅把新发现的长期约束沉淀到 `.trellis/spec/` 或 `docs/`。

### Verification Evidence

- `swift build` 通过。
- `swift test` 通过：27 个测试套件、284 个测试、0 失败。
- Workbench 源码契约、本地化 JSON、Trellis context 和 `git diff --check` 通过。
- Apple HIG 检查得分 100，0 项违规。
- 未连接真实控制器、核心或 9090；未运行 runtime smoke。

## Risk Review Before Start

- `WorkbenchRules.swift` 和 `WorkbenchProxies.swift` 当前已有未提交修改，编辑前必须
  逐段核对并保留用户工作。
- 规则目标与重复组名采用“arranged 来源顺序中的首个精确匹配”，禁止模糊匹配。
- 路径带的 `ViewThatFits` 仅用于低数量 chrome；不得包裹节点列表或规则 Table。
- 不得让 compact directory 展开状态进入持久化 schema。
- 最终构建若因依赖缓存/网络失败，必须如实记录；不得把环境失败报告为代码通过。
