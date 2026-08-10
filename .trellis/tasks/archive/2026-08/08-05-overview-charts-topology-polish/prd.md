# 首页图表与拓扑深度打磨

## Goal

在不改变控制器、Session、实时摄取、个性化布局或持久化语义的前提下，就地打磨现有 Overview 的三张实时图表与完整连接拓扑。用户应能在窄/中/宽窗口和四档字号下快速理解当前或所选时刻的数据，通过鼠标、键盘和 VoiceOver 稳定检查样本与链路，并在持续实时更新和密集拓扑下保持顺畅滚动。

## Confirmed Facts

- 当前 Overview 已由 `WorkbenchOverviewView`、`OverviewDashboardCanvas` 和每窗口 runtime 组成；页面只有一个纵向 `ScrollView`，模块通过 `LazyVStack` 延迟构造。
- Telemetry 已固定为上传、下载和活动连接三张真实 Swift Charts。内存只作为连接图上下文，三张图共用 hover、点击固定、左右步进、暂停、时间窗口和返回实时状态。
- 图表使用有界、generation-scoped 的真实样本和 vectorized `AreaPlot`、`LinePlot`、`PointPlot`；上传/下载共享同一真实 Y 轴尺度，不制造零值历史或静态曲线。
- 拓扑已保留每条活动连接和全部报告链路，使用宽度适配 Sankey、异步布局、分带 Canvas、空间命中索引、hover/pin 高亮、暂停、完整路径展开和同窗口 Connections 跳转。
- 结构 revision 与指标 revision 已分离；纯速率/字节变化不会重建拓扑结构。基础图层、高亮图层、命中层和可访问性表示已经分离。
- 拓扑选择详情已进入稳定 graph inset，节点标签已按实际字体裁切；真实视觉反馈确认 64pt detail、15pt node 和 560–760pt flow area 仍显得过小。
- Telemetry 标题栏已有 regular/compact 布局，但 200–260pt plot 和单层小号 section/metric symbols 没有形成用户要求的首页主视觉；图标还缺少 Zashboard 式统一细线图标、克制语义色与轻表面的秩序感。
- 上一个 Overview 子任务已完成连续 telemetry 表面、移除滚动入场动画和移除 sample-driven 整图动画。本任务建立在这些未提交的现有修改之上，不重复或回退它们。
- Apple 当前 Charts HIG 强调数据优先的视觉层级、紧凑环境中的最大化 plot width、可检查但不依赖交互才能理解关键信息，以及 VoiceOver/Audio Graphs/键盘可达性。Activity Monitor 的网络视图也采用少量明确模式控制配合实时图表，而不是在图表周围堆叠解释性卡片。

## Requirements

### R1. Telemetry visual hierarchy

- 保留上传、下载和活动连接三张同权图表；不新增第四张内存图、3D 图、装饰图或控制器未报告的派生序列。
- 当前或所选值保持每个 panel 的第一视觉层级；标题、状态、时间、轴和上下文信息退居辅助层级，不与数据线竞争。
- Overview 使用扣除页边距后的完整内容宽度；三张 plot 按实际 panel 宽度在 240–300pt 内响应式增长，不继承管理页的 1180pt 阅读宽度上限。Section 使用统一的信息青色 34pt 标记，metric 使用表达真实数据系列的 28pt 语义色标记，内部保持原生 SF Symbols 层级渲染；mint、amber、red、violet 只表达健康、警告、失败、调试或真实数据系列，不承担普通类别区分，密集行继续使用无底色单色图标。
- 上传和下载继续共用同一 Y 轴尺度；连接数使用自己的诚实尺度。最新真实样本继续锚定所选时间窗口右端。
- 保留 area + linear line + latest point 组合、克制网格和语义颜色。颜色不得成为状态或系列的唯一表达方式。
- 普通界面不再以“真实样本数”作为主要 footer 信息；样本真实性由数据合同保证，用户可见 footer 优先保留所选时间和连接图的真实内存上下文。

### R2. Responsive chart controls and interaction

