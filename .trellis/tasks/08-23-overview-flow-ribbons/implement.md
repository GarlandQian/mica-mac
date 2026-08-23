# Implement: 概览流向彩带与双模式视觉焕新

回滚点：7b6d651。全程 `swift build --scratch-path tmp/codex/swift-build`；verifier 用绝对路径 node：`"/Users/garland/Library/Application Support/com.raycast.macos/NodeJS/runtime/22.22.2/bin/node" scripts/verify-real-controller-source.mjs`。

## Phase 1 — Token 与几何修复

- [x] 1.1 `MicaTheme.swift`：新增 `ColumnTint`（source/rule/policyHop/finalOutbound 双模式四色，design.md §2 表）+ `edgeDimmed`；rgb helper 支持 alpha（新增 `rgba(_ hex:alpha:)` 或 withAlphaComponent）。
- [x] 1.2 `WorkbenchOverviewTopology.swift`：`sliceWidth` 按 design.md §3 闭合公式重写（含 2·cx、2·(W−cx)、邻距、gutter=8）；新增 `OverviewTopologyProjection.tint(for:)` 列色映射。
- [x] 1.3 重写 `topologyHeaderGeometryClampsTitlesInsideBand` 单测断言为 §3 基准值（112/162/162/162/112 与 box 不等式）；保留退化用例。
- [x] 1.4 流向排序：columnPlans 构建处改为前向 barycenter（design.md §3.5）；新增 AC7 交叉场景 + 确定性单测；同步既有断言名字序的测试。

## Phase 2 — 渲染焕新

- [x] 2.1 `drawEdge` 四优先级（选中 accent / 状态色 / 列色渐变 / edgeDimmed），渐变沿 boundingRect 横向。
- [x] 2.2 `drawNode` 中性节点列色 14% 填充 + 50% 描边（dim 7%/25%）。
- [x] 2.3 BaseBand 末尾画列头刻线（22×2.5 圆角，列色 0.85，中心对齐 clampedCenter，y = columnHeaderHeight − 4）。
- [x] 2.4 `WorkbenchConnectionPulseView.swift`：metric 去等宽 frame 改 fixedSize；分布条 maxWidth 420。
- [x] 2.5 build 绿。
- [x] 2.6 R9 彩带化：drawEdge 闭合 ribbon Path + 渐变填充（design.md §4.5）；中性节点实心列色块；契约/verifier 同步；门禁重跑。

- [x] 2.7 R10 长链防截断：minimumColumnStep=168 + 图加宽 + 横向滚动；新增 7 列/短链宽度单测；契约/verifier 同步。

## Phase 3 — 验证与同步

- [x] 3.1 全量测试 + MicaPerformanceBenchmarkTests + verifier 绿（verifier 断言同步：渐变、列色、刻线、fixedSize、maxWidth）。
- [x] 3.2 workbench-ui-contract.md 拓扑段 + 脉冲段同步。
- [x] 3.3 trellis-check 对照 PRD 终审（重点：渐变回退条件、状态色契约、双模式 token、排序确定性）。
- [ ] 3.4 用户目验（浅色 + 深色截图）→ 提交归档。
