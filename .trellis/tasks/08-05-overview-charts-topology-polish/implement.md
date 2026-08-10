# 首页图表与拓扑深度打磨实施计划

## Execution Rules

- 当前为 Codex inline 流程：用户批准本规划后运行 `task.py start`，再加载 `trellis-before-dev`；完成后加载 `trellis-check`。
- 以当前 dirty worktree 为基线。不得回退上一个 Overview 子任务或其他用户修改。
- 先完成全部相关编辑，再集中验证；失败后只重跑受影响检查。
- 不启动 Mica、不访问真实控制器、不运行 runtime smoke。临时文件统一放在 `tmp/codex/`，完成时移除 disposable artifacts。
- 不创建/推送 Git commit，不新增 package，不改部署 target 或 Swift tools version。

## Phase 1. Baseline And Trace

- [x] 记录本任务开始时 Overview 相关 diff，区分既有未提交修改与本任务增量。
- [x] 用 `rg` 复核 timeline sample -> projection -> runtime -> chart、connection catalog -> topology/index/layout -> Canvas -> accessibility 的完整路径。
- [x] 仅在 hot path 确实会改变且需要前后对比时运行 Release benchmark `before`；其余测试统一留到全部编辑完成后执行。

回退点：此阶段只读，不修改源码。

## Phase 2. Telemetry Hierarchy And Controls

- [x] 将 Telemetry header/controls 收敛为 regular/compact 两种宽度驱动布局，保留全部命令与三段 timeline 选择。
- [x] 保持三 panel 响应式 3 / 2+1 / 1 组合与稳定 200–260pt 响应式 plot geometry。
- [x] 删除上传/下载普通 footer 的 sample-count 噪音，保留真实 timestamp；连接图保留真实 memory context。
- [x] 保持 vectorized base charts、共享 traffic scale、selection overlay 和无 sample-driven 整图动画。
- [x] 核查 Swift Charts VoiceOver/Audio Graphs；仅在系统自动表示被压平时增加最小 chart descriptor/fallback。
- [x] 补齐新增/调整文案的英文与简体中文。

回退点：Telemetry 只修改现有组件和 localization；runtime/projection 数据语义不变。

## Phase 3. Stable Topology Interaction And Labels

- [x] 将 selection detail 移入 graph 的稳定 header/inset composition，确保 idle/hover/pinned/clear 不改变 graph 原点。
- [x] 保留唯一 path 的 Connections 导航，并保证 hover feedback 不抢占/移动 pointer target。
- [x] 删除固定 `7pt/character` reported-name 改写，改为实际字体/宽度感知的 Canvas text clipping/truncation。
- [x] 保证完整 reported value 在 stable detail、expanded path rows 和 accessibility fallback 中可见、可选择。
- [x] 保持完整 Sankey、列顺序、真实 count/ribbon width、unavailable path、无 nested scroll 和原有命中优先级。
- [x] 确认 hover/pin 只更新 highlight/detail，不重建 normalization/index/layout 或 base bands。

回退点：先完成稳定 detail，再独立完成 label rendering；任一部分可单独恢复现有实现。

## Phase 4. Focused Contracts And Large Fixtures

- [x] 更新 `WorkbenchOverviewPerformanceTests`，覆盖 compact control source contract、selection 不插入 graph sibling、base/highlight 分离和 font-aware label contract。
- [x] 扩展 topology deterministic fixture 至 2,000 connections，验证完整 paths、structure reuse、render-band coverage、local hit candidates 和 cancellation。
- [x] 保持现有 personalization/runtime identity tests 不变；只有预期 UI contract 改变时同步 source verifier。
- [x] 创建 `tmp/codex/hig-audit.json`，用 HIG batch 检查本任务涉及的实际文字/背景对比；28pt macOS pointer controls 按 Workbench 合同和定向 geometry/source 测试验证，不套用移动端 44pt 阈值。记录结果后删除该文件。

