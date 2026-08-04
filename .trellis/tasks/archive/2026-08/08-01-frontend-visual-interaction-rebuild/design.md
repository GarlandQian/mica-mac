# Technical Design: 前端全局视觉与交互重构

## Decision Summary

按 D1-D10 执行：全面重塑品牌为「暗夜仪器（Midnight Instrument）」，主色 C1
电感靛蓝，交互深度 L3（S1 焦点三区），排版 T2（色彩+排版升级），外壳 W2
（精修不动结构），顺序 E1（设计系统先行），且 D10 要求每个共享组件都重新
设计而非仅套 token。本文件锁定 token 精确值、字阶、动效规格、组件重塑
清单、页面动效清单与回退策略。

## 0. 不变的硬边界（任何视觉决策不得违反）

- 不动控制器 API / DTO / 领域模型 / 认证 / 协议 / 日志语义。
- 不添加 mock 数据；所有展示值来自控制器真实上报。
- 数据页：单棵原生 `Table`、固定单行几何、单纵向滚动所有者、增量投影缓存；
  不做逐行动画、不恢复卡片墙/多 Table/嵌套内容玻璃。
- 不引入第三方 Swift 包、不引入第三方字体或定制图标资产；只用 SwiftUI +
  SF Symbols + 系统字体。
- 语义双重编码：颜色之外始终有文字/形状承载语义；Reduce Motion 下动效降级
  为静态等价。
- 文案同时提供英文与简体中文；HIG 对比度 ≥ 4.5:1（正文）/ 3:1（大字与
  图形），命中区域 ≥ 44pt。

## 1. 设计系统（Phase 1 交付物）

### 1.1 色彩 Token（`MicaStyle` 重写）

深色「暗夜仪器」为基准，浅色「实验室白」为对应。精确值：

| Token | Dark | Light | 用途 |
|---|---|---|---|
| `pageFill` | `#0E0F1A` | `#F2F3F9` | 页面底（墨蓝黑 / 冷白纸面） |
| `contentFill` | `#161827` | `#FBFBFE` | 内容带/卡片底 |
| `secondaryContentFill` | `#1E2133` | `#ECEDF6` | 抬升面、chrome fallback |
| `tertiaryContentFill` | `#2A2E45` | `#D9DCE9` | 描边/分隔/禁用底 |
| `accent`（C1 电感靛蓝） | `#8B93FF` | `#4F5BD5` | 选中态、主操作、辉光轨 |
| `accentSoft` | `#8B93FF @ 0.16` | `#4F5BD5 @ 0.12` | 选中底（导航/表格行） |
| `signalCyan` | `#6FD3E7` | `#1E7A93` | 信息/下载/普通日志 |
| `signalMint` | `#7FD4A8` | `#2E7D54` | 成功/健康/上传辅助 |
| `signalAmber` | `#F2BE6E` | `#9A6410` | 警告/降级 |
| `signalRed` | `#F28B9E` | `#B23A52` | 错误/危险/关闭 |
| `signalViolet` | `#B79CFF` | `#6C4FD1` | 上传/debug-trace 级 |
| `separator` | `#FFFFFF @ 0.08` | `#000000 @ 0.09` | 分隔线 |

四信号色与 accent 的色相间隔均 ≥ 30°，杜绝语义混淆。所有组合经
`apple-hig-expert` 的 `hig_checker.py` 验证对比度。

### 1.2 材质与层级

- chrome（侧边栏/工具栏/底部条）用 `.ultraThinMaterial` 之上的墨色半透明
  （contentFill @ 0.82 叠加深色 vignette），不用全透明玻璃铺满内容区。
- 内容区只允许两种浮层：`contentFill` 平面卡片（1pt tertiary 描边，无阴影）
  与 `secondaryContentFill` 抬升面。禁止嵌套玻璃、禁止卡片墙。
- 选中/激活态的「辉光轨」= 2pt accent 竖条 + accentSoft 底，仅用于导航选中、
  焦点区激活步骤；不用于每行。

### 1.3 字阶（`Font` extension 重写）

