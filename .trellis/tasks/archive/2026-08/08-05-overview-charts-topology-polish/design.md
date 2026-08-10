# 首页图表与拓扑深度打磨设计

## 1. Evidence And Design Direction

本任务沿用当前 Workbench monitoring-canvas archetype，不创建第二套 Dashboard。仓库内的 `workbench-ui-contract.md`、`docs/UI_GUIDELINES.md`、现有源码与测试是实现事实来源。

外部设计依据：

- Apple Charts HIG: https://developer.apple.com/design/human-interface-guidelines/charts
- Apple Charting Data HIG: https://developer.apple.com/design/human-interface-guidelines/charting-data
- Activity Monitor network reference: https://support.apple.com/guide/activity-monitor/view-network-activity-actmntr1006/mac

这些资料共同支持四个取向：数据 mark 优先于装饰与轴；紧凑宽度优先保护 plot；交互用于深入检查但不能成为理解关键状态的唯一方式；实时图表旁只保留少量明确的模式和状态控制。

## 2. Existing Architecture And Boundaries

数据流保持：

`generation-owned AppModel timelines/catalog -> Overview projection/cache -> per-window runtime -> Swift Charts / Canvas -> interaction overlay`

- `OverviewTelemetryModuleRuntime` 继续拥有 projection cache、timeline window、pause 和共享日期选择。
- `OverviewTopologyModuleRuntime` 继续拥有 presentation cache、pause、展开状态和交互状态。
- `OverviewTimelineProjectionCache` 继续负责窗口裁剪、downsample 和合并日期；View 不复制这些工作。
- `OverviewTopologyPresentationCache` 继续按 generation + structure revision 构建 topology/index，按 width 构建 layout。
- `OverviewTopologyLayoutBuilder` 继续在并发执行域内计算 geometry、render bands 和 hit index。
- SwiftUI View 只组合已投影数据和发出 intent，不新增 timer、网络请求或平行状态源。

本任务不改变 timeline/capability/session/publication 合同，也不修改 personalization persistence。

## 3. Telemetry Design

### 3.1 Header And Controls

`OverviewTelemetryControls` 拆成语义清楚的三组：presentation state、sample navigation、timeline mode。使用 `ViewThatFits` 或等价的两级组合：

- regular：标题、状态和全部控制在一个水平 header；
- compact：标题/状态为第一行，命令和三段 timeline picker 为第二行。

两种组合调用同一 runtime intent，不复制状态。28pt icon command 保持稳定，timeline picker 不因字号改变业务值。控件换行只由实际宽度驱动。

### 3.2 Chart Surface

三张图继续位于一个连续 surface，宽屏 3 列、中屏 2+1、窄屏 1 列。每个 panel 的稳定层级为：

1. metric symbol + title；
2. current/selected monospaced value；
3. 按实际 panel 宽度在 240–300pt 内响应式增长的 plot；
4. selected/current timestamp，以及连接图真实 memory context。

首页标题图标采用一个原生 `OverviewSymbolMark`：section 为 34pt，metric 为 28pt，使用 SF Symbols hierarchical rendering 和单层低透明语义色底，不加玻璃、阴影、装饰渐变或自绘 SVG。所有 section/category mark 统一使用信息 cyan，避免把 Topology/optional summary 的 violet 误读为 debug/trace、把 Network information 的 mint 误读为健康状态；metric 和状态继续使用对应的真实系列/状态色。上传与下载以斜向箭头和文字共同表达方向。密集状态、路径和事实行保留无底色单色符号，避免把每行变成小卡片。

上传/下载普通 footer 删除 `real_samples_count`，避免将内部投影数量当作用户结论。样本为空时继续使用准确 empty state。

Base chart 保持 vectorized plots 和 `Equatable` 边界。Shared selection indicator 与 transparent plot-wide interaction overlay 留在独立层；hover/keyboard 只变更 `OverviewTimelineInteractionState`。

Overview 根画布不再套用管理页的 1180pt 阅读宽度上限。扣除响应式页边距后，Telemetry 和 Topology 使用完整可用宽度；其他模块仍按既有顺序位于其后。

### 3.3 Accessibility

先验证当前外层 `.accessibilityLabel/.accessibilityValue` 是否压平 Swift Charts 自动 marks/audio graph。若会压平，则用最小 `AXChartDescriptorRepresentable`/`accessibilityChartDescriptor` 恢复完整序列；否则保留系统自动表示，只补充明确的 purpose 和 current/selected summary。不得为每个实时样本创建额外 SwiftUI row。

## 4. Topology Design

### 4.1 Stable Interaction Geometry

当前 `OverviewTopologySelectionDetail` 作为 graph 前的条件 sibling 出现。设计将选择反馈并入 topology graph 的稳定 header/inset 区域，graph node/ribbon 的坐标原点在 nil/hover/pinned 三种状态间保持不变。

- idle：在固定 detail inset 内显示真实连接数和不可用路径数，不显示教学文案或第二个拓扑图标；
- hover：显示完整选择 label/description，但 detail 不参与 graph 外部布局；
- pinned：保持相同位置，并在唯一 path 时提供 Connections intent；
- clear：只清空 detail，不移动 graph。

具体 composition 可以是 graph 内 stable overlay/inset，但必须满足：不遮住实际 node/ribbon、pointer target 不因 detail 出现而移动、长文本不会与 controls 重叠。

### 4.2 Labels And Complete Values

删除 `displayLabel(_:availableWidth:)` 的固定 7pt 字符近似。Canvas 直接消费未修改的 reported name，并按实际 resolved font、font scale 和 `labelRect` 做 tail clipping/truncation。不得构造带 `...` 的替代业务字符串。

