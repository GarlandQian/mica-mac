# Design: 概览流向彩带与双模式视觉焕新

## 1. 架构决策

渲染层 + token + 一处几何排序。几何引擎仅改列内节点排序（§3.5）；列分配/band 拆分/命中索引/labelRect 零改动；`OverviewTopologyBandLayers` 三层结构（Base Canvas + LabelBand + HitBand）与遥测门禁（policyStatusRevision + runtime memo）原样保留。渐变只出现在 BaseBand 的边描边，绘制次数不变（两遍 pass），仅把 `context.stroke(..., with: .color(...))` 换成 `.linearGradient(...)`。

## 2. 列身份色 token 表（待用户过目）

新增 `MicaTheme.ColumnTint`（全部经 `Color(micaLight:dark:)` 动态适配）：

| 列 | 语义 | Light | Dark | 色相 |
|---|---|---|---|---|
| 来源 | source | `#5B7089` | `#7E93B0` | 石板蓝 ~215° |
| 命中规则 | rule | `#9A7B4F` | `#C4A876` | 暖沙 ~38° |
| 代理链（全部 hop） | policyHop | `#7A68AC` | `#A495D6` | 灰紫 ~262° |
| 链出口 | finalOutbound | `#A85F74` | `#CE8499` | 灰玫瑰 ~345° |

避让论证：accent 青绿（#0B8F66/#34D1A3）与状态色（systemGreen/Orange/Red）均为高饱和；四个列色全部降饱和 + 错位色相，暖沙 vs statusOrange（#9A7B4F 偏棕褐、系统橙鲜亮）与灰玫瑰 vs systemRed（灰玫瑰低饱和偏粉）在 1–2.5pt 线宽上可区分。

辅助 token：
- `MicaTheme.edgeDimmed`（选中态非主路径的雾色）：light `rgb(0x14181D)` 16% alpha / dark `rgb(0xE8ECF1)` 14% alpha——显式带 alpha，不依赖 tertiaryLabelColor（修 R5）。
- `MicaTheme.nodePillStroke` 不使用全局 token：直接用各列色 50% alpha。

映射（`OverviewTopologyProjection.tint(for:)`）：`.source→source`、`.rule→rule`、`.policyHop(_)→policyHop`、`.finalOutbound→finalOutbound`。

## 3. sliceWidth 闭合公式（修标题叠字 bug）

对每个列 i（centerX 已减 band.origin.x，带宽 W）：

```
slice_i = max(1, min(W, 2·cx_i, 2·(W − cx_i), distLeft_i, distRight_i) − gutter)
gutter = 8
```

- `2·cx_i` / `2·(W − cx_i)`：保证 clampedCenter 不会把中心内推（half ≤ cx 且 half ≤ W−cx → clamp 为恒等），消除边缘列与邻居相撞的路径。
- `distLeft/distRight`（到相邻列中心距离）：保证相邻 box 不重叠（两半宽之和 ≤ 间距）。
- gutter 保证视觉间隙；clamp 逻辑（clampedCenter）不变，slice > W 退化仍居中。

验证基准（800 宽、中心 60/230/400/570/740）：slice = 112/162/162/162/112 → box 4..116、149..311、319..481、489..651、684..796，互不重叠且全部在界内。单测按此重写。

## 3.5 流向排序（barycenter 前向 pass）

排序点：`columnPlans` 构建处（WorkbenchOverviewTopology.swift ~846，现为 `column.nodes.sorted(by: sankeyNodeOrder)`）。

算法：
1. 第 0 列：`sankeyNodeOrder`（名字序）不变。
2. 第 k 列（k≥1）：每个节点的排序键 = 全部入边源节点的 slot 下标按边流量（`edgeFlowByID`）加权平均；无入边节点键 = +∞（沉底）。
3. 排序比较：键升序，键相同回退 `sankeyNodeOrder`（确定性）。
4. 逐列处理时维护 `slotByID`（节点 → 其在已排序列中的下标）；跨列边（如 source 直连 final）天然支持，因为源列总是先处理。

派生跟随：y 槽位由排序后的数组顺序累加得出（现有 `nextY` 逻辑不变），边端点/labelRect/命中矩形全部从 nodeRects 派生——零额外改动。

测试同步：断言名字序的既有测试改为断言流向序；新增 AC7 交叉场景与确定性单测。

