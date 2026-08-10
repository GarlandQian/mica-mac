# Overview 原生监控工作台实施计划

## Implementation

- [x] 移除 Overview row 的滚动入场动画，并移除三张实时图表的 sample-driven 隐式动画。
- [x] 将 telemetry 三张图收敛为一个连续监控表面，保留宽/中/窄响应式布局与完整交互。
- [x] 调整拓扑摘要、选择详情和画布纵向节奏，保持完整宽度适配、路径交互和同窗展开。
- [x] 将网络信息整理为紧凑的分组定义布局，保持真实字段、顺序、可选择文本和大字号换行。
- [x] 补充 Overview source/performance 测试与 source verifier，防止入场动画、整图 sample 动画和卡片墙回归。

## Validation

- [x] `node --check scripts/verify-real-controller-source.mjs`
- [x] `node scripts/verify-real-controller-source.mjs`
- [x] `python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings`
- [x] `swift test --filter WorkbenchOverviewPerformanceTests --scratch-path tmp/codex/swift-build`
- [x] `swift test --filter WorkbenchOverviewPersonalizationTests --scratch-path tmp/codex/swift-build`
- [x] `swift test --filter ConnectionTopologyTests --scratch-path tmp/codex/swift-build`
- [x] `swift build --scratch-path tmp/codex/swift-build`
- [x] `swift test --scratch-path tmp/codex/swift-build`
- [x] `git diff --check`
- [x] `python3 ./.trellis/scripts/task.py validate 08-04-overview-native-monitoring-workspace`
- [x] 清理 `tmp/codex/swift-build`

## Review Gate

- [x] 父任务和 Phase 2 范围已获用户批准。
- [x] 子任务通过 Trellis validate 并激活后才修改应用源码。
- [x] 未引入 controller/session/API 行为变更；未启动应用、访问控制器或运行 runtime smoke。

## Rollback Points

- 先完成 telemetry/animation 切片，再调整 topology/network facts；失败时只回退本任务新增代码。
- 不触碰 Phase 1 已完成的 shell/settings 文件和父任务其他阶段内容。