- Live/Selected/Paused/Stale 状态、暂停/继续、前后样本、返回实时和 1/3/5 分钟窗口全部保留。
- 标题与控件使用 regular/compact 两种明确布局；在主窗口最小宽度、四档字号和英文/简体中文下不重叠、不裁切、不横向滚动，也不隐藏任何命令。
- 时间窗口仍是清晰的三选一模式；紧凑布局可以换行或采用等价的原生选项控件，但不得改变持久化值和共享 runtime。
- hover 只改变临时选择和 readout/indicator，不把标题栏从 Live 改为 Selected；点击固定选择后才改变全局选择状态，左右方向键沿合并后的真实日期顺序移动。选择变化不重建 base chart。
- 暂停只冻结 presentation；实时摄取继续，返回实时后追上最新保留样本。

### R3. Stable complete topology

- 保留每条活动连接、每个报告 hop、显式 unavailable path、真实聚合 count 和 `log10(count + 1) * 10` ribbon 宽度；不得引入 Top-N、自动聚类、抽样、横向滚动或另一个详情窗口。
- hover、pin 或清除选择不得改变 graph 的原点、尺寸或当前滚动位置，避免目标在指针下移动或 hover 往返抖动。
- 选择反馈使用不改变 graph 布局的稳定 detail/inset 区域；唯一真实路径仍可跳转 Connections，完整路径列表仍在同窗口按需展开。
- 稳定 detail 使用 80pt 无边框信息区；idle 显示真实连接数和不可用路径数，hover/pinned 显示完整 callout label、description、pinned symbol 和唯一路径的 Connections intent。暂停与完整路径命令并入 section header，不重复拓扑图标；前后路径、固定/取消固定和清除通过直接画布交互、键盘、完整路径行及原生右键菜单完成，不把详情变成工具栏，也不把每个 render band 或 node 变成独立焦点。
- 节点显示不得继续按固定字符数修改 controller-reported 名称。紧凑 graph label 必须按实际字体和可用宽度处理，完整原值同时在稳定选择详情、展开路径和可访问性表示中可见、可选择。
- Source、Matched rule、各 chain hop 和 Exit 的角色同时通过列位置、标题和文本表达；颜色只作辅助。
- 稀疏拓扑的 flow 区按可用宽度保留 680–920pt 的响应式最低高度；20pt node bars、8pt gaps 和 callout labels 共同提高可读尺度，密集列仍可继续向下增长。
- 现有 visible-node > ribbon > bounded label target 的命中优先级、28pt 本地节点获取范围和 10pt ribbon tolerance 保持不变，除非定向测试证明需要调整。

### R4. Scroll and update performance

- Overview 继续只有一个纵向滚动所有者；图表、拓扑和路径列表不得增加嵌套横向或纵向 scroll view。
- 保留 topology normalization/index/layout cache、structure reuse、cancellable async work、352pt render bands、异步 base Canvas 和空间命中索引。
- metrics-only frame 不得触发 topology normalization/index/layout；hover/pin 不得重绘 base bands 或重建 graph structure。
- chart sample 更新不得触发 topology/network subtree；chart selection 不得重新计算/downsample sample arrays。
- 只在测量证明有需要时调整缓存或调度，不为“可能更快”增加新的 timer、轮询器或第三方包。
- 使用确定性大数据 fixture 验证 2,000 条连接下的完整路径保留、结构复用、分带覆盖、命中候选有界和取消安全；不写不可移植的绝对 FPS/CPU 断言。

### R5. Accessibility and localization

- 每张图提供清晰的英文/简体中文 purpose、当前/所选值和时间；确认 Swift Charts 的可访问数据表示未被外层 label 覆盖，必要时提供 `accessibilityChartDescriptor` 或等价 numeric/tabular fallback。
- 图表继续支持完整 plot 区 hover/点击和键盘左右导航；所有 icon command 有本地化 label/help。
- 拓扑的完整路径可访问性分组、VoiceOver 顺序和 Connections 跳转保持有效；pointer hover 不是获取完整链路信息的唯一方式。
- 四档 `micaFont`、浅色/深色、Increase Contrast 和 Reduce Motion 下保持可读；不得直接引入与 `micaFont` 平行的界面字体系统。

### R6. Overview source ownership