回退点：测试反映可观察合同，不保留只匹配实现细节的 tautological assertion。

## Phase 5. Consolidated Validation

按最小相关到完整范围依次运行：

```bash
swift test --filter WorkbenchOverviewPerformanceTests --scratch-path tmp/codex/swift-build
swift test --filter ConnectionTopologyTests --scratch-path tmp/codex/swift-build
swift test --filter WorkbenchOverviewPersonalizationTests --scratch-path tmp/codex/swift-build
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings >/dev/null
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
git diff --check
python3 ./.trellis/scripts/task.py validate 08-05-overview-charts-topology-polish
```

- [x] 使用当前安装的 `apple-hig-expert` checker 对 `tmp/codex/hig-audit.json` 运行 contrast batch 检查；项目本地 skill 路径若仍处于用户删除状态，不恢复它。
- [x] 只有 hot path 实际变化时运行 `scripts/run-performance-benchmarks.sh after` 并比较 matching cases。
- [x] 清理 `tmp/codex/swift-build`、HIG JSON 和可丢弃 benchmark 输出。
- [x] 运行 `trellis-check`，处理已验证问题；不修改无关 dirty files。
- [x] 执行 durable spec/docs pass；无新长期合同则记录原因。

## Final Review Gate

- [x] 用户已审核并明确批准本 PRD、设计和实施计划。
- [x] `task.py validate 08-05-overview-charts-topology-polish` 通过。
- [x] 任务经 `task.py start` 进入 `in_progress` 后才修改应用源码。
- [x] 完成时向用户明确说明未运行 runtime smoke，并请求其用真实控制器完成视觉/滚动手感验收。

## Verification Results

- `WorkbenchOverviewPerformanceTests`: 14 tests passed.
- `ConnectionTopologyTests`: 10 tests passed.
- `WorkbenchOverviewPersonalizationTests`: 22 tests passed.
- Full `swift test`: 299 tests in 27 suites passed.
- `swift build`, source verifier, localization JSON validation, `git diff --check`, task validation, and HIG contrast batch all passed; HIG score was 100 with no violations.
- No before/after benchmark was run because normalization, indexing, caching, render-band generation, and hit-candidate algorithms were unchanged; deterministic 2,000-connection contract tests cover the affected presentation path.
- Runtime smoke was intentionally not run. The task requires real-controller visual and scrolling acceptance by the user.
- `trellis-finish-work` was inspected, but the task remains active because its archive flow requires committing current-task changes and this task explicitly forbids commits.

## Phase 6. Overview Source Decomposition

- [x] 更新 PRD/design/task scope，明确 Dashboard、Telemetry、Topology view 和 Topology model/layout 的文件所有权。
- [x] 将 Instrument Rail 与完整 Telemetry 声明块机械迁移到 `WorkbenchOverviewTelemetry.swift`，只放宽 section 入口和跨文件共享 primitive 的访问级别。
- [x] 将完整 Topology SwiftUI/Canvas 声明块机械迁移到 `WorkbenchOverviewTopologyView.swift`，保持 geometry/cache 在 `WorkbenchOverviewTopology.swift`。
- [x] 更新 `workbench-ui-contract.md` 的精确文件清单和 ownership 说明。
- [x] 更新 source verifier 与 `WorkbenchOverviewPerformanceTests` 的文件读取边界，不弱化任何现有断言。
- [x] 运行 Overview/Topology 定向测试、source verifier、Swift build、完整 Swift tests、`git diff --check` 和 Trellis validate。
- [x] 清理拆分验证产生的 `tmp/codex/` 临时构建产物；不启动应用、不访问真实控制器、不提交或推送。

## Source Decomposition Verification

