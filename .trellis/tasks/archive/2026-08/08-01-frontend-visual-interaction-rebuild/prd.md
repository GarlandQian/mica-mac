# 前端全局视觉与交互重构

## Goal

把 Mica 整个前端重塑为「暗夜仪器（Midnight Instrument）」品牌：墨蓝黑
深色基准 + C1 电感靛蓝主色 + 冷调四信号色，配合等宽数字排版与 L3 仪表级
实时动效，使 11 个 destination 全部达到「非常漂亮、交互流畅」的目标。
设计系统先行全局换肤，再逐页重构；每个共享组件都重新设计而非仅换色。
所有工作在不改控制器数据、不引入第三方依赖、不破坏数据页性能边界的前提
下完成。

## Confirmed Facts

- 前端为 Swift 6.2 / SwiftUI，目标 macOS 27；Workbench 共 19 个文件约
  25,580 行，11 个 destination：Overview、Proxies、Connections、Logs、
  Rules、Sources、Controllers、Configuration、Actions、Diagnostics、
  Settings。
- 现有视觉系统：`WorkbenchVisualSystem.swift` 的 `MicaStyle`（Rose Pine
  自适应 token）与 `MicaSurfaces.swift`；`docs/UI_GUIDELINES.md` 与
  `.trellis/spec/frontend/workbench-ui-contract.md` 锁定导航 chrome、表单、
  表格、inspector、空态等行为契约。
- 共享组件集中在 `WorkbenchVisualSystem.swift`（PageScaffold、CommandBar、
  Section、ContentBand、MetricTile、StateView、StatusBadge、StaleNotice、
  IconCommand、DecisionPath 系列、Symbol、Spacing/Bounds/Font）与
  `WorkbenchDataShared.swift`（DataTableViewport、PrimaryCell、DataText、
  DataMetric、InlineConfirmation、InspectorShell/Section/Field）。
- Overview 已有 Charts 图表（`WorkbenchDashboard.swift` 的
  AreaPlot/LinePlot），基图用 `@MainActor Equatable` 与交互态分离；实时
  数据经 `AppModel.liveTrafficRate`/`trafficTimeline`/`memoryTimeline`
  流入；数据页有增量投影缓存——这是 L3 动效的现成接缝。
- 硬约束（AGENTS.md / 契约）：不下载或管理本地核心；不动控制器
  API/DTO/认证/协议；不添加 mock 数据；不引入第三方 Swift 包/字体/图标
  资产；高密度数据页保持单棵原生 Table、固定行几何、单纵向滚动所有者；
  可见文案需英文 + 简体中文。
- 工作区有 259 个未提交改动，与 4 个进行中任务同区——本任务 Phase 0 必须
  先收口这些任务（见 D3）。

## Decisions

- D1: 视觉方向 = **全面重塑品牌（Rebrand）**。允许推翻 Rose Pine 配色、
  排版与图标语言；既有视觉契约不作兼容性约束，按需重写
  `docs/UI_GUIDELINES.md` 与 `workbench-ui-contract.md`。硬约束仍保留。
- D2: 新身份 = **暗夜仪器（Midnight Instrument）**。深色优先墨蓝黑底 +
  单一主色 + 克制四信号色，等宽数字；浅色对应「实验室白」。语义双重编码，
  HIG 对比度与 44pt 命中区域必须通过。
- D3: 地基策略 = **先收口再起楼**。Phase 0 先把 4 个进行中任务收口提交，
  保留功能/性能成果，视觉部分按新身份重做；视觉重塑在干净基线上开始。
- D4: 主色 = **C1 电感靛蓝**（dark `#8B93FF` / light `#4F5BD5`）；四信号色
  冷调校准并与主色色相错开；精确值与墨色阶见 design.md §1.1。
- D5: 交互深度 = **L3 仪表级实时性**。L1 感知流畅为全局基线，L2 编排按
  页面价值选用，L3 实时数据动效纳入范围；加每帧预算验收条款；Reduce
  Motion 下 L3 全部降级为静态等价。
- D6: L3 范围 = **S1 焦点三区**：① Overview（曲线推移 + KPI 数值滚动）、
  ② Proxies（延迟条推移/测速脉冲）、③ 侧边栏/会话条（状态与速率过渡）。
  Connections/Logs 数据平面不做逐行动画，仅选中行与聚合数字过渡。
- D7: 排版/图标 = **T2 色彩 + 排版升级**。新字阶含等宽数字族扩展到表格/
  时间戳/字节；4pt 基线网格；SF Symbols 统一权重/尺寸/variants 语义
  （.fill 仅激活态）。不引入第三方字体/图标资产。
- D8: 外壳 = **W2 精修、结构不变**。保留单 NavigationSplitView、11 个
  destination、内联切换器、工具栏/检查器行为契约；仅重绘外壳视觉。
- D9: 顺序 = **E1 设计系统先行，再逐页应用**。
- D10: **每个组件都重新设计**（见 design.md §2 清单），以提升美感为目标，
  不以套 token 换色为满足。
- D11 (2026-08-01, 用户确认): **折叠 08-01-connection-source-log-workspaces**。
  该任务仅完成 5/52，且其数据页与视觉重构 Phase 4 同文件同范围；将其功能
  需求（连接/来源/日志三页工作区：焦点区、跨页规则/策略精确导航、日志严重
  度色轨、来源生命周期焦点、去除独立操作列）**并入本任务 Phase 4** 统一
  交付，独立任务关闭。功能需求一项不丢，仅合并实施。

## Requirements

