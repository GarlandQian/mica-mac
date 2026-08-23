# PRD: 拓扑视图可读性与性能返工

## 背景

08-17 全局重构交付的 Mica Ops 扁平拓扑视图在真实数据下被用户判定「又丑又卡」（2026-08-20 真实截图反馈）。具体问题：整图发暗发灰、几十条边线同色同宽无法区分、中性节点在近黑画布上几乎不可见、最右列标题「代理链出口」被裁断、实时刷新时明显卡顿。

## 已确认根因（代码核实）

1. **边线**：所有非高亮边统一 `MicaTheme.textSecondary` + 1.5pt，无语义分层（WorkbenchOverviewTopologyView.swift drawEdge）。
2. **中性节点**：填充 `surfaceRaised`（#1C1F23）画在 `canvas`（#0D0E10）上，亮度差 ~4%，肉眼不可见。
3. **文字**：列标题 textSecondary；节点标签在 `colorMode: .nonLinear` Canvas 内 resolve，渲染发闷。
4. **截断**：列标题以 `column.centerX` + `anchor: .center` 绘制，未 clamp 到 band 边界，右列标题超出面板被 clipShape 裁断。
5. **卡顿 A**：`nodeStatusByID` 为计算属性，每次 body 求值全节点重算（policy index resolve × N 节点），且随 policy 目录 revision（延迟测试持续回流）变化 → 所有 band 的 Equatable `==` 失效 → 全部 Canvas 整层重绘。
6. **卡顿 B**：base Canvas `opaque: false` + `colorMode: .nonLinear`，最贵合成组合；选中态再叠全尺寸半透明遮罩 + 第二个 Canvas（两层同时合成）。
7. **卡顿 C**：所有文字标签在 Canvas 闭包内逐个 `resolve(Text)` + 测宽，每次重绘重复。

## 目标

在保留全部产品行为（真实数据、悬停 tooltip、点击→检查器、键盘可达性、命中测试、冻结逻辑、无障碍表征）的前提下，让拓扑视图在真实繁忙控制器数据下**可读**（边/节点/文字层次分明）且**流畅**（常规遥测 tick 不触发拓扑重绘；结构变化时单层绘制）。

## 非目标

- 不改拓扑几何引擎的布局算法（列分配/band 拆分/命中索引保留）。
- 不改其它页面；不改控制器/数据层。
- 不恢复霓虹/辉光/HUD（08-17 AC1/AC3 仍然有效）；状态色仅用于控制器上报状态的契约不破。

## 需求

- R1 边线语义分层：非活跃边用 separator 级低透明细线退到背景；携带控制器上报状态的策略节点其关联边用对应状态色；选中/悬停路径用 accent。任意时刻屏幕上有且仅有一条视觉主导路径组（选中态）。
- R2 节点可见性：中性节点填充与画布拉开可辨层级（surface + 明确描边）；状态节点保持状态色填充。
- R3 文字可读：列标题与节点标签使用 textPrimary/textSecondary 正确层级，渲染清晰（不移入非线性 Canvas 合成）。
- R4 修复右列标题截断：所有列标题完整显示于面板内。
- R5 遥测 tick（流量数据刷新、延迟目录更新）不触发拓扑 Canvas 重绘；仅拓扑结构 revision / 尺寸 / 语言 / 字阶 / 交互选择变化才重绘。
- R6 绘制合成减负：消除选中态第二 Canvas 与全尺寸遮罩层；base Canvas 使用不透明/线性合成。
- R7 标签绘制不再随重绘重复 resolve+测宽。

## 验收标准

- AC1 截图级可读性：默认态下中性节点柱清晰可辨、边线退居背景不糊团、文字为主文本色；选中态主导路径唯一且醒目。
- AC2 右列标题（含最长标题「代理链出口」中英文）在最小/典型/最大面板宽度下完整显示（源码断言 + 布局边界单测）。
- AC3 重绘门禁：构造固定 presentation，仅翻转 policy 目录 revision / 遥测样本时，`OverviewTopologyBandLayers` 的 `==` 保持 true（Equatable 输入不含每 tick 变化的值）；base Canvas 为 `opaque: true` + `colorMode: .linear`；选中态不存在第二个 Canvas/全尺寸遮罩（源码断言）。
- AC4 既有行为全保留：悬停 tooltip、点击→检查器（7 case）、键盘选择、命中测试、暂停/悬停冻结、无障碍表征、空/不可用状态；`swift build` + 全量测试 + `node scripts/verify-real-controller-source.mjs` 绿。
- AC5 Mica Ops 契约不破：accent 仅选中/活跃、状态色仅上报状态、无辉光/渐变装饰、`.trellis/spec` 描述同步。
- AC6 性能基准：`MicaPerformanceBenchmarkTests` 全绿且拓扑相关指标不回退。

## 风险

- WorkbenchOverviewTopologyView.swift 是 08-17 标记的 risky 文件；verifier 对其有大量源码断言（columnHeaderHeight、hudObstacles 排除等），结构改动需同步断言。
- 标签移出 Canvas 后定位必须与几何引擎 labelRect 完全一致，且不得遮挡命中测试（`.allowsHitTesting(false)`）。
- 回滚点：f542178（08-17 完成态）。