- `WorkbenchDashboard.swift`: 2,948 -> 886 lines.
- `WorkbenchOverviewTelemetry.swift`: 1,216 lines; owns Instrument Rail, telemetry controls, charts, and timeline interaction views.
- `WorkbenchOverviewTopologyView.swift`: 851 lines; owns topology workspace, render bands, hit/accessibility views, and Canvas drawing.
- `WorkbenchOverviewPerformanceTests`: 14 tests passed after updating file-boundary assertions.
- Full `swift test`: 299 tests in 27 suites passed after the split.
- Swift build, source verifier, localization JSON validation, `git diff --check`, and Trellis validation passed.

## Phase 7. Primary Canvas Scale Follow-up

- [x] 移除 Overview 根画布的 1180pt 阅读宽度上限，让图表与拓扑使用扣除页边距后的完整内容宽度。
- [x] 将三张主图的 plot 高度按有效 panel 宽度限制在 200–260pt，保留现有 3 / 2+1 / 1 响应式组合和全部交互。
- [x] 将稀疏拓扑 minimum flow height 按可用宽度限制在 560–760pt，保留密集拓扑自然增长和单一纵向滚动所有权。
- [x] 同步源码合同、项目 UI 合同与维护文档；运行定向 Overview 测试、source verifier、Swift build、`git diff --check` 和 Trellis validate。

## Primary Canvas Scale Verification

- `WorkbenchOverviewPerformanceTests`: 14 tests passed.
- `ConnectionTopologyTests`: 10 tests passed.
- Swift build, source verifier, `git diff --check`, and Trellis validation passed.
- Full tests were not rerun because this follow-up only changes local Overview presentation geometry and existing source contracts; runtime smoke remains intentionally skipped.

## Phase 8. Topology Interaction And UI Follow-up

- [x] 扩展 topology interaction snapshot，明确区分 hover 与 pinned，并在结构替换时清除已不存在的选择。
- [x] 增加有界完整路径步进与显式 clear intent；保持 controller path 顺序、完整路径集和 highlight cache 边界。
- [x] 在稳定 detail inset 中增加前后路径、固定/取消固定、清除和 Connections 命令，不改变 graph 原点或高度。
- [x] 将 graph 保持为单一 keyboard focus surface，增加方向键步进、Esc 清除和原生 context menu，不为 render band/node 引入焦点风暴。
- [x] 让展开路径与 accessibility fallback 只对真正 pinned 的路径报告 selected trait，并补齐英文/简体中文 label/help。
- [x] 仅在 highlight band 中减弱遮罩并为选中 ribbon 增加自适应轮廓；不修改 base Canvas、layout、hit index 或 controller 数据。
- [x] 同步定向 tests、source verifier、durable UI contract/docs，并集中运行 Overview/Topology 测试、Swift build、localization JSON、`git diff --check` 和 Trellis validate。

## Topology Interaction Verification

- `WorkbenchOverviewPerformanceTests`: 15 tests passed, including pinned-state and O(1) ordered-path navigation coverage.
- `ConnectionTopologyTests`: 10 tests passed, including the deterministic 2,000-connection complete-path fixture.
- Swift build, source verifier, localization JSON validation, `git diff --check`, and Trellis validation passed.
- HIG contrast batch scored 100 with no violations. The existing 28pt icon controls remain covered by the macOS pointer-control contract; every icon command has localized help and an accessibility label.
- Runtime smoke was intentionally not run. Real-controller pointer feel, focus-ring placement, and dense-topology scrolling remain user-run visual acceptance.

## Phase 9. Topology Visual Hierarchy Correction

- [x] 根据真实视觉反馈撤回 detail inset 内的前后路径、固定/取消固定和清除按钮，保留唯一 Connections intent。
- [x] 将 selection detail 从 80pt 嵌套强调卡片收敛为 64pt 无边框信息区，仅以 pin symbol 表达固定状态。
- [x] 将 highlight 遮罩从 0.58 降至 0.34，并减弱 node/ribbon 轮廓，保留完整 topology 上下文。
- [x] 保留直接点击、方向键、Esc、完整路径行、VoiceOver 和原生 context menu 的全部交互能力与 O(1) 路径步进。
- [x] 同步 source tests/verifier 与 durable UI contract，并运行定向测试、Swift build、source/localization/diff/Trellis 检查。

