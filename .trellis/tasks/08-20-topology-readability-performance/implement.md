# Implement: 拓扑视图可读性与性能返工

回滚点：f542178。全程 `swift build --scratch-path tmp/codex/swift-build`。

## Phase 1 — Runtime 状态 memo（R5）

- [x] 1.1 `OverviewTopologyRuntime` 增加 `@ObservationIgnored private var nodeStatusCache` + `nodeStatuses(topology:policyRevision:)` 方法（key = policyRevision + topology 节点集 revision，命中直接返回）。
- [x] 1.2 `WorkbenchOverviewTopologyView.nodeStatusByID` 计算属性改为调用 runtime 方法；body 传入 `appModel.policyGroupCatalogRevision`。

## Phase 2 — 绘制层重组（R1–R4、R6、R7）

- [x] 2.1 `OverviewTopologyDrawing` 增加纯函数 `clampedHeaderCenter(titleWidth:columnCenterX:bandWidth:)`。
- [x] 2.2 BaseBand 重写：`opaque: true` + `colorMode: .linear`；先画底色；两遍画边（非选中层 + 选中 accent 层，状态边按节点状态着色）；画节点（中性 surfaceRaised + textTertiary 1pt 描边）；不画文字。
- [x] 2.3 新增 LabelBand（ZStack 定位 Text，`.allowsHitTesting(false)`、`.accessibilityHidden(true)`）：列标题 clamp 居中；节点标签按 labelRect/labelSide。
- [x] 2.4 删除 `OverviewTopologyHighlightBand`；BandLayers 重组为 Base+Label+Hit，`==` 改比较 `policyStatusRevision: UInt64`。
- [x] 2.5 build 绿。

## Phase 3 — 验证与同步

- [x] 3.1 新增 clampedHeaderCenter 边界单测。
- [x] 3.2 verifier 断言同步（删 HighlightBand 断言；新增 opaque/linear/单 Canvas/标签层断言）。
- [x] 3.3 全量测试 + MicaPerformanceBenchmarkTests + verifier 全绿。
- [x] 3.4 `.trellis/spec/frontend/workbench-ui-contract.md` 拓扑段同步。
- [x] 3.5 trellis-check 对照 PRD 终审 → 提交。