## 4. 绘制规范

**边（drawEdge，优先级从高到低）：**
1. 选中/悬停路径：accent 实色，线宽 = flow 宽 +1。
2. 状态边（触达携带上报状态的策略节点）：状态色 0.85 alpha 实色（契约：状态色只来自上报）。
3. 默认态：源列色 → 目标列色线性渐变（`Gradient(colors: [src.opacity(0.55), dst.opacity(0.55)])`，双模式统一 0.55），渐变轴沿 edge.source→edge.target（贴合流向），线宽 = flow 宽（0.75–2.5 clamp 不变）。tint 表由 BandLayers 从全量 layout.nodes 构建（跨 band 边共享端点色，F1 修复）。
4. 选中态存在但本边不在路径上：`edgeDimmed` 实色。

**节点（drawNode）：**
1. 选中：accent 填充。
2. 状态节点：状态色填充（选中态中未选中则 0.4 alpha）。
3. 中性：列色 14% 填充 + 列色 55% 1pt 描边；dim 时降为 7% / 25%。（实现定稿 55%，双模式实测可辨）

**列头（LabelBand + Canvas）：**
- LabelBand 标题：Text 不变（.label semibold textSecondary，slice+clamp 用新公式）。
- Canvas 画列色刻线（面板底填充之后、边之前；刻线在标题带 y<40，与边区不重叠）：每列一条 `RoundedRectangle` 22×2.5pt（圆角 1.25，rect y = columnHeaderHeight − 6），fill = 列色 0.85 alpha，x 中心 = clampedCenter。

**脉冲摘要条（WorkbenchConnectionPulseView）：**
- `WorkbenchConnectionPulseMetric`：去掉 `.frame(maxWidth: .infinity)`，改 `.fixedSize()`（值与 detail 行均不截断）；父 HStack 保持 leading 排布 + `Spacer()`，分布条 `WorkbenchConnectionOwnerDistribution` 加 `.frame(maxWidth: 420)`。

## 4.5 R9 真 Sankey 彩带（2026-08-23 定稿）

社区调研（ECharts/D3/Google Charts/reflex.dev sankey 指南）共识：流量图 = 宽度∝流量的**填充带**，链路透明度 0.4–0.6，源节点色贯穿链路，节点实心色块锚定。我们的几何引擎本就是真 Sankey（edge.width = flow×valueScale、assignEdgeCenters 把边按其宽度打包进节点矩形、命中容差 width/2+2）——细描边渲染才是异常。

drawEdge（替换 §4 描边实现）：
- 闭合 ribbon Path：上边 = (source.y−half)→(target.y−half) 贝塞尔（控制点 −half），目标侧直线闭合，下边 = 返程贝塞尔（控制点 +half，control2/control1 顺序互换）；half = max(edge.width, 1.5)/2（视觉地板，数据宽度 ≥1 几乎不动比例）。
- 填充优先级：选中 accent 0.85 → dimmed edgeDimmed → 状态色 0.7 → 渐变（src/dst tint 各 0.45，轴向 source→target）。
drawNode：中性节点实心列色块（无描边），dim 0.35；状态/accent 不变。
列头刻线保留（列身份锚）。

## 5. 兼容与验证

- Equatable 门禁、memo、HitBand、tooltip、inspector 同步、无障碍表征全部不动（行为 AC4 由既有测试 + verifier 锁定）。
- verifier 同步：新增渐变/列色 token/刻线断言；保留 opaque/linear、单 Canvas、clampedCenter 断言（sliceWidth 断言更新）。
- 单测：sliceWidth 基准重写（§3 数值）+ 单列/超宽退化保留。
- 性能：`MicaPerformanceBenchmarkTests` 全绿；若拓扑指标回退 >5%，边降级为源列纯色渐变（同 token，去渐变）。
- 契约文档 `.trellis/spec/frontend/workbench-ui-contract.md` 拓扑段同步（列身份色、渐变彩带、刻线、摘要条、流向排序——替换「nodes sort by reported name」描述）。
- 回滚：`git revert` 到 7b6d651。

## 6. 不做

- 不做发光/辉光/阴影；渐变仅限边的流向编码。
- 不改遥测图表、几何引擎、交互状态机。
- 不引入新依赖。