紧凑 graph 可以只显示可容纳的 tail-truncated visual label，但完整原值必须同时存在于：

- stable selection detail；
- expanded full path rows；
- accessibility fallback。

这样既保留完整业务数据，又不让大字号或长 CJK/endpoint 名称侵入下一列。

### 4.3 Rendering And Hit Testing

保留四层分工：

- base band：异步绘制 columns、nodes、ribbons、labels；
- highlight band：只观察 active highlight；
- hit band：只执行 indexed point lookup；
- accessibility representation：按 32-path group 延迟构造完整 routes。

结构、颜色和宽度语义不变。任何 label 调整不得把 label hit rect 扩展到下一列，也不得改变 visible-node > ribbon > label-padding 的命中顺序。

稀疏 graph 的 minimum flow height 按可用宽度以 0.56 比例计算，并限制在 680–920pt；node bars 增至 20pt、gaps 增至 8pt、minimum readable node 增至 20pt，列标题与节点标签使用 callout 尺度。密集列继续由既有 minimum-readable-node 算法自然增高。这个调整只改变 presentation request 与绘制几何，不改变路径、聚合、缓存 key 或命中算法。

### 4.4 Native Selection Commands

`OverviewTopologyInteractionSnapshot` 显式区分临时 hover 与 pinned selection。稳定 detail inset 使用 80pt 无边框信息区：idle 显示真实连接数和不可用路径数，选择后切换为完整 label/description、固定状态的 pin symbol，以及唯一真实路径的 Connections intent。暂停和完整路径命令位于 section header，详情不再承载前后路径、固定/取消固定或清除按钮，避免在 topology content 内形成第二条工具栏。

整个 graph 是一个 native focusable surface，而不是为每个 352pt render band 或每个 node 创建焦点。方向键通过 topology index 的 ordered path ID/index map，在 controller 顺序的完整 paths 上做 O(1) 有界步进并固定结果，Esc 清除本地选择；原生 context menu 镜像相同命令。展开路径行与 accessibility fallback 只有在路径真正 pinned 时才暴露 selected trait，临时 pointer hover 只保留视觉高亮。

选中高亮继续只重绘 highlight band。遮罩降低至 0.34，节点/ribbon 轮廓同步减弱，在保留完整上下文的同时区分当前 trajectory；base Canvas、空间命中索引、缓存 key 和 controller 数据不变。

## 5. Performance Plan

先以现有 operation-count tests 建立基线，再只修复已证明的问题：

- metrics-only request 必须 exact-hit 或 structure-reuse，不做 normalization/index/layout；
- hover/pin 只更新 highlight cache 和 selection detail；
- width 变化继续取消旧 task，旧 generation/layout 不得 publish；
- render band admission 覆盖完整 graph，并保持 node/edge 顺序；
- hit test 只扫描当前 spatial cell 的本地候选；
- 2,000-connection shared-route fixture 验证线性 normalization、完整 path membership 和有界 layout/hit behavior。

不加入基于 wall-clock 的脆弱单元测试。若本地 Release benchmark 显示本任务改变 hot path，则使用 `scripts/run-performance-benchmarks.sh before/after` 留下离线对比；否则不制造无意义 benchmark churn。

## 6. Files And Ownership

主要实现边界：

- `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift`：Overview 根组合、module layout、optional summaries、network facts 和共享格式化。
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTelemetry.swift`：Instrument rail、Telemetry header/controls、三张 charts、base plots 和 selection overlays。
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift`：Topology section/workspace、render bands、hit/accessibility views 和 Canvas drawing。
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopology.swift`
- `Sources/Mica/Features/Workbench/WorkbenchOverviewProjection.swift`（仅当 accessibility/interaction projection 需要）
- `Sources/Mica/Features/Workbench/WorkbenchOverviewRuntimes.swift`（仅当稳定 runtime 状态需要）
- `Sources/Mica/Resources/Localizable.xcstrings`
- `Tests/MicaTests/WorkbenchOverviewPerformanceTests.swift`
- `Tests/MicaTests/ConnectionTopologyTests.swift`
- `Tests/MicaTests/WorkbenchOverviewPersonalizationTests.swift`（只做回归验证）
- `scripts/verify-real-controller-source.mjs`

不通过本任务整理其他 Workbench 文件或当前 79 项无关 dirty changes。

新增的两个 View 文件是 feature-sized ownership boundaries，不按小组件继续拆文件。机械迁移保留原声明顺序与实现内容；只有跨文件入口从 `private` 调整为 module-internal。`WorkbenchOverviewTopology.swift` 保持 view-free geometry/cache ownership，避免 layout hot path 与 SwiftUI composition 再次混合。

## 7. Compatibility And Rollback

- Swift 6.2、macOS 27 和 SwiftPM targets 保持不变。
- 不增加数据迁移、偏好 key 或 controller compatibility 分支。
- Telemetry controls、chart accessibility、topology stable detail/labels 分成独立切片；任一切片失败可回到现有 UI，而不回退别的用户修改。
- 若自定义 chart descriptor 与系统自动 Audio Graphs 冲突，回退到系统自动表示并只保留 summary label/value。
- 若 font-aware Canvas label 影响 base-band 性能，保留完整未修改字符串和 stable detail，采用 resolved-text clipping 的最小路径，不引入每节点 SwiftUI overlay。

## 8. Durable Documentation

只有实现形成新的跨任务合同，才更新 `workbench-ui-contract.md` 或 `docs/UI_GUIDELINES.md`。如果只是让源码重新满足现有合同，则完成时记录 `No durable docs change`，不重复任务说明。