| 样式 | 定义 | 用途 |
|---|---|---|
| `micaDisplay` | `.system(.title, weight: .bold)` | 页面大标题 / Overview 主指标 |
| `micaHeadline` | `.system(.headline, weight: .semibold)` | section 标题、卡片标题 |
| `micaInstrument` | `.system(.title2, weight: .semibold).monospacedDigit()` | KPI 主数值 |
| `micaData` | `.system(.body, design: .monospaced)` | 表格度量、时间戳、字节、IP |
| `micaDataSmall` | `.system(.callout, design: .monospaced)` | 次级度量、图例值 |
| `micaLabel` | `.callout` | 表单/字段标签 |
| `micaCaption` | `.caption` | 辅助说明、help |

等宽数字用于一切会随时间变化的数值（D7），保证刷新时不横向跳动。行高与
间距统一走 4pt 基线网格：`MicaSpacing` 收敛为 `space1=4 / space2=8 /
space3=12 / space4=16 / space5=24 / space6=32`，废弃现有 16/10/6/4 散值。

### 1.4 图标规约（SF Symbols，无第三方资产）

- 单色渲染 `symbolRenderingMode(.monochrome)` 为默认；激活态用 `.fill`
  variant（D7）。尺寸规约：导航/section 头 15pt medium，行内 13pt regular，
  focus 区 17pt semibold。`WorkbenchSymbol` 提供 `size: .nav/.inline/.focus`
  枚举而不是散值。
- 新增语义映射集中在 token 层（info=signalCyan, ok=signalMint 等），页面不
  直接写颜色。

### 1.5 动效原语（`WorkbenchMotion` 新枚举）

| 原语 | 参数 | 用途 |
|---|---|---|
| `press` | 0.98 scale + 0.12s easeOut | 按钮/可点行按压 |
| `hover` | 0.08s 背景淡入 | 可交互行/图标按钮 |
| `numeric` | `.contentTransition(.numericText())` 150ms | KPI/速率/计数 |
| `expand` | spring(response 0.32, damping 0.86) | 详情/焦点区展开收起 |
| `pageIn` | opacity+8pt 位移 0.28s，stagger 40ms | Overview 卡片入场 |
| `crossfade` | 0.22s | 控制器/标签切换 |
| `liveDraw` | 曲线按新样本插值推移 0.4s linear | L3 流量/内存曲线 |
| `latencyShift` | 条宽/位置 spring 0.5s | L3 延迟条推移 |

全部原语读取 `accessibilityReduceMotion`：开启时退化为即时赋值（无动画）。
动效只应用于「值变化」与「结构变化」，绝不应用到滚动位置或高频行布局。

## 2. 组件重塑清单（D10，Phase 1 同步重绘）

以 `WorkbenchVisualSystem.swift` / `WorkbenchDataShared.swift` /
`WorkbenchChrome.swift` 为主：

| 组件 | 重塑要点 |
|---|---|
| `WorkbenchPageScaffold` | 大标题区 + 命令栏分层，页边距走网格 |
| `WorkbenchCommandBar` | 主操作(accent 填充)/筛选(描边)/检查器(图标)三分区 |
| `WorkbenchSection` | 分节头：15pt 图标 + micaHeadline + 细分隔线 |
| `WorkbenchContentBand` | contentFill 平面 + tertiary 1pt 描边，去浮起阴影 |
| `WorkbenchMetricTile/Label/Value` | KPI 卡：micaInstrument 大数 + micaCaption 标签，数值走 `numeric` 动效 |
| `WorkbenchStateView` | 空态：双色图标(主色+信号色) + micaHeadline 标题 + 说明 |
| `WorkbenchStatusBadge` | 状态徽章：信号色点 + 文字，无彩色填充底 |
| `WorkbenchStaleNotice` | 降级提示带：signalAmber 边条 + 等宽时间戳 |
| `WorkbenchIconCommand` | 图标按钮：28pt 方形 hit 区(≥44pt 含 padding)、hover/press 态 |
| `WorkbenchDecisionPathStep/Connector/Readout` | 焦点路径：步骤卡 + 连接符 + 等宽 readout，激活步骤带辉光轨 |
| `WorkbenchDataTableViewport` | 列头 micaCaption 大写化 + 分隔线；行高固定；选中行 accentSoft |
| `WorkbenchDataPrimaryCell/Text/Metric` | 主列 micaLabel 加粗，度量列 micaData 右对齐 |
| `WorkbenchDataInspectorShell/Section/Field` | 检查器：大标题区 + 分节 + 字段名 micaLabel / 值 micaData 可复制 |
| `WorkbenchDataInlineConfirmation` | 行内确认：signalRed 边条 + 主/次按钮 |
| 侧边栏(`WorkbenchChrome`) | 选中态辉光轨 + `.fill` 图标；控制器切换器精修 |
| 底部会话条 | 三段式（状态 · 速率 micaData · 时间），状态点脉冲（S1③） |