## Topology Visual Hierarchy Verification

- `WorkbenchOverviewPerformanceTests`: 15 tests passed, including compact detail geometry, pinned-state presentation, and O(1) ordered-path navigation coverage.
- Swift build, source verifier, localization JSON validation, `git diff --check`, and Trellis validation passed.
- The correction introduces no new color role, custom glass, nested card, dependency, data projection, or topology rebuild path. The existing macOS pointer geometry and localized accessibility contracts remain unchanged.
- Runtime smoke was intentionally not run. Real-controller visual balance, pointer feel, and dense-topology scrolling remain user-run acceptance.

## Phase 10. Primary Visual Scale Correction

- [x] 根据第二轮真实视觉反馈撤回整体压缩方向，保留去工具栏化的信息层级。
- [x] 将三张主图提升到 240–300pt 响应式 plot，并放大 Overview section 与 metric symbols。
- [x] 将稀疏 topology flow area 提升到 680–920pt，node bars/gaps/minimum readable height 提升到 20/8/20pt，列标题和节点标签改用 callout 尺度。
- [x] 将稳定 selection detail 恢复为 80pt，并放大文字与 pin symbol；不恢复前后/固定/清除常驻按钮。
- [x] 将首页 section/metric 图标统一为 34/28pt 原生层级色标，使用克制语义色和轻底色；密集行保持无底色图标。
- [x] 同步定向 tests、source verifier、durable UI contract/docs，并运行集中验证。

## Primary Visual Scale Verification

- `WorkbenchOverviewPerformanceTests`: 15 tests passed, including the dedicated 34/28-point hierarchical symbol-mark contract and the enlarged chart/topology geometry contracts.
- `ConnectionTopologyTests`: 10 tests passed, including the deterministic 2,000-connection complete-path fixture.
- The selected test build compiled the complete Mica target. Source verifier execution and syntax checks, localization JSON validation, `git diff --check`, and Trellis validation passed.
- Runtime smoke remained intentionally skipped. The user retains real-controller visual acceptance for symbol balance, chart scale, topology density, and pointer feel.

## Phase 11. Overview Coordination Follow-up

- [x] 让临时 chart hover 只更新 readout/indicator，只有 pinned sample 才把 header chrome 切换为 Selected。
- [x] 移除 topology 标题下重复的 command summary 和第二个 topology icon，将 pause/list 命令并入 section heading。
- [x] 使用固定 80pt detail inset 的 idle 状态显示真实连接数与 unavailable path 数，不改变 graph 原点、高度或 hit geometry。
- [x] 将 Overview section/category mark 统一为 informational cyan，保留 metric/data/status 的真实语义色。
- [x] 同步英文/简体中文、本任务设计、durable UI contract、source verifier 和定向 source-contract tests。
- [x] 集中运行 Overview/Topology 定向测试、Swift build、source/localization/diff/Trellis 检查并记录结果。

## Overview Coordination Verification

- `WorkbenchOverviewPerformanceTests`: 15 tests passed, including hover-versus-pin chrome state, unified section tint, topology header ownership, and idle-summary source contracts.
- `ConnectionTopologyTests`: 10 tests passed, including the deterministic 2,000-connection complete-path fixture.
- The selected test build compiled the complete Mica target; the final incremental `swift build` also passed.
- Source verifier syntax/execution, localization JSON validation, `git diff --check`, and Trellis validation passed.
- No new color token or content material was introduced. Existing informational cyan contrast and the prior HIG result remain applicable.
- Runtime smoke remained intentionally skipped. Real-controller visual balance, large-text wrapping, VoiceOver/Audio Graph behavior, and pointer feel remain user-run acceptance.
