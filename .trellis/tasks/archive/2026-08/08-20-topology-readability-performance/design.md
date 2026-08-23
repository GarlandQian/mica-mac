# Design: 拓扑视图可读性与性能返工

## 1. 架构决策

只改渲染层（`WorkbenchOverviewTopologyView.swift`）+ runtime 状态缓存（`WorkbenchOverviewWindowRuntime.swift` 的 `OverviewTopologyRuntime`）；几何引擎 `WorkbenchOverviewTopology.swift` 零改动（列分配/band/命中索引/labelRect 全部保留）。

### 1.1 绘制层重组（每 band）

现状三层：BaseBand Canvas（边+列标题+节点+全部文字）→ HighlightBand（全尺寸遮罩 + 第二 Canvas）→ HitBand。

改为两层 + 文字层：

1. **BaseBand（单 Canvas，`opaque: true`，`colorMode: .linear`，`rendersAsynchronously: true`）**
   - 画面板底色（canvas token 直接填充 band bounds → 允许 opaque）。
   - 两遍画边：先全部非选中边（分层着色，见 §2），若存在 activeSelection 再以 accent 叠画选中边；选中态不需要第二 Canvas/遮罩。
   - 画节点柱（§2）。
   - 不再画任何文字。
   - 绘制闭包接收已解析好的静态输入（颜色/线宽表），不做 Text resolve。
2. **LabelBand（普通 SwiftUI 视图层，`ZStack` + 绝对定位 Text，`.allowsHitTesting(false)`，`.accessibilityHidden(true)`）**
   - 列标题：`Text` 用 `micaThemeFont(.label, weight: .semibold)` + textSecondary，x = clamp(column.centerX, titleHalfWidth, bandWidth − titleHalfWidth)（修 R4）。
   - 节点标签：`Text(verbatim:)` + `micaThemeFont(.label)` + textPrimary，定位完全沿用 `labelRect`/`labelSide`（leading → 左对齐于 labelRect.minX；trailing → 右对齐于 labelRect.maxX，`lineLimit(1)` 截断由系统处理）。
   - 系统文本渲染管线自带缓存；只在 band 输入变化时重排。
3. **HitBand**：原样保留（命中索引来自几何引擎，与绘制层无关）。

删除 `OverviewTopologyHighlightBand` 类型（合并进 BaseBand），删除全尺寸 canvas 遮罩。

### 1.2 重绘门禁（R5）

- `OverviewTopologyBandLayers` 的 Equatable 输入收敛为：`request`（generation/revision/width/minHeight）、`band.id`、`language`、`fontScale`、`policyStatusRevision: UInt64`、`allowsMotion`、`interaction`（引用）。
- `nodeStatusByID` 从计算属性改为 **runtime memo**：`OverviewTopologyRuntime` 增加 `@ObservationIgnored private var nodeStatusCache: (policyRevision: UInt64, topologyRevision: UInt64, map: [String: MicaTheme.Status])?`，方法 `nodeStatuses(topology:policyRevision:)` 仅在 key 变化时重算。视图 body 调用该方法；band `==` 比较 `policyStatusRevision`（UInt64）而非字典。
- 效果：遥测样本刷新（不改 topology revision / policy revision）→ request 不变 → `==` true → 零重绘；延迟目录回流只翻转 UInt64 比较，状态图 memo 命中时不重算。

## 2. 视觉规范（Mica Ops 契约内）

| 元素 | 规格 |
|---|---|
| 非活跃边 | `textTertiary.opacity(0.5)`，线宽 = `max(edge.width, 0.75)`（geometry 已按 flow 计算 width，恢复使用，封顶 2.5） |
| 状态边 | 边的 target（或 source）为携带控制器上报状态的策略节点时，用该状态色 opacity 0.85，线宽同上 |
| 选中/悬停边 | accent 全强度，线宽 = base + 1 |
| 中性节点 | `surfaceRaised` 填充 + `textTertiary` 1pt 描边（关键修复：描边色从 separator 提升到 textTertiary，近黑画布上可辨） |
| 状态节点 | 状态色填充（不变） |
| 选中节点 | accent 填充（不变） |
| 列标题 | textSecondary / .label semibold / clamp 到 band 内 |
| 节点标签 | textPrimary / .label |

无新色板、无辉光/渐变；accent 仍只服务选中/活跃；状态色仍只来自控制器上报。

## 3. 兼容与验证

- verifier：同步删除/改写 `OverviewTopologyHighlightBand` 相关断言；新增 opaque/linear、单 Canvas、标签层 `.allowsHitTesting(false)`、header clamp 断言。
- 新增单测：`OverviewTopologyDrawing.clampedHeaderCenter(titleWidth:columnCenterX:bandWidth:)` 边界（最短/最长中英文标题 × 最左/最右列）。
- 全量测试 + `MicaPerformanceBenchmarkTests` 不回退。
- 回滚：`git revert` 到 f542178。

## 4. 不做

- 不改几何引擎、命中索引、交互状态机、暂停/冻结逻辑。
- 不动 telemetry 面板、不动其它目的地。