- 将 `WorkbenchDashboard.swift` 收敛为 Overview 根组合、响应式 module layout、可选 summaries、network facts 和共享格式化入口。
- Instrument rail、Telemetry controls、三张 charts、selection overlays 和相关 presentation-only views 迁移到 `WorkbenchOverviewTelemetry.swift`。
- Topology section/workspace、Canvas bands、hit/accessibility views 和 drawing helpers 迁移到 `WorkbenchOverviewTopologyView.swift`；现有 `WorkbenchOverviewTopology.swift` 继续只拥有 topology index/cache/layout/geometry。
- 拆分只改变源码所有权，不改变 View identity、AppModel/runtime 依赖、数据投影、交互、可访问性、布局常量或本地化 key。
- 同步 Workbench 精确文件合同、源码 verifier 和 source-contract tests；本切片不同时拆分 Proxies 或 verifier 内部结构。

## Acceptance Criteria

- [ ] AC1：Overview 仍只有三张真实时间序列图；数据来源、共享时间轴、Y 轴语义、pause/return-live 和每窗口 runtime 行为不变。
- [ ] AC2：Telemetry 标题、状态、命令和时间窗口在主窗口最小宽度、窄/中/宽布局、四档字号以及英文/简体中文下无重叠、裁切或横向滚动。
- [ ] AC3：三张图的数据线和当前/所选值构成主层级；Overview 使用完整内容宽度，plot 保持 240–300pt 响应式高度，轴、网格、标题和 footer 保持克制，普通 UI 不再突出技术性的 sample count。
- [ ] AC4：hover、pin、清除选择和实时 revision 更新不会改变拓扑 graph 原点或导致 pointer target 抖动；唯一路径仍可同窗口跳转 Connections。
- [ ] AC5：拓扑完整保留所有连接和 hop，不抽样、不 Top-N、无嵌套 scroll；稀疏 flow 区保持 680–920pt 响应式最低高度，节点名称不再经过固定字符宽度改写，完整真实值可见、可选择并可由 VoiceOver 访问。
- [ ] AC6：metrics-only 更新、hover/pin 和 chart selection 分别命中既有窄更新路径；2,000 连接 fixture 下完整性、缓存复用、分带、命中和取消相关测试通过。
- [ ] AC7：图表和拓扑可通过鼠标、键盘、右键菜单和 VoiceOver 检查；拓扑区分 hover 与 pinned、方向键可步进完整路径、Esc 可清除；浅色/深色、四档字号、Reduce Motion 和 Increase Contrast 不丢失含义。
- [x] AC8：定向 Overview/Topology 测试、source verifier、XCStrings JSON、HIG 检查、Swift build、完整 Swift tests、`git diff --check` 和 Trellis validate 通过。
- [x] AC9：Overview 源码按 Dashboard、Telemetry、Topology view、Topology model/layout 四个职责边界拆分，机械迁移前后行为合同不变。

## Out of Scope

- 不修改 controller API、DTO、capability、认证、Session generation、刷新频率、实时 buffer 上限或重连语义。
- 不修改 Overview 五模块 ID、顺序/可见性/尺寸、presets、全局默认、controller override、CAS 冲突或 UndoManager 合同。
- 不新增图表类型、第四张图、3D 图、迷你地图、Top-N 拓扑、横向拓扑 viewport、弹窗详情或独立 topology destination。
- 不修改 Proxies、Connections、Logs、Rules、Sources、管理页、Settings 或全局 palette。
- 不新增第三方依赖，不启动 Mica，不访问真实控制器，不运行 runtime smoke，不创建或推送 Git 提交。

## Key Decisions

- 继续使用系统 Swift Charts 和本地 Canvas/Path；现有实现已经满足数据、可访问性和性能边界，没有引入 package 的材料收益。
- 优先修复稳定性和信息层级：选择反馈不得移动 graph，完整名称通过 graph label + stable detail/path/accessibility 渐进呈现。
- 性能验收使用 revision、operation count、cache hit、render-band coverage 和 cancellation 等确定性合同；运行时视觉/滚动手感留给用户使用真实控制器验收。
- 没有阻塞规划的开放产品问题。

## Risks And Deferred Items

- 当前工作区包含大量未提交用户修改，其中包括上一个 Overview 子任务的完成结果。实施必须以当前 worktree 为基线，只追加本任务差异。
- 自动检查无法替代真实数据密度下的视觉与 pointer 手感；完成后需要用户进行一次运行时视觉验收，但本任务不会自行启动应用。
- 若实际编译确认 Swift Charts 自动 Audio Graphs 已完整保留，则不额外引入自定义 descriptor；可访问性实现以最小有效机制为准。