### R1. 设计系统（Phase 1）
- 落地 design.md §1.1 全部色彩 token（双外观），替换全部 Rose Pine 旧值。
- 收敛间距为 4pt 基线网格；重写字阶并扩展等宽数字族。
- 新增 `WorkbenchMotion` 动效原语，全部支持 Reduce Motion 降级。
- 统一 SF Symbols 权重/尺寸/variants 规约。

### R2. 组件重塑（Phase 1）
- 按 design.md §2 清单重绘全部共享组件的形状、层级、间距与状态反馈。
- W2 外壳精修：侧边栏选中态辉光轨、底部三段式会话条、工具栏分区、
  检查器大标题区。

### R3. 页面重构（Phase 2-5）
- Overview：卡片入场 stagger、KPI 数值滚动、曲线实时推移。
- Proxies：延迟条推移/测速脉冲、节点/目录行/ribbon/检查器重绘。
- 数据页：列头/单元/选中行/焦点区/检查器重绘，保持单 Table 与固定行
  几何，仅选中行与聚合数字过渡。
- 管理页：表单行/偏好菜单/控制器列表/操作区按新组件重绘，行为契约不变。

### R4. 不变边界
- 不改控制器 API/DTO/认证/协议/日志语义；不加 mock 数据；不加第三方
  依赖/字体/图标资产。
- 数据页单棵原生 Table、固定行几何、单纵向滚动所有者、增量投影缓存不破。
- 动效不进入 projection 缓存热路径；不可见页面不动效不投影；动效 state 不
  入共享 observable。
- 语义双重编码；Reduce Motion 降级；英文 + 简体中文；HIG 对比度与 44pt
  命中区域。

### R5. 双外观
- 深色基准与浅色对应同时交付，不允许只做深色。

### R6. 数据页功能工作区（自 08-01 并入，Phase 4）
- **Connections**：选中连接显示完整真实链路焦点区与关键统计；链路中策略组
  名称与可见组精确匹配时可跨页打开并激活该组；规则 type+payload 唯一精确
  匹配时才可跨页选择；重复/缺失目标只显示完整值不猜测；活动连接的单项/同组
  关闭进入焦点区，关闭全部留命令栏，已关闭连接无关闭命令；删除独立操作列。
- **Sources**：选中来源在表格上方显示紧凑焦点区（来源→内容规模→最近更新/
  健康），右侧提供单项更新与健康检查；Update All 与重载留命令栏；删除独立
  操作列；不合成测试 URL/订阅/更新时间/健康结果，缺失值保持未报告。
- **Logs**：每行约 3pt 低饱和语义色轨 + 明确级别文字双重编码（error 红 /
  warning 琥珀 / debug-trace 紫 / info 青），时间与级别成稳定定位栏，消息为
  主扫描内容；Follow Newest 开/停/回底清晰克制；不排序、不伪造时间、不脱敏。
- 三页保留既有活动/已关闭、过滤、排序、增量投影、滚动恢复、能力门控与
  generation 边界；未选中时不留空焦点区或常驻空 inspector。

## Acceptance Criteria

- [ ] AC1: 全部 Rose Pine 旧色值被新 token 替换（grep 无残留），11 个页面
  呈现统一「暗夜仪器」语言，且每页信息层级符合各自任务。
- [ ] AC2: 数据页仍各只有一棵原生 Table、固定行几何、单纵向滚动所有者，
  无卡片墙/嵌套玻璃/逐行动画。
- [ ] AC3: Overview 卡片入场 stagger、KPI 数值滚动、曲线实时推移生效；
  Proxies 延迟条推移/测速脉冲生效；侧边栏/会话条状态与速率过渡生效。
- [ ] AC4: Reduce Motion 开启时所有动效降级为静态等价，且无语义丢失。
- [ ] AC5: 所有数值/KPI/时间戳/字节使用等宽数字，刷新时不横向跳动。
- [ ] AC6: 每个共享组件按新身份重绘，无「仅换色」组件残留。
- [ ] AC7: 双外观（深色/浅色）均交付，常规/紧凑/最窄宽度及超大字体下无
  重叠或横向页面滚动。
- [ ] AC8: HIG 对比度与 44pt 命中区域检查通过；英文 + 简体中文键齐全。
- [ ] AC9: 滚动/高频刷新无掉帧回归；动效 state 未进入共享 observable 或
  projection 热路径。
- [ ] AC10: `swift build` + `swift test` 通过，`verify-real-controller-source`
  与本地化 JSON 校验通过，`git diff --check` 干净；未连真实控制器/9090。
- [ ] AC11: 连接页完整链路焦点区生效；策略组精确匹配可跨页激活、规则唯一
  精确匹配可跨页选择，模糊/重复目标不产生伪链接；表格无独立操作列。
- [ ] AC12: 来源页选中焦点区含单项更新与健康检查；Update All/重载留命令栏；
  表格无独立操作列；缺失值保持未报告不合成。
- [ ] AC13: 日志页级别窄色轨 + 文字双重编码生效；Follow Newest/手动滚动
  停止跟随行为保留；无逐行卡片或多层结构。

## Out Of Scope

- 控制器 API / DTO / 领域模型 / 认证 / 协议 / 日志语义的任何改动。
- 第三方 Swift 包、第三方字体、定制图标资产、WebView、AppKit Table 桥接。
- 数据页卡片墙/多 Table/逐行动画/嵌套内容玻璃。
- 首页图表/拓扑的信息架构重设计（仅按新身份重绘与加动效）。
- mock 数据、真实控制器联调、旧 runtime smoke。

## Open Questions

（无阻塞问题；D1-D10 均已确认）