## 3. 页面动效清单（S1 三区）

- **Overview**：卡片 `pageIn` stagger 入场；KPI 数值 `numeric`；流量/内存/
  连接曲线 `liveDraw` 实时推移；图例值等宽。
- **Proxies**：测速时延迟条 `latencyShift` 推移 + 进行中克制脉冲
  （opacity 0.6↔1.0, 1.2s）；选中节点 `expand`。
- **侧边栏/会话条**：速率数字 `numeric`；状态切换 `crossfade`；状态点
  `pulse`。
- **Connections/Logs/Rules/Sources**：仅选中行与聚合数字 `numeric`；
  无逐行动画；Follow Newest / Jump 不动滚动位置。

## 3.5 数据页功能结构（自 08-01 并入）

- **连接焦点区**（选中才生成轻量投影）：身份/主机 → 规则 type+payload →
  provider/策略链 → 目标，右侧 readout 显示上传/下载/速率/时间；缺失段明确
  未报告，不补造路径。策略组步骤仅在当前可见组中做大小写敏感精确匹配才为
  导航动作；规则步骤把 controller ID/generation/type/payload 写入 session-bound
  导航请求，由 Rules 页在自有 `allRows` 做唯一精确匹配，零/多命中不动作。
  活动连接的单项/同组关闭进焦点区（沿用 capability/controller ID/generation
  门控），关闭全部留命令栏。无独立操作列。
- **来源焦点区**：来源名称 → 种类/内容规模 → 最近更新/健康；右侧单项更新与
  健康检查（固定命中几何 + 原生进度）。Update All/重载/批量进度留命令栏。
  无独立操作列；缺失值（测试 URL/订阅/更新时间/健康）保持未报告。
- **日志严重度**：投影阶段预计算稳定 severity 枚举；3pt 低饱和色轨 + 单色
  SF Symbol + 本地化级别文字 + VoiceOver 值。时间/级别成稳定定位栏，消息为
  主扫描列；结构化字段按需展开，不做多层卡片。

## 4. 状态与失效路径

- 动效不进入 projection 缓存的热路径：L3 曲线只读已存在的
  `trafficTimeline`/`memoryTimeline` 样本数组（`@MainActor Equatable` 基图
  已隔离），动画只包渲染层插值，不重算投影。
- 不可见页面不做动效也不做投影（沿用既有边界）。
- 高频指标与静态结构仍分属独立失效域；动效 state 不放入共享 observable。

## 5. 兼容与回退

- 不改 DTO / 持久化 schema / 操作契约；token、字阶、动效全在视图层。
- 每页/每组件可独立回退到上一阶段（E1 保证 token 先行稳定）。
- 双外观：深色基准 + 浅色对应同时交付，不允许只做深色。

## 6. 验证策略

- HIG：`hig_checker.py` 对全部新 token 组合跑对比度与命中区域。
- 源码契约：`scripts/verify-real-controller-source.mjs` 更新到新组件结构。
- 本地化：`Localizable.xcstrings` JSON 校验 + 双语键齐全。
- 性能：滚动/高频刷新掉帧回归检查（配合 Phase 0 收口）；Reduce Motion 开关
  路径走查。
- 构建测试：`swift build` + `swift test`（scratch path），不连真实控制器。
